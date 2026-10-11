import SwiftUI

/// A normalized source-plane drawing pad. The montage preview above shows the actual result.
struct BrushPathEditor: View {
    let points: [BrushPoint]
    let progress: Double
    let width: Double
    let sourceAspect: Double
    var maximumHeight: CGFloat = 360
    let commit: ([BrushPoint]) -> Void
    @State private var drawing: [BrushPoint] = []
    @State private var availableWidth: CGFloat = 320

    private var padHeight: CGFloat {
        min(maximumHeight, max(1, availableWidth) / max(0.01, sourceAspect))
    }

    var body: some View {
        GeometryReader { proxy in
            let padWidth = min(max(1, proxy.size.width), maximumHeight * max(0.01, sourceAspect))
            let padHeight = padWidth / max(0.01, sourceAspect)
            HStack(spacing: 0) {
            Spacer(minLength: 0)
            Canvas { context, size in
                for fraction in [0.25, 0.5, 0.75] {
                    var grid = Path()
                    grid.move(to: CGPoint(x: size.width * fraction, y: 0)); grid.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                    grid.move(to: CGPoint(x: 0, y: size.height * fraction)); grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
                let path = points + drawing
                func outline(_ points: [BrushPoint]) -> Path {
                    var result = Path()
                    for (index, point) in points.enumerated() {
                        let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
                        if index == 0 || point.startsStroke == true { result.move(to: position) } else { result.addLine(to: position) }
                    }
                    return result
                }
                context.stroke(outline(path), with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: max(2, width * min(size.width, size.height)), lineCap: .round, lineJoin: .round))
                let visible = drawing.isEmpty ? BrushPaths.prefix(path, progress: progress, width: sourceAspect, height: 1) : path
                context.stroke(outline(visible), with: .color(DesignTokens.amber), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if let first = path.first {
                    context.fill(Path(ellipseIn: CGRect(x: first.x * size.width - 4, y: first.y * size.height - 4, width: 8, height: 8)), with: .color(.white))
                }
            }.frame(width: padWidth, height: padHeight)
                .background(DesignTokens.ink).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25), lineWidth: 1))
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { value in
                    func point(_ location: CGPoint) -> BrushPoint { .init(x: min(1, max(0, location.x / padWidth)), y: min(1, max(0, location.y / padHeight))) }
                    if drawing.isEmpty {
                        var start = point(value.startLocation); start.startsStroke = true
                        drawing = [start]
                    }
                    let next = point(value.location)
                    if drawing.last != next {
                        if drawing.count >= 256 { drawing = drawing.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element) }
                        drawing.append(next)
                    }
                }.onEnded { _ in
                    if drawing.count >= 2, points.count + drawing.count <= 4096 {
                        commit(points + drawing); UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    drawing = []
                }).accessibilityElement(children: .ignore)
                .accessibilityIdentifier("brushPathPad")
                .accessibilityLabel(AppLocalization.bilingual("Dessiner le tracé du calque", "Draw the layer path"))
                .accessibilityValue(String(pathStrokeCount))
            Spacer(minLength: 0)
            }.frame(height: padHeight)
        }.frame(height: padHeight)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private var pathStrokeCount: Int {
        points.isEmpty ? 0 : 1 + points.dropFirst().filter { $0.startsStroke == true }.count
    }
}
