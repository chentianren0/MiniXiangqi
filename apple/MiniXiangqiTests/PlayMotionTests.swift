// The interruption rule, pinned without a wall clock.
//
// docs/interaction-design.md, "Motion and visual effects": a committing
// transition — a move, a capture, an Undo — runs to completion, and input
// arriving during it is discarded rather than queued; a second Undo waits;
// a flip alone is deferred and applied when the transition ends. The animator
// is the seam that makes this observable: the manual one below holds every
// completion until the test fires it, so "during a transition" is a state the
// test stands in for as long as it likes.

import Testing
@testable import MiniXiangqi

/// Runs animation bodies at once and parks their completions for the test to
/// fire in order, exactly as the live animator fires them.
@MainActor
private final class ManualAnimator {
    private(set) var pending: [() -> Void] = []

    var animator: MotionAnimator {
        MotionAnimator { [self] _, body, completion in
            body()
            pending.append(completion)
        }
    }

    /// Fires the oldest parked completion, as time passing would.
    func completeNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()()
    }

    func completeAll() {
        while !pending.isEmpty { completeNext() }
    }
}

@MainActor
private final class FeedbackRecorder {
    private(set) var events: [Feedback.Event] = []
    var feedback: Feedback {
        Feedback { [self] event in events.append(event) }
    }
}

@Suite("The committing-transition gate")
@MainActor
struct PlayMotionTests {

    private func makeMotion(
        playing line: [String] = [],
        reduceMotion: Bool = false
    ) throws -> (PlayMotion, ManualAnimator, FeedbackRecorder) {
        let game = try Game(core: Core.shared.get())
        try game.replay(line)
        let animator = ManualAnimator()
        let recorder = FeedbackRecorder()
        let motion = PlayMotion(game: game,
                                policy: MotionPolicy(reduceMotion: reduceMotion),
                                animator: animator.animator,
                                feedback: recorder.feedback)
        return (motion, animator, recorder)
    }

    // MARK: - Moves

    @Test("A move is a committing transition, and the gate holds until it completes")
    func aMoveHoldsTheGate() throws {
        let (motion, animator, _) = try makeMotion()

        motion.tap(Square("b1")!)
        #expect(motion.game.selected == Square("b1"))
        #expect(!motion.isCommitting, "a lift is presentational, not committing")

        motion.tap(Square("b4")!)
        #expect(motion.game.moves == ["b1b4"], "the move commits at once")
        #expect(motion.committing == .move)
        #expect(motion.transit?.move == Move(text: "b1b4"))
        #expect(motion.transit?.fading == nil, "nothing stood on b4")
        #expect(!motion.canUndo, "Undo is unavailable during the transition")

        animator.completeAll()
        #expect(!motion.isCommitting)
        #expect(motion.transit == nil)
        #expect(motion.canUndo)
    }

    @Test("Input during a committing transition is discarded, never queued")
    func inputDuringATransitionIsDiscarded() throws {
        let (motion, animator, recorder) = try makeMotion()
        motion.tap(Square("b1")!)
        motion.tap(Square("b4")!)
        #expect(motion.isCommitting)

        // A tap that would select, and one that would move: both discarded.
        motion.tap(Square("a2")!)
        #expect(motion.game.selected == nil, "a selection tap during a transition is discarded")
        motion.tap(Square("a3")!)
        #expect(motion.game.moves == ["b1b4"], "no queued move plays afterwards")
        #expect(recorder.events.isEmpty,
                "discarded input is silent: no beat, no landing, nothing")

        animator.completeAll()
        #expect(motion.game.moves == ["b1b4"], "completion replays nothing")

