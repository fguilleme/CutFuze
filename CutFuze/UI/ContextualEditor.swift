import SwiftUI
import UIKit

enum ContextTool: String, Identifiable {
    case speed = "Vitesse"
    case volume = "Volume"
    case fade = "Fondu"
    case animation = "Animation"
    case textEdit = "Modifier"
    case textStyle = "Style"
    case font = "Police"
    case visual = "Effets visuels"
    var id: String { rawValue }
}

enum VisualTool: String, CaseIterable, Identifiable {
    case transform = "Transformer"
    case opacity = "Opacité"
    case mask = "Masque"
    case beauty = "Beauté"
    case geometry = "Géométrie"
    case creative = "Créatif"
    case light = "Lumière"
    var id: String { rawValue }
    fileprivate var effectCategory: EffectCategory? {
        switch self {
        case .beauty: .beauty
        case .geometry: .geometry
        case .creative: .creative
        case .light: .light
        default: nil
        }
    }
}

fileprivate enum EffectCategory: String, CaseIterable, Identifiable {
    case beauty = "Beauté"
    case geometry = "Géométrie"
    case creative = "Créatif"
    case light = "Lumière"
    var id: String { rawValue }

    var effects: [EffectKind] {
        switch self {
        case .beauty: [.skinSmooth, .skinGlow, .sharpness]
        case .geometry: [.bulge, .pinch, .twirl, .kaleidoscope, .pixelate]
        case .creative: [.comic, .crystallize, .glow, .rgbSplit, .shake, .retro, .grain, .vignette, .blur, .fade]
        case .light: [.exposure, .brightness, .contrast, .saturation, .temperature, .tint, .highlights, .shadows]
        }
    }
}

