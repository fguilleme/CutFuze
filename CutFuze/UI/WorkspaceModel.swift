import SwiftUI
import Combine
import AVFoundation
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

@MainActor
final class WorkspaceModel: ObservableObject {
    let store: ProjectStore
    let rootURL: URL
    @Published var projects: [ProjectDocument] = []
    @Published var editor: EditorModel?
    @Published var error: String?
    @Published var busy = false
    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? URL.documentsDirectory.appending(path: "CutFuze", directoryHint: .isDirectory)
        store = ProjectStore(rootURL: self.rootURL)
        refresh()
    }
    func refresh() { do { projects = try store.list().sorted { $0.modifiedAt > $1.modifiedAt } } catch { self.error = error.localizedDescription } }
    func open(_ document: ProjectDocument) { editor = EditorModel(document: document, store: store, rootURL: rootURL) }
    func create() {
        do { let d = ProjectDocument(title: L("Nouvelle histoire")); try store.save(document: d); refresh(); open(d) } catch { self.error = error.localizedDescription }
    }
    func close() { editor?.stop(); editor?.save(); if let error = editor?.error { self.error = error }; editor = nil; refresh() }
    func delete(_ document: ProjectDocument) { do { try store.delete(id: document.id); refresh() } catch { self.error = error.localizedDescription } }
    func duplicate(_ document: ProjectDocument) { do { _ = try store.duplicate(document: document); refresh() } catch { self.error = error.localizedDescription } }
    func update(_ document: ProjectDocument, title: String, collection: String) { do { var copy = document; copy.title = title; copy.collection = collection; copy.modifiedAt = Date(); try store.save(document: copy); refresh() } catch { self.error = error.localizedDescription } }
    func importProject(_ url: URL) {
        busy = true
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() }; busy = false }
            do {
                let store = self.store
                let d = try await Task.detached { try PortableProject.importPackage(from: url, into: store) }.value
                refresh(); open(d)
            } catch { self.error = error.localizedDescription }
        }
    }
    func demo() {
        busy = true
        Task { defer { busy = false }; do { let d = try await DemoFactory.make(in: rootURL); try store.save(document: d); refresh(); open(d) } catch { self.error = error.localizedDescription } }
    }
}

