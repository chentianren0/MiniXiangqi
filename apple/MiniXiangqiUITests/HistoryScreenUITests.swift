// The History destination and its replay, on the running app.
//
// Every game these tests act on was played and filed by the app itself: the
// launch argument replays a line through the core, ply by ply, and files it
// through the same terminal commit the concluding action uses. So the rows are
// records the app could have made, and the list is the store's answer rather
// than a fixture.
//
// The words are written out here rather than read from the application's own
// catalog, exactly as PlayScreenUITests writes them: what needs proving is that
// the accepted words reach the screen.

// **macOS only.** The bundle this file lives in builds for an iOS Simulator too
// now, and this suite does not go there: it drives a window — naming a size,
// reading the frame back, clicking and right-clicking a pointer, typing keys —
// and a window is what iOS has not got. The phone's own evidence is the
// `Phone…UITests` files beside this one, which are a different suite rather than
// a port of this one.
#if os(macOS)

import AppKit
import XCTest

@MainActor
final class HistoryScreenUITests: XCTestCase {

    /// Three games, filed in this order, so the list has a shape worth looking
    /// at: a mate, a claimed draw, and the same mate reached after a shuffle —
    /// two results and three move counts.
    private static let threeGames = [
        "b1b3,b7b6,b3d3",
        "b1b2,b7b6,b2b1,b6b7,b1b2,b7b6,b2b1,b6b7",
        "b1b2,b7b6,b2b1,b6b7,b1b3,b7b6,b3d3",
    ].joined(separator: ";")

    private struct Language {
        let code: String
        let short: String

        /// The three rows' metadata lines, newest first.
        let rows: [String]
        let pinnedSection, otherSection: String
        let emptyTitle, emptyDescription: String
        let pin, unpin, delete, cancel, share: String
        let deleteTitle, deleteMessage: String
        let flipBoard: String
        /// The imported row's own line: the marker, and the game behind it.
        let importedMarker, importedRow: String
        let duplicateTitle, duplicateMessage, view, ok: String
        let newerVersionTitle, newerVersionMessage: String

        static let chinese = Language(
            code: "zh-Hans", short: "zh",
            rows: ["自由对弈 · 红方获胜 · 将死 · 7 步",
                   "自由对弈 · 和棋 · 三次重复 · 8 步",
                   "自由对弈 · 红方获胜 · 将死 · 3 步"],
            pinnedSection: "已置顶", otherSection: "其他对局",
            emptyTitle: "还没有历史对局",
            emptyDescription: "对局结束后会保存到这里。",
            pin: "置顶", unpin: "取消置顶", delete: "删除", cancel: "取消",
            share: "共享",
            deleteTitle: "删除这盘棋？", deleteMessage: "删除后无法恢复。",
            flipBoard: "翻转棋盘",
            importedMarker: "导入",
            importedRow: "人机对弈 · 你执红 · 红方获胜 · 将死 · 3 步",
            duplicateTitle: "这盘棋已经在历史里",
            duplicateMessage: "文件里的对局和历史中的一盘完全相同，所以没有重复添加。",
            view: "查看", ok: "好",
            newerVersionTitle: "这个文件由更新版本的 Mini Xiangqi 创建",
            newerVersionMessage: "当前版本无法读取它。请更新 Mini Xiangqi 后再试。历史没有改变。")

        static let english = Language(
            code: "en", short: "en",
            rows: ["Free Play · Red Wins · Checkmate · 7 moves",
                   "Free Play · Draw · Threefold Repetition · 8 moves",
                   "Free Play · Red Wins · Checkmate · 3 moves"],
            pinnedSection: "Pinned", otherSection: "Other Games",
            emptyTitle: "No Games Yet",
            emptyDescription: "Games you finish are saved here.",
            pin: "Pin", unpin: "Unpin", delete: "Delete", cancel: "Cancel",
            share: "Share",
            deleteTitle: "Delete this game?", deleteMessage: "This game can't be recovered.",
            flipBoard: "Flip Board",
            importedMarker: "Imported",
            importedRow: "Human versus AI · You: Red · Red Wins · Checkmate · 3 moves",
            duplicateTitle: "This Game Is Already in History",
            duplicateMessage: "The game in this file is identical to one already in History, so it wasn't added again.",
            view: "View", ok: "OK",
            newerVersionTitle: "This File Was Created by a Newer Version of Mini Xiangqi",
            newerVersionMessage: "This version can't read it. Update Mini Xiangqi and try again. History is unchanged.")
    }

