// The Play home, on the running screen.
//
// docs/interaction-design.md, "Starting and configuring a game" and "Saving the
// active game before choosing a new mode": the Play destination's root is an
// independent page for choosing what to play, with no board on it; with a game
// active it also carries that game's metadata and a direct Resume; and both mode
// entries stay interactive, presenting the one accepted confirmation whose
// 保存并继续 files the game as it stands before the selected mode's pre-start
// page opens.
//
// The words asserted here are the normative Simplified Chinese of docs/copy.md,
// written out rather than read from the application's own catalog: a test that
// reads the file the application reads asserts only that the file is itself.

// **macOS only.** The bundle this file lives in builds for an iOS Simulator too
// now, and this suite does not go there: it drives a window — naming a size,
// reading the frame back, clicking and right-clicking a pointer, typing keys —
// and a window is what iOS has not got. The phone's own evidence is the
// `Phone…UITests` files beside this one, which are a different suite rather than
// a port of this one.
#if os(macOS)

import XCTest

@MainActor
final class PlayHomeUITests: XCTestCase {

    /// Two plies of an ordinary Free Play game — enough that the metadata has a
    /// count to report and a side to move that is not the opening one.
    private static let openingLine = "b1b3,b7b6"

    /// The shortest checkmate from the start position.
    private static let mateLine = "b1b3,b7b6,b3d3"

    private func scratchStoreName() -> String {
        "mxq-uitest-store-" + UUID().uuidString
    }

    private func launch(replaying line: String? = nil,
                        store: String? = nil,
                        refusingSaves: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)"]
        app.launchArguments += ["-mxq-store-name", store ?? scratchStoreName()]
        // Every preference stated, and a scratch domain to write into. The
        // metadata line and the move list read the notation preference, so a
        // launch that named none would read the machine's.
        app.launchArguments += ["-mxq-defaults-suite", LaunchPreferences.scratchSuite]
        app.launchArguments += LaunchPreferences.arguments()
        // The debug stand-in that refuses every commit, which is the only way
        // to reach the accepted refusal on a real screen: a working store
        // commits. It refuses the archive along with every other mutation, so a
        // launch that asks for it cannot also ask for a replayed line — the
        // game it wants is created on the screen instead, by 开始对局, which
        // the stand-in deliberately lets through.
        if refusingSaves { app.launchArguments.append("-mxq-refuse-saves") }
        if let line { app.launchArguments += ["-mxq-replay", line] }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    /// The back control in the toolbar, which is the whole of how a page over
    /// the home is left.
    private func goBack(_ app: XCUIApplication) {
        let control = app.buttons["play-back"]
        XCTAssertTrue(control.waitForExistence(timeout: 5),
                      "a page over the home carries a way back to it")
        control.click()
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["point-\(name)"]
    }

    /// What a text element says. A SwiftUI `Text` carries its string as the
    /// accessibility value; where a surface hands it over as the label instead,
    /// the label is the same string and is just as good an answer.
    private func reading(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = app.staticTexts[identifier]
        return (element.value as? String) ?? element.label
    }

    private func destination(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.windows.firstMatch.outlines.element(boundBy: 0).cells.element(boundBy: index)
    }

    private func historyRow(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.windows.firstMatch.buttons["history-row-\(index)"]
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The page itself

    /// The home is a page for choosing what to play, and nothing else is on it:
    /// no board, no turn status, no play controls, and — with nothing going —
    /// no current-game card either.
    func testTheHomeOffersTheWaysToPlayAndNoBoard() {
        let app = launch()

        XCTAssertTrue(app.buttons["mode-human-versus-ai"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["mode-free-play"].exists)
        XCTAssertEqual(app.buttons["mode-human-versus-ai"].label, "人机对弈")
        XCTAssertEqual(app.buttons["mode-free-play"].label, "自由对弈")

        XCTAssertFalse(point(app, "d4").exists, "no board is addressable on the home")
        XCTAssertFalse(app.staticTexts["turn-status"].exists, "and nothing about a turn")
        XCTAssertFalse(app.buttons["cluster-undo"].exists, "and no play controls")
        XCTAssertFalse(app.buttons["setup-start"].exists, "the pre-start page is elsewhere")
        XCTAssertFalse(app.staticTexts["home-current-game"].exists,
                       "with no game there is no current game to describe")
        XCTAssertFalse(app.buttons["home-resume"].exists)
        attach(app, named: "60-the-play-home")
    }

    /// Each way to play is reached from the home, and each opens its own
    /// pre-start page — which keeps its preview board, unchanged.
    func testEachModeIsStartedFromTheHome() {
        let app = launch()
        XCTAssertTrue(app.buttons["mode-human-versus-ai"].waitForExistence(timeout: 20))

        app.buttons["mode-human-versus-ai"].click()
        XCTAssertTrue(app.staticTexts["setup-header"].waitForExistence(timeout: 5),
                      "人机对弈 opens its 本局设置 page")
        XCTAssertTrue(app.buttons["setup-start"].exists)
        XCTAssertTrue(app.windows.firstMatch.descendants(matching: .any)["setup-first-mover"].exists,
                      "with the group of per-game choices only this mode has")
        attach(app, named: "61-the-human-versus-ai-pre-start-page-from-the-home")

        goBack(app)
        XCTAssertTrue(app.buttons["mode-free-play"].waitForExistence(timeout: 5),
                      "and going back returns to the home")

        app.buttons["mode-free-play"].click()
        XCTAssertTrue(app.staticTexts["setup-explanation"].waitForExistence(timeout: 5))
        app.buttons["setup-start"].click()
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 15),
                      "开始对局 creates the game and the board opens")
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮")
    }

