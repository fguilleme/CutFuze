import SwiftUI
import AVFoundation
import ImageIO

private func CKL(_ french: String, _ english: String) -> String {
    AppLocalization.bilingual(french, english)
}

/// All coordinates exposed here are source pixels with a top-left origin, like the
/// displayed CGImage. Letterbox taps are rejected rather than clamped to an edge.
enum ChromaPickerGeometry {
    static func fittedRect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    static func sourcePixel(at point: CGPoint, imageSize: CGSize, in bounds: CGSize) -> CGPoint? {
        let fitted = fittedRect(imageSize: imageSize, in: bounds)
        guard fitted.width > 0, fitted.height > 0, fitted.contains(point) else { return nil }
        return CGPoint(x: min(imageSize.width - 1, floor((point.x - fitted.minX) / fitted.width * imageSize.width)), y: min(imageSize.height - 1, floor((point.y - fitted.minY) / fitted.height * imageSize.height)))
    }
    static func srgbHex(in image: CGImage, at sourcePixel: CGPoint) -> String? {
        guard sourcePixel.x >= 0, sourcePixel.y >= 0, sourcePixel.x < CGFloat(image.width), sourcePixel.y < CGFloat(image.height),
              let sample = image.cropping(to: CGRect(x: floor(sourcePixel.x), y: floor(sourcePixel.y), width: 1, height: 1)) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let success = bytes.withUnsafeMutableBytes { storage in
            guard let context = CGContext(data: storage.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard success, bytes[3] > 0 else { return nil }
        let alpha = Double(bytes[3]) / 255
        let rgb = bytes.prefix(3).map { min(255, Int((Double($0) / alpha).rounded())) }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }
}

@MainActor
struct ChromaKeySheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var source: CGImage?
    @State private var result: CGImage?
    @State private var enabled = false
    @State private var hex = "#00FF00"
    @State private var tolerance = 0.2
    @State private var softness = 0.1
    @State private var error: String?
    @State private var selectedPixel: CGPoint?
    @State private var snapshot: ProjectDocument?
    @State private var clipID: UUID?
    @State private var variantID: UUID?
    @State private var localScope = true
    @State private var seconds = 0.0
    @State private var loaded = false
    @State private var previewGeneration = 0
    private var draftKey: String { "\(enabled)|\(hex)|\(tolerance)|\(softness)|\(loaded)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Image(systemName: "scope"); Text(L("Portée") + " · " + L(localScope ? "Format actif" : "Commun")) }.font(.caption).foregroundStyle(DesignTokens.amber)
                    Text(CKL("Touchez la couleur à retirer dans ce média. La pipette utilise son image orientée avant effets, sans les autres couches.", "Tap the color to remove in this media. The picker uses its oriented image before effects, without the other layers.")).font(.subheadline)
                    if let source {
                        sourcePicker(source)
                    } else if error == nil {
                        ProgressView(L("Préparation…")).frame(maxWidth: .infinity, minHeight: 170)
                    }
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8).fill(Color(hex: hex)).frame(width: 44, height: 44).overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.5)))
                        VStack(alignment: .leading) {
                            Text(hex).font(.body.monospaced())
                            if let selectedPixel { Text("\(Int(selectedPixel.x)), \(Int(selectedPixel.y)) px").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        ColorPicker(L("Couleur"), selection: Binding(get: { Color(hex: hex) }, set: { color in
                            let ui = UIColor(color)
                            if let converted = ui.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric, options: nil), let components = converted.components, components.count >= 3 {
                                hex = String(format: "#%02X%02X%02X", Int((components[0] * 255).rounded()), Int((components[1] * 255).rounded()), Int((components[2] * 255).rounded()))
                                enabled = true; selectedPixel = nil
                            }
                        }), supportsOpacity: false).labelsHidden().accessibilityLabel(CKL("Choisir manuellement la couleur à retirer", "Manually choose the color to remove"))
                    }
                    Toggle(CKL("Retirer cette couleur", "Remove this color"), isOn: $enabled)
                    valueSlider(CKL("Tolérance", "Tolerance"), value: $tolerance, range: 0...1)
                    valueSlider(CKL("Douceur des bords", "Edge softness"), value: $softness, range: 0.005...0.5)
                    if let result {
                        Text(CKL("Résultat dans le montage", "Result in the edit")).font(.headline)
                        Image(decorative: result, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 220).background(.black).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text(CKL("Les effets de couleur modifient aussi la couleur à détacher. Vérifiez le résultat et ajustez la tolérance. Annuler conserve vos réglages actuels.", "Color effects also change the color being keyed. Check the result and adjust tolerance. Cancel keeps your current settings.")).font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }.padding(20)
            }
            .navigationTitle(CKL("Pipette chroma", "Chroma picker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Annuler")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(CKL("Appliquer", "Apply")) { apply() }.disabled(!loaded || source == nil) }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .task(id: draftKey) { await renderDraft() }
    }

    private func sourcePicker(_ image: CGImage) -> some View {
        GeometryReader { geometry in
            let imageSize = CGSize(width: image.width, height: image.height)
            let fitted = ChromaPickerGeometry.fittedRect(imageSize: imageSize, in: geometry.size)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(DesignTokens.panel)
                Image(decorative: image, scale: 1).resizable().frame(width: fitted.width, height: fitted.height).position(x: fitted.midX, y: fitted.midY)
                if let pixel = selectedPixel {
                    Image(systemName: "plus.circle").font(.system(size: 26, weight: .bold)).foregroundStyle(.white).shadow(color: .black, radius: 2)
                        .position(x: fitted.minX + (pixel.x + 0.5) / imageSize.width * fitted.width, y: fitted.minY + (pixel.y + 0.5) / imageSize.height * fitted.height)
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard let pixel = ChromaPickerGeometry.sourcePixel(at: value.location, imageSize: imageSize, in: geometry.size), let picked = ChromaPickerGeometry.srgbHex(in: image, at: pixel) else { return }
                    selectedPixel = pixel; hex = picked; enabled = true; error = nil
                })
                .accessibilityLabel(CKL("Image source à échantillonner", "Source image to sample"))
                .accessibilityHint(CKL("Utilisez le sélecteur de couleur pour un réglage accessible.", "Use the color selector for an accessible adjustment."))
        }.frame(height: 235).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).tint(DesignTokens.amber).accessibilityLabel(title).accessibilityValue(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
        }
    }

    private func load() async {
        model.stop()
        guard let item = model.plan.clips.first(where: { $0.id == model.selectedClipID }), let asset = model.document.asset(item.clip.assetID), asset.kind == .video || asset.kind == .image else {
            error = CKL("Sélectionnez une image ou une vidéo.", "Select an image or a video."); return
        }
        snapshot = model.document; clipID = item.id; variantID = model.variantID; localScope = model.localScope
        seconds = min(max(model.playhead, item.globalStart.seconds), max(item.globalStart.seconds, item.end.seconds - 1 / 60_000))
        let presentation = item.presentation
        enabled = presentation.chromaKeyColor != nil; hex = presentation.chromaKeyColor ?? "#00FF00"
        tolerance = presentation.chromaKeyTolerance; softness = presentation.chromaKeySoftness
        do {
            if asset.kind == .image { source = try await MediaImporter.shared.thumbnail(asset: asset, rootURL: model.rootURL, maxSize: 1600) }
            else {
                let url = try MediaFiles.checkedURL(relativePath: asset.relativePath, root: model.rootURL)
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true; generator.dynamicRangePolicy = .forceSDR
                generator.maximumSize = CGSize(width: 1600, height: 1600)
                generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
                let local = MediaTime(seconds: seconds) - item.globalStart
                let sourceTime = TimeMapping.sourceTime(for: local, clip: item.clip)
                let clamped = min(sourceTime.seconds, max(0, asset.duration.seconds - 1 / max(asset.nominalFrameRate, 600)))
                source = try await generator.image(at: CMTime(seconds: clamped, preferredTimescale: 60_000)).image
            }
            try Task.checkCancellation(); loaded = true
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }

    private func renderDraft() async {
        guard loaded, var draft = snapshot, let clipID, let variantID else { return }
        previewGeneration += 1; let generation = previewGeneration
        let set: (inout Presentation) -> Void = { p in p.chromaKeyColor = enabled ? hex : nil; p.chromaKeyTolerance = tolerance; p.chromaKeySoftness = softness }
        if localScope, let index = draft.variants.firstIndex(where: { $0.id == variantID }), let clip = draft.clip(clipID) {
            var p = draft.variants[index].overrides[clipID.uuidString] ?? clip.presentation; set(&p); draft.variants[index].overrides[clipID.uuidString] = p
        } else { draft.updateClip(clipID) { set(&$0.presentation) } }
        let plan = RenderPlan.compile(document: draft, variantID: variantID)
        let ratio = plan.variant.ratio
        do {
            try await Task.sleep(for: .milliseconds(80))
            let rendered = try await model.renderer.render(plan: plan, time: .init(seconds: seconds), rootURL: model.rootURL, size: CGSize(width: ratio >= 1 ? 480 : 480 * ratio, height: ratio >= 1 ? 480 / ratio : 480))
            guard !Task.isCancelled, generation == previewGeneration else { return }; result = rendered
        } catch is CancellationError {} catch { if generation == previewGeneration { self.error = error.localizedDescription } }
    }

    private func apply() {
        guard model.selectedClipID == clipID, model.variantID == variantID, model.localScope == localScope, model.document.revision == snapshot?.revision else {
            error = CKL("Le montage a changé. Fermez puis rouvrez la pipette.", "The edit changed. Close and reopen the picker."); return
        }
        model.changePresentation { p in p.chromaKeyColor = enabled ? hex : nil; p.chromaKeyTolerance = tolerance; p.chromaKeySoftness = softness }
        dismiss()
    }
}
