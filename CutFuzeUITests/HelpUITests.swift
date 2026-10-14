import XCTest

final class HelpUITests: XCTestCase {
    @MainActor func testOfflineHelpOpensTutorialGuideAndContentsInBothLanguages() {
        continueAfterFailure = false
        for language in ["fr", "en"] {
            let french = language == "fr"
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "-AppleLanguages", "(\(language))", "-AppleLocale", french ? "fr_FR" : "en_US"]
            app.launch()
            XCTAssertTrue(app.buttons["editorHelp"].waitForExistence(timeout: 20))
            app.buttons["editorHelp"].tap()
            let title = french ? "Votre première vidéo" : "Your first video"
            XCTAssertTrue(app.buttons["tutorialNext"].waitForExistence(timeout: 5))
            for _ in 0..<6 where !app.staticTexts[title].exists && app.buttons["tutorialPrevious"].exists {
                app.buttons["tutorialPrevious"].tap()
            }
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
            app.buttons["tutorialNext"].tap()
            let firstStep = french ? "1. Choisissez votre vidéo" : "1. Choose your video"
            XCTAssertTrue(app.staticTexts[firstStep].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["tutorialProgress"].label, french ? "Étape 1 sur 6" : "Step 1 of 6")
            let tutorial = XCTAttachment(screenshot: app.screenshot())
            tutorial.name = "help-\(language)-tutorial"; tutorial.lifetime = .keepAlways; add(tutorial)
            app.buttons["tutorialNext"].tap()
            XCTAssertTrue(app.staticTexts[french ? "2. Gardez le meilleur passage" : "2. Keep the best passage"].waitForExistence(timeout: 5))
            app.buttons["tutorialPrevious"].tap()
            XCTAssertTrue(app.staticTexts[firstStep].waitForExistence(timeout: 5))
            app.buttons["closeHelp"].tap()
            app.buttons["editorHelp"].tap()
            XCTAssertTrue(app.staticTexts[firstStep].waitForExistence(timeout: 5), "Closing help must preserve the current step")

            app.segmentedControls["helpDocumentPicker"].buttons[french ? "Aide" : "Help"].tap()
            XCTAssertTrue(app.staticTexts[french ? "Utiliser CutFuze" : "Using CutFuze"].waitForExistence(timeout: 5))
            let layoutTitle = french ? "Comment me repérer dans l’éditeur ?" : "How do I find my way around the editor?"
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "helpTopic-", layoutTitle)).firstMatch.tap()
            XCTAssertTrue(app.staticTexts[layoutTitle].waitForExistence(timeout: 5))
            app.buttons["helpAllTopics"].tap()
            app.buttons["helpContents"].tap()
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "helpSection-", layoutTitle)).firstMatch.tap()
            let section = app.staticTexts[layoutTitle].firstMatch
            XCTAssertTrue(section.waitForExistence(timeout: 5))
            XCTAssertTrue(section.isHittable)
            let guide = XCTAttachment(screenshot: app.screenshot())
            guide.name = "help-\(language)-guide-layout"; guide.lifetime = .keepAlways; add(guide)
            app.buttons["closeHelp"].tap()
            app.buttons["editorBack"].tap()
            XCTAssertTrue(app.buttons["libraryHelp"].waitForExistence(timeout: 5))
            app.buttons["libraryHelp"].tap()
            XCTAssertTrue(app.buttons["closeHelp"].waitForExistence(timeout: 5))
            app.buttons["closeHelp"].tap()
            app.terminate()
        }
    }
}
