// The bands: lift 120–160 ms, travel 180–240 ms, capture ≈250 ms,
// one-ply Undo within 250 ms, flip 300–400 ms. A value inside its band is
// tuning; moving a band is a product decision.

import SwiftUI

enum Motion {

    // MARK: - Selection

    /// Scale and shadow rise, no positional movement. Ease-out, so the piece
    /// answers the tap at once. Deselection reverses it with the same curve.
    static let lift: TimeInterval = 0.14
    static var liftAnimation: Animation { .easeOut(duration: lift) }

    // MARK: - Travel

    /// A one-point step at the floor, the longest board crossing at the ceiling.
    static let travelFloor: TimeInterval = 0.18
    static let travelCeiling: TimeInterval = 0.24

    /// The distance of a one-point step, in cell pitches.
    static let shortestStep: Double = 1
    /// Corner to corner.
    static func longestCrossing(on board: BoardDefinition) -> Double {
        let files = Double(board.fileCount - 1)
        let ranks = Double(board.rankCount - 1)
        return (files * files + ranks * ranks).squareRoot()
    }

    /// Linear in Euclidean distance: every extra pitch buys the same time, and
    /// the band is too narrow for any curve to read differently. Clamped so no
    /// move leaves the band.
    static func travel(distance: Double, on board: BoardDefinition) -> TimeInterval {
        let span = (distance - shortestStep) / (longestCrossing(on: board) - shortestStep)
        return travelFloor + (travelCeiling - travelFloor) * min(max(span, 0), 1)
    }

