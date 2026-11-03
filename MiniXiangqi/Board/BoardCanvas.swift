// The canvas animates one value, `BoardPhases`, so the layering holds during
// motion and a capture's fade is scheduled against its mover's arrival. Under
// Reduce Motion the same phases drive a dissolve where full motion draws
// travel, so every state still arrives.

import SwiftUI

/// Per-square progress values that interpolate as one vector, so a lift can
/// retarget freely: reselecting from one piece to another animates the first
/// down and the second up in the same transaction.
struct SquarePhases: VectorArithmetic {
    private(set) var values: [Square: Double]

    init(_ values: [Square: Double] = [:]) { self.values = values }
    init(raised square: Square?) { self.init(square.map { [$0: 1] } ?? [:]) }
    init(_ square: Square?, at progress: Double) {
        self.init(square.map { [$0: progress] } ?? [:])
    }

    subscript(square: Square) -> Double { values[square] ?? 0 }
    /// Nil where the phase says nothing, which a default of zero cannot tell
    /// apart; a phase whose resting value is one is read through this.
    func stated(_ square: Square) -> Double? { values[square] }
    var marked: [Square] { values.keys.filter { values[$0] ?? 0 > 0 } }
    var strongest: Double { values.values.max() ?? 0 }

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

/// Every animatable quantity of the board, each a progress from 0 to 1.
struct BoardPhases: VectorArithmetic {
    var travel: Double = 0
    /// A capture giving way, or a restored piece returning.
    var fade: Double = 0
    /// A Jieqi reveal. Its own channel rather than a reading of `travel`,
    /// because the identity comes up as the piece lands.
    var reveal: Double = 0
    /// The end of a Jieqi game, disclosing every concealed identity. One phase
    /// for the board, because every disc it touches arrives together.
    var disclosure: Double = 0
    /// Orientation: 0 is Red at the bottom, 1 is flipped.
    var flip: Double = 0
    /// The check rings' one-time swell.
    var check: Double = 0
    /// The legal-destination markers' strengthening.
    var marker: Double = 0
    /// Separate from `marker` because both can stand at once: an illegal tap
    /// strengthens every destination, a hint the one the engine chose. Per
    /// square, so a suggestion moving to another point interpolates.
    var hint = SquarePhases()
    var lifts = SquarePhases()
    /// The Custom Scene editor's placement scaling in and removal scaling out.
    /// A point this phase does not mention carries a disc at rest, so a
    /// placement scales in from zero. A played board hands an empty phase.
    var settled = SquarePhases()

    static let zero = BoardPhases()

    /// While a suggestion stands the other destinations mute, so the suggested
    /// one is the only active-ink marker. Measured against the strongest
    /// suggestion, so the muting arrives, clears and moves with it.
    func muting(at square: Square) -> Double {
        min(max(hint.strongest - hint[square], 0), 1)
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(travel: lhs.travel + rhs.travel, fade: lhs.fade + rhs.fade,
             reveal: lhs.reveal + rhs.reveal,
             disclosure: lhs.disclosure + rhs.disclosure,
             flip: lhs.flip + rhs.flip, check: lhs.check + rhs.check,
             marker: lhs.marker + rhs.marker, hint: lhs.hint + rhs.hint,
             lifts: lhs.lifts + rhs.lifts, settled: lhs.settled + rhs.settled)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(travel: lhs.travel - rhs.travel, fade: lhs.fade - rhs.fade,
             reveal: lhs.reveal - rhs.reveal,
             disclosure: lhs.disclosure - rhs.disclosure,
             flip: lhs.flip - rhs.flip, check: lhs.check - rhs.check,
             marker: lhs.marker - rhs.marker, hint: lhs.hint - rhs.hint,
             lifts: lhs.lifts - rhs.lifts, settled: lhs.settled - rhs.settled)
    }

    mutating func scale(by rhs: Double) {
        travel *= rhs; fade *= rhs; reveal *= rhs; disclosure *= rhs; flip *= rhs
        check *= rhs; marker *= rhs
        hint.scale(by: rhs)
        lifts.scale(by: rhs)
        settled.scale(by: rhs)
    }

