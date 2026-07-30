// The Settings destination, on the running app.
//
// The words are written out here rather than read from the application's own
// catalog, exactly as the other two suites write them: what needs proving is
// that the accepted words reach the screen.
//
// Two seams keep these tests out of the player's own things. `-mxq-store-name`
// gives every launch a store of its own, as it does everywhere else, and
// `-mxq-defaults-suite` gives one a preferences database of its own — because a
// test that clicks a switch writes a real preference, and the player's own
// preferences are no more a test fixture than the player's own games are. A state
// a test only needs to *read* is named on the command line instead: the argument
// domain is searched ahead of everything, so `-deleteConfirmation.enabled 0` is
// the app's answer for that launch and is written nowhere at all.

import AppKit
import XCTest

@MainActor
final class SettingsScreenUITests: XCTestCase {

    /// Three games, filed in this order, for the deletion tests: the same corpus
    /// HistoryScreenUITests files, so a row deleted here is a row that suite
    /// would recognise.
    private static let threeGames = [
        "b1b3,b7b6,b3d3",
        "b1b2,b7b6,b2b1,b6b7,b1b2,b7b6,b2b1,b6b7",
        "b1b2,b7b6,b2b1,b6b7,b1b3,b7b6,b3d3",
    ].joined(separator: ";")

    /// A language to run the interface in, and the strings docs/copy.md accepts
    /// for it. Every string in Settings is here, which is the whole screen.
    private struct Language {
        let code: String
        let short: String

        let settings: String
        let boardSection: String
        let symbols, hanzi, icons: String
        let notation, traditional, wxf: String
        let sound, haptics: String
        let confirmDelete, confirmDeleteFooter: String
        /// What a deletion asks, when it asks.
        let deleteTitle, delete, cancel: String
        /// The oldest of the three filed games — the one the deletion tests
        /// delete, and the row whose disappearance is what they assert.
        let oldestRow: String

        static let chinese = Language(
            code: "zh-Hans", short: "zh",
            settings: "设置",
            boardSection: "棋盘",
            symbols: "棋子符号", hanzi: "汉字", icons: "图标",
            notation: "记谱法", traditional: "中文", wxf: "WXF",
            sound: "声音", haptics: "触感",
            confirmDelete: "删除前确认",
            confirmDeleteFooter: "关闭后，删除立即执行。删除无法撤销。",
            deleteTitle: "删除这盘棋？", delete: "删除", cancel: "取消",
            oldestRow: "自由对弈 · 红方获胜 · 将死 · 3 步")

        static let english = Language(
            code: "en", short: "en",
            settings: "Settings",
            boardSection: "Board",
            symbols: "Piece Symbols", hanzi: "Chinese Characters", icons: "Icons",
            notation: "Notation", traditional: "Chinese", wxf: "WXF",
            sound: "Sound", haptics: "Haptics",
            confirmDelete: "Confirm Before Deleting",
            confirmDeleteFooter: "When off, deletion happens immediately. A deletion cannot be undone.",
            deleteTitle: "Delete this game?", delete: "Delete", cancel: "Cancel",
            oldestRow: "Free Play · Red Wins · Checkmate · 3 moves")
    }

    /// A name for a store nobody keeps, and a name for a preferences database
    /// nobody keeps. Both resolve inside the app's own container, so the runner
    /// never has to reach into it and the system owns reclaiming them.
    private func scratchName(_ what: String) -> String {
        "mxq-uitest-\(what)-" + UUID().uuidString
    }

