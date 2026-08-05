// Nearby play, as far as a Simulator can honestly go.
//
// A Simulator has no Wi-Fi Aware, so there is no room, no pairing and no game to
// play here — and this suite does not pretend otherwise. What it can answer is
// everything on this side of the radio: whether the entry rows are drawn, which
// is a decision about the *hardware* and therefore has to be shown in both of
// its states, and what the sheet those rows raise is made of. The played board
// and the two-device flow belong to real devices, and the owner's own device
// pass is where they are seen.
//
// Both states of the entry are named explicitly, through `-mxq-nearby-capable`.
// A test that only asserted the rows were hidden would prove nothing: a row that
// is never drawn is hidden on every device, radio or no radio.
//
// The words asserted here are the normative Simplified Chinese of docs/copy.md,
// written out rather than read from the application's own catalog: a test that
// reads the file the application reads asserts only that the file is itself.

#if os(iOS)

import XCTest

@MainActor
final class PhoneNearbyUITests: XCTestCase {

    private func launch(nearbyCapable: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)"]
        app.launchArguments += ["-mxq-store-name", "mxq-uitest-store-" + UUID().uuidString]
        app.launchArguments += ["-mxq-defaults-suite", "mxq-uitests-phone"]
        app.launchArguments += ["-mxq-appearance", "light"]
        app.launchArguments += LaunchPreferences.arguments()
        // The one thing a Simulator cannot answer for itself. It decides whether
        // the rows are drawn and nothing else: the radio is still absent, so
        // nothing is started behind them.
        app.launchArguments += ["-mxq-nearby-capable", nearbyCapable ? "1" : "0"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                      "the app should reach the foreground")
        return app
    }

    private func element(_ app: XCUIApplication, saying text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", text))
            .firstMatch
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The entry

    /// The row is absent rather than disabled where the hardware has no radio,
    /// and the four local ways to play are exactly as they were.
    func testTheNearbyRowsAreAbsentWithoutTheRadio() {
        let app = launch(nearbyCapable: false)
        XCTAssertTrue(app.buttons["mode-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 30))

        XCTAssertFalse(app.buttons["mode-xiangqi-nearby"].exists,
                       "a device without the radio offers no nearby row")
        XCTAssertFalse(app.buttons["mode-mini-xiangqi-nearby"].exists)
        for identifier in ["mode-xiangqi-human-versus-ai", "mode-xiangqi-free-play",
                           "mode-mini-xiangqi-human-versus-ai",
                           "mode-mini-xiangqi-free-play"] {
            XCTAssertTrue(app.buttons[identifier].exists,
                          "\(identifier) is untouched by the nearby entry")
        }
        attach(app, named: "phone-nearby-01-the-home-without-the-radio")
    }

    /// With the radio, each game's section carries a third row, under that
    /// game's own two and inside that game's own section.
    func testTheNearbyRowIsTheThirdRowInEachGamesSection() {
        let app = launch(nearbyCapable: true)
        let xiangqiNearby = app.buttons["mode-xiangqi-nearby"]
        XCTAssertTrue(xiangqiNearby.waitForExistence(timeout: 30))

        let miniNearby = app.buttons["mode-mini-xiangqi-nearby"]
        XCTAssertTrue(miniNearby.exists)
        XCTAssertEqual(xiangqiNearby.label, "附近对弈")
        XCTAssertEqual(miniNearby.label, "附近对弈")

        // Third in its own section: after that game's two, and before the next
        // game's first.
        XCTAssertLessThan(app.buttons["mode-xiangqi-free-play"].frame.minY,
                          xiangqiNearby.frame.minY)
        XCTAssertLessThan(xiangqiNearby.frame.minY,
                          app.buttons["mode-mini-xiangqi-human-versus-ai"].frame.minY)
        XCTAssertLessThan(app.buttons["mode-mini-xiangqi-free-play"].frame.minY,
                          miniNearby.frame.minY)
        attach(app, named: "phone-nearby-02-the-home-with-the-rows")
    }

    // MARK: - The sheet the row raises

    /// The propose sheet: the game it was raised for, the side this device would
    /// take, the invitation, and the pairing that has to happen once per pair of
    /// devices. With no radio there is nobody to invite, which is the state a
    /// Simulator can show — and the invitation says so by being unavailable
    /// rather than by explaining itself.
    func testTheProposeSheetOffersTheSideChoiceAndTheInvitation() {
        let app = launch(nearbyCapable: true)
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-nearby"].waitForExistence(timeout: 30))

        app.buttons["mode-mini-xiangqi-nearby"].tap()

        let invite = app.buttons["nearby-invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10),
                      "the row raises the sheet that offers the game")
        XCTAssertTrue(element(app, saying: "迷你象棋").exists,
                      "the sheet names the game its row named")

        // The side is the proposer's choice, and the other device takes what is
        // left — which is why the second option names the other player.
        XCTAssertTrue(app.descendants(matching: .any)["nearby-side"].exists)
        XCTAssertTrue(element(app, saying: "我先手").exists)
        XCTAssertTrue(element(app, saying: "对方先手").exists)

        XCTAssertEqual(invite.label, "发出邀请")
        XCTAssertFalse(invite.isEnabled,
                       "with nobody in the room there is nobody to invite")
        XCTAssertTrue(app.staticTexts["nearby-searching"].exists)
        XCTAssertEqual(app.staticTexts["nearby-searching"].label, "正在查找附近的设备…")

        // Pairing is on the same surface because it is the same errand, and it
        // is done once per pair of devices.
        XCTAssertTrue(element(app, saying: "配对").exists)
        XCTAssertTrue(element(app, saying: "两台设备只需配对一次。").exists)
        attach(app, named: "phone-nearby-03-the-propose-sheet")

        app.buttons["nearby-close"].tap()
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-nearby"].waitForExistence(timeout: 10),
                      "and putting the sheet away returns to the Play home")
        XCTAssertFalse(app.buttons["nearby-invite"].exists)
    }
}

#endif  // os(iOS)
