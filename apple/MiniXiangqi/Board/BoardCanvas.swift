// The board picture, drawn from explicit motion phases.
//
// The canvas is one picture, so its animation is one animatable value: SwiftUI
// interpolates `BoardPhases` through every frame of a transaction and the
// canvas draws that frame. This is what lets the layering hold *during* motion
// — the mover above resting discs and beneath rings, the held disc above them
// — and what lets a capture's fade be scheduled against its mover's arrival
// rather than merely near it.
//
// Reduce Motion is consulted here as rendering, not re-decided: the same
// phases drive a dissolve where full motion draws travel, so every state
// arrives either way and only the travel disappears.

import SwiftUI

/// Per-square progress values that interpolate as one vector, so a lift can
/// retarget freely: reselecting from one piece to another animates the first
/// down and the second up in the same transaction.
struct SquarePhases: VectorArithmetic {
    private(set) var values: [Square: Double]

    init(_ values: [Square: Double] = [:]) { self.values = values }
    /// The lift target for a selection: the held square fully raised.
    init(raised square: Square?) { self.init(square.map { [$0: 1] } ?? [:]) }

    subscript(square: Square) -> Double { values[square] ?? 0 }
    var raised: [Square] { values.keys.filter { values[$0] ?? 0 > 0 } }

    static let zero = SquarePhases()

    static func + (lhs: Self, rhs: Self) -> Self { lhs.merged(with: rhs, +) }
    static func - (lhs: Self, rhs: Self) -> Self { lhs.merged(with: rhs, -) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        Set(lhs.values.keys).union(rhs.values.keys).allSatisfy { lhs[$0] == rhs[$0] }
    }

    mutating func scale(by rhs: Double) {
        values = values.mapValues { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.values.reduce(0) { $0 + $1 * $1 }
    }

    private func merged(with other: Self, _ combine: (Double, Double) -> Double) -> Self {
        var result = values
        for key in Set(values.keys).union(other.values.keys) {
            result[key] = combine(self[key], other[key])
        }
        return Self(result)
    }
}

/// Every animatable quantity of the board, interpolated componentwise. Each
/// component is a progress from 0 to 1; what it means is drawn below.
struct BoardPhases: VectorArithmetic {
    /// The committing transit's progress from origin to destination.
    var travel: Double = 0
    /// The fading disc's progress — a capture giving way, a restored piece
    /// returning.
    var fade: Double = 0
    /// Orientation: 0 is Red at the bottom, 1 is flipped.
    var flip: Double = 0
    /// The check rings' one-time swell.
    var check: Double = 0
    /// The legal-destination markers' strengthening.
    var marker: Double = 0
    /// The selection lift, per square.
    var lifts = SquarePhases()

    static let zero = BoardPhases()

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(travel: lhs.travel + rhs.travel, fade: lhs.fade + rhs.fade,
             flip: lhs.flip + rhs.flip, check: lhs.check + rhs.check,
             marker: lhs.marker + rhs.marker, lifts: lhs.lifts + rhs.lifts)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(travel: lhs.travel - rhs.travel, fade: lhs.fade - rhs.fade,
             flip: lhs.flip - rhs.flip, check: lhs.check - rhs.check,
             marker: lhs.marker - rhs.marker, lifts: lhs.lifts - rhs.lifts)
    }

    mutating func scale(by rhs: Double) {
        travel *= rhs; fade *= rhs; flip *= rhs
        check *= rhs; marker *= rhs
        lifts.scale(by: rhs)
    }

    var magnitudeSquared: Double {
        travel * travel + fade * fade + flip * flip + check * check
            + marker * marker + lifts.magnitudeSquared
    }
}

struct BoardCanvas: View, Animatable {
    var geometry: BoardGeometry
    var placement: Placement
    var style: BoardStyle
    /// Which symbol set the discs carry. Characters unless told otherwise: the
    /// accepted default, and the reason a caller that says nothing about
    /// symbols draws exactly the board it drew before icons existed.
    var symbols: PieceSymbols = .hanzi
    var policy: MotionPolicy

    var destinations: Set<Square> = []
    var captures: Set<Square> = []
    var lastMove: Move?
    var checkedGeneral: Square?
    var transit: Transit?
    /// The second disc of a paired transition — a decision cycle's Undo.
    var companion: Transit?
    var phases: BoardPhases

    var animatableData: BoardPhases {
        get { phases }
        set { phases = newValue }
    }

    private var p: CGFloat { geometry.pitch }

