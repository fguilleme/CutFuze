import SwiftUI

extension EffectUsage {
    var label: String {
        switch self {
        case .textAndShapes: AppLocalization.bilingual("Texte / formes", "Text / shapes")
        case .photoVideo: AppLocalization.bilingual("Photo / vidéo", "Photo / video")
        case .portraits: AppLocalization.bilingual("Portraits", "Portraits")
        case .movingLayers: AppLocalization.bilingual("Calque animé", "Moving layer")
        case .allVisual: AppLocalization.bilingual("Tous visuels", "All visuals")
        }
    }
}

@MainActor struct AppliedEffectsPanel: View {
    @ObservedObject var model: EditorModel
    let clip: Clip
    let editEffect: (EffectInstance) -> Void
    @State private var editingTransition: ClipTransitionContext?

    private var item: RenderClip? { model.plan.clips.first { $0.id == clip.id } }
    private var transitions: [ClipTransitionContext] { item.map { ClipTransitionContext.relevant(to: $0, in: model.plan) } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalization.bilingual("Sur ce segment", "On this segment")).font(.caption.weight(.semibold))
            if clip.effects.isEmpty { Text(AppLocalization.bilingual("Aucun effet appliqué", "No effects applied")).font(.caption).foregroundStyle(.secondary) }
            ForEach(clip.effects) { effect in
                HStack(spacing: 6) {
                    Button { editEffect(effect) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(effectLabel(effect.kind.rawValue)).font(.caption.weight(.semibold))
                            Text(status(effect)).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("appliedEffect-\(effect.kind.rawValue)")
                    Button {
                        model.changeClip(L("Effets")) { c in if let index = c.effects.firstIndex(where: { $0.id == effect.id }) { c.effects[index].enabled.toggle() } }
                    } label: { Image(systemName: effect.enabled ? "eye" : "eye.slash").frame(width: 44, height: 44) }
                        .accessibilityLabel(AppLocalization.bilingual(effect.enabled ? "Désactiver l’effet" : "Activer l’effet", effect.enabled ? "Disable effect" : "Enable effect"))
                        .accessibilityIdentifier("toggleAppliedEffect-\(effect.kind.rawValue)")
                    Button(role: .destructive) { model.changeClip(L("Supprimer l’effet")) { $0.effects.removeAll { $0.id == effect.id } } } label: {
                        Image(systemName: "trash").foregroundStyle(.red).frame(width: 44, height: 44)
                    }.accessibilityLabel(L("Supprimer l’effet")).accessibilityIdentifier("deleteAppliedEffect-\(effect.kind.rawValue)")
                }.padding(.leading, 8).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            Text(L("Transition")).font(.caption.weight(.semibold))
            if transitions.isEmpty { Text(AppLocalization.bilingual("Aucune transition sur ce segment", "No transition on this segment")).font(.caption).foregroundStyle(.secondary) }
            ForEach(transitions) { context in
                Button { editingTransition = context } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text((context.incoming ? L("Entrée") : L("Sortie")) + " · " + transitionLabel(context.transition.kind)).font(.caption.weight(.semibold))
                            Text(AppLocalization.bilingual("Partagée entre deux scènes", "Shared between two scenes") + String(format: " · %.2f s", context.transition.duration.seconds)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "pencil").frame(width: 44, height: 44)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier(context.incoming ? "appliedIncomingTransition" : "appliedOutgoingTransition")
            }
        }.sheet(item: $editingTransition) { context in SceneEditSheet(model: model, initialSceneID: context.sceneID) }
    }

    private func status(_ effect: EffectInstance) -> String {
        if !effect.enabled { return AppLocalization.bilingual("Désactivé", "Disabled") }
        guard let item, item.isActive(at: .init(seconds: model.playhead)) else { return AppLocalization.bilingual("En dehors du segment", "Outside the segment") }
        let time = MediaTime(seconds: model.playhead) - item.globalStart + clip.animationOffset
        return effect.evaluatedAmount(at: time) == nil ? AppLocalization.bilingual("Hors plage à la tête de lecture", "Outside its range at the playhead") : AppLocalization.bilingual("Actif à la tête de lecture", "Active at the playhead")
    }
}

func transitionLabel(_ kind: TransitionKind) -> String {
    switch kind {
    case .none: L("Coupe franche")
    case .dissolve: L("Fondu enchaîné")
    case .black: L("Noir")
    case .white: L("Blanc")
    case .slide: L("Glissement")
    case .wipe: L("Balayage")
    case .zoom: "Zoom"
    case .blur: L("Flou")
    case .glitch: "Glitch"
    }
}