enum EditorMode: String, CaseIterable { case story = "Scénario", timeline = "Timeline" }
enum InspectorTab: String, CaseIterable { case image = "Image", audio = "Son", text = "Texte", animation = "Animation" }
enum EditorSelectionKind: Equatable {
    case none, video, text, audio, overlay
}
enum ImportPlacement: String, CaseIterable, Identifiable {
    case append
    case afterSelection
    case overlay
    var id: Self { self }
    var requiresScene: Bool { self != .append }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published private(set) var document: ProjectDocument
    @Published var selectedClipID: UUID?
    @Published var selectedSceneID: UUID?
    @Published var variantID: UUID
    @Published var playhead = 0.0
    @Published var mode: EditorMode = .timeline
    @Published var inspector: InspectorTab?
    @Published var localScope = true
    @Published var preview: CGImage?
    @Published var playing = false
    @Published private(set) var isFullScreenPreview = false
    @Published var saved = true
    @Published var error: String?
    @Published var busy: String?
    @Published var pendingImports: [MediaAsset] = []
    private var pendingOverlay = false
    private var pendingReplacement: UUID?
    private var importTask: Task<Void, Never>?
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var thumbnails: [UUID: CGImage] = [:]
    @Published var assetThumbnails: [UUID: CGImage] = [:]
    @Published var clipThumbnails: [UUID: [CGImage]] = [:]
    let store: ProjectStore
    let rootURL: URL
    let renderer = FrameRenderer()
    private let history: EditHistory
    private var saveTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var previewGeneration = 0
    private var audioPlayer: AVPlayer?
    private var audioRevision: Int = -1
    private var selectionUndo: [(UUID?, UUID?, Double)] = []
    private var selectionRedo: [(UUID?, UUID?, Double)] = []
    private var gestureActive = false
    private var transactionSelection: (UUID?, UUID?, Double)?
    init(document: ProjectDocument, store: ProjectStore, rootURL: URL) {
        self.document = document; self.store = store; self.rootURL = rootURL
        history = EditHistory(document: document)
        variantID = document.variants[0].id
        selectedSceneID = document.scenes.first?.id
        selectedClipID = nil
        requestPreview(); refreshThumbnails()
    }
    var plan: RenderPlan { RenderPlan.compile(document: document, variantID: variantID) }
    var variant: OutputVariant { plan.variant }
    var selectedClip: Clip? { document.clip(selectedClipID) }
    var selectionKind: EditorSelectionKind {
        guard let clip = selectedClip else { return .none }
        if clip.kind == .text { return .text }
        if clip.kind == .audio { return .audio }
        if clip.kind == .shape || clip.layer > 0 { return .overlay }
        return .video
    }
    var selectedScene: Scene? { document.scenes.first { $0.id == selectedSceneID } }
    var presentation: Presentation { selectedClip.map { variant.overrides[$0.id.uuidString] ?? $0.presentation } ?? .init() }
    var duration: Double { document.duration.seconds }
    var isReplacingPendingImport: Bool { pendingReplacement != nil }
    var suggestedImportPlacement: ImportPlacement { pendingOverlay ? .overlay : .append }
    func releaseDerivedCaches() {
        stop(); previewGeneration += 1; previewTask?.cancel(); thumbnailTask?.cancel(); thumbnails.removeAll(); assetThumbnails.removeAll(); clipThumbnails.removeAll()
        Task { await renderer.clearCaches(); requestPreview() }
    }
    func edit(_ name: String, _ change: (inout ProjectDocument) throws -> Void) {
        stop()
        do {
            let selection = (selectedClipID, selectedSceneID, playhead)
            let before = history.document.revision
            try history.perform(name: name, change)
            if before != history.document.revision { selectionUndo.append(selection); selectionRedo.removeAll() }
            sync()
        } catch { self.error = error.localizedDescription }
    }
    func beginGesture(_ name: String) { stop(); gestureActive = true; transactionSelection = (selectedClipID, selectedSceneID, playhead); history.beginTransaction(name: name) }
    func updateGesture(_ change: (inout ProjectDocument) throws -> Void) {
        do { try history.updateTransaction(change); document = history.document; requestPreview() } catch { self.error = error.localizedDescription }
    }
    func endGesture() {
        gestureActive = false
        do { let revision = history.document.revision; try history.commitTransaction(); if revision != history.document.revision, let selection = transactionSelection { selectionUndo.append(selection); selectionRedo.removeAll() }; transactionSelection = nil; sync() } catch { self.error = error.localizedDescription }
    }
    private func sync() {
        document = history.document; canUndo = history.canUndo; canRedo = history.canRedo
        if document.clip(selectedClipID) == nil { selectedClipID = document.scenes.first?.clips.first?.id }
        if let id = selectedClipID { selectedSceneID = document.scenes.first(where: { $0.clips.contains(where: { $0.id == id }) })?.id }
        else if !document.scenes.contains(where: { $0.id == selectedSceneID }) { selectedSceneID = document.scenes.first?.id }
        playhead = min(playhead, max(0, duration - 1 / 30))
        saved = false; saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .milliseconds(350)); if !Task.isCancelled { save() } }
        thumbnails.removeAll(); assetThumbnails.removeAll(); clipThumbnails.removeAll(); requestPreview(); refreshThumbnails()
    }
    func undo() { stop(); selectionRedo.append((selectedClipID, selectedSceneID, playhead)); history.undo(); if let s = selectionUndo.popLast() { (selectedClipID, selectedSceneID, playhead) = s }; sync() }
    func redo() { stop(); selectionUndo.append((selectedClipID, selectedSceneID, playhead)); history.redo(); if let s = selectionRedo.popLast() { (selectedClipID, selectedSceneID, playhead) = s }; sync() }
    func save() { saveTask?.cancel(); do { try store.save(document: document); saved = true } catch { saved = false; self.error = error.localizedDescription } }
    func selectScene(_ scene: Scene) {
        selectedSceneID = scene.id; selectedClipID = scene.clips.first(where: { $0.kind != .audio })?.id
        seek(plan.scenes.first { $0.id == scene.id }?.start.seconds ?? 0)
    }
    func selectClip(_ clip: RenderClip) { selectedClipID = clip.id; selectedSceneID = clip.sceneID; seek(clip.globalStart.seconds) }
    func clearSelection() { selectedClipID = nil; inspector = nil }
    func displayName(for clip: Clip) -> String {
        if !clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return clip.text }
        guard let asset = document.asset(clip.assetID) else { return fallbackName(for: clip.kind) }
        return displayName(for: asset)
    }
    func displayName(for asset: MediaAsset) -> String {
        let raw = asset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var component = URL(fileURLWithPath: raw).deletingPathExtension().lastPathComponent
        let generatedSuffix = #"(?i)(?:[-_ ]?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$"#
        let beforeSuffix = component
        component = component.replacingOccurrences(of: generatedSuffix, with: "", options: .regularExpression)
        if component != beforeSuffix {
            component = component.replacingOccurrences(of: #"(?:[-_ ]+\d+){2,}$"#, with: "", options: .regularExpression)
        }
        component = component.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        if !component.isEmpty, UUID(uuidString: component) == nil { return component.prefix(1).uppercased() + component.dropFirst() }
        return fallbackName(for: asset.kind)
    }
    private func fallbackName(for kind: ClipKind) -> String {
        switch kind {
        case .video: return L("Vidéo")
        case .image: return L("Photo")
        case .audio: return L("Audio")
        case .text: return L("Texte")
        case .shape: return L("Forme")
        }
    }
    func seek(_ seconds: Double) { stop(); playhead = min(max(0, seconds), max(0, duration - 1 / 120)); requestPreview() }
    func changeVariant(_ id: UUID) { stop(); variantID = id; requestPreview() }
    func setFullScreenPreview(_ enabled: Bool) {
        guard isFullScreenPreview != enabled else { return }
        isFullScreenPreview = enabled
        requestPreview()
    }
    func requestPreview() {
        previewGeneration += 1
        let generation = previewGeneration, plan = self.plan, seconds = playhead, root = rootURL
        previewTask?.cancel()
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(25))
                let edge: Double = isFullScreenPreview ? 1280 : 640
                let size = CGSize(width: plan.variant.ratio >= 1 ? edge : edge * plan.variant.ratio, height: plan.variant.ratio >= 1 ? edge / plan.variant.ratio : edge)
                let image = try await renderer.render(plan: plan, time: .init(seconds: seconds), rootURL: root, size: size)
                if !Task.isCancelled && generation == previewGeneration { preview = image }
            } catch is CancellationError { } catch { if generation == previewGeneration { self.error = error.localizedDescription } }
        }
    }
    func refreshThumbnails() {
        let snapshot = document, root = rootURL
        thumbnailTask?.cancel()
        thumbnailTask = Task {
            let p = RenderPlan.compile(document: snapshot, variantID: snapshot.variants.first?.id)
            for scene in snapshot.scenes where thumbnails[scene.id] == nil {
                guard !Task.isCancelled, document.revision == snapshot.revision else { return }
                if let span = p.scenes.first(where: { $0.id == scene.id }), let image = try? await renderer.render(plan: p, time: span.start + .init(seconds: min(0.4, span.duration.seconds / 2)), rootURL: root, size: CGSize(width: 128, height: 160)) { if document.revision == snapshot.revision { thumbnails[scene.id] = image } }
            }
            for asset in snapshot.assets where asset.kind == .video || asset.kind == .image {
                guard !Task.isCancelled, document.revision == snapshot.revision else { return }
                if assetThumbnails[asset.id] == nil,
                   let image = try? await MediaImporter.shared.thumbnail(asset: asset, rootURL: root, maxSize: 180),
                   document.revision == snapshot.revision {
                    assetThumbnails[asset.id] = image
                }
            }
            for item in p.clips where item.clip.kind == .video || item.clip.kind == .image {
                guard !Task.isCancelled, document.revision == snapshot.revision,
                      clipThumbnails[item.id] == nil,
                      let asset = snapshot.asset(item.clip.assetID) else { continue }
                let sampleCount = asset.kind == .video ? min(24, max(3, Int(ceil(item.duration.seconds / 0.7)))) : 1
                if let frames = try? await MediaImporter.shared.timelineThumbnails(asset: asset, clip: item.clip, rootURL: root, sampleCount: sampleCount),
                   !Task.isCancelled, document.revision == snapshot.revision {
                    clipThumbnails[item.id] = frames
                }
            }
        }
    }
    func togglePlayback() {
        if playing { stop(); return }
        startPlayback(includeAudio: true)
    }
    func startPlayback(includeAudio: Bool) {
        guard !playing else { return }
        playing = true
        let snapshot = plan
        playbackTask = Task {
            do {
                if includeAudio, audioRevision != snapshot.revision {
                    let item = try await AudioComposer.preparePlayerItem(plan: snapshot, rootURL: rootURL)
                    audioPlayer = item.map { AVPlayer(playerItem: $0) }; audioRevision = snapshot.revision
                }
                guard !Task.isCancelled, playing else { return }
                if playhead >= duration - 0.05 { playhead = 0 }
                let origin = playhead
                if includeAudio {
                    await audioPlayer?.seek(to: CMTime(seconds: origin, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                let startedAt = ContinuousClock.now
                if includeAudio { audioPlayer?.play() }
                while playing && !Task.isCancelled {
                    let elapsed = startedAt.duration(to: .now).components
                    let clockSeconds = origin + Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                    let seconds = includeAudio ? (audioPlayer?.currentTime().seconds ?? clockSeconds) : clockSeconds
                    if seconds >= duration { stop(); playhead = max(0, duration - 1 / 30); requestPreview(); break }
                    playhead = seconds
                    let ratio = snapshot.variant.ratio
                    let edge: Double = isFullScreenPreview ? 900 : 480
                    let image = try await renderer.render(plan: snapshot, time: .init(seconds: seconds), rootURL: rootURL, size: CGSize(width: ratio >= 1 ? edge : edge * ratio, height: ratio >= 1 ? edge / ratio : edge))
                    if !Task.isCancelled { preview = image }
                    try await Task.sleep(for: .milliseconds(20))
                }
            } catch {
                // Pausing cancels an in-flight Core Image/AVFoundation operation. Some
                // framework paths surface that as an NSError instead of CancellationError.
                // Once playback has been stopped, cancellation is the expected outcome.
                guard playing, !Task.isCancelled else { return }
                stop()
                self.error = error.localizedDescription
            }
        }
    }
    func stop() { playing = false; playbackTask?.cancel(); playbackTask = nil; audioPlayer?.pause() }
    func changeClip(_ name: String, _ change: (inout Clip) -> Void) { guard let id = selectedClipID else { return }; if gestureActive { updateGesture { $0.updateClip(id, change) } } else { edit(name) { $0.updateClip(id, change) } } }
    func changePresentation(_ change: (inout Presentation) -> Void) {
        guard let id = selectedClipID else { return }
        let local = localScope, variantID = variantID
        let mutation: (inout ProjectDocument) -> Void = { d in
            guard let clip = d.clip(id) else { return }
            if local, let i = d.variants.firstIndex(where: { $0.id == variantID }) { var p = d.variants[i].overrides[id.uuidString] ?? clip.presentation; change(&p); d.variants[i].overrides[id.uuidString] = p }
            else { d.updateClip(id) { change(&$0.presentation) } }
        }
        if gestureActive { updateGesture(mutation) } else { edit(L("Propriétés"), mutation) }
    }
    func changeCaptionPresentations(_ change: (inout Presentation) -> Void) {
        guard selectedClip?.isCaption == true else { return }
        let ids = document.allClips.filter(\.isCaption).map(\.id)
        let local = localScope, activeVariantID = variantID
        let mutation: (inout ProjectDocument) -> Void = { document in
            if local, let variantIndex = document.variants.firstIndex(where: { $0.id == activeVariantID }) {
                for id in ids {
                    guard let clip = document.clip(id) else { continue }
                    var presentation = document.variants[variantIndex].overrides[id.uuidString] ?? clip.presentation
                    change(&presentation)
                    document.variants[variantIndex].overrides[id.uuidString] = presentation
                }
            } else {
                for id in ids { document.updateClip(id) { change(&$0.presentation) } }
            }
        }
        if gestureActive { updateGesture(mutation) } else { edit(L("Style des sous-titres"), mutation) }
    }
    func resetPresentation() {
        guard let id = selectedClipID else { return }; let v = variantID
        edit(L("Réinitialiser")) { d in if localScope, let i = d.variants.firstIndex(where: { $0.id == v }) { d.variants[i].overrides.removeValue(forKey: id.uuidString) } else { d.updateClip(id) { $0.presentation = .init() } } }
    }
    func importFiles(_ urls: [URL], asOverlay: Bool = false, replaceID: UUID? = nil) {
        busy = L("Import…")
        importTask?.cancel()
        importTask = Task {
            defer { busy = nil }
            do {
                var assets: [MediaAsset] = []
                for (index, url) in urls.enumerated() {
                    try Task.checkCancellation()
                    busy = "\(L("Import…")) \(index + 1)/\(urls.count)"
                    assets.append(try await MediaImporter.shared.importFile(url: url, to: rootURL))
                }
                try Task.checkCancellation()
                pendingOverlay = asOverlay; pendingReplacement = replaceID; pendingImports = assets
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    func cancelImport() { importTask?.cancel() }
    func insertPendingImports(placement requestedPlacement: ImportPlacement? = nil) {
        let assets = pendingImports, replaceID = pendingReplacement
        let placement = requestedPlacement ?? suggestedImportPlacement
                edit(L("Ajouter")) { d in
                    var insertionIndex = d.scenes.firstIndex(where: { $0.id == selectedSceneID }).map { $0 + 1 } ?? d.scenes.count
                    for asset in assets {
                        if !d.assets.contains(where: { $0.id == asset.id }) { d.assets.append(asset) }
                        let dur = asset.kind == .image ? MediaTime(seconds: 5) : asset.duration
                        if let id = replaceID {
                            d.updateClip(id) { clip in clip.assetID = asset.id; clip.kind = asset.kind; clip.sourceStart = .zero; if asset.kind == .image { clip.sourceDuration = clip.duration } else { clip.sourceDuration = min(clip.sourceDuration, dur); clip.duration = min(clip.duration, dur / clip.speed) } }
                        } else if asset.kind == .audio {
                            d.globalClips.append(Clip(assetID: asset.id, kind: .audio, duration: dur, sourceDuration: dur, layer: 0))
                        } else if placement == .overlay, let i = d.scenes.firstIndex(where: { $0.id == selectedSceneID }) {
                            var clip = Clip(assetID: asset.id, kind: asset.kind, duration: min(dur, d.scenes[i].duration), sourceDuration: min(dur, d.scenes[i].duration), layer: 5)
                            clip.presentation.scale = 0.45
                            d.scenes[i].clips.append(clip)
                            selectedClipID = clip.id
                        } else {
                            let clip = Clip(assetID: asset.id, kind: asset.kind, duration: dur, sourceDuration: dur)
                            let scene = Scene(title: displayName(for: asset), duration: dur, clips: [clip])
                            if placement == .afterSelection {
                                d.scenes.insert(scene, at: min(insertionIndex, d.scenes.count)); insertionIndex += 1
                            } else { d.scenes.append(scene) }
                            selectedSceneID = scene.id; selectedClipID = clip.id
                        }
                    }
                }
        pendingImports = []; pendingOverlay = false; pendingReplacement = nil
    }

    func addText(caption: Bool = false) {
        var clip = Clip(kind: .text, duration: selectedScene?.duration ?? .init(seconds: 5), text: caption ? L("Sous-titres") : L("Votre atelier de montage."), layer: 10, isCaption: caption)
        clip.presentation.y = caption ? 0.84 : 0.5; clip.presentation.textBackgroundOpacity = caption ? 0.65 : 0
        addToSelectedScene(clip)
        inspector = .text
    }
    func addShape() {
        var clip = Clip(kind: .shape, duration: selectedScene?.duration ?? .init(seconds: 5), layer: 4)
        clip.presentation.scale = 0.35; clip.presentation.color = "#EBA65A"; clip.presentation.mask = .ellipse
        addToSelectedScene(clip); inspector = .image
    }
    func addToSelectedScene(_ clip: Clip) {
        edit(L("Ajouter")) { d in
            if let i = d.scenes.firstIndex(where: { $0.id == selectedSceneID }) { d.scenes[i].clips.append(clip); d.scenes[i].duration = max(d.scenes[i].duration, clip.end) }
            else { let scene = Scene(title: L("Nouvelle histoire"), duration: clip.end, clips: [clip]); d.scenes.append(scene); selectedSceneID = scene.id }
            selectedClipID = clip.id
        }
    }
    func deleteClip() { guard let id = selectedClipID else { return }; deleteClip(id) }
    func deleteClip(_ id: UUID) { edit(L("Supprimer")) { d in for i in d.scenes.indices { d.scenes[i].clips.removeAll { $0.id == id } }; d.globalClips.removeAll { $0.id == id }; for i in d.variants.indices { d.variants[i].overrides.removeValue(forKey: id.uuidString) } } }
    func deleteCaptionTrack() {
        let ids = Set(document.allClips.filter(\.isCaption).map(\.id))
        guard !ids.isEmpty else { return }
        edit(L("Supprimer la piste de sous-titres")) { document in
            for index in document.scenes.indices { document.scenes[index].clips.removeAll { ids.contains($0.id) } }
            document.globalClips.removeAll { ids.contains($0.id) }
            for index in document.variants.indices {
                for id in ids { document.variants[index].overrides.removeValue(forKey: id.uuidString) }
            }
        }
    }
    func moveScene(_ sceneID: UUID, by offset: Int) {
        edit(L("Scénario")) { d in guard let i = d.scenes.firstIndex(where: { $0.id == sceneID }) else { return }; let target = max(0, min(d.scenes.count - 1, i + offset)); let scene = d.scenes.remove(at: i); d.scenes.insert(scene, at: target) }
    }
}
extension ProjectDocument {
    mutating func updateClip(_ id: UUID, _ change: (inout Clip) -> Void) {
        for s in scenes.indices { if let c = scenes[s].clips.firstIndex(where: { $0.id == id }) { change(&scenes[s].clips[c]); return } }
        if let i = globalClips.firstIndex(where: { $0.id == id }) { change(&globalClips[i]) }
    }
}

struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in SentTransferredFile(movie.url) } importing: { received in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return Self(url: target)
        }
    }
}
struct ImportedImage: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { image in SentTransferredFile(image.url) } importing: { received in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return Self(url: target)
        }
    }
}
