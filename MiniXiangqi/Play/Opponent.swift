// A search result never commits a move by itself: the core keeps no game, so
// every result is checked against the game's revision before its move is
// played.
//
// The AI's move has a floor, not a delay. It departs at the later of the search
// returning and a short interval after the player's move finished animating
// (its arrival, not the tap), so a near-instant reply never looks like a twitch.

import Foundation
import MiniXiangqiCore
import Observation

@Observable
@MainActor
final class Opponent {

    enum Activity: Equatable {
        /// No search running, or one too young to show.
        case idle
        case thinking
        /// The engine could not be prepared and the player chose 稍后. The
        /// game is saved and resumable; the retry lives here.
        case stalled
    }

    private(set) var activity: Activity = .idle

    /// Non-nil exactly while the alert is up; 稍后 clears it into `.stalled`
    /// and 重试 into another attempt.
    private(set) var preparationFailure: CoreError?

    private let engine: AIEngine
    private let game: Game
    private let motion: PlayMotion
    private let timer: MotionTimer

    /// One at a time: one window, one active game, one side for the machine.
    private var ticket: UInt64?

    /// Bumped by everything that invalidates work in flight, so a stale
    /// preparation or timer answers to nothing.
    private var attempt = 0

    /// Not the same as "the engine is not ready": a second attempt started
    /// while the first is in flight would allocate Hash twice.
    private var preparing = false

    /// While set, nothing is prepared or searched: the engine was released on
    /// purpose.
    private var suspended = false

    /// The reply the search returned, held until it is due.
    private var pendingReply: Move?
    /// The floor's deadline.
    private var replyDue: TimeInterval?
    /// When the player's move finished animating; nil before they have moved,
    /// as in an AI-first opening.
    private var playerArrival: TimeInterval?

    init(engine: AIEngine, game: Game, motion: PlayMotion,
         timer: MotionTimer = .live) {
        self.engine = engine
        self.game = game
        self.motion = motion
        self.timer = timer
    }

    // MARK: - What the screen tells it

    /// The game is on screen: a created game whose first mover is the AI, or a
    /// resumed one still owed a reply.
    func begin() {
        ensureSearch()
    }

    /// The search starts here rather than at the landing: the floor governs when
    /// the reply departs, so the machine thinks while the player's piece slides.
    func gameChanged() {
        ensureSearch()
    }

    /// If the AI owes a move, this landing was the player's and starts the
    /// floor. A waiting reply can now be drawn, since only one committing
    /// transition runs at a time.
    func landed() {
        if game.searchExpected {
            let arrival = timer.now()
            playerArrival = arrival
            // A reply that came back while the player's move was travelling,
            // such as a forced mate found in milliseconds, still keeps the floor.
            if pendingReply != nil { replyDue = arrival + Motion.replyFloor }
        }
        deliver()
    }

    /// Before an Undo, a claim or a resignation. Needed for correctness: a
    /// cancellation that follows no change leaves the revision matching, so the
    /// cancelled ticket is the only thing that rejects the late result.
    func cancelSearch() {
        attempt += 1
        if let ticket { engine.cancelSearch(ticket) }
        ticket = nil
        pendingReply = nil
        replyDue = nil
        activity = .idle
    }

    /// System sleep or a backgrounded scene; never a loss of focus.
    /// Cancel before release: `mxq_engine_teardown` refuses with
    /// SEARCH_IN_PROGRESS rather than stalling.
    func suspend() {
        suspended = true
        release()
    }

    /// Prepares nothing itself; `ensureSearch` decides whether a search is owed.
    func resume() {
        suspended = false
        ensureSearch()
    }

    /// Cancels and releases whole, like a suspension, but is not one: the app is
    /// still in front and nothing will say the pressure has passed. So it asks
    /// again at once whether a search is owed, with a fresh probe, which under
    /// real pressure shows the notice rather than a machine that quietly stopped.
    func memoryPressure() {
        release { [weak self] in self?.ensureSearch() }
    }

    private func release(then next: (@MainActor () -> Void)? = nil) {
        cancelSearch()
        engine.cancelAllSearches()
        preparationFailure = nil
        engine.teardownEngine(then: next)
    }

    /// 重试, from the alert or the stalled slot. Each retry takes a fresh memory
    /// probe, which is the point of retrying.
    func retryPreparation() {
        preparationFailure = nil
        activity = .idle
        suspended = false
        ensureSearch()
    }

