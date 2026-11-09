import XCTest

final class HistoryTests: XCTestCase {
    @MainActor
    func testHistory() throws {
        // Kilograms, as the sample sets.
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 10))
        try app.auditScreen()
        snap("History")

        // The latest Push A, which beat the record of the bench press; early in a month, it is in a month still folded.
        let folded = app.buttons.matching(NSPredicate(format: "value == %@", "Collapsed"))
        let pushA = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Push A")).firstMatch
        if !pushA.exists {
            folded.firstMatch.tap()
        }
        pushA.tap()
        XCTAssertTrue(app.navigationBars["Push A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Records beaten"].waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("History › Session")

        app.buttons["More actions"].tap()
        let delete = app.buttons["Delete the session"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.staticTexts["Its sets disappear from the history, the records and “Previous”. The session saved in Health stays."].waitForExistence(timeout: 5))
        snap("History › Delete the session")
        app.buttons["Delete the session"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProgress() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["History"].tap()
        let progress = app.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()
        XCTAssertTrue(app.buttons["Exercise"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "85 kg").exists)
        try app.auditScreen()
        snap("History › Progress")

        // The other measures of an exercise done with a weight and reps.
        app.buttons["Measure"].tap()
        let volume = app.buttons["Session volume"]
        XCTAssertTrue(volume.waitForExistence(timeout: 5))
        snap("History › Progress, measures")
        volume.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == %@", "Session volume")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistoryInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")
        app.tabBars.buttons["Historique"].tap()
        XCTAssertTrue(app.staticTexts["Cette semaine"].waitForExistence(timeout: 10))
        snap("Historique")
        app.buttons["Progression"].tap()
        XCTAssertTrue(app.buttons["Exercice"].waitForExistence(timeout: 5))
        snap("Historique › Progression")
    }

    @MainActor
    func testHistoryWithLargestText() throws {
        let app = launch(language: "en", locale: "en_GB", textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 10))
        try app.auditScreen()
        snap("History, largest text")
    }
}