    /// One of the archive corpus's own goldens, verbatim: a human-versus-AI
    /// game red mated in three plies. It is written out rather than read from
    /// `fixtures/archive/` because the runner and the app are separate
    /// sandboxes and neither can reach a path in the repository — the same
    /// reason the launch argument carries the bytes rather than a path.
    private static let goldenGame = """
    {"archive_format":"minixiangqi-game","archive_version":2,"content":{"ai_level":"standard","ai_movetime_ms":3000,"end_reason":"checkmate","ended_at":"2026-01-01T00:00:04.000Z","first_mover_choice":"human-first","human_side":"red","mode":"human-vs-ai","moves":["b1b3","a6a5","b3d3"],"outcome":"red-wins","rules_id":"minixiangqi","rules_version":1,"start_fen":"rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1","started_at":"2026-01-01T00:00:00.000Z"},"game_id":"019b76da-a803-7000-8000-000000000003","origin":{"app_version":"1.0.0","exported_at":"2026-01-01T00:00:04.000Z"}}
    """

    /// The corpus's created-by-a-newer-version rejection, which is the one
    /// message the data contract requires to be distinct.
    private static let newerVersionGame = """
    {"archive_format":"minixiangqi-game","archive_version":3,"content":{"a_member_from_the_future":"x","mode":"free-play","moves":["b1b3","b7b5"],"rules_id":"minixiangqi","rules_version":1,"start_fen":"rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1","started_at":"2026-01-01T00:00:00.000Z"},"game_id":"019b76da-a800-7000-8000-000000000000","origin":{"app_version":"1.0.0","exported_at":"2026-01-01T00:01:00.000Z"}}
    """

