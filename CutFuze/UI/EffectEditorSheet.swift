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
    @State private var focusBurst = true
    @State private var previewHeight: CGFloat = 160
    @State private var previewHeightAtDragStart: CGFloat?
    @State private var availableHeight: CGFloat = 700
    private var previewHeightRange: ClosedRange<CGFloat> { 80...max(100, min(500, availableHeight * 0.48)) }

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
    private var intensityRange: ClosedRange<Double> { draft?.kind.intensityRange ?? -1...1 }
    private var isBurst: Bool { draft?.kind.isTimedPreset == true }
    private var focusedWindow: ClosedRange<MediaTime>? {
        guard focusBurst, isBurst, let start = draft?.start, let duration = draft?.duration else { return nil }
        let lower = max(clipStart, clipStart + start - animationOffset)
        let upper = min(clipStart + clipDuration, clipStart + start + duration - animationOffset)
        return lower < upper ? lower...upper : nil
    }
    private var graphRange: ClosedRange<Double> {
        let values = (gestureBefore ?? draft)?.amountKeyframes?.map(\.value) ?? []
        return min(intensityRange.lowerBound, values.min() ?? 0)...max(intensityRange.upperBound, values.max() ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item = rendered, let effect = draft {
                    if let image = preview ?? model.preview {
                        Section {
                            VStack(spacing: 0) {
                                Image(decorative: image, scale: 1).resizable().scaledToFit()
                                    .frame(maxWidth: .infinity).frame(height: min(previewHeight, previewHeightRange.upperBound))
                                    .accessibilityLabel(L("Aperçu du réglage")).accessibilityIdentifier("effectCurvePreview")
                                CurvePreviewResizeHandle(value: previewHeight, active: previewHeightAtDragStart != nil, changed: { translation, ended in
                                    if previewHeightAtDragStart == nil {
                                        previewHeightAtDragStart = min(previewHeight, previewHeightRange.upperBound)
                                        UISelectionFeedbackGenerator().selectionChanged()
                                    }
                                    setPreviewHeight((previewHeightAtDragStart ?? previewHeight) + translation)
                                    if ended { previewHeightAtDragStart = nil; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                                }, adjusted: { setPreviewHeight(previewHeight + $0) }).frame(maxWidth: .infinity).frame(height: 22)
                            }
                        }.listRowBackground(DesignTokens.ink)
                    }
                    Section {
                    VStack(spacing: 5) {
                        if let description = effectDescription(effect.kind) {
                            Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if isBurst {
                            Button { focusBurst.toggle() } label: {
                                Label(focusBurst ? EFL("Voir tout le clip", "Show entire clip") : EFL("Zoom sur l’effet", "Focus on effect"), systemImage: "arrow.left.and.right")
                                    .font(.caption).frame(minHeight: 44)
                            }.buttonStyle(.plain).accessibilityIdentifier("effectFocusRange")
                        }
                        // The graph's scalar adapter does not edit clip opacity;
                        // effect values stay in their existing animation domain.
                        KeyframeGraph(clip: item, property: .opacity, globalTime: (clipStart + .init(seconds: localTime)).seconds, selectedID: selectedKeyID, valueRange: graphRange,
                                      pointIDs: Set(keys.map(\.id)),
                                      animationPoints: keys.map { .init(id: $0.id, time: $0.time, property: .opacity, value: $0.value, easing: $0.easing) },
                                      title: L("Intensité"), evaluate: { time in effect.animatedAmount(at: time - item.globalStart + item.clip.animationOffset) },
                                      timeWindow: focusedWindow,
                                      onScrub: { scrub(($0 - clipStart).seconds) }, onSelect: { selectKey($0.id) }, onMove: movePoint)
                        Slider(value: Binding(get: { localTime }, set: scrub), in: 0...max(0.001, clipDuration.seconds))
                            .tint(DesignTokens.amber).accessibilityLabel(L("Parcourir l’animation")).accessibilityIdentifier("keyframeTimeSlider")
                        interpolationControl
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
                    }.padding(.bottom, 6)
                    }.listRowBackground(DesignTokens.ink)
                        if effect.kind == .neon {
                            Section(EFL("Halo du néon", "Neon glow")) { coloredEffectControls }
                        }
                        if effect.kind == .lightSweep {
                            Section(EFL("Reflet lumineux", "Light reflection")) { coloredEffectControls }
                        }
                        if effect.kind == .liquidDistortion {
                            Section(EFL("Ondulations", "Waves")) {
                                parameterSlider(title: EFL("Vitesse des ondes", "Wave speed"), value: Binding(get: { draft?.liquidFlowSpeed ?? 1 }, set: { value in changeDraft { $0.liquidSpeed = value } }), range: 0.25...2, identifier: "liquidFlowSpeed", percentage: false)
                            }
                        }
                        if effect.kind == .directionalBlur {
                            Section(EFL("Direction du flou", "Blur direction")) {
                                parameterSlider(title: EFL("Angle", "Angle"), value: Binding(get: { draft?.directionalBlurAngle ?? 45 }, set: { value in changeDraft { $0.blurAngle = value } }), range: -180...180, identifier: "directionalBlurAngle", suffix: "°")
                                HStack {
                                    ForEach([0.0, 45, 90], id: \.self) { angle in
                                        Button { changeDraft { $0.blurAngle = angle } } label: {
                                            parameterChoice("\(Int(angle))°", selected: effect.directionalBlurAngle == angle)
                                        }.buttonStyle(.plain)
                                            .accessibilityIdentifier("blurDirection-\(Int(angle))")
                                            .accessibilityAddTraits(effect.directionalBlurAngle == angle ? .isSelected : [])
                                    }
                                }
                            }
                        }
                        if effect.kind == .popHalftone {
                            Section(EFL("Points d’impression", "Print dots")) {
                                parameterSlider(title: EFL("Taille des points", "Dot size"), value: Binding(get: { draft?.halftoneDotScale ?? 0.45 }, set: { value in changeDraft { $0.dotScale = value } }), range: 0...1, identifier: "halftoneDotScale")
                            }
                        }
                        if effect.kind == .duotone {
                            Section(EFL("Palette à deux couleurs", "Two-color palette")) {
                                HStack(spacing: 10) {
                                    ForEach([("#152A62", "#FFB5DA"), ("#163A32", "#F8DA78"), ("#401E5A", "#91F4FF")], id: \.0) { dark, light in
                                        Button { changeDraft { $0.colorHex = dark; $0.secondaryColorHex = light } } label: {
                                            HStack(spacing: 0) { Color(hex: dark); Color(hex: light) }
                                                .frame(width: 48, height: 28).clipShape(Capsule())
                                                .overlay(Capsule().stroke(effect.colorHex == dark && effect.secondaryColorHex == light ? DesignTokens.amber : .clear, lineWidth: 2))
                                                .frame(width: 60, height: 44)
                                        }.buttonStyle(.plain).accessibilityLabel("\(dark), \(light)").accessibilityIdentifier("duotonePalette-\(dark)")
                                            .accessibilityAddTraits(effect.colorHex == dark && effect.secondaryColorHex == light ? .isSelected : [])
                                    }
                                    Button { changeDraft { let dark = $0.colorHex ?? "#152A62"; $0.colorHex = $0.secondaryColorHex ?? "#FFB5DA"; $0.secondaryColorHex = dark } } label: { Image(systemName: "arrow.left.arrow.right").frame(width: 44, height: 44) }
                                        .accessibilityLabel(EFL("Inverser les couleurs", "Swap colors")).accessibilityIdentifier("swapDuotoneColors")
                                }
                                ColorPicker(EFL("Ombres", "Shadows"), selection: effectColor(secondary: false), supportsOpacity: false)
                                ColorPicker(EFL("Hautes lumières", "Highlights"), selection: effectColor(secondary: true), supportsOpacity: false)
                            }
                        }
                        if effect.kind == .ghostTrail {
                            Section(EFL("Images précédentes", "Previous frames")) {
                                Stepper(value: Binding(get: { draft?.ghostCount ?? 3 }, set: { value in changeDraft { $0.echoCount = value } }), in: 1...5) {
                                    Text(EFL("Images fantômes", "Ghost frames") + " : \(draft?.ghostCount ?? 3)")
                                }.accessibilityIdentifier("ghostCount")
                                parameterSlider(title: EFL("Espacement", "Spacing"), value: Binding(get: { draft?.ghostSpacing ?? 0.12 }, set: { value in changeDraft { $0.echoSpacing = value } }), range: 1.0 / 60...0.4, identifier: "ghostSpacing", percentage: false, suffix: " s", fractionDigits: 2)
                                parameterSlider(title: EFL("Persistance", "Persistence"), value: Binding(get: { draft?.ghostDecay ?? 0.55 }, set: { value in changeDraft { $0.echoDecay = value } }), range: 0.1...0.85, identifier: "ghostDecay")
                            }
                        }
                        if effect.kind == .stopMotion {
                            Section(EFL("Cadence du calque", "Layer frame rate")) {
                                HStack {
                                    ForEach([4.0, 8, 12, 24], id: \.self) { fps in
                                        Button { changeDraft { $0.heldFrameRate = fps } } label: {
                                            parameterChoice("\(Int(fps)) fps", selected: effect.stopMotionFrameRate == fps)
                                        }.buttonStyle(.plain)
                                            .accessibilityIdentifier("heldFPS-\(Int(fps))").accessibilityAddTraits(effect.stopMotionFrameRate == fps ? .isSelected : [])
                                    }
                                }
                                Stepper(value: Binding(get: { Int(draft?.stopMotionFrameRate ?? 8) }, set: { value in changeDraft { $0.heldFrameRate = Double(value) } }), in: 2...24) {
                                    Text("\(Int(draft?.stopMotionFrameRate ?? 8)) fps")
                                }.accessibilityIdentifier("heldFrameRate")
                                Text(EFL("À intensité maximale, l’image et la pose sont maintenues entre deux pas. L’audio et les autres pistes restent fluides.", "At full intensity, the image and pose are held between steps. Audio and other tracks stay smooth.")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
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
                            Text(EFL("L’interpolation règle l’arrivée vers le point sélectionné. Le premier point fixe le départ.", "Interpolation controls the approach to the selected keyframe. The first keyframe sets the starting value."))
                                .font(.caption).foregroundStyle(.secondary)
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
                }
            }.buttonStyle(.borderless).scrollDismissesKeyboard(.interactively).accessibilityIdentifier("effectSettings")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { availableHeight = $0 }
                .navigationTitle(draft.map { effectLabel($0.kind.rawValue) } ?? L("Effets")).navigationBarTitleDisplayMode(.inline)
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
        }.presentationSizing(.page).presentationDetents([.large])
            .preferredColorScheme(.dark).onAppear(perform: load).task(id: previewKey) { await render() }
    }

    private func setPreviewHeight(_ value: CGFloat) {
        var transaction = Transaction(); transaction.animation = nil
        withTransaction(transaction) { previewHeight = min(previewHeightRange.upperBound, max(previewHeightRange.lowerBound, value)) }
    }

    private var interpolationControl: some View {
        HStack {
            Text(L("Interpolation"))
            Spacer()
            Picker(L("Interpolation"), selection: $easing) {
                ForEach(KeyframeEasing.allCases, id: \.self) { Text(animationEasingLabel($0)).tag($0) }
            }.pickerStyle(.menu).labelsHidden()
                .accessibilityIdentifier("effectEasing").accessibilityValue(animationEasingLabel(easing))
                .disabled(selectedKeyID == nil || selectedKeyID == keys.first?.id).onChange(of: easing) { _, value in
                    guard let selectedKeyID, selectedKeyID != keys.first?.id else { return }
                    changeDraft { effect in
                        if let index = effect.amountKeyframes?.firstIndex(where: { $0.id == selectedKeyID }) { effect.amountKeyframes?[index].easing = value }
                    }
                }
        }.font(.caption).frame(minHeight: 44)
    }

    private var coloredEffectControls: some View {
        Group {
            HStack(spacing: 8) {
                ForEach(draft?.kind == .neon ? ["#49E6FF", "#FF48D7", "#A6FF45", "#FFBC47", "#FFFFFF"] : ["#FFD58A", "#FFFFFF", "#49E6FF", "#FF48D7", "#A6FF45"], id: \.self) { hex in
                    Button { changeDraft { $0.colorHex = hex } } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 24, height: 24)
                            .overlay { if draft?.colorHex == hex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black) } }
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(hex).accessibilityIdentifier("\(draft?.kind == .neon ? "neonColor" : "effectColor")-\(hex)").accessibilityAddTraits(draft?.colorHex == hex ? .isSelected : [])
                }
            }.accessibilityElement(children: .contain)
            if draft?.kind == .neon {
                parameterSlider(title: EFL("Étendue du halo", "Glow spread"), value: Binding(get: { draft?.neonGlowRadius ?? 0.45 }, set: { value in changeDraft { $0.glowRadius = value } }), range: 0...1, identifier: "neonGlowRadius")
            } else {
                parameterSlider(title: EFL("Largeur du reflet", "Reflection width"), value: Binding(get: { draft?.lightSweepWidth ?? 0.35 }, set: { value in changeDraft { $0.sweepWidth = value } }), range: 0...1, identifier: "lightSweepWidth")
            }
            ColorPicker(EFL("Personnaliser", "Custom color"), selection: Binding(get: { Color(hex: draft?.colorHex ?? (draft?.kind == .neon ? "#49E6FF" : "#FFD58A")) }, set: { color in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
                changeDraft { $0.colorHex = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }
            }), supportsOpacity: false)
        }
    }

    private func effectColor(secondary: Bool) -> Binding<Color> {
        Binding(get: { Color(hex: secondary ? (draft?.secondaryColorHex ?? "#FFB5DA") : (draft?.colorHex ?? "#152A62")) }, set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            let hex = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
            changeDraft { if secondary { $0.secondaryColorHex = hex } else { $0.colorHex = hex } }
        })
    }

    private func parameterSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, identifier: String, percentage: Bool = true, suffix: String? = nil, fractionDigits: Int = 0) -> some View {
        let label = suffix.map { String(format: "%.*f%@", fractionDigits, value.wrappedValue, $0) } ?? (percentage ? "\(Int((value.wrappedValue * 100).rounded())) %" : String(format: "%.2f ×", value.wrappedValue))
        return VStack(spacing: 2) {
            HStack { Text(title); Spacer(); Text(label).monospacedDigit().foregroundStyle(DesignTokens.amber) }.font(.caption)
            Slider(value: value, in: range, onEditingChanged: editGesture)
                .accessibilityLabel(title).accessibilityIdentifier(identifier).accessibilityValue(label)
        }.frame(minHeight: 48)
    }

    private func parameterChoice(_ title: String, selected: Bool) -> some View {
        Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            .foregroundStyle(selected ? DesignTokens.ink : Color.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? DesignTokens.amber : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func load() {
        guard snapshot == nil, let clip = model.selectedClip, let effect = clip.effects.first(where: { $0.id == effectID }) else { return }
        model.stop(); snapshot = model.document; draft = effect; clipID = clip.id
        scrub(min(max(0, model.playhead - clipStart.seconds), max(0, clipDuration.seconds - 1 / 60_000)))
        if effect.kind == .lightSweep || effect.kind == .lensPulse, let start = effect.start, let duration = effect.duration {
            // Show the reflection itself on entry rather than the empty beginning of its pass.
            scrub((start - animationOffset).seconds + duration.seconds * 0.5)
        } else if isBurst, let start = effect.start, effect.evaluatedAmount(at: animationTime) == nil {
            scrub((start - animationOffset).seconds)
        }
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

private func effectDescription(_ kind: EffectKind) -> String? {
    switch kind {
    case .impactZoom: EFL("Zoom rapide, secousse et flou radial.", "Quick zoom, shake and radial blur.")
    case .shortGlitch: EFL("Décalages en bandes et séparation des couleurs sur une courte rafale.", "Band shifts and color separation in a short burst.")
    case .neon: EFL("Contour lumineux et halo diffus. Réglez son étendue indépendamment de l’intensité.", "Luminous outline with a soft glow. Adjust its spread independently of intensity.")
    case .dream: EFL("Lumière douce, détails adoucis et couleurs pastel. L’intensité reste animable.", "Soft light, softened details and pastel colors. Intensity can be animated.")
    case .lightSweep: EFL("Reflet mobile : couleur et largeur réglables. La plage définit sa durée.", "Moving reflection: adjustable color and width. The time range sets its duration.")
    case .liquidDistortion: EFL("Ondulations animées, comme une image vue à travers l’eau. Réglez l’intensité et la vitesse des ondes.", "Animated ripples, like an image seen through water. Adjust intensity and wave speed.")
    case .directionalBlur: EFL("Étire les détails dans une direction. Choisissez l’angle, puis animez l’intensité pour une montée de vitesse.", "Smears details in one direction. Choose the angle, then animate intensity for a burst of speed.")
    case .popHalftone: EFL("Transforme les tons en points d’impression. Réglez la taille des points et mélangez le résultat avec l’image d’origine.", "Turns tones into printed dots. Adjust dot size and blend the result with the original image.")
    case .duotone: EFL("Remplace les tons sombres et clairs par deux couleurs. Choisissez une palette, personnalisez-la ou inversez les couleurs.", "Maps dark and light tones to two colors. Choose a palette, customize it or swap the colors.")
    case .lensPulse: EFL("Une déformation de lentille sur toute l’image accompagne une impulsion de zoom. Modifiez les trois points pour régler l’impact et le retour.", "A full-image lens distortion accompanies a zoom pulse. Edit the three keyframes to shape the impact and return.")
    case .ghostTrail: EFL("Superpose jusqu’à cinq images précédentes, avec espacement et persistance réglables. Visible sur une vidéo en mouvement ou un calque animé ; calcul plus long.", "Blends up to five previous frames, with adjustable spacing and persistence. Visible on moving video or an animated layer; rendering takes longer.")
    case .stopMotion: EFL("Maintient les images du calque à une cadence réduite. Le montage conserve sa durée et sa cadence d’export.", "Holds the layer’s frames at a lower rate. Montage duration and export frame rate stay unchanged.")
    default: nil
    }
}
