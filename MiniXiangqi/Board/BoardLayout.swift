// Two arrangements, side by side and stacked, chosen by the space available
// rather than by device. The choice is whichever gives the board the larger
// pitch, a tie going to side by side, which shows the move list for free. A
// width threshold cannot express it: side by side costs width and stacked
// costs height, so a short Mac window takes side by side while a wider iPad in
// portrait takes stacked.

import SwiftUI

enum BoardLayout {
    enum Shape: Equatable {
        /// The board on one side, the panel beside it.
        case sideBySide
        /// The turn status above the board, the play controls below it.
        case stacked
    }

    static let panelWidth: CGFloat = 260

    /// An allowance rather than a padding: it is taken off the space the board
    /// is fitted into, and the board is then centred in the whole. At the
    /// minimum window that is exactly 24 points on every side.
    static let boardPadding: CGFloat = 24

    static let panelInset: CGFloat = 16

    /// The concealing board's floor pitch, so a resident captured disc never
    /// draws smaller than the smallest board its piece could stand on.
    static let capturedDiscPitch: CGFloat =
        BoardGeometry.minimumPitch(for: GameKind.jieqi.board)

    /// A piece that left the board face down keeps its face partway up, so an
    /// open capture and a disclosed one never read as the same disc.
    static let capturedWasHiddenArrival: Double = 0.55

    /// What a board fitted to the sheet's width would carry, so a disc matches
    /// its size on the board where the widths agree. A wrapping surface's
    /// height never governs, so only the width is asked.
    static func capturedSheetPitch(in width: CGFloat, game: GameKind) -> CGFloat {
        let board = game.board
        let fitted = BoardGeometry.fitting(CGSize(width: width,
                                                  height: .greatestFiniteMagnitude),
                                           board: board)
            ?? BoardGeometry(board: board, pitch: BoardGeometry.minimumPitch(for: board))
        return min(fitted.pitch, BoardGeometry.maximumPitch(for: board))
    }

    /// The shape rule spends this constant, so the decision does not depend on
    /// anything on screen. The layout spends the chrome's measured height
    /// instead, because a status line at a large text size is taller and the
    /// board is what yields. At the default text size the status is 71 points
    /// and the control cluster 45.
    static let stackedChromeHeight: CGFloat = 140

    // MARK: - Choosing the shape

    /// A shape that cannot be drawn at all loses to one that can. Where neither
    /// fits, stacked is drawn: its board is bounded by the width, and a space
    /// too small for either is too narrow rather than too short.
    static func shape(in size: CGSize, game: GameKind) -> Shape {
        switch (sideBySidePitch(in: size, game: game),
                stackedPitch(in: size, game: game)) {
        case (nil, _): .stacked
        case (_, nil): .sideBySide
        case (let beside?, let above?): beside >= above ? .sideBySide : .stacked
        }
    }

    /// Nil where even the floor does not fit beside the panel.
    private static func sideBySidePitch(in size: CGSize, game: GameKind) -> CGFloat? {
        BoardGeometry.fitting(sideBySideSpace(in: size), board: game.board)
            .map { min($0.pitch, BoardGeometry.maximumPitch(for: game.board)) }
    }

    /// It spends the air beside the board, which a board screen does not, and
    /// that cannot change the answer: where the stacked candidate is bound by
    /// the width it is already the larger board. So one probe answers for a
    /// board and the pre-start page that previews it, and they never disagree.
    private static func stackedPitch(in size: CGSize, game: GameKind) -> CGFloat? {
        BoardGeometry.fitting(stackedSpace(in: size, chrome: stackedChromeHeight,
                                           air: boardPadding),
                              board: game.board)
            .map { min($0.pitch, BoardGeometry.maximumPitch(for: game.board)) }
    }

    // MARK: - Side by side

    private static func sideBySideSpace(in size: CGSize) -> CGSize {
        CGSize(width: size.width - panelWidth - 2 * boardPadding,
               height: size.height - 2 * boardPadding)
    }

    /// The largest board that fits beside the panel, between the pitch floor
    /// and ceiling.
    static func geometry(in size: CGSize, game: GameKind) -> BoardGeometry {
        let board = game.board
        let fitted = BoardGeometry.fitting(sideBySideSpace(in: size), board: board)
            ?? BoardGeometry(board: board, pitch: BoardGeometry.minimumPitch(for: board))
        return BoardGeometry(board: board,
                             pitch: min(fitted.pitch, BoardGeometry.maximumPitch(for: board)))
    }

    // MARK: - Stacked

    /// The air is a parameter because a board screen keeps none and a
    /// pre-start preview keeps the allowance.
    private static func stackedSpace(in size: CGSize, chrome: CGFloat,
                                     air: CGFloat) -> CGSize {
        CGSize(width: size.width - 2 * air,
               height: size.height - chrome - 2 * boardPadding)
    }

    /// A floor-sized board plus its air. Below it there is no smaller board to
    /// draw, only a floor-sized one drawn over whatever is beneath it.
    static func minimumBoardHeight(for game: GameKind) -> CGFloat {
        let board = game.board
        return BoardGeometry(board: board, pitch: BoardGeometry.minimumPitch(for: board))
            .blockSize.height + 2 * boardPadding
    }

