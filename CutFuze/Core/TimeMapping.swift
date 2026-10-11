import Foundation

/// Integrates 1/v(s) analytically for each linear source-domain speed segment.
enum TimeMapping {
    /// Temporal effects may need a pre-cut frame. Reuse the same speed integral
    /// over a widened media interval; never change the document's source bounds.
    static func historicalSourceTime(for localTime: MediaTime, clip: Clip, assetDuration: MediaTime) -> MediaTime {
        guard localTime < .zero else { return sourceTime(for: localTime, clip: clip) }
        var extended = clip
        let currentBoundary = clip.reversed ? clip.sourceStart + clip.sourceDuration : clip.sourceStart
        if clip.reversed { extended.sourceDuration = max(.zero, assetDuration - clip.sourceStart) }
        else { extended.sourceStart = .zero; extended.sourceDuration = clip.sourceStart + clip.sourceDuration }
        let offset = self.localTime(forSource: currentBoundary, clip: extended)
        return sourceTime(for: max(.zero, offset + localTime), clip: extended)
    }

    static func sourceTime(for localTime: MediaTime, clip: Clip) -> MediaTime {
        let low = clip.sourceStart.seconds
        let high = low + clip.sourceDuration.seconds
        let target = min(max(0, localTime.seconds), outputDuration(clip: clip).seconds)
        var a = low, b = high
        for _ in 0..<48 {
            let mid = (a + b) * 0.5
            let elapsed = clip.reversed ? integral(from: mid, to: high, clip: clip) : integral(from: low, to: mid, clip: clip)
            if clip.reversed { if elapsed > target { a = mid } else { b = mid } }
            else { if elapsed < target { a = mid } else { b = mid } }
        }
        return .init(seconds: (a + b) * 0.5)
    }
    static func localTime(forSource sourceTime: MediaTime, clip: Clip) -> MediaTime {
        let low = clip.sourceStart.seconds, high = low + clip.sourceDuration.seconds
        let source = min(high, max(low, sourceTime.seconds))
        return .init(seconds: clip.reversed ? integral(from: source, to: high, clip: clip) : integral(from: low, to: source, clip: clip))
    }
    static func outputDuration(clip: Clip) -> MediaTime {
        .init(seconds: integral(from: clip.sourceStart.seconds, to: clip.sourceStart.seconds + clip.sourceDuration.seconds, clip: clip))
    }
    static func speed(atSource time: Double, clip: Clip) -> Double {
        let points = clip.speedPoints.sorted { $0.sourceTime < $1.sourceTime }
        guard let first = points.first, let last = points.last else { return max(0.1, min(100, clip.speed)) }
        if time <= first.sourceTime.seconds { return max(0.1, min(100, first.speed)) }
        if time >= last.sourceTime.seconds { return max(0.1, min(100, last.speed)) }
        for index in 1..<points.count where time <= points[index].sourceTime.seconds {
            let p = points[index - 1], q = points[index]
            let width = q.sourceTime.seconds - p.sourceTime.seconds
            let fraction = width > 0 ? (time - p.sourceTime.seconds) / width : 0
            return max(0.1, min(100, p.speed + (q.speed - p.speed) * fraction))
        }
        return max(0.1, min(100, clip.speed))
    }
    private static func integral(from: Double, to: Double, clip: Clip) -> Double {
        guard to > from else { return 0 }
        let cuts = [from] + clip.speedPoints.map { $0.sourceTime.seconds }.filter { $0 > from && $0 < to }.sorted() + [to]
        var result = 0.0
        for index in 1..<cuts.count {
            let a = cuts[index - 1], b = cuts[index], va = speed(atSource: a, clip: clip), vb = speed(atSource: b, clip: clip)
            let slope = (vb - va) / (b - a)
            result += abs(slope) < 1e-10 ? (b - a) / va : log(vb / va) / slope
        }
        return result
    }
}

