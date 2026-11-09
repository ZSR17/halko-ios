import XCTest

final class ToolsTests: XCTestCase {
    @MainActor
    func testPlates() throws {
        // Kilograms, as the sample plates.
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(app.navigationBars["Tools"].waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Tools")

        app.buttons["Plate calculator"].tap()
        XCTAssertTrue(app.element(containing: "Per side: 1 × 25 kg + 1 × 15 kg").waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Plates")

        // One step up cannot be made with these plates: the closest loads instead.
        app.buttons["Add 0.5 kg"].tap()
        XCTAssertTrue(app.element(containing: "with your plates").waitForExistence(timeout: 5))
        snap("Plates, closest")

        app.buttons["Add a plate"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        snap("Plates › Add a plate")
    }

    @MainActor
    func testOneRepMax() throws {
        let app = launch(language: "en", locale: "en_GB")
        app.tabBars.buttons["Tools"].tap()
        let tool = app.buttons["1RM calculator"]
        XCTAssertTrue(tool.waitForExistence(timeout: 5))
        tool.tap()
        XCTAssertTrue(app.element(containing: "Estimated 1RM").waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("1RM")

        // From the best set of an exercise done.
        app.buttons["Exercise"].tap()
        let bench = app.buttons["Barbell Bench Press - Medium Grip"]
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()
        XCTAssertTrue(app.element(containing: "Estimated 1RM").waitForExistence(timeout: 5))
        snap("1RM, from an exercise")

        // A line of the table opens the plates for its weight.
        app.collectionViews.firstMatch.swipeUp()
        let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "95")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.tap()
        XCTAssertTrue(app.navigationBars["Plate calculator"].waitForExistence(timeout: 5))
        snap("1RM › Plates")
    }

    @MainActor
    func testToolsInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")
        app.tabBars.buttons["Outils"].tap()
        let tool = app.buttons["Calculateur de disques"]
        XCTAssertTrue(tool.waitForExistence(timeout: 5))
        tool.tap()
        XCTAssertTrue(app.element(containing: "Par côté").waitForExistence(timeout: 5))
        snap("Disques")
    }

    @MainActor
    func testPlatesWithLargestText() throws {
        let app = launch(language: "en", locale: "en_GB", textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.tabBars.buttons["Tools"].tap()
        let tool = app.buttons["Plate calculator"]
        XCTAssertTrue(tool.waitForExistence(timeout: 5))
        tool.tap()
        XCTAssertTrue(app.element(containing: "Total weight").waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("Plates, largest text")
    }
}
