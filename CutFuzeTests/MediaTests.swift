import XCTest
import AVFoundation
import CoreImage
import ImageIO
import VideoToolbox
import UIKit
@testable import CutFuze

@MainActor final class MediaTests: XCTestCase {
    func testAnimatedMaskChangesRenderedAndExportedSilhouette() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var clip = Clip(kind: .shape, duration: .init(seconds: 2))
        clip.presentation.mask = .rectangle; clip.presentation.color = "#FFFFFF"
        clip.presentation.maskHeight = 0.5
        clip.keyframes = [.init(time: .zero, property: .maskWidth, value: 0.2), .init(time: .init(seconds: 1), property: .maskWidth, value: 0.6, easing: .easeOut)]
        let document = ProjectDocument(globalClips: [clip]); try document.validate()
        let variant = document.variants[1].id
        let plan = RenderPlan.compile(document: document, variantID: variant)
        let renderer = FrameRenderer(softwareRendering: true)
        let early = try await renderer.render(plan: plan, time: .zero, rootURL: root, size: .init(width: 128, height: 128))
        let late = try await renderer.render(plan: plan, time: .init(seconds: 1), rootURL: root, size: .init(width: 128, height: 128))
        XCTAssertLessThan(pixel(early, x: 40, y: 64)[0], 10)
        XCTAssertGreaterThan(pixel(late, x: 40, y: 64)[0], 200)
        let output = root.appendingPathComponent("animated-mask.mp4")
        _ = try await MovieExporter().export(document: document, variantID: variant, rootURL: root, settings: MovieExportSettings(longEdge: 128), outputURL: output, progress: { _ in })
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let decoded = try await generator.image(at: .init(seconds: 1, preferredTimescale: 600))
        XCTAssertEqual(decoded.actualTime.seconds, 1, accuracy: 1 / 24.0)
        XCTAssertGreaterThan(pixel(decoded.image, x: 40, y: 64)[0], 180)
    }

    func testShapeFreeResizeRendersAndExportsWithoutCroppingOrAspectLock() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var clip = Clip(kind: .shape, duration: .init(seconds: 0.2))
        clip.presentation.mask = .rectangle; clip.presentation.scale = 0.35
        clip.presentation.maskHeight = 9.0 / 16; clip.presentation.color = "#FFFFFF"
        clip.presentation = PreviewInteractionGeometry.resizedShapePresentation(from: clip.presentation, translation: .init(width: 30, height: 0), canvasSize: .init(width: 360, height: 640))
        let document = ProjectDocument(globalClips: [clip])
        let plan = RenderPlan.compile(document: document, variantID: document.variants[0].id)
        let image = try await FrameRenderer(softwareRendering: true).render(plan: plan, time: .zero, rootURL: root, size: .init(width: 180, height: 320))
        // Expected silhouette: 93 × 63 px centred on this portrait canvas.
        XCTAssertGreaterThan(pixel(image, x: 47, y: 160)[0], 200)
        XCTAssertLessThan(pixel(image, x: 40, y: 160)[0], 10)
        XCTAssertGreaterThan(pixel(image, x: 90, y: 134)[0], 200)
        XCTAssertLessThan(pixel(image, x: 90, y: 122)[0], 10)
        let output = root.appendingPathComponent("wide-shape.mp4")
        _ = try await MovieExporter().export(document: document, variantID: document.variants[0].id, rootURL: root, settings: MovieExportSettings(longEdge: 320), outputURL: output, progress: { _ in })
        let decoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: .zero).image
        XCTAssertEqual(decoded.width, 180); XCTAssertEqual(decoded.height, 320)
        XCTAssertGreaterThan(pixel(decoded, x: 47, y: 160)[0], 180)
        XCTAssertLessThan(pixel(decoded, x: 90, y: 122)[0], 30)
    }

    func testOverlayShapesRenderDistinctSilhouettesAndExport() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let renderer = FrameRenderer(softwareRendering: true)
        var images = Set<Data>()
        for shape in MaskKind.overlayShapes {
            var clip = Clip(kind: .shape, duration: .init(seconds: 0.2))
            clip.presentation.mask = shape; clip.presentation.color = "#EBA65A"
            clip.presentation.maskWidth = 0.7; clip.presentation.maskHeight = 0.7
            let document = ProjectDocument(globalClips: [clip])
            try document.validate()
            XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(document)), document)
            let image = try await renderer.render(plan: .compile(document: document, variantID: document.variants[1].id), time: .zero, rootURL: root, size: CGSize(width: 128, height: 128))
            images.insert(try XCTUnwrap(image.dataProvider?.data as Data?))
            XCTAssertGreaterThan(pixel(image, x: 64, y: 64)[0], 100)
            XCTAssertLessThan(pixel(image, x: 5, y: 5)[0], 10)
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = "overlay-\(shape.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
            if [.cloud, .star, .heart].contains(shape) {
                let output = root.appendingPathComponent("\(shape.rawValue).mp4")
                _ = try await MovieExporter().export(document: document, variantID: document.variants[1].id, rootURL: root, settings: MovieExportSettings(longEdge: 128), outputURL: output, progress: { _ in })
                let decoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: .zero).image
                XCTAssertGreaterThan(pixel(decoded, x: 64, y: 64)[0], 100)
            }
        }
        XCTAssertEqual(images.count, MaskKind.overlayShapes.count)
    }
    func testShortAudioAtDoubleSpeedPreparesPlaysAndExportsWithAdaptedDuration() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("short.caf"); try audioFixture(at: source, seconds: 0.12)
        let asset = try await MediaImporter().importFile(url: source, to: root)
        let clip = Clip(assetID: asset.id, kind: .audio, duration: asset.duration, sourceDuration: asset.duration)
        var doc = ProjectDocument(assets: [asset], globalClips: [clip])
        try DocumentEditor.setConstantSpeed(2, clipID: clip.id, in: &doc); try doc.validate()
        let plan = RenderPlan.compile(document: doc, variantID: nil)
        XCTAssertEqual(plan.duration.seconds, 0.06, accuracy: 0.0001)
        let prepared = try await AudioComposer.prepare(plan: plan, rootURL: root)
        XCTAssertTrue(prepared.hasAudio)
        let tracks = try await prepared.composition.loadTracks(withMediaType: .audio)
        let range = try await XCTUnwrap(tracks.first).load(.timeRange)
        XCTAssertEqual(range.duration.seconds, 0.06, accuracy: 0.0001)
        let audition = CaptionSegmentPlayer(plan: plan, rootURL: root)
        audition.toggle(id: clip.id, start: .zero, end: plan.duration)
        try await waitForAudition { audition.activeID == nil }
        XCTAssertNil(audition.error)
        let output = root.appendingPathComponent("short-double-speed.mp4")
        let result = try await MovieExporter().export(document: doc, variantID: doc.variants[1].id, rootURL: root, settings: .init(longEdge: 128, frameRate: 24, bitrate: 200_000), outputURL: output, progress: { _ in })
        XCTAssertTrue(result.hasAudio)
        let attachment = XCTAttachment(contentsOfFile: output); attachment.name = "short-double-speed"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testVolumeCurveChangesDecodedAudioAndAllowsZeroBaseVolume() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("tone.caf"); try audioFixture(at: source)
        let asset = try await MediaImporter().importFile(url: source, to: root)
        let clip = Clip(assetID: asset.id, kind: .audio, duration: asset.duration, sourceDuration: asset.duration,
            keyframes: [.init(time: .zero, property: .volume, value: 0.08), .init(time: .init(seconds: 0.4), property: .volume, value: 0.08), .init(time: .init(seconds: 0.6), property: .volume, value: 0.6, easing: .easeInOut), .init(time: asset.duration, property: .volume, value: 0.6)], volume: 0)
        let doc = ProjectDocument(assets: [asset], globalClips: [clip]); try doc.validate()
        let prepared = try await AudioComposer.prepare(plan: .compile(document: doc, variantID: nil), rootURL: root)
        XCTAssertTrue(prepared.hasAudio, "Positive volume keys must remain audible when the base volume is zero")
        let output = root.appendingPathComponent("volume-curve.mp4")
        _ = try await MovieExporter().export(document: doc, variantID: doc.variants[1].id, rootURL: root, settings: .init(longEdge: 128, frameRate: 24, bitrate: 200_000), outputURL: output, progress: { _ in })
        let peaks = try await MediaImporter().waveform(url: output, bins: 10)
        XCTAssertGreaterThan(peaks.suffix(2).min() ?? 0, (peaks.prefix(2).max() ?? 1) * 4)
        let attachment = XCTAttachment(contentsOfFile: output); attachment.name = "volume-curve"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testCreativeEffectsRenderDeterministicallyAndSurviveSplitOnCPU() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("pattern.png"); try imageFixture(at: url)
        let asset = try await MediaImporter().importFile(url: url, to: root)
        let size = CGSize(width: 160, height: 160), renderer = FrameRenderer(softwareRendering: true)
        let original = Clip(assetID: asset.id, kind: .image, duration: .init(seconds: 1), sourceDuration: .init(seconds: 1))
        let plain = ProjectDocument(assets: [asset], scenes: [.init(duration: .init(seconds: 1), clips: [original])])
        let baseline = try await renderer.render(plan: .compile(document: plain, variantID: nil), time: .init(seconds: 0.15), rootURL: root, size: size)
        for kind in [EffectKind.impactZoom, .shortGlitch, .neon, .dream, .lightSweep, .liquidDistortion, .directionalBlur, .popHalftone, .duotone] {
            let sampleTime = MediaTime(seconds: kind == .lightSweep ? 0.5 : 0.15)
            var doc = plain
            doc.scenes[0].clips[0].effects = [.readyToUse(kind, duration: .init(seconds: 1))]
            let plan = RenderPlan.compile(document: doc, variantID: nil)
            let image = try await renderer.render(plan: plan, time: sampleTime, rootURL: root, size: size)
            XCTAssertNotEqual(image.dataProvider?.data as Data?, baseline.dataProvider?.data as Data?, "\(kind) must visibly change a patterned image")
            let repeated = try await renderer.render(plan: plan, time: sampleTime, rootURL: root, size: size)
            XCTAssertEqual(image.dataProvider?.data as Data?, repeated.dataProvider?.data as Data?)
            try DocumentEditor.splitClip(original.id, at: .init(seconds: 0.12), in: &doc)
            let split = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: sampleTime, rootURL: root, size: size)
            XCTAssertEqual(image.dataProvider?.data as Data?, split.dataProvider?.data as Data?, "\(kind) must keep the same phase after splitting")
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = "creative-render-\(kind.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
            let movie = root.appendingPathComponent("\(kind.rawValue).mp4")
            let settings = MovieExportSettings(longEdge: 160, frameRate: 24, bitrate: 1_000_000)
            _ = try await MovieExporter().export(document: doc, variantID: doc.variants[1].id, rootURL: root, settings: settings, outputURL: movie, progress: { _ in })
            let exportTime = kind == .lightSweep ? 0.5 : 0.125
            let expected = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: exportTime), rootURL: root, size: size)
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie)); generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let frame = try await generator.image(at: CMTime(seconds: exportTime, preferredTimescale: 24))
            XCTAssertEqual(frame.actualTime.seconds, exportTime, accuracy: 0.0001, "Compare the exact animated frame, not a nearby keyframe")
            let decoded = frame.image
            let decodedAttachment = XCTAttachment(image: UIImage(cgImage: decoded)); decodedAttachment.name = "creative-decoded-\(kind.rawValue)"; decodedAttachment.lifetime = .keepAlways; add(decodedAttachment)
            var totalError = 0
            for y in stride(from: 10, to: 150, by: 5) { for x in stride(from: 10, to: 150, by: 5) {
                let a = pixel(expected, x: x, y: y), b = pixel(decoded, x: x, y: y)
                for channel in 0..<3 { totalError += abs(Int(a[channel]) - Int(b[channel])) }
            } }
            XCTAssertLessThan(Double(totalError) / (28 * 28 * 3), 15, "\(kind) preview and export agree after a cut")
            let exported = XCTAttachment(contentsOfFile: movie); exported.name = "creative-export-\(kind.rawValue)"; exported.lifetime = .keepAlways; add(exported)
            if kind == .impactZoom || kind == .shortGlitch {
                let outside = try await renderer.render(plan: plan, time: .init(seconds: 0.6), rootURL: root, size: size)
                XCTAssertEqual(outside.dataProvider?.data as Data?, baseline.dataProvider?.data as Data?)
            }
        }
    }

    func testTemporalCreativeEffectsSampleRealVideoHoldOnlyTheirLayerAndExportAfterSplit() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await SyntheticVideoCorpus.make(in: root)
        let asset = try await MediaImporter().importFile(url: fixture.movieURL, to: root)
        let renderer = FrameRenderer(softwareRendering: true), size = CGSize(width: 160, height: 90)
        let clip = Clip(assetID: asset.id, kind: .video, duration: .init(seconds: 1), sourceStart: .init(seconds: 0.25), sourceDuration: .init(seconds: 1))
        let plain = ProjectDocument(assets: [asset], globalClips: [clip])
        for kind in [EffectKind.lensPulse, .ghostTrail, .stopMotion] {
            var document = plain
            document.globalClips[0].effects = [.readyToUse(kind, duration: clip.duration)]
            let time = MediaTime(seconds: kind == .lensPulse ? 0.25 : kind == .stopMotion ? 0.68 : 0.64)
            let image = try await renderer.render(plan: .compile(document: document, variantID: nil), time: time, rootURL: root, size: size)
            let original = try await renderer.render(plan: .compile(document: plain, variantID: nil), time: time, rootURL: root, size: size)
            XCTAssertNotEqual(image.dataProvider?.data as Data?, original.dataProvider?.data as Data?, "\(kind) must visibly affect real moving frames")
            let repeated = try await renderer.render(plan: .compile(document: document, variantID: nil), time: time, rootURL: root, size: size)
            XCTAssertEqual(repeated.dataProvider?.data as Data?, image.dataProvider?.data as Data?)
            let changedID = clip.id
            if kind == .ghostTrail {
                document.globalClips[0].effects[0].echoSpacing = 0.25
                let wider = try await renderer.render(plan: .compile(document: document, variantID: nil), time: time, rootURL: root, size: size)
                XCTAssertNotEqual(image.dataProvider?.data as Data?, wider.dataProvider?.data as Data?)
                document = plain; document.globalClips[0].effects = [.readyToUse(kind, duration: clip.duration)]
            }
            if kind == .stopMotion {
                let heldA = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .init(seconds: 0.51), rootURL: root, size: size)
                let heldB = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .init(seconds: 0.59), rootURL: root, size: size)
                XCTAssertEqual(heldA.dataProvider?.data as Data?, heldB.dataProvider?.data as Data?, "Both times sample the same 8 fps layer frame")
                XCTAssertNotEqual(heldA.dataProvider?.data as Data?, image.dataProvider?.data as Data?)
                var overlay = shape("#FF00FF", duration: 1); overlay.layer = 5; overlay.presentation.scale = 0.12
                overlay.keyframes = [.init(time: .zero, property: .x, value: 0.1), .init(time: .init(seconds: 1), property: .x, value: 0.9)]
                var montage = document; montage.globalClips.append(overlay)
                let movingA = try await renderer.render(plan: .compile(document: montage, variantID: nil), time: .init(seconds: 0.51), rootURL: root, size: size)
                let movingB = try await renderer.render(plan: .compile(document: montage, variantID: nil), time: .init(seconds: 0.59), rootURL: root, size: size)
                XCTAssertNotEqual(movingA.dataProvider?.data as Data?, movingB.dataProvider?.data as Data?, "Another layer stays smooth")
            }
            try DocumentEditor.splitClip(changedID, at: .init(seconds: kind == .lensPulse ? 0.2 : kind == .stopMotion ? 0.66 : 0.6), in: &document)
            let split = try await renderer.render(plan: .compile(document: document, variantID: nil), time: time, rootURL: root, size: size)
            XCTAssertEqual(image.dataProvider?.data as Data?, split.dataProvider?.data as Data?, "\(kind) must preserve pre-cut sampling and phase")
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = "temporal-render-\(kind.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
            let variant = document.variants.first { $0.widthRatio > $0.heightRatio }!
            let movie = root.appendingPathComponent("\(kind.rawValue).mp4")
            _ = try await MovieExporter().export(document: document, variantID: variant.id, rootURL: root, settings: .init(longEdge: 160, frameRate: 30, bitrate: 1_000_000), outputURL: movie, progress: { _ in })
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie)); generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let exportTime = kind == .lensPulse ? 0.2666666667 : kind == .stopMotion ? 0.7 : 0.6333333333
            let encoded = try await generator.image(at: CMTime(seconds: exportTime, preferredTimescale: 30))
            let expected = try await renderer.render(plan: .compile(document: document, variantID: variant.id), time: .init(seconds: encoded.actualTime.seconds), rootURL: root, size: size)
            let decodedAttachment = XCTAttachment(image: UIImage(cgImage: encoded.image)); decodedAttachment.name = "temporal-decoded-\(kind.rawValue)"; decodedAttachment.lifetime = .keepAlways; add(decodedAttachment)
            var difference = 0.0, samples = 0.0
            for y in stride(from: 5, to: 85, by: 5) { for x in stride(from: 5, to: 155, by: 5) {
                let a = pixel(expected, x: x, y: y), b = pixel(encoded.image, x: x, y: y)
                for channel in 0..<3 { difference += Double(abs(Int(a[channel]) - Int(b[channel]))); samples += 1 }
            } }
            XCTAssertLessThan(difference / samples, 15, "\(kind) preview and export must agree")
            let tracks = try await AVURLAsset(url: movie).loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let frameRate = try await track.load(.nominalFrameRate)
            XCTAssertEqual(frameRate, 30, accuracy: 0.01, "Stop-motion must not lower export FPS")
            let export = XCTAttachment(contentsOfFile: movie); export.name = "temporal-export-\(kind.rawValue)"; export.lifetime = .keepAlways; add(export)
            for index in document.globalClips.indices { document.globalClips[index].effects[0].amountKeyframes = nil; document.globalClips[index].effects[0].amount = 0 }
            let neutral = try await renderer.render(plan: .compile(document: document, variantID: nil), time: time, rootURL: root, size: size)
            XCTAssertEqual(neutral.dataProvider?.data as Data?, original.dataProvider?.data as Data?)
        }
    }

    func testThirdCreativeSeriesParametersChangePixelsAndRespectCurvesAndTransparency() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("pattern.png"); try imageFixture(at: url)
        let asset = try await MediaImporter().importFile(url: url, to: root)
        let renderer = FrameRenderer(softwareRendering: true), size = CGSize(width: 160, height: 160)
        let clip = Clip(assetID: asset.id, kind: .image, duration: .init(seconds: 1), sourceDuration: .init(seconds: 1))
        let plain = ProjectDocument(assets: [asset], globalClips: [clip])
        let baseline = try await renderer.render(plan: .compile(document: plain, variantID: nil), time: .zero, rootURL: root, size: size)
        for kind in [EffectKind.directionalBlur, .popHalftone, .duotone] {
            var document = plain
            var effect = EffectInstance.readyToUse(kind, duration: clip.duration)
            effect.amount = 1
            if kind == .directionalBlur { effect.blurAngle = 0 }
            document.globalClips[0].effects = [effect]
            let first = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .zero, rootURL: root, size: size)
            XCTAssertNotEqual(first.dataProvider?.data as Data?, baseline.dataProvider?.data as Data?)
            switch kind {
            case .directionalBlur: effect.blurAngle = 90
            case .popHalftone: effect.dotScale = 0.95
            case .duotone: effect.colorHex = "#163A32"; effect.secondaryColorHex = "#F8DA78"
            default: XCTFail("Unexpected test effect")
            }
            document.globalClips[0].effects = [effect]
            let changed = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .zero, rootURL: root, size: size)
            XCTAssertNotEqual(first.dataProvider?.data as Data?, changed.dataProvider?.data as Data?, "\(kind) parameter must change the image")
            effect.amountKeyframes = [.init(time: .zero, value: 0), .init(time: .init(seconds: 1), value: 1, easing: .easeIn)]
            document.globalClips[0].effects = [effect]
            let neutral = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .zero, rootURL: root, size: size)
            XCTAssertEqual(neutral.dataProvider?.data as Data?, baseline.dataProvider?.data as Data?, "Zero on a curve is a true bypass")
            effect.enabled = false; document.globalClips[0].effects = [effect]
            let disabled = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .init(seconds: 0.5), rootURL: root, size: size)
            XCTAssertEqual(disabled.dataProvider?.data as Data?, baseline.dataProvider?.data as Data?)
            effect.enabled = true; effect.start = .init(seconds: 0.25); effect.duration = .init(seconds: 0.25)
            document.globalClips[0].effects = [effect]
            let outside = try await renderer.render(plan: .compile(document: document, variantID: nil), time: .init(seconds: 0.75), rootURL: root, size: size)
            XCTAssertEqual(outside.dataProvider?.data as Data?, baseline.dataProvider?.data as Data?)

            let back = shape("#F0C020", duration: 1)
            var text = Clip(kind: .text, duration: .init(seconds: 1), text: "Pop", presentation: Presentation(textSize: 0.22), layer: 1)
            text.effects = [.readyToUse(kind, duration: text.duration)]
            let textDocument = ProjectDocument(globalClips: [back, text])
            let textImage = try await renderer.render(plan: .compile(document: textDocument, variantID: nil), time: .zero, rootURL: root, size: size)
            let background = try await renderer.render(plan: .compile(document: ProjectDocument(globalClips: [back]), variantID: nil), time: .zero, rootURL: root, size: size)
            XCTAssertEqual(pixel(textImage, x: 5, y: 5), pixel(background, x: 5, y: 5), "\(kind) must not fill transparent text pixels")
            for (label, image) in [("default", first), ("parameter", changed), ("text", textImage)] {
                let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = "third-series-\(kind.rawValue)-\(label)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    func testLiquidWavesMoveOverTimeAndRespectSpeedAndNeutralIntensity() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("pattern.png"); try imageFixture(at: url)
        let asset = try await MediaImporter().importFile(url: url, to: root)
        let clip = Clip(assetID: asset.id, kind: .image, duration: .init(seconds: 1), sourceDuration: .init(seconds: 1), effects: [.readyToUse(.liquidDistortion, duration: .init(seconds: 1))])
        var doc = ProjectDocument(assets: [asset], globalClips: [clip])
        let renderer = FrameRenderer(softwareRendering: true), size = CGSize(width: 160, height: 160)
        let first = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.2), rootURL: root, size: size)
        let boundaries = stride(from: 20, to: 145, by: 15).compactMap { y in
            (20..<140).first { x in let rgba = pixel(first, x: x, y: y); return rgba[2] > rgba[0] }
        }
        XCTAssertGreaterThan((boundaries.max() ?? 0) - (boundaries.min() ?? 0), 2, "A straight edge must visibly ripple, not merely shift as one flat plane")
        let later = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.7), rootURL: root, size: size)
        XCTAssertNotEqual(first.dataProvider?.data as Data?, later.dataProvider?.data as Data?, "Liquid must move, not be a static distortion")
        doc.globalClips[0].effects[0].liquidSpeed = 2
        let faster = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.7), rootURL: root, size: size)
        XCTAssertNotEqual(faster.dataProvider?.data as Data?, later.dataProvider?.data as Data?)
        doc.globalClips[0].effects[0].amount = 0
        let zero = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.7), rootURL: root, size: size)
        doc.globalClips[0].effects = []
        let plain = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.7), rootURL: root, size: size)
        XCTAssertEqual(zero.dataProvider?.data as Data?, plain.dataProvider?.data as Data?)
        for (name, image) in [("liquid-first", first), ("liquid-later", later)] {
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testLightSweepMovesAcrossMaskedLayerWithoutLightingOutsideIt() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var effect = EffectInstance.readyToUse(.lightSweep, duration: .init(seconds: 1))
        effect.start = .init(seconds: 0.2); effect.duration = .init(seconds: 0.6); effect.amountKeyframes = nil; effect.amount = 1
        var clip = shape("#303030", duration: 1); clip.effects = [effect]
        clip.presentation.mask = .rectangle; clip.presentation.maskWidth = 0.6; clip.presentation.maskHeight = 0.6
        let doc = ProjectDocument(globalClips: [clip]), renderer = FrameRenderer(softwareRendering: true), size = CGSize(width: 160, height: 160)
        let early = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.38), rootURL: root, size: size)
        let late = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.62), rootURL: root, size: size)
        XCTAssertGreaterThan(Int(pixel(early, x: 40, y: 80)[0]), Int(pixel(late, x: 40, y: 80)[0]) + 20)
        XCTAssertGreaterThan(Int(pixel(late, x: 120, y: 80)[0]), Int(pixel(early, x: 120, y: 80)[0]) + 20)
        XCTAssertEqual(pixel(early, x: 10, y: 80)[0], 0, "The reflection must respect the mask alpha")
        let before = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.1), rootURL: root, size: size)
        let after = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.9), rootURL: root, size: size)
        XCTAssertEqual(before.dataProvider?.data as Data?, after.dataProvider?.data as Data?)
        for (name, image) in [("sweep-early", early), ("sweep-late", late)] {
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testNeonFollowsTextAndMaskAlphaWithCustomColorAndMovieExport() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var effect = EffectInstance.readyToUse(.neon, duration: .init(seconds: 0.5)); effect.colorHex = "#FF48D7"
        effect.glowRadius = 0.9
        var clip = Clip(kind: .text, duration: .init(seconds: 0.5), text: "CutFuze", presentation: Presentation(textSize: 0.14), effects: [effect])
        let renderer = FrameRenderer(softwareRendering: true), size = CGSize(width: 256, height: 256)
        var doc = ProjectDocument(globalClips: [clip])
        let pink = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.125), rootURL: root, size: size)
        doc.globalClips[0].effects[0].colorHex = "#49E6FF"
        let cyan = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.125), rootURL: root, size: size)
        XCTAssertNotEqual(pink.dataProvider?.data as Data?, cyan.dataProvider?.data as Data?)
        let output = root.appendingPathComponent("neon.mp4")
        let settings = MovieExportSettings(longEdge: 256, frameRate: 24, bitrate: 2_000_000)
        _ = try await MovieExporter().export(document: doc, variantID: doc.variants[1].id, rootURL: root, settings: settings, outputURL: output, progress: { _ in })
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output)); generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let decoded = try await generator.image(at: CMTime(seconds: 0.125, preferredTimescale: 24)).image
        var totalError = 0
        for y in stride(from: 50, to: 200, by: 5) { for x in stride(from: 10, to: 245, by: 5) {
            let expected = pixel(cyan, x: x, y: y), actual = pixel(decoded, x: x, y: y)
            for channel in 0..<3 { totalError += abs(Int(expected[channel]) - Int(actual[channel])) }
        } }
        XCTAssertLessThan(Double(totalError) / (30 * 47 * 3), 15, "Preview and lossy export should agree")
        let video = XCTAttachment(contentsOfFile: output); video.name = "neon-export"; video.lifetime = .keepAlways; add(video)
        let screenshot = XCTAttachment(image: UIImage(cgImage: cyan)); screenshot.name = "neon-text"; screenshot.lifetime = .keepAlways; add(screenshot)
        clip.kind = .shape; clip.presentation.mask = .ellipse; clip.presentation.maskWidth = 0.6; clip.presentation.maskHeight = 0.6
        doc.globalClips = [clip]
        let masked = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.1), rootURL: root, size: size)
        doc.globalClips[0].effects = []
        let noHalo = try await renderer.render(plan: .compile(document: doc, variantID: nil), time: .init(seconds: 0.1), rootURL: root, size: size)
        XCTAssertNotEqual(masked.dataProvider?.data as Data?, noHalo.dataProvider?.data as Data?, "The halo must survive masking")
        let contour = XCTAttachment(image: UIImage(cgImage: masked)); contour.name = "neon-masked-shape"; contour.lifetime = .keepAlways; add(contour)
    }

    func testNeonSpreadAddsLightOutsideContourWithoutChangingIntensity() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var effect = EffectInstance.readyToUse(.neon, duration: .init(seconds: 1)); effect.amount = 1; effect.glowRadius = 0
        var style = Presentation(); style.mask = .ellipse; style.maskWidth = 0.6; style.maskHeight = 0.6
        let clip = Clip(kind: .shape, duration: .init(seconds: 1), presentation: style, effects: [effect])
        var doc = ProjectDocument(globalClips: [clip])
        let renderer = FrameRenderer(softwareRendering: true), size = CGSize(width: 256, height: 256)
        let narrow = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.25), rootURL: root, size: size)
        doc.globalClips[0].effects[0].glowRadius = 1
        let wide = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.25), rootURL: root, size: size)
        let outsideNarrow = pixel(narrow, x: 39, y: 128), outsideWide = pixel(wide, x: 39, y: 128)
        XCTAssertGreaterThan(Int(outsideWide[1]), Int(outsideNarrow[1]) + 5, "The broad halo must illuminate pixels away from the silhouette, not just recolor the edge")
        XCTAssertEqual(doc.globalClips[0].effects[0].amount, 1)
        for (name, image) in [("neon-contour-only", narrow), ("neon-wide-halo", wide)] {
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        try DocumentEditor.splitClip(clip.id, at: .init(seconds: 0.2), in: &doc)
        let split = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.25), rootURL: root, size: size)
        XCTAssertEqual(wide.dataProvider?.data as Data?, split.dataProvider?.data as Data?)
        doc.globalClips[1].effects[0].amount = 0
        let zero = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.25), rootURL: root, size: size)
        doc.globalClips[1].effects = []
        let plain = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[1].id), time: .init(seconds: 0.25), rootURL: root, size: size)
        XCTAssertEqual(zero.dataProvider?.data as Data?, plain.dataProvider?.data as Data?)
    }
    func testColoredCaptionBackdropSurvivesMovieExport() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var style = Presentation(textSize: 0.1, background: "#EF4444", textBackgroundOpacity: 1)
        style.textBackgroundShape = .cloud
        let caption = Clip(kind: .text, duration: .init(seconds: 0.5), text: "Bonjour", presentation: style)
        let doc = ProjectDocument(globalClips: [caption])
        let output = root.appendingPathComponent("colored-caption.mp4")
        _ = try await MovieExporter().export(document: doc, variantID: doc.variants[0].id, rootURL: root, settings: MovieExportSettings(longEdge: 320), outputURL: output, progress: { _ in })
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output)); generator.appliesPreferredTrackTransform = true
        let frame = try await generator.image(at: .zero).image
        var pixels = [UInt8](repeating: 0, count: frame.width * frame.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: frame.width, height: frame.height, bitsPerComponent: 8, bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        }
        let redPixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 120 && Int(pixels[$0]) > Int(pixels[$0 + 1]) + 50 }.count
        XCTAssertGreaterThan(redPixels, 100)
    }

    func testExportProfilesSeparateConstantQualityFromAdaptiveAndManualBitrate() {
        let variant = ProjectDocument().variants[0]
        let compact = MovieExportSettings(longEdge: 1920, qualityProfile: .compact)
        let balanced = MovieExportSettings(longEdge: 1920, qualityProfile: .balanced)
        let fidelity = MovieExportSettings(longEdge: 1920, qualityProfile: .fidelity)
        XCTAssertLessThan(compact.estimatedBitrate(for: variant), balanced.estimatedBitrate(for: variant))
        XCTAssertLessThan(balanced.estimatedBitrate(for: variant), fidelity.estimatedBitrate(for: variant))
        let hevc = MovieExportSettings(longEdge: 1920, codec: .hevc, qualityProfile: .balanced)
        XCTAssertLessThan(hevc.estimatedBitrate(for: variant), balanced.estimatedBitrate(for: variant))
        let larger = MovieExportSettings(longEdge: 3840, frameRate: 60, qualityProfile: .balanced)
        XCTAssertGreaterThan(larger.estimatedBitrate(for: variant), balanced.estimatedBitrate(for: variant) * 7)
        let cq = balanced.compressionProperties(for: variant, supportsConstantQuality: true, supportsQualityPriority: true)
        XCTAssertEqual(cq[kVTCompressionPropertyKey_ConstantQualityFactor as String] as? Double, 0.72)
        XCTAssertNil(cq[AVVideoAverageBitRateKey])
        XCTAssertEqual(cq[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] as? Bool, false)
        let fallback = balanced.compressionProperties(for: variant, supportsConstantQuality: false, supportsQualityPriority: false)
        XCTAssertEqual(fallback[AVVideoAverageBitRateKey] as? Int, balanced.estimatedBitrate(for: variant))
        XCTAssertNil(fallback[kVTCompressionPropertyKey_ConstantQualityFactor as String])
        let manual = MovieExportSettings(bitrate: 4_000_000)
        let properties = manual.compressionProperties(for: variant, supportsConstantQuality: true, supportsQualityPriority: true)
        XCTAssertEqual(properties[AVVideoAverageBitRateKey] as? Int, 4_000_000)
        XCTAssertNil(properties[kVTCompressionPropertyKey_ConstantQualityFactor as String])
    }

    func testQualityProfilesProduceVerifiedH264AndHEVCFiles() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let doc = ProjectDocument(scenes: [.init(duration: .init(seconds: 0.5), clips: [shape("#387F56")])])
        let size = MovieExportSettings(longEdge: 320).dimensions(for: doc.variants[0])
        let expected = try await FrameRenderer(softwareRendering: true).render(plan: .compile(document: doc, variantID: doc.variants[0].id), time: .zero, rootURL: root, size: size)
        let expectedColor = pixel(expected, x: Int(size.width / 2), y: Int(size.height / 2))
        for codec in MovieCodec.allCases {
            for profile in MovieQualityProfile.allCases {
                let settings = MovieExportSettings(longEdge: 320, frameRate: 30, codec: codec, qualityProfile: profile)
                let output = root.appendingPathComponent("\(codec.rawValue)-\(profile.rawValue).mp4")
                let supported = settings.supportedEncoderProperties(for: doc.variants[0])
                let receipt = try await MovieExporter().export(document: doc, variantID: doc.variants[0].id, rootURL: root, settings: settings, outputURL: output, progress: { _ in })
                XCTAssertEqual(receipt.constantQuality, supported.contains(kVTCompressionPropertyKey_ConstantQualityFactor as String))
                XCTAssertEqual(receipt.frameRate, 30, accuracy: 0.1)
                XCTAssertGreaterThan(try Data(contentsOf: output).count, 500)
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output)); generator.appliesPreferredTrackTransform = true
                let decoded = try await generator.image(at: .zero)
                let exportedColor = pixel(decoded.image, x: Int(size.width / 2), y: Int(size.height / 2))
                for channel in 0..<3 {
                    XCTAssertLessThanOrEqual(abs(Int(expectedColor[channel]) - Int(exportedColor[channel])), 5, "\(codec.rawValue) / \(profile.rawValue) must preserve display-referred midtone colors")
                }
                print("Export profile \(codec.rawValue) / \(profile.rawValue): constantQuality=\(receipt.constantQuality), bytes=\(try Data(contentsOf: output).count)")
            }
        }
    }

    func testCaptionAuditionClampsRangesAndReportsNoAudio() async throws {
        XCTAssertEqual(CaptionSegmentPlayer.range(start: .init(seconds: -1), end: .init(seconds: 4), duration: .init(seconds: 3)), 0...3)
        XCTAssertNil(CaptionSegmentPlayer.range(start: .init(seconds: 4), end: .init(seconds: 5), duration: .init(seconds: 3)))
        XCTAssertNil(CaptionSegmentPlayer.range(start: .init(seconds: 1), end: .init(seconds: 1), duration: .init(seconds: 3)))
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let doc = ProjectDocument(scenes: [.init(duration: .init(seconds: 3), clips: [shape("#000000", duration: 3)])])
        let audition = CaptionSegmentPlayer(plan: .compile(document: doc, variantID: nil), rootURL: root)
        defer { audition.stop() }
        audition.toggle(id: UUID(), start: .zero, end: .init(seconds: 1))
        try await waitForAudition { audition.activeID == nil }
        XCTAssertNotNil(audition.error)
        XCTAssertFalse(audition.preparing)
    }

    func testCaptionAuditionRealAudioAutoStopSwitchAndCancellation() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("caption-tone.caf")
        try audioFixture(at: url, seconds: 3)
        let asset = try await MediaImporter().importFile(url: url, to: root)
        let doc = ProjectDocument(assets: [asset], scenes: [.init(duration: .init(seconds: 3))],
                                  globalClips: [Clip(assetID: asset.id, kind: .audio, duration: .init(seconds: 3), sourceDuration: .init(seconds: 3))])
        let audition = CaptionSegmentPlayer(plan: .compile(document: doc, variantID: nil), rootURL: root)
        defer { audition.stop() }
        let first = UUID(), second = UUID()
        audition.toggle(id: first, start: .init(seconds: 0.2), end: .init(seconds: 1.2))
        try await waitForAudition { !audition.preparing && audition.position > 0.25 }
        XCTAssertEqual(audition.activeID, first); XCTAssertNil(audition.error)
        audition.toggle(id: second, start: .init(seconds: 1.5), end: .init(seconds: 2))
        XCTAssertEqual(audition.activeID, second)
        try await waitForAudition { audition.activeID == nil }
        XCTAssertEqual(audition.position, 2, accuracy: 0.01); XCTAssertNil(audition.error)
        audition.toggle(id: first, start: .zero, end: .init(seconds: 1))
        audition.toggle(id: first, start: .zero, end: .init(seconds: 1))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(audition.activeID); XCTAssertFalse(audition.preparing)
        audition.toggle(id: second, start: .init(seconds: 1), end: .init(seconds: 2))
        audition.stop()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(audition.activeID); XCTAssertFalse(audition.preparing)
    }

    private func waitForAudition(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertTrue(condition(), "The audition did not reach its expected state.")
    }

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
