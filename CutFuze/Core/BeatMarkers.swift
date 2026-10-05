import Foundation

/// An absolute project-time guide. Scene reorder and clip retiming do not move manual beats.
struct BeatMarker: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var time: MediaTime
    var label: String = ""
}

extension ProjectDocument {
    /// Optional persistence keeps older schema-2 documents readable without a fabricated migration.
    var rhythmMarkers: [BeatMarker] { (beatMarkers ?? []).sorted { $0.time < $1.time } }

    @discardableResult
    mutating func addBeatMarker(at time: MediaTime, label: String = "") throws -> UUID {
        try Self.validateMarkerTime(time)
        var markers = beatMarkers ?? []
        if let existing = markers.firstIndex(where: { $0.time == time }) {
            if !label.isEmpty { markers[existing].label = String(label.prefix(256)) }
            beatMarkers = markers
            return markers[existing].id
        }
        guard markers.count < 10_000 else { throw DocumentError.invalid("Trop de repères rythmiques") }
        let marker = BeatMarker(time: time, label: String(label.prefix(256)))
        markers.append(marker)
        beatMarkers = markers
        return marker.id
    }

    mutating func updateBeatMarker(_ id: UUID, time: MediaTime, label: String) throws {
        try Self.validateMarkerTime(time)
        guard var markers = beatMarkers, let index = markers.firstIndex(where: { $0.id == id }) else { throw DocumentError.missing("Repère rythmique") }
        guard !markers.contains(where: { $0.id != id && $0.time == time }) else { throw DocumentError.invalid("Un repère existe déjà à cet instant") }
        markers[index].time = time
        markers[index].label = String(label.prefix(256))
        beatMarkers = markers
    }

    mutating func removeBeatMarker(_ id: UUID) { beatMarkers?.removeAll { $0.id == id } }

    /// Caller converts its touch-point threshold into composition time at the current zoom.
    func nearestBeat(to time: MediaTime, tolerance: MediaTime) -> BeatMarker? {
        guard tolerance >= .zero else { return nil }
        return rhythmMarkers.filter { abs(($0.time - time).seconds) <= tolerance.seconds }
            .min { abs(($0.time - time).seconds) < abs(($1.time - time).seconds) }
    }

    func validateBeatMarkers() throws {
        let markers = beatMarkers ?? []
        guard markers.count <= 10_000, Set(markers.map(\.id)).count == markers.count else { throw DocumentError.invalid("Identifiants de repères rythmiques") }
        for marker in markers {
            try Self.validateMarkerTime(marker.time)
            guard marker.label.count <= 256 else { throw DocumentError.invalid("Nom du repère trop long") }
        }
    }

    private static func validateMarkerTime(_ time: MediaTime) throws {
        guard time.timescale > 0, time.timescale <= 1_000_000, time.value >= 0, time.seconds <= 604_800 else { throw DocumentError.invalid("Temps du repère rythmique") }
    }
}
