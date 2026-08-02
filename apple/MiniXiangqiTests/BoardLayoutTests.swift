// Which of the two arrangements a space takes, and what the board comes to
// inside it.
//
// docs/interaction-design.md, "Layout shapes": two arrangements chosen by the
// available space rather than by device identity, so a resized Mac window and a
// windowed iPad behave the same way as each other. `BoardLayout.shape(in:game:)` is
// that rule, and this is where it is held to the shapes the contract names —
// on a phone, on an iPad in both orientations, and at the accepted macOS floor,
// where the answer is load-bearing in the other direction: that floor was
// photographed and accepted as side by side, and a rule that stacked it would
// be a regression rather than an adaptation.
//
// The sizes below are the *layout* areas, not screen sizes: what a screen's own
// GeometryReader is handed once the status bar, the navigation bar, and
// whatever the navigation container is showing are off. The iOS ones were read
// off the running app on the two devices this phase's evidence was taken on —
// an iPhone 17 Pro Max and an iPad Pro 11-inch — and are rounded, deliberately:
// a rule that only held at one exact pixel count would not be a rule.
//
// On a phone that last term is now **two** numbers rather than one, because
// docs/interaction-design.md § Navigation has the two board screens hide the
// destination bar: a home is handed the shorter area and a board screen the
// taller one, the difference being the bar's own height. The 402-point phone
// below is pinned at both.

import CoreGraphics
import Testing
@testable import MiniXiangqi

@Suite("Layout shapes")
@MainActor
struct BoardLayoutTests {
    private let mini = GameKind.miniXiangqi

    private var miniMinimumPitch: CGFloat {
        BoardGeometry.minimumPitch(for: mini.board)
    }

    private var miniMaximumPitch: CGFloat {
        BoardGeometry.maximumPitch(for: mini.board)
    }

    // MARK: - The shapes the contract names

