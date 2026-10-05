import SwiftUI

private func EFL(_ french: String, _ english: String) -> String { Locale.current.language.languageCode?.identifier == "fr" ? french : english }

@MainActor struct EffectEditorSheet: View {
    @ObservedObject var model: EditorModel
    let effectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EffectInstance?
    @State private var snapshot: ProjectDocument?
    @State private var clipID: UUID?
    @State private var clipStart = 0.0
    @State private var clipDuration = 1.0
    @State private var animationOffset = 0.0
    @State private var localTime = 0.0
    @State private var selectedKeyID: UUID?
    @State private var easing: KeyframeEasing = .linear
    @State private var preview: CGImage?
    @State private var error: String?
    @State private var generation = 0
    private var animationTime: MediaTime { .init(seconds: animationOffset + localTime) }
    private var previewKey: String { "\(localTime)|\(String(describing: draft))" }
    private var keys: [EffectAmountKeyframe] { (draft?.amountKeyframes ?? []).sorted { $0.time < $1.time } }
    private var currentAmount: Double {
        guard let draft else { return 0 }
        return KeyframeEvaluator.value(property: .opacity, at: animationTime, keyframes: keys.map { .init(time: $0.time, property: .opacity, value: $0.value, easing: $0.easing) }, fallback: draft.amount)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(EFL("Effet commun à tous les formats", "Effect shared by every format")).font(.caption).foregroundStyle(DesignTokens.amber)
                    if let effect = draft {
                        Toggle(EFL("Effet actif", "Effect enabled"), isOn: Binding(get: { draft?.enabled ?? true }, set: { draft?.enabled = $0 }))
                        ValueSlider(title: EFL("Position dans le clip", "Position in clip"), value: $localTime, range: 0...max(0.001, clipDuration - 1 / 60_000), suffix: " s")
                        ValueSlider(title: L("Intensité"), value: Binding(get: { currentAmount }, set: { value in
                            if keys.isEmpty { draft?.amount = value } else { setKey(at: animationTime, value: value) }
                        }), range: effect.kind == .exposure ? -2...2 : -1...1)
                        Toggle(EFL("Limiter la plage", "Limit time range"), isOn: Binding(get: { draft?.start != nil || draft?.duration != nil }, set: { limited in
                            draft?.start = limited ? .init(seconds: animationOffset) : nil
                            draft?.duration = limited ? .init(seconds: clipDuration) : nil
                        }))
                        if effect.start != nil || effect.duration != nil {
                            ValueSlider(title: L("Début"), value: Binding(get: { max(0, (draft?.start?.seconds ?? animationOffset) - animationOffset) }, set: { start in
                                let end = (draft?.start?.seconds ?? animationOffset) + (draft?.duration?.seconds ?? clipDuration)
                                draft?.start = .init(seconds: animationOffset + start)
                                draft?.duration = .init(seconds: max(1 / 60_000, end - animationOffset - start))
                            }), range: 0...max(0.001, clipDuration - 1 / 60_000), suffix: " s")
                            let start = max(0, (effect.start?.seconds ?? animationOffset) - animationOffset)
                            ValueSlider(title: L("Fin"), value: Binding(get: { min(clipDuration, (draft?.start?.seconds ?? animationOffset) + (draft?.duration?.seconds ?? clipDuration) - animationOffset) }, set: { end in
                                draft?.duration = .init(seconds: max(1 / 60_000, animationOffset + end - (draft?.start?.seconds ?? animationOffset)))
                            }), range: min(clipDuration, start + 1 / 60_000)...max(start + 1 / 60_000, clipDuration), suffix: " s")
                        }
                        HStack {
                            Button { seekKey(previous: true) } label: { Image(systemName: "backward.end").frame(width: 44, height: 44) }.accessibilityLabel(EFL("Point précédent", "Previous keyframe"))
                            Button(L("Ajouter un point")) { setKey(at: animationTime, value: currentAmount) }.buttonStyle(.bordered)
                            Button { seekKey(previous: false) } label: { Image(systemName: "forward.end").frame(width: 44, height: 44) }.accessibilityLabel(EFL("Point suivant", "Next keyframe"))
                        }
                        Picker(EFL("Interpolation du point", "Keyframe interpolation"), selection: $easing) {
                            Text(EFL("Linéaire", "Linear")).tag(KeyframeEasing.linear)
                            Text(EFL("Accélération", "Ease in")).tag(KeyframeEasing.easeIn)
                            Text(EFL("Décélération", "Ease out")).tag(KeyframeEasing.easeOut)
                            Text(EFL("Doux", "Ease in/out")).tag(KeyframeEasing.easeInOut)
                        }.onChange(of: easing) { _, value in if let index = draft?.amountKeyframes?.firstIndex(where: { $0.id == selectedKeyID }) { draft?.amountKeyframes?[index].easing = value } }
                        if let key = keys.first(where: { $0.id == selectedKeyID }) {
                            ValueSlider(title: EFL("Déplacer ce point", "Move this keyframe"), value: Binding(get: { min(clipDuration, max(0, (draft?.amountKeyframes?.first { $0.id == key.id }?.time.seconds ?? animationOffset) - animationOffset)) }, set: { seconds in moveKey(key.id, to: .init(seconds: animationOffset + seconds)) }), range: 0...max(0.001, clipDuration), suffix: " s")
                        }
                        ForEach(keys) { key in
                            HStack {
                                Button { localTime = min(clipDuration, max(0, key.time.seconds - animationOffset)); selectedKeyID = key.id; easing = key.easing } label: { Text(String(format: "%.3f s · %.2f", key.time.seconds - animationOffset, key.value)).font(.caption.monospacedDigit()).frame(minHeight: 44) }
                                Spacer()
                                Button { draft?.amountKeyframes?.removeAll { $0.id == key.id }; if draft?.amountKeyframes?.isEmpty == true { draft?.amountKeyframes = nil } } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel(L("Supprimer"))
                            }
                        }
                        Button(L("Retirer les points")) { let amount = currentAmount; draft?.amountKeyframes = nil; draft?.amount = amount; selectedKeyID = nil }.disabled(keys.isEmpty)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }.padding(20)
            }.pinnedPreview(preview).navigationTitle(draft.map { effectLabel($0.kind.rawValue) } ?? L("Effets")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Annuler")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(EFL("Appliquer", "Apply")) { apply() }.disabled(draft == nil) }
                }
        }.preferredColorScheme(.dark).onAppear(perform: load).task(id: previewKey) { await render() }
    }
    private func load() {
        guard snapshot == nil, let clip = model.selectedClip, let effect = clip.effects.first(where: { $0.id == effectID }), let item = model.plan.clips.first(where: { $0.id == clip.id }) else { return }
        model.stop(); snapshot = model.document; draft = effect; clipID = clip.id
        clipStart = item.globalStart.seconds; clipDuration = item.duration.seconds; animationOffset = clip.animationOffset.seconds
        localTime = min(max(0, model.playhead - clipStart), max(0, clipDuration - 1 / 60_000))
    }
    private func setKey(at time: MediaTime, value: Double) {
        var updated = keys
        if let index = updated.firstIndex(where: { $0.time == time }) { updated[index].value = value; selectedKeyID = updated[index].id }
        else { let key = EffectAmountKeyframe(time: time, value: value, easing: easing); updated.append(key); selectedKeyID = key.id }
        draft?.amountKeyframes = updated
    }
    private func moveKey(_ id: UUID, to time: MediaTime) {
        var updated = keys; updated.removeAll { $0.id != id && $0.time == time }
        if let index = updated.firstIndex(where: { $0.id == id }) { updated[index].time = time }
        draft?.amountKeyframes = updated; localTime = max(0, time.seconds - animationOffset)
    }
    private func seekKey(previous: Bool) {
        let target = previous ? keys.last(where: { $0.time < animationTime }) : keys.first(where: { $0.time > animationTime })
        if let target { localTime = min(clipDuration, max(0, target.time.seconds - animationOffset)); selectedKeyID = target.id; easing = target.easing }
    }
    private func render() async {
        guard var document = snapshot, let effect = draft, let clipID else { return }
        generation += 1; let token = generation
        document.updateClip(clipID) { clip in if let index = clip.effects.firstIndex(where: { $0.id == effectID }) { clip.effects[index] = effect } }
        let plan = RenderPlan.compile(document: document, variantID: model.variantID), ratio = model.variant.ratio
        do {
            try await Task.sleep(for: .milliseconds(60))
            let image = try await model.renderer.render(plan: plan, time: .init(seconds: clipStart + min(localTime, max(0, clipDuration - 1 / 60_000))), rootURL: model.rootURL, size: CGSize(width: ratio >= 1 ? 480 : 480 * ratio, height: ratio >= 1 ? 480 / ratio : 480))
            if token == generation && !Task.isCancelled { preview = image }
        } catch is CancellationError {} catch { if token == generation { self.error = error.localizedDescription } }
    }
    private func apply() {
        guard let effect = draft, model.document.revision == snapshot?.revision, model.selectedClipID == clipID else { error = EFL("Le montage a changé. Rouvrez l’effet.", "The edit changed. Reopen this effect."); return }
        model.changeClip(L("Effets")) { clip in if let index = clip.effects.firstIndex(where: { $0.id == effectID }) { clip.effects[index] = effect } }
        dismiss()
    }
}
