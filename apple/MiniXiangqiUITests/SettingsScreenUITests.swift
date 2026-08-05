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
final class SettingsScreenUITests: XCTestCase {

    /// Three games, filed in this order, for the deletion tests: the same corpus
    /// HistoryScreenUITests files, so a row deleted here is a row that suite
    /// would recognise.
    private static let threeGames = [
        "minixiangqi:b1b3,b7b6,b3d3",
        "minixiangqi:b1b2,b7b6,b2b1,b6b7,b1b2,b7b6,b2b1,b6b7",
        "minixiangqi:b1b2,b7b6,b2b1,b6b7,b1b3,b7b6,b3d3",
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
        /// The human-versus-AI defaults group: its header, its two rows, their
        /// accepted new-install values, and the footer that says what they are
        /// for and what they deliberately are not.
        let defaultsSection, defaultFirstMover, defaultAiLevel: String
        let iMoveFirst, standardLevel, defaultsFooter: String
        /// The About row at the foot of the screen, and the page it opens: the
        /// three facts about this build, the licence and its statement, and the
        /// source the licence is about.
        let about, name, version, build: String
        let license, licenseStatement, source: String
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
            defaultsSection: "人机对弈默认设置",
            defaultFirstMover: "默认先后手", defaultAiLevel: "默认 AI 等级",
            iMoveFirst: "我先手", standardLevel: "标准",
            defaultsFooter: "这些设置用于开始新的人机对弈，不会改变进行中的对局。",
            about: "关于", name: "名称", version: "版本", build: "构建版本",
            license: "许可证",
            licenseStatement: "Mini Xiangqi 是自由软件，依据 GNU General Public License v3 发布。",
            source: "源代码",
            deleteTitle: "删除这盘棋？", delete: "删除", cancel: "取消",
            oldestRow: "迷你象棋 · 自由对弈 · 红方获胜 · 将死 · 3 步")