    var magnitudeSquared: Double {
        travel * travel + fade * fade + reveal * reveal
            + disclosure * disclosure + flip * flip + check * check
            + marker * marker + hint.magnitudeSquared + lifts.magnitudeSquared
            + settled.magnitudeSquared
    }
}

struct BoardCanvas: View, Animatable {
    var geometry: BoardGeometry
    var placement: Placement
    var style: BoardStyle
    var symbols: PieceSymbols = .hanzi
    var policy: MotionPolicy

    var destinations: Set<Square> = []
    var captures: Set<Square> = []
    var forbidden: Set<Square> = []
    /// In revolutions. It changes outside any transaction, so the caller drives
    /// it from a clock rather than the canvas animating it.
    var dashDrift: Double = 0
    var lastMove: Move?
    var checkedGeneral: Square?
    var transit: Transit?
    /// The second disc of a paired transition: a decision cycle's Undo.
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

    /// The layering, bottom to top: the hint halo; last-move brackets;
    /// destination dots; resting discs; the disc in transit; rings around
    /// resting discs; the held disc with its attached selection ring.
    private func drawPosition(in context: inout GraphicsContext, flip: Double) {
        drawHalo(in: &context, flip: flip)
        drawLastMove(in: &context, flip: flip)
        drawDestinations(in: &context, flip: flip)
        drawForbidden(in: &context, flip: flip)
        drawRestingPieces(in: &context, flip: flip)
        drawTransit(in: &context, flip: flip)
        drawRings(in: &context, flip: flip)
        drawLiftedPieces(in: &context, flip: flip)
    }

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
        // Palace diagonals at the grid's weight, so the palace reads as part of
        // the board rather than as decoration.
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

        // Star points are part of the board rather than marks on it, so they
        // are drawn here, and a stone simply covers one.
        for square in geometry.board.starPoints {
            context.fill(circle(at: point(square, flip: 0),
                                radius: geometry.starPointRadius),
                         with: .color(style.grid))
        }
    }

    // MARK: - Markers

    /// A wash says only *here*; the strengthened marker and the muted rest of
    /// the set carry the state, so it is the one mark drawn below record
    /// strength. It fills the point's free space: an empty point's cell, or a
    /// capture target's marker band, showing through the ring's gaps.
    private func drawHalo(in context: inout GraphicsContext, flip: Double) {
        for square in phases.hint.marked {
            let strength = min(max(phases.hint[square], 0), 1)
            let centre = point(square, flip: flip)
            // The shape follows what stands on the point, not the capture set:
            // the set snaps with the position while the phase fades.
            guard placement[square] == nil else {
                context.stroke(
                    circle(at: centre, radius: geometry.haloBandRadius),
                    with: .color(style.activeInk
                        .opacity(BoardGeometry.haloBandOpacity * strength)),
                    lineWidth: geometry.haloBandStroke)
                continue
            }
            for wash in BoardGeometry.haloWashes {
                context.fill(circle(at: centre, radius: wash.radius * p),
                             with: .color(style.activeInk
                                 .opacity(wash.opacity * strength)))
            }
        }
    }

    private func drawLastMove(in context: inout GraphicsContext, flip: Double) {
        guard let lastMove else { return }
        // The origin is drawn lighter so the pair says which way the move went.
        // Weight alone, since a paler ink would eat into its contrast. A
        // placement has no origin.
        let marks = [(lastMove.to, geometry.lastMoveStroke)]
            + (lastMove.from.map { [($0, geometry.lastMoveOriginStroke)] } ?? [])
        for (square, stroke) in marks {
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
        // The illegal-tap answer and a suggestion strengthen the dot by the
        // same amount, so they share one geometry and one ceiling.
        for square in destinations where !captures.contains(square) {
            let diameter = geometry.destinationDotDiameter(emphasis: emphasis(at: square))
            let centre = point(square, flip: flip)
            let box = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2,
                             width: diameter, height: diameter)
            context.fill(Path(ellipseIn: box), with: .color(ink(at: square)))
        }
    }

