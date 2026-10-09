import AVFoundation
import SwiftUI
import Combine
import Translation
import UniformTypeIdentifiers

private func SL(_ french: String, _ english: String) -> String {
    AppLocalization.bilingual(french, english)
}

@MainActor
private enum SceneAudioInsertion {
    static func insert(_ asset: MediaAsset, into model: EditorModel, at globalTime: Double? = nil, extendScene: Bool) {
        let requestedTime = globalTime.map { min(max(0, $0), max(0, model.duration)) }
        let targetSpan = requestedTime.flatMap { time in
            model.plan.scenes.first { time >= $0.start.seconds && time < $0.end.seconds }
        } ?? model.plan.scenes.first { $0.id == model.selectedSceneID }
        let sceneID = targetSpan?.id ?? model.selectedSceneID
        let localStart = targetSpan.map { max(0, (requestedTime ?? $0.start.seconds) - $0.start.seconds) } ?? 0
        model.edit(SL("Ajouter une narration", "Add narration")) { document in
            document.assets.append(asset)
            var clip = Clip(assetID: asset.id, kind: .audio, duration: asset.duration, sourceDuration: asset.duration, layer: 1)
            clip.start = .init(seconds: localStart)
            if let index = document.scenes.firstIndex(where: { $0.id == sceneID }) {
                if extendScene {
                    let oldDuration = document.scenes[index].duration
                    for c in document.scenes[index].clips.indices where document.scenes[index].clips[c].kind == .image && document.scenes[index].clips[c].end == oldDuration {
                        document.scenes[index].clips[c].duration = max(.zero, .init(seconds: localStart) + asset.duration - document.scenes[index].clips[c].start)
                        document.scenes[index].clips[c].sourceDuration = document.scenes[index].clips[c].duration
                    }
                    document.scenes[index].duration = max(oldDuration, .init(seconds: localStart) + asset.duration)
                }
                document.scenes[index].clips.append(clip)
            } else {
                document.scenes.append(.init(title: SL("Narration", "Narration"), duration: asset.duration, clips: [clip]))
            }
            model.selectedClipID = clip.id
        }
    }
}

private enum VoiceoverMode: String, CaseIterable {
    case withVideo
    case placeAfter
}