    // MARK: - The game that is already going

    /// The card, the way back into the game, and the metadata that describes it
    /// — read off the game rather than composed from anything the home knows.
    func testTheHomeDescribesTheActiveGameAndResumesIt() {
        let app = launch(replaying: Self.openingLine)
        XCTAssertTrue(point(app, "d4").waitForExistence(timeout: 20),
                      "a launch with a game to resume opens at the board")

        goBack(app)

        XCTAssertTrue(app.staticTexts["home-current-game"].waitForExistence(timeout: 5))
        XCTAssertEqual(reading(app, "home-current-game"),
                       "自由对弈 · 进行中 · 轮到红方 · 2 步",
                       "the accepted metadata composition, on the game as it stands")
        XCTAssertEqual(app.buttons["home-resume"].label, "回到对局")
        XCTAssertFalse(point(app, "d4").exists, "and still no board on the home")
        attach(app, named: "62-the-play-home-with-a-game-going")

        app.buttons["home-resume"].click()
        XCTAssertTrue(point(app, "d4").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["炮六进二"].exists,
                      "the same game, exactly where it was left")
    }

    /// The accepted confirmation, and what 保存并继续 does: the old game filed as
    /// ended early, and the chosen mode's pre-start page open with no new game.
    func testSwitchingModeMidGameFilesTheGameAndOpensTheOtherMode() {
        let app = launch(replaying: Self.openingLine)
        XCTAssertTrue(point(app, "d4").waitForExistence(timeout: 20))
        goBack(app)
        XCTAssertTrue(app.buttons["mode-human-versus-ai"].waitForExistence(timeout: 5))

        app.buttons["mode-human-versus-ai"].click()

        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5),
                      "a mode entry over a game confirms rather than navigating")
        // Everything the alert says, however this platform apportions it
        // between the sheet's own label and the text inside it.
        let said = ([confirmation.label]
                    + confirmation.staticTexts.allElementsBoundByIndex
                        .map { ($0.value as? String) ?? $0.label }).joined(separator: "\n")
        XCTAssertTrue(said.contains("开始新对局？"), "the accepted title — it reads \(said)")
        XCTAssertTrue(said.contains("当前对局"), "the accepted metadata header")
        XCTAssertTrue(said.contains("自由对弈 · 进行中 · 轮到红方 · 2 步"),
                      "over the same line the card shows — it reads \(said)")
        XCTAssertTrue(said.contains("这盘对局将按当前状态保存到历史。"))
        XCTAssertTrue(confirmation.buttons["取消"].exists)
        XCTAssertTrue(confirmation.buttons["保存并继续"].exists)
        attach(app, named: "63-the-save-and-continue-confirmation")

        confirmation.buttons["保存并继续"].click()

        XCTAssertTrue(app.staticTexts["setup-header"].waitForExistence(timeout: 10),
                      "the selected mode's pre-start page opens")
        XCTAssertFalse(app.staticTexts["turn-status"].exists,
                       "and no new game exists until 开始对局 succeeds")
        attach(app, named: "64-the-chosen-mode-after-saving")

        destination(app, 1).click()
        XCTAssertTrue(historyRow(app, 0).waitForExistence(timeout: 10),
                      "the game that was going is in History")
        XCTAssertTrue(historyRow(app, 0).label.contains("自由对弈 · 提前结束 · 2 步"),
                      "recorded as ended early with no competitive result — it reads "
                      + historyRow(app, 0).label)
        XCTAssertFalse(historyRow(app, 1).exists, "one game, one record")
    }

    /// An unconfirmed natural result keeps its own result when it is filed this
    /// way. The classification is the core's, and this is the case where it is
    /// not 提前结束.
    func testAFinishedGameKeepsItsResultThroughTheSwitch() {
        let app = launch(replaying: Self.mateLine)
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 20))
        app.buttons["result-close"].click()

        goBack(app)
        XCTAssertTrue(app.staticTexts["home-current-game"].waitForExistence(timeout: 5))
        XCTAssertEqual(reading(app, "home-current-game"),
                       "自由对弈 · 红方获胜 · 将死 · 3 步",
                       "a result the player has not confirmed is still the active game")

        app.buttons["mode-free-play"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons["保存并继续"].click()
        XCTAssertTrue(app.staticTexts["setup-explanation"].waitForExistence(timeout: 10))

        destination(app, 1).click()
        XCTAssertTrue(historyRow(app, 0).waitForExistence(timeout: 10))
        XCTAssertTrue(historyRow(app, 0).label.contains("自由对弈 · 红方获胜 · 将死 · 3 步"),
                      "its actual winner and its exact reason — it reads "
                      + historyRow(app, 0).label)
    }

    /// The refusal, on the real screen: with the store refusing the archive,
    /// 保存并继续 files nothing and the accepted 无法保存对局 retry presents over
    /// a game that is exactly as it stood. 取消 discards the remembered
    /// destination and leaves the game there to go back to.
    func testARefusedArchiveKeepsTheGameAndPresentsTheRetry() {
        let app = launch(refusingSaves: true)
        XCTAssertTrue(app.buttons["mode-free-play"].waitForExistence(timeout: 20))

        // The game this is about, created on the screen: a refusing store still
        // creates, because a stand-in that would not let a game be created
        // could never reach a game to refuse.
        app.buttons["mode-free-play"].click()
        XCTAssertTrue(app.buttons["setup-start"].waitForExistence(timeout: 5))
        app.buttons["setup-start"].click()
        XCTAssertTrue(point(app, "d4").waitForExistence(timeout: 15),
                      "开始对局 creates the game and the board opens")

        goBack(app)
        XCTAssertTrue(app.staticTexts["home-current-game"].waitForExistence(timeout: 5))
        let line = reading(app, "home-current-game")
        XCTAssertEqual(line, "自由对弈 · 进行中 · 轮到红方 · 0 步",
                       "the game as it stands, before anything is asked of it")

        app.buttons["mode-human-versus-ai"].click()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["保存并继续"].click()

        // The retry, by the one button only it carries — the confirmation that
        // is dismissing itself has 保存并继续 and this one does not.
        let refusal = app.sheets.firstMatch
        XCTAssertTrue(refusal.buttons["重试"].waitForExistence(timeout: 10),
                      "a refused archive presents the accepted retry")
        let said = ([refusal.label]
                    + refusal.staticTexts.allElementsBoundByIndex
                        .map { ($0.value as? String) ?? $0.label }).joined(separator: "\n")
        XCTAssertTrue(said.contains("无法保存对局"), "the accepted title — it reads \(said)")
        XCTAssertTrue(said.contains("当前对局仍然保留。请重试。"),
                      "and the accepted message — it reads \(said)")
        XCTAssertTrue(refusal.buttons["取消"].exists)
        attach(app, named: "65-the-refused-save-and-continue")

        refusal.buttons["取消"].click()

        XCTAssertTrue(app.buttons["mode-free-play"].waitForExistence(timeout: 5),
                      "the home is still the page")
        XCTAssertFalse(app.buttons["setup-start"].exists,
                       "a refusal never enters a pre-start state")
        XCTAssertEqual(reading(app, "home-current-game"), line,
                       "and the game is exactly as it stood")

        destination(app, 1).click()
        XCTAssertTrue(app.staticTexts["还没有历史对局"].waitForExistence(timeout: 10),
                      "a refusal commits nothing")

        destination(app, 0).click()
        XCTAssertTrue(app.buttons["home-resume"].waitForExistence(timeout: 5))
        app.buttons["home-resume"].click()
        XCTAssertTrue(point(app, "d4").waitForExistence(timeout: 10),
                      "and the game the retry was about is still there to go back to")
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮")
    }

    /// 取消 leaves everything exactly as it was: the game, the page, and an
    /// empty History.
    func testCancellingTheConfirmationChangesNothing() {
        let app = launch(replaying: Self.openingLine)
        XCTAssertTrue(point(app, "d4").waitForExistence(timeout: 20))
        goBack(app)
        XCTAssertTrue(app.buttons["mode-free-play"].waitForExistence(timeout: 5))

        app.buttons["mode-free-play"].click()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["取消"].click()

        XCTAssertTrue(app.buttons["mode-free-play"].waitForExistence(timeout: 5),
                      "the home is still the page")
        XCTAssertFalse(app.buttons["setup-start"].exists, "no pre-start page opened")
        XCTAssertEqual(reading(app, "home-current-game"),
                       "自由对弈 · 进行中 · 轮到红方 · 2 步",
                       "and the game is untouched")

        destination(app, 1).click()
        XCTAssertTrue(app.staticTexts["还没有历史对局"].waitForExistence(timeout: 10),
                      "cancelling files nothing")

        // And the game is still there to go back to.
        destination(app, 0).click()
        XCTAssertTrue(app.buttons["home-resume"].waitForExistence(timeout: 5))
        app.buttons["home-resume"].click()
        XCTAssertTrue(app.staticTexts["炮六进二"].waitForExistence(timeout: 10))
    }
}

#endif  // os(macOS)
