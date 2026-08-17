// Jieqi on the running screen: the row, the dealt board, a move that turns a
// piece up, the surface that holds what a capture disclosed, and the row the
// filed game becomes.
//
// docs/interaction-design.md, "The Jieqi board" and "Captured pieces". What can
// only be seen here is that the deal reaches a board at all, that a face-down
// disc is announced by its side and as face down and by nothing else, that the
// piece that moved is face up where it landed, and that the captured surface is
// resident beside the board in this shape.
//
// **The two openings are legal whatever the deal is**, which is what makes this
// suite writable: a hidden piece moves as the piece whose square it stands on,
// so `b3b4` is a cannon's step and `b8b1` is a cannon's shot over the one screen
// that step left standing — and neither depends on what either piece turns out
// to be. Nothing here knows a deal.
//
// The words asserted are the accepted Simplified Chinese, written out rather
// than read from the application's own catalog: a test that reads the file the
// application reads asserts only that the file is itself.

// **macOS only**, like the other window-driving suites beside it.
#if os(macOS)

import XCTest

@MainActor
final class JieqiUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)"]
        app.launchArguments += ["-mxq-store-name", "mxq-uitest-store-" + UUID().uuidString]
        app.launchArguments += ["-mxq-defaults-suite", LaunchPreferences.scratchSuite]
        app.launchArguments += LaunchPreferences.arguments()
        // A window wide enough for the side-by-side shape, which is the one
        // this suite is about: the captured surface is resident in the panel
        // there, where the stacked shape reaches it from the toolbar instead.
        app.launchArguments += ["-mxq-window", "1100x760"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["point-\(name)"]
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)[identifier]
    }

    /// An element's text, waited for before it is read. A label taken from the
    /// snapshot a page was still assembling in reads back empty, and an
    /// assertion made there is a race that passes on a fast run.
    private func reading(_ element: XCUIElement,
                         file: StaticString = #filePath,
                         line: UInt = #line) -> String {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        // The value first where there is one, and the label otherwise — an
        // element with no value of its own reports an empty string rather than
        // nothing, which is exactly what a board point does.
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// One move, played the way a person plays it.
    private func play(_ app: XCUIApplication, _ from: String, _ to: String) {
        point(app, from).click()
        point(app, to).click()
    }

    /// The Play home's Jieqi section, opened to its Free Play page and started.
    private func startAGame(_ app: XCUIApplication) {
        let row = app.buttons["mode-jieqi-free-play"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the Jieqi section carries Free Play")
        XCTAssertEqual(row.label, "自由对弈")
        row.click()

        let start = app.buttons["setup-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(reading(app.staticTexts["setup-game"]), "揭棋")
        start.click()
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 20),
                      "开始对局 deals a game and opens the board on it")
    }

    // MARK: - The section, the deal, and the board

    /// The whole of the stage's flow in one run: the row, the dealt board, a
    /// reveal, a capture and its surface, and the History row the filed game
    /// becomes.
    func testAJieqiGameIsDealtPlayedAndFiled() {
        let app = launch()

        // Two rows, not three: the game has no AI to offer, and its nearby row
        // lands with the wire that carries it.
        XCTAssertTrue(app.staticTexts["揭棋"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["mode-jieqi-human-versus-ai"].exists,
                       "nothing in the app plays this game")

        startAGame(app)

        // **The dealt board.** Thirty discs face down on their own start
        // squares, the two generals face up between them — and a face-down disc
        // is announced by its side and as face down, never by what is under it.
        XCTAssertEqual(reading(point(app, "a1")), "a1 红 暗子")
        XCTAssertEqual(reading(point(app, "b3")), "b3 红 暗子")
        XCTAssertEqual(reading(point(app, "b8")), "b8 黑 暗子")
        XCTAssertEqual(reading(point(app, "e1")), "e1 红 帅",
                       "the generals are the only pieces that start face up")
        XCTAssertEqual(reading(point(app, "e10")), "e10 黑 将")
        XCTAssertEqual(reading(point(app, "e5")), "e5 空")

        // The Free Play cluster: 悔棋, 判和 and 翻转棋盘, and no 提示 — the
        // capability is not there rather than momentarily impossible.
        XCTAssertTrue(app.buttons["cluster-undo"].exists)
        XCTAssertTrue(app.buttons["cluster-claim"].exists)
        XCTAssertTrue(app.buttons["cluster-flip"].exists)
        XCTAssertFalse(app.buttons["hint-request"].exists,
                       "no engine plays this game, so there is nobody to ask")
        XCTAssertFalse(app.buttons["cluster-resign"].exists,
                       "and Free Play has no opponent to resign to")

        // The captured surface is resident beside the board, and says so before
        // anything has been taken.
        XCTAssertEqual(reading(element(app, "captured-empty")), "还没有棋子被吃。")
        attach(app, named: "80-the-dealt-jieqi-board")

        // **A move turns the piece up where it lands.** The piece on the
        // cannon's square moves as a cannon whatever it is, and arrives face up.
        play(app, "b3", "b4")
        XCTAssertTrue(app.staticTexts["轮到黑方"].waitForExistence(timeout: 10))
        XCTAssertEqual(reading(point(app, "b3")), "b3 空")
        let revealed = reading(point(app, "b4"))
        XCTAssertTrue(revealed.hasPrefix("b4 红 "),
                      "the piece is Red's and on b4 — it reads \(revealed)")
        XCTAssertFalse(revealed.contains("暗子"),
                       "and it is face up: a hidden piece flips on completing its move")

        // **A capture of a face-down piece.** Black's own cannon square takes
        // Red's b1 over the screen the first move left on b4, and what the
        // capture disclosed stands in the surface.
        play(app, "b8", "b1")
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 10))
        XCTAssertTrue(reading(point(app, "b1")).hasPrefix("b1 黑 "),
                      "Black's piece stands where Red's did")

        let red = reading(element(app, "captured-red"))
        XCTAssertTrue(red.hasPrefix("红 "),
                      "whose piece it was, then what it was — it reads \(red)")
        XCTAssertNotEqual(red, "红",
                          "a hidden capture is shown whole to its capturer, and in "
                          + "Free Play one person holds both hands")
        XCTAssertFalse(element(app, "captured-empty").exists)
        attach(app, named: "81-a-jieqi-capture")

        // What the move list draws for those two plies — the mover named by
        // its square's role and marked, with what it turned up last — is pinned
        // in the unit suite, where the reading can be asserted whole against
        // the position that produced it. The attachment above is where it is
        // seen on the screen.

        // **The filed game reads like any game's row.** Choosing another way to
        // play with a game active presents the accepted confirmation, which
        // archives this one before opening anything.
        app.buttons["play-back"].click()
        XCTAssertTrue(app.buttons["mode-xiangqi-free-play"].waitForExistence(timeout: 10))
        let card = reading(app.staticTexts["home-current-game"])
        XCTAssertTrue(card.contains("揭棋"),
                      "the current-game card names the game — it reads \(card)")
        app.buttons["mode-xiangqi-free-play"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5),
                      "a mode chosen with a game active presents the accepted "
                      + "confirmation rather than opening anything")
        app.sheets.firstMatch.buttons["保存并继续"].click()

        app.windows.firstMatch.outlines.element(boundBy: 0).cells.element(boundBy: 1).click()
        let row = app.windows.firstMatch.buttons["history-row-0"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(row.label.contains("揭棋 · 自由对弈"),
                      "the History row reads like any game's — it reads \(row.label)")
        XCTAssertTrue(row.label.contains("2 步"))
        attach(app, named: "82-a-filed-jieqi-game")
    }
}

#endif  // os(macOS)
