// The move the player may ask the engine for, and everything that decides
// whether they may ask for it.
//
// docs/product.md, "Play modes": an on-demand hint in human-versus-AI play and
// in Free Play, in both games, and never in Nearby Play — which is why this
// type lives beside the local board's own machinery and the nearby screen never
// builds one. Nothing here is recorded: a suggestion is presentation, like
// flipping the board, and the game, History and every export are untouched by
// it.
//
// docs/engine-integration.md, "Search lifecycle": the hint is a search like any
// other and obeys the same rules. It is checked against the same identity and
// revision pair before anything is shown, it commits nothing — applying the
// move is the player's own tap through the ordinary input path — and it is
// cancelled by a move, an Undo, leaving the board, and suspension. **The
// cancellation at the player's own commit is not politeness**: the core runs one
// search at a time and queues the rest, so a hint still running when the player
// moves would put the AI's reply behind up to a whole thinking time of work
// about a position the game has left.
//
// The thinking time is the game's where the game froze one, and the Settings
// default AI level's where it did not. A Deep game gives deeper hints and the
// hint is never a different opponent from the one playing; Free Play freezes no
// level, so the hint takes the level the player has called theirs.

import Foundation
import MiniXiangqiCore
import Observation

@Observable
@MainActor
final class Hint {

    /// What the turn status's hint slot is carrying.
    enum Activity: Equatable {
        /// Nothing at all: no search running, or one too young to show.
        case idle
        /// A search has been running long enough to be worth an indicator —
        /// the same threshold the AI's own activity waits out, because an
        /// indicator that arrives and leaves inside a third of a second reads
        /// as a flicker rather than as thinking.
        case thinking
    }

    private(set) var activity: Activity = .idle

    /// The preparation failure awaiting an answer. Non-nil exactly while the
    /// accepted **无法获取提示** notice is up.
    private(set) var preparationFailure: CoreError?

    private let engine: AIEngine
    private let game: Game
    private let motion: PlayMotion
    private let timer: MotionTimer

    /// Where the Settings default AI level is read from, which is where the
    /// thinking time of a Free Play hint comes from. Read at the moment of use,
    /// like every preference.
    private let defaults: UserDefaults

    /// The outstanding hint search, if one is running. One at a time, and never
    /// beside the AI's own: the core refuses a hint while any search is
    /// outstanding, and a hint is only ever offered on the player's own turn.
    private var ticket: UInt64?

    /// Bumped by everything that invalidates work in flight, so a preparation,
    /// a timer or a result belonging to a superseded request answers to nothing
    /// when it comes back.
    private var attempt = 0

    /// True between asking for a preparation and hearing back.
    private var preparing = false

    /// Whether the outstanding-search refusal has already been asked again.
    /// `mxq_search_cancel` is cooperative and returns before the engine thread
    /// has retired what it cancelled, so a hint asked for immediately after a
    /// cancellation can be refused for a search that is already on its way out.
    /// The core's own instruction for that is to ask again rather than to
    /// expect the next call to be admitted; once is enough, and a second
    /// refusal is a state the player can answer by pressing again.
    private var askedAgain = false

    /// The suggestion this position already has. A repeated request on an
    /// unchanged position re-shows it rather than thinking about the same
    /// position twice; the revision is what makes "unchanged" a fact of the
    /// core's rather than a guess here.
    private var cached: (revision: UInt64, move: Move)?

    /// How long after an outstanding-search refusal the request is made again.
    /// Short, because what it waits for is the engine thread retiring a search
    /// that has already been told to stop.
    private static let askAgainInterval: TimeInterval = 0.05

    init(engine: AIEngine, game: Game, motion: PlayMotion,
         timer: MotionTimer = .live,
         defaults: UserDefaults = Preferences.defaults) {
        self.engine = engine
        self.game = game
        self.motion = motion
        self.timer = timer
        self.defaults = defaults
    }

    // MARK: - Whether there is a hint to ask for

    /// Whether a hint is on offer right now. The control is **absent** where
    /// this is false rather than disabled: a control that can never be pressed
    /// on the machine's turn is a promise about a turn that is not the
    /// player's.
    var isOffered: Bool {
        guard !game.isFinished else { return false }
        switch game.mode {
        // The player's own turn, which the core answers by not expecting a
        // search. It is read rather than re-derived from the mode and the side
        // to move, exactly as the board's own input rule reads it.
        case .humanVersusAI: return !game.searchExpected
        // Free Play is one person on both sides, so either turn is theirs.
        case .freePlay: return true
        // Never in nearby play. A suggestion engine on one side of a game
        // between two people is not this product's nearby play, and the nearby
        // board never builds this object at all — this is the second lock on
        // the same door rather than the only one.
        case .nearby: return false
        }
    }

    /// The thinking time a hint takes here.
    ///
    /// The game's own frozen movetime where it froze one, so a Deep game gives
    /// deeper hints and the hint is never a different opponent from the one
    /// playing. Free Play freezes none, so it takes the Settings default AI
    /// level's — the level the player has called theirs — which is also why the
    /// core needs an entry that takes a thinking time rather than cross-checks
    /// one.
    var movetimeMilliseconds: UInt32 {
        game.isHumanVersusAI
            ? game.configuration.movetimeMilliseconds
            : Preferences.defaultAiLevel(in: defaults).movetimeMilliseconds
    }

