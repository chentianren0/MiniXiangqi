// The two arrangements' measurements, and the rule that chooses between them.
//
// docs/interaction-design.md, "Layout shapes": two arrangements cover every
// device and window size — **side by side**, the board with a panel beside it
// carrying the turn status, the move list and the controls; and **stacked**,
// the turn status above the board and the play controls below it. They are
// chosen by the available *space* rather than by device identity, so a resized
// Mac window and a windowed iPad behave the same way as each other.
//
// **The choice is which arrangement gives the board more.** Both shapes fit the
// same board block into the same rectangle and differ only in what they take out of
// it first: side by side takes 260 points of width, stacked takes the chrome's
// height. Whichever leaves the larger board wins, and a tie goes to side by
// side, which costs the board nothing and shows the move list for free.
//
// That rule is the contract's own reasoning applied to real screens, and it is
// what a width threshold alone cannot express. The two shapes' costs are on
// different axes, so the crossover is not at a width: the accepted macOS
// minimum window is bound by its *height* and takes side by side there, while
// an iPad in portrait is bound by nothing and takes stacked at more than twice
// that width. One number would have to be both below 626 and above 834.
//
// Play settled the side-by-side numbers against a rendered screen; replay is
// the same shape with a different panel in it, and a second copy of the numbers
// is a second thing to keep in step.

import SwiftUI

enum BoardLayout {
    /// The two arrangements the contract accepts.
    enum Shape: Equatable {
        /// The board on one side, the panel beside it.
        case sideBySide
        /// The turn status above the board, the play controls below it.
        case stacked
    }

    static let panelWidth: CGFloat = 260

    /// The air around the board, and an allowance rather than a padding: it is
    /// taken off the space the board is fitted into, and the board is then
    /// centred in the whole of it. At the minimum window that comes to exactly
    /// 24 points on every side, which is what the number is chosen for. Above
    /// the minimum the centring hands the board more than 24, and that is
    /// accepted — the surplus a window has beyond the board it can carry
    /// belongs around the board rather than inside it.
    static let boardPadding: CGFloat = 24

    /// The panel's sections read down one edge, so they begin on one edge: this
    /// far in from the panel's own.
    static let panelInset: CGFloat = 16

    /// The cell one captured disc occupies. A pitch, like every other dimension
    /// a disc is drawn from, so the same routine that draws a board's piece
    /// draws this one at the size this surface can spare — small enough that a
    /// side's whole complement wraps into a panel's width, large enough that the
    /// character on it is read rather than guessed at. It is a visual specific
    /// docs/interaction-design.md leaves to a rendered board, and this is the
    /// value that stands until the board says otherwise.
    static let capturedDiscPitch: CGFloat = 26

    /// What the captured-pieces surface is granted where it is a resident
    /// section of a panel the move list shares — replay's, beside the board.
    /// Two rows of discs with their labels; a side that has lost more than one
    /// row's worth scrolls inside the grant rather than taking the room the
    /// list is standing in.
    static let capturedSurfaceHeight: CGFloat = 96

    /// What the stacked shape's chrome asks for: the turn status above the
    /// board and the play controls below it, together.
    ///
    /// It is the stacked shape's counterpart to `panelWidth`, and it is used
    /// two ways. The rule below spends it to decide the shape, where a constant
    /// is what makes the decision independent of anything on screen. The layout
    /// itself spends the chrome's *measured* height instead, because a status
    /// line at an accessibility text size is taller than this and the board is
    /// what yields — the contract's "chrome tightens before the board does" has
    /// a floor at both ends, and this is the chrome's. Measured on the running
    /// app at the default text size, where the status comes to 71 and the
    /// control cluster to 45, with the air between them inside the board's own
    /// padding.
    static let stackedChromeHeight: CGFloat = 140

    // MARK: - Choosing the shape

