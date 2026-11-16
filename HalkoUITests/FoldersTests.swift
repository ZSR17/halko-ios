import XCTest

final class FoldersTests: XCTestCase {
    // A folder created from the + of the tab, which stays on the page, opened empty, renamed, then deleted.
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
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Upper body")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Workouts"].exists)
        snap("Workouts, folder created")

        folder.tap()
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

    // Reorder from a card touched and held: a workout dragged over another to take its place, then let go on a folder
    // to go in it, last; Done goes back to the page.
    @MainActor
    func testDrag() throws {
        let app = launch(language: "en", locale: "en_GB")
        let fullBody = app.card("Full body express")
        let core = app.card("Core 15 min")
        XCTAssertTrue(core.waitForExistence(timeout: 5))
        XCTAssertLessThan(fullBody.frame.minY, core.frame.minY)

        core.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Reorder"].waitForExistence(timeout: 5))
        app.buttons["Reorder"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Touch and hold a card").exists)
        snap("Workouts, reordering")

        core.press(forDuration: 1, thenDragTo: fullBody, withVelocity: .slow, thenHoldForDuration: 0.5)
        wait(until: core.frame.minY < fullBody.frame.minY)
        snap("Workouts, dragged")

        let program = app.card("PPL program")
        fullBody.press(forDuration: 1, thenDragTo: program, withVelocity: .slow, thenHoldForDuration: 0.5)
        wait(until: program.label.contains("4 workouts"))
        XCTAssertFalse(fullBody.exists)
        // Where it went, said for a moment.
        XCTAssertTrue(app.element(containing: "moved to").waitForExistence(timeout: 2))
        snap("Workouts, filed in a folder")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Workouts"].buttons["Add"].waitForExistence(timeout: 5))
        program.tap()
        XCTAssertTrue(app.navigationBars["PPL program"].waitForExistence(timeout: 5))
        let legs = app.card("Legs")
        XCTAssertTrue(fullBody.waitForExistence(timeout: 5))
        XCTAssertLessThan(legs.frame.minY, fullBody.frame.minY)
        snap("Folder, dropped in")
    }

    // A card touched and held without moving: what can be done of it, as in the menu of its page.
    @MainActor
    func testCardMenus() throws {
        let app = launch(language: "en", locale: "en_GB")
        let core = app.card("Core 15 min")
        XCTAssertTrue(core.waitForExistence(timeout: 5))

        core.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Duplicate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Move to folder"].exists)
        snap("Workouts › Card menu")
        app.buttons["Duplicate"].tap()
        XCTAssertTrue(app.card("Core 15 min (copy)").waitForExistence(timeout: 5))

        app.card("PPL program").press(forDuration: 1)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["New workout here"].exists)
        snap("Workouts › Folder menu")
        app.buttons["Delete the folder"].tap()
        XCTAssertTrue(app.element(containing: "go back to Workouts").waitForExistence(timeout: 5))
        snap("Workouts › Delete a folder")
        app.buttons.matching(identifier: "Delete the folder").firstMatch.tap()
        wait(until: !app.card("PPL program").exists)
        XCTAssertTrue(app.card("Push A").waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddInFrench() throws {
        let app = launch(language: "fr", locale: "fr_FR")

        app.navigationBars["Séances"].buttons["Ajouter"].tap()
        XCTAssertTrue(app.buttons["Nouveau dossier"].waitForExistence(timeout: 5))
        snap("Séances › Ajouter")
    }

    // The cards move with an animation.
    @MainActor
    private func wait(until condition: @autoclosure () -> Bool) {
        let deadline = Date.now.addingTimeInterval(5)
        while !condition() && Date.now < deadline {
            RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        }
        XCTAssertTrue(condition())
    }
}

private extension XCUIApplication {
    // A card of a workout or of a folder, by the start of its label: a button, or, while reordering, a card only dragged.
    func card(_ label: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }
}
