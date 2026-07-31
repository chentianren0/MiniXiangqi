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
// same square into the same rectangle and differ only in what they take out of
// it first: side by side takes 260 points of width, stacked takes the chrome's
// height. Whichever leaves the larger board wins, and a tie goes to side by
// side, which costs the board nothing and shows the move list for free.
//
// That rule is the contract's own reasoning applied to real screens, and it is
// what a width threshold alone cannot express. The two shapes' costs are on
// different axes, so the crossover is not at a width: the accepted macOS
// minimum window is bound by its *height* and takes side by side there, while
// an iPad in portrait is bound by nothing and takes stacked at more than twice
// that width. One number would have to be both below 616 and above 834.
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
    static func shape(in size: CGSize) -> Shape {
        switch (sideBySidePitch(in: size), stackedPitch(in: size)) {
        case (nil, _): .stacked
        case (_, nil): .sideBySide
        case (let beside?, let above?): beside >= above ? .sideBySide : .stacked
        }
    }

    /// The largest pitch the side-by-side shape can draw here, or nil where
    /// even the accepted floor does not fit beside the panel.
    private static func sideBySidePitch(in size: CGSize) -> CGFloat? {
        BoardGeometry.fitting(sideBySideSpace(in: size))
            .map { min($0.pitch, BoardGeometry.maximumPitch) }
    }

    /// The same, for the stacked shape, spending the chrome allowance rather
    /// than the panel's width.
    private static func stackedPitch(in size: CGSize) -> CGFloat? {
        BoardGeometry.fitting(stackedSpace(in: size, chrome: stackedChromeHeight))
            .map { min($0.pitch, BoardGeometry.maximumPitch) }
    }

    // MARK: - Side by side

    private static func sideBySideSpace(in size: CGSize) -> CGSize {
        CGSize(width: size.width - panelWidth - 2 * boardPadding,
               height: size.height - 2 * boardPadding)
    }

    /// The largest board that fits beside the panel, bounded by the accepted
    /// floor and ceiling.
    static func geometry(in size: CGSize) -> BoardGeometry {
        let fitted = BoardGeometry.fitting(sideBySideSpace(in: size))
            ?? BoardGeometry(pitch: BoardGeometry.minimumPitch)
        return BoardGeometry(pitch: min(fitted.pitch, BoardGeometry.maximumPitch))
    }

    // MARK: - Stacked

    private static func stackedSpace(in size: CGSize, chrome: CGFloat) -> CGSize {
        CGSize(width: size.width - 2 * boardPadding,
               height: size.height - chrome - 2 * boardPadding)
    }

    /// The largest board that fits between the status above it and the controls
    /// below it, bounded by the same floor and ceiling.
    ///
    /// `chrome` is what those two actually came to, so a status line grown by an
    /// accessibility text size takes its room from the board rather than
    /// overflowing the screen.
    static func stackedGeometry(in size: CGSize,
                                chrome: CGFloat = stackedChromeHeight) -> BoardGeometry {
        let fitted = BoardGeometry.fitting(stackedSpace(in: size, chrome: chrome))
            ?? BoardGeometry(pitch: BoardGeometry.minimumPitch)
        return BoardGeometry(pitch: min(fitted.pitch, BoardGeometry.maximumPitch))
    }

    // MARK: - Previews

    /// The smallest a preview is allowed to become. Not a contract floor —
    /// the contract gives a preview none — but a board smaller than this stops
    /// being a picture of a board at all.
    static let previewFloorPitch: CGFloat = 18

    /// The board a pre-start page previews. It is noninteractive and has no
    /// touch targets, so the accepted 44-point floor does not apply to it and
    /// the setup controls take the space they need first.
    static func previewGeometry(in size: CGSize) -> BoardGeometry {
        let fitted = BoardGeometry.fitting(sideBySideSpace(in: size), floor: previewFloorPitch)
            ?? BoardGeometry(pitch: previewFloorPitch)
        return BoardGeometry(pitch: min(fitted.pitch, BoardGeometry.maximumPitch))
    }

    /// The same preview in the stacked shape, with the setup controls beneath
    /// it in place of the panel beside it.
    static func stackedPreviewGeometry(in size: CGSize, chrome: CGFloat) -> BoardGeometry {
        let fitted = BoardGeometry.fitting(stackedSpace(in: size, chrome: chrome),
                                           floor: previewFloorPitch)
            ?? BoardGeometry(pitch: previewFloorPitch)
        return BoardGeometry(pitch: min(fitted.pitch, BoardGeometry.maximumPitch))
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
        BoardGeometry(pitch: BoardGeometry.minimumPitch).coreSide
            + panelWidth + 2 * boardPadding
    }

    static var minimumHeight: CGFloat {
        BoardGeometry(pitch: BoardGeometry.minimumPitch).blockSize.height
            + 2 * boardPadding
    }
}
