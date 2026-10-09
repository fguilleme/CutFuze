import XCTest

/// Captures real interface states using only CutFuze's original demo media.
/// Run on dedicated simulators; never on a user's working project.
final class AppStoreScreenshotTests: XCTestCase {
    @MainActor func testFrenchAppStoreScreenshots() throws { try captureSet(language: "fr") }
    @MainActor func testEnglishAppStoreScreenshots() throws { try captureSet(language: "en") }

    @MainActor private func captureSet(language: String) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "fr" ? "fr_FR" : "en_US", "-reversedLayout", "NO", "--demo"]
        app.launch()
        XCTAssertTrue(app.scrollViews["timelineScroll"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["export"].label, language == "fr" ? "Exporter" : "Export")
        if app.frame.width > 800 {
            // Use the normal editor divider to give the portrait iPad preview more space.
            let divider = app.descendants(matching: .any)["viewerTimelineDivider"].firstMatch
            XCTAssertTrue(divider.isHittable)
            let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 290)))
            let height = Int((divider.value as? String ?? "").split(separator: " ").first ?? "0") ?? 0
            XCTAssertGreaterThan(height, 500)
        }
        // Play the actual montage so the title and caption are visible in the viewer.
        app.buttons["play"].tap()
        let clock = app.staticTexts["currentTimecode"]
        let advanced = NSPredicate { _, _ in clock.label != "00:00" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advanced, object: app)], timeout: 10), .completed)
        Thread.sleep(forTimeInterval: 1)
        app.buttons["play"].tap()
        capture("\(language)-01-montage")

        app.buttons["export"].tap()
        XCTAssertTrue(app.buttons["closeExport"].waitForExistence(timeout: 5))
        capture("\(language)-05-multiformat")
        app.buttons["closeExport"].tap()

        let caption = clip(app, kind: "caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 5)); caption.tap()
        app.buttons["tool-Police"].tap()
        XCTAssertTrue(app.buttons["fontCategory-Expressives"].waitForExistence(timeout: 5))
        app.buttons["fontCategory-Expressives"].tap()
        app.buttons["fontChoice-AvenirNextCondensed-Heavy"].tap()
        capture("\(language)-02-texte")
        app.buttons["closeContextTool"].tap()

        let video = clip(app, kind: "video")
        XCTAssertTrue(video.exists); video.tap()
        app.buttons["tool-Effets visuels"].tap()
        app.buttons["visualTool-Géométrie"].tap()
        XCTAssertTrue(app.buttons["effect-bulge"].waitForExistence(timeout: 5))
        capture("\(language)-03-effets")
        app.buttons["closeContextTool"].tap()

        app.buttons["tool-Animation"].tap()
        app.buttons["animationPreset-zoom"].tap()
        app.buttons["advancedAnimation"].tap()
        XCTAssertTrue(app.sliders["keyframeTimeSlider"].waitForExistence(timeout: 5))
        app.sliders["keyframeTimeSlider"].adjust(toNormalizedSliderPosition: 0.3)
        XCTAssertTrue(app.descendants(matching: .any)["keyframeGraph"].exists)
        capture("\(language)-04-animation")
        app.navigationBars.buttons[language == "fr" ? "Fermer" : "Close"].tap()
        app.buttons["closeContextTool"].tap()
        app.buttons["editorBack"].tap()

        let templates = app.buttons[language == "fr" ? "Modèles" : "Templates"]
        for _ in 0..<8 where !templates.isHittable { app.swipeUp() }
        XCTAssertTrue(templates.isHittable); templates.tap()
        app.staticTexts[language == "fr" ? "Une voix, une idée" : "One voice, one idea"].tap()
        XCTAssertTrue(app.staticTexts[language == "fr" ? "Voici mon idée" : "Here is my idea"].waitForExistence(timeout: 15))
        capture("\(language)-06-modeles")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
    }

    private func clip(_ app: XCUIApplication, kind: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timelineClip-\(kind)-")).firstMatch
    }

    @MainActor private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
