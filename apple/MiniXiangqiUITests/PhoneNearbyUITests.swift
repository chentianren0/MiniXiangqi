// Nearby play, as far as a Simulator can honestly go.
//
// A Simulator has no Wi-Fi Aware, and every launch here holds the other path
// down, so there is no room, no pairing and no game to play — and this suite
// does not pretend otherwise. What it can answer is everything on this side of
// them: that the entry rows are drawn, and what the sheet those rows raise is
// made of. The played board and the two-device flow belong to real devices, and
// the driven device run is where they are seen.
//
// **The local network is held down on purpose, with `-mxq-nearby-paths radio`.**
// A Simulator's Bonjour is the *host's*, so a suite that left it running would
// browse the developer's own network and advertise this app on it — and the
// empty room these tests assert would hold whatever else happened to be
// advertising, including another Simulator two tests away. An empty room has to
// be a fact of the launch rather than a hope about the room.
//
// **A Simulator is a device with no radio, and that is exactly the interesting
// case now.** The feature is two ways of reaching another device and one of them
// asks the hardware for nothing, so the rows stand here as they stand on every
// iPhone and iPad — with nothing forced and nothing faked. The one thing a
// device without the radio cannot do is pair, and the sheet's own pairing
// section is where that shows.
//
// The words asserted here are the accepted Simplified Chinese, written out
// rather than read from the application's own catalog: a test that reads the
// file the application reads asserts only that the file is itself.

#if os(iOS)

import XCTest

@MainActor
final class PhoneNearbyUITests: XCTestCase {

    private func launch(board: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)"]
        app.launchArguments += ["-mxq-store-name", "mxq-uitest-store-" + UUID().uuidString]
        app.launchArguments += ["-mxq-defaults-suite", "mxq-uitests-phone"]
        app.launchArguments += ["-mxq-appearance", "light"]
        app.launchArguments += LaunchPreferences.arguments()
        // Nobody in the room, as a fact rather than a hope: the radio does not
        // exist here, and this is what keeps the other path from reaching the
        // network this machine is on.
        app.launchArguments += ["-mxq-nearby-paths", "radio"]
        // The board itself, which no amount of pressing reaches here: the
        // session is handed to the app, and everything above it — the flow, the
        // board's model, the position — is the real thing.
        if let board { app.launchArguments += ["-mxq-nearby-board", board] }
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

    /// The rows stand on a device with no radio, and the four local ways to play
    /// are exactly as they were.
    ///
    /// This device *is* the case: a Simulator has no Wi-Fi Aware at all, and the
    /// rows are drawn anyway, because the other way of reaching a device needs
    /// no hardware and the row stands wherever either could carry a game.
    func testTheNearbyRowsStandOnADeviceWithNoRadio() {
        let app = launch()
        XCTAssertTrue(app.buttons["mode-xiangqi-human-versus-ai"]
            .waitForExistence(timeout: 30))

        XCTAssertTrue(app.buttons["mode-xiangqi-nearby"].exists,
                      "a device without the radio offers nearby all the same")
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-nearby"].exists)
        for identifier in ["mode-xiangqi-human-versus-ai", "mode-xiangqi-free-play",
                           "mode-mini-xiangqi-human-versus-ai",
                           "mode-mini-xiangqi-free-play"] {
            XCTAssertTrue(app.buttons[identifier].exists,
                          "\(identifier) is untouched by the nearby entry")
        }
        attach(app, named: "phone-nearby-01-the-home-with-no-radio")
    }

    /// Each game's section carries a third row, under that game's own two and
    /// inside that game's own section.
    func testTheNearbyRowIsTheThirdRowInEachGamesSection() {
        let app = launch()
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
        let app = launch()
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
        // And with no radio the section says so rather than building the
        // system's pairing views, which is what keeps this launch alive: those
        // views engage a peer-to-peer Wi-Fi service the Simulator does not
        // have, and the app is terminated moments later. The designed row is
        // the evidence that the guard held.
        XCTAssertTrue(element(app, saying: "这台设备无法配对").exists,
                      "a device without the radio says so where the pairing controls "
                      + "would be")
        attach(app, named: "phone-nearby-03-the-propose-sheet")

        app.buttons["nearby-close"].tap()
        XCTAssertTrue(app.buttons["mode-mini-xiangqi-nearby"].waitForExistence(timeout: 10),
                      "and putting the sheet away returns to the Play home")
        XCTAssertFalse(app.buttons["nearby-invite"].exists)
    }

