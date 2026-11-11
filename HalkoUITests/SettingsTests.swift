import XCTest

final class SettingsTests: XCTestCase {
    @MainActor
    func testLanguageAndUnits() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Settings")

        // A language chosen shows at the next start.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Language")).firstMatch.tap()
        let french = app.buttons["Français"]
        XCTAssertTrue(french.waitForExistence(timeout: 5))
        french.tap()
        XCTAssertTrue(app.element(containing: "the next time it opens").waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Settings › Language")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.element(containing: "Français").waitForExistence(timeout: 5))

        // Pounds, apart from the region (kilometres and miles in Britain): the plates weigh in them at once.
        XCTAssertTrue(app.buttons["kg"].isSelected)
        XCTAssertTrue(app.buttons["mi"].isSelected)
        app.buttons["lb"].tap()
        app.tabBars.buttons["Tools"].tap()
        app.buttons["Plate calculator"].tap()
        XCTAssertTrue(app.navigationBars["Plate calculator"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "lb").exists)
        XCTAssertFalse(app.element(containing: "kg").exists)
    }

    @MainActor
    func testRestAlert() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["Settings"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rest end")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Watch"))
        row.tap()
        XCTAssertTrue(app.navigationBars["Rest end"].waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Settings › Rest end")

        // The iPhone too, and another sound, heard when touched.
        app.buttons["Both"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ringtone")).firstMatch.tap()
        let gong = app.buttons["Gong"]
        XCTAssertTrue(gong.waitForExistence(timeout: 5))
        gong.tap()
        XCTAssertTrue(gong.isSelected)
        try app.auditScreen()
        snap("Settings › Rest end › Ringtone")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Without the sound, its choices go; the countdown stays.
        // On the switch itself: its label alone does not turn it.
        app.switches["Sound"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ringtone")).firstMatch.exists)
        app.reveal(app.buttons["10 s"])
        app.buttons["10 s"].tap()
        XCTAssertTrue(app.buttons["10 s"].isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.element(containing: "Watch and iPhone · vibration").waitForExistence(timeout: 5))
    }
}
