import XCTest

final class WorkspaceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testPauseDoesNotPresentCancellationError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["openDemo"].waitForExistence(timeout: 10))
        app.buttons["openDemo"].tap()
        let playback = app.buttons["play"]
        XCTAssertTrue(playback.waitForExistence(timeout: 10))
        playback.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        playback.tap()
        XCTAssertTrue(app.buttons["Lire"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Erreur"].waitForExistence(timeout: 1))
    }

    @MainActor func testFullScreenPreviewPlaybackAndDismissal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["openDemo"].waitForExistence(timeout: 10))
        app.buttons["openDemo"].tap()
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

    @MainActor func testLayerTextFieldShowsKeyboardWithoutMovingEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["openDemo"].waitForExistence(timeout: 10))
        app.buttons["openDemo"].tap()
        XCTAssertTrue(app.buttons["Texte"].waitForExistence(timeout: 10))
        app.buttons["Texte"].tap()
        if app.buttons["Texte libre"].waitForExistence(timeout: 2) { app.buttons["Texte libre"].tap() }
        let field = app.descendants(matching: .any)["layerTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let editorTop = app.buttons["Scénario"].frame.minY
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Scénario"].frame.minY, editorTop, accuracy: 2)
        XCTAssertTrue(app.buttons["Terminé"].waitForExistence(timeout: 2))
        app.buttons["Terminé"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["collapseEditingArea"].exists)
        app.buttons["Scénario"].tap()
        XCTAssertTrue(app.buttons["collapseEditingArea"].waitForExistence(timeout: 2))
        app.buttons["collapseEditingArea"].tap()
        XCTAssertFalse(app.buttons["collapseEditingArea"].exists)
    }

    @MainActor func testLibraryStoryTimelineVariantsUndoReopenAndLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["openDemo"].waitForExistence(timeout: 10))
        capture("01-library")
        app.buttons["openDemo"].tap()
        XCTAssertTrue(app.buttons["Timeline"].waitForExistence(timeout: 10))
        capture("02-story")
        // Reorder via the actual scene contextual menu, keeping the project music visible.
        let second = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "02, Trouver son rythme")).firstMatch
        XCTAssertTrue(second.exists)
        app.buttons["sceneMenu-1"].tap()
        let earlier = app.buttons["Déplacer avant"].exists ? app.buttons["Déplacer avant"] : app.buttons["Move earlier"]
        XCTAssertTrue(earlier.waitForExistence(timeout: 3)); earlier.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "01, Trouver son rythme")).firstMatch.waitForExistence(timeout: 3))
        let undo = app.buttons["Annuler la modification"].exists ? app.buttons["Annuler la modification"] : app.buttons["Undo edit"]
        XCTAssertTrue(undo.isEnabled); undo.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "01, Lever les yeux")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Timeline"].tap()
        capture("03-timeline")
        let square = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Carré")).firstMatch
        XCTAssertTrue(square.exists); square.tap()
        app.buttons["Image"].tap()
        capture("04-square-inspector")
        // A real image drag creates one document transaction in the active output variant.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.24)))
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        let redo = app.buttons["Rétablir"].exists ? app.buttons["Rétablir"] : app.buttons["Redo"]
        XCTAssertTrue(redo.isEnabled); redo.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.2)
        capture("05-landscape")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.2)
        if app.buttons["closeInspector"].exists { app.buttons["closeInspector"].tap() } // close inspector
        let compare = app.buttons["Comparer les formats"].exists ? app.buttons["Comparer les formats"] : app.buttons["Compare formats"]
        compare.tap(); capture("06-variants")
        let close = app.buttons["closeComparison"]
        close.tap()
        app.buttons["export"].tap()
        capture("07-export-settings")
        app.buttons["closeExport"].tap()
        app.buttons["editorBack"].tap()
        XCTAssertTrue(app.buttons["newProject"].waitForExistence(timeout: 5))
        let project = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Trente secondes de lumière")).firstMatch
        XCTAssertTrue(project.exists); project.tap()
        XCTAssertTrue(app.buttons["Timeline"].waitForExistence(timeout: 5))
        capture("08-reopened")
        app.buttons["addMedia"].tap()
        app.buttons["Ressources locales"].tap()
        let resource = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "resource-")).firstMatch
        XCTAssertTrue(resource.waitForExistence(timeout: 5)); resource.tap()
        XCTAssertTrue(app.buttons["Insérer"].waitForExistence(timeout: 10))
        capture("09-import-review")
        app.buttons["Annuler"].tap()
        app.buttons["Texte"].tap()
        app.buttons["Modifier les sous-titres"].tap()
        XCTAssertTrue(app.buttons["closeCaptions"].waitForExistence(timeout: 5))
        capture("10-captions")
        let saveCaption = app.buttons["saveCaption"]
        for _ in 0..<5 { if saveCaption.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(saveCaption.isHittable)
        capture("10b-caption-editor")
        app.buttons["closeCaptions"].tap()
        if app.buttons["closeInspector"].exists { app.buttons["closeInspector"].tap() }
        app.buttons["export"].tap()
        let package = app.buttons["Exporter le projet complet"]
        for _ in 0..<4 { if package.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(package.isHittable); package.tap()
        let file = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ".cutlabproject")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        capture("11-portable-project")
        app.buttons["closeExport"].tap()
    }
    @MainActor private func capture(_ name: String) { Thread.sleep(forTimeInterval: 0.3); let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
}
