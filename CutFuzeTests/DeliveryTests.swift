import XCTest
import AVFoundation
@testable import CutFuze

final class DeliveryTests: XCTestCase {
    @MainActor func testThirtySecondDemoPortableReexportAndDeliveryArtifacts() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Delivery-" + UUID().uuidString)
        let original = parent.appendingPathComponent("Original"), isolated = parent.appendingPathComponent("Isolated")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let demo = try await DemoFactory.make(in: original)
        let package = parent.appendingPathComponent("Trente-secondes-de-lumiere.cutlabproject")
        try PortableProject.export(document: demo, rootURL: original, to: package)
        let projectAttachment = XCTAttachment(contentsOfFile: package); projectAttachment.name = "Demo-project.cutlabproject"; projectAttachment.lifetime = .keepAlways; add(projectAttachment)
        try FileManager.default.removeItem(at: original)
        let store = ProjectStore(rootURL: isolated)
        var imported = try PortableProject.importPackage(from: package, into: store)
        imported.title = "Trente secondes de lumière · transport vérifié"
        try store.save(document: imported)
        let reopened = try store.load(id: imported.id)
        XCTAssertEqual(reopened.scenes.count, 3)
        XCTAssertEqual(reopened.variants.map(\.overrides), demo.variants.map(\.overrides))
        XCTAssertEqual(reopened.duration.seconds, 30, accuracy: 0.001)
        let exporter = MovieExporter()
        let start = ContinuousClock.now
        for variant in reopened.variants {
            let output = parent.appendingPathComponent("Demo-\(Int(variant.widthRatio))x\(Int(variant.heightRatio)).mp4")
            let receipt: ExportReceipt
            do {
                receipt = try await exporter.export(document: reopened, variantID: variant.id, rootURL: isolated, settings: .init(longEdge: 1280, frameRate: 30, codec: .h264, bitrate: 4_000_000), outputURL: output) { progress in
                    if progress < 0.005 || progress > 0.93 { print("Delivery \(variant.name) progress \(progress)") }
                }
            } catch {
                XCTFail("Delivery export \(variant.name): \(error.localizedDescription)")
                return
            }
            XCTAssertEqual(receipt.duration, 30, accuracy: 1 / 30)
            XCTAssertTrue(receipt.hasAudio)
            let asset = AVURLAsset(url: output), generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
            for time in [1.5, 14.0, 28.0] { _ = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60000)) }
            let tracks = try await asset.loadTracks(withMediaType: .video); XCTAssertEqual(tracks.count, 1)
            let attachment = XCTAttachment(contentsOfFile: output); attachment.name = output.lastPathComponent; attachment.lifetime = .keepAlways; add(attachment)
        }
        let measure = XCTAttachment(string: "Simulator: three 30-second 1280px H.264 variants exported sequentially from transported demo after deleting source. Elapsed \(start.duration(to: .now)). No physical-device claim.")
        measure.name = "Demo-export-measurement"; measure.lifetime = .keepAlways; add(measure)
    }
}
