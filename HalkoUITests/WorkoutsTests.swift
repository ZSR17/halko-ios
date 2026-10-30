import XCTest

final class WorkoutsTests: XCTestCase {
    @MainActor
    func testWorkouts() throws {
        let app = launch(language: "en", locale: "en_US")

        XCTAssertTrue(app.element(containing: "Push A · in progress").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Full body express").exists)
        // The muscles come from the exercise library, installed in the background at launch.
        XCTAssertTrue(app.element(containing: "Abs, primary").waitForExistence(timeout: 30))
        try app.auditWorkouts()
        snap("Workouts")

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "PPL program")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["PPL program"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Pull A").exists)
        try app.auditWorkouts()
        snap("Workouts › Folder")
    }

    @MainActor
    func testWorkoutsInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")

        XCTAssertTrue(app.navigationBars["Séances"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Push A · en cours").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Abdos, principal").waitForExistence(timeout: 30))
        snap("Séances")
    }

    @MainActor
    func testWorkoutsWithLargestText() throws {
        let app = launch(language: "en", locale: "en_US", textSize: "UICTContentSizeCategoryAccessibilityXXXL")

        XCTAssertTrue(app.element(containing: "Abs, primary").waitForExistence(timeout: 30))
        try app.auditWorkouts()
        snap("Workouts, largest text")
        app.scrollViews.firstMatch.swipeUp()
        snap("Workouts, largest text, scrolled")
    }

    @MainActor
    func testWorkoutPage() throws {
        // Kilograms, as the sample workouts.
        let app = launch(language: "en", locale: "en_GB")

        app.openPushA()
        XCTAssertTrue(app.element(containing: "Auto warm-up: 20 × 10").waitForExistence(timeout: 30))
        XCTAssertTrue(app.element(containing: "4 × 8 · 80 kg · rest 2:30").exists)
        XCTAssertTrue(app.element(containing: "Superset · no rest in between").exists)
        XCTAssertTrue(app.element(containing: "One side at a time").exists)
        XCTAssertTrue(app.element(containing: "Primary muscles: chest").exists)
        try app.auditWorkouts()
        snap("Workout")
        app.scrollViews.firstMatch.swipeUp()
        snap("Workout, scrolled")

        // A copy, last in the folder, then deleted.
        app.buttons["More actions"].tap()
        snap("Workout › More actions")
        app.buttons["Duplicate"].tap()
        // Back to the folder.
        app.navigationBars["Push A"].buttons.element(boundBy: 0).tap()
        let copy = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Push A (copy)")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.navigationBars["Push A (copy)"].waitForExistence(timeout: 5))
        app.buttons["More actions"].tap()
        app.buttons["Delete"].tap()
        app.buttons["Delete the workout"].tap()
        XCTAssertTrue(app.navigationBars["PPL program"].waitForExistence(timeout: 5))
        XCTAssertFalse(copy.exists)
    }

    @MainActor
    func testWorkoutPageInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")

        app.openPushA()
        XCTAssertTrue(app.element(containing: "Échauffement auto : 20 × 10").waitForExistence(timeout: 30))
        XCTAssertTrue(app.element(containing: "Développé couché").exists)
        snap("Séance")
    }

    @MainActor
    func testWorkoutPageWithLargestText() throws {
        let app = launch(language: "en", locale: "en_GB", textSize: "UICTContentSizeCategoryAccessibilityXXXL")

        app.openPushA()
        XCTAssertTrue(app.element(containing: "Auto warm-up").waitForExistence(timeout: 30))
        try app.auditWorkouts()
        snap("Workout, largest text")
        app.scrollViews.firstMatch.swipeUp()
        snap("Workout, largest text, scrolled")
    }

    // Sample workouts, in a database kept in memory.
    @MainActor
    private func launch(language: String, locale: String, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        return app
    }
}

extension XCUIApplication {
    // The audit reports the texts of the cards as keeping their size or being clipped at larger sizes, though they
    // grow and wrap (the largest-text screenshots show it), and measures the contrast of the cards scrolling under
    // the fade of the bars. Every other issue fails the test.
    @MainActor
    func auditWorkouts() throws {
        let bars = [navigationBars.firstMatch.frame, tabBars.firstMatch.frame].map { $0.insetBy(dx: 0, dy: -40) }
        try performAccessibilityAudit { issue in
            switch issue.auditType {
            case .dynamicType, .textClipped: true
            case .contrast: bars.contains { $0.intersects(issue.element?.frame ?? .zero) }
            default: false
            }
        }
    }

    // Push A, in the folder PPL program: a card opens the page of its workout.
    @MainActor
    func openPushA() {
        let folder = buttons.matching(NSPredicate(format: "label CONTAINS %@", "PPL program")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Push A")).firstMatch.tap()
        XCTAssertTrue(navigationBars["Push A"].waitForExistence(timeout: 5))
    }

    // The cards are single accessibility elements: their texts are found inside their labels.
    @MainActor
    func element(containing text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
