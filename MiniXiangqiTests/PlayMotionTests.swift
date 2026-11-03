import Testing
@testable import MiniXiangqi

@Suite("The committing-transition gate", .retiringItsCores)
@MainActor
struct PlayMotionTests {

    private func square(_ name: String) -> Square {
        Square(name, on: GameKind.miniXiangqi.board)!
    }

    private func makeMotion(playing line: [String] = [])
        throws -> (PlayMotion, ManualAnimator, FeedbackRecorder) {
        let game = try openGame(on: TestLibraries.fresh())
        try game.replay(line)
        let animator = ManualAnimator()
        let recorder = FeedbackRecorder()
        let motion = PlayMotion(game: game, policy: MotionPolicy(reduceMotion: false),
                                animator: animator.animator, feedback: recorder.feedback)
        return (motion, animator, recorder)
    }

    @Test("A move is a committing transition, and the gate holds until it completes")
    func aMoveHoldsTheGate() throws {
        let (motion, animator, _) = try makeMotion()
        motion.tap(square("b1"))
        #expect(!motion.isCommitting, "a lift is presentational")

        motion.tap(square("b4"))
        #expect(motion.game.moves == ["b1b4"])
        #expect(motion.committing == .move)
        #expect(!motion.canUndo)

        animator.completeAll()
        #expect(!motion.isCommitting)
        #expect(motion.canUndo)
    }

    @Test("Input during a committing transition is discarded, never queued")
    func inputDuringATransitionIsDiscarded() throws {
        let (motion, animator, _) = try makeMotion()
        motion.tap(square("b1"))
        motion.tap(square("b4"))

        motion.tap(square("a2"))
        #expect(motion.game.selected == nil)
        motion.tap(square("a3"))
        #expect(motion.game.moves == ["b1b4"])
        #expect(motion.refusals == 0, "discarded input is not answered")

        animator.completeAll()
        #expect(motion.game.moves == ["b1b4"], "completion replays nothing")
    }

    @Test("A second Undo during an Undo is refused")
    func aSecondUndoIsRefused() throws {
        let (motion, animator, _) = try makeMotion(playing: ["b1b4", "a6a5"])
        motion.undo()
        #expect(motion.committing == .undo)
        motion.undo()
        #expect(motion.game.moves == ["b1b4"], "refused, not queued")

        animator.completeAll()
        motion.undo()
        #expect(motion.game.moves.isEmpty)
    }

    @Test("A flip during a move is deferred, then applied when it lands")
    func aFlipDuringAMoveIsDeferred() throws {
        let (motion, animator, _) = try makeMotion()
        motion.tap(square("b1"))
        motion.tap(square("b4"))
        motion.flip()
        #expect(!motion.game.flipped)

        animator.completeAll()
        #expect(motion.game.flipped)
    }

    @Test("Two flips during a move cancel out, and an idle flip is immediate")
    func flipsCompose() throws {
        let (motion, animator, _) = try makeMotion()
        motion.tap(square("b1"))
        motion.tap(square("b4"))
        motion.flip()
        motion.flip()
        animator.completeAll()
        #expect(!motion.game.flipped)

        motion.flip()
        #expect(motion.game.flipped)
        #expect(!motion.isCommitting)
    }

    @Test("The board's own arrival report lands the move; the backstop cannot double it")
    func arrivalWiresAreIdempotent() throws {
        let (motion, animator, recorder) = try makeMotion()
        motion.tap(square("b1"))
        motion.tap(square("b4"))

        motion.travelArrived()
        #expect(!motion.isCommitting)
        #expect(motion.landings == 1)

        animator.completeAll()
        #expect(motion.landings == 1)
        #expect(recorder.sounds == [.plain])
    }

    @Test("A capture's gate waits for both wires, in either order",
          arguments: [true, false])
    func captureArrivalsCompose(travelFirst: Bool) throws {
        let (motion, _, recorder) = try makeMotion(playing: ["d2d3", "d6d5", "d3d4"])
        motion.tap(square("d5"))
        motion.tap(square("d4"))

        if travelFirst { motion.travelArrived() } else { motion.fadeArrived() }
        #expect(motion.isCommitting, "one wire is not the landing")
        if travelFirst { motion.fadeArrived() } else { motion.travelArrived() }
        #expect(!motion.isCommitting)
        #expect(motion.landings == 1)

        motion.travelArrived()
        motion.fadeArrived()
        #expect(motion.landings == 1, "stray reports land nothing")
        #expect(recorder.sounds == [.capture])
    }

    /// Plays all but the last move of a line, then the last one by two taps.
    private func landing(_ line: [String]) throws -> (PlayMotion, FeedbackRecorder) {
        let last = try #require(line.last.flatMap { Move(text: $0, on: GameKind.miniXiangqi.board) })
        let (motion, animator, recorder) = try makeMotion(playing: Array(line.dropLast()))
        motion.tap(try #require(last.from))
        motion.tap(last.to)
        animator.completeAll()
        return (motion, recorder)
    }

    @Test("A capture sounds like a capture, even one that checks")
    func aCaptureSoundsLikeACapture() throws {
        #expect(try landing(GameTests.captureLine).1.sounds == [.capture])
        let (checking, recorder) = try landing(GameTests.capturingCheckLine)
        #expect(checking.game.evaluation.inCheck)
        #expect(recorder.sounds == [.capture])
    }

    @Test("A checking move sounds the accent")
    func aCheckSoundsTheAccent() throws {
        let (motion, recorder) = try landing(GameTests.checkLine)
        #expect(motion.game.checkedGeneral != nil)
        #expect(recorder.sounds == [.check])
    }

    @Test("A move that ends the game sounds the conclusion instead of a landing")
    func aMateSoundsTheConclusion() throws {
        let (motion, recorder) = try landing(GameTests.mateLine)
        #expect(motion.game.isFinished)
        #expect(recorder.sounds == [.conclusion])
        #expect(motion.landings == 1, "a disc still landed")
    }

    @Test("An Undo that lands back into a check sounds the accent")
    func anUndoIntoCheckSoundsTheAccent() throws {
        let (motion, animator, recorder) = try makeMotion(playing: GameTests.checkLine + ["d5c5"])
        #expect(!motion.game.evaluation.inCheck)

        motion.undo()
        animator.completeAll()
        #expect(motion.game.checkedGeneral != nil)
        #expect(recorder.sounds == [.check])
    }
}
