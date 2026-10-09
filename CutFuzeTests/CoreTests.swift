import XCTest
@testable import CutFuze

final class CoreTests: XCTestCase {
    func testChangingEasingImmediatelyChangesRenderedCurveAndSupportsUndo() throws {
        let start = Keyframe(time: .zero, property: .scale, value: 1)
        let end = Keyframe(time: .init(seconds: 4), property: .scale, value: 2)
        let clip = Clip(kind: .shape, duration: .init(seconds: 4), sourceDuration: .init(seconds: 4), keyframes: [start, end])
        let history = EditHistory(document: ProjectDocument(scenes: [.init(duration: .init(seconds: 4), clips: [clip])]))
        let expected: [(KeyframeEasing, Double)] = [(.linear, 1.25), (.easeIn, 1.0625), (.easeOut, 1.4375), (.easeInOut, 1.15625)]
        for (easing, value) in expected {
            try history.perform(name: "Interpolation") { try AnimationEditing.setEasing(easing, keyframeID: end.id, clipID: clip.id, in: &$0) }
            let rendered = try XCTUnwrap(RenderPlan.compile(document: history.document, variantID: nil).clips.first)
            XCTAssertEqual(rendered.evaluatedPresentation(at: .init(seconds: 1)).scale, value, accuracy: 0.000001)
            let restored = try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(history.document))
            XCTAssertEqual(restored.clip(clip.id)?.keyframes.last?.easing, easing)
        }
        history.undo()
        XCTAssertEqual(history.document.clip(clip.id)?.keyframes.last?.easing, .easeOut)
        history.redo()
        XCTAssertEqual(history.document.clip(clip.id)?.keyframes.last?.easing, .easeInOut)
    }
    func testCaptionReviewTextResponseRejectsRefusalProseAndMalformedJSON() throws {
        let input = CaptionReviewInput(id: UUID(), original: "Les chat joue.", text: "Les chat joue.", start: .zero, end: .init(seconds: 1))
        let json = #"{"text":"Les chats jouent."}"#
        XCTAssertEqual(try CaptionProofreading.decodePhraseResponse(json, for: [input]).first?.replacement, "Les chats jouent.")
        XCTAssertEqual(try CaptionProofreading.decodePhraseResponse("```json\n" + json + "\n```", for: [input]).first?.id, input.id)
        for bad in ["Je ne peux pas vous aider avec ce contenu.", "Voici la réponse : " + json,
                    #"{"text":""}"#, #"{"text":false}"#, #"{"text":0}"#, #"{"text":null}"#,
                    #"{"text":"Bonjour","reason":"test"}"#,
                    #"{"captions":[],"refusal":"Non"}"#] {
            XCTAssertThrowsError(try CaptionProofreading.decodePhraseResponse(bad, for: [input]))
        }
    }

    func testCaptionPhraseGroupingPreservesBoundariesAndRejectsPartialAcceptance() throws {
        var doc = document(); doc.scenes[0].clips.removeAll { $0.isCaption }
        doc.globalClips = ["Les chat", "joue dans le", "jardin.", "Bonjour !", "Autre phrase"].enumerated().map {
            Clip(kind: .text, start: .init(seconds: Double($0.offset)), duration: .init(seconds: 1), text: $0.element, isCaption: true)
        }
        let inputs = CaptionProofreading.inputs(in: doc)
        let batches = try CaptionProofreading.phraseBatches(inputs)
        XCTAssertEqual(batches.map(\.count), [3, 1, 1])
        XCTAssertEqual(batches.flatMap { $0 }.map(\.id), inputs.map(\.id))
        let response = #"{"text":"Les chats jouent dans le jardin."}"#
        var corrections = try CaptionProofreading.decodePhraseResponse(response, for: batches[0])
        XCTAssertEqual(corrections.count, 2)
        let before = doc.globalClips
        corrections[1].accepted = false
        XCTAssertThrowsError(try CaptionProofreading.apply(corrections, in: &doc))
        XCTAssertEqual(doc.globalClips, before)
        corrections[1].accepted = true
        let history = EditHistory(document: doc)
        try history.perform(name: "Relecture de phrase") { try CaptionProofreading.apply(corrections, in: &$0) }
        XCTAssertEqual(history.document.globalClips.prefix(3).map(\.text).joined(separator: " "), "Les chats jouent dans le jardin.")
        XCTAssertEqual(history.document.globalClips.map(\.start), before.map(\.start))
        XCTAssertEqual(history.document.globalClips.map(\.duration), before.map(\.duration))
        history.undo(); XCTAssertEqual(history.document.globalClips, before)
        var layers = inputs; layers[1].layer = 1
        XCTAssertEqual(try CaptionProofreading.phraseBatches(layers).prefix(3).map(\.count), [1, 1, 1])
    }

    func testCaptionPhraseRedistributionKeepsApproximateCutsAndEveryWordOnce() throws {
        let inputs = ["Les chat", "joue dans le", "jardin."].enumerated().map {
            CaptionReviewInput(id: UUID(), original: $0.element, text: $0.element,
                               start: .init(seconds: Double($0.offset)), end: .init(seconds: Double($0.offset + 1)))
        }
        let result = try CaptionProofreading.decodePhraseResponse(#"{"text":"Les chats jouent dans le jardin."}"#, for: inputs)
        let parts = inputs.map { input in result.first { $0.id == input.id }?.replacement ?? input.text }
        XCTAssertEqual(parts, ["Les chats", "jouent dans le", "jardin."])
        XCTAssertEqual(parts.joined(separator: " "), "Les chats jouent dans le jardin.")
        XCTAssertTrue(result.allSatisfy { $0.groupID == inputs[0].id })
        let longer = try CaptionProofreading.decodePhraseResponse(#"{"text":"Les chats jouent tranquillement dans le grand jardin."}"#, for: inputs)
        let longerParts = inputs.map { input in longer.first { $0.id == input.id }?.replacement ?? input.text }
        XCTAssertEqual(longerParts.joined(separator: " "), "Les chats jouent tranquillement dans le grand jardin.")
        XCTAssertTrue(longerParts.allSatisfy { !$0.isEmpty })
        XCTAssertThrowsError(try CaptionProofreading.decodePhraseResponse(#"{"text":"Non."}"#, for: inputs))
        XCTAssertThrowsError(try CaptionProofreading.decodePhraseResponse("Je ne peux pas relire ce texte.", for: inputs))
        XCTAssertThrowsError(try CaptionProofreading.decodePhraseResponse(#"{"text":"Bonjour","reason":"refusal"}"#, for: inputs))
    }

    @MainActor func testRealCaptionIntelligenceProofreadsWholePhraseAndNeutralLanguageFragment() async throws {
        if let reason = CaptionIntelligence.unavailableReason { throw XCTSkip(reason) }
        let inputs = ["Les chat", "joue dans le", "jardin."].enumerated().map {
            CaptionReviewInput(id: UUID(), original: $0.element, text: $0.element,
                               start: .init(seconds: Double($0.offset)), end: .init(seconds: Double($0.offset + 1)))
        }
        var progress: [Int] = []
        let corrections = try await CaptionIntelligence.review(inputs, wholeTrack: true) { count, _ in progress.append(count) }
        let text = inputs.map { input in corrections.first { $0.id == input.id }?.replacement ?? input.text }.joined(separator: " ")
        XCTAssertEqual(text.lowercased(), "les chats jouent dans le jardin.")
        XCTAssertEqual(progress, [3])
        XCTAssertTrue(corrections.allSatisfy { $0.groupID == inputs[0].id })
        for correction in corrections {
            let input = try XCTUnwrap(inputs.first { $0.id == correction.id })
            XCTAssertEqual(correction.start, input.start); XCTAssertEqual(correction.end, input.end)
        }
        let neutral = CaptionReviewInput(id: UUID(), original: "Pas espagnol", text: "Pas espagnol", start: .zero, end: .init(seconds: 2))
        let result = try await CaptionIntelligence.review([neutral]) { _, _ in }
        let neutralText = result.first?.replacement ?? neutral.text
        XCTAssertTrue(neutralText.lowercased().contains("pas espagnol"), neutralText)
    }

    @MainActor func testRealCaptionIntelligenceProcessesMultipleBatchesWithoutChangingTiming() async throws {
        if let reason = CaptionIntelligence.unavailableReason { throw XCTSkip(reason) }
        let inputs = (0..<9).map { index in
            CaptionReviewInput(id: UUID(), original: "Les chat joue.", text: "Les chat joue.",
                               start: .init(seconds: Double(index)), end: .init(seconds: Double(index + 1)))
        }
        var progress: [Int] = []
        let corrections = try await CaptionIntelligence.review(inputs, wholeTrack: true) { completed, total in
            progress.append(completed); XCTAssertEqual(total, 9)
        }
        XCTAssertEqual(progress, Array(1...9))
        XCTAssertEqual(corrections.map(\.id), inputs.map(\.id))
        XCTAssertEqual(corrections.map(\.start), inputs.map(\.start))
        XCTAssertEqual(corrections.map(\.end), inputs.map(\.end))
        XCTAssertTrue(corrections.allSatisfy { $0.replacement.contains("chats") && $0.replacement.contains("jouent") })
    }

    func testCaptionProofreadingPreservesTimingSourceStyleFormatsAndSingleUndo() throws {
        var doc = document(); doc.assets[0].kind = .video
        let media = Clip(assetID: doc.assets[0].id, kind: .video, duration: .init(seconds: 10), sourceDuration: .init(seconds: 10))
        let caption = Clip(kind: .text, start: .init(seconds: 2), duration: .init(seconds: 6), text: "Les chat joue.", isCaption: true,
                           captionSourceAssetID: doc.assets[0].id, captionSourceClipID: media.id,
                           captionSourceStart: .init(seconds: 2), captionSourceEnd: .init(seconds: 8), captionAnalyzedRevision: 3)
        let second = Clip(kind: .text, start: .init(seconds: 8), duration: .init(seconds: 1), text: "Autre texte", isCaption: true)
        doc.scenes[0].clips = [media, caption, second]
        var presentation = Presentation(); presentation.y = 0.3
        doc.variants[1].overrides[caption.id.uuidString] = presentation
        let inputs = CaptionProofreading.inputs(in: doc)
        var corrections = try CaptionProofreading.corrections(for: inputs, indexedTexts: [(1, "Autre texte."), (0, "Les chats jouent.")])
        corrections[1].accepted = false
        let history = EditHistory(document: doc)
        try history.perform(name: "Relecture") { try CaptionProofreading.apply(corrections, in: &$0) }
        var expected = caption; expected.text = "Les chats jouent."
        XCTAssertEqual(history.document.clip(caption.id), expected)
        XCTAssertEqual(history.document.clip(second.id), second)
        XCTAssertEqual(history.document.variants, doc.variants)
        history.undo(); XCTAssertEqual(history.document.scenes, doc.scenes)
        history.redo(); XCTAssertEqual(history.document.clip(caption.id)?.text, "Les chats jouent.")
    }

    func testCaptionProofreadingRejectsMalformedOutputAndStaleEditsAtomically() throws {
        var doc = document()
        let first = Clip(kind: .text, duration: .init(seconds: 3), text: "Bonjour", isCaption: true)
        let second = Clip(kind: .text, start: .init(seconds: 3), duration: .init(seconds: 3), text: "Salut", isCaption: true)
        doc.scenes[0].clips = doc.scenes[0].clips.filter { !$0.isCaption } + [first, second]
        let inputs = CaptionProofreading.inputs(in: doc)
        XCTAssertThrowsError(try CaptionProofreading.corrections(for: inputs, indexedTexts: [(0, "Bonjour.")]))
        XCTAssertThrowsError(try CaptionProofreading.corrections(for: inputs, indexedTexts: [(0, "Bonjour."), (0, "Salut.")]))
        XCTAssertThrowsError(try CaptionProofreading.corrections(for: inputs, indexedTexts: [(-1, "Bonjour."), (1, "Salut.")]))
        XCTAssertThrowsError(try CaptionProofreading.corrections(for: inputs, indexedTexts: [(0, " "), (1, "Salut.")]))
        XCTAssertTrue(try CaptionProofreading.corrections(for: inputs, indexedTexts: [(0, "Bonjour"), (1, "Salut")]).isEmpty)
        var corrections = try CaptionProofreading.corrections(for: inputs, indexedTexts: [(0, "Bonjour."), (1, "Salut.")])
        try DocumentEditor.updateClip(second.id, in: &doc) { $0.text = "Modifié à la main" }
        let saved = doc.scenes
        XCTAssertThrowsError(try CaptionProofreading.apply(corrections, in: &doc))
        XCTAssertEqual(doc.scenes, saved)
        corrections[1].accepted = false
        try CaptionProofreading.apply(corrections, in: &doc)
        XCTAssertEqual(doc.clip(first.id)?.text, "Bonjour.")
        XCTAssertEqual(doc.clip(second.id)?.text, "Modifié à la main")
    }

    func testCaptionProofreadingBatchesAndUnsavedDraftDoNotMutateDocument() throws {
        var doc = document()
        doc.scenes[0].clips.removeAll { $0.isCaption }
        doc.globalClips = (0..<19).map { Clip(kind: .text, start: .init(seconds: Double($0)), duration: .init(seconds: 1), text: String(repeating: "é", count: 150), isCaption: true) }
        let id = doc.globalClips[0].id
        let inputs = CaptionProofreading.inputs(in: doc, draftID: id, draft: "Brouillon")
        XCTAssertEqual(inputs.first?.text, "Brouillon")
        XCTAssertEqual(doc.clip(id)?.text, String(repeating: "é", count: 150))
        let batches = try CaptionProofreading.batches(inputs)
        XCTAssertEqual(batches.flatMap { $0 }.map(\.id), inputs.map(\.id))
        XCTAssertTrue(batches.allSatisfy { $0.count <= 8 && $0.reduce(0) { $0 + $1.text.utf8.count } <= 1800 })
        let correction = try CaptionProofreading.corrections(for: [inputs[0]], indexedTexts: [(0, "Brouillon.")])
        XCTAssertEqual(correction.first?.original, doc.clip(id)?.text)
        XCTAssertEqual(correction.first?.reviewedText, "Brouillon")
        XCTAssertTrue(try CaptionProofreading.batches([]).isEmpty)
        let tooLong = CaptionReviewInput(id: id, original: "", text: String(repeating: "é", count: 901), start: .zero, end: .init(seconds: 1))
        XCTAssertThrowsError(try CaptionProofreading.batches([tooLong]))
    }

    func testEffectPointEditorPreservesIdentityDomainAndRejectsCollisions() throws {
        var effect = EffectInstance(kind: .brightness, amount: 0.2, start: .init(seconds: 5.5), duration: .init(seconds: 3))
        let domain = MediaTime(seconds: 5)...MediaTime(seconds: 10)
        let firstID = try EffectAnimationEditing.upsert(at: .init(seconds: 6), value: 0.1, easing: .easeOut, domain: domain, in: &effect)
        let lastID = try EffectAnimationEditing.upsert(at: .init(seconds: 9), value: 0.8, easing: .linear, domain: domain, in: &effect)
        XCTAssertEqual(try EffectAnimationEditing.upsert(at: .init(seconds: 6), value: 0.3, easing: .easeOut, domain: domain, in: &effect), firstID)
        try EffectAnimationEditing.move(firstID, to: .init(seconds: 7), value: 0.5, domain: domain, in: &effect)
        let key = try XCTUnwrap(effect.amountKeyframes?.first { $0.id == firstID })
        XCTAssertEqual(key.time, .init(seconds: 7)); XCTAssertEqual(key.value, 0.5); XCTAssertEqual(key.easing, .easeOut)
        XCTAssertEqual(effect.amountKeyframes?.count, 2); XCTAssertEqual(effect.amountKeyframes?.last?.id, lastID)
        XCTAssertEqual(effect.start, .init(seconds: 5.5)); XCTAssertEqual(effect.duration, .init(seconds: 3))
        XCTAssertEqual(effect.animatedAmount(at: .init(seconds: 8)), 0.65, accuracy: 0.000001)
        XCTAssertNil(effect.evaluatedAmount(at: .init(seconds: 8.5)))
        let saved = effect
        XCTAssertThrowsError(try EffectAnimationEditing.move(firstID, to: .init(seconds: 9), value: 1, domain: domain, in: &effect))
        XCTAssertThrowsError(try EffectAnimationEditing.move(firstID, to: .init(seconds: 4), value: 1, domain: domain, in: &effect))
        XCTAssertThrowsError(try EffectAnimationEditing.upsert(at: .init(seconds: 8), value: .nan, easing: .linear, domain: domain, in: &effect))
        XCTAssertEqual(effect, saved)
        var doc = document(); let clipID = doc.scenes[0].clips[0].id
        doc.scenes[0].clips[0].effects = [effect]
        let splitID = try DocumentEditor.splitClip(clipID, at: .init(seconds: 5), in: &doc)
        let split = try XCTUnwrap(RenderPlan.compile(document: doc, variantID: nil).clips.first { $0.id == splitID })
        XCTAssertEqual(split.clip.animationOffset, .init(seconds: 5))
        XCTAssertEqual(split.clip.effects.first?.animatedAmount(at: .init(seconds: 8) - split.globalStart + split.clip.animationOffset), 0.65)
        let history = EditHistory(document: doc)
        try history.perform(name: "Effet") { candidate in
            candidate.updateClip(splitID) { $0.effects[0] = EffectInstance(kind: .brightness, amount: 0.2) }
        }
        history.undo(); XCTAssertEqual(history.document.clip(splitID)?.effects.first, effect)
        history.redo(); XCTAssertNil(history.document.clip(splitID)?.effects.first?.amountKeyframes)
    }
    private func document() -> ProjectDocument {
        let asset = MediaAsset(relativePath: "Assets/source.png", kind: .image, name: "Mire", duration: .init(seconds: 10), width: 2, height: 2)
        let image = Clip(assetID: asset.id, kind: .image, duration: .init(seconds: 10), sourceDuration: .init(seconds: 10))
        let title = Clip(kind: .text, start: .init(seconds: 1), duration: .init(seconds: 8), text: "Un récit", keyframes: [.init(time: .zero, property: .x, value: 0.2), .init(time: .init(seconds: 8), property: .x, value: 0.8)], layer: 10, isCaption: true)
        return ProjectDocument(title: "Atelier", assets: [asset], scenes: [.init(title: "Ouverture", duration: .init(seconds: 10), clips: [image, title]), .init(title: "Suite", duration: .init(seconds: 4), clips: [Clip(kind: .shape, duration: .init(seconds: 4))])], globalClips: [Clip(kind: .text, start: .init(seconds: 3), duration: .init(seconds: 9), text: "Global")])
    }
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CutFuzeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func sourceRoot(for doc: ProjectDocument) throws -> URL {
        let root = try temporaryRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        // Original tiny deterministic RGBA PNG, enough to prove byte portability.
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        try bytes.write(to: root.appendingPathComponent(doc.assets[0].relativePath))
        return root
    }
    func testDocumentRoundTripAndV1Migration() throws {
        let original = document()
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(original)), original)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentCodec.encode(original)) as? [String: Any])
        legacy["schemaVersion"] = 1; legacy["revision"] = nil; legacy["collection"] = nil; legacy["variants"] = nil
        let migrated = try DocumentCodec.decode(JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.schemaVersion, 2); XCTAssertEqual(migrated.scenes, original.scenes)
        XCTAssertEqual(migrated.assets, original.assets); XCTAssertEqual(migrated.variants.count, 3)
        legacy["schemaVersion"] = 987
        XCTAssertThrowsError(try DocumentCodec.decode(JSONSerialization.data(withJSONObject: legacy)))
    }
    func testSceneReorderMovesChildrenAndPreservesGlobalAnchor() throws {
        var doc = document()
        let global = doc.globalClips, moved = doc.scenes[0], firstChild = moved.clips[0].id
        try DocumentEditor.reorderScene(moved.id, to: 1, in: &doc)
        let plan = RenderPlan.compile(document: doc, variantID: nil)
        XCTAssertEqual(plan.clips.first { $0.id == firstChild }?.globalStart, .init(seconds: 4))
        XCTAssertEqual(doc.globalClips, global); XCTAssertEqual(plan.clips.first { $0.id == global[0].id }?.globalStart, .init(seconds: 3))
    }
    func testTimelineMoveCanTransferClipIntoEarlierScene() throws {
        var doc = document()
        let movedID = try XCTUnwrap(doc.scenes[1].clips.first?.id)

        try DocumentEditor.moveClip(movedID, toGlobalStart: .init(seconds: 3), in: &doc)

        XCTAssertFalse(doc.scenes[1].clips.contains { $0.id == movedID })
        let moved = try XCTUnwrap(doc.scenes[0].clips.first { $0.id == movedID })
        XCTAssertEqual(moved.start, .init(seconds: 3))
        XCTAssertEqual(RenderPlan.compile(document: doc, variantID: nil).clips.first { $0.id == movedID }?.globalStart, .init(seconds: 3))
        try doc.validate()
    }
    func testTimelineMoveKeepsProjectOwnedClipOnAbsoluteTimeline() throws {
        var doc = document()
        let movedID = try XCTUnwrap(doc.globalClips.first?.id)

        try DocumentEditor.moveClip(movedID, toGlobalStart: .init(seconds: 1), in: &doc)

        XCTAssertEqual(doc.globalClips.first { $0.id == movedID }?.start, .init(seconds: 1))
        XCTAssertEqual(RenderPlan.compile(document: doc, variantID: nil).clips.first { $0.id == movedID }?.globalStart, .init(seconds: 1))
        try doc.validate()
    }
    func testTimelineMoveDoesNotStretchDestinationSceneOrProject() throws {
        var doc = document()
        let movedID = doc.scenes[0].clips[0].id
        let durationBefore = doc.duration

        try DocumentEditor.moveClip(movedID, toGlobalStart: .init(seconds: 3), in: &doc)

        XCTAssertTrue(doc.globalClips.contains { $0.id == movedID && $0.start == .init(seconds: 3) })
        XCTAssertEqual(doc.scenes[0].duration, .init(seconds: 10))
        XCTAssertEqual(doc.duration, durationBefore)
        try doc.validate()
    }
    func testSceneDuplicateSharesMediaAndCopiesVariantOverrides() throws {
        var doc = document(); let original = doc.scenes[0]
        var square = original.clips[0].presentation; square.x = 0.25
        doc.variants[1].overrides[original.clips[0].id.uuidString] = square
        let newID = try DocumentEditor.duplicateScene(original.id, in: &doc)
        let duplicate = try XCTUnwrap(doc.scenes.first { $0.id == newID })
        XCTAssertNotEqual(duplicate.clips[0].id, original.clips[0].id)
        XCTAssertEqual(duplicate.clips[0].assetID, original.clips[0].assetID)
        XCTAssertEqual(doc.assets.count, 1)
        XCTAssertEqual(doc.variants[1].overrides[duplicate.clips[0].id.uuidString], square)
        try doc.validate()
    }
    func testSceneSplitAndGroupPreserveSourceAndAnimation() throws {
        var doc = document(); let sceneID = doc.scenes[0].id
        let old = RenderPlan.compile(document: doc, variantID: nil)
        let secondID = try DocumentEditor.splitScene(sceneID, at: .init(seconds: 5), in: &doc)
        let split = RenderPlan.compile(document: doc, variantID: nil)
        XCTAssertEqual(old.duration, split.duration)
        let animated = try XCTUnwrap(split.clips.first { $0.sceneID == secondID && $0.clip.kind == .text })
        let prior = try XCTUnwrap(old.clips.first { $0.clip.isCaption })
        XCTAssertEqual(animated.evaluatedPresentation(at: .init(seconds: 6)), prior.evaluatedPresentation(at: .init(seconds: 6)))
        _ = try DocumentEditor.groupScenes([sceneID, secondID], in: &doc)
        XCTAssertEqual(doc.scenes.count, 2)
        let grouped = RenderPlan.compile(document: doc, variantID: nil)
        XCTAssertEqual(grouped.clips.map(\.globalStart), split.clips.map(\.globalStart))
        XCTAssertEqual(grouped.duration, old.duration)
        try doc.validate()
    }
    func testCommonCutAndIsolatedSquarePresentationWithUndoRedo() throws {
        let original = document(), history = EditHistory(document: document())
        let id = history.document.scenes[0].clips[0].id, square = history.document.variants[1].id
        var presentation = Presentation(); presentation.x = 0.2
        try history.perform(name: "Cadrer") { try DocumentEditor.setPresentation(presentation, clipID: id, variantID: square, in: &$0) }
        try history.perform(name: "Couper") { _ = try DocumentEditor.splitClip(id, at: .init(seconds: 4), in: &$0) }
        let cut = history.document
        for variant in cut.variants { XCTAssertEqual(RenderPlan.compile(document: cut, variantID: variant.id).clips.filter { $0.clip.kind == .image }.map(\.duration), [.init(seconds: 4), .init(seconds: 6)]) }
        XCTAssertEqual(RenderPlan.compile(document: cut, variantID: square).clips.first?.presentation.x, 0.2)
        XCTAssertEqual(RenderPlan.compile(document: cut, variantID: cut.variants[0].id).clips.first?.presentation.x, 0.5)
        history.undo(); XCTAssertEqual(history.document.scenes[0].clips.count, original.scenes[0].clips.count)
        history.undo(); XCTAssertTrue(history.document.variants[1].overrides.isEmpty)
        let revision = history.document.revision
        history.redo(); history.redo()
        XCTAssertGreaterThan(history.document.revision, revision)
        XCTAssertEqual(history.document.scenes, cut.scenes); XCTAssertEqual(history.document.variants, cut.variants)
    }
    func testContinuousGestureIsOneUndoAndCancellationRestores() throws {
        let history = EditHistory(document: document()), id = history.document.scenes[0].clips[0].id
        let original = history.document
        history.beginTransaction(name: "Glisser")
        for value in [0.2, 0.3, 0.4] { try history.updateTransaction { try DocumentEditor.updateClip(id, in: &$0) { $0.presentation.x = value } } }
        history.cancelTransaction(); XCTAssertEqual(history.document, original); XCTAssertFalse(history.canUndo)
        history.beginTransaction(name: "Glisser")
        try history.updateTransaction { try DocumentEditor.updateClip(id, in: &$0) { $0.presentation.x = 0.6 } }
        try history.commitTransaction(); XCTAssertTrue(history.canUndo)
        history.undo(); XCTAssertEqual(history.document.scenes, original.scenes); XCTAssertFalse(history.canUndo)
    }

    @MainActor func testCaptionTrackCommonStyleUpdatesExistingFormatOverrides() throws {
        var doc = document()
        let captionID = try XCTUnwrap(doc.allClips.first(where: \.isCaption)?.id)
        for index in doc.variants.indices {
            var override = try XCTUnwrap(doc.clip(captionID)?.presentation)
            override.x = Double(index) * 0.1
            override.textSize = 0.045
            doc.variants[index].overrides[captionID.uuidString] = override
        }
        let originalX = doc.variants.map { $0.overrides[captionID.uuidString]?.x }
        let root = try temporaryRoot()
        let model = EditorModel(document: doc, store: ProjectStore(rootURL: root), rootURL: root)
        model.selectedClipID = captionID

        model.changeCaptionPresentations { $0.textSize = 0.065 }

        XCTAssertEqual(model.document.clip(captionID)?.presentation.textSize, 0.065)
        XCTAssertEqual(model.document.variants.map { $0.overrides[captionID.uuidString]?.textSize }, Array(repeating: 0.065, count: doc.variants.count))
        XCTAssertEqual(model.document.variants.map { $0.overrides[captionID.uuidString]?.x }, originalX)
    }

    @MainActor func testTimelineSelectionPreservesPlayheadAndExplicitNavigationMovesIt() throws {
        let root = try temporaryRoot()
        let model = EditorModel(document: document(), store: ProjectStore(rootURL: root), rootURL: root)
        let clip = try XCTUnwrap(model.plan.clips.first)
        model.seek(5)

        model.selectClip(clip)
        XCTAssertEqual(model.playhead, 5, accuracy: 0.001)

        model.selectClip(clip, movePlayhead: true)
        XCTAssertEqual(model.playhead, clip.globalStart.seconds, accuracy: 0.001)
    }

    @MainActor func testCaptionTrackPositionPreservesOffsetsFormatsAndSingleUndo() throws {
        var doc = document()
        let first = try XCTUnwrap(doc.allClips.first(where: \.isCaption))
        var second = first; second.id = UUID(); second.presentation.x = 0.3; second.presentation.y = 0.7
        doc.scenes[1].clips.append(second)
        doc.scenes[1].duration = second.end
        var square = first.presentation; square.x = 0.4; square.y = 0.6
        doc.variants[1].overrides[first.id.uuidString] = square
        let root = try temporaryRoot()
        let model = EditorModel(document: doc, store: ProjectStore(rootURL: root), rootURL: root)
        model.selectedClipID = first.id
        model.captionWholeTrack = true
        model.beginGesture("Position des sous-titres")
        model.movePreviewElement(toX: 0.55, y: 0.55)
        model.movePreviewElement(toX: 0.6, y: 0.6)
        model.endGesture()
        XCTAssertEqual(try XCTUnwrap(model.document.clip(first.id)).presentation.x, 0.6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(model.document.clip(second.id)).presentation.x, 0.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(model.document.clip(second.id)).presentation.y, 0.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(model.document.variants[1].overrides[first.id.uuidString]).x, 0.5, accuracy: 0.001)
        XCTAssertEqual(model.document.clip(first.id)?.start, first.start)
        XCTAssertEqual(model.document.clip(second.id)?.duration, second.duration)
        let moved = try XCTUnwrap(model.plan.clips.first { $0.id == first.id })
        let original = try XCTUnwrap(RenderPlan.compile(document: doc, variantID: model.variantID).clips.first { $0.id == first.id })
        XCTAssertEqual(moved.evaluatedPresentation(at: .init(seconds: 3)).x, original.evaluatedPresentation(at: .init(seconds: 3)).x + 0.1, accuracy: 0.001)
        XCTAssertEqual(model.document.clip(first.id)?.keyframes.map(\.time), first.keyframes.map(\.time))
        model.undo()
        XCTAssertEqual(model.document.scenes, doc.scenes)
        XCTAssertEqual(model.document.variants, doc.variants)
        XCTAssertFalse(model.canUndo)
        model.redo()
        model.captionWholeTrack = false
        model.movePreviewElement(toX: 0.7, y: 0.4)
        XCTAssertEqual(try XCTUnwrap(model.document.clip(second.id)).presentation.x, 0.4, accuracy: 0.001)
    }

    @MainActor func testCaptionFontAppliesToTrackAndExistingFormatOverrides() throws {
        var doc = document()
        let first = try XCTUnwrap(doc.allClips.first(where: \.isCaption))
        var second = first; second.id = UUID()
        doc.scenes[0].clips.append(second)
        doc.variants[1].overrides[first.id.uuidString] = first.presentation
        let root = try temporaryRoot()
        let model = EditorModel(document: doc, store: ProjectStore(rootURL: root), rootURL: root)
        model.selectedClipID = first.id; model.captionWholeTrack = true
        model.changeSelectedTextPresentation { $0.textFont = "AvenirNextCondensed-Heavy" }
        XCTAssertEqual(model.document.clip(second.id)?.presentation.textFont, "AvenirNextCondensed-Heavy")
        XCTAssertEqual(model.document.variants[1].overrides[first.id.uuidString]?.textFont, "AvenirNextCondensed-Heavy")
        XCTAssertEqual(model.document.scenes[0].clips[0].presentation, doc.scenes[0].clips[0].presentation)
        model.undo()
        XCTAssertEqual(model.document.scenes, doc.scenes)
    }

    @MainActor func testCaptionBackdropAppliesToTrackWithUndoAndKeepsFraming() throws {
        var doc = document()
        let first = try XCTUnwrap(doc.allClips.first(where: \.isCaption))
        var second = first; second.id = UUID(); second.presentation.x = 0.3
        doc.scenes[0].clips.append(second)
        doc.variants[1].overrides[first.id.uuidString] = first.presentation
        let root = try temporaryRoot()
        let model = EditorModel(document: doc, store: ProjectStore(rootURL: root), rootURL: root)
        model.selectedClipID = first.id; model.captionWholeTrack = true
        model.changeSelectedTextPresentation { $0.textBackgroundShape = .cloud; $0.background = "#EF4444"; $0.textBackgroundOpacity = 1 }
        XCTAssertEqual(model.document.clip(second.id)?.presentation.textBackgroundShape, .cloud)
        XCTAssertEqual(model.document.clip(second.id)?.presentation.background, "#EF4444")
        XCTAssertEqual(model.document.clip(second.id)?.presentation.x, 0.3)
        XCTAssertEqual(model.document.variants[1].overrides[first.id.uuidString]?.textBackgroundShape, .cloud)
        XCTAssertEqual(model.document.clip(second.id)?.start, second.start)
        model.undo(); XCTAssertEqual(model.document.scenes, doc.scenes); XCTAssertEqual(model.document.variants, doc.variants)
    }

    @MainActor func testRemovingBackgroundOnlyChangesSelectedPhoto() throws {
        let asset = MediaAsset(relativePath: "Assets/photo.png", kind: .image, name: "Photo", duration: .init(seconds: 5), width: 1080, height: 1920)
        let first = Clip(assetID: asset.id, kind: .image, duration: .init(seconds: 5), sourceDuration: .init(seconds: 5))
        var second = Clip(assetID: asset.id, kind: .image, duration: .init(seconds: 5), sourceDuration: .init(seconds: 5), layer: 1)
        second.presentation.x = 0.7
        let doc = ProjectDocument(assets: [asset], scenes: [.init(duration: .init(seconds: 5), clips: [first, second])])
        let root = try temporaryRoot()
        let model = EditorModel(document: doc, store: ProjectStore(rootURL: root), rootURL: root)
        model.selectedClipID = second.id

        model.togglePersonBackgroundRemoval()

        XCTAssertFalse(try XCTUnwrap(model.document.clip(first.id)).presentation.removePersonBackground)
        XCTAssertTrue(try XCTUnwrap(model.document.clip(second.id)).presentation.removePersonBackground)
        XCTAssertTrue(model.presentation.removePersonBackground)
        model.undo()
        XCTAssertFalse(try XCTUnwrap(model.document.clip(second.id)).presentation.removePersonBackground)
    }

    func testPreviewInteractionSelectsTopmostVisibleElementAndSnapsMovement() throws {
        let asset = MediaAsset(relativePath: "Assets/source.png", kind: .image, name: "Fond", duration: .init(seconds: 5), width: 1600, height: 900)
        let background = Clip(assetID: asset.id, kind: .image, duration: .init(seconds: 5), sourceDuration: .init(seconds: 5))
        var title = Clip(kind: .text, duration: .init(seconds: 5), text: "Titre", layer: 10)
        title.presentation.x = 0.3
        title.presentation.y = 0.4
        title.presentation.rotation = 20
        var caption = Clip(kind: .text, duration: .init(seconds: 5), text: "Sous-titre", layer: 20, isCaption: true)
        caption.presentation.x = 0.3
        caption.presentation.y = 0.4
        let document = ProjectDocument(assets: [asset], scenes: [.init(duration: .init(seconds: 5), clips: [background, title, caption])])
        let plan = RenderPlan.compile(document: document, variantID: document.variants[0].id)
        let size = CGSize(width: 180, height: 320)
        let layouts = PreviewInteractionGeometry.layouts(plan: plan, time: .init(seconds: 1), canvasSize: size)

        XCTAssertEqual(layouts.count, 3)
        XCTAssertEqual(PreviewInteractionGeometry.hitTest(CGPoint(x: 54, y: 128), layouts: layouts), caption.id)
        XCTAssertTrue(try XCTUnwrap(layouts.first { $0.id == title.id }).contains(CGPoint(x: 54, y: 128)))

        var origin = Presentation()
        origin.x = 0.42
        origin.y = 0.62
        let moved = PreviewInteractionGeometry.movedPresentation(from: origin, translation: CGSize(width: 13, height: -37), canvasSize: size)
        XCTAssertEqual(moved.presentation.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(moved.presentation.y, 0.5, accuracy: 0.0001)
        XCTAssertTrue(moved.snappedX)
        XCTAssertTrue(moved.snappedY)

        let contained = PreviewInteractionGeometry.containedHandlePosition(
            CGPoint(x: 4, y: 316),
            canvasSize: size
        )
        XCTAssertEqual(contained.x, 22, accuracy: 0.001)
        XCTAssertEqual(contained.y, 298, accuracy: 0.001)
    }
    func testFailedCommandLeavesDocumentAndHistoryIntact() throws {
        let original = document(), history = EditHistory(document: document())
        let before = history.document
        XCTAssertThrowsError(try history.perform(name: "Invalide") { $0.scenes[0].duration = .zero })
        XCTAssertEqual(history.document, before); XCTAssertFalse(history.canUndo)
        XCTAssertEqual(original.scenes.count, history.document.scenes.count)
    }
    func testTransitionClampsAvoidDoubleConsumption() {
        var doc = document()
        doc.globalClips = []
        doc.scenes[0].transition = .init(kind: .dissolve, duration: .init(seconds: 20))
        doc.scenes.append(.init(title: "Fin", duration: .init(seconds: 2), clips: []))
        doc.scenes[1].transition = .init(kind: .dissolve, duration: .init(seconds: 20))
        let plan = RenderPlan.compile(document: doc, variantID: nil)
        XCTAssertEqual(plan.scenes[0].transition.duration, .init(seconds: 2))
        XCTAssertEqual(plan.scenes[1].transition.duration, .init(seconds: 1))
        XCTAssertLessThanOrEqual(plan.scenes[0].transition.duration + plan.scenes[1].transition.duration, doc.scenes[1].duration)
        XCTAssertEqual(plan.duration, .init(seconds: 13))
    }
    func testSpeedCurveIntegratesReciprocalAndInvertibleReverse() {
        var clip = Clip(kind: .video, duration: .init(seconds: 10), sourceDuration: .init(seconds: 10), speedPoints: [.init(sourceTime: .zero, speed: 1), .init(sourceTime: .init(seconds: 10), speed: 3)])
        XCTAssertEqual(TimeMapping.outputDuration(clip: clip).seconds, log(3) / 0.2, accuracy: 1.0 / 60_000)
        for reverse in [false, true] {
            clip.reversed = reverse
            for source in stride(from: 0.0, through: 10.0, by: 0.25) {
                let local = TimeMapping.localTime(forSource: .init(seconds: source), clip: clip)
                XCTAssertEqual(TimeMapping.sourceTime(for: local, clip: clip).seconds, source, accuracy: 0.0001)
            }
        }
    }
    func testClipSplitPreservesReversedCurveMapping() throws {
        var doc = document(); doc.assets[0].kind = .video
        let clip = Clip(assetID: doc.assets[0].id, kind: .video, duration: .init(seconds: 5), sourceDuration: .init(seconds: 10), speed: 2, reversed: true)
        doc.scenes[0].clips = [clip]
        _ = try DocumentEditor.splitClip(clip.id, at: .init(seconds: 2), in: &doc)
        let right = doc.scenes[0].clips[1]
        XCTAssertEqual(right.sourceStart, .zero); XCTAssertEqual(right.sourceDuration, .init(seconds: 6))
        XCTAssertEqual(right.effectSeed, clip.id); XCTAssertEqual(doc.scenes[0].clips[0].effectSeed, clip.id)
        XCTAssertEqual(TimeMapping.sourceTime(for: .init(seconds: 1), clip: right), TimeMapping.sourceTime(for: .init(seconds: 3), clip: clip))
    }
    func testRippleTrimMovesSceneFollowersButKeepsGlobalMusic() throws {
        var doc = document(); doc.scenes[0].clips = [Clip(kind: .shape, duration: .init(seconds: 4)), Clip(kind: .text, start: .init(seconds: 4), duration: .init(seconds: 6), text: "suite")]
        let id = doc.scenes[0].clips[0].id, global = doc.globalClips
        try DocumentEditor.trimClip(id, from: .init(seconds: 1), to: .init(seconds: 3), ripple: true, in: &doc)
        XCTAssertEqual(doc.scenes[0].duration, .init(seconds: 8)); XCTAssertEqual(doc.scenes[0].clips[1].start, .init(seconds: 2)); XCTAssertEqual(doc.globalClips, global)
    }

    func testTimelineBoundaryResizeCanTrimAndReextendMedia() throws {
        let asset = MediaAsset(relativePath: "Assets/source.mov", kind: .video, name: "Plan", duration: .init(seconds: 10), width: 1920, height: 1080)
        let clip = Clip(assetID: asset.id, kind: .video, start: .init(seconds: 1), duration: .init(seconds: 6), sourceStart: .init(seconds: 2), sourceDuration: .init(seconds: 6))
        var document = ProjectDocument(assets: [asset], scenes: [.init(duration: .init(seconds: 8), clips: [clip])])

        try DocumentEditor.resizeClip(clip.id, edge: .trailing, by: .init(seconds: -2), in: &document)
        var resized = try XCTUnwrap(document.clip(clip.id))
        XCTAssertEqual(resized.duration.seconds, 4, accuracy: 0.001)
        XCTAssertEqual(resized.sourceDuration.seconds, 4, accuracy: 0.001)

        try DocumentEditor.resizeClip(clip.id, edge: .trailing, by: .init(seconds: 1.5), in: &document)
        resized = try XCTUnwrap(document.clip(clip.id))
        XCTAssertEqual(resized.duration.seconds, 5.5, accuracy: 0.001)
        XCTAssertEqual(resized.sourceDuration.seconds, 5.5, accuracy: 0.001)

        try DocumentEditor.resizeClip(clip.id, edge: .leading, by: .init(seconds: -1), in: &document)
        resized = try XCTUnwrap(document.clip(clip.id))
        XCTAssertEqual(resized.start.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(resized.duration.seconds, 6.5, accuracy: 0.001)
        XCTAssertEqual(resized.sourceStart.seconds, 1, accuracy: 0.001)
    }
    func testKeyframeHalfOpenBoundsAndCaptionSRT() throws {
        let clip = RenderPlan.compile(document: document(), variantID: nil).clips[0]
        XCTAssertTrue(clip.isActive(at: clip.globalStart)); XCTAssertFalse(clip.isActive(at: clip.end))
        let srt = "\u{FEFF}1\r\n00:00:01,250 --> 00:00:02,750\r\nÉtincelle ✨\r\nSeconde ligne\r\n"
        let captions = try CaptionCodec.importSRT(srt)
        XCTAssertEqual(captions[0].start, .init(seconds: 1.25)); XCTAssertEqual(captions[0].duration, .init(seconds: 1.5))
        XCTAssertTrue(CaptionCodec.exportVTT(captions).hasPrefix("WEBVTT\n\n00:00:01.250"))
        XCTAssertEqual(try CaptionCodec.importSRT(CaptionCodec.exportSRT(captions)).map(\.text), captions.map(\.text))
        XCTAssertThrowsError(try CaptionCodec.importSRT("1\n00:00:02,000 --> 00:00:01,000\nNon"))
    }
    func testCaptionSourceRemapAfterSpeedAndReverse() {
        let assetID = UUID(), source = CaptionSegment(start: .init(seconds: 2), end: .init(seconds: 4), text: "mot", sourceAssetID: assetID)
        let clip = Clip(assetID: assetID, kind: .video, duration: .init(seconds: 5), sourceDuration: .init(seconds: 10), speed: 2, reversed: true)
        let rendered = RenderClip(clip: clip, globalStart: .init(seconds: 3), duration: clip.duration, presentation: clip.presentation, sceneID: nil)
        let mapped = CaptionCodec.remap([source], through: rendered)
        XCTAssertEqual(mapped[0].start, .init(seconds: 6)); XCTAssertEqual(mapped[0].end, .init(seconds: 7))
    }
    func testTranscribedWordsBecomeReadableCaptionPhrases() {
        let assetID = UUID()
        let words = [
            TranscribedWord(text: "Bonjour", start: 0, duration: 0.25, confidence: 1),
            TranscribedWord(text: "tout", start: 0.3, duration: 0.2, confidence: 1),
            TranscribedWord(text: "le", start: 0.55, duration: 0.1, confidence: 1),
            TranscribedWord(text: "monde", start: 0.7, duration: 0.25, confidence: 1),
            TranscribedWord(text: ".", start: 0.95, duration: 0.05, confidence: 1),
            TranscribedWord(text: "Après", start: 1.9, duration: 0.25, confidence: 1),
            TranscribedWord(text: "la pause", start: 2.2, duration: 0.4, confidence: 1)
        ]
        let segments = CaptionSegmenter.segments(from: words, sourceAssetID: assetID, analyzedRevision: 7)
        XCTAssertEqual(segments.map(\.text), ["Bonjour tout le monde.", "Après la pause"])
        XCTAssertEqual(segments[0].start, .zero)
        XCTAssertEqual(segments[0].end, .init(seconds: 1))
        XCTAssertEqual(segments[1].sourceAssetID, assetID)
        XCTAssertEqual(segments[1].analyzedRevision, 7)
    }
    #if canImport(UIKit)
    @MainActor func testPendingMediaCanBeInsertedAfterSelectedScene() throws {
        let original = document(), root = try temporaryRoot()
        let model = EditorModel(document: original, store: ProjectStore(rootURL: root), rootURL: root)
        model.selectedSceneID = original.scenes[0].id
        let video = MediaAsset(relativePath: "Assets/added.mov", kind: .video, name: "Vidéo ajoutée", duration: .init(seconds: 3), width: 1920, height: 1080)
        let image = MediaAsset(relativePath: "Assets/added.png", kind: .image, name: "Image ajoutée", duration: .zero, width: 1000, height: 1000)
        model.pendingImports = [video, image]
        model.insertPendingImports(placement: .afterSelection)
        XCTAssertEqual(model.document.scenes.map(\.title), ["Ouverture", "Vidéo ajoutée", "Image ajoutée", "Suite"])
        XCTAssertEqual(model.document.scenes[1].duration, .init(seconds: 3))
        XCTAssertEqual(model.document.scenes[2].duration, .init(seconds: 5))
        XCTAssertTrue(model.pendingImports.isEmpty)
    }

    @MainActor func testPendingAudioAppendsAfterWholeMontageWhenAudioTrackIsEmpty() throws {
        var original = document()
        original.globalClips.removeAll { $0.kind == .audio }
        let originalEnd = original.duration
        let root = try temporaryRoot()
        let model = EditorModel(document: original, store: ProjectStore(rootURL: root), rootURL: root)
        let first = MediaAsset(relativePath: "Assets/music-1.m4a", kind: .audio, name: "Musique 1", duration: .init(seconds: 3))
        let second = MediaAsset(relativePath: "Assets/music-2.m4a", kind: .audio, name: "Musique 2", duration: .init(seconds: 2))

        model.pendingImports = [first, second]
        model.insertPendingImports(placement: .append)

        let audio = model.document.globalClips.filter { $0.kind == .audio }
        XCTAssertEqual(audio.count, 2)
        XCTAssertEqual(audio[0].start, originalEnd)
        XCTAssertEqual(audio[1].start, originalEnd + first.duration)
        XCTAssertEqual(model.document.duration, originalEnd + first.duration + second.duration)
    }
    @MainActor func testVisibleMediaNamesHideGeneratedIdentifiersAndPaths() throws {
        let root = try temporaryRoot()
        let model = EditorModel(document: document(), store: ProjectStore(rootURL: root), rootURL: root)
        let generated = MediaAsset(relativePath: "Assets/illustration.png", kind: .image, name: "illustration-3-0-EFF41C0A-2F91-47F2-8EAF-57F90527B9AD")
        let uuidOnly = MediaAsset(relativePath: "Assets/source.mov", kind: .video, name: "EFF41C0A-2F91-47F2-8EAF-57F90527B9AD.mov")
        let userFile = MediaAsset(relativePath: "Assets/holiday.mov", kind: .video, name: "/private/imports/Vacances.mov")
        XCTAssertEqual(model.displayName(for: generated), "Illustration")
        XCTAssertEqual(model.displayName(for: uuidOnly), L("Vidéo"))
        XCTAssertEqual(model.displayName(for: userFile), "Vacances")
    }
    #endif
    func testAtomicStoreRecoveryAndNoMediaDuplication() throws {
        let root = try temporaryRoot(), store = ProjectStore(rootURL: root)
        var doc = document(); try store.save(document: doc)
        let before = doc; doc.title = "Seconde version"; try store.save(document: doc)
        XCTAssertEqual(try store.load(id: doc.id), doc)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("Projects/\(doc.id.uuidString)/manifest.json"))
        XCTAssertEqual(try store.load(id: doc.id), before)
        let duplicate = try store.duplicate(document: before)
        XCTAssertNotEqual(duplicate.id, before.id); XCTAssertEqual(duplicate.assets, before.assets)
        XCTAssertEqual(try store.list().count, 2)
    }
    func testPortableProjectSurvivesDeletionOfSourceAndPreservesVariants() throws {
        var doc = document(); var local = Presentation(); local.scale = 1.6
        doc.variants[1].overrides[doc.scenes[0].clips[0].id.uuidString] = local
        let source = try sourceRoot(for: doc), destination = try temporaryRoot(), archiveRoot = try temporaryRoot()
        let package = archiveRoot.appendingPathComponent("Story.cutlabproject")
        try PortableProject.export(document: doc, rootURL: source, to: package)
        let sourceBytes = try Data(contentsOf: source.appendingPathComponent(doc.assets[0].relativePath))
        try FileManager.default.removeItem(at: source)
        let store = ProjectStore(rootURL: destination)
        var imported = try PortableProject.importPackage(from: package, into: store)
        XCTAssertNotEqual(imported.id, doc.id); XCTAssertEqual(imported.variants, doc.variants); XCTAssertEqual(imported.scenes, doc.scenes)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(imported.assets[0].relativePath)), sourceBytes)
        imported.title = "Édité après transport"; try store.save(document: imported)
        XCTAssertEqual(try store.load(id: imported.id).title, imported.title)
        let secondPackage = archiveRoot.appendingPathComponent("Second.cutlabproject")
        try PortableProject.export(document: imported, rootURL: destination, to: secondPackage)
        let second = try PortableProject.importPackage(from: secondPackage, into: store)
        XCTAssertNotEqual(second.id, imported.id)
        XCTAssertEqual(try store.list().count, 2)
        for variant in second.variants { XCTAssertEqual(RenderPlan.compile(document: second, variantID: variant.id).duration, doc.duration) }
    }
    func testPortableDigestTamperingAndTruncationAreRejectedAtomically() throws {
        let doc = document(), source = try sourceRoot(for: doc), destination = try temporaryRoot(), packages = try temporaryRoot()
        let package = packages.appendingPathComponent("test.cutlabproject")
        try PortableProject.export(document: doc, rootURL: source, to: package)
        let valid = try Data(contentsOf: package)
        var bad = valid; bad[bad.count - 1] ^= 0xff; try bad.write(to: package)
        let store = ProjectStore(rootURL: destination)
        XCTAssertThrowsError(try PortableProject.importPackage(from: package, into: store)); XCTAssertTrue(try store.list().isEmpty)
        try valid.dropLast(7).write(to: package)
        XCTAssertThrowsError(try PortableProject.importPackage(from: package, into: store)); XCTAssertTrue(try store.list().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }
    func testPortableRejectsTraversalAbsolutePathsAndResourceLimit() throws {
        let doc = document(), source = try sourceRoot(for: doc), destination = try temporaryRoot(), packages = try temporaryRoot()
        let package = packages.appendingPathComponent("test.cutlabproject")
        try PortableProject.export(document: doc, rootURL: source, to: package)
        let valid = try Data(contentsOf: package), store = ProjectStore(rootURL: destination)
        let length = valid[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let originalHeader = try XCTUnwrap(JSONSerialization.jsonObject(with: valid[16..<(16 + Int(length))]) as? [String: Any])
        for path in ["../escape", "/tmp/escape", "Assets/../../escape", "Assets\\escape", "Assets//escape"] {
            var header = originalHeader
            var files = try XCTUnwrap(header["files"] as? [[String: Any]]); files[0]["path"] = path; header["files"] = files
            let bytes = try JSONSerialization.data(withJSONObject: header)
            var size = UInt64(bytes.count).bigEndian, malicious = Data("CFUZPK02".utf8)
            withUnsafeBytes(of: &size) { malicious.append(contentsOf: $0) }; malicious.append(bytes); malicious.append(valid.dropFirst(16 + Int(length)))
            try malicious.write(to: package)
            XCTAssertThrowsError(try PortableProject.importPackage(from: package, into: store))
        }
        try valid.write(to: package)
        XCTAssertThrowsError(try PortableProject.importPackage(from: package, into: store, limits: .init(maximumBytes: 1)))
        XCTAssertThrowsError(try PortableProject.importPackage(from: package, into: store, cancelled: { true }))
        XCTAssertTrue(try store.list().isEmpty)
    }
    func testExportRejectsSymlinkAndCancelledExportPreservesPreviousFile() throws {
        let doc = document(), source = try sourceRoot(for: doc), packages = try temporaryRoot()
        let package = packages.appendingPathComponent("keep.cutlabproject"), prior = Data("Prior result".utf8)
        try prior.write(to: package)
        XCTAssertThrowsError(try PortableProject.export(document: doc, rootURL: source, to: package, cancelled: { true }))
        XCTAssertEqual(try Data(contentsOf: package), prior)
        let original = source.appendingPathComponent(doc.assets[0].relativePath), external = packages.appendingPathComponent("outside.png")
        try FileManager.default.moveItem(at: original, to: external)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: external)
        XCTAssertThrowsError(try PortableProject.export(document: doc, rootURL: source, to: package))
        XCTAssertEqual(try Data(contentsOf: package), prior)
    }
    func testInvalidCrossReferenceAndHostileTimeAreRejectedWithoutOverflow() throws {
        var doc = document(); doc.scenes[0].clips[0].assetID = UUID()
        XCTAssertThrowsError(try doc.validate())
        doc = document(); doc.scenes[0].clips[0].duration = .init(value: Int64.max, timescale: 1)
        XCTAssertThrowsError(try doc.validate())
        doc = document(); doc.variants[0].overrides[UUID().uuidString] = Presentation()
        XCTAssertThrowsError(try doc.validate())
    }
    func testRationalTimesCombineWithoutFrameDrift() {
        let a = MediaTime(value: 1001, timescale: 24_000), b = MediaTime(value: 1001, timescale: 30_000)
        XCTAssertEqual(a + b, MediaTime(value: 9009, timescale: 120_000))
        XCTAssertEqual(MediaTime(value: 1, timescale: 30), MediaTime(value: 2000, timescale: 60_000))
        XCTAssertEqual(Set([MediaTime(value: 1, timescale: 30), MediaTime(value: 2000, timescale: 60_000)]).count, 1)
        var total = MediaTime.zero
        for _ in 0..<24_000 { total = total + a }
        XCTAssertEqual(total, MediaTime(seconds: 1001))
    }
    func testBoundCaptionsFollowSpeedSplitAndUndo() throws {
        var doc = document(); doc.assets[0].kind = .video
        let media = Clip(assetID: doc.assets[0].id, kind: .video, duration: .init(seconds: 10), sourceDuration: .init(seconds: 10))
        let caption = Clip(kind: .text, start: .init(seconds: 2), duration: .init(seconds: 6), text: "Source words", isCaption: true, captionSourceAssetID: doc.assets[0].id, captionSourceClipID: media.id, captionSourceStart: .init(seconds: 2), captionSourceEnd: .init(seconds: 8))
        doc.scenes[0].clips = [media, caption]
        let history = EditHistory(document: doc)
        try history.perform(name: "Vitesse") { document in
            try DocumentEditor.updateClip(media.id, in: &document) { $0.speed = 2; $0.duration = .init(seconds: 5) }
        }
        XCTAssertEqual(history.document.clip(caption.id)?.start, .init(seconds: 1))
        XCTAssertEqual(history.document.clip(caption.id)?.duration, .init(seconds: 3))
        history.undo(); XCTAssertEqual(history.document.scenes, doc.scenes)
        _ = try DocumentEditor.splitClip(media.id, at: .init(seconds: 5), in: &doc)
        let captions = doc.scenes[0].clips.filter(\.isCaption).sorted { $0.start < $1.start }
        XCTAssertEqual(captions.count, 2); XCTAssertEqual(captions.map(\.start), [.init(seconds: 2), .init(seconds: 5)])
        XCTAssertEqual(captions.map(\.duration), [.init(seconds: 3), .init(seconds: 3)])
        try doc.validate()
    }
    func testBoundCaptionsFollowSceneSplitAndDuplicate() throws {
        var doc = document(); doc.assets[0].kind = .video
        let media = Clip(assetID: doc.assets[0].id, kind: .video, duration: .init(seconds: 10), sourceDuration: .init(seconds: 10))
        let caption = Clip(kind: .text, start: .init(seconds: 2), duration: .init(seconds: 6), text: "Source words", isCaption: true, captionSourceAssetID: doc.assets[0].id, captionSourceClipID: media.id, captionSourceStart: .init(seconds: 2), captionSourceEnd: .init(seconds: 8))
        doc.scenes[0].clips = [media, caption]
        let second = try DocumentEditor.splitScene(doc.scenes[0].id, at: .init(seconds: 5), in: &doc)
        XCTAssertEqual(doc.scenes[0].clips.filter(\.isCaption).count, 1)
        XCTAssertEqual(doc.scenes[1].clips.filter(\.isCaption).count, 1)
        XCTAssertEqual(doc.scenes[1].clips.first(where: \.isCaption)?.start, .zero)
        _ = try DocumentEditor.duplicateScene(second, in: &doc)
        try doc.validate()
        let copied = doc.scenes[2]
        XCTAssertEqual(copied.clips.first(where: \.isCaption)?.captionSourceClipID, copied.clips.first(where: { $0.kind == .video })?.id)
    }

    func testAnimatedVariantKeepsLocalFramingAndSharedMotion() throws {
        var doc = document(); let id = doc.scenes[0].clips[0].id
        doc.scenes[0].clips[0].keyframes = [.init(time: .zero, property: .scale, value: 1), .init(time: .init(seconds: 10), property: .scale, value: 1.2), .init(time: .zero, property: .x, value: 0.5), .init(time: .init(seconds: 10), property: .x, value: 0.7)]
        var square = Presentation(); square.scale = 1.6; square.x = 0.25
        doc.variants[1].overrides[id.uuidString] = square
        let vertical = try XCTUnwrap(RenderPlan.compile(document: doc, variantID: doc.variants[0].id).clips.first { $0.id == id })
        let local = try XCTUnwrap(RenderPlan.compile(document: doc, variantID: doc.variants[1].id).clips.first { $0.id == id })
        XCTAssertEqual(vertical.evaluatedPresentation(at: .init(seconds: 5)).scale, 1.1, accuracy: 0.00001)
        XCTAssertEqual(local.evaluatedPresentation(at: .init(seconds: 5)).scale, 1.76, accuracy: 0.00001)
        XCTAssertEqual(local.evaluatedPresentation(at: .init(seconds: 5)).x, 0.35, accuracy: 0.00001)
        XCTAssertEqual(vertical.evaluatedPresentation(at: .init(seconds: 5)).x, 0.6, accuracy: 0.00001)
        _ = try DocumentEditor.splitClip(id, at: .init(seconds: 4), in: &doc)
        let right = try XCTUnwrap(RenderPlan.compile(document: doc, variantID: doc.variants[1].id).clips.first { $0.clip.kind == .image && $0.id != id })
        XCTAssertEqual(right.evaluatedPresentation(at: .init(seconds: 5)), local.evaluatedPresentation(at: .init(seconds: 5)))
    }

    func testCaptionEditingSplitMergeRetainsSourceProvenanceAndUndo() throws {
        var doc = document(); doc.assets[0].kind = .video
        let media = Clip(assetID: doc.assets[0].id, kind: .video, duration: .init(seconds: 10), sourceDuration: .init(seconds: 10))
        let caption = Clip(kind: .text, start: .init(seconds: 2), duration: .init(seconds: 6), text: "Alpha Beta", isCaption: true, captionSourceAssetID: doc.assets[0].id, captionSourceClipID: media.id, captionSourceStart: .init(seconds: 2), captionSourceEnd: .init(seconds: 8), captionAnalyzedRevision: 3)
        doc.scenes[0].clips = [media, caption]
        var local = Presentation(); local.scale = 1.3
        doc.variants[1].overrides[caption.id.uuidString] = local
        let history = EditHistory(document: doc)
        try history.perform(name: "Scinder") { _ = try CaptionEditing.split(caption.id, at: .init(seconds: 5), firstText: "Alpha", secondText: "Beta", in: &$0) }
        var cues = CaptionEditing.captions(in: history.document)
        XCTAssertEqual(cues.count, 2); XCTAssertEqual(cues.map { $0.clip.text }, ["Alpha", "Beta"])
        XCTAssertEqual(cues.map { $0.clip.captionSourceStart }, [.init(seconds: 2), .init(seconds: 5)])
        XCTAssertEqual(cues.map { $0.clip.captionSourceEnd }, [.init(seconds: 5), .init(seconds: 8)])
        XCTAssertEqual(history.document.variants[1].overrides[cues[1].id.uuidString], local)
        try history.perform(name: "Vitesse") { d in try DocumentEditor.updateClip(media.id, in: &d) { $0.speed = 2; $0.duration = .init(seconds: 5) } }
        cues = CaptionEditing.captions(in: history.document)
        XCTAssertEqual(cues.map(\.globalStart), [.init(seconds: 1), .init(seconds: 2.5)])
        let secondID = cues[1].id
        try history.perform(name: "Fusion") { _ = try CaptionEditing.merge(caption.id, with: secondID, in: &$0) }
        cues = CaptionEditing.captions(in: history.document)
        XCTAssertEqual(cues.count, 1); XCTAssertEqual(cues[0].clip.text, "Alpha\nBeta")
        XCTAssertEqual(cues[0].clip.captionSourceStart, .init(seconds: 2)); XCTAssertEqual(cues[0].clip.captionSourceEnd, .init(seconds: 8))
        XCTAssertEqual(cues[0].duration, .init(seconds: 3)); XCTAssertNil(history.document.variants[1].overrides[secondID.uuidString])
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(history.document)).scenes, history.document.scenes)
        history.undo(); history.undo(); history.undo()
        XCTAssertEqual(history.document.scenes, doc.scenes); XCTAssertEqual(history.document.variants, doc.variants)
    }
    func testCaptionTimingEditsInverseMapReversedSourceAndStyleScope() throws {
        var doc = document(); doc.assets[0].kind = .video
        let media = Clip(assetID: doc.assets[0].id, kind: .video, duration: .init(seconds: 10), sourceDuration: .init(seconds: 10), reversed: true)
        let caption = Clip(kind: .text, start: .init(seconds: 2), duration: .init(seconds: 6), text: "Initial", isCaption: true, captionSourceAssetID: doc.assets[0].id, captionSourceClipID: media.id, captionSourceStart: .init(seconds: 2), captionSourceEnd: .init(seconds: 8))
        let other = Clip(kind: .text, start: .init(seconds: 8), duration: .init(seconds: 1), text: "Other", isCaption: true)
        doc.scenes[0].clips = [media, caption, other]
        try CaptionEditing.update(caption.id, text: "Corrigé", from: .init(seconds: 1), to: .init(seconds: 3), in: &doc)
        XCTAssertEqual(doc.clip(caption.id)?.captionSourceStart, .init(seconds: 7)); XCTAssertEqual(doc.clip(caption.id)?.captionSourceEnd, .init(seconds: 9))
        XCTAssertEqual(doc.clip(caption.id)?.start, .init(seconds: 1)); XCTAssertEqual(doc.clip(caption.id)?.duration, .init(seconds: 2))
        var local = Presentation(); local.y = 0.25; local.textLetterSpacing = 0.2; local.textLineSpacing = 0.3
        let square = doc.variants[1].id
        doc.variants[1].overrides[caption.id.uuidString] = local
        try CaptionEditing.applyStyle(from: caption.id, variantID: square, in: &doc)
        XCTAssertEqual(doc.variants[1].overrides[other.id.uuidString], local)
        XCTAssertTrue(doc.variants[0].overrides.isEmpty)
        XCTAssertEqual(doc.clip(other.id)?.presentation.y, 0.5)
        XCTAssertEqual(doc.clip(other.id)?.text, "Other"); XCTAssertEqual(doc.clip(other.id)?.start, .init(seconds: 8))
        XCTAssertThrowsError(try CaptionEditing.merge(caption.id, with: other.id, in: &doc))
        try CaptionEditing.detachSource(caption.id, in: &doc)
        XCTAssertNil(doc.clip(caption.id)?.captionSourceClipID)
        _ = try CaptionEditing.merge(caption.id, with: other.id, in: &doc)
        XCTAssertEqual(doc.clip(caption.id)?.duration, .init(seconds: 8))
        try doc.validate()
    }
    func testTextSpacingDefaultsDecodeOlderPresentation() throws {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Presentation())) as? [String: Any])
        value["textLetterSpacing"] = nil; value["textLineSpacing"] = nil
        let restored = try JSONDecoder().decode(Presentation.self, from: JSONSerialization.data(withJSONObject: value))
        XCTAssertEqual(restored.textLetterSpacing, 0); XCTAssertEqual(restored.textLineSpacing, 0)
    }

    func testVariantKeyframeEditingInvertsComposedValuesAndUpdatesIdentity() throws {
        var doc = document(); let id = doc.scenes[0].clips[0].id
        var common = Presentation(); common.x = 0.4; common.y = 0.6; common.scale = 1.2; common.rotation = 10; common.opacity = 0.8
        doc.scenes[0].clips[0].presentation = common
        var square = common; square.x = 0.7; square.y = 0.3; square.scale = 1.8; square.rotation = 30; square.opacity = 0.4
        let variant = doc.variants[1].id; doc.variants[1].overrides[id.uuidString] = square
        let values: [(KeyframeProperty, Double, Double)] = [(.x, 0.8, 0.5), (.y, 0.4, 0.7), (.scale, 2.7, 1.8), (.rotation, 45, 25), (.opacity, 0.3, 0.6)]
        for (property, displayed, expected) in values {
            try AnimationEditing.upsert(clipID: id, property: property, at: .init(seconds: 3), displayedValue: displayed, variantID: variant, easing: .easeInOut, in: &doc)
            let key = try XCTUnwrap(doc.clip(id)?.keyframes.first { $0.property == property })
            XCTAssertEqual(key.value, expected, accuracy: 0.000001)
        }
        let before = doc.clip(id)!.keyframes
        let rendered = try XCTUnwrap(RenderPlan.compile(document: doc, variantID: variant).clips.first { $0.id == id })
        for (property, displayed, _) in values { XCTAssertEqual(AnimationEditing.value(property, in: rendered.evaluatedPresentation(at: .init(seconds: 3))), displayed, accuracy: 0.000001) }
        try AnimationEditing.upsertCurrentPose(clipID: id, at: .init(seconds: 3), variantID: variant, in: &doc)
        XCTAssertEqual(doc.clip(id)?.keyframes.map(\.id), before.map(\.id))
        XCTAssertTrue(doc.clip(id)!.keyframes.allSatisfy { $0.easing == .easeInOut })
        XCTAssertEqual(doc.variants[1].overrides[id.uuidString], square)
        XCTAssertTrue(doc.variants[0].overrides.isEmpty)
        let portrait = try XCTUnwrap(RenderPlan.compile(document: doc, variantID: doc.variants[0].id).clips.first { $0.id == id })
        XCTAssertEqual(portrait.evaluatedPresentation(at: .init(seconds: 3)).scale, 1.8, accuracy: 0.000001)
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(doc)), doc)
    }
    func testKeyframeNavigationAndEditingPreserveSplitAnimationDomain() throws {
        var doc = document(); let id = doc.scenes[0].clips[0].id
        doc.scenes[0].clips[0].keyframes = [
            .init(time: .zero, property: .x, value: 0.2),
            .init(time: .init(seconds: 3), property: .x, value: 0.4),
            .init(time: .init(seconds: 7), property: .x, value: 0.6),
            .init(time: .init(seconds: 7), property: .scale, value: 1.1),
            .init(time: .init(seconds: 10), property: .x, value: 0.8)]
        let second = try DocumentEditor.splitClip(id, at: .init(seconds: 5), in: &doc)
        let rendered = try XCTUnwrap(RenderPlan.compile(document: doc, variantID: nil).clips.first { $0.id == second })
        XCTAssertEqual(rendered.clip.animationOffset, .init(seconds: 5))
        XCTAssertNil(AnimationEditing.neighbor(in: rendered, from: .init(seconds: 6), forward: false))
        XCTAssertEqual(AnimationEditing.neighbor(in: rendered, from: .init(seconds: 6), forward: true), .init(seconds: 7))
        XCTAssertEqual(AnimationEditing.neighbor(in: rendered, from: .init(seconds: 7), forward: true), .init(seconds: 10))
        try AnimationEditing.upsert(clipID: second, property: .rotation, at: .init(seconds: 6), displayedValue: 22, variantID: nil, easing: .easeOut, in: &doc)
        XCTAssertEqual(doc.clip(second)?.keyframes.first { $0.property == .rotation }?.time, .init(seconds: 6))
        XCTAssertThrowsError(try AnimationEditing.upsert(clipID: second, property: .x, at: .init(seconds: 4), displayedValue: 0.5, variantID: nil, easing: .linear, in: &doc))
    }

    func testMovingKeyframePreservesIdentitySplitOffsetAndFormatConversion() throws {
        var doc = document(); let original = doc.scenes[0].clips[0].id
        doc.scenes[0].clips[0].keyframes = [.init(time: .init(seconds: 7), property: .scale, value: 1.2), .init(time: .init(seconds: 9), property: .scale, value: 1.5)]
        let second = try DocumentEditor.splitClip(original, at: .init(seconds: 5), in: &doc)
        let key = try XCTUnwrap(doc.clip(second)?.keyframes.first)
        var framed = doc.clip(second)!.presentation; framed.scale = 2
        let variant = doc.variants[1].id; doc.variants[1].overrides[second.uuidString] = framed
        let before = doc
        try AnimationEditing.move(keyframeID: key.id, clipID: second, to: .init(seconds: 8), displayedValue: 3, variantID: variant, easing: .easeOut, in: &doc)
        let edited = try XCTUnwrap(doc.clip(second)?.keyframes.first { $0.id == key.id })
        XCTAssertEqual(edited.time, .init(seconds: 8)); XCTAssertEqual(edited.value, 1.5, accuracy: 0.000001)
        XCTAssertEqual(edited.easing, .easeOut); XCTAssertEqual(doc.clip(second)?.keyframes.count, 2)
        XCTAssertEqual(doc.clip(original), before.clip(original)); XCTAssertEqual(doc.variants, before.variants)
        let rendered = try XCTUnwrap(RenderPlan.compile(document: doc, variantID: variant).clips.first { $0.id == second })
        XCTAssertEqual(rendered.evaluatedPresentation(at: .init(seconds: 8)).scale, 3, accuracy: 0.000001)
        let saved = doc
        XCTAssertThrowsError(try AnimationEditing.move(keyframeID: key.id, clipID: second, to: .init(seconds: 9), displayedValue: 2, variantID: variant, easing: .linear, in: &doc))
        XCTAssertEqual(doc, saved)
        XCTAssertThrowsError(try AnimationEditing.move(keyframeID: key.id, clipID: second, to: .init(seconds: 4), displayedValue: 2, variantID: variant, easing: .linear, in: &doc))
        XCTAssertEqual(doc, saved); try doc.validate()
        let history = EditHistory(document: before)
        try history.perform(name: "Déplacer le point") { $0 = saved }
        history.undo(); XCTAssertEqual(history.document.scenes, before.scenes)
        history.redo(); XCTAssertEqual(history.document.scenes, saved.scenes)
    }

    func testMotionAnimationPresetsCreateIntentionalZones() throws {
        let firstID = UUID(), secondID = UUID()
        let first = Clip(id: firstID, kind: .image, duration: .init(seconds: 4), sourceDuration: .init(seconds: 4))
        let second = Clip(id: secondID, kind: .image, start: .init(seconds: 4), duration: .init(seconds: 4), sourceDuration: .init(seconds: 4))
        var document = ProjectDocument(scenes: [.init(duration: .init(seconds: 8), clips: [first, second])])

        try AnimationEditing.applyPreset(.fade, zone: .entrance, clipID: firstID, in: &document)
        var edited = try XCTUnwrap(document.clip(firstID))
        let fade = edited.keyframes.filter { $0.property == .opacity }.sorted { $0.time < $1.time }
        XCTAssertEqual(fade.map(\.time), [.zero, .init(seconds: 0.6)])
        XCTAssertEqual(fade.map(\.value), [0, 1])

        try AnimationEditing.applyPreset(.slide, zone: .exit, clipID: firstID, in: &document)
        edited = try XCTUnwrap(document.clip(firstID))
        let slide = edited.keyframes.filter { $0.property == .x }.sorted { $0.time < $1.time }
        XCTAssertEqual(slide.map(\.time), [.init(seconds: 3.4), .init(seconds: 4)])
        XCTAssertEqual(slide.first?.value, 0.5)
        XCTAssertEqual(try XCTUnwrap(slide.last).value, 0.78, accuracy: 0.000_001)

        try AnimationEditing.applyPreset(.pulse, zone: .loop, clipID: firstID, in: &document)
        edited = try XCTUnwrap(document.clip(firstID))
        XCTAssertGreaterThan(edited.keyframes.filter { $0.property == .scale }.count, 4)
        XCTAssertTrue(document.clip(secondID)?.keyframes.isEmpty == true)
    }
    func testFadePresetPreservesManualKeysAndUndo() throws {
        var doc = document(); let id = doc.scenes[0].clips[0].id
        let scale = Keyframe(time: .init(seconds: 4), property: .scale, value: 1.4, easing: .easeIn)
        let opacity = Keyframe(time: .init(seconds: 5), property: .opacity, value: 0.7, easing: .easeOut)
        doc.scenes[0].clips[0].keyframes = [scale, opacity]
        let history = EditHistory(document: doc)
        try history.perform(name: "Fondu") { try AnimationEditing.applyFade(.combination, duration: .init(seconds: 2), clipID: id, in: &$0) }
        let keys = history.document.clip(id)!.keyframes
        XCTAssertTrue(keys.contains(scale)); XCTAssertTrue(keys.contains(opacity))
        XCTAssertEqual(keys.filter { $0.property == .opacity }.map(\.time).sorted(), [0, 2, 5, 8, 10].map { MediaTime(seconds: Double($0)) })
        XCTAssertEqual(keys.first { $0.time == .zero }?.value, 0)
        XCTAssertEqual(keys.first { $0.time == .init(seconds: 2) }?.value, 1)
        XCTAssertEqual(keys.first { $0.time == .init(seconds: 10) }?.value, 0)
        var invalid = history.document
        XCTAssertThrowsError(try AnimationEditing.applyFade(.combination, duration: .init(seconds: 6), clipID: id, in: &invalid))
        history.undo(); XCTAssertEqual(history.document.scenes, doc.scenes)
        var transparent = Presentation(); transparent.opacity = 0
        var visible = Presentation(); visible.opacity = 0.8
        XCTAssertEqual(try AnimationEditing.commonValue(displayed: 0.4, property: .opacity, common: transparent, variant: visible), 0.5)
        XCTAssertThrowsError(try AnimationEditing.commonValue(displayed: 0.4, property: .opacity, common: visible, variant: transparent))
    }

}
