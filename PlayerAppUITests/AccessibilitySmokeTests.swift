import XCTest

final class AccessibilitySmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrimaryNavigationAndEqualizerControlsExposeUsableTargets() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        for name in ["Library", "Sources", "EQ", "Output", "Settings"] {
            assertAccessibleTarget(app.tabBars.buttons[name], name: name)
        }

        app.tabBars.buttons["EQ"].tap()
        let addBand = app.buttons["equalizer.addBand"]
        XCTAssertTrue(addBand.waitForExistence(timeout: 5))
        assertAccessibleTarget(addBand, name: "Add Band")
        addBand.tap()

        assertAccessibleTarget(
            app.buttons["equalizer.filterType"],
            name: "Filter Type"
        )
        for identifier in [
            "bandFrequency.exact",
            "bandGain.exact",
            "bandQuality.exact"
        ] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 3))
            assertAccessibleTarget(control, name: identifier)
        }
    }

    private func assertAccessibleTarget(
        _ element: XCUIElement,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, "Missing \(name).", file: file, line: line)
        XCTAssertFalse(element.label.isEmpty, "Missing label for \(name).", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
    }
}
