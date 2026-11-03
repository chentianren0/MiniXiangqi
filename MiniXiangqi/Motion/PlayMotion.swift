// Interruption divides in two. A presentational transition (a lift, a marker)
// re-targets freely toward whatever the player just did. A committing one (a
// move, a capture, an Undo) runs to completion, and input arriving during it is
// discarded rather than queued. A flip is deferred rather than discarded: it
// changes nothing about the game, so it applies when the transition ends.
//
// Every input funnels through here and commits through Game, so this is where
// "a committing transition is running" is a fact rather than a guess.

import SwiftUI

@Observable
final class PlayMotion {
    let game: Game
    var policy: MotionPolicy

    private let animator: MotionAnimator
    private let feedback: Feedback

    /// Counts the board screen triggers its haptics on: every landing, and
    /// every touch the game could not act on.
    private(set) var landings = 0
    private(set) var refusals = 0

    private let transits: TransitMotion

    /// Meaningful only while one holds the gate, which is what `committing` says.
    private var transitionKind: Transit.Kind?

    /// The committing transition that is running, if one is. This is the gate:
    /// while it is non-nil, board input is discarded, Undo is refused, and a
    /// flip is deferred.
    var committing: Transit.Kind? { transits.isRunning ? transitionKind : nil }
    var isCommitting: Bool { transits.isRunning }

    /// Toggled, because two deferred flips are no flip at all.
    private(set) var flipDeferred = false

    /// A flip holds no committing gate but does hold board input: mid-rotation
    /// the tap targets already stand at the orientation being turned to, so a
    /// tap would land on a point the player is not looking at. Those taps are
    /// discarded silently, since the player asked for the flip.
    private(set) var isFlipping = false

    /// The second disc is a paired one's: the two plies of a decision cycle
    /// rewinding together.
    var transit: Transit? { transits.transit }
    var transitCompanion: Transit? { transits.companion }
    var transitFade: Double { transits.fade }
    var transitReveal: Double { transits.reveal }

    /// The check rings' one-time swell as they appear. Never raised under
    /// Reduce Motion: the pulse is removed, not converted.
    private(set) var checkEmphasis: Double = 0
    /// The illegal-tap answer: a pulse in full motion, a single persistent state
    /// under Reduce Motion, cleared when the selection changes.
    private(set) var markerEmphasis: Double = 0

    /// No new geometry: the suggestion is the ordinary selection on the piece
    /// plus the ordinary strengthening on one of its destinations.
    private(set) var suggested: Square?
    private(set) var hintEmphasis: Double = 0

    /// The acknowledgment beat.
    private(set) var beatEmphasis: Double = 0

    /// A flip's own completion is tied to the turn it belonged to, since a
    /// second press replaces that turn.
    private var flipGeneration = 0

    /// Includes the Undo it would interrupt.
    var canUndo: Bool { game.canUndo && !isCommitting }

    /// A committing transition has landed and the gate is open again. The
    /// opponent's reply floor is measured from here: the AI must not leave
    /// before the player's move has finished being shown.
    var landed: (() -> Void)?

    /// Committed by the core, whatever is still being drawn. The opponent starts
    /// its search here, so it is already thinking while the player's piece slides.
    var committed: (() -> Void)?

    init(game: Game,
         policy: MotionPolicy = MotionPolicy(reduceMotion: false),
         animator: MotionAnimator = .live,
         feedback: Feedback = .live) {
        self.game = game
        self.policy = policy
        self.animator = animator
        self.feedback = feedback
        self.transits = TransitMotion(animator: animator)
        // Unowned: the transit belongs to this object and cannot outlive it; a
        // strong capture would be a cycle for the life of every game.
        transits.arrived = { [unowned self] in announceLanding() }
        transits.ended = { [unowned self] in land() }
    }

    /// A position that arrives already in check, a resumed game, pulses its
    /// rings as they first appear, as a played check's do at its landing.
    func boardAppeared() {
        pulseCheckIfNeeded()
    }

