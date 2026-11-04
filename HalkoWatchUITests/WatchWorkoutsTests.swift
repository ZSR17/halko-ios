import XCTest

final class WatchWorkoutsTests: XCTestCase {
    // The sample workouts, in a database kept in memory, as the iPhone would have sent them.
    @MainActor
    func testWorkouts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()

        let push = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Push A'")).firstMatch
        XCTAssertTrue(push.waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
        snap("Watch 1 – Séances")

        push.tap()
        // 5 exercises, 4 + 3 + 3 + 3 + 3 working sets: the warm-ups are not counted.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '5 exercices · 16 séries'")).firstMatch.waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
        snap("Watch 2 – Push A")
        app.swipeUp()
        snap("Watch 2 – Push A, bas")
    }

    // A screenshot kept in the test results: the CI publishes it with the run.
    @MainActor
    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
