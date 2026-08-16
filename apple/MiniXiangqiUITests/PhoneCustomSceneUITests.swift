// Composing a Custom Scene on a phone: the row, the editor, and the game it
// starts.
//
// The smallest set that can only be answered by the running app on this
// platform. What lives in the unit suite is the draft and what the core says
// about it, and what the macOS suite drives is the same flow beside a panel;
// what is only true here is that the editor assembles in the **stacked** shape
// — an interactive board fitted to the phone's width with the palette, the side
// choice and 开始对局 beneath it, all of them reachable — and that a scene game
// opens on the board from there.
//
// **The words asserted are the accepted Simplified Chinese**, written out
// rather than read from the application's own catalog, exactly as the other
// phone suites do it.

#if os(iOS)

import XCTest

@MainActor
final class PhoneCustomSceneUITests: XCTestCase {

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

    private func text(of element: XCUIElement) -> String {
        guard element.exists else { return "" }
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    /// Puts one piece down: pick the entry, then tap the point.
    private func place(_ app: XCUIApplication, _ side: String, _ letter: String,
                       at square: String) {
        app.buttons["palette-\(side)-\(letter)"].tap()
        point(app, square).tap()
    }

    /// The editor's core flow on the stacked layout, reached the way a player
    /// reaches it.
    ///
    /// It would catch the row missing from the phone's home, an editor whose
    /// board or palette does not fit the width the stacked shape gives it, a
    /// tap that placed nothing, a 开始对局 that stayed disabled over a legal
    /// playable position, and a scene game that opened on the wrong side.
    func testComposingASceneAndStartingItOnAPhone() {
        let app = launch()

        let row = app.buttons["mode-xiangqi-custom-scene"]
        XCTAssertTrue(row.waitForExistence(timeout: 30),
                      "the Play home carries the Custom Scene row on a phone too")
        XCTAssertEqual(row.label, "自定排局")
        row.tap()

        let start = app.buttons["scene-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the row opens the editor")
        XCTAssertTrue(point(app, "e1").exists,
                      "with an interactive board fitted into the stacked shape")
        XCTAssertFalse(start.isEnabled, "an empty board is no position to start from")
        XCTAssertEqual(text(of: control(app, "scene-reason")), "先给双方各放一个将帅。")

        place(app, "red", "k", at: "e1")
        place(app, "black", "k", at: "d10")
        place(app, "red", "r", at: "a1")
        XCTAssertEqual(point(app, "a1").label, "a1 红 俥", "the piece went where it was put")
        XCTAssertTrue(start.isEnabled, "a legal, playable position is one to start from")

        // The side to move is a choice on the page, and Black is what this
        // scene begins with.
        app.buttons["黑"].tap()
        start.tap()

        XCTAssertTrue(point(app, "d10").waitForExistence(timeout: 20),
                      "开始对局 opens the board on the composed position")
        XCTAssertEqual(point(app, "d10").label, "d10 黑 将")
        XCTAssertTrue(text(of: control(app, "turn-status")).contains("轮到黑方"),
                      "with Black to move — it reads "
                      + text(of: control(app, "turn-status")))
    }
}

#endif  // os(iOS)