    // MARK: - Asking

    /// **提示**. Shows the suggestion this position already has, or asks for
    /// one — preparing the engine first where nothing is prepared, which is
    /// what a Free Play game that has never asked always needs.
    func request() {
        guard isOffered, ticket == nil, !preparing, preparationFailure == nil else { return }
        if let cached, cached.revision == game.evaluation.positionRevision {
            motion.showHint(cached.move)
            return
        }
        if engine.engineIsReady(for: game.kind) {
            search()
        } else {
            prepareThenSearch()
        }
    }

    /// 重试 on the notice. Every retry obtains a fresh memory probe, which is
    /// the whole point of retrying.
    func retryPreparation() {
        preparationFailure = nil
        request()
    }

    /// 取消 on the notice, and the dismissal that follows every answer to it.
    func dismissPreparationFailure() {
        preparationFailure = nil
    }

    /// Whether the failure the notice is up for is the one the accepted
    /// insufficient-memory message is *about*.
    ///
    /// By **code**, as this app maps every engine failure: only a budget below
    /// the minimum and an allocation that failed at a budget that was not are
    /// the situation "close some other apps" answers. A missing or mismatched
    /// network, a variant that would not load, a faulted engine — those reach
    /// the same notice, because the player pressed a control and is owed an
    /// answer, but they name no cause, since naming the wrong one is worse than
    /// naming none.
    var preparationFailureNamesMemory: Bool {
        preparationFailure?.isInsufficientMemory ?? false
    }

    // MARK: - Putting it down

    /// Everything a hint holds, put down: the search cancelled, the suggestion
    /// taken off the board, and the cache dropped with the position it was
    /// about.
    ///
    /// What calls it is every event that invalidates a suggestion — the
    /// player's own commit, an Undo, leaving the board, suspension, and the
    /// game ending. At the commit it runs **before** the AI's reply is asked
    /// for, because the engine thread runs one search at a time and the reply
    /// would otherwise queue behind a hint about a position that is already
    /// gone.
    func cancel() {
        attempt += 1
        if let ticket { engine.cancelSearch(ticket) }
        ticket = nil
        preparing = false
        askedAgain = false
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
        // A fresh probe at every attempt: the retry that follows a refusal has
        // to see the memory the user just freed, and a cached value would
        // answer with the state that produced the refusal.
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
        do {
            ticket = try engine.startHintSearch(movetimeMilliseconds: movetime) {
                [weak self] result in
                self?.received(result, from: token)
            }
        } catch {
            ticket = nil
            answer(error.asCoreError, from: token)
            return
        }
        askedAgain = false
        // The indicator appears only once the search has run long enough to be
        // worth showing, which is the threshold the AI's own activity waits
        // out. A hint at 快速 is a second's work and a great many are answered
        // before this fires at all.
        timer.after(Motion.thinkingIndicatorDelay) { [weak self] in
            guard let self, token == attempt, ticket != nil else { return }
            activity = .thinking
        }
    }

    /// A start the core refused.
    ///
    /// The readiness refusals have one answer, as they do for the AI's own
    /// search: the engine was torn down or prepared for the other game between
    /// the query and the start, so it is prepared again. An outstanding search
    /// is asked again once. Anything else leaves the control exactly where it
    /// was, with nothing shown and nothing claimed: the player may press again.
    private func answer(_ failure: CoreError, from token: Int) {
        switch failure.status {
        case MxqStatus(MXQ_ERR_ENGINE_NOT_PREPARED), MxqStatus(MXQ_ERR_STATE_ENGINE_NOT_READY):
            prepareThenSearch()
        case MxqStatus(MXQ_ERR_STATE_SEARCH_IN_PROGRESS) where !askedAgain:
            askedAgain = true
            timer.after(Self.askAgainInterval) { [weak self] in
                guard let self, token == attempt, ticket == nil, isOffered else { return }
                search()
            }
        default:
            askedAgain = false
        }
    }

    /// A hint search has answered. On the main actor, having been copied out of
    /// core storage on the engine thread as the callback contract requires.
    private func received(_ result: SearchResult, from token: Int) {
        guard token == attempt, result.ticket == ticket else { return }
        ticket = nil
        activity = .idle
        // A cancelled or stale answer is about a position the player has left;
        // a malformed, illegal or failed one produced nothing to suggest. None
        // of them is worth a word: the control is still there to press.
        guard result.outcome == .move else { return }
        // The frontend's own staleness comparison, which the interface requires
        // in addition to the core's: the core compares before delivery and this
        // compares before showing, and neither alone covers both race
        // directions.
        guard result.gameID == game.identity,
              result.positionRevision == game.evaluation.positionRevision,
              let move = Move(text: result.move, on: game.kind.board) else { return }
        cached = (result.positionRevision, move)
        motion.showHint(move)
    }
}

private extension Error {
    var asCoreError: CoreError { CoreError(wrapping: self) }
}
