import XCTest

extension XCTestCase {
    // A screenshot kept in the test results: the CI publishes it with the run, to see the screen without a Mac.
    @MainActor
    func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // The sample data, in a database kept in memory.
    @MainActor
    func launch(language: String, locale: String, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        return app
    }
}
