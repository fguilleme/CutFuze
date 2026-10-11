import XCTest

final class WorkspaceUITests: XCTestCase {
    @MainActor func testAudioMenuImportsOrReusesOnlyAudio() throws {
        let app = launchDemo()
        app.buttons["addAudio"].tap()
        XCTAssertTrue(app.buttons["importAudio"].exists)
        XCTAssertTrue(app.buttons["importedAudioLibrary"].exists)
        XCTAssertTrue(app.buttons["Voix off"].exists)
        XCTAssertTrue(app.buttons["Synthèse vocale"].exists)
        capture("audio-import-menu")
        app.buttons["importAudio"].tap()
        let cancel = app.buttons["Annuler"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "The system file importer must open")
        capture("audio-file-importer")
        cancel.tap()
        app.buttons["addAudio"].tap(); app.buttons["importedAudioLibrary"].tap()
        let library = app.descendants(matching: .any)["audioLibrary"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["libraryImportAudio"].exists)
        app.buttons["libraryImportAudio"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        let resources = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "resource-"))
        XCTAssertEqual(resources.count, 1, "The demo has one audio asset, not its video resources")
        capture("imported-audio-library")
        resources.firstMatch.tap()
        XCTAssertTrue(app.buttons["Ajouter"].waitForExistence(timeout: 5))
        // Insert at the active scene so both audio clips are visible in the
        // accessibility viewport. Appending at montage end is covered in CoreTests.
        app.buttons.containing(.staticText, identifier: "En superposition").firstMatch.tap()
        capture("reuse-audio-review")
        app.buttons["Ajouter"].tap()
        XCTAssertTrue(app.buttons["tool-Volume"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timelineClip-audio-")).count, 2)
        capture("reused-audio-timeline")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
    }

    @MainActor func testVisualToolsOpenFocusedCurvesAndEffectsResizePreview() throws {
        let app = launchDemo()
        firstTimelineClip(app, kind: "video").tap()
        app.buttons["tool-Effets visuels"].tap()
        for (tool, property) in [("Transformer", "scale"), ("Opacité", "opacity"), ("Masque", "maskWidth")] {
            app.buttons["visualTool-\(tool)"].tap()
            if tool == "Masque" { app.buttons["mask-ellipse"].tap() }
            capture("visual-tools-\(property)-shortcut")
            app.buttons["editVisualCurve"].tap()
            let propertyButton = app.buttons["keyframeProperty-\(property)"]
            XCTAssertTrue(propertyButton.waitForExistence(timeout: 5))
            XCTAssertTrue(propertyButton.isSelected)
            if tool == "Opacité" { XCTAssertFalse(app.buttons["keyframeProperty-scale"].exists) }
            app.buttons["saveKeyframe"].tap()
            XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).count, 0)
            capture("visual-curve-\(property)")
            app.buttons["closeCurveEditor"].tap()
        }
        let tabs = app.scrollViews["visualTools"]
        for (category, kind) in [("Beauté", "skinSmooth"), ("Géométrie", "bulge"), ("Lumière", "exposure")] {
            let button = app.buttons["visualTool-\(category)"]
            for _ in 0..<4 where !button.isHittable { tabs.swipeLeft() }
            XCTAssertTrue(button.isHittable); button.tap()
            app.buttons["effect-\(kind)"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["effectSettings"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["keyframeGraph"].exists)
            app.buttons["effectSaveKeyframe"].tap()
            XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).count, 0)
            if kind == "skinSmooth" {
                let divider = app.descendants(matching: .any)["curvePreviewDivider"].firstMatch
                let before = try XCTUnwrap(Int(divider.value as? String ?? ""))
                let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 70)))
                XCTAssertGreaterThan(try XCTUnwrap(Int(divider.value as? String ?? "")), before + 40)
            }
            capture("effect-curve-\(kind)")
            app.buttons["effectApply"].tap()
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
    }

    @MainActor func testShapePreviewResizesWithoutLockedAspectRatio() throws {
        let app = launchDemo()
        app.buttons["Overlay"].tap(); app.buttons["Forme"].tap()
        app.buttons["overlayShape-rectangle"].tap()
        let frame = app.descendants(matching: .any)["previewSelectionFrame"]
        XCTAssertTrue(frame.waitForExistence(timeout: 5))
        let initial = frame.frame
        let handle = app.descendants(matching: .any)["previewResizeHandle"]
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 30, dy: 0)))
        Thread.sleep(forTimeInterval: 0.5)
        let wide = frame.frame
        XCTAssertGreaterThan(wide.width, initial.width + 25)
        XCTAssertEqual(wide.height, initial.height, accuracy: 5)
        capture("overlay-free-width")
        app.buttons["Annuler la modification"].tap()
        XCTAssertEqual(frame.frame.width, initial.width, accuracy: 5)
        let verticalStart = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        verticalStart.press(forDuration: 0.1, thenDragTo: verticalStart.withOffset(CGVector(dx: 0, dy: 25)))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertGreaterThan(frame.frame.height, initial.height + 25)
        XCTAssertEqual(frame.frame.width, initial.width, accuracy: 5)
        capture("overlay-free-height")
        app.buttons["tool-Effets visuels"].tap()
        app.buttons["visualTool-Transformer"].tap()
        let panel = app.scrollViews["contextToolScroll"]
        let width = app.sliders["Largeur"]
        let height = app.sliders["Hauteur"]
        for _ in 0..<3 where !width.isHittable { panel.swipeUp() }
        XCTAssertTrue(width.isHittable)
        let oldHeight = height.value as? String
        width.adjust(toNormalizedSliderPosition: 0.4)
        XCTAssertEqual(height.value as? String, oldHeight)
        for _ in 0..<3 where !height.isHittable { panel.swipeUp() }
        XCTAssertTrue(height.isHittable)
        let oldWidth = width.value as? String
        height.adjust(toNormalizedSliderPosition: 0.3)
        XCTAssertEqual(width.value as? String, oldWidth)
        capture("overlay-dimensions-panel")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
    }

    @MainActor func testOverlayShapePickerAddsAndChangesShape() throws {
        let app = launchDemo()
        app.buttons["Overlay"].tap()
        app.buttons["Forme"].tap()
        for kind in ["ellipse", "rectangle", "roundedRectangle", "cloud", "star", "heart"] {
            XCTAssertTrue(app.buttons["overlayShape-\(kind)"].waitForExistence(timeout: 3))
        }
        capture("overlay-shape-picker")
        app.buttons["overlayShape-heart"].tap()
        XCTAssertTrue(app.buttons["editOverlayShape"].waitForExistence(timeout: 3))
        capture("overlay-heart")
        app.buttons["editOverlayShape"].tap()
        XCTAssertTrue(app.buttons["overlayShape-heart"].isSelected)
        app.buttons["overlayShape-cloud"].tap()
        app.buttons["editOverlayShape"].tap()
        XCTAssertTrue(app.buttons["overlayShape-cloud"].isSelected)
        app.buttons["closeShapePicker"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("overlay-cloud")
        app.terminate()
    }

    @MainActor func testAudioSpeedVolumeCurveAndUnifiedEffectScrolling() throws {
        let app = launchDemo()
        firstTimelineClip(app, kind: "audio").tap()
        app.buttons["tool-Vitesse"].tap()
        app.buttons["speedPreset-200"].tap()
        XCTAssertTrue(app.buttons["speedPreset-200"].isSelected)
        XCTAssertEqual(app.sliders["Vitesse"].value as? String, "2.00×")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("audio-double-speed")
        app.buttons["tool-Volume"].tap()
        let panel = app.scrollViews["contextToolScroll"]
        for _ in 0..<3 where !app.buttons["editVolumeCurve"].isHittable { panel.swipeUp() }
        app.buttons["editVolumeCurve"].tap()
        let form = app.descendants(matching: .any)["keyframeEditorForm"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["keyframeProperty-volume"].exists)
        XCTAssertFalse(app.buttons["keyframeProperty-scale"].exists)
        let graph = app.descendants(matching: .any)["keyframeGraph"]
        graph.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.4)).tap()
        app.buttons["saveKeyframe"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-")).count, 1)
        capture("volume-curve-point")
        let preview = app.descendants(matching: .any)["curvePreview"]
        let before = preview.frame.minY
        form.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.8)).press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.4)), withVelocity: XCUIGestureVelocity(rawValue: 150), thenHoldForDuration: 0.3)
        XCTAssertTrue(!preview.exists || !preview.isHittable || preview.frame.minY < before - 20, "The preview scrolls with the curve and settings")
        XCTAssertTrue(app.textFields["keyframeValueField"].waitForExistence(timeout: 3))
        capture("volume-curve-settings")
        form.swipeDown()
        for _ in 0..<4 where !app.buttons["listenVolumeCurve"].isHittable { form.swipeUp() }
        app.buttons["listenVolumeCurve"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.descendants(matching: .any)["volumeAuditionError"].exists)
        app.buttons["closeCurveEditor"].tap()
        app.buttons["closeContextTool"].tap()
        firstTimelineClip(app, kind: "video").tap()
        app.buttons["tool-Effets visuels"].tap()
        app.buttons["visualTool-Créatif"].tap()
        app.buttons["effect-neon"].tap()
        let effects = app.descendants(matching: .any)["effectSettings"]
        XCTAssertTrue(effects.waitForExistence(timeout: 5))
        let effectPreview = app.descendants(matching: .any)["effectCurvePreview"]
        let effectTop = effectPreview.frame.minY
        capture("effect-curve-top")
        effects.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.8)).press(forDuration: 0.1, thenDragTo: effects.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.4)), withVelocity: XCUIGestureVelocity(rawValue: 150), thenHoldForDuration: 0.3)
        XCTAssertTrue(!effectPreview.exists || !effectPreview.isHittable || effectPreview.frame.minY < effectTop - 20)
        revealEffectParameter(app.sliders["neonGlowRadius"], in: effects)
        XCTAssertTrue(app.sliders["neonGlowRadius"].isHittable)
        capture("effect-curve-scrolled")
        app.terminate()
    }

    @MainActor func testTextMenuHasTextAutoCaptionsAndSRTWithoutDuplicateManualCaption() throws {
        let app = launchDemo()
        app.buttons["Texte"].tap()
        XCTAssertTrue(app.buttons["Ajouter du texte"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Sous-titres automatiques"].exists)
        XCTAssertTrue(app.buttons["Importer un SRT"].exists)
        XCTAssertFalse(app.buttons["Sous-titres"].exists)
        capture("simplified-text-menu")
        app.buttons["Ajouter du texte"].tap()
        XCTAssertTrue(app.buttons["tool-Modifier"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
    }

    @MainActor private func revealEffectParameter(_ slider: XCUIElement, in settings: XCUIElement) {
        // A full swipe can skip the short first section on an iPhone.
        // Bring the complete thumb inside the viewport with small, reversible scrolls.
        var upward = true
        for _ in 0..<16 {
            let viewport = settings.frame
            if slider.exists {
                let frame = slider.frame
                if slider.isHittable, frame.minY >= viewport.minY + 12, frame.maxY <= viewport.maxY - 28 { return }
                upward = frame.maxY > viewport.maxY - 28
            } else { upward.toggle() }
            // Hold before lifting to stop inertial scrolling; use the gutter,
            // not the slider itself, as the start of the scroll gesture.
            settings.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: upward ? 0.75 : 0.35))
                .press(forDuration: 0.1, thenDragTo: settings.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: upward ? 0.65 : 0.45)), withVelocity: XCUIGestureVelocity(rawValue: 50), thenHoldForDuration: 0.3)
        }
    }

    @MainActor func testSecondCreativeSeriesEditsCurvesReflectionAndWaveSpeed() throws {
        let app = launchDemo()
        firstTimelineClip(app, kind: "video").tap()
        app.buttons["tool-Effets visuels"].tap()
        app.buttons["visualTool-Créatif"].tap()
        capture("creative-second-series-catalog")
        let points = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-"))
        for kind in ["dream", "lightSweep", "liquidDistortion"] {
            app.buttons["effect-\(kind)"].tap()
            XCTAssertTrue(app.buttons["effectApply"].waitForExistence(timeout: 5))
            let settings = app.descendants(matching: .any)["effectSettings"]
            var storedParameter: String?
            if kind == "dream" {
                XCTAssertEqual(points.count, 0)
                app.descendants(matching: .any)["keyframeGraph"].coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3)).tap()
                app.buttons["effectSaveKeyframe"].tap()
                XCTAssertEqual(points.count, 1)
            } else if kind == "lightSweep" {
                XCTAssertEqual(points.count, 4)
                XCTAssertTrue(points.allElementsBoundByIndex.allSatisfy { $0.isHittable })
                let color = app.buttons["effectColor-#49E6FF"]
                revealEffectParameter(color, in: settings)
                XCTAssertTrue(color.isHittable); color.tap(); XCTAssertTrue(color.isSelected)
                let width = app.sliders["lightSweepWidth"]
                revealEffectParameter(width, in: settings)
                XCTAssertTrue(width.isHittable); width.adjust(toNormalizedSliderPosition: 0.8)
                storedParameter = try XCTUnwrap(width.value as? String)
                XCTAssertEqual(try XCTUnwrap(Double(storedParameter!.replacingOccurrences(of: " %", with: ""))), 80, accuracy: 5)
                app.buttons["effectUndo"].tap(); XCTAssertEqual(width.value as? String, "35 %")
                app.buttons["effectRedo"].tap(); XCTAssertEqual(width.value as? String, storedParameter)
            } else {
                let speed = app.sliders["liquidFlowSpeed"]
                revealEffectParameter(speed, in: settings)
                XCTAssertTrue(speed.isHittable); speed.adjust(toNormalizedSliderPosition: 0.75)
                storedParameter = try XCTUnwrap(speed.value as? String)
                XCTAssertEqual(try XCTUnwrap(Double(storedParameter!.replacingOccurrences(of: " ×", with: ""))), 1.5625, accuracy: 0.1)
                app.buttons["effectUndo"].tap(); XCTAssertEqual(speed.value as? String, "1.00 ×")
                app.buttons["effectRedo"].tap(); XCTAssertEqual(speed.value as? String, storedParameter)
                app.descendants(matching: .any)["keyframeGraph"].coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3)).tap()
            }
            Thread.sleep(forTimeInterval: 1)
            XCTAssertFalse(app.descendants(matching: .any)["effectEditorError"].exists)
            capture("creative-second-\(kind)")
            app.buttons["effectApply"].tap()
            app.buttons["effect-\(kind)"].tap()
            XCTAssertTrue(app.buttons["effectApply"].waitForExistence(timeout: 5))
            if kind == "dream" { XCTAssertEqual(points.count, 1) }
            else {
                let slider = app.sliders[kind == "lightSweep" ? "lightSweepWidth" : "liquidFlowSpeed"]
                revealEffectParameter(slider, in: settings)
                XCTAssertEqual(slider.value as? String, storedParameter)
                if kind == "lightSweep" {
                    let color = app.buttons["effectColor-#49E6FF"]
                    for _ in 0..<5 where !color.isHittable { settings.swipeDown() }
                    XCTAssertTrue(color.isSelected)
                }
            }
            XCTAssertFalse(app.descendants(matching: .any)["effectEditorError"].exists)
            app.buttons["effectCancel"].tap()
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
    }

    @MainActor func testCreativePresetsHaveFocusedEditableCurvesAndNeonColor() throws {
        let app = launchDemo()
        firstTimelineClip(app, kind: "video").tap()
        app.buttons["tool-Effets visuels"].tap()
        app.buttons["visualTool-Créatif"].tap()
        capture("creative-presets-catalog")
        let points = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-"))
        for (kind, count) in [("impactZoom", 4), ("shortGlitch", 5)] {
            app.buttons["effect-\(kind)"].tap()
            XCTAssertTrue(app.buttons["effectApply"].waitForExistence(timeout: 5))
            XCTAssertEqual(points.count, count)
            XCTAssertTrue(points.allElementsBoundByIndex.allSatisfy { $0.isHittable }, "Burst keyframes should not be clustered at the beginning of a long clip")
            capture("creative-preset-\(kind)")
            let last = try XCTUnwrap(points.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX })
            last.tap()
            XCTAssertTrue(last.isSelected)
            let interpolation = app.buttons["effectEasing"]
            XCTAssertTrue(interpolation.isHittable)
            interpolation.tap()
            app.buttons["Accélération et décélération"].tap()
            XCTAssertEqual(interpolation.value as? String, "Accélération et décélération")
            XCTAssertEqual(last.value as? String, "Accélération et décélération")
            capture("creative-easing-\(kind)")
            app.buttons["effectUndo"].tap()
            XCTAssertEqual(last.value as? String, "Décélération")
            let position = last.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let before = last.label
            position.press(forDuration: 0.1, thenDragTo: position.withOffset(CGVector(dx: -25, dy: -20)))
            XCTAssertTrue(waitForLabel(last, equals: before, matching: false))
            XCTAssertFalse(app.descendants(matching: .any)["effectEditorError"].exists)
            app.buttons["effectUndo"].tap()
            XCTAssertTrue(waitForLabel(last, equals: before))
            app.buttons["effectApply"].tap()
            app.buttons["effect-\(kind)"].tap()
            XCTAssertTrue(app.buttons["effectApply"].waitForExistence(timeout: 5))
            XCTAssertEqual(points.count, count)
            app.buttons["effectCancel"].tap()
        }
        firstTimelineClip(app, kind: "text").tap()
        app.buttons["tool-Effets visuels"].tap()
        app.buttons["visualTool-Créatif"].tap()
        app.buttons["effect-neon"].tap()
        XCTAssertTrue(app.buttons["effectApply"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["keyframeGraph"].coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.3)).tap()
        let pink = app.buttons["neonColor-#FF48D7"]
        let settings = app.descendants(matching: .any)["effectSettings"]
        for _ in 0..<5 where !pink.isHittable { settings.swipeUp() }
        XCTAssertTrue(pink.isHittable, app.debugDescription)
        pink.tap()
        XCTAssertTrue(pink.isSelected)
        let spread = app.sliders["neonGlowRadius"]
        for _ in 0..<5 where !spread.isHittable { settings.swipeUp() }
        XCTAssertTrue(spread.isHittable)
        spread.adjust(toNormalizedSliderPosition: 0.9)
        let appliedSpread = try XCTUnwrap(spread.value as? String)
        let percentage = try XCTUnwrap(Double(appliedSpread.replacingOccurrences(of: " %", with: "")))
        XCTAssertEqual(percentage, 90, accuracy: 5, "Touch positioning has a small device-dependent tolerance")
        app.buttons["effectUndo"].tap()
        XCTAssertEqual(spread.value as? String, "45 %")
        app.buttons["effectRedo"].tap()
        XCTAssertEqual(spread.value as? String, appliedSpread)
        Thread.sleep(forTimeInterval: 1)
        capture("creative-neon-custom-color")
        app.buttons["effectApply"].tap()
        app.buttons["effect-neon"].tap()
        XCTAssertTrue(app.buttons["effectApply"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !pink.isHittable { settings.swipeUp() }
        XCTAssertTrue(pink.isSelected)
        for _ in 0..<5 where !spread.isHittable { settings.swipeUp() }
        XCTAssertEqual(spread.value as? String, appliedSpread)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
    }

    @MainActor func testCurvePreviewCanBeResizedBothWays() throws {
        let app = launchDemo()
        firstTimelineClip(app, kind: "video").tap()
        app.buttons["tool-Animation"].tap()
        app.buttons["animationPreset-zoom"].tap()
        app.buttons["advancedAnimation"].tap()
        let divider = app.descendants(matching: .any)["curvePreviewDivider"].firstMatch
        XCTAssertTrue(divider.waitForExistence(timeout: 5))
        let before = try XCTUnwrap(Int(divider.value as? String ?? ""))
        capture("curve-preview-before-resize")
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 90)))
        let larger = try XCTUnwrap(Int(divider.value as? String ?? ""))
        XCTAssertGreaterThan(larger, before + 50)
        capture("curve-preview-expanded")
        let end = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        end.press(forDuration: 0.05, thenDragTo: end.withOffset(CGVector(dx: 0, dy: -70)))
        XCTAssertLessThan(try XCTUnwrap(Int(divider.value as? String ?? "")), larger - 40)
        XCTAssertTrue(app.buttons["keyframeEasing"].exists)
        capture("curve-preview-reduced")
        app.terminate()
    }

    @MainActor func testIPadStyleShowsBackgroundControlsWithoutScrolling() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout") }
        let app = launchDemo()
        firstTimelineClip(app, kind: "caption").tap()
        app.buttons["tool-Style"].tap()
        XCTAssertTrue(app.buttons["textBackgroundColor-#EF4444"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["textBackgroundColor-#EF4444"].isHittable)
        XCTAssertTrue(app.buttons["textBackground-heart"].isHittable)
        XCTAssertTrue(app.buttons["increase-Taille"].isHittable)
        capture("ipad-style-expanded")
        app.terminate()
    }

    @MainActor func testColoredTextBackgroundShapes() throws {
        continueAfterFailure = false
        let app = launchDemo()
        app.buttons["play"].tap()
        Thread.sleep(forTimeInterval: 2)
        app.buttons["play"].tap()
        firstTimelineClip(app, kind: "text").tap()
        app.buttons["tool-Style"].tap()
        let red = app.buttons["textBackgroundColor-#EF4444"]
        let panel = app.scrollViews["contextToolScroll"]
        for _ in 0..<5 where !red.isHittable { panel.swipeUp() }
        XCTAssertTrue(red.isHittable); red.tap()
        let shapes = app.scrollViews["textBackgroundShapes"]
        for name in ["rounded", "cloud", "star", "heart"] {
            let button = app.buttons["textBackground-\(name)"]
            for _ in 0..<5 where !button.isHittable { shapes.swipeLeft() }
            XCTAssertTrue(button.isHittable); button.tap()
            XCTAssertTrue(button.isSelected)
            capture("text-colored-background-\(name)")
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
    }

    @MainActor func testKeyframeLowerControlsRemainReachable() throws {
        continueAfterFailure = false
        let app = launchDemo()
        firstTimelineClip(app, kind: "video").tap()
        app.buttons["tool-Animation"].tap()
        app.buttons["animationPreset-zoom"].tap()
        app.buttons["advancedAnimation"].tap()
        XCTAssertTrue(app.sliders["keyframeTimeSlider"].waitForExistence(timeout: 5))
        capture("keyframe-scroll-initial")
        let form = app.descendants(matching: .any)["keyframeEditorForm"].firstMatch
        func scrollSettings() {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.2)))
        }
        let value = app.textFields["keyframeValueField"]
        for _ in 0..<6 where !value.isHittable { scrollSettings() }
        XCTAssertTrue(value.isHittable)
        let fade = app.buttons["applyKeyframeFade"]
        for _ in 0..<6 where !fade.isHittable { scrollSettings() }
        XCTAssertTrue(fade.isHittable)
        capture("keyframe-scroll-lower-controls")
        app.terminate()
    }

    @MainActor func testCurveEasingPersistsImmediatelyWithoutSavingPoint() throws {
        continueAfterFailure = false
        let app = launchDemo()
        firstTimelineClip(app, kind: "video").tap()
        app.buttons["tool-Animation"].tap()
        app.buttons["animationPreset-zoom"].tap()
        app.buttons["advancedAnimation"].tap()
        XCTAssertTrue(app.sliders["keyframeTimeSlider"].waitForExistence(timeout: 5))
        let keys = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graphKey-"))
        XCTAssertGreaterThan(keys.count, 1)
        // Accessibility order follows screen geometry, not keyframe chronology.
        func seconds(_ element: XCUIElement) -> Double {
            Double(element.label.components(separatedBy: ", ").last?.replacingOccurrences(of: " s", with: "") ?? "0") ?? 0
        }
        let endPoint = try XCTUnwrap(keys.allElementsBoundByIndex.max { seconds($0) < seconds($1) })
        endPoint.tap()
        let picker = app.buttons["keyframeEasing"]
        for _ in 0..<6 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable)
        for label in ["Accélération", "Décélération", "Accélération et décélération", "Linéaire"] {
            picker.tap()
            let option = app.buttons[label]
            if option.waitForExistence(timeout: 2) { option.tap() } else { app.staticTexts[label].tap() }
            XCTAssertEqual(picker.value as? String, label)
            XCTAssertEqual(endPoint.value as? String, label)
        }
        capture("curve-linear-after-choice")
        app.buttons["keyframeUndo"].tap()
        XCTAssertEqual(picker.value as? String, "Accélération et décélération")
        capture("curve-eased-after-undo")
        app.buttons["keyframeRedo"].tap()
        XCTAssertEqual(picker.value as? String, "Linéaire")
        app.terminate()
    }

    @MainActor func testVideoExportCompletesAfterBriefBackgroundSwitch() throws {
        continueAfterFailure = false
        let app = launchDemo()
        app.buttons["export"].tap()
        XCTAssertTrue(app.buttons["exportVariant-1x1"].waitForExistence(timeout: 5))
        app.buttons["exportVariant-1x1"].tap()
        app.buttons["exportVariant-16x9"].tap()
        let resolution = app.buttons["exportResolution"]
        for _ in 0..<5 where !resolution.isHittable { app.swipeUp() }
        resolution.tap()
        app.buttons["720p · 1280 px"].tap()
        let start = app.buttons["Lancer l’export"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["Annuler l’export"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()
        XCTAssertTrue(app.staticTexts["Terminé"].waitForExistence(timeout: 120))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("export-completed-after-brief-background")
        app.terminate()
    }

    @MainActor func testExportProfilesAndReturnFromAnotherApp() throws {
        continueAfterFailure = false
        let app = launchDemo()
        app.buttons["export"].tap()
        let profiles = app.segmentedControls["exportQualityProfile"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 5))
        XCTAssertTrue(profiles.buttons["Équilibré"].isSelected)
        profiles.buttons["Compact"].tap()
        XCTAssertTrue(profiles.buttons["Compact"].isSelected)
        profiles.buttons["Haute fidélité"].tap()
        XCTAssertTrue(profiles.buttons["Haute fidélité"].isSelected)
        capture("export-quality-profiles")
        let advanced = app.buttons["Avancé"]
        for _ in 0..<5 where !advanced.isHittable { app.swipeUp() }
        advanced.tap()
        let manual = app.switches["exportManualBitrate"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
        XCTAssertFalse(profiles.isEnabled)
        manual.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["closeExport"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("export-advanced-after-app-switch")
        app.terminate()
    }

    @MainActor func testTemplateImportOpensPhotoLibrary() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["newProject"].waitForExistence(timeout: 10))
        let templates = app.buttons["Templates"]
        for _ in 0..<8 where !templates.isHittable { app.swipeUp() }
        templates.tap()
        app.staticTexts["One voice, one idea"].tap()
        let photos = app.buttons["templatePhotos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 15))
        for _ in 0..<4 where !photos.isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["templateFiles"].exists)
        photos.tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 10)
            || app.staticTexts["Photos"].exists
            || app.navigationBars["Photos"].exists)
        XCTAssertFalse(app.navigationBars["Browse"].exists)
        capture("template-photo-library")
        app.terminate()
    }

    @MainActor func testEnglishInterfaceAndFrenchLanguageRestoration() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["newProject"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["newProject"].label, "New project")
        XCTAssertTrue(app.staticTexts["Your editing workshop."].exists)
        capture("english-library")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Privacy"].waitForExistence(timeout: 5))
        capture("english-settings")
        app.buttons["Close"].tap()
        let demo = app.buttons["openDemo"]
        for _ in 0..<6 where !demo.isHittable { app.swipeUp() }
        app.buttons["Templates"].tap()
        XCTAssertTrue(app.staticTexts["One voice, one idea"].waitForExistence(timeout: 5))
        capture("english-templates")
        app.staticTexts["One voice, one idea"].tap()
        XCTAssertTrue(app.staticTexts["Here is my idea"].waitForExistence(timeout: 10))
        capture("english-template-detail")
        app.navigationBars.buttons["Templates"].tap()
        app.buttons["Close"].tap()
        demo.tap()
        XCTAssertTrue(app.scrollViews["timelineScroll"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["export"].label, "Export")
        capture("english-timeline")
        let video = firstTimelineClip(app, kind: "video")
        XCTAssertTrue(video.waitForExistence(timeout: 5)); video.tap()
        app.buttons["tool-Effets visuels"].tap()
        XCTAssertEqual(app.buttons["visualTool-Transformer"].label, "Transform")
        XCTAssertTrue(app.buttons["fitMedia"].isHittable)
        capture("english-visual-effects")
        app.buttons["closeContextTool"].tap()
        let caption = firstTimelineClip(app, kind: "caption")
        XCTAssertTrue(caption.exists); caption.tap()
        app.buttons["action-EditCaptions"].tap()
        let field = app.descendants(matching: .any)["captionTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let original = field.value as? String
        app.buttons["reviewCaptions"].tap()
        XCTAssertTrue(app.segmentedControls["captionReviewScope"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["captionReviewScope"].buttons["Entire track"].isSelected)
        capture("english-caption-review")
        app.buttons["closeCaptionReview"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, original)
        app.buttons["Close"].tap()
        app.buttons["export"].tap()
        XCTAssertTrue(app.buttons["closeExport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Formats to export"].exists)
        XCTAssertTrue(app.buttons["Start export"].exists)
        capture("english-export")
        app.buttons["closeExport"].tap()
        app.terminate()
        // Only the test process overrides its language; device preferences are untouched.
        _ = launchDemo()
        XCTAssertEqual(app.buttons["export"].label, "Exporter")
        capture("french-language-restored")
    }

    @MainActor func testCaptionProofreadingEntryScopeAndCancelPreserveText() throws {
        let app = launchDemo()
        let caption = firstTimelineClip(app, kind: "caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 10)); caption.tap()
        app.buttons["action-EditCaptions"].tap()
        let field = app.descendants(matching: .any)["captionTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let original = field.value as? String
        capture("caption-proofreading-access")
        app.buttons["reviewCaptions"].tap()
        XCTAssertTrue(app.segmentedControls["captionReviewScope"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["captionReviewScope"].buttons["Toute la piste"].isSelected)
        XCTAssertTrue(app.staticTexts["Les fragments sont relus comme des phrases, puis répartis sur les segments existants. Les temps restent inchangés."].exists)
        capture("caption-proofreading-whole-phrase-scope")
        app.segmentedControls["captionReviewScope"].buttons["Ce segment"].tap()
        XCTAssertFalse(app.buttons["applyCaptionCorrections"].isEnabled)
        capture("caption-proofreading-entry")
        app.buttons["closeCaptionReview"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, original)
    }

    @MainActor func testCaptionProofreadingWithRealAppleIntelligenceAndUndo() throws {
        let app = launchDemo()
        let caption = firstTimelineClip(app, kind: "caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 10)); caption.tap()
        app.buttons["action-EditCaptions"].tap()
        let field = app.descendants(matching: .any)["captionTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(field.value as? String)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count))
        field.typeText("Les chat joue dans le jardin.")
        app.buttons["Terminé"].tap()
        app.buttons["reviewCaptions"].tap()
        XCTAssertTrue(app.segmentedControls["captionReviewScope"].waitForExistence(timeout: 5))
        if app.staticTexts["captionReviewUnavailable"].exists {
            capture("caption-proofreading-unavailable")
            throw XCTSkip("Apple Intelligence indisponible sur l’appareil de test : " + app.staticTexts["captionReviewUnavailable"].label)
        }
        app.segmentedControls["captionReviewScope"].buttons["Ce segment"].tap()
        app.buttons["startCaptionReview"].tap()
        let correction = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "captionCorrection-")).firstMatch
        let response = NSPredicate { _, _ in correction.exists || app.staticTexts["captionReviewError"].exists || app.staticTexts["captionReviewUnavailable"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: response, object: app)], timeout: 90), .completed)
        XCTAssertTrue(correction.exists, app.debugDescription)
        let proposed = try XCTUnwrap(correction.value as? String)
        XCTAssertFalse(proposed.isEmpty)
        XCTAssertNotEqual(proposed, original)
        XCTAssertTrue(proposed.contains("chats"), proposed)
        XCTAssertTrue(proposed.contains("jouent"), proposed)
        let listen = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "listenCaption-")).firstMatch
        XCTAssertTrue(listen.exists)
        listen.tap()
        let playing = NSPredicate { _, _ in listen.label.contains("Arrêter l’écoute") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: app)], timeout: 10), .completed)
        capture("caption-proofreading-listening")
        listen.tap()
        XCTAssertTrue(listen.label.contains("Écouter le segment"))
        listen.tap()
        let finished = NSPredicate { _, _ in listen.label.contains("Écouter le segment") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: app)], timeout: 15), .completed)
        XCTAssertFalse(app.staticTexts["captionAuditionError"].exists)
        XCTAssertEqual(correction.value as? String, proposed)
        let acceptance = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "acceptCorrection-")).firstMatch
        XCTAssertTrue(acceptance.exists)
        let acceptanceControl = acceptance.switches.firstMatch.exists ? acceptance.switches.firstMatch : acceptance
        acceptanceControl.tap()
        XCTAssertFalse(app.buttons["applyCaptionCorrections"].isEnabled)
        acceptanceControl.tap()
        XCTAssertTrue(app.buttons["applyCaptionCorrections"].isEnabled)
        capture("caption-proofreading-proposal")
        app.buttons["applyCaptionCorrections"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, proposed)
        app.buttons["captionUndo"].tap()
        XCTAssertEqual(field.value as? String, original)
        capture("caption-proofreading-single-undo")
    }

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
