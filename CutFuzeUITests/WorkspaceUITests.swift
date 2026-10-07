import XCTest

final class WorkspaceUITests: XCTestCase {
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
        XCTAssertTrue(app.buttons["tool-Ajuster"].exists)
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

        let size = app.sliders["Taille"]
        let outline = app.sliders["Contour"]
        let background = app.sliders["Fond"]
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        XCTAssertTrue(outline.exists)
        XCTAssertTrue(background.exists)
        XCTAssertLessThan(background.frame.maxX, app.frame.maxX - 8)
        XCTAssertGreaterThanOrEqual(outline.frame.minX, 0)
        let before = size.value as? String
        app.buttons["increase-Taille"].tap()
        XCTAssertNotEqual(size.value as? String, before)
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
        let size = app.sliders["Taille"]
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        let before = size.value as? String
        app.buttons["increase-Taille"].tap()
        XCTAssertNotEqual(size.value as? String, before)
        capture("caption-editor-style")

        app.segmentedControls.buttons["Texte"].tap()
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editCaption-")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        capture("caption-editor-keyboard")
        app.buttons["Terminé"].tap()
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

    @MainActor private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.35)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
