import Foundation

enum BrushPaintMode: String, Codable, CaseIterable, Sendable { case reveal, stroke }

struct BrushPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    /// Nil in legacy documents; true starts a disconnected stroke.
    var startsStroke: Bool? = nil
}

enum BrushPaths {
    static let sweep: [BrushPoint] = (0..<32).flatMap { row in
        let y = (Double(row) + 0.5) / 32
        return [BrushPoint(x: row.isMultiple(of: 2) ? 0 : 1, y: y),
                BrushPoint(x: row.isMultiple(of: 2) ? 1 : 0, y: y)]
    }
    static let signature: [BrushPoint] = [
        .init(x: 0.08, y: 0.7), .init(x: 0.24, y: 0.22), .init(x: 0.19, y: 0.76),
        .init(x: 0.43, y: 0.35), .init(x: 0.38, y: 0.67), .init(x: 0.62, y: 0.32),
        .init(x: 0.57, y: 0.68), .init(x: 0.9, y: 0.5)
    ]

    /// Constant speed along pixel-space arc length, including a partial final segment.
    static func prefix(_ points: [BrushPoint], progress: Double, width: Double, height: Double) -> [BrushPoint] {
        guard points.count > 1, progress > 0 else { return [] }
        if progress >= 1 { return points }
        let lengths = zip(points, points.dropFirst()).map { a, b in b.startsStroke == true ? 0 : hypot((b.x - a.x) * width, (b.y - a.y) * height) }
        var remaining = lengths.reduce(0, +) * progress
        var result = [points[0]]
        for (index, length) in lengths.enumerated() {
            if remaining <= 0 { break }
            if length <= remaining { result.append(points[index + 1]); remaining -= length }
            else {
                let t = remaining / length
                let a = points[index], b = points[index + 1]
                result.append(.init(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                break
            }
        }
        return result
    }
}
