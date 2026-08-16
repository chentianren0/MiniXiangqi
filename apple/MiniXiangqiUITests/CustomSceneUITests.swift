// The Custom Scene row and the editor it opens, on the running screen.
//
// docs/interaction-design.md, "Custom Scene": the row is the last of the
// Xiangqi section and it opens an editor — an empty interactive board, a
// palette, a side-to-move choice, a live reason, and 开始对局 enabled on a
// position that is both legal and playable. What Start creates is an ordinary
// Free Play game from the composed position.
//
// The words asserted here are the accepted Simplified Chinese, written out
// rather than read from the application's own catalog: a test that reads the
// file the application reads asserts only that the file is itself.

// **macOS only**, like the other window-driving suites beside it: this one
// clicks a pointer at a window and reads frames back.
#if os(macOS)

import XCTest

@MainActor
final class CustomSceneUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)"]
        app.launchArguments += ["-mxq-store-name", "mxq-uitest-store-" + UUID().uuidString]
        app.launchArguments += ["-mxq-defaults-suite", LaunchPreferences.scratchSuite]
        app.launchArguments += LaunchPreferences.arguments()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["point-\(name)"]
    }

    /// A palette entry, named by the side and the core's own letter for the
    /// piece — the same spelling a FEN uses.
    private func palette(_ app: XCUIApplication, _ side: String,
                         _ letter: String) -> XCUIElement {
        app.buttons["palette-\(side)-\(letter)"]
    }

    private func reading(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = app.staticTexts[identifier]
        return (element.value as? String) ?? element.label
    }

    /// Puts one piece down: pick the entry, then tap the point.
    private func place(_ app: XCUIApplication, _ side: String, _ letter: String,
                       at square: String) {
        palette(app, side, letter).click()
        point(app, square).click()
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The row

    /// The row stands last in the Xiangqi section and opens the editor, whose
    /// board is empty and addressable.
    func testTheRowIsLastInTheXiangqiSectionAndOpensTheEditor() {
        let app = launch()
        let scene = app.buttons["mode-xiangqi-custom-scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 20))
        XCTAssertEqual(scene.label, "自定排局")
        XCTAssertGreaterThan(scene.frame.minY,
                             app.buttons["mode-xiangqi-free-play"].frame.minY,
                             "under that game's ways to play")
        XCTAssertLessThan(scene.frame.minY, app.staticTexts["迷你象棋"].frame.minY,
                          "and still inside the Xiangqi section")
        XCTAssertFalse(app.buttons["mode-mini-xiangqi-custom-scene"].exists,
                       "Xiangqi's alone")

        scene.click()

        XCTAssertTrue(app.buttons["scene-start"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["scene-start"].label, "开始对局")
        XCTAssertFalse(app.buttons["scene-start"].isEnabled,
                       "an empty board is no position to start from")
        XCTAssertEqual(reading(app, "scene-reason"), "先给双方各放一个将帅。")
        XCTAssertTrue(point(app, "e1").exists, "the board is on the page and addressable")
        XCTAssertEqual(point(app, "e1").label, "e1 空", "and every point of it is empty")
        XCTAssertTrue(palette(app, "red", "k").exists)
        XCTAssertEqual(palette(app, "red", "k").value as? String, "1",
                       "each entry carries how many of it remain")
        XCTAssertEqual(palette(app, "red", "p").value as? String, "5")
        attach(app, named: "70-the-custom-scene-editor")

        // It is a pre-start page over the home, left by the toolbar's own back
        // control, and leaving it discards the draft.
        app.buttons["play-back"].click()
        XCTAssertTrue(app.buttons["mode-xiangqi-custom-scene"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["home-current-game"].exists,
                       "the editor created nothing")
    }

    // MARK: - Composing a scene and playing it

    /// The editor's whole flow: pieces down, Black to move, Start — and the
    /// board opens on the composed position with Black to move.
    func testComposingASceneAndStartingIt() {
        let app = launch()
        XCTAssertTrue(app.buttons["mode-xiangqi-custom-scene"].waitForExistence(timeout: 20))
        app.buttons["mode-xiangqi-custom-scene"].click()
        XCTAssertTrue(app.buttons["scene-start"].waitForExistence(timeout: 10))

        place(app, "red", "k", at: "e1")
        XCTAssertEqual(palette(app, "red", "k").value as? String, "0",
                       "the one general is on the board")
        XCTAssertFalse(app.buttons["scene-start"].isEnabled,
                       "one general is not both")

        place(app, "black", "k", at: "d10")
        place(app, "red", "r", at: "a1")
        XCTAssertEqual(point(app, "a1").label, "a1 红 俥")
        XCTAssertEqual(palette(app, "red", "r").value as? String, "1",
                       "one of the two chariots is left")
        XCTAssertTrue(app.buttons["scene-start"].isEnabled,
                      "a legal, playable position is one to start from")
        XCTAssertFalse(app.staticTexts["scene-reason"].exists,
                       "and it says nothing about a position with nothing wrong with it")

        // A tap on a piece takes it back off, and the palette gets it back.
        point(app, "a1").click()
        XCTAssertEqual(palette(app, "red", "r").value as? String, "2")
        place(app, "red", "r", at: "a1")

        app.windows.firstMatch.radioButtons["黑"].click()
        attach(app, named: "71-a-composed-scene")

        app.buttons["scene-start"].click()

        XCTAssertTrue(app.staticTexts["轮到黑方"].waitForExistence(timeout: 20),
                      "the board opens on the composed position, with Black to move")
        XCTAssertEqual(point(app, "d10").label, "d10 黑 将")
        XCTAssertEqual(point(app, "a1").label, "a1 红 俥")
        XCTAssertFalse(app.buttons["cluster-resign"].exists,
                       "a Free Play game has no opponent to resign to")
        XCTAssertTrue(app.buttons["hint-request"].exists,
                      "and the Free Play cluster is otherwise unchanged")
        XCTAssertTrue(app.buttons["cluster-undo"].exists)
        XCTAssertTrue(app.buttons["cluster-flip"].exists)
        attach(app, named: "72-the-scene-game")

        // Two plies, Black's first: the game is played from here like any other
        // Free Play game.
        point(app, "d10").click()
        point(app, "d9").click()
        XCTAssertTrue(app.staticTexts["轮到红方"].waitForExistence(timeout: 10),
                      "Black made ply 0, so the turn passed to Red")
        point(app, "a1").click()
        point(app, "a2").click()
        XCTAssertTrue(app.staticTexts["轮到黑方"].waitForExistence(timeout: 10))

        // The game is the library's active game, and the home describes it with
        // the side the core reports rather than one counted off the plies.
        app.buttons["play-back"].click()
        XCTAssertTrue(app.staticTexts["home-current-game"].waitForExistence(timeout: 10))
        XCTAssertEqual(reading(app, "home-current-game"),
                       "象棋 · 自由对弈 · 进行中 · 轮到黑方 · 2 步")

        // Filed by the accepted save-and-continue, so the record's replay is
        // reachable — and there the move list pairs from the record's own start
        // side too: Black's opening ply stands in the second column of the
        // first row, with the Red cell beside it empty, and Red's answer opens
        // the row beneath it.
        app.buttons["mode-xiangqi-free-play"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons["保存并继续"].click()
        XCTAssertTrue(app.staticTexts["setup-explanation"].waitForExistence(timeout: 10))

        destination(app, 1).click()
        XCTAssertTrue(historyRow(app, 0).waitForExistence(timeout: 10))
        historyRow(app, 0).click()

        let black = app.buttons["move-0"]
        let red = app.buttons["move-1"]
        XCTAssertTrue(black.waitForExistence(timeout: 10), "the record opens for replay")
        XCTAssertGreaterThan(black.frame.minX, red.frame.minX,
                             "the opening ply is Black's, so it sits in the Black column")
        XCTAssertLessThan(black.frame.minY, red.frame.minY,
                          "and Red's answer opens the next row rather than sharing that one")
        attach(app, named: "73-the-scene-record-replayed")
    }

    private func destination(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.windows.firstMatch.outlines.element(boundBy: 0).cells.element(boundBy: index)
    }

    private func historyRow(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.windows.firstMatch.buttons["history-row-\(index)"]
    }
}

#endif  // os(macOS)
