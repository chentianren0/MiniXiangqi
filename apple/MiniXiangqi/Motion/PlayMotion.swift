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
    /// closing a gate some later transition holds.
    private var generation = 0

    /// The landing arrives on two wires — the board's own animation reaching
    /// its target, and the transaction completion as its backstop — and each
    /// event counts once, whichever wire reports it first.
    private var travelReported = false
    private var fadeReported = false

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

    /// A tap on a point of a live board. The finished game's taps — closing
    /// the notice, or the beat that answers a board with nothing left to
    /// accept — belong to the screen, which also holds the gate ahead of this.
    func tap(_ square: Square) {
        guard !isCommitting else { return }   // discarded, never queued
        if square == game.selected {
            cancelSelection()
        } else if game.selected != nil, game.destinations.contains(square) {
            commit(to: square)
        } else if game.placement[square]?.side == game.evaluation.sideToMove {
            select(square)
        } else if game.selected != nil {
            answerIllegalTap()
        } else {
            acknowledge()
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

    /// Applied at once between committing transitions, deferred across one:
    /// flipping changes nothing about the game, so nothing of it is discarded.
    func flip() {
        guard !isCommitting else {
            flipDeferred.toggle()
            return
        }
        animator.run(policy.movement(Motion.flipAnimation)) { [self] in
            game.flipped.toggle()
        } completion: { }
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

    private func commit(to square: Square) {
        guard let from = game.selected, let piece = game.placement[from] else { return }
        let move = Move(from: from, to: square)
        let captured = game.placement[square]
        let travel = Motion.travel(distance: Motion.distance(of: move))
        let token = begin(.move)
        animator.run(policy.movement(Motion.travelAnimation(travel))) { [self] in
            game.tap(square)
            guard game.lastMove == move, game.failure == nil else {
                abandon(token)
                return
            }
            transit = Transit(kind: .move, move: move, piece: piece,
                              fading: captured.map { ($0, square) })
        } completion: { [self] in
            guard generation == token else { return }
            travelArrived()
        }
        guard committing == .move, transit?.fading != nil, !policy.reduceMotion else { return }
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
    func travelArrived() {
        guard committing != nil, !travelReported else { return }
        travelReported = true
        feedback.perform(.landing)
        if committing == .move, transit?.fading != nil, !policy.reduceMotion, !fadeReported {
            return
        }
        land()
    }

    /// A capture's removal has finished, 50 ms behind the arrival it answers.
    /// Both wires report it too; the gate opens on the later of the two
    /// events, wherever each was heard first.
    func fadeArrived() {
        guard committing == .move, transit?.fading != nil, !fadeReported else { return }
        fadeReported = true
        if travelReported { land() }
    }

    private func begin(_ kind: Transit.Kind) -> Int {
        committing = kind
        markerEmphasis = 0
        travelReported = false
        fadeReported = false
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
