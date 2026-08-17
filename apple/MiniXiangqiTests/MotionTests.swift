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

    private let miniBoard = GameKind.miniXiangqi.board
    private let xiangqiBoard = GameKind.xiangqi.board

    @Test("The selection lift sits inside 120–160 ms")
    func liftBand() {
        #expect(Motion.lift >= 0.12 && Motion.lift <= 0.16)
    }

    @Test("Travel spans exactly the accepted 180–240 ms band")
    func travelBand() {
        // The floor at a one-point step and the ceiling at the longest
        // crossing, exactly: the band's edges are the mapping's endpoints.
        #expect(Motion.travel(distance: Motion.shortestStep, on: miniBoard)
                == Motion.travelFloor)
        #expect(Motion.travel(distance: Motion.longestCrossing(on: miniBoard), on: miniBoard)
                == Motion.travelCeiling)
        #expect(Motion.travel(distance: Motion.shortestStep, on: xiangqiBoard)
                == Motion.travelFloor)
        #expect(Motion.travel(distance: Motion.longestCrossing(on: xiangqiBoard),
                              on: xiangqiBoard) == Motion.travelCeiling)
        #expect(Motion.travelFloor == 0.18)
        #expect(Motion.travelCeiling == 0.24)
    }

    @Test("Travel rises monotonically with distance and never leaves the band")
    func travelMonotone() {
        let distances = stride(from: 0.5, through: 10.0, by: 0.25).map { $0 }
        for board in [miniBoard, xiangqiBoard] {
            for (near, far) in zip(distances, distances.dropFirst()) {
                #expect(Motion.travel(distance: near, on: board)
                        <= Motion.travel(distance: far, on: board))
            }
            for distance in distances {
                let duration = Motion.travel(distance: distance, on: board)
                #expect(duration >= Motion.travelFloor && duration <= Motion.travelCeiling)
            }
        }
        // Strictly rising inside the endpoints, so a longer move never reads
        // as the same event as a shorter one.
        #expect(Motion.travel(distance: 2, on: miniBoard)
                > Motion.travel(distance: 1, on: miniBoard))
        #expect(Motion.travel(distance: 6, on: xiangqiBoard)
                > Motion.travel(distance: 3, on: xiangqiBoard))
    }

    @Test("A move's distance is the length of the line its disc travels")
    func distanceIsEuclidean() {
        #expect(Motion.distance(of: Move(text: "d4d5", on: miniBoard)!) == 1)
        #expect(Motion.distance(of: Move(text: "a1g7", on: miniBoard)!)
                == Motion.longestCrossing(on: miniBoard))
        #expect(Motion.distance(of: Move(text: "a1i10", on: xiangqiBoard)!)
                == Motion.longestCrossing(on: xiangqiBoard))
        #expect(abs(Motion.distance(of: Move(text: "b1c3", on: miniBoard)!)
                    - (5.0).squareRoot()) < 0.0001)
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
            let event = Motion.travel(distance: distance, on: miniBoard) + tail
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

    @Test("The pulses and the beat are brief, and every one of them swells")
    func pulseShapes() {
        #expect(Motion.checkPulseRise + Motion.checkPulseFall <= 0.5)
        #expect(Motion.markerPulseRise + Motion.markerPulseFall <= 0.5)
        #expect(Motion.beatRise + Motion.beatFall <= 0.5)
        #expect(Motion.checkPulseGain > 0 && Motion.markerDotGain > 0
                && Motion.markerRingGain > 0)
        // The strengthened destination dot stays far inside its cell. It marks
        // an empty point, so the floor the two rings answer to does not apply.
        let geometry = BoardGeometry(board: miniBoard,
                                     pitch: BoardGeometry.minimumPitch(for: miniBoard))
        #expect(geometry.destinationDotDiameter(emphasis: 1) / 2 < geometry.markerOuterLimit)
    }

    @Test("Every swollen ring's ink stays inside the marker band")
    func swollenRingsStayInTheMarkerBand() {
        // Both rings are drawn around an *occupied* point — a disc the player
        // may take, a general in check — so both are bounded at both ends: no
        // marker's ink inside markerInnerLimit, every marker inside its own
        // cell. The peak is where that is decided, and where both rings first
        // got it wrong: the check swell reached 0.405 p and the strengthened
        // capture ring 0.4175 p, both of them onto the disc.
        //
        // The inner edges are pinned *on* the floor by construction, so they
        // are compared with the hair floating point leaves on an equality.
        let hair: CGFloat = 1e-9
        for pitch in [BoardGeometry.minimumPitch(for: miniBoard), 60,
                      BoardGeometry.maximumPitch(for: miniBoard)] {
            let geometry = BoardGeometry(board: miniBoard, pitch: pitch)

            let capture = geometry.captureRingStroke(emphasis: 1)
            let captureRadius = geometry.captureRingRadius(stroke: capture)
            #expect(captureRadius - capture / 2 >= geometry.markerInnerLimit - hair,
                    "the strengthened capture ring must not reach the disc it rings")
            #expect(captureRadius + capture / 2 <= geometry.markerOuterLimit + hair,
                    "and its outer edge stays at the cell boundary")

            let check = geometry.checkRingStroke(emphasis: 1)
            let rings = geometry.checkRingRadii(emphasis: 1)
            #expect(rings.inner - check / 2 >= geometry.markerInnerLimit - hair,
                    "the swollen inner ring must not reach the general it rings")
            #expect(rings.outer + check / 2 <= geometry.markerOuterLimit + hair,
                    "and the outer one stays inside its cell")
            #expect(rings.inner + check / 2 < rings.outer - check / 2,
                    "the two must still read as two at the peak: a double ring")
        }
    }

    @Test("At rest the swells leave the settled geometry exactly as it is")
    func pulsesRestOnTheSettledGeometry() {
        let geometry = BoardGeometry(board: miniBoard, pitch: 60)
        #expect(geometry.checkRingStroke(emphasis: 0) == geometry.checkRingStroke)
        #expect(geometry.checkRingRadii(emphasis: 0).inner == geometry.checkRingInnerRadius)
        #expect(geometry.checkRingRadii(emphasis: 0).outer == geometry.checkRingOuterRadius)
        #expect(geometry.captureRingStroke(emphasis: 0) == geometry.captureRingStroke)
        #expect(geometry.destinationDotDiameter(emphasis: 0) == geometry.destinationDotDiameter)
        // The band's two limits are where the rings already hang from at rest,
        // which is why the swell has nowhere to grow but between them.
        #expect(abs(geometry.checkRingInnerRadius - geometry.checkRingStroke / 2
                    - geometry.markerInnerLimit) < 1e-9)
        #expect(abs(geometry.checkRingOuterRadius + geometry.checkRingStroke / 2
                    - geometry.markerOuterLimit) < 1e-9)
    }

    // MARK: - The one continuous motion

    @Test("A suggested capture's dashes turn a revolution in about ten seconds")
    func dashDriftTurnsSlowly() {
        #expect(Motion.dashDriftPeriod >= 8 && Motion.dashDriftPeriod <= 12,
                "the contract accepts roughly ten seconds")
        #expect(Motion.dashDrift(elapsed: 0) == 0,
                "the dashes start where the pattern draws them at rest")
        #expect(Motion.dashDrift(elapsed: Motion.dashDriftPeriod / 4) == 0.25)
        #expect(Motion.dashDrift(elapsed: Motion.dashDriftPeriod) == 0,
                "a whole revolution is the rest position again")
        #expect(Motion.dashDrift(elapsed: 2.5 * Motion.dashDriftPeriod) == 0.5,
                "and whole turns are dropped, however long a suggestion stands")
        // Monotone inside a revolution, and never outside one: the phase is a
        // position on the ring, not an accumulating quantity.
        var previous = -1.0
        for step in 0..<100 {
            let drift = Motion.dashDrift(elapsed: Double(step) / 100 * Motion.dashDriftPeriod)
            #expect(drift >= 0 && drift < 1)
            #expect(drift > previous)
            previous = drift
        }
    }

    // MARK: - The refused placement

    @Test("A refused disc shakes across its point and stays inside the cell")
    func refusalShakeIsBoundedByTheCell() {
        #expect(Motion.refusalOffset(0) == 0,
                "the disc is offered on the point it was aimed at")
        #expect(Motion.refusalOffset(1) == 0, "and it ends there")
        // Damped: every crossing is smaller than the one before, so the disc
        // settles as it fades rather than being cut off mid-swing.
        #expect(abs(Motion.refusalOffset(0.25 / Motion.refusalCrossings))
                > abs(Motion.refusalOffset(1 - 0.25 / Motion.refusalCrossings)))

        // The stated containment: a disc carried this far from the centre keeps
        // its whole body inside the point's own cell, at every board size,
        // because both quantities are fractions of the pitch. Measured against
        // the drawn disc rather than against the constant.
        let geometry = BoardGeometry(board: GameKind.xiangqi.board, pitch: 44)
        let reach = Motion.refusalAmplitude * geometry.pitch
            + geometry.discDiameter / 2
        #expect(reach <= geometry.markerOuterLimit + 1e-9)
        // And the amplitude is what the offset actually reaches, so the bound
        // above is a bound on the drawn disc rather than on a constant.
        let peak = (0...1000).map { abs(Motion.refusalOffset(Double($0) / 1000)) }.max()!
        #expect(peak <= Motion.refusalAmplitude)
    }

    @Test("The dashes turn only for a suggested capture, and never under Reduce Motion")
    func dashDriftRunsOnlyWhileASuggestedCaptureStands() {
        let board = GameKind.miniXiangqi.board
        let capture = Square("d4", on: board)!
        let empty = Square("d3", on: board)!
        func view(suggested: Square?, reduceMotion: Bool = false) -> BoardView {
            BoardView(geometry: BoardGeometry(board: board,
                                              pitch: BoardGeometry.minimumPitch(for: board)),
                      placement: Placement(fen: frozenStart(.miniXiangqi),
                                           game: .miniXiangqi),
                      destinations: [capture, empty],
                      captures: [capture],
                      suggested: suggested,
                      hintEmphasis: suggested == nil ? 0 : 1,
                      policy: MotionPolicy(reduceMotion: reduceMotion))
        }
        #expect(view(suggested: capture).driftsDashes)
        #expect(!view(suggested: empty).driftsDashes,
                "an empty point has no dashes to turn")
        #expect(!view(suggested: nil).driftsDashes,
                "and the drift ends with everything that ends the suggestion")
        #expect(!view(suggested: capture, reduceMotion: true).driftsDashes,
                "a rotation is motion, so Reduce Motion holds the dashes still")
    }

    // MARK: - The suggestion's own phase

    @Test("A standing suggestion mutes every destination marker but its own")
    func aSuggestionMutesTheRestOfTheSet() {
        let board = GameKind.miniXiangqi.board
        let suggested = Square("b4", on: board)!
        let other = Square("c4", on: board)!

        #expect(BoardPhases.zero.muting(at: other) == 0,
                "with no suggestion on the board the whole set is active ink")

        let shown = BoardPhases(hint: SquarePhases(suggested, at: 1))
        #expect(shown.muting(at: suggested) == 0,
                "the suggested marker is the one active-ink marker the set shows")
        #expect(shown.muting(at: other) == 1)

        // Arriving and clearing are the same interpolation seen from two ends,
        // and the suggested marker is never muted at any point along it.
        let arriving = BoardPhases(hint: SquarePhases(suggested, at: 0.4))
        #expect(arriving.muting(at: suggested) == 0)
        #expect(arriving.muting(at: other) == 0.4)

        // A suggestion that moves carries the muting with it rather than
        // dropping the whole set and raising it again.
        let midway = BoardPhases(hint: SquarePhases([suggested: 0.5, other: 0.5]))
        #expect(midway.muting(at: suggested) == 0)
        #expect(midway.muting(at: other) == 0)
        #expect(midway.muting(at: Square("d4", on: board)!) == 0.5)
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
        let board = GameKind.miniXiangqi.board
        let a = Square("b1", on: board)!, b = Square("d4", on: board)!
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
        let suggested = Square("b4", on: GameKind.miniXiangqi.board)!
        var phases = BoardPhases(travel: 1, fade: 0.5, flip: 1, check: 0.2, marker: 0.4,
                                 hint: SquarePhases(suggested, at: 1))
        phases.scale(by: 0.5)
        #expect(phases.travel == 0.5 && phases.fade == 0.25 && phases.flip == 0.5)
        #expect(phases.hint[suggested] == 0.5,
                "the suggestion interpolates with everything else, per square")
        let sum = phases + phases
        #expect(sum.travel == 1 && sum.check == 0.2 && sum.marker == 0.4)
        #expect(sum.hint[suggested] == 1)
        #expect((sum - phases).fade == 0.25)
        #expect((sum - phases).hint[suggested] == 0.5)
        #expect(BoardPhases.zero.magnitudeSquared == 0)
        #expect(BoardPhases(hint: SquarePhases(suggested, at: 1)).magnitudeSquared == 1)

        // The settle phase's resting value is **one**, and it is carried by the
        // point being unmentioned rather than by a number. A board that is
        // played says nothing about any point, and every disc on it is drawn at
        // full size; a point mentioned at nothing is a disc that has gone. The
        // two are not the same answer, and a reader that could not tell them
        // apart would draw every piece in the app at zero size.
        #expect(BoardPhases.zero.settled.stated(suggested) == nil,
                "a played board mentions no point, so every disc is at rest")
        #expect(SquarePhases([suggested: 0]).stated(suggested) == 0,
                "and a leaving point is mentioned at nothing, which is not nil")
    }
}
