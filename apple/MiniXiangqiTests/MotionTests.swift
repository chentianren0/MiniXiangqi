// The chosen motion values, held against the accepted bands.
//
// docs/interaction-design.md, "Motion and visual effects", accepts bands and
// leaves the values to implementation; these tests pin every chosen value
// inside its band, the travel mapping's endpoints exactly at the band's edges,
// and the one Reduce Motion rule's answers. A value drifting out of its band
// is a contract violation, not a tuning pass, and this is what notices.

import SwiftUI
import Testing
@testable import MiniXiangqi

@Suite("Motion values against the accepted bands")
@MainActor
struct MotionTests {

    @Test("The selection lift sits inside 120–160 ms")
    func liftBand() {
        #expect(Motion.lift >= 0.12 && Motion.lift <= 0.16)
    }

    @Test("Travel spans exactly the accepted 180–240 ms band")
    func travelBand() {
        // The floor at a one-point step and the ceiling at the longest
        // crossing, exactly: the band's edges are the mapping's endpoints.
        #expect(Motion.travel(distance: Motion.shortestStep) == Motion.travelFloor)
        #expect(Motion.travel(distance: Motion.longestCrossing) == Motion.travelCeiling)
        #expect(Motion.travelFloor == 0.18)
        #expect(Motion.travelCeiling == 0.24)
    }

    @Test("Travel rises monotonically with distance and never leaves the band")
    func travelMonotone() {
        let distances = stride(from: 0.5, through: 10.0, by: 0.25).map { $0 }
        for (near, far) in zip(distances, distances.dropFirst()) {
            #expect(Motion.travel(distance: near) <= Motion.travel(distance: far))
        }
        for distance in distances {
            let duration = Motion.travel(distance: distance)
            #expect(duration >= Motion.travelFloor && duration <= Motion.travelCeiling)
        }
        // Strictly rising inside the endpoints, so a longer move never reads
        // as the same event as a shorter one.
        #expect(Motion.travel(distance: 2) > Motion.travel(distance: 1))
        #expect(Motion.travel(distance: 6) > Motion.travel(distance: 3))
    }

    @Test("A move's distance is the length of the line its disc travels")
    func distanceIsEuclidean() {
        #expect(Motion.distance(of: Move(text: "d4d5")!) == 1)
        #expect(Motion.distance(of: Move(text: "a1g7")!) == Motion.longestCrossing)
        #expect(abs(Motion.distance(of: Move(text: "b1c3")!) - (5.0).squareRoot()) < 0.0001)
    }

