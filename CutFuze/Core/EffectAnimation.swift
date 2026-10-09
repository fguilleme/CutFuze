import Foundation

struct EffectAmountKeyframe: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var time: MediaTime
    var value: Double
    var easing: KeyframeEasing = .linear
}

extension EffectInstance {
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
        guard start.map(valid) ?? true, duration.map(valid) ?? true, keys.count <= 10_000,
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
