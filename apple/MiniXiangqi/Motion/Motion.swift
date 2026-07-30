// Every duration, curve, and proportion of the motion language, in one place.
//
// docs/interaction-design.md, "Motion and visual effects", accepts bands —
// lift 120–160 ms, travel 180–240 ms, capture ≈250 ms, one-ply Undo within
// 250 ms, flip 300–400 ms — and leaves the exact values to be settled against
// running hardware. These are the settled values, and MotionTests pins each one
// inside its band rather than trusting this comment. A change to an accepted
// band is a contract change; a change to a value inside one is a tuning pass.

import SwiftUI

enum Motion {

    // MARK: - Selection

    /// The lift: scale and shadow rise, no positional movement. 140 ms, the
    /// middle of the accepted 120–160 ms band; ease-out, so the piece answers
    /// the tap at once and settles into the raised state. Deselection reverses
    /// it with the same curve.
    static let lift: TimeInterval = 0.14
    static var liftAnimation: Animation { .easeOut(duration: lift) }

    // MARK: - Travel

    /// Travel scales with distance inside the accepted 180–240 ms band: a
    /// one-point step at the floor, the longest board crossing at the ceiling.
    static let travelFloor: TimeInterval = 0.18
    static let travelCeiling: TimeInterval = 0.24

    /// The distance of a one-point step, in cell pitches.
    static let shortestStep: Double = 1
    /// The longest crossing this board offers, corner to corner: √(6² + 6²).
    static let longestCrossing: Double = (72.0).squareRoot()

    /// The accepted mapping is a chosen proportion, not a derived quantity.
    /// The choice: linear in Euclidean distance between the two accepted
    /// endpoints. Linear is the one mapping with nothing to explain — every
    /// extra pitch of distance buys the same extra time — and the band is
    /// narrow enough that no curve within it could read differently.
    /// Monotone by construction; clamped so no move leaves the band.
    static func travel(distance: Double) -> TimeInterval {
        let span = (distance - shortestStep) / (longestCrossing - shortestStep)
        return travelFloor + (travelCeiling - travelFloor) * min(max(span, 0), 1)
    }

    /// The distance a move travels, in pitches. Euclidean, because that is the
    /// length of the line the disc is drawn along.
    static func distance(of move: Move) -> Double {
        let df = Double(move.to.file - move.from.file)
        let dr = Double(move.to.rank - move.from.rank)
        return (df * df + dr * dr).squareRoot()
    }

    /// A slid piece starts and stops like a hand: ease in, ease out.
    static func travelAnimation(_ duration: TimeInterval) -> Animation {
        .easeInOut(duration: duration)
    }

    /// The mover rides raised and settles onto its point over the final
    /// quarter of the way — the set-down that the landing feedback reports.
    /// An Undo's mover starts at rest, so it rises over the first fifth.
    static let settleStart: Double = 0.75
    static let riseEnd: Double = 0.20

    /// How raised the disc in transit is, 0 to 1, at `progress` of the way.
    /// A tapped move departs already raised — the player was holding it —
    /// while a rising transit lifts off first; both settle at the end.
    static func transitLift(_ progress: Double, rising: Bool) -> Double {
        let rise = rising ? min(progress / riseEnd, 1) : 1
        let settle = progress < settleStart
            ? 1 : (1 - progress) / (1 - settleStart)
        return max(min(rise, settle), 0)
    }

    // MARK: - Capture

    /// The captured disc's scale-and-fade begins this long before the mover
    /// arrives and runs this long, so the removal completes 50 ms after the
    /// arrival that caused it. The whole event is travel + 50 ms: ≈250 ms at
    /// the middle of the travel band, exactly as the contract targets.
    /// The lead is what makes the removal read as caused by the arrival —
    /// the disc gives way under the mover sliding in, and the tail finishes
    /// under the mover, which lands on top.
    static let captureFadeLead: TimeInterval = 0.06
    static let captureFade: TimeInterval = 0.11
    /// How far the captured disc shrinks as it fades.
    static let captureShrink: Double = 0.6

    static func captureFadeAnimation(travel: TimeInterval) -> Animation {
        .easeIn(duration: captureFade).delay(travel - captureFadeLead)
    }

    // MARK: - Undo