        static let english = Language(
            code: "en", short: "en",
            settings: "Settings",
            boardSection: "Board",
            symbols: "Piece Symbols", hanzi: "Chinese Characters", icons: "Icons",
            notation: "Notation", traditional: "Chinese", wxf: "WXF",
            sound: "Sound", haptics: "Haptics",
            confirmDelete: "Confirm Before Deleting",
            confirmDeleteFooter: "When off, deletion happens immediately. A deletion cannot be undone.",
            defaultsSection: "Human versus AI Defaults",
            defaultFirstMover: "Default First Mover", defaultAiLevel: "Default AI Level",
            iMoveFirst: "I Move First", standardLevel: "Standard",
            defaultsFooter: "These settings apply when you start a new Human versus AI game. They don't change a game in progress.",
            about: "About", name: "Name", version: "Version", build: "Build",
            license: "License",
            licenseStatement: "Mini Xiangqi is free software, released under the GNU General Public License v3.",
            source: "Source Code",
            deleteTitle: "Delete this game?", delete: "Delete", cancel: "Cancel",
            oldestRow: "Mini Xiangqi · Free Play · Red Wins · Checkmate · 3 moves")
    }

    /// A name for a store nobody keeps. It resolves inside the app's own
    /// temporary directory, so the runner never has to reach into the container
    /// and the system owns reclaiming it — which is why this one may be unique per
    /// launch and the preferences suite below may not.
    private func scratchStoreName() -> String {
        "mxq-uitest-store-" + UUID().uuidString
    }

    /// The preferences database a launch reads and writes. **Every launch names
    /// one**, so no test in this file ever reads or writes the player's own
    /// preferences: a suite is searched ahead of the app's own domain, so a
    /// machine where the owner has switched 声音 off is not a machine where this
    /// suite goes red, and a click here can never land in the domain the shipping
    /// app keeps.
    ///
    /// The names are fixed rather than unique per launch. A suite is a plist in
    /// the app's container and nothing reclaims it — a UUID per launch would leave
    /// two more files behind on every run, for ever — so each purpose keeps one
    /// file and overwrites it.
    ///
    /// Two purposes, because they want opposite things: the frames and the
    /// default-state assertions want a database nothing has written, and the
    /// tests about *writing* a preference have to write one. No test using
    /// `.untouched` clicks a control, which is what keeps it untouched.
    private enum Defaults: String {
        case untouched = "mxq-uitests-settings-untouched"
        case written = "mxq-uitests-settings-written"
    }

    /// The appearance a frame is taken in, always named rather than inherited:
    /// the machine's own appearance is what a Mac set to switch automatically
    /// changes at sunset, and a screenshot series that let it decide would have a
    /// light half only until the evening.
    private enum Appearance: String { case light, dark }

    private func launch(history: String? = nil,
                        in language: Language = .chinese,
                        window: String = "900x600",
                        appearance: Appearance = .light,
                        preferences: [String: String] = [:],
                        writing written: Set<String> = [],
                        defaults: Defaults = .untouched) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language.code))"]
        app.launchArguments += ["-mxq-store-name", scratchStoreName()]
        app.launchArguments += ["-mxq-window", window]
        app.launchArguments += ["-mxq-appearance", appearance.rawValue]
        app.launchArguments += ["-mxq-defaults-suite", defaults.rawValue]
        if let history { app.launchArguments += ["-mxq-history", history] }
        // Every preference stated in the argument domain: read-only states this
        // launch wants, and the accepted default for every key it does not name.
        // The scratch suite alone is not enough to say what a preference is,
        // because a suite is searched *behind* the application's own domain —
        // which is the operator's, and which one afternoon in Settings is enough
        // to change. The exception is a key this launch is about to write: the
        // click has to be readable afterwards, and a named key would outrank it.
        app.launchArguments += LaunchPreferences.arguments(overriding: preferences,
                                                           leavingToTheDomain: written)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        // The Play destination settling is what says the seeding has finished.
        // With every seeded game filed there is no active game left, so what
        // arrives is the Play home's mode entries rather than a board.
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-human-versus-ai"]
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

    /// The seven controls the design fixes, in the four preference groups it
    /// fixes them in, each showing the accepted default. Nothing is clicked:
    /// this is the screen a first launch opens on.
    func testTheSettingsTabOffersTheSevenAcceptedControls() {
        let app = launch()
        let language = Language.chinese
        openSettings(app, in: language)

        // The board group's own header, and the two choices in it.
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

        // The human-versus-AI defaults, which initialize a future game's setup
        // page and reach no game that already exists — which is what the one
        // other footer on this screen says out loud.
        XCTAssertTrue(app.staticTexts[language.defaultsSection].exists)
        XCTAssertTrue(app.staticTexts[language.defaultFirstMover].exists)
        XCTAssertTrue(app.staticTexts[language.defaultAiLevel].exists)
        let firstMover = control(app, "settings-first-mover")
        let aiLevel = control(app, "settings-ai-level")
        XCTAssertEqual(firstMover.value as? String, language.iMoveFirst,
                       "我先手 is the accepted new-install default — it reads "
                       + String(describing: firstMover.value))
        XCTAssertEqual(aiLevel.value as? String, language.standardLevel,
                       "and 标准 is — it reads \(String(describing: aiLevel.value))")
        XCTAssertTrue(app.staticTexts[language.defaultsFooter].exists,
                      "with the accepted footer under the pair")

        // The two feedback switches, on where nobody has said otherwise. A row's
        // label is a text of its own beside the switch rather than the switch's
        // own label, so the words and the state are read off two elements.
        //
        // **`settings-haptics` is required unconditionally here because this is
        // the macOS suite, where the switch is always offered.** An iOS suite
        // cannot copy this: the row is absent on a device that reports no haptic
        // engine, and whether the Simulator reports one has not been measured —
        // so read `Haptics.isOffered` rather than assuming the row exists.
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

    /// Everything on the screen is still reachable, and nothing is clipped
    /// sideways, at the accepted minimum window.
    ///
    /// **Present and unclipped, not all visible at once.** With the
    /// human-versus-AI defaults and 关于 the screen is five groups, and five
    /// groups do not fit 520 points of window without scrolling. That is what
    /// a `Form` is: the accepted floor is the *play* content's, and a
    /// preference list that scrolls at the smallest window is the platform's
    /// own answer rather than a layout failure. So what this asserts is what a
    /// frame series can assert about a list that extends past the window —
    /// every control is there, none of them is cut off by the window's
    /// *width*, and they read down the screen in the accepted order. How far
    /// past the window the list goes is what the logged frames and the
    /// screenshot are for.
    func testTheScreenFitsTheMinimumWindow() {
        let app = launch(window: "760x520")
        let language = Language.chinese
        openSettings(app, in: language)

        // 760 by 520 is what docs/interaction-design.md accepts as this
        // platform's smallest window, and the window stops there however much
        // smaller a launch asks for.
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(window.size, CGSize(width: 760, height: 520),
                       "the accepted minimum window")
        for identifier in ["settings-symbols", "settings-notation",
                           "settings-first-mover", "settings-ai-level",
                           "settings-defaults-footer",
                           "settings-sound", "settings-haptics",
                           "settings-confirm-delete",
                           "settings-confirm-delete-footer",
                           "settings-about"] {
            let element = control(app, identifier)
            XCTAssertTrue(element.exists, "\(identifier) should be there at the minimum")
            // Horizontally, nothing may be clipped: a control cut off by the
            // window's width is unreadable at any scroll position.
            XCTAssertGreaterThanOrEqual(element.frame.minX, window.minX,
                                        "\(identifier) should not run off the left edge")
            XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX,
                                     "\(identifier) should not run off the right edge")
            print("SETTINGS-EVIDENCE minimum-window \(identifier) frame=\(element.frame)")
        }

        // And they are in the accepted order, top to bottom: the board group,
        // the human-versus-AI defaults, the two feedback switches, the deletion
        // confirmation, and 关于 at the foot of all of them. Order is what a
        // frame series can assert about a list that extends past the window;
        // how far past it goes is what the screenshot and the logged frames
        // are for.
        let order = ["settings-symbols", "settings-notation",
                     "settings-first-mover", "settings-ai-level",
                     "settings-defaults-footer",
                     "settings-sound", "settings-haptics",
                     "settings-confirm-delete", "settings-confirm-delete-footer",
                     "settings-about"]
        let tops = order.map { control(app, $0).frame.minY }
        XCTAssertEqual(tops, tops.sorted(),
                       "the groups should read down the screen in the accepted order")
        attach(app, named: "41-the-settings-screen-at-the-minimum-window")
    }

    // MARK: - 关于

    /// The About page on this platform, where the application also has the
    /// system's own About box in its app menu: the page in Settings is the same
    /// page every Apple platform gets, because what it says — the licence, the
    /// build it identifies, and where the source is — is the same everywhere.
    ///
    /// In the normative language only. The words themselves are proved in both
    /// languages by the mechanical catalog check, and by this suite's own frames
    /// for the screen the row sits at the foot of; what a second launch here
    /// would photograph is the same page in the other one.
    func testTheAboutPageStatesTheLicenceAndTheVersion() {
        let app = launch(window: "900x800")
        let language = Language.chinese
        openSettings(app, in: language)

        // Read off the row rather than looking for a text beside it: at this
        // window the list is taller than the window, and a row below the fold
        // is in the tree while the text drawn inside it is not.
        let row = reveal(app, "settings-about")
        XCTAssertTrue(detail(app, "settings-about").contains(language.about)
                      || app.staticTexts[language.about].exists,
                      "关于 should be at the foot of Settings — the row reads "
                      + detail(app, "settings-about"))
        row.click()

        // The three facts about this build. What each one *is* comes from the
        // bundle and is asserted in the unit suite, which can read it; what is
        // asserted here is that it arrived — an empty row and a right one look
        // the same to everything except a reader.
        XCTAssertTrue(control(app, "about-name").waitForExistence(timeout: 10),
                      "the About page should open")
        for (identifier, label) in [("about-name", language.name),
                                    ("about-version", language.version),
                                    ("about-build", language.build)] {
            XCTAssertTrue(control(app, identifier).exists)
            XCTAssertTrue(app.staticTexts[label].exists, "\(identifier) should read \(label)")
        }
        XCTAssertTrue(detail(app, "about-name").contains("Mini Xiangqi"),
                      "名称 should carry the product name — it reads " + detail(app, "about-name"))
        for identifier in ["about-version", "about-build"] {
            XCTAssertTrue(detail(app, identifier).contains(where: \.isNumber),
                          "\(identifier) should carry a number read from the bundle — it reads "
                          + detail(app, identifier))
        }

        // The licence, the source it is a licence about, and the sentence that
        // says what the two of them mean.
        // Read off the rows themselves rather than looking for a text beside
        // them: a link's title is the link's own label and is not a text of its
        // own, unlike a row whose value sits next to it.
        XCTAssertTrue(detail(app, "about-license").contains(language.license),
                      "the licence row should read \(language.license) — it reads "
                      + detail(app, "about-license"))
        XCTAssertTrue(detail(app, "about-source").contains(language.source),
                      "the source row should read \(language.source) — it reads "
                      + detail(app, "about-source"))
        XCTAssertTrue(app.staticTexts[language.licenseStatement].exists,
                      "the footer should state the licence")
        attach(app, named: "42-the-about-page")

        // And the document behind the row is the licence itself. A licence that
        // fell out of the bundle would leave this page blank, which is the one
        // failure the page cannot report on its own.
        control(app, "about-license").click()
        // Label **or** value: a static text carries its string in one of the two
        // depending on the platform drawing it, and this platform puts a text
        // view's contents in the value.
        let heading = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@",
                        "GNU GENERAL PUBLIC LICENSE", "GNU GENERAL PUBLIC LICENSE")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10),
                      "the licence page should show the GNU General Public License")
        attach(app, named: "43-the-licence")
    }

    /// Brings a row within reach and hands it back: a `Form` taller than the
    /// window leaves its last group below the fold, and a click on something
    /// that is not hittable lands somewhere else.
    ///
    /// **The list scrolled is the one the row is in.** A `NavigationSplitView`
    /// puts a scroll view on each side of itself, and the window's first is as
    /// likely to be the sidebar's as the detail column's — scrolling that one
    /// moves the destination list while the row stays exactly where it was, six
    /// times over, and the click afterwards lands on whatever is there instead.
    private func reveal(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let element = control(app, identifier)
        XCTAssertTrue(element.waitForExistence(timeout: 10),
                      "\(identifier) should be on the screen")
        let list = app.windows.firstMatch.scrollViews
            .containing(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
        var scrolls = 0
        while !element.isHittable && list.exists && scrolls < 6 {
            list.scroll(byDeltaX: 0, deltaY: -80)
            scrolls += 1
        }
        return element
    }

    /// Everything a row says, in one string: its own label, its value, and the
    /// texts inside it. A row of a label and a value is one element in one
    /// presentation and a container of two texts in another, and a test that
    /// picked one of those would be reading nil in the other.
    private func detail(_ app: XCUIApplication, _ identifier: String) -> String {
        let row = control(app, identifier)
        guard row.exists else { return "" }
        var parts = [row.label, String(describing: row.value ?? "")]
        let texts = row.staticTexts
        for index in 0..<texts.count { parts.append(texts.element(boundBy: index).label) }
        return parts.joined(separator: " ")
    }

    // MARK: - What a switch does

    /// The switch, clicked in the real screen, reaching the flow it governs
    /// inside the same launch. No preference is named on the command line: the
    /// click is the only thing that writes, and the deletion afterwards is what
    /// reads.
    func testTurningTheConfirmationOffInSettingsMakesADeletionImmediate() {
        let language = Language.chinese
        let app = launch(history: Self.threeGames, in: language,
                         writing: ["deleteConfirmation.enabled"], defaults: .written)
        openSettings(app, in: language)

        // The written suite is the same file every run, so it opens holding
        // whatever the last run left in it. What this test is about is the
        // transition, not the state it starts from, so the switch is put on first
        // if it is not — and the click that turns it off is always a click.
        let confirm = control(app, "settings-confirm-delete")
        if confirm.value as? Int == 0 { confirm.click() }
        XCTAssertEqual(confirm.value as? Int, 1, "on, whether it began there or was put back")
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
        let reopened = control(app, "settings-confirm-delete")
        XCTAssertEqual(reopened.value as? Int, 0)

        // Left as the accepted default, so the suite's one file is not a growing
        // pile of a previous run's decisions. The put-back above makes this a
        // courtesy rather than a dependency.
        reopened.click()
        XCTAssertEqual(reopened.value as? Int, 1)
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
        let app = launch(in: language,
                         writing: ["notation.style", "pieces.symbols"], defaults: .written)
        openSettings(app, in: language)

        // Nothing is assumed about what the pickers show on arrival: what this
        // launch does not name is whatever a persistent domain holds, and the
        // written suite is the same file every run. So each choice is taken to
        // the accepted default first — a click either way, from wherever it
        // began — and the transition after it is the one under test.
        let notation = control(app, "settings-notation")
        choose(language.traditional, from: notation, in: app)
        choose(language.wxf, from: notation, in: app)
        XCTAssertEqual(notation.value as? String, language.wxf,
                       "WXF is what was chosen")

        let symbols = control(app, "settings-symbols")
        choose(language.hanzi, from: symbols, in: app)
        choose(language.icons, from: symbols, in: app)
        XCTAssertEqual(symbols.value as? String, language.icons)
        attach(app, named: "44-the-board-choices-taken")

        // Away and back, which rebuilds the screen: what it shows now comes from
        // the preferences database rather than from the view that wrote it.
        openHistory(app)
        openSettings(app, in: language)
        XCTAssertEqual(control(app, "settings-notation").value as? String, language.wxf)
        XCTAssertEqual(control(app, "settings-symbols").value as? String, language.icons)

        // Left on the accepted defaults, so the suite's one file is not a
        // growing pile of a previous run's decisions. The put-back above makes
        // this a courtesy rather than a dependency.
        choose(language.traditional, from: control(app, "settings-notation"), in: app)
        choose(language.hanzi, from: control(app, "settings-symbols"), in: app)
    }

    /// Takes one named choice from a picker, and says so where a failure can be
    /// read. A picker on this platform opens a menu and the choice is a menu
    /// item in it, which is two interactions rather than one.
    private func choose(_ name: String, from picker: XCUIElement,
                        in app: XCUIApplication) {
        picker.click()
        let item = app.menuItems[name]
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "the picker should offer \(name)")
        item.click()
        XCTAssertEqual(picker.value as? String, name,
                       "the picker should now read \(name)")
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
        for appearance in [Appearance.light, .dark] {
            let dark = appearance == .dark
            let app = launch(in: language, appearance: appearance)
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
            // language, and the frame that shows both options of a pair. Opened
            // and cancelled, never chosen — which is what keeps this launch's
            // suite one nothing has written, and the frames above the accepted
            // defaults on every run.
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

#endif  // os(macOS)
