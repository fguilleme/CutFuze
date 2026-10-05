import AVFoundation
import SwiftUI

private func VL(_ french: String, _ english: String) -> String { Locale.current.language.languageCode?.identifier == "fr" ? french : (ExtraStrings.english[french] ?? Strings.english[french] ?? english) }

struct VisionSheet: View {
    @ObservedObject var model: EditorModel
    @StateObject private var tracking = VisionTrackingService()
    @Environment(\.dismiss) private var dismiss
    @State private var sourceID: UUID?
    @State private var image: CGImage?
    @State private var region = CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
    @State private var error: String?
    @State private var result: TrackingResult?
    @State private var task: Task<Void, Never>?
    @State private var analyzedRevision: Int?
    private var sources: [RenderClip] { model.plan.clips.filter { $0.clip.kind == .video } }
    private var selectedSource: RenderClip? { sources.first { $0.id == sourceID } }
    private var target: RenderClip? { model.plan.clips.first { $0.id == model.selectedClipID } }
    private var validTarget: Bool { target?.clip.kind == .text || target?.clip.kind == .shape }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(VL("Dessinez un rectangle autour du sujet. Le suivi s’arrête si la confiance devient trop faible.", "Draw a rectangle around the subject. Tracking stops when confidence becomes too low.")).font(.subheadline)
                    Picker(VL("Vidéo source", "Source video"), selection: $sourceID) {
                        ForEach(sources) { source in Text(model.document.asset(source.clip.assetID)?.name ?? "Video").tag(Optional(source.id)) }
                    }.disabled(tracking.isWorking)
                    if let image {
                        GeometryReader { geometry in
                            ZStack(alignment: .topLeading) {
                                Image(decorative: image, scale: 1).resizable()
                                Rectangle().stroke(DesignTokens.amber, lineWidth: 3)
                                    .frame(width: region.width * geometry.size.width, height: region.height * geometry.size.height)
                                    .offset(x: region.minX * geometry.size.width, y: (1 - region.maxY) * geometry.size.height)
                            }.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                                    guard !tracking.isWorking else { return }
                                    let a = CGPoint(x: max(0, min(1, value.startLocation.x / geometry.size.width)), y: max(0, min(1, value.startLocation.y / geometry.size.height)))
                                    let b = CGPoint(x: max(0, min(1, value.location.x / geometry.size.width)), y: max(0, min(1, value.location.y / geometry.size.height)))
                                    region = CGRect(x: min(a.x, b.x), y: 1 - max(a.y, b.y), width: max(0.015, abs(a.x - b.x)), height: max(0.015, abs(a.y - b.y)))
                                    result = nil
                                })
                                .accessibilityLabel(VL("Région suivie dans la vidéo", "Tracked video region"))
                        }.aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    VStack {
                        regionSlider(VL("Centre horizontal", "Horizontal center"), keyPath: \.origin.x, maximum: max(0, 1 - region.width))
                        regionSlider(VL("Centre vertical", "Vertical center"), keyPath: \.origin.y, maximum: max(0, 1 - region.height))
                        regionSlider(VL("Largeur", "Width"), keyPath: \.size.width, maximum: max(0.02, 1 - region.minX), minimum: 0.02)
                        regionSlider(VL("Hauteur", "Height"), keyPath: \.size.height, maximum: max(0.02, 1 - region.minY), minimum: 0.02)
                    }.disabled(tracking.isWorking)
                    Text(VL("La trajectoire remplace les keyframes de position de la couche sélectionnée. Elle est calculée pour le format actif et reste une animation commune aux formats.", "The trajectory replaces the selected layer’s position keyframes. It is calculated for the active format and remains an animation shared by all formats.")).font(.footnote).foregroundStyle(.secondary)
                    if !validTarget { Text(VL("Sélectionnez d’abord un texte ou une forme dans l’atelier.", "First select a text or shape layer in the editor.")).foregroundStyle(.orange) }
                    if tracking.isWorking { ProgressView(value: tracking.progress); Button(L("Annuler")) { task?.cancel(); tracking.cancel() } }
                    else { Button(VL("Analyser le mouvement", "Analyze motion")) { analyze() }.buttonStyle(.borderedProminent).tint(DesignTokens.amber).disabled(!validTarget || sourceID == nil) }
                    if let result {
                        Text(VL("\(result.points.count) positions mesurées", "\(result.points.count) measured positions"))
                        if let lost = result.lostAtSourceSeconds { Text(VL("Suivi perdu à \(timeLabel(lost)) dans la source. La trajectoire s’arrête à la dernière position fiable.", "Tracking lost at \(timeLabel(lost)) in the source. The trajectory stops at the last reliable position.")).font(.footnote) }
                        Button(VL("Appliquer à la couche sélectionnée", "Apply to selected layer")) { apply(result) }.buttonStyle(.bordered)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(22)
            }.navigationTitle(VL("Suivi de région", "Region tracking")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() } } }
        }.onAppear { sourceID = sources.first?.id }
            .task(id: sourceID) { result = nil; await thumbnail() }
            .onDisappear { task?.cancel(); tracking.cancel() }
    }
    private func regionSlider(_ title: String, keyPath: WritableKeyPath<CGRect, CGFloat>, maximum: Double, minimum: Double = 0) -> some View {
        HStack { Text(title).font(.caption).frame(width: 100, alignment: .leading); Slider(value: Binding(get: { Double(region[keyPath: keyPath]) }, set: { region[keyPath: keyPath] = $0; result = nil }), in: minimum...max(minimum + 0.001, maximum)); Text("\(Int(region[keyPath: keyPath] * 100))%").font(.caption.monospacedDigit()).frame(width: 40) }
    }
    private func thumbnail() async {
        guard let source = selectedSource, let asset = model.document.asset(source.clip.assetID) else { return }
        do {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: model.rootURL.appendingPathComponent(asset.relativePath)))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 720, height: 720)
            image = try await generator.image(at: CMTime(seconds: source.clip.sourceStart.seconds, preferredTimescale: 60_000)).image
        } catch { self.error = error.localizedDescription }
    }
    private func analyze() {
        guard let source = selectedSource, let asset = model.document.asset(source.clip.assetID) else { return }
        result = nil; error = nil; analyzedRevision = model.document.revision; model.stop()
        task = Task { do { result = try await tracking.track(url: model.rootURL.appendingPathComponent(asset.relativePath), sourceStart: source.clip.sourceStart.seconds, duration: source.clip.sourceDuration.seconds, region: region) } catch is CancellationError {} catch { self.error = error.localizedDescription } }
    }
    private func apply(_ result: TrackingResult) {
        guard analyzedRevision == model.document.revision, let source = selectedSource, let sourceAsset = model.document.asset(source.clip.assetID), let target else { error = VL("Le montage a changé. Relancez l’analyse.", "The edit changed. Run the analysis again."); return }
        let keys = VisionTrackingService.keyframes(from: result, source: source, sourceAsset: sourceAsset, target: target, variant: model.variant)
        guard !keys.isEmpty else { error = VisionAnalysisError.noSamples.localizedDescription; return }
        model.changeClip(VL("Appliquer le suivi", "Apply tracking")) { clip in clip.keyframes.removeAll { $0.property == .x || $0.property == .y }; clip.keyframes.append(contentsOf: keys) }
        dismiss()
    }
}

