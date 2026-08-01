// The interruption rule, pinned without a wall clock.
//
// docs/interaction-design.md, "Motion and visual effects": a committing
// transition — a move, a capture, an Undo — runs to completion, and input
// arriving during it is discarded rather than queued; a second Undo waits;
// a flip alone is deferred and applied when the transition ends. The animator
// is the seam that makes this observable: the manual one in TestSupport holds
// every completion until the test fires it, so "during a transition" is a
// state the test stands in for as long as it likes.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The committing-transition gate", .retiringItsCores)
@MainActor
struct PlayMotionTests {

    private func makeMotion(
        playing line: [String] = [],
        reduceMotion: Bool = false,
        rules: Rules? = nil,
        defaults: UserDefaults? = nil
    ) throws -> (PlayMotion, ManualAnimator, FeedbackRecorder) {
        // The real core over a scratch store, unless the test brought the
        // refusing stand-in — which wraps one of the same.
        let game = try openGame(on: rules ?? TestCores.fresh())
        try game.replay(line)
        let animator = ManualAnimator()
        let recorder = try FeedbackRecorder(
            defaults: defaults ?? ScratchDefaults.make(soundEnabled: true))
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

    @Test("Against the machine the flip is the same toggle, over the orientation the mode chose")
    func theFlipAgainstTheMachine() throws {
        // The owner's recommendation of 2026-07-31, recorded in issue #80, and
        // the semantics the Windows half already ships: what is on screen is
        // the mode's own orientation *exclusive-or* the player's flip. An AI
        // 先手 game resolves the human as Black, so it opens with Black at the
        // bottom; one flip views the same game from the machine's side.
        let core = try TestCores.fresh()
        try core.create(.humanVersusAI(game: .miniXiangqi, humanSide: .black,
                                      level: .fast, choice: .aiFirst))
        let game = try Game(rules: core)
        #expect(game.flipped, "the mode's own orientation: the human's side is at the bottom")

        let animator = ManualAnimator()
        let recorder = try FeedbackRecorder(
            defaults: ScratchDefaults.make(soundEnabled: true))
        let motion = PlayMotion(game: game,
                                policy: MotionPolicy(reduceMotion: false),
                                animator: animator.animator,
                                feedback: recorder.feedback)

        let fen = game.evaluation.fen
        let sideToMove = game.evaluation.sideToMove
        motion.flip()
        #expect(!game.flipped, "the player's flip turns the mode's orientation over")
        #expect(!motion.isCommitting, "and is never a committing transition")
        #expect(game.evaluation.fen == fen, "the game is untouched: the position…")
        #expect(game.evaluation.sideToMove == sideToMove, "…and whose turn it is")
        #expect(game.moves.isEmpty, "…and the record")

        motion.flip()
        #expect(game.flipped, "two flips are none, exactly as in Free Play")

        // A new game is where it goes back to the mode's own answer, and it
        // goes back because the orientation is decided at creation and never
        // persisted: the flip is a field of the game on screen and of nothing
        // longer-lived, which is Free Play's behaviour that this mode inherits
        // rather than a rule of its own.
        motion.flip()
        #expect(!game.flipped)
        let next = try TestCores.fresh()
        try next.create(.humanVersusAI(game: .miniXiangqi, humanSide: .black,
                                      level: .fast, choice: .aiFirst))
        #expect(try Game(rules: next).flipped,
                "the next game opens the way its own mode opens it")
    }

    @Test("Board input is discarded while the board is turning round")
    func inputDuringAFlipIsDiscarded() throws {
        // The canvas carries each disc along the arc of the rotation while the
        // tap targets over it stand at the orientation being turned *to*, so
        // for the length of the flip a tap would commit a move at a point the
        // player is not looking at.
        let (motion, animator, recorder) = try makeMotion()

        motion.flip()
        #expect(motion.isFlipping)
        #expect(motion.game.flipped, "the orientation changes at once; the drawing catches up")

        motion.tap(Square("b1")!)
        #expect(motion.game.selected == nil, "a tap mid-flip is discarded")
        #expect(recorder.events.isEmpty,
                "and discarded silently: the player asked for this flip")

        // The canvas's own flip phase reaching its target is what reports the
        // arrival, with the transaction completion behind it as the backstop —
        // the same two wires the landing arrives on.
        motion.flipArrived()
        #expect(!motion.isFlipping)
        animator.completeAll()
        #expect(!motion.isFlipping, "the backstop reports the same arrival, not another")

