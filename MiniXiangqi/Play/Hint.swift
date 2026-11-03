// A suggestion is presentation, like flipping the board: nothing is recorded,
// and the move is applied only by the player's own tap. Networked play never
// builds a Hint.

import Foundation
import MiniXiangqiCore
import Observation

@Observable
@MainActor
final class Hint {

    enum Activity: Equatable {
        /// No search running, or one too young to show.
        case idle
        /// Waits out the AI indicator's threshold: an indicator that comes and
        /// goes within a third of a second reads as a flicker.
        case thinking
    }

    private(set) var activity: Activity = .idle

    /// Non-nil exactly while the 无法获取提示 notice is up.
    private(set) var preparationFailure: CoreError?

    private let engine: AIEngine
    private let game: Game
    private let motion: PlayMotion
    private let timer: MotionTimer

    /// One at a time, and never beside the AI's: a hint is offered only on the
    /// player's turn, and every commit cancels it before the reply is asked for.
    private var ticket: UInt64?

    /// Bumped by everything that invalidates work in flight, so a stale
    /// preparation, timer or result answers to nothing.
    private var attempt = 0

    private var preparing = false

    /// Keyed by revision, so a repeated request on an unchanged position
    /// re-shows it rather than searching again.
    private var cached: (revision: Int, move: Move)?

    init(engine: AIEngine, game: Game, motion: PlayMotion,
         timer: MotionTimer = .live) {
        self.engine = engine
        self.game = game
        self.motion = motion
        self.timer = timer
    }

    // MARK: - Whether there is a hint to ask for

    /// Where false the control greys rather than leaving the cluster, so it
    /// stays where a thumb last found it. A finished board drops it with the
    /// game.
    var isOffered: Bool {
        guard !game.isFinished else { return false }
        switch game.mode {
        // Read from the core, as the board's input rule reads it, not
        // re-derived from the mode and the side to move.
        case .humanVersusAI: return !game.searchExpected
        // Free Play is one person on both sides, so either turn is theirs.
        case .freePlay: return true
        // A second lock: the networked board never builds a Hint at all.
        case .nearby, .online: return false
        }
    }

    /// The game's frozen movetime, so the hint is never a different opponent
    /// from the one playing. Free Play freezes none and takes the Settings
    /// default level.
    var movetimeMilliseconds: UInt32 {
        game.isHumanVersusAI
            ? game.configuration.movetimeMilliseconds
            : AiLevel.stored.movetimeMilliseconds
    }

    // MARK: - Asking

    /// **提示**. Re-shows the cached suggestion, or searches, preparing the
    /// engine first where nothing is prepared.
    func request() {
        guard isOffered, ticket == nil, !preparing, preparationFailure == nil else { return }
        if let cached, cached.revision == game.revision {
            motion.showHint(cached.move)
            return
        }
        if engine.engineIsReady(for: game.kind) {
            search()
        } else {
            prepareThenSearch()
        }
    }

    /// 重试 on the notice. Each retry takes a fresh memory probe, which is the
    /// point of retrying.
    func retryPreparation() {
        preparationFailure = nil
        request()
    }

    /// 取消 on the notice, and the dismissal that follows every answer to it.
    func dismissPreparationFailure() {
        preparationFailure = nil
    }

    /// Only a budget below the minimum or a failed allocation is answered by
    /// "close some other apps". Other failures reach the same notice but name
    /// no cause, since naming the wrong one is worse than naming none.
    var preparationFailureNamesMemory: Bool {
        preparationFailure?.isInsufficientMemory ?? false
    }

    // MARK: - Putting it down

    /// Called on every event that invalidates a suggestion. At the player's
    /// commit it must run before the AI's reply is asked for: the engine runs
    /// one search at a time, so the reply would queue behind a hint about a
    /// position already gone.
    func cancel() {
        attempt += 1
        if let ticket { engine.cancelSearch(ticket) }
        ticket = nil
        preparing = false
        activity = .idle
        preparationFailure = nil
        cached = nil
        motion.clearHint()
    }

    // MARK: - The search

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
                search()
            case .failure(let error):
                preparationFailure = error
            }
        }
    }

    private func search() {
        let movetime = movetimeMilliseconds
        guard movetime > 0 else { return }
        attempt += 1
        let token = attempt
        let revision = game.revision
        do {
            ticket = try engine.startHintSearch(game.searchLine, movetimeMilliseconds: movetime) {
                [weak self] result in
                self?.received(result, from: token, at: revision)
            }
        } catch {
            ticket = nil
            answer(error.asCoreError)
            return
        }
        // Shown only once the search outlasts the AI indicator's threshold; most
        // hints at 快速 answer before then.
        timer.after(Motion.thinkingIndicatorDelay) { [weak self] in
            guard let self, token == attempt, ticket != nil else { return }
            activity = .thinking
        }
    }

    /// A readiness refusal means the engine was torn down or prepared for the
    /// other game between the query and the start, so it is prepared again.
    /// Anything else leaves the control as it was.
    private func answer(_ failure: CoreError) {
        switch failure.status {
        case MxqStatus(MXQ_ERR_ENGINE_NOT_PREPARED), MxqStatus(MXQ_ERR_STATE_ENGINE_NOT_READY):
            prepareThenSearch()
        default:
            break
        }
    }

    /// On the main actor, the result having been copied out of core storage on
    /// the engine thread.
    private func received(_ result: SearchResult, from token: Int, at revision: Int) {
        guard token == attempt, result.ticket == ticket else { return }
        ticket = nil
        activity = .idle
        // Cancelled, malformed or failed answers are not worth a word: the
        // control is still there to press.
        guard result.outcome == .move else { return }
        guard revision == game.revision,
              let move = Move(text: result.move, on: game.kind.board) else { return }
        cached = (revision, move)
        motion.showHint(move)
    }
}

private extension Error {
    var asCoreError: CoreError { CoreError(wrapping: self) }
}