struct ContextToolPanel: View {
    @ObservedObject var model: EditorModel
    let tool: ContextTool
    @Binding var visualTool: VisualTool
    let close: () -> Void
    let showTiming: () -> Void
    @State private var textDraft = ""
    @State private var showCaptions = false
    @State private var showKeyframes = false
    @State private var editingEffect: EffectInstance?
    @State private var animationZone: MotionAnimationZone = .entrance
    @FocusState private var textFocused: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var controlsViewportHeight: CGFloat {
        if tool == .font { return verticalSizeClass == .compact ? 130 : 232 }
        if tool == .visual { return verticalSizeClass == .compact ? 96 : 144 }
        if tool == .animation { return verticalSizeClass == .compact ? 108 : 122 }
        return verticalSizeClass == .compact ? 56 : 94
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L(tool.rawValue)).font(.subheadline.weight(.semibold))
                Button(action: close) {
                    Text("×")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: tool == .visual ? 44 : 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Fermer"))
                .accessibilityIdentifier("closeContextTool")
                Spacer()
                if model.localScope, tool == .visual, visualTool.effectCategory == nil {
                    Text("\(Int(model.variant.widthRatio)):\(Int(model.variant.heightRatio))")
                        .font(.caption2.weight(.bold)).foregroundStyle(DesignTokens.amber)
                }
                if tool == .visual, visualTool.effectCategory == nil {
                    Menu {
                        Button(L("Tous les formats")) { model.localScope = false }
                        Button("\(Int(model.variant.widthRatio)):\(Int(model.variant.heightRatio)) \(L("seulement"))") { model.localScope = true }
                    } label: {
                        Image(systemName: "rectangle.3.group").frame(width: 44, height: tool == .visual ? 44 : 36)
                    }.accessibilityLabel(L("Formats concernés"))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: tool == .visual ? 44 : 36)
            if tool == .visual {
                ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(VisualTool.allCases) { item in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                visualTool = item
                            } label: {
                                HStack(spacing: 4) {
                                    Text(L(item.rawValue))
                                    if let category = item.effectCategory, let clip = model.selectedClip {
                                        let count = clip.effects.filter { category.effects.contains($0.kind) }.count
                                        if count > 0 { Text("\(count)").monospacedDigit().foregroundStyle(DesignTokens.amber) }
                                    }
                                }.font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).frame(height: 44)
                                    .background(visualTool == item ? DesignTokens.amber.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("visualTool-\(item.rawValue)")
                                .accessibilityAddTraits(visualTool == item ? .isSelected : [])
                                .id(item.id)
                        }
                    }
                }.frame(height: 44).accessibilityIdentifier("visualTools")
                    .onAppear { proxy.scrollTo(visualTool.id, anchor: .center) }
                    .onChange(of: visualTool) { _, item in proxy.scrollTo(item.id, anchor: .center) }
                }
            }
            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    if let clip = model.selectedClip { controls(for: clip) }
                    else { Text(L("Aucun élément sélectionné")).foregroundStyle(DesignTokens.muted) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: controlsViewportHeight)
            .clipped()
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("contextToolScroll")
            .id(tool == .visual ? visualTool.rawValue : tool.rawValue)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
        .background(DesignTokens.panel)
        .sheet(isPresented: $showCaptions) { CaptionEditorSheet(model: model) }
        .sheet(isPresented: $showKeyframes) { KeyframeEditorSheet(model: model) }
        .sheet(item: $editingEffect) { effect in EffectEditorSheet(model: model, effectID: effect.id) }
        .onAppear { textDraft = model.selectedClip?.text ?? "" }
        .onChange(of: model.selectedClipID) { _, _ in textDraft = model.selectedClip?.text ?? ""; textFocused = false }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(L("Terminé")) { textFocused = false } } }
    }

    @ViewBuilder private func controls(for clip: Clip) -> some View {
        switch tool {
        case .speed:
            VStack(spacing: 5) {
                ValueSlider(title: L("Vitesse"), value: Binding(get: { model.selectedClip?.speed ?? 1 }, set: { value in model.changeClip(L("Vitesse")) { $0.speed = value; $0.duration = $0.sourceDuration / value } }), range: 0.1...4, suffix: "×", editing: gesture)
                HStack(spacing: 8) {
                    ForEach([0.5, 1.0, 2.0], id: \.self) { value in
                        Button("\(value, specifier: "%g")×") { model.changeClip(L("Vitesse")) { $0.speed = value; $0.duration = $0.sourceDuration / value } }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                    }
                    Spacer()
                    Button(L("Réglage précis"), action: showTiming).buttonStyle(.bordered).frame(minHeight: 44)
                }.font(.caption)
            }
        case .volume:
            VStack(spacing: 8) {
                ValueSlider(title: L("Volume"), value: Binding(get: { model.selectedClip?.volume ?? 1 }, set: { value in model.changeClip(L("Volume")) { $0.volume = value } }), range: 0...2, editing: gesture)
                Toggle(L("Muet"), isOn: Binding(get: { model.selectedClip?.muted ?? false }, set: { value in model.changeClip(L("Muet")) { $0.muted = value } })).frame(minHeight: 44)
            }
        case .fade:
            VStack(spacing: 5) {
                ValueSlider(title: L("Fondu entrant"), value: Binding(get: { model.selectedClip?.fadeIn.seconds ?? 0 }, set: { value in model.changeClip(L("Fondu entrant")) { $0.fadeIn = .init(seconds: value) } }), range: 0...max(0.1, clip.duration.seconds / 2), suffix: "s", editing: gesture)
                ValueSlider(title: L("Fondu sortant"), value: Binding(get: { model.selectedClip?.fadeOut.seconds ?? 0 }, set: { value in model.changeClip(L("Fondu sortant")) { $0.fadeOut = .init(seconds: value) } }), range: 0...max(0.1, clip.duration.seconds / 2), suffix: "s", editing: gesture)
            }
        case .visual:
            visualControls(for: clip)
        case .animation:
            animationControls(for: clip)
        case .textEdit:
            textEditControls(for: clip)
        case .textStyle:
            textStyleControls
        case .font:
            fontControls
        }
    }

    @ViewBuilder private func visualControls(for clip: Clip) -> some View {
        switch visualTool {
        case .transform:
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    if clip.kind == .image || clip.kind == .video {
                    mediaFitButton(fill: false, title: L("Ajuster"), identifier: "fitMedia")
                    mediaFitButton(fill: true, title: L("Remplir"), identifier: "fillMedia")
                    }
                    Toggle(L("Miroir"), isOn: presentationBool(\.mirror))
                        .font(.caption2)
                        .fixedSize()
                        .frame(minHeight: 44)
                    Spacer(minLength: 0)
                    Button(action: model.resetPresentation) {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L("Réinitialiser"))
                }
                ValueSlider(title: L("Échelle"), value: presentation(\.scale), range: 0.1...4, editing: gesture)
                ValueSlider(title: L("Horizontal"), value: presentation(\.x), range: -0.5...1.5, editing: gesture)
                ValueSlider(title: L("Vertical"), value: presentation(\.y), range: -0.5...1.5, editing: gesture)
                ValueSlider(title: L("Rotation"), value: presentation(\.rotation), range: -180...180, suffix: "°", editing: gesture)
            }
        case .opacity:
            ValueSlider(title: L("Opacité"), value: presentation(\.opacity), range: 0...1, editing: gesture)
        case .mask:
            VStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(MaskKind.allCases, id: \.self) { kind in
                            Button { model.changePresentation { $0.mask = kind } } label: {
                                Text(effectLabel(kind.rawValue)).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).frame(height: 44)
                                    .background(model.presentation.mask == kind ? DesignTokens.amber.opacity(0.18) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityIdentifier("mask-\(kind.rawValue)")
                                .accessibilityAddTraits(model.presentation.mask == kind ? .isSelected : [])
                        }
                    }
                }
                if model.presentation.mask != .none {
                    ValueSlider(title: L("Largeur du masque"), value: presentation(\.maskWidth), range: 0.05...1.5, editing: gesture)
                    ValueSlider(title: L("Hauteur du masque"), value: presentation(\.maskHeight), range: 0.05...1.5, editing: gesture)
                    ValueSlider(title: L("Position X du masque"), value: presentation(\.maskX), range: 0...1, editing: gesture)
                    ValueSlider(title: L("Position Y du masque"), value: presentation(\.maskY), range: 0...1, editing: gesture)
                    ValueSlider(title: L("Rotation du masque"), value: presentation(\.maskRotation), range: -180...180, suffix: "°", editing: gesture)
                    ValueSlider(title: L("Contour progressif"), value: presentation(\.maskFeather), range: 0...0.2, editing: gesture)
                    Toggle(L("Inverser le masque"), isOn: presentationBool(\.maskInverted)).font(.caption)
                }
            }
        case .beauty, .geometry, .creative, .light:
            effectControls(for: clip)
        }
    }

    private func animationControls(for clip: Clip) -> some View {
            VStack(spacing: 6) {
                Picker(L("Moment de l’animation"), selection: $animationZone) {
                    Text(L("Entrée")).tag(MotionAnimationZone.entrance)
                    Text(L("Sortie")).tag(MotionAnimationZone.exit)
                    Text(L("Boucle")).tag(MotionAnimationZone.loop)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("animationZone")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(AnimationEditing.presets(for: animationZone), id: \.self) { preset in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                model.edit(L("Animation")) { try AnimationEditing.applyPreset(preset, zone: animationZone, clipID: clip.id, in: &$0) }
                            } label: {
                                Label(L(animationPresetLabel(preset)), systemImage: animationPresetSymbol(preset))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .frame(height: 38)
                                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("animationPreset-\(preset.rawValue)")
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text(clip.keyframes.isEmpty ? L("Aucune animation") : "\(clip.keyframes.count) \(L("points d’animation"))")
                        .font(.caption2).foregroundStyle(DesignTokens.muted)
                    Spacer()
                    if !clip.keyframes.isEmpty {
                        Button(L("Effacer")) { model.changeClip(L("Animation")) { $0.keyframes.removeAll() } }
                            .font(.caption).foregroundStyle(.red)
                    }
                    Button(L("Éditer les points")) { showKeyframes = true }
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("advancedAnimation")
                }
            }
    }

    private func textEditControls(for clip: Clip) -> some View {
            VStack(spacing: 7) {
                TextField(L("Texte du calque"), text: $textDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...2).focused($textFocused)
                    .accessibilityIdentifier("layerTextField")
                HStack {
                    if clip.isCaption { Button(L("Modifier les sous-titres")) { showCaptions = true }.buttonStyle(.bordered) }
                    Spacer()
                    Button(L("Mettre à jour")) { textFocused = false; model.changeClip(L("Texte")) { $0.text = textDraft } }
                        .buttonStyle(.borderedProminent).tint(DesignTokens.amber).foregroundStyle(DesignTokens.ink)
                        .disabled(textDraft == clip.text)
                }.font(.caption)
            }
    }

    private var textStyleControls: some View {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    CompactTextSizeStepper(title: L("Taille"), value: presentation(\.textSize), range: 0.02...0.2)
                    Spacer(minLength: 0)
                    HStack(spacing: 1) {
                        ForEach(["#FFFFFF", "#15191F", "#EBA65A", "#A0C9BD"], id: \.self) { hex in
                            Button { model.changeSelectedTextPresentation { $0.color = hex } } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 24, height: 24)
                                    .overlay { Circle().strokeBorder(model.presentation.color == hex ? DesignTokens.amber : .white.opacity(0.35), lineWidth: 2) }
                                    .frame(width: 38, height: 38)
                            }.accessibilityLabel(hex)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(L("Couleur"))
                }
                HStack(spacing: 12) {
                    CompactInlineSlider(title: L("Contour"), value: presentation(\.textOutline), range: 0...0.1)
                    CompactInlineSlider(title: L("Fond"), value: presentation(\.textBackgroundOpacity), range: 0...1)
                }
            }
    }

    private var fontControls: some View {
            VStack(spacing: 8) {
                TextFontPicker(selectedFont: Binding(get: { model.presentation.textFont }, set: { value in model.changeSelectedTextPresentation { $0.textFont = value } }))
                HStack {
                    Toggle(L("Gras"), isOn: presentationBool(\.textBold)).frame(maxWidth: 110)
                    Picker(L("Alignement"), selection: Binding(get: { model.presentation.textAlignment }, set: { value in model.changeSelectedTextPresentation { $0.textAlignment = value } })) {
                        Text(L("Gauche")).tag("left"); Text(L("Centre")).tag("center"); Text(L("Droite")).tag("right")
                    }.pickerStyle(.segmented)
                }
            }
    }

    private func effectControls(for clip: Clip) -> some View {
        let category = visualTool.effectCategory ?? .beauty
        return
            VStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(category.effects, id: \.self) { kind in
                            let applied = clip.effects.first { $0.kind == kind }
                            Button { selectEffect(kind, from: clip) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: effectSymbol(kind))
                                    Text(effectLabel(kind.rawValue))
                                    if applied != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignTokens.amber) }
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).frame(height: 40)
                                .background(applied == nil ? Color.white.opacity(0.07) : DesignTokens.amber.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("effect-\(kind.rawValue)")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
    }

    private func mediaFitButton(fill: Bool, title: String, identifier: String) -> some View {
        let selected = model.presentation.fill == fill
        return Button { model.setMediaFill(fill) } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? DesignTokens.ink : Color.white.opacity(0.88))
                .frame(width: 68, height: 32)
                .background(selected ? DesignTokens.amber : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selected ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
                }
                .frame(width: 68, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func presentation(_ key: WritableKeyPath<Presentation, Double>) -> Binding<Double> {
        Binding(get: { model.presentation[keyPath: key] }, set: { value in
            if tool == .textStyle { model.changeSelectedTextPresentation { $0[keyPath: key] = value } }
            else { model.changePresentation { $0[keyPath: key] = value } }
        })
    }
    private func presentationBool(_ key: WritableKeyPath<Presentation, Bool>) -> Binding<Bool> {
        Binding(get: { model.presentation[keyPath: key] }, set: { value in
            if tool == .font { model.changeSelectedTextPresentation { $0[keyPath: key] = value } }
            else { model.changePresentation { $0[keyPath: key] = value } }
        })
    }
    private func gesture(_ active: Bool) { if active { model.beginGesture(L(tool.rawValue)) } else { model.endGesture() } }
    private func upsertPose(_ clip: Clip) {
        guard let rendered = model.plan.clips.first(where: { $0.id == clip.id }) else { return }
        let time = min(max(MediaTime(seconds: model.playhead), rendered.globalStart), rendered.end)
        model.edit(L("Images clés")) { try AnimationEditing.upsertCurrentPose(clipID: clip.id, at: time, variantID: model.variantID, in: &$0) }
    }

    private func selectEffect(_ kind: EffectKind, from clip: Clip) {
        if let applied = clip.effects.first(where: { $0.kind == kind }) {
            editingEffect = applied
            return
        }
        let effect = EffectInstance(kind: kind, amount: 0.45)
        UISelectionFeedbackGenerator().selectionChanged()
        model.changeClip(L("Effets")) { $0.effects.append(effect) }
        DispatchQueue.main.async { editingEffect = effect }
    }
}

