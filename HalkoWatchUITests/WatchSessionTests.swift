import XCTest

final class WatchSessionTests: XCTestCase {
    // The bench press of Push A: 4 warm-ups, then a working set that beats the 1RM of the session done before.
    @MainActor
    func testSession() throws {
        let app = openPushA()
        app.buttons["Démarrer"].tap()
        let proceed = app.buttons["Continuer"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "Avant ta première séance").exists)
        try app.performAccessibilityAudit()
        snap("Watch – Avant ta première séance")
        proceed.tap()

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
        XCTAssertTrue(app.buttons["Continuer la séance"].exists)
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
        start(app)
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
        snap("Watch – Abandonner la séance")
        confirm.tap()
        XCTAssertTrue(pushA(app).waitForExistence(timeout: 5))
    }

    // Every set of a workout validated: the session can only be finished.
    @MainActor
    func testAllDone() throws {
        let app = launchApp()
        let quick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Quick'")).firstMatch
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        scrollTo(quick, in: app)
        quick.tap()
        XCTAssertTrue(app.buttons["Démarrer"].waitForExistence(timeout: 5))
        start(app)

        let validate = app.buttons["Valider"]
        XCTAssertTrue(validate.waitForExistence(timeout: 10))
        validate.tap()
        let skip = app.buttons["Passer"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(validate.waitForExistence(timeout: 5))
        validate.tap()

        XCTAssertTrue(text(app, "Toutes les séries sont faites").waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
        snap("Watch – Toutes les séries faites")
        XCTAssertTrue(app.buttons["Terminer la séance"].exists)
    }

    // The sample workouts, in a database kept in memory, on the page of Push A.
    @MainActor
    private func openPushA() -> XCUIApplication {
        let app = launchApp()
        let push = pushA(app)
        XCTAssertTrue(push.waitForExistence(timeout: 10))
        push.tap()
        XCTAssertTrue(app.buttons["Démarrer"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        return app
    }

    // Start, through « Before your first workout ».
    @MainActor
    private func start(_ app: XCUIApplication) {
        app.buttons["Démarrer"].tap()
        let proceed = app.buttons["Continuer"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 5))
        proceed.tap()
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