struct StabilizationSheet: View {
    @ObservedObject var model: EditorModel
    @StateObject private var service = VisionStabilizationService()
    @Environment(\.dismiss) private var dismiss
    @State private var crop = 1.15
    @State private var result: StabilizationResult?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var revision: Int?
    private var source: RenderClip? { model.plan.clips.first { $0.id == model.selectedClipID && $0.clip.kind == .video } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(VL("Stabilisation par translation", "Translation stabilization")).font(.headline)
                    Text(VL("Pour un plan court avec de petites secousses, jusqu’à 60 secondes. Ce traitement ne corrige ni les rotations, ni le rolling shutter, ni les grands changements de scène.", "For a short shot with small shakes, up to 60 seconds. This process does not correct rotation, rolling shutter or large scene changes."))
                    HStack { Text(VL("Recadrage maximal", "Maximum crop")); Slider(value: $crop, in: 1.05...1.35); Text("\(Int((crop - 1) * 100))%").monospacedDigit() }.disabled(service.isWorking)
                    Text(VL("Les animations de position et d’échelle seront remplacées par la correction mesurée. Elles sont communes aux formats.", "Position and scale animations will be replaced by the measured correction. These animations are shared across formats.")).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    if service.isWorking { ProgressView(value: service.progress); Button(L("Annuler")) { task?.cancel(); service.cancel() } }
                    else { Button(VL("Analyser la vidéo", "Analyze video")) { analyze() }.disabled(source == nil) }
                    if let result {
                        Text(VL("Échelle de correction : ", "Correction scale: ") + result.cropScale.formatted(.number.precision(.fractionLength(3))))
                        Text(VL("Déplacement mesuré entre images : ", "Measured inter-frame displacement: ") + result.measuredJitter.formatted(.number.precision(.fractionLength(4))))
                        Button(VL("Appliquer les keyframes de correction", "Apply correction keyframes")) { apply(result) }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle(VL("Stabiliser", "Stabilize")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() } } }
        }.onDisappear { task?.cancel(); service.cancel() }
    }
    private func analyze() {
        guard let source, let asset = model.document.asset(source.clip.assetID) else { return }
        revision = model.document.revision; result = nil; error = nil; model.stop()
        task = Task { do { result = try await service.analyze(url: model.rootURL.appendingPathComponent(asset.relativePath), sourceStart: source.clip.sourceStart.seconds, duration: source.clip.sourceDuration.seconds, maximumCrop: crop) } catch is CancellationError {} catch { self.error = error.localizedDescription } }
    }
    private func apply(_ result: StabilizationResult) {
        guard revision == model.document.revision, let source, let asset = model.document.asset(source.clip.assetID) else { error = VL("Le montage a changé. Relancez l’analyse.", "The edit changed. Run the analysis again."); return }
        let keys = VisionStabilizationService.keyframes(from: result, source: source, asset: asset, variant: model.variant)
        model.changeClip(VL("Stabilisation", "Stabilization")) { clip in clip.keyframes.removeAll { $0.property == .x || $0.property == .y || $0.property == .scale }; clip.keyframes.append(contentsOf: keys) }
        dismiss()
    }
}
