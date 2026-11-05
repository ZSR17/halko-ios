import XCTest

final class WatchSessionTests: XCTestCase {
    // The bench press of Push A: 4 warm-ups, then a working set that beats the 1RM of the session done before.
    @MainActor
    func testSession() throws {
        let app = openPushA()
        app.buttons["Démarrer"].tap()

        let validate = app.buttons["Valider"]
        XCTAssertTrue(validate.waitForExistence(timeout: 10))
        XCTAssertTrue(text(app, "Échauffement 1 / 4").waitForExistence(timeout: 5))
        snap("Watch 3 – Échauffement")

        let skip = app.buttons["Passer"]
        for _ in 1...4 {
            validate.tap()
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
            XCTAssertTrue(validate.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(text(app, "Série 1 / 4").waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
        snap("Watch 3 – Série en cours")

        validate.tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "Série 2 / 4").waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
        snap("Watch 4 – Repos")
        let add = app.buttons["Ajouter 15 secondes"]
        XCTAssertTrue(add.exists)
        add.tap()
        app.buttons["Retirer 15 secondes"].tap()

        app.swipeLeft()
        XCTAssertTrue(text(app, "Ensuite").waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
        snap("Watch 5 – Métriques")

        let finish = app.buttons["Terminer"]
        scrollTo(finish, in: app)
        snap("Watch 5 – Métriques, bas")
        finish.tap()
        let save = app.buttons["Enregistrer la séance"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        snap("Watch – Terminer la séance")
        save.tap()

        XCTAssertTrue(text(app, "Séance enregistrée").waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "Record").waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
        snap("Watch 6 – Résumé")

        app.buttons["OK"].tap()
        XCTAssertTrue(pushA(app).waitForExistence(timeout: 5))
    }

    // Without a set done, only discarding is offered; nothing stays of the session.
    @MainActor
    func testDiscard() throws {
        let app = openPushA()
        app.buttons["Démarrer"].tap()
        XCTAssertTrue(text(app, "Échauffement 1 / 4").waitForExistence(timeout: 10))

        app.swipeLeft()
        let finish = app.buttons["Terminer"]
        scrollTo(finish, in: app)
        finish.tap()
        let discard = app.buttons["Abandonner la séance"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Enregistrer la séance"].exists)
        discard.tap()
        let confirm = app.buttons["Abandonner"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(pushA(app).waitForExistence(timeout: 5))
    }

    // The sample workouts, in a database kept in memory, on the page of Push A.
    @MainActor
    private func openPushA() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        let push = pushA(app)
        XCTAssertTrue(push.waitForExistence(timeout: 10))
        push.tap()
        XCTAssertTrue(app.buttons["Démarrer"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func pushA(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Push A'")).firstMatch
    }

    @MainActor
    private func text(_ app: XCUIApplication, _ part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
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