    /// A cross, unmistakable against the circular markers and what a renju
    /// board prints. Record ink, because active ink says *you may*. A forbidden
    /// point is always empty, so the cross never has to clear a stone.
    private func drawForbidden(in context: inout GraphicsContext, flip: Double) {
        guard !forbidden.isEmpty else { return }
        let arm = geometry.forbiddenArm
        var path = Path()
        for square in forbidden {
            let centre = point(square, flip: flip)
            path.move(to: CGPoint(x: centre.x - arm, y: centre.y - arm))
            path.addLine(to: CGPoint(x: centre.x + arm, y: centre.y + arm))
            path.move(to: CGPoint(x: centre.x - arm, y: centre.y + arm))
            path.addLine(to: CGPoint(x: centre.x + arm, y: centre.y - arm))
        }
        context.stroke(path, with: .color(style.recordInk),
                       style: StrokeStyle(lineWidth: geometry.forbiddenStroke,
                                          lineCap: .round))
    }

    /// The stronger of the two emphases rather than their sum, so both stay
    /// inside one ceiling.
    private func emphasis(at square: Square) -> Double {
        max(phases.marker, phases.hint[square])
    }

    /// Emphasis and ink are separate: a marker strengthened while the set is
    /// muted keeps its muted ink, so proximity never unmutes.
    private func ink(at square: Square) -> Color {
        style.markerInk(muted: phases.muting(at: square))
    }

