// The machine on the other side of the board.
//
// docs/engine-integration.md, "Search lifecycle", and docs/core-interface.md,
// "Search facade": search runs away from the UI thread — on the core's own
// engine thread, which is what "away" means here — a result is never what
// commits a move, and every result is checked against the current game and
// position revision *twice*, once by the core before delivery and once by the
// frontend before applying, because neither check alone covers both race
// directions. This file is where the frontend's half of that lives.
//
// docs/interaction-design.md, "Motion and visual effects": the AI's move has a
// floor, not a delay. Its piece departs at the later of the search returning and
// a short fixed interval after the player's own move has finished animating —
// the arrival, not the tap that committed it. A search of a second or more is
// unaffected; only a near-instant reply waits, so the AI never appears to twitch
// rather than move.
//
// Issue #71's decision 2 and decision 3 live here too: AI activity is a small
// system activity indicator that appears only once a search has run long enough
// to be worth showing, and a mid-game preparation failure keeps the situation's
// name while adding the guarantee that the game is saved, with the stalled state
// afterwards living in the turn status's own activity slot.

import Foundation
import MiniXiangqiCore
import Observation

@Observable
@MainActor
final class Opponent {

    /// What the turn status's AI activity slot is carrying.
    enum Activity: Equatable {
        /// Nothing at all: no search running, or one too young to show.
        case idle
        /// A search has been running long enough to be worth an indicator.
        case thinking
        /// The engine could not be prepared and the player chose 稍后. The
        /// game is saved and resumable; the retry lives here.
        case stalled
    }

    private(set) var activity: Activity = .idle

    /// The mid-game preparation failure awaiting an answer. Non-nil exactly
    /// while the accepted alert is up; 稍后 clears it into `.stalled` and 重试
    /// clears it into another attempt.
    private(set) var preparationFailure: CoreError?

    private let engine: AIEngine
    private let game: Game
    private let motion: PlayMotion
    private let timer: MotionTimer

    /// The outstanding search, if one is running. One at a time: this app has
    /// one window, one active game, and one side for the machine to play.
    private var ticket: UInt64?

    /// Bumped by everything that invalidates work in flight — a cancellation, a
    /// suspension, a new attempt — so that a preparation or a timer belonging to
    /// a superseded attempt answers to nothing when it comes back.
    private var attempt = 0

    /// True between asking for a preparation and hearing back. It is not the
    /// same as "the engine is not ready": a second attempt started while the
    /// first is in flight would be a second Hash allocation.
    private var preparing = false

    /// Set by the platform's suspension signal and cleared when the machine
    /// comes back. While it stands, nothing is prepared and nothing is
    /// searched: the engine was released on purpose.
    private var suspended = false

    /// The reply the search returned, held until it is due.
    private var pendingReply: Move?
    /// The instant the reply may depart — the floor's deadline.
    private var replyDue: TimeInterval?
    /// When the player's own move finished animating. The floor is measured
    /// from here; nil before the player has moved, which is the AI-first
    /// opening, where there is no move of the player's to wait for.
    private var playerArrival: TimeInterval?

    init(engine: AIEngine, game: Game, motion: PlayMotion,
         timer: MotionTimer = .live) {
        self.engine = engine
        self.game = game
        self.motion = motion
        self.timer = timer
    }

    // MARK: - What the screen tells it

    /// The game is on screen and whatever it owes is owed now: a created game
    /// whose resolved first mover is the AI, or a resumed one waiting on a
    /// reply it never got.
    func begin() {
        ensureSearch()
    }

    /// A committing change has been made. The search starts here rather than at
    /// the landing, because the floor governs when the reply *departs*, not when
    /// the thinking begins: a player who has moved should have the machine
    /// already thinking while their own piece is still sliding.
    func gameChanged() {
        ensureSearch()
    }

    /// A committing transition has finished being drawn. If the AI owes a move,
    /// the landing was the player's and it starts the floor; either way a reply
    /// already waiting can now be drawn, since only one committing transition
    /// runs at a time.
    func landed() {
        if game.searchExpected { playerArrival = timer.now() }
        deliver()
    }

