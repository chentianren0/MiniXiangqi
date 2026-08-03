// The Settings destination on a phone.
//
// The screen is the same four groups it is on a Mac, and this file does not
// re-prove the copy the Mac's suite already proves. What it proves is what only
// a phone can say: that the accepted controls arrive as this platform's own
// controls — a picker row that is a button carrying its selection, a switch that
// is a switch — that they answer a finger, that a preference written by one
// survives leaving the screen, and that the whole of it follows the language the
// launch names rather than the one the Simulator was left in.
//
// **触感 is the row this file exists for.** The Mac's suite requires it
// unconditionally and says out loud that an iOS suite cannot copy that: the row
// is absent on a device with no haptic engine, and the contract's own words are
// that the toggle is "unavailable rather than silently ineffective". So nothing
// here asserts the row is present, and nothing asserts it is absent. What is
// asserted is that the screen and the hardware agree — which is the clause
// itself, and which is true on a device of either kind.
//
// Every launch states every preference in the argument domain, per
// LaunchPreferences. A Simulator's preference domains belong to the machine as
// much as a Mac's do: a suite is searched *behind* the application's own domain,
// so naming a scratch suite is not the same as saying what a preference is, and
// the one launch here that wants to *write* a preference leaves that one key to
// the domain so the tap can be read back.

#if os(iOS)

import CoreHaptics
import XCTest

@MainActor
final class PhoneSettingsUITests: XCTestCase {

    /// A language to run the interface in, and the strings docs/copy.md accepts
    /// for it. Every string on the Settings screen is here, which is the whole
    /// screen — 触感 included, for the device that offers it.
    private struct Language {
        let code: String
        let short: String

        let settings: String
        let boardSection: String
        let symbols, hanzi: String
        let notation, traditional: String
        let sound, haptics: String
        let confirmDelete, confirmDeleteFooter: String
        let defaultsSection, defaultFirstMover, defaultAiLevel: String
        let iMoveFirst, standardLevel, defaultsFooter: String

        static let chinese = Language(
            code: "zh-Hans", short: "zh",
            settings: "设置",
            boardSection: "棋盘",
            symbols: "棋子符号", hanzi: "汉字",
            notation: "记谱法", traditional: "中文",
            sound: "声音", haptics: "触感",
            confirmDelete: "删除前确认",
            confirmDeleteFooter: "关闭后，删除立即执行。删除无法撤销。",
            defaultsSection: "人机对弈默认设置",
            defaultFirstMover: "默认先后手", defaultAiLevel: "默认 AI 等级",
            iMoveFirst: "我先手", standardLevel: "标准",
            defaultsFooter: "这些设置用于开始新的人机对弈，不会改变进行中的对局。")

        static let english = Language(
            code: "en", short: "en",
            settings: "Settings",
            boardSection: "Board",
            symbols: "Piece Symbols", hanzi: "Chinese Characters",
            notation: "Notation", traditional: "Chinese",
            sound: "Sound", haptics: "Haptics",
            confirmDelete: "Confirm Before Deleting",
            confirmDeleteFooter: "When off, deletion happens immediately. A deletion cannot be undone.",
            defaultsSection: "Human versus AI Defaults",
            defaultFirstMover: "Default First Mover", defaultAiLevel: "Default AI Level",
            iMoveFirst: "I Move First", standardLevel: "Standard",
            defaultsFooter: "These settings apply when you start a new Human versus AI game. They don't change a game in progress.")
    }

    /// The preferences database a launch reads and writes, so no test here ever
    /// touches the ones the Simulator was left holding. Two files, because they
    /// want opposite things: the reading tests want one nothing has written, and
    /// the test about *writing* a preference has to write one. Fixed names
    /// rather than one per launch — a suite is a plist in the app's container
    /// and nothing reclaims it.
    private enum Defaults: String {
        case untouched = "mxq-uitests-phone-settings"
        case written = "mxq-uitests-phone-settings-written"
    }

    private func scratchStoreName() -> String {
        "mxq-uitest-store-" + UUID().uuidString
    }

