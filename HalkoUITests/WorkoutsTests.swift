import XCTest

final class WorkoutsTests: XCTestCase {
    @MainActor
    func testWorkouts() throws {
        let app = launch(language: "en", locale: "en_US")

        XCTAssertTrue(app.element(containing: "Push A · in progress").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Full body express").exists)
        // The muscles come from the exercise library, installed in the background at launch.
        XCTAssertTrue(app.element(containing: "Abs, primary").waitForExistence(timeout: 30))
        try app.performAccessibilityAudit()
        snap("Workouts")

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "PPL program")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["PPL program"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Pull A").exists)
        try app.performAccessibilityAudit()
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
        snap("Workouts, largest text")
        app.swipeUp()
        snap("Workouts, largest text, scrolled")
        try app.performAccessibilityAudit()
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
    // The cards are single accessibility elements: their texts are found inside their labels.
    @MainActor
    func element(containing text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
