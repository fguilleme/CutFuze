import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

struct EditorScreen: View {
    @ObservedObject var model: EditorModel
    let close: () -> Void
    @State private var photos: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showExport = false
    @State private var showCompare = false
    @State private var showStory = false
    @State private var showCaptions = false
    @State private var captionEditorInitialID: UUID?
    @State private var showVoice = false
    @State private var showNarration = false
    @State private var showTranscription = false
    @State private var showTiming = false
    @State private var showVision = false
    @State private var showStabilization = false
    @State private var showMediaLibrary = false
    @State private var showCanvas = false
    @State private var showBeats = false
    @State private var showSceneEdit = false
    @State private var showFullScreenPreview = false
    @State private var confirmDeleteCaptionTrack = false
    @State private var importingOverlay = false
    @State private var replaceID: UUID?
    @State private var activeTool: ContextTool?
    @State private var visualTool: VisualTool = .transform
    @State private var viewerHeight: CGFloat?
    @State private var viewerHeightAtDragStart: CGFloat?
    @State private var viewerDividerIsDragging = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var compact: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let defaultViewerHeight = landscape ? max(92, geometry.size.height * 0.27) : min(310, max(220, geometry.size.height * 0.40))
            let minimumViewerHeight: CGFloat = landscape ? 80 : 130
            let activeToolHeight: CGFloat = switch activeTool {
            case nil: 0
            case .visual?: compact ? 218 : 266
            case .animation?: compact ? 176 : 188
            case .font?: compact ? 192 : 294
            case .textStyle? where horizontalSizeClass == .regular && !compact: 322
            default: compact ? 118 : 156
            }
            let captionScopeHeight: CGFloat = model.selectedClip?.isCaption == true ? 42 : 0
            let reservedHeight: CGFloat = (compact ? 44 : 50) + (compact ? 36 : 40) + (compact ? 56 : 62) + (compact ? 110 : 170) + 22 + activeToolHeight + captionScopeHeight
            let maximumViewerHeight = max(minimumViewerHeight, geometry.size.height - reservedHeight)
            let displayedViewerHeight = min(max(viewerHeight ?? defaultViewerHeight, minimumViewerHeight), maximumViewerHeight)
            VStack(spacing: 0) {
                projectBar
                viewer.frame(height: displayedViewerHeight)
                    .padding(.horizontal, landscape ? 48 : 10)
                transport
                viewerTimelineDivider(height: displayedViewerHeight, range: minimumViewerHeight...maximumViewerHeight)
                TimelinePanel(model: model, showStory: { model.stop(); showStory = true }, showCaptions: { openCaptionEditor(initialID: nil) })
                    .frame(maxHeight: .infinity).layoutPriority(1)
                if let activeTool {
                    ContextToolPanel(model: model, tool: activeTool, visualTool: $visualTool, close: { self.activeTool = nil }, showTiming: { showTiming = true })
                        .frame(width: geometry.size.width, height: activeToolHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                contextualBar
            }
        }
        .background(DesignTokens.ink).foregroundStyle(.white).preferredColorScheme(.dark)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay { if showFullScreenPreview { FullScreenPreview(model: model) { showFullScreenPreview = false }.transition(.opacity).zIndex(100) } }
        .statusBarHidden(showFullScreenPreview)
        .photosPicker(isPresented: $showPhotos, selection: $photos, maxSelectionCount: 30, selectionBehavior: .ordered, matching: .any(of: [.images, .videos]))
        .onChange(of: photos) { _, items in importPhotos(items) }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .image, .audio, .plainText], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): importURLs(urls); case .failure(let error): model.error = error.localizedDescription }
        }
        .sheet(isPresented: $showExport) { ExportScreen(model: model) }
        .sheet(isPresented: $showCompare) { VariantComparison(model: model) }
        .sheet(isPresented: $showStory) { StoryModeSheet(model: model) }
        .sheet(isPresented: $showCaptions, onDismiss: { captionEditorInitialID = nil }) { CaptionEditorSheet(model: model, initialSelectionID: captionEditorInitialID) }
        .sheet(isPresented: $showVoice) { VoiceoverSheet(model: model) }
        .sheet(isPresented: $showNarration) { NarrationSheet(model: model) }
        .sheet(isPresented: $showTranscription) { TranscriptionSheet(model: model) }
        .sheet(isPresented: $showStabilization) { StabilizationSheet(model: model) }
        .sheet(isPresented: $showVision) { VisionSheet(model: model) }
        .sheet(isPresented: $showMediaLibrary) { MediaLibrarySheet(model: model) }
        .sheet(isPresented: $showCanvas) { CanvasSheet(model: model) }
        .sheet(isPresented: $showBeats) { BeatMarkersSheet(model: model) }
        .sheet(isPresented: $showTiming) { TimingSheet(model: model) }
        .sheet(isPresented: $showSceneEdit) { SceneEditSheet(model: model) }
        .sheet(isPresented: Binding(get: { !model.pendingImports.isEmpty }, set: { if !$0 { model.pendingImports = [] } })) { ImportReviewSheet(model: model) }
        .confirmationDialog(L("Supprimer la piste de sous-titres ?"), isPresented: $confirmDeleteCaptionTrack, titleVisibility: .visible) {
            Button(L("Supprimer tous les sous-titres"), role: .destructive) { model.deleteCaptionTrack() }
            Button(L("Annuler"), role: .cancel) {}
        } message: { Text(L("Tous les sous-titres du montage seront supprimés. Vous pourrez annuler cette action.")) }
        .alert(L("Erreur"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(L("OK")) { model.error = nil } } message: { Text(model.error ?? "") }
        .overlay(alignment: .top) {
            if let busy = model.busy { HStack { ProgressView(); Text(busy).font(.subheadline); if busy.hasPrefix(L("Import…")) { Button(L("Annuler")) { model.cancelImport() } } }.padding(14).background(.regularMaterial, in: Capsule()).padding(.top, 56) }
        }
        .onChange(of: model.selectedClipID) { _, _ in visualTool = .transform; withAnimation(.easeOut(duration: 0.16)) { activeTool = nil } }
        .onDisappear { model.stop(); model.save() }
    }

    private var projectBar: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "chevron.left", label: "Bibliothèque", action: close).accessibilityIdentifier("editorBack")
            VStack(alignment: .leading, spacing: 1) {
                Text(model.document.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) { Image(systemName: model.saved ? "checkmark.circle.fill" : "circle.dotted"); Text(L(model.saved ? "Sauvegardé" : "Sauvegarde…")) }.font(.system(size: 9, weight: .medium)).foregroundStyle(DesignTokens.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            IconButton(symbol: "arrow.uturn.backward", label: "Annuler la modification", action: model.undo).disabled(!model.canUndo).opacity(model.canUndo ? 1 : 0.3)
            IconButton(symbol: "arrow.uturn.forward", label: "Rétablir", action: model.redo).disabled(!model.canRedo).opacity(model.canRedo ? 1 : 0.3)
            Button { model.stop(); showExport = true } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 42).background(DesignTokens.amber, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(DesignTokens.ink) }
                .padding(.trailing, 10).accessibilityLabel(L("Exporter")).accessibilityIdentifier("export")
        }.frame(height: compact ? 44 : 50)
    }

    private var viewer: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.55))
                if let preview = model.preview {
                    let ratio = model.variant.ratio
                    let width = min(max(1, geo.size.width - 10), max(1, geo.size.height - 10) * ratio)
                    let height = width / ratio
                    PreviewCanvasEditor(model: model, image: preview, edit: editPreviewClip)
                        .frame(width: width, height: height)
                } else if model.document.scenes.isEmpty {
                    VStack(spacing: 10) { FrameMark(); Text(L("Construisez votre première scène")).font(.subheadline).foregroundStyle(.white.opacity(0.62)); Button(L("Ajouter un média")) { importingOverlay = false; showPhotos = true }.buttonStyle(.bordered) }
                } else { ProgressView() }
            }
        }
    }

    private func editPreviewClip(_ clip: Clip) {
        if clip.kind == .text {
            if clip.isCaption { openCaptionEditor(initialID: clip.id) }
            else { withAnimation(.easeOut(duration: 0.16)) { activeTool = .textEdit } }
        } else { visualTool = .transform; activeTool = .visual }
    }

    private var transport: some View {
        ZStack {
            HStack(spacing: 5) {
                Button { model.stop(); showFullScreenPreview = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 36)
                }
                .accessibilityLabel(L("Plein écran"))
                .accessibilityIdentifier("fullScreenPreview")
                .disabled(model.preview == nil)
                Text(timeLabel(model.playhead))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("currentTimecode")
                Text("/").font(.caption2).foregroundStyle(DesignTokens.muted)
                Text(timeLabel(model.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.muted)
                Spacer()
            }
            Button(action: model.togglePlayback) {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .disabled(model.duration <= 0)
            .accessibilityLabel(L(model.playing ? "Pause" : "Lire"))
            .accessibilityIdentifier("play")
        }
        .padding(.horizontal, 8)
        .frame(height: compact ? 36 : 40)
    }

    private func viewerTimelineDivider(height: CGFloat, range: ClosedRange<CGFloat>) -> some View {
        return ZStack {
            Color.clear
            Capsule()
                .fill(viewerDividerIsDragging ? DesignTokens.amber : .white.opacity(0.34))
                .frame(width: 38, height: viewerDividerIsDragging ? 4 : 3)
        }
            .frame(height: 22)
            .zIndex(10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if viewerHeightAtDragStart == nil {
                            viewerHeightAtDragStart = height
                            viewerDividerIsDragging = true
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        let origin = viewerHeightAtDragStart ?? height
                        let target = min(range.upperBound, max(range.lowerBound, origin + value.translation.height))
                        let liveHeight = (target / 2).rounded() * 2
                        if abs((viewerHeight ?? height) - liveHeight) >= 1.5 {
                            var transaction = Transaction()
                            transaction.animation = nil
                            withTransaction(transaction) { viewerHeight = liveHeight }
                        }
                    }
                    .onEnded { value in
                        let origin = viewerHeightAtDragStart ?? height
                        let target = min(range.upperBound, max(range.lowerBound, origin + value.translation.height))
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            viewerHeight = target
                            viewerHeightAtDragStart = nil
                            viewerDividerIsDragging = false
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(L("Redimensionner l’aperçu et la timeline"))
            .accessibilityValue("\(Int(height)) pt")
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat = direction == .increment ? 24 : -24
                viewerHeight = min(range.upperBound, max(range.lowerBound, height + delta))
            }
            .accessibilityIdentifier("viewerTimelineDivider")
    }

    private var contextualBar: some View {
        VStack(spacing: 0) {
        if model.selectedClip?.isCaption == true {
            CaptionScopePicker(model: model)
                .padding(.horizontal, 14).padding(.vertical, 5)
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                switch model.selectionKind {
                case .none: noSelectionActions
                case .video: videoActions
                case .text: textActions
                case .audio: audioActions
                case .overlay: overlayActions
                }
            }.padding(.horizontal, 5)
        }
        .frame(height: compact ? 56 : 62).background(DesignTokens.panel.opacity(0.95))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
        .accessibilityIdentifier("contextualToolbar")
        }.background(DesignTokens.panel.opacity(0.95))
    }

    @ViewBuilder private var noSelectionActions: some View {
        Menu { mediaMenuItems } label: { ContextActionLabel(title: "Médias", symbol: "photo.on.rectangle.angled") }.accessibilityIdentifier("addMedia")
        Menu { audioMenuItems } label: { ContextActionLabel(title: "Audio", symbol: "waveform") }
        Menu { textMenuItems } label: { ContextActionLabel(title: "Texte", symbol: "textformat") }
        Menu { overlayMenuItems } label: { ContextActionLabel(title: "Overlay", symbol: "square.on.square") }
        Menu { effectsMenuItems } label: { ContextActionLabel(title: "Effets", symbol: "sparkles") }
        formatMenu
    }

    @ViewBuilder private var videoActions: some View {
        action("Diviser", "scissors", perform: splitSelected, identifier: "action-Split")
        tool("Vitesse", "speedometer", .speed); tool("Volume", "speaker.wave.2", .volume); tool("Animation", "diamond", .animation); tool("Effets", "camera.filters", .visual); cutoutAction; moreMenu
    }
    @ViewBuilder private var textActions: some View {
        if model.selectedClip?.isCaption == true {
            action("Modifier", "pencil", perform: { openCaptionEditor(initialID: model.selectedClipID) }, identifier: "action-EditCaptions")
        } else {
            tool("Modifier", "pencil", .textEdit)
        }
        tool("Style", "paintbrush", .textStyle); tool("Police", "textformat.size", .font); tool("Animation", "diamond", .animation); tool("Effets", "camera.filters", .visual)
        action("Dupliquer", "doc.on.doc", perform: duplicateSelected); action("Supprimer", "trash", destructive: true, perform: model.deleteClip)
    }
    @ViewBuilder private var audioActions: some View {
        action("Diviser", "scissors", perform: splitSelected, identifier: "action-Split"); tool("Volume", "speaker.wave.2", .volume); tool("Fondu", "waveform.path", .fade); tool("Vitesse", "speedometer", .speed)
        action("Dupliquer", "doc.on.doc", perform: duplicateSelected); action("Supprimer", "trash", destructive: true, perform: model.deleteClip)
    }
    @ViewBuilder private var overlayActions: some View {
        tool("Effets", "camera.filters", .visual)
        if let clip = model.selectedClip, clip.kind == .image || clip.kind == .video { cutoutAction }
        tool("Animation", "diamond", .animation)
        action("Dupliquer", "doc.on.doc", perform: duplicateSelected); action("Supprimer", "trash", destructive: true, perform: model.deleteClip)
    }

    private var cutoutAction: some View {
        let selected = model.presentation.removePersonBackground
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            model.togglePersonBackgroundRemoval()
        } label: {
            ContextActionLabel(title: "Détourer", symbol: "person.crop.rectangle")
                .background(selected ? DesignTokens.amber.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(L(selected ? "Activé" : "Désactivé"))
        .accessibilityIdentifier("action-RemoveBackground")
    }

    private func action(_ title: String, _ symbol: String, destructive: Bool = false, perform: @escaping () -> Void, identifier: String? = nil) -> some View {
        Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); perform() } label: { ContextActionLabel(title: title, symbol: symbol, destructive: destructive) }.accessibilityIdentifier(identifier ?? "action-\(title)")
    }
    private func tool(_ title: String, _ symbol: String, _ value: ContextTool) -> some View {
        Button { UISelectionFeedbackGenerator().selectionChanged(); withAnimation(.easeOut(duration: 0.16)) { activeTool = activeTool == value ? nil : value } } label: { ContextActionLabel(title: title, symbol: symbol).background(activeTool == value ? DesignTokens.amber.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 12)) }
            .accessibilityAddTraits(activeTool == value ? .isSelected : []).accessibilityIdentifier("tool-\(value.rawValue)")
    }

    private var formatMenu: some View {
        Menu {
            Section(L("Format actif")) { ForEach(model.document.variants) { variant in Button { model.changeVariant(variant.id) } label: { if variant.id == model.variantID { Label(L(variant.name), systemImage: "checkmark") } else { Text(L(variant.name)) } } } }
            Button(L("Canevas et formats"), systemImage: "aspectratio") { showCanvas = true }
            Button(L("Comparer les formats"), systemImage: "rectangle.on.rectangle") { model.stop(); showCompare = true }
        } label: { ContextActionLabel(title: "Format", symbol: "aspectratio") }.accessibilityIdentifier("formatTool")
    }
    private var moreMenu: some View {
        Menu {
            Button(L("Suivre un objet (Vision)"), systemImage: "viewfinder") { showVision = true }
            Button(L("Stabiliser la vidéo (Vision)"), systemImage: "camera.metering.center.weighted") { showStabilization = true }
            Button(L("Précision temporelle"), systemImage: "timer") { showTiming = true }
            Button(L("Extraire le son"), systemImage: "waveform", action: extractAudio)
            Button(L("Sous-titres automatiques"), systemImage: "waveform.and.mic") { model.stop(); showTranscription = true }
            Button(L("Modifier les sous-titres"), systemImage: "captions.bubble") { openCaptionEditor(initialID: nil) }
            Button(L("Arrêt sur image"), systemImage: "camera", action: freezeFrame)
            Button(L("Remplacer le média"), systemImage: "arrow.triangle.2.circlepath") { replaceID = model.selectedClipID; importingOverlay = false; showFiles = true }
            Button(L("Dupliquer"), systemImage: "doc.on.doc", action: duplicateSelected)
            if model.selectedClip?.isCaption == true { Button(L("Supprimer la piste de sous-titres"), systemImage: "captions.bubble", role: .destructive) { confirmDeleteCaptionTrack = true } }
            Button(L("Supprimer"), systemImage: "trash", role: .destructive, action: model.deleteClip)
        } label: { ContextActionLabel(title: "Plus", symbol: "ellipsis") }
    }

    @ViewBuilder private var mediaMenuItems: some View {
        Button(L("Photos et vidéos"), systemImage: "photo.on.rectangle.angled") { importingOverlay = false; replaceID = nil; showPhotos = true }
        Button(L("Fichiers"), systemImage: "folder") { importingOverlay = false; replaceID = nil; showFiles = true }
        Button(L("Ressources locales"), systemImage: "rectangle.stack") { showMediaLibrary = true }
    }
    @ViewBuilder private var audioMenuItems: some View {
        Button(L("Musique"), systemImage: "music.note") { showMediaLibrary = true }
        Button(L("Effets sonores"), systemImage: "waveform.badge.plus") { showMediaLibrary = true }
        Button(L("Voix off"), systemImage: "mic") { model.stop(); showVoice = true }
        Button(L("Synthèse vocale"), systemImage: "text.bubble") { model.stop(); showNarration = true }
    }
    @ViewBuilder private var textMenuItems: some View {
        Button(L("Ajouter du texte"), systemImage: "textformat") { model.addText() }
        Button(L("Sous-titres"), systemImage: "captions.bubble") { model.addText(caption: true) }
        Button(L("Sous-titres automatiques"), systemImage: "waveform.and.mic") { model.stop(); showTranscription = true }
        Button(L("Importer un SRT"), systemImage: "doc.text") { importingOverlay = false; showFiles = true }
    }
    @ViewBuilder private var overlayMenuItems: some View {
        Button(L("Photos et vidéos"), systemImage: "photo.on.rectangle.angled") { importingOverlay = true; replaceID = nil; showPhotos = true }
        Button(L("Fichiers"), systemImage: "folder") { importingOverlay = true; replaceID = nil; showFiles = true }
        Button(L("Forme"), systemImage: "circle.square") { model.addShape() }
    }
    @ViewBuilder private var effectsMenuItems: some View {
        Button(L("Transition"), systemImage: "rectangle.2.swap") { if let scene = model.selectedScene { model.selectScene(scene); showSceneEdit = true } }.disabled(model.selectedScene == nil)
        Button(L("Repères rythmiques"), systemImage: "metronome") { showBeats = true }
    }

    private func splitSelected() { guard let id = model.selectedClipID, let clip = model.plan.clips.first(where: { $0.id == id }) else { return }; let local = MediaTime(seconds: model.playhead) - clip.globalStart; model.edit(L("Scinder")) { _ = try DocumentEditor.splitClip(id, at: local, in: &$0) } }
    private func openCaptionEditor(initialID: UUID?) {
        captionEditorInitialID = initialID
        model.stop()
        DispatchQueue.main.async { showCaptions = true }
    }
    private func duplicateSelected() { if let id = model.selectedClipID { model.edit(L("Dupliquer")) { _ = try DocumentEditor.duplicateClip(id, in: &$0) } } }
    private func extractAudio() {
        guard var clip = model.selectedClip, let id = model.selectedClipID else { return }; clip.id = UUID(); clip.kind = .audio; clip.muted = false; clip.layer = 0
        model.edit(L("Extraire le son")) { document in document.updateClip(id) { $0.muted = true }; if let index = document.scenes.firstIndex(where: { $0.id == model.selectedSceneID }) { document.scenes[index].clips.append(clip) } else { document.globalClips.append(clip) } }
    }
    private func freezeFrame() {
        guard let clip = model.selectedClip, let asset = model.document.asset(clip.assetID), let rendered = model.plan.clips.first(where: { $0.id == clip.id }) else { return }
        let source = TimeMapping.sourceTime(for: .init(seconds: max(0, model.playhead - rendered.globalStart.seconds)), clip: clip); model.busy = L("Préparation…")
        Task { defer { model.busy = nil }; do {
            let av = AVURLAsset(url: model.rootURL.appendingPathComponent(asset.relativePath)); let generator = AVAssetImageGenerator(asset: av); generator.appliesPreferredTrackTransform = true; generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let image = try await generator.image(at: CMTime(seconds: source.seconds, preferredTimescale: 60_000)).image
            let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png"); guard let data = UIImage(cgImage: image).pngData() else { return }; try data.write(to: url); model.importFiles([url], asOverlay: false, replaceID: clip.id)
        } catch { model.error = error.localizedDescription } }
    }
    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }; model.busy = L("Import…")
        Task { do { var urls: [URL] = []; for item in items { if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) { if let value = try await item.loadTransferable(type: ImportedMovie.self) { urls.append(value.url) } } else if let value = try await item.loadTransferable(type: ImportedImage.self) { urls.append(value.url) } }; photos = []; model.importFiles(urls, asOverlay: importingOverlay, replaceID: replaceID) } catch { model.busy = nil; model.error = error.localizedDescription } }
    }
    private func importURLs(_ urls: [URL]) { let captions = urls.filter { $0.pathExtension.lowercased() == "srt" }; for url in captions { model.importSRT(url) }; let media = urls.filter { $0.pathExtension.lowercased() != "srt" }; if !media.isEmpty { model.importFiles(media, asOverlay: importingOverlay, replaceID: replaceID) } }
}

