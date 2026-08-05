// Playing the machine, on the running app.
//
// A UI test cannot script the AI's move — the opponent is a real search over a
// real network, and which move it likes is its own business — so nothing here
// asserts a move. What it asserts is the invariants around one: that a legal
// reply arrived, that the turn came back, that one Undo takes the whole
// exchange back, that the cluster is the accepted human-versus-AI cluster, and
// that the board is turned the way the accepted orientation rule turns it.
//
// The searches run at 快速 — `go movetime 1000` — because a test that waits five
// seconds a move is a test nobody runs. The memory probe is forced to a modest
// figure through the debug affordance so that every prepare allocates a sensible
// Hash rather than the four gigabytes this machine would otherwise offer;
// the arithmetic is the core's either way, and the boundaries themselves are
// pinned by the unit suite where they are cheap.

// **macOS only.** The bundle this file lives in builds for an iOS Simulator too
// now, and this suite does not go there: it drives a window — naming a size,
// reading the frame back, clicking and right-clicking a pointer, typing keys —
// and a window is what iOS has not got. The phone's own evidence is the
// `Phone…UITests` files beside this one, which are a different suite rather than
// a port of this one.
#if os(macOS)

import XCTest

@MainActor
final class HumanVersusAIUITests: XCTestCase {

    /// One gibibyte of "available", which the accepted arithmetic turns into a
    /// 768 MiB Hash: comfortably over the 256 MiB minimum, and small enough that
    /// eight launches do not spend their time in the allocator.
    private static let modestMemory = "1073741824"

    /// Far below the reserve, so the budget lands under the 256 MiB minimum and
    /// the accepted notice is what 开始对局 produces.
    private static let starvedMemory = "1048576"

    private func scratchStoreName() -> String {
        "mxq-uitest-store-" + UUID().uuidString
    }

