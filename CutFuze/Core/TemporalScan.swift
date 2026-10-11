import Foundation

enum ScanDirection: String, Codable, CaseIterable, Sendable {
    case down, up, right, left
    var isHorizontal: Bool { self == .right || self == .left }
    var reversed: Bool { self == .up || self == .left }
}

extension EffectInstance {
    var temporalScanDuration: Double { min(10, max(0.2, scanDuration ?? 2)) }
    var temporalScanDirection: ScanDirection { scanDirection ?? .down }
    var temporalScanStart: MediaTime { scanStart ?? .zero }
    var temporalScanShowsLine: Bool { scanLineVisible ?? true }

    func scanProgress(at animationTime: MediaTime) -> Double {
        min(1, max(0, (animationTime - temporalScanStart).seconds / temporalScanDuration))
    }

    /// Positions are measured from the leading edge of the scan, not the canvas origin.
    func scanCaptureTime(at position: Double) -> MediaTime {
        temporalScanStart + .init(seconds: min(1, max(0, position)) * temporalScanDuration)
    }
}
