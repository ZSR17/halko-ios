import XCTest

final class RootTests: XCTestCase {
    func testTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        for tab in ["Workouts", "Exercises", "History", "Tools", "Settings"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
            try app.performAccessibilityAudit()
            snap(tab)
        }
    }
}