    /// 稍后. The stalled state moves to the turn status with its own retry. Undo
    /// is also a way out: it returns the game to the player's decision point,
    /// where no search is owed.
    func deferPreparation() {
        preparationFailure = nil
        // A retry already under way is not a deferral. The alert's dismissal
        // arrives after the button's action, so 重试 would otherwise be followed
        // by a stall that stops the attempt it started.
        guard !preparing, ticket == nil else { return }
        activity = game.searchExpected ? .stalled : .idle
    }

    // MARK: - The loop

    private func ensureSearch() {
        guard game.isHumanVersusAI else { return }
        guard game.searchExpected else {
            // Clear the stalled slot, which would otherwise outlive its reason
            // after an Undo.
            if activity != .idle { activity = .idle }
            preparationFailure = nil
            return
        }
        guard !suspended, ticket == nil, pendingReply == nil, !preparing,
              preparationFailure == nil, activity != .stalled else { return }

        if engine.engineIsReady(for: game.kind) {
            startSearch()
        } else {
            prepareThenSearch()
        }
    }

    private func prepareThenSearch() {
        preparing = true
        attempt += 1
        let token = attempt
        // A fresh probe each attempt, so a retry sees the memory the user just
        // freed.
        engine.prepareEngine(for: game.kind, engine.memoryBudget()) { [weak self] result in
            guard let self, token == attempt else { return }
            preparing = false
            switch result {
            case .success:
                ensureSearch()
            case .failure(let error):
                report(error)
            }
        }
    }

    private func startSearch() {
        let movetime = game.configuration.movetimeMilliseconds
        guard movetime > 0 else { return }
        attempt += 1
        let token = attempt
        let revision = game.revision
        do {
            ticket = try engine.startSearch(game.searchLine, movetimeMilliseconds: movetime) {
                [weak self] result in
                self?.received(result, from: token, at: revision)
            }
        } catch {
            // A readiness refusal means the engine was torn down or prepared for
            // the other game between the query and the start, so it is prepared
            // again.
            ticket = nil
            let failure = error.asCoreError
            if failure.status == MxqStatus(MXQ_ERR_ENGINE_NOT_PREPARED)
                || failure.status == MxqStatus(MXQ_ERR_STATE_ENGINE_NOT_READY) {
                prepareThenSearch()
            } else {
                report(failure)
            }
            return
        }
        // Shown only past the threshold; sooner it would read as a flicker.
        timer.after(Motion.thinkingIndicatorDelay) { [weak self] in
            guard let self, token == attempt, ticket != nil else { return }
            activity = .thinking
        }
    }

    /// Only memory failures get the 无法启动 AI 对手 alert asking to close other
    /// apps. Anything else (a missing or mismatched network, a variant that
    /// would not load, a faulted engine) is a damaged installation and takes the
    /// stalled slot with no cause named: the wrong cause is worse than none.
    private func report(_ failure: CoreError) {
        if failure.isInsufficientMemory {
            preparationFailure = failure
        } else {
            activity = .stalled
        }
    }

    /// On the main actor, the result having been copied out of core storage on
    /// the engine thread.
    private func received(_ result: SearchResult, from token: Int, at revision: Int) {
        guard token == attempt, result.ticket == ticket else { return }
        ticket = nil
        activity = .idle

        switch result.outcome {
        case .move:
            guard revision == game.revision else { return }
            guard let move = Move(text: result.move, on: game.kind.board) else {
                // A `.move` result should carry canonical notation; one that
                // cannot be read stalls like any unusable answer.
                activity = .stalled
                return
            }
            pendingReply = move
            // With no arrival yet (an AI-first opening, or a move still
            // travelling), `landed()` sets the floor when the arrival happens.
            let now = timer.now()
            replyDue = playerArrival.map { max(now, $0 + Motion.replyFloor) } ?? now
            deliver()
        case .cancelled:
            // Whoever cancelled decides what happens next.
            break
        case .malformed, .illegal, .failed:
            // The engine was torn down under the search: the suspension path,
            // arriving as a typed failure rather than a cancellation.
            if result.status == MxqStatus(MXQ_ERR_ENGINE_NOT_PREPARED) {
                ensureSearch()
                return
            }
            // Anything else: the game is untouched and saved, and the slot says
            // only that the AI cannot start now. Not the memory alert, which
            // names a cause.
            activity = .stalled
        }
    }

    /// Plays the held reply if it is due and the board is free to draw it.
    private func deliver() {
        guard let move = pendingReply, let due = replyDue else { return }
        // The player's move may still be landing; `landed()` calls back here.
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

        // A failed save of the reply shows nothing; the retry is the app's. The
        // position is unchanged but the result's request is over, so search
        // again rather than push the same result.
        if game.opponentFailure != nil { ensureSearch() }
    }
}

private extension Error {
    var asCoreError: CoreError { CoreError(wrapping: self) }
}
