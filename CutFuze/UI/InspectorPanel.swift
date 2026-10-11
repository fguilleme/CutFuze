import SwiftUI
import UIKit

struct InspectorPanel: View {
    @ObservedObject var model: EditorModel
    @State private var textDraft = ""
    @State private var showChroma = false
    @State private var editingEffect: EffectInstance?
    @State private var showCaptions = false
    @State private var showKeyframes = false
    @State private var applyStyleToCaptionTrack = true
    @FocusState private var textFieldFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L(model.inspector?.rawValue ?? "Propriétés")).font(.subheadline.bold())
                    Spacer()
                    Button(L("Réinitialiser")) { if model.inspector == .image || model.inspector == .text { model.resetPresentation() } else if model.inspector == .audio { model.changeClip(L("Réinitialiser")) { $0.volume = 1; $0.muted = false; $0.fadeIn = .zero; $0.fadeOut = .zero } } else { model.changeClip(L("Réinitialiser")) { $0.keyframes = [] } } }.font(.caption).frame(minHeight: 32)
                    Button { textFieldFocused = false; model.inspector = nil } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }.accessibilityLabel(L("Fermer")).accessibilityIdentifier("closeInspector")
                }
                if let clip = model.selectedClip {
                    if model.inspector == .image || model.inspector == .text {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L("Formats concernés")).font(.caption.weight(.semibold)).foregroundStyle(DesignTokens.muted)
                            Picker(L("Formats concernés"), selection: $model.localScope) {
                                Text(L("Tous les formats")).tag(false)
                                Text("\(Int(model.variant.widthRatio)):\(Int(model.variant.heightRatio)) \(L("seulement"))").tag(true)
                            }.pickerStyle(.segmented)
                            Text(L("Ce choix concerne les cadrages de sortie, pas la durée du montage.")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    switch model.inspector {
                    case .image: imageControls(clip)
                    case .audio: audioControls(clip)
                    case .text: textControls(clip)
                    case .animation: animationControls(clip)
                    case nil: EmptyView()
                    }
                } else { Text(L("Sélectionnez une scène ou un calque pour le modifier.")).font(.caption).foregroundStyle(.secondary) }
            }.padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DesignTokens.panel).sheet(isPresented: $showChroma) { ChromaKeySheet(model: model) }
            .sheet(isPresented: $showCaptions) { CaptionEditorSheet(model: model) }
            .sheet(isPresented: $showKeyframes) { KeyframeEditorSheet(model: model) }
            .sheet(item: $editingEffect) { effect in EffectEditorSheet(model: model, effectID: effect.id) }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Terminé")) { textFieldFocused = false }
                }
            }
            .onChange(of: model.inspector) { _, tab in if tab != .text { textFieldFocused = false } }
            .onChange(of: model.selectedClipID) { _, _ in textFieldFocused = false }
            .onChange(of: model.mode) { _, _ in textFieldFocused = false }
            .onChange(of: applyStyleToCaptionTrack) { _, wholeTrack in if wholeTrack { textFieldFocused = false } }
            .onDisappear { textFieldFocused = false }
    }
    private func imageControls(_ clip: Clip) -> some View {
        VStack(spacing: 12) {
            HStack { Button(L("Ajuster")) { model.changePresentation { $0.fill = false } }.buttonStyle(.bordered); Button(L("Remplir")) { model.changePresentation { $0.fill = true } }.buttonStyle(.bordered); Spacer(); Toggle(L("Miroir"), isOn: presentationBool(\.mirror)).font(.caption).fixedSize() }
            if clip.kind == .video || clip.kind == .image { Button(L("Pipette chroma")) { showChroma = true }.buttonStyle(.bordered); Toggle(L("Détourer les personnes (Vision)"), isOn: presentationBool(\.removePersonBackground)).font(.caption) }
            property("Échelle", \.scale, 0.1...4)
            property("Horizontal", \.x, -0.5...1.5)
            property("Vertical", \.y, -0.5...1.5)
            property("Rotation", \.rotation, -180...180, suffix: "°")
            property("Opacité", \.opacity, 0...1)
            HStack { Text(L("Masque")); Spacer(); Picker(L("Masque"), selection: Binding(get: { model.presentation.mask }, set: { value in model.changePresentation { $0.mask = value } })) { ForEach(MaskKind.allCases, id: \.self) { Text(effectLabel($0.rawValue)).tag($0) } }.labelsHidden() }.font(.caption)
            if model.presentation.mask != .none {
                property("Largeur du masque", \.maskWidth, 0.05...1.5); property("Hauteur du masque", \.maskHeight, 0.05...1.5)
                property("Position X du masque", \.maskX, 0...1); property("Position Y du masque", \.maskY, 0...1)
                property("Rotation du masque", \.maskRotation, -180...180)
                property("Contour progressif", \.maskFeather, 0...0.2)
                Toggle(L("Inverser le masque"), isOn: presentationBool(\.maskInverted)).font(.caption)
            }
            HStack { Text(L("Fusion")); Spacer(); Picker(L("Fusion"), selection: Binding(get: { model.presentation.blend }, set: { value in model.changePresentation { $0.blend = value } })) { ForEach(BlendMode.allCases, id: \.self) { Text(effectLabel($0.rawValue)).tag($0) } }.labelsHidden() }.font(.caption)
            HStack { Text(L("Effets")).font(.caption.bold()); Spacer(); Menu { ForEach(EffectKind.allCases, id: \.self) { kind in Button(effectLabel(kind.rawValue)) { model.changeClip(L("Effets")) { $0.effects.append(.readyToUse(kind, duration: clip.duration, offset: clip.animationOffset, defaultAmount: 0.3)) } } } } label: { Image(systemName: "plus.circle").frame(width: 44, height: 32) } }
            ForEach(clip.effects) { effect in HStack { Button { editingEffect = effect } label: { Image(systemName: "clock.badge.checkmark").frame(width: 36, height: 44) }.accessibilityLabel(L("Plage et animation de l’effet")); ValueSlider(title: effectLabel(effect.kind.rawValue), value: Binding(get: { model.selectedClip?.effects.first { $0.id == effect.id }?.amount ?? 0 }, set: { value in model.changeClip(L("Effets")) { c in if let i = c.effects.firstIndex(where: { $0.id == effect.id }) { c.effects[i].amount = value } } }), range: effect.kind == .exposure ? -2...2 : 0...1, editing: gesture); Button(role: .destructive) { model.changeClip(L("Supprimer")) { $0.effects.removeAll { $0.id == effect.id } } } label: { Image(systemName: "trash").foregroundStyle(.red).frame(width: 44, height: 44) }.accessibilityLabel(L("Supprimer l’effet")) } }
            HStack { Button(L("Au premier plan")) { model.changeClip(L("Ordre des couches")) { $0.layer += 1 } }; Spacer(); Button(L("À l’arrière-plan")) { model.changeClip(L("Ordre des couches")) { $0.layer -= 1 } } }.font(.caption)
            anchorControls(clip)
        }
    }
    private func audioControls(_ clip: Clip) -> some View {
        VStack(spacing: 12) {
            Toggle(L("Muet"), isOn: Binding(get: { clip.muted }, set: { value in model.changeClip(L("Muet")) { $0.muted = value } })).font(.caption)
            ValueSlider(title: L("Volume"), value: Binding(get: { clip.volume }, set: { v in model.changeClip(L("Volume")) { $0.volume = v } }), range: 0...2, editing: gesture)
            ValueSlider(title: L("Fondu entrant"), value: Binding(get: { clip.fadeIn.seconds }, set: { v in model.changeClip(L("Fondu entrant")) { $0.fadeIn = .init(seconds: v) } }), range: 0...max(0.1, clip.duration.seconds / 2), suffix: "s", editing: gesture)
            ValueSlider(title: L("Fondu sortant"), value: Binding(get: { clip.fadeOut.seconds }, set: { v in model.changeClip(L("Fondu sortant")) { $0.fadeOut = .init(seconds: v) } }), range: 0...max(0.1, clip.duration.seconds / 2), suffix: "s", editing: gesture)
            anchorControls(clip)
        }
    }
    private func textControls(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(L("Modifier les sous-titres")) { textFieldFocused = false; showCaptions = true }.buttonStyle(.bordered).accessibilityIdentifier("captionEditor")
            if clip.kind == .text {
                if clip.isCaption {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Sous-titres concernés")).font(.caption.weight(.semibold)).foregroundStyle(DesignTokens.muted)
                        Picker(L("Sous-titres concernés"), selection: $applyStyleToCaptionTrack) {
                            Text(L("Ce segment")).tag(false)
                            Text(L("Toute la piste")).tag(true)
                        }.pickerStyle(.segmented)
                        Text(L("Les réglages de style ci-dessous s’appliquent au segment sélectionné ou à tous les sous-titres.")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if !clip.isCaption || !applyStyleToCaptionTrack {
                    TextField(L("Texte du calque"), text: $textDraft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
                        .focused($textFieldFocused)
                        .accessibilityIdentifier("layerTextField")
                        .onAppear { textDraft = clip.text }.onChange(of: clip.id) { _, _ in textDraft = clip.text }.onChange(of: clip.text) { _, value in textDraft = value }
                    Button(L("Mettre à jour")) { textFieldFocused = false; model.changeClip(L("Texte")) { $0.text = textDraft } }.buttonStyle(.bordered).disabled(textDraft == clip.text)
                }
                textProperty("Taille", \.textSize, 0.02...0.2, clip: clip)
                Picker(L("Police"), selection: Binding(get: { model.presentation.textFont }, set: { font in changeTextPresentation(clip) { $0.textFont = font } })) {
                    ForEach(EditorFontCatalog.available) { Text(L($0.title)).font($0.font).tag($0.id) }
                }.font(.caption)
                if model.presentation.textFont == "system" { Toggle(L("Gras"), isOn: textPresentationBool(\.textBold, clip: clip)).font(.caption) }
                else if UIFont(name: model.presentation.textFont, size: 16) == nil { Text(L("Police indisponible : choisissez un remplacement installé.")).font(.caption).foregroundStyle(.orange) }
                textProperty("Espacement des lettres", \.textLetterSpacing, -0.1...0.5, suffix: " em", clip: clip)
                textProperty("Interligne supplémentaire", \.textLineSpacing, 0...1, suffix: " em", clip: clip)
                HStack { Text(L("Couleur")).font(.caption); Spacer(); ForEach(["#FFFFFF", "#15191F", "#EBA65A", "#A0C9BD"], id: \.self) { hex in Button { changeTextPresentation(clip) { $0.color = hex } } label: { Circle().fill(Color(hex: hex)).frame(width: 28, height: 28).overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1) }.frame(width: 36, height: 44) }.accessibilityLabel(hex) } }
                Picker(L("Alignement"), selection: Binding(get: { model.presentation.textAlignment }, set: { v in changeTextPresentation(clip) { $0.textAlignment = v } })) { Text(L("Gauche")).tag("left"); Text(L("Centre")).tag("center"); Text(L("Droite")).tag("right") }.pickerStyle(.segmented)
                textProperty("Contour", \.textOutline, 0...0.1, clip: clip); textProperty("Ombre", \.textShadow, 0...0.1, clip: clip); textProperty("Fond", \.textBackgroundOpacity, 0...1, clip: clip)
                textProperty("Horizontal", \.x, 0...1, clip: clip); textProperty("Vertical", \.y, 0...1, clip: clip)
            } else { Button(L("Texte libre")) { model.addText() }.buttonStyle(.bordered); Button(L("Sous-titres")) { model.addText(caption: true) }.buttonStyle(.bordered) }
        }
    }
    private func animationControls(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(clip.keyframes.count) \(L("Images clés").lowercased())").font(.caption).foregroundStyle(.secondary)
            Button(L("Modifier les images clés")) { showKeyframes = true }.buttonStyle(.bordered).accessibilityIdentifier("keyframeEditor")
            if let rendered = model.plan.clips.first(where: { $0.id == clip.id }) {
                let time = MediaTime(seconds: model.playhead)
                let previous = AnimationEditing.neighbor(in: rendered, from: time, forward: false)
                let next = AnimationEditing.neighbor(in: rendered, from: time, forward: true)
                HStack {
                    Button { if let previous { model.seek(min(previous.seconds, rendered.end.seconds - 1.0 / 60_000)) } } label: { Label(L("Point précédent"), systemImage: "backward.end") }.disabled(previous == nil)
                    Spacer()
                    Button { if let next { model.seek(min(next.seconds, rendered.end.seconds - 1.0 / 60_000)) } } label: { Label(L("Point suivant"), systemImage: "forward.end") }.disabled(next == nil)
                }.font(.caption)
                Button(L("Ajouter ou mettre à jour la pose")) {
                    let clamped = min(max(time, rendered.globalStart), rendered.end)
                    model.edit(L("Images clés")) { try AnimationEditing.upsertCurrentPose(clipID: clip.id, at: clamped, variantID: model.variantID, in: &$0) }
                }.buttonStyle(.bordered)
            }
            Text(L("L’animation est commune aux formats. Les valeurs affichées tiennent compte du cadrage actif.")).font(.caption).foregroundStyle(.secondary)
            Button(L("Retirer les points")) { model.changeClip(L("Images clés")) { $0.keyframes.removeAll { $0.property != .volume } } }.font(.caption).disabled(!clip.keyframes.contains { $0.property != .volume })
        }
    }
    private func anchorControls(_ clip: Clip) -> some View {
        HStack { Text(L("Ancrage")).font(.caption); Spacer(); Menu { Button(L("Projet entier")) { let start = model.plan.clips.first { $0.id == clip.id }?.globalStart ?? .zero; model.edit(L("Ancrage")) { try DocumentEditor.moveClip(clip.id, toScene: nil, at: start, in: &$0) } }; ForEach(model.document.scenes) { scene in Button(scene.title) { model.edit(L("Ancrage")) { try DocumentEditor.moveClip(clip.id, toScene: scene.id, at: .zero, in: &$0) } } } } label: { Label(model.selectedScene?.title ?? L("Projet entier"), systemImage: model.selectedSceneID == nil ? "pin.fill" : "rectangle.stack").font(.caption).lineLimit(1).frame(minHeight: 36) } }
    }
    private func property(_ title: String, _ key: WritableKeyPath<Presentation, Double>, _ range: ClosedRange<Double>, suffix: String = "") -> some View {
        ValueSlider(title: L(title), value: Binding(get: { model.presentation[keyPath: key] }, set: { v in model.changePresentation { $0[keyPath: key] = v } }), range: range, suffix: suffix, editing: gesture)
    }
    private func textProperty(_ title: String, _ key: WritableKeyPath<Presentation, Double>, _ range: ClosedRange<Double>, suffix: String = "", clip: Clip) -> some View {
        ValueSlider(title: L(title), value: Binding(get: { model.presentation[keyPath: key] }, set: { value in changeTextPresentation(clip) { $0[keyPath: key] = value } }), range: range, suffix: suffix, editing: gesture)
    }
    private func changeTextPresentation(_ clip: Clip, _ change: (inout Presentation) -> Void) {
        if clip.isCaption && applyStyleToCaptionTrack { model.changeCaptionPresentations(change) }
        else { model.changePresentation(change) }
    }
    private func textPresentationBool(_ key: WritableKeyPath<Presentation, Bool>, clip: Clip) -> Binding<Bool> {
        Binding(get: { model.presentation[keyPath: key] }, set: { value in changeTextPresentation(clip) { $0[keyPath: key] = value } })
    }
    private func presentationBool(_ key: WritableKeyPath<Presentation, Bool>) -> Binding<Bool> { Binding(get: { model.presentation[keyPath: key] }, set: { v in model.changePresentation { $0[keyPath: key] = v } }) }
    private func gesture(_ active: Bool) { if active { model.beginGesture(L("Propriétés")) } else { model.endGesture() } }
}
struct ValueSlider: View {
    var title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix = ""
    var editing: (Bool) -> Void = { _ in }
    var body: some View {
        VStack(spacing: 2) { HStack { Text(title); Spacer(); Text(String(format: "%.2f", value) + suffix).monospacedDigit().foregroundStyle(DesignTokens.amber) }.font(.caption); Slider(value: $value, in: range, onEditingChanged: editing).accessibilityLabel(title).accessibilityValue(String(format: "%.2f", value) + suffix) }
            .frame(minHeight: 48)
    }
}
func effectLabel(_ value: String) -> String {
    if value == "cloud" { return AppLocalization.bilingual("Nuage", "Cloud") }
    if value == "star" { return AppLocalization.bilingual("Étoile", "Star") }
    if value == "heart" { return AppLocalization.bilingual("Cœur", "Heart") }
    switch value {
    case "impactZoom": return AppLocalization.bilingual("Zoom impact", "Impact zoom")
    case "shortGlitch": return AppLocalization.bilingual("Glitch court", "Short glitch")
    case "neon": return AppLocalization.bilingual("Néon", "Neon")
    case "dream": return AppLocalization.bilingual("Rêve", "Dream")
    case "lightSweep": return AppLocalization.bilingual("Balayage lumineux", "Light sweep")
    case "liquidDistortion": return AppLocalization.bilingual("Déformation liquide", "Liquid distortion")
    case "directionalBlur": return AppLocalization.bilingual("Flou filé", "Directional blur")
    case "popHalftone": return AppLocalization.bilingual("Trame pop", "Pop halftone")
    case "duotone": return AppLocalization.bilingual("Duotone", "Duotone")
    case "lensPulse": return AppLocalization.bilingual("Grand-angle pulsé", "Wide-angle pulse")
    case "ghostTrail": return AppLocalization.bilingual("Traînée fantôme", "Ghost trail")
    case "stopMotion": return AppLocalization.bilingual("Stop-motion", "Stop motion")
    case "roughEdges": return AppLocalization.bilingual("Bords déchirés", "Torn edges")
    case "writeOn": return AppLocalization.bilingual("Écriture tracée", "Write-on")
    case "timeScan": return AppLocalization.bilingual("Scan temporel", "Time scan")
    default: break
    }
    let names = ["none":"Aucun", "dissolve":"Fondu enchaîné", "black":"Noir", "white":"Blanc", "slide":"Glissement", "wipe":"Balayage", "zoom":"Zoom", "blur":"Flou", "glitch":"Fragmentation", "exposure":"Exposition", "brightness":"Luminosité", "contrast":"Contraste", "saturation":"Saturation", "temperature":"Température", "tint":"Teinte", "highlights":"Hautes lumières", "shadows":"Ombres", "sharpness":"Netteté", "vignette":"Vignette", "grain":"Grain", "fade":"Noirs adoucis", "glow":"Lueur", "rgbSplit":"Séparation RGB", "pixelate":"Pixelisation", "shake":"Tremblement", "retro":"Rétro", "skinSmooth":"Lissage peau", "skinGlow":"Éclat du teint", "bulge":"Bombement", "pinch":"Pincement", "twirl":"Tourbillon", "kaleidoscope":"Kaléidoscope", "comic":"BD", "crystallize":"Cristallisation", "ellipse":"Ellipse", "rectangle":"Rectangle", "roundedRectangle":"Rectangle arrondi", "linear":"Séparation", "band":"Bande", "normal":"Normal", "multiply":"Produit", "screen":"Écran", "overlay":"Superposition", "lighten":"Éclaircir", "darken":"Assombrir"]
    return L(names[value] ?? value)
}
