// Launches the app and plays on it.
//
// This is the only check that exercises the whole path at once: the core
// initialises from the bundled variant configuration, the position comes back
// from it, the board renders, and a move a person makes is accepted or refused
// by the core rather than by anything in Swift. The screenshots are attached to
// the test results so the screen can be looked at rather than reasoned about.
//
// The two replayed lines are the core's own answers, pinned by the unit suite:
// a change that stops them being a checkmate or a repetition fails there first,
// with a better message than a click that cannot find a button.

import XCTest

@MainActor
final class PlayScreenUITests: XCTestCase {

    /// The shortest checkmate from the start position. Red's cannon reaches the
    /// general's file, screened by Black's own soldier.
    private static let mateLine = "b1b3,b7b6,b3d3"

    /// The start position a third time, which is what makes the draw claimable.
    private static let shuffleLine = "b1b2,b7b6,b2b1,b6b7,b1b2,b7b6,b2b1,b6b7"

    private func launch(replaying line: String? = nil,
                        darkAppearance: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if let line { app.launchArguments += ["-mxq-replay", line] }
        if darkAppearance { app.launchArguments += ["-mxq-appearance", "dark"] }
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["The core did not start"].exists)
        // The board appearing is what settles the screen, so it is waited for
        // first: a refused replay line never shows a board, and checking for
        // the failure text before the screen settles would pass against the
        // spinner that precedes both outcomes.
        let boardUp = point(app, "d1").waitForExistence(timeout: 10)
        XCTAssertFalse(app.staticTexts["The game did not start"].exists,
                       "a replay line the core refuses arrives here")
        XCTAssertTrue(boardUp, "the board's points should be addressable")
        return app
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        // A beat for whatever is animating to finish. An assertion is satisfied
        // by the first frame that carries the state, and a screenshot of a
        // half-crossfaded control is a screenshot that lies about the design.
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["point-\(name)"]
    }

    /// What a text element says. A SwiftUI `Text` carries its string as the
    /// accessibility value, and an element combined from several of them — the
    /// turn status is one — arrives as one joined string.
    private func reading(_ app: XCUIApplication, _ identifier: String) -> String {
        app.staticTexts[identifier].value as? String ?? ""
    }

    // MARK: - Playing

    func testAGameCanBePlayedOnTheBoard() {
        let app = launch()
        attach(app, named: "1-starting-position")

        // The elements must sit over the points they name, which the labels
        // are what can say: b1 carries Red's cannon at the start position.
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮")
        XCTAssertEqual(point(app, "d7").label, "d7 黑 将")
        XCTAssertEqual(point(app, "d4").label, "d4 空")

        // Select the cannon on b1 and show its legal destinations.
        point(app, "b1").click()
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮 已选择",
                       "the click must address the square it named")
        attach(app, named: "2-a-piece-selected")

        // c3 is empty and no cannon move reaches it. The core refuses it, so
        // nothing moves and the selection survives — the correction is one
        // click away.
        point(app, "c3").click()
        XCTAssertTrue(app.staticTexts["轮到红方"].exists,
                      "an illegal tap must not consume the turn")
        XCTAssertFalse(app.staticTexts["1."].exists,
                       "an illegal tap must not enter the move list")
        attach(app, named: "3-after-an-illegal-tap")

        // A legal one: the cannon runs up its own empty file. The move list is
        // what proves it happened — a turn that reads "轮到红方" reads the same
        // whether two moves were played or none, which is how an earlier
        // version of this test passed against a play() that did nothing.
        point(app, "b4").click()
        XCTAssertTrue(app.staticTexts["炮六进三"].waitForExistence(timeout: 5),
                      "the move should appear in the move list, in traditional notation")
        XCTAssertTrue(app.staticTexts["轮到黑方"].exists, "the turn should have passed to Black")
        attach(app, named: "4-after-a-move")

        // Black replies with a soldier, so the move list shows a numbered pair.
        point(app, "a6").click()
        point(app, "a5").click()
        XCTAssertTrue(app.staticTexts["卒1进1"].waitForExistence(timeout: 5),
                      "Black's reply should read in Arabic numerals")
        XCTAssertTrue(app.staticTexts["轮到红方"].exists,
                      "the turn should have come back to Red")
        attach(app, named: "5-after-black-replies")

        // Each numeral strip shows the numerals of the player it faces, so
        // both must follow the board round.
        let redStrip = app.windows.firstMatch.descendants(matching: .any)["file-numerals-red"]
        let blackStrip = app.windows.firstMatch.descendants(matching: .any)["file-numerals-black"]
        XCTAssertEqual(redStrip.label, "七 六 五 四 三 二 一")
        XCTAssertEqual(blackStrip.label, "1 2 3 4 5 6 7")

        // Turning the board round changes presentation only.
        app.buttons["翻转棋盘"].click()
        XCTAssertEqual(redStrip.label, "一 二 三 四 五 六 七",
                       "Red's numerals should follow the board round")
        XCTAssertEqual(blackStrip.label, "7 6 5 4 3 2 1",
                       "Black's numerals should follow the board round")
        attach(app, named: "6-board-turned-round")

        // One Undo removes one ply, so Black's reply leaves the list and the
        // turn goes back to Black.
        app.buttons["悔棋"].click()
        XCTAssertTrue(app.staticTexts["轮到黑方"].waitForExistence(timeout: 5),
                      "the turn should have gone back to Black")
        XCTAssertFalse(app.staticTexts["卒1进1"].exists,
                       "the undone move should have left the move list")
        XCTAssertTrue(app.staticTexts["炮六进三"].exists,
                      "Undo removes one ply, not the game")
        attach(app, named: "7-after-taking-a-move-back")
    }

    // MARK: - The result notice

    func testTheResultNoticeCarriesTheCheckmate() {
        let app = launch(replaying: Self.mateLine)

        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(reading(app, "result-title"), "红方获胜")
        XCTAssertEqual(reading(app, "result-reason"), "将死")
        XCTAssertEqual(app.buttons["result-undo"].label, "悔棋")
        XCTAssertEqual(app.buttons["result-new-game"].label, "开始新对局")
        XCTAssertTrue(reading(app, "turn-status").contains("红方胜"),
                      "the status line carries the result too")
        attach(app, named: "8-the-result-notice-over-the-mated-board")

        // Undo takes the mating move back, which resumes the game and takes the
        // notice with it.
        app.buttons["result-undo"].click()
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["result-title"].exists,
                       "a resumed game has no result to show")
        XCTAssertFalse(app.staticTexts["炮六平四"].exists,
                       "the mating move should have left the move list")
        XCTAssertTrue(app.staticTexts["炮六进二"].exists,
                      "Undo removes one ply, not the game")
        attach(app, named: "9-after-taking-the-mate-back")
    }

    func testTheResultNoticeStartsANewGame() {
        let app = launch(replaying: Self.mateLine)
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10))

        app.buttons["result-new-game"].click()

        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 5))
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮",
                       "the starting position should be back")
        XCTAssertFalse(app.staticTexts["1."].exists, "the move list should be empty")
        XCTAssertFalse(app.staticTexts["result-title"].exists)
        attach(app, named: "10-a-new-game-from-the-notice")
    }

    func testClosingTheResultNoticeLeavesTheFinishedBoard() {
        let app = launch(replaying: Self.mateLine)
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10))

        app.buttons["result-close"].click()

        XCTAssertFalse(app.staticTexts["result-title"].exists, "the notice should have closed")
        XCTAssertEqual(point(app, "d3").label, "d3 红 炮",
                       "the final position should still be on the board")
        XCTAssertTrue(reading(app, "turn-status").contains("红方胜"),
                      "the status line still carries the result")
        XCTAssertTrue(reading(app, "turn-status").contains("将死"))
        XCTAssertTrue(app.buttons["悔棋"].isEnabled,
                      "a natural result stays undoable")
        XCTAssertTrue(app.buttons["cluster-new-game"].exists,
                      "the concluding action takes the draw claim's slot")
        XCTAssertFalse(app.buttons["判和"].exists,
                       "a finished game has no draw to judge")
        attach(app, named: "11-the-finished-board-with-the-notice-closed")

        // Closing is final for this result: nothing the player does to the
        // board brings the notice back.
        app.buttons["翻转棋盘"].click()
        XCTAssertFalse(app.staticTexts["result-title"].exists,
                       "the notice should not return for a result already seen")

        app.buttons["cluster-new-game"].click()
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 5))
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮",
                       "the starting position should be back")
        XCTAssertFalse(app.staticTexts["1."].exists, "the move list should be empty")
        attach(app, named: "12-a-new-game-from-the-cluster")
    }

    func testAClickOnTheBoardClosesTheResultNotice() {
        let app = launch(replaying: Self.mateLine)
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10))

        // A corner point, well clear of the notice standing over the middle.
        point(app, "a1").click()

        XCTAssertFalse(app.staticTexts["result-title"].exists,
                       "a click on the finished board should close the notice")
        XCTAssertTrue(reading(app, "turn-status").contains("红方胜"),
                      "the game is still over")

        // Closed is closed: another click on the finished board moves nothing
        // and brings nothing back.
        point(app, "g1").click()
        XCTAssertFalse(app.staticTexts["result-title"].exists,
                       "the notice should not return for a result already seen")
        XCTAssertEqual(point(app, "d3").label, "d3 红 炮",
                       "a click on a finished board moves nothing")

        // The dismissal belonged to the finished game it closed, not to every
        // result after it: reaching the mate again announces it again. The
        // beat: input during the Undo's reversal is discarded, so the clicks
        // wait out the transition rather than race it.
        app.buttons["悔棋"].click()
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.4)
        point(app, "b3").click()
        point(app, "d3").click()
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 5),
                      "a fresh result presents a fresh notice")
    }

    func testTheCancelKeyClosesTheResultNotice() {
        let app = launch(replaying: Self.mateLine)
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10))

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        XCTAssertFalse(app.staticTexts["result-title"].exists,
                       "the cancel key should close the notice")
        XCTAssertTrue(reading(app, "turn-status").contains("红方胜"),
                      "the game is still over")
    }

    func testTheResultNoticeInDarkAppearance() {
        let app = launch(replaying: Self.mateLine, darkAppearance: true)
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(reading(app, "result-title"), "红方获胜")
        attach(app, named: "13-the-result-notice-in-dark-appearance")
    }

    // MARK: - The motion states a still frame can carry

    /// The check line is pinned by the unit suite: a check that is only a
    /// check. What a screenshot can show is the persistent state — the double
    /// ring around the general after its one-time pulse has settled; the
    /// pulse itself, and every travel, is judged by running the app.
    func testTheCheckStateRingsTheGeneral() {
        let app = launch(replaying: "b1b3,d6d5,b3d3")

        XCTAssertEqual(point(app, "d7").label, "d7 黑 将 被将军",
                       "the checked general carries the state")
        XCTAssertTrue(reading(app, "turn-status").contains("轮到黑方"),
                      "whose turn it is remains true while they are in check")
        XCTAssertTrue(reading(app, "turn-status").contains("将军"),
                      "the token accompanies the side-to-move line")
        attach(app, named: "18-the-check-rings")
    }

    /// The capture line is pinned by the unit suite. The screenshot is the
    /// post-state: the taken soldier gone, the taker on its point, the
    /// brackets on the move that did it.
    func testTheBoardAfterACapture() {
        let app = launch(replaying: "d2d3,d6d5,d3d4,d5d4")

        XCTAssertEqual(point(app, "d4").label, "d4 黑 卒",
                       "the taker stands where the taken stood")
        XCTAssertEqual(point(app, "d5").label, "d5 空")
        XCTAssertTrue(app.staticTexts["卒4进1"].exists,
                      "the capture reads in the move list")
        attach(app, named: "19-after-a-capture")
    }

    /// A tap the game cannot accept is answered on the turn status — the
    /// acknowledgment beat. The beat is opacity rising and falling over
    /// 400 ms, so the screenshot is taken inside it; the board itself must
    /// show nothing, which the labels prove.
    func testARefusedTapBeatsOnTheTurnStatus() {
        let app = launch(replaying: Self.mateLine)
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10))

        point(app, "a1").click()   // closes the notice: an accepted input
        XCTAssertFalse(app.staticTexts["result-title"].exists)

        point(app, "g1").click()   // nothing left to accept: the beat answers
        Thread.sleep(forTimeInterval: 0.15)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "20-the-beat-answering-a-refused-tap"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertEqual(point(app, "d3").label, "d3 红 炮",
                       "the refused tap moved nothing")
        XCTAssertFalse(app.staticTexts["result-title"].exists,
                       "and brought nothing back")
    }

    // MARK: - The claimable draw

    func testTheDrawCanBeClaimed() {
        let app = launch(replaying: Self.shuffleLine)

        XCTAssertTrue(app.buttons["判和"].waitForExistence(timeout: 10))
        XCTAssertTrue(reading(app, "turn-status").contains("可判和 · 三次重复"),
                      "the status line carries the standing offer")
        let claim = app.buttons["判和"]
        XCTAssertTrue(claim.isEnabled, "the claim the core offers is the player's to take")
        attach(app, named: "14-the-repetition-is-claimable")

        // The claim's own notice is a sheet, so its buttons are addressed
        // through it: the window behind carries buttons of the same name.
        claim.click()
        let notice = app.sheets.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertEqual(notice.staticTexts.firstMatch.value as? String,
                       "局面已三次重复，可以和棋结束。",
                       "the notice says what the claim is")
        attach(app, named: "15-the-draw-claim-notice")

        // Cancelling leaves the game exactly as it was, with the same claim
        // still standing.
        notice.buttons["继续对局"].click()
        XCTAssertFalse(app.staticTexts["result-title"].exists, "the game continues")
        XCTAssertTrue(app.buttons["判和"].isEnabled, "the claim is still there to take")

        claim.click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons["以和棋结束"].click()

        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(reading(app, "result-title"), "和棋")
        XCTAssertEqual(reading(app, "result-reason"), "三次重复")
        XCTAssertFalse(app.buttons["result-undo"].exists,
                       "a claimed draw is the player's own confirmed result")
        XCTAssertTrue(reading(app, "turn-status").contains("和局"),
                      "the status line agrees")
        attach(app, named: "16-a-claimed-draw")

        app.buttons["result-close"].click()
        XCTAssertFalse(app.staticTexts["result-title"].exists)
        XCTAssertTrue(app.buttons["cluster-new-game"].exists)
        XCTAssertFalse(app.buttons["悔棋"].isEnabled,
                       "a claimed draw cannot be taken back")
        attach(app, named: "17-a-claimed-draw-with-the-notice-closed")
    }
}