    /// Stops the machine thinking, because what it is thinking about is about to
    /// stop being true — an Undo, a claim, a resignation. Cancellation is a
    /// correctness requirement and not only a promptness one: a cancellation
    /// that follows no mutation leaves the position revision matching, so the
    /// cancelled rung is the only one that would reject the late result.
    func cancelSearch() {
        attempt += 1
        if let ticket { engine.cancelSearch(ticket) }
        ticket = nil
        pendingReply = nil
        replyDue = nil
        activity = .idle
    }

    /// The platform's own suspension signal — system sleep, termination, a
    /// backgrounded scene — and never a loss of focus. Cancel first, then
    /// release: `mxq_engine_teardown` refuses with SEARCH_IN_PROGRESS rather
    /// than stalling, so the order is the contract's rather than a preference.
    func suspend() {
        suspended = true
        release()
    }

    /// The machine is awake again. Nothing is prepared by *this*: preparation
    /// happens when a search is next owed, and `ensureSearch` is where that is
    /// decided — a Free Play game, a finished one, or one waiting on the player
    /// prepares nothing at all.
    func resume() {
        suspended = false
        ensureSearch()
    }

    /// A memory-pressure notification. It takes the same cancel-and-release
    /// path, whole rather than shrinking Hash in place — but it is **not** a
    /// suspension, and this distinction is load-bearing: the app is still in
    /// front of the player, and nothing will ever tell it the pressure has
    /// passed. So there is no resume to wait for. What follows the release is
    /// the ordinary question of whether a search is owed, asked again with a
    /// fresh probe, which under real pressure produces the accepted notice
    /// rather than a machine that has quietly stopped playing.
    func memoryPressure() {
        release { [weak self] in self?.ensureSearch() }
    }

    private func release(then next: (@MainActor () -> Void)? = nil) {
        cancelSearch()
        engine.cancelAllSearches()
        preparationFailure = nil
        engine.teardownEngine(then: next)
    }

    /// 重试, from the alert or from the turn status's stalled slot. Every retry
    /// obtains a fresh memory probe, which is the whole point of retrying.
    func retryPreparation() {
        preparationFailure = nil
        activity = .idle
        suspended = false
        ensureSearch()
    }

    /// 稍后. The alert goes away and the stalled state moves to where
    /// things-about-the-game live, carrying its own retry. Undo remains
    /// available and is itself a way out: taking the player's last move back
    /// returns the game to their decision point, where no search is owed.
    func deferPreparation() {
        preparationFailure = nil
        // A retry already under way is not a deferral. The alert's dismissal
        // arrives *after* the button's own action, so 重试 would otherwise be
        // followed by a stall that stops the very attempt it started.
        guard !preparing, ticket == nil else { return }
        activity = game.searchExpected ? .stalled : .idle
    }

    // MARK: - The loop

    private func ensureSearch() {
        guard game.isHumanVersusAI else { return }
        guard game.searchExpected else {
            // Nothing is owed, so nothing is shown. A stalled slot outlives its
            // own reason otherwise — an Undo is exactly the way out the
            // accepted mid-game presentation names.
            if activity != .idle { activity = .idle }
            preparationFailure = nil
            return
        }
        guard !suspended, ticket == nil, pendingReply == nil, !preparing,
              preparationFailure == nil, activity != .stalled else { return }

        if engine.engineIsReady() {
            startSearch()
        } else {
            prepareThenSearch()
        }
    }

    private func prepareThenSearch() {
        preparing = true
        attempt += 1
        let token = attempt
        // A fresh probe at every attempt: the retry that follows a refusal has
        // to see the memory the user just freed, and a cached value would
        // answer with the state that produced the refusal.
        engine.prepareEngine(engine.memoryBudget()) { [weak self] result in
            guard let self, token == attempt else { return }
            preparing = false
            switch result {
            case .success:
                ensureSearch()
            case .failure(let error):
                // The alert first, per the accepted mid-game presentation; the
                // stalled slot is what 稍后 leaves behind.
                preparationFailure = error
            }
        }
    }

