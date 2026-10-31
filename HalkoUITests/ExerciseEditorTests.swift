import XCTest

final class ExerciseEditorTests: XCTestCase {
    @MainActor
    func testNewExercise() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["Exercises"].tap()
        XCTAssertTrue(app.staticTexts["877 exercises"].waitForExistence(timeout: 30))

        app.buttons["New exercise"].tap()
        XCTAssertTrue(app.navigationBars["New exercise"].waitForExistence(timeout: 5))
        // No name yet.
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        XCTAssertFalse(app.element(containing: "Library exercise").exists)
        try app.auditScreen()
        snap("New exercise")

        app.chooseType("Duration")
        app.switches["Body weight"].tap()
        let name = app.textFields["Name"]
        name.tap()
        name.typeText("Wall sit")
        snap("New exercise, filled in")
        app.buttons["Save"].tap()

        // In the list, as the user's own.
        XCTAssertTrue(app.staticTexts["878 exercises"].waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("wall sit")
        let created = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wall sit")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertTrue(created.label.contains("custom"))
        created.tap()
        XCTAssertTrue(app.element(containing: "Duration").waitForExistence(timeout: 5))
    }

    @MainActor
    func testYourVersion() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.openBenchPress()

        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit exercise"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Library exercise").exists)
        // Nothing changed yet.
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        try app.auditScreen()
        snap("Edit exercise")

        // Done 7 times as weight and reps (sample sessions): asked first, and left as it was.
        app.chooseType("Duration")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.label.contains("Duration"))
        XCTAssertTrue(alert.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Your 7 sets")).firstMatch.exists)
        snap("Edit exercise, type change")
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)

        app.swipeUp()
        snap("Edit exercise, scrolled")
        app.swipeDown()
        let name = app.textFields["Name"]
        // At the end of the name.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + "My bench press")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["My bench press"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "your version").exists)
        snap("Exercise, your version")

        // Back to the library's.
        app.buttons["Edit"].tap()
        let revert = app.buttons["Revert to original"]
        app.scroll(to: revert)
        revert.tap()
        app.buttons["Go back to the original"].tap()
        XCTAssertTrue(app.staticTexts["Barbell Bench Press - Medium Grip"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.element(containing: "your version").exists)
    }

    @MainActor
    func testDeleteCustomExercise() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["Exercises"].tap()
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("home weighted")
        let custom = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Home weighted push-ups")).firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 30))
        custom.tap()

        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit exercise"].waitForExistence(timeout: 5))
        let delete = app.buttons["Delete exercise"]
        app.scroll(to: delete)
        snap("Edit exercise, custom")
        delete.tap()
        app.buttons["Delete the exercise"].tap()

        // Back on the list, without it.
        XCTAssertTrue(app.element(containing: "No exercises match.").waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditorInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")
        app.tabBars.buttons["Exercices"].tap()
        XCTAssertTrue(app.element(containing: "877 exercices").waitForExistence(timeout: 30))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("developpe couche")
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Développé couché,")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()

        app.buttons["Modifier"].tap()
        XCTAssertTrue(app.navigationBars["Modifier l’exercice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Exercice de la bibliothèque").exists)
        snap("Modifier l’exercice")
        app.swipeUp()
        snap("Modifier l’exercice, défilé")
    }

    @MainActor
    func testEditorWithLargestText() throws {
        let app = launch(language: "en", locale: "en_GB", textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.tabBars.buttons["Exercises"].tap()
        XCTAssertTrue(app.buttons["New exercise"].waitForExistence(timeout: 5))
        app.buttons["New exercise"].tap()
        XCTAssertTrue(app.navigationBars["New exercise"].waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("New exercise, largest text")
        app.swipeUp()
        snap("New exercise, largest text, scrolled")
    }
}

extension XCUIApplication {
    // The page of the bench press of the library, done in the sample sessions.
    @MainActor
    func openBenchPress() {
        tabBars.buttons["Exercises"].tap()
        searchFields.firstMatch.tap()
        searchFields.firstMatch.typeText("medium bench")
        let bench = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Barbell Bench Press - Medium Grip")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 30))
        bench.tap()
        XCTAssertTrue(buttons["Edit"].waitForExistence(timeout: 5))
    }

    // Down the form, which makes its rows only when they come into view.
    @MainActor
    func scroll(to element: XCUIElement) {
        for _ in 0..<6 where !element.exists {
            swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    // The type of the exercise being edited, from its menu.
    @MainActor
    func chooseType(_ type: String) {
        buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Exercise type")).firstMatch.tap()
        let choice = buttons[type]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
    }
}
