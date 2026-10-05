import Foundation
@preconcurrency import AVFoundation
import CoreImage
import CoreText
import ImageIO
import Vision

/// Both preview and export call this renderer. Caches contain derived resources only.
/// The actor serializes access to image generators; images are bounded to output size.
actor FrameRenderer {
    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, .outputColorSpace: CGColorSpace(name: CGColorSpace.itur_709)!])
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
            let key = "\(clip.text)|\(p.textSize)|\(p.color)|\(p.textFont)|\(p.textAlignment)|\(p.textBold)|\(p.textOutline)|\(p.textShadow)|\(p.background)|\(p.textBackgroundOpacity)|\(p.textLetterSpacing)|\(p.textLineSpacing)|\(Int(rect.width))x\(Int(rect.height))"
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
                let generated = try await withTaskCancellationHandler {
                    try await generator.image(at: CMTime(seconds: sourceSeconds, preferredTimescale: 60_000))
                } onCancel: { generator.cancelAllCGImageGeneration() }
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
        for var effect in clip.effects {
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
        case .pixelate: return image.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(1, abs(a) * 45 * radius)])
        case .shake: return image.transformed(by: CGAffineTransform(translationX: sin(time * 47) * a * 12 * radius, y: cos(time * 61) * a * 9 * radius))
        case .retro:
            let stylized = image.applyingFilter("CIPhotoEffectProcess")
            return alpha(stylized, min(1, abs(a))).composited(over: image)
        case .rgbSplit:
            let shift = abs(a) * 16 * radius
            let r = image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1,y: 0,z: 0,w: 0), "inputGVector": CIVector(x: 0,y: 0,z: 0,w: 0), "inputBVector": CIVector(x: 0,y: 0,z: 0,w: 0)]).transformed(by: .init(translationX: shift, y: 0))
            let gb = image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0,y: 0,z: 0,w: 0)]).transformed(by: .init(translationX: -shift, y: 0))
            return r.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: gb])
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

    private func segmentPerson(in image: CIImage, cacheKey: String, feather: Double) throws -> CIImage {
        try Task.checkCancellation()
        let rawMask: CIImage
        if let cached = personMasks[cacheKey] { rawMask = cached }
        else {
            let request = VNGeneratePersonSegmentationRequest()
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
        let maxWidth = rect.width * 0.86
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil, CGSize(width: maxWidth, height: rect.height * 0.9), nil)
        let textRect = CGRect(x: (rect.width - maxWidth) / 2, y: max(0, (rect.height - ceil(fit.height)) / 2), width: maxWidth, height: min(rect.height, ceil(fit.height) + 4))
        if p.textBackgroundOpacity > 0 {
            let bg = color(p.background)
            context.setFillColor(CGColor(red: bg.red, green: bg.green, blue: bg.blue, alpha: p.textBackgroundOpacity))
            context.addPath(CGPath(roundedRect: textRect.insetBy(dx: -10, dy: -7), cornerWidth: 8, cornerHeight: 8, transform: nil)); context.fillPath()
        }
        if p.textShadow > 0 { context.setShadow(offset: CGSize(width: 0, height: -2), blur: p.textShadow * 8, color: CGColor(gray: 0, alpha: 0.8)) }
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: textRect, transform: nil), nil)
        CTFrameDraw(frame, context)
        guard let raster = context.makeImage() else { throw MediaFailure.rendering("Texte raster") }
        return raster
    }
}
