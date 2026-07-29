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
//
// The travelling disc itself is TransitMotion's, shared with replay: what a
// move looks like on its way to a point is the same question wherever the move
// came from. What stays here is everything that is only true of *play* — the
// gate, the game the transitions mutate, and the meaning each landing carries.

import SwiftUI

@Observable
final class PlayMotion {
    let game: Game
    var policy: MotionPolicy

    private let animator: MotionAnimator
    private let feedback: Feedback

    /// The travelling disc, and the arrival that ends it. Play holds its gate
    /// over this; the transit itself knows nothing about the gate.
    private let transits: TransitMotion

    /// The kind of the transition that took the gate. Only meaningful while
    /// one holds it, which is what `committing` says.
    private var transitionKind: Transit.Kind?

    /// The committing transition that is running, if one is. This is the gate:
    /// while it is non-nil, board input is discarded, Undo is refused, and a
    /// flip is deferred.
    var committing: Transit.Kind? { transits.isRunning ? transitionKind : nil }
    var isCommitting: Bool { transits.isRunning }

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
    var transit: Transit? { transits.transit }
    /// The fading disc's progress, 0 to 1 — scheduled against the mover's
    /// arrival for a capture, from its departure for an Undo.
    var transitFade: Double { transits.fade }

    /// The check rings' one-time swell as they appear. Never raised under
    /// Reduce Motion: the pulse is removed, not converted.
    private(set) var checkEmphasis: Double = 0
    /// The legal-destination markers' strengthening — the illegal-tap answer.
    /// A pulse in full motion; a single persistent state change under Reduce
    /// Motion, cleared when the selection changes.
    private(set) var markerEmphasis: Double = 0
    /// The turn status background's emphasis — the acknowledgment beat.
    private(set) var beatEmphasis: Double = 0

    /// A flip's own completion is tied to the turn it belonged to, since a
    /// second press replaces that turn.
    private var flipGeneration = 0

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
        self.transits = TransitMotion(animator: animator)
        // Unowned: the transit belongs to this object and cannot outlive it,
        // and a stored closure holding it back would be a cycle for the life
        // of every game.
        transits.arrived = { [unowned self] in announceLanding() }
        transits.ended = { [unowned self] in land() }
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
        begin(.undo)
        transits.run(policy.movement(Motion.travelAnimation(travel))) { [self] in
            game.undo()
            // An Undo the core refused did not happen: nothing to draw,
            // nothing to hold the gate for.
            guard game.failure == nil else { return nil }
            return Transit(kind: .undo,
                           move: Move(from: played.to, to: played.from),
                           piece: mover,
                           fading: game.placement[played.to].map { ($0, played.to) })
        }
        // The restored piece returns as the mover departs — the capture read
        // backwards — inside the travel, so one ply stays within its 250 ms.
        guard !policy.reduceMotion else { return }
        transits.raiseFade(Motion.restoreFadeAnimation)
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
        begin(.move)
        // The plan, resolved once and before anything can arrive: a removal is
        // drawn for a capture in full motion, and the gate waits for exactly
        // the wires this line schedules.
        transits.run(policy.movement(Motion.travelAnimation(travel)),
                     drawingRemoval: captured != nil && !policy.reduceMotion) { [self] in
            game.tap(move.to)
            guard game.lastMove == move, game.failure == nil else { return nil }
            return Transit(kind: .move, move: move, piece: piece,
                           fading: captured.map { ($0, move.to) })
        }
        guard transits.drawsRemoval else { return }
        // The captured disc gives way under the arriving mover: its removal is
        // scheduled against the arrival, leading it by 60 ms and finishing
        // 50 ms after it, so it cannot read as a second, unrelated animation.
        // The gate holds for that tail.
        transits.raiseFade(Motion.captureFadeAnimation(travel: travel))
    }

    /// Takes the gate, before the core is asked. Whatever the transition turns
    /// out to be able to draw, input is refused from this instant.
    private func begin(_ kind: Transit.Kind) {
        transitionKind = kind
        markerEmphasis = 0
    }

    // MARK: - Arrivals

    /// The mover has reached its point — see TransitMotion for the two wires
    /// that report it. The landing feedback fires here: the event completing,
    /// never the tap that asked.
    ///
    /// Felt and heard together, and they are not the same choice: the haptic is
    /// the alignment pattern at every landing there is, while the sound is the
    /// one that says what this landing was.
    private func announceLanding() {
        feedback.perform(.landing)
        feedback.play(.ofTheLanding(transit,
                                    finished: game.isFinished,
                                    inCheck: game.checkedGeneral != nil))
    }

    /// Every committing transition ends here: the gate opens, a deferred flip
    /// applies, and a check that arrived with the new position pulses its
    /// rings — which appear only now, because they belong to the position and
    /// the position finishes arriving at the landing.
    private func land() {
        pulseCheckIfNeeded()
        if flipDeferred {
            flipDeferred = false
            flip()
        }
    }

    /// The board's own arrival wires, forwarded. They are the canvas's to
    /// call, and the gate is this object's to open.
    func travelArrived() { transits.travelArrived() }
    func fadeArrived() { transits.fadeArrived() }

    // MARK: - Pulses

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
