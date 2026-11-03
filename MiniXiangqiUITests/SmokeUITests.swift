import XCTest

/// Three flows through the real app, on the Mac and on a phone: a move against
/// the AI and its Undo; a filed game replayed, shared and deleted from History;
/// one setting changed and kept.
@MainActor
final class SmokeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testPlayAMoveAgainstTheAIAndUndo() {
        let app = launch()
        startGameAgainstTheAI(app)

        playAndAwaitTheReply(app)

        tap(control(app, "cluster-undo"))
        XCTAssertTrue(waitForLabel(point(app, "b1"), containing: "炮"),
                      "Undo takes back the exchange and the cannon is home")
        XCTAssertTrue(waitForStatus(app, containing: "轮到红方"), "with Red to move")
    }

    func testReplayShareAndDeleteFromHistory() {
        let app = launch()
        startGameAgainstTheAI(app)
        playAndAwaitTheReply(app)

        tap(control(app, "cluster-resign"))
        tap(alertButton(app, "认输"))
        let replay = control(app, "result-replay")
        XCTAssertTrue(replay.waitForExistence(timeout: 10), "resigning files the game")

        tap(replay)
        let progress = control(app, "replay-progress")
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "History opens its replay")
        XCTAssertTrue(waitForText(progress, "0 / 2"), "at the start of the two plies")
        tap(control(app, "replay-next"))
        XCTAssertTrue(waitForText(progress, "1 / 2"), "and a step walks the record")
        goBack(app)

        let row = control(app, "history-row-0")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the record is in History's list")
        share(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "sharing leaves the record")

        delete(row, in: app)
        XCTAssertTrue(waitForAbsence(row), "and deleting removes it")
    }

    func testChangeOneSetting() {
        let app = launch()
        openDestination(app, 2)
        let confirm = control(app, "settings-confirm-delete")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        let before = isOn(confirm)

        toggle(confirm)
        XCTAssertTrue(waitForState(confirm, !before), "the switch moves")

        openDestination(app, 0)
        openDestination(app, 2)
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertEqual(isOn(confirm), !before, "and the preference is kept")

        toggle(confirm)
        XCTAssertTrue(waitForState(confirm, before))
    }

    // MARK: - Launching

    /// A scratch store per launch, so no flow plays into the player's library;
    /// the setup defaults are named through the argument domain, which outranks
    /// what the machine has stored without writing to it.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)",
                                "-mxq-store-name", "mxq-uitest-\(UUID().uuidString)",
                                "-defaults.firstMover", "human-first",
                                "-defaults.aiLevel", "fast"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        return app
    }

    private func startGameAgainstTheAI(_ app: XCUIApplication) {
        let mode = control(app, "mode-mini-xiangqi-human-versus-ai")
        XCTAssertTrue(mode.waitForExistence(timeout: 30))
        tap(mode)
        let start = control(app, "setup-start")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        tap(start)
        XCTAssertTrue(point(app, "b1").waitForExistence(timeout: 60), "the board opens")
        XCTAssertTrue(waitForStatus(app, containing: "轮到红方"))
    }

    /// Red's cannon to b4, then the AI's answer. The answer is awaited by state
    /// rather than by watching the status pass through Black's turn, which a
    /// fast reply can cross between two reads.
    private func playAndAwaitTheReply(_ app: XCUIApplication) {
        play(app, from: "b1", to: "b4")
        XCTAssertTrue(waitUntil {
            !point(app, "b1").label.contains("炮")
                && reading(control(app, "turn-status")).contains("轮到红方")
        }, "the move lands and the AI replies")
    }

    // MARK: - Addressing the app

    private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        control(app, "point-\(name)")
    }

    private func play(_ app: XCUIApplication, from: String, to: String) {
        tap(point(app, from))
        XCTAssertTrue(waitForLabel(point(app, from), containing: "已选择"))
        tap(point(app, to))
    }

    private func reading(_ element: XCUIElement) -> String {
        guard element.exists else { return "" }
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    private func isOn(_ element: XCUIElement) -> Bool {
        switch element.value {
        case let number as Int: number == 1
        case let text as String: text == "1"
        default: false
        }
    }

    // MARK: - Waiting

    private func waitUntil(_ timeout: TimeInterval = 60, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func waitForStatus(_ app: XCUIApplication, containing text: String) -> Bool {
        waitUntil { reading(control(app, "turn-status")).contains(text) }
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String) -> Bool {
        waitUntil(10) { element.exists && element.label.contains(text) }
    }

    private func waitForText(_ element: XCUIElement, _ text: String) -> Bool {
        waitUntil(10) { reading(element) == text }
    }

    private func waitForState(_ element: XCUIElement, _ on: Bool) -> Bool {
        waitUntil(5) { isOn(element) == on }
    }

    private func waitForAbsence(_ element: XCUIElement) -> Bool {
        waitUntil(10) { !element.exists }
    }

    // MARK: - The two platforms

    #if os(macOS)
    private func tap(_ element: XCUIElement) { element.click() }

    private func toggle(_ element: XCUIElement) { element.click() }

    private func alertButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let button = app.sheets.firstMatch.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        return button
    }

    private func openDestination(_ app: XCUIApplication, _ index: Int) {
        let sidebar = app.windows.firstMatch.outlines.element(boundBy: 0)
        let show = app.windows.firstMatch.toolbars.buttons["显示边栏"]
        if !sidebar.waitForExistence(timeout: 3), show.exists {
            // A narrow window collapses the sidebar.
            show.click()
        }
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        sidebar.cells.element(boundBy: index).click()
    }

    private func goBack(_ app: XCUIApplication) {
        app.windows.firstMatch.toolbars.buttons["chevron.backward"].click()
    }

    private func menuItem(_ title: String, on row: XCUIElement,
                          in app: XCUIApplication) -> XCUIElement {
        let item = app.menus[row.identifier].menuItems[title]
        for _ in 0..<3 {
            _ = waitUntil(5) { row.isHittable }
            row.rightClick()
            if item.waitForExistence(timeout: 3) { return item }
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTFail("the row's menu should offer \(title)")
        return item
    }

    private func share(_ row: XCUIElement, in app: XCUIApplication) {
        menuItem("共享", on: row, in: app).click()
        let picker = app.popovers.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the system's share picker opens")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(picker))
    }

    private func delete(_ row: XCUIElement, in app: XCUIApplication) {
        menuItem("删除", on: row, in: app).click()
        let confirm = app.sheets.firstMatch.buttons["删除"]
        if confirm.waitForExistence(timeout: 3) { confirm.click() }
    }
    #else
    private func tap(_ element: XCUIElement) { element.tap() }

    private func toggle(_ element: XCUIElement) {
        let inner = element.switches.firstMatch
        (inner.exists ? inner : element).tap()
    }

    private func alertButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let button = app.alerts.firstMatch.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        return button
    }

    private func openDestination(_ app: XCUIApplication, _ index: Int) {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons.element(boundBy: index).tap()
    }

    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func share(_ row: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        tap(app.buttons["共享"])
        let sheet = app.otherElements["ShareSheet.RemoteContainerView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the system's share sheet opens")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(waitForAbsence(sheet))
    }

    private func delete(_ row: XCUIElement, in app: XCUIApplication) {
        row.swipeLeft()
        tap(app.buttons["删除"])
        let confirm = app.alerts.firstMatch.buttons["删除"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
    }
    #endif
}
