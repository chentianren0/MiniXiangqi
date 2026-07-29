// Every board dimension as a multiple of the cell pitch `p`.
//
// Nothing on the board is a fixed point value, so the board scales from its
// floor to a large window without any dimension being re-tuned and without the
// relationships between them changing.
//
// This is where the exact values live, and deliberately so.
// docs/interaction-design.md fixes the *relationships* and the gates — a
// marker stays inside its own cell, a style's decoration stays inside the
// disc, the contrast ratios each ink must reach, the 44-point floor and the
// 720-point ceiling — and then says plainly that the exact dimensions are not
// fixed there, because settling them in prose before anyone had seen a board
// produced numbers that were internally consistent and unverifiable. They are
// settled here instead, against a board that renders, and the gates are
// measured by BoardStyleTests rather than asserted in a comment.

import CoreGraphics

struct BoardGeometry {
    /// The distance between two adjacent points.
    var pitch: CGFloat

    /// The accepted floor on every interactive board, on every platform.
    static let minimumPitch: CGFloat = 44

    /// The board core stops growing at 720 points. Beyond that the two palaces
    /// drift far enough apart on a large display to cost more in eye movement
    /// than the extra size returns, and a disc passes 82 points, which no
    /// physical set resembles. Surplus space goes to the surrounding layout
    /// rather than to the board.
    static let maximumPitch: CGFloat = 720 / 7

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
    /// stroke inside it — at whatever stroke it is drawn with.
    func captureRingRadius(stroke: CGFloat) -> CGFloat { markerOuterLimit - stroke / 2 }
    /// Twelve dashes of 18 degrees separated by 12-degree gaps. Fixing the
    /// count rather than a length keeps the pattern identical at every pitch.
    static let captureDashCount = 12
    static let captureDashDegrees: CGFloat = 18

    var checkRingStroke: CGFloat { 0.025 * pitch }
    var checkRingInnerRadius: CGFloat { 0.4325 * pitch }
    var checkRingOuterRadius: CGFloat { 0.4875 * pitch }

    var lastMoveArm: CGFloat { 0.13 * pitch }
    var lastMoveStroke: CGFloat { 0.045 * pitch }
    /// The origin's brackets: the destination's shape, ink, inset, and
    /// containment, at 0.6 of the weight. The pair marks one move, so it should
    /// say which way the move went and not only which two points it touched,
    /// and weight is what can say it — a paler ink cannot, because record ink
    /// has a contrast floor to hold, which BoardStyleTests measures, and
    /// Increase Contrast promotes the ink while leaving weight alone. The
    /// factor is settled against a rendered board: at 0.6 the origin reads as
    /// the same marker, softer, and it is also where the softening runs out of
    /// room — at the 44-point floor it comes to `1.19` points against a grid
    /// line of `1.14`, and a marker that draws lighter than the board's own
    /// lines has stopped being a marker.
    var lastMoveOriginStroke: CGFloat { 0.6 * lastMoveStroke }
    var lastMoveInset: CGFloat { 0.05 * pitch }

    var hoverSide: CGFloat { 0.90 * pitch }
    var hoverCornerRadius: CGFloat { 0.12 * pitch }

    // MARK: - Markers under emphasis

    // Two markers swell: the check rings' one-time pulse as they appear, and
    // the legal destinations' answer to an illegal tap. Both put extra ink on
    // an occupied point, so both are bounded by the same two limits, and how
    // far each may grow is decided here — beside the limits it may not cross,
    // rather than in the canvas that draws it. MotionTests pins the peaks
    // against the limits by asking these, so no test re-derives them.

    /// The strengthened destination dot. It marks an *empty* point, where only
    /// the cell bounds it, so it grows in every direction.
    func destinationDotDiameter(emphasis: Double) -> CGFloat {
        destinationDotDiameter * (1 + Motion.markerDotGain * emphasis)
    }

    /// The strengthened capture ring's stroke. The ring's outer edge stays at
    /// the cell boundary, so the extra weight grows inward, towards the disc
    /// it surrounds — and stops short of `markerInnerLimit`.
    func captureRingStroke(emphasis: Double) -> CGFloat {
        captureRingStroke * (1 + Motion.markerRingGain * emphasis)
    }

    /// The check rings' stroke at `emphasis` of their one-time swell.
    func checkRingStroke(emphasis: Double) -> CGFloat {
        checkRingStroke * (1 + Motion.checkPulseGain * emphasis)
    }

    /// The two rings' centre-line radii at `emphasis` of the swell. At rest
    /// the inner ring's inner edge lies exactly on `markerInnerLimit` and the
    /// outer ring's outer edge exactly on `markerOuterLimit`; the swell pins
    /// both and grows the strokes into the gap between the rings, which is the
    /// only room the band has. Growing each ring inward from its own outer
    /// edge — the obvious reading of "the weight grows inward" — would carry
    /// the inner ring across the floor and onto the general it rings.
    func checkRingRadii(emphasis: Double) -> (inner: CGFloat, outer: CGFloat) {
        let grown = (checkRingStroke(emphasis: emphasis) - checkRingStroke) / 2
        return (inner: checkRingInnerRadius + grown,
                outer: checkRingOuterRadius - grown)
    }

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

    /// The centre of a point partway through the board flip, `flip` from 0 to
    /// 1 with Red at the bottom at 0.
    ///
    /// The flipped board is the unflipped board rotated half a turn about its
    /// centre, so the flip carries every point along the arc of that rotation:
    /// the arcs are concentric, so no two discs can ever collide mid-flip,
    /// where interpolating each point along a straight line would drive all
    /// of them through the centre at once. The rotation alone would swing the
    /// corner points beyond the core on the diagonals, so the whole position
    /// is scaled by `1/(|cos| + |sin|)` — the rotating square held inside its
    /// own bounding square — which keeps the outermost points riding exactly
    /// along the outer grid lines: every disc keeps the same clearance from
    /// the core's edge mid-flip that it has at rest. Positions rotate; the
    /// characters are never rotated, so they stay upright throughout.
    func center(of square: Square, flip: Double) -> CGPoint {
        guard flip != 0 else { return center(of: square, flipped: false) }
        guard flip != 1 else { return center(of: square, flipped: true) }
        let base = center(of: square, flipped: false)
        let mid = coreSide / 2
        let angle = Double.pi * flip
        let squeeze = 1 / (abs(cos(angle)) + abs(sin(angle)))
        let dx = base.x - mid, dy = base.y - mid
        return CGPoint(x: mid + (dx * cos(angle) - dy * sin(angle)) * squeeze,
                       y: mid + (dx * sin(angle) + dy * cos(angle)) * squeeze)
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
        var pitch = min((size.width / 7).rounded(.down), maximumPitch.rounded(.down))
        while pitch >= minimumPitch {
            let candidate = BoardGeometry(pitch: pitch)
            if candidate.blockSize.height <= size.height { return candidate }
            pitch -= 1
        }
        return nil
    }
}
