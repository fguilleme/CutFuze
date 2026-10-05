import SwiftUI
import UniformTypeIdentifiers


struct TimingSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var clipID: UUID?
    @State private var start = 0.0
    @State private var sourceIn = 0.0
    @State private var sourceOut = 5.0
    @State private var duration = 5.0
    @State private var speed = 1.0
    @State private var curve = false
    @State private var points: [SpeedPoint] = []
    @State private var ripple = false
    @State private var extendScene = false
    @State private var preview: CGImage?
    @State private var validationError: String?
    private var selected: Clip? { model.document.clip(clipID) }
    private var temporalMedia: Bool { selected?.kind == .video || selected?.kind == .audio }
    private var signature: String { "\(clipID?.uuidString ?? "")|\(start)|\(sourceIn)|\(sourceOut)|\(duration)|\(speed)|\(curve)|\(points)|\(ripple)|\(extendScene)" }
    var body: some View {
        NavigationStack {
            Form {
                if let image = preview ?? model.preview {
                    Section { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 150).accessibilityLabel(L("Aperçu du réglage")) }
                }
                Section(L("Position dans le montage")) {
                    numeric(L("Début") + " (s)", value: $start)
                    if !temporalMedia { numeric(L("Durée") + " (s)", value: $duration) }
                    Toggle(L("Déplacer les éléments suivants"), isOn: $ripple)
                    Toggle(L("Prolonger la scène si nécessaire"), isOn: $extendScene)
                    Text(L("Les sous-titres liés suivent le média. Les pistes ancrées au projet gardent leur position absolue.")).font(.caption).foregroundStyle(.secondary)
                }
                if temporalMedia {
                    Section(L("Plage du média source")) {
                        numeric(L("Début") + " (s)", value: $sourceIn)
                        numeric(L("Fin") + " (s)", value: $sourceOut)
                        Text(L("Bornes source indépendantes du temps de montage.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Section(L("Vitesse")) {
                        Toggle(L("Courbe"), isOn: $curve)
                        if !curve { numeric(L("Vitesse ×"), value: $speed) }
                        else {
                            Menu(L("Profil original")) {
                                ForEach(["Progressif", "Décélération", "Impact", "Plateau"], id: \.self) { name in Button(profileName(name)) { setProfile(name) } }
                            }
                            ForEach(points.indices, id: \.self) { index in
                                HStack {
                                    TextField(L("Source s"), value: $points[index].sourceTime.secondsValue, format: .number.precision(.fractionLength(0...3))).keyboardType(.decimalPad).accessibilityLabel(L("Temps source du point"))
                                    TextField("×", value: $points[index].speed, format: .number.precision(.fractionLength(0...2))).keyboardType(.decimalPad).accessibilityLabel(L("Vitesse du point"))
                                    Button(role: .destructive) { points.remove(at: index) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel(L("Supprimer le point"))
                                }
                            }
                            Button(L("Ajouter un point de vitesse")) { points.append(.init(sourceTime: .init(seconds: (sourceIn + sourceOut) / 2), speed: 1)) }
                            Text(L("La vitesse varie linéairement entre les points en temps source. Durée calculée par intégration de 1/v.")).font(.caption).foregroundStyle(.secondary)
                        }
                        if let candidate = try? candidateDocument(), let clip = candidate.clip(clipID) { LabeledContent(L("Durée"), value: String(format: "%.3f s", clip.duration.seconds)) }
                    }
                }
                if let validationError { Section { Text(validationError).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle(L("Précision temporelle"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Annuler")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("Enregistrer")) { save() }.disabled(selected == nil || validationError != nil) }
            }
            .onAppear { load() }
            .task(id: signature) { await renderDraft() }
        }.presentationDetents([.medium, .large]).preferredColorScheme(.dark)
    }
    private func numeric(_ label: String, value: Binding<Double>) -> some View {
        HStack { Text(label); Spacer(); TextField(label, value: value, format: .number.precision(.fractionLength(0...3))).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(maxWidth: 100).accessibilityLabel(label) }
    }
    private func load() {
        guard let clip = model.selectedClip else { return }
        clipID = clip.id; start = clip.start.seconds; sourceIn = clip.sourceStart.seconds; sourceOut = (clip.sourceStart + clip.sourceDuration).seconds
        duration = clip.duration.seconds; speed = clip.speed; points = clip.speedPoints; curve = !points.isEmpty
    }
    private func candidateDocument() throws -> ProjectDocument {
        var candidate = model.document
        try apply(to: &candidate)
        CaptionBindingUpdater.refresh(&candidate)
        try candidate.validate()
        return candidate
    }
    private func apply(to document: inout ProjectDocument) throws {
        guard let clipID, let original = document.clip(clipID), start.isFinite, start >= 0 else { throw DocumentError.invalid(L("Position de début")) }
        var updated = original
        updated.start = .init(seconds: start)
        if temporalMedia {
            guard sourceIn.isFinite, sourceOut.isFinite, sourceIn >= 0, sourceOut > sourceIn, speed.isFinite, (0.1...100).contains(speed) else { throw DocumentError.invalid(L("Plage source ou vitesse (0,1 à 100×)")) }
            if let asset = document.asset(original.assetID), sourceOut > asset.duration.seconds + 1.0 / 60_000 { throw DocumentError.invalid(L("Fin au-delà du média source")) }
            updated.sourceStart = .init(seconds: sourceIn); updated.sourceDuration = .init(seconds: sourceOut - sourceIn); updated.speed = speed
            updated.speedPoints = curve ? points.sorted { $0.sourceTime < $1.sourceTime } : []
            guard !curve || (!points.isEmpty && points.allSatisfy({ $0.sourceTime.seconds >= sourceIn && $0.sourceTime.seconds <= sourceOut && (0.1...100).contains($0.speed) })) else { throw DocumentError.invalid(L("Placez les points dans la plage source, entre 0,1 et 100×.")) }
            updated.duration = TimeMapping.outputDuration(clip: updated)
            // A source trim advances animation phase; changing speed keeps phase continuous.
            if sourceIn >= original.sourceStart.seconds { updated.animationOffset = original.animationOffset + TimeMapping.localTime(forSource: .init(seconds: original.reversed ? sourceOut : sourceIn), clip: original) }
            updated.animationDuration = original.animationDuration ?? original.duration
        } else {
            guard duration.isFinite, duration > 0 else { throw DocumentError.invalid(L("Durée")) }
            updated.duration = .init(seconds: duration)
        }
        let delta = updated.end - original.end
        try DocumentEditor.updateClip(clipID, in: &document) { $0 = updated }
        if let sceneIndex = document.scenes.firstIndex(where: { $0.clips.contains(where: { $0.id == clipID }) }) {
            if ripple {
                for index in document.scenes[sceneIndex].clips.indices where document.scenes[sceneIndex].clips[index].id != clipID && document.scenes[sceneIndex].clips[index].start >= original.end && document.scenes[sceneIndex].clips[index].captionSourceClipID != clipID {
                    document.scenes[sceneIndex].clips[index].start = max(.zero, document.scenes[sceneIndex].clips[index].start + delta)
                }
                document.scenes[sceneIndex].duration = max(.init(value: 1), document.scenes[sceneIndex].duration + delta)
            }
            let latest = document.scenes[sceneIndex].clips.filter { $0.captionSourceClipID != clipID }.map(\.end).max() ?? updated.end
            if latest > document.scenes[sceneIndex].duration {
                guard extendScene else { throw DocumentError.invalid(L("Activez « Prolonger la scène » pour conserver la totalité des éléments.")) }
                document.scenes[sceneIndex].duration = latest
            }
        }
    }
    private func save() {
        do { let candidate = try candidateDocument(); model.edit(L("Précision temporelle")) { $0 = candidate }; dismiss() }
        catch { validationError = error.localizedDescription }
    }
    private func renderDraft() async {
        guard clipID != nil else { return }
        do {
            try await Task.sleep(for: .milliseconds(140))
            let candidate = try candidateDocument(); validationError = nil
            let plan = RenderPlan.compile(document: candidate, variantID: model.variantID)
            let time = min(MediaTime(seconds: model.playhead), max(.zero, plan.duration - .init(value: 1)))
            let ratio = plan.variant.ratio, edge = 350.0
            let image = try await model.renderer.render(plan: plan, time: time, rootURL: model.rootURL, size: CGSize(width: ratio >= 1 ? edge : edge * ratio, height: ratio >= 1 ? edge / ratio : edge))
            if !Task.isCancelled { preview = image }
        } catch is CancellationError { } catch { if !Task.isCancelled { validationError = error.localizedDescription } }
    }
    private func profileName(_ value: String) -> String {
        switch value { case "Progressif": return L(value); case "Décélération": return L(value); case "Impact": return L(value); default: return L(value) }
    }
    private func setProfile(_ profile: String) {
        let values: [(Double, Double)]
        switch profile {
        case "Progressif": values = [(0,0.5),(1,2)]
        case "Décélération": values = [(0,2),(1,0.5)]
        case "Impact": values = [(0,1),(0.4,2.5),(0.6,0.4),(1,1)]
        default: values = [(0,1),(0.25,2),(0.75,2),(1,1)]
        }
        points = values.map { .init(sourceTime: .init(seconds: sourceIn + (sourceOut - sourceIn) * $0.0), speed: $0.1) }
    }
}

private extension MediaTime {
    var secondsValue: Double { get { seconds } set { self = .init(seconds: newValue) } }
}

struct SceneEditSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var sceneID: UUID?
    @State private var title = ""
    @State private var narration = ""
    @State private var duration = 5.0
    @State private var transition: TransitionKind = .none
    @State private var overlap = 0.5
    @State private var validationError: String?
    var body: some View {
        NavigationStack {
            Form {
                if let image = model.preview { Section { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 130) } }
                Section(L("Scénario")) {
                    TextField(L("Titre du projet"), text: $title)
                    TextField(L("Note de narration"), text: $narration, axis: .vertical).lineLimit(3...6)
                    Text(L("Brouillon éditorial : ne modifie pas les enregistrements.")).font(.caption).foregroundStyle(.secondary)
                    HStack { Text(L("Durée") + " (s)"); TextField(L("Durée"), value: $duration, format: .number.precision(.fractionLength(0...3))).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
                Section(L("Transition")) {
                    Picker(L("Transition"), selection: $transition) { ForEach(TransitionKind.allCases, id: \.self) { Text(transitionName($0)).tag($0) } }
                    if transition != .none {
                        HStack { Text(L("Durée") + " (s)"); TextField(L("Durée"), value: $overlap, format: .number.precision(.fractionLength(0...3))).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        Text(L("La transition chevauche la scène suivante. Sa durée est limitée à la moitié de chacune des deux scènes.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let validationError { Text(validationError).foregroundStyle(.red) }
            }.navigationTitle(L("Scénario"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Annuler")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(L("Enregistrer")) { save() } }
                }
                .onAppear { if let scene = model.selectedScene { sceneID = scene.id; title = scene.title; narration = scene.narration; duration = scene.duration.seconds; transition = scene.transition.kind; overlap = scene.transition.duration.seconds } }
        }.presentationDetents([.medium, .large]).preferredColorScheme(.dark)
    }
    private func save() {
        do {
            guard let index = model.document.scenes.firstIndex(where: { $0.id == sceneID }), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, duration.isFinite, duration > 0, overlap.isFinite, overlap >= 0 else { throw DocumentError.invalid(L("Durée")) }
            guard duration >= (model.document.scenes[index].clips.map(\.end).max()?.seconds ?? 0) else { throw DocumentError.invalid(L("Réduisez les clips avant de raccourcir leur scène.")) }
            var candidate = model.document
            candidate.scenes[index].title = title; candidate.scenes[index].narration = narration; candidate.scenes[index].duration = .init(seconds: duration)
            candidate.scenes[index].transition = .init(kind: transition, duration: .init(seconds: overlap))
            try candidate.validate()
            model.edit(L("Scénario")) { $0 = candidate }; dismiss()
        } catch { validationError = error.localizedDescription }
    }
    private func transitionName(_ kind: TransitionKind) -> String {
        switch kind {
        case .none: L("Coupe franche")
        case .dissolve: L("Fondu enchaîné")
        case .black: L("Noir")
        case .white: L("Blanc")
        case .slide: L("Glissement")
        case .wipe: L("Balayage")
        case .zoom: "Zoom"
        case .blur: L("Flou")
        case .glitch: "Glitch"
        }
    }
}

extension EditorModel {
    func importSRT(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 8 * 1024 * 1024 else { throw DocumentError.invalid(L("SRT trop volumineux")) }
            let segments = try CaptionCodec.importSRT(String(contentsOf: url, encoding: .utf8))
            edit(L("Sous-titres SRT")) { document in document.globalClips += segments.map { $0.asClip() } }
        } catch { self.error = error.localizedDescription }
    }
}
