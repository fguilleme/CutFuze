import AVFoundation
import UIKit
import XCTest
@testable import CutFuze

@MainActor
final class ServiceTests: XCTestCase {
    func testDemoContainsThirtySecondsOfRealLocalAssetsAndThreeLayouts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let demo = try await DemoFactory.make(in: root)
        XCTAssertEqual(demo.duration.seconds, 30, accuracy: 0.00001)
        XCTAssertEqual(demo.scenes.count, 3)
        XCTAssertEqual(demo.variants.count, 3)
        XCTAssertEqual(demo.allClips.filter(\.isCaption).count, 3)
        XCTAssertEqual(demo.globalClips.count, 1)
        for asset in demo.assets {
            let url = root.appendingPathComponent(asset.relativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertEqual(asset.sha256.count, 64)
            if asset.kind == .image {
                let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
                XCTAssertEqual(image.size, CGSize(width: 1280, height: 960))
            }
        }
        let sound = try XCTUnwrap(demo.assets.first { $0.kind == .audio })
        let file = try AVAudioFile(forReading: root.appendingPathComponent(sound.relativePath))
        XCTAssertEqual(file.processingFormat.sampleRate, 48_000)
        XCTAssertEqual(file.length, 1_440_000)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let values = Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
        XCTAssertGreaterThan(values.map { abs($0) }.max() ?? 0, 0.005)
        XCTAssertLessThan(values.map { abs($0) }.max() ?? 1, 1)
        let imageID = try XCTUnwrap(demo.scenes.first?.clips.first?.id.uuidString)
        let layouts = demo.variants.compactMap { $0.overrides[imageID] }
        XCTAssertEqual(layouts.count, 3)
        XCTAssertNotEqual(layouts[0], layouts[1])
        XCTAssertNotEqual(layouts[1], layouts[2])
    }

    func testTwelveTemplatesCreateDifferentEditableStories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(TemplateCatalog.all.count, 12)
        var signatures = Set<String>()
        for definition in TemplateCatalog.all {
            let project = try await TemplateCatalog.make(template: definition, in: root.appendingPathComponent(definition.id))
            XCTAssertEqual(project.scenes.count, definition.sceneTitles.count)
            XCTAssertEqual(project.duration.seconds, definition.duration, accuracy: 0.001)
            XCTAssertTrue(project.allClips.contains { $0.kind == .text })
            XCTAssertTrue(project.allClips.contains { !$0.keyframes.isEmpty })
            XCTAssertFalse(project.assets.isEmpty)
            let signature = project.scenes.map { "\($0.title):\($0.duration.value):\($0.transition.kind)" }.joined(separator: "|")
            XCTAssertTrue(signatures.insert(signature).inserted)
            var edited = project
            edited.scenes[0].clips[0].presentation.rotation = 23
            XCTAssertNotEqual(edited, project)
        }
    }
}
