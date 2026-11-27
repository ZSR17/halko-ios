import XCTest

final class ExercisesTests: XCTestCase {
    @MainActor
    func testExercises() throws {
        // Kilograms, as the sample sets.
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["Exercises"].tap()

        // The library, installed in the background at launch, and the exercise made by the user.
        XCTAssertTrue(app.staticTexts["877 exercises"].waitForExistence(timeout: 30))
        try app.auditScreen()
        snap("Exercises")

        // The body, small, opens large; a muscle tapped on it, around the chest: where the body is drawn moves a
        // little from one launch to the next. VoiceOver reads the muscles as buttons.
        app.buttons["Muscles"].tap()
        XCTAssertTrue(app.navigationBars["Muscles"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["muscle-chest"].value as? String, "Not picked")
        try app.auditScreen()
        app.tapChest()
        XCTAssertTrue(app.element(containing: "Primary muscle:").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'muscle-' AND value == 'Primary'")).firstMatch.exists)
        snap("Exercises › Muscles")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Muscles"].waitForNonExistence(timeout: 5))
        // The muscle picked beside the small body, the list kept to it.
        XCTAssertTrue(app.element(containing: "Primary muscle:").exists)
        snap("Exercises, a muscle picked")
        app.buttons["Clear"].tap()
        XCTAssertTrue(app.element(containing: "Tap one of the figures").waitForExistence(timeout: 5))

        // The equipment at hand.
        app.switches["Barbell"].tap()
        XCTAssertFalse(app.element(containing: "Home weighted push-ups").exists)
        snap("Exercises, with a barbell")

        app.searchFields.firstMatch.tap()
        // Its words in any order.
        app.searchFields.firstMatch.typeText("medium bench")
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Barbell Bench Press - Medium Grip")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        // The title and its button stay while searching.
        XCTAssertTrue(app.navigationBars["Exercises"].buttons["New exercise"].exists)
        snap("Exercises, searching")
        bench.tap()

        // The records of the sample sessions: 85 kg × 3 before, 80 kg × 8 today.
        XCTAssertTrue(app.element(containing: "Max weight").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "85 kg").exists)
        XCTAssertTrue(app.element(containing: "101.3 kg").exists)
        XCTAssertTrue(app.element(containing: "80 × 8").exists)
        XCTAssertTrue(app.element(containing: "Primary muscle: chest").exists)
        try app.auditScreen()
        snap("Exercise")
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.element(containing: "How to").exists)
        XCTAssertTrue(app.element(containing: "Progress").exists)
        snap("Exercise, scrolled")

        // A session of its progress opens.
        let session = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "85 kg")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.tap()
        XCTAssertTrue(app.navigationBars["Push A"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomExercise() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["Exercises"].tap()

        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("push-ups")
        let custom = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Home weighted push-ups")).firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 30))
        XCTAssertTrue(custom.label.contains("custom"))
        custom.tap()
        XCTAssertTrue(app.element(containing: "Weighted bodyweight").waitForExistence(timeout: 5))
        // Never done: no records.
        XCTAssertFalse(app.element(containing: "Stats").exists)
        try app.auditScreen()
        snap("Exercise, custom")
    }

    @MainActor
    func testExercisesInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")
        app.tabBars.buttons["Exercices"].tap()

        XCTAssertTrue(app.navigationBars["Exercices"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "877 exercices").waitForExistence(timeout: 30))
        snap("Exercices")

        // Found without its accents, and by its English name.
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("developpe couche")
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Développé couché,")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()
        XCTAssertTrue(app.element(containing: "Charge max").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Principal : pectoraux").exists)
        snap("Fiche exercice")
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.element(containing: "Exécution").exists)
        snap("Fiche exercice, défilée")
    }

    @MainActor
    func testExercisesWithLargestText() throws {
        let app = launch(language: "en", locale: "en_GB", textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.tabBars.buttons["Exercises"].tap()

        XCTAssertTrue(app.element(containing: "Tap one of the figures").waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Exercises, largest text")
        app.buttons["Muscles"].tap()
        XCTAssertTrue(app.navigationBars["Muscles"].waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Exercises › Muscles, largest text")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Muscles"].waitForNonExistence(timeout: 5))
        app.scrollViews.firstMatch.swipeUp()
        snap("Exercises, largest text, scrolled")

        // The search field stays in view.
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("medium bench")
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Barbell Bench Press - Medium Grip")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 30))
        bench.tap()
        // The records are further down.
        XCTAssertTrue(app.element(containing: "Weight and reps").waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Exercise, largest text")
        app.scrollViews.firstMatch.swipeUp()
        snap("Exercise, largest text, scrolled")
    }
}

extension XCUIApplication {
    // The left of the chest on the large body seen from the front, in the sheet of the muscles (default text size):
    // the two sides centered, 170 × 340 points 14 apart, over their names and the hint.
    @MainActor
    func tapChest() {
        let hint = staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Tap a muscle'")).firstMatch.frame
        coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX - 107, dy: hint.minY - 279)).tap()
    }
}
