import SwiftUI
import Photos
import AVKit

private struct ShareFiles: Identifiable { let id = UUID(); var urls: [URL] }
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock(); private var flag = false
    func cancel() { lock.lock(); flag = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
struct ExportScreen: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: ProjectDocument?
    @State private var selected: Set<UUID> = []
    @State private var settings = MovieExportSettings(longEdge: 1920, codec: .hevc, qualityProfile: .balanced)
    @State private var manualBitrate = false
    @State private var quality = MovieQualityProfile.balanced
    @StateObject private var continuedWork = ContinuedWork()
    @State private var running = false
    @State private var progress = 0.0
    @State private var currentName = ""
    @State private var receipts: [ExportReceipt] = []
    @State private var files: [URL] = []
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    @State private var flag = CancellationFlag()
    @State private var sharing: ShareFiles?
    @State private var player: AVPlayer?
    @State private var photosSaved = false
    private var document: ProjectDocument { snapshot ?? model.document }
    private var estimatedBytes: Double {
        document.variants.filter { selected.contains($0.id) }.reduce(0) {
            $0 + document.duration.seconds * Double(settings.estimatedBitrate(for: $1) + 192_000) / 8
        }
    }
    private func E(_ fr: String, _ en: String) -> String { AppLocalization.bilingual(fr, en) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L("Un montage.\nPlusieurs horizons.")).font(.system(size: 32, weight: .medium, design: .serif)).foregroundStyle(DesignTokens.ink)
                    Text(L("Les formats partagent les mêmes coupes et le même son.")).font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Formats à exporter")).font(.subheadline.bold())
                        ForEach(document.variants) { variant in
                            let size = settings.dimensions(for: variant)
                            Button { if selected.contains(variant.id) { selected.remove(variant.id) } else { selected.insert(variant.id) } } label: {
                                HStack(spacing: 14) {
                                    ZStack { RoundedRectangle(cornerRadius: 8).fill(DesignTokens.paper).frame(width: 52, height: 52); RoundedRectangle(cornerRadius: 3).strokeBorder(DesignTokens.ink, lineWidth: 1.5).frame(width: variant.ratio >= 1 ? 30 : 30 * variant.ratio, height: variant.ratio >= 1 ? 30 / variant.ratio : 30) }
                                    VStack(alignment: .leading, spacing: 4) { Text("\(Int(variant.widthRatio)):\(Int(variant.heightRatio)) · \(L(variant.name))").font(.subheadline.weight(.semibold)); Text("\(Int(size.width)) × \(Int(size.height)) px").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                                    Spacer(); Image(systemName: selected.contains(variant.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(variant.id) ? DesignTokens.ink : .secondary)
                                }
                            }.buttonStyle(.plain).disabled(running).accessibilityAddTraits(selected.contains(variant.id) ? .isSelected : []).accessibilityIdentifier("exportVariant-\(Int(variant.widthRatio))x\(Int(variant.heightRatio))")
                        }
                    }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(E("Qualité / taille", "Quality / size")).font(.subheadline.bold())
                            Picker(E("Profil d’export", "Export profile"), selection: $quality) {
                                ForEach(MovieQualityProfile.allCases, id: \.self) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).accessibilityIdentifier("exportQualityProfile").disabled(manualBitrate)
                            Text(qualityDescription).font(.caption).foregroundStyle(.secondary)
                        }
                        Picker(L("Résolution"), selection: $settings.longEdge) { Text("720p · 1280 px").tag(1280); Text("1080p · 1920 px").tag(1920); Text("1440p · 2560 px").tag(2560); Text("2160p · 3840 px").tag(3840) }.accessibilityIdentifier("exportResolution")
                        Picker(L("Cadence"), selection: $settings.frameRate) { ForEach([24, 25, 30, 50, 60], id: \.self) { Text("\($0) fps").tag($0) } }
                        Picker(E("Compression", "Compression"), selection: $settings.codec) {
                            Text(E("Efficace · HEVC", "Efficient · HEVC")).tag(MovieCodec.hevc)
                            Text(E("Compatible · H.264", "Compatible · H.264")).tag(MovieCodec.h264)
                        }.accessibilityIdentifier("exportCompression")
                        Text(E("Qualité constante si l’encodeur la prend en charge ; sinon débit adapté au profil, à la résolution et à la cadence. HEVC peut être moins compatible avec certains lecteurs.", "Constant quality when supported by the encoder; otherwise bitrate is adapted to the profile, resolution and frame rate. HEVC may be less compatible with some players.")).font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup(E("Avancé", "Advanced")) {
                            Toggle(E("Débit manuel", "Manual bitrate"), isOn: $manualBitrate).accessibilityIdentifier("exportManualBitrate")
                            if manualBitrate {
                                Picker(E("Débit vidéo", "Video bitrate"), selection: $settings.bitrate) { Text("4 Mb/s").tag(4_000_000); Text("8 Mb/s").tag(8_000_000); Text("16 Mb/s").tag(16_000_000); Text("35 Mb/s").tag(35_000_000) }
                            }
                        }
                        HStack { Text("SDR · Rec.709"); Spacer(); Text("≈ \(Int(estimatedBytes / 1_000_000)) \(L("Mo"))").monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                        if !manualBitrate { Text(E("Taille indicative : elle varie avec le mouvement et les détails. Ce n’est pas une limite de fichier.", "Indicative size: it varies with motion and detail. This is not a file-size limit.")).font(.caption).foregroundStyle(.secondary) }
                    }.pickerStyle(.menu).tint(DesignTokens.ink).disabled(running).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    if running {
                        VStack(alignment: .leading, spacing: 10) { HStack { Text(currentName).font(.subheadline.bold()); Spacer(); Text("\(Int(progress * 100)) %").monospacedDigit() }; ProgressView(value: progress).tint(DesignTokens.ink); Button(L("Annuler l’export"), role: .destructive) { flag.cancel(); task?.cancel() }.frame(minHeight: 44) }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        Button(action: exportMovies) { Label(L("Lancer l’export"), systemImage: "arrow.up.right").font(.headline).frame(maxWidth: .infinity).frame(height: 56).foregroundStyle(.white).background(DesignTokens.ink, in: RoundedRectangle(cornerRadius: 16)) }.disabled(selected.isEmpty || document.duration <= .zero)
                    }
                    if let failure { Text(failure).font(.subheadline).foregroundStyle(.red).textSelection(.enabled) }
                    if let notice = continuedWork.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if !receipts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Terminé")).font(.title3.bold())
                            ForEach(receipts, id: \.url) { receipt in
                                HStack { Button { player = AVPlayer(url: receipt.url); player?.play() } label: { Label("\(receipt.width) × \(receipt.height) · \(String(format: "%.2f", receipt.duration))s", systemImage: "play.circle").font(.caption.monospacedDigit()) }; Spacer(); Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                Text(receipt.constantQuality ? E("Encodé en qualité constante", "Encoded with constant quality") : E("Encodé avec un débit cible", "Encoded with a target bitrate")).font(.caption).foregroundStyle(.secondary)
                            }
                            if let player { VideoPlayer(player: player).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 12)) }
                            Button { sharing = ShareFiles(urls: receipts.map(\.url)) } label: { Label(L("Partager"), systemImage: "square.and.arrow.up").frame(minHeight: 44) }
                            Button(photosSaved ? L("Enregistré dans Photos") : L("Enregistrer dans Photos")) { saveToPhotos() }.disabled(photosSaved)
                        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: exportPackage) { Label(L("Exporter le projet complet"), systemImage: "shippingbox").font(.subheadline.bold()).frame(minHeight: 44) }.disabled(running)
                        Text(L("Documents et médias inclus. Réouvrable sur un autre appareil.")).font(.caption).foregroundStyle(.secondary)
                        HStack { Button("SRT") { exportCaptions(vtt: false) }; Button("VTT") { exportCaptions(vtt: true) } }.buttonStyle(.bordered).disabled(CaptionCodec.segments(document: document).isEmpty || running).accessibilityLabel(L("Exporter les sous-titres"))
                        ForEach(files, id: \.self) { url in Button { sharing = ShareFiles(urls: [url]) } label: { Label(url.lastPathComponent, systemImage: "square.and.arrow.up").font(.caption).frame(minHeight: 44) } }
                    }.foregroundStyle(DesignTokens.ink)
                }.padding(22)
            }.background(DesignTokens.paper).foregroundStyle(DesignTokens.ink).navigationTitle(L("Exporter")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Fermer")) { player?.pause(); dismiss() }.disabled(running).tint(DesignTokens.ink).accessibilityIdentifier("closeExport") } }
        }.preferredColorScheme(.light).interactiveDismissDisabled(running)
        .onAppear { if snapshot == nil { snapshot = model.document; selected = Set(model.document.variants.map(\.id)) } }
        .onDisappear { player?.pause() }
        .onChange(of: quality) { _, value in if !manualBitrate { settings.qualityProfile = value } }
        .onChange(of: manualBitrate) { _, value in settings.qualityProfile = value ? nil : quality }
        .sheet(item: $sharing) { share in ActivitySheet(urls: share.urls) }
    }
    private var qualityDescription: String {
        switch quality {
        case .compact: E("Fichier plus léger, avec un compromis sur les détails.", "Smaller file, with a trade-off in detail.")
        case .balanced: E("Un compromis entre détails préservés et taille du fichier.", "A balance between preserved detail and file size.")
        case .fidelity: E("Priorité aux détails ; le fichier peut être plus volumineux.", "Prioritize detail; the file may be larger.")
        }
    }
    private func exportMovies() {
        let d = document, root = model.rootURL, settings = settings
        let variants = d.variants.filter { selected.contains($0.id) }
        running = true; failure = nil; progress = 0; receipts = []; photosSaved = false; flag = CancellationFlag()
        task = Task {
            var success = false
            defer { running = false; continuedWork.finish(success: success) }
            await continuedWork.begin(title: E("Export vidéo CutFuze", "CutFuze video export")) { flag.cancel(); task?.cancel() }
            let exporter = MovieExporter()
            do {
                for (index, variant) in variants.enumerated() {
                    try Task.checkCancellation()
                    currentName = "\(Int(variant.widthRatio)):\(Int(variant.heightRatio))"; progress = 0
                    let output = root.appendingPathComponent("Exports", isDirectory: true).appendingPathComponent("\(d.id.uuidString.prefix(8))-\(Int(variant.widthRatio))x\(Int(variant.heightRatio))-r\(d.revision).mp4")
                    let receipt = try await exporter.export(document: d, variantID: variant.id, rootURL: root, settings: settings, outputURL: output) { value in Task { @MainActor in progress = value; continuedWork.update((Double(index) + value) / Double(variants.count)) } }
                    receipts.append(receipt)
                }
                success = true
            } catch is CancellationError { failure = L("Export annulé. Les fichiers déjà terminés restent disponibles.") } catch { failure = error.localizedDescription }
        }
    }
    private func exportPackage() {
        let d = document, root = model.rootURL
        let output = root.appendingPathComponent("Exports", isDirectory: true).appendingPathComponent("\(d.id.uuidString.prefix(8))-r\(d.revision).cutlabproject")
        running = true; failure = nil; progress = 0; currentName = L("Projet complet"); flag = CancellationFlag(); let cancel = flag
        task = Task {
            defer { running = false }
            do { try await Task.detached { try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true); try PortableProject.export(document: d, rootURL: root, to: output, cancelled: { cancel.cancelled }) }.value; if !files.contains(output) { files.append(output) }; progress = 1 }
            catch { failure = error.localizedDescription }
        }
    }
    private func exportCaptions(vtt: Bool) {
        do {
            let url = model.rootURL.appendingPathComponent("Exports", isDirectory: true).appendingPathComponent("\(document.id.uuidString.prefix(8)).\(vtt ? "vtt" : "srt")")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let segments = CaptionCodec.segments(document: document)
            try (vtt ? CaptionCodec.exportVTT(segments) : CaptionCodec.exportSRT(segments)).write(to: url, atomically: true, encoding: .utf8)
            sharing = ShareFiles(urls: [url])
        } catch { failure = error.localizedDescription }
    }
    private func saveToPhotos() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { failure = L("Accès Photos refusé. Vos fichiers restent disponibles via Partager."); return }
            do { let urls = receipts.map(\.url); try await PHPhotoLibrary.shared().performChanges { for url in urls { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) } }; photosSaved = true } catch { failure = error.localizedDescription }
        }
    }
}
struct ActivitySheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
struct VariantComparison: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var images: [UUID: CGImage] = [:]
    @State private var error: String?
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text(L("Même instant, plusieurs compositions.")).font(.system(size: 30, weight: .medium, design: .serif))
            Text(timeLabel(model.playhead)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            ForEach(model.document.variants) { variant in VStack(alignment: .leading, spacing: 8) { HStack { Text("\(Int(variant.widthRatio)):\(Int(variant.heightRatio))").font(.headline); Spacer(); Button(L("Ouvrir")) { model.changeVariant(variant.id); dismiss() } }; if let image = images[variant.id] { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 260).frame(maxWidth: .infinity).background(.black).clipShape(RoundedRectangle(cornerRadius: 14)) } else { ProgressView().frame(height: 150).frame(maxWidth: .infinity) } } }
            if let error { Text(error).foregroundStyle(.red) }
        }.padding(22) }.background(DesignTokens.ink).navigationTitle(L("Comparer les formats")).navigationBarTitleDisplayMode(.inline).toolbar { Button(L("Fermer")) { dismiss() }.accessibilityIdentifier("closeComparison") } }.preferredColorScheme(.dark)
            .task { let snapshot = model.document, time = MediaTime(seconds: model.playhead); let renderer = FrameRenderer(); do { for variant in snapshot.variants { let ratio = variant.ratio; images[variant.id] = try await renderer.render(plan: .compile(document: snapshot, variantID: variant.id), time: time, rootURL: model.rootURL, size: CGSize(width: ratio >= 1 ? 480 : 480*ratio, height: ratio >= 1 ? 480/ratio : 480)) } } catch { self.error = error.localizedDescription } }
    }
}
