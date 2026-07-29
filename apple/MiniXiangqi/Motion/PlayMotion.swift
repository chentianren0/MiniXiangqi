// The play screen's motion: every transition the board runs, the gate the
// committing ones hold, and the feedback that fires with them.
//
// docs/interaction-design.md, "Motion and visual effects": interruption
// divides in two. A presentational transition — a lift, a marker — re-targets
// freely toward whatever the player just did. A committing transition — a
// move, a capture, an Undo — runs to completion, and input arriving during it
// is discarded rather than queued, so a player never watches a stack of
// actions replay. Board flipping is the one action deferred rather than
// discarded: it changes nothing about the game, so it is applied when the
// running transition ends.
//
// Every input funnels through here and commits through Game — the same
// legal-move boundary a future drag input will use — so this type is where
// "a committing transition is running" is a fact rather than a guess, and
// where the tests can pin the gating without a wall clock: the animator is a
// seam, and a test's animator completes when the test says so.

import SwiftUI

/// Runs an animation and reports its completion. The live one is SwiftUI's;
/// a test's holds the completion until the test fires it, so the gate can be
/// observed mid-transition without sleeping through one.
struct MotionAnimator {
    var perform: (Animation, () -> Void, @escaping () -> Void) -> Void

    func run(_ animation: Animation, body: () -> Void,
             completion: @escaping () -> Void) {
        perform(animation, body, completion)
    }

    static let live = MotionAnimator { animation, body, completion in
        withAnimation(animation, completionCriteria: .logicallyComplete, body) {
            MainActor.assumeIsolated(completion)
        }
    }
}

/// A committing transition as the board draws it: the visual move, the disc
/// making it, and the disc fading at one end — a capture giving way at the
/// destination, or a restored piece returning at an Undo's origin.
struct Transit {
    enum Kind { case move, undo }

    var kind: Kind
    var move: Move
    var piece: Piece
    /// The piece fading while the mover travels, and where it fades.
    var fading: (piece: Piece, at: Square)?
}

@Observable
final class PlayMotion {
    let game: Game
    var policy: MotionPolicy

    private let animator: MotionAnimator
    private let feedback: Feedback

    /// The committing transition that is running, if one is. This is the gate:
    /// while it is non-nil, board input is discarded, Undo is refused, and a
    /// flip is deferred.
    private(set) var committing: Transit.Kind?
    var isCommitting: Bool { committing != nil }

    /// A flip requested while a committing transition ran, applied when it
    /// ends. Toggled, because two deferred flips are no flip at all.
    private(set) var flipDeferred = false

    /// Whether the board is turning round. A flip is presentational and holds
    /// no committing gate, but it does hold board input: for its 350 ms the
    /// canvas draws every point partway through the rotation while the tap
    /// targets over it already stand at the orientation being turned *to*, so
    /// a tap in that window would commit a move at a point the player is not
    /// looking at. Those taps are discarded, and silently — the player asked
    /// for the flip, and answering their own request with a refusal beat would
    /// be noise.
    private(set) var isFlipping = false

    /// What the board is drawing for the running committing transition.
    private(set) var transit: Transit?
    /// The fading disc's progress, 0 to 1 — scheduled against the mover's
    /// arrival for a capture, from its departure for an Undo.
    private(set) var transitFade: Double = 0

    /// The check rings' one-time swell as they appear. Never raised under
    /// Reduce Motion: the pulse is removed, not converted.
    private(set) var checkEmphasis: Double = 0
    /// The legal-destination markers' strengthening — the illegal-tap answer.
    /// A pulse in full motion; a single persistent state change under Reduce
    /// Motion, cleared when the selection changes.
    private(set) var markerEmphasis: Double = 0
    /// The turn status background's emphasis — the acknowledgment beat.
    private(set) var beatEmphasis: Double = 0

    /// Ties a completion to the transition that scheduled it. A committing
    /// transition abandoned in its own body — a move the core refused — still
    /// gets its completion called, and the token keeps that stale call from
    /// closing a gate some later transition holds. A flip's own completion is
    /// tied the same way, since a second press replaces the turn it belonged
    /// to.
    private var generation = 0
    private var flipGeneration = 0

