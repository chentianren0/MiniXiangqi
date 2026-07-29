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
        let pin, unpin, delete, cancel: String
        let deleteTitle, deleteMessage: String
        let flipBoard: String

        static let chinese = Language(
            code: "zh-Hans", short: "zh",
            rows: ["自由对弈 · 红方获胜 · 将死 · 7 步",
                   "自由对弈 · 和棋 · 三次重复 · 8 步",
                   "自由对弈 · 红方获胜 · 将死 · 3 步"],
            pinnedSection: "已置顶", otherSection: "其他对局",
            emptyTitle: "还没有历史对局",
            emptyDescription: "对局结束后会保存到这里。",
            pin: "置顶", unpin: "取消置顶", delete: "删除", cancel: "取消",
            deleteTitle: "删除这盘棋？", deleteMessage: "删除后无法恢复。",
            flipBoard: "翻转棋盘")

        static let english = Language(
            code: "en", short: "en",
            rows: ["Free Play · Red Wins · Checkmate · 7 moves",
                   "Free Play · Draw · Threefold Repetition · 8 moves",
                   "Free Play · Red Wins · Checkmate · 3 moves"],
            pinnedSection: "Pinned", otherSection: "Other Games",
            emptyTitle: "No Games Yet",
            emptyDescription: "Games you finish are saved here.",
            pin: "Pin", unpin: "Unpin", delete: "Delete", cancel: "Cancel",
            deleteTitle: "Delete this game?", deleteMessage: "This game can't be recovered.",
            flipBoard: "Flip Board")
    }

    private func launch(history: String? = nil,
                        in language: Language = .chinese,
                        window: String = "900x600") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language.code))"]
        app.launchArguments += ["-mxq-store-name", "mxq-uitest-store-\(UUID().uuidString)"]
        app.launchArguments += ["-mxq-window", window]
        if let history { app.launchArguments += ["-mxq-history", history] }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        // The board settles the launch: the seeding runs before it, so a board
        // on screen means every seeded game has been filed.
        XCTAssertTrue(app.windows.firstMatch.descendants(matching: .any)["point-d1"]
            .waitForExistence(timeout: 15))
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
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["point-\(name)"]
    }
}