private func animationPresetLabel(_ preset: MotionAnimationPreset) -> String {
    switch preset {
    case .fade: "Fondu"
    case .zoom: "Zoom"
    case .slide: "Glissement"
    case .float: "Flottement"
    case .pulse: "Pulsation"
    case .spin: "Rotation"
    case .shake: "Tremblement"
    }
}

private func animationPresetSymbol(_ preset: MotionAnimationPreset) -> String {
    switch preset {
    case .fade: "circle.lefthalf.filled"
    case .zoom: "arrow.up.left.and.arrow.down.right"
    case .slide: "arrow.right"
    case .float: "arrow.up.and.down"
    case .pulse: "waveform.path.ecg"
    case .spin: "arrow.clockwise"
    case .shake: "waveform.path"
    }
}

private func effectSymbol(_ kind: EffectKind) -> String {
    switch kind {
    case .skinSmooth: "face.smiling"
    case .skinGlow: "sun.max.fill"
    case .bulge, .pinch: "circle.grid.cross"
    case .twirl: "tornado"
    case .kaleidoscope: "hexagon"
    case .comic: "text.bubble"
    case .crystallize: "snowflake"
    case .exposure, .brightness, .highlights, .shadows: "sun.max"
    case .contrast: "circle.lefthalf.filled"
    case .saturation, .temperature, .tint: "paintpalette"
    case .sharpness: "camera.aperture"
    case .vignette: "circle.dashed"
    case .grain: "circle.grid.3x3.fill"
    case .fade: "circle.bottomhalf.filled"
    case .blur: "drop.halffull"
    case .glow: "sparkles"
    case .rgbSplit: "circle.hexagongrid"
    case .pixelate: "square.grid.3x3.fill"
    case .shake: "waveform.path"
    case .retro: "camera.filters"
    }
}