    // MARK: - Input

    /// What a tap means is the game's to say; this adds the motion that carries
    /// it out.
    func tap(_ square: Square) {
        // Discarded, never queued; and mid-flip a tap cannot mean what the
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

    func cancelSelection() {
        guard !isCommitting, game.selected != nil else { return }
        animator.run(policy.movement(Motion.liftAnimation)) { [self] in
            game.selected = nil
            markerEmphasis = 0
            clearHint()
        } completion: { }
    }

    /// No marker of its own: the suggested piece is taken up exactly as the
    /// player's tap takes one up, and the suggested destination's marker
    /// strengthens. Whether the piece may be taken up is asked of the game.
    func showHint(_ move: Move) {
        guard !isCommitting, !isFlipping else { return }
        // A move with no origin is a stone going down: there is no piece to
        // take up, so the mark is the whole of it.
        guard let origin = move.from else { return markSuggestedPoint(move) }
        guard game.selected == origin
                || game.effect(ofTapAt: origin) == .select(origin) else { return }
        animator.run(policy.movement(Motion.liftAnimation)) { [self] in
            game.selected = origin
            markerEmphasis = 0
        } completion: { }
        raiseHint(at: move.to)
    }

    /// The pending-stone mark at the engine's point: the same mark the player's
    /// own first tap raises under 落子前确认, so tapping it plays the move and
    /// tapping elsewhere moves it. Whether the point may be marked is the game's
    /// answer.
    private func markSuggestedPoint(_ move: Move) {
        switch game.effect(ofTapAt: move.to) {
        case .play, .select: break
        case .cancelSelection, .illegal, .unavailable: return
        }
        animator.run(policy.movement(Motion.liftAnimation)) { [self] in
            game.selected = move.to
            markerEmphasis = 0
        } completion: { }
        raiseHint(at: move.to)
    }

    /// Under Reduce Motion the strengthened state arrives without the swell. It
    /// stays strengthened while the suggestion stands: a marker that decayed
    /// would leave nothing saying which point the engine chose.
    private func raiseHint(at square: Square) {
        suggested = square
        guard let rise = policy.pulse(.easeOut(duration: Motion.markerPulseRise)) else {
            hintEmphasis = 1
            return
        }
        animator.run(rise) { [self] in
            hintEmphasis = 1
        } completion: { }
    }

    /// Everything that ends a suggestion calls this. On a board that places,
    /// the mark is left standing: by then it is the player's own pending mark,
    /// and every act that ends a suggestion already clears it.
    func clearHint() {
        suggested = nil
        hintEmphasis = 0
    }

    /// In human-versus-AI play one decision is a whole exchange; how many plies
    /// is `Game.undoPlies`. A cycle rewinds in one gesture, both discs together:
    /// one travel and one arrival, which keeps it inside 600 ms.
    func undo() {
        guard canUndo else { return }
        guard !game.kind.isPlacement else { return undoPlacements() }
        let plies = max(game.undoPlies, 1)
        var played: [Move] = []
        for text in game.moves.suffix(plies) {
            guard let move = Move(text: text, on: game.kind.board) else {
                assertionFailure("the core retained an unreadable move")
                return
            }
            played.append(move)
        }
        // Placement games returned above; every ply here has an origin.
        guard played.count == plies, let last = played.last,
              let lastOrigin = last.from, let mover = game.placement[last.to]
        else { return }

        // Read off the position between the two moves, the core's answer
        // rather than one worked out here.
        let between = plies == 2 ? game.placement(atPly: game.moves.count - 1) : nil
        let first = plies == 2 ? played.first : nil
        let firstMover = first.flatMap { between?[$0.to] }

        // Two discs share one duration, from the longer journey.
        let distance = max(Motion.distance(of: last),
                           first.map(Motion.distance(of:)) ?? 0)
        let travel = Motion.travel(distance: distance, on: game.kind.board)

        begin(.undo)
        transits.run(policy.movement(Motion.travelAnimation(travel))) { [self] in
            game.undo()
            // A refused Undo did not happen: nothing to draw or hold the gate for.
            guard game.failure == nil else { return nil }
            committed?()
            // Where the reply took the very piece that invited it, the two
            // reversals share a square, and it belongs to the one carrying that
            // piece home.
            let restored = plies == 2
                ? (first?.to == last.to ? nil : between?[last.to])
                : game.placement[last.to]
            // A retraction returns the concealment: a ply that revealed a piece
            // puts it back face down. Nil where nothing turned back over.
            let returned = game.placement[lastOrigin].flatMap {
                $0.isFaceDown ? $0 : nil
            }
            return Transit(kind: .undo,
                           move: Move(from: last.to, to: lastOrigin),
                           piece: mover,
                           fading: restored.map { ($0, last.to) },
                           revealed: returned)
        }
        // The first ply returns whatever it turned over too: a human move that
        // revealed, answered by a reply that did not, is the ordinary case.
        if let first, let firstOrigin = first.from, let firstMover {
            transits.pair(with: Transit(kind: .undo,
                                        move: Move(from: first.to, to: firstOrigin),
                                        piece: firstMover,
                                        fading: game.placement[first.to].map { ($0, first.to) },
                                        revealed: game.placement[firstOrigin]
                                            .flatMap { $0.isFaceDown ? $0 : nil }))
        }
        // Raised after the pairing, because either disc's returning face needs
        // drawing.
        if !policy.reduceMotion {
            transits.raiseReveal(Motion.revealAnimation(travel: travel))
        }
        // The restored pieces return as the movers depart, inside the travel.
        guard !policy.reduceMotion else { return }
        transits.raiseFade(Motion.restoreFadeAnimation)
    }

    /// Nothing travels: a stone came from off the board, so there is no disc to
    /// carry home and no gate to hold. The commit is still announced, the
    /// landing felt and heard, and a refusal leaves the game where it stood.
    private func undoPlacements() {
        markerEmphasis = 0
        clearHint()
        animator.run(policy.fade(Motion.stateFadeAnimation)) { [self] in
            game.undo()
        } completion: { }
        guard game.failure == nil else { return }
        committed?()
        announcePlacement()
        landed?()
    }

    /// The floor that decides when it departs is the opponent's: by the time
    /// this is called the move is due.
    func playOpponent(_ move: Move) {
        guard move.from != nil else {
            place(move) { [self] in game.playOpponent(move) }
            return
        }
        commit(move) { [self] in game.playOpponent(move) }
    }

    /// The one result that arrives with nothing moving, so the conclusion
    /// sounds at the commit. Whether the claim exists is the game's to say, by
    /// whether it took it.
    func claimDraw() {
        guard !game.claimedDraw else { return }
        animator.run(policy.fade(Motion.stateFadeAnimation)) { [self] in
            game.claimDraw()
        } completion: { }
        guard game.claimedDraw else { return }
        feedback.play(.conclusion)
    }

    /// Sounds at the commit for the same reason `claimDraw` does.
    func resign() {
        guard !game.resigned else { return }
        animator.run(policy.fade(Motion.stateFadeAnimation)) { [self] in
            game.resign()
        } completion: { }
        guard game.resigned else { return }
        feedback.play(.conclusion)
    }

    /// Deferred across a committing transition, never discarded. A second press
    /// while one runs re-targets it, turning back from wherever it had got to,
    /// because a flip is presentational.
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
            // This completion belongs to a turn a re-target replaced.
            guard flipGeneration == token else { return }
            flipArrived()
        }
    }

    /// Reported by the canvas's flip phase and by the transaction completion
    /// behind it, so input never stays discarded because a completion never came.
    func flipArrived() {
        isFlipping = false
    }

    /// Opacity only, with the lightest feedback. For input the game cannot
    /// accept, never for input it acted on.
    func acknowledge() {
        refusals += 1
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
            // A selection elsewhere answers the suggestion.
            clearHint()
        } completion: { }
    }

    private func commit(_ move: Move) {
        guard move.from != nil else {
            place(move) { [self] in game.tap(move.to) }
            return
        }
        commit(move) { [self] in game.tap(move.to) }
    }

    /// Deliberately not `TransitMotion`: a stone neither crosses the board nor
    /// holds a gate. It appears with the position and the landing is the
    /// commit, so the next tap acts on a position the stone is already part of.
    private func place(_ move: Move, apply: () -> Void) {
        markerEmphasis = 0
        clearHint()
        animator.run(policy.fade(Motion.stateFadeAnimation), body: apply) { }
        guard game.lastMove == move, game.failure == nil,
              game.opponentFailure == nil else { return }
        committed?()
        announcePlacement()
        landed?()
    }

    /// Heard as the stone's click, or as the conclusion where it ended the game.
    private func announcePlacement() {
        landings += 1
        feedback.play(.ofTheLanding(nil, stone: true,
                                    finished: game.isFinished, inCheck: false))
    }

    /// A person's move and the opponent's differ only in how they are committed.
    private func commit(_ move: Move, apply: () -> Void) {
        guard let origin = move.from, let piece = game.placement[origin] else { return }
        let captured = game.placement[move.to]
        let travel = Motion.travel(distance: Motion.distance(of: move), on: game.kind.board)
        begin(.move)
        // Resolved once, before anything can arrive: the gate waits for exactly
        // the wires this schedules.
        transits.run(policy.movement(Motion.travelAnimation(travel)),
                     drawingRemoval: captured != nil && !policy.reduceMotion) {
            apply()
            guard game.lastMove == move, game.failure == nil,
                  game.opponentFailure == nil else { return nil }
            committed?()
            // Read off the committed position: the piece at the destination is
            // face up there whatever it set out as.
            let arrived = piece.isFaceDown ? game.placement[move.to] : nil
            return Transit(kind: .move, move: move, piece: piece,
                           fading: captured.map { ($0, move.to) },
                           revealed: arrived)
        }
        // Under Reduce Motion the canvas draws it from the dissolve's own
        // progress, so nothing is scheduled.
        if !policy.reduceMotion {
            transits.raiseReveal(Motion.revealAnimation(travel: travel))
        }
        guard transits.drawsRemoval else { return }
        // Scheduled against the arrival, so it cannot read as an unrelated
        // animation; the gate holds for its tail.
        transits.raiseFade(Motion.captureFadeAnimation(travel: travel))
    }

    /// Takes the gate before the core is asked: input is refused from this instant.
    private func begin(_ kind: Transit.Kind) {
        transitionKind = kind
        markerEmphasis = 0
        // Whatever was suggested was about the position being left.
        clearHint()
    }

    // MARK: - Arrivals

    /// The landing feedback fires here, at the event completing, never at the
    /// tap. See TransitMotion for the two wires that report it.
    private func announceLanding() {
        landings += 1
        feedback.play(.ofTheLanding(transit,
                                    finished: game.isFinished,
                                    inCheck: game.checkedGeneral != nil))
    }

    /// The check rings pulse only now: they belong to the position, which
    /// finishes arriving at the landing.
    private func land() {
        pulseCheckIfNeeded()
        landed?()
        if flipDeferred {
            flipDeferred = false
            flip()
        }
    }

    /// The canvas calls these; the gate is this object's to open.
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

    /// No board mark and no lost selection: where the piece may go teaches more
    /// than where it may not.
    private func answerIllegalTap() {
        refusals += 1
        guard let rise = policy.pulse(.easeOut(duration: Motion.markerPulseRise)) else {
            // One state change, kept until the selection changes.
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
