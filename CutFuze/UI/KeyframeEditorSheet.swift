import SwiftUI

struct KeyframeEditorSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var clipID: UUID?
    @State private var property: KeyframeProperty = .scale
    @State private var globalSeconds = 0.0
    @State private var displayedValue = 1.0
    @State private var easing: KeyframeEasing = .linear
    @State private var selectedKeyID: UUID?
    @State private var preset: FadeAnimationPreset = .combination
    @State private var fadeDuration = 0.5
    @State private var preview: CGImage?
    @State private var localError: String?
    @State private var renderError: String?
    private var rendered: RenderClip? { model.plan.clips.first { $0.id == clipID } }
    private var draftTime: MediaTime {
        if let rendered, let key = rendered.clip.keyframes.first(where: { $0.id == selectedKeyID && $0.property == property }) {
            let exact = rendered.globalStart + key.time - rendered.clip.animationOffset
            if abs(exact.seconds - globalSeconds) < 1e-9 { return exact }
        }
        return .init(seconds: globalSeconds)
    }
    private var propertyTimes: [MediaTime] { rendered.map { item in
        item.clip.keyframes.filter { $0.property == property }.map { item.globalStart + $0.time - item.clip.animationOffset }.filter { $0 >= item.globalStart && $0 <= item.end }.sorted()
    } ?? [] }
    private var previous: MediaTime? { propertyTimes.last { $0 < draftTime } }
    private var next: MediaTime? { propertyTimes.first { $0 > draftTime } }
    private var draftRendered: RenderClip? {
        var candidate = model.document
        do { try mutatePoint(in: &candidate) } catch { return rendered }
        return RenderPlan.compile(document: candidate, variantID: model.variantID).clips.first { $0.id == clipID }
    }
    private var graphRange: ClosedRange<Double> {
        guard let rendered else { return range }
        let values = (0...100).map { AnimationEditing.value(property, in: rendered.evaluatedPresentation(at: rendered.globalStart + MediaTime(seconds: rendered.duration.seconds * Double($0) / 100))) }
        let lower = values.min() ?? displayedValue, upper = values.max() ?? displayedValue
        let padding = max((upper - lower) * 0.15, property == .rotation ? 15 : 0.15)
        return max(range.lowerBound, lower - padding)...max(max(range.lowerBound, lower - padding) + 0.01, min(max(range.upperBound, upper), upper + padding))
    }
    private var signature: String { "\(clipID?.uuidString ?? "")|\(property.rawValue)|\(globalSeconds)|\(displayedValue)|\(easing.rawValue)|\(model.document.revision)" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let rendered {
                    VStack(spacing: 5) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(KeyframeProperty.allCases, id: \.self) { item in
                                    Button { property = item; selectedKeyID = nil; loadValue() } label: {
                                        Text(animationPropertyLabel(item)).font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(height: 44)
                                            .background(property == item ? DesignTokens.amber.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                    }.buttonStyle(.plain).accessibilityIdentifier("keyframeProperty-\(item.rawValue)")
                                        .accessibilityAddTraits(property == item ? .isSelected : [])
                                }
                            }
                        }
                        KeyframeGraph(clip: draftRendered ?? rendered, property: property, globalTime: globalSeconds, selectedID: selectedKeyID, valueRange: graphRange,
                                      pointIDs: Set(rendered.clip.keyframes.map(\.id)),
                                      onScrub: selectTime, onSelect: select, onMove: movePoint)
                        Slider(value: Binding(get: { globalSeconds }, set: { selectTime(.init(seconds: $0)) }), in: rendered.globalStart.seconds...max(rendered.globalStart.seconds + 0.001, rendered.end.seconds))
                            .tint(DesignTokens.amber).accessibilityLabel(L("Parcourir l’animation")).accessibilityIdentifier("keyframeTimeSlider")
                        HStack {
                            Button { savePoint() } label: {
                                Label(L(selectedKeyID == nil ? "Ajouter un point" : "Enregistrer le point"), systemImage: selectedKeyID == nil ? "plus.diamond" : "checkmark")
                                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
                            }.buttonStyle(.plain).foregroundStyle(DesignTokens.amber).accessibilityIdentifier("saveKeyframe")
                            Spacer()
                            if let key = rendered.clip.keyframes.first(where: { $0.id == selectedKeyID }) {
                                Button(role: .destructive) { remove(key) } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                                    .buttonStyle(.plain).accessibilityLabel(L("Supprimer le point")).accessibilityIdentifier("deleteSelectedKeyframe")
                            }
                        }
                        if let message = localError ?? renderError {
                            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 6).background(DesignTokens.ink)
                }
            Form {
                Section(L("Point d’animation")) {
                    HStack { Text(L("Instant") + " (s)"); TextField(L("Instant"), value: Binding(get: { globalSeconds - (rendered?.globalStart.seconds ?? 0) }, set: { globalSeconds = $0 + (rendered?.globalStart.seconds ?? 0) }), format: .number.precision(.fractionLength(0...4))).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                    HStack {
                        Button { if let previous { selectTime(previous) } } label: { Label(L("Point précédent"), systemImage: "backward.end") }.disabled(previous == nil)
                        Spacer()
                        Button { if let next { selectTime(next) } } label: { Label(L("Point suivant"), systemImage: "forward.end") }.disabled(next == nil)
                    }
                    ValueSlider(title: animationPropertyLabel(property), value: $displayedValue, range: range)
                    HStack { Text(L("Valeur")); TextField(L("Valeur"), value: $displayedValue, format: .number.precision(.fractionLength(0...4))).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation) }
                    Picker(L("Interpolation"), selection: $easing) { ForEach(KeyframeEasing.allCases, id: \.self) { Text(animationEasingLabel($0)).tag($0) } }
                    Text(L("L’interpolation choisie décrit l’arrivée sur ce point depuis le précédent.")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L("Fondus d’entrée et de sortie")) {
                    Picker(L("Animation"), selection: $preset) { Text(L("Entrée")).tag(FadeAnimationPreset.entrance); Text(L("Sortie")).tag(FadeAnimationPreset.exit); Text(L("Entrée et sortie")).tag(FadeAnimationPreset.combination) }.pickerStyle(.segmented)
                    HStack { Text(L("Durée") + " (s)"); TextField(L("Durée"), value: $fadeDuration, format: .number.precision(.fractionLength(0...3))).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    Text(L("Seuls les points d’opacité aux bornes du fondu sont ajoutés ou modifiés. Les autres points manuels sont conservés.")).font(.caption).foregroundStyle(.secondary)
                    Button(L("Appliquer le fondu")) { applyPreset() }
                }
                Section(L("Images clés")) {
                    if let rendered {
                        ForEach(rendered.clip.keyframes.filter { $0.property == property && $0.time >= rendered.clip.animationOffset && $0.time <= rendered.clip.animationOffset + rendered.duration }.sorted { $0.time < $1.time }) { key in
                            HStack {
                                Button { select(key) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(animationPropertyLabel(key.property)).font(.subheadline)
                                        Text(String(format: "%.3f s · %@", (rendered.globalStart + key.time - rendered.clip.animationOffset).seconds, animationEasingLabel(key.easing))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) { remove(key) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel(L("Supprimer le point"))
                            }
                        }
                    }
                }
                Section { Text(L("L’animation est commune aux formats. Les valeurs affichées tiennent compte du cadrage actif.")).font(.caption).foregroundStyle(.secondary) }
            }.buttonStyle(.borderless).scrollDismissesKeyboard(.interactively)
            }.pinnedPreview(preview ?? model.preview).navigationTitle(L("Éditer les points")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { model.undo(); loadValue() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).accessibilityLabel(L("Annuler la modification")).accessibilityIdentifier("keyframeUndo")
                        Button { model.redo(); loadValue() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).accessibilityLabel(L("Rétablir")).accessibilityIdentifier("keyframeRedo")
                    }
                }
                .onAppear {
                    model.stop(); clipID = model.selectedClipID
                    if let rendered {
                        globalSeconds = min(max(model.playhead, rendered.globalStart.seconds), rendered.end.seconds)
                        if !rendered.clip.keyframes.contains(where: { $0.property == property }), let first = rendered.clip.keyframes.sorted(by: { $0.time < $1.time }).first { property = first.property }
                        fadeDuration = min(0.5, rendered.duration.seconds / 3); loadValue()
                    }
                }
                .task(id: signature) { await renderDraft() }
        }.preferredColorScheme(.dark)
    }
    private var range: ClosedRange<Double> {
        switch property { case .x, .y: -0.5...1.5; case .scale: 0.05...4; case .rotation: -180...180; case .opacity: 0...1 }
    }
    private func selectTime(_ time: MediaTime) {
        selectedKeyID = nil; globalSeconds = time.seconds
        if let rendered { model.seek(min(time.seconds, rendered.end.seconds - 1.0 / 60_000)) }
        loadValue()
    }
    private func select(_ key: Keyframe) {
        guard let rendered else { return }
        property = key.property; selectedKeyID = key.id
        globalSeconds = (rendered.globalStart + key.time - rendered.clip.animationOffset).seconds
        easing = key.easing; loadValue()
        model.seek(min(globalSeconds, rendered.end.seconds - 1.0 / 60_000))
    }
    private func loadValue() {
        guard let rendered else { return }
        displayedValue = AnimationEditing.value(property, in: rendered.evaluatedPresentation(at: draftTime))
        let local = draftTime - rendered.globalStart + rendered.clip.animationOffset
        if let key = rendered.clip.keyframes.first(where: { $0.time == local && $0.property == property }) { selectedKeyID = key.id; easing = key.easing }
        else { selectedKeyID = nil }
    }
    private func movePoint(_ key: Keyframe, _ time: MediaTime, _ value: Double, _ finished: Bool) {
        selectedKeyID = key.id; globalSeconds = time.seconds; displayedValue = value; easing = key.easing
        if finished {
            savePoint()
            if localError != nil, let original = rendered?.clip.keyframes.first(where: { $0.id == key.id }) { select(original) }
            else { loadValue() }
        }
    }
    private func mutatePoint(in candidate: inout ProjectDocument) throws {
        guard let clipID else { return }
        if let selectedKeyID {
            try AnimationEditing.move(keyframeID: selectedKeyID, clipID: clipID, to: draftTime, displayedValue: displayedValue, variantID: model.variantID, easing: easing, in: &candidate)
        } else {
            try AnimationEditing.upsert(clipID: clipID, property: property, at: draftTime, displayedValue: displayedValue, variantID: model.variantID, easing: easing, in: &candidate)
        }
    }
    private func savePoint() {
        guard clipID != nil, globalSeconds.isFinite else { return }
        perform(L("Images clés")) { try mutatePoint(in: &$0) }
        if localError == nil { loadValue() }
    }
    private func applyPreset() {
        guard let clipID, fadeDuration.isFinite else { return }
        perform(L("Fondus d’entrée et de sortie")) { try AnimationEditing.applyFade(preset, duration: .init(seconds: fadeDuration), clipID: clipID, in: &$0) }
        loadValue()
    }
    private func remove(_ key: Keyframe) {
        guard let clipID else { return }
        perform(L("Supprimer le point")) { try DocumentEditor.updateClip(clipID, in: &$0) { $0.keyframes.removeAll { $0.id == key.id } } }
        if selectedKeyID == key.id { selectedKeyID = nil }; loadValue()
    }
    private func perform(_ name: String, _ mutation: (inout ProjectDocument) throws -> Void) {
        do { var candidate = model.document; try mutation(&candidate); try candidate.validate(); model.edit(name) { $0 = candidate }; localError = nil }
        catch { localError = error.localizedDescription }
    }
    private func renderDraft() async {
        guard clipID != nil, let rendered, globalSeconds.isFinite else { return }
        do {
            try await Task.sleep(for: .milliseconds(140))
            var candidate = model.document
            try mutatePoint(in: &candidate)
            try candidate.validate()
            let plan = RenderPlan.compile(document: candidate, variantID: model.variantID), ratio = model.variant.ratio
            let time = min(max(draftTime, rendered.globalStart), rendered.end - .init(value: 1))
            let image = try await model.renderer.render(plan: plan, time: time, rootURL: model.rootURL, size: CGSize(width: ratio >= 1 ? 350 : 350 * ratio, height: ratio >= 1 ? 350 / ratio : 350))
            if !Task.isCancelled { preview = image; renderError = nil }
        } catch is CancellationError { } catch { if !Task.isCancelled { renderError = error.localizedDescription } }
    }
}

func animationPropertyLabel(_ value: KeyframeProperty) -> String {
    switch value { case .x: L("Horizontal"); case .y: L("Vertical"); case .scale: L("Échelle"); case .rotation: L("Rotation"); case .opacity: L("Opacité") }
}
func animationEasingLabel(_ value: KeyframeEasing) -> String {
    switch value { case .linear: L("Linéaire"); case .easeIn: L("Accélération"); case .easeOut: L("Décélération"); case .easeInOut: L("Accélération et décélération") }
}
