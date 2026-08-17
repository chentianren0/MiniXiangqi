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

    /// An element's label, waited for before it is read: a label taken from the
    /// snapshot a page was still assembling in reads back empty, and an
    /// assertion made there is a race that passes on a fast run.
    private func label(_ app: XCUIApplication, _ identifier: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        return element.label
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The entry

    /// The rows stand on a device with no radio, in every game's section, and
    /// the local ways to play are exactly as they were.
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

        // Every game the app carries, it carries with somebody: the dealt game
        // and the placement games' sections end in the same nearby row, further
        // down the list. Jieqi's is its second row rather than its third — that
        // game has no AI to offer — and it is a nearby row like any other.
        for identifier in ["mode-jieqi-nearby", "mode-gomoku-nearby", "mode-renju-nearby"] {
            XCTAssertTrue(scrollTo(app, identifier),
                          "\(identifier) completes that game's section")
        }
        attach(app, named: "phone-nearby-01b-the-placement-sections")
    }

    /// Brings a row into the list and answers whether it was there to bring: a
    /// list realizes the rows it is showing, so a row below the fold has to be
    /// scrolled to before it can be asked about at all.
    private func scrollTo(_ app: XCUIApplication, _ identifier: String) -> Bool {
        for _ in 0..<6 {
            if app.buttons[identifier].exists { return true }
            app.swipeUp()
        }
        return app.buttons[identifier].exists
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
        XCTAssertFalse(app.buttons["nearby-captured"].exists,
                       "a game whose position is wholly public displays no captures")
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

    /// docs/interaction-design.md § Layout shapes: in the stacked shape the
    /// board's frame does not follow the controls, and a nearby game is where
    /// that is felt every ply. The turn passing swaps the two negotiations for
    /// the claim, and the two sets are not the same width — on this phone one
    /// of them wraps to a second row where the other stands in one — so a board
    /// sized around the cluster on screen would rise and fall with every turn.
    ///
    /// The two sides of the turn are two launches, because a Simulator has no
    /// radio to pass one with: the moments are staged, exactly as every other
    /// board in this file is, and what is compared is the board each moment
    /// draws. What it would catch: the board's geometry reading the cluster's
    /// live height again, and any control added to one side of the turn and not
    /// the other paying for itself out of the board.
    func testTheBoardIsTheSameBoardOnBothSidesOfTheTurn() {
        let offTurn = launch(board: "off-turn")
        XCTAssertTrue(offTurn.buttons["cluster-offer-draw"].waitForExistence(timeout: 30),
                      "the off-turn cluster carries the negotiations")
        let off = corners(offTurn)
        // This is the side that wraps on this phone, so it is where the slot is
        // asked for the whole of what it reserves: the second row stands below
        // the board and inside the screen rather than under a board drawn over
        // it.
        let flip = offTurn.buttons["cluster-flip"]
        XCTAssertGreaterThan(flip.frame.minY, off[0].maxY,
                             "the cluster stands below the board")
        // **And it really has wrapped**, which is this test's premise rather
        // than an incidental: 翻转棋盘 is on a row of its own, beneath the
        // negotiations. A width or a set that stopped wrapping here would leave
        // the two scenes the same height and the comparison below with nothing
        // to catch, so it is asserted rather than assumed.
        XCTAssertGreaterThan(flip.frame.minY,
                             offTurn.buttons["cluster-offer-draw"].frame.maxY,
                             "the off-turn set wraps to a second row on this phone — "
                             + "翻转棋盘 is at \(flip.frame) and 提和 at "
                             + "\(offTurn.buttons["cluster-offer-draw"].frame)")
        XCTAssertTrue(offTurn.frame.contains(flip.frame),
                      "and inside the screen — it is at \(flip.frame)")
        offTurn.terminate()

        let onTurn = launch(board: "on-turn")
        XCTAssertTrue(onTurn.buttons["cluster-claim"].waitForExistence(timeout: 30),
                      "and the on-turn cluster carries the claim")
        let on = corners(onTurn)

        for (side, other) in zip(on, off) {
            XCTAssertEqual(side.minX, other.minX, accuracy: 0.5,
                           "the board does not move when the turn passes")
            XCTAssertEqual(side.minY, other.minY, accuracy: 0.5,
                           "the board does not move when the turn passes — it is at "
                           + "\(side) on turn and \(other) off it")
            XCTAssertEqual(side.width, other.width, accuracy: 0.5,
                           "nor change size — it is \(side) on turn and \(other) off it")
            XCTAssertEqual(side.height, other.height, accuracy: 0.5,
                           "nor change size — it is \(side) on turn and \(other) off it")
        }
        attach(onTurn, named: "phone-nearby-09-the-board-across-the-turn")
    }

    /// Where the board is and how big it is, read as two opposite corners of
    /// it: the pair moves if the block moves and changes if the pitch does.
    private func corners(_ app: XCUIApplication) -> [CGRect] {
        [app.descendants(matching: .any)["point-a1"].frame,
         app.descendants(matching: .any)["point-g7"].frame]
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

    // MARK: - The dealt board, and what its captures took
    //
    // docs/interaction-design.md § Captured pieces: **Jieqi displays them,
    // because there the reasoning does not hold — what a capture takes off the
    // board is knowledge, and knowledge is that game's material.** Nearby play
    // is where that surface has two readers: each device draws its own player's
    // knowledge, so the two players' surfaces are not the same surface.
    //
    // The staged session is a dealt board with a capture each way, which is what
    // makes the two rows say the two different things at once.

    /// The surface is reached from the board's own toolbar — the move list's
    /// answer to the same question, on the same surface and for the same reason
    /// — and what stands in it is drawn for this device's player.
    func testTheNearbyJieqiBoardReachesWhatItsCapturesTook() {
        let app = launch(board: "jieqi")

        // The dealt board itself, drawn from the deal its session holds: a
        // face-down disc says whose piece it is and no more.
        XCTAssertTrue(point(app, "a1").waitForExistence(timeout: 30))
        XCTAssertEqual(label(app, "point-a1"), "a1 红 暗子")

        let opener = app.buttons["nearby-captured"]
        XCTAssertTrue(opener.exists,
                      "the board keeps its pitch floor, so the surface is reached "
                      + "rather than resident")
        opener.tap()

        // This device's player is Red, and their own face-down loss is a count
        // and nothing more: losing a hidden piece tells its owner that a piece
        // is gone and never which.
        XCTAssertEqual(label(app, "captured-red"), "红 1 暗子")

        // The piece they took is whole, because the capture disclosed it to them
        // alone — the horse the staged deal had standing on h10 — and it says
        // it left face down, the hidden word joined to its name.
        XCTAssertEqual(label(app, "captured-black"), "黑 暗马")
        attach(app, named: "phone-nearby-14-what-the-captures-took")

        app.buttons["captured-done"].tap()
        XCTAssertTrue(point(app, "a1").waitForExistence(timeout: 10),
                      "and the board is where it was")
    }

    // MARK: - A board stones are placed on
    //
    // The same staged sessions, in the two games the protocol carries without
    // knowing anything about them. What is asked here is what only the drawn
    // board can answer: that a nearby placement board is the placement board —
    // stones, coordinates, the crosses — and that the cluster is the set these
    // games have.

    /// A point of the drawn board, by the coordinate it is named at.
    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["point-\(name)"]
    }

    /// An element's label, waited for rather than read once: what a board draws
    /// after a tap arrives when the transition it rides does.
    private func wait(_ element: XCUIElement, saying wanted: String,
                      timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label.contains(wanted) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    /// A nearby Gomoku board is the board: a stone stands where the session put
    /// it, and the board is the fifteen-line one with the Go-style coordinates.
    func testAPlacementBoardDrawsStonesAndCoordinates() {
        let app = launch(board: "placement-off-turn")
        let centre = point(app, "h8")
        XCTAssertTrue(centre.waitForExistence(timeout: 30),
                      "a 15-line board's own centre point is addressable")
        XCTAssertTrue(centre.label.contains("黑"),
                      "the first mover's stone is the black one — h8 reads "
                      + "\(centre.label)")

        // A point nothing stands on, and the far corner of a board that is
        // fifteen lines each way rather than nine or seven.
        XCTAssertTrue(point(app, "a1").label.contains("空"))
        XCTAssertTrue(point(app, "o15").exists, "the board runs to o15")
        attach(app, named: "phone-nearby-10-a-placement-board")
    }

    /// Off turn the cluster is the negotiations two people have between them,
    /// and 翻转棋盘 is not there at all — a stone has no orientation to read.
    func testThePlacementClusterKeepsTheNegotiationsAndDropsTheFlip() {
        let app = launch(board: "placement-off-turn")
        let offer = app.buttons["cluster-offer-draw"]
        XCTAssertTrue(offer.waitForExistence(timeout: 30))
        XCTAssertEqual(offer.label, "提和")
        XCTAssertTrue(offer.isEnabled, "a draw offered to a person is meaningful")

        let undo = app.buttons["cluster-undo"]
        XCTAssertTrue(undo.exists)
        XCTAssertTrue(undo.isEnabled, "this device has a stone of its own to ask back")
        XCTAssertTrue(app.buttons["cluster-resign"].exists)
        XCTAssertFalse(app.buttons["cluster-flip"].exists,
                       "stones carry no orientation a player could read")
        XCTAssertFalse(app.buttons["cluster-claim"].exists)
        attach(app, named: "phone-nearby-11-the-placement-cluster")
    }

    /// On turn there is nothing to claim, so 认输 stands alone — and the Renju
    /// position's forbidden point is on the board, marked as the core's answer
    /// rather than as anything this screen worked out.
    func testThePlacementOnTurnClusterAndTheForbiddenPoint() {
        let app = launch(board: "placement-on-turn")
        let resign = app.buttons["cluster-resign"]
        XCTAssertTrue(resign.waitForExistence(timeout: 30))

        XCTAssertFalse(app.buttons["cluster-claim"].exists,
                       "there is no repetition in these games to claim")
        XCTAssertFalse(app.buttons["cluster-flip"].exists)
        XCTAssertFalse(app.buttons["cluster-offer-draw"].exists,
                       "an offer is the off-turn player's to open")
        XCTAssertFalse(app.buttons["cluster-undo"].exists)

        XCTAssertTrue(point(app, "h8").label.contains("禁手"),
                      "the point a double three would make is Black's to see — "
                      + "h8 reads \(point(app, "h8").label)")
        attach(app, named: "phone-nearby-12-a-renju-board-on-turn")
    }

    /// A stone placed on a nearby board stands on its point and passes the turn.
    ///
    /// The staged driver keeps the ply, which is what the engine does with one,
    /// so this reaches the whole of the board's own commit path: the tap, the
    /// point sent as its own single-square text, the stone drawn where it was
    /// put, and the turn belonging to the other player afterwards. What it would
    /// catch is the placement commit landing in the movement path, which has an
    /// origin to read and a disc to send across the board and would draw nothing
    /// at all here.
    func testAStonePlacedOnANearbyBoardStandsAndPassesTheTurn() {
        let app = launch(board: "placement-on-turn")
        let target = point(app, "b2")
        XCTAssertTrue(target.waitForExistence(timeout: 30))
        XCTAssertTrue(target.label.contains("空"), "an empty point to place on")

        let status = app.descendants(matching: .any)["turn-status"]
        XCTAssertTrue(status.label.contains("轮到黑方"),
                      "it is the first mover's turn — the status reads \(status.label)")

        target.tap()

        // The stone is on the point it was tapped, and it is this device's own
        // colour: the first mover's, which these games call black.
        XCTAssertTrue(wait(point(app, "b2"), saying: "黑"),
                      "the stone stands where it was put — b2 reads "
                      + "\(point(app, "b2").label)")
        XCTAssertTrue(wait(status, saying: "轮到白方"),
                      "and the turn has passed — the status reads \(status.label)")
        attach(app, named: "phone-nearby-13-a-stone-placed")
    }
}

#endif  // os(iOS)
