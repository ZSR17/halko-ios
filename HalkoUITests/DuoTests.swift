import XCTest

// The screens of the iPhone Duo open, in two columns. Run on its simulator only, opened by the CI before.
final class DuoTests: XCTestCase {
    @MainActor
    func testWorkoutsInTwoColumns() throws {
        let app = launch(language: "en", locale: "en_GB")

        // The workouts on the left, the first one's page on the right.
        XCTAssertTrue(app.element(containing: "Full body express").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Push A · in progress").exists)
        XCTAssertTrue(app.element(containing: "Auto warm-up: 20 × 10").waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Start the workout"].exists)
        try app.auditScreen()
        snapInnerScreen("Duo › Workouts")

        app.element(containing: "Full body express").tap()
        XCTAssertTrue(app.navigationBars["Full body express"].waitForExistence(timeout: 5))
        // The list stays beside.
        XCTAssertTrue(app.element(containing: "Pull A").exists)
        snapInnerScreen("Duo › Workouts › Full body express")
    }

    @MainActor
    func testWorkoutsInTwoColumnsInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")

        XCTAssertTrue(app.element(containing: "Push A · en cours").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Échauffement auto").waitForExistence(timeout: 30))
        snapInnerScreen("Duo › Séances")
    }

    @MainActor
    func testLiveSessionInTwoColumns() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.openSessionInProgress()

        // The sets on the right; on the left the program, the bench press under way, and its last sessions.
        XCTAssertTrue(app.element(containing: "Set 2 of 4 · Barbell Bench Press - Medium Grip").waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Program"].exists)
        XCTAssertTrue(app.element(containing: "1 / 4 sets").exists)
        XCTAssertTrue(app.element(containing: "Superset · no rest in between").exists)
        XCTAssertTrue(app.element(containing: "Barbell Bench Press - Medium Grip · history").exists)
        XCTAssertTrue(app.element(containing: "Estimated 1RM").exists)
        XCTAssertTrue(app.buttons["Finish"].exists)
        try app.auditScreen()
        snapInnerScreen("Duo › Session")

        // The way back is above the program; the session goes on.
        app.buttons["Workouts"].firstMatch.tap()
        XCTAssertTrue(app.element(containing: "Push A · in progress").waitForExistence(timeout: 5))
    }

    @MainActor
    func testExercisesInTwoColumns() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.buttons["Exercises"].firstMatch.tap()

        // The library on the left, the first exercise's page on the right.
        XCTAssertTrue(app.staticTexts["877 exercises"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 10))
        try app.auditScreen()
        snapInnerScreen("Duo › Exercises")

        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("medium bench")
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Barbell Bench Press - Medium Grip")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()
        XCTAssertTrue(app.element(containing: "Max weight").waitForExistence(timeout: 5))
        XCTAssertTrue(bench.isSelected)
        snapInnerScreen("Duo › Exercises › Bench press")
    }

    @MainActor
    func testHistoryInTwoColumns() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.buttons["History"].firstMatch.tap()

        // The sessions on the left, the latest one on the right.
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["More actions"].waitForExistence(timeout: 10))
        try app.auditScreen()
        snapInnerScreen("Duo › History")

        // In Progress, the exercises on the left, the progress of the first one on the right.
        app.buttons["Progress"].tap()
        XCTAssertTrue(app.buttons["Measure"].waitForExistence(timeout: 10))
        try app.auditScreen()
        snapInnerScreen("Duo › History › Progress")
    }

    @MainActor
    func testToolsInTwoColumns() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.buttons["Tools"].firstMatch.tap()

        // The tools on the left, the plates on the right.
        XCTAssertTrue(app.element(containing: "Per side: 1 × 25 kg + 1 × 15 kg").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Plate calculator"].isSelected)
        try app.auditScreen()
        snapInnerScreen("Duo › Tools")

        app.buttons["1RM calculator"].tap()
        XCTAssertTrue(app.buttons["1RM calculator"].isSelected)
        XCTAssertFalse(app.element(containing: "Per side:").exists)
        snapInnerScreen("Duo › Tools › 1RM")
    }

    @MainActor
    func testSettingsInTwoColumns() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.buttons["Settings"].firstMatch.tap()

        // The settings on the left, the language on the right.
        XCTAssertTrue(app.element(containing: "Same as the iPhone").waitForExistence(timeout: 10))
        try app.auditScreen()
        snapInnerScreen("Duo › Settings")

        app.element(containing: "Rest end").tap()
        XCTAssertTrue(app.navigationBars["Rest end"].waitForExistence(timeout: 5))
        // The list stays beside.
        XCTAssertTrue(app.element(containing: "Set timer").exists)
        try app.auditScreen()
        snapInnerScreen("Duo › Settings › Rest end")
    }

    // XCTest's screenshots of the inner screen are black: the CI takes them, from the Mac, with simctl. Asked by a
    // file in the folder it gives, and done when the CI has removed it.
    @MainActor
    private func snapInnerScreen(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["DUO_SHOTS"] else {
            return XCTFail("No folder for the screenshots of the inner screen")
        }
        let request = URL(filePath: folder).appending(path: "\(name).request")
        XCTAssertNoThrow(try Data().write(to: request, options: .atomic))
        let taken = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: request.path(percentEncoded: false))
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [taken], timeout: 30), .completed, "Screenshot not taken: \(name)")
    }
}
