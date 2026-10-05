import AVFoundation
import Combine
import Foundation
import Vision

struct TrackedPoint: Equatable, Sendable {
    let sourceSeconds: Double
    let centerX: Double
    let centerY: Double // Vision coordinates: origin at bottom left.
    let confidence: Float
}
struct TrackingResult: Sendable {
    let points: [TrackedPoint]
    let lostAtSourceSeconds: Double?
}

enum VisionAnalysisError: LocalizedError {
    case noVideo, invalidRegion, tooLong, stabilizationTooLong, lostImmediately, noSamples
    var errorDescription: String? {
        let french = Locale.current.language.languageCode?.identifier == "fr"
        switch self {
        case .noVideo: return french ? "Sélectionnez une vidéo décodable." : "Select a decodable video."
        case .invalidRegion: return french ? "Dessinez une région à suivre dans l’image." : "Draw a region to track in the image."
        case .tooLong: return french ? "Limitez l’extrait à 10 minutes pour cette analyse locale." : "Trim the selected clip to ten minutes for this local analysis."
        case .stabilizationTooLong: return french ? "Limitez l’extrait à 60 secondes pour la stabilisation locale." : "Trim the clip to 60 seconds for local stabilization."
        case .lostImmediately: return french ? "La région a été perdue dès le début. Choisissez une zone plus contrastée." : "The region was lost immediately. Choose a more distinctive area."
        case .noSamples: return french ? "La source et la couche choisie ne se chevauchent pas." : "The source and selected layer do not overlap."
        }
    }
}

@MainActor
final class VisionTrackingService: ObservableObject {
    @Published private(set) var progress = 0.0
    @Published private(set) var isWorking = false
    private var work: Task<TrackingResult, Error>?

    func track(url: URL, sourceStart: Double, duration: Double, region: CGRect, framesPerSecond: Double = 10) async throws -> TrackingResult {
        guard !isWorking else { throw VoiceServiceError.busy }
        guard duration > 0, duration <= 600 else { throw VisionAnalysisError.tooLong }
        guard region.minX >= 0, region.minY >= 0, region.maxX <= 1, region.maxY <= 1, region.width >= 0.015, region.height >= 0.015 else { throw VisionAnalysisError.invalidRegion }
        isWorking = true; progress = 0
        defer { isWorking = false; work = nil }
        let service = self
        let job = Task.detached(priority: .userInitiated) {
            try await Self.analyze(url: url, start: sourceStart, duration: duration, region: region, fps: max(1, min(10, framesPerSecond))) { progress in
                Task { @MainActor in service.progress = progress }
            }
        }
        work = job
        return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
    }

    func cancel() { work?.cancel() }

    nonisolated private static func analyze(url: URL, start: Double, duration: Double, region: CGRect, fps: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> TrackingResult {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw VisionAnalysisError.noVideo }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let sequence = VNSequenceRequestHandler()
        var observation = VNDetectedObjectObservation(boundingBox: region)
        var points: [TrackedPoint] = []
        let count = max(2, Int(ceil(duration * fps)))
        for index in 0..<count {
            try Task.checkCancellation()
            let requestedSeconds = start + min(duration - 1 / 600, Double(index) / fps)
            let generated = try await generator.image(at: CMTime(seconds: requestedSeconds, preferredTimescale: 60_000))
            let result: VNDetectedObjectObservation? = try autoreleasepool {
                let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                request.trackingLevel = .accurate
                try sequence.perform([request], on: generated.image)
                return request.results?.first as? VNDetectedObjectObservation
            }
            guard let result, result.confidence >= 0.3 else {
                guard points.count >= 2 else { throw VisionAnalysisError.lostImmediately }
                return .init(points: points, lostAtSourceSeconds: generated.actualTime.seconds)
            }
            observation = result
            points.append(.init(sourceSeconds: generated.actualTime.seconds, centerX: result.boundingBox.midX, centerY: result.boundingBox.midY, confidence: result.confidence))
            progress(Double(index + 1) / Double(count))
        }
        return .init(points: points, lostAtSourceSeconds: nil)
    }

