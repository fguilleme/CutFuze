import SwiftUI

struct CaptionEditorSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var text = ""
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var splitTime = 0.5
    @State private var firstText = ""
    @State private var secondText = ""
    @State private var scopeLocal = false
    @State private var localError: String?
    @State private var confirmDeleteTrack = false
    private var captions: [RenderClip] { CaptionEditing.captions(in: model.document) }
    private var selected: RenderClip? { captions.first { $0.id == selectedID } }
    private var next: RenderClip? {
        guard let index = captions.firstIndex(where: { $0.id == selectedID }), index + 1 < captions.count else { return nil }
        return captions[index + 1]
    }
    var body: some View {
        NavigationStack {
            List {
                Section(L("Segments du montage")) {
                    if captions.isEmpty { ContentUnavailableView(L("Aucun sous-titre"), systemImage: "captions.bubble", description: Text(L("Importez un SRT, transcrivez un média ou ajoutez un sous-titre dans l’atelier."))) }
                    ForEach(captions) { caption in
                        Button { select(caption) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: caption.id == selectedID ? "checkmark.circle.fill" : "circle").foregroundStyle(caption.id == selectedID ? DesignTokens.amber : DesignTokens.muted)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(caption.clip.text).foregroundStyle(.primary).lineLimit(3)
                                    Text(String(format: "%.3f → %.3f s", caption.globalStart.seconds, caption.end.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if caption.clip.captionSourceClipID != nil { Image(systemName: "link").foregroundStyle(DesignTokens.teal).accessibilityLabel(L("Lié à la source")) }
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityIdentifier("caption-\(caption.id.uuidString)")
                    }
                }
                if let selected {
                    Section(L("Corriger le segment")) {
                        TextField(L("Texte du calque"), text: $text, axis: .vertical).lineLimit(2...6)
                        timing(L("Début") + " (s)", value: $start)
                        timing(L("Fin") + " (s)", value: $end)
                        Button(L("Enregistrer le segment")) { update() }.accessibilityIdentifier("saveCaption")
                        if selected.clip.captionSourceClipID != nil {
                            Text(L("Les nouveaux temps sont reconvertis vers la source. La liaison suit ensuite les coupes et changements de vitesse.")).font(.caption).foregroundStyle(.secondary)
                            Button(L("Détacher explicitement de la source")) { perform(L("Détacher le sous-titre")) { try CaptionEditing.detachSource(selected.id, in: &$0) } }
                        }
                    }
                    Section(L("Scinder le segment")) {
                        timing(L("Instant de scission") + " (s)", value: $splitTime)
                        TextField(L("Texte avant la scission"), text: $firstText, axis: .vertical).lineLimit(2...4)
                        TextField(L("Texte après la scission"), text: $secondText, axis: .vertical).lineLimit(2...4)
                        Text(L("Choisissez le temps et les deux textes. Aucun horodatage mot à mot n’est inventé.")).font(.caption).foregroundStyle(.secondary)
                        Button(L("Scinder")) { split() }.disabled(firstText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secondText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let next {
                        Section(L("Fusionner les segments")) {
                            Text(next.clip.text).font(.callout).foregroundStyle(.secondary)
                            Text(L("La fusion conserve le style du premier segment. Les deux segments doivent partager leur scène et leur source." )).font(.caption).foregroundStyle(.secondary)
                            Button(L("Fusionner avec le suivant")) { perform(L("Fusionner les sous-titres")) { _ = try CaptionEditing.merge(selected.id, with: next.id, in: &$0) } }
                        }
                    }
                    Section(L("Style de tous les sous-titres")) {
                        Picker(L("Formats concernés"), selection: $scopeLocal) {
                            Text(L("Tous les formats")).tag(false)
                            Text("\(Int(model.variant.widthRatio)):\(Int(model.variant.heightRatio)) \(L("seulement"))").tag(true)
                        }.pickerStyle(.segmented)
                        Text(L("Ce choix concerne les cadrages de sortie, pas la durée du montage.")).font(.caption).foregroundStyle(.secondary)
                        Text(L("Reprend la présentation du segment sélectionné. Le texte, les temps et les liens restent inchangés.")).font(.caption).foregroundStyle(.secondary)
                        Button(L("Appliquer le style à tous")) {
                            let variant = scopeLocal ? model.variantID : nil
                            perform(L("Style des sous-titres")) { try CaptionEditing.applyStyle(from: selected.id, variantID: variant, in: &$0) }
                        }
                    }
                    Section {
                        Button(L("Supprimer tous les sous-titres"), role: .destructive) { confirmDeleteTrack = true }
                            .accessibilityIdentifier("deleteCaptionTrack")
                    }
                }
                if let localError { Section { Text(localError).foregroundStyle(.red) } }
            }.pinnedPreview(model.preview).navigationTitle(L("Modifier les sous-titres")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() }.accessibilityIdentifier("closeCaptions") }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { model.undo(); refresh() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).accessibilityLabel(L("Annuler la modification"))
                        Button { model.redo(); refresh() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).accessibilityLabel(L("Rétablir"))
                    }
                }
                .onAppear { scopeLocal = model.localScope; if let preferred = captions.first(where: { $0.id == model.selectedClipID }) ?? captions.first { select(preferred) } }
                .confirmationDialog(L("Supprimer la piste de sous-titres ?"), isPresented: $confirmDeleteTrack, titleVisibility: .visible) {
                    Button(L("Supprimer tous les sous-titres"), role: .destructive) { model.deleteCaptionTrack(); dismiss() }
                    Button(L("Annuler"), role: .cancel) {}
                } message: {
                    Text(L("Tous les sous-titres du montage seront supprimés. Vous pourrez annuler cette action."))
                }
        }.preferredColorScheme(.dark)
    }
    private func timing(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title); Spacer(); TextField(title, value: value, format: .number.precision(.fractionLength(0...3))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110).accessibilityLabel(title) }
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
