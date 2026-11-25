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
        snap("Duo › Workouts")

        app.element(containing: "Full body express").tap()
        XCTAssertTrue(app.navigationBars["Full body express"].waitForExistence(timeout: 5))
        // The list stays beside.
        XCTAssertTrue(app.element(containing: "Pull A").exists)
        snap("Duo › Workouts › Full body express")
    }

    @MainActor
    func testWorkoutsInTwoColumnsInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")

        XCTAssertTrue(app.element(containing: "Push A · en cours").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Échauffement auto").waitForExistence(timeout: 30))
        snap("Duo › Séances")
    }
}