    /// Resolves media orientation before Vision; converts its coordinates through the exact
    /// active presentation (fit/fill, scale, mirror, rotation) into normalized canvas positions.
    static func keyframes(from result: TrackingResult, source: RenderClip, sourceAsset: MediaAsset, target: RenderClip, variant: OutputVariant) -> [Keyframe] {
        let canvasW = variant.ratio, canvasH = 1.0
        let sourceW = Double(max(1, sourceAsset.width)), sourceH = Double(max(1, sourceAsset.height))
        var frames: [Keyframe] = []
        var usedTimes = Set<MediaTime>()
        for point in result.points {
            let local = TimeMapping.localTime(forSource: .init(seconds: point.sourceSeconds), clip: source.clip)
            let global = source.globalStart + local
            guard global >= target.globalStart, global < target.end else { continue }
            let time = global - target.globalStart + target.clip.animationOffset
            guard usedTimes.insert(time).inserted else { continue }
            let p = source.evaluatedPresentation(at: global)
            let fit = p.fill ? max(canvasW / sourceW, canvasH / sourceH) : min(canvasW / sourceW, canvasH / sourceH)
            let x = (point.centerX - 0.5) * sourceW * fit * p.scale * (p.mirror ? -1 : 1)
            let y = (0.5 - point.centerY) * sourceH * fit * p.scale
            let angle = p.rotation * .pi / 180
            let mappedX = p.x + (x * cos(angle) - y * sin(angle)) / canvasW
            let mappedY = p.y + (x * sin(angle) + y * cos(angle)) / canvasH
            // Convert the desired active-format location into the common animation domain.
            frames.append(.init(time: time, property: .x, value: target.clip.presentation.x + mappedX - target.presentation.x))
            frames.append(.init(time: time, property: .y, value: target.clip.presentation.y + mappedY - target.presentation.y))
        }
        return frames.sorted { $0.time < $1.time }
    }
}

struct StabilizationSample: Sendable {
    let sourceSeconds: Double
    let correctionX: Double // Normalized oriented-media width.
    let correctionY: Double // Normalized oriented-media height, top-left origin.
}
struct StabilizationResult: Sendable {
    let samples: [StabilizationSample]
    let cropScale: Double
    let measuredJitter: Double
    let smoothedJitter: Double
}

/// Translation-only stabilization for short imported shots. Registration measures image content;
/// a symmetric temporal average removes rapid displacement while retaining slow movement.
@MainActor
final class VisionStabilizationService: ObservableObject {
    @Published private(set) var progress = 0.0
    @Published private(set) var isWorking = false
    private var work: Task<StabilizationResult, Error>?
    func cancel() { work?.cancel() }

    func analyze(url: URL, sourceStart: Double, duration: Double, maximumCrop: Double = 1.15) async throws -> StabilizationResult {
        guard !isWorking else { throw VoiceServiceError.busy }
        guard duration > 0, duration <= 60 else { throw VisionAnalysisError.stabilizationTooLong }
        isWorking = true; progress = 0
        defer { isWorking = false; work = nil }
        let service = self
        let job = Task.detached(priority: .userInitiated) {
            try await Self.register(url: url, start: sourceStart, duration: duration, maximumCrop: maximumCrop) { progress in Task { @MainActor in service.progress = progress } }
        }
        work = job
        return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
    }

