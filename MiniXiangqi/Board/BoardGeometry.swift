// Every board dimension is a multiple of the cell pitch `p`, so the board
// scales without re-tuning and its proportions never change.

import CoreGraphics

struct BoardGeometry {
    var board: BoardDefinition

    /// The distance between two adjacent points.
    var pitch: CGFloat

    /// Pitches stay whole points so every derived dimension sits on stable
    /// pixel bounds. The placement games take the smaller floor this gives
    /// them: a stone carries no symbol, so a smaller cell costs tap-target size
    /// rather than legibility.
    static let minimumCoreWidth: CGFloat = 308
    static let maximumCoreWidth: CGFloat = 714

    static func minimumPitch(for board: BoardDefinition) -> CGFloat {
        (minimumCoreWidth / CGFloat(board.fileCount)).rounded(.down)
    }

    static func maximumPitch(for board: BoardDefinition) -> CGFloat {
        (maximumCoreWidth / CGFloat(board.fileCount)).rounded(.down)
    }

    var minimumPitch: CGFloat { Self.minimumPitch(for: board) }
    var maximumPitch: CGFloat { Self.maximumPitch(for: board) }

    init(board: BoardDefinition, pitch: CGFloat) {
        self.board = board
        self.pitch = pitch
    }

    // MARK: - The board itself

    /// The half-cell margin beyond the outer points, which is what keeps an
    /// edge disc from being clipped and contains the outermost points' markers.
    var margin: CGFloat { 0.5 * pitch }

    /// Every point plus a half-cell margin on each outer edge.
    var coreSize: CGSize {
        CGSize(width: CGFloat(board.fileCount) * pitch,
               height: CGFloat(board.rankCount) * pitch)
    }

    /// Clamped so the lines never coarsen as the board grows. The palace
    /// diagonals match it.
    var gridStroke: CGFloat { min(max(0.026 * pitch, 0.80), 1.60) }

    // MARK: - Pieces

    var discDiameter: CGFloat { 0.80 * pitch }
    var symbolSize: CGFloat { 0.50 * pitch }

    /// Wider than a disc, as stones sit nearly edge to edge on a Go board, but
    /// inside its cell, so neighbouring stones never overlap.
    var stoneDiameter: CGFloat { 0.88 * pitch }

    /// Part of the board, in the grid's ink, rather than a marker on it.
    var starPointRadius: CGFloat { 0.055 * pitch }

    /// A style's own rings and edge strokes live at or inside `0.40 p`.
    var styleDecorationLimit: CGFloat { 0.40 * pitch }

    /// The stroke is drawn inside the body's edge rather than centred on it,
    /// so a heavy edge grows inward instead of past the body.
    func edgeRadius(body: CGFloat, stroke: CGFloat) -> CGFloat {
        body / 2 - stroke / 2
    }

