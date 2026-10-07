import SwiftUI
import UIKit

private enum CaptionWorkspaceTab: String, CaseIterable, Identifiable {
    case text = "Texte"
    case style = "Style"
    case effects = "Effets"
    var id: String { rawValue }
}

struct CaptionEditorSheet: View {
    @ObservedObject var model: EditorModel
    var initialSelectionID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var activeTab: CaptionWorkspaceTab = .text
    @State private var text = ""
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var splitTime = 0.5
    @State private var firstText = ""
    @State private var secondText = ""
    @State private var scopeLocal = false
    @State private var styleWholeTrack = true
    @State private var editingEffect: EffectInstance?
    @State private var localError: String?
    @State private var confirmDeleteTrack = false
    @FocusState private var textFocused: Bool

    private var captions: [RenderClip] { CaptionEditing.captions(in: model.document) }
    private var selected: RenderClip? { captions.first { $0.id == selectedID } }
    private var next: RenderClip? {
        guard let index = captions.firstIndex(where: { $0.id == selectedID }), index + 1 < captions.count else { return nil }
        return captions[index + 1]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let selected { quickEditor(for: selected) }
                else if captions.isEmpty {
                    ContentUnavailableView(L("Aucun sous-titre"), systemImage: "captions.bubble", description: Text(L("Importez un SRT, transcrivez un média ou ajoutez un sous-titre dans l’atelier.")))
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                Divider()
                List {
                    Section(L("Segments du montage")) {
                        ForEach(captions) { caption in captionRow(caption) }
                    }
                    if let selected { advancedTools(for: selected) }
                    if let localError { Section { Text(localError).foregroundStyle(.red) } }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .pinnedPreview(textFocused ? nil : model.preview)
            .navigationTitle(L("Modifier les sous-titres"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Fermer")) { dismiss() }.accessibilityIdentifier("closeCaptions")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { model.undo(); refresh() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!model.canUndo).accessibilityLabel(L("Annuler la modification"))
                    Button { model.redo(); refresh() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!model.canRedo).accessibilityLabel(L("Rétablir"))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Terminé")) { textFocused = false }
                }
            }
            .onAppear {
                scopeLocal = model.localScope
                if let preferred = captions.first(where: { $0.id == initialSelectionID }) ?? captions.first(where: { $0.id == model.selectedClipID }) ?? captions.first {
                    select(preferred)
                }
            }
            .onChange(of: scopeLocal) { _, value in model.localScope = value }
            .confirmationDialog(L("Supprimer la piste de sous-titres ?"), isPresented: $confirmDeleteTrack, titleVisibility: .visible) {
                Button(L("Supprimer tous les sous-titres"), role: .destructive) { model.deleteCaptionTrack(); dismiss() }
                Button(L("Annuler"), role: .cancel) {}
            } message: {
                Text(L("Tous les sous-titres du montage seront supprimés. Vous pourrez annuler cette action."))
            }
            .sheet(item: $editingEffect) { effect in EffectEditorSheet(model: model, effectID: effect.id) }
        }
        .preferredColorScheme(.dark)
    }

    private func quickEditor(for selected: RenderClip) -> some View {
        VStack(spacing: 9) {
            Picker(L("Édition du sous-titre"), selection: $activeTab) {
                ForEach(CaptionWorkspaceTab.allCases) { tab in Text(L(tab.rawValue)).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch activeTab {
            case .text:
                VStack(spacing: 7) {
                    TextField(L("Texte du sous-titre"), text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .focused($textFocused)
                        .accessibilityIdentifier("captionTextField")
                    HStack {
                        Text(String(format: "%.2f → %.2f s", start, end))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Enregistrer")) { textFocused = false; update() }
                            .buttonStyle(.borderedProminent).tint(DesignTokens.amber).foregroundStyle(DesignTokens.ink)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("saveCaption")
                    }
                }
            case .style:
                VStack(spacing: 7) {
                    HStack(spacing: 8) {
                        Picker(L("Sous-titres concernés"), selection: $styleWholeTrack) {
                            Text(L("Ce segment")).tag(false)
                            Text(L("Toute la piste")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        Menu {
                            Button(L("Tous les formats")) { scopeLocal = false }
                            Button("\(Int(model.variant.widthRatio)):\(Int(model.variant.heightRatio)) \(L("seulement"))") { scopeLocal = true }
                        } label: {
                            Image(systemName: "rectangle.3.group").frame(width: 40, height: 32)
                        }
                        .accessibilityLabel(L("Formats concernés"))
                    }
                    CompactValueSlider(title: L("Taille"), value: style(\.textSize), range: 0.02...0.2, step: 0.01, editing: styleGesture)
                    HStack(spacing: 4) {
                        ForEach(["#FFFFFF", "#15191F", "#EBA65A", "#A0C9BD"], id: \.self) { hex in
                            Button { changeStyle { $0.color = hex } } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 24, height: 24)
                                    .overlay { Circle().strokeBorder(model.presentation.color == hex ? DesignTokens.amber : .white.opacity(0.35), lineWidth: 2) }
                                    .frame(width: 38, height: 38)
                            }
                            .accessibilityLabel(hex)
                        }
                        Spacer()
                        Menu {
                            Button(L("Système")) { changeStyle { $0.textFont = "system" } }
                            ForEach(["Georgia", "Georgia-Bold", "Menlo-Regular", "Menlo-Bold"].filter { UIFont(name: $0, size: 16) != nil }, id: \.self) { font in
                                Button(font) { changeStyle { $0.textFont = font } }
                            }
                        } label: {
                            Label(L("Police"), systemImage: "textformat.size").font(.caption).frame(minHeight: 38)
                        }
                        Menu {
                            Button(L("Gauche")) { changeStyle { $0.textAlignment = "left" } }
                            Button(L("Centre")) { changeStyle { $0.textAlignment = "center" } }
                            Button(L("Droite")) { changeStyle { $0.textAlignment = "right" } }
                        } label: {
                            Image(systemName: "text.alignleft").frame(width: 38, height: 38)
                        }
                        .accessibilityLabel(L("Alignement"))
                    }
                }
            case .effects:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(EffectKind.allCases, id: \.self) { kind in
                                Button(effectLabel(kind.rawValue)) { model.changeClip(L("Effets")) { $0.effects.append(.init(kind: kind, amount: 0.3)) } }
                            }
                        } label: {
                            Label(L("Ajouter"), systemImage: "plus").frame(height: 44).padding(.horizontal, 10)
                                .background(DesignTokens.ink, in: RoundedRectangle(cornerRadius: 10))
                        }
                        ForEach(selected.clip.effects) { effect in
                            HStack(spacing: 0) {
                                Button { editingEffect = effect } label: {
                                    Text(effectLabel(effect.kind.rawValue)).font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(height: 44)
                                }
                                Button { model.changeClip(L("Supprimer")) { $0.effects.removeAll { $0.id == effect.id } } } label: {
                                    Image(systemName: "xmark").frame(width: 38, height: 44)
                                }
                                .accessibilityLabel(L("Supprimer"))
                            }
                            .background(DesignTokens.ink, in: RoundedRectangle(cornerRadius: 10))
                        }
                        if selected.clip.effects.isEmpty {
                            Text(L("Aucun effet appliqué")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 48)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(DesignTokens.panel)
    }

    private func captionRow(_ caption: RenderClip) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button { textFocused = false; select(caption) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: caption.id == selectedID ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(caption.id == selectedID ? DesignTokens.amber : DesignTokens.muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(caption.clip.text).foregroundStyle(.primary).lineLimit(2)
                        HStack(spacing: 5) {
                            Text(String(format: "%.3f → %.3f s", caption.globalStart.seconds, caption.end.seconds))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            if caption.clip.captionSourceClipID != nil {
                                Image(systemName: "link").font(.caption2).foregroundStyle(DesignTokens.teal)
                                    .accessibilityLabel(L("Lié à la source"))
                            }
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("caption-\(caption.id.uuidString)")
            Button {
                select(caption); activeTab = .text
                DispatchQueue.main.async { textFocused = true }
            } label: {
                Image(systemName: "pencil").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(L("Modifier ce sous-titre"))
            .accessibilityIdentifier("editCaption-\(caption.id.uuidString)")
        }
        .frame(minHeight: 52)
    }

    @ViewBuilder private func advancedTools(for selected: RenderClip) -> some View {
        Section(L("Temps du segment")) {
            timing(L("Début") + " (s)", value: $start)
            timing(L("Fin") + " (s)", value: $end)
            Button(L("Enregistrer les temps")) { update() }
            if selected.clip.captionSourceClipID != nil {
                Text(L("Les nouveaux temps sont reconvertis vers la source. La liaison suit ensuite les coupes et changements de vitesse."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Détacher explicitement de la source")) { perform(L("Détacher le sous-titre")) { try CaptionEditing.detachSource(selected.id, in: &$0) } }
            }
        }
        Section(L("Scinder le segment")) {
            timing(L("Instant de scission") + " (s)", value: $splitTime)
            TextField(L("Texte avant la scission"), text: $firstText, axis: .vertical).lineLimit(2...4)
            TextField(L("Texte après la scission"), text: $secondText, axis: .vertical).lineLimit(2...4)
            Button(L("Scinder")) { split() }
                .disabled(firstText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secondText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let next {
            Section(L("Fusionner les segments")) {
                Text(next.clip.text).font(.callout).foregroundStyle(.secondary)
                Button(L("Fusionner avec le suivant")) { perform(L("Fusionner les sous-titres")) { _ = try CaptionEditing.merge(selected.id, with: next.id, in: &$0) } }
            }
        }
        Section {
            Button(L("Supprimer tous les sous-titres"), role: .destructive) { confirmDeleteTrack = true }
                .accessibilityIdentifier("deleteCaptionTrack")
        }
    }

    private func timing(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110).accessibilityLabel(title)
        }
    }

    private func select(_ caption: RenderClip) {
        selectedID = caption.id; model.selectClip(caption)
        text = caption.clip.text; start = caption.globalStart.seconds; end = caption.end.seconds; splitTime = (start + end) / 2
        firstText = text; secondText = ""; localError = nil
    }

    private func refresh() { if let current = selected ?? captions.first { select(current) } else { selectedID = nil } }

    private func update() {
        guard let selectedID, start.isFinite, end.isFinite else { return }
        perform(L("Corriger le sous-titre")) { try CaptionEditing.update(selectedID, text: text, from: .init(seconds: start), to: .init(seconds: end), in: &$0) }
    }

    private func split() {
        guard let selectedID, splitTime.isFinite else { return }
        perform(L("Scinder le sous-titre")) { _ = try CaptionEditing.split(selectedID, at: .init(seconds: splitTime), firstText: firstText, secondText: secondText, in: &$0) }
    }

    private func style(_ key: WritableKeyPath<Presentation, Double>) -> Binding<Double> {
        Binding(get: { model.presentation[keyPath: key] }, set: { value in changeStyle { $0[keyPath: key] = value } })
    }

    private func changeStyle(_ change: (inout Presentation) -> Void) {
        if styleWholeTrack { model.changeCaptionPresentations(change) }
        else { model.changePresentation(change) }
    }

    private func styleGesture(_ active: Bool) {
        if active { model.beginGesture(L("Style des sous-titres")) }
        else { model.endGesture() }
    }

    private func perform(_ name: String, _ operation: (inout ProjectDocument) throws -> Void) {
        do {
            var candidate = model.document
            try operation(&candidate)
            CaptionBindingUpdater.refresh(&candidate)
            try candidate.validate()
            model.edit(name) { $0 = candidate }
            refresh()
        } catch { localError = error.localizedDescription }
    }
}