    /// The landing arrives on two wires — the board's own animation reaching
    /// its target, and the transaction completion as its backstop — and each
    /// event counts once, whichever wire reports it first.
    private var travelReported = false
    private var fadeReported = false

    /// Whether this transition draws a removal at all: a capture in full
    /// motion does, an Undo's restore and everything under Reduce Motion do
    /// not. Resolved once, when the transit begins, and never read back off
    /// the policy afterwards — Reduce Motion can be switched *while* a
    /// transition runs, and a gate that asked the live policy at the arrival
    /// what the departure had scheduled would sit waiting for a removal nobody
    /// ever drew, discarding every tap for the rest of the game.
    private var fadeScheduled = false

    /// Undo is unavailable while any committing transition runs, including the
    /// Undo it would interrupt. The cluster and notice buttons reflect this.
    var canUndo: Bool { game.canUndo && !isCommitting }

    init(game: Game,
         policy: MotionPolicy = MotionPolicy(reduceMotion: false),
         animator: MotionAnimator = .live,
         feedback: Feedback = .live) {
        self.game = game
        self.policy = policy
        self.animator = animator
        self.feedback = feedback
    }

    /// A position that arrives already in check — a resumed or replayed game —
    /// pulses its rings as they first appear, exactly as a played check's do
    /// at its landing.
    func boardAppeared() {
        pulseCheckIfNeeded()
    }

    // MARK: - Input

    /// A tap on a point. What it *means* is the game's to say — Game decides
    /// the affordance for the position, including that a finished board has
    /// nothing left to offer — and what is added here is the motion that
    /// carries it out. Closing the result notice standing in front of the
    /// board is the screen's own, since the notice is not a fact about the
    /// position.
    func tap(_ square: Square) {
        // Discarded, never queued: a committing transition runs to completion,
        // and while the board is turning round a tap cannot mean what the
        // player took it to mean.
        guard !isCommitting, !isFlipping else { return }
        switch game.effect(ofTapAt: square) {
        case .cancelSelection: cancelSelection()
        case .play(let move): commit(move)
        case .select: select(square)
        case .illegal: answerIllegalTap()
        case .unavailable: acknowledge()
        }
    }

    /// Tapping outside the board cancels the selection; with nothing selected
    /// such a tap is aimed at nothing and answered by nothing.
    func cancelSelection() {
        guard !isCommitting, game.selected != nil else { return }
        animator.run(policy.movement(Motion.liftAnimation)) { [self] in
            game.selected = nil
            markerEmphasis = 0
        } completion: { }
    }

    func undo() {
        guard canUndo, let text = game.moves.last, let played = Move(text: text),
              let mover = game.placement[played.to] else { return }
        let travel = Motion.travel(distance: Motion.distance(of: played))
        let token = begin(.undo)
        animator.run(policy.movement(Motion.travelAnimation(travel))) { [self] in
            game.undo()
            guard game.failure == nil else {
                // An Undo the core refused did not happen: nothing to draw,
                // nothing to hold the gate for.
                abandon(token)
                return
            }
            transit = Transit(kind: .undo,
                              move: Move(from: played.to, to: played.from),
                              piece: mover,
                              fading: game.placement[played.to].map { ($0, played.to) })
        } completion: { [self] in
            guard generation == token else { return }
            travelArrived()
        }
        // The restored piece returns as the mover departs — the capture read
        // backwards — inside the travel, so one ply stays within its 250 ms.
        if committing == .undo, transit?.fading != nil, !policy.reduceMotion {
            animator.run(Motion.restoreFadeAnimation) { [self] in
                transitFade = 1
            } completion: { }
        }
    }

    /// The player takes the draw the core is offering. It is the one result
    /// that arrives with nothing moving, so it is also the one place the
    /// concluding sound cannot wait for a landing: it sounds at the commit,
    /// which is the moment the game ends. Whether the claim exists at all is
    /// the game's to say, and it says so by whether it took it.
    func claimDraw() {
        guard !game.claimedDraw else { return }
        animator.run(policy.fade(Motion.stateFadeAnimation)) { [self] in
            game.claimDraw()
        } completion: { }
        guard game.claimedDraw else { return }
        feedback.play(.conclusion)
    }

