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
    /// One square at a progress of its own — a suggestion's strengthening,
    /// which is a state of one point rather than of the board.
    init(_ square: Square?, at progress: Double) {
        self.init(square.map { [$0: progress] } ?? [:])
    }

    subscript(square: Square) -> Double { values[square] ?? 0 }
    /// The progress this phase carries for a square, or nil where it says
    /// nothing about it at all — the distinction a default of zero cannot make,
    /// and the one a phase whose resting value is *one* is read through.
    func stated(_ square: Square) -> Double? { values[square] }
    /// Every square this phase says anything about.
    var marked: [Square] { values.keys.filter { values[$0] ?? 0 > 0 } }
    /// The largest progress any square carries.
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

/// Every animatable quantity of the board, interpolated componentwise. Each
/// component is a progress from 0 to 1; what it means is drawn below.
struct BoardPhases: VectorArithmetic {
    /// The committing transit's progress from origin to destination.
    var travel: Double = 0
    /// The fading disc's progress — a capture giving way, a restored piece
    /// returning.
    var fade: Double = 0
    /// How far the arriving face has come up on the travelling disc: a Jieqi
    /// reveal, and nothing else. It is a channel of its own beside the travel
    /// rather than a reading of it, because what it draws is scheduled against
    /// the arrival rather than spread over the journey — the identity comes up
    /// as the piece lands, which is what makes a reveal one event.
    var reveal: Double = 0
    /// How far the whole deal has come up: the end of a Jieqi game, which
    /// discloses every identity the position still conceals. It is one phase for
    /// the board rather than one per disc, because what it draws is one event —
    /// the game ending — and every disc it touches arrives together.
    var disclosure: Double = 0
    /// Orientation: 0 is Red at the bottom, 1 is flipped.
    var flip: Double = 0
    /// The check rings' one-time swell.
    var check: Double = 0
    /// The legal-destination markers' strengthening.
    var marker: Double = 0
    /// The suggested destination's own strengthening — a hint being shown. It
    /// is a phase of its own rather than the one above because the two answer
    /// different things and can stand at once: an illegal tap strengthens every
    /// destination the held piece has, and a hint strengthens the one the
    /// engine chose. It is per square for the reason the lift is: the point a
    /// suggestion stands on is part of what the suggestion says, so a
    /// suggestion arriving, clearing, or moving to another point interpolates
    /// as one vector rather than jumping between two states.
    var hint = SquarePhases()
    /// The selection lift, per square.
    var lifts = SquarePhases()
    /// How far a disc has settled onto its point, per square — the Custom Scene
    /// editor's placement scaling in and its removal scaling out.
    ///
    /// **A point this phase does not mention carries a disc at rest**, which is
    /// what makes a placement scale in from nothing without a state set twice:
    /// the point is unmentioned until the piece is put down, so the vector
    /// interpolates it from zero. Every board that is played hands an empty
    /// phase and therefore draws every disc at full size.
    var settled = SquarePhases()

    static let zero = BoardPhases()

    /// How far one destination marker's ink has dropped from active toward
    /// record, 0 to 1. While a suggestion stands the rest of the set mutes, so
    /// that the suggested marker is the one active-ink marker the selection
    /// shows and finding it is a glance rather than a comparison. Stated as a
    /// difference against the strongest suggestion on the board, so that the
    /// muting arrives, clears, and moves with the suggestion itself.
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
    /// Which symbol set the discs carry. Characters unless told otherwise: the
    /// accepted default, and the reason a caller that says nothing about
    /// symbols draws exactly the board it drew before icons existed.
    var symbols: PieceSymbols = .hanzi
    var policy: MotionPolicy

    var destinations: Set<Square> = []
    var captures: Set<Square> = []
    /// The points the side to move may not play, where a game has any. Renju's
    /// forbidden points during Black's turn are the only ones today; every other
    /// game hands an empty set and draws nothing.
    var forbidden: Set<Square> = []
    /// How far the dashes of a suggested capture's ring have turned, in
    /// revolutions. The board's one continuous motion, and the one thing it
    /// draws that changes outside a transaction, so it arrives as a value the
    /// caller drives from a clock rather than as a phase the canvas animates.
    var dashDrift: Double = 0
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

    /// The accepted layering, bottom to top: the hint halo; last-move brackets;
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

    /// A point's centre partway through the flip: the contained rotation
    /// BoardGeometry defines. Point centres remain distinct and every disc stays
    /// inside the core; adjacent discs may overlap briefly while it is scaled.
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

