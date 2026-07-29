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

import AppKit
import XCTest

@MainActor
final class PlayScreenUITests: XCTestCase {

    /// The shortest checkmate from the start position. Red's cannon reaches the
    /// general's file, screened by Black's own soldier.
    private static let mateLine = "b1b3,b7b6,b3d3"

    /// The start position a third time, which is what makes the draw claimable.
    private static let shuffleLine = "b1b2,b7b6,b2b1,b6b7,b1b2,b7b6,b2b1,b6b7"

    /// A language to run the interface in, and the strings docs/copy.md
    /// accepts for it.
    ///
    /// The words are written out here rather than read from the application's
    /// own catalog. A test that reads the file the application reads asserts
    /// only that the file is itself; what needs proving is that the accepted
    /// words reach the screen, so the accepted words are what stands in the
    /// test. A copy change is a change to docs/copy.md, to the catalog, and to
    /// the line below that quotes it — which is the point.
    private struct Language {
        /// What `-AppleLanguages` is given, and what a frame is named after.
        let code: String
        let short: String

        let undo, claimDraw, flipBoard, newGame: String
        let redToMove, drawAvailableAndReason, redWinsLine, checkmate: String
        let redWinsNotice: String
        let claimTitle, claimMessage, keepPlaying, endAsDraw: String

        /// A whole point description, which is where the two languages part
        /// company most sharply: Chinese names a piece by the character on its
        /// disc, English by the piece's name.
        let cannonSelectedOnB1: String

        let coreDidNotStart, gameDidNotStart: String

        static let chinese = Language(
            code: "zh-Hans", short: "zh",
            undo: "悔棋", claimDraw: "判和", flipBoard: "翻转棋盘", newGame: "开始新对局",
            redToMove: "轮到红方", drawAvailableAndReason: "可判和 · 三次重复",
            redWinsLine: "红方胜", checkmate: "将死", redWinsNotice: "红方获胜",
            claimTitle: "局面已三次重复", claimMessage: "可以和棋结束。",
            keepPlaying: "继续对局", endAsDraw: "以和棋结束",
            cannonSelectedOnB1: "b1 红 炮 已选择",
            coreDidNotStart: "核心未能启动", gameDidNotStart: "对局未能开始")

        static let english = Language(
            code: "en", short: "en",
            undo: "Undo", claimDraw: "Claim Draw", flipBoard: "Flip Board", newGame: "New Game",
            redToMove: "Red to Move", drawAvailableAndReason: "Draw Available · Threefold Repetition",
            redWinsLine: "Red Wins", checkmate: "Checkmate", redWinsNotice: "Red Wins",
            claimTitle: "This position has occurred three times.",
            claimMessage: "You can end the game as a draw.",
            keepPlaying: "Keep Playing", endAsDraw: "End as a Draw",
            cannonSelectedOnB1: "b1 Red Cannon Selected",
            coreDidNotStart: "The core did not start", gameDidNotStart: "The game did not start")
    }

    /// A name for a store nobody keeps. Every launch passes one: the app
    /// persists the active game now, so a launch that inherited the player's
    /// own store would resume a game no test asked for — and could file one.
    ///
    /// A name and not a path, because the runner and the app are different
    /// sandbox containers: a path minted here is unwritable over there. The
    /// app resolves the name inside its own temporary directory, so a
    /// relaunch given the same name is the same store — the resume tests'
    /// whole subject — and the leftovers are the system's to reclaim, since
    /// this process cannot reach into that container to tidy them.
    private func scratchStoreName() -> String {
        "mxq-uitest-store-" + UUID().uuidString
    }