    private func startSearch() {
        guard let movetime = game.configuration?.movetimeMilliseconds, movetime > 0
        else { return }
        attempt += 1
        let token = attempt
        do {
            ticket = try engine.startSearch(movetimeMilliseconds: movetime) {
                [weak self] result in
                self?.received(result, from: token)
            }
        } catch {
            // The one refusal with an answer: the engine was torn down under
            // the search — the suspension path — so it is prepared again,
            // because a search is owed. Anything else is a failure the player
            // is told about in the accepted mid-game way.
            ticket = nil
            if error.asCoreError.status == MxqStatus(MXQ_ERR_ENGINE_NOT_PREPARED) {
                prepareThenSearch()
            } else {
                preparationFailure = CoreError(wrapping: error)
            }
            return
        }
        // The indicator appears only once the search has run long enough to be
        // worth showing. Below that it would appear and vanish inside a third of
        // a second, which reads as a flicker rather than as thinking.
        timer.after(Motion.thinkingIndicatorDelay) { [weak self] in
            guard let self, token == attempt, ticket != nil else { return }
            activity = .thinking
        }
    }

    /// A search has answered. On the main actor, having been copied out of core
    /// storage on the engine thread as the callback contract requires.
    private func received(_ result: SearchResult, from token: Int) {
        guard token == attempt, result.ticket == ticket else { return }
        ticket = nil
        activity = .idle

        switch result.outcome {
        case .move:
            // The frontend's own staleness comparison, which the interface
            // requires in addition to the core's: the core compares before
            // delivery and this compares before applying, and neither alone
            // covers both race directions.
            guard result.gameID == game.identity,
                  result.positionRevision == game.evaluation.positionRevision,
                  let move = Move(text: result.move) else { return }
            pendingReply = move
            // The floor: the later of now and a short interval after the
            // player's own move finished animating.
            let now = timer.now()
            let floor = playerArrival.map { $0 + Motion.replyFloor } ?? now
            replyDue = max(now, floor)
            deliver()
        case .cancelled, .stale:
            // Whoever cancelled decides what happens next, and a stale result
            // is one the position has already left behind. Nothing here.
            break
        case .malformed, .illegal, .failed:
            // The engine was torn down under the search — the suspension path,
            // reaching the frontend as a typed failure rather than as a
            // cancellation — so a search that is still owed is prepared again.
            if result.status == MxqStatus(MXQ_ERR_ENGINE_NOT_PREPARED) {
                ensureSearch()
                return
            }
            // Anything else: the engine produced nothing this game can use.
            // The game is untouched, saved and resumable, and the slot says the
            // one thing that is true of every such failure — the AI cannot
            // start right now — with the retry beside it. Deliberately *not*
            // the insufficient-memory alert: that alert names a cause, and
            // naming the wrong cause is worse than naming none.
            activity = .stalled
        }
    }

    /// Plays the held reply if it is due and the board is free to draw it.
    private func deliver() {
        guard let move = pendingReply, let due = replyDue else { return }
        // One committing transition at a time. The player's own move may still
        // be landing; `landed()` calls back here when it has.
        guard !motion.isCommitting else { return }

        let now = timer.now()
        guard now >= due else {
            let token = attempt
            timer.after(due - now) { [weak self] in
                guard let self, token == attempt else { return }
                deliver()
            }
            return
        }

        pendingReply = nil
        replyDue = nil
        playerArrival = nil
        motion.playOpponent(move)

        // A failed save of the AI's reply shows nothing at all: the retry is
        // the app's, not the user's. The game is at the last committed
        // position with the AI still to move, so a new search is requested from
        // it rather than the same result being pushed again — the position is
        // unchanged, but the result belonged to a request that is over.
        if game.opponentFailure != nil { ensureSearch() }
    }
}

private extension Error {
    var asCoreError: CoreError { CoreError(wrapping: self) }
}