struct CompactTextSizeStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    private let referenceWidth = 320.0

    private var points: Int { Int((value * referenceWidth).rounded()) }

    private func setPoints(_ points: Int) {
        value = min(range.upperBound, max(range.lowerBound, Double(points) / referenceWidth))
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.76))
            Button { setPoints(points - 1) } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.07), in: Circle())
                    .frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(value <= range.lowerBound)
            .accessibilityLabel(L("Réduire") + " " + title.lowercased())
            .accessibilityIdentifier("decrease-\(title)")
            Text("\(points) pt")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DesignTokens.amber)
                .frame(width: 50)
                .accessibilityIdentifier("textSizeValue")
            Button { setPoints(points + 1) } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.07), in: Circle())
                    .frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(value >= range.upperBound)
            .accessibilityLabel(L("Augmenter") + " " + title.lowercased())
            .accessibilityIdentifier("increase-\(title)")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct CompactInlineSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2)
                .frame(width: 46, alignment: .leading)
            SmallThumbSlider(title: title, value: $value, range: range)
                .frame(height: 20)
        }
    }
}

struct SmallThumbSlider: UIViewRepresentable {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var editing: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumTrackTintColor = UIColor(DesignTokens.amber)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.14)
        slider.setThumbImage(Self.thumbImage, for: .normal)
        slider.setThumbImage(Self.thumbImage, for: .highlighted)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.began(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.ended(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.accessibilityLabel = title
        slider.accessibilityValue = String(format: "%.3f", value)
    }

    private static let thumbImage: UIImage = {
        let size = CGSize(width: 18, height: 18)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: rect)
            UIColor(DesignTokens.amber).withAlphaComponent(0.55).setStroke()
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: rect)
        }.withRenderingMode(.alwaysOriginal)
    }()

    final class Coordinator: NSObject {
        var parent: SmallThumbSlider
        init(_ parent: SmallThumbSlider) { self.parent = parent }
        @objc func changed(_ slider: UISlider) { parent.value = Double(slider.value) }
        @objc func began(_ slider: UISlider) { parent.editing(true) }
        @objc func ended(_ slider: UISlider) { parent.editing(false) }
    }
}

struct ContextActionLabel: View {
    let title: String
    let symbol: String
    var destructive = false
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
            Text(L(title)).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .frame(minWidth: 58, minHeight: 54)
        .foregroundStyle(destructive ? Color.red : Color.white.opacity(0.88))
        .contentShape(Rectangle())
    }
}
