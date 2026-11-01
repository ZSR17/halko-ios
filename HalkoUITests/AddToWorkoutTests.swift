import XCTest

final class AddToWorkoutTests: XCTestCase {
    @MainActor
    func testAddToWorkout() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.openBenchPress()
        app.buttons["Add to a workout"].tap()

        XCTAssertTrue(app.navigationBars["Add to a workout"].waitForExistence(timeout: 5))
        // Push A plans the bench press already; Pull A does not.
        XCTAssertTrue(app.choice("Push A").label.contains("already has this exercise"))
        try app.auditScreen()
        snap("Add to a workout")
        XCTAssertFalse(app.choice("Pull A").label.contains("already has this exercise"))
        snap("Add to a workout, full height")

        app.choice("Pull A").tap()
        XCTAssertTrue(app.navigationBars["Edit workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "6 exercises").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Remove Barbell Bench Press - Medium Grip"].exists)
        snap("Add to a workout, editor")
        app.buttons["Save"].tap()

        // Back on the exercise's page, now in Pull A.
        XCTAssertTrue(app.buttons["Add to a workout"].waitForExistence(timeout: 5))
        app.buttons["Add to a workout"].tap()
        let pull = app.choice("Pull A")
        XCTAssertTrue(pull.waitForExistence(timeout: 5))
        XCTAssertTrue(pull.label.contains("6 exercises"))
        XCTAssertTrue(pull.label.contains("already has this exercise"))
    }

    @MainActor
    func testCancelLeavesTheWorkout() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.openBenchPress()
        app.buttons["Add to a workout"].tap()
        app.choice("Pull A").tap()
        XCTAssertTrue(app.element(containing: "6 exercises").waitForExistence(timeout: 5))
        // The exercise added counts as a change.
        app.buttons["Cancel"].tap()
        app.buttons["Discard Changes"].tap()

        XCTAssertTrue(app.buttons["Add to a workout"].waitForExistence(timeout: 5))
        app.buttons["Add to a workout"].tap()
        let pull = app.choice("Pull A")
        XCTAssertTrue(pull.waitForExistence(timeout: 5))
        XCTAssertTrue(pull.label.contains("5 exercises"))
    }

    @MainActor
    func testAddToNewWorkout() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.openBenchPress()
        app.buttons["Add to a workout"].tap()
        app.buttons["New workout"].tap()

        XCTAssertTrue(app.navigationBars["New workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "1 exercise").waitForExistence(timeout: 5))
        // No name yet.
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        let name = app.textFields["Workout name"]
        name.tap()
        name.typeText("Chest day")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.buttons["Add to a workout"].waitForExistence(timeout: 5))
        app.buttons["Add to a workout"].tap()
        let chest = app.choice("Chest day")
        XCTAssertTrue(chest.waitForExistence(timeout: 5))
        XCTAssertTrue(chest.label.contains("1 exercise"))
    }

    @MainActor
    func testAddToWorkoutInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")
        app.tabBars.buttons["Exercices"].tap()
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("developpe couche")
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Développé couché,")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 30))
        app.open(bench, showing: app.buttons["Ajouter à une séance"])
        app.buttons["Ajouter à une séance"].tap()
        XCTAssertTrue(app.navigationBars["Ajouter à une séance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.choice("Push A").label.contains("contient déjà cet exercice"))
        snap("Ajouter à une séance")
    }

    @MainActor
    func testAddToWorkoutWithLargestText() throws {
        let app = launch(language: "en", locale: "en_GB", textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.openBenchPress()
        app.buttons["Add to a workout"].tap()
        XCTAssertTrue(app.navigationBars["Add to a workout"].waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Add to a workout, largest text")
    }
}

extension XCUIApplication {
    // A workout of the sheet, by its name. The list only makes the rows in view: it is pulled up (the sheet to its
    // full height, then the list) until the row shows.
    @MainActor
    func choice(_ name: String) -> XCUIElement {
        let row = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(navigationBars.matching(NSPredicate(format: "identifier IN %@", ["Add to a workout", "Ajouter à une séance"])).firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<4 where !row.exists || !row.isHittable {
            collectionViews.firstMatch.swipeUp()
        }
        return row
    }
}