    /// Applied at once between committing transitions, deferred across one:
    /// flipping changes nothing about the game, so nothing of it is discarded.
    /// A second press while one is running re-targets it — the board turns
    /// back the way it came, from wherever it had got to — because a flip is
    /// presentational, and a presentational transition re-targets freely
    /// toward whatever the player just did.
    func flip() {
        guard !isCommitting else {
            flipDeferred.toggle()
            return
        }
        flipGeneration += 1
        let token = flipGeneration
        isFlipping = true
        animator.run(policy.movement(Motion.flipAnimation)) { [self] in
            game.flipped.toggle()
        } completion: { [self] in
            // A re-target owns the board now, and this completion belongs to
            // the turn it replaced.
            guard flipGeneration == token else { return }
            flipArrived()
        }
    }

    /// The board has finished turning, and its points are where they are
    /// drawn again. Reported by the canvas's own flip phase reaching its
    /// target and by the transaction completion behind it — the same two wires
    /// the landing arrives on, for the same reason: input must not stay
    /// discarded because a completion never came.
    func flipArrived() {
        isFlipping = false
    }

    /// The acknowledgment beat: the turn status's background rises to full
    /// emphasis and falls back, opacity only, no movement, and the lightest
    /// feedback answers the touch. For input the game cannot accept — a tap
    /// that selects nothing, a tap on a finished board whose notice is already
    /// away — never for input it acted on.
    func acknowledge() {
        feedback.perform(.acknowledgement)
        animator.run(policy.fade(.easeOut(duration: Motion.beatRise))) { [self] in
            beatEmphasis = 1
        } completion: { [self] in
            animator.run(policy.fade(.easeInOut(duration: Motion.beatFall))) { [self] in
                beatEmphasis = 0
            } completion: { }
        }
    }

    // MARK: - The transitions themselves

    private func select(_ square: Square) {
        animator.run(policy.movement(Motion.liftAnimation)) { [self] in
            game.tap(square)
            markerEmphasis = 0
        } completion: { }
    }

    private func commit(_ move: Move) {
        guard let piece = game.placement[move.from] else { return }
        let captured = game.placement[move.to]
        let travel = Motion.travel(distance: Motion.distance(of: move))
        // The plan, resolved once and before anything can arrive: a removal is
        // drawn for a capture in full motion, and the gate below waits for
        // exactly the wires this line scheduled.
        let token = begin(.move, drawingRemoval: captured != nil && !policy.reduceMotion)
        animator.run(policy.movement(Motion.travelAnimation(travel))) { [self] in
            game.tap(move.to)
            guard game.lastMove == move, game.failure == nil else {
                abandon(token)
                return
            }
            transit = Transit(kind: .move, move: move, piece: piece,
                              fading: captured.map { ($0, move.to) })
        } completion: { [self] in
            guard generation == token else { return }
            travelArrived()
        }
        guard committing == .move, fadeScheduled else { return }
        // The captured disc gives way under the arriving mover: its removal is
        // scheduled against the arrival, leading it by 60 ms and finishing
        // 50 ms after it, so it cannot read as a second, unrelated animation.
        // The gate holds for that tail.
        animator.run(Motion.captureFadeAnimation(travel: travel)) { [self] in
            transitFade = 1
        } completion: { [self] in
            guard generation == token else { return }
            fadeArrived()
        }
    }

    // MARK: - Arrivals

    /// The mover has reached its point. Reported by the board's animation on
    /// the frame it arrives, and by the transaction completion as a backstop;
    /// the first report is the landing, the second is nothing. The landing
    /// feedback fires here — the event completing, never the tap that asked —
    /// and the gate opens unless a capture's removal tail still holds it.
    ///
    /// Felt and heard together, and they are not the same choice: the haptic is
    /// the alignment pattern at every landing there is, while the sound is the
    /// one below that says what this landing was.
    func travelArrived() {
        guard committing != nil, !travelReported else { return }
        travelReported = true
        feedback.perform(.landing)
        feedback.play(soundOfTheLanding())
        // A removal outlives the arrival that caused it, and the gate holds
        // for that tail — when one is being drawn. Whether one is was settled
        // at the departure; asking the policy again here is what would leave
        // the gate shut across a Reduce Motion switch.
        guard !fadeScheduled || fadeReported else { return }
        land()
    }