    nonisolated private static func register(url: URL, start: Double, duration: Double, maximumCrop: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> StabilizationResult {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VisionAnalysisError.noVideo }
        let frameRate = Double(try await track.load(.nominalFrameRate))
        // Analyze every output sample up to 30 Hz; never claim to correct unsampled high-frequency motion.
        let fps = min(30, max(1, frameRate))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: CMTime(seconds: start, preferredTimescale: 60_000)).image
        let referencePixels = try StabilizationRegistrationFrame(image: first)
        let count = max(2, Int(ceil(duration * fps)))
        var offsets: [(Double, Double, Double)] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let seconds = start + min(duration - 1 / 600, Double(index) / fps)
            let generated = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 60_000))
            let visionAlignment: CGAffineTransform = try autoreleasepool {
                let request = VNTranslationalImageRegistrationRequest(targetedCGImage: generated.image)
                let handler = VNImageRequestHandler(cgImage: first)
                try handler.perform([request])
                guard let observation = request.results?.first else { throw VisionAnalysisError.noSamples }
                return observation.alignmentTransform
            }
            let pixels = try StabilizationRegistrationFrame(image: generated.image)
            let alignment = try StabilizationRegistration.translation(reference: referencePixels, current: pixels, initial: visionAlignment)
            let x = alignment.tx / Double(generated.image.width), y = -alignment.ty / Double(generated.image.height)
            guard x.isFinite, y.isFinite, abs(x) < 0.2, abs(y) < 0.2 else { throw VisionAnalysisError.lostImmediately }
            offsets.append((generated.actualTime.seconds, x, y))
            progress(Double(index + 1) / Double(count))
        }
        let radius = max(2, Int(fps * 0.18))
        var samples: [StabilizationSample] = []
        var smooth: [(Double, Double)] = []
        var maxCorrection = 0.0
        for index in offsets.indices {
            let range = max(0, index - radius)...min(offsets.count - 1, index + radius)
            let sx = range.reduce(0.0) { $0 + offsets[$1].1 } / Double(range.count)
            let sy = range.reduce(0.0) { $0 + offsets[$1].2 } / Double(range.count)
            smooth.append((sx, sy))
            let dx = offsets[index].1 - sx, dy = offsets[index].2 - sy
            maxCorrection = max(maxCorrection, max(abs(dx), abs(dy)))
            samples.append(.init(sourceSeconds: offsets[index].0, correctionX: dx, correctionY: dy))
        }
        let crop = 1 / max(0.5, 1 - 2 * maxCorrection)
        guard crop <= max(1.01, maximumCrop) else { throw DocumentError.invalid("Le mouvement dépasse le recadrage autorisé. Augmentez la marge ou choisissez un extrait plus stable.") }
        func jitter(_ positions: [(Double, Double)]) -> Double {
            guard positions.count > 1 else { return 0 }
            return sqrt((1..<positions.count).reduce(0.0) { value, i in value + pow(positions[i].0 - positions[i - 1].0, 2) + pow(positions[i].1 - positions[i - 1].1, 2) } / Double(positions.count - 1))
        }
        return .init(samples: samples, cropScale: crop, measuredJitter: jitter(offsets.map { ($0.1, $0.2) }), smoothedJitter: jitter(smooth))
    }

    static func keyframes(from result: StabilizationResult, source: RenderClip, asset: MediaAsset, variant: OutputVariant) -> [Keyframe] {
        let canvasW = variant.ratio, canvasH = 1.0
        let sourceW = Double(max(1, asset.width)), sourceH = Double(max(1, asset.height))
        var keys: [Keyframe] = []
        for sample in result.samples {
            let local = TimeMapping.localTime(forSource: .init(seconds: sample.sourceSeconds), clip: source.clip)
            let p = source.evaluatedPresentation(at: source.globalStart + local)
            let fit = p.fill ? max(canvasW / sourceW, canvasH / sourceH) : min(canvasW / sourceW, canvasH / sourceH)
            let scale = p.scale * result.cropScale
            let x = sample.correctionX * sourceW * fit * scale * (p.mirror ? -1 : 1)
            let y = sample.correctionY * sourceH * fit * scale
            let angle = p.rotation * .pi / 180
            let time = local + source.clip.animationOffset
            // Store common-domain keyframes: the renderer composes their delta/ratio
            // onto the variant baseline. Storing the resolved framing would apply it twice.
            let common = source.clip.presentation, baseline = source.presentation
            keys.append(.init(time: time, property: .x, value: common.x + p.x - baseline.x + (x * cos(angle) - y * sin(angle)) / canvasW))
            keys.append(.init(time: time, property: .y, value: common.y + p.y - baseline.y + (x * sin(angle) + y * cos(angle)) / canvasH))
            keys.append(.init(time: time, property: .scale, value: scale * common.scale / baseline.scale))
        }
        return keys
    }
}

/// A bounded luminance raster used to verify image registration. Vision's phase correlation
/// can choose a periodic texture's wrong peak while still reporting confidence 1. A real
/// photometric match checks that peak and searches only physically plausible translations.
struct StabilizationRegistrationFrame {
    let width: Int
    let height: Int
    let scale: Double
    let pixels: [UInt8]
    init(image: CGImage) throws {
        width = min(240, image.width)
        height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
        scale = Double(width) / Double(image.width)
        let rasterWidth = width, rasterHeight = height
        var bytes = [UInt8](repeating: 0, count: rasterWidth * rasterHeight)
        let didDraw = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: rasterWidth, height: rasterHeight, bitsPerComponent: 8, bytesPerRow: rasterWidth, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: rasterWidth, height: rasterHeight))
            return true
        }
        guard didDraw else { throw VisionAnalysisError.noSamples }
        pixels = bytes
    }
}

