import Foundation
@preconcurrency import AVFoundation
import CoreImage
import CoreText
import ImageIO
import Vision

/// Both preview and export call this renderer. Caches contain derived resources only.
/// The actor serializes access to image generators; images are bounded to output size.
actor FrameRenderer {
    private let context: CIContext
    private let softwareRendering: Bool
    init(softwareRendering: Bool = false) {
        self.softwareRendering = softwareRendering
        context = CIContext(options: [.useSoftwareRenderer: softwareRendering, .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, .outputColorSpace: CGColorSpace(name: CGColorSpace.itur_709)!])
    }
    private var generators: [String: AVAssetImageGenerator] = [:]
    private var images: [String: CGImage] = [:]
    private var textImages: [String: CGImage] = [:]
    private var rendering = false
    private var chromaCubes: [String: Data] = [:]
    private var personMasks: [String: CIImage] = [:]

    func clearCaches() {
        generators.values.forEach { $0.cancelAllCGImageGeneration() }
        generators.removeAll(); images.removeAll(); textImages.removeAll(); chromaCubes.removeAll(); personMasks.removeAll()
        context.clearCaches()
    }

    func render(plan: RenderPlan, time: MediaTime, rootURL: URL, size: CGSize) async throws -> CGImage {
        while rendering { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(1)) }
        rendering = true
        defer { rendering = false }
        try Task.checkCancellation()
        guard size.width >= 2, size.height >= 2, size.width <= 4096, size.height <= 4096 else { throw MediaFailure.rendering("Dimensions invalides") }
        let rect = CGRect(origin: .zero, size: CGSize(width: Int(size.width), height: Int(size.height)))
        let active = plan.clips.filter { $0.isActive(at: time) && $0.clip.kind != .audio }
        let spans = plan.scenes.filter { $0.start <= time && time < $0.end }
        var canvas = CIImage(color: color(plan.variant.canvas?.color ?? "#000000")).cropped(to: rect)
        for (index, span) in spans.enumerated() {
            let background = active.first { $0.sceneID == span.id && $0.clip.kind != .text }?.presentation.background ?? "#000000"
            var scene = CIImage(color: color(plan.variant.canvas?.color ?? background)).cropped(to: rect)
            if let settings = plan.variant.canvas, settings.mode != .solid {
                var backgroundClip: RenderClip?
                if settings.mode == .blurredMedia {
                    backgroundClip = active.first { $0.sceneID == span.id && ($0.clip.kind == .image || $0.clip.kind == .video) }
                } else if let id = settings.imageAssetID {
                    backgroundClip = RenderClip(clip: Clip(assetID: id, kind: .image), globalStart: .zero, duration: plan.duration, presentation: .init(), sceneID: span.id)
                }
                if var copy = backgroundClip {
                    copy.presentation = .init(); copy.clip.presentation = .init(); copy.clip.keyframes = []
                    copy.clip.fadeIn = .zero; copy.clip.fadeOut = .zero
                    var raster = try await layerImage(copy, plan: plan, time: time, rootURL: rootURL, rect: rect)
                    if settings.mode == .blurredMedia, settings.blur > 0 {
                        raster = raster.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: settings.blur * min(rect.width, rect.height)]).cropped(to: rect)
                    }
                    scene = raster.composited(over: scene).cropped(to: rect)
                }
            }
            for renderClip in active where renderClip.sceneID == span.id {
                let layer = try await layerImage(renderClip, plan: plan, time: time, rootURL: rootURL, rect: rect)
                scene = blend(layer, over: scene, mode: renderClip.presentation.blend).cropped(to: rect)
            }
            if index > 0, let previous = spans[safe: index - 1], previous.transition.duration > .zero {
                let progress = (time - span.start).seconds / previous.transition.duration.seconds
                canvas = transition(canvas, scene, kind: previous.transition.kind, progress: progress, rect: rect)
            } else { canvas = scene }
        }
        for renderClip in active where renderClip.sceneID == nil {
            let layer = try await layerImage(renderClip, plan: plan, time: time, rootURL: rootURL, rect: rect)
            canvas = blend(layer, over: canvas, mode: renderClip.presentation.blend).cropped(to: rect)
        }
        try Task.checkCancellation()
        guard let result = context.createCGImage(canvas, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.itur_709)!) else { throw MediaFailure.rendering("Core Image") }
        return result
    }

    private func layerImage(_ item: RenderClip, plan: RenderPlan, time: MediaTime, rootURL: URL, rect: CGRect) async throws -> CIImage {
        let clip = item.clip
        let p = item.evaluatedPresentation(at: time)
        var image: CIImage
        if clip.kind == .shape {
            image = CIImage(color: color(p.color)).cropped(to: rect)
        } else if clip.kind == .text {
            let key = "\(clip.text)|\(p.textSize)|\(p.color)|\(p.textFont)|\(p.textAlignment)|\(p.textBold)|\(p.textOutline)|\(p.textShadow)|\(p.background)|\(p.textBackgroundOpacity)|\(p.textBackgroundShape.rawValue)|\(p.textLetterSpacing)|\(p.textLineSpacing)|\(Int(rect.width))x\(Int(rect.height))"
            let raster: CGImage
            if let cached = textImages[key] { raster = cached }
            else {
                raster = try TextRasterizer.render(text: clip.text, presentation: p, size: rect.size)
                if textImages.values.reduce(0, { $0 + $1.bytesPerRow * $1.height }) + raster.bytesPerRow * raster.height > 32_000_000 { textImages.removeAll(keepingCapacity: true) }
                if raster.bytesPerRow * raster.height <= 32_000_000 { textImages[key] = raster }
            }
            image = CIImage(cgImage: raster)
        } else {
            guard let asset = plan.assets.first(where: { $0.id == clip.assetID }) else { throw MediaFailure.missing(clip.id.uuidString) }
            let url = try MediaFiles.checkedURL(relativePath: asset.relativePath, root: rootURL)
            let maxDimension = min(4096, Int(max(rect.width, rect.height) * min(3, max(1, p.scale))))
            let key = "\(url.path)|\(maxDimension)"
            if clip.kind == .image {
                let raster: CGImage
                if let cached = images[key] { raster = cached }
                else {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: min(maxDimension, 8192)] as CFDictionary) else { throw MediaFailure.unreadable(asset.name) }
                    raster = decoded
                    if images.values.reduce(0, { $0 + $1.bytesPerRow * $1.height }) + raster.bytesPerRow * raster.height > 64_000_000 { images.removeAll(keepingCapacity: true) }
                    if raster.bytesPerRow * raster.height <= 64_000_000 { images[key] = raster }
                }
                image = CIImage(cgImage: raster)
            } else {
                let generator: AVAssetImageGenerator
                if let cached = generators[key] { generator = cached }
                else {
                    generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                    generator.appliesPreferredTrackTransform = true
                    generator.dynamicRangePolicy = .forceSDR
                    generator.maximumSize = CGSize(width: min(maxDimension, 8192), height: min(maxDimension, 8192))
                    generator.requestedTimeToleranceBefore = .zero
                    generator.requestedTimeToleranceAfter = .zero
                    if generators.count >= 6 { generators.values.forEach { $0.cancelAllCGImageGeneration() }; generators.removeAll(keepingCapacity: true) }
                    generators[key] = generator
                }
                let sourceTime = TimeMapping.sourceTime(for: time - item.globalStart, clip: clip)
                // The source interval is half-open, including during reverse playback.
                let sourceSeconds = min(max(0, sourceTime.seconds), max(0, asset.duration.seconds - 1 / max(asset.nominalFrameRate, 600)))
                // The generator is cached and shared by consecutive preview renders.
                // `cancelAllCGImageGeneration()` here also cancels the replacement render
                // that starts during a drag, which AVFoundation reports as a generic
                // "operation impossible" error. Let the async request finish, then honor
                // this task's cancellation without invalidating the next request.
                let generated = try await generator.image(at: CMTime(seconds: sourceSeconds, preferredTimescale: 60_000))
                try Task.checkCancellation()
                image = CIImage(cgImage: generated.image)
            }
        }
        let sourceRect = image.extent
        var personMask: CIImage?
        if p.removePersonBackground, clip.kind == .image || clip.kind == .video {
            let stamp = clip.kind == .video ? TimeMapping.sourceTime(for: time - item.globalStart, clip: clip).value : 0
            let key = "\(rootURL.path)|\(clip.assetID?.uuidString ?? "")|\(stamp)|\(sourceRect.width)x\(sourceRect.height)"
            personMask = try segmentPerson(in: image, cacheKey: key, feather: p.maskFeather)
        }
        let animationTime = time - item.globalStart + clip.animationOffset
        for var effect in clip.effects where effect.kind != .neon {
            guard let amount = effect.evaluatedAmount(at: animationTime), amount != 0 else { continue }
            effect.amount = amount
            image = apply(effect, to: image, time: animationTime.seconds, seed: clip.effectSeed ?? clip.id)
        }
        image = image.cropped(to: sourceRect)
        if let key = p.chromaKeyColor { image = chroma(image, key: color(key), tolerance: p.chromaKeyTolerance, softness: p.chromaKeySoftness) }
        if let personMask {
            image = image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: sourceRect), kCIInputMaskImageKey: personMask])
        }
        if p.mask != .none {
            let mask = try maskImage(p, rect: sourceRect)
            image = image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: sourceRect), kCIInputMaskImageKey: mask])
        }
        // Contour effects must see the alpha produced by cutout/chroma/masks;
        // otherwise masking would erase their halo after it was generated.
        for var effect in clip.effects where effect.kind == .neon {
            guard let amount = effect.evaluatedAmount(at: animationTime), amount != 0 else { continue }
            effect.amount = amount
            image = neon(effect, image: image, isolated: clip.kind == .text || clip.kind == .shape || personMask != nil || p.chromaKeyColor != nil || p.mask != .none)
        }
        let fitting = p.fill ? max(rect.width / sourceRect.width, rect.height / sourceRect.height) : min(rect.width / sourceRect.width, rect.height / sourceRect.height)
        let scale = fitting * p.scale
        let transform = CGAffineTransform(translationX: rect.width * p.x, y: rect.height * (1 - p.y))
            .rotated(by: -p.rotation * .pi / 180)
            .scaledBy(x: scale * (p.mirror ? -1 : 1), y: scale)
            .translatedBy(x: -sourceRect.midX, y: -sourceRect.midY)
        image = image.transformed(by: transform)
        let elapsed = (time - item.globalStart + clip.animationOffset).seconds
        let envelopeDuration = clip.animationDuration?.seconds ?? item.duration.seconds
        var opacity = p.opacity
        if clip.fadeIn.seconds > 0 { opacity *= min(1, max(0, elapsed / clip.fadeIn.seconds)) }
        if clip.fadeOut.seconds > 0 { opacity *= min(1, max(0, (envelopeDuration - elapsed) / clip.fadeOut.seconds)) }
        return alpha(image, opacity).cropped(to: rect)
    }

    private func alpha(_ image: CIImage, _ value: Double) -> CIImage {
        guard value < 1 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, value))])
    }

    private func blend(_ image: CIImage, over background: CIImage, mode: BlendMode) -> CIImage {
        let name: String
        switch mode { case .normal: name = "CISourceOverCompositing"; case .multiply: name = "CIMultiplyBlendMode"; case .screen: name = "CIScreenBlendMode"; case .overlay: name = "CIOverlayBlendMode"; case .lighten: name = "CILightenBlendMode"; case .darken: name = "CIDarkenBlendMode" }
        return image.applyingFilter(name, parameters: [kCIInputBackgroundImageKey: background])
    }

    private func apply(_ effect: EffectInstance, to image: CIImage, time: Double, seed: UUID) -> CIImage {
        let a = effect.amount
        let rect = image.extent
        let radius = max(rect.width, rect.height) / 720
        switch effect.kind {
        case .exposure: return image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: a])
        case .brightness: return image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: a])
        case .contrast: return image.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + a])
        case .saturation: return image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: max(0, 1 + a)])
        case .temperature: return image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500 + a * 2500, y: 0), "inputTargetNeutral": CIVector(x: 6500, y: 0)])
        case .tint: return image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: a * 100), "inputTargetNeutral": CIVector(x: 6500, y: 0)])
        case .highlights: return image.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": 1 - a])
        case .shadows: return image.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": a])
        case .sharpness: return image.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: a])
        case .vignette: return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: max(0, a) * 2, kCIInputRadiusKey: min(rect.width, rect.height) * 0.6])
        case .fade: return image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: a * 0.15, kCIInputContrastKey: 1 - a * 0.25])
        case .blur: return image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: abs(a) * 24 * radius]).cropped(to: rect)
        case .glow: return image.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: abs(a) * 20 * radius, kCIInputIntensityKey: abs(a)])
        case .impactZoom:
            let strength = min(1, max(0, a)), scale = 1 + strength * 0.18
            let transform = CGAffineTransform(translationX: rect.midX + sin(time * 43) * strength * 5 * radius, y: rect.midY + cos(time * 59) * strength * 4 * radius)
                .scaledBy(x: scale, y: scale).translatedBy(x: -rect.midX, y: -rect.midY)
            return image.clampedToExtent().transformed(by: transform).cropped(to: rect)
                .clampedToExtent().applyingFilter("CIZoomBlur", parameters: [kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY), "inputAmount": strength * 8]).cropped(to: rect)
        case .shortGlitch:
            let strength = min(1, max(0, a))
            // A frame-indexed seed is stable across preview, export and splits.
            var state = seed.uuidString.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 } ^ UInt64(max(0, floor(time * 18)))
            var displaced = image
            for index in 0..<7 {
                state = state &* 6364136223846793005 &+ 1
                let shift = (Double((state >> 32) % 201) / 100 - 1) * strength * rect.width * 0.07
                let band = CGRect(x: rect.minX, y: rect.minY + rect.height * Double(index) / 7, width: rect.width, height: rect.height / 7 + 1)
                let strip = image.clampedToExtent().transformed(by: .init(translationX: shift, y: 0)).cropped(to: band)
                displaced = strip.composited(over: displaced)
            }
            var split = effect; split.kind = .rgbSplit; split.amount = strength * 0.75
            return apply(split, to: displaced.cropped(to: rect), time: time, seed: seed).cropped(to: rect)
        case .neon: return neon(effect, image: image, isolated: false)
        case .pixelate: return image.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(1, abs(a) * 45 * radius)])
        case .shake: return image.transformed(by: CGAffineTransform(translationX: sin(time * 47) * a * 12 * radius, y: cos(time * 61) * a * 9 * radius))
        case .retro:
            let stylized = image.applyingFilter("CIPhotoEffectProcess")
            return alpha(stylized, min(1, abs(a))).composited(over: image)
        case .skinSmooth:
            let softened = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.02 + abs(a) * 0.08, "inputSharpness": 0.35])
            return alpha(softened, min(0.9, abs(a))).composited(over: image)
        case .skinGlow:
            let warm = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500 + abs(a) * 700, y: 0), "inputTargetNeutral": CIVector(x: 6500, y: 0)])
                .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 4 + abs(a) * 14 * radius, kCIInputIntensityKey: 0.15 + abs(a) * 0.5])
            return alpha(warm, min(0.75, abs(a))).composited(over: image)
        case .bulge:
            return image.applyingFilter("CIBumpDistortion", parameters: [kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY), kCIInputRadiusKey: min(rect.width, rect.height) * 0.55, kCIInputScaleKey: a * 0.65]).cropped(to: rect)
        case .pinch:
            return image.applyingFilter("CIPinchDistortion", parameters: [kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY), kCIInputRadiusKey: min(rect.width, rect.height) * 0.65, kCIInputScaleKey: a * 0.8]).cropped(to: rect)
        case .twirl:
            return image.applyingFilter("CITwirlDistortion", parameters: [kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY), kCIInputRadiusKey: min(rect.width, rect.height) * 0.7, kCIInputAngleKey: a * .pi * 2]).cropped(to: rect)
        case .kaleidoscope:
            return image.applyingFilter("CIKaleidoscope", parameters: ["inputCount": 3 + Int(abs(a) * 9), kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY), kCIInputAngleKey: a * .pi]).cropped(to: rect)
        case .comic:
            let stylized = image.applyingFilter("CIComicEffect")
            return alpha(stylized, min(1, abs(a))).composited(over: image)
        case .crystallize:
            let stylized = image.applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: 2 + abs(a) * 30 * radius, kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY)]).cropped(to: rect)
            return alpha(stylized, min(1, abs(a))).composited(over: image)
        case .rgbSplit:
            let shift = abs(a) * 16 * radius
            let r = image.clampedToExtent().applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1,y: 0,z: 0,w: 0), "inputGVector": CIVector(x: 0,y: 0,z: 0,w: 0), "inputBVector": CIVector(x: 0,y: 0,z: 0,w: 0)]).transformed(by: .init(translationX: shift, y: 0))
            let gb = image.clampedToExtent().applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0,y: 0,z: 0,w: 0)]).transformed(by: .init(translationX: -shift, y: 0))
            return r.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: gb]).cropped(to: rect)
        case .grain:
            var state = seed.uuidString.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 } ^ UInt64(max(0, time * 30))
            var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                state = state &* 6364136223846793005 &+ 1
                let value = UInt8(truncatingIfNeeded: state >> 32)
                bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value; bytes[offset + 3] = 255
            }
            let noise = CIImage(bitmapData: Data(bytes), bytesPerRow: 256, size: CGSize(width: 64, height: 64), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()).transformed(by: .init(scaleX: rect.width / 64, y: rect.height / 64))
            return alpha(noise, min(0.35, abs(a) * 0.25)).applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        }
    }

    private func neon(_ effect: EffectInstance, image: CIImage, isolated: Bool) -> CIImage {
        let rect = image.extent, unit = max(rect.width, rect.height) / 720
        let amount = min(1, max(0, effect.amount)), tint = color(effect.colorHex ?? "#49E6FF")
        let edges: CIImage
        if isolated {
            let silhouette = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
            edges = silhouette.applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: max(1, 2 * unit)])
        } else {
            edges = image.clampedToExtent().applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.4])
        }
        let mask = edges.cropped(to: rect).applyingFilter("CIMaskToAlpha")
        let transparent = CIImage(color: .clear).cropped(to: rect)
        let outline = CIImage(color: tint).cropped(to: rect).applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: transparent, kCIInputMaskImageKey: mask])
        let spread = effect.neonGlowRadius
        guard spread > 0 else { return alpha(outline, amount).composited(over: image).cropped(to: rect) }
        // Give the blur enough luminous energy to remain visible away from a thin edge.
        // A tight glow and a broad halo keep the neon core crisp without tying spread to intensity.
        let glowSource = outline.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: (1 + spread * 5) * unit])
        let nearGlow = glowSource.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: (2 + spread * 6) * unit])
        let halo = glowSource.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: (2 + spread * 52) * unit])
        return alpha(outline, amount).composited(over: alpha(nearGlow, amount * 0.85))
            .composited(over: alpha(halo, amount)).composited(over: image).cropped(to: rect)
    }

    private func segmentPerson(in image: CIImage, cacheKey: String, feather: Double) throws -> CIImage {
        try Task.checkCancellation()
        let rawMask: CIImage
        if let cached = personMasks[cacheKey] { rawMask = cached }
        else {
            let request = VNGeneratePersonSegmentationRequest()
            request.usesCPUOnly = softwareRendering
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            try handler.perform([request])
            try Task.checkCancellation()
            guard let observation = request.results?.first else { throw MediaFailure.rendering("Vision n’a pas produit de masque de personne") }
            rawMask = CIImage(cvPixelBuffer: observation.pixelBuffer)
            if personMasks.count >= 8 { personMasks.removeAll(keepingCapacity: true) }
            personMasks[cacheKey] = rawMask
        }
        var mask = rawMask.transformed(by: .init(scaleX: image.extent.width / rawMask.extent.width, y: image.extent.height / rawMask.extent.height))
        if feather > 0 { mask = mask.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather * min(image.extent.width, image.extent.height) * 0.03]).cropped(to: image.extent) }
        return mask
    }

    private func chroma(_ image: CIImage, key: CIColor, tolerance: Double, softness: Double) -> CIImage {
        let n = 24
        let cacheKey = "\(key.red)|\(key.green)|\(key.blue)|\(tolerance)|\(softness)"
        if let data = chromaCubes[cacheKey] { return image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": n, "inputCubeData": data]) }
        var cube = [Float](); cube.reserveCapacity(n * n * n * 4)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let red = Float(r) / Float(n - 1), green = Float(g) / Float(n - 1), blue = Float(b) / Float(n - 1)
            let distance = sqrt(pow(Double(red) - key.red, 2) + pow(Double(green) - key.green, 2) + pow(Double(blue) - key.blue, 2))
            let alpha = Float(min(1, max(0, (distance - tolerance) / max(0.001, softness))))
            // Despill only the keyed dominant channel in partially transparent edges.
            var rOut = red, gOut = green, bOut = blue
            if alpha < 1 {
                if key.green > max(key.red, key.blue) { gOut = min(green, max(red, blue) + (green - max(red, blue)) * alpha) }
                if key.blue > max(key.red, key.green) { bOut = min(blue, max(red, green) + (blue - max(red, green)) * alpha) }
                if key.red > max(key.green, key.blue) { rOut = min(red, max(green, blue) + (red - max(green, blue)) * alpha) }
            }
            cube += [rOut * alpha, gOut * alpha, bOut * alpha, alpha]
        } } }
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        if chromaCubes.count >= 8 { chromaCubes.removeAll(keepingCapacity: true) }
        chromaCubes[cacheKey] = data
        return image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": n, "inputCubeData": data])
    }

    private func maskImage(_ p: Presentation, rect: CGRect) throws -> CIImage {
        guard let context = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw MediaFailure.rendering("Masque") }
        context.setFillColor(gray: p.maskInverted ? 1 : 0, alpha: 1); context.fill(rect)
        context.translateBy(x: rect.width * p.maskX, y: rect.height * (1 - p.maskY))
        context.rotate(by: -p.maskRotation * .pi / 180)
        context.setFillColor(gray: p.maskInverted ? 0 : 1, alpha: 1)
        let box = CGRect(x: -rect.width * p.maskWidth / 2, y: -rect.height * p.maskHeight / 2, width: rect.width * p.maskWidth, height: rect.height * p.maskHeight)
        switch p.mask {
        case .none: context.fill(rect)
        case .ellipse: context.fillEllipse(in: box)
        case .rectangle, .band: context.fill(box)
        case .roundedRectangle: context.addPath(CGPath(roundedRect: box, cornerWidth: min(box.width, box.height) * 0.18, cornerHeight: min(box.width, box.height) * 0.18, transform: nil)); context.fillPath()
        case .linear: context.fill(CGRect(x: -rect.width * 2, y: -rect.height * 2, width: rect.width * 4, height: rect.height * 2))
        }
        guard let raster = context.makeImage() else { throw MediaFailure.rendering("Masque raster") }
        var mask = CIImage(cgImage: raster)
        if p.maskFeather > 0 { mask = mask.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: p.maskFeather * min(rect.width, rect.height) * 0.15]).cropped(to: rect) }
        return mask
    }

    private func transition(_ outgoing: CIImage, _ incoming: CIImage, kind: TransitionKind, progress: Double, rect: CGRect) -> CIImage {
        let p = min(1, max(0, progress))
        switch kind {
        case .none: return incoming
        case .dissolve: return alpha(incoming, p).composited(over: outgoing)
        case .black, .white:
            let middle = CIImage(color: kind == .black ? .black : .white).cropped(to: rect)
            return p < 0.5 ? alpha(middle, p * 2).composited(over: outgoing) : alpha(incoming, (p - 0.5) * 2).composited(over: middle)
        case .slide:
            return incoming.transformed(by: .init(translationX: rect.width * (1 - p), y: 0)).composited(over: outgoing.transformed(by: .init(translationX: -rect.width * p, y: 0))).cropped(to: rect)
        case .wipe: return incoming.cropped(to: CGRect(x: 0, y: 0, width: rect.width * p, height: rect.height)).composited(over: outgoing)
        case .zoom:
            let scale = 1 + (1 - p) * 0.8
            let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: scale, y: scale).translatedBy(x: -rect.midX, y: -rect.midY)
            return alpha(incoming.transformed(by: transform), p).composited(over: outgoing).cropped(to: rect)
        case .blur:
            let radius = sin(p * .pi) * rect.width / 30
            let mixed = alpha(incoming, p).composited(over: outgoing)
            return mixed.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: rect)
        case .glitch:
            var result = alpha(incoming, p).composited(over: outgoing)
            for row in 0..<7 {
                let band = CGRect(x: 0, y: rect.height * Double(row) / 7, width: rect.width, height: rect.height / 7)
                let dx = sin(Double(row) * 15 + p * 91) * sin(p * .pi) * rect.width * 0.12
                let source = row.isMultiple(of: 2) ? incoming : outgoing
                result = source.cropped(to: band).transformed(by: .init(translationX: dx, y: 0)).composited(over: result)
            }
            return result.cropped(to: rect)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

