import XCTest

final class WorkoutEditorTests: XCTestCase {
    @MainActor
    func testEditWorkout() throws {
        // Kilograms, as the sample workouts.
        let app = launch(language: "en", locale: "en_GB")
        app.openWorkoutEditor()
        // Nothing changed yet.
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        XCTAssertTrue(app.element(containing: "5 exercises · 1 superset").exists)
        try app.auditScreen()
        snap("Edit workout")

        // A warm-up made a working set, then a warm-up again: as it was.
        let firstSet = app.buttons["Set 1"]
        XCTAssertEqual(firstSet.value as? String, "Warm-up")
        firstSet.tap()
        XCTAssertEqual(firstSet.value as? String, "Working set 1")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        firstSet.tap()
        XCTAssertEqual(firstSet.value as? String, "Warm-up")
        XCTAssertFalse(app.buttons["Save"].isEnabled)

        // The help of the (i), closed by a tap elsewhere.
        app.buttons["How editing works"].tap()
        XCTAssertTrue(app.element(containing: "Swipe a set left to delete it.").waitForExistence(timeout: 5))
        snap("Edit workout › Help")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(app.element(containing: "Swipe a set left to delete it.").waitForNonExistence(timeout: 5))

        // The bench press and the shoulder press made a superset.
        app.buttons["Link as a superset with the next"].firstMatch.tap()
        XCTAssertTrue(app.element(containing: "5 exercises · 2 supersets").waitForExistence(timeout: 5))
        app.swipeUp()
        snap("Edit workout, scrolled")
        app.swipeUp()
        try app.auditScreen()
        snap("Edit workout, end")

        // Taken out, then saved: the page has one exercise fewer.
        let remove = app.buttons["Remove Side Bridge"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.element(containing: "4 exercises · 2 supersets").waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Push A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "4 exercises").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element(containing: "Side Bridge").exists)
    }

    @MainActor
    func testDiscardChangesThenReorder() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.openWorkoutEditor()
        let name = app.textFields["Workout name"]
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        name.typeText(" heavy")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 5))
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.navigationBars["Push A"].waitForExistence(timeout: 5))

        // Opened again, without the change.
        app.buttons["More actions"].tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit workout"].waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Push A")
        let bench = app.handle("Move Barbell Bench Press - Medium Grip")
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        // Held and taken to the bottom of the screen: last.
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        bench.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.3, thenDragTo: bottom)
        let handles = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label BEGINSWITH %@)", "Move ", "Move the superset"))
        let order = handles.allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }.map(\.label)
        XCTAssertEqual(order.last, "Move Barbell Bench Press - Medium Grip")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        snap("Edit workout, reordered")
    }

    @MainActor
    func testAddExercises() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.openWorkoutEditor()
        let add = app.buttons["Add an exercise"]
        // Made with the rest of the screen, but under it.
        for _ in 0..<6 where !add.isHittable {
            app.swipeUp()
        }
        add.tap()
        XCTAssertTrue(app.navigationBars["Add exercises"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["877 exercises"].waitForExistence(timeout: 30))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("barbell curl")
        let curl = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Barbell Curl,")).firstMatch
        XCTAssertTrue(curl.waitForExistence(timeout: 5))
        curl.tap()
        if !curl.isSelected {
            // The first tap only put the keyboard away.
            curl.tap()
        }
        XCTAssertTrue(curl.isSelected)
        snap("Add exercises")
        app.buttons["Add 1"].tap()
        XCTAssertTrue(app.element(containing: "6 exercises").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Remove Barbell Curl"].exists)
    }

    @MainActor
    func testNewWorkout() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.navigationBars["Workouts"].buttons["New workout"].tap()
        XCTAssertTrue(app.navigationBars["New workout"].waitForExistence(timeout: 5))
        // No name yet.
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        XCTAssertTrue(app.element(containing: "0 exercises").exists)
        // The name is being typed: the keyboard put away first, since the audit does not always tell it from the
        // screen while it comes up.
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        try app.auditScreen()
        snap("New workout")

        let name = app.textFields["Workout name"]
        name.tap()
        name.typeText("Legs B")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Add an exercise"].tap()
        XCTAssertTrue(app.staticTexts["877 exercises"].waitForExistence(timeout: 30))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("full squat")
        let squat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Barbell Full Squat,")).firstMatch
        XCTAssertTrue(squat.waitForExistence(timeout: 5))
        squat.tap()
        if !squat.isSelected {
            // The first tap only put the keyboard away.
            squat.tap()
        }
        app.buttons["Add 1"].tap()
        XCTAssertTrue(app.element(containing: "1 exercise").waitForExistence(timeout: 5))
        snap("New workout, filled in")
        app.buttons["Save"].tap()

        // Last on the page, with its exercise.
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Legs B")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("1 exercise"))
    }

    @MainActor
    func testEditorInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")
        app.openPushA()
        app.buttons["Plus d’actions"].tap()
        app.buttons["Modifier"].tap()
        XCTAssertTrue(app.navigationBars["Modifier la séance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "5 exercices · 1 superset").exists)
        XCTAssertTrue(app.buttons["Série 1"].exists)
        snap("Modifier la séance")
        app.swipeUp()
        snap("Modifier la séance, défilé")
        app.swipeUp()
        snap("Modifier la séance, fin")
    }

    @MainActor
    func testEditorWithLargestText() throws {
        let app = launch(language: "en", locale: "en_GB", textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.openWorkoutEditor()
        snap("Edit workout, largest text")
        app.swipeUp()
        snap("Edit workout, largest text, scrolled")
        try app.auditScreen()
        // Lower down too, past the table of the bench press.
        for _ in 0..<4 {
            app.swipeUp()
        }
        try app.auditScreen()
        snap("Edit workout, largest text, end")
    }
}

extension XCUIApplication {
    // The editor of Push A, from its page.
    @MainActor
    func openWorkoutEditor() {
        openPushA()
        buttons["More actions"].tap()
        buttons["Edit"].tap()
        XCTAssertTrue(navigationBars["Edit workout"].waitForExistence(timeout: 5))
        // The exercises are read from the library, installed in the background at launch.
        XCTAssertTrue(handle("Move Barbell Bench Press - Medium Grip").waitForExistence(timeout: 30))
    }

    // The handle moving an exercise or a superset.
    @MainActor
    func handle(_ label: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}