    /// Undo reverses the move visually with the same distance mapping, so one
    /// ply completes within the accepted 250 ms (the ceiling is 240 ms), and a
    /// future decision cycle of two plies within the accepted 600 ms. The
    /// restored piece fades back in from the mover's departure, the capture
    /// read backwards.
    static let restoreFade: TimeInterval = 0.11
    static var restoreFadeAnimation: Animation { .easeOut(duration: restoreFade) }

    // MARK: - The opponent's reply

    /// The AI's move has a floor, not a delay: its piece departs at the later
    /// of the search returning and this long after the player's own move
    /// finished animating. A search of a second or more is unaffected — the
    /// floor has long since passed — and only a near-instant reply waits, so
    /// the AI never appears to twitch rather than move.
    ///
    /// 300 ms: long enough that the player's landing has been seen and heard as
    /// its own event before the answer starts, short enough that nobody waiting
    /// for a reply reads it as hesitation. Measured from the arrival rather than
    /// from the tap that committed it, because the arrival is when the player's
    /// move finished being shown.
    static let replyFloor: TimeInterval = 0.30

    /// How long a search must run before its activity is worth showing. Below
    /// this the indicator would appear and vanish inside a third of a second,
    /// which reads as a flicker rather than as thinking.
    static let thinkingIndicatorDelay: TimeInterval = 0.40

    // MARK: - Flip

    /// 350 ms, the middle of the accepted 300–400 ms band: one coordinated
    /// re-layout, characters upright throughout.
    static let flip: TimeInterval = 0.35
    static var flipAnimation: Animation { .easeInOut(duration: flip) }

    // MARK: - Pulses

    /// The check rings' one-time stroke-weight pulse as they appear: a swell
    /// and a settle. The extra weight grows into the gap *between* the two
    /// rings, which is the only room the marker band has: at rest the inner
    /// ring's inner edge already sits on the 0.42 p floor no marker may cross
    /// on an occupied point, and the outer ring's outer edge on the 0.50 p
    /// cell boundary. Both of those edges are pinned through the swell.
    static let checkPulseRise: TimeInterval = 0.12
    static let checkPulseFall: TimeInterval = 0.20
    /// Peak stroke ×1.3, which is what the band leaves: two 0.025 p strokes in
    /// the 0.08 p between the limits still stand 0.015 p apart at the peak —
    /// the same near-meeting the swell has always read as, the swell reading
    /// as one emphasis before the double ring separates again. BoardGeometry
    /// shapes it, and MotionTests pins the peak against both limits.
    static let checkPulseGain: Double = 0.3

    /// The illegal-tap answer: the legal-destination markers strengthen and
    /// relax — the dots grow a quarter, the capture rings' stroke by not quite
    /// half, both inward or within the cell. Under Reduce Motion the
    /// strengthened state arrives once and stays until the selection changes.
    static let markerPulseRise: TimeInterval = 0.10
    static let markerPulseFall: TimeInterval = 0.20
    /// A destination dot marks an empty point, where only the cell bounds it.
    static let markerDotGain: Double = 0.25
    /// ×1.45. The capture ring's outer edge stays at the cell boundary, where
    /// the contract fixes it, so the strengthening grows inward — and inward
    /// it has the marker band's 0.08 p to spend against a 0.055 p stroke. Half
    /// again would put ink 0.0025 p past the floor, onto the disc the ring is
    /// drawn around.
    static let markerRingGain: Double = 0.45

    // MARK: - The acknowledgment beat

    /// The turn status's background rises to full emphasis and falls back,
    /// opacity only, no movement. Opacity is not motion, so the beat is
    /// identical under Reduce Motion.
    static let beatRise: TimeInterval = 0.10
    static let beatFall: TimeInterval = 0.30
    /// The opacity full emphasis reaches — what the beat's 0-to-1 progress is
    /// multiplied by, not the progress itself. Neutral primary, never a tint:
    /// saturated colour on the play screen means which side a piece belongs to.
    static let beatPeakOpacity: Double = 0.12

    // MARK: - Everything else

    /// The brief crossfade that replaces animated position, scale, or rotation
    /// under Reduce Motion, and the pace of ordinary state fades — the result
    /// notice arriving over the board, a marker set appearing.
    static let crossfade: TimeInterval = 0.12
    static let stateFade: TimeInterval = 0.20
    static var stateFadeAnimation: Animation { .easeOut(duration: stateFade) }

    /// The result notice's settle: a spring with barely any bounce, because
    /// the notice is an announcement, not a toy.
    static var noticeAnimation: Animation { .spring(duration: 0.35) }
}