    /// A capture's removal has finished, 50 ms behind the arrival it answers.
    /// Both wires report it too; the gate opens on the later of the two
    /// events, wherever each was heard first.
    func fadeArrived() {
        guard committing != nil, fadeScheduled, !fadeReported else { return }
        fadeReported = true
        if travelReported { land() }
    }

    /// What this landing sounds like: one sound, chosen by what has arrived
    /// rather than by what was pressed, in the accepted order of precedence.
    ///
    /// - The game being over outranks everything, and replaces the landing
    ///   sound rather than joining it: a result is the last thing that
    ///   happened, and a tock underneath it would be the move competing with
    ///   its own consequence.
    /// - A capture outranks a check, because the take is the louder fact and
    ///   the check has the rings, the 将军 token, and the status line saying it
    ///   as well.
    /// - Everything else is the plain tock, an Undo's return included: taking a
    ///   move back is a disc landing on a point, and a sound played backwards
    ///   would be a fifth thing to learn for an action the board already
    ///   animates in reverse.
    ///
    /// It reads the arrived position and the transit's own plan, both of which
    /// are settled before anything can arrive. A capture is the transit's
    /// fading disc — but only a move's, since an Undo's fading disc is the
    /// piece coming *back*, which is a restoration and not a take.
    private func soundOfTheLanding() -> Feedback.Sound {
        if game.isFinished { return .conclusion }
        if transit?.kind == .move, transit?.fading != nil { return .capture }
        // The same condition the rings are drawn on, so the accent and the
        // pulse are one event: an Undo that lands back into a check is a check
        // arriving, and it is answered as one.
        if game.checkedGeneral != nil { return .check }
        return .plain
    }

    private func begin(_ kind: Transit.Kind, drawingRemoval: Bool = false) -> Int {
        committing = kind
        markerEmphasis = 0
        travelReported = false
        fadeReported = false
        fadeScheduled = drawingRemoval
        generation += 1
        return generation
    }

    private func abandon(_ token: Int) {
        guard generation == token else { return }
        committing = nil
        transit = nil
        transitFade = 0
    }

    /// Every committing transition ends here: the gate opens, a deferred flip
    /// applies, and a check that arrived with the new position pulses its
    /// rings — which appear only now, because they belong to the position and
    /// the position finishes arriving at the landing.
    private func land() {
        committing = nil
        transit = nil
        transitFade = 0
        pulseCheckIfNeeded()
        if flipDeferred {
            flipDeferred = false
            flip()
        }
    }

    private func pulseCheckIfNeeded() {
        guard game.checkedGeneral != nil,
              let rise = policy.pulse(.easeOut(duration: Motion.checkPulseRise)) else { return }
        animator.run(rise) { [self] in
            checkEmphasis = 1
        } completion: { [self] in
            animator.run(.easeInOut(duration: Motion.checkPulseFall)) { [self] in
                checkEmphasis = 0
            } completion: { }
        }
    }

    /// The illegal-tap answer. No board mark and no lost selection: the legal
    /// destinations strengthen, because where the piece may go teaches more
    /// than marking where it may not, and the lightest feedback answers the
    /// touch itself, ahead of anything drawn.
    private func answerIllegalTap() {
        feedback.perform(.acknowledgement)
        guard let rise = policy.pulse(.easeOut(duration: Motion.markerPulseRise)) else {
            // Reduce Motion: the markers strengthen once — a single state
            // change, no pulse — and stay until the selection changes.
            markerEmphasis = 1
            return
        }
        animator.run(rise) { [self] in
            markerEmphasis = 1
        } completion: { [self] in
            animator.run(.easeInOut(duration: Motion.markerPulseFall)) { [self] in
                markerEmphasis = 0
            } completion: { }
        }
    }
}
