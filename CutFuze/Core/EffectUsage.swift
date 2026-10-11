import Foundation

/// Recommendations, not renderer compatibility restrictions.
enum EffectUsage: CaseIterable, Hashable {
    case textAndShapes, photoVideo, portraits, movingLayers, allVisual
}

extension EffectKind {
    var suggestedUsage: EffectUsage {
        switch self {
        case .roughEdges, .writeOn, .neon, .lightSweep: .textAndShapes
        case .skinSmooth, .skinGlow: .portraits
        case .ghostTrail, .stopMotion, .timeScan: .movingLayers
        case .exposure, .brightness, .contrast, .saturation, .temperature, .tint, .highlights, .shadows, .sharpness,
             .vignette, .grain, .retro, .comic, .crystallize, .dream, .popHalftone, .duotone: .photoVideo
        default: .allVisual
        }
    }
}

struct ClipTransitionContext: Identifiable, Equatable {
    var id: UUID { sceneID }
    let sceneID: UUID
    let incoming: Bool
    let transition: Transition

    /// Scene transitions affect all intersecting layers, not just the primary video.
    static func relevant(to clip: RenderClip, in plan: RenderPlan) -> [Self] {
        guard let sceneID = clip.sceneID, let index = plan.scenes.firstIndex(where: { $0.id == sceneID }) else { return [] }
        var result: [Self] = []
        for source in [index - 1, index] where source >= 0 && source + 1 < plan.scenes.count {
            let scene = plan.scenes[source]
            let lower = plan.scenes[source + 1].start
            let upper = scene.end
            if scene.transition.kind != .none, scene.transition.duration > .zero,
               clip.globalStart < upper, clip.globalStart + clip.duration > lower {
                result.append(.init(sceneID: scene.id, incoming: source < index, transition: scene.transition))
            }
        }
        return result
    }
}