    private func launch(replaying line: String? = nil,
                        in language: Language = .chinese,
                        store: String? = nil,
                        refusingSaves: Bool = false,
                        darkAppearance: Bool = false,
                        window: String? = nil,
                        hidingNumerals: Bool = false,
                        liftingWindowMinimum: Bool = false,
                        ignoringSavedState: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // The interface language, named rather than inherited. What these
        // tests assert is copy, and the language the machine running them
        // happens to be set to is not evidence about either of the two the
        // application speaks. The normative one is the default.
        app.launchArguments += ["-AppleLanguages", "(\(language.code))"]
        app.launchArguments += ["-mxq-store-name", store ?? scratchStoreName()]
        if refusingSaves { app.launchArguments.append("-mxq-refuse-saves") }
        if let line { app.launchArguments += ["-mxq-replay", line] }
        if darkAppearance { app.launchArguments += ["-mxq-appearance", "dark"] }
        if let window { app.launchArguments += ["-mxq-window", window] }
        if hidingNumerals { app.launchArguments.append("-mxq-hide-numerals") }
        if liftingWindowMinimum { app.launchArguments.append("-mxq-no-minimum") }
        // AppKit's own switch, not one of ours: it makes the launch behave as
        // a first launch, with no saved frame to restore, which is the only
        // condition under which the scene's default size is what opens.
        if ignoringSavedState { app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"] }
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts[language.coreDidNotStart].exists)
        // The board appearing is what settles the screen, so it is waited for
        // first: a refused replay line never shows a board, and checking for
        // the failure text before the screen settles would pass against the
        // spinner that precedes both outcomes.
        let boardUp = point(app, "d1").waitForExistence(timeout: 10)
        XCTAssertFalse(app.staticTexts[language.gameDidNotStart].exists,
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
        app.buttons["cluster-flip"].click()
        XCTAssertEqual(redStrip.label, "一 二 三 四 五 六 七",
                       "Red's numerals should follow the board round")
        XCTAssertEqual(blackStrip.label, "7 6 5 4 3 2 1",
                       "Black's numerals should follow the board round")
        attach(app, named: "6-board-turned-round")

        // Board input is discarded while the board turns, because for those
        // 350 ms the points are not under the discs they name, and it is
        // handed back at the arrival. That hand-back is a wire the running app
        // has to fire for itself — a gate left holding would leave the board
        // deaf for the rest of the game, and no unit test can see the live
        // wiring. The screenshot above has already waited out the flip, so a
        // click that selects is the evidence that the gate reopened.
        point(app, "b4").click()
        XCTAssertEqual(point(app, "b4").label, "b4 红 炮 已选择",
                       "the board should accept input again once the flip lands")
        point(app, "b4").click()
        XCTAssertEqual(point(app, "b4").label, "b4 红 炮",
                       "and the same click again puts the piece down")

        // One Undo removes one ply, so Black's reply leaves the list and the
        // turn goes back to Black.
        app.buttons["cluster-undo"].click()
        XCTAssertTrue(app.staticTexts["轮到黑方"].waitForExistence(timeout: 5),
                      "the turn should have gone back to Black")
        XCTAssertFalse(app.staticTexts["卒1进1"].exists,
                       "the undone move should have left the move list")
        XCTAssertTrue(app.staticTexts["炮六进三"].exists,
                      "Undo removes one ply, not the game")
        attach(app, named: "7-after-taking-a-move-back")
    }

    // MARK: - The game that survives quitting

    /// The stage's own test: quit the app mid-game, open it again. Two moves
    /// are made the way a person makes them, the process is terminated with
    /// no farewell, and the relaunch must show the identical position, the
    /// identical notation, and the turn where it stood. Orientation is the
    /// one thing deliberately not carried: the flip is session-scoped by the
    /// accepted design, a relaunch is a new sitting, and the board it opens
    /// is the default one — which the flipped board before quitting is here
    /// to prove.
    func testTheActiveGameSurvivesQuitting() {
        let store = scratchStoreName()
        let app = launch(store: store)

        point(app, "b1").click()
        point(app, "b4").click()
        XCTAssertTrue(app.staticTexts["炮六进三"].waitForExistence(timeout: 5))
        point(app, "a6").click()
        point(app, "a5").click()
        XCTAssertTrue(app.staticTexts["卒1进1"].waitForExistence(timeout: 5))

        // Turn the board round before quitting, so the relaunch can show
        // orientation resetting rather than merely staying.
        app.buttons["cluster-flip"].click()
        let strips = app.windows.firstMatch.descendants(matching: .any)
        XCTAssertEqual(strips["file-numerals-red"].label, "一 二 三 四 五 六 七")

        app.terminate()

        let again = launch(store: store)
        XCTAssertEqual(point(again, "b4").label, "b4 红 炮",
                       "the cannon stands where the quit left it")
        XCTAssertEqual(point(again, "a5").label, "a5 黑 卒")
        XCTAssertEqual(point(again, "b1").label, "b1 空")
        XCTAssertEqual(point(again, "a6").label, "a6 空")
        XCTAssertTrue(again.staticTexts["炮六进三"].exists,
                      "the move list reads exactly as it did")
        XCTAssertTrue(again.staticTexts["卒1进1"].exists)
        XCTAssertTrue(again.staticTexts["轮到红方"].exists,
                      "and it is still Red to move")
        let stripsAgain = again.windows.firstMatch.descendants(matching: .any)
        XCTAssertEqual(stripsAgain["file-numerals-red"].label, "七 六 五 四 三 二 一",
                       "a new sitting opens the default way round")
        attach(again, named: "21-the-resumed-game-after-relaunch")

        // The resumed game is the same game to play on: an Undo takes back
        // the ply the previous sitting made.
        again.buttons["cluster-undo"].click()
        XCTAssertTrue(again.staticTexts["轮到黑方"].waitForExistence(timeout: 5))
        XCTAssertFalse(again.staticTexts["卒1进1"].exists)
    }

    /// An unconfirmed natural result is the game's state, so quitting on the
    /// mate and relaunching presents the finished board and its notice again;
    /// Undo still resumes it, because nothing was confirmed; and 开始新对局
    /// files it, after which a further relaunch has nothing to resume.
    func testAnUnconfirmedResultSurvivesQuittingAndFilesOnNewGame() {
        let store = scratchStoreName()
        var app = launch(replaying: Self.mateLine, store: store)
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10))
        app.terminate()

