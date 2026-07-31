// Which of the two arrangements a space takes, and what the board comes to
// inside it.
//
// docs/interaction-design.md, "Layout shapes": two arrangements chosen by the
// available space rather than by device identity, so a resized Mac window and a
// windowed iPad behave the same way as each other. `BoardLayout.shape(in:)` is
// that rule, and this is where it is held to the shapes the contract names —
// on a phone, on an iPad in both orientations, and at the accepted macOS floor,
// where the answer is load-bearing in the other direction: that floor was
// photographed and accepted as side by side, and a rule that stacked it would
// be a regression rather than an adaptation.
//
// The sizes below are the *layout* areas, not screen sizes: what the play
// screen's own GeometryReader is handed once the status bar, the navigation bar
// and the tab bar or sidebar are off. The iOS ones were read off the running
// app on the two devices this phase's evidence was taken on — an iPhone 17 Pro
// Max and an iPad Pro 11-inch — and are rounded, deliberately: a rule that only
// held at one exact pixel count would not be a rule.

import CoreGraphics
import Testing
@testable import MiniXiangqi

@Suite("Layout shapes")
@MainActor
struct BoardLayoutTests {

    // MARK: - The shapes the contract names

    @Test("A phone stacks: the panel leaves nothing that is still a board")
    func phonePortraitStacks() {
        let phone = CGSize(width: 440, height: 770)
        #expect(BoardLayout.shape(in: phone) == .stacked)
        // And what it stacks is a real board, above the accepted floor.
        #expect(BoardLayout.stackedGeometry(in: phone).pitch >= BoardGeometry.minimumPitch)
    }

    @Test("An iPad in portrait stacks: the panel would cost the board more than it returns")
    func padPortraitStacks() {
        let padPortrait = CGSize(width: 834, height: 1130)
        #expect(BoardLayout.shape(in: padPortrait) == .stacked)
        // The stacked board there is the largest the contract allows; the panel
        // beside it would have been less than two thirds of that.
        #expect(BoardLayout.stackedGeometry(in: padPortrait).pitch == BoardGeometry.maximumPitch)
        #expect(BoardLayout.geometry(in: padPortrait).pitch < BoardGeometry.maximumPitch)
    }

    @Test("An iPad in landscape goes side by side: the height is what bounds the board there")
    func padLandscapeGoesSideBySide() {
        let padLandscape = CGSize(width: 929, height: 790)
        #expect(BoardLayout.shape(in: padLandscape) == .sideBySide)
        #expect(BoardLayout.geometry(in: padLandscape).pitch
                > BoardLayout.stackedGeometry(in: padLandscape).pitch)
    }

    @Test("The accepted macOS floor stays side by side, at exactly the 44-point pitch")
    func macOSFloorStaysSideBySide() {
        // 616 by 388 is the accepted play-content floor, and the board sits
        // exactly on its own floor inside it. The stacked shape cannot be drawn
        // at that height at all, which is what settles the choice.
        let floor = CGSize(width: BoardLayout.minimumWidth, height: BoardLayout.minimumHeight)
        #expect(floor == CGSize(width: 616, height: 388))
        #expect(BoardLayout.shape(in: floor) == .sideBySide)
        #expect(BoardLayout.geometry(in: floor).pitch == BoardGeometry.minimumPitch)
    }

    @Test("An ordinary Mac window stays side by side")
    func macOSWindowStaysSideBySide() {
        // The window sizes the macOS screenshot series is taken at, less the
        // navigation container's own sidebar and toolbar.
        for size in [CGSize(width: 656, height: 508), CGSize(width: 1566, height: 998)] {
            #expect(BoardLayout.shape(in: size) == .sideBySide,
                    "\(size) is a Mac window the accepted look was photographed at")
        }
    }

    @Test("A tie goes to side by side, which costs the board nothing and shows the list")
    func aTieGoesToSideBySide() {
        // Wide enough and tall enough for both shapes to reach the ceiling.
        let ample = CGSize(width: 1200, height: 1200)
        #expect(BoardLayout.geometry(in: ample).pitch == BoardGeometry.maximumPitch)
        #expect(BoardLayout.stackedGeometry(in: ample).pitch == BoardGeometry.maximumPitch)
        #expect(BoardLayout.shape(in: ample) == .sideBySide)
    }

    @Test("A space too small for either shape is stacked, not squeezed side by side")
    func aSpaceTooSmallForEitherStacks() {
        // Neither arrangement fits a board at its floor here. The stacked one is
        // what is drawn: the space is too narrow rather than too short, and the
        // shape whose board is bounded by the width is the one that says so.
        #expect(BoardLayout.shape(in: CGSize(width: 300, height: 300)) == .stacked)
    }

    // MARK: - What the stacked shape gives the board

    @Test("The stacked board honours the same floor and ceiling as the side-by-side one")
    func stackedRespectsFloorAndCeiling() {
        let vast = CGSize(width: 4000, height: 4000)
        #expect(BoardLayout.stackedGeometry(in: vast).pitch == BoardGeometry.maximumPitch)
        // Below the floor the geometry falls back to the floor rather than to
        // something smaller: the board may not be driven below it.
        let cramped = CGSize(width: 100, height: 100)
        #expect(BoardLayout.stackedGeometry(in: cramped).pitch == BoardGeometry.minimumPitch)
    }

    @Test("Chrome grown by an accessibility text size takes its room from the board")
    func chromeTakesItsRoomFromTheBoard() {
        // A height-bound space, so the chrome is what the board is competing
        // with. Doubling the chrome cannot leave the board the same size.
        let space = CGSize(width: 1000, height: 700)
        let ordinary = BoardLayout.stackedGeometry(in: space,
                                                   chrome: BoardLayout.stackedChromeHeight)
        let grown = BoardLayout.stackedGeometry(in: space,
                                                chrome: 2 * BoardLayout.stackedChromeHeight)
        #expect(grown.pitch < ordinary.pitch)
    }

    @Test("A preview yields to the controls under it, below the interactive floor")
    func theStackedPreviewYields() {
        // The pre-start board is noninteractive and carries no size floor, so a
        // page whose controls need the room gets a smaller preview rather than
        // a clipped one.
        let space = CGSize(width: 440, height: 500)
        let preview = BoardLayout.stackedPreviewGeometry(in: space, chrome: 300)
        #expect(preview.pitch < BoardGeometry.minimumPitch)
        #expect(preview.pitch >= BoardLayout.previewFloorPitch)
    }
}
