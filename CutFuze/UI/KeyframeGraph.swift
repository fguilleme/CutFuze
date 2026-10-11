import SwiftUI

/// Uses the renderer's interpolation, including format framing and split offsets.
struct KeyframeGraph: View {
    var clip: RenderClip
    var property: KeyframeProperty
    var globalTime: Double
    var selectedID: UUID?
    var valueRange: ClosedRange<Double>
    var pointIDs: Set<UUID>
    var animationPoints: [Keyframe]? = nil
    var title: String? = nil
    var evaluate: ((MediaTime) -> Double)? = nil
    /// Optional focused interval for short effect bursts on long clips.
    var timeWindow: ClosedRange<MediaTime>? = nil
    var onScrub: (MediaTime) -> Void
    var onSelect: (Keyframe) -> Void
    var onMove: (Keyframe, MediaTime, Double, Bool) -> Void
    @State private var zoom = 1.0

    private var graphStart: MediaTime { max(clip.globalStart, timeWindow?.lowerBound ?? clip.globalStart) }
    private var graphEnd: MediaTime { min(clip.end, timeWindow?.upperBound ?? clip.end) }
    private var graphDuration: Double { max(1 / 60_000, (graphEnd - graphStart).seconds) }

    private var keys: [Keyframe] {
        (animationPoints ?? clip.clip.keyframes).filter { pointIDs.contains($0.id) && $0.property == property && $0.time >= graphStart - clip.globalStart + clip.clip.animationOffset && $0.time <= graphEnd - clip.globalStart + clip.clip.animationOffset }.sorted { $0.time < $1.time }
    }
    private func time(_ fraction: Double) -> MediaTime {
        graphStart + MediaTime(seconds: min(1, max(0, fraction)) * graphDuration)
    }
    private func value(at time: MediaTime) -> Double {
        evaluate?(time) ?? (property == .volume ? clip.evaluatedVolume(at: time) : AnimationEditing.value(property, in: clip.evaluatedPresentation(at: time)))
    }
    private func y(_ value: Double, height: Double) -> Double {
        height * (1 - min(1, max(0, (value - valueRange.lowerBound) / (valueRange.upperBound - valueRange.lowerBound))))
    }
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text("\(title ?? animationPropertyLabel(property)) · \(keys.count)").font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "%.2f / %.2f s", globalTime - clip.globalStart.seconds, clip.duration.seconds))
                    .font(.caption.monospacedDigit()).accessibilityIdentifier("keyframeLocalTime")
                Button { zoom = max(1, zoom / 2) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(L("Réduire le zoom temporel")).disabled(zoom == 1)
                Button { zoom = min(8, zoom * 2) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(L("Augmenter le zoom temporel")).accessibilityIdentifier("zoomKeyframeGraph").disabled(zoom == 8)
            }
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: zoom > 1) {
                let width = max(1, (geometry.size.width - 44) * zoom), height = max(1, geometry.size.height - 44)
                ZStack(alignment: .topLeading) {
                    Path { path in
                        for fraction in [0.0, 0.5, 1.0] {
                            path.move(to: CGPoint(x: 22, y: 22 + height * fraction))
                            path.addLine(to: CGPoint(x: 22 + width, y: 22 + height * fraction))
                        }
                    }.stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    Path { path in
                        for index in 0...100 {
                            let fraction = Double(index) / 100
                            let point = CGPoint(x: 22 + width * fraction, y: 22 + y(value(at: time(fraction)), height: height))
                            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }.stroke(DesignTokens.amber, lineWidth: 2)
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 22 + width * min(1, max(0, (globalTime - graphStart.seconds) / graphDuration)))
                        Rectangle().fill(Color.white.opacity(0.8)).frame(width: 1, height: height + 16).id("graphPlayhead")
                        Spacer(minLength: 0)
                    }.offset(y: 14).allowsHitTesting(false)
                    ForEach(0...4, id: \.self) { index in
                        Text(String(format: "%.2f s", (graphStart - clip.globalStart).seconds + graphDuration * Double(index) / 4))
                            .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                            .position(x: 22 + width * Double(index) / 4, y: height + 37)
                    }
                    ForEach(keys) { key in
                        let keyTime = clip.globalStart + key.time - clip.clip.animationOffset
                        let x = width * (keyTime - graphStart).seconds / graphDuration
                        let pointY = y(value(at: keyTime), height: height)
                        Button { onSelect(key) } label: {
                            Image(systemName: key.id == selectedID ? "diamond.fill" : "diamond")
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(key.id == selectedID ? DesignTokens.amber : .white)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).offset(x: x, y: pointY)
                        .accessibilityLabel("\(title ?? animationPropertyLabel(property)), \(String(format: "%.2f", (keyTime - clip.globalStart).seconds)) s")
                        .accessibilityIdentifier("graphKey-\(key.id)").accessibilityAddTraits(key.id == selectedID ? .isSelected : [])
                        .accessibilityValue(animationEasingLabel(key.easing))
                        .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("keyframeGraph"))
                            .onChanged { gesture in
                                onMove(key, time((gesture.location.x - 22) / width), valueRange.upperBound - min(1, max(0, (gesture.location.y - 22) / height)) * (valueRange.upperBound - valueRange.lowerBound), false)
                            }
                            .onEnded { gesture in
                                onMove(key, time((gesture.location.x - 22) / width), valueRange.upperBound - min(1, max(0, (gesture.location.y - 22) / height)) * (valueRange.upperBound - valueRange.lowerBound), true)
                            })
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { onScrub(time(($0.location.x - 22) / width)) })
                }
                .coordinateSpace(name: "keyframeGraph")
                .frame(width: width + 44, height: geometry.size.height)
                }
                .onChange(of: globalTime) { _, _ in
                    if selectedID == nil { proxy.scrollTo("graphPlayhead", anchor: .center) }
                }
                .onChange(of: selectedID) { _, _ in proxy.scrollTo("graphPlayhead", anchor: .center) }
                .onChange(of: zoom) { _, _ in proxy.scrollTo("graphPlayhead", anchor: .center) }
                }
            }.frame(height: 112)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading) {
                        Text(String(format: "%.2f", valueRange.upperBound))
                        Spacer()
                        Text(String(format: "%.2f", valueRange.lowerBound))
                    }.font(.system(size: 9)).foregroundStyle(.secondary).frame(height: 94).padding(.leading, 2).allowsHitTesting(false)
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("keyframeGraph")
            Text(keys.isEmpty ? L("Touchez la courbe puis ajoutez un point") : L("Touchez un point · glissez pour le déplacer"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
