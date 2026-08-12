// Placing a stone on a phone: the board, the tap, and the optional confirmation.
//
// The smallest set that can only be answered by the running app. What lives in
// the unit suite is the grammar — what a tap on a point *means* — and what lives
// here is whether the app actually assembles a placement board out of it: the
// Play home's new row, the pre-start page, a board of 225 real points with
// Go-style coordinates around it, a tap that puts a stone down, and a cluster
// with the three controls these games do not carry absent from it.
//
// **The words asserted are the accepted Simplified Chinese**, written out rather
// than read from the application's own catalog, exactly as the other phone
// suites do it: a test that reads the file the application reads asserts only
// that the file is itself.
//
// What is deliberately not here: how the stone's click sounds, how the landing
// feels, and whether pitch 20 is a comfortable tap target — all three are the
// owner's device pass, and a Simulator is the wrong instrument for any of them.

#if os(iOS)

import XCTest

@MainActor
final class PhonePlacementUITests: XCTestCase {

    /// A Renju position with a double three at h8, which is a point Black may
    /// not play. Black holds the two points either side of h8 on the rank and
    /// the two either side of it on the file; White's four are in the corners,
    /// out of every line. Eight plies leaves Black to move, which is when the
    /// marks are on the board.
    private static let doubleThreeLine = "renju:g8,a1,i8,a15,h7,o1,h9,o15"

    private func scratchStoreName() -> String {
        "mxq-uitest-store-" + UUID().uuidString
    }

    private func launch(replaying line: String? = nil,
                        preferences: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)"]
        app.launchArguments += ["-mxq-store-name", scratchStoreName()]
        app.launchArguments += ["-mxq-defaults-suite", "mxq-uitests-phone"]
        app.launchArguments += ["-mxq-appearance", "light"]
        app.launchArguments += LaunchPreferences.arguments(overriding: preferences)
        if let line { app.launchArguments += ["-mxq-replay", line] }
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

    /// Opens a Free Play game of one of the new games from the home, the way a
    /// player reaches one.
    private func openFreePlay(_ app: XCUIApplication, row: String) {
        let entry = app.buttons[row]
        XCTAssertTrue(entry.waitForExistence(timeout: 10),
                      "the Play home carries a \(row) row")
        entry.tap()
        let start = app.buttons["setup-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5),
                      "the row opens that game's pre-start page")
        start.tap()
        XCTAssertTrue(point(app, "h8").waitForExistence(timeout: 15),
                      "开始对局 opens a board with points on it")
    }

    /// The whole visible surface of a placement game, reached the way a player
    /// reaches it and asserted where it stands.
    ///
    /// It would catch the Play home's new rows disappearing or leading to the
    /// wrong game, a board drawn at the wrong size, the coordinate strips
    /// reverting to the xiangqi numerals — which for a 15-rank board is the
    /// crash the nine-element numeral array would produce — a tap that placed
    /// nothing, and any of the three controls these games dropped coming back.
    func testFreePlayGomokuRendersAndPlacesAStone() {
        let app = launch()
        openFreePlay(app, row: "mode-gomoku-free-play")

        // A board of its own size: the corners exist and so does the centre.
        for name in ["a1", "o15", "a15", "o1", "h8"] {
            XCTAssertTrue(point(app, name).exists, "\(name) is a point of this board")
        }
        XCTAssertFalse(point(app, "p1").exists, "and the board stops at o")

        // Go-style coordinates: letters along the bottom, numbers up the side,
        // in place of the file-numeral strips the xiangqi boards carry.
        let letters = control(app, "file-letters")
        XCTAssertTrue(letters.exists, "the bottom edge carries the file letters")
        XCTAssertTrue(text(of: letters).contains("i"),
                      "no letter is skipped: the edge spells what the moves spell")
        XCTAssertTrue(control(app, "rank-numbers").exists,
                      "the side carries the rank numbers")
        XCTAssertFalse(control(app, "file-numerals-red").exists,
                       "and the xiangqi numeral strips are nowhere on this board")

        // Black moves first, in this game's own words.
        XCTAssertEqual(text(of: control(app, "turn-status")).contains("轮到黑方"), true,
                       "the status is \(text(of: control(app, "turn-status")))")

        // The cluster: 悔棋 alone in Free Play. 提示, 判和 and 翻转棋盘 are
        // capabilities these games do not have, and absence is what says so.
        XCTAssertTrue(control(app, "cluster-undo").exists)
        XCTAssertFalse(control(app, "hint-request").exists)
        XCTAssertFalse(control(app, "cluster-claim").exists)
        XCTAssertFalse(control(app, "cluster-flip").exists)

        // One tap, one stone.
        XCTAssertTrue(text(of: point(app, "h8")).contains("空"), "h8 starts empty")
        point(app, "h8").tap()
        let placed = expectation(description: "the stone is on h8")
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if text(of: point(app, "h8")).contains("黑") { placed.fulfill(); break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        wait(for: [placed], timeout: 1)
        XCTAssertTrue(text(of: control(app, "turn-status")).contains("轮到白方"),
                      "and the turn passes to White")
    }

    /// The pending stone, under the switch that turns it on.
    ///
    /// It would catch the confirmation being ignored — a tap placing a stone
    /// where it should only mark the point — the mark refusing to move to
    /// another point without being cancelled first, and the second tap on the
    /// mark failing to commit, which is the whole of what the switch buys.
    func testPendingStoneMarksThenCommits() {
        let app = launch(preferences: ["placementConfirmation.enabled": "1"])
        openFreePlay(app, row: "mode-gomoku-free-play")

        // The first tap marks rather than places.
        point(app, "h8").tap()
        XCTAssertTrue(text(of: point(app, "h8")).contains("待确认"),
                      "h8 reads \(text(of: point(app, "h8")))")
        XCTAssertTrue(text(of: point(app, "h8")).contains("空"),
                      "and there is no stone on it yet")

        // Another legal point moves the mark rather than placing anything.
        point(app, "i9").tap()
        XCTAssertTrue(text(of: point(app, "i9")).contains("待确认"))
        XCTAssertFalse(text(of: point(app, "h8")).contains("待确认"),
                       "the mark moved rather than multiplying")

        // Tapping the mark is the confirmation.
        point(app, "i9").tap()
        let placed = expectation(description: "the stone is on i9")
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if text(of: point(app, "i9")).contains("黑") { placed.fulfill(); break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        wait(for: [placed], timeout: 1)
        XCTAssertFalse(text(of: point(app, "i9")).contains("待确认"),
                       "and the mark is gone with the stone that took its place")
    }

    /// Renju's forbidden points, on the board and reachable by a screen reader.
    ///
    /// It would catch the marks never reaching the board — the derivation is in
    /// the unit suite, and this is whether the board is handed it — and a
    /// forbidden point that accepted a tap anyway, which would ask the core for
    /// a move it has already refused.
    func testRenjuMarksBlacksForbiddenPoints() {
        let app = launch(replaying: Self.doubleThreeLine)
        XCTAssertTrue(point(app, "h8").waitForExistence(timeout: 15))
        XCTAssertTrue(text(of: control(app, "turn-status")).contains("轮到黑方"),
                      "eight plies leaves Black to move")
        XCTAssertTrue(text(of: point(app, "h8")).contains("禁手"),
                      "h8 reads \(text(of: point(app, "h8")))")

        point(app, "h8").tap()
        XCTAssertTrue(text(of: point(app, "h8")).contains("空"),
                      "and a tap on it places nothing")
    }
}

#endif
