import XCTest

/// Fluxos críticos. O argumento `-uitesting` faz o app usar um banco em memória.
final class DayliUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitesting"]
        app.launch()
        return app
    }

    /// Textos dentro de botões são expostos como parte do rótulo do botão; buscamos em qualquer elemento.
    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func completeOnboarding(_ app: XCUIApplication) {
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Luíza\n")
        let next = app.buttons["onboarding.next"]
        for _ in 0..<4 { next.tap() }
    }

    func testOnboardingLeadsToToday() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(app.tabBars.buttons["Hoje"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Luíza").waitForExistence(timeout: 5))
    }

    func testQuickAddTaskAppearsAndCanBeCompleted() {
        let app = launch()
        completeOnboarding(app)
        app.tabBars.buttons["Tarefas"].tap()
        let field = app.textFields["tasks.quickAdd"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Enviar relatório\n")
        XCTAssertTrue(element(app, containing: "Enviar relatório").waitForExistence(timeout: 5))

        app.tabBars.buttons["Hoje"].tap()
        XCTAssertTrue(element(app, containing: "Enviar relatório").waitForExistence(timeout: 5))
        app.buttons["Não concluída"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Concluída"].firstMatch.waitForExistence(timeout: 5))
    }

    func testPlannerOpensWithoutChangingData() {
        let app = launch()
        completeOnboarding(app)
        app.buttons["today.organize"].tap()
        XCTAssertTrue(app.navigationBars["Organizar meu dia"].waitForExistence(timeout: 5))
        app.buttons["Fechar"].tap()
    }
}
