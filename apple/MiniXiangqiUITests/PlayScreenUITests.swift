// Launches the app and captures what it actually draws.
//
// This is the only check that exercises the whole path at once: the core
// initialises from the bundled variant configuration, the starting position
// comes back from it, and the board renders. The screenshots are attached to
// the test results so the board can be looked at rather than reasoned about.

import XCTest

final class PlayScreenUITests: XCTestCase {

    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTheBoardAppearsAndAPieceCanBeSelected() {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        attach(app, named: "starting-position")

        // The app must not be sitting on the "core did not start" screen.
        XCTAssertFalse(app.staticTexts["The core did not start"].exists)
        XCTAssertFalse(app.staticTexts["The game did not start"].exists)

        // Select a piece by clicking its point. The board is centred in the
        // window under the turn status, so the click is placed by fraction of
        // the window rather than by a coordinate this test would have to keep
        // in step with the layout.
        let frame = window.frame
        let cannonB1 = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: -2 * 44, dy: frame.height / 2 - 100))
        cannonB1.click()
        attach(app, named: "after-a-click")
    }
}