    private func launch(in language: Language = .chinese,
                        writing written: Set<String> = [],
                        defaults: Defaults = .untouched) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language.code))"]
        app.launchArguments += ["-mxq-store-name", scratchStoreName()]
        app.launchArguments += ["-mxq-defaults-suite", defaults.rawValue]
        app.launchArguments += ["-mxq-appearance", "light"]
        app.launchArguments += LaunchPreferences.arguments(leavingToTheDomain: written)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                      "the app should reach the foreground")
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 30),
                      "the Play home settling is what says the launch has finished")
        return app
    }

    // MARK: - Addressing the screen

    private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// The navigation's destinations, by position: Play, History, Settings. A
    /// position rather than a name, because the name is copy and this file runs
    /// in both languages.
    private func destination(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.tabBars.firstMatch.buttons.element(boundBy: index)
    }

    private func openSettings(_ app: XCUIApplication, _ language: Language) {
        destination(app, 2).tap()
        XCTAssertTrue(app.staticTexts[language.boardSection].waitForExistence(timeout: 20),
                      "the third destination should be Settings")
    }

    /// What a picker row is showing.
    ///
    /// On this platform a `Picker` in a `Form` is a button whose accessibility
    /// label is the row's title and its selection joined — 棋子符号、汉字 — with
    /// the selection also standing as a text of its own inside it. The selection
    /// is what a test is after, so the inner text is what is read; the whole
    /// label goes into the failure message, where it can be seen.
    private func selection(of identifier: String, in app: XCUIApplication) -> String {
        let row = control(app, identifier)
        guard row.exists else { return "" }
        let inner = row.staticTexts.element(boundBy: 0)
        return inner.exists ? inner.label : row.label
    }

    /// Whether a switch is on. The platform hands a switch's state over as a
    /// string on one platform and a number on another, and a test that guessed
    /// which would be reading nil on the other.
    private func isOn(_ element: XCUIElement) -> Bool {
        if let text = element.value as? String { return text == "1" || text == "true" }
        if let number = element.value as? Int { return number == 1 }
        if let flag = element.value as? Bool { return flag }
        return false
    }

    /// Flips a switch with a finger. The row is one element spanning the whole
    /// width with the switch itself inside it at the trailing edge, so a tap at
    /// the row's centre would land on the label rather than on the control.
    private func toggle(_ identifier: String, in app: XCUIApplication) {
        let row = control(app, identifier)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(identifier) should be on the screen")
        let inner = row.switches.element(boundBy: 0)
        (inner.exists ? inner : row).tap()
    }

    /// Waits for a switch to read a state. A switch answers a touch with a
    /// movement, and a value read the instant after the tap is a value read
    /// mid-slide.
    private func wait(for identifier: String, toBe on: Bool,
                      in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isOn(control(app, identifier)) == on { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The screen

    func testTheSettingsScreenOnAPhone() {
        photographSettings(in: .chinese)
    }

    /// The same screen with the language named on the command line, which is the
    /// whole of how the app's language is decided: it has no control of its own,
    /// and the argument domain is what a hermetic launch says it in. Running the
    /// screen in both languages is also what keeps the notation reading
    /// comparable across them — `notation.style` follows the interface language
    /// now, and every launch here names it, so 中文 is what both should show.
    func testTheSettingsScreenFollowsTheLanguageTheLaunchNames() {
        photographSettings(in: .english)
    }

    private func photographSettings(in language: Language) {
        let app = launch(in: language)
        openSettings(app, language)

        // The board group, and the two choices in it at their accepted defaults.
        XCTAssertTrue(app.staticTexts[language.boardSection].exists)
        XCTAssertTrue(app.staticTexts[language.symbols].exists,
                      "the symbols row should be labelled \(language.symbols)")
        XCTAssertTrue(app.staticTexts[language.notation].exists,
                      "and the notation row \(language.notation)")
        XCTAssertEqual(selection(of: "settings-symbols", in: app), language.hanzi,
                       "\(language.hanzi) is the accepted default — the row reads "
                       + control(app, "settings-symbols").label)
        XCTAssertEqual(selection(of: "settings-notation", in: app), language.traditional,
                       "and the launch states \(language.traditional) — the row reads "
                       + control(app, "settings-notation").label)

        // The human-versus-AI defaults, headed and footed.
        XCTAssertTrue(app.staticTexts[language.defaultsSection].exists)
        XCTAssertTrue(app.staticTexts[language.defaultFirstMover].exists)
        XCTAssertTrue(app.staticTexts[language.defaultAiLevel].exists)
        XCTAssertEqual(selection(of: "settings-first-mover", in: app), language.iMoveFirst)
        XCTAssertEqual(selection(of: "settings-ai-level", in: app), language.standardLevel)
        XCTAssertTrue(app.staticTexts[language.defaultsFooter].exists,
                      "with the accepted footer under the pair")

        // 声音 is on this screen on every device, whatever the hardware says
        // about the row beside it.
        let sound = control(app, "settings-sound")
        XCTAssertTrue(sound.exists, "settings-sound should be on the screen")
        XCTAssertTrue(app.staticTexts[language.sound].exists,
                      "and should read \(language.sound)")
        XCTAssertTrue(isOn(sound), "声音 defaults on")

        // And the one with a footer.
        let confirm = control(app, "settings-confirm-delete")
        XCTAssertTrue(confirm.exists)
        XCTAssertTrue(app.staticTexts[language.confirmDelete].exists)
        XCTAssertTrue(isOn(confirm), "删除前确认 defaults on")
        XCTAssertTrue(app.staticTexts[language.confirmDeleteFooter].exists,
                      "the one load-bearing footer says what turning it off costs")

        // No interface-language control: the operating system owns the language.
        XCTAssertFalse(app.staticTexts["语言"].exists)
        XCTAssertFalse(app.staticTexts["Language"].exists)

        // The destination's own name, on the tab that leads to it.
        XCTAssertEqual(destination(app, 2).label, language.settings)

        attach(app, named: "\(language.short)-phone-settings")
    }

    // MARK: - The row the hardware decides

    /// docs/interaction-design.md § Sound and haptics: "Haptics are available
    /// only where the hardware provides them; on a device without them the
    /// toggle is unavailable rather than silently ineffective."
    ///
    /// **Both outcomes are legal, so neither is asserted.** What is asserted is
    /// that the screen and the hardware say the same thing. The hardware answer
    /// is read here from `CHHapticEngine.capabilitiesForHardware()`, which is
    /// the same public question `Haptics.hardwareReportsHaptics` asks and the
    /// same device it asks it of — the runner and the app are two processes on
    /// one machine. That the app's own `Haptics.isOffered` equals that answer is
    /// pinned in-process by `HapticsTests`, which can `@testable import` what a
    /// UI-test bundle cannot; between the two, the row on this screen is tied to
    /// the app's own decision rather than to a guess made here.
    ///
    /// On a Simulator the answer is generally no engine and therefore no row,
    /// which is exactly the case a Mac run can never reach — the Mac's own
    /// suite requires the row unconditionally, because there the question cannot
    /// be asked at all and the accepted answer is to offer it.
    func testTheHapticsRowFollowsTheHardwareRatherThanAnAssumption() {
        let offered = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        let language = Language.chinese
        let app = launch(in: language)
        openSettings(app, language)

        let row = control(app, "settings-haptics")
        // The row's absence has to be waited *out* rather than read at once: an
        // element that is not there yet and an element that will never be there
        // look the same to a query taken too early. The 声音 row above it is on
        // the screen either way, so its arrival is what says the group is drawn.
        XCTAssertTrue(control(app, "settings-sound").waitForExistence(timeout: 20))

        XCTAssertEqual(row.exists, offered,
                       offered
                       ? "this device reports a haptic engine, so 触感 should be offered"
                       : "this device reports no haptic engine, so 触感 should be absent "
                         + "rather than present and dead")
        XCTAssertEqual(app.staticTexts[language.haptics].exists, offered,
                       "and the words follow the row")

        if offered {
            XCTAssertTrue(isOn(row), "触感 defaults on where it is offered")
        } else {
            // The group survives losing a row: it has no header to be left
            // stranded, and 声音 stands alone without meaning anything different.
            XCTAssertTrue(isOn(control(app, "settings-sound")),
                          "声音 is unchanged by the row beside it not being there")
            XCTAssertTrue(control(app, "settings-confirm-delete").exists,
                          "and the group below it is where it was")
        }
        print("PHONE-EVIDENCE haptics-hardware=\(offered) row-present=\(row.exists)")
        attach(app, named: "phone-settings-haptics-row")
    }

    // MARK: - What a tap writes

    /// A switch flipped with a finger is written where it is read from, not held
    /// in the view that drew it: leaving the screen and coming back rebuilds it
    /// from the preferences database, and the answer has to survive the trip.
    ///
    /// No preference this test is about is named on the command line — a named
    /// key would outrank the tap — so it is written not to depend on the state
    /// it starts from.
    func testASwitchFlippedWithAFingerSurvivesLeavingTheScreen() {
        let language = Language.chinese
        let app = launch(in: language,
                         writing: ["deleteConfirmation.enabled"], defaults: .written)
        openSettings(app, language)

        // The written suite is the same file every run, so it opens holding
        // whatever the last run left in it. What this test is about is the
        // transition, so the switch is put on first if it is not, and the flip
        // that turns it off is always a flip.
        XCTAssertTrue(control(app, "settings-confirm-delete").waitForExistence(timeout: 10))
        if !isOn(control(app, "settings-confirm-delete")) {
            toggle("settings-confirm-delete", in: app)
        }
        XCTAssertTrue(wait(for: "settings-confirm-delete", toBe: true, in: app),
                      "on, whether it began there or was put back")

        toggle("settings-confirm-delete", in: app)
        XCTAssertTrue(wait(for: "settings-confirm-delete", toBe: false, in: app),
                      "and the tap turns it off")
        attach(app, named: "phone-settings-the-confirmation-switched-off")

        // Away and back, which tears the screen down and rebuilds it.
        destination(app, 0).tap()
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 20))
        openSettings(app, language)
        XCTAssertTrue(control(app, "settings-confirm-delete").waitForExistence(timeout: 10))
        XCTAssertFalse(isOn(control(app, "settings-confirm-delete")),
                       "the tap reached the preferences database rather than the view")

        // Left on the accepted default, so this suite's one file is not a
        // growing pile of a previous run's decisions. The put-back above makes
        // this a courtesy rather than a dependency.
        toggle("settings-confirm-delete", in: app)
        XCTAssertTrue(wait(for: "settings-confirm-delete", toBe: true, in: app))
    }
}

#endif  // os(iOS)