func color(_ hex: String) -> CIColor {
    let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let value = UInt64(normalized, radix: 16) ?? 0xFFFFFF
    return CIColor(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
}

enum TextRasterizer {
    static func render(text: String, presentation p: Presentation, size: CGSize) throws -> CGImage {
        let rect = CGRect(origin: .zero, size: size)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw MediaFailure.rendering("Texte") }
        let fontName = p.textFont == "system" ? (p.textBold ? "HelveticaNeue-Bold" : "HelveticaNeue") : p.textFont
        let fontSize = max(8, p.textSize * min(size.width, size.height))
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        var alignment: CTTextAlignment = p.textAlignment == "left" ? .left : p.textAlignment == "right" ? .right : .center
        var spacing = CGFloat(p.textLineSpacing) * fontSize
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            withUnsafePointer(to: &spacing) { space in
                let settings = [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer), CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: space)]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        let ink = color(p.color)
        let cgColor = CGColor(red: ink.red, green: ink.green, blue: ink.blue, alpha: 1)
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor, NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph]
        attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = p.textLetterSpacing * fontSize
        if p.textOutline > 0 { attrs[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -p.textOutline * 5; attrs[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = CGColor(gray: 0, alpha: 1) }
        let string = NSAttributedString(string: text, attributes: attrs)
        let setter = CTFramesetterCreateWithAttributedString(string)
        let backdrop = p.textBackgroundOpacity > 0
        let maxWidth = rect.width * (backdrop ? p.textBackgroundShape.widthLimit : 0.86)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil, CGSize(width: maxWidth, height: rect.height * 0.9 / (backdrop ? p.textBackgroundShape.expansion : 1)), nil)
        let textRect = CGRect(x: (rect.width - maxWidth) / 2, y: max(0, (rect.height - ceil(fit.height)) / 2), width: maxWidth, height: min(rect.height, ceil(fit.height) + 4))
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: textRect, transform: nil), nil)
        if p.textBackgroundOpacity > 0 {
            let bg = color(p.background)
            context.setFillColor(CGColor(red: bg.red, green: bg.green, blue: bg.blue, alpha: p.textBackgroundOpacity))
            let lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            var bounds = CGRect.null
            for (index, line) in lines.enumerated() {
                var ascent: CGFloat = 0, descent: CGFloat = 0
                let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                bounds = bounds.union(CGRect(x: textRect.minX + origins[index].x, y: textRect.minY + origins[index].y - descent, width: width, height: ascent + descent))
            }
            if !bounds.isNull {
                let padded = bounds.insetBy(dx: -fontSize * 0.3, dy: -fontSize * 0.2)
                let factor = p.textBackgroundShape.expansion
                let width = min(rect.width - 4, padded.width * factor)
                let height = min(rect.height - 4, padded.height * factor)
                let centerY = padded.midY - (p.textBackgroundShape == .heart ? height * 0.08 : 0)
                let backgroundRect = CGRect(x: padded.midX - width / 2, y: max(2, min(rect.height - height - 2, centerY - height / 2)), width: width, height: height)
                context.addPath(p.textBackgroundShape.path(in: backgroundRect)); context.fillPath()
            }
        }
        if p.textShadow > 0 { context.setShadow(offset: CGSize(width: 0, height: -2), blur: p.textShadow * 8, color: CGColor(gray: 0, alpha: 0.8)) }
        CTFrameDraw(frame, context)
        guard let raster = context.makeImage() else { throw MediaFailure.rendering("Texte raster") }
        return raster
    }
}

