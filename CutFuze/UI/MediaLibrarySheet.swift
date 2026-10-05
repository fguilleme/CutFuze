import SwiftUI

struct ImportReviewSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var placement: ImportPlacement = .append
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L("Réordonnez les médias ou retirez ceux que vous ne voulez pas ajouter.")).font(.subheadline).foregroundStyle(.secondary)
                }
                Section(L("Médias sélectionnés")) {
                    ForEach(model.pendingImports) { asset in MediaAssetRow(asset: asset, rootURL: model.rootURL) }
                        .onMove { source, target in model.pendingImports.move(fromOffsets: source, toOffset: target) }
                        .onDelete { model.pendingImports.remove(atOffsets: $0) }
                }
                if model.isReplacingPendingImport {
                    Section(L("Destination")) { Text(L("Le média sélectionné remplacera le plan actuel.")) }
                } else {
                    Section(L("Destination")) {
                        placementButton(.append, title: L("À la suite du montage"), detail: L("Chaque image ou vidéo devient une nouvelle scène à la fin."), symbol: "rectangle.stack.badge.plus")
                        placementButton(.afterSelection, title: L("Après la scène sélectionnée"), detail: L("Crée de nouvelles scènes juste après la scène active."), symbol: "rectangle.stack.fill.badge.plus")
                        placementButton(.overlay, title: L("En superposition"), detail: L("Ajoute les médias comme calques sur la scène active."), symbol: "square.on.square")
                    }
                }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle(L("Import"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Annuler")) { model.pendingImports = []; dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(model.isReplacingPendingImport ? L("Remplacer") : L("Ajouter")) { model.insertPendingImports(placement: placement); dismiss() }.disabled(model.pendingImports.isEmpty || (placement.requiresScene && model.selectedScene == nil)) } }
                .onAppear {
                    let suggested = model.suggestedImportPlacement
                    placement = suggested.requiresScene && model.selectedScene == nil ? .append : suggested
                }
        }.preferredColorScheme(.dark)
    }
    private func placementButton(_ value: ImportPlacement, title: String, detail: String, symbol: String) -> some View {
        Button { placement = value } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 28).foregroundStyle(placement == value ? DesignTokens.amber : DesignTokens.muted)
                VStack(alignment: .leading, spacing: 3) { Text(title).foregroundStyle(.primary); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Image(systemName: placement == value ? "checkmark.circle.fill" : "circle").foregroundStyle(placement == value ? DesignTokens.amber : DesignTokens.muted)
            }.frame(minHeight: 48)
        }.buttonStyle(.plain).disabled(value.requiresScene && model.selectedScene == nil)
    }
}
struct MediaLibrarySheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ClipKind?
    @State private var overlay = false
    var body: some View {
        NavigationStack { List {
            Section { Picker(L("Filtre"), selection: $filter) { Text(L("Tous")).tag(ClipKind?.none); Text(L("Vidéo")).tag(ClipKind?.some(.video)); Text(L("Image")).tag(ClipKind?.some(.image)); Text(L("Son")).tag(ClipKind?.some(.audio)) }.pickerStyle(.segmented); Toggle(L("Ajouter en superposition"), isOn: $overlay).disabled(model.selectedScene == nil) }
            ForEach(model.document.assets.filter { filter == nil || $0.kind == filter }) { asset in
                Button { model.importFiles([model.rootURL.appendingPathComponent(asset.relativePath)], asOverlay: overlay); dismiss() } label: { MediaAssetRow(asset: asset, rootURL: model.rootURL) }.accessibilityIdentifier("resource-\(asset.id)")
            }
        }.navigationTitle(L("Ressources locales")).toolbar { Button(L("Fermer")) { dismiss() } } }.preferredColorScheme(.dark)
    }
}
struct MediaAssetRow: View {
    let asset: MediaAsset
    let rootURL: URL
    @State private var thumbnail: CGImage?
    var body: some View {
        HStack(spacing: 12) {
            ZStack { RoundedRectangle(cornerRadius: 8).fill(DesignTokens.panel); if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().scaledToFill() } else { Image(systemName: clipSymbol(asset.kind)).foregroundStyle(DesignTokens.amber) } }.frame(width: 64, height: 52).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) { Text(asset.name).font(.subheadline).lineLimit(1); Text(asset.kind == .image ? "\(asset.width) × \(asset.height)" : timeLabel(asset.duration.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }.frame(minHeight: 56).task { if asset.kind != .audio { thumbnail = try? await MediaImporter.shared.thumbnail(asset: asset, rootURL: rootURL, maxSize: 180) } }
    }
}
