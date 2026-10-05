import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct EditorScreen: View {
    @ObservedObject var model: EditorModel
    let close: () -> Void
    @AppStorage("reversedLayout") private var reversed = false
    @AppStorage("editorPreviewHeightFraction") private var previewHeightFraction = 0.30
    @State private var photos: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showExport = false
    @State private var showCompare = false
    @State private var showVoice = false
    @State private var showNarration = false
    @State private var showTranscription = false
    @State private var showTiming = false
    @State private var showVision = false
    @State private var showStabilization = false
    @State private var showMediaLibrary = false
    @State private var showCanvas = false
    @State private var showBeats = false
    @State private var importingOverlay = false
    @State private var replaceID: UUID?
    @State private var draggingScene: UUID?
    @State private var previewTransform: Presentation?
    @State private var previewDrag: Presentation?
    @State private var showSceneEdit = false
    @State private var showFullScreenPreview = false
    @State private var confirmDeleteCaptionTrack = false
    @GestureState private var previewResizeTranslation: CGFloat = 0
    @State private var editingAreaExpandedForInspector = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compact: Bool { verticalSizeClass == .compact }
    private var editingAreaIsCollapsed: Bool { model.inspector != nil && !editingAreaExpandedForInspector }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let previewHeight = resizedPreviewHeight(totalHeight: geometry.size.height, landscape: landscape)
            VStack(spacing: 0) {
                header
                if landscape {
                    HStack(spacing: 10) {
                        if reversed, model.inspector != nil { inspectorPanel.frame(width: geometry.size.width * 0.35) }
                        previewArea.frame(maxWidth: .infinity)
                        if !reversed, model.inspector != nil { inspectorPanel.frame(width: geometry.size.width * 0.35) }
                    }.frame(height: previewHeight).padding(.horizontal, 14)
                    previewResizeHandle(totalHeight: geometry.size.height)
                    transport
                    editingArea
                } else {
                    previewArea.frame(height: previewHeight).padding(.horizontal, 16)
                    previewResizeHandle(totalHeight: geometry.size.height)
                    transport
                    if model.inspector != nil {
                        inspectorPanel
                            .frame(maxHeight: editingAreaIsCollapsed ? .infinity : max(140, geometry.size.height * 0.32))
                            .padding(.horizontal, 14)
                    }
                    editingArea
                }
                inspectorBar
            }
        }
        .background(DesignTokens.ink).foregroundStyle(.white).preferredColorScheme(.dark)
        // Keep the editor geometry stable while typing. The inspector owns its scroll view,
        // so shrinking the whole workspace for the keyboard only makes the lower editor jump.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay {
            if showFullScreenPreview {
                FullScreenPreview(model: model) { showFullScreenPreview = false }
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .statusBarHidden(showFullScreenPreview)
        .photosPicker(isPresented: $showPhotos, selection: $photos, maxSelectionCount: 30, selectionBehavior: .ordered, matching: .any(of: [.images, .videos]))
        .onChange(of: photos) { _, items in importPhotos(items) }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .image, .audio, .plainText], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): importURLs(urls); case .failure(let e): model.error = e.localizedDescription }
        }
        .sheet(isPresented: $showExport) { ExportScreen(model: model) }
        .sheet(isPresented: $showCompare) { VariantComparison(model: model) }
        .sheet(isPresented: $showVoice) { VoiceoverSheet(model: model) }
        .sheet(isPresented: $showNarration) { NarrationSheet(model: model) }
        .sheet(isPresented: $showTranscription) { TranscriptionSheet(model: model) }
        .sheet(isPresented: $showStabilization) { StabilizationSheet(model: model) }
        .sheet(isPresented: $showVision) { VisionSheet(model: model) }
        .sheet(isPresented: $showMediaLibrary) { MediaLibrarySheet(model: model) }
        .sheet(isPresented: $showCanvas) { CanvasSheet(model: model) }
        .sheet(isPresented: $showBeats) { BeatMarkersSheet(model: model) }
        .sheet(isPresented: Binding(get: { !model.pendingImports.isEmpty }, set: { if !$0 { model.pendingImports = [] } })) { ImportReviewSheet(model: model) }
        .sheet(isPresented: $showTiming) { TimingSheet(model: model) }
        .sheet(isPresented: $showSceneEdit) { SceneEditSheet(model: model) }
        .confirmationDialog(L("Supprimer la piste de sous-titres ?"), isPresented: $confirmDeleteCaptionTrack, titleVisibility: .visible) {
            Button(L("Supprimer tous les sous-titres"), role: .destructive) { model.deleteCaptionTrack() }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Tous les sous-titres du montage seront supprimés. Vous pourrez annuler cette action."))
        }
        .alert(L("Erreur"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(L("OK")) { model.error = nil } } message: { Text(model.error ?? "") }
        .overlay(alignment: .top) { if let busy = model.busy { HStack { ProgressView(); Text(busy).font(.subheadline); if busy.hasPrefix(L("Import…")) { Button(L("Annuler")) { model.cancelImport() } } }.padding(14).background(.regularMaterial, in: Capsule()).padding(.top, 56) } }
        .onChange(of: model.inspector) { _, inspector in
            if inspector != nil { editingAreaExpandedForInspector = false }
        }
        .onDisappear { model.stop(); model.save() }
    }
    private var header: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "chevron.left", label: model.inspector == nil ? "Bibliothèque" : "Fermer") { if model.inspector != nil { model.inspector = nil } else { close() } }.accessibilityIdentifier("editorBack")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.document.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Label(L(model.saved ? "Sauvegardé" : "Sauvegarde…"), systemImage: model.saved ? "checkmark.circle" : "circle.dotted").font(.system(size: 10)).foregroundStyle(DesignTokens.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            IconButton(symbol: "arrow.uturn.backward", label: "Annuler la modification", action: model.undo).disabled(!model.canUndo).opacity(model.canUndo ? 1 : 0.3)
            IconButton(symbol: "arrow.uturn.forward", label: "Rétablir", action: model.redo).disabled(!model.canRedo).opacity(model.canRedo ? 1 : 0.3)
            Button { model.stop(); showExport = true } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 42).background(DesignTokens.amber, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(DesignTokens.ink) }.padding(.trailing, 12).accessibilityLabel(L("Exporter")).accessibilityIdentifier("export")
        }.frame(height: compact ? 44 : 57)
    }
    private var previewArea: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.5))
                if let preview = model.preview {
                    Image(decorative: preview, scale: 1).resizable().scaledToFit().padding(6)
                        .gesture(DragGesture(minimumDistance: 6).onChanged { value in
                            guard model.selectedClip != nil, previewTransform == nil else { return }
                            if previewDrag == nil { previewDrag = model.presentation; model.beginGesture(L("Propriétés")) }
                            guard let origin = previewDrag, let id = model.selectedClipID else { return }
                            let ratio = model.variant.ratio
                            let w = min(geo.size.width - 12, (geo.size.height - 12) * ratio), h = w / ratio
                            var p = origin; p.x += value.translation.width / w; p.y += value.translation.height / h
                            let v = model.localScope ? model.variantID : nil
                            model.updateGesture { try DocumentEditor.setPresentation(p, clipID: id, variantID: v, in: &$0) }
                        }.onEnded { _ in if previewDrag != nil { model.endGesture(); previewDrag = nil } })
                        .simultaneousGesture(SimultaneousGesture(MagnificationGesture(), RotationGesture()).onChanged { value in
                            guard let id = model.selectedClipID else { return }
                            if previewTransform == nil {
                                if previewDrag != nil { model.endGesture(); previewDrag = nil }
                                previewTransform = model.presentation; model.beginGesture(L("Propriétés"))
                            }
                            guard var p = previewTransform else { return }
                            p.scale = min(4, max(0.1, p.scale * (value.first ?? 1)))
                            p.rotation += value.second?.degrees ?? 0
                            let variantID = model.localScope ? model.variantID : nil
                            model.updateGesture { try DocumentEditor.setPresentation(p, clipID: id, variantID: variantID, in: &$0) }
                        }.onEnded { _ in if previewTransform != nil { model.endGesture(); previewTransform = nil } })
                } else if model.document.scenes.isEmpty {
                    VStack(spacing: 12) { FrameMark(); Text(L("Construisez votre première scène")).font(.subheadline).foregroundStyle(.white.opacity(0.65)); Button(L("Ajouter un média")) { showPhotos = true }.buttonStyle(.bordered) }
                } else { ProgressView() }
                if previewDrag != nil {
                    Path { p in p.move(to: CGPoint(x: geo.size.width/2, y: 0)); p.addLine(to: CGPoint(x: geo.size.width/2, y: geo.size.height)); p.move(to: CGPoint(x: 0, y: geo.size.height/2)); p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height/2)) }.stroke(DesignTokens.amber.opacity(0.7), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])).allowsHitTesting(false)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            model.stop()
                            showFullScreenPreview = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.62), in: Circle())
                        }
                        .foregroundStyle(.white)
                        .accessibilityLabel(L("Plein écran"))
                        .accessibilityIdentifier("fullScreenPreview")
                        .disabled(model.preview == nil)
                    }
                    Spacer()
                }.padding(9)
            }
        }
    }
    private var transport: some View {
        HStack(spacing: 8) {
            IconButton(symbol: model.playing ? "pause.fill" : "play.fill", label: model.playing ? "Pause" : "Lire", tint: DesignTokens.amber, action: model.togglePlayback).disabled(model.duration <= 0).accessibilityIdentifier("play")
            Text("\(timeLabel(model.playhead)) / \(timeLabel(model.duration))").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(DesignTokens.muted).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 3) {
                ForEach(model.document.variants) { variant in
                    let selected = variant.id == model.variantID
                    Button { model.changeVariant(variant.id) } label: { Text("\(Int(variant.widthRatio)):\(Int(variant.heightRatio))").font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(minWidth: 38, minHeight: 38).background(selected ? DesignTokens.amber : DesignTokens.panel, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(selected ? DesignTokens.ink : .white.opacity(0.7)) }.accessibilityLabel("\(L("Format actif")) \(variant.name)").accessibilityAddTraits(selected ? .isSelected : [])
                }
            } }.fixedSize(horizontal: false, vertical: true)
            IconButton(symbol: "rectangle.on.rectangle", label: "Comparer les formats") { model.stop(); showCompare = true }
        }.padding(.horizontal, 8).frame(height: compact ? 38 : 48)
    }
    private func resizedPreviewHeight(totalHeight: CGFloat, landscape: Bool) -> CGFloat {
        let minimum: CGFloat = landscape ? 88 : 120
        let maximum = max(minimum, totalHeight * (landscape ? 0.48 : 0.52))
        let liveFraction = previewHeightFraction + Double(previewResizeTranslation / totalHeight)
        return min(maximum, max(minimum, totalHeight * CGFloat(liveFraction)))
    }
    private func previewResizeHandle(totalHeight: CGFloat) -> some View {
        HStack(spacing: 7) {
            Capsule().fill(.white.opacity(0.18)).frame(width: 34, height: 2)
            Image(systemName: "arrow.up.and.down").font(.system(size: 9, weight: .bold)).foregroundStyle(DesignTokens.muted)
            Capsule().fill(.white.opacity(0.18)).frame(width: 34, height: 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .updating($previewResizeTranslation) { value, translation, _ in
                    translation = value.translation.height
                }
                .onEnded { value in
                    previewHeightFraction = min(0.52, max(0.15, previewHeightFraction + Double(value.translation.height / totalHeight)))
                }
        )
        .transaction { transaction in transaction.animation = nil }
        .accessibilityElement()
        .accessibilityLabel(L("Taille de l’aperçu vidéo"))
        .accessibilityValue("\(Int(previewHeightFraction * 100)) %")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: previewHeightFraction = min(0.52, previewHeightFraction + 0.05)
            case .decrement: previewHeightFraction = max(0.15, previewHeightFraction - 0.05)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("previewResizeHandle")
    }
    private var editingArea: some View {
        Group {
            if editingAreaIsCollapsed {
                Button { editingAreaExpandedForInspector = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.mode == .story ? "list.bullet.rectangle" : "timeline.selection")
                        Text(L(model.mode.rawValue)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(L("Afficher")).font(.caption).foregroundStyle(DesignTokens.muted)
                        Image(systemName: "chevron.up").font(.caption.bold())
                    }
                    .padding(.horizontal, 16)
                    .frame(height: compact ? 38 : 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .background(DesignTokens.panel.opacity(0.45))
                .accessibilityLabel("\(L("Afficher")) \(L(model.mode.rawValue))")
                .accessibilityIdentifier(model.mode.rawValue)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: 0) { ForEach(EditorMode.allCases, id: \.self) { mode in Button { model.mode = mode } label: { Text(L(mode.rawValue)).font(.subheadline.weight(.semibold)).padding(.horizontal, 15).frame(height: 38).background(model.mode == mode ? DesignTokens.panel : .clear, in: Capsule()).foregroundStyle(model.mode == mode ? .white : DesignTokens.muted) }.accessibilityAddTraits(model.mode == mode ? .isSelected : []).accessibilityIdentifier(mode.rawValue) } }
                        Spacer(minLength: 0)
                        if model.inspector != nil {
                            Button { editingAreaExpandedForInspector = false } label: {
                                Image(systemName: "chevron.down")
                                    .font(.caption.bold())
                                    .frame(width: 38, height: 38)
                            }
                            .accessibilityLabel(L("Réduire le scénario ou la timeline"))
                            .accessibilityIdentifier("collapseEditingArea")
                        }
                        addMenu
                    }.padding(.horizontal, 16).padding(.vertical, compact ? 0 : 5)
                    if model.mode == .story { story }
                    else { TimelinePanel(model: model).frame(maxHeight: .infinity) }
                }.frame(maxHeight: .infinity)
            }
        }
    }
    private var story: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 8) {
                ForEach(Array(model.document.scenes.enumerated()), id: \.element.id) { index, scene in
                    sceneRow(scene, index: index)
                        .draggable(scene.id.uuidString) { Text(scene.title).padding().background(DesignTokens.panel) }
                        .dropDestination(for: String.self) { items, _ in guard let value = items.first, let id = UUID(uuidString: value) else { return false }; model.edit(L("Scénario")) { try DocumentEditor.reorderScene(id, to: index, in: &$0) }; return true }

                }
                if !model.document.globalClips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("Projet entier"), systemImage: "pin.fill").font(.caption.weight(.semibold)).foregroundStyle(DesignTokens.teal)
                        ForEach(model.document.globalClips) { clip in Button { if let rendered = model.plan.clips.first(where: { $0.id == clip.id }) { model.selectClip(rendered); model.inspector = clip.kind == .audio ? .audio : .image } } label: { HStack { Image(systemName: clip.kind == .audio ? "waveform" : "square.on.square"); Text(model.document.asset(clip.assetID)?.name ?? clip.text).lineLimit(1); Spacer(); Text(timeLabel(clip.duration.seconds)).monospacedDigit() }.font(.caption).frame(minHeight: 36) }.foregroundStyle(.white.opacity(0.8)) }
                    }.padding(12).background(DesignTokens.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
            }.frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.bottom, 10)
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("storyScroll")
    }
    private func sceneRow(_ scene: Scene, index: Int) -> some View {
        HStack(spacing: 12) {
            Button { model.selectScene(scene) } label: { HStack(spacing: 12) {
            Text(String(format: "%02d", index + 1)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(model.selectedSceneID == scene.id ? DesignTokens.amber : DesignTokens.muted)
            ZStack { RoundedRectangle(cornerRadius: 8).fill(DesignTokens.ink); if let image = model.thumbnails[scene.id] { Image(decorative: image, scale: 1).resizable().scaledToFill().frame(width: 48, height: 54).clipped() } }.frame(width: 48, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(scene.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) { Text(String(format: "%.1f s", scene.duration.seconds)); Text("·"); ForEach(Array(Set(scene.clips.map(\.kind))).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { Image(systemName: clipSymbol($0)) }; if model.selectedSceneID == scene.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignTokens.amber) } }.font(.system(size: 10)).foregroundStyle(DesignTokens.muted)
                if !scene.narration.isEmpty { Text(scene.narration).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            } }.buttonStyle(.plain)
            Menu { sceneMenu(scene, index: index) } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44).contentShape(Rectangle()) }.foregroundStyle(.white.opacity(0.7)).accessibilityLabel(L("Propriétés")).accessibilityIdentifier("sceneMenu-\(index)")
        }.padding(10).background(model.selectedSceneID == scene.id ? DesignTokens.panel : DesignTokens.panel.opacity(0.35), in: RoundedRectangle(cornerRadius: 13)).overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(model.selectedSceneID == scene.id ? DesignTokens.amber.opacity(0.6) : .clear, lineWidth: 1) }
    }
    @ViewBuilder private func sceneMenu(_ scene: Scene, index: Int) -> some View {
        Button(L("Propriétés"), systemImage: "slider.horizontal.3") { model.selectScene(scene); showSceneEdit = true }
        Menu(L("Calques")) { ForEach(scene.clips) { clip in Button(clip.text.isEmpty ? (model.document.asset(clip.assetID)?.name ?? L(clip.kind.rawValue)) : clip.text, systemImage: clipSymbol(clip.kind)) { if let rendered = model.plan.clips.first(where: { $0.id == clip.id }) { model.selectClip(rendered); model.inspector = clip.kind == .text ? .text : clip.kind == .audio ? .audio : .image } } } }
        Button(L("Déplacer avant"), systemImage: "arrow.up") { model.moveScene(scene.id, by: -1) }.disabled(index == 0)
        Button(L("Déplacer après"), systemImage: "arrow.down") { model.moveScene(scene.id, by: 1) }.disabled(index == model.document.scenes.count - 1)
        Button(L("Dupliquer"), systemImage: "doc.on.doc") { model.edit(L("Dupliquer")) { _ = try DocumentEditor.duplicateScene(scene.id, in: &$0) } }
        Button(L("Scinder la scène"), systemImage: "scissors") { let offset = model.playhead - (model.plan.scenes.first { $0.id == scene.id }?.start.seconds ?? 0); model.edit(L("Scinder la scène")) { _ = try DocumentEditor.splitScene(scene.id, at: .init(seconds: offset), in: &$0) } }
        if index + 1 < model.document.scenes.count { Button(L("Regrouper avec la suivante"), systemImage: "rectangle.3.group") { let next = model.document.scenes[index + 1].id; model.edit(L("Regrouper avec la suivante")) { _ = try DocumentEditor.groupScenes([scene.id, next], in: &$0) } } }
        Button(L("Supprimer"), systemImage: "trash", role: .destructive) { model.edit(L("Supprimer")) { try DocumentEditor.removeScene(scene.id, in: &$0) } }
    }
    private var addMenu: some View {
        Menu {
            Button(L("Canevas"), systemImage: "aspectratio") { showCanvas = true }
            Button(L("Repères rythmiques"), systemImage: "metronome") { showBeats = true }
            Button(L("Photos et vidéos"), systemImage: "photo.on.rectangle.angled") { importingOverlay = false; replaceID = nil; showPhotos = true }
            Button(L("Ressources locales"), systemImage: "rectangle.stack") { showMediaLibrary = true }
            Button(L("Fichiers"), systemImage: "folder") { importingOverlay = false; replaceID = nil; showFiles = true }
            Button("Superposition", systemImage: "square.on.square") { importingOverlay = true; replaceID = nil; showPhotos = true }
            Button(L("Texte libre"), systemImage: "textformat") { model.addText() }
            Button(L("Sous-titres"), systemImage: "captions.bubble") { model.addText(caption: true) }
            Button(L("Forme"), systemImage: "circle.square") { model.addShape() }
            Button(L("Voix off"), systemImage: "mic") { model.stop(); showVoice = true }
            Button(L("Synthétiser la narration"), systemImage: "waveform") { model.stop(); showNarration = true }
            Button(L("Générer les sous-titres"), systemImage: "captions.bubble") { model.stop(); showTranscription = true }
        } label: { Label(L("Ajouter"), systemImage: "plus").font(.caption.weight(.semibold)).frame(height: 38).padding(.horizontal, 11).foregroundStyle(DesignTokens.amber) }.accessibilityIdentifier("addMedia")
    }
    private var inspectorBar: some View {
        HStack(spacing: 0) {
            ForEach(InspectorTab.allCases, id: \.self) { tab in Button { model.inspector = model.inspector == tab ? nil : tab } label: { VStack(spacing: 4) { Image(systemName: tab == .image ? "slider.horizontal.3" : tab == .audio ? "waveform" : tab == .text ? "textformat" : "diamond").font(.system(size: 17)); Text(L(tab.rawValue)).font(.system(size: 10, weight: .medium)) }.frame(maxWidth: .infinity).frame(height: compact ? 44 : 51).foregroundStyle(model.inspector == tab ? DesignTokens.amber : .white.opacity(0.75)) }.disabled(model.selectedClip == nil) }
            Menu {
                Button(L("Scinder"), systemImage: "scissors") { splitSelected() }
                Button(L("Dupliquer"), systemImage: "doc.on.doc") { if let id = model.selectedClipID { model.edit(L("Dupliquer")) { _ = try DocumentEditor.duplicateClip(id, in: &$0) } } }
                Button(L("Suivre un objet (Vision)"), systemImage: "viewfinder") { showVision = true }.disabled(model.selectedClip?.kind != .text && model.selectedClip?.kind != .shape)
                Button(L("Précision temporelle"), systemImage: "timer") { showTiming = true }
                Button(L("Remplacer le média"), systemImage: "arrow.triangle.2.circlepath") { replaceID = model.selectedClipID; showFiles = true }
                Button(L("Extraire le son"), systemImage: "waveform") { extractAudio() }.disabled(model.selectedClip?.kind != .video)
                Button(L("Stabiliser la vidéo (Vision)"), systemImage: "camera.metering.center.weighted") { showStabilization = true }.disabled(model.selectedClip?.kind != .video)
                Button(L("Inverser la vidéo (son coupé)"), systemImage: "backward") { model.changeClip(L("Vitesse")) { $0.reversed.toggle(); if $0.reversed { $0.muted = true } } }.disabled(model.selectedClip?.kind != .video)
                Button(L("Arrêt sur image"), systemImage: "camera") { freezeFrame() }.disabled(model.selectedClip?.kind != .video)
                if model.selectedClip?.isCaption == true {
                    Button(L("Supprimer la piste de sous-titres"), systemImage: "captions.bubble", role: .destructive) { confirmDeleteCaptionTrack = true }
                }
                Button(L("Supprimer"), systemImage: "trash", role: .destructive, action: model.deleteClip)
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: compact ? 44 : 51) }.disabled(model.selectedClip == nil)
        }.padding(.horizontal, 8).background(DesignTokens.panel.opacity(0.6))
    }
    private var inspectorPanel: some View { InspectorPanel(model: model).clipShape(RoundedRectangle(cornerRadius: 14)) }
    private func splitSelected() { guard let id = model.selectedClipID, let c = model.plan.clips.first(where: { $0.id == id }) else { return }; let local = MediaTime(seconds: model.playhead) - c.globalStart; model.edit(L("Scinder")) { _ = try DocumentEditor.splitClip(id, at: local, in: &$0) } }
    private func extractAudio() {
        guard var clip = model.selectedClip, let id = model.selectedClipID else { return }
        clip.id = UUID(); clip.kind = .audio; clip.muted = false; clip.layer = 0
        model.edit(L("Extraire le son")) { d in d.updateClip(id) { $0.muted = true }; if let i = d.scenes.firstIndex(where: { $0.id == model.selectedSceneID }) { d.scenes[i].clips.append(clip) } else { d.globalClips.append(clip) } }
    }
    private func freezeFrame() {
        guard let clip = model.selectedClip, let asset = model.document.asset(clip.assetID), let rendered = model.plan.clips.first(where: { $0.id == clip.id }) else { return }
        let source = TimeMapping.sourceTime(for: .init(seconds: max(0, model.playhead - rendered.globalStart.seconds)), clip: clip)
        model.busy = L("Préparation…")
        Task { defer { model.busy = nil }; do {
            let av = AVURLAsset(url: model.rootURL.appendingPathComponent(asset.relativePath)); let generator = AVAssetImageGenerator(asset: av); generator.appliesPreferredTrackTransform = true; generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let image = try await generator.image(at: CMTime(seconds: source.seconds, preferredTimescale: 60_000)).image
            let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png"); guard let data = UIImage(cgImage: image).pngData() else { return }; try data.write(to: url)
            model.importFiles([url], asOverlay: false, replaceID: clip.id)
        } catch { model.error = error.localizedDescription } }
    }
    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        model.busy = L("Import…")
        Task { do { var urls: [URL] = []; for item in items { if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) { if let value = try await item.loadTransferable(type: ImportedMovie.self) { urls.append(value.url) } } else if let value = try await item.loadTransferable(type: ImportedImage.self) { urls.append(value.url) } }; photos = []; model.importFiles(urls, asOverlay: importingOverlay, replaceID: replaceID) } catch { model.busy = nil; model.error = error.localizedDescription } }
    }
    private func importURLs(_ urls: [URL]) {
        let captions = urls.filter { $0.pathExtension.lowercased() == "srt" }
        for url in captions { model.importSRT(url) }
        let media = urls.filter { $0.pathExtension.lowercased() != "srt" }
        if !media.isEmpty { model.importFiles(media, asOverlay: importingOverlay, replaceID: replaceID) }
    }
}