    /// Granted rather than taken: `stackedGeometry` honours the board's floor
    /// whatever it is handed, so a shorter slot would draw the board over the
    /// chrome. Reserving the floor first makes the chrome what tightens.
    static func stackedChrome(in size: CGSize, game: GameKind,
                              asking wanted: CGFloat) -> CGFloat {
        max(0, min(wanted, size.height - minimumBoardHeight(for: game)))
    }

    // MARK: - The cluster's reserved slot

    /// The air the stacked shape keeps around the control cluster beneath the
    /// board, and between the cluster's two rows when it takes two.
    static let clusterAir: CGFloat = 8

    /// One row of cluster controls, until a row has been measured.
    static let clusterRowHeight: CGFloat = 29

    /// The cluster's tallest arrangement, two rows, whichever it is drawing.
    /// The board is sized around this reservation, so a row coming or going
    /// moves nothing but the air between the board and the controls. `row` is
    /// measured, as a row is as tall as the text size makes its controls.
    static func stackedCluster(row: CGFloat) -> CGFloat {
        2 * row + 3 * clusterAir
    }

    /// One row, measured hidden. Both label forms stand in it, because a row is
    /// as tall as the tallest control it can carry.
    struct ClusterRow: View {
        var report: (CGFloat) -> Void

        var body: some View {
            HStack(spacing: BoardLayout.clusterAir) {
                Button { } label: {
                    Label("control.flipBoard", systemImage: "arrow.up.arrow.down")
                        .lineLimit(1)
                }
                Button { } label: {
                    Label("control.flipBoard", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.glass)
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { report($0) }
        }
    }

    /// A board screen spends no horizontal allowance: the block takes the
    /// whole width, so a 402-point phone carries Xiangqi at pitch 44 rather than
    /// 39. `chrome` is what the chrome measured, so a status line grown by a
    /// large text size takes its room from the board.
    static func stackedGeometry(in size: CGSize, game: GameKind,
                                chrome: CGFloat = stackedChromeHeight) -> BoardGeometry {
        let board = game.board
        let fitted = BoardGeometry.fitting(stackedSpace(in: size, chrome: chrome, air: 0),
                                           board: board)
            ?? BoardGeometry(board: board, pitch: BoardGeometry.minimumPitch(for: board))
        return BoardGeometry(board: board,
                             pitch: min(fitted.pitch, BoardGeometry.maximumPitch(for: board)))
    }

    /// The surface runs to the screen edges beneath the numeral strips, so no
    /// sliver of page shows beside a board the width sized. Space beside a
    /// board bound by height or by its maximum footprint is layout air and
    /// stays unpainted. Asked of the block, not the file count, because a
    /// Go-style board's side strip makes the block wider than its core.
    static func surfaceBleed(in width: CGFloat, board: BoardGeometry) -> CGFloat {
        let larger = BoardGeometry(board: board.board, pitch: board.pitch + 1)
        guard larger.blockSize.width > width else { return 0 }
        return max(0, (width - board.blockSize.width) / 2)
    }

    // MARK: - Previews

    /// Below this a board stops being a picture of a board.
    static let previewFloorPitch: CGFloat = 18

    /// Noninteractive, so the interactive floor does not apply and the setup
    /// controls take the space they need first.
    static func previewGeometry(in size: CGSize, game: GameKind) -> BoardGeometry {
        let board = game.board
        let fitted = BoardGeometry.fitting(sideBySideSpace(in: size), board: board,
                                           floor: previewFloorPitch)
            ?? BoardGeometry(board: board, pitch: previewFloorPitch)
        return BoardGeometry(board: board,
                             pitch: min(fitted.pitch, BoardGeometry.maximumPitch(for: board)))
    }

    /// A preview keeps its air: running edge to edge between rows of setup
    /// controls, it would read as the page's header.
    static func stackedPreviewGeometry(in size: CGSize, game: GameKind,
                                       chrome: CGFloat) -> BoardGeometry {
        let board = game.board
        let fitted = BoardGeometry.fitting(stackedSpace(in: size, chrome: chrome,
                                                        air: boardPadding),
                                           board: board, floor: previewFloorPitch)
            ?? BoardGeometry(board: board, pitch: previewFloorPitch)
        return BoardGeometry(board: board,
                             pitch: min(fitted.pitch, BoardGeometry.maximumPitch(for: board)))
    }

    // MARK: - The window's floor

    /// What the content asks for; the navigation container adds its sidebar,
    /// so the window's minimum is measured on the running app. Only a resizable
    /// window uses it: on iOS the system sizes the scene.
    static var minimumWidth: CGFloat {
        GameKind.allCases.map { game in
            let board = game.board
            return BoardGeometry(board: board, pitch: BoardGeometry.minimumPitch(for: board))
                .blockSize.width
        }.max()! + panelWidth + 2 * boardPadding
    }

    /// What a window stops shrinking at is what a board block cannot be given
    /// less than.
    static var minimumHeight: CGFloat {
        GameKind.allCases.map { minimumBoardHeight(for: $0) }.max()!
    }
}
