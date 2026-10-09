import SwiftUI

private func EFL(_ french: String, _ english: String) -> String { AppLocalization.bilingual(french, english) }

@MainActor struct EffectEditorSheet: View {
    @ObservedObject var model: EditorModel
    let effectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EffectInstance?
    @State private var snapshot: ProjectDocument?
    @State private var clipID: UUID?
    @State private var localTime = 0.0
    @State private var selectedKeyID: UUID?
    @State private var easing: KeyframeEasing = .linear
    @State private var preview: CGImage?
    @State private var error: String?
    @State private var renderError: String?
    @State private var generation = 0
    @State private var undoStack: [EffectInstance] = []
    @State private var redoStack: [EffectInstance] = []
    @State private var gestureBefore: EffectInstance?

    private var rendered: RenderClip? { model.plan.clips.first { $0.id == clipID } }
    private var clipStart: MediaTime { rendered?.globalStart ?? .zero }
    private var clipDuration: MediaTime { rendered?.duration ?? .init(seconds: 1) }
    private var animationOffset: MediaTime { rendered?.clip.animationOffset ?? .zero }
    private var animationTime: MediaTime {
        if let key = keys.first(where: { $0.id == selectedKeyID }), abs((key.time - animationOffset).seconds - localTime) < 1e-9 { return key.time }
        return animationOffset + .init(seconds: localTime)
    }
    private var domain: ClosedRange<MediaTime> { animationOffset...(animationOffset + clipDuration) }
    private var previewKey: String { "\(localTime)|\(String(describing: draft))" }
    private var keys: [EffectAmountKeyframe] { (draft?.amountKeyframes ?? []).sorted { $0.time < $1.time } }
    private var visibleKeys: [EffectAmountKeyframe] { keys.filter { domain.contains($0.time) } }
    private var currentAmount: Double { draft?.animatedAmount(at: animationTime) ?? 0 }
    private var intensityRange: ClosedRange<Double> { draft?.kind == .exposure ? -2...2 : -1...1 }
    private var graphRange: ClosedRange<Double> {
        let values = (gestureBefore ?? draft)?.amountKeyframes?.map(\.value) ?? []
        return min(intensityRange.lowerBound, values.min() ?? 0)...max(intensityRange.upperBound, values.max() ?? 0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let item = rendered, let effect = draft {
                    VStack(spacing: 5) {
                        // The graph's scalar adapter does not edit clip opacity;
                        // effect values stay in their existing animation domain.
                        KeyframeGraph(clip: item, property: .opacity, globalTime: (clipStart + .init(seconds: localTime)).seconds, selectedID: selectedKeyID, valueRange: graphRange,
                                      pointIDs: Set(keys.map(\.id)),
                                      animationPoints: keys.map { .init(id: $0.id, time: $0.time, property: .opacity, value: $0.value, easing: $0.easing) },
                                      title: L("Intensité"), evaluate: { time in effect.animatedAmount(at: time - item.globalStart + item.clip.animationOffset) },
                                      onScrub: { scrub(($0 - clipStart).seconds) }, onSelect: { selectKey($0.id) }, onMove: movePoint)
                        Slider(value: Binding(get: { localTime }, set: scrub), in: 0...max(0.001, clipDuration.seconds))
                            .tint(DesignTokens.amber).accessibilityLabel(L("Parcourir l’animation")).accessibilityIdentifier("keyframeTimeSlider")
                        HStack {
                            Button { setKey(at: animationTime, value: currentAmount) } label: {
                                Label(L(selectedKeyID == nil ? "Ajouter un point" : "Enregistrer le point"), systemImage: selectedKeyID == nil ? "plus.diamond" : "checkmark")
                                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
                            }.buttonStyle(.plain).foregroundStyle(DesignTokens.amber).accessibilityIdentifier("effectSaveKeyframe")
                            Spacer()
                            if selectedKeyID != nil {
                                Button(role: .destructive) { removeSelectedKey() } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                                    .buttonStyle(.plain).accessibilityLabel(L("Supprimer le point")).accessibilityIdentifier("effectDeleteKeyframe")
                            }
                        }
                        if let message = error ?? renderError { Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).accessibilityIdentifier("effectEditorError") }
                    }.padding(.horizontal, 16).padding(.bottom, 6).background(DesignTokens.ink)
                    Form {
                        Section(L("Intensité")) {
                            Toggle(EFL("Effet actif", "Effect enabled"), isOn: Binding(get: { draft?.enabled ?? true }, set: { value in changeDraft { $0.enabled = value } })).accessibilityIdentifier("effectEnabled")
                            ValueSlider(title: L("Intensité"), value: Binding(get: { currentAmount }, set: { value in
                                if keys.isEmpty { changeDraft { $0.amount = value } } else { setKey(at: animationTime, value: value) }
                            }), range: intensityRange, editing: editGesture)
                            HStack {
                                Button { seekKey(previous: true) } label: { Label(L("Point précédent"), systemImage: "backward.end").frame(minHeight: 44) }.disabled(!visibleKeys.contains { $0.time < animationTime })
                                Spacer()
                                Button { seekKey(previous: false) } label: { Label(L("Point suivant"), systemImage: "forward.end").frame(minHeight: 44) }.disabled(!visibleKeys.contains { $0.time > animationTime })
                            }
                            Picker(L("Interpolation"), selection: $easing) {
                                ForEach(KeyframeEasing.allCases, id: \.self) { Text(animationEasingLabel($0)).tag($0) }
                            }.disabled(selectedKeyID == nil).onChange(of: easing) { _, value in
                                guard let selectedKeyID else { return }
                                changeDraft { effect in
                                    if let index = effect.amountKeyframes?.firstIndex(where: { $0.id == selectedKeyID }) { effect.amountKeyframes?[index].easing = value }
                                }
                            }
                            Button(L("Retirer les points")) {
                                let amount = currentAmount
                                changeDraft { $0.amountKeyframes = nil; $0.amount = amount }; selectedKeyID = nil
                            }.disabled(keys.isEmpty)
                        }
                        Section(EFL("Plage de l’effet", "Effect time range")) {
                            Toggle(EFL("Limiter la plage", "Limit time range"), isOn: Binding(get: { draft?.start != nil || draft?.duration != nil }, set: { limited in
                                changeDraft { $0.start = limited ? animationOffset : nil; $0.duration = limited ? clipDuration : nil }
                            })).accessibilityIdentifier("effectLimitRange")
                            if effect.start != nil || effect.duration != nil {
                                ValueSlider(title: L("Début"), value: Binding(get: { max(0, ((draft?.start ?? animationOffset) - animationOffset).seconds) }, set: { start in
                                    changeDraft { effect in
                                        let end = (effect.start ?? animationOffset) + (effect.duration ?? clipDuration)
                                        effect.start = animationOffset + .init(seconds: start)
                                        effect.duration = max(.init(value: 1), end - effect.start!)
                                    }
                                }), range: 0...max(0.001, clipDuration.seconds - 1 / 60_000), suffix: " s", editing: editGesture)
                                let start = max(0, ((effect.start ?? animationOffset) - animationOffset).seconds)
                                ValueSlider(title: L("Fin"), value: Binding(get: { min(clipDuration.seconds, ((draft?.start ?? animationOffset) + (draft?.duration ?? clipDuration) - animationOffset).seconds) }, set: { end in
                                    changeDraft { $0.duration = max(.init(value: 1), animationOffset + .init(seconds: end) - ($0.start ?? animationOffset)) }
                                }), range: min(clipDuration.seconds, start + 1 / 60_000)...max(start + 1 / 60_000, clipDuration.seconds), suffix: " s", editing: editGesture)
                            }
                        }
                        Section {
                            Text(EFL("Effet commun à tous les formats", "Effect shared by every format")).font(.caption).foregroundStyle(DesignTokens.amber)
                            Button(L("Supprimer l’effet"), role: .destructive) { removeEffect() }.frame(minHeight: 44)
                        }
                    }.buttonStyle(.borderless).accessibilityIdentifier("effectSettings")
                }
            }.pinnedPreview(preview ?? model.preview).navigationTitle(draft.map { effectLabel($0.kind.rawValue) } ?? L("Effets")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(L("Annuler")).accessibilityIdentifier("effectCancel")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { undoDraft() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(undoStack.isEmpty).accessibilityLabel(L("Annuler la modification")).accessibilityIdentifier("effectUndo")
                        Button { redoDraft() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(redoStack.isEmpty).accessibilityLabel(L("Rétablir")).accessibilityIdentifier("effectRedo")
                        Button { apply() } label: { Image(systemName: "checkmark") }.disabled(draft == nil).accessibilityLabel(L("Appliquer")).accessibilityIdentifier("effectApply")
                    }
                }
        }.preferredColorScheme(.dark).onAppear(perform: load).task(id: previewKey) { await render() }
    }

    private func load() {
        guard snapshot == nil, let clip = model.selectedClip, let effect = clip.effects.first(where: { $0.id == effectID }) else { return }
        model.stop(); snapshot = model.document; draft = effect; clipID = clip.id
        scrub(min(max(0, model.playhead - clipStart.seconds), max(0, clipDuration.seconds - 1 / 60_000)))
    }
    private func changeDraft(_ change: (inout EffectInstance) throws -> Void) {
        guard let before = draft else { return }
        do {
            var candidate = before; try change(&candidate); try candidate.validateAnimation()
            if candidate != before {
                if gestureBefore == nil { undoStack.append(before); redoStack = [] }
                draft = candidate
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func editGesture(_ editing: Bool) {
        if editing { if gestureBefore == nil { gestureBefore = draft } }
        else {
            if let before = gestureBefore, before != draft { undoStack.append(before); redoStack = [] }
            gestureBefore = nil
        }
    }
    private func undoDraft() {
        guard let previous = undoStack.popLast(), let current = draft else { return }
        redoStack.append(current); draft = previous; error = nil; refreshSelection()
    }
    private func redoDraft() {
        guard let next = redoStack.popLast(), let current = draft else { return }
        undoStack.append(current); draft = next; error = nil; refreshSelection()
    }
    private func scrub(_ seconds: Double) {
        localTime = min(clipDuration.seconds, max(0, seconds)); selectedKeyID = nil; refreshSelection()
    }
    private func refreshSelection() {
        let time = animationTime
        if let key = visibleKeys.first(where: { $0.time == time }) { selectedKeyID = key.id; easing = key.easing }
        else { selectedKeyID = nil }
    }
    private func selectKey(_ id: UUID) {
        guard let key = visibleKeys.first(where: { $0.id == id }) else { return }
        selectedKeyID = key.id; localTime = (key.time - animationOffset).seconds; easing = key.easing
    }
    private func setKey(at time: MediaTime, value: Double) {
        changeDraft { effect in selectedKeyID = try EffectAnimationEditing.upsert(at: time, value: value, easing: easing, domain: domain, in: &effect) }
    }
    private func movePoint(_ key: Keyframe, _ time: MediaTime, _ value: Double, _ finished: Bool) {
        editGesture(true)
        guard let original = gestureBefore else { return }
        do {
            var candidate = original
            try EffectAnimationEditing.move(key.id, to: time - clipStart + animationOffset, value: value, domain: domain, in: &candidate)
            draft = candidate; selectedKeyID = key.id; localTime = (time - clipStart).seconds; error = nil
        } catch {
            self.error = error.localizedDescription
            if finished { draft = original; selectKey(key.id) }
        }
        if finished { editGesture(false) }
    }
    private func removeSelectedKey() {
        guard let id = selectedKeyID else { return }
        changeDraft { effect in
            effect.amountKeyframes?.removeAll { $0.id == id }
            if effect.amountKeyframes?.isEmpty == true { effect.amountKeyframes = nil }
        }; selectedKeyID = nil
    }
    private func seekKey(previous: Bool) {
        let target = previous ? visibleKeys.last(where: { $0.time < animationTime }) : visibleKeys.first(where: { $0.time > animationTime })
        if let target { selectKey(target.id) }
    }
    private func render() async {
        guard var document = snapshot, let effect = draft, let clipID else { return }
        generation += 1; let token = generation
        document.updateClip(clipID) { clip in if let index = clip.effects.firstIndex(where: { $0.id == effectID }) { clip.effects[index] = effect } }
        let plan = RenderPlan.compile(document: document, variantID: model.variantID), ratio = model.variant.ratio
        do {
            try await Task.sleep(for: .milliseconds(60))
            let time = clipStart + .init(seconds: min(localTime, max(0, clipDuration.seconds - 1 / 60_000)))
            let image = try await model.renderer.render(plan: plan, time: time, rootURL: model.rootURL, size: CGSize(width: ratio >= 1 ? 480 : 480 * ratio, height: ratio >= 1 ? 480 / ratio : 480))
            if token == generation && !Task.isCancelled { preview = image; renderError = nil }
        } catch is CancellationError {} catch { if token == generation && !Task.isCancelled { renderError = error.localizedDescription } }
    }
    private func apply() {
        guard let effect = draft, model.document.revision == snapshot?.revision, model.selectedClipID == clipID else { error = EFL("Le montage a changé. Rouvrez l’effet.", "The edit changed. Reopen this effect."); return }
        model.changeClip(L("Effets")) { clip in if let index = clip.effects.firstIndex(where: { $0.id == effectID }) { clip.effects[index] = effect } }
        dismiss()
    }
    private func removeEffect() {
        guard model.document.revision == snapshot?.revision, model.selectedClipID == clipID else { error = EFL("Le montage a changé. Rouvrez l’effet.", "The edit changed. Reopen this effect."); return }
        model.changeClip(L("Supprimer l’effet")) { $0.effects.removeAll { $0.id == effectID } }
        dismiss()
    }
}
