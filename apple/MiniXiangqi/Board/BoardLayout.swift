// The side-by-side shape's measurements, in one place.
//
// docs/interaction-design.md, "Layout shapes": ordinary Mac windows put the
// board on one side with a panel beside it. Play settled these numbers against
// a rendered screen; replay is the same shape with a different panel in it, and
// a second copy of the numbers is a second thing to keep in step.

import SwiftUI

enum BoardLayout {
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

    /// The largest board that fits beside the panel, bounded by the accepted
    /// floor and ceiling.
    static func geometry(in size: CGSize) -> BoardGeometry {
        let available = CGSize(width: size.width - panelWidth - 2 * boardPadding,
                               height: size.height - 2 * boardPadding)
        let fitted = BoardGeometry.fitting(available)
            ?? BoardGeometry(pitch: BoardGeometry.minimumPitch)
        return BoardGeometry(pitch: min(fitted.pitch, BoardGeometry.maximumPitch))
    }

    /// The smallest a preview is allowed to become. Not a contract floor —
    /// the contract gives a preview none — but a board smaller than this stops
    /// being a picture of a board at all.
    static let previewFloorPitch: CGFloat = 18

    /// The board a pre-start page previews. It is noninteractive and has no
    /// touch targets, so the accepted 44-point floor does not apply to it and
    /// the setup controls take the space they need first.
    static func previewGeometry(in size: CGSize) -> BoardGeometry {
        let available = CGSize(width: size.width - panelWidth - 2 * boardPadding,
                               height: size.height - 2 * boardPadding)
        let fitted = BoardGeometry.fitting(available, floor: previewFloorPitch)
            ?? BoardGeometry(pitch: previewFloorPitch)
        return BoardGeometry(pitch: min(fitted.pitch, BoardGeometry.maximumPitch))
    }

    /// Both the board and the chrome have floors, so the window has one too.
    /// This is what the *content* asks for; the navigation container adds its
    /// own sidebar to it, which is why the window's minimum is measured on the
    /// running app rather than computed here.
    static var minimumWidth: CGFloat {
        BoardGeometry(pitch: BoardGeometry.minimumPitch).coreSide
            + panelWidth + 2 * boardPadding
    }

    static var minimumHeight: CGFloat {
        BoardGeometry(pitch: BoardGeometry.minimumPitch).blockSize.height
            + 2 * boardPadding
    }
}
