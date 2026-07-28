// Every board dimension as a multiple of the cell pitch `p`.
//
// Nothing on the board is a fixed point value, so the board scales from its
// floor to a large window without any dimension being re-tuned and without the
// relationships between them changing. The figures here are the accepted ones
// in docs/interaction-design.md, "Board metrics" and "Game-state markers"; this
// type is where they are written down once so that no view invents its own.

import CoreGraphics

struct BoardGeometry {
    /// The distance between two adjacent points.
    var pitch: CGFloat

    /// The accepted floor on every interactive board, on every platform.
    static let minimumPitch: CGFloat = 44

    // MARK: - The board itself

    /// The half-cell margin beyond the outer points, which is what keeps an
    /// edge disc from being clipped and contains the outermost points' markers.
    var margin: CGFloat { 0.5 * pitch }

    /// 7 points plus a half-cell margin on each side.
    var coreSide: CGFloat { 7 * pitch }

    /// `0.026 p`, clamped to between 0.80 and 1.60 points, so the lines never
    /// coarsen as the board grows. The palace diagonals match it exactly.
    var gridStroke: CGFloat { min(max(0.026 * pitch, 0.80), 1.60) }

    // MARK: - Pieces

    var discDiameter: CGFloat { 0.80 * pitch }
    var symbolSize: CGFloat { 0.50 * pitch }

    /// A style's own rings and edge strokes live at or inside `0.40 p`.
    var styleDecorationLimit: CGFloat { 0.40 * pitch }

    /// The centre-line radius of a disc's edge stroke. The stroke is drawn
    /// inside the disc's own edge rather than centred on it, which is what
    /// keeps a heavy edge — 传统's Black disc carries one — from reaching past
    /// the style-decoration limit and into the band markers occupy.
    func discEdgeRadius(stroke: CGFloat) -> CGFloat {
        discDiameter / 2 - stroke / 2
    }

    /// How far a style's decoration actually reaches from the point's centre.
    func decorationExtent(edgeStroke: CGFloat) -> CGFloat {
        discEdgeRadius(stroke: edgeStroke) + edgeStroke / 2
    }

    // MARK: - Markers

    /// No marker's ink falls inside this radius on an occupied point.
    var markerInnerLimit: CGFloat { 0.42 * pitch }
    /// Every marker is contained by its own cell.
    var markerOuterLimit: CGFloat { 0.50 * pitch }

    var selectionRingRadius: CGFloat { 0.440 * pitch }
    var selectionRingStroke: CGFloat { 0.030 * pitch }
    var selectionLift: CGFloat { 1.05 }

    var destinationDotDiameter: CGFloat { 0.22 * pitch }

    var captureRingStroke: CGFloat { 0.055 * pitch }
    /// Outer edge exactly at the cell boundary, so the centre line sits half a
    /// stroke inside it.
    var captureRingRadius: CGFloat { markerOuterLimit - captureRingStroke / 2 }
    /// Twelve dashes of 18 degrees separated by 12-degree gaps. Fixing the
    /// count rather than a length keeps the pattern identical at every pitch.
    static let captureDashCount = 12
    static let captureDashDegrees: CGFloat = 18

    var checkRingStroke: CGFloat { 0.025 * pitch }
    var checkRingInnerRadius: CGFloat { 0.4325 * pitch }
    var checkRingOuterRadius: CGFloat { 0.4875 * pitch }

    var lastMoveArm: CGFloat { 0.13 * pitch }
    var lastMoveStroke: CGFloat { 0.045 * pitch }
    var lastMoveInset: CGFloat { 0.05 * pitch }

    var hoverSide: CGFloat { 0.90 * pitch }
    var hoverCornerRadius: CGFloat { 0.12 * pitch }

    // MARK: - File numerals

    /// `0.32 p`, rounded to the nearest point and clamped to between 13 and 20.
    var numeralSize: CGFloat { min(max((0.32 * pitch).rounded(), 13), 20) }
    /// `0.08 p + 0.887 s`: the first term is clear space between the board's
    /// outer line and the tallest numeral.
    var stripHeight: CGFloat { (0.08 * pitch + 0.887 * numeralSize).rounded() }

    /// The board core together with the two file-numeral strips — the rectangle
    /// no glass surface may intersect.
    var blockSize: CGSize {
        CGSize(width: coreSide, height: coreSide + 2 * stripHeight)
    }

    // MARK: - Placing points

    /// The centre of a point within the board core, with the board core's own
    /// origin at (0, 0). `flipped` puts Black at the bottom.
    func center(of square: Square, flipped: Bool) -> CGPoint {
        let file = flipped ? Square.count - 1 - square.file : square.file
        let rank = flipped ? square.rank : Square.count - 1 - square.rank
        return CGPoint(x: margin + CGFloat(file) * pitch,
                       y: margin + CGFloat(rank) * pitch)
    }

    /// The point a tap at `location` addresses, or nil when the tap fell
    /// outside every cell — the half-cell margin means every location inside
    /// the board core belongs to exactly one point.
    func square(at location: CGPoint, flipped: Bool) -> Square? {
        let column = Int(((location.x - margin) / pitch).rounded())
        let row = Int(((location.y - margin) / pitch).rounded())
        guard (0..<Square.count).contains(column), (0..<Square.count).contains(row) else {
            return nil
        }
        return Square(file: flipped ? Square.count - 1 - column : column,
                      rank: flipped ? row : Square.count - 1 - row)
    }

    /// The largest pitch whose board block fits `size`, or nil when even the
    /// floor does not fit.
    static func fitting(_ size: CGSize) -> BoardGeometry? {
        // stripHeight depends on the pitch, so solve by trying the width-bound
        // pitch and stepping down until the block's height fits too.
        var pitch = (size.width / 7).rounded(.down)
        while pitch >= minimumPitch {
            let candidate = BoardGeometry(pitch: pitch)
            if candidate.blockSize.height <= size.height { return candidate }
            pitch -= 1
        }
        return nil
    }
}