    private func launch(history: String? = nil,
                        importing files: [String] = [],
                        in language: Language = .chinese,
                        window: String = "900x600") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language.code))"]
        app.launchArguments += ["-mxq-store-name", "mxq-uitest-store-\(UUID().uuidString)"]
        // Every preference stated, and a scratch domain to write into: this
        // suite asserts the accepted defaults, and a launch that named none
        // would be asserting whatever the machine's own preferences say.
        app.launchArguments += ["-mxq-defaults-suite", LaunchPreferences.scratchSuite]
        app.launchArguments += LaunchPreferences.arguments()
        app.launchArguments += ["-mxq-window", window]
        if let history { app.launchArguments += ["-mxq-history", history] }
        if !files.isEmpty {
            // Base64, because a launch argument is a string and a game file is
            // bytes. The app decodes and feeds each one through the same call
            // the file picker's completion makes.
            let encoded = files
                .map { Data($0.utf8).base64EncodedString() }
                .joined(separator: ";")
            app.launchArguments += ["-mxq-import", encoded]
        }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        // The Play destination settles the launch: the seeding runs before it,
        // so anything on screen there means every seeded game has been filed.
        // With the seeded games filed there is no active game left, so what
        // arrives is the Play home's mode entries rather than a board.
        XCTAssertTrue(app.buttons["mode-human-versus-ai"].waitForExistence(timeout: 15))
        return app
    }

    /// The navigation's two destinations, by position: Play then History. A
    /// position rather than a label, because the label is copy and these tests
    /// run in both languages.
    private func destination(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.windows.firstMatch.outlines.element(boundBy: 0).cells.element(boundBy: index)
    }

    private func openHistory(_ app: XCUIApplication) {
        destination(app, 1).click()
    }

    private func row(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.windows.firstMatch.buttons["history-row-\(index)"]
    }

    /// Opens one row's context menu — the pointer equivalent the contract asks
    /// for. The menu is addressed by the row's own identifier rather than
    /// globally, because the app's menu bar carries a Delete of its own and the
    /// two titles would otherwise collide.
    private func invoke(_ title: String, onRow index: Int, in app: XCUIApplication) {
        let row = row(app, index)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let item = app.menus["history-row-\(index)"].menuItems[title]
        // A right-click that lands while the window is coming back to the front
        // — just after an alert was dismissed, say — activates the window and
        // opens nothing, and one that lands mid-relayout can open a menu that
        // closes again before it is read. That is the window server's business
        // rather than the app's, so the whole open-and-read is retried until
        // the item itself is there to click.
        for _ in 0..<3 {
            row.rightClick()
            if item.waitForExistence(timeout: 3) {
                item.click()
                // The menu dismisses and the list re-lays out; the next
                // interaction has to address the list rather than a menu on
                // its way out.
                Thread.sleep(forTimeInterval: 0.5)
                return
            }
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTFail("the row's context menu should offer \(title)")
    }

    /// Opens one row's context menu and leaves it open, retried for the same
    /// window-server reasons `invoke` retries. Returns the menu once `title` is
    /// in it; the caller closes it.
    @discardableResult
    private func openMenu(showing title: String, onRow index: Int,
                          in app: XCUIApplication) -> XCUIElement {
        let row = row(app, index)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let menu = app.menus["history-row-\(index)"]
        for _ in 0..<3 {
            row.rightClick()
            if menu.menuItems[title].waitForExistence(timeout: 3) { return menu }
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTFail("the row's context menu should offer \(title)")
        return menu
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The list

    func testTheListShowsEveryFiledGameNewestFirst() {
        let app = launch(history: Self.threeGames)
        openHistory(app)

        let language = Language.chinese
        for (index, metadata) in language.rows.enumerated() {
            let row = row(app, index)
            XCTAssertTrue(row.waitForExistence(timeout: 10), "row \(index) should be in the list")
            XCTAssertTrue(row.label.contains(metadata),
                          "row \(index) should read \(metadata) — it reads \(row.label)")
        }
        XCTAssertFalse(row(app, 3).exists, "three games were filed, so there are three rows")
        // Nothing is pinned, so there is one unheaded section and the list
        // looks like a plain list of games.
        XCTAssertFalse(app.staticTexts[language.pinnedSection].exists)
        XCTAssertFalse(app.staticTexts[language.otherSection].exists)
        attach(app, named: "24-the-history-list")
    }

    func testPinningMovesAGameToItsOwnSection() {
        let app = launch(history: Self.threeGames)
        openHistory(app)
        let language = Language.chinese
        XCTAssertTrue(row(app, 0).waitForExistence(timeout: 10))

        // The oldest game, which is last: pinning it must move it to the front.
        invoke(language.pin, onRow: 2, in: app)

        XCTAssertTrue(app.staticTexts[language.pinnedSection].waitForExistence(timeout: 5),
                      "a pinned record puts the two accepted groups on screen")
        XCTAssertTrue(app.staticTexts[language.otherSection].exists)
        XCTAssertTrue(row(app, 0).label.contains(language.rows[2]),
                      "the pinned game is now first — the core's order, not this screen's")
        XCTAssertTrue(row(app, 1).label.contains(language.rows[0]))
        attach(app, named: "25-the-history-list-with-a-pinned-game")

        // And unpinning puts it back where its date says it belongs.
        invoke(language.unpin, onRow: 0, in: app)
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, 2).label.contains(language.rows[2]),
                      "unpinned, it is the oldest game again")
        XCTAssertFalse(app.staticTexts[language.pinnedSection].exists,
                       "and with nothing pinned there is one unheaded section again")
    }

    func testAnEmptyHistorySaysSo() {
        let app = launch()
        openHistory(app)
        let language = Language.chinese

        XCTAssertTrue(app.staticTexts[language.emptyTitle].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[language.emptyDescription].exists)
        XCTAssertFalse(row(app, 0).exists)
        attach(app, named: "26-the-empty-history")
    }

    // MARK: - Deletion

    func testDeletingAGameAsksFirstAndIsPermanent() {
        let app = launch(history: Self.threeGames)
        openHistory(app)
        let language = Language.chinese
        XCTAssertTrue(row(app, 0).waitForExistence(timeout: 10))

        invoke(language.delete, onRow: 1, in: app)

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5),
                      "删除前确认 defaults on, so a deletion asks")
        let lines = sheet.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(lines, [language.deleteTitle, language.deleteMessage])
        attach(app, named: "27-the-deletion-confirmation")

        // Cancelling changes nothing: the record remains in the list.
        sheet.buttons[language.cancel].click()
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, 1).label.contains(language.rows[1]),
                      "the game the player did not delete is still there")

        invoke(language.delete, onRow: 1, in: app)
        app.sheets.firstMatch.buttons[language.delete].click()

        XCTAssertTrue(app.buttons["history-row-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, 2).exists, "two games are left")
        XCTAssertTrue(row(app, 0).label.contains(language.rows[0]))
        XCTAssertTrue(row(app, 1).label.contains(language.rows[2]),
                      "and the deleted one is gone from between them")
    }

    // MARK: - Share

    /// 共享 exports the selected record as one game file. What can be asserted
    /// from here is that the action is on every row, in the surface the
    /// contract names, and that invoking it opens the system's own share UI:
    /// past that point the sheet belongs to the system and this suite has no
    /// business inside it.
    func testEveryRowOffersShare() {
        let app = launch(history: Self.threeGames)
        openHistory(app)
        let language = Language.chinese
        XCTAssertTrue(row(app, 0).waitForExistence(timeout: 10))

        for index in 0..<3 {
            openMenu(showing: language.share, onRow: index, in: app)
            if index == 0 { attach(app, named: "36-the-share-action-on-a-row") }
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.4)
        }

        // And it really invokes: the share UI comes up over the window, and the
        // escape key puts it away again with the list untouched behind it.
        invoke(language.share, onRow: 0, in: app)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(row(app, 0).waitForExistence(timeout: 5),
                      "the list is exactly as it was")
        XCTAssertTrue(row(app, 2).exists, "and still holds all three games")
    }

    // MARK: - Import

    /// One game file, imported end to end through the real pipeline: the bytes
    /// go to `mxq_store_import`, the record it creates is what the list reads,
    /// and the row that appears is the whole of the success presentation.
    func testImportingAGameAddsItToTheList() {
        let app = launch(importing: [Self.goldenGame])
        openHistory(app)
        let language = Language.chinese

        let row = row(app, 0)
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the imported game is in the list")
        XCTAssertTrue(row.label.contains(language.importedRow),
                      "and reads as the game the file described — it reads \(row.label)")
        XCTAssertTrue(row.label.contains(language.importedMarker),
                      "with the imported marker the contract asks for")
        // A successful import says nothing: the row is the answer. Asserted as
        // the absence of the words an import would have said rather than as the
        // absence of a sheet — the window carries containers a sheet query can
        // match that have nothing to do with an alert.
        XCTAssertFalse(app.staticTexts[language.duplicateTitle].exists)
        XCTAssertFalse(app.staticTexts[language.newerVersionTitle].exists)
        XCTAssertFalse(app.buttons[language.ok].exists,
                       "and no alert to acknowledge")
        XCTAssertFalse(self.row(app, 1).exists, "one file, one game")
        attach(app, named: "37-the-imported-game-in-the-list")
    }

    /// The same file twice. The second import is a success that deliberately
    /// does not meet the expectation a first one sets, which is exactly when an
    /// alert is right — and it offers the record it found.
    func testImportingTheSameGameTwiceSaysSo() {
        let app = launch(importing: [Self.goldenGame, Self.goldenGame])
        openHistory(app)
        let language = Language.chinese

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        let lines = sheet.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(lines, [language.duplicateTitle, language.duplicateMessage])
        XCTAssertTrue(sheet.buttons[language.view].exists,
                      "the accepted answer offers a way to view the existing record")
        attach(app, named: "38-the-duplicate-answer")

        // 查看 opens the record the library already had.
        sheet.buttons[language.view].click()
        let progress = app.windows.firstMatch.descendants(matching: .any)["replay-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(progress.value as? String, "0 / 3",
                       "which is the game the file described")
    }

    /// The one rejection the data contract requires to be distinguishable, and
    /// never to be presented as corruption.
    func testAFileFromANewerVersionSaysThatAndNotCorruption() {
        let app = launch(importing: [Self.newerVersionGame])
        openHistory(app)
        let language = Language.chinese

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        let lines = sheet.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(lines, [language.newerVersionTitle, language.newerVersionMessage])
        // Not corruption, in either language: the message says what is true.
        XCTAssertFalse(lines.contains { $0.contains("损坏") })
        attach(app, named: "39-the-newer-version-answer")

        sheet.buttons[language.ok].click()
        XCTAssertTrue(app.staticTexts[language.emptyTitle].waitForExistence(timeout: 5),
                      "and the library is exactly as empty as it was")
    }

    // MARK: - Replay

    func testReplayWalksTheRecordedGame() {
        let app = launch(history: Self.threeGames)
        openHistory(app)
        XCTAssertTrue(row(app, 0).waitForExistence(timeout: 10))
        row(app, 0).click()

        let window = app.windows.firstMatch
        let progress = window.descendants(matching: .any)["replay-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "replay opens on the record")
        XCTAssertEqual(progress.value as? String, "0 / 7",
                       "replay begins at the game's initial position")
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮",
                       "and the initial position is the starting one")
        XCTAssertFalse(app.buttons["replay-first"].isEnabled, "there is nothing before it")
        XCTAssertFalse(app.buttons["replay-previous"].isEnabled)
        XCTAssertTrue(app.buttons["replay-next"].isEnabled)

        // The board is a read-only document: a click on it does nothing at all.
        point(app, "b1").click()
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮",
                       "no piece is ever held in replay")

        app.buttons["replay-next"].click()
        app.buttons["replay-next"].click()
        app.buttons["replay-next"].click()
        app.buttons["replay-next"].click()
        app.buttons["replay-next"].click()
        XCTAssertEqual(progress.value as? String, "5 / 7")
        XCTAssertEqual(point(app, "b3").label, "b3 红 炮",
                       "the cannon stands where the fifth ply put it")
        attach(app, named: "28-replay-mid-walk")

        app.buttons["replay-last"].click()
        XCTAssertEqual(progress.value as? String, "7 / 7")
        XCTAssertEqual(point(app, "d3").label, "d3 红 炮", "the mating move's square")
        XCTAssertEqual(point(app, "d7").label, "d7 黑 将 被将军",
                       "and the checked general carries the state, with no piece held to hide it")
        XCTAssertFalse(app.buttons["replay-next"].isEnabled, "and nothing after the last ply")
        XCTAssertFalse(app.buttons["replay-last"].isEnabled)
        attach(app, named: "29-replay-at-the-final-position")

        app.buttons["replay-first"].click()
        XCTAssertEqual(progress.value as? String, "0 / 7")
    }

    /// The same walk, one ply at a time, with the travel in it.
    ///
    /// A step travels for 180–240 ms and the disc is on its point when it
    /// stops. That instant is what this waits for and photographs; mid-travel
    /// is deliberately not photographed, because a frame 100 ms into an
    /// animation is not something a test can ask for and get the same answer
    /// twice. What the animation must not cost is that every ply still arrives,
    /// exactly once, at the point the record says — and that is a claim a test
    /// can make.
    func testEachStepTravelsAndLandsOnItsPoint() {
        let app = launch(history: Self.threeGames)
        openHistory(app)
        XCTAssertTrue(row(app, 0).waitForExistence(timeout: 10))
        row(app, 0).click()

        let progress = app.windows.firstMatch.descendants(matching: .any)["replay-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(progress.value as? String, "0 / 7")

        // Pressed the way a person presses it: each ply is let land before the
        // next is asked for.
        for ply in 1...7 {
            app.buttons["replay-next"].click()
            let arrived = expectation(for: NSPredicate(format: "value == '\(ply) / 7'"),
                                      evaluatedWith: progress)
            wait(for: [arrived], timeout: 5)
        }

        XCTAssertEqual(point(app, "d3").label, "d3 红 炮",
                       "the cannon settled on the mating move's point")
        XCTAssertEqual(point(app, "b3").label, "b3 空",
                       "and left the one it travelled from")
        XCTAssertEqual(point(app, "d7").label, "d7 黑 将 被将军")
        attach(app, named: "31-replay-a-step-landed")

        // Backwards through the take-back the same way: the mover returns and
        // the position is the record's own again.
        app.buttons["replay-previous"].click()
        let back = expectation(for: NSPredicate(format: "value == '6 / 7'"),
                               evaluatedWith: progress)
        wait(for: [back], timeout: 5)
        XCTAssertEqual(point(app, "b3").label, "b3 红 炮", "the cannon came back")
        XCTAssertEqual(point(app, "d3").label, "d3 空")
    }

    func testAutoplayWalksItselfAndAManualStepStopsIt() {
        let app = launch(history: Self.threeGames)
        openHistory(app)
        XCTAssertTrue(row(app, 0).waitForExistence(timeout: 10))
        row(app, 0).click()

        let progress = app.windows.firstMatch.descendants(matching: .any)["replay-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        app.buttons["replay-autoplay"].click()
        attach(app, named: "30-replay-playing")

        // It walks forward on its own, and stops at the final position.
        let finished = expectation(for: NSPredicate(format: "value == '7 / 7'"),
                                   evaluatedWith: progress)
        wait(for: [finished], timeout: 20)
        XCTAssertEqual(app.buttons["replay-autoplay"].label, "自动播放",
                       "playback stopped, so the control offers to start again")
    }

    func testTheMoveListJumpsToASelectedMove() {
        let app = launch(history: Self.threeGames)
        openHistory(app)
        XCTAssertTrue(row(app, 0).waitForExistence(timeout: 10))
        row(app, 0).click()

        let progress = app.windows.firstMatch.descendants(matching: .any)["replay-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["move-4"].label, "炮六进二",
                       "the whole recorded line reads in traditional notation from the start")

        app.buttons["move-3"].click()
        XCTAssertEqual(progress.value as? String, "4 / 7",
                       "selecting the fourth move shows the position it produced")
    }

    // MARK: - One window

    /// The product excludes multiple main windows, and on macOS the exclusion
    /// is enforced by the scene type rather than by a policy anyone has to
    /// remember: a `Window` has no New Window command to invoke. The cheapest
    /// honest form of that claim is to ask the app for one and count.
    func testTheAppHasExactlyOneMainWindow() {
        let app = launch(history: Self.threeGames)
        XCTAssertEqual(app.windows.count, 1)

        app.typeKey("n", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.windows.count, 1, "⌘N opens nothing: there is one window scene")

        let file = app.menuBars.menuBarItems["File"]
        if file.exists {
            file.click()
            XCTAssertFalse(app.menuItems["New Window"].exists,
                           "and the File menu carries no New Window item")
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    // MARK: - The two languages

    /// The History surfaces in each language, photographed. The list, the
    /// empty state, the deletion confirmation, and replay mid-walk are the four
    /// frames the copy lives on.
    func testTheHistorySurfacesInChinese() {
        photographHistory(in: .chinese)
    }

    func testTheHistorySurfacesInEnglish() {
        photographHistory(in: .english)
    }

    private func photographHistory(in language: Language) {
        let app = launch(history: Self.threeGames, in: language)
        openHistory(app)
        XCTAssertTrue(row(app, 0).waitForExistence(timeout: 10))
        for (index, metadata) in language.rows.enumerated() {
            XCTAssertTrue(row(app, index).label.contains(metadata),
                          "row \(index) reads \(row(app, index).label)")
        }

        // Pin the oldest, so the frame carries both accepted groups.
        invoke(language.pin, onRow: 2, in: app)
        XCTAssertTrue(app.staticTexts[language.pinnedSection].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[language.otherSection].exists)
        attach(app, named: "\(language.short)-history-list")

        // The row's actions, where 共享 now stands beside the two that were
        // already there — this language's words for all three.
        let menu = openMenu(showing: language.share, onRow: 0, in: app)
        XCTAssertTrue(menu.menuItems[language.delete].exists)
        XCTAssertTrue(menu.menuItems[language.unpin].exists,
                      "the pinned row offers to unpin, not to pin again")
        attach(app, named: "\(language.short)-history-row-actions")
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // The deletion confirmation, which is the one irreversible act here.
        invoke(language.delete, onRow: 1, in: app)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let lines = sheet.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(lines, [language.deleteTitle, language.deleteMessage])
        attach(app, named: "\(language.short)-history-delete-confirmation")
        sheet.buttons[language.cancel].click()

        // Replay, part-way through, with the transport under the list.
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: 5))
        row(app, 1).click()
        let progress = app.windows.firstMatch.descendants(matching: .any)["replay-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        app.buttons["replay-next"].click()
        app.buttons["replay-next"].click()
        app.buttons["replay-next"].click()
        XCTAssertEqual(progress.value as? String, "3 / 7")
        XCTAssertEqual(app.buttons["replay-flip"].label, language.flipBoard)
        // Traditional notation is game presentation, not interface copy: it
        // reads the same in either language.
        XCTAssertEqual(app.buttons["move-4"].label, "炮六进二")
        attach(app, named: "\(language.short)-replay")

        // The empty state, in a store nothing was filed into.
        let empty = launch(in: language)
        openHistory(empty)
        XCTAssertTrue(empty.staticTexts[language.emptyTitle].waitForExistence(timeout: 10))
        XCTAssertTrue(empty.staticTexts[language.emptyDescription].exists)
        attach(empty, named: "\(language.short)-history-empty")

        // Import: the same file twice, so one frame carries the row a
        // successful import produces and the other the duplicate's answer.
        let imported = launch(importing: [Self.goldenGame, Self.goldenGame], in: language)
        openHistory(imported)
        let duplicate = imported.sheets.firstMatch
        XCTAssertTrue(duplicate.waitForExistence(timeout: 15))
        let duplicateLines = duplicate.staticTexts.allElementsBoundByIndex
            .map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(duplicateLines, [language.duplicateTitle, language.duplicateMessage])
        attach(imported, named: "\(language.short)-import-duplicate")

        duplicate.buttons[language.ok].click()
        XCTAssertTrue(row(imported, 0).waitForExistence(timeout: 5))
        XCTAssertTrue(row(imported, 0).label.contains(language.importedRow))
        XCTAssertTrue(row(imported, 0).label.contains(language.importedMarker))
        attach(imported, named: "\(language.short)-history-imported-row")

        // And the refusal the compatibility promise is written as.
        let refused = launch(importing: [Self.newerVersionGame], in: language)
        openHistory(refused)
        let newer = refused.sheets.firstMatch
        XCTAssertTrue(newer.waitForExistence(timeout: 15))
        let newerLines = newer.staticTexts.allElementsBoundByIndex
            .map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(newerLines, [language.newerVersionTitle, language.newerVersionMessage])
        attach(refused, named: "\(language.short)-import-newer-version")
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["point-\(name)"]
    }
}

#endif  // os(macOS)