        app = launch(store: store)
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10),
                      "the unconfirmed result presents its notice again")
        XCTAssertEqual(reading(app, "result-title"), "红方获胜")
        XCTAssertEqual(reading(app, "result-reason"), "将死")
        XCTAssertEqual(point(app, "d3").label, "d3 红 炮",
                       "over the mated position it announced the first time")
        attach(app, named: "22-the-notice-presented-again-after-relaunch")

        // Unconfirmed is unconfirmed across a relaunch: the mating move can
        // still be taken back, and the game runs on.
        app.buttons["result-undo"].click()
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["result-title"].exists)
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"),
                               evaluatedWith: app.buttons["cluster-undo"])],
             timeout: 5)

        // Mate again, and this time file it: the concluding action commits
        // the result to History before the board resets.
        point(app, "b3").click()
        point(app, "d3").click()
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 5))
        app.buttons["result-new-game"].click()
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 5))
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮",
                       "the starting position is back")
        app.terminate()

        // The filed game stays filed: this launch resumes nothing.
        app = launch(store: store)
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮")
        XCTAssertFalse(app.staticTexts["result-title"].exists,
                       "a filed result does not come back")
        XCTAssertFalse(app.staticTexts["1."].exists, "the move list is empty")
    }

    /// The save-failure capsule, produced on the real screen: with the debug
    /// stand-in refusing every commit, a legal move is played and does not
    /// happen — the position unchanged, the move list empty, and the accepted
    /// sentence standing at the turn status until it withdraws by itself.
    func testARefusedSaveAnswersWithTheCapsule() {
        let app = launch(refusingSaves: true)

        point(app, "b1").click()
        point(app, "b4").click()

        let capsule = app.windows.firstMatch.descendants(matching: .any)["save-failure"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 5),
                      "the refused save answers at the turn status")
        XCTAssertTrue(app.staticTexts["无法保存这一步，请重试。"].exists,
                      "with the register's words")
        attach(app, named: "23-the-save-failure-capsule")

        XCTAssertEqual(point(app, "b1").label, "b1 红 炮 已选择",
                       "the position did not change, and the piece is still held")
        XCTAssertEqual(point(app, "b4").label, "b4 空 可走",
                       "the destination is still empty, still on offer — the correction is one tap away")
        XCTAssertFalse(app.staticTexts["1."].exists,
                       "a move that did not happen enters no list")
        XCTAssertTrue(app.staticTexts["轮到红方"].exists)

        // Transient: it withdraws by its own clock, no dismissal asked.
        wait(for: [expectation(for: NSPredicate(format: "exists == false"),
                               evaluatedWith: capsule)],
             timeout: 10)
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
        XCTAssertTrue(app.buttons["cluster-undo"].isEnabled,
                      "a natural result stays undoable")
        XCTAssertTrue(app.buttons["cluster-new-game"].exists,
                      "the concluding action takes the draw claim's slot")
        XCTAssertFalse(app.buttons["cluster-claim"].exists,
                       "a finished game has no draw to judge")
        attach(app, named: "11-the-finished-board-with-the-notice-closed")

        // Closing is final for this result: nothing the player does to the
        // board brings the notice back.
        app.buttons["cluster-flip"].click()
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
        // result after it: reaching the mate again announces it again. Input
        // during the Undo's reversal is discarded, so the clicks wait the
        // transition out rather than race it — and what says it is over is the
        // control the gate itself disables: 悔棋 is unavailable until the
        // reversal lands.
        app.buttons["cluster-undo"].click()
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"),
                               evaluatedWith: app.buttons["cluster-undo"])],
             timeout: 5)
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
        // A wall clock on purpose. The beat is a background opacity rising and
        // falling, and an opacity is nothing XCUI can wait on: no attribute
        // carries it, no element appears while it runs, and the assertions
        // below — which are about the board — are true before and after it.
        // The screenshot is the only thing that needs to land inside the beat,
        // so this waits into it rather than for it.
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

        XCTAssertTrue(app.buttons["cluster-claim"].waitForExistence(timeout: 10))
        XCTAssertTrue(reading(app, "turn-status").contains("可判和 · 三次重复"),
                      "the status line carries the standing offer")
        let claim = app.buttons["cluster-claim"]
        XCTAssertTrue(claim.isEnabled, "the claim the core offers is the player's to take")
        attach(app, named: "14-the-repetition-is-claimable")

        // The claim's own notice is a sheet, so its buttons are addressed
        // through it: the window behind carries buttons of the same name.
        claim.click()
        let notice = app.sheets.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        // One accepted sentence, said in the two roles an alert has: what has
        // happened is the title, what can be done about it is the message.
        let lines = notice.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(lines, ["局面已三次重复", "可以和棋结束。"],
                       "the notice says what the claim is")
        attach(app, named: "15-the-draw-claim-notice")

        // Cancelling leaves the game exactly as it was, with the same claim
        // still standing.
        notice.buttons["继续对局"].click()
        XCTAssertFalse(app.staticTexts["result-title"].exists, "the game continues")
        XCTAssertTrue(app.buttons["cluster-claim"].isEnabled, "the claim is still there to take")

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
        XCTAssertFalse(app.buttons["cluster-undo"].isEnabled,
                       "a claimed draw cannot be taken back")
        attach(app, named: "17-a-claimed-draw-with-the-notice-closed")
    }

    // MARK: - The two languages

    // docs/copy.md is the register: normative Simplified Chinese with an
    // approved English beside it, the pair stored under one symbolic key. The
    // String Catalog is what puts them on screen, and the only thing that can
    // say the catalog is live is the running screen in each language. So the
    // two tests below walk one language each over the surfaces the copy lives
    // on — ordinary play, the result notice, the claim's alert, and the
    // cluster at the smallest window the product allows — and photograph them.
    //
    // They also assert what does *not* change with the language. Traditional
    // notation, the piece characters, and the numeral strips are game
    // presentation rather than interface copy: the same characters in every
    // language, and asserted here so that a future translation cannot quietly
    // take them.

    func testTheInterfaceInChinese() {
        photographTheInterface(in: .chinese)
    }

    func testTheInterfaceInEnglish() {
        photographTheInterface(in: .english)
    }

    private func photographTheInterface(in language: Language) {
        // Ordinary play, mid-game: the turn status, a filled move list, and
        // the control cluster, all carrying words at once.
        let play = launch(replaying: Self.evidenceLine, in: language)
        XCTAssertEqual(play.buttons["cluster-undo"].label, language.undo,
                       "the control's label is the register's, in this language")
        XCTAssertEqual(play.buttons["cluster-claim"].label, language.claimDraw)
        XCTAssertEqual(play.buttons["cluster-flip"].label, language.flipBoard)
        XCTAssertTrue(reading(play, "turn-status").contains(language.redToMove),
                      "the turn status names the side to move")

        // The move list is not copy. It reads the same either way.
        XCTAssertTrue(play.staticTexts["卒4进1"].exists,
                      "traditional notation is game presentation, not interface copy")
        XCTAssertTrue(play.staticTexts["5."].exists, "and so is a row number")
        let strips = play.windows.firstMatch.descendants(matching: .any)
        XCTAssertEqual(strips["file-numerals-red"].label, "七 六 五 四 三 二 一",
                       "each player's own numerals, in either language")
        XCTAssertEqual(strips["file-numerals-black"].label, "1 2 3 4 5 6 7")
        attach(play, named: "\(language.short)-play")

        // Where the two languages part company most sharply. A screen reader
        // hears the character in Chinese, because that is what the disc shows
        // and what the reader is learning, and the piece's name in English.
        point(play, "b1").click()
        XCTAssertEqual(point(play, "b1").label, language.cannonSelectedOnB1,
                       "the point description switches with the language")
        attach(play, named: "\(language.short)-piece-selected")

        // The result notice, and the status line that keeps saying it.
        let finished = launch(replaying: Self.mateLine, in: language)
        XCTAssertTrue(finished.staticTexts["result-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(reading(finished, "result-title"), language.redWinsNotice)
        XCTAssertEqual(reading(finished, "result-reason"), language.checkmate)
        XCTAssertEqual(finished.buttons["result-undo"].label, language.undo)
        XCTAssertEqual(finished.buttons["result-new-game"].label, language.newGame)
        XCTAssertTrue(reading(finished, "turn-status").contains(language.redWinsLine),
                      "the shorter status-line form of the same result")
        attach(finished, named: "\(language.short)-result-notice")

        // The claim's alert, which is one accepted sentence said in the two
        // roles an alert has.
        let claimable = launch(replaying: Self.shuffleLine, in: language)
        XCTAssertTrue(claimable.buttons["cluster-claim"].waitForExistence(timeout: 10))
        XCTAssertTrue(reading(claimable, "turn-status").contains(language.drawAvailableAndReason),
                      "the standing offer and its reason, joined by the metadata middot")
        claimable.buttons["cluster-claim"].click()
        let notice = claimable.sheets.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        attach(claimable, named: "\(language.short)-claim-alert")

        let lines = notice.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(lines.count, 2, "a title and a message, never one recombined title")
        XCTAssertEqual(lines.first, language.claimTitle)
        XCTAssertEqual(lines.last, language.claimMessage)
        XCTAssertTrue(notice.buttons[language.keepPlaying].exists)
        XCTAssertTrue(notice.buttons[language.endAsDraw].exists)
        notice.buttons[language.keepPlaying].click()

        // The smallest window the product allows, where the English labels are
        // materially wider than the Chinese they translate. Both states of the
        // cluster are photographed, because the finished game's concluding
        // action is the longest of the three and is what the flip control's
        // fallback to its symbol exists for. Nothing here says what the
        // cluster should look like; it says that all of it is still on screen,
        // and the frames are what the words are read off.
        for (line, name) in [(Self.evidenceLine, "play"), (Self.mateLine, "result")] {
            let smallest = launch(replaying: line, in: language, window: "320x240")
            let window = smallest.windows.firstMatch.frame
            let cluster = ["cluster-undo",
                           line == Self.mateLine ? "cluster-new-game" : "cluster-claim",
                           "cluster-flip"]
            for identifier in cluster {
                let button = smallest.buttons[identifier]
                XCTAssertTrue(button.exists, "\(identifier) should still be there at the minimum")
                XCTAssertTrue(window.contains(button.frame),
                              "\(identifier) should sit inside the minimum window, not past it")
                print("CLUSTER-EVIDENCE \(language.short)-\(name) \(identifier) "
                      + "label=\(button.label) width=\(button.frame.width)")
            }
            attach(smallest, named: "\(language.short)-\(name)-minimum-window")
        }
    }

    /// The failure screen the play screen shows when a game will not start.
    /// It is the one surface whose Chinese the register had to supply — the
    /// application shipped an English literal with nothing behind it — so it
    /// is worth seeing rather than assuming. A replay line the core refuses is
    /// what puts it on screen.
    func testTheGameThatDidNotStartSaysSoInBothLanguages() {
        for language in [Language.chinese, .english] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(\(language.code))",
                                   "-mxq-store-name", scratchStoreName(),
                                   "-mxq-replay", "d1d7"]
            app.launch()
            XCTAssertTrue(app.staticTexts[language.gameDidNotStart].waitForExistence(timeout: 20),
                          "a refused replay line should say so in \(language.code)")
            attach(app, named: "\(language.short)-game-did-not-start")
            app.terminate()
        }
    }

    // MARK: - The layout at the sizes the window can be

    // Evidence, not a verdict. Nothing here says what the layout should do at
    // any size; it photographs what it does do at the sizes that bound it — the
    // size a first launch opens at, the window's own minimum, sizes below it,
    // an ordinary one, and the largest the display can show whole — with the
    // strips on and off, so the decisions can be taken against frames rather
    // than against arithmetic, and stay taken afterwards. Every frame
    // is named with the window size it was taken at, and logged beside the
    // layout area and the cell pitch measured off the running app, because a
    // screenshot that does not say what size it was taken at is not evidence
    // about a layout.
    //
    // A window taller than the screen is cropped by the screen when it is
    // photographed, and a cropped frame is evidence about the display rather
    // than about the layout, so the series stops at what fits. Where the
    // display is large enough for the board to reach its ceiling, the ceiling
    // is asserted; where it is not, that is recorded rather than asserted, and
    // the frames stop short of it.

    /// A capture and a quiet shuffle: five numbered rows in the move list, a
    /// point that changed hands, and a game still running. It opens with the
    /// unit suite's pinned capture line; the rest takes the two cannons out
    /// along the empty b-file and back, then pushes the two edge soldiers, so
    /// the position moves on rather than standing a third time and turning the
    /// screen into a claimable draw. Every move of it goes through the core, so
    /// a move that stopped being legal fails this test where it launches.
    private static let evidenceLine =
        "d2d3,d6d5,d3d4,d5d4,b1b2,b7b6,b2b1,b6b7,a2a3,a6a5"

    /// The cell pitch the running app settled on. Each tap target is one cell,
    /// placed from the same geometry that draws the board, so the board's size
    /// is measured off the screen here rather than recomputed.
    private func pitch(_ app: XCUIApplication) -> CGFloat {
        point(app, "d4").frame.width
    }

    func testTheLayoutAcrossTheWindowSizes() {
        // Sizes here are window sizes: what `-mxq-window` sets, what the window
        // occupies on screen, and what the screenshot comes out at, all one
        // number. The layout itself gets that height less the title bar, and
        // the title bar is measured rather than assumed. The board fills the
        // layout's full height and the board block is centred in it, so the
        // board's own centre would sit on the window's centre if there were no
        // chrome; how far below it sits is half the chrome.
        let reference = launch(replaying: Self.evidenceLine, window: "800x480")
        let referenceFrame = reference.windows.firstMatch.frame
        XCTAssertEqual(referenceFrame.size, CGSize(width: 800, height: 480),
                       "-mxq-window should set the window size it names")
        let boardCentre = (point(reference, "d7").frame.midY
                           + point(reference, "d1").frame.midY) / 2
        let titleBar = 2 * (boardCentre - referenceFrame.midY)
        XCTAssertTrue((16...64).contains(titleBar),
                      "a measured title bar outside this range means the board moved, not the chrome")
        XCTAssertTrue(reference.staticTexts["5."].exists,
                      "the evidence line should fill five numbered rows")

        // The largest window this display can show whole. Read off the screen
        // rather than assumed, so the series runs as large as wherever it runs
        // allows: a window taller than the screen is cropped when photographed.
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1024, height: 583)
        let largest = CGSize(width: visible.width.rounded(.down),
                             height: visible.height.rounded(.down))

        var log = ["title-bar=\(titleBar) largest-window-on-this-display=\(largest)"]

        @discardableResult
        func record(_ label: String,
                    window: CGSize?,
                    replaying line: String = Self.evidenceLine,
                    hidingNumerals: Bool = false,
                    liftingWindowMinimum: Bool = false) -> (window: CGSize, pitch: CGFloat) {
            let requested = window.map { "\(Int($0.width))x\(Int($0.height))" }
            let app = launch(replaying: line,
                             window: requested,
                             hidingNumerals: hidingNumerals,
                             liftingWindowMinimum: liftingWindowMinimum,
                             ignoringSavedState: requested == nil)
            let arrived = app.windows.firstMatch.frame.size
            let cell = pitch(app)
            let name = "\(label)-\(Int(arrived.width))x\(Int(arrived.height))"
            attach(app, named: name)
            log.append("""
                \(name) requested=\(requested ?? "the scene's default") \
                layout=\(Int(arrived.width))x\(Int(arrived.height - titleBar)) \
                pitch=\(cell) board-core=\(cell * 7)
                """)
            print("LAYOUT-EVIDENCE \(log.last!)")
            return (arrived, cell)
        }

        // What a first launch opens at: no `-mxq-window`, and no saved frame to
        // restore. Today that is the display's whole visible area, on this
        // display and on every one measured so far — the content is flexible in
        // both directions and nothing tells the window otherwise. It is
        // photographed like the rest because a size nobody has looked at is not
        // a decided size, and this one has not been decided yet.
        let first = record("firstlaunch", window: nil)
        XCTAssertGreaterThanOrEqual(first.window.width, 616,
                                    "a first launch cannot open below the minimum")
        XCTAssertGreaterThanOrEqual(first.window.height, 420)

        // The smallest window the product allows. The size asked for is far
        // below it on both axes, so what comes back is the minimum itself.
        let floor = record("min-strips", window: CGSize(width: 320, height: 240))
        XCTAssertEqual(floor.pitch, 44, accuracy: 0.5,
                       "the board should sit exactly on its floor at the smallest window")
        // Pitch 44 alone cannot catch a minimum that shrank: below the floor
        // the fallback pins 44 too. The accepted number itself is the pin.
        XCTAssertEqual(floor.window.width, 616,
                       "the minimum window is the decided 616 points wide")
        XCTAssertEqual(floor.window.height - titleBar, 388, accuracy: 0.5,
                       "the minimum layout is the decided 388 points under the measured title bar")
        record("min-nostrips", window: CGSize(width: 320, height: 240), hidingNumerals: true)
        record("min-result", window: CGSize(width: 320, height: 240), replaying: Self.mateLine)

        // An ordinary window, and as close to 900 by 700 as the display allows.
        let mid = CGSize(width: min(900, largest.width), height: min(700, largest.height))
        record("mid-strips", window: mid)
        record("mid-nostrips", window: mid, hidingNumerals: true)

        // As large as the display can show whole.
        let large = record("large-strips", window: largest)
        XCTAssertLessThanOrEqual(large.pitch * 7, 720,
                                 "the board core must never pass its ceiling")
        // Reaching the ceiling is a claim about a display with the room for it.
        // On a smaller one the largest frame is what it is, and saying so
        // belongs in the log rather than in a failure.
        if largest.width >= 1030 && largest.height - titleBar >= 820 {
            XCTAssertGreaterThan(large.pitch * 7, 700,
                                 "a display with the room should reach the ceiling")
        } else {
            log.append("ceiling-not-reachable-on-this-display board-core=\(large.pitch * 7)")
        }

        // Below the floor, one axis at a time, with the floor lifted. The
        // product cannot be driven here; the frames are what the floor is being
        // judged against.
        record("belowmin-narrow",
               window: CGSize(width: floor.window.width - 56, height: floor.window.height),
               liftingWindowMinimum: true)
        record("belowmin-short",
               window: CGSize(width: floor.window.width, height: floor.window.height - 48),
               liftingWindowMinimum: true)

        let measurements = XCTAttachment(string: log.joined(separator: "\n"))
        measurements.name = "layout-measurements"
        measurements.lifetime = .keepAlways
        add(measurements)
    }
}
