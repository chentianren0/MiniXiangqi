// Jieqi on a phone: the dealt board in the stacked shape, and the captured
// surface reached rather than resident.
//
// The smallest set that can only be answered by the running app on this
// platform. What lives in the unit suite is the deal, the reading and the
// disclosure rule; what the macOS suite drives is the same flow beside a panel,
// where the captured surface is a section of it. What is only true here is that
// the board fits the phone's width with thirty face-down discs on it, and that
// the surface holding what a capture disclosed is reached from the board's own
// toolbar — the move list's precedent, for the move list's reason: the board
// keeps its pitch floor before anything else is given room.
//
// **The two openings are legal whatever the deal is**: a hidden piece moves as
// the piece whose square it stands on, so `b3b4` is a cannon's step and `b8b1`
// is a cannon's shot over the screen that step left standing. Nothing here
// knows a deal.
//
// **The words asserted are the accepted Simplified Chinese**, written out rather
// than read from the application's own catalog, exactly as the other phone
// suites do it.

#if os(iOS)

import XCTest

@MainActor
final class PhoneJieqiUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)"]
        app.launchArguments += ["-mxq-store-name", "mxq-uitest-store-" + UUID().uuidString]
        app.launchArguments += ["-mxq-defaults-suite", "mxq-uitests-phone"]
        app.launchArguments += ["-mxq-appearance", "light"]
        app.launchArguments += LaunchPreferences.arguments()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                      "the app should reach the foreground")
        return app
    }

    private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        control(app, "point-\(name)")
    }

    private func play(_ app: XCUIApplication, _ from: String, _ to: String) {
        point(app, from).tap()
        point(app, to).tap()
    }

    /// An element, waited for before it is read.
    private func settled(_ element: XCUIElement,
                         file: StaticString = #filePath,
                         line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        return element
    }

    /// An element's text, waited for before it is read. A label taken from the
    /// snapshot a page was still assembling in reads back empty, and an
    /// assertion made there is a race that passes on a fast run.
    private func reading(_ element: XCUIElement,
                         file: StaticString = #filePath,
                         line: UInt = #line) -> String {
        let element = settled(element, file: file, line: line)
        // The value first where there is one, and the label otherwise — an
        // element with no value of its own reports an empty string rather than
        // nothing, which is exactly what a board point does.
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    func testADealtGameIsPlayedAndItsCapturesAreReached() {
        let app = launch()

        let row = app.buttons["mode-jieqi-free-play"]
        XCTAssertTrue(row.waitForExistence(timeout: 30),
                      "the Play home carries the Jieqi section on a phone too")
        XCTAssertEqual(row.label, "自由对弈")
        XCTAssertFalse(app.buttons["mode-jieqi-human-versus-ai"].exists,
                       "nothing in the app plays this game")
        row.tap()

        let start = settled(app.buttons["setup-start"])
        XCTAssertEqual(reading(app.staticTexts["setup-game"]), "揭棋")
        start.tap()

        // The dealt board, fitted into the stacked shape: every point of it is
        // addressable, and a face-down disc says whose it is and no more.
        XCTAssertTrue(point(app, "a1").waitForExistence(timeout: 20))
        XCTAssertEqual(reading(point(app, "a1")), "a1 红 暗子")
        XCTAssertEqual(reading(point(app, "b8")), "b8 黑 暗子")
        XCTAssertEqual(reading(point(app, "e1")), "e1 红 帅",
                       "the generals are the only pieces that start face up")
        XCTAssertEqual(reading(point(app, "e5")), "e5 空")
        XCTAssertFalse(app.buttons["hint-request"].exists,
                       "no engine plays this game, so there is nobody to ask")

        // A move turns the piece up where it lands.
        play(app, "b3", "b4")
        XCTAssertEqual(reading(point(app, "b3")), "b3 空")
        let revealed = reading(point(app, "b4"))
        XCTAssertTrue(revealed.hasPrefix("b4 红 "),
                      "the piece is Red's and on b4 — it reads \(revealed)")
        XCTAssertFalse(revealed.contains("暗子"),
                       "and it is face up: a hidden piece flips on completing its move")

        // Black's cannon square takes Red's b1 over the screen that move left
        // standing on b4.
        play(app, "b8", "b1")
        XCTAssertTrue(reading(point(app, "b1")).hasPrefix("b1 黑 "),
                      "Black's piece stands where Red's did")

        // **The captured surface is reached rather than resident here**, from
        // the board's own toolbar, and what the capture disclosed stands in it.
        let opener = settled(app.buttons["play-captured"])
        opener.tap()
        let red = reading(control(app, "captured-red"))
        XCTAssertTrue(red.hasPrefix("红 "),
                      "whose piece it was, then what it was — it reads \(red)")
        XCTAssertNotEqual(red, "红",
                          "a hidden capture is shown whole to its capturer, and in "
                          + "Free Play one person holds both hands")
        settled(app.buttons["captured-done"]).tap()
        XCTAssertTrue(point(app, "b1").waitForExistence(timeout: 10),
                      "and the board is where it was")
    }
}

#endif  // os(iOS)