        // The board's own printed reference points, in the grid's ink and at the
        // grid's own weight of presence: they are part of the board rather than
        // marks on it, which is why they are drawn here and not among the
        // markers, and why a stone simply covers one.
        for square in geometry.board.starPoints {
            context.fill(circle(at: point(square, flip: 0),
                                radius: geometry.starPointRadius),
                         with: .color(style.grid))
        }
    }

    // MARK: - Markers

    /// The halo the suggested point carries: a wash of active ink at low
    /// opacity, drawn beneath the pieces exactly where the pointer hover fill
    /// is drawn. It is a wash rather than a marker among the shape families —
    /// it says *here*, and the strengthened marker above it and the muted rest
    /// of the set are what carry the state — which is why it is the one mark
    /// the board draws below record strength, and why the board without it
    /// still says which destination the engine chose.
    ///
    /// It fills whatever space the point has free: an empty point's cell,
    /// beneath the dot; a capture target's marker band, behind the dashed ring,
    /// where it shows through the gaps between the dashes. Its opacity rides
    /// the suggestion's own phase, so it arrives and goes with the suggestion.
    private func drawHalo(in context: inout GraphicsContext, flip: Double) {
        for square in phases.hint.marked {
            let strength = min(max(phases.hint[square], 0), 1)
            let centre = point(square, flip: flip)
            // The shape follows what is standing on the point, not the capture
            // set: the set snaps with the position while the phase fades, and a
            // clearing suggestion on a capture should fade out as the band it
            // was, not as a cell wash drawn under a disc.
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
        // One marker at two points, and the origin's half of it is drawn
        // lighter, so the pair says which way the move went rather than only
        // which two points it touched. Weight alone: same shape, same record
        // ink, same inset — a paler ink would eat into the contrast the ink
        // has to hold.
        //
        // A placement has no origin, so it is marked at the one point it
        // touched: there is no direction to say.
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
        // The illegal-tap answer strengthens the dot by a quarter at most —
        // still far inside its cell — and a suggested destination is
        // strengthened by exactly the same amount, which is why the two share
        // one geometry and one ceiling.
        for square in destinations where !captures.contains(square) {
            let diameter = geometry.destinationDotDiameter(emphasis: emphasis(at: square))
            let centre = point(square, flip: flip)
            let box = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2,
                             width: diameter, height: diameter)
            context.fill(Path(ellipseIn: box), with: .color(ink(at: square)))
        }
    }

    /// The points the side to move may not play: a small cross at each, inside
    /// its own cell, in **record** ink.
    ///
    /// A cross because it has to be unmistakable against every circular marker
    /// the board draws, and because it is what a renju board prints; record ink
    /// because active ink is what says *you may*, and a prohibition drawn in it
    /// would compete with the affordances rather than qualify them. Every
    /// forbidden point is empty by the rule that makes it forbidden, so the
    /// cross never falls on a stone and nothing here has to clear one.
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

    /// How strongly one point's marker is drawn. The suggested point takes the
    /// stronger of the two emphases rather than their sum, so a hint standing
    /// while an illegal tap is answered stays inside the one ceiling both
    /// markers are bounded by.
    private func emphasis(at square: Square) -> Double {
        max(phases.marker, phases.hint[square])
    }

    /// The ink one destination marker is drawn in. Active, until a suggestion
    /// stands: then every destination marker but the suggested one drops to
    /// record ink, and the drop rides the suggestion's own phase, so the whole
    /// set mutes and un-mutes in the transaction the suggestion arrives and
    /// clears in.
    ///
    /// The ink a marker is drawn in and how strongly it is drawn are separate
    /// questions, and the emphasis above answers only the second: a marker
    /// strengthened while the set is muted keeps its muted ink, which is what
    /// the contract requires of a drag's nearby strengthening — proximity never
    /// unmutes.
    private func ink(at square: Square) -> Color {
        style.markerInk(muted: phases.muting(at: square))
    }

    private func drawRings(in context: inout GraphicsContext, flip: Double) {
        // A dashed ring around an enemy disc the player may take. Its answer
        // to an illegal tap grows the stroke inward — the outer edge stays at
        // the cell boundary, where the contract fixes it, and the inward
        // growth stops at the marker floor rather than reaching the disc.
        for square in captures {
            let stroke = geometry.captureRingStroke(emphasis: emphasis(at: square))
            let radius = geometry.captureRingRadius(stroke: stroke)
            let circumference = 2 * CGFloat.pi * radius
            let dash = circumference * BoardGeometry.captureDashDegrees / 360
            let gap = circumference / CGFloat(BoardGeometry.captureDashCount) - dash
            // A suggested capture's dashes turn, and only its: the drift is a
            // fraction of a revolution, and a revolution around this ring is
            // its whole circumference.
            let drift = phases.hint[square] > 0 ? dashDrift * circumference : 0
            context.stroke(circle(at: point(square, flip: flip), radius: radius),
                           with: .color(ink(at: square)),
                           style: StrokeStyle(lineWidth: stroke,
                                              lineCap: .butt, dash: [dash, gap],
                                              dashPhase: drift))
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
                // A disc partway onto or off the board — a piece being composed
                // into a scene, or taken back out of one. Scale is motion, so
                // under Reduce Motion the same phase arrives as opacity and the
                // disc never changes size, exactly as the lift beside it does.
                let settled = phases.settled.stated(square) ?? 1
                // Reduce Motion raises a piece by dissolve: the resting
                // rendering fades here while the raised one fades in above,
                // and no size ever animates.
                //
                // **A piece the ending has disclosed comes up in its place**:
                // the game is over, every identity is disclosed to both players,
                // and the disc that was face down carries the piece it was all
                // along. It is the reveal's own drawing at rest — one body, one
                // ring, and the symbol arriving by opacity — so nothing moves
                // and Reduce Motion changes nothing about it.
                let face = disclosed(piece, at: square)
                draw(face.piece, at: point(square, flip: flip), lift: 0,
                     scale: policy.reduceMotion ? 1 : settled,
                     opacity: (1 - lift) * (policy.reduceMotion ? settled : 1),
                     symbolOpacity: face.symbol,
                     in: context)
            }
        }
    }

    /// One resting piece as the end of the game leaves it: itself, or — where
    /// the ending has disclosed the deal and this disc was face down — the
    /// piece the record held under it, with its symbol coming up on the phase.
    ///
    /// The concealed identity is read here and nowhere else on this board, and
    /// only while the disclosure stands: a game that has ended discloses every
    /// hidden identity to both players, which is the one moment the position's
    /// concealment is over.
    private func disclosed(_ piece: Piece,
                           at square: Square) -> (piece: Piece, symbol: Double) {
        guard piece.isFaceDown, phases.disclosure > 0,
              let identity = placement.concealedIdentity(at: square)
        else { return (piece, 1) }
        return (Piece(kind: identity, side: piece.side),
                min(max(phases.disclosure, 0), 1))
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
        // A transit is a body crossing the board, so it has an origin to cross
        // from. The placement games commit with nothing travelling and build
        // none; this is the type saying so rather than a case to handle.
        guard let origin = transit.move.from else { return }
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

        // **A reveal is drawn on the one disc that travels.** The face-down body
        // and the piece it turns up as are the same disc in the same ring — they
        // differ by the symbol alone — so one disc is drawn throughout and its
        // symbol is what arrives, and at no point are there two. Under Reduce
        // Motion the identity rides the dissolve's own progress, which is that
        // rule unchanged: opacity is not motion.
        //
        // A move that puts a piece *back* face down — an Undo of a reveal, which
        // returns the position's concealment — is the same drawing read
        // backwards: the face that has a symbol is the one that left, and the
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
            // The travel without motion: a dissolve between the two ends. The
            // face it leaves with stands at the origin and the face it arrives
            // with stands at the destination, which is the reveal drawn in the
            // one language this mode has.
            if progress < 1 {
                draw(transit.piece, at: from, lift: 0, opacity: 1 - progress, in: context)
            }
            if progress > 0 {
                draw(face, at: to, lift: 0, opacity: progress,
                     symbolOpacity: symbol, in: context)
            }
        } else {
            // A move departs raised — it was already held — and settles onto
            // its point over the final quarter; an Undo's disc rises first,
            // because nothing held it. The settle is the landing the
            // feedback reports.
            let centre = CGPoint(x: from.x + (to.x - from.x) * progress,
                                 y: from.y + (to.y - from.y) * progress)
            let lift = Motion.transitLift(progress, rising: transit.kind == .undo)
            draw(face, at: centre, lift: lift, symbolOpacity: symbol, in: context)
        }
    }

    private func drawLiftedPieces(in context: inout GraphicsContext, flip: Double) {
        let inTransit = transitSquares
        // Ordered by progress — the higher a disc, the later it draws — with
        // the square as a tiebreak so equal heights never trade places
        // between frames.
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
                // A placement game marks an *empty* point: the stone is not on
                // the board until the mark is confirmed, so the ring below is
                // the whole of the mark. Every other board raises a point only
                // by holding the piece standing on it, and a ring left behind
                // at a vacated origin while a move animates away from it would
                // be a mark about nothing.
                guard geometry.board.play == .placement else { continue }
            }
            // The solid selection ring, attached to the piece — or standing on
            // its own where the game places rather than moves. Lift and shadow
            // may not carry selection alone; the ring is what makes the state
            // certain, so it rides the same progress.
            context.stroke(circle(at: centre, radius: geometry.selectionRingRadius),
                           with: .color(style.activeInk.opacity(lift)),
                           lineWidth: geometry.selectionRingStroke)
        }
    }

    // MARK: - Discs

    /// One disc, drawn by the one routine that draws a piece anywhere in this
    /// app — `PieceDrawing`, which the Custom Scene palette calls too, so a
    /// palette entry and the piece it puts on the board are the same drawing at
    /// two pitches rather than two drawings that have to be kept in step.
    private func draw(_ piece: Piece, at centre: CGPoint, lift: Double,
                      scale: CGFloat = 1, opacity: Double = 1,
                      symbolOpacity: Double = 1,
                      in context: GraphicsContext) {
        PieceDrawing(geometry: geometry, style: style, symbols: symbols)
            .draw(piece, at: centre, lift: lift, scale: scale, opacity: opacity,
                  symbolOpacity: symbolOpacity, in: context)
    }
}
