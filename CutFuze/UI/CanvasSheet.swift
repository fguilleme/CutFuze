import SwiftUI
import PhotosUI

struct CanvasSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CanvasSettings()
    @State private var preview: CGImage?
    @State private var error: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importedAsset: MediaAsset?
    @State private var importingPhoto = false
    @State private var importTask: Task<Void, Never>?
    private let renderer = FrameRenderer()
    private var canvasImages: [MediaAsset] {
        var images = model.document.assets.filter { $0.kind == .image }
        if let importedAsset, !images.contains(where: { $0.id == importedAsset.id }) { images.append(importedAsset) }
        return images
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let preview { Image(decorative: preview, scale: 1).resizable().scaledToFit().frame(height: 190) }
                Form {
                    Section(L("Fond du format actif")) {
                        Picker(L("Fond"), selection: $draft.mode) {
                            Text(L("Couleur unie")).tag(CanvasBackground.solid)
                            Text(L("Image importée")).tag(CanvasBackground.image)
                            Text(L("Copie floutée")).tag(CanvasBackground.blurredMedia)
                        }
                        HStack { ForEach(["#000000", "#F6F3EE", "#15191F", "#EBA65A", "#A0C9BD"], id: \.self) { hex in
                            Button { draft.color = hex } label: { Circle().fill(Color(hex: hex)).frame(width: 30, height: 30).overlay { if draft.color == hex { Image(systemName: "checkmark").foregroundStyle(hex == "#000000" ? .white : .black) } }.frame(minWidth: 44, minHeight: 44) }.buttonStyle(.plain).accessibilityLabel(hex)
                        } }
                        if draft.mode == .image {
                            Picker(L("Image importée"), selection: $draft.imageAssetID) {
                                Text(L("Sélectionner")).tag(UUID?.none)
                                ForEach(canvasImages) { Text($0.name).tag(Optional($0.id)) }
                            }
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label(L("Choisir une photo"), systemImage: "photo.badge.plus").frame(minHeight: 44)
                            }
                            .disabled(importingPhoto)
                            .accessibilityIdentifier("canvasPhotoPicker")
                            if importingPhoto { ProgressView(L("Import…")) }
                            Text(L("Choisissez une photo existante ou importez-en une directement depuis votre photothèque.")).font(.caption).foregroundStyle(.secondary)
                        }
                        if draft.mode == .blurredMedia { ValueSlider(title: L("Flou"), value: $draft.blur, range: 0...0.2) }
                        Text(L("Utilisez Ajuster dans Image pour révéler le fond autour du média.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Section(L("Ajouter un format")) {
                        Button("4:5") { addFormat(name: "4:5", width: 4, height: 5) }
                        if let asset = model.document.asset(model.selectedClip?.assetID), asset.width > 0, asset.height > 0 {
                            Button(L("Ratio du média original")) { addFormat(name: L("Original"), width: Double(asset.width), height: Double(asset.height)) }
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle(L("Canevas"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Annuler")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(L("Appliquer")) {
                        let id = model.variantID, settings = draft
                        model.edit(L("Canevas")) { doc in
                            if let importedAsset, !doc.assets.contains(where: { $0.id == importedAsset.id }) { doc.assets.append(importedAsset) }
                            if let i = doc.variants.firstIndex(where: { $0.id == id }) { doc.variants[i].canvas = settings }
                        }; dismiss()
                    }.disabled(draft.mode == .image && draft.imageAssetID == nil) }
                }
                .onAppear { draft = model.variant.canvas ?? .init() }
                .onChange(of: selectedPhoto) { _, item in
                    guard let item else { return }
                    importTask?.cancel()
                    importTask = Task { await importPhoto(item) }
                }
                .task(id: draft) { await render() }
        }.preferredColorScheme(.dark).onDisappear { importTask?.cancel() }
    }
    private func addFormat(name: String, width: Double, height: Double) {
        let ratio = width / height
        if let existing = model.document.variants.first(where: { abs($0.ratio - ratio) < 0.0001 }) { model.changeVariant(existing.id); dismiss(); return }
        let new = OutputVariant(name: name, widthRatio: width, heightRatio: height, canvas: draft)
        model.edit(L("Ajouter un format")) { $0.variants.append(new) }; model.changeVariant(new.id); dismiss()
    }
    @MainActor private func render() async {
        var doc = model.document
        if let importedAsset, !doc.assets.contains(where: { $0.id == importedAsset.id }) { doc.assets.append(importedAsset) }
        guard let i = doc.variants.firstIndex(where: { $0.id == model.variantID }) else { return }
        doc.variants[i].canvas = draft
        do {
            let size = MovieExportSettings(longEdge: 480).dimensions(for: doc.variants[i])
            let image = try await renderer.render(plan: .compile(document: doc, variantID: model.variantID), time: .init(seconds: model.playhead), rootURL: model.rootURL, size: size)
            guard !Task.isCancelled else { return }; preview = image; error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    @MainActor private func importPhoto(_ item: PhotosPickerItem) async {
        importingPhoto = true; error = nil
        defer { importingPhoto = false; selectedPhoto = nil }
        do {
            guard let transferred = try await item.loadTransferable(type: ImportedImage.self) else { throw MediaFailure.unreadable(L("Photo")) }
            defer { try? FileManager.default.removeItem(at: transferred.url) }
            let imported = try await MediaImporter.shared.importFile(url: transferred.url, to: model.rootURL)
            guard imported.kind == .image else { throw MediaFailure.unsupported(L("Photo")) }
            let asset = model.document.assets.first(where: { $0.relativePath == imported.relativePath }) ?? imported
            importedAsset = asset; draft.mode = .image; draft.imageAssetID = asset.id
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
