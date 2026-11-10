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

        // One step up cannot be made with these plates: the closest loads instead, below and above.
        app.buttons["Add 0.5 kg"].tap()
        let below = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Below")).firstMatch
        XCTAssertTrue(below.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Above")).firstMatch.exists)
        try app.auditScreen()
        snap("Plates, closest")
        below.tap()
        XCTAssertTrue(app.element(containing: "Per side: 1 × 25 kg + 1 × 15 kg").waitForExistence(timeout: 5))

        // Held down, + goes on adding.
        let total = app.textFields["Total weight"]
        let before = try XCTUnwrap(kilograms(total))
        app.buttons["Add 0.5 kg"].press(forDuration: 2)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(kilograms(total)), before + 1.5)

        // A plate typed wrong is corrected, not deleted.
        let plate = app.buttons["Edit the plate of 25 kg"]
        app.reveal(plate)
        plate.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        snap("Plates › Edit the plate")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "30")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Edit the plate of 30 kg"].waitForExistence(timeout: 5))

        app.reveal(app.buttons["Add a plate"])
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
        XCTAssertTrue(app.buttons["Exercise"].waitForExistence(timeout: 5))
        try app.auditScreen()
        snap("1RM")

        // From the best set of an exercise done.
        app.buttons["Exercise"].tap()
        let bench = app.buttons["Barbell Bench Press - Medium Grip"]
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()
        XCTAssertTrue(app.buttons["Exercise"].waitForExistence(timeout: 5))
        snap("1RM, from an exercise")

        // The estimate opens the plates for its weight.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Estimated 1RM")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Plate calculator"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Exercise"].waitForExistence(timeout: 5))

        // A line of the table opens the plates for its weight.
        let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "95")).firstMatch
        app.reveal(line)
        XCTAssertTrue(app.element(containing: "Estimated 1RM").exists)
        snap("1RM, table")
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

    // The value of a box in kilograms, typed in English.
    @MainActor
    private func kilograms(_ field: XCUIElement) -> Double? {
        (field.value as? String).flatMap { Double($0) }
    }
}

extension XCUIApplication {
    // The rows of a list exist only once near the screen.
    @MainActor
    func reveal(_ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable && swipes < 6 {
            collectionViews.firstMatch.swipeUp(velocity: .slow)
            swipes += 1
        }
    }
}
