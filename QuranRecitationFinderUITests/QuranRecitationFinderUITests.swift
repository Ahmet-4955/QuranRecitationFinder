import XCTest

final class QuranRecitationFinderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Test 1: App launch

    @MainActor func testLaunch_showsErkennenTab() throws {
        let app = makeApp(language: "de")
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Erkennen"].waitForExistence(timeout: 8))
    }

    // MARK: - Tests 2-5: Text input (German)

    @MainActor func testTextInput_AlIkhlas_test2() throws {
        let app = makeApp(language: "de")
        app.launch()
        openTextInputSheetDE(app)

        let textView = firstTextInput(app)
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("قل هو الله احد")

        let searchBtn = app.buttons["Suchen"]
        XCTAssertTrue(searchBtn.isEnabled, "'Suchen' muss nach Texteingabe aktiv sein")
        searchBtn.tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '112'"))
                .firstMatch.waitForExistence(timeout: 15)
        )
    }

    @MainActor func testTextInput_ArRahman_test3() throws {
        let app = makeApp(language: "de")
        app.launch()
        openTextInputSheetDE(app)

        let textView = firstTextInput(app)
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("فباي الاء ربكما تكذبان")
        app.buttons["Suchen"].tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '55'"))
                .firstMatch.waitForExistence(timeout: 15)
        )
    }

    @MainActor func testTextInput_AlFatiha_test4() throws {
        let app = makeApp(language: "de")
        app.launch()
        openTextInputSheetDE(app)

        let textView = firstTextInput(app)
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("اهدنا الصراط المستقيم صراط الذين انعمت عليهم")
        app.buttons["Suchen"].tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1:6' OR label CONTAINS '1:7'"))
                .firstMatch.waitForExistence(timeout: 15)
        )
    }

    @MainActor func testTextInput_ModernArabic_test5() throws {
        let app = makeApp(language: "de")
        app.launch()
        openTextInputSheetDE(app)

        let textView = firstTextInput(app)
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("مرحبا كيف حالك اليوم يا صديقي")
        app.buttons["Suchen"].tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'erkannt'"))
                .firstMatch.waitForExistence(timeout: 15)
        )
    }

    // MARK: - Test 6: Translation language switch to Turkish

    @MainActor func testLanguageSwitch_toTurkish_test6() throws {
        let app = makeApp(language: "de")
        app.launch()

        // First search to get a result
        openTextInputSheetDE(app)
        let textView = firstTextInput(app)
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("قل هو الله احد")
        app.buttons["Suchen"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '112'"))
                .firstMatch.waitForExistence(timeout: 15)
        )

        // Go to Settings and switch translation to Turkish
        app.tabBars.buttons["Einstellungen"].tap()
        // Find the Language/Sprache picker cell and tap it
        let sprachePicker = app.cells.containing(.staticText, identifier: "Sprache").firstMatch
        XCTAssertTrue(sprachePicker.waitForExistence(timeout: 5))
        sprachePicker.tap()
        // Select Türkçe
        XCTAssertTrue(app.buttons["Türkçe"].waitForExistence(timeout: 5))
        app.buttons["Türkçe"].tap()

        // Back on Recognize tab – search again for the same verse
        app.tabBars.buttons["Erkennen"].tap()
        openTextInputSheetDE(app)
        let textView2 = firstTextInput(app)
        XCTAssertTrue(textView2.waitForExistence(timeout: 5))
        textView2.tap()
        textView2.typeText("قل هو الله احد")
        app.buttons["Suchen"].tap()

        // Verify Turkish translation appears ("Allah birdir" is from turkish_rwwad 112:1)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Allah birdir'"))
                .firstMatch.waitForExistence(timeout: 15),
            "Turkish translation should appear after language switch"
        )
    }

    // MARK: - Test 7: Verlauf (history) tab shows entries and supports swipe-to-delete

    @MainActor func testHistory_test7() throws {
        let app = makeApp(language: "de")
        app.launch()

        // Run three searches to populate history (tests 2-4)
        let searches = [
            "قل هو الله احد",
            "فباي الاء ربكما تكذبان",
            "اهدنا الصراط المستقيم صراط الذين انعمت عليهم",
        ]
        for query in searches {
            openTextInputSheetDE(app)
            let tv = firstTextInput(app)
            XCTAssertTrue(tv.waitForExistence(timeout: 5))
            tv.tap()
            tv.typeText(query)
            app.buttons["Suchen"].tap()
            // Wait for result before next search
            Thread.sleep(forTimeInterval: 3)
        }

        // Go to Verlauf tab
        app.tabBars.buttons["Verlauf"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))

        // Verlauf should have entries (at least 2 confirmed recognitions)
        let cells = app.cells
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 5), "Verlauf should have at least one entry")

        // Swipe to delete the first entry
        cells.firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["Löschen"].waitForExistence(timeout: 3))
        app.buttons["Löschen"].tap()
    }

    // MARK: - Test 19: German tab labels

    @MainActor func testGermanTabs_test19() throws {
        let app = makeApp(language: "de")
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Erkennen"].exists)
        XCTAssertTrue(app.tabBars.buttons["Verlauf"].exists)
        XCTAssertTrue(app.tabBars.buttons["Einstellungen"].exists)
    }

    // MARK: - Test 20: Turkish tab labels

    @MainActor func testTurkishTabs_test20() throws {
        let app = makeApp(language: "tr")
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Tanı"].exists)
        XCTAssertTrue(app.tabBars.buttons["Geçmiş"].exists)
        XCTAssertTrue(app.tabBars.buttons["Ayarlar"].exists)
    }

    // MARK: - Test 21: English tab labels

    @MainActor func testEnglishTabs_test21() throws {
        let app = makeApp(language: "en")
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Recognize"].exists)
        XCTAssertTrue(app.tabBars.buttons["History"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    // MARK: - Diagnostic (used for debugging element labels)

    @MainActor func testDiagnostic_dumpUI() throws {
        let app = makeApp(language: "de")
        app.launch()
        // Wait for tab bar to appear (confirms app fully loaded)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar never appeared")
        Thread.sleep(forTimeInterval: 2)

        var lines = ["=== BUTTONS ==="]
        for btn in app.buttons.allElementsBoundByIndex {
            lines.append("Button: '\(btn.label)' id='\(btn.identifier)'")
        }
        lines.append("=== NAV BAR BUTTONS ===")
        for btn in app.navigationBars.buttons.allElementsBoundByIndex {
            lines.append("NavBar: '\(btn.label)' id='\(btn.identifier)'")
        }
        lines.append("=== TOOLBAR BUTTONS ===")
        for btn in app.toolbars.buttons.allElementsBoundByIndex {
            lines.append("Toolbar: '\(btn.label)' id='\(btn.identifier)'")
        }
        lines.append("=== TEXTFIELDS ===")
        for tf in app.textFields.allElementsBoundByIndex {
            lines.append("TF: '\(tf.label)' id='\(tf.identifier)'")
        }
        lines.append("=== TEXTVIEWS ===")
        for tv in app.textViews.allElementsBoundByIndex {
            lines.append("TV: '\(tv.label)' id='\(tv.identifier)'")
        }
        lines.append("=== ALL STATIC TEXTS (first 20) ===")
        for (i, st) in app.staticTexts.allElementsBoundByIndex.prefix(20).enumerated() {
            lines.append("ST[\(i)]: '\(st.label)'")
        }

        let output = lines.joined(separator: "\n")
        let url = URL(fileURLWithPath: "/tmp/xcuitest-dump.txt")
        try output.write(to: url, atomically: true, encoding: .utf8)

        // Also attach as XCTAttachment so it shows in xcresult
        let attachment = XCTAttachment(string: output)
        attachment.name = "ui-dump"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Helpers

    private func makeApp(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        let locale: String
        switch language {
        case "tr": locale = "tr_TR"
        case "de": locale = "de_DE"
        default:   locale = "en_US"
        }
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        return app
    }

    private func openTextInputSheetDE(_ app: XCUIApplication) {
        let btn = app.buttons["Text eingeben"]
        XCTAssertTrue(btn.waitForExistence(timeout: 10))
        btn.tap()
        XCTAssertTrue(app.navigationBars["Text eingeben"].waitForExistence(timeout: 5))
    }

    private func firstTextInput(_ app: XCUIApplication) -> XCUIElement {
        let tv = app.textViews.firstMatch
        if tv.exists { return tv }
        return app.textFields.firstMatch
    }
}
