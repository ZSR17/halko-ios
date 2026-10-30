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

        // The chest tapped on the body (VoiceOver reads the muscles as buttons, not where they are drawn), then the
        // equipment at hand.
        let chest = app.buttons["muscle-chest"]
        XCTAssertEqual(chest.value as? String, "Not picked")
        app.tapChest()
        XCTAssertEqual(chest.value as? String, "Primary")
        XCTAssertTrue(app.element(containing: "Primary muscle: chest").exists)
        app.switches["Barbell"].tap()
        XCTAssertFalse(app.element(containing: "Home weighted push-ups").exists)
        snap("Exercises, chest with a barbell")

        app.searchFields.firstMatch.tap()
        // Its words in any order.
        app.searchFields.firstMatch.typeText("medium bench")
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Barbell Bench Press - Medium Grip")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
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
        snap("Exercise, scrolled")
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
        XCTAssertFalse(app.element(containing: "Records").exists)
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

        XCTAssertTrue(app.element(containing: "Tap a muscle once").waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Exercises, largest text")
        app.scrollViews.firstMatch.swipeUp()
        snap("Exercises, largest text, scrolled")

        // The search field shows again at the top.
        app.scrollViews.firstMatch.swipeDown()
        app.scrollViews.firstMatch.swipeDown()
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
    // The left of the chest on the body seen from the front, under the search field at the top of the Exercises tab
    // (iPhone 17 Pro, default text size).
    @MainActor
    func tapChest() {
        let search = searchFields.firstMatch.frame
        coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: search.maxY + 31)).tap()
    }
}