    @Test("A phone stacks: the panel leaves nothing that is still a board")
    func phonePortraitStacks() {
        let phone = CGSize(width: 440, height: 770)
        #expect(BoardLayout.shape(in: phone, game: mini) == .stacked)
        // And what it stacks is a real board, above the accepted floor.
        #expect(BoardLayout.stackedGeometry(in: phone, game: mini).pitch
                >= miniMinimumPitch)
    }

    /// The narrower phone the device policy actually names, and the one every
    /// screenshot in this campaign is taken on.
    ///
    /// 402 is the screen's width. The two heights are what is left of 874 once
    /// the status bar and the navigation bar are off — **672** with the
    /// destination bar under them as well, which is what the homes have and
    /// what every board screen had before § Navigation's board-screen rule, and
    /// **720** without it, which is what the board and replay have now. Both are
    /// rounded stand-ins rather than the device's exact figures — measured on
    /// the running app the areas come to 675 and 724 — and rounded deliberately,
    /// for the reason at the top of this file: a rule that only held at one
    /// exact pixel count would not be a rule. What is asserted below therefore
    /// holds either side of those few points, and it is asserted at *both*
    /// heights because the rule has to hold at both.
    ///
    /// The pitch each shape actually draws stays a rendered number and lives
    /// with the pictures, not here — with the one exception at the end, which is
    /// a relation between the two screens rather than a size.
    ///
    /// It is the tighter of the two phones in both directions, so it is where
    /// the stacked shape's floors are reached first.
    @Test("The 402-point iPhone stacks, and replay's chrome fits inside it",
          arguments: [CGFloat(672), CGFloat(720)])
    func phone402PortraitStacks(height: CGFloat) {
        let phone = CGSize(width: 402, height: height)
        #expect(BoardLayout.shape(in: phone, game: mini) == .stacked)
        #expect(BoardLayout.stackedGeometry(in: phone, game: mini).pitch
                >= miniMinimumPitch)

        // Play's chrome leaves the board well clear of its floor: this phone is
        // not a phone that draws floor-sized boards.
        #expect(BoardLayout.stackedGeometry(in: phone, game: mini,
                                            chrome: BoardLayout.stackedChromeHeight).pitch
                > miniMinimumPitch)

        // Replay's chrome is the header above the board plus the panel beneath
        // it. Asking for the whole of the panel's side-by-side height put that
        // sum past what this phone has once a floor-sized board is reserved, and
        // pinned the board on its floor; the owner's buy-back (2026-07-31)
        // brought the ask under that line, so the phone grants it whole and the
        // board it leaves stands clear of the floor rather than on it.
        //
        // The header's measured height is written into the sum for honesty
        // rather than for arithmetic: what is asserted is the relation between
        // the ask, the grant and the floor, not either number.
        let asked: CGFloat = 69 + 200
        let chrome = BoardLayout.stackedChrome(in: phone, game: mini, asking: asked)
        #expect(chrome == asked, "the ask fits, so it is granted whole")
        #expect(chrome < phone.height - BoardLayout.minimumBoardHeight(for: mini))
        let board = BoardLayout.stackedGeometry(in: phone, game: mini, chrome: chrome)
        #expect(board.pitch > miniMinimumPitch, "the board is off its floor")
        #expect(board.blockSize.height <= phone.height - chrome)

        // The grant still tightens where the space really is short — a header
        // grown by an accessibility text size is the case it exists for. There
        // the chrome yields, the board stands exactly on its floor, and the
        // block still fits the slot it is left.
        let outsized: CGFloat = 200 + 200
        let tightened = BoardLayout.stackedChrome(in: phone, game: mini,
                                                  asking: outsized)
        #expect(tightened < outsized, "the chrome is what tightens, not the board")
        #expect(tightened == phone.height - BoardLayout.minimumBoardHeight(for: mini))
        let floored = BoardLayout.stackedGeometry(in: phone, game: mini,
                                                  chrome: tightened)
        #expect(floored.pitch == miniMinimumPitch)
        #expect(floored.blockSize.height <= phone.height - tightened)
    }

    @Test("Xiangqi keeps Mini Xiangqi's width footprint and uses the extra height")
    func xiangqiKeepsTheWidthFootprint() {
        let phone = CGSize(width: 402, height: 720)
        let miniBoard = BoardLayout.stackedGeometry(in: phone, game: .miniXiangqi)
        let xiangqiBoard = BoardLayout.stackedGeometry(in: phone, game: .xiangqi)

        #expect(BoardLayout.shape(in: phone, game: .xiangqi) == .stacked)
        #expect(abs(miniBoard.coreSize.width - xiangqiBoard.coreSize.width) <= 3)
        #expect(xiangqiBoard.pitch == 39)
        #expect(xiangqiBoard.coreSize.height > miniBoard.coreSize.height)
        #expect(xiangqiBoard.blockSize.height <= phone.height
                - BoardLayout.stackedChromeHeight)
    }

    /// What hiding the destination bar bought this phone, stated as the relation
    /// it is rather than as the pitch it comes to.
    ///
    /// Replay's chrome is more than twice play's, so on the shorter area
    /// replay's board was the smaller of the two: its height was what bound it.
    /// The bar's own height is exactly what stops that being true — on the
    /// taller area **both** boards run out of *width* first, so replay draws the
    /// same board play does. That is the whole of what the change gives this
    /// screen, and it is also why the move list gains nothing: what the board
    /// cannot use, nothing else on the page is asking for.
    @Test("Hiding the bar makes replay's board the size play's is, not merely nearer")
    func replayReachesPlaysBoardOnceTheBarIsHidden() {
        let replayChrome: CGFloat = 69 + 200
        func boards(in height: CGFloat) -> (play: CGFloat, replay: CGFloat) {
            let phone = CGSize(width: 402, height: height)
            return (BoardLayout.stackedGeometry(in: phone, game: mini,
                                                chrome: BoardLayout.stackedChromeHeight).pitch,
                    BoardLayout.stackedGeometry(
                        in: phone, game: mini,
                        chrome: BoardLayout.stackedChrome(in: phone, game: mini,
                                                         asking: replayChrome)).pitch)
        }

        let withTheBar = boards(in: 672)
        #expect(withTheBar.replay < withTheBar.play,
                "with the bar under it, replay pays for its heavier chrome")

        let without = boards(in: 720)
        #expect(without.replay == without.play,
                "without it, both boards are bound by the phone's width instead")
    }

    @Test("An iPad in portrait stacks: the panel would cost the board more than it returns")
    func padPortraitStacks() {
        let padPortrait = CGSize(width: 834, height: 1130)
        #expect(BoardLayout.shape(in: padPortrait, game: mini) == .stacked)
        // The stacked board there is the largest the contract allows; the panel
        // beside it would have been less than two thirds of that.
        #expect(BoardLayout.stackedGeometry(in: padPortrait, game: mini).pitch
                == miniMaximumPitch)
        #expect(BoardLayout.geometry(in: padPortrait, game: mini).pitch
                < miniMaximumPitch)
    }

    @Test("An iPad in landscape goes side by side: the height is what bounds the board there")
    func padLandscapeGoesSideBySide() {
        let padLandscape = CGSize(width: 929, height: 790)
        #expect(BoardLayout.shape(in: padLandscape, game: mini) == .sideBySide)
        #expect(BoardLayout.geometry(in: padLandscape, game: mini).pitch
                > BoardLayout.stackedGeometry(in: padLandscape, game: mini).pitch)
    }

    @Test("Xiangqi uses the same adaptive shapes on iPad")
    func xiangqiUsesTheAdaptiveShapes() {
        #expect(BoardLayout.shape(in: CGSize(width: 834, height: 1130),
                                  game: .xiangqi) == .stacked)
        #expect(BoardLayout.shape(in: CGSize(width: 929, height: 790),
                                  game: .xiangqi) == .sideBySide)
    }

    @Test("The unified macOS floor holds either game side by side")
    func macOSFloorStaysSideBySide() {
        // The width is Mini Xiangqi's existing side-by-side floor; Xiangqi's
        // taller floor sets the shared height. Either game can therefore be
        // switched in without changing the window's minimum.
        let floor = CGSize(width: BoardLayout.minimumWidth, height: BoardLayout.minimumHeight)
        #expect(floor == CGSize(width: 616, height: 416))
        #expect(BoardLayout.minimumBoardHeight(for: .miniXiangqi) == 388)
        #expect(BoardLayout.minimumBoardHeight(for: .xiangqi) == 416)
        for game in GameKind.allCases {
            #expect(BoardLayout.shape(in: floor, game: game) == .sideBySide)
            #expect(BoardLayout.geometry(in: floor, game: game).pitch
                    == BoardGeometry.minimumPitch(for: game.board))
        }
    }

    @Test("An ordinary Mac window stays side by side")
    func macOSWindowStaysSideBySide() {
        // The window sizes the macOS screenshot series is taken at, less the
        // navigation container's own sidebar and toolbar.
        for size in [CGSize(width: 656, height: 508), CGSize(width: 1566, height: 998)] {
            #expect(BoardLayout.shape(in: size, game: mini) == .sideBySide,
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
        #expect(BoardLayout.shape(in: CGSize(width: 656, height: 573), game: mini)
                == .sideBySide)
        #expect(BoardLayout.shape(in: CGSize(width: 656, height: 574), game: mini)
                == .stacked)
    }

    @Test("A tie goes to side by side, which costs the board nothing and shows the list")
    func aTieGoesToSideBySide() {
        // Wide enough and tall enough for both shapes to reach the ceiling.
        let ample = CGSize(width: 1200, height: 1200)
        #expect(BoardLayout.geometry(in: ample, game: mini).pitch == miniMaximumPitch)
        #expect(BoardLayout.stackedGeometry(in: ample, game: mini).pitch
                == miniMaximumPitch)
        #expect(BoardLayout.shape(in: ample, game: mini) == .sideBySide)
    }

    @Test("A space too small for either shape is stacked, not squeezed side by side")
    func aSpaceTooSmallForEitherStacks() {
        // Neither arrangement fits a board at its floor here. The stacked one is
        // what is drawn: the space is too narrow rather than too short, and the
        // shape whose board is bounded by the width is the one that says so.
        #expect(BoardLayout.shape(in: CGSize(width: 300, height: 300), game: mini)
                == .stacked)
    }

    // MARK: - What the stacked shape gives the board

    @Test("The stacked board honours the same floor and ceiling as the side-by-side one")
    func stackedRespectsFloorAndCeiling() {
        let vast = CGSize(width: 4000, height: 4000)
        #expect(BoardLayout.stackedGeometry(in: vast, game: mini).pitch
                == miniMaximumPitch)
        // Below the floor the geometry falls back to the floor rather than to
        // something smaller: the board may not be driven below it.
        let cramped = CGSize(width: 100, height: 100)
        #expect(BoardLayout.stackedGeometry(in: cramped, game: mini).pitch
                == miniMinimumPitch)
    }

    @Test("Chrome grown by an accessibility text size takes its room from the board")
    func chromeTakesItsRoomFromTheBoard() {
        // A height-bound space, so the chrome is what the board is competing
        // with. Doubling the chrome cannot leave the board the same size.
        let space = CGSize(width: 1000, height: 700)
        let ordinary = BoardLayout.stackedGeometry(in: space, game: mini,
                                                   chrome: BoardLayout.stackedChromeHeight)
        let grown = BoardLayout.stackedGeometry(in: space, game: mini,
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
        for game in GameKind.allCases {
            for width in widths {
                for height in stride(from: BoardLayout.minimumBoardHeight(for: game),
                                     through: 1400, by: 1) {
                    let size = CGSize(width: width, height: height)
                    for wanted in asking {
                        let chrome = BoardLayout.stackedChrome(in: size, game: game,
                                                               asking: wanted)
                        let block = BoardLayout.stackedGeometry(in: size, game: game,
                                                                chrome: chrome)
                            .blockSize.height
                        if block > size.height - chrome {
                            overflowing.append("\(game) \(width)×\(height) asking \(wanted): "
                                               + "\(block) drawn into \(size.height - chrome)")
                        }
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
        #expect(BoardLayout.shape(in: window, game: mini) == .stacked)
        let chrome = BoardLayout.stackedChrome(in: window, game: mini, asking: 260)
        #expect(chrome < 260, "the chrome is what tightens, not the board")
        #expect(BoardLayout.stackedGeometry(in: window, game: mini,
                                            chrome: chrome).blockSize.height
                <= window.height - chrome)
        // And where there is room for both, the chrome asks and receives.
        let ample = CGSize(width: 834, height: 1130)
        #expect(BoardLayout.stackedChrome(in: ample, game: mini, asking: 260) == 260)
    }

    @Test("A preview yields to the controls under it, below the interactive floor")
    func theStackedPreviewYields() {
        // The pre-start board is noninteractive and carries no size floor, so a
        // page whose controls need the room gets a smaller preview rather than
        // a clipped one.
        let space = CGSize(width: 440, height: 500)
        let preview = BoardLayout.stackedPreviewGeometry(in: space, game: mini,
                                                         chrome: 300)
        #expect(preview.pitch < miniMinimumPitch)
        #expect(preview.pitch >= BoardLayout.previewFloorPitch)
    }
}
