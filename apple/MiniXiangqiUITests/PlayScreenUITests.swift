// Launches the app and plays on it.
//
// This is the only check that exercises the whole path at once: the core
// initialises from the bundled variant configuration, the position comes back
// from it, the board renders, and a move a person makes is accepted or refused
// by the core rather than by anything in Swift. The screenshots are attached to
// the test results so the screen can be looked at rather than reasoned about.

import XCTest

final class PlayScreenUITests: XCTestCase {

    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func point(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["point-\(name)"]
    }

    func testAGameCanBePlayedOnTheBoard() {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["The core did not start"].exists)
        XCTAssertFalse(app.staticTexts["The game did not start"].exists)
        XCTAssertTrue(point(app, "d1").waitForExistence(timeout: 10),
                      "the board's points should be addressable")
        attach(app, named: "1-starting-position")

        // The elements must sit over the points they name, which the labels
        // are what can say: b1 carries Red's cannon at the start position.
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮")
        XCTAssertEqual(point(app, "d7").label, "d7 黑 将")
        XCTAssertEqual(point(app, "d4").label, "d4 空")

        // Select the cannon on b1 and show its legal destinations.
        point(app, "b1").click()
        XCTAssertEqual(point(app, "b1").label, "b1 红 炮 已选择",
                       "the click must address the square it named")
        attach(app, named: "2-a-piece-selected")

        // c3 is empty and no cannon move reaches it. The core refuses it, so
        // nothing moves and the selection survives — the correction is one
        // click away.
        point(app, "c3").click()
        XCTAssertTrue(app.staticTexts["轮到红方"].exists,
                      "an illegal tap must not consume the turn")
        XCTAssertFalse(app.staticTexts["1."].exists,
                       "an illegal tap must not enter the move list")
        attach(app, named: "3-after-an-illegal-tap")

        // A legal one: the cannon runs up its own empty file. The move list is
        // what proves it happened — a turn that reads "轮到红方" reads the same
        // whether two moves were played or none, which is how an earlier
        // version of this test passed against a play() that did nothing.
        point(app, "b4").click()
        XCTAssertTrue(app.staticTexts["炮六进三"].waitForExistence(timeout: 5),
                      "the move should appear in the move list, in traditional notation")
        XCTAssertTrue(app.staticTexts["轮到黑方"].exists, "the turn should have passed to Black")
        attach(app, named: "4-after-a-move")

        // Black replies with a soldier, so the move list shows a numbered pair.
        point(app, "a6").click()
        point(app, "a5").click()
        XCTAssertTrue(app.staticTexts["卒1进1"].waitForExistence(timeout: 5),
                      "Black's reply should read in Arabic numerals")
        XCTAssertTrue(app.staticTexts["轮到红方"].exists,
                      "the turn should have come back to Red")
        attach(app, named: "5-after-black-replies")

        // Each numeral strip shows the numerals of the player it faces, so
        // both must follow the board round.
        let redStrip = app.windows.firstMatch.descendants(matching: .any)["file-numerals-red"]
        let blackStrip = app.windows.firstMatch.descendants(matching: .any)["file-numerals-black"]
        XCTAssertEqual(redStrip.label, "七 六 五 四 三 二 一")
        XCTAssertEqual(blackStrip.label, "1 2 3 4 5 6 7")

        // Turning the board round changes presentation only.
        app.buttons["翻转棋盘"].click()
        XCTAssertEqual(redStrip.label, "一 二 三 四 五 六 七",
                       "Red's numerals should follow the board round")
        XCTAssertEqual(blackStrip.label, "7 6 5 4 3 2 1",
                       "Black's numerals should follow the board round")
        // Attached after the assertions, which wait: a screenshot taken in the
        // same instant as the click can catch a half-updated frame, and a
        // screenshot that lies is worse than none.
        attach(app, named: "6-board-turned-round")
    }
}