struct VoiceoverSheet: View {
    @ObservedObject var model: EditorModel
    @StateObject private var recorder = VoiceRecorder()
    @Environment(\.dismiss) private var dismiss
    @State private var task: Task<Void, Never>?
    @State private var pending: MediaAsset?
    @State private var error: String?
    @State private var inserting = false
    @State private var confirmExtension = false
    @State private var importedURL: URL?
    @State private var referencePlayback = false
    @State private var mode = VoiceoverMode.withVideo
    @State private var recordingStart = 0.0
    @State private var insertionTime = 0.0
    private var isRecording: Bool { recorder.state == .recording }
    private var counting: Bool { if case .countdown = recorder.state { return true }; return false }
    private var showsPreview: Bool { mode == .withVideo || (mode == .placeAfter && pending != nil) }
    private var targetSpan: SceneSpan? {
        model.plan.scenes.first { insertionTime >= $0.start.seconds && insertionTime < $0.end.seconds }
            ?? model.plan.scenes.first { $0.id == model.selectedSceneID }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker(SL("Mode d’enregistrement", "Recording mode"), selection: $mode) {
                        Text(SL("Avec la vidéo", "With video")).tag(VoiceoverMode.withVideo)
                        Text(SL("Placer après", "Place afterward")).tag(VoiceoverMode.placeAfter)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRecording || counting || pending != nil)

                    if showsPreview, let preview = model.preview {
                        ZStack(alignment: .bottomTrailing) {
                            Color.black
                            Image(decorative: preview, scale: 1).resizable().scaledToFit()
                            Text(timeLabel(model.playhead)).font(.caption.monospacedDigit().bold()).padding(7).background(.black.opacity(0.65), in: Capsule()).padding(8)
                        }
                        .frame(maxWidth: .infinity).frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel(SL("Aperçu vidéo", "Video preview"))
                    }

                    if mode == .placeAfter, pending != nil, let span = targetSpan {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(SL("Position d’insertion", "Insertion position")).font(.subheadline.bold()); Spacer(); Text(timeLabel(insertionTime)).monospacedDigit().foregroundStyle(DesignTokens.amber) }
                            Slider(value: Binding(get: { insertionTime }, set: { insertionTime = $0; model.seek($0) }), in: span.start.seconds...max(span.start.seconds + 0.001, span.end.seconds - 1.0 / 120.0))
                            Text(SL("Parcourez la scène puis insérez la prise à l’image choisie.", "Scrub through the scene, then insert the recording at the chosen frame.")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    Image(systemName: "mic.fill").font(.system(size: 42)).foregroundStyle(DesignTokens.amber)
                    Text(model.selectedScene?.title ?? SL("Nouvelle scène", "New scene")).font(.title2.bold())
                    Text(status).font(.headline).multilineTextAlignment(.center)
                    Text(timeLabel(recorder.elapsed)).font(.system(size: 34, design: .monospaced))
                    ProgressView(value: Double(recorder.level)).tint(DesignTokens.amber).accessibilityLabel(SL("Niveau microphone", "Microphone level"))
                    Text(mode == .withVideo
                         ? SL("La vidéo démarre au temps courant et la prise y sera synchronisée.", "Video starts at the current time and the recording is synchronized there.")
                         : SL("Enregistrez d’abord, puis choisissez l’image où insérer la prise.", "Record first, then choose the frame where the recording should be inserted."))
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if mode == .withVideo {
                        Toggle(SL("Lire le montage au casque", "Play reference through headphones"), isOn: $referencePlayback).disabled(isRecording || counting)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    if inserting { ProgressView() }
                    if isRecording {
                        Button { _ = recorder.stop() } label: { Label(SL("Arrêter la prise", "Stop recording"), systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(.borderedProminent).tint(.red)
                    } else if counting {
                        Button(L("Annuler")) { task?.cancel(); recorder.cancel() }.buttonStyle(.bordered)
                    } else if let pending {
                        Button(SL("Utiliser cette prise", "Use this recording")) { use(pending) }.buttonStyle(.borderedProminent).tint(DesignTokens.amber)
                        Button(SL("Nouvelle prise", "New recording")) { self.pending = nil; recorder.cancel(); start() }.buttonStyle(.bordered)
                    } else {
                        Button { start() } label: { Label(SL("Enregistrer après 3 secondes", "Record after 3 seconds"), systemImage: "record.circle").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(.borderedProminent).tint(DesignTokens.amber).disabled(inserting)
                    }
                }.padding(24)
            }.navigationTitle(SL("Voix off", "Voiceover")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() } } }
        }
        .onChange(of: recorder.state) { _, state in
            if state == .recording && mode == .withVideo {
                model.seek(recordingStart)
                if referencePlayback && !hasHeadphones {
                    referencePlayback = false
                    error = SL("Le casque n’est plus disponible. La vidéo continue sans son de référence.", "Headphones are no longer available. Video continues without reference audio.")
                }
                model.startPlayback(includeAudio: referencePlayback)
            }
            else if state != .recording { model.stop() }
        }
        .onChange(of: recorder.completedURL) { _, url in if let url, url != importedURL { importRecording(url) } }
        .onAppear { insertionTime = model.playhead; recordingStart = model.playhead }
        .confirmationDialog(SL("La voix dépasse la scène", "Recording is longer than the scene"), isPresented: $confirmExtension, titleVisibility: .visible) {
            Button(SL("Prolonger la scène et ses images fixes", "Extend scene and still images")) { if let pending { insert(pending, extendScene: true) } }
            Button(L("Annuler"), role: .cancel) {}
        } message: { Text(SL("La voix sera conservée en entier. Les vidéos ne sont pas étirées : ajoutez un visuel si elles se terminent avant la voix.", "The complete recording is preserved. Videos are not stretched; add a visual if they end before the recording.")) }
        .onDisappear { task?.cancel(); recorder.cancel(); model.stop() }
    }
    private var status: String {
        switch recorder.state {
        case .idle: return SL("Prêt à enregistrer", "Ready to record")
        case .countdown(let count): return "\(count)…"
        case .recording: return SL("Enregistrement", "Recording")
        case .finished: return SL("Prise enregistrée", "Recording saved")
        case .interrupted(let message), .failed(let message): return message
        }
    }
    private func start() {
        error = nil; pending = nil
        recordingStart = mode == .withVideo ? model.playhead : insertionTime
        if mode == .withVideo && referencePlayback {
            guard hasHeadphones else {
                error = SL("Branchez un casque pour écouter la référence pendant l’enregistrement.", "Connect headphones to hear the reference during recording.")
                return
            }
        }
        model.stop()
        let url = model.rootURL.appendingPathComponent("Recordings/\(UUID().uuidString).m4a")
        task = Task { do { try await recorder.start(at: url) } catch is CancellationError {} catch { self.error = error.localizedDescription } }
    }
    private func importRecording(_ url: URL) {
        importedURL = url; inserting = true
        task = Task { defer { inserting = false }; do { pending = try await MediaImporter.shared.importFile(url: url, to: model.rootURL); try? FileManager.default.removeItem(at: url) } catch { self.error = error.localizedDescription } }
    }
    private func use(_ asset: MediaAsset) {
        let position = mode == .withVideo ? recordingStart : insertionTime
        if let span = model.plan.scenes.first(where: { position >= $0.start.seconds && position < $0.end.seconds }), position + asset.duration.seconds > span.end.seconds { confirmExtension = true }
        else { insert(asset, extendScene: false) }
    }
    private var hasHeadphones: Bool {
        let ports: [AVAudioSession.Port] = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { ports.contains($0.portType) }
    }
    private func insert(_ asset: MediaAsset, extendScene: Bool) {
        let position = mode == .withVideo ? recordingStart : insertionTime
        SceneAudioInsertion.insert(asset, into: model, at: position, extendScene: extendScene)
        dismiss()
    }
}

