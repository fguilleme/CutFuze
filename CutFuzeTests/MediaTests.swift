import XCTest
import AVFoundation
import CoreImage
import ImageIO
@testable import CutFuze

@MainActor final class MediaTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func shape(_ hex: String, duration: Double = 0.5) -> Clip {
        Clip(kind: .shape, duration: .init(seconds: duration), sourceDuration: .init(seconds: duration), presentation: Presentation(color: hex))
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress!, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: -CGFloat(x), y: -CGFloat(y)); context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    private func imageFixture(at url: URL) throws {
        let context = CGContext(data: nil, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.85, green: 0.12, blue: 0.15, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        context.setFillColor(CGColor(red: 0.05, green: 0.2, blue: 0.95, alpha: 1)); context.fill(CGRect(x: 80, y: 0, width: 80, height: 90))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
    private func audioFixture(at url: URL, seconds: Double = 1) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
        let samples = Int(seconds * 48_000)
        for base in stride(from: 0, to: samples, by: 2048) {
            let count = min(2048, samples - base); buffer.frameLength = AVAudioFrameCount(count)
            for index in 0..<count {
                let t = Double(base + index) / 48_000
                buffer.floatChannelData![0][index] = Float(sin(t * 2 * .pi * 440) * 0.3)
            }
            try file.write(from: buffer)
        }
    }

    func testRendererLayerOrderMaskNeutralAndCaptionBoundaries() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let renderer = FrameRenderer()
        var back = shape("#FF0000", duration: 1)
        var front = shape("#0000FF", duration: 1); front.layer = 1
        front.presentation.mask = .ellipse; front.presentation.maskWidth = 0.5; front.presentation.maskHeight = 0.5
        var doc = ProjectDocument(scenes: [.init(duration: .init(seconds: 1), clips: [back, front])])
        let size = CGSize(width: 160, height: 160)
        let first = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.2), rootURL: root, size: size)
        XCTAssertGreaterThan(pixel(first, x: 80, y: 80)[2], 220)
        XCTAssertGreaterThan(pixel(first, x: 5, y: 5)[0], 220)
        back.effects = EffectKind.allCases.map { .init(kind: $0, amount: 0) }
        doc.scenes[0].clips[0] = back
        let neutral = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.2), rootURL: root, size: size)
        XCTAssertEqual(first.dataProvider?.data as Data?, neutral.dataProvider?.data as Data?)
        let caption = Clip(kind: .text, start: .init(seconds: 0.25), duration: .init(seconds: 0.5), text: "Été • 你好", presentation: Presentation(textSize: 0.25), layer: 2, isCaption: true)
        doc.scenes[0].clips.append(caption)
        let before = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.249), rootURL: root, size: size)
        let during = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.25), rootURL: root, size: size)
        let after = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.75), rootURL: root, size: size)
        XCTAssertEqual(before.dataProvider?.data as Data?, after.dataProvider?.data as Data?)
        XCTAssertNotEqual(before.dataProvider?.data as Data?, during.dataProvider?.data as Data?)
    }

    func testEightTransitionsAndEffectCatalogRender() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let renderer = FrameRenderer()
        var signatures = Set<Data>()
        for kind in TransitionKind.allCases where kind != .none {
            var markerA = shape("#FFFF00", duration: 1); markerA.layer = 1; markerA.presentation.scale = 0.3; markerA.presentation.x = 0.3
            var markerB = shape("#FFFFFF", duration: 1); markerB.layer = 1; markerB.presentation.scale = 0.3; markerB.presentation.x = 0.7
            let doc = ProjectDocument(scenes: [.init(duration: .init(seconds: 1), clips: [shape("#ED3424", duration: 1), markerA], transition: .init(kind: kind, duration: .init(seconds: 0.4))), .init(duration: .init(seconds: 1), clips: [shape("#183DDD", duration: 1), markerB])])
            let image = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.73), rootURL: root, size: CGSize(width: 128, height: 128))
            signatures.insert(image.dataProvider!.data! as Data)
        }
        XCTAssertEqual(signatures.count, 8, "Eight visually distinct transitions on a patterned corpus")
        for kind in EffectKind.allCases {
            var clip = shape("#806050"); clip.effects = [.init(kind: kind, amount: 0.5)]
            let doc = ProjectDocument(scenes: [.init(duration: .init(seconds: 0.5), clips: [clip])])
            _ = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.2), rootURL: root, size: CGSize(width: 128, height: 128))
        }
    }

    func testPhotosOnlyThreeVariantsAudioPortableReexport() async throws {
        let sourceRoot = try temporaryRoot(), cleanRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: sourceRoot); try? FileManager.default.removeItem(at: cleanRoot) }
        let imageURL = sourceRoot.appendingPathComponent("fixture.png")
        let audioURL = sourceRoot.appendingPathComponent("tone.caf")
        try imageFixture(at: imageURL); try audioFixture(at: audioURL)
        let importer = MediaImporter()
        let photo = try await importer.importFile(url: imageURL, to: sourceRoot)
        let audio = try await importer.importFile(url: audioURL, to: sourceRoot)
        XCTAssertEqual(photo.width, 160); XCTAssertTrue(audio.hasAudio)
        let waveform = try await importer.waveform(asset: audio, rootURL: sourceRoot, sampleCount: 24)
        XCTAssertGreaterThan(waveform.max() ?? 0, 0.25)
        let imageClip = Clip(assetID: photo.id, kind: .image, duration: .init(seconds: 0.5), sourceDuration: .init(seconds: 0.5))
        var doc = ProjectDocument(assets: [photo, audio], scenes: [.init(duration: .init(seconds: 0.5), clips: [imageClip])], globalClips: [.init(assetID: audio.id, kind: .audio, duration: .init(seconds: 0.5), sourceDuration: .init(seconds: 0.5), fadeOut: .init(seconds: 0.1))])
        var square = imageClip.presentation; square.x = 0.25
        doc.variants[1].overrides[imageClip.id.uuidString] = square
        let exporter = MovieExporter()
        let settings = MovieExportSettings(longEdge: 160, frameRate: 24, bitrate: 500_000)
        var durations: [Double] = []
        for variant in doc.variants {
            let output = sourceRoot.appendingPathComponent("\(variant.name).mp4")
            let result = try await exporter.export(document: doc, variantID: variant.id, rootURL: sourceRoot, settings: settings, outputURL: output, progress: { _ in })
            XCTAssertTrue(result.hasAudio); XCTAssertEqual(result.frameRate, 24, accuracy: 0.1)
            XCTAssertEqual(result.width, Int(settings.dimensions(for: variant).width))
            XCTAssertEqual(result.height, Int(settings.dimensions(for: variant).height))
            durations.append(result.duration)
            let attachment = XCTAttachment(contentsOfFile: output); attachment.lifetime = .keepAlways; add(attachment)
            let peaks = try await importer.waveform(url: output, bins: 12)
            XCTAssertGreaterThan(peaks.max() ?? 0, 0.1)
            let rendered = try await FrameRenderer().render(plan: .compile(document: doc, variantID: variant.id), time: .init(seconds: 0.125), rootURL: sourceRoot, size: settings.dimensions(for: variant))
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output)); generator.appliesPreferredTrackTransform = true
            let decoded = try await generator.image(at: CMTime(seconds: 0.125, preferredTimescale: 24)).image
            let expected = pixel(rendered, x: 10, y: 10), actual = pixel(decoded, x: 10, y: 10)
            for channel in 0..<3 { XCTAssertLessThan(abs(Int(expected[channel]) - Int(actual[channel])), 30, "Lossy H.264 tolerance per channel") }
        }
        XCTAssertLessThan((durations.max() ?? 0) - (durations.min() ?? 0), 1.0 / 24)
        let package = cleanRoot.appendingPathComponent("story.cutlabproject")
        try PortableProject.export(document: doc, rootURL: sourceRoot, to: package)
        let store = ProjectStore(rootURL: cleanRoot)
        let imported = try PortableProject.importPackage(from: package, into: store)
        try FileManager.default.removeItem(at: sourceRoot)
        let reopened = try store.load(id: imported.id)
        XCTAssertEqual(reopened.variants.count, 3)
        for variant in reopened.variants {
            let result = try await exporter.export(document: reopened, variantID: variant.id, rootURL: cleanRoot, settings: settings, outputURL: cleanRoot.appendingPathComponent("portable-\(variant.name).mp4"), progress: { _ in })
            XCTAssertTrue(result.hasAudio)
            let attachment = XCTAttachment(contentsOfFile: result.url); attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testCancellationMissingCorruptAndRestart() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let corrupt = root.appendingPathComponent("corrupt.mp4"); try Data("not a movie".utf8).write(to: corrupt)
        do { _ = try await MediaImporter().importFile(url: corrupt, to: root); XCTFail("Corrupt media accepted") } catch { }
        let asset = MediaAsset(relativePath: "Media/missing.mov", kind: .video, name: "Missing", duration: .init(seconds: 1))
        let missing = ProjectDocument(assets: [asset], scenes: [.init(duration: .init(seconds: 1), clips: [.init(assetID: asset.id, kind: .video, duration: .init(seconds: 1))])])
        do { _ = try await FrameRenderer().render(plan: .compile(document: missing, variantID: nil), time: .zero, rootURL: root, size: CGSize(width: 128, height: 128)); XCTFail("Missing media accepted") } catch { }
        let doc = ProjectDocument(scenes: [.init(duration: .init(seconds: 0.5), clips: [shape("#123456")])])
        let exporter = MovieExporter(), output = root.appendingPathComponent("cancel.mp4")
        let task = Task { try await exporter.export(document: doc, variantID: doc.variants[0].id, rootURL: root, settings: .init(longEdge: 128, frameRate: 24, bitrate: 200_000), outputURL: output, progress: { _ in }) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled export finished") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let result = try await exporter.export(document: doc, variantID: doc.variants[0].id, rootURL: root, settings: .init(longEdge: 128, frameRate: 24, bitrate: 200_000), outputURL: output, progress: { _ in })
        XCTAssertFalse(result.hasAudio); XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        var replacement = doc
        replacement.scenes[0].clips[0].presentation.color = "#FF0000"
        _ = try await exporter.export(document: replacement, variantID: replacement.variants[0].id, rootURL: root, settings: .init(longEdge: 128, frameRate: 24, bitrate: 200_000), outputURL: output, progress: { _ in })
        let replacementGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        let replacedFrame = try await replacementGenerator.image(at: .zero).image
        XCTAssertGreaterThan(pixel(replacedFrame, x: 20, y: 20)[0], 200, "Exporting again atomically replaces the previous verified movie")
    }
    func testBlendsChromaAndAnimatedMaskPixels() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let renderer = FrameRenderer()
        let back = shape("#804020", duration: 1)
        for blendMode in BlendMode.allCases {
            var front = shape("#4080C0", duration: 1); front.layer = 1; front.presentation.blend = blendMode
            let doc = ProjectDocument(scenes: [.init(duration: .init(seconds: 1), clips: [back, front])])
            let image = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.2), rootURL: root, size: CGSize(width: 128, height: 128))
            let rgb = pixel(image, x: 64, y: 64)
            XCTAssertEqual(rgb[3], 255)
            if blendMode == .multiply { XCTAssertLessThan(rgb[0], 90); XCTAssertLessThan(rgb[1], 90) }
            if blendMode == .screen { XCTAssertGreaterThan(rgb[0], 128); XCTAssertGreaterThan(rgb[2], 180) }
        }
        var keyed = shape("#00FF00", duration: 1); keyed.layer = 1
        keyed.presentation.chromaKeyColor = "#00FF00"
        let doc = ProjectDocument(scenes: [.init(duration: .init(seconds: 1), clips: [back, keyed])])
        let result = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.2), rootURL: root, size: CGSize(width: 128, height: 128))
        let rgb = pixel(result, x: 64, y: 64)
        XCTAssertEqual(Int(rgb[0]), 128, accuracy: 5); XCTAssertEqual(Int(rgb[1]), 64, accuracy: 5)
        var rotated = shape("#FFFFFF", duration: 1); rotated.layer = 1
        rotated.presentation.mask = .rectangle; rotated.presentation.maskWidth = 0.2; rotated.presentation.maskHeight = 0.8
        rotated.presentation.maskRotation = 90
        let rotatedDoc = ProjectDocument(scenes: [.init(duration: .init(seconds: 1), clips: [shape("#000000", duration: 1), rotated])])
        let mask = try await renderer.render(plan: .compile(document: rotatedDoc, variantID: nil), time: .zero, rootURL: root, size: CGSize(width: 128, height: 128))
        XCTAssertGreaterThan(pixel(mask, x: 24, y: 64)[0], 220)
        XCTAssertLessThan(pixel(mask, x: 64, y: 24)[0], 20)
    }

    func testVideoSourceReverseCurveAndRenderingTiming() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var moving = shape("#FA3920", duration: 1)
        moving.presentation.scale = 0.2
        moving.keyframes = [.init(time: .zero, property: .x, value: 0.2), .init(time: .init(seconds: 1), property: .x, value: 0.8)]
        let sourceDoc = ProjectDocument(scenes: [.init(duration: .init(seconds: 1), clips: [moving])])
        let exporter = MovieExporter()
        let sourceURL = root.appendingPathComponent("moving.mp4")
        _ = try await exporter.export(document: sourceDoc, variantID: sourceDoc.variants[1].id, rootURL: root, settings: .init(longEdge: 160, frameRate: 30, bitrate: 600_000), outputURL: sourceURL, progress: { _ in })
        let imported = try await MediaImporter().importFile(url: sourceURL, to: root)
        XCTAssertEqual(imported.kind, .video); XCTAssertFalse(imported.hasAudio)
        var video = Clip(assetID: imported.id, kind: .video, duration: .init(seconds: 1), sourceDuration: .init(seconds: 1))
        let forwardFilmstrip = try await MediaImporter().timelineThumbnails(asset: imported, clip: video, rootURL: root, sampleCount: 4)
        XCTAssertEqual(forwardFilmstrip.count, 4)
        XCTAssertNotEqual(forwardFilmstrip.first?.dataProvider?.data as Data?, forwardFilmstrip.last?.dataProvider?.data as Data?, "Timeline thumbnails must advance with video time")
        var reversedFilmstripClip = video; reversedFilmstripClip.reversed = true
        let reverseFilmstrip = try await MediaImporter().timelineThumbnails(asset: imported, clip: reversedFilmstripClip, rootURL: root, sampleCount: 4)
        XCTAssertEqual(reverseFilmstrip.count, 4)
        XCTAssertEqual(forwardFilmstrip.first?.dataProvider?.data as Data?, reverseFilmstrip.last?.dataProvider?.data as Data?, "Reverse clips must display their source frames in reverse order")
        let renderer = FrameRenderer()
        func document(_ clip: Clip) -> ProjectDocument { ProjectDocument(assets: [imported], scenes: [.init(duration: clip.duration, clips: [clip])]) }
        let forward = try await renderer.render(plan: .compile(document: document(video), variantID: nil), time: .init(seconds: 0.2), rootURL: root, size: CGSize(width: 160, height: 160))
        video.reversed = true
        let reverse = try await renderer.render(plan: .compile(document: document(video), variantID: nil), time: .init(seconds: 0.8), rootURL: root, size: CGSize(width: 160, height: 160))
        XCTAssertEqual(forward.dataProvider?.data as Data?, reverse.dataProvider?.data as Data?)
        video.reversed = false
        video.speedPoints = [.init(sourceTime: .zero, speed: 0.5), .init(sourceTime: .init(seconds: 1), speed: 2)]
        video.duration = TimeMapping.outputDuration(clip: video)
        let local = TimeMapping.localTime(forSource: .init(seconds: 0.2), clip: video)
        let curved = try await renderer.render(plan: .compile(document: document(video), variantID: nil), time: local, rootURL: root, size: CGSize(width: 160, height: 160))
        XCTAssertEqual(forward.dataProvider?.data as Data?, curved.dataProvider?.data as Data?)
        let clock = ContinuousClock(), start = ContinuousClock.now
        for frame in 0..<15 { _ = try await renderer.render(plan: .compile(document: sourceDoc, variantID: nil), time: .init(seconds: Double(frame) / 30), rootURL: root, size: CGSize(width: 360, height: 640)) }
        let elapsed = start.duration(to: clock.now)
        let note = XCTAttachment(string: "Simulator rendering: 15 generated frames, 360×640, elapsed \(elapsed). This is not a physical-device benchmark.")
        note.lifetime = .keepAlways; add(note)
    }

    func testAudioVideoImpulsesAfterCutsAndRetime() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("impulses.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        do {
            let file = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
            for base in stride(from: 0, to: 48_000, by: 2048) {
                let count = min(2048, 48_000 - base); buffer.frameLength = AVAudioFrameCount(count)
                for i in 0..<count {
                    let t = Double(base + i) / 48_000
                    let pulse = [0.1, 0.6, 0.9].contains { t >= $0 && t < $0 + 0.01 }
                    buffer.floatChannelData![0][i] = pulse ? Float(sin(t * 2 * .pi * 1800) * 0.8) : 0
                }
                try file.write(from: buffer)
            }
        }
        let asset = try await MediaImporter().importFile(url: sourceURL, to: root)
        let first = Clip(assetID: asset.id, kind: .audio, duration: .init(seconds: 0.4), sourceDuration: .init(seconds: 0.4))
        let second = Clip(assetID: asset.id, kind: .audio, duration: .init(seconds: 0.2), sourceStart: .init(seconds: 0.4), sourceDuration: .init(seconds: 0.4), speed: 2)
        let third = Clip(assetID: asset.id, kind: .audio, duration: .init(seconds: 0.4), sourceStart: .init(seconds: 0.8), sourceDuration: .init(seconds: 0.2), speed: 0.5)
        var flashes: [Clip] = []
        for time in [0.1, 0.5, 0.8] { var flash = shape("#FFFFFF", duration: 1.0 / 30); flash.start = .init(seconds: time); flash.layer = 5; flashes.append(flash) }
        let doc = ProjectDocument(assets: [asset], scenes: [.init(duration: first.duration, clips: [first]), .init(duration: second.duration, clips: [second]), .init(duration: third.duration, clips: [third])], globalClips: flashes)
        let output = root.appendingPathComponent("sync.mp4")
        _ = try await MovieExporter().export(document: doc, variantID: doc.variants[1].id, rootURL: root, settings: .init(longEdge: 128, frameRate: 30, bitrate: 250_000), outputURL: output, progress: { _ in })
        let movie = AVURLAsset(url: output)
        let audioTracks = try await movie.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(audioTracks.first)
        let reader = try AVAssetReader(asset: movie)
        let audio = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32])
        reader.add(audio); XCTAssertTrue(reader.startReading())
        var peaks = [(time: Double, amplitude: Float)](repeating: (0,0), count: 3)
        let expected = [0.1, 0.5, 0.8]
        var decodedPeak: Float = 0
        while let sample = audio.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating: 0, count: length / 4)
            _ = values.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            for (i, value) in values.enumerated() {
                decodedPeak = max(decodedPeak, abs(value))
                let time = start + Double(i) / 48_000
                for index in expected.indices where abs(time - expected[index]) < 0.06 && abs(value) > peaks[index].amplitude { peaks[index] = (time, abs(value)) }
            }
        }
        XCTAssertLessThanOrEqual(decodedPeak, 1, "AAC stereo-to-mono decoded corpus peak must stay below full scale")
        let generator = AVAssetImageGenerator(asset: movie)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        for index in expected.indices {
            XCTAssertGreaterThan(peaks[index].amplitude, 0.08)
            let frame = try await generator.image(at: CMTime(seconds: expected[index], preferredTimescale: 30)).image
            XCTAssertGreaterThan(pixel(frame, x: 64, y: 64)[0], 220)
            XCTAssertLessThan(abs(peaks[index].time - expected[index]), 1.0 / 30, "A/V impulse offset after cut and retime")
        }
        let note = XCTAttachment(string: "30 fps sync corpus: expected \(expected), measured audio peaks \(peaks), entire decoded mono peak \(decodedPeak). Measured on simulator after AAC/H.264 decoding.")
        note.lifetime = .keepAlways; add(note)
        let attachment = XCTAttachment(contentsOfFile: output); attachment.lifetime = .keepAlways; add(attachment)
    }

    func testImportedOrientationUsesTrackTransform() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await SyntheticVideoCorpus.make(in: root, rotated: true)
        let asset = try await MediaImporter().importFile(url: fixture.movieURL, to: root)
        XCTAssertEqual(asset.width, 180); XCTAssertEqual(asset.height, 320)
        let clip = Clip(assetID: asset.id, kind: .video, duration: .init(seconds: 0.2), sourceDuration: .init(seconds: 0.2))
        let doc = ProjectDocument(assets: [asset], scenes: [.init(duration: clip.duration, clips: [clip])])
        let frame = try await FrameRenderer().render(plan: .compile(document: doc, variantID: doc.variants[0].id), time: .zero, rootURL: root, size: CGSize(width: 180, height: 320))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fixture.movieURL)); generator.appliesPreferredTrackTransform = true
        let reference = try await generator.image(at: .zero).image
        XCTAssertEqual(reference.width, frame.width); XCTAssertEqual(reference.height, frame.height)
        for point in [(20,20), (90,160), (160,300)] {
            let actual = pixel(frame, x: point.0, y: point.1), expected = pixel(reference, x: point.0, y: point.1)
            for channel in 0..<3 { XCTAssertLessThan(abs(Int(actual[channel]) - Int(expected[channel])), 8) }
        }
        let result = try await MovieExporter().export(document: doc, variantID: doc.variants[0].id, rootURL: root, settings: .init(longEdge: 320, frameRate: 30, bitrate: 600_000), outputURL: root.appendingPathComponent("oriented.mp4"), progress: { _ in })
        XCTAssertEqual(result.width, 180); XCTAssertEqual(result.height, 320)
    }

    func testChromaPickerLetterboxCoordinatesAndSRGBSampling() throws {
        let imageSize = CGSize(width: 200, height: 100), bounds = CGSize(width: 300, height: 300)
        XCTAssertEqual(ChromaPickerGeometry.fittedRect(imageSize: imageSize, in: bounds), CGRect(x: 0, y: 75, width: 300, height: 150))
        XCTAssertNil(ChromaPickerGeometry.sourcePixel(at: CGPoint(x: 20, y: 10), imageSize: imageSize, in: bounds))
        XCTAssertEqual(ChromaPickerGeometry.sourcePixel(at: CGPoint(x: 150, y: 150), imageSize: imageSize, in: bounds), CGPoint(x: 100, y: 50))
        XCTAssertEqual(ChromaPickerGeometry.sourcePixel(at: CGPoint(x: 299, y: 224), imageSize: imageSize, in: bounds), CGPoint(x: 199, y: 99))
        let data = Data([255,0,0,255, 0,255,0,255, 0,0,255,255, 128,128,128,128])
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        XCTAssertEqual(ChromaPickerGeometry.srgbHex(in: image, at: CGPoint(x: 0, y: 0)), "#FF0000")
        XCTAssertEqual(ChromaPickerGeometry.srgbHex(in: image, at: CGPoint(x: 1, y: 0)), "#00FF00")
        XCTAssertEqual(ChromaPickerGeometry.srgbHex(in: image, at: CGPoint(x: 0, y: 1)), "#0000FF")
        XCTAssertEqual(ChromaPickerGeometry.srgbHex(in: image, at: CGPoint(x: 1, y: 1)), "#FFFFFF")
        XCTAssertNil(ChromaPickerGeometry.srgbHex(in: image, at: CGPoint(x: 2, y: 1)))
    }

    func testAtomicMovieInstallationReplacesAndPreservesPreviousOnFailure() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("movie.mp4")
        let staging = root.appendingPathComponent(".pending.mp4")
        let previous = Data("previous completed bytes".utf8), next = Data("new verified bytes".utf8)
        try previous.write(to: destination); try next.write(to: staging)
        try MovieFileInstallation.install(temporary: staging, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), next)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertThrowsError(try MovieFileInstallation.install(temporary: staging, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), next, "A missing staging file must preserve the completed output")
    }

    func testEffectRangeKeyframesLegacyDecodeAndSplitRenderContinuity() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let legacy = Data("{\"id\":\"\(UUID().uuidString)\",\"kind\":\"brightness\",\"amount\":0.2,\"enabled\":true}".utf8)
        XCTAssertNil(try JSONDecoder().decode(EffectInstance.self, from: legacy).amountKeyframes)
        let effect = EffectInstance(kind: .brightness, amount: 0, start: .init(seconds: 0.25), duration: .init(seconds: 0.5), amountKeyframes: [.init(time: .init(seconds: 0.25), value: 0), .init(time: .init(seconds: 0.75), value: 0.5)])
        XCTAssertNil(effect.evaluatedAmount(at: .init(seconds: 0.249)))
        XCTAssertEqual(effect.evaluatedAmount(at: .init(seconds: 0.5)), 0.25)
        XCTAssertNil(effect.evaluatedAmount(at: .init(seconds: 0.75)))
        var clip = shape("#303030", duration: 1); clip.effects = [effect]
        var document = ProjectDocument(scenes: [.init(duration: .init(seconds: 1), clips: [clip])])
        let renderer = FrameRenderer(), size = CGSize(width: 128, height: 128)
        let before = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .init(seconds: 0.2), rootURL: root, size: size)
        let animated = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .init(seconds: 0.5), rootURL: root, size: size)
        let after = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .init(seconds: 0.75), rootURL: root, size: size)
        XCTAssertEqual(before.dataProvider?.data as Data?, after.dataProvider?.data as Data?)
        XCTAssertGreaterThan(pixel(animated, x: 64, y: 64)[0], pixel(before, x: 64, y: 64)[0])
        try DocumentEditor.splitClip(clip.id, at: .init(seconds: 0.5), in: &document)
        let split = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .init(seconds: 0.5), rootURL: root, size: size)
        XCTAssertEqual(animated.dataProvider?.data as Data?, split.dataProvider?.data as Data?)
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(document)), document)
    }

}
