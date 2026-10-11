import Foundation
@preconcurrency import AVFoundation
import CoreImage
import Darwin
import VideoToolbox

enum MovieQualityProfile: String, CaseIterable, Sendable {
    case compact, balanced, fidelity
    var title: String { switch self {
    case .compact: AppLocalization.bilingual("Compact", "Compact")
    case .balanced: AppLocalization.bilingual("Équilibré", "Balanced")
    case .fidelity: AppLocalization.bilingual("Haute fidélité", "High fidelity")
    } }
    var factor: Double { switch self { case .compact: 0.55; case .balanced: 0.72; case .fidelity: 0.88 } }
    var bitsPerPixel: Double { switch self { case .compact: 0.075; case .balanced: 0.14; case .fidelity: 0.24 } }
}

struct MovieExportSettings: Equatable, Sendable {
    var longEdge: Int = 1080
    var frameRate: Int = 30
    var codec: MovieCodec = .h264
    var bitrate: Int = 8_000_000
    // nil retains the explicit bitrate workflow, including existing callers.
    var qualityProfile: MovieQualityProfile? = nil
    func estimatedBitrate(for variant: OutputVariant) -> Int {
        guard let qualityProfile else { return bitrate }
        let size = dimensions(for: variant)
        let codecFactor = codec == .hevc ? 0.65 : 1.0
        return max(200_000, Int(size.width * size.height * Double(frameRate) * qualityProfile.bitsPerPixel * codecFactor))
    }
    func compressionProperties(for variant: OutputVariant, supportsConstantQuality: Bool, supportsQualityPriority: Bool) -> [String: Any] {
        var properties: [String: Any] = [AVVideoExpectedSourceFrameRateKey: frameRate, AVVideoMaxKeyFrameIntervalKey: frameRate * 2]
        if let qualityProfile, supportsConstantQuality {
            properties[kVTCompressionPropertyKey_ConstantQualityFactor as String] = qualityProfile.factor
        } else {
            properties[AVVideoAverageBitRateKey] = estimatedBitrate(for: variant)
        }
        if qualityProfile != nil, supportsQualityPriority {
            properties[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = false
        }
        return properties
    }
    func supportedEncoderProperties(for variant: OutputVariant) -> Set<String> {
        let size = dimensions(for: variant)
        var properties: CFDictionary?
        let status = VTCopySupportedPropertyDictionaryForEncoder(width: Int32(size.width), height: Int32(size.height), codecType: codec == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC, encoderSpecification: nil, encoderIDOut: nil, supportedPropertiesOut: &properties)
        guard status == noErr, let properties else { return [] }
        return Set((properties as NSDictionary).allKeys.compactMap { $0 as? String })
    }
    func dimensions(for variant: OutputVariant) -> CGSize {
        let ratio = variant.ratio
        let width = ratio >= 1 ? Double(longEdge) : Double(longEdge) * ratio
        let height = ratio >= 1 ? Double(longEdge) / ratio : Double(longEdge)
        return CGSize(width: max(2, Int((width / 2).rounded()) * 2), height: max(2, Int((height / 2).rounded()) * 2))
    }
}

enum MovieCodec: String, CaseIterable, Sendable { case h264 = "H.264", hevc = "HEVC" }

struct ExportReceipt: Sendable {
    var url: URL
    var width: Int
    var height: Int
    var frameRate: Double
    var duration: Double
    var hasAudio: Bool
    var constantQuality: Bool = false
}

actor MovieExporter {
    private let renderer = FrameRenderer(softwareRendering: true)
    private var exporting = false
    private let context = CIContext(options: [.useSoftwareRenderer: true, .outputColorSpace: CGColorSpace(name: CGColorSpace.itur_709)!])
    // Use the transfer function carried by the video tags. The named Core
    // Graphics Rec.709 display profile does not use the same transfer curve as
    // Core Video's ITU_R_709_2 buffers; treating their bytes as identical washes
    // out midtones when AVFoundation decodes the exported movie.
    private static let videoColorAttachments: [String: String] = [
        kCVImageBufferColorPrimariesKey as String: kCVImageBufferColorPrimaries_ITU_R_709_2 as String,
        kCVImageBufferTransferFunctionKey as String: kCVImageBufferTransferFunction_ITU_R_709_2 as String,
        kCVImageBufferYCbCrMatrixKey as String: kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String
    ]
    private static let videoColorSpace = CVImageBufferCreateColorSpaceFromAttachments(videoColorAttachments as CFDictionary)?.takeRetainedValue() ?? CGColorSpace(name: CGColorSpace.itur_709)!

    /// The value-type document parameter is a frozen snapshot. Call sequentially for variants.
    func export(document: ProjectDocument, variantID: UUID, rootURL: URL, settings: MovieExportSettings, outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> ExportReceipt {
        while exporting { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(10)) }
        exporting = true
        defer { exporting = false }
        try Task.checkCancellation()
        guard [24,25,30,50,60].contains(settings.frameRate), settings.longEdge >= 64, settings.longEdge <= 3840, settings.bitrate >= 100_000 else { throw MediaFailure.export("Réglages hors limites") }
        guard document.variants.contains(where: { $0.id == variantID }) else { throw MediaFailure.export("Format manquant") }
        let plan = RenderPlan.compile(document: document, variantID: variantID)
        guard plan.duration > .zero else { throw MediaFailure.export("Projet vide") }
        let size = settings.dimensions(for: plan.variant)
        let frameCount = max(1, Int(ceil(plan.duration.seconds * Double(settings.frameRate))))
        let encodedDuration = CMTime(value: Int64(frameCount), timescale: Int32(settings.frameRate))
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let supported = settings.supportedEncoderProperties(for: plan.variant)
        let constantQuality = settings.qualityProfile != nil && supported.contains(kVTCompressionPropertyKey_ConstantQualityFactor as String)
        // Quality-driven output has no fixed size; reserve conservatively and check while writing.
        try MediaFiles.checkSpace(at: parent, bytes: Int64(plan.duration.seconds * Double(settings.estimatedBitrate(for: plan.variant) + 256_000) / 8 * (constantQuality ? 3 : 1.25)) + 16_777_216)
        let temporary = parent.appendingPathComponent(".\(UUID().uuidString).mp4")
        // Nonthrowing cleanup must never overwrite the error being unwound by this async function.
        defer { _ = unlink(temporary.path) }
        var phase = L("Création de l’encodeur")
        do {
            let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
            let codec: AVVideoCodecType = settings.codec == .h264 ? .h264 : .hevc
            let compression = settings.compressionProperties(for: plan.variant, supportsConstantQuality: constantQuality, supportsQualityPriority: supported.contains(kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String))
            let outputSettings: [String: Any] = [AVVideoCodecKey: codec, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height), AVVideoCompressionPropertiesKey: compression, AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]]
            guard writer.canApply(outputSettings: outputSettings, forMediaType: .video) else { throw MediaFailure.unsupported("Codec ou résolution non pris en charge par cet appareil") }
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            video.expectsMediaDataInRealTime = false
            video.mediaTimeScale = Int32(settings.frameRate * 1000)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height), kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
            guard writer.canAdd(video) else { throw MediaFailure.export("Piste vidéo refusée") }; writer.add(video)
            phase = L("Préparation du mixage audio")
            let prepared = try await AudioComposer.prepare(plan: plan, rootURL: rootURL)
            var audioInput: AVAssetWriterInput?
            var audioReader: AVAssetReader?
            var audioOutput: AVAssetReaderAudioMixOutput?
            if prepared.hasAudio {
                let reader = try AVAssetReader(asset: prepared.composition)
                reader.timeRange = CMTimeRange(start: .zero, duration: encodedDuration)
                let tracks = try await prepared.composition.loadTracks(withMediaType: .audio)
                let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMIsFloatKey: false, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsNonInterleaved: false])
                output.audioMix = prepared.mix
                reader.add(output)
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else { throw MediaFailure.export("Piste audio refusée") }; writer.add(input)
                audioInput = input; audioReader = reader; audioOutput = output
            }
            defer { audioReader?.cancelReading(); if writer.status == .writing { writer.cancelWriting() } }
            phase = L("Démarrage de l’encodeur")
            guard writer.startWriting() else { throw writer.error ?? MediaFailure.export("Démarrage encodeur") }
            writer.startSession(atSourceTime: .zero)
            if let audioReader, !audioReader.startReading() { throw audioReader.error ?? MediaFailure.export("Démarrage audio") }
            var nextAudio = audioOutput?.copyNextSampleBuffer()
            var frameIndex = 0
            var audioFinished = audioInput == nil
            var videoFinished = false
            var lastProgress = ContinuousClock.now
            // Both inputs must be serviced cooperatively. Awaiting one blocked input
            // can deadlock the writer while it waits for samples from the other input.
            while !videoFinished || !audioFinished {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? MediaFailure.export("Encodeur arrêté") }
                var advanced = false
                if let audioInput, !audioFinished {
                    let videoTime = CMTime(value: Int64(frameIndex), timescale: Int32(settings.frameRate))
                    let audioHorizon = CMTimeAdd(videoTime, CMTime(value: 1, timescale: 4))
                    var supplied = 0
                    while audioInput.isReadyForMoreMediaData, let sample = nextAudio, supplied < 8 {
                        let stamp = CMSampleBufferGetPresentationTimeStamp(sample)
                        if stamp >= encodedDuration { nextAudio = nil; break }
                        if !videoFinished && video.isReadyForMoreMediaData && stamp > audioHorizon { break }
                        phase = String(format: L("Encodage audio à %.3f s"), stamp.seconds)
                        guard audioInput.append(sample) else { throw writer.error ?? MediaFailure.export("Encodage audio") }
                        nextAudio = audioOutput?.copyNextSampleBuffer()
                        supplied += 1; advanced = true
                    }
                    if nextAudio == nil {
                        if let audioReader, audioReader.status == .failed { throw audioReader.error ?? MediaFailure.export("Lecture audio") }
                        audioInput.markAsFinished(); audioFinished = true; advanced = true
                    }
                }
                if !videoFinished && video.isReadyForMoreMediaData {
                    phase = String(format: L("Encodage image %d/%d"), frameIndex + 1, frameCount)
                    let timestamp = CMTime(value: Int64(frameIndex), timescale: Int32(settings.frameRate))
                    let renderTime = MediaTime(seconds: min(timestamp.seconds, max(0, plan.duration.seconds - 1.0 / 60_000)))
                    let image = try await renderer.render(plan: plan, time: renderTime, rootURL: rootURL, size: size)
                    guard let pool = adaptor.pixelBufferPool else { throw MediaFailure.export("Pool de pixels indisponible") }
                    var pixelBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else { throw MediaFailure.export("Allocation image") }
                    for (key, value) in Self.videoColorAttachments { CVBufferSetAttachment(pixelBuffer, key as CFString, value as CFString, .shouldPropagate) }
                    context.render(CIImage(cgImage: image), to: pixelBuffer, bounds: CGRect(origin: .zero, size: size), colorSpace: Self.videoColorSpace)
                    guard adaptor.append(pixelBuffer, withPresentationTime: timestamp) else { throw writer.error ?? MediaFailure.export(String(format: L("Encodage image %d"), frameIndex)) }
                    if frameIndex.isMultiple(of: settings.frameRate * 2) { try MediaFiles.checkSpace(at: parent, bytes: 8_388_608) }
                    frameIndex += 1; advanced = true
                    progress(Double(frameIndex) / Double(frameCount) * 0.94)
                    if frameIndex == frameCount { video.markAsFinished(); videoFinished = true }
                }
                if advanced { lastProgress = .now }
                else {
                    guard lastProgress.duration(to: .now) < .seconds(30) else {
                        throw MediaFailure.export(String(format: L("Encodeur sans progression : vidéo %d/%d, audio %@"), frameIndex, frameCount, L(audioFinished ? "terminé" : "en attente")))
                    }
                    try await Task.sleep(for: .milliseconds(2))
                }
            }
            if let audioReader, audioReader.status == .failed { throw audioReader.error ?? MediaFailure.export("Lecture audio") }
            phase = L("Finalisation de l’encodeur")
            writer.endSession(atSourceTime: encodedDuration)
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw writer.error ?? MediaFailure.export("Finalisation du fichier") }
            progress(0.97)
            phase = L("Relecture du fichier terminé")
            var receipt = try await verify(url: temporary, expectedSize: size, expectedDuration: encodedDuration.seconds, expectedRate: Double(settings.frameRate), expectedAudio: prepared.hasAudio, expectedCodec: codec)
            receipt.constantQuality = constantQuality
            phase = L("Installation atomique du fichier vérifié")
            try Task.checkCancellation()
            try MovieFileInstallation.install(temporary: temporary, to: outputURL)
            progress(1)
            return ExportReceipt(url: outputURL, width: receipt.width, height: receipt.height, frameRate: receipt.frameRate, duration: receipt.duration, hasAudio: receipt.hasAudio)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let exists = FileManager.default.fileExists(atPath: temporary.path)
            throw MediaFailure.export(String(format: L("%@ : %@ (fichier temporaire %@)."), phase, error.localizedDescription, L(exists ? "présent" : "absent")))
        }
    }

    private func verify(url: URL, expectedSize: CGSize, expectedDuration: Double, expectedRate: Double, expectedAudio: Bool, expectedCodec: AVVideoCodecType) async throws -> ExportReceipt {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaFailure.export("Relecture : vidéo absente") }
        let descriptions = try await track.load(.formatDescriptions)
        let actualCodec = descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) }
        let desiredCodec = expectedCodec == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC
        guard actualCodec == desiredCodec else { throw MediaFailure.export("Relecture : codec différent du réglage") }
        let size = try await track.load(.naturalSize)
        let rate = Double(try await track.load(.nominalFrameRate))
        let duration = try await asset.load(.duration).seconds
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        guard size == expectedSize, abs(duration - expectedDuration) <= 1 / expectedRate + 0.01, abs(rate - expectedRate) < 0.1, hasAudio == expectedAudio else { throw MediaFailure.export("Relecture : caractéristiques différentes des réglages") }
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
        _ = try await generator.image(at: CMTime(seconds: max(0, duration * 0.5), preferredTimescale: 60_000))
        return ExportReceipt(url: url, width: Int(size.width), height: Int(size.height), frameRate: rate, duration: duration, hasAudio: hasAudio)
    }
}


/// A same-directory POSIX rename performs one atomic replacement. Foundation's
/// copy/remove replacement machinery is not needed for a verified sibling file.
enum MovieFileInstallation {
    static func install(temporary: URL, to destination: URL) throws {
        let sourceParent = temporary.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let destinationParent = destination.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        guard sourceParent == destinationParent else { throw MediaFailure.export("Le fichier de préparation doit être voisin de la destination") }
        let file = try FileHandle(forWritingTo: temporary)
        do { try file.synchronize(); try file.close() } catch { try? file.close(); throw error }
        guard rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: destination.path])
        }
    }
}
