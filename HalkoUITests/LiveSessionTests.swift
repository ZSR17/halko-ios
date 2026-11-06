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

        // Half a kilogram more for the set to do.
        app.buttons["Add 0.5 kg"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "80.5")).firstMatch.waitForExistence(timeout: 5))

        // A set to come changed in its box, before its turn; the button above the panel puts the keyboard away.
        let later = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Set 4,")).firstMatch
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        later.tap()
        later.typeText("90")
        snap("Session › Typing")
        app.buttons["Hide the keyboard"].tap()
        XCTAssertTrue(app.buttons["Hide the keyboard"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(later.value as? String, "90")

        // A set more for this session, like the last one: its button, under the sets, brought above the bottom block
        // first (XCUI would touch the block over it).
        let addSet = app.buttons["Add a set"].firstMatch
        let panelTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Set 2 of 4")).firstMatch
        let middle = app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        for _ in 0..<8 where addSet.frame.maxY > panelTitle.frame.minY - 24 {
            middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -120)))
        }
        addSet.tap()
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

        // Deleting an exercise is asked first, where its menu was; a tap elsewhere keeps it.
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["More actions for Barbell Bench Press - Medium Grip"].tap()
        app.buttons["Delete this exercise"].tap()
        XCTAssertTrue(app.element(containing: "from this session?").waitForExistence(timeout: 5))
        snap("Session › Delete an exercise")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.element(containing: "Exercise 1 of 5").waitForExistence(timeout: 5))

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

    // The plank of Quick: getting in position, holding, the set validated with the time held, the rest.
    @MainActor
    func testSetTimer() throws {
        let app = launch(language: "fr", locale: "fr_FR")
        let quick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Quick")).firstMatch
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.tap()
        app.buttons["Démarrer la séance"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["La reprendre"].tap()
        XCTAssertTrue(app.buttons["Terminer"].waitForExistence(timeout: 5))
        app.buttons["Terminer"].tap()
        app.buttons["Abandonner la séance"].tap()
        app.alerts.buttons["Abandonner"].tap()
        XCTAssertTrue(app.buttons["Démarrer la séance"].waitForExistence(timeout: 5))
        app.buttons["Démarrer la séance"].tap()
        let proceed = app.buttons["Continuer"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 5))
        proceed.tap()

        let startTimer = app.buttons["Démarrer le chrono"]
        XCTAssertTrue(startTimer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Valider"].exists)
        try app.auditScreen()
        snap("Chrono › Série à faire")

        startTimer.tap()
        let begin = app.buttons["Commencer"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Mets-toi en place").exists)
        snap("Chrono › Mise en place")

        // Cancelled: nothing recorded, the set to do again.
        app.buttons["Annuler"].tap()
        XCTAssertTrue(startTimer.waitForExistence(timeout: 5))
        startTimer.tap()
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()
        let stop = app.buttons["Arrêter et valider"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        snap("Chrono › Décompte")
        stop.tap()
        XCTAssertTrue(app.buttons["Passer"].waitForExistence(timeout: 5))
        snap("Chrono › Repos après la série")
    }

    @MainActor
    func testSetTimerSettings() throws {
        let app = launch(language: "fr", locale: "fr_FR")
        app.tabBars.buttons["Réglages"].tap()
        let row = app.buttons["Chrono d'une série"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.element(containing: "À l'objectif").waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Réglages › Chrono d'une série")
        app.buttons["Durée"].tap()
        XCTAssertTrue(app.buttons["Valider"].waitForExistence(timeout: 5))
        snap("Réglages › Chrono, roues")
        app.buttons["Valider"].tap()
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

        // The first session started: what Halko asks of the system, once, before it begins (the sample data asks
        // nothing of the system).
        XCTAssertTrue(app.staticTexts["Before your first workout"].waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Start › Before your first workout")
        app.buttons["Continue"].tap()
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
