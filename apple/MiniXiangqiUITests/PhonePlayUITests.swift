// Playing on a phone: the stacked shape, and a finger.
//
// **This is not the Mac suites ported.** Those drive a window — they name a
// size, read the frame back, and assert what the layout did with it — and a
// window is the one thing iOS has not got. What a phone has instead is the other
// half of docs/interaction-design.md § Layout shapes: the arrangement the
// contract calls **stacked**, chosen by the available space, with the turn
// status above the board, the play controls below it, and the move record
// reached on demand rather than resident. Nothing on a Mac exercises that
// arrangement's own affordances, because on a Mac the panel is almost always
// what fits; nothing on a Mac exercises a tap at all.
//
// So the questions this file asks are the ones only a phone can answer. Is the
// stacked shape what a 402-point phone takes? Does Mini Xiangqi still meet its
// 44-point floor, and does Xiangqi expose 90 actual, disjoint cells at the
// 39-point pitch this phone gives it? Does a tap select a piece and a second tap
// move it? Does the 棋谱 sheet come up over the board and go away again? Does the
// phone hold its portrait layout when the device is turned — the one orientation
// clause that belongs to the phone rather than to the iPad? Does a board screen
// put the destination bar away and a home keep it, which § Navigation asks of
// this presentation and of no other? And does the result flow, which every
// platform shares, actually reach a filed record from here?
//
// What is deliberately **not** here: anything about a window; how a landing
// feels in the hand, which is the owner's device pass and cannot be felt by a
// test process; and any measurement of latency, memory or energy, which is the
// device pass too. A Simulator is the wrong instrument for all three.
//
// Every launch states every preference in the argument domain, per
// LaunchPreferences — the #77 lesson, which is not a macOS lesson: a Simulator's
// preference domains are as much the operator's as a Mac's are, and a suite that
// named none would assert whatever the last run left behind.
//
// The words asserted here are the accepted Simplified Chinese, written out
// rather than read from the application's own catalog: a test that
// reads the file the application reads asserts only that the file is itself.

#if os(iOS)

import XCTest

@MainActor
final class PhonePlayUITests: XCTestCase {

    /// Two plies of an ordinary Free Play game — enough that the move record has
    /// something to show and the board something to have moved.
    private static let openingLine = "minixiangqi:b1b3,b7b6"

    /// The shortest checkmate from the start position.
    private static let mateLine = "minixiangqi:b1b3,b7b6,b3d3"

    /// One gibibyte of "available", which the accepted arithmetic turns into a
    /// 768 MiB Hash: over the 256 MiB minimum, and small enough that a launch
    /// does not spend its time in the allocator. The same figure the Mac's
    /// human-versus-AI suite forces, and for the same reason.
    private static let modestMemory = "1073741824"

    private func scratchStoreName() -> String {
        "mxq-uitest-store-" + UUID().uuidString
    }

    /// One launch, with everything about it stated.
    ///
    /// `-mxq-window` is absent and has to be: it is a macOS affordance, and the
    /// phone's size is the phone's. What is stated instead is everything that
    /// *is* a preference — through `LaunchPreferences`, so this file and the
    /// Mac's read the same table — plus the appearance, which is named here for
    /// the same reason it is named there: a screenshot series that let the
    /// system decide would change halfway through the evening.
    private func launch(replaying line: String? = nil,
                        history: String? = nil,
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
        // Games played and filed before the board opens, so that a test which
        // needs a record to open has one. The same argument the Mac's History
        // suite seeds its library with.
        if let history { app.launchArguments += ["-mxq-history", history] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                      "the app should reach the foreground")
        return app
    }

    // MARK: - Addressing the screen