    var body: some View {
        Canvas { context, _ in
            // The grid is identical in both orientations, so it never takes
            // part in the flip and never dims through a dissolve.
            drawGrid(in: &context)
            if policy.reduceMotion, 0 < phases.flip, phases.flip < 1 {
                // The flip without motion: the two orientations dissolve.
                var settled = context
                settled.opacity = 1 - phases.flip
                drawPosition(in: &settled, flip: 0)
                var arriving = context
                arriving.opacity = phases.flip
                drawPosition(in: &arriving, flip: 1)
            } else {
                drawPosition(in: &context, flip: phases.flip)
            }
        }
    }

    /// The accepted layering, bottom to top: last-move brackets; destination
    /// dots; resting discs; the disc in transit; rings around resting discs;
    /// the held disc with its attached selection ring.
    private func drawPosition(in context: inout GraphicsContext, flip: Double) {
        drawLastMove(in: &context, flip: flip)
        drawDestinations(in: &context, flip: flip)
        drawRestingPieces(in: &context, flip: flip)
        drawTransit(in: &context, flip: flip)
        drawRings(in: &context, flip: flip)
        drawLiftedPieces(in: &context, flip: flip)
    }

    /// A point's centre partway through the flip: the contained rotation
    /// BoardGeometry defines, under which no two discs can collide and no
    /// disc leaves the core.
    private func point(_ square: Square, flip: Double) -> CGPoint {
        geometry.center(of: square, flip: flip)
    }

    // MARK: - Grid

    private func drawGrid(in context: inout GraphicsContext) {
        var path = Path()
        for rank in 0..<geometry.board.rankCount {
            let alongRank = point(Square(file: 0, rank: rank), flip: 0)
            let toRank = point(Square(file: geometry.board.fileCount - 1, rank: rank), flip: 0)
            path.move(to: alongRank)
            path.addLine(to: toRank)
        }

        for file in 0..<geometry.board.fileCount {
            let first = Square(file: file, rank: 0)
            let last = Square(file: file, rank: geometry.board.rankCount - 1)
            if let river = geometry.board.riverAfterRank,
               file != 0, file != geometry.board.fileCount - 1 {
                path.move(to: point(first, flip: 0))
                path.addLine(to: point(Square(file: file, rank: river), flip: 0))
                path.move(to: point(Square(file: file, rank: river + 1), flip: 0))
                path.addLine(to: point(last, flip: 0))
            } else {
                path.move(to: point(first, flip: 0))
                path.addLine(to: point(last, flip: 0))
            }
        }
        // Each palace is a 3-by-3 block of points, its two diagonals drawn
        // corner point to corner point at the same stroke weight as the grid,
        // so the palace reads as part of the board rather than as decoration.
        for palace in geometry.board.palaces {
            path.move(to: point(Square(file: palace.files.lowerBound,
                                             rank: palace.ranks.lowerBound), flip: 0))
            path.addLine(to: point(Square(file: palace.files.upperBound,
                                          rank: palace.ranks.upperBound), flip: 0))
            path.move(to: point(Square(file: palace.files.upperBound,
                                      rank: palace.ranks.lowerBound), flip: 0))
            path.addLine(to: point(Square(file: palace.files.lowerBound,
                                          rank: palace.ranks.upperBound), flip: 0))
        }
        context.stroke(path, with: .color(style.grid), lineWidth: geometry.gridStroke)
    }

    // MARK: - Markers

