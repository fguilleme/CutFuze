import AVFoundation
import XCTest
@testable import CutFuze

@MainActor
final class VisionTests: XCTestCase {
    func testRealVisionTracksEncodedMovingRectangle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await SyntheticVideoCorpus.make(in: root)
        let tracker = VisionTrackingService()
        let result = try await tracker.track(url: fixture.movieURL, sourceStart: 0, duration: 2, region: CGRect(x: 40.0 / 320, y: 68.0 / 180, width: 44.0 / 320, height: 44.0 / 180))
        XCTAssertNil(result.lostAtSourceSeconds)
        XCTAssertGreaterThanOrEqual(result.points.count, 18)
        let first = try XCTUnwrap(result.points.first), last = try XCTUnwrap(result.points.last)
        XCTAssertGreaterThan(last.centerX - first.centerX, 0.3)
        XCTAssertLessThan(abs(last.centerY - first.centerY), 0.08)
        XCTAssertGreaterThanOrEqual(result.points.map(\.confidence).min() ?? 0, 0.3)
        XCTAssertEqual(last.centerX, (40 + 57 * 2.3 + 22) / 320, accuracy: 0.055)
        let proof = XCTAttachment(string: "Real Vision samples: \(result.points.count); first center: \(first.centerX),\(first.centerY); last center: \(last.centerX),\(last.centerY); minimum confidence: \(result.points.map(\.confidence).min() ?? 0)")
        proof.name = "Vision-tracking-measurements"; proof.lifetime = .keepAlways; add(proof)
    }

    func testStabilizationReducesMeasuredMotionInActualRenderedFrames() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await SyntheticVideoCorpus.make(in: root, cameraShake: true)
        let service = VisionStabilizationService()
        let result = try await service.analyze(url: fixture.movieURL, sourceStart: 0, duration: 2, maximumCrop: 1.2)
        XCTAssertGreaterThan(result.measuredJitter, 0.005)
        XCTAssertLessThan(result.smoothedJitter, result.measuredJitter * 0.5)
        XCTAssertLessThan(result.cropScale, 1.2)
        let asset = MediaAsset(relativePath: fixture.movieURL.lastPathComponent, kind: .video, name: "Shake", duration: .init(seconds: 2), width: 320, height: 180, nominalFrameRate: 30)
        let clip = Clip(assetID: asset.id, kind: .video, duration: .init(seconds: 2), sourceDuration: .init(seconds: 2))
        var document = ProjectDocument(assets: [asset], scenes: [.init(duration: .init(seconds: 2), clips: [clip])], variants: [.init(name: "Test", widthRatio: 16, heightRatio: 9)])
        let before = RenderPlan.compile(document: document, variantID: nil)
        document.scenes[0].clips[0].keyframes = VisionStabilizationService.keyframes(from: result, source: before.clips[0], asset: asset, variant: before.variant)
        let after = RenderPlan.compile(document: document, variantID: nil)
        let renderer = FrameRenderer()
        var raw: [CGPoint] = [], corrected: [CGPoint] = []
        for frame in stride(from: 0, to: 60, by: 3) {
            let time = MediaTime(seconds: Double(frame) / 30)
            let a = try await renderer.render(plan: before, time: time, rootURL: root, size: CGSize(width: 320, height: 180))
            let b = try await renderer.render(plan: after, time: time, rootURL: root, size: CGSize(width: 320, height: 180))
            raw.append(try orangeCenter(a)); corrected.append(try orangeCenter(b))
        }
        func deviation(_ points: [CGPoint]) -> Double {
            let x = points.map(\.x).reduce(0,+) / Double(points.count), y = points.map(\.y).reduce(0,+) / Double(points.count)
            return sqrt(points.reduce(0.0) { $0 + pow($1.x - x, 2) + pow($1.y - y, 2) } / Double(points.count))
        }
        let beforeDeviation = deviation(raw), afterDeviation = deviation(corrected)
        let proof = XCTAttachment(string: "Translation-only stabilization; raw rendered center RMS: \(beforeDeviation) pixels; corrected rendered center RMS: \(afterDeviation) pixels; ratio: \(afterDeviation / beforeDeviation); applied crop scale: \(result.cropScale); measured registration jitter: \(result.measuredJitter); smoothed jitter: \(result.smoothedJitter)")
        proof.name = "Vision-stabilization-measurements"; proof.lifetime = .keepAlways; add(proof)
        XCTAssertLessThan(afterDeviation, beforeDeviation * 0.55, "The rendered correction must reduce the actual moving-object displacement.")
    }

    func testStabilizationRejectsPeriodicTextureRegistrationOutlierUsingRealPixels() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await SyntheticVideoCorpus.make(in: root, cameraShake: true)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fixture.movieURL))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: .zero).image
        let shifted = try await generator.image(at: CMTime(value: 7, timescale: 30)).image
        // This is the spurious correlation peak observed on the encoded repeated grid.
        // The expected correction below is measured from pixels, not fixture formulas.
        let corrected = try StabilizationRegistration.translation(reference: StabilizationRegistrationFrame(image: first), current: StabilizationRegistrationFrame(image: shifted), initial: .init(translationX: 4, y: -93))
        let before = try orangeCenter(first), after = try orangeCenter(shifted)
        XCTAssertEqual(corrected.tx, before.x - after.x, accuracy: 1.8)
        XCTAssertEqual(corrected.ty, after.y - before.y, accuracy: 1.8)
    }

    func testStabilizationKeyframesRespectVariantFraming() throws {
        let asset = MediaAsset(relativePath: "sample.mp4", kind: .video, name: "Sample", duration: .init(seconds: 1), width: 320, height: 180)
        let clip = Clip(assetID: asset.id, kind: .video, duration: .init(seconds: 1), sourceDuration: .init(seconds: 1))
        var framing = Presentation(); framing.x = 0.25; framing.scale = 1.4
        var document = ProjectDocument(assets: [asset], scenes: [.init(duration: .init(seconds: 1), clips: [clip])], variants: [.init(name: "Test", widthRatio: 16, heightRatio: 9, overrides: [clip.id.uuidString: framing])])
        let before = RenderPlan.compile(document: document, variantID: nil)
        let result = StabilizationResult(samples: [.init(sourceSeconds: 0, correctionX: 0.01, correctionY: 0)], cropScale: 1.1, measuredJitter: 0.02, smoothedJitter: 0.001)
        document.scenes[0].clips[0].keyframes = VisionStabilizationService.keyframes(from: result, source: before.clips[0], asset: asset, variant: before.variant)
        let evaluated = RenderPlan.compile(document: document, variantID: nil).clips[0].evaluatedPresentation(at: .zero)
        XCTAssertEqual(evaluated.scale, 1.54, accuracy: 0.00001)
        XCTAssertEqual(evaluated.x, 0.2654, accuracy: 0.00001)
    }

    func testTrackingKeyframesRespectTargetVariantBaseline() throws {
        let asset = MediaAsset(relativePath: "sample.mp4", kind: .video, name: "Sample", duration: .init(seconds: 1), width: 320, height: 180)
        let video = Clip(assetID: asset.id, kind: .video, duration: .init(seconds: 1), sourceDuration: .init(seconds: 1))
        let text = Clip(kind: .text, duration: .init(seconds: 1), text: "Follow", layer: 10)
        var localText = text.presentation; localText.x = 0.2; localText.y = 0.8
        var document = ProjectDocument(assets: [asset], scenes: [.init(duration: .init(seconds: 1), clips: [video, text])], variants: [.init(name: "Test", widthRatio: 16, heightRatio: 9, overrides: [text.id.uuidString: localText])])
        let before = RenderPlan.compile(document: document, variantID: nil)
        let result = TrackingResult(points: [.init(sourceSeconds: 0, centerX: 0.6, centerY: 0.7, confidence: 0.9)], lostAtSourceSeconds: nil)
        document.scenes[0].clips[1].keyframes = VisionTrackingService.keyframes(from: result, source: before.clips[0], sourceAsset: asset, target: before.clips[1], variant: before.variant)
        let evaluated = RenderPlan.compile(document: document, variantID: nil).clips[1].evaluatedPresentation(at: .zero)
        XCTAssertEqual(evaluated.x, 0.6, accuracy: 0.00001)
        XCTAssertEqual(evaluated.y, 0.3, accuracy: 0.00001)
    }

    private func orangeCenter(_ image: CGImage) throws -> CGPoint {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var x = 0.0, y = 0.0, count = 0.0
        for row in 0..<image.height {
            for column in 0..<image.width {
                let i = (row * image.width + column) * 4
                if bytes[i] > 180 && bytes[i + 1] > 90 && bytes[i + 1] < 220 && bytes[i + 2] < 90 {
                    x += Double(column); y += Double(row); count += 1
                }
            }
        }
        XCTAssertGreaterThan(count, 400)
        return CGPoint(x: x / max(1, count), y: y / max(1, count))
    }

    func testCorpusContainsOrientedFramesAndSampleTimedImpulses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await SyntheticVideoCorpus.make(in: root, rotated: true)
        let asset = AVURLAsset(url: fixture.movieURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
        let oriented = CGRect(origin: .zero, size: size).applying(transform)
        XCTAssertEqual(abs(oriented.width), 180, accuracy: 0.1)
        XCTAssertEqual(abs(oriented.height), 320, accuracy: 0.1)
        let file = try AVAudioFile(forReading: fixture.audioURL)
        XCTAssertEqual(file.length, 96_000)
        file.framePosition = 24_000
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 100))
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertGreaterThan(abs(samples[3]), 0.5)
        XCTAssertEqual(samples[50], 0)
    }
}
