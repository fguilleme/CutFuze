import Foundation

struct EffectAmountKeyframe: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var time: MediaTime
    var value: Double
    var easing: KeyframeEasing = .linear
}

extension EffectInstance {
    func evaluatedAmount(at animationTime: MediaTime) -> Double? {
        guard enabled, animationTime >= (start ?? .zero) else { return nil }
        if let duration, animationTime >= (start ?? .zero) + duration { return nil }
        let keys = (amountKeyframes ?? []).map { Keyframe(id: $0.id, time: $0.time, property: .opacity, value: $0.value, easing: $0.easing) }
        return KeyframeEvaluator.value(property: .opacity, at: animationTime, keyframes: keys, fallback: amount)
    }
    func validateAnimation() throws {
        func valid(_ time: MediaTime) -> Bool { time.timescale > 0 && time.timescale <= 1_000_000 && time.value >= 0 && time.seconds <= 604_800 }
        let keys = amountKeyframes ?? []
        guard start.map(valid) ?? true, duration.map(valid) ?? true, keys.count <= 10_000,
              keys.allSatisfy({ valid($0.time) && $0.value.isFinite }), Set(keys.map(\.time)).count == keys.count,
              Set(keys.map(\.id)).count == keys.count else { throw DocumentError.invalid("Animation d’effet") }
    }
}
