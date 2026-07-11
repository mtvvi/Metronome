import XCTest

final class ReleaseSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrimaryTabsAndCompleteEqualizerEditorAreReachable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Sources"].exists)
        XCTAssertTrue(app.tabBars.buttons["Output"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)

        app.tabBars.buttons["EQ"].tap()

        XCTAssertTrue(app.staticTexts["Parametric Equalizer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Equalizer"].exists)
        XCTAssertTrue(app.staticTexts["Master Gain"].exists)
        XCTAssertTrue(app.buttons["Add Band"].exists)
        XCTAssertTrue(app.buttons["Presets"].exists)
        XCTAssertTrue(app.buttons["Import or export equalizer preset"].exists)
    }

    func testEqualizerExactValuesPersistAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["EQ"].waitForExistence(timeout: 10))
        app.tabBars.buttons["EQ"].tap()

        let addBand = app.buttons["equalizer.addBand"]
        XCTAssertTrue(addBand.waitForExistence(timeout: 5))
        XCTAssertTrue(addBand.isEnabled)
        addBand.tap()

        replaceExactValue(identifier: "bandFrequency.exact", with: "120", in: app)
        replaceExactValue(identifier: "bandGain.exact", with: "-4.8", in: app)
        replaceExactValue(identifier: "bandQuality.exact", with: "0.70", in: app)

        app.buttons["equalizer.save"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["EQ"].waitForExistence(timeout: 10))
        app.tabBars.buttons["EQ"].tap()

        XCTAssertTrue(app.buttons["bandFrequency.exact"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.buttons["bandFrequency.exact"].value as? String)?.contains("120") == true)
        XCTAssertTrue((app.buttons["bandGain.exact"].value as? String)?.contains("4.8") == true)
        XCTAssertTrue((app.buttons["bandQuality.exact"].value as? String)?.contains("0.70") == true)
    }

    func testAllEqualizerFilterTypesExposeOnlyApplicableControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["EQ"].waitForExistence(timeout: 10))
        app.tabBars.buttons["EQ"].tap()
        let addBand = app.buttons["equalizer.addBand"]
        XCTAssertTrue(addBand.waitForExistence(timeout: 5))
        addBand.tap()

        let cases: [(name: String, hasGain: Bool, hasQuality: Bool)] = [
            ("Parametric", true, true),
            ("Low Pass", false, false),
            ("High Pass", false, false),
            ("Resonant Low Pass", false, true),
            ("Resonant High Pass", false, true),
            ("Band Pass", false, true),
            ("Band Stop", false, true),
            ("Low Shelf", true, false),
            ("High Shelf", true, false),
            ("Resonant Low Shelf", true, true),
            ("Resonant High Shelf", true, true)
        ]

        for filter in cases {
            let picker = app.buttons["equalizer.filterType"]
            XCTAssertTrue(picker.waitForExistence(timeout: 3))
            picker.tap()
            let option = app.buttons[filter.name]
            XCTAssertTrue(option.waitForExistence(timeout: 3))
            option.tap()

            XCTAssertEqual(
                app.buttons["bandGain.exact"].exists,
                filter.hasGain,
                "Unexpected Gain control visibility for \(filter.name)."
            )
            XCTAssertEqual(
                app.buttons["bandQuality.exact"].exists,
                filter.hasQuality,
                "Unexpected Quality control visibility for \(filter.name)."
            )
        }
    }

    private func replaceExactValue(
        identifier: String,
        with value: String,
        in app: XCUIApplication
    ) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        let existing = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing))
        field.typeText(value)
        app.buttons["Apply"].tap()
    }
}
