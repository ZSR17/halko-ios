import XCTest

final class FoldersTests: XCTestCase {
    // A folder created from the + of the tab, opened empty, renamed, then deleted.
    @MainActor
    func testFolder() throws {
        let app = launch(language: "en", locale: "en_GB")

        app.navigationBars["Workouts"].buttons["Add"].tap()
        XCTAssertTrue(app.buttons["New folder"].waitForExistence(timeout: 5))
        snap("Workouts › Add")
        app.buttons["New folder"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.buttons["Create"].isEnabled)
        field.typeText("Upper body")
        snap("Workouts › New folder")
        app.alerts.buttons["Create"].tap()

        XCTAssertTrue(app.navigationBars["Upper body"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "No workouts in this folder").exists)
        try app.auditScreen()
        snap("Folder, empty")

        app.buttons["More actions"].tap()
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
        snap("Folder › More actions")
        app.buttons["Rename"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText(" 2")
        app.alerts.buttons["Rename"].tap()
        XCTAssertTrue(app.navigationBars["Upper body 2"].waitForExistence(timeout: 5))

        app.buttons["More actions"].tap()
        app.buttons["Delete the folder"].tap()
        let confirm = app.buttons.matching(identifier: "Delete the folder").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snap("Folder › Delete")
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.element(containing: "Upper body").exists)
    }

    @MainActor
    func testReorder() throws {
        let app = launch(language: "en", locale: "en_GB")

        app.navigationBars["Workouts"].buttons["Reorder"].tap()
        XCTAssertTrue(app.element(containing: "Workouts in no folder").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Mobility").exists)
        try app.auditScreen()
        snap("Workouts › Reorder")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Reorder"].waitForExistence(timeout: 5))

        // In a folder, from its menu.
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "PPL program")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["PPL program"].waitForExistence(timeout: 5))
        app.buttons["More actions"].tap()
        app.buttons["Reorder"].tap()
        XCTAssertTrue(app.element(containing: "Pull A").waitForExistence(timeout: 5))
        snap("Folder › Reorder")
    }

    @MainActor
    func testReorderInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")

        app.navigationBars["Séances"].buttons["Réorganiser"].tap()
        XCTAssertTrue(app.element(containing: "Séances hors dossier").waitForExistence(timeout: 5))
        snap("Séances › Réorganiser")
        app.buttons["OK"].tap()
        app.navigationBars["Séances"].buttons["Ajouter"].tap()
        XCTAssertTrue(app.buttons["Nouveau dossier"].waitForExistence(timeout: 5))
        snap("Séances › Ajouter")
    }
}
