import SwiftUI

struct KeyframeEditorSheet: View {
    @ObservedObject var model: EditorModel
    let initialProperty: KeyframeProperty
    let properties: [KeyframeProperty]?
    @StateObject private var audition: CaptionSegmentPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var previewHeight: CGFloat = 100
    @State private var previewHeightAtDragStart: CGFloat?
    @State private var availableHeight: CGFloat = 700
    init(model: EditorModel, initialProperty: KeyframeProperty = .scale, properties: [KeyframeProperty]? = nil) {
        self.model = model; self.initialProperty = initialProperty; self.properties = properties
        _audition = StateObject(wrappedValue: CaptionSegmentPlayer(plan: model.plan, rootURL: model.rootURL))
    }
    private var volumeMode: Bool { initialProperty == .volume }
    private var availableProperties: [KeyframeProperty] {
        volumeMode ? [.volume] : (properties ?? (KeyframeProperty.visual + ((rendered?.presentation.mask ?? MaskKind.none) != .none ? KeyframeProperty.mask : [])))
    }
    private func evaluatedValue(in clip: RenderClip, at time: MediaTime) -> Double {
        property == .volume ? clip.evaluatedVolume(at: time) : AnimationEditing.value(property, in: clip.evaluatedPresentation(at: time))
    }
    private var previewHeightRange: ClosedRange<CGFloat> { 80...max(100, min(500, availableHeight * 0.48)) }
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
        let values = (0...100).map { evaluatedValue(in: rendered, at: rendered.globalStart + MediaTime(seconds: rendered.duration.seconds * Double($0) / 100)) }
        let lower = values.min() ?? displayedValue, upper = values.max() ?? displayedValue
        let padding = max((upper - lower) * 0.15, property == .rotation ? 15 : 0.15)
        return max(range.lowerBound, lower - padding)...max(max(range.lowerBound, lower - padding) + 0.01, min(max(range.upperBound, upper), upper + padding))
    }
    private var signature: String { "\(clipID?.uuidString ?? "")|\(property.rawValue)|\(globalSeconds)|\(displayedValue)|\(easing.rawValue)|\(model.document.revision)" }
    var body: some View {
        NavigationStack {
            Form {
                if let image = preview ?? model.preview {
                    Section {
                        VStack(spacing: 0) {
                            Image(decorative: image, scale: 1).resizable().scaledToFit()
                                .frame(maxWidth: .infinity).frame(height: min(previewHeight, previewHeightRange.upperBound))
                                .accessibilityLabel(L("Aperçu du réglage")).accessibilityIdentifier("curvePreview")
                            previewDivider
                        }
                    }.listRowBackground(DesignTokens.ink)
                }
                if let rendered {
                    Section {
                    VStack(spacing: 5) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(availableProperties, id: \.self) { item in
                                    Button { property = item; selectedKeyID = nil; loadValue() } label: {
                                        Text(animationPropertyLabel(item)).font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(height: 44)
                                            .background(property == item ? DesignTokens.amber.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                    }.buttonStyle(.plain).accessibilityIdentifier("keyframeProperty-\(item.rawValue)")
                                        .accessibilityAddTraits(property == item ? .isSelected : [])
                                }
                            }
                        }
                        KeyframeGraph(clip: draftRendered ?? rendered, property: property, globalTime: audition.activeID == nil ? globalSeconds : audition.position, selectedID: selectedKeyID, valueRange: graphRange,
                                      pointIDs: Set(rendered.clip.keyframes.map(\.id)),
                                      onScrub: selectTime, onSelect: select, onMove: movePoint)
                        Slider(value: Binding(get: { globalSeconds }, set: { selectTime(.init(seconds: $0)) }), in: rendered.globalStart.seconds...max(rendered.globalStart.seconds + 0.001, rendered.end.seconds))
                            .tint(DesignTokens.amber).accessibilityLabel(L("Parcourir l’animation")).accessibilityIdentifier("keyframeTimeSlider")
                        HStack {
                            Text(L("Interpolation")).font(.caption)
                            Spacer()
                            Picker(L("Interpolation"), selection: Binding(get: { easing }, set: changeEasing)) {
                                ForEach(KeyframeEasing.allCases, id: \.self) { Text(animationEasingLabel($0)).tag($0) }
                            }.pickerStyle(.menu).labelsHidden().font(.caption)
                                .accessibilityIdentifier("keyframeEasing").accessibilityValue(animationEasingLabel(easing))
                                .disabled(selectedKeyID != nil && previous == nil)
                        }.frame(minHeight: 44)
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
                        if volumeMode {
                            Button(action: listen) {
                                Label(audition.activeID == nil ? AppLocalization.bilingual("Écouter le segment", "Listen to segment") : L("Arrêter"), systemImage: audition.activeID == nil ? "play.fill" : "stop.fill").frame(minHeight: 44)
                            }.accessibilityIdentifier("listenVolumeCurve")
                            if let message = audition.error { Text(L(message)).font(.caption).foregroundStyle(.red).accessibilityIdentifier("volumeAuditionError") }
                        }
                    }.padding(.bottom, 6)
                    }.listRowBackground(DesignTokens.ink)
                }
                Section(L("Point d’animation")) {
                    HStack { Text(L("Instant") + " (s)"); TextField(L("Instant"), value: Binding(get: { globalSeconds - (rendered?.globalStart.seconds ?? 0) }, set: { globalSeconds = $0 + (rendered?.globalStart.seconds ?? 0) }), format: .number.precision(.fractionLength(0...4))).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                    HStack {
                        Button { if let previous { selectTime(previous) } } label: { Label(L("Point précédent"), systemImage: "backward.end") }.disabled(previous == nil)
                        Spacer()
                        Button { if let next { selectTime(next) } } label: { Label(L("Point suivant"), systemImage: "forward.end") }.disabled(next == nil)
                    }
                    ValueSlider(title: animationPropertyLabel(property), value: $displayedValue, range: range)
                    HStack { Text(L("Valeur")); TextField(L("Valeur"), value: $displayedValue, format: .number.precision(.fractionLength(0...4))).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("keyframeValueField") }
                    Text(selectedKeyID != nil && previous == nil
                         ? AppLocalization.bilingual("Ce premier point n’a pas de transition d’arrivée. Sélectionnez le point suivant pour modifier la courbe entre les deux.", "This first point has no incoming transition. Select the next point to change the curve between them.")
                         : L("L’interpolation choisie décrit l’arrivée sur ce point depuis le précédent.")).font(.caption).foregroundStyle(.secondary)
                }
                if availableProperties.contains(.opacity) { Section(L("Fondus d’entrée et de sortie")) {
                    Picker(L("Animation"), selection: $preset) { Text(L("Entrée")).tag(FadeAnimationPreset.entrance); Text(L("Sortie")).tag(FadeAnimationPreset.exit); Text(L("Entrée et sortie")).tag(FadeAnimationPreset.combination) }.pickerStyle(.segmented)
                    HStack { Text(L("Durée") + " (s)"); TextField(L("Durée"), value: $fadeDuration, format: .number.precision(.fractionLength(0...3))).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    Text(L("Seuls les points d’opacité aux bornes du fondu sont ajoutés ou modifiés. Les autres points manuels sont conservés.")).font(.caption).foregroundStyle(.secondary)
                    Button(L("Appliquer le fondu")) { applyPreset() }.accessibilityIdentifier("applyKeyframeFade")
                } }
                Section(L("Images clés")) {
                    if let rendered {
                        ForEach(rendered.clip.keyframes.filter { $0.property == property && $0.time >= rendered.clip.animationOffset && $0.time <= rendered.clip.animationOffset + rendered.duration }.sorted { $0.time < $1.time }) { key in
                            HStack {
                                Button { select(key) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(animationPropertyLabel(key.property)).font(.subheadline)
                                        Text(String(format: "%.3f s · %@", (rendered.globalStart + key.time - rendered.clip.animationOffset).seconds, animationEasingLabel(key.easing))).font(.caption.monospacedDigit()).foregroundStyle(.secondary).accessibilityIdentifier("keyframeDetail-\(key.id)")
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) { remove(key) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel(L("Supprimer le point"))
                            }
                        }
                    }
                }
                Section { Text(volumeMode ? AppLocalization.bilingual("Le volume est commun aux formats. 1× correspond au niveau original ; les fondus et le mixage restent appliqués.", "Volume is shared by all formats. 1× is the original level; fades and mixing still apply.") : L("L’animation est commune aux formats. Les valeurs affichées tiennent compte du cadrage actif.")).font(.caption).foregroundStyle(.secondary) }
            }.buttonStyle(.borderless).scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("keyframeEditorForm")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { availableHeight = $0 }
                .navigationTitle(volumeMode ? AppLocalization.bilingual("Courbe de volume", "Volume curve") : L("Éditer les points")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() }.accessibilityIdentifier("closeCurveEditor") }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { model.undo(); loadValue() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).accessibilityLabel(L("Annuler la modification")).accessibilityIdentifier("keyframeUndo")
                        Button { model.redo(); loadValue() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).accessibilityLabel(L("Rétablir")).accessibilityIdentifier("keyframeRedo")
                    }
                }
                .onAppear {
                    model.stop(); clipID = model.selectedClipID; property = initialProperty
                    if let rendered {
                        globalSeconds = min(max(model.playhead, rendered.globalStart.seconds), rendered.end.seconds)
                        if properties == nil, !volumeMode, !rendered.clip.keyframes.contains(where: { $0.property == property }), let first = rendered.clip.keyframes.filter({ availableProperties.contains($0.property) }).sorted(by: { $0.time < $1.time }).first { property = first.property }
                        fadeDuration = min(0.5, rendered.duration.seconds / 3); loadValue()
                    }
                }
                .task(id: signature) { await renderDraft() }
                .onChange(of: signature) { _, _ in audition.stop() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { audition.stop() } }
                .onDisappear { audition.stop() }
        }.presentationSizing(.page).presentationDetents([.large])
            .preferredColorScheme(.dark)
    }
    private var previewDivider: some View {
        CurvePreviewResizeHandle(value: previewHeight, active: previewHeightAtDragStart != nil, changed: { translation, ended in
                if previewHeightAtDragStart == nil {
                    previewHeightAtDragStart = min(previewHeight, previewHeightRange.upperBound)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                setPreviewHeight((previewHeightAtDragStart ?? previewHeight) + translation)
                if ended {
                    previewHeightAtDragStart = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        }, adjusted: { setPreviewHeight(previewHeight + $0) }).frame(maxWidth: .infinity).frame(height: 22)
    }
    private func setPreviewHeight(_ value: CGFloat) {
        let target = min(previewHeightRange.upperBound, max(previewHeightRange.lowerBound, value))
        var transaction = Transaction(); transaction.animation = nil
        withTransaction(transaction) { previewHeight = target }
    }
    private var range: ClosedRange<Double> {
        switch property { case .x, .y: -0.5...1.5; case .scale: 0.05...4; case .rotation, .maskRotation: -180...180; case .opacity, .maskX, .maskY: 0...1; case .volume: 0...2; case .maskWidth, .maskHeight: 0.05...1.5; case .maskFeather: 0...0.2 }
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
        displayedValue = evaluatedValue(in: rendered, at: draftTime)
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
    private func changeEasing(_ value: KeyframeEasing) {
        easing = value
        guard let selectedKeyID, let clipID,
              rendered?.clip.keyframes.first(where: { $0.id == selectedKeyID })?.easing != value else { return }
        perform(L("Interpolation")) { try AnimationEditing.setEasing(value, keyframeID: selectedKeyID, clipID: clipID, in: &$0) }
        if localError != nil { loadValue() }
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
    private func listen() {
        guard let rendered, let clipID else { return }
        if audition.activeID != nil { audition.stop(); return }
        do {
            var candidate = model.document; try mutatePoint(in: &candidate); try candidate.validate()
            audition.replacePlan(.compile(document: candidate, variantID: model.variantID))
            audition.toggle(id: clipID, start: rendered.globalStart, end: rendered.end)
        } catch { localError = error.localizedDescription }
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

/// A resize drag owns its touch; drags elsewhere still scroll the whole editor.
struct CurvePreviewResizeHandle: UIViewRepresentable {
    var value: CGFloat
    var active: Bool
    var changed: (CGFloat, Bool) -> Void
    var adjusted: (CGFloat) -> Void
    func makeUIView(context: Context) -> Handle { Handle(changed: changed) }
    func updateUIView(_ view: Handle, context: Context) {
        view.changed = changed; view.adjusted = adjusted
        view.accessibilityLabel = AppLocalization.bilingual("Hauteur de l’aperçu", "Preview height")
        view.accessibilityValue = "\(Int(value))"
        view.bar.backgroundColor = active ? UIColor(Color(hex: "#EBA65A")).cgColor : UIColor.white.withAlphaComponent(0.34).cgColor
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Handle, context: Context) -> CGSize { CGSize(width: proposal.width ?? 100, height: 22) }
    final class Handle: UIView {
        var changed: (CGFloat, Bool) -> Void
        var adjusted: ((CGFloat) -> Void)?
        let bar = CALayer()
        private var pan: UIPanGestureRecognizer!
        init(changed: @escaping (CGFloat, Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
            isAccessibilityElement = true; accessibilityTraits = .adjustable
            accessibilityIdentifier = "curvePreviewDivider"
            bar.cornerRadius = 1.5; layer.addSublayer(bar)
            pan = UIPanGestureRecognizer(target: self, action: #selector(dragged))
            addGestureRecognizer(pan)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            bar.frame = CGRect(x: (bounds.width - 38) / 2, y: (bounds.height - 3) / 2, width: 38, height: 3)
        }
        override func accessibilityIncrement() { adjusted?(30) }
        override func accessibilityDecrement() { adjusted?(-30) }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView { scroll.panGestureRecognizer.require(toFail: pan) }
                ancestor = view.superview
            }
        }
        @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began, .changed: changed(gesture.translation(in: window).y, false)
            case .ended, .cancelled: changed(gesture.translation(in: window).y, true)
            default: break
            }
        }
    }
}

func animationPropertyLabel(_ value: KeyframeProperty) -> String {
    switch value { case .x: L("Horizontal"); case .y: L("Vertical"); case .scale: L("Échelle"); case .rotation: L("Rotation"); case .opacity: L("Opacité"); case .volume: L("Volume"); case .maskWidth: L("Largeur du masque"); case .maskHeight: L("Hauteur du masque"); case .maskX: L("Position X du masque"); case .maskY: L("Position Y du masque"); case .maskRotation: L("Rotation du masque"); case .maskFeather: L("Contour progressif") }
}
func animationEasingLabel(_ value: KeyframeEasing) -> String {
    switch value { case .linear: L("Linéaire"); case .easeIn: L("Accélération"); case .easeOut: L("Décélération"); case .easeInOut: L("Accélération et décélération") }
}