struct NarrationSheet: View {
    @ObservedObject var model: EditorModel
    @StateObject private var synthesizer = SpeechFileSynthesizer()
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var voice = ""
    @State private var rate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var pending: MediaAsset?
    @State private var confirmExtension = false
    var body: some View {
        NavigationStack {
            Form {
                Section(SL("Brouillon de narration", "Narration draft")) {
                    TextEditor(text: $text).frame(minHeight: 140)
                    Text(SL("Modifier ce texte ne remplace pas un enregistrement existant.", "Editing this text does not replace an existing recording.")).font(.footnote).foregroundStyle(.secondary)
                }
                Section(SL("Voix système installées", "Available system voices")) {
                    Picker(SL("Voix", "Voice"), selection: $voice) { ForEach(synthesizer.availableVoices, id: \.identifier) { Text("\($0.name) · \($0.language)").tag($0.identifier) } }
                    HStack { Text(SL("Débit", "Rate")); Slider(value: $rate, in: 0.25...0.65); Text(rate.formatted(.number.precision(.fractionLength(2)))).monospacedDigit() }
                }
                Section {
                    if synthesizer.isWorking { ProgressView(SL("Synthèse locale…", "Generating speech locally…")); Button(L("Annuler")) { task?.cancel(); synthesizer.cancel() } }
                    else {
                        Button(SL("Créer le fichier audio", "Create audio file")) { generate() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || voice.isEmpty)
                        if let pending { Button(SL("Insérer dans la scène", "Insert into scene")) { use(pending) }; Text(timeLabel(pending.duration.seconds)).monospacedDigit() }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle(SL("Synthétiser une voix", "Synthesize narration")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() } } }
        }.onAppear {
            text = model.selectedScene?.narration ?? ""
            voice = synthesizer.availableVoices.first(where: { $0.language.hasPrefix(Locale.current.language.languageCode?.identifier ?? "fr") })?.identifier ?? synthesizer.availableVoices.first?.identifier ?? ""
        }
        .confirmationDialog(SL("La voix dépasse la scène", "Narration is longer than the scene"), isPresented: $confirmExtension, titleVisibility: .visible) {
            Button(SL("Prolonger la scène et ses images fixes", "Extend scene and still images")) { if let pending { insert(pending, extend: true) } }
            Button(L("Annuler"), role: .cancel) {}
        } message: { Text(SL("Le son sera conservé en entier. Complétez les visuels au besoin.", "The complete audio will be preserved. Add visuals where needed.")) }
        .onDisappear { task?.cancel(); synthesizer.cancel() }
    }
    private func generate() {
        error = nil; pending = nil; model.stop()
        let url = model.rootURL.appendingPathComponent("Recordings/\(UUID().uuidString).caf")
        task = Task { do { _ = try await synthesizer.synthesize(text: text, voiceIdentifier: voice, rate: Float(rate), to: url); pending = try await MediaImporter.shared.importFile(url: url, to: model.rootURL); try? FileManager.default.removeItem(at: url) } catch is CancellationError {} catch { self.error = error.localizedDescription } }
    }
    private func use(_ asset: MediaAsset) { if let scene = model.selectedScene, asset.duration > scene.duration { confirmExtension = true } else { insert(asset, extend: false) } }
    private func insert(_ asset: MediaAsset, extend: Bool) {
        SceneAudioInsertion.insert(asset, into: model, extendScene: extend)
        let id = model.selectedSceneID
        model.edit(SL("Narration", "Narration")) { document in if let i = document.scenes.firstIndex(where: { $0.id == id }) { document.scenes[i].narration = text } }
        dismiss()
    }
}

private struct CaptionGenerationPair: Sendable {
    var original: CaptionSegment
    var projected: CaptionSegment
}

private struct CaptionGenerationJob: Sendable {
    var sourceID: UUID
    var sourceSceneID: UUID?
    var sourceSceneStart: MediaTime?
    var assetID: UUID
    var revision: Int
    var captions: [CaptionGenerationPair]
}

struct TranscriptionSheet: View {
    @ObservedObject var model: EditorModel
    @StateObject private var transcriber = LocalTranscriber()
    @Environment(\.dismiss) private var dismiss
    @State private var clipID: UUID?
    @State private var language = "fr-FR"
    @State private var translationTarget = "original"
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationJob: CaptionGenerationJob?
    @State private var activeTranslationSession: TranslationSession?
    @State private var isTranslating = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var count = 0
    private var sources: [RenderClip] { model.plan.clips.filter { item in model.document.asset(item.clip.assetID)?.hasAudio == true } }
    var body: some View {
        NavigationStack {
            Form {
                Section(SL("Source et langue", "Source and language")) {
                    Picker(SL("Clip source", "Source clip"), selection: $clipID) { ForEach(sources) { clip in Text(model.document.asset(clip.clip.assetID)?.name ?? "Audio").tag(Optional(clip.id)) } }
                    Picker(SL("Langue parlée", "Spoken language"), selection: $language) { Text(L("Français (France)")).tag("fr-FR"); Text("English (US)").tag("en-US"); Text("English (UK)").tag("en-GB"); Text(L("Español")).tag("es-ES"); Text(L("Deutsch")).tag("de-DE"); Text(L("Italiano")).tag("it-IT") }
                }.disabled(transcriber.isWorking || isTranslating)
                Section(SL("Traduction des sous-titres", "Caption translation")) {
                    Picker(SL("Langue des sous-titres", "Caption language"), selection: $translationTarget) {
                        Text(SL("Texte original", "Original text")).tag("original")
                        if !language.hasPrefix("fr") { Text(L("Français")).tag("fr") }
                        if !language.hasPrefix("en") { Text("English").tag("en") }
                        if !language.hasPrefix("es") { Text(L("Español")).tag("es") }
                        if !language.hasPrefix("de") { Text(L("Deutsch")).tag("de") }
                        if !language.hasPrefix("it") { Text(L("Italiano")).tag("it") }
                        if !language.hasPrefix("pt") { Text(L("Português")).tag("pt") }
                    }
                    Text(SL("La traduction conserve exactement les timecodes de la transcription. iOS peut télécharger le modèle de traduction lors de la première utilisation.", "Translation preserves the transcription timecodes exactly. iOS may download the translation model the first time it is used.")).font(.footnote).foregroundStyle(.secondary)
                }.disabled(transcriber.isWorking || isTranslating)
                Section {
                    Text(SL("L’audio reste local. Si nécessaire, iOS télécharge uniquement le modèle de langue. Les temps proviennent du moteur ; relisez toujours le texte.", "Audio stays on this device. If needed, iOS downloads only the language model. Timing comes from the speech engine; always review the text.")).font(.footnote)
                    if transcriber.isWorking || isTranslating {
                        if isTranslating { ProgressView(SL("Traduction locale…", "Translating locally…")) }
                        else { ProgressView(value: transcriber.progress) }
                        if let status = transcriber.statusMessage { Text(status).font(.footnote).foregroundStyle(.secondary) }
                        Button(L("Annuler")) { cancel() }
                    }
                    else { Button(SL("Générer les sous-titres", "Generate captions")) { generate() }.disabled(clipID == nil || sources.isEmpty) }
                    if sources.isEmpty { Text(SL("Ajoutez d’abord une vidéo avec son ou un fichier audio.", "First add a video with audio or an audio file.")).foregroundStyle(.secondary) }
                    if count > 0 { Text(SL("\(count) segments ajoutés. Ils sont modifiables dans Texte.", "\(count) segments added. Edit them in Text.")) }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle(L("Sous-titres")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() } } }
        }
        .translationTask(translationConfiguration) { session in await translateAndInsert(using: session) }
        .onAppear { clipID = sources.first(where: { $0.id == model.selectedClipID })?.id ?? sources.first?.id; language = Locale.current.language.languageCode?.identifier == "fr" ? "fr-FR" : "en-US" }
        .onChange(of: language) { _, value in if translationTarget != "original", value.hasPrefix(translationTarget) { translationTarget = "original" } }
        .onDisappear { cancel() }
    }
    private func generate() {
        guard let source = sources.first(where: { $0.id == clipID }), let asset = model.document.asset(source.clip.assetID) else { return }
        let snapshotRevision = model.document.revision
        error = nil; count = 0; model.stop()
        task = Task {
            var extracted: URL?
            defer { if let extracted { try? FileManager.default.removeItem(at: extracted) } }
            do {
                var url = model.rootURL.appendingPathComponent(asset.relativePath)
                if asset.kind == .video {
                    let output = FileManager.default.temporaryDirectory.appendingPathComponent("transcription-\(UUID().uuidString).m4a")
                    extracted = output
                    let avAsset = AVURLAsset(url: url)
                    guard let exporter = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetAppleM4A) else { throw VoiceServiceError.invalidAudio }
                    try await exporter.export(to: output, as: .m4a)
                    url = output
                }
                let words = try await transcriber.transcribe(url: url, locale: Locale(identifier: language))
                try Task.checkCancellation()
                guard model.document.revision == snapshotRevision else { throw DocumentError.invalid(SL("Le montage a changé ; relancez la transcription.", "The edit changed; generate captions again.")) }
                let segments = CaptionSegmenter.segments(from: words, sourceAssetID: asset.id, analyzedRevision: snapshotRevision)
                let mapped = segments.compactMap { original -> CaptionGenerationPair? in
                    guard let projected = CaptionCodec.remap([original], through: source).first else { return nil }
                    return CaptionGenerationPair(original: original, projected: projected)
                }
                guard !mapped.isEmpty else { throw VoiceServiceError.emptyAudio }
                let job = CaptionGenerationJob(
                    sourceID: source.id,
                    sourceSceneID: source.sceneID,
                    sourceSceneStart: source.sceneID.flatMap { sceneID in model.plan.scenes.first(where: { $0.id == sceneID })?.start },
                    assetID: asset.id,
                    revision: snapshotRevision,
                    captions: mapped
                )
                if translationTarget == "original" {
                    try insert(job)
                } else {
                    translationJob = job
                    isTranslating = true
                    let sourceLanguage = Locale.Language(identifier: language)
                    let targetLanguage = Locale.Language(identifier: translationTarget)
                    if translationConfiguration?.source == sourceLanguage && translationConfiguration?.target == targetLanguage {
                        translationConfiguration?.invalidate()
                    } else {
                        translationConfiguration = .init(source: sourceLanguage, target: targetLanguage)
                    }
                }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func translateAndInsert(using session: TranslationSession) async {
        guard var job = translationJob else { return }
        activeTranslationSession = session
        do {
            try await session.prepareTranslation()
            try Task.checkCancellation()
            let requests = job.captions.enumerated().map { index, pair in
                TranslationSession.Request(sourceText: pair.projected.text, clientIdentifier: String(index))
            }
            let responses = try await session.translations(from: requests)
            let translated = Dictionary(uniqueKeysWithValues: responses.compactMap { response in
                response.clientIdentifier.flatMap(Int.init).map { ($0, response.targetText) }
            })
            guard translated.count == job.captions.count else { throw DocumentError.invalid(SL("La traduction est incomplète. Réessayez.", "Translation is incomplete. Try again.")) }
            for index in job.captions.indices {
                guard let text = translated[index]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { throw DocumentError.invalid(SL("La traduction est incomplète. Réessayez.", "Translation is incomplete. Try again.")) }
                job.captions[index].original.text = text
                job.captions[index].projected.text = text
            }
            try insert(job)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        activeTranslationSession = nil
        translationJob = nil
        isTranslating = false
    }
    private func insert(_ job: CaptionGenerationJob) throws {
        guard model.document.revision == job.revision else { throw DocumentError.invalid(SL("Le montage a changé ; relancez la transcription.", "The edit changed; generate captions again.")) }
        model.edit(SL("Génération des sous-titres", "Caption generation")) { document in
            let previous = Set(document.allClips.filter { $0.isCaption && $0.captionSourceClipID == job.sourceID }.map(\.id))
            for index in document.scenes.indices { document.scenes[index].clips.removeAll { previous.contains($0.id) } }
            document.globalClips.removeAll { previous.contains($0.id) }
            for index in document.variants.indices {
                for id in previous { document.variants[index].overrides.removeValue(forKey: id.uuidString) }
            }
            for pair in job.captions {
                var caption = pair.projected.asClip()
                caption.captionSourceAssetID = job.assetID
                caption.captionSourceClipID = job.sourceID
                caption.captionSourceStart = pair.original.start
                caption.captionSourceEnd = pair.original.end
                caption.captionAnalyzedRevision = job.revision
                if let sceneID = job.sourceSceneID, let index = document.scenes.firstIndex(where: { $0.id == sceneID }), let sceneStart = job.sourceSceneStart {
                    caption.start = caption.start - sceneStart
                    caption.duration = min(caption.duration, document.scenes[index].duration - caption.start)
                    if caption.duration > .zero { document.scenes[index].clips.append(caption) }
                } else { document.globalClips.append(caption) }
            }
        }
        count = job.captions.count
    }
    private func cancel() {
        task?.cancel()
        task = nil
        transcriber.cancel()
        activeTranslationSession?.cancel()
        activeTranslationSession = nil
        translationConfiguration = nil
        translationJob = nil
        isTranslating = false
    }
}

struct TemplatesScreen: View {
    @ObservedObject var workspace: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text(SL("Douze histoires originales. Chaque modèle devient un projet entièrement modifiable.", "Twelve original stories. Each template becomes a fully editable project.")).foregroundStyle(.secondary) }
                ForEach(TemplateCatalog.all) { template in
                    NavigationLink(value: template.id) {
                        HStack(spacing: 14) {
                            Image(systemName: template.symbol).font(.title2).foregroundStyle(Color(hex: template.accent)).frame(width: 42, height: 54).background(DesignTokens.ink, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) { Text(L(template.name)).font(.headline); Text(L(template.subtitle)).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Text(timeLabel(template.duration)).font(.caption.monospacedDigit())
                        }.padding(.vertical, 5)
                    }
                }
            }.scrollContentBackground(.hidden).background(DesignTokens.paper).navigationTitle(L("Modèles"))
                .navigationDestination(for: String.self) { id in if let template = TemplateCatalog.all.first(where: { $0.id == id }) { TemplateDetailScreen(workspace: workspace, template: template, finished: { dismiss() }) } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() } } }
        }
        .preferredColorScheme(.light)
    }
}