enum StabilizationRegistration {
    static func translation(reference: StabilizationRegistrationFrame, current: StabilizationRegistrationFrame, initial: CGAffineTransform) throws -> CGAffineTransform {
        guard reference.width == current.width, reference.height == current.height else { throw VisionAnalysisError.noSamples }
        let width = reference.width, height = reference.height
        let radiusX = max(2, Int(Double(width) * 0.18)), radiusY = max(2, Int(Double(height) * 0.18))
        let marginX = radiusX + 2, marginY = radiusY + 2
        guard width > 2 * marginX + 4, height > 2 * marginY + 4 else { throw VisionAnalysisError.noSamples }
        // The fixed interior has equal support for all candidates. Edges, letterboxing,
        // frame counters and newly exposed pixels cannot dominate the comparison.
        func score(_ dx: Int, _ dy: Int, stride step: Int) -> Double {
            var error = 0.0, samples = 0
            for y in Swift.stride(from: marginY, to: height - marginY, by: step) {
                let row = y * width, shiftedRow = (y - dy) * width
                for x in Swift.stride(from: marginX, to: width - marginX, by: step) {
                    let difference = Double(reference.pixels[row + x]) - Double(current.pixels[shiftedRow + x - dx])
                    error += min(2500, difference * difference)
                    samples += 1
                }
            }
            return error / Double(max(1, samples))
        }
        var bestX = 0, bestY = 0, bestScore = score(0, 0, stride: 4)
        // Raster rows increase downward. Vision's CG affine y translation increases
        // upward, so both the candidate and result need an explicit sign conversion.
        if initial.tx.isFinite, initial.ty.isFinite,
           abs(initial.tx * reference.scale) <= Double(radiusX) + 1,
           abs(initial.ty * reference.scale) <= Double(radiusY) + 1 {
            let candidateX = Int((initial.tx * reference.scale).rounded()), candidateY = Int((-initial.ty * reference.scale).rounded())
            if abs(candidateX) <= radiusX, abs(candidateY) <= radiusY {
                let candidateScore = score(candidateX, candidateY, stride: 4)
                if candidateScore < bestScore { bestX = candidateX; bestY = candidateY; bestScore = candidateScore }
            }
        }
        // A coarse-to-fine pixel search is independent of the fixture's known trajectory.
        // It validates plausible Vision results too, which may lock onto a moving foreground.
        for dy in Swift.stride(from: -radiusY, through: radiusY, by: 3) {
            for dx in Swift.stride(from: -radiusX, through: radiusX, by: 3) {
                let candidate = score(dx, dy, stride: 4)
                if candidate < bestScore { bestScore = candidate; bestX = dx; bestY = dy }
            }
        }
        let coarseX = bestX, coarseY = bestY
        bestScore = score(bestX, bestY, stride: 2)
        for dy in max(-radiusY, coarseY - 3)...min(radiusY, coarseY + 3) {
            for dx in max(-radiusX, coarseX - 3)...min(radiusX, coarseX + 3) {
                let candidate = score(dx, dy, stride: 2)
                if candidate < bestScore { bestScore = candidate; bestX = dx; bestY = dy }
            }
        }
        var sum = 0.0, squares = 0.0, count = 0.0
        for y in Swift.stride(from: marginY, to: height - marginY, by: 4) {
            for x in Swift.stride(from: marginX, to: width - marginX, by: 4) {
                let value = Double(reference.pixels[y * width + x]); sum += value; squares += value * value; count += 1
            }
        }
        let variance = squares / count - pow(sum / count, 2)
        guard variance > 4, bestScore < max(25, variance * 0.6) else { throw VisionAnalysisError.lostImmediately }
        return CGAffineTransform(translationX: Double(bestX) / reference.scale, y: -Double(bestY) / reference.scale)
    }
}