    func discEdgeRadius(stroke: CGFloat) -> CGFloat {
        edgeRadius(body: discDiameter, stroke: stroke)
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
    /// Outer edge exactly at the cell boundary.
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
    /// The destination's brackets at 0.6 of the weight, so the pair says which
    /// way the move went. Weight rather than a paler ink: record ink has a
    /// contrast floor, and Increase Contrast promotes ink but not weight. 0.6 is
    /// as soft as it goes: at the 44-point floor it is 1.19 points against a
    /// grid line of 1.14.
    var lastMoveOriginStroke: CGFloat { 0.6 * lastMoveStroke }
    var lastMoveInset: CGFloat { 0.05 * pitch }

    var hoverSide: CGFloat { 0.90 * pitch }
    var hoverCornerRadius: CGFloat { 0.12 * pitch }

    /// Half the cross's diagonal, so the arms reach about 0.31 p from the
    /// centre.
    var forbiddenArm: CGFloat { 0.22 * pitch }
    var forbiddenStroke: CGFloat { 0.045 * pitch }

    // MARK: - The hint halo

    // The hint halo is emphasis rather than state, so it is the one mark drawn
    // below record strength and holds no contrast floor of its own. It must
    // stay inside the cell, and the marker standing on it must still reach its
    // ratio.

    /// Outermost first; the overlapping circles make one wash that fades
    /// outward. Radii as multiples of the pitch.
    static let haloWashes: [(radius: CGFloat, opacity: Double)] = [
        (0.47, 0.08), (0.38, 0.09), (0.29, 0.10)]

    /// The opacity where every wash overlaps: the ground the suggested dot's
    /// active ink is measured against.
    static var haloPeakOpacity: Double {
        haloWashes.reduce(0) { $0 + $1.opacity - $0 * $1.opacity }
    }

    /// On an occupied point the wash takes the marker band, behind the dashed
    /// capture ring. Its inner edge at 0.41 p crosses the 0.42 p marker floor,
    /// which is sound: it is emphasis beneath the pieces, and it still clears
    /// the disc face at 0.40 p.
    var haloBandRadius: CGFloat { 0.45 * pitch }
    var haloBandStroke: CGFloat { 0.08 * pitch }
    static let haloBandOpacity: Double = 0.22

    // MARK: - Markers under emphasis

    // Both swelling markers put extra ink on an occupied point, so how far each
    // may grow is decided here, beside the limits it may not cross.

    /// It marks an empty point, where only the cell bounds it, so it grows in
    /// every direction.
    func destinationDotDiameter(emphasis: Double) -> CGFloat {
        destinationDotDiameter * (1 + Motion.markerDotGain * emphasis)
    }

    /// The outer edge stays at the cell boundary, so extra weight grows inward
    /// and stops short of `markerInnerLimit`.
    func captureRingStroke(emphasis: Double) -> CGFloat {
        captureRingStroke * (1 + Motion.markerRingGain * emphasis)
    }

    func checkRingStroke(emphasis: Double) -> CGFloat {
        checkRingStroke * (1 + Motion.checkPulseGain * emphasis)
    }

    /// At rest the rings' edges lie exactly on the two marker limits, so the
    /// swell pins both and grows the strokes into the gap between them.
    /// Growing each ring inward would carry the inner ring onto the general.
    func checkRingRadii(emphasis: Double) -> (inner: CGFloat, outer: CGFloat) {
        let grown = (checkRingStroke(emphasis: emphasis) - checkRingStroke) / 2
        return (inner: checkRingInnerRadius + grown,
                outer: checkRingOuterRadius - grown)
    }

    // MARK: - The edge coordinates

    /// Xiangqi boards carry a file numeral strip above and below, each in the
    /// numbers of the player it faces. Placement games carry Go-style
    /// coordinates, which the 记谱法 preference does not reach.
    enum Coordinates { case fileNumerals, goStyle }

    var coordinates: Coordinates {
        switch board.play {
        case .movement: .fileNumerals
        case .placement: .goStyle
        }
    }

    var numeralSize: CGFloat { min(max((0.32 * pitch).rounded(), 13), 20) }
    /// The first term is clear space between the board's outer line and the
    /// tallest numeral.
    var stripHeight: CGFloat { (0.08 * pitch + 0.887 * numeralSize).rounded() }

    /// A strip running up a side: the same clear space, and room for two
    /// digits at `1.25 s` for the pair.
    var stripWidth: CGFloat { (0.08 * pitch + 1.25 * numeralSize).rounded() }

    /// The board core with its coordinate strips: the rectangle no glass
    /// surface may intersect. Anything that fits a board asks this, not the core.
    var blockSize: CGSize {
        switch coordinates {
        case .fileNumerals:
            CGSize(width: coreSize.width, height: coreSize.height + 2 * stripHeight)
        case .goStyle:
            CGSize(width: coreSize.width + stripWidth,
                   height: coreSize.height + stripHeight)
        }
    }

    // MARK: - Placing points

    /// The centre of a point within the board core, with the board core's own
    /// origin at (0, 0). `flipped` puts Black at the bottom.
    func center(of square: Square, flipped: Bool) -> CGPoint {
        let file = flipped ? board.fileCount - 1 - square.file : square.file
        let rank = flipped ? square.rank : board.rankCount - 1 - square.rank
        return CGPoint(x: margin + CGFloat(file) * pitch,
                       y: margin + CGFloat(rank) * pitch)
    }

    /// `flip` runs from 0 to 1, Red at the bottom at 0.
    ///
    /// Points travel concentric arcs rather than straight lines through the
    /// centre. The rotating rectangle is scaled to stay inside its own bounds,
    /// which can briefly bring adjacent discs over one another. Characters and
    /// icons stay upright.
    func center(of square: Square, flip: Double) -> CGPoint {
        guard flip != 0 else { return center(of: square, flipped: false) }
        guard flip != 1 else { return center(of: square, flipped: true) }
        let base = center(of: square, flipped: false)
        let mid = CGPoint(x: coreSize.width / 2, y: coreSize.height / 2)
        let angle = Double.pi * flip
        let cosine = abs(cos(angle)), sine = abs(sin(angle))
        let width = coreSize.width, height = coreSize.height
        let squeeze = min(width / (width * cosine + height * sine),
                          height / (width * sine + height * cosine))
        let dx = base.x - mid.x, dy = base.y - mid.y
        return CGPoint(x: mid.x + (dx * cos(angle) - dy * sin(angle)) * squeeze,
                       y: mid.y + (dx * sin(angle) + dy * cos(angle)) * squeeze)
    }

    /// Nil outside every cell. The half-cell margin gives every location in the
    /// core exactly one point.
    func square(at location: CGPoint, flipped: Bool) -> Square? {
        let column = Int(((location.x - margin) / pitch).rounded())
        let row = Int(((location.y - margin) / pitch).rounded())
        guard (0..<board.fileCount).contains(column),
              (0..<board.rankCount).contains(row) else {
            return nil
        }
        return Square(file: flipped ? board.fileCount - 1 - column : column,
                      rank: flipped ? row : board.rankCount - 1 - row)
    }

    /// The largest pitch whose board block fits `size`, or nil when even the
    /// floor does not fit.
    ///
    /// A pre-start preview passes a lower `floor`: the floor protects
    /// interaction, which a preview has none of. Both dimensions are checked
    /// because a Go-style board's side strip can make the pitch the width
    /// suggests one too large.
    static func fitting(_ size: CGSize, board: BoardDefinition,
                        floor: CGFloat? = nil) -> BoardGeometry? {
        let floor = floor ?? minimumPitch(for: board)
        var pitch = min((size.width / CGFloat(board.fileCount)).rounded(.down),
                        maximumPitch(for: board))
        while pitch >= floor {
            let candidate = BoardGeometry(board: board, pitch: pitch)
            if candidate.blockSize.height <= size.height,
               candidate.blockSize.width <= size.width { return candidate }
            pitch -= 1
        }
        return nil
    }
}