private final class TemplateScratchDirectory: ObservableObject {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Template-\(UUID().uuidString)")
    deinit { try? FileManager.default.removeItem(at: url) }
}

private struct TemplateDetailScreen: View {
    @ObservedObject var workspace: WorkspaceModel
    let template: TemplateDefinition
    let finished: () -> Void
    @State private var document: ProjectDocument?
    @State private var preview: CGImage?
    @StateObject private var scratch = TemplateScratchDirectory()
    private var previewRoot: URL { scratch.url }
    @State private var variantIndex = 0
    @State private var position = 1.0
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack { DesignTokens.ink; if let preview { Image(decorative: preview, scale: 1).resizable().scaledToFit() } else { ProgressView().tint(.white) } }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 18))
                Picker(L("Format"), selection: $variantIndex) { Text("9:16").tag(0); Text("1:1").tag(1); Text("16:9").tag(2) }.pickerStyle(.segmented)
                Slider(value: $position, in: 0...max(0.1, template.duration - 0.1)).accessibilityLabel(SL("Instant de prévisualisation", "Preview time"))
                Text(L(template.subtitle)).font(.headline)
                if let document {
                    ForEach(document.scenes) { scene in HStack { Text(scene.title); Spacer(); Text(timeLabel(scene.duration.seconds)).monospacedDigit().foregroundStyle(.secondary) } }
                    Button(SL("Choisir des photos ou vidéos", "Choose photos or videos")) { importing = true }.buttonStyle(.bordered).disabled(busy)
                    Button(SL("Ouvrir dans l’atelier", "Open in the editor")) { open() }.buttonStyle(.borderedProminent).tint(DesignTokens.ink).disabled(busy)
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                Text(SL("Les médias choisis remplacent les plans dans l’ordre. Textes, durée et cadrage restent modifiables dans l’atelier.", "Selected media replace shots in order. Text, timing and framing remain editable in the editor.")).font(.footnote).foregroundStyle(.secondary)
            }.padding(22)
        }.background(DesignTokens.paper).navigationTitle(L(template.name)).navigationBarTitleDisplayMode(.inline)
            .task { guard document == nil else { return }; do { document = try await TemplateCatalog.make(template: template, in: previewRoot); await render() } catch { self.error = error.localizedDescription } }
            .task(id: "\(variantIndex)-\(position)") { await render() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in switch result { case .success(let urls): replace(urls); case .failure(let error): self.error = error.localizedDescription } }

    }
    private func render() async {
        guard let document else { return }
        do { preview = try await FrameRenderer().render(plan: .compile(document: document, variantID: document.variants[variantIndex].id), time: .init(seconds: position), rootURL: previewRoot, size: CGSize(width: 420, height: 420 / document.variants[variantIndex].ratio)) } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func replace(_ urls: [URL]) {
        busy = true
        Task {
            defer { busy = false }
            do {
                guard var updated = document else { return }
                for (index, url) in urls.prefix(updated.scenes.count).enumerated() {
                    let asset = try await MediaImporter.shared.importFile(url: url, to: previewRoot)
                    updated.assets.append(asset)
                    if let i = updated.scenes[index].clips.firstIndex(where: { $0.kind == .image || $0.kind == .video }) {
                        updated.scenes[index].clips[i].assetID = asset.id
                        updated.scenes[index].clips[i].kind = asset.kind
                        if asset.kind == .video {
                            let duration = min(asset.duration, updated.scenes[index].duration)
                            updated.scenes[index].clips[i].duration = duration
                            updated.scenes[index].clips[i].sourceDuration = duration
                        }
                    }
                }
                document = updated
                await render()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func open() {
        busy = true
        Task {
            defer { busy = false }
            do {
                guard var document else { return }
                let usedIDs = Set(document.allClips.compactMap(\.assetID))
                var assets: [MediaAsset] = []
                for original in document.assets where usedIDs.contains(original.id) {
                    var asset = try await MediaImporter.shared.importFile(url: previewRoot.appendingPathComponent(original.relativePath), to: workspace.rootURL)
                    asset.id = original.id
                    assets.append(asset)
                }
                document.assets = assets
                try workspace.store.save(document: document)
                workspace.refresh(); workspace.open(document); finished()
            } catch { self.error = error.localizedDescription }
        }
    }
}
