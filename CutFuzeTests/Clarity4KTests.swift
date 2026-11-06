import XCTest
import CoreImage
import ImageIO
import AVFoundation
import UIKit
@testable import CutFuze

@MainActor final class Clarity4KTests: XCTestCase {
    func testParametersPersistAcrossSplitUndoAndOlderProjects() throws {
        var effect = EffectInstance.readyToUse(.clarity4K, duration: .init(seconds: 2))
        XCTAssertEqual(effect.kind.intensityRange, 0...1)
        XCTAssertEqual(effect.kind.suggestedUsage, .photoVideo)
        XCTAssertTrue(EffectCategory.light.effects.contains(.clarity4K))
        effect.clarityDetail = 0.9; effect.clarityContrast = 0.6; effect.clarityColor = 0.1
        effect.amountKeyframes = [.init(time: .zero, value: 0), .init(time: .init(seconds: 2), value: 1, easing: .easeIn)]
        let clip = Clip(kind: .shape, duration: .init(seconds: 2), effects: [effect])
        let history = EditHistory(document: ProjectDocument(globalClips: [clip]))
        try history.perform(name: "Split") { try DocumentEditor.splitClip(clip.id, at: .init(seconds: 1), in: &$0) }
        XCTAssertEqual(history.document.globalClips[1].effects, [effect])
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(history.document)), history.document)
        history.undo(); XCTAssertEqual(history.document.globalClips, [clip])
        history.redo(); XCTAssertEqual(history.document.globalClips.count, 2)
        for invalid in [-0.1, 1.1, Double.nan, .infinity] {
            var candidate = effect; candidate.clarityDetail = invalid
            XCTAssertThrowsError(try candidate.validateAnimation())
            candidate = effect; candidate.clarityContrast = invalid
            XCTAssertThrowsError(try candidate.validateAnimation())
            candidate = effect; candidate.clarityColor = invalid
            XCTAssertThrowsError(try candidate.validateAnimation())
        }
        let older = try JSONDecoder().decode(EffectInstance.self, from: Data("{\"id\":\"\(UUID())\",\"kind\":\"sharpness\",\"amount\":0.5,\"enabled\":true}".utf8))
        XCTAssertNil(older.clarityDetail); XCTAssertNil(older.clarityContrast); XCTAssertNil(older.clarityColor)
    }

    func testLookStrengthDetailAndTransparentCorners() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let asset = try await makeAsset(root)
        var clip = Clip(assetID: asset.id, kind: .image, duration: .init(seconds: 1), sourceDuration: .init(seconds: 1))
        let renderer = FrameRenderer(softwareRendering: true)
        func frame(_ clip: Clip) async throws -> CGImage {
            try await renderer.render(plan: .compile(document: ProjectDocument(assets: [asset], globalClips: [clip]), variantID: nil), time: .zero, rootURL: root, size: CGSize(width: 320, height: 180))
        }
        let plain = try await frame(clip)
        var effect = EffectInstance.readyToUse(.clarity4K, duration: clip.duration)
        effect.amount = 0; clip.effects = [effect]
        let zero = try await frame(clip)
        XCTAssertEqual(zero.dataProvider?.data as Data?, plain.dataProvider?.data as Data?)
        effect.amount = 1; effect.enabled = false; clip.effects = [effect]
        let disabled = try await frame(clip)
        XCTAssertEqual(disabled.dataProvider?.data as Data?, plain.dataProvider?.data as Data?)
        effect.enabled = true; effect.clarityDetail = 0; effect.clarityContrast = 0; effect.clarityColor = 0; clip.effects = [effect]
        let neutral = try await frame(clip)
        XCTAssertEqual(neutral.dataProvider?.data as Data?, plain.dataProvider?.data as Data?)

        effect.clarityDetail = 1; clip.effects = [effect]
        let detail = try await frame(clip)
        XCTAssertGreaterThan(textureEnergy(detail), textureEnergy(plain) * 1.01, "Fine texture must become more defined, not merely brighter")
        effect = .readyToUse(.clarity4K, duration: clip.duration); effect.amount = 1; clip.effects = [effect]
        let full = try await frame(clip)
        effect.amount = 0.5; clip.effects = [effect]
        let half = try await frame(clip)
        let fullDifference = difference(plain, full), halfDifference = difference(plain, half)
        XCTAssertGreaterThan(fullDifference, 0.5)
        XCTAssertGreaterThan(halfDifference, 0.1); XCTAssertLessThan(halfDifference, fullDifference)
        for point in [(5, 5), (315, 5), (5, 175), (315, 175)] {
            XCTAssertEqual(pixel(full, point.0, point.1), pixel(plain, point.0, point.1), "Do not add a halo to transparent corners")
        }
        for (name, image) in [("clarity-before", plain), ("clarity-half", half), ("clarity-after", full)] {
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testTransparentSourceMatchesAnOpaqueLayerAtHalfOpacity() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let opaque = try await makeAsset(root), transparent = try await makeAsset(root, translucent: true)
        let effect = EffectInstance.readyToUse(.clarity4K, duration: .init(seconds: 1))
        var clip = Clip(assetID: opaque.id, kind: .image, duration: .init(seconds: 1), sourceDuration: .init(seconds: 1), effects: [effect])
        clip.presentation.opacity = 128.0 / 255
        let renderer = FrameRenderer(softwareRendering: true), size = CGSize(width: 320, height: 180)
        let expected = try await renderer.render(plan: .compile(document: ProjectDocument(assets: [opaque], globalClips: [clip]), variantID: nil), time: .zero, rootURL: root, size: size)
        clip.assetID = transparent.id; clip.presentation.opacity = 1
        let actual = try await renderer.render(plan: .compile(document: ProjectDocument(assets: [transparent], globalClips: [clip]), variantID: nil), time: .zero, rootURL: root, size: size)
        XCTAssertLessThan(difference(expected, actual), 3, "The effect must preserve translucent image alpha rather than multiplying it twice")
    }

    func testAnimatedLookMatchesAfterSplitAndExport() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let asset = try await makeAsset(root)
        var effect = EffectInstance.readyToUse(.clarity4K, duration: .init(seconds: 0.5))
        effect.amountKeyframes = [.init(time: .zero, value: 0), .init(time: .init(seconds: 0.5), value: 1, easing: .easeOut)]
        let clip = Clip(assetID: asset.id, kind: .image, duration: .init(seconds: 0.5), sourceDuration: .init(seconds: 0.5), effects: [effect])
        var document = ProjectDocument(assets: [asset], globalClips: [clip])
        let originalPlan = RenderPlan.compile(document: document, variantID: document.variants[0].id)
        try DocumentEditor.splitClip(clip.id, at: .init(seconds: 0.25), in: &document)
        let settings = MovieExportSettings(longEdge: 320, frameRate: 24, bitrate: 4_000_000)
        let size = settings.dimensions(for: document.variants[0])
        let time = MediaTime(seconds: 0.375), renderer = FrameRenderer(softwareRendering: true)
        let expected = try await renderer.render(plan: originalPlan, time: time, rootURL: root, size: size)
        let split = try await renderer.render(plan: .compile(document: document, variantID: document.variants[0].id), time: time, rootURL: root, size: size)
        XCTAssertEqual(expected.dataProvider?.data as Data?, split.dataProvider?.data as Data?)
        let output = root.appendingPathComponent("clarity4k.mp4")
        let receipt = try await MovieExporter().export(document: document, variantID: document.variants[0].id, rootURL: root, settings: settings, outputURL: output, progress: { _ in })
        XCTAssertEqual(receipt.width, Int(size.width)); XCTAssertEqual(receipt.height, Int(size.height))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output)); generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let decoded = try await generator.image(at: CMTime(value: 9, timescale: 24)).image
        XCTAssertLessThan(difference(expected, decoded), 14, "The animated export must match the preview within compression tolerance")
        let attachment = XCTAttachment(contentsOfFile: output); attachment.name = "clarity4k-export"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Clarity4K-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func makeAsset(_ root: URL, translucent: Bool = false) async throws -> MediaAsset {
        var bytes = [UInt8](repeating: 255, count: 320 * 180 * 4)
        for y in 0..<180 { for x in 0..<320 {
            let index = (y * 320 + x) * 4
            let value = 0.46 + 0.09 * sin(Double(x) * 0.65) + 0.035 * cos(Double(y) * 0.4)
            bytes[index] = UInt8((value * 255).rounded())
            bytes[index + 1] = UInt8(((value + 0.015) * 255).rounded())
            bytes[index + 2] = UInt8(((value - 0.025) * 255).rounded())
            if y > 130 { bytes[index] = 165; bytes[index + 1] = 100; bytes[index + 2] = 65 }
            if translucent {
                for channel in 0..<3 { bytes[index + channel] = UInt8((Double(bytes[index + channel]) * 128 / 255).rounded()) }
                bytes[index + 3] = 128
            }
            if (x < 20 || x >= 300) && (y < 20 || y >= 160) {
                bytes[index] = 0; bytes[index + 1] = 0; bytes[index + 2] = 0; bytes[index + 3] = 0
            }
        } }
        let image = CIImage(bitmapData: Data(bytes), bytesPerRow: 320 * 4, size: CGSize(width: 320, height: 180), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let raster = try XCTUnwrap(context.createCGImage(image, from: image.extent))
        let url = root.appendingPathComponent(translucent ? "detail-translucent.png" : "detail-chart.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, raster, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try await MediaImporter().importFile(url: url, to: root)
    }
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress!, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: -CGFloat(x), y: -CGFloat(y)); context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    private func textureEnergy(_ image: CGImage) -> Double {
        (40..<280).reduce(0.0) { $0 + abs(Double(pixel(image, $1, 90)[0]) - Double(pixel(image, $1 - 1, 90)[0])) }
    }
    private func difference(_ first: CGImage, _ second: CGImage) -> Double {
        var total = 0.0, count = 0
        for y in stride(from: 8, to: first.height - 8, by: 9) { for x in stride(from: 8, to: first.width - 8, by: 9) {
            let a = pixel(first, x, y), b = pixel(second, x, y)
            for channel in 0..<3 { total += abs(Double(a[channel]) - Double(b[channel])); count += 1 }
        } }
        return total / Double(max(1, count))
    }
}
