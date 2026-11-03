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

    @Test("A phone stacks: the panel leaves nothing that is still a board")
    func phonePortraitStacks() {
        let phone = CGSize(width: 440, height: 770)
        #expect(BoardLayout.shape(in: phone, game: mini) == .stacked)
        #expect(BoardLayout.stackedGeometry(in: phone, game: mini).pitch
                >= miniMinimumPitch)
    }

    @Test("The 402-point iPhone stacks, and replay's chrome fits inside it",
          arguments: [CGFloat(672), CGFloat(720)])
    func phone402PortraitStacks(height: CGFloat) {
        let phone = CGSize(width: 402, height: height)
        #expect(BoardLayout.shape(in: phone, game: mini) == .stacked)
        #expect(BoardLayout.stackedGeometry(in: phone, game: mini).pitch
                >= miniMinimumPitch)

        #expect(BoardLayout.stackedGeometry(in: phone, game: mini,
                                            chrome: BoardLayout.stackedChromeHeight).pitch
                > miniMinimumPitch)

        let asked: CGFloat = 69 + 200
        let chrome = BoardLayout.stackedChrome(in: phone, game: mini, asking: asked)
        #expect(chrome == asked, "the ask fits, so it is granted whole")
        #expect(chrome < phone.height - BoardLayout.minimumBoardHeight(for: mini))
        let board = BoardLayout.stackedGeometry(in: phone, game: mini, chrome: chrome)
        #expect(board.pitch > miniMinimumPitch, "the board is off its floor")
        #expect(board.blockSize.height <= phone.height - chrome)

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
        #expect(xiangqiBoard.pitch == 44,
                "the full-width fitting gives nine files the whole 402 points")
        #expect(xiangqiBoard.coreSize.height > miniBoard.coreSize.height)
        #expect(xiangqiBoard.blockSize.height <= phone.height
                - BoardLayout.stackedChromeHeight)
    }

    @Test("A stacked board screen takes the screen's width; a preview keeps its air")
    func aStackedBoardScreenTakesTheWholeWidth() {
        let phone = CGSize(width: 402, height: 720)
        let miniBoard = BoardLayout.stackedGeometry(in: phone, game: mini)
        #expect(miniBoard.pitch == 57)
        #expect(phone.width - miniBoard.blockSize.width < miniBoard.pitch,
                "what is left over is less than one cell, never a margin")

        let xiangqi = BoardLayout.stackedGeometry(in: phone, game: .xiangqi)
        #expect(xiangqi.pitch == 44)
        #expect(phone.width - xiangqi.blockSize.width < xiangqi.pitch)

        let preview = BoardLayout.stackedPreviewGeometry(
            in: phone, game: mini, chrome: BoardLayout.stackedChromeHeight)
        #expect(preview.pitch < miniBoard.pitch)
        #expect(preview.blockSize.width
                <= phone.width - 2 * BoardLayout.boardPadding)
    }

    @Test("The shape the rule picks is the shape whose drawn board is the larger")
    func theShapeRuleIsUnmovedByTheAirTheBoardScreenDoesNotSpend() {
        var wrong: [String] = []
        for game in GameKind.allCases {
            let floor = BoardGeometry.minimumPitch(for: game.board)
            for width in stride(from: CGFloat(320), through: 1600, by: 40) {
                for height in stride(from: CGFloat(400), through: 1600, by: 40) {
                    let size = CGSize(width: width, height: height)
                    let beside = BoardLayout.geometry(in: size, game: game).pitch
                    let stacked = BoardLayout.stackedGeometry(in: size, game: game).pitch
                    if beside == floor, stacked == floor { continue }
                    let larger: BoardLayout.Shape = beside >= stacked ? .sideBySide : .stacked
                    if BoardLayout.shape(in: size, game: game) != larger {
                        wrong.append("\(game) \(width)×\(height): rule says "
                                     + "\(BoardLayout.shape(in: size, game: game)), "
                                     + "beside draws \(beside) and stacked \(stacked)")
                    }
                }
            }
        }
        #expect(wrong.isEmpty, "the rule and the drawn boards disagree at: \(wrong.prefix(5))")
    }

    @Test("The board surface covers the pitch remainder, and never a real margin")
    func theSurfaceRunsToTheEdgesOnlyWhereTheWidthBinds() {
        let phone = CGSize(width: 402, height: 720)
        for game in GameKind.allCases {
            let board = BoardLayout.stackedGeometry(in: phone, game: game)
            let bleed = BoardLayout.surfaceBleed(in: phone.width, board: board)
            #expect(bleed > 0, "\(game) is bound by this phone's width")
            #expect(2 * bleed + board.blockSize.width == phone.width,
                    "and the surface meets both edges exactly")
        }

        let padPortrait = CGSize(width: 834, height: 1130)
        let capped = BoardLayout.stackedGeometry(in: padPortrait, game: mini)
        #expect(capped.pitch == miniMaximumPitch)
        #expect(BoardLayout.surfaceBleed(in: padPortrait.width, board: capped) == 0)

        let heightBound = BoardLayout.stackedGeometry(in: phone, game: mini, chrome: 269)
        #expect(heightBound.pitch < 57)
        #expect(BoardLayout.surfaceBleed(in: phone.width, board: heightBound) == 0)
    }

    @Test("Hiding the bar buys replay's board pitch, and costs its move list nothing")
    func replayGainsFromTheHiddenBarWithoutCostingTheList() {
        let replayHeader: CGFloat = 69
        let replayPanel: CGFloat = 200
        let asked = replayHeader + replayPanel
        func replay(in height: CGFloat) -> (pitch: CGFloat, panel: CGFloat) {
            let phone = CGSize(width: 402, height: height)
            let chrome = BoardLayout.stackedChrome(in: phone, game: mini, asking: asked)
            return (BoardLayout.stackedGeometry(in: phone, game: mini, chrome: chrome).pitch,
                    chrome - replayHeader)
        }
        func play(in height: CGFloat) -> CGFloat {
            BoardLayout.stackedGeometry(in: CGSize(width: 402, height: height), game: mini,
                                        chrome: BoardLayout.stackedChromeHeight).pitch
        }

        let withTheBar = replay(in: 672)
        #expect(withTheBar.pitch < play(in: 672),
                "with the bar under it, replay pays for its heavier chrome")

        let without = replay(in: 720)
        #expect(without.pitch > withTheBar.pitch,
                "and the bar's own height is pitch to replay's board")
        #expect(without.pitch == 52,
                "which is the figure the replay clause names for this phone")
        #expect(without.pitch < play(in: 720),
                "though the full-width fitting lifts play's board past it, replay's being bound by its chrome's height rather than by the width")

        #expect(withTheBar.panel == replayPanel)
        #expect(without.panel == replayPanel,
                "the list is granted its whole ask at both heights")
    }

    @Test("An iPad in portrait stacks: the panel would cost the board more than it returns")
    func padPortraitStacks() {
        let padPortrait = CGSize(width: 834, height: 1130)
        #expect(BoardLayout.shape(in: padPortrait, game: mini) == .stacked)
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

    @Test("The unified macOS floor holds every game side by side")
    func macOSFloorStaysSideBySide() {
        let floor = CGSize(width: BoardLayout.minimumWidth, height: BoardLayout.minimumHeight)
        #expect(floor == CGSize(width: 626, height: 416))
        #expect(BoardLayout.minimumBoardHeight(for: .miniXiangqi) == 388)
        #expect(BoardLayout.minimumBoardHeight(for: .xiangqi) == 416)
        #expect(BoardLayout.minimumBoardHeight(for: .gomoku15) == 361)
        for game in GameKind.allCases {
            #expect(BoardLayout.shape(in: floor, game: game) == .sideBySide)
            #expect(BoardLayout.geometry(in: floor, game: game).pitch
                    >= BoardGeometry.minimumPitch(for: game.board))
        }
        #expect(BoardLayout.geometry(in: floor, game: .gomoku15).pitch == 20,
                "the placement board is the one the floor is measured against")
    }

    @Test("An ordinary Mac window stays side by side")
    func macOSWindowStaysSideBySide() {
        for size in [CGSize(width: 656, height: 508), CGSize(width: 1566, height: 998)] {
            #expect(BoardLayout.shape(in: size, game: mini) == .sideBySide,
                    "\(size) is a Mac window the accepted look was photographed at")
        }
    }

    @Test("The boundary between the two shapes, one point of height apart")
    func theShapeBoundary() {
        #expect(BoardLayout.shape(in: CGSize(width: 656, height: 573), game: mini)
                == .sideBySide)
        #expect(BoardLayout.shape(in: CGSize(width: 656, height: 574), game: mini)
                == .stacked)
    }

    @Test("A tie goes to side by side, which costs the board nothing and shows the list")
    func aTieGoesToSideBySide() {
        let ample = CGSize(width: 1200, height: 1200)
        #expect(BoardLayout.geometry(in: ample, game: mini).pitch == miniMaximumPitch)
        #expect(BoardLayout.stackedGeometry(in: ample, game: mini).pitch
                == miniMaximumPitch)
        #expect(BoardLayout.shape(in: ample, game: mini) == .sideBySide)
    }

    @Test("A space too small for either shape is stacked, not squeezed side by side")
    func aSpaceTooSmallForEitherStacks() {
        #expect(BoardLayout.shape(in: CGSize(width: 300, height: 300), game: mini)
                == .stacked)
    }

    @Test("The stacked board honours the same floor and ceiling as the side-by-side one")
    func stackedRespectsFloorAndCeiling() {
        let vast = CGSize(width: 4000, height: 4000)
        #expect(BoardLayout.stackedGeometry(in: vast, game: mini).pitch
                == miniMaximumPitch)
        let cramped = CGSize(width: 100, height: 100)
        #expect(BoardLayout.stackedGeometry(in: cramped, game: mini).pitch
                == miniMinimumPitch)
    }

    @Test("Chrome grown by an accessibility text size takes its room from the board")
    func chromeTakesItsRoomFromTheBoard() {
        let space = CGSize(width: 1000, height: 700)
        let ordinary = BoardLayout.stackedGeometry(in: space, game: mini,
                                                   chrome: BoardLayout.stackedChromeHeight)
        let grown = BoardLayout.stackedGeometry(in: space, game: mini,
                                                chrome: 2 * BoardLayout.stackedChromeHeight)
        #expect(grown.pitch < ordinary.pitch)
    }

    @Test("The drawn board fits the slot the chrome leaves it, at every size")
    func theStackedBoardFitsItsSlot() {
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
        let window = CGSize(width: 616, height: 535)
        #expect(BoardLayout.shape(in: window, game: mini) == .stacked)
        let chrome = BoardLayout.stackedChrome(in: window, game: mini, asking: 260)
        #expect(chrome < 260, "the chrome is what tightens, not the board")
        #expect(BoardLayout.stackedGeometry(in: window, game: mini,
                                            chrome: chrome).blockSize.height
                <= window.height - chrome)
        let ample = CGSize(width: 834, height: 1130)
        #expect(BoardLayout.stackedChrome(in: ample, game: mini, asking: 260) == 260)
    }

    @Test("The cluster's slot is its tallest arrangement, whichever one is drawn")
    func theClusterSlotIsTheTallestArrangement() {
        let row: CGFloat = 34
        let air = BoardLayout.clusterAir
        let oneRow = row + 2 * air
        let twoRows = 2 * row + 3 * air

        let reserved = BoardLayout.stackedCluster(row: row)
        #expect(reserved == twoRows, "the slot is the taller of the two")
        #expect(reserved > oneRow, "and the shorter one is drawn inside it")

        let phone = CGSize(width: 402, height: 720)
        let chrome = BoardLayout.stackedChrome(in: phone, game: mini, asking: reserved)
        #expect(chrome == reserved, "the slot fits, so it is granted whole")
        let board = BoardLayout.stackedGeometry(in: phone, game: mini, chrome: chrome)
        #expect(board.pitch > miniMinimumPitch, "with the board well off its floor")
        #expect(board.blockSize.height <= phone.height - chrome)

        let short = CGSize(width: 402, height: 480)
        let outsized = BoardLayout.stackedCluster(row: 120)
        let tightened = BoardLayout.stackedChrome(in: short, game: mini, asking: outsized)
        #expect(tightened < outsized, "the chrome is what tightens, not the board")
        let floored = BoardLayout.stackedGeometry(in: short, game: mini, chrome: tightened)
        #expect(floored.pitch == miniMinimumPitch)
        #expect(floored.blockSize.height <= short.height - tightened)
    }

    @Test("A preview yields to the controls under it, below the interactive floor")
    func theStackedPreviewYields() {
        let space = CGSize(width: 440, height: 500)
        let preview = BoardLayout.stackedPreviewGeometry(in: space, game: mini,
                                                         chrome: 300)
        #expect(preview.pitch < miniMinimumPitch)
        #expect(preview.pitch >= BoardLayout.previewFloorPitch)
    }
}