private struct FullScreenPreview: View {
    @ObservedObject var model: EditorModel
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let preview = model.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(L("Aperçu plein écran"))
            } else {
                ProgressView().tint(.white)
            }

            VStack(spacing: 0) {
                    HStack {
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.62), in: Circle())
                        }
                        .accessibilityLabel(L("Quitter le plein écran"))
                        .accessibilityIdentifier("closeFullScreenPreview")
                        Spacer()
                        Text(model.variant.name)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(.black.opacity(0.62), in: Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    Spacer()

                    VStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { min(model.playhead, max(model.duration, 0.001)) },
                                set: { model.seek($0) }
                            ),
                            in: 0...max(model.duration, 0.001)
                        )
                        .tint(DesignTokens.amber)
                        .accessibilityLabel(L("Instant"))
                        HStack(spacing: 14) {
                            Button(action: model.togglePlayback) {
                                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 19, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(DesignTokens.amber, in: Circle())
                                    .foregroundStyle(DesignTokens.ink)
                            }
                            .accessibilityLabel(L(model.playing ? "Pause" : "Lire"))
                            .accessibilityIdentifier("fullScreenPlay")
                            Text("\(timeLabel(model.playhead)) / \(timeLabel(model.duration))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                    .background(.black.opacity(0.68))
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { model.setFullScreenPreview(true) }
        .onDisappear {
            model.stop()
            model.setFullScreenPreview(false)
        }
    }
}

func clipSymbol(_ kind: ClipKind) -> String { switch kind { case .video: "film"; case .image: "photo"; case .audio: "waveform"; case .text: "textformat"; case .shape: "circle.square" } }

import AVFoundation