    /// An element by its identifier, whatever type iOS gave it. Identifiers are
    /// the app's own contract and do not change with the interface language or
    /// with which control SwiftUI reached for; types and labels do both.
    private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        control(app, "point-\(name)")
    }

    /// What an element says.
    ///
    /// **The value has to be tested for emptiness rather than for nil.** A
    /// SwiftUI `Text` hands its string over as the accessibility *value* on
    /// macOS; on iOS it hands it over as the label and leaves the value an empty
    /// string, which is not nil — so the obvious `(value as? String) ?? label`
    /// returns `""` for every text on this platform, and every assertion built
    /// on it compares nothing to something. Measured, not guessed: the first run
    /// of this suite failed eight assertions that way, all of them reading the
    /// empty value of an element whose label was right there.
    private func text(of element: XCUIElement) -> String {
        guard element.exists else { return "" }
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    private func reading(_ app: XCUIApplication, _ identifier: String) -> String {
        text(of: control(app, identifier))
    }

    /// The navigation's destinations, by position: Play, History, Settings.
    ///
    /// At a phone's width the one adaptive container presents as a tab bar
    /// rather than as the sidebar a Mac window gets — which is the compact-width
    /// half of the contract's one-container rule, and the half no Mac run
    /// reaches. Addressed by position rather than by name for the same reason
    /// the Mac's suites address its sidebar by position: the name is copy.
    private func destination(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.tabBars.firstMatch.buttons.element(boundBy: index)
    }

    /// The back control in the navigation bar, which is how a page over the home
    /// is left.
    private func goBack(_ app: XCUIApplication) {
        let control = app.buttons["play-back"]
        XCTAssertTrue(control.waitForExistence(timeout: 5),
                      "a page over the home carries a way back to it")
        control.tap()
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

    /// Waits for an element to go away.
    ///
    /// Something going away has to be waited *out* rather than read once. A
    /// surface being dismissed is animated, and a query taken the instant after
    /// the tap sees the frame it was still in — so an assertion made there is a
    /// race that passes on a fast run and fails on a loaded one.
    private func waitForAbsence(_ element: XCUIElement,
                                timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    /// Waits for the turn status to say — or to stop saying — something.
    private func waitForStatus(_ app: XCUIApplication, containing text: String,
                               timeout: TimeInterval = 60) -> Bool {
        waitForStatus(app, timeout: timeout) { $0.contains(text) }
    }

    private func waitForStatus(_ app: XCUIApplication, timeout: TimeInterval = 60,
                               until satisfied: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if satisfied(reading(app, "turn-status")) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    /// Plays one move the way a person does, and waits for the board to answer
    /// the first tap before making the second. The wait is not politeness: a
    /// board that has just been built answers its first touch a frame or two
    /// later than one that has been on screen, and a destination tapped before
    /// the piece was taken up is a tap at nothing.
    private func play(_ app: XCUIApplication, from: String, to: String) {
        point(app, from).tap()
        XCTAssertTrue(waitForLabel(point(app, from), containing: "已选择"),
                      "the board should take up the piece on \(from) — it reads "
                      + point(app, from).label)
        point(app, to).tap()
    }

    /// Presses a control through the middle of it.
    ///
    /// `XCUIElement.tap()` picks its own point inside an element's frame, and
    /// for the result notice's actions the point it picks does not press them:
    /// measured on this Simulator, `app.buttons["result-save"].tap()` files
    /// nothing and instead dismisses the notice, which is what a tap on the
    /// *board behind it* does. The same press delivered through the element's
    /// own centre files the game and the notice becomes the recorded one, so the
    /// button and the app are both fine and it is the chosen point that is not.
    ///
    /// Those actions are 34 points tall where the board's own points are 50, and
    /// they stand over a live board. Whether a thumb finds them is a question
    /// for the owner's device pass; what a test can do is press where a person
    /// aiming at a button would, which is the middle.
    private func press(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The home, under a tab bar

    /// The phone opens on the Play home, and the three destinations are a bar of
    /// tabs across the bottom rather than a sidebar down the side. The page
    /// itself is the same page the Mac's suite asserts — the ways to play and no
    /// board — and it is asserted again here because "the same page" is the
    /// claim being made about the two platforms.
    func testThePhoneOpensOnThePlayHomeUnderATabBar() {
        let app = launch()

        XCTAssertTrue(app.buttons["mode-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["mode-xiangqi-human-versus-ai"].label, "人机对弈")
        XCTAssertEqual(app.buttons["mode-xiangqi-free-play"].label, "自由对弈")
        XCTAssertEqual(app.buttons["mode-mini-xiangqi-human-versus-ai"].label, "人机对弈")
        XCTAssertEqual(app.buttons["mode-mini-xiangqi-free-play"].label, "自由对弈")

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.exists,
                      "at a phone's width the one container presents as a tab bar")
        XCTAssertEqual(tabs.buttons.count, 3, "Play, History, Settings")
        XCTAssertEqual(destination(app, 0).label, "对局")
        XCTAssertEqual(destination(app, 1).label, "历史")
        XCTAssertEqual(destination(app, 2).label, "设置")
        XCTAssertGreaterThan(tabs.frame.minY, app.frame.midY,
                             "and it stands across the bottom, under the thumb")

        XCTAssertFalse(point(app, "d4").exists, "no board is addressable on the home")
        XCTAssertFalse(control(app, "turn-status").exists, "and nothing about a turn")
        XCTAssertFalse(app.buttons["cluster-undo"].exists, "and no play controls")
        XCTAssertFalse(app.buttons["home-resume"].exists,
                       "with no game there is no way back into one")
        attach(app, named: "phone-01-the-play-home")
    }

    // MARK: - Xiangqi, at a phone's actual pitch

    /// Standard Xiangqi through the complete path that owns its identity: one of
    /// the local ways to play on the Play home — which on a phone now stands
    /// beside a nearby row per game — a pre-start page that still says 象棋, and
    /// only then a created game. The running board is the evidence the model
    /// alone cannot give: all 90 named points are present, every hit frame is the
    /// actual 39-point cell this 402-point phone draws rather than an overlapping
    /// 44-point overlay, and two taps commit an ordinary Xiangqi move.
    func testXiangqiStartsFromItsHomeEntryAsNinetyDisjointTappablePoints() {
        let app = launch()
        XCTAssertTrue(app.buttons["mode-xiangqi-free-play"]
            .waitForExistence(timeout: 30))

        let modeIdentifiers = [
            "mode-xiangqi-human-versus-ai",
            "mode-xiangqi-free-play",
            "mode-mini-xiangqi-human-versus-ai",
            "mode-mini-xiangqi-free-play",
        ]
        for identifier in modeIdentifiers {
            XCTAssertTrue(app.buttons[identifier].exists,
                          "the local ways to play should include \(identifier)")
        }

        app.buttons["mode-xiangqi-free-play"].tap()
        XCTAssertTrue(control(app, "setup-game").waitForExistence(timeout: 10))
        XCTAssertEqual(reading(app, "setup-game"), "象棋",
                       "the selected game should survive the trip into setup")
        XCTAssertEqual(reading(app, "setup-explanation"),
                       "你将控制红黑双方，红方先行。")
        XCTAssertFalse(control(app, "turn-status").exists,
                       "the Xiangqi preview is not a game yet")
        attach(app, named: "phone-xiangqi-01-the-setup-page")

        control(app, "setup-start").tap()
        XCTAssertTrue(point(app, "a10").waitForExistence(timeout: 90),
                      "开始对局 should expose Xiangqi's far corner")
        XCTAssertEqual(app.frame.width, 402, accuracy: 0.5,
                       "phone layout evidence belongs to the named 402-point device")

        let pointElements = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "point-"))
            .allElementsBoundByIndex
        let files = "abcdefghi".map { String($0) }
        let expectedPointIdentifiers = Set(files.flatMap { file in
            (1...10).map { "point-\(file)\($0)" }
        })
        XCTAssertEqual(pointElements.count, 90,
                       "a 9 by 10 board should expose one hit element per point")
        XCTAssertEqual(Set(pointElements.map(\.identifier)), expectedPointIdentifiers,
                       "the point identifiers should cover a1 through i10 exactly")

        XCTAssertEqual(point(app, "a1").label, "a1 红 俥")
        XCTAssertEqual(point(app, "i1").label, "i1 红 俥")
        XCTAssertEqual(point(app, "a10").label, "a10 黑 车")
        XCTAssertEqual(point(app, "i10").label, "i10 黑 车")
        XCTAssertEqual(pointElements.filter { !$0.label.contains(" 空") }.count, 32,
                       "standard Xiangqi should begin with its full complement")
        XCTAssertEqual(control(app, "file-numerals-red").label,
                       "九 八 七 六 五 四 三 二 一")

        // docs/interaction-design.md § Layout shapes: a stacked board screen is
        // fitted to the full width, so nine files divide the whole 402 points
        // rather than what is left after an allowance on each side. That is what
        // the rule buys this phone, and it is measured on the running board
        // rather than computed: 44 points a cell, against 39 before it.
        let pitch = point(app, "a1").frame.width
        XCTAssertEqual(pitch, 44, accuracy: 0.5,
                       "full-width fitting on a 402-point phone should yield pitch 44")
        XCTAssertGreaterThanOrEqual(pitch, 34,
                                    "Xiangqi should remain above its interactive floor")
        // And the board meets the glass: what nine whole-point cells cannot
        // spend is a few points, and the surface behind the block covers them.
        let strip = control(app, "file-numerals-red")
        XCTAssertEqual(strip.frame.width, 9 * pitch, accuracy: 1,
                       "the numeral strip spans the board's own core width")
        XCTAssertLessThan(app.frame.width - strip.frame.width, pitch,
                          "and what is left beside it is less than one cell")
        for element in pointElements {
            XCTAssertEqual(element.frame.width, pitch, accuracy: 0.5,
                           "\(element.identifier) should be exactly one pitch wide")
            XCTAssertEqual(element.frame.height, pitch, accuracy: 0.5,
                           "\(element.identifier) should be exactly one pitch tall")
        }

        let pointsByIdentifier = Dictionary(
            pointElements.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first })
        for rank in 1...10 {
            for fileIndex in 0..<(files.count - 1) {
                let leftName = "point-\(files[fileIndex])\(rank)"
                let rightName = "point-\(files[fileIndex + 1])\(rank)"
                guard let left = pointsByIdentifier[leftName],
                      let right = pointsByIdentifier[rightName] else {
                    XCTFail("missing adjacent Xiangqi points \(leftName), \(rightName)")
                    continue
                }
                XCTAssertEqual(left.frame.maxX, right.frame.minX, accuracy: 0.5,
                               "adjacent hit cells should meet without overlapping")
            }
        }
        for file in files {
            for rank in 1..<10 {
                let lowerName = "point-\(file)\(rank)"
                let upperName = "point-\(file)\(rank + 1)"
                guard let lower = pointsByIdentifier[lowerName],
                      let upper = pointsByIdentifier[upperName] else {
                    XCTFail("missing adjacent Xiangqi points \(lowerName), \(upperName)")
                    continue
                }
                XCTAssertEqual(upper.frame.maxY, lower.frame.minY, accuracy: 0.5,
                               "adjacent hit cells should meet without overlapping")
            }
        }
        let a10Frame = point(app, "a10").frame
        let i1Frame = point(app, "i1").frame
        print("PHONE-XIANGQI-EVIDENCE points=\(pointElements.count) pitch=\(pitch) "
              + "a10=\(a10Frame) i1=\(i1Frame)")
        attach(app, named: "phone-xiangqi-02-the-standard-board")

        point(app, "a4").tap()
        XCTAssertTrue(waitForLabel(point(app, "a4"), containing: "已选择"),
                      "the starting soldier should respond to the first tap")
        XCTAssertTrue(waitForLabel(point(app, "a5"), containing: "可走"),
                      "one step forward should be offered as a legal Xiangqi move")
        point(app, "a5").tap()
        XCTAssertTrue(waitForLabel(point(app, "a5"), containing: "红 兵"),
                      "the destination should hold the moved soldier")
        XCTAssertTrue(waitForLabel(point(app, "a4"), containing: "空"),
                      "the soldier's starting point should be empty")
        XCTAssertTrue(waitForStatus(app, containing: "轮到黑方", timeout: 15),
                      "a committed Red move should hand Free Play to Black")
        attach(app, named: "phone-xiangqi-03-after-the-tapped-move")
    }

    // MARK: - A game against the machine, started and played with a finger

    /// The whole of what a phone does that a Mac cannot: a mode chosen from the
    /// home, a game created on its pre-start page, the stacked shape it opens
    /// in, a point big enough to hit, a move made with two taps, and a real
    /// search answering it.
    ///
    /// The level is forced to 快速 through the persistent default the draft
    /// initializes from — the real path a level reaches a game by — so the
    /// machine's answer is a one-second search rather than a three-second one.
    /// The memory probe is forced to a modest figure for the same reason the
    /// Mac's suite forces it: the arithmetic is the core's either way, and its
    /// boundaries are pinned in the unit suite where they are cheap.
    func testAGameAgainstTheMachineIsStartedFromSetupAndTakesATappedMove() {
        let app = launch(preferences: ["defaults.aiLevel": "fast"],
                         availableMemory: Self.modestMemory)
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 30))

        app.buttons["mode-mini-xiangqi-human-versus-ai"].tap()
        XCTAssertTrue(control(app, "setup-header").waitForExistence(timeout: 10),
                      "人机对弈 opens its 本局设置 page")
        XCTAssertEqual(reading(app, "setup-header"), "本局设置")
        XCTAssertTrue(control(app, "setup-first-mover").exists,
                      "with the group of per-game choices only this mode has")
        // docs/interaction-design.md § Navigation: a pre-start page is not a
        // board screen, so it is on the keeping side of the destination-bar
        // rule. This is where that rule's boundary lies, one page short of the
        // board, which is why it is asserted here rather than only at the home.
        XCTAssertTrue(app.tabBars.firstMatch.exists,
                      "本局设置 is not a board screen, so it keeps the bar")
        attach(app, named: "phone-02-the-setup-page")

        control(app, "setup-start").tap()
        XCTAssertTrue(point(app, "d1").waitForExistence(timeout: 90),
                      "开始对局 should create the game and open the board")

        // And the board is, so it puts the bar away — the owner's own
        // recommendation from the device pass (2026-07-31). Waited out rather
        // than read once: the bar leaves with an animation.
        XCTAssertTrue(waitForAbsence(app.tabBars.firstMatch),
                      "the board hides the destination bar")

        // The stacked shape, by the one affordance only it has: in the panel
        // shape the move record is resident and there is nothing to raise it.
        XCTAssertTrue(app.buttons["play-move-list"].exists,
                      "a phone takes the stacked shape, where the record is on demand")

        // The turn status is in the bar's centre, in the title's place, and the
        // page carries no name — docs/interaction-design.md § Turn status. A
        // player looking at a board does not need the page named, and the
        // status is what the height would have gone on.
        let status = control(app, "turn-status")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.frame.midY, app.buttons["play-back"].frame.midY, accuracy: 12,
                       "the status stands in the bar's centre, beside the control that "
                       + "walks back out, rather than in a block above the board")
        XCTAssertFalse(app.navigationBars.staticTexts["对局"].exists,
                       "and the board page spends its bar centre on the status, not a title")

        // The accepted human-versus-AI cluster, all five of it: 提示 leads,
        // 翻转棋盘 closes it, and every control carries its word at this width —
        // over two rows, since one row of five words is wider than the phone.
        XCTAssertEqual(app.buttons["hint-request"].label, "提示")
        XCTAssertEqual(app.buttons["cluster-undo"].label, "悔棋")
        XCTAssertEqual(app.buttons["cluster-claim"].label, "判和")
        XCTAssertEqual(app.buttons["cluster-resign"].label, "认输")
        XCTAssertEqual(app.buttons["cluster-flip"].label, "翻转棋盘",
                       "human-versus-AI carries the board-flip control too")
        for identifier in ["hint-request", "cluster-undo", "cluster-claim",
                           "cluster-resign", "cluster-flip"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(app.frame.contains(button.frame),
                          "\(identifier) should sit inside a 402-point phone, not past it")
            print("PHONE-EVIDENCE \(identifier) frame=\(button.frame)")
        }

        // The accepted 44-point floor, measured on a real phone rather than
        // computed. It is a touch-target rule, so a phone is where it means
        // something, and the corners are checked as well as the middle because
        // a stray inset shows up at an edge first.
        for name in ["a7", "d4", "g1"] {
            let square = point(app, name)
            XCTAssertGreaterThanOrEqual(square.frame.width, 44,
                                        "\(name) should be at least 44 points wide — "
                                        + "it is \(square.frame.width)")
            XCTAssertGreaterThanOrEqual(square.frame.height, 44,
                                        "\(name) should be at least 44 points tall — "
                                        + "it is \(square.frame.height)")
            print("PHONE-EVIDENCE point-\(name) frame=\(square.frame)")
        }
        attach(app, named: "phone-03-the-stacked-board")

        // 认输 asks before it acts, here as everywhere, and this platform asks
        // with an alert of its own rather than a sheet over a window.
        app.buttons["cluster-resign"].tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10),
                      "认输 confirms rather than resigning")
        let said = ([confirmation.label]
                    + confirmation.staticTexts.allElementsBoundByIndex
                        .map { text(of: $0) }).joined(separator: "\n")
        XCTAssertTrue(said.contains("认输？"), "the accepted title — it reads \(said)")
        XCTAssertTrue(said.contains("认输后本局将记为你落败。"),
                      "and the accepted message — it reads \(said)")
        attach(app, named: "phone-04-the-resign-confirmation")
        confirmation.buttons["取消"].tap()

        // 我先手 is the accepted default, so Red is at the bottom and the turn
        // is the player's own.
        XCTAssertTrue(waitForStatus(app, containing: "轮到红方", timeout: 15))
        XCTAssertEqual(control(app, "file-numerals-red").label, "七 六 五 四 三 二 一",
                       "the human is Red, so Red is at the bottom")

        // Where the board starts is not where it has to stay: 翻转棋盘 turns it
        // to the machine's side and turns nothing else. The strips read the
        // orientation off the board itself, so they are what says it happened.
        app.buttons["cluster-flip"].tap()
        XCTAssertTrue(waitForLabel(control(app, "file-numerals-red"),
                                   containing: "一 二 三 四 五 六 七"),
                      "the flip should turn the board over — the red strip reads "
                      + control(app, "file-numerals-red").label)
        XCTAssertTrue(waitForStatus(app, containing: "轮到红方", timeout: 5),
                      "and the turn is untouched: a flip is presentation")
        attach(app, named: "phone-03a-the-flipped-board")

        app.buttons["cluster-flip"].tap()
        XCTAssertTrue(waitForLabel(control(app, "file-numerals-red"),
                                   containing: "七 六 五 四 三 二 一"),
                      "and a second flip puts the human's own side back at the bottom")

        // The move itself: two taps, and the position moved.
        play(app, from: "b1", to: "b4")
        XCTAssertTrue(waitForLabel(point(app, "b4"), containing: "红 炮"),
                      "the tapped destination should be holding the piece — b4 reads "
                      + point(app, "b4").label)
        XCTAssertTrue(waitForLabel(point(app, "b1"), containing: "空"),
                      "and the square it left should be empty — b1 reads "
                      + point(app, "b1").label)
        attach(app, named: "phone-05-after-the-tapped-move")

        // The reply. Which move it is, is the machine's business; that a legal
        // one arrived and the turn came back is the invariant — and on this
        // platform it is also the first evidence that the engine, its network
        // and the memory probe all work from an iOS process.
        //
        // **The machine's own turn is not something a test can be sure of
        // seeing**, and an assertion that waited for 轮到黑方 to be *observed*
        // was asserting this process's sampling rate rather than the app.
        // Measured rather than reasoned about: at 快速, from the opening, the
        // search on this Simulator returns inside a single accessibility query,
        // so the poll's next read already says 轮到红方 and the wait fails while
        // the reply is on the board behind it. Reproduced on the branch and
        // again on an unchanged checkout, which is what says it is the
        // assertion's defect and not this round's.
        //
        // What is durable is the exchange itself, and it is a stronger claim
        // than the one it replaces: the turn is the player's again, and one of
        // Black's own pieces has left its starting point — so a search really
        // ran and really moved something, rather than a status string having
        // changed.
        XCTAssertTrue(waitForStatus(app, containing: "轮到红方", timeout: 120),
                      "the machine answers within its own thinking time and hands "
                      + "the turn back — Black cannot mate in one from here — the "
                      + "status reads " + reading(app, "turn-status"))
        let blackStart = ["a7", "b7", "c7", "d7", "e7", "f7", "g7",
                          "a6", "c6", "d6", "e6", "g6"]
        XCTAssertTrue(blackStart.contains { point(app, $0).label.contains("空") },
                      "and it answered by moving one of its own pieces — every one "
                      + "of Black's starting points is still occupied")
        attach(app, named: "phone-06-after-the-machines-reply")
    }

    // MARK: - The move record, on demand

    /// In the stacked shape the record is reached rather than resident: a
    /// toolbar item raises a sheet over the board, and the board is still there
    /// underneath it. This is the arrangement's own affordance, and it exists on
    /// no Mac window this project's suites drive.
    func testTheMoveRecordIsReachedOnDemandAndPutAway() {
        let app = launch(replaying: Self.openingLine)
        XCTAssertTrue(point(app, "d4").waitForExistence(timeout: 30),
                      "the replay fixture opens at the board it made")
        XCTAssertFalse(app.staticTexts["炮六进二"].exists,
                       "the record is not resident in this shape")

        app.buttons["play-move-list"].tap()

        XCTAssertTrue(app.buttons["move-list-done"].waitForExistence(timeout: 10),
                      "棋谱 raises the record over the board")
        XCTAssertTrue(app.staticTexts["炮六进二"].exists,
                      "with the game's moves in the accepted notation")
        XCTAssertTrue(app.staticTexts["砲2进1"].exists,
                      "each side reading in its own numerals")
        XCTAssertTrue(app.staticTexts["1."].exists, "numbered by decision")
        XCTAssertTrue(point(app, "d4").exists,
                      "and the board is covered rather than replaced")
        attach(app, named: "phone-07-the-move-record-sheet")

        app.buttons["move-list-done"].tap()

        // The toolbar item is behind the sheet the whole time it is up, so its
        // presence says nothing about the sheet having gone. What says so is the
        // sheet's own Done going away.
        XCTAssertTrue(waitForAbsence(app.buttons["move-list-done"]),
                      "完成 puts the record away")
        XCTAssertFalse(app.staticTexts["炮六进二"].exists,
                       "and the record is gone with it")
        XCTAssertTrue(app.buttons["play-move-list"].isHittable,
                      "leaving the toolbar item able to raise it again")
        XCTAssertTrue(point(app, "d4").exists, "and the board as it was")
        attach(app, named: "phone-08-the-board-after-the-record")

        // Raised a second time, because a sheet that cannot be re-opened is a
        // sheet that took its trigger with it.
        app.buttons["play-move-list"].tap()
        XCTAssertTrue(app.buttons["move-list-done"].waitForExistence(timeout: 10))
        app.buttons["move-list-done"].tap()
        XCTAssertTrue(waitForAbsence(app.buttons["move-list-done"]))
    }

    // MARK: - Turning the device

    /// docs/testing.md: "Verify iPhone stays in portrait when rotated and shows
    /// no orientation prompt." It is the one orientation clause that belongs to
    /// the phone, and it is invisible from a Mac.
    ///
    /// What makes this an assertion rather than a screenshot is that the two
    /// shapes are chosen by the available space: a phone that *followed* the
    /// rotation would hand the layout 874 by 402, where the panel fits and the
    /// stacked shape's toolbar item would not be drawn at all. So the toolbar
    /// item surviving the turn is the layout not having turned, and the frame
    /// staying portrait is the window not having.
    func testTheBoardKeepsItsPortraitShapeWhenTheDeviceIsTurned() {
        let app = launch(replaying: Self.openingLine)
        XCTAssertTrue(point(app, "d4").waitForExistence(timeout: 30))
        let upright = app.frame
        XCTAssertGreaterThan(upright.height, upright.width, "the premise: portrait")

        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        // The rotation is the device's, and it is animated; the assertion is
        // about where the app settled rather than about a frame mid-turn.
        Thread.sleep(forTimeInterval: 2)

        XCTAssertEqual(app.frame, upright,
                       "the phone does not follow the device into landscape")
        XCTAssertTrue(app.buttons["play-move-list"].exists,
                      "so the layout is still the stacked one — the panel shape has "
                      + "no toolbar item to raise the record with")
        XCTAssertTrue(point(app, "d4").exists, "and the board is still addressable")
        XCTAssertFalse(app.alerts.firstMatch.exists, "with nothing asked about it")
        attach(app, named: "phone-09-the-device-turned")

        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.frame, upright, "and turning back changes nothing either")
        XCTAssertTrue(point(app, "d4").exists)
    }

    // MARK: - The end of a game

    /// The result flow, as far as it goes without a search in it: the notice
    /// arrives over the board, 保存 files the game, the notice says so, and the
    /// record is in History. Every step is a touch, and the position underneath
    /// is never dimmed or taken away.
    func testTheResultNoticeIsSavedAndPutAwayWithAFinger() {
        let app = launch(replaying: Self.mateLine)
        XCTAssertTrue(control(app, "result-title").waitForExistence(timeout: 30),
                      "a finished game presents its result")

        XCTAssertEqual(reading(app, "result-title"), "红方获胜")
        XCTAssertEqual(reading(app, "result-reason"), "将死")
        XCTAssertEqual(app.buttons["result-new-game"].label, "保存并开始新对局")
        XCTAssertEqual(app.buttons["result-save"].label, "保存")
        XCTAssertFalse(app.buttons["result-done"].exists,
                       "an unconfirmed result has nothing to be done with yet")
        XCTAssertTrue(point(app, "d4").exists,
                      "and the board it came from is still there behind it")
        attach(app, named: "phone-10-the-result-notice")

        press(app.buttons["result-save"])

        XCTAssertTrue(waitForLabel(control(app, "result-title"),
                                   containing: "已记录到历史"),
                      "保存 files the game and the notice says where it went — "
                      + "it reads " + reading(app, "result-title"))
        XCTAssertEqual(reading(app, "result-reason"), "将死",
                       "the reason under it is unchanged")
        XCTAssertEqual(app.buttons["result-replay"].label, "回放")
        XCTAssertEqual(app.buttons["result-done"].label, "完成")
        XCTAssertFalse(app.buttons["result-save"].exists, "a filed game is not filed twice")
        attach(app, named: "phone-11-the-recorded-result")

        // Closing decides nothing: the board keeps the result, the turn status
        // still carries it, and the concluding action is in the cluster.
        press(app.buttons["result-close"])
        XCTAssertTrue(waitForAbsence(control(app, "result-title")),
                      "the close control puts the notice away")
        XCTAssertTrue(app.buttons["cluster-new-game"].exists,
                      "the concluding action is in the cluster behind it")
        XCTAssertTrue(waitForStatus(app, containing: "红方胜", timeout: 10),
                      "the status still carries the result — it reads "
                      + reading(app, "turn-status"))
        XCTAssertTrue(point(app, "d4").exists)
        attach(app, named: "phone-12-the-board-after-closing")

        // And the record exists, which is what 保存 promised. The way to
        // History from here is out of the board first: this screen has put the
        // destination bar away, per docs/interaction-design.md § Navigation, and
        // the bar comes back with the home. That is the walk a person makes, and
        // asserting the bar's return on the way is what says the change withdrew
        // no destination.
        goBack(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10),
                      "leaving the board brings the destination bar back")
        destination(app, 1).tap()
        let row = control(app, "history-row-0")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the filed game is in History")
        XCTAssertTrue(row.label.contains("迷你象棋 · 自由对弈 · 红方获胜 · 将死 · 3 步"),
                      "with its own result and its exact reason — it reads " + row.label)
        attach(app, named: "phone-13-the-record-in-history")
    }

    // MARK: - Replay, and the bar the board screens put away

    /// docs/interaction-design.md § Navigation: the board and replay hide the
    /// destination bar where it stands across the bottom of the screen; the
    /// homes keep it. A phone is the only presentation the rule applies to, so
    /// a phone is the only place it can be driven — and this is also the first
    /// time any suite reaches replay from this platform, which is the second
    /// thing the test is for: the screen is not only laid out but reachable.
    func testAReplayHidesTheDestinationBarAndLeavingItBringsItBack() {
        let app = launch(history: Self.mateLine)
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 30),
                      "a launch with no game to resume opens on the Play home")

        destination(app, 1).tap()
        let row = control(app, "history-row-0")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the seeded game is in History")
        XCTAssertTrue(app.tabBars.firstMatch.exists,
                      "and the list is a home, so it carries the bar")

        row.tap()

        XCTAssertTrue(control(app, "replay-progress").waitForExistence(timeout: 20),
                      "the row opens the record's replay")
        XCTAssertEqual(reading(app, "replay-progress"), "0 / 3",
                       "which begins at the game's initial position")
        XCTAssertTrue(app.buttons["replay-next"].exists,
                      "with the transport under the board")
        // Waited out rather than read once: the bar leaves with the push.
        XCTAssertTrue(waitForAbsence(app.tabBars.firstMatch),
                      "and the replay screen puts the destination bar away — the "
                      + "owner's own recommendation from the device pass (2026-07-31)")
        attach(app, named: "phone-14-the-replay-without-the-bar")

        // The bar belongs to the screen rather than to the session, so leaving
        // returns it. The back control is addressed by position because it is
        // the platform's own and its label is the platform's own too.
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), "back reaches the list again")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10),
                      "with the bar under it")
        attach(app, named: "phone-15-the-list-with-the-bar-back")
    }
}

#endif  // os(iOS)