    private func drawLastMove(in context: inout GraphicsContext, flip: Double) {
        guard let lastMove else { return }
        // One marker at two points, and the origin's half of it is drawn
        // lighter, so the pair says which way the move went rather than only
        // which two points it touched. Weight alone: same shape, same record
        // ink, same inset — a paler ink would eat into the contrast the ink
        // has to hold.
        for (square, stroke) in [(lastMove.from, geometry.lastMoveOriginStroke),
                                 (lastMove.to, geometry.lastMoveStroke)] {
            context.stroke(bracketPath(at: point(square, flip: flip)),
                           with: .color(style.recordInk),
                           style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }
    }

    /// Four L-shaped corner brackets on the cell, inset from each corner.
    private func bracketPath(at centre: CGPoint) -> Path {
        let half = 0.5 * p - geometry.lastMoveInset
        let arm = geometry.lastMoveArm
        var path = Path()
        for x in [-1.0, 1.0] as [CGFloat] {
            for y in [-1.0, 1.0] as [CGFloat] {
                let corner = CGPoint(x: centre.x + x * half, y: centre.y + y * half)
                path.move(to: CGPoint(x: corner.x - x * arm, y: corner.y))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x, y: corner.y - y * arm))
            }
        }
        return path
    }

    private func drawDestinations(in context: inout GraphicsContext, flip: Double) {
        // The illegal-tap answer strengthens the dot by a quarter at most —
        // still far inside its cell.
        let diameter = geometry.destinationDotDiameter(emphasis: phases.marker)
        for square in destinations where !captures.contains(square) {
            let centre = point(square, flip: flip)
            let box = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2,
                             width: diameter, height: diameter)
            context.fill(Path(ellipseIn: box), with: .color(style.activeInk))
        }
    }

    private func drawRings(in context: inout GraphicsContext, flip: Double) {
        // A dashed ring around an enemy disc the player may take. Its answer
        // to an illegal tap grows the stroke inward — the outer edge stays at
        // the cell boundary, where the contract fixes it, and the inward
        // growth stops at the marker floor rather than reaching the disc.
        if !captures.isEmpty {
            let stroke = geometry.captureRingStroke(emphasis: phases.marker)
            let radius = geometry.captureRingRadius(stroke: stroke)
            let circumference = 2 * CGFloat.pi * radius
            let dash = circumference * BoardGeometry.captureDashDegrees / 360
            let gap = circumference / CGFloat(BoardGeometry.captureDashCount) - dash
            for square in captures {
                context.stroke(circle(at: point(square, flip: flip), radius: radius),
                               with: .color(style.activeInk),
                               style: StrokeStyle(lineWidth: stroke,
                                                  lineCap: .butt, dash: [dash, gap]))
            }
        }
        // A double ring around a checked general, hidden while it is held and
        // absent while a committing transition runs: the rings belong to the
        // position, and the position finishes arriving at the landing. The
        // one-time pulse swells the strokes into the gap between the rings, so
        // the pair stays inside the marker band at both ends; at the peak the
        // two nearly meet, one emphasis before the double ring separates
        // again.
        if transit == nil, let checkedGeneral, phases.lifts[checkedGeneral] == 0 {
            let stroke = geometry.checkRingStroke(emphasis: phases.check)
            let radii = geometry.checkRingRadii(emphasis: phases.check)
            for radius in [radii.inner, radii.outer] {
                context.stroke(circle(at: point(checkedGeneral, flip: flip), radius: radius),
                               with: .color(style.activeInk),
                               lineWidth: stroke)
            }
        }
    }

    private func circle(at centre: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                               width: radius * 2, height: radius * 2))
    }

    // MARK: - Pieces

    /// The transits being drawn: one ordinarily, two while a decision cycle is
    /// being taken back.
    private var transits: [Transit] { [transit, companion].compactMap { $0 } }

    /// The squares whose discs the transits draw themselves.
    private var transitSquares: Set<Square> {
        var squares: Set<Square> = []
        for transit in transits {
            squares.insert(transit.move.to)
            if let fading = transit.fading { squares.insert(fading.at) }
        }
        return squares
    }

    private func drawRestingPieces(in context: inout GraphicsContext, flip: Double) {
        let inTransit = transitSquares
        for rank in 0..<geometry.board.rankCount {
            for file in 0..<geometry.board.fileCount {
                let square = Square(file: file, rank: rank)
                guard let piece = placement[square], !inTransit.contains(square) else { continue }
                let lift = phases.lifts[square]
                if lift > 0, !policy.reduceMotion { continue }   // drawn above the rings
                // Reduce Motion raises a piece by dissolve: the resting
                // rendering fades here while the raised one fades in above,
                // and no size ever animates.
                draw(piece, at: point(square, flip: flip), lift: 0,
                     opacity: 1 - lift, in: context)
            }
        }
    }

    /// The disc in transit and the disc giving way to it — or, for an Undo,
    /// returning as it departs.
    private func drawTransit(in context: inout GraphicsContext, flip: Double) {
        for transit in transits {
            draw(transit, in: &context, flip: flip)
        }
    }

    private func draw(_ transit: Transit, in context: inout GraphicsContext,
                      flip: Double) {
        let progress = phases.travel

        if let fading = transit.fading {
            // For a capture the fade is scheduled against the arrival; under
            // Reduce Motion it rides the dissolve itself. Either way its
            // direction says what happened: out for a capture, in for a
            // restored piece.
            let fade = policy.reduceMotion ? progress : phases.fade
            let visible = transit.kind == .move ? 1 - fade : fade
            let shrink = policy.reduceMotion
                ? 1 : Motion.captureShrink + (1 - Motion.captureShrink) * visible
            if visible > 0 {
                draw(fading.piece, at: point(fading.at, flip: flip), lift: 0,
                     scale: shrink, opacity: visible, in: context)
            }
        }

        let from = point(transit.move.from, flip: flip)
        let to = point(transit.move.to, flip: flip)
        if policy.reduceMotion {
            // The travel without motion: a dissolve between the two ends.
            if progress < 1 {
                draw(transit.piece, at: from, lift: 0, opacity: 1 - progress, in: context)
            }
            if progress > 0 {
                draw(transit.piece, at: to, lift: 0, opacity: progress, in: context)
            }
        } else {
            // A move departs raised — it was already held — and settles onto
            // its point over the final quarter; an Undo's disc rises first,
            // because nothing held it. The settle is the landing the
            // feedback reports.
            let centre = CGPoint(x: from.x + (to.x - from.x) * progress,
                                 y: from.y + (to.y - from.y) * progress)
            let lift = Motion.transitLift(progress, rising: transit.kind == .undo)
            draw(transit.piece, at: centre, lift: lift, in: context)
        }
    }

    private func drawLiftedPieces(in context: inout GraphicsContext, flip: Double) {
        let inTransit = transitSquares
        // Ordered by progress — the higher a disc, the later it draws — with
        // the square as a tiebreak so equal heights never trade places
        // between frames.
        let raised = phases.lifts.raised.sorted {
            (phases.lifts[$0], $0.rank * geometry.board.fileCount + $0.file)
                < (phases.lifts[$1], $1.rank * geometry.board.fileCount + $1.file)
        }
        for square in raised {
            guard let piece = placement[square], !inTransit.contains(square) else { continue }
            let lift = phases.lifts[square]
            let centre = point(square, flip: flip)
            if policy.reduceMotion {
                draw(piece, at: centre, lift: 1, opacity: lift, in: context)
            } else {
                draw(piece, at: centre, lift: lift, in: context)
            }
            // The solid selection ring, attached to the piece. Lift and
            // shadow may not carry selection alone; the ring is what makes
            // the state certain, so it rides the same progress.
            context.stroke(circle(at: centre, radius: geometry.selectionRingRadius),
                           with: .color(style.activeInk.opacity(lift)),
                           lineWidth: geometry.selectionRingStroke)
        }
    }

    // MARK: - Discs

    /// One disc, `lift` of the way from resting to raised: scale and shadow
    /// rise together, and nothing else changes. The context arrives by value
    /// — a copy draws into the same canvas — so the disc's opacity composes
    /// with whatever the caller already set.
    private func draw(_ piece: Piece, at centre: CGPoint, lift: Double,
                      scale externalScale: CGFloat = 1, opacity: Double = 1,
                      in context: GraphicsContext) {
        var context = context
        context.opacity *= opacity

        let scale = (1 + (geometry.selectionLift - 1) * lift) * externalScale
        let shadow = style.restingShadow.blended(toward: style.liftShadow, by: lift)
        let diameter = geometry.discDiameter * scale
        let box = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2,
                         width: diameter, height: diameter)
        let edge = style.discEdgeStroke(piece.side) * p

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: shadow.color,
                                    radius: shadow.radius * p,
                                    y: shadow.y * p))
            layer.fill(Path(ellipseIn: box), with: .color(style.discFace))
        }
        context.stroke(circle(at: centre, radius: geometry.discEdgeRadius(stroke: edge) * scale),
                       with: .color(style.discEdge(piece.side)), lineWidth: edge)

        drawSymbol(of: piece, at: centre, scale: scale, in: &context)
    }

    /// What the disc carries: the piece's character, or its icon.
    ///
    /// One place, so the two sets are drawn at the same size, on the same
    /// centre, in the same role ink — and so every disc the board draws gets
    /// them, the resting one, the held one, and the one in transit alike. An
    /// icon is never rotated, exactly as a character is never rotated, so both
    /// stand upright throughout a flip.
    private func drawSymbol(of piece: Piece, at centre: CGPoint, scale: CGFloat,
                            in context: inout GraphicsContext) {
        let size = geometry.symbolSize * scale
        let ink = style.symbol(piece.side)
        switch symbols {
        case .hanzi:
            var symbol = context.resolve(
                Text(piece.kind.character(for: piece.side))
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(ink))
            symbol.shading = .color(ink)
            context.draw(symbol, at: centre)
        case .icons:
            let box = CGRect(x: centre.x - size / 2, y: centre.y - size / 2,
                             width: size, height: size)
            context.fill(PieceIcon.path(for: piece.kind, in: box),
                         with: .color(ink), style: FillStyle(eoFill: true))
        }
    }
}