enum KeyframeEvaluator {
    static func value(property: KeyframeProperty, at time: MediaTime, keyframes: [Keyframe], fallback: Double) -> Double {
        let keys = keyframes.filter { $0.property == property }.sorted { $0.time < $1.time }
        guard let first = keys.first, let last = keys.last else { return fallback }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        for index in 1..<keys.count where time < keys[index].time {
            let a = keys[index - 1], b = keys[index]
            var fraction = (time - a.time).seconds / (b.time - a.time).seconds
            switch b.easing {
            case .linear: break
            case .easeIn: fraction *= fraction
            case .easeOut: fraction = 1 - pow(1 - fraction, 2)
            case .easeInOut: fraction = fraction * fraction * (3 - 2 * fraction)
            }
            return a.value + (b.value - a.value) * fraction
        }
        return last.value
    }
    static func evaluate(presentation: Presentation, keyframes: [Keyframe], at time: MediaTime) -> Presentation {
        var result = presentation
        result.x = value(property: .x, at: time, keyframes: keyframes, fallback: result.x)
        result.y = value(property: .y, at: time, keyframes: keyframes, fallback: result.y)
        result.scale = value(property: .scale, at: time, keyframes: keyframes, fallback: result.scale)
        result.rotation = value(property: .rotation, at: time, keyframes: keyframes, fallback: result.rotation)
        result.opacity = value(property: .opacity, at: time, keyframes: keyframes, fallback: result.opacity)
        result.maskWidth = value(property: .maskWidth, at: time, keyframes: keyframes, fallback: result.maskWidth)
        result.maskHeight = value(property: .maskHeight, at: time, keyframes: keyframes, fallback: result.maskHeight)
        result.maskX = value(property: .maskX, at: time, keyframes: keyframes, fallback: result.maskX)
        result.maskY = value(property: .maskY, at: time, keyframes: keyframes, fallback: result.maskY)
        result.maskRotation = value(property: .maskRotation, at: time, keyframes: keyframes, fallback: result.maskRotation)
        result.maskFeather = value(property: .maskFeather, at: time, keyframes: keyframes, fallback: result.maskFeather)
        return result
    }
}

extension RenderClip {
    func evaluatedVolume(at globalTime: MediaTime) -> Double {
        max(0, min(8, KeyframeEvaluator.value(property: .volume, at: globalTime - globalStart + clip.animationOffset, keyframes: clip.keyframes, fallback: clip.volume)))
    }

    func evaluatedPresentation(at globalTime: MediaTime) -> Presentation {
        let base = clip.presentation
        let animated = KeyframeEvaluator.evaluate(presentation: base, keyframes: clip.keyframes, at: globalTime - globalStart + clip.animationOffset)
        var resolved = presentation
        // Shared keyframes are evaluated against the common presentation. A variant adds
        // its own framing to that motion instead of being overwritten by absolute keys.
        let properties = Set(clip.keyframes.map(\.property))
        if properties.contains(.x) { resolved.x += animated.x - base.x }
        if properties.contains(.y) { resolved.y += animated.y - base.y }
        if properties.contains(.scale) { resolved.scale *= animated.scale / max(0.000001, base.scale) }
        if properties.contains(.rotation) { resolved.rotation += animated.rotation - base.rotation }
        if properties.contains(.opacity) { resolved.opacity *= base.opacity > 0.000001 ? animated.opacity / base.opacity : animated.opacity }
        if properties.contains(.maskWidth) { resolved.maskWidth *= animated.maskWidth / max(0.000001, base.maskWidth) }
        if properties.contains(.maskHeight) { resolved.maskHeight *= animated.maskHeight / max(0.000001, base.maskHeight) }
        if properties.contains(.maskX) { resolved.maskX += animated.maskX - base.maskX }
        if properties.contains(.maskY) { resolved.maskY += animated.maskY - base.maskY }
        if properties.contains(.maskRotation) { resolved.maskRotation += animated.maskRotation - base.maskRotation }
        if properties.contains(.maskFeather) { resolved.maskFeather = min(0.2, max(0, resolved.maskFeather + animated.maskFeather - base.maskFeather)) }
        return resolved
    }
}
