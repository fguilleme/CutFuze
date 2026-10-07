import SwiftUI
import UIKit

enum ContextTool: String, Identifiable {
    case speed = "Vitesse"
    case volume = "Volume"
    case fade = "Fondu"
    case adjust = "Ajuster"
    case animation = "Animation"
    case textEdit = "Modifier"
    case textStyle = "Style"
    case font = "Police"
    case effects = "Effets"
    case opacity = "Opacité"
    case transform = "Transformer"
    var id: String { rawValue }
}

struct ContextToolPanel: View {
    @ObservedObject var model: EditorModel
    let tool: ContextTool
    let close: () -> Void
    let showTiming: () -> Void
    @State private var textDraft = ""
    @State private var showCaptions = false
    @State private var showKeyframes = false
    @State private var editingEffect: EffectInstance?
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L(tool.rawValue)).font(.subheadline.weight(.semibold))
                if model.localScope, tool == .adjust || tool == .opacity || tool == .transform {
                    Text("\(Int(model.variant.widthRatio)):\(Int(model.variant.heightRatio))")
                        .font(.caption2.weight(.bold)).foregroundStyle(DesignTokens.amber)
                }
                Spacer()
                if tool == .adjust || tool == .opacity || tool == .transform {
                    Menu {
                        Button(L("Tous les formats")) { model.localScope = false }
                        Button("\(Int(model.variant.widthRatio)):\(Int(model.variant.heightRatio)) \(L("seulement"))") { model.localScope = true }
                    } label: {
                        Image(systemName: "rectangle.3.group").frame(width: 40, height: 36)
                    }.accessibilityLabel(L("Formats concernés"))
                }
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 36) }
                    .accessibilityLabel(L("Fermer"))
                    .accessibilityIdentifier("closeContextTool")
            }
            Group {
                if let clip = model.selectedClip { controls(for: clip) }
                else { Text(L("Aucun élément sélectionné")).foregroundStyle(DesignTokens.muted) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
        case .adjust:
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button(L("Ajuster")) { model.changePresentation { $0.fill = false } }.buttonStyle(.bordered)
                    Button(L("Remplir")) { model.changePresentation { $0.fill = true } }.buttonStyle(.bordered)
                    Toggle(L("Miroir"), isOn: presentationBool(\.mirror)).font(.caption).frame(minHeight: 44)
                    Spacer()
                    Button(L("Réinitialiser"), action: model.resetPresentation).font(.caption).frame(minHeight: 44)
                }
                ValueSlider(title: L("Échelle"), value: presentation(\.scale), range: 0.1...4, editing: gesture)
            }
        case .animation:
            HStack(spacing: 10) {
                Label("\(clip.keyframes.count)", systemImage: "diamond.fill").foregroundStyle(DesignTokens.amber)
                Button(L("Ajouter ou mettre à jour la pose")) { upsertPose(clip) }.buttonStyle(.bordered).frame(minHeight: 44)
                Button(L("Modifier les images clés")) { showKeyframes = true }.buttonStyle(.bordered).frame(minHeight: 44)
            }.font(.caption)
        case .textEdit:
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
        case .textStyle:
            VStack(spacing: 6) {
                CompactValueSlider(title: L("Taille"), value: presentation(\.textSize), range: 0.02...0.2, step: 0.01, editing: gesture)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Couleur")).font(.caption2)
                        HStack(spacing: 1) {
                            ForEach(["#FFFFFF", "#15191F", "#EBA65A", "#A0C9BD"], id: \.self) { hex in
                                Button { model.changePresentation { $0.color = hex } } label: {
                                    Circle().fill(Color(hex: hex)).frame(width: 24, height: 24)
                                        .overlay { Circle().strokeBorder(model.presentation.color == hex ? DesignTokens.amber : .white.opacity(0.35), lineWidth: 2) }
                                        .frame(width: 38, height: 38)
                                }.accessibilityLabel(hex)
                            }
                        }
                    }
                    VStack(spacing: 4) {
                        CompactInlineSlider(title: L("Contour"), value: presentation(\.textOutline), range: 0...0.1)
                        CompactInlineSlider(title: L("Fond"), value: presentation(\.textBackgroundOpacity), range: 0...1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        case .font:
            VStack(spacing: 8) {
                Picker(L("Police"), selection: Binding(get: { model.presentation.textFont }, set: { value in model.changePresentation { $0.textFont = value } })) {
                    Text(L("Système")).tag("system")
                    ForEach(["Georgia", "Georgia-Bold", "Menlo-Regular", "Menlo-Bold"].filter { UIFont(name: $0, size: 16) != nil }, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
                HStack {
                    Toggle(L("Gras"), isOn: presentationBool(\.textBold)).frame(maxWidth: 110)
                    Picker(L("Alignement"), selection: Binding(get: { model.presentation.textAlignment }, set: { value in model.changePresentation { $0.textAlignment = value } })) {
                        Text(L("Gauche")).tag("left"); Text(L("Centre")).tag("center"); Text(L("Droite")).tag("right")
                    }.pickerStyle(.segmented)
                }
            }
        case .effects:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(EffectKind.allCases, id: \.self) { kind in
                            Button(effectLabel(kind.rawValue)) { model.changeClip(L("Effets")) { $0.effects.append(.init(kind: kind, amount: 0.3)) } }
                        }
                    } label: { Label(L("Ajouter"), systemImage: "plus").frame(minHeight: 44) }.buttonStyle(.bordered)
                    ForEach(clip.effects) { effect in
                        Button { editingEffect = effect } label: {
                            HStack(spacing: 6) { Text(effectLabel(effect.kind.rawValue)); Text("\(Int(effect.amount * 100)) %").foregroundStyle(DesignTokens.amber) }
                                .font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(height: 44).background(DesignTokens.ink, in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                    if clip.effects.isEmpty { Text(L("Aucun effet appliqué")).font(.caption).foregroundStyle(DesignTokens.muted) }
                }
            }
        case .opacity:
            ValueSlider(title: L("Opacité"), value: presentation(\.opacity), range: 0...1, editing: gesture)
        case .transform:
            VStack(spacing: 4) {
                ValueSlider(title: L("Horizontal"), value: presentation(\.x), range: -0.5...1.5, editing: gesture)
                ValueSlider(title: L("Vertical"), value: presentation(\.y), range: -0.5...1.5, editing: gesture)
                ValueSlider(title: L("Rotation"), value: presentation(\.rotation), range: -180...180, suffix: "°", editing: gesture)
            }
        }
    }

    private func presentation(_ key: WritableKeyPath<Presentation, Double>) -> Binding<Double> {
        Binding(get: { model.presentation[keyPath: key] }, set: { value in model.changePresentation { $0[keyPath: key] = value } })
    }
    private func presentationBool(_ key: WritableKeyPath<Presentation, Bool>) -> Binding<Bool> {
        Binding(get: { model.presentation[keyPath: key] }, set: { value in model.changePresentation { $0[keyPath: key] = value } })
    }
    private func gesture(_ active: Bool) { if active { model.beginGesture(L(tool.rawValue)) } else { model.endGesture() } }
    private func upsertPose(_ clip: Clip) {
        guard let rendered = model.plan.clips.first(where: { $0.id == clip.id }) else { return }
        let time = min(max(MediaTime(seconds: model.playhead), rendered.globalStart), rendered.end)
        model.edit(L("Images clés")) { try AnimationEditing.upsertCurrentPose(clipID: clip.id, at: time, variantID: model.variantID, in: &$0) }
    }
}

struct CompactValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var editing: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.3f", value))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.amber)
            }
            .font(.caption)
            HStack(spacing: 4) {
                if let step {
                    Button { value = max(range.lowerBound, value - step) } label: {
                        Image(systemName: "minus").frame(width: 36, height: 28)
                    }
                    .accessibilityLabel(L("Réduire") + " " + title.lowercased())
                    .accessibilityIdentifier("decrease-\(title)")
                }
                SmallThumbSlider(title: title, value: $value, range: range, editing: editing)
                    .frame(height: 28)
                if let step {
                    Button { value = min(range.upperBound, value + step) } label: {
                        Image(systemName: "plus").frame(width: 36, height: 28)
                    }
                    .accessibilityLabel(L("Augmenter") + " " + title.lowercased())
                    .accessibilityIdentifier("increase-\(title)")
                }
            }
        }
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
