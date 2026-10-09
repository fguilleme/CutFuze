import XCTest

final class WorkspaceUITests: XCTestCase {
    @MainActor func testVisualToolsShareOnePanelAndMaskIsDirectlyEditable() throws {
        let app = launchDemo()
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 10)); video.tap()
        app.buttons["tool-Effets visuels"].tap()
        let tabs = app.scrollViews["visualTools"]
        let panel = app.scrollViews["contextToolScroll"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["visualTool-Transformer"].isSelected)
        XCTAssertTrue(app.buttons["fitMedia"].isHittable)
        XCTAssertFalse(app.buttons["tool-Opacité"].exists)
        XCTAssertFalse(app.buttons["tool-Transformer"].exists)
        XCTAssertFalse(app.buttons["tool-Visuel"].exists)
        capture("grouped-effects-transform")
        app.buttons["visualTool-Opacité"].tap()
        let opacity = app.sliders["Opacité"]
        XCTAssertTrue(opacity.waitForExistence(timeout: 3))
        let before = opacity.value as? String
        opacity.adjust(toNormalizedSliderPosition: 0.4)
        XCTAssertNotEqual(opacity.value as? String, before)
        XCTAssertTrue(app.buttons["visualTool-Opacité"].isSelected)
        capture("grouped-effects-opacity")
        app.buttons["visualTool-Masque"].tap()
        app.buttons["mask-ellipse"].tap()
        XCTAssertTrue(app.buttons["mask-ellipse"].isSelected)
        let feather = app.sliders["Contour progressif"]
        for _ in 0..<3 where !feather.isHittable { panel.swipeUp() }
        XCTAssertTrue(feather.isHittable)
        feather.adjust(toNormalizedSliderPosition: 0.3)
        XCTAssertTrue(app.buttons["visualTool-Masque"].isHittable)
        XCTAssertTrue(app.buttons["closeContextTool"].isHittable)
        XCTAssertFalse(app.alerts["Erreur"].exists)
        capture("grouped-effects-mask-scrolled")
        app.buttons["visualTool-Géométrie"].tap()
        XCTAssertTrue(app.buttons["effect-bulge"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["visualTool-Géométrie"].isSelected)
        capture("grouped-effects-geometry")
        app.buttons["visualTool-Masque"].tap()
        XCTAssertTrue(app.buttons["mask-ellipse"].isSelected)
        XCTAssertTrue(app.buttons["mask-ellipse"].isHittable)
        app.buttons["mask-none"].tap()
        XCTAssertTrue(app.buttons["mask-none"].isSelected)
        app.buttons["Annuler la modification"].tap()
        XCTAssertTrue(app.buttons["mask-ellipse"].isSelected)
    }

    @MainActor func testVisualEffectEditorSharesGraphDraftUndoAndApply() throws {
        let app = launchDemo()
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 10)); video.tap()
        app.buttons["tool-Effets visuels"].tap()
        app.buttons["visualTool-Géométrie"].tap(); app.buttons["effect-bulge"].tap()
        XCTAssertTrue(app.buttons["effectApply"].waitForExistence(timeout: 5))
        let scrub = app.sliders["keyframeTimeSlider"]
        XCTAssertTrue(scrub.exists)
        let points = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-"))
        XCTAssertEqual(points.count, 0)
        app.buttons["effectSaveKeyframe"].tap()
        XCTAssertEqual(points.count, 1)
        let initialTime = app.staticTexts["keyframeLocalTime"].label
        scrub.adjust(toNormalizedSliderPosition: 0.7)
        XCTAssertTrue(waitForLabel(app.staticTexts["keyframeLocalTime"], equals: initialTime, matching: false))
        // Put the second point well away from the first, using the graph's own
        // scrub gesture rather than assuming XCTest's slider drag is exact.
        app.descendants(matching: .any)["keyframeGraph"].coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.3)).tap()
        app.buttons["effectSaveKeyframe"].tap()
        XCTAssertEqual(points.count, 2)
        let first = points.firstMatch; first.tap()
        XCTAssertTrue(first.isSelected)
        let before = first.label
        let center = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 45, dy: -15)))
        XCTAssertTrue(waitForLabel(first, equals: before, matching: false))
        XCTAssertFalse(app.descendants(matching: .any)["effectEditorError"].exists)
        capture("effect-curve-point-moved")
        app.buttons["effectUndo"].tap()
        XCTAssertTrue(waitForLabel(first, equals: before))
        app.buttons["effectRedo"].tap()
        XCTAssertTrue(waitForLabel(first, equals: before, matching: false))
        app.buttons["zoomKeyframeGraph"].tap()
        app.buttons["Point suivant"].tap()
        points.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["effectDeleteKeyframe"].isHittable)
        app.buttons["effectDeleteKeyframe"].tap(); XCTAssertEqual(points.count, 1)
        app.buttons["effectUndo"].tap(); XCTAssertEqual(points.count, 2)
        capture("effect-curve-zoomed")
        let limit = app.switches["effectLimitRange"]
        let settings = app.descendants(matching: .any)["effectSettings"]
        for _ in 0..<2 where !limit.exists { settings.swipeUp() }
        XCTAssertTrue(limit.exists)
        // SwiftUI exposes both the labelled row and the actual UISwitch.
        limit.switches.firstMatch.tap()
        XCTAssertTrue(app.sliders["Début"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Fin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["effectApply"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["keyframeGraph"].isHittable)
        capture("effect-curve-range")
        app.buttons["effectUndo"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: limit)], timeout: 4), .completed)
        app.buttons["effectApply"].tap()
        XCTAssertFalse(app.buttons["effectApply"].exists)
        app.buttons["effect-bulge"].tap()
        XCTAssertTrue(app.buttons["effectApply"].waitForExistence(timeout: 5)); XCTAssertEqual(points.count, 2)
        points.firstMatch.tap()
        app.buttons["effectDeleteKeyframe"].tap(); XCTAssertEqual(points.count, 1)
        app.buttons["effectCancel"].tap()
        app.buttons["effect-bulge"].tap()
        XCTAssertTrue(app.buttons["effectApply"].waitForExistence(timeout: 5)); XCTAssertEqual(points.count, 2)
        capture("effect-curve-reopened")
    }
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testPauseDoesNotPresentCancellationError() throws {
        let app = launchDemo()
        let playback = app.buttons["play"]
        XCTAssertTrue(playback.waitForExistence(timeout: 10))
        playback.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        playback.tap()
        XCTAssertTrue(app.buttons["Lire"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Erreur"].waitForExistence(timeout: 1))
    }

    @MainActor func testFullScreenPreviewPlaybackAndDismissal() throws {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["fullScreenPreview"].waitForExistence(timeout: 10))
        app.buttons["fullScreenPreview"].tap()
        XCTAssertTrue(app.buttons["closeFullScreenPreview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fullScreenPlay"].exists)
        capture("fullscreen-preview")
        app.buttons["fullScreenPlay"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        app.buttons["closeFullScreenPreview"].tap()
        XCTAssertTrue(app.buttons["fullScreenPreview"].waitForExistence(timeout: 5))
    }

    @MainActor func testContextualToolbarTracksVideoTextAudioAndEmptySelection() throws {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["addMedia"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Audio"].exists)
        XCTAssertTrue(app.buttons["Texte"].exists)
        XCTAssertTrue(app.buttons["Overlay"].exists)
        XCTAssertTrue(app.buttons["Effets"].exists)
        XCTAssertTrue(app.buttons["formatTool"].exists)

        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 5)); video.tap()
        XCTAssertTrue(app.buttons["action-Split"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tool-Vitesse"].exists)
        XCTAssertTrue(app.buttons["tool-Effets visuels"].exists)
        capture("editor-video-selection")

        let text = firstTimelineClip(app, kind: "text")
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap()
        XCTAssertTrue(app.buttons["tool-Modifier"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tool-Style"].exists)
        XCTAssertTrue(app.buttons["tool-Police"].exists)
        capture("editor-text-selection")

        let audio = firstTimelineClip(app, kind: "audio")
        XCTAssertTrue(audio.waitForExistence(timeout: 5)); audio.tap()
        XCTAssertTrue(app.buttons["tool-Volume"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tool-Fondu"].exists)
        capture("editor-audio-selection")

        let timeline = app.scrollViews["timelineScroll"]
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.05)).tap()
        XCTAssertTrue(app.buttons["addMedia"].waitForExistence(timeout: 3))
    }

    @MainActor func testSelectedMediaCutoutIsReachableAndUndoable() throws {
        let app = launchDemo()
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.tap()

        let cutout = app.buttons["action-RemoveBackground"]
        XCTAssertTrue(cutout.waitForExistence(timeout: 3))
        XCTAssertFalse(cutout.isSelected)
        cutout.tap()
        XCTAssertTrue(cutout.isSelected)
        XCTAssertTrue(app.buttons["Annuler la modification"].isEnabled)
        capture("selected-media-cutout")

        app.buttons["Annuler la modification"].tap()
        XCTAssertFalse(cutout.isSelected)
    }

    @MainActor func testAnimationPresetsAndEffectFamiliesAreClear() throws {
        let app = launchDemo()
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.tap()

        app.buttons["tool-Animation"].tap()
        XCTAssertTrue(app.segmentedControls["animationZone"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["animationPreset-fade"].exists)
        XCTAssertTrue(app.buttons["animationPreset-zoom"].exists)
        app.buttons["Boucle"].tap()
        XCTAssertTrue(app.buttons["animationPreset-float"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["animationPreset-pulse"].exists)
        capture("animation-presets")
        app.buttons["closeContextTool"].tap()

        app.buttons["tool-Effets visuels"].tap()
        app.buttons["visualTool-Beauté"].tap()
        XCTAssertTrue(app.buttons["visualTool-Beauté"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["closeContextTool"].isHittable)
        XCTAssertTrue(app.buttons["effect-skinSmooth"].exists)
        app.buttons["visualTool-Géométrie"].tap()
        XCTAssertTrue(app.buttons["effect-bulge"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["effect-kaleidoscope"].exists)
        capture("effect-families")
        app.buttons["closeContextTool"].tap()
        XCTAssertFalse(app.buttons["visualTool-Géométrie"].exists)
    }

    @MainActor func testVisualKeyframeEditorSelectsMovesScrubsAndUndoes() throws {
        let app = launchDemo()
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 10)); video.tap()
        app.buttons["tool-Animation"].tap()
        app.buttons["animationPreset-zoom"].tap()
        app.buttons["advancedAnimation"].tap()
        XCTAssertTrue(app.sliders["keyframeTimeSlider"].waitForExistence(timeout: 5))
        let graph = app.descendants(matching: .any)["keyframeGraph"]
        XCTAssertTrue(graph.exists)
        capture("animation-curve-overview")
        app.buttons["zoomKeyframeGraph"].tap()
        app.buttons["zoomKeyframeGraph"].tap()
        let point = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).firstMatch
        XCTAssertTrue(point.waitForExistence(timeout: 3))
        point.tap()
        XCTAssertTrue(point.isSelected)
        capture("animation-curve-point-selected")
        let original = point.label
        let center = point.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 55, dy: -10)))
        XCTAssertNotEqual(point.label, original)
        XCTAssertFalse(app.alerts["Erreur"].exists)
        capture("animation-point-moved")
        app.buttons["keyframeUndo"].tap()
        XCTAssertTrue(waitForLabel(point, equals: original))
        let beforeTime = app.staticTexts["keyframeLocalTime"].label
        app.sliders["keyframeTimeSlider"].adjust(toNormalizedSliderPosition: 0.55)
        XCTAssertNotEqual(app.staticTexts["keyframeLocalTime"].label, beforeTime)
        app.buttons["keyframeProperty-opacity"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).count, 0)
        app.buttons["saveKeyframe"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).count, 1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).firstMatch.isHittable)
        capture("animation-opacity-new-point")
        app.buttons["deleteSelectedKeyframe"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).count, 0)
        app.buttons["keyframeUndo"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).count, 1)
        app.buttons["keyframeRedo"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).count, 0)
    }

    @MainActor func testTimelineSplitProducesUndoAndCompactSpeedPanel() throws {
        let app = launchDemo()
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 10)); video.tap()

        app.buttons["tool-Vitesse"].tap()
        XCTAssertTrue(app.buttons["closeContextTool"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["Vitesse"].exists)
        capture("editor-speed-panel")
        app.buttons["closeContextTool"].tap()

        app.buttons["play"].tap()
        Thread.sleep(forTimeInterval: 0.35)
        app.buttons["play"].tap()
        app.buttons["action-Split"].tap()
        let undo = app.buttons["Annuler la modification"]
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
    }

    @MainActor func testSelectingAudioPreservesPlayheadForSplit() throws {
        let app = launchDemo()
        let play = app.buttons["play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        Thread.sleep(forTimeInterval: 1.2)
        play.tap()

        let timecode = app.staticTexts["currentTimecode"]
        XCTAssertTrue(timecode.waitForExistence(timeout: 3))
        let before = timecode.label
        XCTAssertNotEqual(before, "00:00")

        let audio = firstTimelineClip(app, kind: "audio")
        XCTAssertTrue(audio.waitForExistence(timeout: 3))
        audio.tap()

        XCTAssertEqual(timecode.label, before)
        XCTAssertTrue(app.buttons["action-Split"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts["Erreur"].exists)
        capture("audio-selection-keeps-playhead")
    }

    @MainActor func testCaptionTrackDragAndExpressiveFontGallery() throws {
        let app = launchDemo()
        let timeline = app.scrollViews["timelineScroll"]
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.03)).tap()
        let caption = firstTimelineClip(app, kind: "caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 5)); caption.tap()
        let scope = app.segmentedControls["captionScope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 3))
        scope.buttons["Toute la piste"].tap()
        let selection = app.otherElements["previewSelectionFrame"]
        XCTAssertTrue(selection.waitForExistence(timeout: 3))
        let before = selection.frame.midY
        let center = selection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -30)))
        XCTAssertLessThan(selection.frame.midY, before - 12)
        XCTAssertTrue(app.buttons["Annuler la modification"].isEnabled)
        capture("caption-track-position")

        app.buttons["tool-Police"].tap()
        let impact = app.buttons["fontChoice-AvenirNextCondensed-Heavy"]
        XCTAssertTrue(impact.waitForExistence(timeout: 3)); impact.tap()
        XCTAssertTrue(impact.isSelected)
        XCTAssertTrue(scope.buttons["Toute la piste"].isSelected)
        XCTAssertFalse(app.alerts["Erreur"].exists)
        capture("expressive-font-gallery")
        app.buttons["fontCategory-Manuscrites"].tap()
        XCTAssertTrue(app.buttons["fontChoice-MarkerFelt-Wide"].waitForExistence(timeout: 3))
        capture("handwritten-font-gallery")
    }

    @MainActor func testCaptionListOffersFontGalleryAndSharedTrackScope() throws {
        let app = launchDemo()
        let caption = firstTimelineClip(app, kind: "caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 10)); caption.tap()
        app.buttons["action-EditCaptions"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["captionTextField"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Police"].tap()
        let scope = try XCTUnwrap(app.segmentedControls.matching(identifier: "captionScope").allElementsBoundByIndex.first { $0.isHittable })
        scope.buttons["Toute la piste"].tap()
        app.buttons["fontCategory-Manuscrites"].tap()
        let font = app.buttons["fontChoice-MarkerFelt-Wide"]
        XCTAssertTrue(font.waitForExistence(timeout: 3)); font.tap()
        XCTAssertTrue(font.isSelected); XCTAssertTrue(scope.buttons["Toute la piste"].isSelected)
        XCTAssertTrue(font.isHittable)
        capture("caption-list-handwritten-fonts")
    }

    @MainActor func testTimelineHandlesTrimAndTransformControlsRemainReachable() throws {
        let app = launchDemo()
        // Keep the actual clip end inside the viewport. At the default zoom the
        // accessibility frame can be clipped by the right edge of the timeline.
        app.buttons["Réduire le zoom temporel"].tap()
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.tap()

        let trailing = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "timelineTrimTrailing-"))
            .firstMatch
        XCTAssertTrue(trailing.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(trailing.frame.width, 44)
        let widthBefore = video.frame.width
        let trailingFrame = trailing.frame
        let trailingCenter = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: trailingFrame.midX, dy: trailingFrame.midY))
        trailingCenter.press(forDuration: 0.05, thenDragTo: trailingCenter.withOffset(CGVector(dx: -30, dy: 0)))
        XCTAssertLessThan(video.frame.width, widthBefore - 12)

        app.buttons["tool-Effets visuels"].tap()
        XCTAssertTrue(app.buttons["visualTool-Transformer"].waitForExistence(timeout: 3))
        let panel = app.scrollViews["contextToolScroll"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        // Start on the label, not on a slider: a slider consumes that drag.
        let scrollStart = app.staticTexts["Horizontal"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollStart.withOffset(CGVector(dx: 0, dy: -105)))
        XCTAssertTrue(app.sliders["Horizontal"].exists)
        let rotation = app.sliders["Rotation"]
        XCTAssertTrue(rotation.exists)
        capture("timeline-trim-transform-scroll")
        XCTAssertTrue(panel.frame.intersects(rotation.frame))
        XCTAssertTrue(rotation.isHittable)
    }

    @MainActor func testTimelineClipCanMoveIntoEarlierScene() throws {
        let app = launchDemo()
        app.buttons["Réduire le zoom temporel"].tap()
        app.buttons["Réduire le zoom temporel"].tap()

        let videos = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timelineClip-video-"))
        XCTAssertGreaterThanOrEqual(videos.count, 2)
        let clip = videos.element(boundBy: 1)
        XCTAssertTrue(clip.waitForExistence(timeout: 5))
        let identifier = clip.identifier
        let before = clip.frame.minX
        let center = clip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.55, thenDragTo: center.withOffset(CGVector(dx: -90, dy: 0)))

        let moved = app.buttons[identifier]
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        XCTAssertLessThan(moved.frame.minX, before - 45)
        XCTAssertFalse(app.alerts["Erreur"].exists)
        XCTAssertTrue(app.buttons["Annuler la modification"].isEnabled)
        capture("timeline-move-earlier")
    }

    @MainActor func testFitAndFillUpdateSelectedState() throws {
        let app = launchDemo()
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.tap()
        app.buttons["tool-Effets visuels"].tap()

        let fit = app.buttons["fitMedia"]
        let fill = app.buttons["fillMedia"]
        XCTAssertTrue(fit.waitForExistence(timeout: 3))
        XCTAssertTrue(fill.exists)
        XCTAssertLessThanOrEqual(fit.frame.width, 70)
        XCTAssertLessThanOrEqual(fill.frame.width, 70)
        XCTAssertLessThanOrEqual(fit.frame.height, 44)
        XCTAssertLessThanOrEqual(fill.frame.height, 44)
        fit.tap()
        XCTAssertTrue(fit.isSelected)
        XCTAssertFalse(fill.isSelected)
        fill.tap()
        XCTAssertTrue(fill.isSelected)
        XCTAssertTrue(app.buttons["Annuler la modification"].isEnabled)
        capture("fit-fill-working")
    }

    @MainActor func testTextKeyboardDoesNotMoveTimelineAndStoryIsSecondary() throws {
        let app = launchDemo()
        let text = firstTimelineClip(app, kind: "text")
        XCTAssertTrue(text.waitForExistence(timeout: 10)); text.tap()
        app.buttons["tool-Modifier"].tap()
        let field = app.descendants(matching: .any)["layerTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let timelineTop = app.buttons["timelineStart"].frame.minY
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["timelineStart"].frame.minY, timelineTop, accuracy: 2)
        app.buttons["Terminé"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        app.buttons["closeContextTool"].tap()
        app.buttons["openStory"].tap()
        XCTAssertTrue(app.buttons["closeStory"].waitForExistence(timeout: 5))
        capture("editor-story-secondary")
        app.buttons["closeStory"].tap()
        XCTAssertTrue(app.scrollViews["timelineScroll"].waitForExistence(timeout: 5))
    }

    @MainActor func testViewerTimelineDividerResizesBothZones() throws {
        let app = launchDemo()
        let divider = app.otherElements["viewerTimelineDivider"]
        XCTAssertTrue(divider.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(divider.frame.height, 20)
        let before = app.buttons["timelineStart"].frame.minY
        let origin = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = origin.withOffset(CGVector(dx: 0, dy: 70))
        origin.press(forDuration: 0.05, thenDragTo: destination)
        let after = app.buttons["timelineStart"].frame.minY
        XCTAssertGreaterThan(after, before + 15)
        capture("viewer-height-resized")
    }

    @MainActor func testPreviewTapSelectsTopmostTextAndDragMovesIt() throws {
        let app = launchDemo()
        let caption = firstTimelineClip(app, kind: "caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        caption.tap()

        let canvas = app.otherElements["previewCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.29)).tap()

        let selection = app.otherElements["previewSelectionFrame"]
        XCTAssertTrue(selection.waitForExistence(timeout: 3))
        XCTAssertEqual(selection.label, "Lever les yeux")
        XCTAssertTrue(app.buttons["Supprimer"].exists)
        XCTAssertTrue(app.buttons["Faire pivoter"].exists)
        XCTAssertTrue(app.buttons["Redimensionner"].exists)
        let before = selection.frame.midX
        let start = selection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 36, dy: 18)))
        XCTAssertGreaterThan(selection.frame.midX, before + 15)
        XCTAssertTrue(app.buttons["Annuler la modification"].isEnabled)
        capture("preview-direct-manipulation")
    }

    @MainActor func testPreviewVideoDragDoesNotShowErrorAndHandlesStayTappable() throws {
        let app = launchDemo()
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.tap()

        let selection = app.otherElements["previewSelectionFrame"]
        XCTAssertTrue(selection.waitForExistence(timeout: 3))
        let delete = app.buttons["Supprimer"]
        let edit = app.buttons["Modifier"]
        XCTAssertTrue(delete.isHittable)
        XCTAssertTrue(edit.isHittable)
        XCTAssertLessThanOrEqual(delete.frame.width, 44)
        XCTAssertLessThanOrEqual(edit.frame.width, 44)

        let before = selection.frame.midX
        let start = selection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 28, dy: 0)))
        XCTAssertGreaterThan(selection.frame.midX, before + 10)
        XCTAssertFalse(app.alerts["Erreur"].waitForExistence(timeout: 1))

        edit.tap()
        XCTAssertTrue(app.buttons["fitMedia"].waitForExistence(timeout: 3))
        capture("preview-video-drag-controls")
    }

    @MainActor func testCaptionTapSelectsAndLongPressOffersBothDeletionScopes() throws {
        let app = launchDemo()
        let caption = firstTimelineClip(app, kind: "caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        caption.tap()
        XCTAssertTrue(app.buttons["action-EditCaptions"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Modifier ce segment"].waitForExistence(timeout: 1))

        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        caption.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Supprimer ce segment"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Supprimer toute la piste"].exists)
    }

    @MainActor func testTextStylePanelFitsCompactViewport() throws {
        let app = launchDemo()
        let caption = firstTimelineClip(app, kind: "caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        caption.tap()
        XCTAssertTrue(app.buttons["tool-Style"].waitForExistence(timeout: 3))
        app.buttons["tool-Style"].tap()

        let size = app.staticTexts["textSizeValue"]
        let outline = app.sliders["Contour"]
        let background = app.sliders["Fond"]
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        XCTAssertFalse(app.sliders["Taille"].exists)
        XCTAssertTrue(size.label.hasSuffix(" pt"))
        XCTAssertFalse(size.label.contains("%"))
        XCTAssertTrue(outline.exists)
        XCTAssertTrue(background.exists)
        XCTAssertLessThan(background.frame.maxX, app.frame.maxX - 8)
        XCTAssertGreaterThanOrEqual(outline.frame.minX, 0)
        let before = size.label
        app.buttons["increase-Taille"].tap()
        XCTAssertNotEqual(size.label, before)
        capture("editor-text-style-compact")
    }

    @MainActor func testCaptionEditorKeepsEditingAboveKeyboardAndChangesSize() throws {
        let app = launchDemo()
        let caption = firstTimelineClip(app, kind: "caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        caption.tap()
        XCTAssertTrue(app.buttons["action-EditCaptions"].waitForExistence(timeout: 3))
        app.buttons["action-EditCaptions"].tap()

        let field = app.descendants(matching: .any)["captionTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Style"].tap()
        let size = app.staticTexts["textSizeValue"]
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        XCTAssertFalse(app.sliders["Taille"].exists)
        XCTAssertTrue(size.label.hasSuffix(" pt"))
        XCTAssertFalse(size.label.contains("%"))
        let before = size.label
        app.buttons["increase-Taille"].tap()
        XCTAssertNotEqual(size.label, before)
        capture("caption-editor-style")

        app.segmentedControls.buttons["Texte"].tap()
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editCaption-")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()
        let originalText = field.value as? String
        app.typeText(" test")
        XCTAssertNotEqual(field.value as? String, originalText)
        if app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            capture("caption-editor-keyboard")
            app.buttons["Terminé"].tap()
        } else {
            // A physical device may have a hardware keyboard connected. Typing above
            // proves focus; the compact editor must still stay in the upper viewport.
            XCTAssertLessThan(field.frame.maxY, app.frame.height * 0.45)
            capture("caption-editor-hardware-keyboard")
        }
    }

    @MainActor func testPrimaryEditorStatesFormatImportAndExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["openDemo"].waitForExistence(timeout: 10))
        capture("01-library")
        app.buttons["openDemo"].tap()
        XCTAssertTrue(app.scrollViews["timelineScroll"].waitForExistence(timeout: 10))
        capture("02-timeline-default")

        app.buttons["formatTool"].tap()
        let compare = app.buttons["Comparer les formats"]
        XCTAssertTrue(compare.waitForExistence(timeout: 3)); compare.tap()
        capture("03-format-comparison")
        app.buttons["closeComparison"].tap()

        app.buttons["export"].tap(); XCTAssertTrue(app.buttons["closeExport"].waitForExistence(timeout: 5))
        capture("04-export-settings")
        app.buttons["closeExport"].tap()

        app.buttons["addMedia"].tap(); app.buttons["Ressources locales"].tap()
        let resource = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "resource-")).firstMatch
        XCTAssertTrue(resource.waitForExistence(timeout: 5)); resource.tap()
        XCTAssertTrue(app.buttons["Ajouter"].waitForExistence(timeout: 15))
        capture("05-import-review")
        app.buttons["Annuler"].tap()
    }

    @MainActor private func launchDemo() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["openDemo"].waitForExistence(timeout: 10))
        app.buttons["openDemo"].tap()
        XCTAssertTrue(app.scrollViews["timelineScroll"].waitForExistence(timeout: 10))
        return app
    }

    private func firstTimelineClip(_ app: XCUIApplication, kind: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timelineClip-\(kind)-")).firstMatch
    }

    private func waitForLabel(_ element: XCUIElement, equals label: String, matching: Bool = true) -> Bool {
        let predicate = NSPredicate(format: matching ? "label == %@" : "label != %@", label)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 4) == .completed
    }

    @MainActor private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.35)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
