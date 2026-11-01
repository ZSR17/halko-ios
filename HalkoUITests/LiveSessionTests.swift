import XCTest

final class LiveSessionTests: XCTestCase {
    @MainActor
    func testLiveSession() throws {
        // Kilograms, as the sample workouts.
        let app = launch(language: "en", locale: "en_GB")
        app.openSessionInProgress()

        // The sample session: the warm-ups and the first working set of the bench press done.
        XCTAssertTrue(app.element(containing: "Exercise 1 of 5").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Set 2 of 4 · Barbell Bench Press - Medium Grip").waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Undo Set 1"].exists)
        XCTAssertTrue(app.buttons["Undo Warm-up 4"].exists)
        try app.auditScreen()
        snap("Session")

        // A set more for this session, like the last one: its button, under the sets, shown first.
        app.scrollViews.firstMatch.swipeUp()
        app.buttons["Add a set"].firstMatch.tap()
        XCTAssertTrue(app.element(containing: "Set 2 of 5").waitForExistence(timeout: 5))
        app.scrollViews.firstMatch.swipeDown()

        // Validated: the rest, with what comes next.
        app.buttons["Validate the set"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "set 3").exists)
        XCTAssertTrue(app.buttons["Undo Set 2"].exists)
        snap("Session › Rest")
        app.buttons["Add 15 seconds"].tap()
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.element(containing: "Set 3 of 5").waitForExistence(timeout: 5))

        // Undone: the set to do again.
        app.buttons["Undo Set 2"].tap()
        XCTAssertTrue(app.element(containing: "Set 2 of 5").waitForExistence(timeout: 5))
        app.buttons["Validate the set"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()

        // Left and come back to: the session goes on where it was.
        app.navigationBars.buttons["Workouts"].tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5))
        app.openSessionInProgress()
        XCTAssertTrue(app.element(containing: "Set 3 of 5").waitForExistence(timeout: 5))

        // Saved: the summary, with the estimated 1RM beaten (80 × 8 today, 85 × 3 before).
        app.buttons["Finish"].tap()
        snap("Session › Finish")
        app.buttons["Save the session"].tap()
        XCTAssertTrue(app.staticTexts["Workout saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Estimated 1RM").exists)
        try app.auditScreen()
        snap("Session › Summary")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.element(containing: "Push A · in progress").exists)
    }

    @MainActor
    func testLiveSessionInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")
        app.openSessionInProgress()

        XCTAssertTrue(app.element(containing: "Exercice 1 sur 5").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Série 2 sur 4").waitForExistence(timeout: 30))
        snap("Séance en cours")
        app.buttons["Valider la série"].tap()
        XCTAssertTrue(app.buttons["Passer"].waitForExistence(timeout: 5))
        snap("Séance en cours › Repos")
    }

    @MainActor
    func testLiveSessionWithLargestText() throws {
        let app = launch(language: "en", locale: "en_GB", textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.openSessionInProgress()

        XCTAssertTrue(app.buttons["Validate the set"].waitForExistence(timeout: 30))
        try app.auditScreen()
        snap("Session, largest text")
        app.buttons["Validate the set"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        snap("Session › Rest, largest text")
    }

    @MainActor
    func testStartWorkout() throws {
        let app = launch(language: "en", locale: "en_GB")

        // Another workout while Push A is in progress: one session at a time.
        let folder = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "PPL program")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pull A")).firstMatch.tap()
        app.buttons["Start the workout"].tap()
        XCTAssertTrue(app.alerts["A session is already in progress"].waitForExistence(timeout: 5))
        snap("Start › Already in progress")
        app.alerts.buttons["Resume it"].tap()

        // Push A discarded, Pull A starts.
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 5))
        app.buttons["Finish"].tap()
        app.buttons["Discard the session"].tap()
        app.alerts.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["Start the workout"].waitForExistence(timeout: 5))
        app.buttons["Start the workout"].tap()
        XCTAssertTrue(app.element(containing: "Exercise 1 of 5").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Set 1 of 4 · Pullups").waitForExistence(timeout: 30))
        snap("Start › Pull A")
    }
}

extension XCUIApplication {
    // The banner of the Workouts tab.
    @MainActor
    func openSessionInProgress() {
        let banner = buttons.matching(NSPredicate(format: "label CONTAINS %@", "Push A ·")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        banner.tap()
    }
}
