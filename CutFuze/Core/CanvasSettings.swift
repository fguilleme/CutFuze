import Foundation

enum CanvasBackground: String, Codable, CaseIterable, Sendable { case solid, image, blurredMedia }
struct CanvasSettings: Codable, Hashable, Sendable {
    var mode: CanvasBackground = .solid
    var color: String = "#000000"
    var imageAssetID: UUID? = nil
    var blur: Double = 0.04
}
