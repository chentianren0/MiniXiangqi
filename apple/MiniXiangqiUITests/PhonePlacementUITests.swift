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

    /// One gibibyte of "available", which the accepted arithmetic turns into a
    /// 768 MiB Hash: over the 256 MiB minimum, and small enough that a launch
    /// does not spend its time in the allocator. The same figure the other
    /// suites force, for the same reason — and it applies to whichever engine a
    /// game is played on, there being one memory policy for both.
    private static let modestMemory = "1073741824"

    private func launch(replaying line: String? = nil,
                        preferences: [String: String] = [:],
                        availableMemory: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)"]
        app.launchArguments += ["-mxq-store-name", scratchStoreName()]
        app.launchArguments += ["-mxq-defaults-suite", "mxq-uitests-phone"]
        app.launchArguments += ["-mxq-appearance", "light"]
        app.launchArguments += LaunchPreferences.arguments(overriding: preferences)
        if let availableMemory {
            app.launchArguments += ["-mxq-available-memory", availableMemory]
        }
        if let line { app.launchArguments += ["-mxq-replay", line] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                      "the app should reach the foreground")
        return app
    }

    /// Waits for the turn status to say something.
    private func waitForStatus(_ app: XCUIApplication, containing wanted: String,
                               timeout: TimeInterval = 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if text(of: control(app, "turn-status")).contains(wanted) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
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

        // The cluster: 提示 and 悔棋 in Free Play. 判和 and 翻转棋盘 are
        // capabilities these games do not have, and absence is what says so.
        XCTAssertTrue(control(app, "hint-request").exists)
        XCTAssertTrue(control(app, "cluster-undo").exists)
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

    // MARK: - Playing the machine

    /// A whole human-versus-AI game of Gomoku, from the home row to a reply.
    ///
    /// It would catch the interface gap this stage exists to close: readiness is
    /// two identifiers compared, and while the frontend composed one of them out
    /// of the *first* engine's revision the comparison could never match for a
    /// game the second engine plays — so preparation succeeded, readiness stayed
    /// false, and the reply loop asked for another preparation for ever. Nothing
    /// short of a real game against a real search shows that: the engine really
    /// prepares, the status really leaves the machine's side, and no stub can be
    /// wrong in the way the real one was.
    ///
    /// It also carries the side mapping end to end. **我先手 maps to Black**,
    /// which is the first mover in every game and the dark stone in these two,
    /// and the only proof of that is the stone the player's own tap puts down.
    ///
    /// 快速 keeps it to a second a move.
    func testHumanVersusAIGomokuGivesThePlayerBlackAndTheMachineAnswers() {
        let app = launch(preferences: ["defaults.aiLevel": "fast",
                                       "defaults.firstMover": "human-first"],
                         availableMemory: Self.modestMemory)

        let entry = app.buttons["mode-gomoku-human-versus-ai"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15),
                      "the Play home carries Gomoku's 人机对弈 row")
        entry.tap()
        let start = app.buttons["setup-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5),
                      "the row opens Gomoku's own pre-start page")
        start.tap()
        XCTAssertTrue(point(app, "h8").waitForExistence(timeout: 60),
                      "开始对局 prepares the placement engine and opens the board")

        // The cluster this mode carries: 提示, 悔棋 and 认输, and neither of the
        // two these games do not have.
        XCTAssertTrue(control(app, "hint-request").exists)
        XCTAssertTrue(control(app, "cluster-undo").exists)
        XCTAssertTrue(control(app, "cluster-resign").exists)
        XCTAssertFalse(control(app, "cluster-claim").exists)
        XCTAssertFalse(control(app, "cluster-flip").exists)

        // 我先手 resolved the first mover, and the first mover is Black here.
        XCTAssertTrue(waitForStatus(app, containing: "轮到黑方", timeout: 10),
                      "the status reads \(text(of: control(app, "turn-status")))")
        XCTAssertTrue(waitForStatus(app, containing: "你", timeout: 5),
                      "and the controller label names the turn as the player's own")

        point(app, "h8").tap()
        XCTAssertTrue(waitForLabel(point(app, "h8"), containing: "黑"),
                      "我先手 put a black stone down — h8 reads "
                      + text(of: point(app, "h8")))

        // The machine's answer. Which point it takes is its own business, so
        // what is asserted is that it took one and handed the turn back.
        //
        // **Its own turn is not asserted, and cannot honestly be**: the bridge
        // leaves the engine's trivial-opening probe on, so a reply to a board
        // with one stone on it comes back without a search — measured here, in
        // less time than this process's first query into the tree after the tap.
        // A poll for 轮到白方 would be asserting this process's sampling rate
        // rather than the app, which is the lesson `PhonePlayUITests` already
        // carries about waiting to *observe* a turn.
        //
        // The stone is what makes the durable claim whole. The turn coming back
        // says a ply was committed; a white stone on the board says the machine
        // is what committed it.
        XCTAssertTrue(waitForStatus(app, containing: "轮到黑方", timeout: 120),
                      "the machine answers within its own thinking time and hands "
                      + "the turn back — the status reads "
                      + text(of: control(app, "turn-status")))
        let whiteStones = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                  "point-", "白"))
        XCTAssertGreaterThan(whiteStones.count, 0,
                             "and it answered with a stone of its own")
    }

    // MARK: - The hint, in the placement grammar

    /// **提示 on a board that places is the pending stone.** The engine's
    /// suggestion arrives as the mark, at a point the player did not touch, and
    /// tapping the mark plays the move through the ordinary input path.
    ///
    /// It would catch the presentation reverting to the movement grammar, which
    /// fails silently and is why this is worth a running app: the control is
    /// pressable, the search runs, the answer comes back, and the board never
    /// changes. It also covers the lazy preparation a Free Play hint needs —
    /// this is the first thing that ever asks the *second* engine to be prepared
    /// outside game creation.
    ///
    /// The board is read across the press as well, which is the #181 rule: a
    /// board in the stacked shape is sized from the cluster's reserved slot and
    /// does not follow it, so a hint's indicator standing in the lamp's place
    /// must move nothing. It is two reads here rather than a sampling loop —
    /// this control was already on the row before the press, so what is left to
    /// catch is an indicator that measures differently from the lamp, and that
    /// shows at the answer.
    func testTheHintIsThePendingStoneAndTappingItPlaysIt() {
        let app = launch(preferences: ["defaults.aiLevel": "fast"],
                         availableMemory: Self.modestMemory)
        openFreePlay(app, row: "mode-gomoku-free-play")

        let hint = control(app, "hint-request")
        XCTAssertTrue(hint.isEnabled, "either turn is the player's own in Free Play")
        let before = boardCorners(app)
        hint.tap()

        // The suggested point is found by the state it carries, never by name:
        // the engine chooses the point, and the board says which one it chose.
        let suggested = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "建议")).firstMatch
        XCTAssertTrue(suggested.waitForExistence(timeout: 120),
                      "a suggestion should arrive within the level's thinking time")
        XCTAssertTrue(text(of: suggested).contains("待确认"),
                      "and it is the pending stone standing at the point — it reads "
                      + text(of: suggested))
        XCTAssertTrue(text(of: suggested).contains("空"),
                      "with nothing committed by showing it")
        assertBoardIsWhereItWas(boardCorners(app), before,
                                "the board should not move when a hint is asked for")

        // Tapping the mark plays it, exactly as tapping a mark the player raised
        // themselves does.
        suggested.tap()
        XCTAssertTrue(waitForStatus(app, containing: "轮到白方", timeout: 15),
                      "tapping the suggestion plays it and the turn passes — the "
                      + "status reads " + text(of: control(app, "turn-status")))
        XCTAssertEqual(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "建议")).count, 0,
                       "and the suggestion went with the position it was about")
    }

    /// Where the board is and how big it is, read as two opposite corners of it:
    /// the pair moves if the block moves and changes if the pitch does.
    private func boardCorners(_ app: XCUIApplication) -> [CGRect] {
        [point(app, "a1").frame, point(app, "o15").frame]
    }

    private func assertBoardIsWhereItWas(_ corners: [CGRect], _ was: [CGRect],
                                         _ message: String, line: UInt = #line) {
        XCTAssertEqual(corners.count, was.count, message, line: line)
        for (now, before) in zip(corners, was) {
            XCTAssertEqual(now.minX, before.minX, accuracy: 0.5, message, line: line)
            XCTAssertEqual(now.minY, before.minY, accuracy: 0.5, message, line: line)
            XCTAssertEqual(now.width, before.width, accuracy: 0.5, message, line: line)
            XCTAssertEqual(now.height, before.height, accuracy: 0.5, message, line: line)
        }
    }

    /// Waits for an element's label to say something.
    private func waitForLabel(_ element: XCUIElement, containing wanted: String,
                              timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, text(of: element).contains(wanted) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
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