        motion.tap(Square("b1")!)
        #expect(motion.game.selected == Square("b1"), "and taps are ordinary input again")
    }

    @Test("A second press during a flip turns the board back")
    func aSecondFlipRetargets() throws {
        let (motion, animator, _) = try makeMotion()
        motion.flip()
        motion.flip()
        #expect(!motion.game.flipped,
                "a flip is presentational, so it re-targets: the board turns back")
        #expect(motion.isFlipping, "and is still turning, so input is still discarded")
        motion.tap(Square("b1")!)
        #expect(motion.game.selected == nil)

        animator.completeNext()   // the turn the second press replaced
        #expect(motion.isFlipping, "the replaced turn's completion is not this one's")
        animator.completeNext()
        #expect(!motion.isFlipping)
        motion.tap(Square("b1")!)
        #expect(motion.game.selected == Square("b1"))
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

    @Test("A capture lands on the plan it departed with, not the policy it lands under")
    func aCaptureLandsOnWhatItScheduled() throws {
        // Reduce Motion draws no removal, so the gate waits for the travel
        // alone. Switching the setting mid-transition must not change what the
        // arrival waits for: asking the live policy at the arrival was a gate
        // that latched shut — every later tap discarded, 悔棋 disabled for
        // good, the result notice unreachable.
        let (reduced, _, _) = try makeMotion(playing: ["d2d3", "d6d5", "d3d4"],
                                             reduceMotion: true)
        reduced.tap(Square("d5")!)
        reduced.tap(Square("d4")!)
        #expect(reduced.committing == .move)

        reduced.policy = MotionPolicy(reduceMotion: false)
        reduced.travelArrived()
        #expect(!reduced.isCommitting, "the gate opens on what was scheduled")
        #expect(reduced.canUndo, "so 悔棋 comes back")
        reduced.tap(Square("a2")!)
        #expect(reduced.game.selected == Square("a2"), "and the board accepts input again")

        // And the other way round: a removal that *was* scheduled still holds
        // the gate through its tail, however the policy reads by the time it
        // gets there.
        let (full, _, _) = try makeMotion(playing: ["d2d3", "d6d5", "d3d4"])
        full.tap(Square("d5")!)
        full.tap(Square("d4")!)
        full.policy = MotionPolicy(reduceMotion: true)
        full.travelArrived()
        #expect(full.isCommitting, "the removal it scheduled still holds the gate")
        full.fadeArrived()
        #expect(!full.isCommitting)
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

    // MARK: - Transitions that never happened

    @Test("A refused ply abandons its transition, and its late completion cannot land the next")
    func aRefusedPlyAbandonsItsTransition() throws {
        // A committing transition takes the gate before the core is asked, so
        // a core that refuses leaves one holding nothing to draw. It has to
        // let go, and without a landing: nothing arrived, so nothing sounds.
        let rules = RefusingRules(try TestCores.fresh())
        let (refused, refusedAnimator, refusedFeedback) = try makeMotion(rules: rules)

        refused.tap(Square("b1")!)
        refusedAnimator.completeAll()
        rules.refuses = true
        refused.tap(Square("b4")!)

        #expect(refused.game.moves.isEmpty, "the refused ply did not happen")
        #expect(refused.game.failure != nil, "and the failure is recorded rather than swallowed")
        #expect(!refused.isCommitting, "an abandoned transition holds no gate")
        #expect(refused.transit == nil, "and leaves nothing on the board")
        #expect(refusedFeedback.events.isEmpty, "nothing landed, so nothing sounded")

        // Its completion was scheduled before the refusal and still arrives.
        refusedAnimator.completeAll()
        #expect(!refused.isCommitting)
        #expect(refusedFeedback.events.isEmpty)

        // The same guard, at the moment it earns its keep: a transition whose
        // landing came in on the canvas's wire still has a transaction
        // completion parked behind it, and by the time that fires the *next*
        // move can be in flight. The token is what keeps it from being heard
        // as that move's landing and opening a gate it does not hold.
        let (motion, animator, recorder) = try makeMotion()
        motion.tap(Square("b1")!)
        animator.completeNext()          // the lift
        motion.tap(Square("b4")!)
        motion.travelArrived()           // the canvas reports the landing
        #expect(!motion.isCommitting)
        #expect(recorder.events == [.landing])

        motion.tap(Square("a6")!)        // Black replies
        motion.tap(Square("a5")!)
        #expect(motion.committing == .move, "the second move holds the gate")

        animator.completeNext()          // the first move's completion, arriving late
        #expect(motion.committing == .move,
                "a stale completion cannot land the move that came after it")
        #expect(recorder.events == [.landing], "nor sound a second landing")

        animator.completeAll()
        #expect(!motion.isCommitting, "and the move it belongs to lands on its own wire")
        #expect(recorder.events == [.landing, .landing])
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
        #expect(recorder.sounds.isEmpty,
                "and answered silently: learning where a piece may go is not a failure")
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
        #expect(recorder.sounds.isEmpty, "refused input is felt, never heard")
        #expect(motion.beatEmphasis == 1, "the background rises to full emphasis")

        animator.completeAll()
        #expect(motion.beatEmphasis == 0, "and falls back")
        #expect(motion.game.selected == nil)
    }

    // MARK: - What a landing sounds like

    /// Plays a pinned line and stops on its last landing. Everything before the
    /// last move is replayed into the position, and the last move is made the
    /// way a player makes it — one tap to lift, one to place — so what is heard
    /// is what the screen would have produced, on the wire it would have come
    /// in on.
    private func landing(_ line: [String],
                         defaults: UserDefaults? = nil) throws
        -> (PlayMotion, FeedbackRecorder) {
        let last = try #require(line.last.flatMap(Move.init(text:)))
        let (motion, animator, recorder) = try makeMotion(playing: Array(line.dropLast()),
                                                          defaults: defaults)
        motion.tap(last.from)
        motion.tap(last.to)
        animator.completeAll()
        return (motion, recorder)
    }

    @Test("An ordinary arrival is the plain tock")
    func aPlainLandingSoundsPlain() throws {
        let (motion, recorder) = try landing(["b1b4"])
        #expect(recorder.sounds == [.plain])
        #expect(recorder.events == [.landing], "felt as every landing is")
        #expect(motion.game.evaluation.state == .ongoing)
    }

    @Test("A capture sounds like a capture")
    func aCaptureSoundsLikeACapture() throws {
        let (motion, recorder) = try landing(GameTests.captureLine)
        #expect(motion.transit == nil, "the take has finished")
        #expect(recorder.sounds == [.capture], "a landing with mass, not the plain tock")
        #expect(recorder.events == [.landing])
    }

    @Test("A checking move sounds the accent")
    func aCheckSoundsTheAccent() throws {
        let (motion, recorder) = try landing(GameTests.checkLine)
        #expect(motion.game.checkedGeneral != nil, "the line gives check")
        #expect(recorder.sounds == [.check])
    }

    @Test("A capture that checks sounds like a capture")
    func aCapturingCheckSoundsLikeACapture() throws {
        let (motion, recorder) = try landing(GameTests.capturingCheckLine)
        // The premise, so this test proves what it claims to be about: the
        // horse takes the soldier and the general is in check, both at once.
        #expect(motion.game.evaluation.inCheck)
        #expect(motion.game.placement[Square("c5")!] == Piece(kind: .horse, side: .red))
        #expect(recorder.sounds == [.capture],
                "the take is the louder fact, and the rings say the rest")
    }

    @Test("A move that ends the game sounds the conclusion instead of a landing")
    func aMateSoundsTheConclusion() throws {
        let (motion, recorder) = try landing(GameTests.mateLine)
        #expect(motion.game.isFinished)
        #expect(recorder.sounds == [.conclusion],
                "one sound, and it replaces the landing rather than joining it")
        #expect(recorder.events == [.landing],
                "the haptic is unchanged: a disc still landed on a point")
    }

    @Test("Claiming the draw sounds the conclusion, with nothing landing")
    func aClaimSoundsTheConclusion() throws {
        let (motion, _, recorder) = try makeMotion(playing: GameTests.shuffleLine)
        #expect(motion.game.evaluation.claimAvailable)

        motion.claimDraw()
        #expect(motion.game.isFinished)
        #expect(recorder.sounds == [.conclusion],
                "the one result that arrives with no piece moving still sounds")
        #expect(recorder.events.isEmpty, "and nothing landed, so nothing is felt")

        motion.claimDraw()
        #expect(recorder.sounds == [.conclusion], "a second claim is not a second result")
    }

    @Test("A claim the core is not offering ends nothing and sounds nothing")
    func anUnavailableClaimIsSilent() throws {
        let (motion, _, recorder) = try makeMotion()
        motion.claimDraw()
        #expect(!motion.game.isFinished, "only the core decides the claim exists")
        #expect(recorder.sounds.isEmpty)
    }

    @Test("An Undo's return is the plain tock")
    func anUndoSoundsPlain() throws {
        let (motion, animator, recorder) = try makeMotion(playing: GameTests.captureLine)

        motion.undo()
        animator.completeAll()
        #expect(motion.game.moves.count == 3, "the take is back on the board")
        #expect(recorder.sounds == [.plain],
                "a piece landing on a point, and no sound played backwards")
        #expect(recorder.events == [.landing])
    }

    @Test("An Undo that lands back into a check sounds the accent")
    func anUndoIntoCheckSoundsTheAccent() throws {
        // The rule is about the position that arrives, not about the action
        // that produced it: the rings pulse at this landing exactly as they did
        // at the move's, so the accent that goes with them sounds too. What an
        // Undo never gets is a sound of its own.
        let (motion, animator, recorder) = try makeMotion(
            playing: GameTests.checkLine + ["d5c5"])
        #expect(!motion.game.evaluation.inCheck, "the screen stepped aside")

        motion.undo()
        animator.completeAll()
        #expect(motion.game.checkedGeneral != nil, "and the check is back")
        #expect(recorder.sounds == [.check])
    }

    // MARK: - The two switches

    @Test("With sound switched off the board is silent and still felt")
    func soundOffSilencesOnlyTheSound() throws {
        let defaults = try ScratchDefaults.make(soundEnabled: false)
        defer { ScratchDefaults.clear() }

        let (_, recorder) = try landing(GameTests.captureLine, defaults: defaults)
        #expect(recorder.sounds.isEmpty, "nothing is heard")
        #expect(recorder.events == [.landing],
                "and the haptic is untouched: it answers to its own switch")
    }

    @Test("Sound is on where nobody has said otherwise, and follows the toggle back")
    func soundDefaultsToOn() throws {
        let unset = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }
        #expect(Preferences.sound.value(in: unset), "an absent preference is sound on")

        let (_, heard) = try landing(["b1b4"], defaults: unset)
        #expect(heard.sounds == [.plain])

        // Read at the landing rather than cached: switching it back on within
        // the life of one feedback is heard on the next landing, not the next
        // launch.
        let toggled = try ScratchDefaults.make(soundEnabled: false)
        let (motion, animator, recorder) = try makeMotion(defaults: toggled)
        motion.tap(Square("b1")!)
        motion.tap(Square("b4")!)
        animator.completeAll()
        #expect(recorder.sounds.isEmpty)

        Preferences.sound.set(true, in: toggled)
        motion.tap(Square("a6")!)
        motion.tap(Square("a5")!)
        animator.completeAll()
        #expect(recorder.sounds == [.plain])
        ScratchDefaults.clear()
    }

    @Test("With haptics switched off the board is unfelt and still heard")
    func hapticsOffStillsOnlyTheHaptic() throws {
        let defaults = try ScratchDefaults.make(hapticsEnabled: false)
        defer { ScratchDefaults.clear() }

        // A capture, so the sound that survives is a chosen one rather than the
        // one a silenced gate would leave behind by accident.
        let (_, recorder) = try landing(GameTests.captureLine, defaults: defaults)
        #expect(recorder.events.isEmpty, "nothing is felt")
        #expect(recorder.sounds == [.capture],
                "and the sound is untouched: it answers to its own switch")
    }

    @Test("An illegal tap with haptics off answers on the board and nowhere else")
    func hapticsOffStillsTheTouchAnswerToo() throws {
        let defaults = try ScratchDefaults.make(hapticsEnabled: false)
        defer { ScratchDefaults.clear() }
        let (motion, animator, recorder) = try makeMotion(defaults: defaults)

        motion.tap(Square("b1")!)
        animator.completeAll()
        motion.tap(Square("c3")!)   // no cannon move reaches c3

        #expect(recorder.events.isEmpty, "the switch covers both patterns, not just the landing")
        #expect(recorder.sounds.isEmpty, "an illegal tap was always silent")
        #expect(motion.markerEmphasis == 1,
                "and the answer the contract requires is still on the board")
    }

    @Test("Haptics are on where nobody has said otherwise, and follow the toggle back")
    func hapticsDefaultToOn() throws {
        let unset = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }
        #expect(Preferences.haptics.value(in: unset), "an absent preference is haptics on")

        let (_, felt) = try landing(["b1b4"], defaults: unset)
        #expect(felt.events == [.landing])

        // Read at the event rather than cached, exactly as the sound gate is.
        let toggled = try ScratchDefaults.make(hapticsEnabled: false)
        let (motion, animator, recorder) = try makeMotion(defaults: toggled)
        motion.tap(Square("b1")!)
        motion.tap(Square("b4")!)
        animator.completeAll()
        #expect(recorder.events.isEmpty)

        Preferences.haptics.set(true, in: toggled)
        motion.tap(Square("a6")!)
        motion.tap(Square("a5")!)
        animator.completeAll()
        #expect(recorder.events == [.landing])
        ScratchDefaults.clear()
    }

    @Test("Both switched off leaves a move that is neither heard nor felt")
    func bothOffLeavesTheMoveItself() throws {
        let defaults = try ScratchDefaults.make(soundEnabled: false, hapticsEnabled: false)
        defer { ScratchDefaults.clear() }

        let (motion, recorder) = try landing(["b1b4"], defaults: defaults)
        #expect(recorder.sounds.isEmpty)
        #expect(recorder.events.isEmpty)
        #expect(motion.game.moves.count == 1,
                "the move itself is not feedback and is unaffected")
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
