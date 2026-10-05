import XCTest
@testable import CutFuze

final class BeatMarkerTests: XCTestCase {
    private func document() -> ProjectDocument {
        ProjectDocument(scenes: [.init(title: "A", duration: .init(seconds: 3), clips: [.init(kind: .shape, duration: .init(seconds: 3))]), .init(title: "B", duration: .init(seconds: 2), clips: [.init(kind: .shape, duration: .init(seconds: 2))])])
    }
    func testRoundTripAndOlderSchemaWithoutMarkerField() throws {
        var original = document()
        let id = try original.addBeatMarker(at: .init(value: 22_501), label: "Temps fort")
        let data = try JSONEncoder().encode(original)
        let reopened = try JSONDecoder().decode(ProjectDocument.self, from: data)
        XCTAssertEqual(reopened.rhythmMarkers.first?.id, id)
        XCTAssertEqual(reopened.rhythmMarkers.first?.time, MediaTime(value: 22_501))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "beatMarkers")
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(decoded.rhythmMarkers.isEmpty)
        try decoded.validate()
    }
    func testUndoRedoAndSceneReorderKeepAbsoluteTime() throws {
        let history = EditHistory(document: document())
        try history.perform(name: "Marker") { _ = try $0.addBeatMarker(at: .init(seconds: 1.25), label: "Beat") }
        let marker = try XCTUnwrap(history.document.rhythmMarkers.first)
        try history.perform(name: "Scene order") { $0.scenes.reverse() }
        XCTAssertEqual(history.document.rhythmMarkers.first, marker)
        history.undo()
        XCTAssertEqual(history.document.rhythmMarkers.first, marker)
        history.undo()
        XCTAssertTrue(history.document.rhythmMarkers.isEmpty)
        history.redo()
        XCTAssertEqual(history.document.rhythmMarkers.first, marker)
    }
    func testSnappingThresholdAndDuplicateTime() throws {
        var project = document()
        let id = try project.addBeatMarker(at: .init(seconds: 1.25))
        XCTAssertEqual(try project.addBeatMarker(at: .init(seconds: 1.25), label: "Accent"), id)
        XCTAssertEqual(project.rhythmMarkers.count, 1)
        XCTAssertEqual(project.nearestBeat(to: .init(seconds: 1.3), tolerance: .init(seconds: 0.08))?.id, id)
        XCTAssertNil(project.nearestBeat(to: .init(seconds: 1.4), tolerance: .init(seconds: 0.08)))
        try project.updateBeatMarker(id, time: .init(seconds: 2), label: "Next")
        XCTAssertEqual(project.rhythmMarkers[0].time.seconds, 2)
        project.removeBeatMarker(id)
        XCTAssertTrue(project.rhythmMarkers.isEmpty)
        XCTAssertThrowsError(try project.addBeatMarker(at: .init(seconds: -1)))
    }
}