    private func launch(history: String? = nil,
                        in language: Language = .chinese,
                        window: String = "900x600",
                        darkAppearance: Bool = false,
                        preferences: [String: String] = [:],
                        defaultsSuite: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language.code))"]
        app.launchArguments += ["-mxq-store-name", scratchName("store")]
        app.launchArguments += ["-mxq-window", window]
        if darkAppearance { app.launchArguments += ["-mxq-appearance", "dark"] }
        if let history { app.launchArguments += ["-mxq-history", history] }
        if let defaultsSuite { app.launchArguments += ["-mxq-defaults-suite", defaultsSuite] }
        // Read-only preference states, named in the argument domain rather than
        // written anywhere.
        for (key, value) in preferences.sorted(by: { $0.key < $1.key }) {
            app.launchArguments += ["-\(key)", value]
        }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        // The board settles the launch: the seeding runs before it, so a board on
        // screen means every seeded game has been filed.
        XCTAssertTrue(app.windows.firstMatch.descendants(matching: .any)["point-d1"]
            .waitForExistence(timeout: 15))
        return app
    }

    /// The navigation's destinations, by position: Play, History, Settings. A
    /// position rather than a label, because the label is copy and these tests
    /// run in both languages.
    private func destination(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.windows.firstMatch.outlines.element(boundBy: 0).cells.element(boundBy: index)
    }

    private func openSettings(_ app: XCUIApplication, in language: Language = .chinese) {
        destination(app, 2).click()
        XCTAssertTrue(app.staticTexts[language.boardSection].waitForExistence(timeout: 10),
                      "the third destination should be Settings")
    }

    private func openHistory(_ app: XCUIApplication) {
        destination(app, 1).click()
    }

    private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)[identifier]
    }

    private func row(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.windows.firstMatch.buttons["history-row-\(index)"]
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Deletes a row through its context menu — the pointer equivalent of the
    /// swipe's Delete, and the same call the complete swipe invokes, since every
    /// route to a deletion goes through one place in the screen. Retried, and
    /// given a beat afterwards, for the window-server reasons
    /// HistoryScreenUITests documents.
    ///
    /// **The last row is the one to delete.** With the confirmation off there is
    /// no sheet over the list afterwards, and the menu item sits above the rows
    /// below the one it belongs to: deleting from the middle leaves the pointer
    /// over a row that has just moved under it, and a stray event there opens a
    /// replay instead of doing nothing. Deleting the last row leaves the pointer
    /// over empty list.
    private func invokeDelete(onRow index: Int, in app: XCUIApplication,
                              _ language: Language) {
        let row = row(app, index)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let item = app.menus["history-row-\(index)"].menuItems[language.delete]
        for _ in 0..<3 {
            row.rightClick()
            if item.waitForExistence(timeout: 3) {
                item.click()
                // The menu dismisses and the list re-lays out; the next
                // interaction has to address the list rather than a menu on its
                // way out.
                Thread.sleep(forTimeInterval: 0.5)
                return
            }
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTFail("the row's context menu should offer \(language.delete)")
    }

    // MARK: - The screen

    /// The five controls the design fixes, in the three groups it fixes them in,
    /// each showing the accepted default. Nothing is clicked: this is the screen
    /// a first launch opens on.
    func testTheSettingsTabOffersTheFiveAcceptedControls() {
        let app = launch()
        let language = Language.chinese
        openSettings(app, in: language)

        // The one group with a header, and the two choices in it.
        XCTAssertTrue(app.staticTexts[language.boardSection].exists)
        XCTAssertTrue(app.staticTexts[language.symbols].exists,
                      "the symbols row should be labelled 棋子符号")
        XCTAssertTrue(app.staticTexts[language.notation].exists,
                      "and the notation row 记谱法")

        let symbols = control(app, "settings-symbols")
        let notation = control(app, "settings-notation")
        XCTAssertTrue(symbols.exists)
        XCTAssertTrue(notation.exists)
        XCTAssertEqual(symbols.value as? String, language.hanzi,
                       "汉字 is the accepted default — it reads \(String(describing: symbols.value))")
        XCTAssertEqual(notation.value as? String, language.traditional,
                       "and 中文 is — it reads \(String(describing: notation.value))")

        // The two feedback switches, on where nobody has said otherwise. A row's
        // label is a text of its own beside the switch rather than the switch's
        // own label, so the words and the state are read off two elements.
        for (identifier, label) in [("settings-sound", language.sound),
                                    ("settings-haptics", language.haptics)] {
            let control = control(app, identifier)
            XCTAssertTrue(control.exists, "\(identifier) should be on the screen")
            XCTAssertTrue(app.staticTexts[label].exists, "\(identifier) should read \(label)")
            XCTAssertEqual(control.value as? Int, 1, "\(identifier) defaults on")
        }

        // And the one with a footer.
        let confirm = control(app, "settings-confirm-delete")
        XCTAssertTrue(confirm.exists)
        XCTAssertTrue(app.staticTexts[language.confirmDelete].exists)
        XCTAssertEqual(confirm.value as? Int, 1, "删除前确认 defaults on")
        XCTAssertTrue(app.staticTexts[language.confirmDeleteFooter].exists,
                      "the one load-bearing footer says what turning it off costs")

        // No interface-language control: the operating system owns the language.
        XCTAssertFalse(app.staticTexts["语言"].exists)
        XCTAssertFalse(app.staticTexts["Language"].exists)
        attach(app, named: "40-the-settings-screen")
    }

    /// Everything on the screen still fits — and is still hittable — at the
    /// accepted minimum window.
    func testTheScreenFitsTheMinimumWindow() {
        let app = launch(window: "760x492")
        let language = Language.chinese
        openSettings(app, in: language)

        let window = app.windows.firstMatch.frame
        XCTAssertEqual(window.size, CGSize(width: 760, height: 492),
                       "the accepted minimum window")
        for identifier in ["settings-symbols", "settings-notation", "settings-sound",
                           "settings-haptics", "settings-confirm-delete",
                           "settings-confirm-delete-footer"] {
            let element = control(app, identifier)
            XCTAssertTrue(element.exists, "\(identifier) should be there at the minimum")
            XCTAssertTrue(window.contains(element.frame),
                          "\(identifier) should sit inside the minimum window, not past it")
            print("SETTINGS-EVIDENCE minimum-window \(identifier) frame=\(element.frame)")
        }
        attach(app, named: "41-the-settings-screen-at-the-minimum-window")
    }

    // MARK: - What a switch does

    /// The switch, clicked in the real screen, reaching the flow it governs
    /// inside the same launch. Nothing is injected: the click is the only thing
    /// that writes, and the deletion afterwards is what reads.
    func testTurningTheConfirmationOffInSettingsMakesADeletionImmediate() {
        let language = Language.chinese
        let app = launch(history: Self.threeGames, in: language,
                         defaultsSuite: scratchName("defaults"))
        openSettings(app, in: language)

        let confirm = control(app, "settings-confirm-delete")
        XCTAssertEqual(confirm.value as? Int, 1, "it starts on")
        confirm.click()
        XCTAssertEqual(confirm.value as? Int, 0, "and the click turns it off")
        attach(app, named: "42-the-confirmation-switched-off")

        openHistory(app)
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: 10), "three games are filed")
        invokeDelete(onRow: 2, in: app, language)

        // Gone, with nothing asked. The absence of the question is asserted by
        // the words it would have used: the window carries containers a sheet
        // query can match that have nothing to do with an alert.
        XCTAssertFalse(app.staticTexts[language.deleteTitle].waitForExistence(timeout: 2),
                       "with 删除前确认 off, a deletion asks nothing")
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, 2).exists, "two games are left")
        XCTAssertFalse(row(app, 0).label.contains(language.oldestRow))
        XCTAssertFalse(row(app, 1).label.contains(language.oldestRow),
                       "and the one deleted is the one that is gone")
        attach(app, named: "43-the-list-after-an-immediate-deletion")

        // And the switch is still off when the screen is opened again: it was
        // written where it is read from, not held in the view that drew it.
        openSettings(app, in: language)
        XCTAssertEqual(control(app, "settings-confirm-delete").value as? Int, 0)
    }

    /// The same deletion with the preference named off on the command line, which
    /// is the state without the click: the flow honours the key rather than the
    /// screen.
    func testAConfirmationNamedOffDeletesImmediately() {
        let language = Language.chinese
        let app = launch(history: Self.threeGames, in: language,
                         preferences: ["deleteConfirmation.enabled": "0"])
        openHistory(app)
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: 10), "three games are filed")

        invokeDelete(onRow: 2, in: app, language)
        XCTAssertFalse(app.staticTexts[language.deleteTitle].waitForExistence(timeout: 2))
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, 2).exists, "two games are left")
        XCTAssertFalse(row(app, 1).label.contains(language.oldestRow),
                       "and the one deleted is the one that is gone")

        // The screen agrees with the flow about what the key says.
        openSettings(app, in: language)
        XCTAssertEqual(control(app, "settings-confirm-delete").value as? Int, 0)
    }

    /// And named on, which is what every other deletion test relies on being the
    /// default: the gate is a gate rather than an inversion.
    func testAConfirmationNamedOnStillAsks() {
        let language = Language.chinese
        let app = launch(history: Self.threeGames, in: language,
                         preferences: ["deleteConfirmation.enabled": "1"])
        openHistory(app)
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: 10), "three games are filed")

        invokeDelete(onRow: 2, in: app, language)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "it asks")
        XCTAssertTrue(app.staticTexts[language.deleteTitle].exists)
        sheet.buttons[language.cancel].click()
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: 5),
                      "and cancelling leaves all three games")
    }

    /// A choice whose consumer is not built yet still has to be stored, because
    /// the key is the interface between this screen and the rendering that will
    /// read it. What can be asserted from here is the whole of that: the choice
    /// is offered, taking it changes what the screen shows, and it is still taken
    /// when the screen is opened again.
    func testAChoiceIsKeptWhereItsConsumerWillReadIt() {
        let language = Language.chinese
        let app = launch(in: language, defaultsSuite: scratchName("defaults"))
        openSettings(app, in: language)

        let notation = control(app, "settings-notation")
        XCTAssertEqual(notation.value as? String, language.traditional)
        notation.click()
        app.menuItems[language.wxf].click()
        XCTAssertEqual(notation.value as? String, language.wxf,
                       "WXF is what was chosen")

        let symbols = control(app, "settings-symbols")
        symbols.click()
        app.menuItems[language.icons].click()
        XCTAssertEqual(symbols.value as? String, language.icons)
        attach(app, named: "44-the-board-choices-taken")

        // Away and back, which rebuilds the screen: what it shows now comes from
        // the preferences database rather than from the view that wrote it.
        openHistory(app)
        openSettings(app, in: language)
        XCTAssertEqual(control(app, "settings-notation").value as? String, language.wxf)
        XCTAssertEqual(control(app, "settings-symbols").value as? String, language.icons)
    }

    // MARK: - The two languages

    func testTheSettingsScreenInChinese() {
        photographSettings(in: .chinese)
    }

    func testTheSettingsScreenInEnglish() {
        photographSettings(in: .english)
    }

    /// The screen in one language, in both appearances. Every string on it is
    /// read off the running app in the language it was launched in, so a frame
    /// and an assertion are about the same words.
    private func photographSettings(in language: Language) {
        for dark in [false, true] {
            let app = launch(in: language, darkAppearance: dark)
            openSettings(app, in: language)

            XCTAssertTrue(app.staticTexts[language.boardSection].exists)
            XCTAssertTrue(app.staticTexts[language.symbols].exists)
            XCTAssertTrue(app.staticTexts[language.notation].exists)
            XCTAssertEqual(control(app, "settings-symbols").value as? String, language.hanzi)
            XCTAssertEqual(control(app, "settings-notation").value as? String,
                           language.traditional)
            XCTAssertTrue(app.staticTexts[language.sound].exists)
            XCTAssertTrue(app.staticTexts[language.haptics].exists)
            XCTAssertTrue(app.staticTexts[language.confirmDelete].exists)
            XCTAssertTrue(app.staticTexts[language.confirmDeleteFooter].exists)
            // The destination's own name, in the sidebar that leads to it. The
            // name is the cell's text rather than the cell's own label.
            XCTAssertTrue(destination(app, 2).staticTexts[language.settings].exists,
                          "the third sidebar item should read \(language.settings)")

            attach(app, named: "\(language.short)-settings" + (dark ? "-dark" : ""))

            // The two choices open: what a reader sees before deciding, in this
            // language, and the frame that shows both options of a pair.
            control(app, "settings-notation").click()
            XCTAssertTrue(app.menuItems[language.wxf].waitForExistence(timeout: 5))
            XCTAssertTrue(app.menuItems[language.traditional].exists)
            attach(app, named: "\(language.short)-settings-notation-open"
                   + (dark ? "-dark" : ""))
            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
        }
    }
}