    /// Which arrangement a space of this size takes: whichever gives the board
    /// more, with a tie going to side by side.
    ///
    /// A shape that cannot be drawn at all — the phone, where 260 points of
    /// panel leaves nothing like a board, and the minimum Mac window, where the
    /// chrome's height leaves nothing like one — loses to the shape that can.
    /// Where neither fits, the stacked shape is what is drawn: it is the one
    /// whose board is bounded by the width, and a space too small for either is
    /// a space too narrow rather than too short.
    static func shape(in size: CGSize, game: GameKind) -> Shape {
        switch (sideBySidePitch(in: size, game: game),
                stackedPitch(in: size, game: game)) {
        case (nil, _): .stacked
        case (_, nil): .sideBySide
        case (let beside?, let above?): beside >= above ? .sideBySide : .stacked
        }
    }

    /// The largest pitch the side-by-side shape can draw here, or nil where
    /// even the accepted floor does not fit beside the panel.
    private static func sideBySidePitch(in size: CGSize, game: GameKind) -> CGFloat? {
        BoardGeometry.fitting(sideBySideSpace(in: size), board: game.board)
            .map { min($0.pitch, BoardGeometry.maximumPitch(for: game.board)) }
    }

    /// The same, for the stacked shape, spending the chrome allowance rather
    /// than the panel's width.
    ///
    /// It spends the air beside the board as well, which a drawn board screen
    /// does not — see `stackedGeometry` — and **that cannot change the answer**.
    /// Where the stacked candidate is bound by the width, it is already the
    /// larger board by construction: it is fitted into the same width less 48
    /// points where the side-by-side candidate is fitted into that width less
    /// the panel as well, so the rule has chosen stacked before any air is
    /// argued about. Side by side therefore wins only where the stacked
    /// candidate is bound by its height or standing at its maximum footprint,
    /// and neither of those moves when the air beside the board does. What is
    /// left is one probe answering for every page in the shape, which is what a
    /// board and the pre-start page that previews it need in order not to
    /// disagree about which shape they are in.
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

    /// The largest board that fits beside the panel, bounded by the accepted
    /// floor and ceiling.
    static func geometry(in size: CGSize, game: GameKind) -> BoardGeometry {
        let board = game.board
        let fitted = BoardGeometry.fitting(sideBySideSpace(in: size), board: board)
            ?? BoardGeometry(board: board, pitch: BoardGeometry.minimumPitch(for: board))
        return BoardGeometry(board: board,
                             pitch: min(fitted.pitch, BoardGeometry.maximumPitch(for: board)))
    }

    // MARK: - Stacked

    /// The rectangle a stacked board is fitted into: the width less whatever
    /// air is kept beside it, and the height less the chrome and its own
    /// allowance.
    ///
    /// The air is a parameter because the two things drawn in this shape
    /// answer it differently — a board screen keeps none and a pre-start
    /// preview keeps the allowance — and that difference belongs here rather
    /// than at the call sites, so that every caller of the same kind gets the
    /// same answer without knowing the arithmetic.
    private static func stackedSpace(in size: CGSize, chrome: CGFloat,
                                     air: CGFloat) -> CGSize {
        CGSize(width: size.width - 2 * air,
               height: size.height - chrome - 2 * boardPadding)
    }

    /// The least height a board block can be handed, its air included: a
    /// floor-sized board plus the allowance around it.
    ///
    /// It is the same quantity a resizable window's own height floor is, and
    /// for the same reason — below it there is no smaller board to draw, only
    /// a floor-sized one drawn over whatever is beneath it.
    static func minimumBoardHeight(for game: GameKind) -> CGFloat {
        let board = game.board
        return BoardGeometry(board: board, pitch: BoardGeometry.minimumPitch(for: board))
            .blockSize.height + 2 * boardPadding
    }

