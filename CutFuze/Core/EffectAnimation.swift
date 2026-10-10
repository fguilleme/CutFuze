import Foundation

extension EffectKind {
    var intensityRange: ClosedRange<Double> {
        switch self {
        case .exposure: -2...2
        case .impactZoom, .shortGlitch, .neon: 0...1
        default: -1...1
        }
    }
}

struct EffectAmountKeyframe: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var time: MediaTime
    var value: Double
    var easing: KeyframeEasing = .linear
}

extension EffectInstance {
    var neonGlowRadius: Double { min(1, max(0, glowRadius ?? 0.45)) }
    /// Presets live in the same time domain as manually edited effect points.
    /// Splitting a clip preserves this envelope and the renderer's deterministic seed.
    static func readyToUse(_ kind: EffectKind, duration: MediaTime, offset: MediaTime = .zero, localTime: Double = 0, defaultAmount: Double = 0.45) -> EffectInstance {
        var effect = EffectInstance(kind: kind, amount: kind == .neon ? 0.65 : defaultAmount)
        if kind == .neon { effect.colorHex = "#49E6FF"; effect.glowRadius = 0.45 }
        guard kind == .impactZoom || kind == .shortGlitch, duration.value > 0 else { return effect }
        let length = min(duration.seconds, kind == .impactZoom ? 0.48 : 0.30)
        // Shift a burst backwards when the playhead is too close to the clip end.
        let start = offset + MediaTime(seconds: min(max(0, localTime), max(0, duration.seconds - length)))
        effect.start = start; effect.duration = .init(seconds: length)
        let envelope: [(Double, Double, KeyframeEasing)] = kind == .impactZoom
            ? [(0, 0.85, .linear), (0.16, 1, .easeOut), (0.42, 0.3, .easeOut), (1, 0, .easeOut)]
            : [(0, 0.75, .linear), (0.14, 1, .linear), (0.36, 0.25, .linear), (0.55, 0.8, .linear), (1, 0, .easeOut)]
        var seen = Set<MediaTime>()
        effect.amountKeyframes = envelope.compactMap { fraction, value, easing in
            let time = start + MediaTime(seconds: length * fraction)
            guard seen.insert(time).inserted else { return nil }
            return .init(time: time, value: value, easing: easing)
        }
        return effect
    }
    func animatedAmount(at animationTime: MediaTime) -> Double {
        let keys = (amountKeyframes ?? []).map { Keyframe(id: $0.id, time: $0.time, property: .opacity, value: $0.value, easing: $0.easing) }
        return KeyframeEvaluator.value(property: .opacity, at: animationTime, keyframes: keys, fallback: amount)
    }
    func evaluatedAmount(at animationTime: MediaTime) -> Double? {
        guard enabled, animationTime >= (start ?? .zero) else { return nil }
        if let duration, animationTime >= (start ?? .zero) + duration { return nil }
        return animatedAmount(at: animationTime)
    }
    func validateAnimation() throws {
        func valid(_ time: MediaTime) -> Bool { time.timescale > 0 && time.timescale <= 1_000_000 && time.value >= 0 && time.seconds <= 604_800 }
        let keys = amountKeyframes ?? []
        guard start.map(valid) ?? true, duration.map(valid) ?? true, glowRadius.map({ $0.isFinite && (0...1).contains($0) }) ?? true, keys.count <= 10_000,
              keys.allSatisfy({ valid($0.time) && $0.value.isFinite }), Set(keys.map(\.time)).count == keys.count,
              Set(keys.map(\.id)).count == keys.count else { throw DocumentError.invalid("Animation d’effet") }
    }
}

enum EffectAnimationEditing {
    @discardableResult
    static func upsert(at time: MediaTime, value: Double, easing: KeyframeEasing, domain: ClosedRange<MediaTime>, in effect: inout EffectInstance) throws -> UUID {
        guard domain.contains(time), value.isFinite else { throw DocumentError.invalid("Point en dehors du clip") }
        var candidate = effect
        var keys = candidate.amountKeyframes ?? []
        let id: UUID
        if let index = keys.firstIndex(where: { $0.time == time }) {
            keys[index].value = value; keys[index].easing = easing; id = keys[index].id
        } else {
            let key = EffectAmountKeyframe(time: time, value: value, easing: easing)
            keys.append(key); id = key.id
        }
        candidate.amountKeyframes = keys
        try candidate.validateAnimation(); effect = candidate
        return id
    }
    static func move(_ id: UUID, to time: MediaTime, value: Double, domain: ClosedRange<MediaTime>, in effect: inout EffectInstance) throws {
        guard domain.contains(time), value.isFinite else { throw DocumentError.invalid("Point en dehors du clip") }
        var candidate = effect
        guard var keys = candidate.amountKeyframes, let index = keys.firstIndex(where: { $0.id == id }) else { throw DocumentError.missing("Point d’animation") }
        guard !keys.contains(where: { $0.id != id && $0.time == time }) else { throw DocumentError.invalid("Un point existe déjà à cet instant") }
        keys[index].time = time; keys[index].value = value
        candidate.amountKeyframes = keys
        try candidate.validateAnimation(); effect = candidate
    }
}