    /// In pitches. Euclidean, because that is the line the disc is drawn along.
    /// A placement arrives from off the board, so it has no distance.
    static func distance(of move: Move) -> Double {
        guard let from = move.from else { return 0 }
        let df = Double(move.to.file - from.file)
        let dr = Double(move.to.rank - from.rank)
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

    /// How raised the disc in transit is, 0 to 1. A tapped move departs already
    /// raised, since the player was holding it; a rising transit lifts off first.
    static func transitLift(_ progress: Double, rising: Bool) -> Double {
        let rise = rising ? min(progress / riseEnd, 1) : 1
        let settle = progress < settleStart
            ? 1 : (1 - progress) / (1 - settleStart)
        return max(min(rise, settle), 0)
    }

    // MARK: - Capture

    /// The removal completes 50 ms after the arrival, so the whole event is
    /// travel + 50 ms, ≈250 ms mid-band. The lead makes the removal read as
    /// caused by the arrival: the disc gives way under the mover sliding in.
    static let captureFadeLead: TimeInterval = 0.06
    static let captureFade: TimeInterval = 0.11
    /// How far the captured disc shrinks as it fades.
    static let captureShrink: Double = 0.6

    static func captureFadeAnimation(travel: TimeInterval) -> Animation {
        .easeIn(duration: captureFade).delay(travel - captureFadeLead)
    }

    // MARK: - The reveal

    /// The identity comes up on the travelling disc and is fully there as it
    /// lands: one event, so nothing is scheduled after the arrival. It takes the
    /// crossfade's duration, ending exactly where the travel ends.
    static func revealAnimation(travel: TimeInterval) -> Animation {
        .easeInOut(duration: crossfade).delay(max(travel - crossfade, 0))
    }

    // MARK: - Undo

    /// The same distance mapping, so one ply stays within 250 ms and a two-ply
    /// cycle well within 600 ms: both discs travel at once, over the longer
    /// journey. The restored pieces fade in from the movers' departure.
    static let restoreFade: TimeInterval = 0.11
    static var restoreFadeAnimation: Animation { .easeOut(duration: restoreFade) }

    // MARK: - The opponent's reply

    /// A floor, not a delay: the reply departs at the later of the search
    /// returning and this long after the player's move landed, so only a
    /// near-instant reply waits. Long enough that the landing reads as its own
    /// event, short enough not to read as hesitation.
    static let replyFloor: TimeInterval = 0.30

    /// Below this the indicator would flicker rather than read as thinking.
    static let thinkingIndicatorDelay: TimeInterval = 0.40

    // MARK: - Flip

    /// One coordinated re-layout, characters upright throughout.
    static let flip: TimeInterval = 0.35
    static var flipAnimation: Animation { .easeInOut(duration: flip) }

    // MARK: - Pulses

    /// The check rings' one-time stroke-weight swell as they appear. The extra
    /// weight grows into the gap between the rings: the inner ring's inner edge
    /// stays on the 0.42 p floor no marker may cross on an occupied point, and
    /// the outer ring's outer edge on the 0.50 p cell boundary.
    static let checkPulseRise: TimeInterval = 0.12
    static let checkPulseFall: TimeInterval = 0.20
    /// Peak stroke ×1.3, what the band leaves: two 0.025 p strokes in the
    /// 0.08 p between the limits still stand 0.015 p apart at the peak.
    static let checkPulseGain: Double = 0.3

    /// The illegal-tap answer: the legal-destination markers strengthen and
    /// relax, inward or within the cell. Under Reduce Motion the strengthened
    /// state arrives once and stays until the selection changes.
    static let markerPulseRise: TimeInterval = 0.10
    static let markerPulseFall: TimeInterval = 0.20
    /// A destination dot marks an empty point, where only the cell bounds it.
    static let markerDotGain: Double = 0.25
    /// ×1.45. The ring's outer edge stays on the cell boundary, so it grows
    /// inward, with the band's 0.08 p against a 0.055 p stroke; ×1.5 would put
    /// ink past the floor onto the disc.
    static let markerRingGain: Double = 0.45

    // MARK: - The suggested capture's drift

    /// One revolution in ten seconds while a suggestion stands on a capture:
    /// the board's one continuous motion, permitted because the player asked
    /// for the state it marks, and slow enough to read as a living mark rather
    /// than an animation. Reduce Motion stops it.
    static let dashDriftPeriod: TimeInterval = 10

    /// In revolutions. Whole turns are dropped, so the value stays inside one
    /// revolution. Time is an argument so a test need not wait out a clock.
    static func dashDrift(elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        return (elapsed / dashDriftPeriod).truncatingRemainder(dividingBy: 1)
    }

    // MARK: - A refused placement

    /// The Custom Scene editor's answer to a point that will not take the held
    /// piece: the disc shakes off across the point and goes. 360 ms: long
    /// enough for three crossings to read as a refusal, short enough not to be
    /// waited on. 0.10 p is all a body has to move in: a disc's radius is
    /// 0.40 p and its cell reaches 0.50 p.
    static let refusal: TimeInterval = 0.36
    static let refusalCrossings: Double = 3
    static let refusalAmplitude: Double = 0.10

    /// In pitches. Damped, starting and ending on the point, so the disc
    /// settles as it fades. Motion, so Reduce Motion removes it.
    static func refusalOffset(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return sin(clamped * 2 * .pi * refusalCrossings) * refusalAmplitude
            * (1 - clamped)
    }

    // MARK: - The acknowledgment beat

    /// Opacity only, so the beat is identical under Reduce Motion.
    static let beatRise: TimeInterval = 0.10
    static let beatFall: TimeInterval = 0.30
    /// Multiplied into the beat's 0-to-1 progress. Neutral primary, never a
    /// tint: saturated colour on the play screen means a side.
    static let beatPeakOpacity: Double = 0.12

    // MARK: - Everything else

    /// Stands in for position, scale or rotation under Reduce Motion.
    /// `stateFade` paces ordinary state fades.
    static let crossfade: TimeInterval = 0.12
    static let stateFade: TimeInterval = 0.20
    static var stateFadeAnimation: Animation { .easeOut(duration: stateFade) }

    /// The result notice's settle: a spring with barely any bounce, because
    /// the notice is an announcement, not a toy.
    static var noticeAnimation: Animation { .spring(duration: 0.35) }
}