    /// What the stacked shape *grants* chrome asking for `wanted` points of
    /// height beneath the board.
    ///
    /// Granted rather than taken, and this is the mechanism that keeps the
    /// board inside the space it is drawn in. `stackedGeometry` honours the
    /// board's floor whatever it is handed, so a slot shorter than that floor
    /// does not produce a smaller board — it produces a board drawn over the
    /// chrome and off the bottom of the screen. Reserving the floor here,
    /// before the chrome is given anything, is what makes that impossible:
    /// above it the chrome gets what it asks for, and below it the chrome is
    /// what tightens, which is the contract's own order.
    ///
    /// Only a space shorter than a floor-sized board leaves the board larger
    /// than its slot, and no division of such a space avoids that. A window
    /// that reaches this shape is never that short.
    static func stackedChrome(in size: CGSize, game: GameKind,
                              asking wanted: CGFloat) -> CGFloat {
        max(0, min(wanted, size.height - minimumBoardHeight(for: game)))
    }

    // MARK: - The cluster's reserved slot

    /// The air the stacked shape keeps around the control cluster beneath the
    /// board, and between the cluster's two rows when it takes two.
    static let clusterAir: CGFloat = 8

    /// One row of cluster controls, until a row has been measured. The
    /// cluster's own share of the allowance above, less that air.
    static let clusterRowHeight: CGFloat = 29

    /// What the stacked shape reserves for the control cluster beneath the
    /// board: the cluster's **tallest** arrangement, whichever one it is
    /// drawing.
    ///
    /// docs/interaction-design.md, "Layout shapes": in this shape the board's
    /// frame does not follow the controls. The cluster is one row or two — the
    /// words wrap beneath, or the symbols do — and which it is changes with the
    /// scene the game is in, with the text size and with the width. The board is
    /// sized and centred around this reservation rather than around the
    /// arrangement on screen, so a row coming or going moves nothing but the air
    /// between the board and the controls. Two rows, with air above the cluster,
    /// between its rows, and below it.
    ///
    /// `row` is one row's own height, measured rather than assumed: a row is as
    /// tall as the reader's text size makes its controls.
    static func stackedCluster(row: CGFloat) -> CGFloat {
        2 * row + 3 * clusterAir
    }

    /// One row of the cluster, measured where it cannot be seen: what the
    /// reservation above is two of.
    ///
    /// A row is as tall as the tallest control it can carry, so both label
    /// forms stand in it — a row that has given up its words is a row of
    /// symbols, and which form is drawn is the arrangement's answer rather than
    /// the reservation's. It carries no identifier and nothing a screen reader
    /// can reach: it is a measurement, and there is only one of every control on
    /// this screen.
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

    /// The largest board a stacked **board screen** fits into the height its
    /// chrome leaves, bounded by the same floor and ceiling — and into the
    /// whole of the width.
    ///
    /// docs/interaction-design.md, "Layout shapes": the shape spends no
    /// horizontal allowance on a board screen. The block takes the screen's
    /// width, the whole-point pitch leaves a few points of remainder at most,
    /// and the air the allowance held moves above and below the board, where
    /// the height is. It is what this shape exists to buy: a 402-point phone
    /// carries Xiangqi at pitch 44 rather than 39. Where something other than
    /// the width binds the board — an iPad's capped footprint, a short window —
    /// nothing changes, because there the width was never what was short.
    ///
    /// `chrome` is what the chrome actually came to, so a status line grown by
    /// an accessibility text size takes its room from the board rather than
    /// overflowing the screen.
    static func stackedGeometry(in size: CGSize, game: GameKind,
                                chrome: CGFloat = stackedChromeHeight) -> BoardGeometry {
        let board = game.board
        let fitted = BoardGeometry.fitting(stackedSpace(in: size, chrome: chrome, air: 0),
                                           board: board)
            ?? BoardGeometry(board: board, pitch: BoardGeometry.minimumPitch(for: board))
        return BoardGeometry(board: board,
                             pitch: min(fitted.pitch, BoardGeometry.maximumPitch(for: board)))
    }