    // MARK: - The board's negotiations
    //
    // A staged session, because a Simulator has no radio to get one from. What
    // is asserted is the one thing a picture of a board can answer for: which
    // controls the moment carries. Everything about *whether* the engine allows
    // an act is the flow suite's, against the engine's own law.

    /// Off turn the cluster is the two negotiations, 认输 and 翻转棋盘 — and
    /// neither the claim nor an answer, because neither is this side's.
    func testTheOffTurnBoardCarriesTheNegotiations() {
        let app = launch(board: "off-turn")
        let offer = app.buttons["cluster-offer-draw"]
        XCTAssertTrue(offer.waitForExistence(timeout: 30))
        XCTAssertEqual(offer.label, "提和")
        XCTAssertTrue(offer.isEnabled)

        let undo = app.buttons["cluster-undo"]
        XCTAssertTrue(undo.exists)
        XCTAssertEqual(undo.label, "悔棋")
        XCTAssertTrue(undo.isEnabled, "this device has a ply of its own to ask back")

        XCTAssertFalse(app.buttons["cluster-claim"].exists,
                       "a claim is a turn action, and it is not this device's turn")
        XCTAssertFalse(app.buttons["cluster-accept"].exists,
                       "nothing is standing to answer")
        XCTAssertTrue(app.buttons["cluster-resign"].exists)
        XCTAssertTrue(app.buttons["cluster-flip"].exists)
        XCTAssertFalse(app.staticTexts["nearby-asking"].exists)
        attach(app, named: "phone-nearby-04-off-turn")
    }

    /// On turn it is the claim instead — present and unavailable, because the
    /// position has nothing to claim.
    func testTheOnTurnBoardCarriesTheClaim() {
        let app = launch(board: "on-turn")
        let claim = app.buttons["cluster-claim"]
        XCTAssertTrue(claim.waitForExistence(timeout: 30))
        XCTAssertEqual(claim.label, "判和")
        XCTAssertFalse(claim.isEnabled, "there is no repetition to claim yet")

        XCTAssertFalse(app.buttons["cluster-offer-draw"].exists,
                       "an offer is the off-turn player's to open")
        XCTAssertFalse(app.buttons["cluster-undo"].exists)
        XCTAssertTrue(app.buttons["cluster-resign"].exists)
        XCTAssertTrue(app.buttons["cluster-flip"].exists)
        attach(app, named: "phone-nearby-05-on-turn")
    }

    /// A claim the engine says stands is the enabled control and the 可判和 line
    /// beside the turn status — the same pair the local game's claim is.
    func testAStandingClaimIsTheControlAndTheLine() {
        let app = launch(board: "claimable")
        let claim = app.buttons["cluster-claim"]
        XCTAssertTrue(claim.waitForExistence(timeout: 30))
        XCTAssertTrue(claim.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["turn-status"].label.contains("可判和"),
                      "the standing offer is the control and the line together")
        attach(app, named: "phone-nearby-06-the-claim-stands")
    }

    /// What the other player asked for is a line in the turn status's own quiet
    /// register, with 接受 beside it and nothing blocking the board.
    func testAnArrivingOfferIsALineAndAnAnswer() {
        let app = launch(board: "offered")
        let asking = app.staticTexts["nearby-asking"]
        XCTAssertTrue(asking.waitForExistence(timeout: 30))
        XCTAssertEqual(asking.label, "对方提和")

        let accept = app.buttons["cluster-accept"]
        XCTAssertTrue(accept.exists)
        XCTAssertEqual(accept.label, "接受")
        XCTAssertFalse(app.buttons["cluster-claim"].exists,
                       "the turn is about the answer, not about a claim")
        XCTAssertTrue(app.buttons["cluster-resign"].exists)
        attach(app, named: "phone-nearby-07-a-draw-offered")
    }

    /// And a take-back asked for is the same shape with its own words.
    func testAnArrivingTakeBackIsALineAndAnAnswer() {
        let app = launch(board: "undo-asked")
        let asking = app.staticTexts["nearby-asking"]
        XCTAssertTrue(asking.waitForExistence(timeout: 30))
        XCTAssertEqual(asking.label, "对方请求悔棋")
        XCTAssertEqual(app.buttons["cluster-accept"].label, "接受")
        attach(app, named: "phone-nearby-08-a-take-back-asked")
    }
}

#endif  // os(iOS)