    private func drawRings(in context: inout GraphicsContext, flip: Double) {
        // Emphasis grows the stroke inward: the outer edge stays at the cell
        // boundary, and the growth stops at the marker floor.
        for square in captures {
            let stroke = geometry.captureRingStroke(emphasis: emphasis(at: square))
            let radius = geometry.captureRingRadius(stroke: stroke)
            let circumference = 2 * CGFloat.pi * radius
            let dash = circumference * BoardGeometry.captureDashDegrees / 360
            let gap = circumference / CGFloat(BoardGeometry.captureDashCount) - dash
        // Only a suggested capture's dashes turn; the drift is in revolutions.
            let drift = phases.hint[square] > 0 ? dashDrift * circumference : 0
            context.stroke(circle(at: point(square, flip: flip), radius: radius),
                           with: .color(ink(at: square)),
                           style: StrokeStyle(lineWidth: stroke,
                                              lineCap: .butt, dash: [dash, gap],
                                              dashPhase: drift))
        }
        // Hidden while held and absent during a committing transition: the
        // rings belong to the position, which finishes arriving at the landing.
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
                // Scale is motion, so under Reduce Motion settling and lifting
                // arrive as opacity and no size animates.
                let settled = phases.settled.stated(square) ?? 1
                // A disc the ending disclosed shows its identity in place, its
                // symbol arriving by opacity.
                let face = disclosed(piece, at: square)
                draw(face.piece, at: point(square, flip: flip), lift: 0,
                     scale: policy.reduceMotion ? 1 : settled,
                     opacity: (1 - lift) * (policy.reduceMotion ? settled : 1),
                     symbolOpacity: face.symbol,
                     in: context)
            }
        }
    }

    /// The concealed identity is read here and nowhere else on this board, and
    /// only while the disclosure stands.
    private func disclosed(_ piece: Piece,
                           at square: Square) -> (piece: Piece, symbol: Double) {
        guard piece.isFaceDown, phases.disclosure > 0,
              let identity = placement.concealedIdentity(at: square)
        else { return (piece, 1) }
        return (Piece(kind: identity, side: piece.side),
                min(max(phases.disclosure, 0), 1))
    }

    /// The disc in transit and the disc giving way to it, or for an Undo,
    /// returning.
    private func drawTransit(in context: inout GraphicsContext, flip: Double) {
        for transit in transits {
            draw(transit, in: &context, flip: flip)
        }
    }

    private func draw(_ transit: Transit, in context: inout GraphicsContext,
                      flip: Double) {
        // Placement games commit with nothing travelling.
        guard let origin = transit.move.from else { return }
        let progress = phases.travel

        if let fading = transit.fading {
            // The fade's direction says what happened: out for a capture, in
            // for a restored piece.
            let fade = policy.reduceMotion ? progress : phases.fade
            let visible = transit.kind == .move ? 1 - fade : fade
            let shrink = policy.reduceMotion
                ? 1 : Motion.captureShrink + (1 - Motion.captureShrink) * visible
            if visible > 0 {
                draw(fading.piece, at: point(fading.at, flip: flip), lift: 0,
                     scale: shrink, opacity: visible, in: context)
            }
        }

        // A reveal is drawn on the one disc that travels, its symbol arriving;
        // there are never two discs. An Undo of a reveal reads backwards: the
        // symbol goes as the disc returns.
        let progressed = policy.reduceMotion ? progress : phases.reveal
        let face: Piece
        let symbol: Double
        switch transit.revealed {
        case nil:
            face = transit.piece
            symbol = 1
        case let arriving? where arriving.isFaceDown:
            face = transit.piece
            symbol = 1 - progressed
        case let arriving?:
            face = arriving
            symbol = progressed
        }

        let from = point(origin, flip: flip)
        let to = point(transit.move.to, flip: flip)
        if policy.reduceMotion {
            // A dissolve between the two ends: the leaving face at the origin,
            // the arriving face at the destination.
            if progress < 1 {
                draw(transit.piece, at: from, lift: 0, opacity: 1 - progress, in: context)
            }
            if progress > 0 {
                draw(face, at: to, lift: 0, opacity: progress,
                     symbolOpacity: symbol, in: context)
            }
        } else {
            // A move departs raised, as it was already held, and settles over
            // the final quarter; an Undo's disc rises first. The settle is the
            // landing the feedback reports.
            let centre = CGPoint(x: from.x + (to.x - from.x) * progress,
                                 y: from.y + (to.y - from.y) * progress)
            let lift = Motion.transitLift(progress, rising: transit.kind == .undo)
            draw(face, at: centre, lift: lift, symbolOpacity: symbol, in: context)
        }
    }

    private func drawLiftedPieces(in context: inout GraphicsContext, flip: Double) {
        let inTransit = transitSquares
        // Higher discs draw later; the square breaks ties so equal heights
        // never trade places between frames.
        let raised = phases.lifts.marked.sorted {
            (phases.lifts[$0], $0.rank * geometry.board.fileCount + $0.file)
                < (phases.lifts[$1], $1.rank * geometry.board.fileCount + $1.file)
        }
        for square in raised {
            let lift = phases.lifts[square]
            let centre = point(square, flip: flip)
            if let piece = placement[square] {
                guard !inTransit.contains(square) else { continue }
                if policy.reduceMotion {
                    draw(piece, at: centre, lift: 1, opacity: lift, in: context)
                } else {
                    draw(piece, at: centre, lift: lift, in: context)
                }
            } else {
                // Only a placement game marks an empty point: elsewhere a ring
                // at a vacated origin would mark nothing.
                guard geometry.board.play == .placement else { continue }
            }
            // Lift and shadow may not carry selection alone; the ring makes the
            // state certain.
            context.stroke(circle(at: centre, radius: geometry.selectionRingRadius),
                           with: .color(style.activeInk.opacity(lift)),
                           lineWidth: geometry.selectionRingStroke)
        }
    }

    // MARK: - Discs

    private func draw(_ piece: Piece, at centre: CGPoint, lift: Double,
                      scale: CGFloat = 1, opacity: Double = 1,
                      symbolOpacity: Double = 1,
                      in context: GraphicsContext) {
        PieceDrawing(geometry: geometry, style: style, symbols: symbols)
            .draw(piece, at: centre, lift: lift, scale: scale, opacity: opacity,
                  symbolOpacity: symbolOpacity, in: context)
    }
}