    /// How far the style's board surface runs past the block on each side of a
    /// stacked board screen.
    ///
    /// docs/interaction-design.md, "Layout shapes": the surface runs to the
    /// screen edges beneath the numeral strips, so the board meets the glass
    /// without a sliver of page beside it. What a whole-point pitch cannot
    /// spend is a few points — a 402-point phone leaves Xiangqi six — and the
    /// page showing through there reads as a board laid crookedly on the screen
    /// rather than as a margin.
    ///
    /// What the width is *bound* by is the line between the two readings. Only
    /// a board the width itself sized leaves a remainder of that kind, and it
    /// is always less than one file; where the board was bound by the height or
    /// stopped at its maximum footprint — an iPad in portrait, where the board
    /// stops 120 points short of the screen — the space beside it is the
    /// surrounding layout's air by the contract's own rule, and painting it
    /// would inflate the board's margin instead of ending it.
    /// Whether the width is what bound the board is asked of the block rather
    /// than derived from the file count, because a block is not always as wide
    /// as its core: a Go-style board carries a strip up its side. The question
    /// is the same either way — would one more point of pitch have overflowed
    /// this width — and asking it of the block answers it for every board.
    static func surfaceBleed(in width: CGFloat, board: BoardGeometry) -> CGFloat {
        let larger = BoardGeometry(board: board.board, pitch: board.pitch + 1)
        guard larger.blockSize.width > width else { return 0 }
        return max(0, (width - board.blockSize.width) / 2)
    }

    // MARK: - Previews

    /// The smallest a preview is allowed to become. Not a contract floor —
    /// the contract gives a preview none — but a board smaller than this stops
    /// being a picture of a board at all.
    static let previewFloorPitch: CGFloat = 18

    /// The board a pre-start page previews. It is noninteractive and has no
    /// touch targets, so the selected game's interactive floor does not apply
    /// to it and the setup controls take the space they need first.
    static func previewGeometry(in size: CGSize, game: GameKind) -> BoardGeometry {
        let board = game.board
        let fitted = BoardGeometry.fitting(sideBySideSpace(in: size), board: board,
                                           floor: previewFloorPitch)
            ?? BoardGeometry(board: board, pitch: previewFloorPitch)
        return BoardGeometry(board: board,
                             pitch: min(fitted.pitch, BoardGeometry.maximumPitch(for: board)))
    }

    /// The same preview in the stacked shape, with the setup controls beneath
    /// it in place of the panel beside it.
    ///
    /// **A preview keeps its air.** The full-width fitting above is the board
    /// screens': a preview sits among setup controls on a page rather than
    /// alone on a screen, and a picture of a board running edge to edge between
    /// two rows of controls would read as the page's header rather than as the
    /// board the page is about.
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

    /// Both the board and the chrome have floors, so the window has one too.
    /// This is what the *content* asks for; the navigation container adds its
    /// own sidebar to it, which is why the window's minimum is measured on the
    /// running app rather than computed here.
    ///
    /// It is the side-by-side shape's floor, and it belongs to the platform
    /// with a resizable window. iOS and iPadOS have no window to bound: the
    /// screen is the size it is, a multitasking iPad is sized by the system
    /// rather than by the app, and a minimum wider than an iPhone would be a
    /// layout asking to be clipped rather than one asking to be stacked.
    static var minimumWidth: CGFloat {
        GameKind.allCases.map { game in
            let board = game.board
            return BoardGeometry(board: board, pitch: BoardGeometry.minimumPitch(for: board))
                .blockSize.width
        }.max()! + panelWidth + 2 * boardPadding
    }

    /// The same quantity the stacked shape reserves for the board above its
    /// chrome: what a window stops shrinking at is what a board block cannot
    /// be given less than.
    static var minimumHeight: CGFloat {
        GameKind.allCases.map { minimumBoardHeight(for: $0) }.max()!
    }
}
