import Foundation

extension EffectKind {
    var intensityRange: ClosedRange<Double> {
        switch self {
        case .exposure: -2...2
        case .impactZoom, .shortGlitch, .neon, .dream, .lightSweep, .liquidDistortion, .directionalBlur, .popHalftone, .duotone, .lensPulse, .ghostTrail, .stopMotion, .roughEdges, .writeOn: 0...1
        default: -1...1
        }
    }
    var isTimedPreset: Bool { self == .impactZoom || self == .shortGlitch || self == .lightSweep || self == .lensPulse }
    var isTemporal: Bool { self == .ghostTrail || self == .stopMotion }
}

struct EffectAmountKeyframe: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var time: MediaTime
    var value: Double
    var easing: KeyframeEasing = .linear
}

extension EffectInstance {
    var neonGlowRadius: Double { min(1, max(0, glowRadius ?? 0.45)) }
    var lightSweepWidth: Double { min(1, max(0, sweepWidth ?? 0.35)) }
    var liquidFlowSpeed: Double { min(2, max(0.25, liquidSpeed ?? 1)) }
    var directionalBlurAngle: Double { min(180, max(-180, blurAngle ?? 45)) }
    var halftoneDotScale: Double { min(1, max(0, dotScale ?? 0.45)) }
    var ghostCount: Int { min(5, max(1, echoCount ?? 3)) }
    var ghostSpacing: Double { min(0.4, max(1 / 60, echoSpacing ?? 0.12)) }
    var ghostDecay: Double { min(0.85, max(0.1, echoDecay ?? 0.55)) }
    var stopMotionFrameRate: Double { min(24, max(2, heldFrameRate ?? 8)) }
    var edgeCoarseness: Double { min(1, max(0, roughnessScale ?? 0.5)) }
    var strokeWidth: Double { min(0.5, max(0.01, brushWidth ?? 0.18)) }
    var paintMode: BrushPaintMode { brushMode ?? .reveal }
    var strokePath: [BrushPoint] { brushPath ?? BrushPaths.sweep }
    /// Presets live in the same time domain as manually edited effect points.
    /// Splitting a clip preserves this envelope and the renderer's deterministic seed.
    static func readyToUse(_ kind: EffectKind, duration: MediaTime, offset: MediaTime = .zero, localTime: Double = 0, defaultAmount: Double = 0.45) -> EffectInstance {
        var effect = EffectInstance(kind: kind, amount: kind == .neon ? 0.65 : defaultAmount)
        if kind == .neon { effect.colorHex = "#49E6FF"; effect.glowRadius = 0.45 }
        if kind == .dream { effect.amount = 0.55 }
        if kind == .liquidDistortion { effect.amount = 0.55; effect.liquidSpeed = 1 }
        if kind == .lightSweep { effect.colorHex = "#FFD58A"; effect.sweepWidth = 0.35 }
        if kind == .directionalBlur { effect.amount = 0.65; effect.blurAngle = 45 }
        if kind == .popHalftone { effect.amount = 0.8; effect.dotScale = 0.45 }
        if kind == .duotone { effect.amount = 1; effect.colorHex = "#152A62"; effect.secondaryColorHex = "#FFB5DA" }
        if kind == .ghostTrail { effect.amount = 0.75; effect.echoCount = 3; effect.echoSpacing = 0.12; effect.echoDecay = 0.55 }
        if kind == .stopMotion { effect.amount = 1; effect.heldFrameRate = 8 }
        if kind == .roughEdges { effect.amount = 0.55; effect.roughnessScale = 0.5 }
        if kind == .writeOn {
            effect.amount = 1; effect.brushWidth = 0.18; effect.brushMode = .reveal; effect.colorHex = "#FFD58A"
            let length = min(1.5, duration.seconds)
            let start = offset + MediaTime(seconds: min(max(0, localTime), max(0, duration.seconds - length)))
            if length > 0 {
                effect.amountKeyframes = [.init(time: start, value: 0), .init(time: start + .init(seconds: length), value: 1)]
            }
            // No end interval: the completed drawing remains visible for the rest of the clip.
            return effect
        }
        guard kind.isTimedPreset, duration.value > 0 else { return effect }
        let length = min(duration.seconds, kind == .lightSweep ? 1.2 : kind == .lensPulse ? 0.7 : kind == .impactZoom ? 0.48 : 0.30)
        // Shift a burst backwards when the playhead is too close to the clip end.
        let start = offset + MediaTime(seconds: min(max(0, localTime), max(0, duration.seconds - length)))
        effect.start = start; effect.duration = .init(seconds: length)
        let envelope: [(Double, Double, KeyframeEasing)]
        switch kind {
        case .lightSweep: envelope = [(0, 0, .linear), (0.15, 0.85, .easeOut), (0.85, 0.85, .linear), (1, 0, .easeIn)]
        case .impactZoom: envelope = [(0, 0.85, .linear), (0.16, 1, .easeOut), (0.42, 0.3, .easeOut), (1, 0, .easeOut)]
        case .lensPulse: envelope = [(0, 0, .linear), (0.28, 1, .easeOut), (1, 0, .easeInOut)]
        default: envelope = [(0, 0.75, .linear), (0.14, 1, .linear), (0.36, 0.25, .linear), (0.55, 0.8, .linear), (1, 0, .easeOut)]
        }
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
              sweepWidth.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              liquidSpeed.map({ $0.isFinite && (0.25...2).contains($0) }) ?? true,
              blurAngle.map({ $0.isFinite && (-180...180).contains($0) }) ?? true,
              dotScale.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              echoCount.map({ (1...5).contains($0) }) ?? true,
              echoSpacing.map({ $0.isFinite && (1 / 60...0.4).contains($0) }) ?? true,
              echoDecay.map({ $0.isFinite && (0.1...0.85).contains($0) }) ?? true,
              heldFrameRate.map({ $0.isFinite && (2...24).contains($0) }) ?? true,
              roughnessScale.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              brushWidth.map({ $0.isFinite && (0.01...0.5).contains($0) }) ?? true,
              brushPath.map({ ($0.isEmpty || $0.count >= 2) && $0.count <= 4096 && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) } }) ?? true,
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