private struct FullScreenPreview: View {
    @ObservedObject var model: EditorModel
    let close: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let preview = model.preview { Image(decorative: preview, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel(L("Aperçu plein écran")) } else { ProgressView().tint(.white) }
            VStack(spacing: 0) {
                HStack { Button(action: close) { Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44).background(.black.opacity(0.62), in: Circle()) }.accessibilityLabel(L("Quitter le plein écran")).accessibilityIdentifier("closeFullScreenPreview"); Spacer(); Text(model.variant.name).font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(height: 34).background(.black.opacity(0.62), in: Capsule()) }.padding(.horizontal, 16).padding(.top, 10)
                Spacer()
                VStack(spacing: 10) {
                    Slider(value: Binding(get: { min(model.playhead, max(model.duration, 0.001)) }, set: { model.seek($0) }), in: 0...max(model.duration, 0.001)).tint(DesignTokens.amber).accessibilityLabel(L("Instant"))
                    HStack(spacing: 14) { Button(action: model.togglePlayback) { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 19, weight: .semibold)).frame(width: 44, height: 44).background(DesignTokens.amber, in: Circle()).foregroundStyle(DesignTokens.ink) }.accessibilityLabel(L(model.playing ? "Pause" : "Lire")).accessibilityIdentifier("fullScreenPlay"); Text("\(timeLabel(model.playhead)) / \(timeLabel(model.duration))").font(.system(size: 12, weight: .medium, design: .monospaced)); Spacer() }
                }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 16).background(.black.opacity(0.68))
            }
        }.foregroundStyle(.white).preferredColorScheme(.dark).statusBarHidden(true).persistentSystemOverlays(.hidden).onAppear { model.setFullScreenPreview(true) }.onDisappear { model.stop(); model.setFullScreenPreview(false) }
    }
}

func clipSymbol(_ kind: ClipKind) -> String { switch kind { case .video: "film"; case .image: "photo"; case .audio: "waveform"; case .text: "textformat"; case .shape: "circle.square" } }