extension TextBackgroundShape {
    /// Original vector backdrops, shared by preview and export; coordinates use Core Graphics' upward Y axis.
    func path(in rect: CGRect) -> CGPath {
        switch self {
        case .rectangle: return CGPath(rect: rect, transform: nil)
        case .rounded: return CGPath(roundedRect: rect, cornerWidth: min(rect.height * 0.22, rect.width * 0.1), cornerHeight: min(rect.height * 0.22, rect.width * 0.1), transform: nil)
        case .capsule: return CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        case .star:
            let path = CGMutablePath()
            for index in 0..<10 {
                let angle = Double.pi / 2 + Double(index) * Double.pi / 5
                let radius = index.isMultiple(of: 2) ? 0.5 : 0.3
                let point = CGPoint(x: rect.midX + cos(angle) * rect.width * radius, y: rect.midY + sin(angle) * rect.height * radius)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath(); return path
        case .heart, .cloud:
            let path = CGMutablePath()
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
            func curve(_ x: Double, _ y: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) {
                path.addCurve(to: point(x, y), control1: point(a, b), control2: point(c, d))
            }
            if self == .heart {
                path.move(to: point(0.5, 0))
                curve(0, 0.72, 0.4, 0.14, 0, 0.42)
                curve(0.5, 0.82, 0, 1.06, 0.36, 1.08)
                curve(1, 0.72, 0.64, 1.08, 1, 1.06)
                curve(0.5, 0, 1, 0.42, 0.6, 0.14)
            } else {
                path.move(to: point(0.18, 0.1))
                curve(0.08, 0.58, -0.08, 0.08, -0.05, 0.5)
                curve(0.34, 0.88, 0, 0.84, 0.16, 1)
                curve(0.7, 0.9, 0.42, 1.04, 0.62, 1.04)
                curve(0.92, 0.57, 0.86, 1, 1, 0.8)
                curve(0.82, 0.1, 1.06, 0.45, 1.05, 0.08)
                curve(0.5, 0.08, 0.7, -0.02, 0.6, -0.01)
                curve(0.18, 0.1, 0.35, -0.02, 0.22, -0.03)
            }
            path.closeSubpath(); return path
        }
    }
}
