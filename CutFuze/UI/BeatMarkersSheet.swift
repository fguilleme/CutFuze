import SwiftUI

private func BL(_ french: String, _ english: String) -> String {
    if Locale.current.language.languageCode?.identifier == "fr" { return french }
    return ExtraStrings.english[french] ?? english
}

struct BeatMarkersSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var label = ""
    @State private var seconds = 0.0
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(BL("Posez un repère à la tête de lecture, puis ajustez son temps. Les repères restent ancrés au projet quand vous déplacez les scènes.", "Place a marker at the playhead, then refine its time. Markers remain anchored to the project when scenes move.")).font(.footnote).foregroundStyle(.secondary)
                    Button { add() } label: { Label(BL("Ajouter au temps courant", "Add at playhead") + " · " + timeLabel(model.playhead), systemImage: "metronome") }
                }
                Section(BL("Repères manuels", "Manual markers")) {
                    if model.document.rhythmMarkers.isEmpty {
                        Text(BL("Aucun repère. Écoutez votre musique, positionnez la tête de lecture puis ajoutez un repère.", "No markers. Listen to your music, position the playhead and add a marker.")).foregroundStyle(.secondary)
                    }
                    ForEach(model.document.rhythmMarkers) { marker in
                        Button {
                            selectedID = marker.id; seconds = marker.time.seconds; label = marker.label
                            model.seek(marker.time.seconds)
                        } label: {
                            HStack {
                                Image(systemName: selectedID == marker.id ? "diamond.fill" : "diamond").foregroundStyle(DesignTokens.amber)
                                Text(marker.label.isEmpty ? BL("Repère", "Marker") : marker.label).foregroundStyle(.primary)
                                Spacer()
                                Text(timeLabel(marker.time.seconds)).monospacedDigit().foregroundStyle(.secondary)
                            }.frame(minHeight: 32)
                        }.accessibilityAddTraits(selectedID == marker.id ? .isSelected : [])
                    }.onDelete { offsets in
                        let ids = offsets.map { model.document.rhythmMarkers[$0].id }
                        model.edit(BL("Supprimer des repères", "Delete markers")) { document in ids.forEach { document.removeBeatMarker($0) } }
                        if let selectedID, ids.contains(selectedID) { self.selectedID = nil }
                    }
                }
                if let selectedID, model.document.rhythmMarkers.contains(where: { $0.id == selectedID }) {
                    Section(BL("Réglage précis", "Precise timing")) {
                        TextField(BL("Nom du repère", "Marker label"), text: $label)
                        HStack {
                            Text(BL("Temps en secondes", "Time in seconds"))
                            TextField("0.000", value: $seconds, format: .number.precision(.fractionLength(3))).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        Button(BL("Appliquer la modification", "Apply changes")) {
                            model.edit(BL("Modifier un repère", "Edit marker")) { document in try document.updateBeatMarker(selectedID, time: .init(seconds: seconds), label: label) }
                        }.disabled(!seconds.isFinite || seconds < 0 || seconds > 604_800)
                        Button(L("Supprimer"), role: .destructive) { model.edit(BL("Supprimer un repère", "Delete marker")) { $0.removeBeatMarker(selectedID) }; self.selectedID = nil }
                    }
                }
            }.navigationTitle(BL("Repères rythmiques", "Rhythm markers")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() } } }
        }
    }
    private func add() {
        model.edit(BL("Ajouter un repère", "Add marker")) { document in selectedID = try document.addBeatMarker(at: .init(seconds: model.playhead)) }
        seconds = model.playhead
        label = model.document.rhythmMarkers.first(where: { $0.id == selectedID })?.label ?? ""
    }
}