    @Test("The capture event ends about 250 ms after it began")
    func captureEvent() {
        // The removal leads the arrival and outlives it by 50 ms, so the
        // whole event is the travel plus that tail: within ~230–290 ms across
        // every distance, and ≈250 ms for the short travels captures usually
        // are. The contract's ≈250 ms is a target, not a wall; the tail is
        // what makes the removal read as caused by the arrival.
        #expect(Motion.captureFade > Motion.captureFadeLead,
                "the removal must outlive the arrival it answers")
        let tail = Motion.captureFade - Motion.captureFadeLead
        #expect(Motion.travelFloor + tail >= 0.20)
        #expect(Motion.travelCeiling + tail <= 0.29)
        for distance in [1.0, 2, 3] {
            let event = Motion.travel(distance: distance) + tail
            #expect(abs(event - 0.25) <= 0.0201,
                    "a short capture, the common one, lands on ≈250 ms")
        }
    }

    @Test("One undone ply completes within the accepted 250 ms")
    func undoWithinItsCeiling() {
        // Undo reuses the travel mapping, and the restored piece returns
        // within the travel, so the slowest ply is the travel ceiling.
        #expect(Motion.travelCeiling <= 0.25)
        #expect(Motion.restoreFade <= Motion.travelFloor)
        // A future decision cycle of two plies stays within its 600 ms.
        #expect(2 * Motion.travelCeiling <= 0.6)
    }

    @Test("The flip sits inside 300–400 ms")
    func flipBand() {
        #expect(Motion.flip >= 0.30 && Motion.flip <= 0.40)
    }

    @Test("The pulses and the beat are brief, and their gains stay in the cell")
    func pulseShapes() {
        #expect(Motion.checkPulseRise + Motion.checkPulseFall <= 0.5)
        #expect(Motion.markerPulseRise + Motion.markerPulseFall <= 0.5)
        #expect(Motion.beatRise + Motion.beatFall <= 0.5)
        #expect(Motion.checkPulseGain > 0 && Motion.markerDotGain > 0
                && Motion.markerRingGain > 0)
        // The strengthened destination dot stays far inside its cell.
        let geometry = BoardGeometry(pitch: BoardGeometry.minimumPitch)
        let dot = geometry.destinationDotDiameter * (1 + Motion.markerDotGain)
        #expect(dot / 2 < geometry.markerOuterLimit)
    }

    @Test("The transit lift holds the disc raised and settles it at the end")
    func transitLiftEnvelope() {
        // A tapped move departs raised — the player was holding it.
        #expect(Motion.transitLift(0, rising: false) == 1)
        #expect(Motion.transitLift(0.5, rising: false) == 1)
        #expect(Motion.transitLift(1, rising: false) == 0)
        // An Undo's disc rises first, because nothing held it.
        #expect(Motion.transitLift(0, rising: true) == 0)
        #expect(Motion.transitLift(Motion.riseEnd, rising: true) == 1)
        #expect(Motion.transitLift(0.5, rising: true) == 1)
        #expect(Motion.transitLift(1, rising: true) == 0)
    }

    // MARK: - The one Reduce Motion rule

    @Test("Movement becomes the brief crossfade under Reduce Motion")
    func movementCrossfades() {
        let full = MotionPolicy(reduceMotion: false)
        let reduced = MotionPolicy(reduceMotion: true)
        let travel = Motion.travelAnimation(0.2)
        #expect(full.movement(travel) == travel)
        #expect(reduced.movement(travel) == reduced.crossfade)
        #expect(reduced.crossfade == .linear(duration: Motion.crossfade))
    }

    @Test("Opacity, colour, stroke, and shadow keep their animation")
    func fadesAreUntouched() {
        let beat = Animation.easeOut(duration: Motion.beatRise)
        #expect(MotionPolicy(reduceMotion: true).fade(beat) == beat)
        #expect(MotionPolicy(reduceMotion: false).fade(beat) == beat)
    }

    @Test("Pulses are removed, never converted")
    func pulsesAreRemoved() {
        let rise = Animation.easeOut(duration: Motion.checkPulseRise)
        #expect(MotionPolicy(reduceMotion: true).pulse(rise) == nil)
        #expect(MotionPolicy(reduceMotion: false).pulse(rise) == rise)
    }

    @Test("A scroll has no crossfade to fall back to, so it arrives at once")
    func scrollsArriveImmediately() {
        #expect(MotionPolicy(reduceMotion: true).scroll(.default) == nil)
        #expect(MotionPolicy(reduceMotion: false).scroll(.default) == .default)
    }

    @Test("The notice's spring does not survive: scale is motion")
    func noticeSpringCrossfades() {
        let reduced = MotionPolicy(reduceMotion: true)
        #expect(reduced.appear == reduced.crossfade)
        #expect(MotionPolicy(reduceMotion: false).appear == Motion.noticeAnimation)
    }

    // MARK: - The phase vectors

    @Test("Square phases interpolate as one vector, so a lift can retarget")
    func squarePhasesArithmetic() {
        let a = Square("b1")!, b = Square("d4")!
        let from = SquarePhases(raised: a)
        let to = SquarePhases(raised: b)

        var delta = to - from
        #expect(delta[a] == -1 && delta[b] == 1)
        delta.scale(by: 0.5)
        let midway = from + delta
        #expect(midway[a] == 0.5 && midway[b] == 0.5)
        #expect(midway.magnitudeSquared == 0.5)

        // Descended squares weigh nothing, so a finished retarget equals the
        // plain target: the vector forgets where the lift came from.
        #expect(from + (to - from) == to)
        #expect(SquarePhases(raised: nil) == SquarePhases.zero)
    }

    @Test("Board phases compose componentwise")
    func boardPhasesArithmetic() {
        var phases = BoardPhases(travel: 1, fade: 0.5, flip: 1, check: 0.2, marker: 0.4)
        phases.scale(by: 0.5)
        #expect(phases.travel == 0.5 && phases.fade == 0.25 && phases.flip == 0.5)
        let sum = phases + phases
        #expect(sum.travel == 1 && sum.check == 0.2 && sum.marker == 0.4)
        #expect((sum - phases).fade == 0.25)
        #expect(BoardPhases.zero.magnitudeSquared == 0)
    }
}