        // The same taps after the transition are ordinary input again.
        motion.tap(Square("a2")!)
        #expect(motion.game.selected == nil, "a2 is Black's turn now — nothing to select")
    }

    @Test("A second Undo during an Undo is refused")
    func aSecondUndoIsRefused() throws {
        let (motion, animator, _) = try makeMotion(playing: ["b1b4", "a6a5"])

        motion.undo()
        #expect(motion.committing == .undo)
        #expect(motion.game.moves == ["b1b4"], "the first Undo took its ply")
        #expect(!motion.canUndo)

        motion.undo()
        #expect(motion.game.moves == ["b1b4"], "the second is refused, not queued")

        animator.completeAll()
        #expect(!motion.isCommitting)
        motion.undo()
        #expect(motion.game.moves.isEmpty, "after completion an Undo is welcome again")
    }

    @Test("A flip during a move is deferred, then applied when it lands")
    func aFlipDuringAMoveIsDeferred() throws {
        let (motion, animator, _) = try makeMotion()
        motion.tap(Square("b1")!)
        motion.tap(Square("b4")!)

        motion.flip()
        #expect(!motion.game.flipped, "the flip waits for the landing")
        #expect(motion.flipDeferred)

        animator.completeAll()
        #expect(motion.game.flipped, "the deferred flip applies at the landing")
        #expect(!motion.flipDeferred)
    }

    @Test("Two flips during a move cancel out, and an idle flip is immediate")
    func flipsCompose() throws {
        let (motion, animator, _) = try makeMotion()
        motion.tap(Square("b1")!)
        motion.tap(Square("b4")!)
        motion.flip()
        motion.flip()
        animator.completeAll()
        #expect(!motion.game.flipped, "two deferred flips are no flip at all")

        motion.flip()
        #expect(motion.game.flipped, "an idle flip applies at once")
        #expect(!motion.isCommitting, "a flip is never a committing transition")
    }

    // MARK: - Captures

    @Test("A capture holds the gate through the removal's tail")
    func aCaptureHoldsTheGateForItsTail() throws {
        // Black's soldier takes the red soldier on d4.
        let (motion, animator, recorder) = try makeMotion(playing: ["d2d3", "d6d5", "d3d4"])
        motion.tap(Square("d5")!)
        motion.tap(Square("d4")!)

        #expect(motion.committing == .move)
        #expect(motion.transit?.fading?.piece == Piece(kind: .soldier, side: .red))
        #expect(motion.transit?.fading?.at == Square("d4"))

        animator.completeNext()   // the selection lift
        #expect(recorder.events.isEmpty, "nothing has landed yet")
        animator.completeNext()   // the travel: the arrival
        #expect(recorder.events == [.landing], "the landing reports at the arrival")
        #expect(motion.isCommitting, "the removal's 50 ms tail still holds the gate")

        animator.completeNext()   // the removal's tail
        #expect(!motion.isCommitting)
        #expect(motion.transit == nil)
    }

    // MARK: - Undo as travel

    @Test("Undo travels the move back and returns the captured piece")
    func undoRestoresTheCapture() throws {
        let (motion, animator, _) = try makeMotion(playing: ["d2d3", "d6d5", "d3d4", "d5d4"])

        motion.undo()
        #expect(motion.game.moves == ["d2d3", "d6d5", "d3d4"])
        let transit = try #require(motion.transit)
        #expect(transit.kind == .undo)
        #expect(transit.move == Move(from: Square("d4")!, to: Square("d5")!),
                "the piece travels back the way it came")
        #expect(transit.fading?.piece == Piece(kind: .soldier, side: .red),
                "the captured piece returns where it stood")
        #expect(transit.fading?.at == Square("d4"))
        #expect(motion.transitFade == 1, "the return is scheduled with the departure")

        animator.completeAll()
        #expect(!motion.isCommitting)
        #expect(motion.game.placement[Square("d4")!] == Piece(kind: .soldier, side: .red))
    }

    // MARK: - The two arrival wires

    @Test("The board's own arrival report lands the move; the backstop cannot double it")
    func arrivalWiresAreIdempotent() throws {
        let (motion, animator, recorder) = try makeMotion()
        motion.tap(Square("b1")!)
        motion.tap(Square("b4")!)

        motion.travelArrived()   // the canvas frame reaching its target
        #expect(!motion.isCommitting, "the arrival opens the gate")
        #expect(recorder.events == [.landing])

        animator.completeAll()   // the transaction completion, arriving late
        #expect(recorder.events == [.landing], "the second wire reports nothing")
    }

    @Test("A capture's gate waits for both wires, in either order")
    func captureArrivalsCompose() throws {
        let (motion, _, recorder) = try makeMotion(playing: ["d2d3", "d6d5", "d3d4"])
        motion.tap(Square("d5")!)
        motion.tap(Square("d4")!)

        motion.travelArrived()
        #expect(recorder.events == [.landing])
        #expect(motion.isCommitting, "the removal's tail still holds the gate")
        motion.fadeArrived()
        #expect(!motion.isCommitting)

        // Stray reports after the landing answer to nothing.
        motion.travelArrived()
        motion.fadeArrived()
        #expect(recorder.events == [.landing])
        #expect(!motion.isCommitting)
    }

    // MARK: - The feedback moments

    @Test("Landing feedback fires at the landing, not the lift")
    func landingFiresAtTheLanding() throws {
        let (motion, animator, recorder) = try makeMotion()
        motion.tap(Square("b1")!)
        motion.tap(Square("b4")!)
        #expect(recorder.events.isEmpty, "commitment is not arrival")

        animator.completeNext()   // the lift's completion
        #expect(recorder.events.isEmpty)
        animator.completeNext()   // the travel's completion
        #expect(recorder.events == [.landing])
    }

    @Test("An illegal tap answers at the touch and strengthens the markers")
    func illegalTapAnswers() throws {
        let (motion, animator, recorder) = try makeMotion()
        motion.tap(Square("b1")!)
        animator.completeAll()

        motion.tap(Square("c3")!)   // no cannon move reaches c3
        #expect(recorder.events == [.acknowledgement],
                "the touch is answered before anything is drawn")
        #expect(motion.game.selected == Square("b1"), "the selection is retained")
        #expect(motion.markerEmphasis == 1, "the legal destinations strengthen")

        animator.completeAll()
        #expect(motion.markerEmphasis == 0, "the pulse relaxes")
    }

    @Test("Under Reduce Motion the markers strengthen once and stay")
    func illegalTapUnderReduceMotion() throws {
        let (motion, animator, recorder) = try makeMotion(reduceMotion: true)
        motion.tap(Square("b1")!)
        animator.completeAll()

        motion.tap(Square("c3")!)
        #expect(recorder.events == [.acknowledgement])
        #expect(motion.markerEmphasis == 1)
        animator.completeAll()
        #expect(motion.markerEmphasis == 1,
                "a single state change, no pulse: the answer stays")

        motion.tap(Square("a2")!)   // switching the selection clears it
        #expect(motion.markerEmphasis == 0)
    }

    @Test("A tap that selects nothing gets the acknowledgment beat")
    func emptyTapGetsTheBeat() throws {
        let (motion, animator, recorder) = try makeMotion()

        motion.tap(Square("d4")!)   // empty, and nothing is selected
        #expect(recorder.events == [.acknowledgement])
        #expect(motion.beatEmphasis == 1, "the background rises to full emphasis")

        animator.completeAll()
        #expect(motion.beatEmphasis == 0, "and falls back")
        #expect(motion.game.selected == nil)
    }

    // MARK: - The check pulse

    @Test("A checking move pulses the rings at its landing, not its commit")
    func checkPulsesAtTheLanding() throws {
        let (motion, animator, _) = try makeMotion(playing: ["b1b3", "d6d5"])
        motion.tap(Square("b3")!)
        motion.tap(Square("d3")!)

        #expect(motion.game.checkedGeneral != nil, "the line gives check")
        #expect(motion.checkEmphasis == 0, "no pulse while the move still travels")

        animator.completeNext()   // the lift
        animator.completeNext()   // the travel: the landing
        #expect(motion.checkEmphasis == 1, "the rings appear swelling")
        animator.completeAll()
        #expect(motion.checkEmphasis == 0, "once, and never again")
    }

    @Test("Under Reduce Motion the check pulse is removed, not converted")
    func checkPulseRemovedUnderReduceMotion() throws {
        let (motion, animator, _) = try makeMotion(playing: ["b1b3", "d6d5"],
                                                   reduceMotion: true)
        motion.tap(Square("b3")!)
        motion.tap(Square("d3")!)
        animator.completeAll()
        #expect(motion.game.checkedGeneral != nil)
        #expect(motion.checkEmphasis == 0,
                "the ring and the 将军 token already say everything")
    }

    // MARK: - Cancelling

    @Test("Tapping outside the board cancels the selection and nothing else")
    func outsideTapCancels() throws {
        let (motion, _, recorder) = try makeMotion()
        motion.tap(Square("b1")!)
        motion.cancelSelection()
        #expect(motion.game.selected == nil)
        #expect(recorder.events.isEmpty, "a cancel is accepted input — no beat")

        motion.cancelSelection()
        #expect(recorder.events.isEmpty, "with nothing selected it answers nothing")
    }
}
