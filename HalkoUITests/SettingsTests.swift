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
}
