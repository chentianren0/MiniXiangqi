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

    /// The narrower phone the device policy actually names, and the one every
    /// screenshot in this campaign is taken on.
    ///
    /// 402 by 672 is roughly what an iPhone 17 hands a screen's own
    /// GeometryReader: 402 points of screen width, and what is left of 874 once
    /// the status bar, the navigation bar and the tab bar are off. It is a
    /// rounded stand-in rather than the device's exact figure — measuring the
    /// running app against the rendered board puts the height a couple of points
    /// higher — and rounded deliberately, for the reason at the top of this
    /// file: a rule that only held at one exact pixel count would not be a rule.
    /// What is asserted below therefore holds either side of that couple of
    /// points; the pitch each shape actually draws is a rendered number and
    /// lives with the pictures, not here.
    ///
    /// It is the tighter of the two phones in both directions, so it is where
    /// the stacked shape's floors are reached first.
    @Test("The 402-point iPhone stacks, and replay's chrome now fits inside it")
    func phone402PortraitStacks() {
        let phone = CGSize(width: 402, height: 672)
        #expect(BoardLayout.shape(in: phone) == .stacked)
        #expect(BoardLayout.stackedGeometry(in: phone).pitch >= BoardGeometry.minimumPitch)

        // Play's chrome leaves the board well clear of its floor: this phone is
        // not a phone that draws floor-sized boards.
        #expect(BoardLayout.stackedGeometry(in: phone,
                                            chrome: BoardLayout.stackedChromeHeight).pitch
                > BoardGeometry.minimumPitch)

        // Replay's chrome is the header above the board plus the panel beneath
        // it. Asking for the whole of the panel's side-by-side height put that
        // sum past what this phone has once a floor-sized board is reserved, and
        // pinned the board on its floor; the owner's buy-back (2026-07-31)
        // brought the ask under that line, so the phone now grants it whole and
        // the board it leaves stands clear of the floor rather than on it.
        //
        // The header's measured height is written into the sum for honesty
        // rather than for arithmetic: what is asserted is the relation between
        // the ask, the grant and the floor, not either number.
        let asked: CGFloat = 69 + 200
        let chrome = BoardLayout.stackedChrome(in: phone, asking: asked)
        #expect(chrome == asked, "the ask fits, so it is granted whole")
        #expect(chrome < phone.height - BoardLayout.minimumBoardHeight)
        let board = BoardLayout.stackedGeometry(in: phone, chrome: chrome)
        #expect(board.pitch > BoardGeometry.minimumPitch, "the board is off its floor")
        #expect(board.blockSize.height <= phone.height - chrome)

        // The grant still tightens where the space really is short — a header
        // grown by an accessibility text size is the case it exists for. There
        // the chrome yields, the board stands exactly on its floor, and the
        // block still fits the slot it is left.
        let outsized: CGFloat = 200 + 200
        let tightened = BoardLayout.stackedChrome(in: phone, asking: outsized)
        #expect(tightened < outsized, "the chrome is what tightens, not the board")
        #expect(tightened == phone.height - BoardLayout.minimumBoardHeight)
        let floored = BoardLayout.stackedGeometry(in: phone, chrome: tightened)
        #expect(floored.pitch == BoardGeometry.minimumPitch)
        #expect(floored.blockSize.height <= phone.height - tightened)
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

    @Test("The boundary between the two shapes, one point of height apart")
    func theShapeBoundary() {
        // What the two tests above cannot say: where the answer changes. Both
        // of them name a size and assert the shape it takes, so between them
        // lies a region neither describes; this is the one place in that
        // region where a change to the rule shows up as a changed answer.
        //
        // 656 points of content width holds the side-by-side board to 49 —
        // it is bound by the width there, so no extra height helps it — while
        // one more point of height is exactly what buys the stacked board a
        // 50th, and 50 beats 49.
        #expect(BoardLayout.shape(in: CGSize(width: 656, height: 573)) == .sideBySide)
        #expect(BoardLayout.shape(in: CGSize(width: 656, height: 574)) == .stacked)
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

    // MARK: - The board fits the slot it is given

    @Test("The drawn board fits the slot the chrome leaves it, at every size")
    func theStackedBoardFitsItsSlot() {
        // The one invariant a stacked screen depends on, swept rather than
        // sampled at the sizes that happen to have been photographed. The
        // board's floor means `stackedGeometry` can return a block larger than
        // the space it was asked about; what makes that safe is that the
        // chrome is *granted* its height rather than taking it, so the slot
        // the board is left is never smaller than the block it draws.
        //
        // Every width a screen or window reaches, against every height from a
        // floor-sized board up.
        let widths: [CGFloat] = [320, 402, 440, 616, 656, 676, 744, 834, 1024, 1210, 1566]
        let asking: [CGFloat] = [0, 116, 140, 260, 400]
        var overflowing: [String] = []
        for width in widths {
            for height in stride(from: BoardLayout.minimumBoardHeight, through: 1400, by: 1) {
                let size = CGSize(width: width, height: height)
                for wanted in asking {
                    let chrome = BoardLayout.stackedChrome(in: size, asking: wanted)
                    let block = BoardLayout.stackedGeometry(in: size, chrome: chrome)
                        .blockSize.height
                    if block > size.height - chrome {
                        overflowing.append("\(width)×\(height) asking \(wanted): "
                                           + "\(block) drawn into \(size.height - chrome)")
                    }
                }
            }
        }
        #expect(overflowing.isEmpty,
                "the board is drawn over the chrome at: \(overflowing.prefix(5))")
    }

    @Test("The chrome yields where the board's floor needs the height, and the board fits")
    func theStackedChromeYieldsToTheBoardsFloor() {
        // 616 by 535 is the narrowest ordinary Mac window that takes the
        // stacked shape, and replay's panel is a fixed 260-point block of
        // chrome. Taken whole it would leave the board 275 points to draw a
        // block that cannot go below 340 — 65 points of board over the panel
        // and off the bottom of the window.
        let window = CGSize(width: 616, height: 535)
        #expect(BoardLayout.shape(in: window) == .stacked)
        let chrome = BoardLayout.stackedChrome(in: window, asking: 260)
        #expect(chrome < 260, "the chrome is what tightens, not the board")
        #expect(BoardLayout.stackedGeometry(in: window, chrome: chrome).blockSize.height
                <= window.height - chrome)
        // And where there is room for both, the chrome asks and receives.
        let ample = CGSize(width: 834, height: 1130)
        #expect(BoardLayout.stackedChrome(in: ample, asking: 260) == 260)
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