    private func launch(store: String? = nil,
                        availableMemory: String? = modestMemory,
                        firstMoverDefault: String? = nil,
                        levelDefault: String? = nil,
                        language: String = "zh-Hans",
                        window: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))"]
        app.launchArguments += ["-mxq-store-name", store ?? scratchStoreName()]
        // A scratch preference domain, so a test that writes a default never
        // touches the ones on the machine it runs on — and every preference
        // stated in the argument domain, which is what makes *reading* one
        // hermetic too: a suite is searched behind the application's own domain,
        // so the scratch domain alone does not keep the machine's answers out.
        app.launchArguments += ["-mxq-defaults-suite", "com.chentianren.MiniXiangqi.uitests"]
        var preferences: [String: String] = [:]
        if let firstMoverDefault { preferences["defaults.firstMover"] = firstMoverDefault }
        if let levelDefault { preferences["defaults.aiLevel"] = levelDefault }
        app.launchArguments += LaunchPreferences.arguments(overriding: preferences)
        if let availableMemory {
            app.launchArguments += ["-mxq-available-memory", availableMemory]
        }
        if let window { app.launchArguments += ["-mxq-window", window] }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["point-\(name)"]
    }

    /// What an element says. Addressed by identifier over every descendant
    /// rather than over the static texts alone: the turn status combines its
    /// children, and a combined element that has gained an activity indicator
    /// is no longer typed as a static text.
    private func reading(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = app.windows.firstMatch.descendants(matching: .any)[identifier]
        guard element.exists else { return "" }
        return (element.value as? String) ?? element.label
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Walks the pre-start page: the mode, the two controls, then 开始对局.
    /// Ends when the board is addressable, which is what a created game looks
    /// like from out here.
    ///
    /// The level is **not** picked here. It arrives through the persistent
    /// default the draft is initialized from — which is the real path a level
    /// reaches a game by, and which is a value rather than a popup menu to
    /// drive. The picker itself is exercised where it is the subject, in the
    /// draft test below.
    @discardableResult
    private func startGame(_ app: XCUIApplication,
                           firstMover: String? = "setup.iMoveFirst") -> Bool {
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 15))
        app.buttons["mode-mini-xiangqi-human-versus-ai"].click()
        XCTAssertTrue(app.buttons["setup-start"].waitForExistence(timeout: 5))
        if let firstMover { choose(app, firstMover) }
        app.buttons["setup-start"].click()
        return point(app, "d1").waitForExistence(timeout: 60)
    }

    /// The segmented first-mover control, by the accepted labels.
    private func choose(_ app: XCUIApplication, _ key: String) {
        let labels = ["setup.iMoveFirst": "我先手",
                      "setup.aiMovesFirst": "AI 先手",
                      "setup.random": "随机"]
        app.windows.firstMatch.radioButtons[labels[key]!].click()
    }

    private func chooseLevel(_ app: XCUIApplication, _ key: String) {
        let labels = ["setup.level.fast": "快速",
                      "setup.level.standard": "标准",
                      "setup.level.deep": "深思"]
        let picker = app.windows.firstMatch.descendants(matching: .any)["setup-ai-level"]
        picker.click()
        let item = app.menuItems[labels[key]!]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the level menu should open")
        item.click()
    }

    /// Waits for the turn status to say what it is waiting for.
    private func waitForStatus(_ app: XCUIApplication, containing text: String,
                               timeout: TimeInterval = 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if reading(app, "turn-status").contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    /// Plays one move the way a person does, and waits for the board to answer
    /// the first half of it before making the second.
    ///
    /// The wait is not politeness. A board that has just been built — a created
    /// game, or one rebuilt from the store — answers its first click a frame or
    /// two later than one that has been on screen, and a destination clicked
    /// before the piece was taken up is a click at nothing.
    private func play(_ app: XCUIApplication, from: String, to: String) {
        point(app, from).click()
        XCTAssertTrue(waitForLabel(point(app, from), containing: "已选择"),
                      "the board should take up the piece on \(from) — it reads "
                      + point(app, from).label)
        point(app, to).click()
    }

    /// Waits for an element's label to say something.
    private func waitForLabel(_ element: XCUIElement, containing text: String,
                              timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label.contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    /// Waits for the turn status to stop saying something. The machine having
    /// answered is exactly this: whether it replied with a move or ended the
    /// game with one, the turn stops being its own.
    private func waitForStatusToLeave(_ app: XCUIApplication, _ text: String,
                                      timeout: TimeInterval = 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !reading(app, "turn-status").contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    // MARK: - A game against the machine

    func testTheMachineReplies() {
        // 深思 rather than 快速, alone among these tests. The assertion that the
        // status names the machine while it thinks has to be made while it is
        // thinking, and a one-second search is shorter than the accessibility
        // queries that lead up to the assertion: at 深思 the label stands for
        // five seconds, which no query latency can outrun.
        let app = launch(levelDefault: "deep")
        XCTAssertTrue(startGame(app),
                      "开始对局 should create the game and open the board")
        attach(app, named: "hvai-1-the-opening-position")

        // The accepted cluster: 悔棋, 判和, 认输 and 翻转棋盘 — the fourth is the
        // owner's recommendation of 2026-07-31, and it carries the same label
        // here as it does in Free Play whichever of its two shapes it is in.
        XCTAssertTrue(app.buttons["cluster-undo"].exists)
        XCTAssertTrue(app.buttons["cluster-claim"].exists)
        XCTAssertEqual(app.buttons["cluster-resign"].label, "认输")
        XCTAssertEqual(app.buttons["cluster-flip"].label, "翻转棋盘",
                       "human-versus-AI carries the board-flip control too")

        // 我先手 resolves Red, so Red is at the bottom and the turn is the
        // player's own.
        let strips = app.windows.firstMatch.descendants(matching: .any)
        XCTAssertEqual(strips["file-numerals-red"].label, "七 六 五 四 三 二 一",
                       "the human is Red, so Red is at the bottom")
        XCTAssertTrue(waitForStatus(app, containing: "轮到红方", timeout: 5))
        XCTAssertTrue(waitForStatus(app, containing: "你", timeout: 5),
                      "the controller label names whose turn it is")

        // The player's move. The turn passes to the machine, and its label
        // says so.
        play(app, from: "b1", to: "b4")
        XCTAssertTrue(waitForStatus(app, containing: "轮到黑方"),
                      "the turn should pass to the machine")
        XCTAssertTrue(waitForStatus(app, containing: "AI", timeout: 5),
                      "and the controller label should name it")

        attach(app, named: "hvai-2-the-machine-thinking")

        // That board input is refused while the machine owes a move is asserted
        // in the unit suite instead, against the affordance itself. Racing it
        // here would mean clicking inside a window bounded on one side by a real
        // search and on the other by how long a query into the accessibility
        // tree happens to take, and those two are close enough on a loaded
        // machine to make the test about the machine rather than about the rule.

        // The reply. Which move it is, is the machine's business; that a legal
        // one arrived and the turn came back is the invariant.
        XCTAssertTrue(waitForStatusToLeave(app, "轮到黑方"),
                      "the machine should answer within its own thinking time")
        XCTAssertTrue(waitForStatus(app, containing: "轮到红方", timeout: 5),
                      "and hand the turn back — Black cannot mate in one from here")
        XCTAssertTrue(waitForStatus(app, containing: "你", timeout: 5))
        XCTAssertTrue(app.staticTexts["炮六进三"].exists,
                      "the player's own move is in the list")
        XCTAssertTrue(app.staticTexts["1."].exists, "with the reply beside it in row one")
        attach(app, named: "hvai-3-after-the-reply")

        // One Undo takes back the whole exchange: the reply and the move that
        // invited it, which is the decision cycle the core counts for us.
        app.buttons["cluster-undo"].click()
        XCTAssertTrue(waitForStatus(app, containing: "轮到红方", timeout: 10))
        XCTAssertFalse(app.staticTexts["炮六进三"].exists,
                       "the player's own move went back with the reply")
        XCTAssertFalse(app.staticTexts["1."].exists, "the move list is empty again")
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮",
                       "and the starting position is back")
        attach(app, named: "hvai-4-after-the-cycle-undo")
    }

    /// 认输 with its confirmation, and the record it makes.
    func testResigningRecordsTheLoss() {
        let app = launch()
        XCTAssertTrue(startGame(app))

        app.buttons["cluster-resign"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let lines = sheet.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(lines, ["认输？", "认输后本局将记为你落败。"])
        XCTAssertTrue(sheet.buttons["取消"].exists)
        attach(app, named: "hvai-5-the-resign-confirmation")

        // Cancelling changes nothing.
        sheet.buttons["取消"].click()
        XCTAssertTrue(waitForStatus(app, containing: "轮到红方", timeout: 10))
        XCTAssertTrue(app.buttons["cluster-resign"].isEnabled)

        app.buttons["cluster-resign"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons["认输"].click()

        // Resignation is a terminal commit, so the record exists the moment it
        // returns and the notice reads as the recorded state.
        XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(reading(app, "result-title"), "已记录到历史")
        XCTAssertEqual(reading(app, "result-reason"), "认输")
        XCTAssertTrue(waitForStatus(app, containing: "黑方胜", timeout: 5),
                      "the human was Red, so the loss is Black's win")
        XCTAssertFalse(app.buttons["result-save"].exists,
                       "a resignation was filed by the resigning")
        attach(app, named: "hvai-6-the-recorded-resignation")
    }

    /// AI 先手: the machine opens, and the board is turned so the human's own
    /// side is at the bottom.
    func testTheMachineMovesFirstAndTheBoardTurnsRound() {
        let app = launch(levelDefault: "fast")
        XCTAssertTrue(startGame(app, firstMover: "setup.aiMovesFirst"))

        let strips = app.windows.firstMatch.descendants(matching: .any)
        XCTAssertEqual(strips["file-numerals-black"].label, "7 6 5 4 3 2 1",
                       "the human is Black, so Black is at the bottom")
        attach(app, named: "hvai-7-the-machine-opening")

        XCTAssertTrue(waitForStatus(app, containing: "轮到黑方"),
                      "the machine's opening move should arrive")
        XCTAssertTrue(waitForStatus(app, containing: "你", timeout: 5),
                      "and hand the turn to the player")
        XCTAssertTrue(app.staticTexts["1."].exists, "the opening move is in the list")

        // Its opening move alone cannot be taken back: there is no decision of
        // the player's to return to.
        XCTAssertFalse(app.buttons["cluster-undo"].isEnabled,
                       "the AI's opening move alone cannot be undone")
        attach(app, named: "hvai-8-after-the-machine-opened")
    }

    // MARK: - The four controls, in the panel that has to hold them

    /// The cluster this mode gained a fourth control for, in the panel that has
    /// to hold it, in each language the app speaks.
    ///
    /// **This is the width the placement was decided against, and it is not the
    /// window's.** Side by side, the cluster lives in a 260-point panel flush
    /// with the window's trailing edge and has 228 points inside the panel's
    /// inset — the same 228 at every window size, because the panel does not
    /// grow with the window. Four English labels come to 359 of them, so the row
    /// gives up the trailing word, and where even that will not fit 翻转棋盘
    /// drops to a second row beneath the others. Which of the three
    /// arrangements a language gets is the layout's answer rather than a
    /// promise; what is asserted is the promise — every control inside the
    /// panel's own inset edge, none of it hanging past into the board — and the
    /// frames are what the arrangement is read off.
    ///
    /// The window is a comfortable one deliberately. At the minimum the app
    /// clamps a smaller request up to its own floor *after* the window has been
    /// centred, so the window overhangs the display and a screenshot of it is
    /// cut off at the right — which is exactly the edge this test is about. The
    /// assertion below is measured from the window's trailing edge rather than
    /// from its width, so it says the same thing at either size.
    ///
    /// The words are written out rather than read from the application's own
    /// catalog, and the register itself is verified where it is the subject —
    /// `PlayScreenUITests`, which walks both languages over every surface the
    /// copy lives on. These four are here because a control whose label went
    /// missing would pass an existence check.
    func testTheFourControlsFitThePanelInBothLanguages() {
        let words = [("zh-Hans", "zh", ["cluster-undo": "悔棋", "cluster-claim": "判和",
                                        "cluster-resign": "认输", "cluster-flip": "翻转棋盘"]),
                     ("en", "en", ["cluster-undo": "Undo", "cluster-claim": "Claim Draw",
                                   "cluster-resign": "Resign", "cluster-flip": "Flip Board"])]
        for (code, short, labels) in words {
            let app = launch(levelDefault: "fast", language: code, window: "900x700")
            // 我先手 is the default, so the pre-start page needs no choice made
            // on it — which is what keeps this test out of the segmented
            // control's localized labels.
            XCTAssertTrue(startGame(app, firstMover: nil),
                          "开始对局 should create the game and open the board in \(code)")
            let window = app.windows.firstMatch.frame
            // The panel's own inner edge: 16 points in from the window's
            // trailing edge, which is where the cluster's padding puts it.
            let edge = window.maxX - 16
            for identifier in ["cluster-undo", "cluster-claim", "cluster-resign", "cluster-flip"] {
                let button = app.buttons[identifier]
                XCTAssertTrue(button.exists,
                              "\(identifier) should be on screen in the panel in \(code)")
                XCTAssertLessThanOrEqual(button.frame.maxX, edge + 0.5,
                                         "\(identifier) should end inside the panel's inset, "
                                         + "not past it — it ends at \(button.frame.maxX) "
                                         + "and the inset edge is \(edge)")
                XCTAssertEqual(button.label, labels[identifier],
                               "and carry its own label whatever shape it is drawn in")
                print("CLUSTER-EVIDENCE hvai-\(short) \(identifier) "
                      + "frame=\(button.frame) panel-edge=\(edge)")
            }
            attach(app, named: "hvai-\(short)-panel")
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 20),
                          "the process has to be gone before the next launch asks for it")
        }
    }

    // MARK: - Insufficient memory

    /// The accepted notice, produced on the real screen by forcing the probe
    /// below the minimum. 取消 keeps the page and the draft, and creates
    /// nothing.
    func testInsufficientMemoryKeepsThePageAndTheDraft() {
        let app = launch(availableMemory: Self.starvedMemory)
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 15))
        app.buttons["mode-mini-xiangqi-human-versus-ai"].click()
        XCTAssertTrue(app.buttons["setup-start"].waitForExistence(timeout: 5))
        chooseLevel(app, "setup.level.deep")
        app.buttons["setup-start"].click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20))
        let lines = sheet.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        XCTAssertEqual(lines, ["无法启动 AI 对手",
                               "当前可用内存不足。请尝试关闭一些其他 App，然后重试。"])
        XCTAssertTrue(sheet.buttons["取消"].exists)
        XCTAssertTrue(sheet.buttons["重试"].exists)
        attach(app, named: "hvai-9-the-insufficient-memory-notice")

        sheet.buttons["取消"].click()
        XCTAssertTrue(app.buttons["setup-start"].waitForExistence(timeout: 5),
                      "取消 keeps the page and re-enables 开始对局")
        XCTAssertTrue(app.buttons["setup-start"].isEnabled)
        XCTAssertFalse(point(app, "d1").exists, "and no game was created")
        // The draft is untouched: 深思 is still selected.
        XCTAssertTrue(app.windows.firstMatch.descendants(matching: .any)["setup-ai-level"]
                        .value as? String == "深思",
                      "the draft survives the failure it caused")
        attach(app, named: "hvai-10-the-page-after-cancelling")
    }

    // MARK: - The draft, and the defaults behind it

    /// The controls open on the Settings defaults, and what the page holds is a
    /// draft: leaving discards it, and coming back reads the defaults again.
    func testTheDraftOpensFromTheDefaultsAndIsDiscardedOnLeaving() {
        let app = launch(firstMoverDefault: "ai-first", levelDefault: "fast")
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 15))
        app.buttons["mode-mini-xiangqi-human-versus-ai"].click()
        XCTAssertTrue(app.buttons["setup-start"].waitForExistence(timeout: 5))

        let controls = app.windows.firstMatch.descendants(matching: .any)
        XCTAssertEqual(controls["setup-ai-level"].value as? String, "快速",
                       "the page opens on the persistent default")
        attach(app, named: "hvai-11-the-setup-page")

        // Change the draft, then leave.
        chooseLevel(app, "setup.level.deep")
        XCTAssertEqual(controls["setup-ai-level"].value as? String, "深思")

        let destinations = app.windows.firstMatch.outlines.element(boundBy: 0).cells
        destinations.element(boundBy: 2).click()   // Settings
        XCTAssertTrue(app.staticTexts["人机对弈默认设置"].waitForExistence(timeout: 10),
                      "the defaults group is on the Settings screen")
        // The draft was never written back: both defaults read as they were.
        let settings = app.windows.firstMatch.descendants(matching: .any)
        XCTAssertEqual(settings["settings-ai-level"].value as? String, "快速",
                       "a draft is not a preference: the Settings default is untouched")
        XCTAssertEqual(settings["settings-first-mover"].value as? String, "AI 先手")
        XCTAssertTrue(app.staticTexts["这些设置用于开始新的人机对弈，不会改变进行中的对局。"].exists,
                      "with the accepted footer under it")
        attach(app, named: "hvai-12-the-settings-defaults-group")

        destinations.element(boundBy: 0).click()   // Play
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 10),
                      "leaving the page discards the draft and returns to the Play home")
        app.buttons["mode-mini-xiangqi-human-versus-ai"].click()
        XCTAssertTrue(app.buttons["setup-start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.descendants(matching: .any)["setup-ai-level"]
                        .value as? String, "快速",
                       "and the controls are initialized afresh from the defaults")

        // The first-mover default reached the draft too, which the created
        // game is what proves: nothing on this page was touched, and 开始对局
        // resolves AI 先手 — so the human is Black and the board turns round.
        app.buttons["setup-start"].click()
        XCTAssertTrue(point(app, "d1").waitForExistence(timeout: 60))
        XCTAssertEqual(app.windows.firstMatch.descendants(matching: .any)["file-numerals-black"]
                        .label, "7 6 5 4 3 2 1",
                       "the default resolved AI 先手, so the human is Black at the bottom")
    }

    // MARK: - Resume

    /// An active human-versus-AI game resumes with its own orientation and its
    /// own controls, and the machine picks up a move it still owes.
    func testAnActiveGameResumesWithItsOrientationAndItsOpponent() {
        let store = scratchStoreName()
        var app = launch(store: store, levelDefault: "fast")
        XCTAssertTrue(startGame(app, firstMover: "setup.aiMovesFirst"))
        XCTAssertTrue(waitForStatus(app, containing: "轮到黑方"),
                      "the machine opened, so the turn is the player's")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 20),
                      "the process has to be gone before the next launch asks for it")

        app = launch(store: store, levelDefault: "fast")
        // The launch opens at the home and the card is the way back into the
        // game, which is the whole of what a resumed game is entered by: no
        // pre-start page stands anywhere on this path, and nothing was chosen
        // a second time.
        XCTAssertTrue(app.buttons["home-resume"].waitForExistence(timeout: 20),
                      "the game that was going is on the home the launch opened")
        XCTAssertFalse(app.buttons["setup-start"].exists)
        app.buttons["home-resume"].click()
        XCTAssertTrue(point(app, "d1").waitForExistence(timeout: 20),
                      "and 回到对局 opens the game itself")
        let strips = app.windows.firstMatch.descendants(matching: .any)
        XCTAssertEqual(strips["file-numerals-black"].label, "7 6 5 4 3 2 1",
                       "and resumes with the human's own side at the bottom")
        XCTAssertTrue(app.buttons["cluster-resign"].exists,
                      "with the human-versus-AI cluster")
        XCTAssertTrue(waitForStatus(app, containing: "轮到黑方", timeout: 5))
        XCTAssertTrue(app.staticTexts["1."].exists, "the machine's opening move survived")
        attach(app, named: "hvai-13-the-resumed-game")

        // The orientation the mode chose, and the one the player can ask for
        // over the top of it: 翻转棋盘 turns this board to the machine's side,
        // and turns nothing else. The move that is already recorded is still
        // recorded and the turn is still the same turn — the flip is
        // presentation, here exactly as it is in Free Play.
        app.buttons["cluster-flip"].click()
        XCTAssertTrue(waitForLabel(strips["file-numerals-red"],
                                   containing: "七 六 五 四 三 二 一"),
                      "the flip should turn the board to Red at the bottom — it reads "
                      + strips["file-numerals-red"].label)
        XCTAssertTrue(app.staticTexts["1."].exists, "the record is untouched by a flip")
        XCTAssertTrue(waitForStatus(app, containing: "轮到黑方", timeout: 5),
                      "and so is the turn")
        attach(app, named: "hvai-13a-the-resumed-game-flipped")

        // And back, because a flip is a toggle and two of them are none.
        app.buttons["cluster-flip"].click()
        XCTAssertTrue(waitForLabel(strips["file-numerals-black"],
                                   containing: "7 6 5 4 3 2 1"),
                      "a second flip returns the human's own side to the bottom")

        // It is the same game to play on: the player moves and the machine
        // answers, which means the engine was prepared again when a search was
        // next owed — the whole point of resuming a game that owes one.
        //
        // *Answers*, not *replies with a move that leaves the game running*: the
        // machine is a real search, and a legal answer may end the game. Its
        // answer is the third ply either way, and the third ply is what opens
        // the second numbered row — a fact about the record rather than a frame
        // of the turn status that a poll has to be lucky enough to catch.
        play(app, from: "a6", to: "a5")
        XCTAssertTrue(app.staticTexts["2."].waitForExistence(timeout: 60),
                      "the resumed game's opponent answered, which means the engine "
                      + "was prepared again when a search was next owed")
        attach(app, named: "hvai-14-the-resumed-game-played-on")
    }
}

#endif  // os(macOS)
