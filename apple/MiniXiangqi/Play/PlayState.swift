// The game the app is playing, the state before there is one, and the
// presentation state that belongs to the game rather than to the screen showing
// it.
//
// It lives **above** the navigation container, and that placement is the whole
// point of the type. The container keeps one destination's content alive at a
// time: leaving Play tears the play screen down, and returning to it builds a
// fresh one. A game held inside that screen would therefore be resumed again on
// every visit — a full decode-and-replay of the stored line each time — and,
// worse, the view state that says the player has already put the result notice
// away would be rebuilt with it, so a notice they closed would come back. The
// contract is explicit that it does not present itself again for the same
// result, and a game is the app's state rather than a tab's.
//
// So resuming happens exactly once per launch, here, and the play screen
// re-renders against a living object it did not create.
//
// docs/interaction-design.md, "Starting and configuring a game": a game is no
// longer created by its first move. With no active game the destination offers
// the two modes; choosing one opens that mode's pre-start state, whose controls
// are an in-memory draft initialized afresh from the Settings defaults and
// discarded the moment the player leaves. 开始对局 is what creates the game, and
// for human-versus-AI it runs the accepted ordering — prepare, resolve, create,
// search — with each step a gate on the next.

import MiniXiangqiCore
import Observation

/// The pre-start controls' values. A draft and nothing else: not autosaved,
/// never written back to the Settings defaults, and gone as soon as the player
/// leaves the page.
struct SetupDraft: Equatable {
    var firstMover: FirstMoverChoice
    var level: AiLevel

    /// Afresh from the persistent defaults, which is what every entry to the
    /// pre-start page gets. Read at the moment of use, like every preference.
    static func fromDefaults() -> SetupDraft {
        SetupDraft(firstMover: Preferences.defaultFirstMover(),
                   level: Preferences.defaultAiLevel())
    }

    /// The human's side, once a Random choice is drawn. Called only inside a
    /// creation attempt that has already prepared successfully, and committed
    /// only by a successful create — so a retry draws again.
    func resolveHumanSide() -> Side {
        switch firstMover {
        case .humanFirst: .red
        case .aiFirst: .black
        case .random: Bool.random() ? .red : .black
        }
    }

    /// What the pre-start board previews. 随机 remains unresolved and previews
    /// Red at the bottom; only a successful creation can flip the board.
    var previewsHumanAsBlack: Bool { firstMover == .aiFirst }
}

@Observable
final class PlayState {
    private let core: Core
    private let rules: Rules

    /// The engine the pre-start flow prepares and the opponent searches with.
    /// The core, in the app; a stand-in in the tests that are about what the
    /// creation ordering does when preparation refuses, which a working engine
    /// will not produce on request.
    private let engine: AIEngine

    /// Which of the destination's three states is showing.
    enum Phase: Equatable {
        /// No active game: the two mode entries.
        case start
        /// That mode's pre-start state, over a noninteractive preview.
        case setup(PlayMode)
        /// A game.
        case playing
    }

    private(set) var phase: Phase = .start

    private(set) var game: Game?
    private(set) var motion: PlayMotion?
    private(set) var opponent: Opponent?

    /// The pre-start controls' draft. Meaningful only while `phase` is
    /// `.setup`, and replaced afresh on every entry.
    var draft = SetupDraft.fromDefaults()

    /// Why the last **开始对局** created nothing. The page and the draft stay,
    /// and the control is enabled again.
    enum CreationFailure: Equatable {
        /// The accepted 无法启动 AI 对手 notice: the budget was below the
        /// minimum, or the allocation failed at a budget that was not.
        case aiUnavailable
        /// The game could not be persisted. Nothing was created, and anything
        /// prepared for it has been released.
        case notSaved(CoreError)
    }

    private(set) var creationFailure: CreationFailure?

    /// Whether a creation attempt is in flight. **开始对局** cannot be invoked
    /// again while it is.
    private(set) var creating = false

    /// The attempt in flight, and the invalidation of every earlier one.
    /// Leaving the pre-start state bumps it, which is what stops a late
    /// completion from committing after the draft is discarded.
    private var attempt = 0

    /// The start attempt that failed, if one did. A game that will not start is
    /// shown rather than swallowed — it is a bug in this app or a packaging
    /// failure, never a rules outcome.
    private(set) var startFailure: CoreError?

    /// Whether the player has closed the result notice. It is presentation and
    /// not game state — closing the notice changes nothing about the game — but
    /// it is the *game's* presentation, not the screen's: the notice does not
    /// come back for a result already seen, and walking to History and back is
    /// not seeing a new result. A result still unconfirmed at quit does present
    /// its notice again at the next launch, because the finished, unfiled game
    /// is exactly what resumed.
    var resultDismissed = false

    /// Whether the once-per-launch start has run.
    private var started = false

    /// The platform's suspension signals, watched for as long as this lives.
    private var suspension: Suspension?

    init(core: Core, engine: AIEngine? = nil) {
        self.core = core
        self.rules = Self.rules(over: core)
        self.engine = engine ?? core
    }

    /// Opens the stored active game, once. Every later visit to the play
    /// destination finds the game already here.
    func startIfNeeded(policy: MotionPolicy) {
        guard !started else { return }
        started = true
        #if DEBUG
        fileLaunchHistory()
        #endif
        watchForSuspension()
        resumeAtLaunch(policy: policy)
    }

    // MARK: - Before there is a game

    /// A mode was chosen on the start state. Its pre-start page opens with a
    /// draft taken afresh from the persistent defaults.
    func choose(_ mode: PlayMode) {
        guard phase == .start else { return }
        draft = SetupDraft.fromDefaults()
        creationFailure = nil
        phase = .setup(mode)
    }

    /// The player left the play destination. The draft is discarded, an attempt
    /// in flight is invalidated, and no game is created — a completion arriving
    /// afterwards commits nothing.
    func leavePage() {
        guard case .setup = phase else { return }
        attempt += 1
        creating = false
        creationFailure = nil
        phase = .start
    }

    /// Dismisses the creation failure without leaving the page: 取消 on the
    /// accepted notice. The draft is untouched and 开始对局 is on offer again.
    func dismissCreationFailure() {
        creationFailure = nil
    }

    /// **开始对局**.
    ///
    /// docs/engine-integration.md, "Accepted preparation ordering": prepare,
    /// resolve, create, search, each a gate on the next. A preparation failure
    /// creates nothing and resolves nothing; a Random choice is drawn only after
    /// preparation succeeds and is committed only by the create that follows, so
    /// a retry draws again; a persistence failure releases the prepared engine
    /// and creates nothing.
    func startGame(policy: MotionPolicy) {
        guard case .setup(let mode) = phase, !creating else { return }
        creating = true
        creationFailure = nil
        attempt += 1
        let token = attempt

        guard mode == .humanVersusAI else {
            create(.freePlay, policy: policy, token: token)
            return
        }

        // A fresh probe at every attempt. The prior value is never cached: the
        // retry that follows the insufficient-memory notice exists precisely to
        // see the memory the user just freed.
        engine.prepareEngine(engine.memoryBudget()) { [weak self] result in
            guard let self else { return }
            guard token == attempt else {
                // The player left while this was in flight, or pressed 重试 and
                // a newer attempt owns the engine now. Either way this attempt
                // creates nothing. Anything *it* prepared is released — but
                // only when nothing newer is relying on it, because the engine
                // is one engine and a stale completion must not pull it out
                // from under the attempt that replaced it.
                if !creating { engine.teardownEngine(then: nil) }
                return
            }
            if case .failure(let error) = result {
                creating = false
                creationFailure = Self.creationFailure(for: error)
                return
            }
            // Everything from here is synchronous, so there is no second window
            // in which a completion could arrive late and commit.
            let human = draft.resolveHumanSide()
            create(.humanVersusAI(humanSide: human, level: draft.level,
                                  choice: draft.firstMover),
                   policy: policy, token: token)
        }
    }

    /// A preparation refusal, as the page presents it.
    ///
    /// By **code**, not by domain. Insufficient memory and a failed Hash
    /// allocation are one situation to the person in front of the screen —
    /// memory is not available right now — and the accepted notice says so
    /// once. Every other engine-domain failure reaches this from the same
    /// `mxq_engine_prepare` call: a missing or mismatched network, a variant
    /// that would not load, a faulted engine. Telling someone to close other
    /// apps about a damaged installation is worse than telling them nothing,
    /// so those take the cause-free creation-failure notice instead.
    private static func creationFailure(for failure: CoreError) -> CreationFailure {
        failure.isInsufficientMemory ? .aiUnavailable : .notSaved(failure)
    }

    private func create(_ configuration: GameConfiguration, policy: MotionPolicy,
                        token: Int) {
        do {
            core.endSession()
            try rules.create(configuration)
            adopt(try Game(rules: rules), policy: policy)
            creating = false
            phase = .playing
            opponent?.begin()
        } catch {
            creating = false
            creationFailure = .notSaved(CoreError(wrapping: error))
            core.endSession()
            // The engine was prepared for a game that does not exist.
            if configuration.mode == .humanVersusAI {
                engine.teardownEngine(then: nil)
            }
        }
    }

    // MARK: - Concluding a game

    /// What 保存 does on a finished board: the terminal commit and nothing
    /// else. The game becomes a History record and the board stays exactly
    /// where the result left it — the notice above reads the filing off the
    /// game and becomes the recorded one, which is the whole of the change on
    /// screen. A filing the store refuses files nothing and answers `false`:
    /// the accepted retry presents, and the game stays active as it stood.
    func save() -> Bool {
        guard let game else { return true }
        do {
            try game.file()
            return true
        } catch {
            return false
        }
    }

    /// What 开始新对局 does on a finished board: the same filing first — a
    /// claimed draw and an already-saved result were both filed before this
    /// was pressed, and neither is filed twice — and then the finished game's
    /// own mode opens its pre-start state, so the next game's side and level are
    /// chosen rather than inherited. A filing the store refuses resets nothing
    /// and answers `false`: the accepted retry presents, and the game stays
    /// exactly as it stood.
    func startNewGame() -> Bool {
        guard let game else { return true }
        let mode = game.mode
        guard file(game) else { return false }
        release()
        phase = .start
        choose(mode)
        return true
    }

    /// 完成 on the recorded notice: back to the Play start state, with nothing
    /// filed a second time on the way.
    func finish() -> Bool {
        guard let game else { return true }
        guard file(game) else { return false }
        release()
        phase = .start
        return true
    }

    private func file(_ game: Game) -> Bool {
        do {
            try game.file()
            return true
        } catch {
            return false
        }
    }

    /// Lets go of the finished game and of the engine that was playing it. The
    /// order is the contract's: cancel, then release, because teardown refuses
    /// rather than stalls while a search is outstanding.
    private func release() {
        let wasHumanVersusAI = game?.isHumanVersusAI ?? false
        opponent?.cancelSearch()
        opponent = nil
        motion = nil
        game = nil
        resultDismissed = false
        core.endSession()
        if wasHumanVersusAI {
            engine.teardownEngine(then: nil)
        }
    }

    /// Keeps the running motion on the current policy when Reduce Motion
    /// changes under it.
    func adopt(_ policy: MotionPolicy) {
        motion?.policy = policy
    }

    // MARK: - Launch

    /// Opens the game the library holds, or the start state when it holds none:
    /// launch is a resume, and a resumed human-versus-AI game owing a move
    /// prepares and searches for it exactly as a fresh one would.
    private func resumeAtLaunch(policy: MotionPolicy) {
        startFailure = nil
        resultDismissed = false
        // Whatever session a previous game held is over; release before resume
        // is the single-session rule's precondition, not a saving act — the core
        // committed everything as it happened.
        core.endSession()
        do {
            #if DEBUG
            // A launch line needs a board to be played onto, and a game is no
            // longer created by its first move: the Free Play game the line
            // belongs to is created here, exactly as 开始对局 would create it.
            if !Self.launchReplayLine.isEmpty, try !core.activeGameExists() {
                try rules.create(.freePlay)
            }
            #endif
            let resumed = try Game(rules: rules)
            guard resumed.identity != nil else {
                phase = .start
                return
            }
            #if DEBUG
            try resumed.replay(Self.launchReplayLine)
            #endif
            adopt(resumed, policy: policy)
            phase = .playing
            opponent?.begin()
        } catch {
            game = nil
            motion = nil
            opponent = nil
            startFailure = CoreError(wrapping: error)
        }
    }

    /// Takes a game onto the screen: its motion, its opponent where it has one,
    /// and the wires between them.
    private func adopt(_ game: Game, policy: MotionPolicy) {
        self.game = game
        let motion = PlayMotion(game: game, policy: policy)
        self.motion = motion
        let opponent = Opponent(engine: engine, game: game, motion: motion)
        self.opponent = opponent
        // The search starts at the commit and the reply departs after the
        // landing, so the opponent listens at both.
        motion.committed = { [weak opponent] in opponent?.gameChanged() }
        motion.landed = { [weak opponent] in opponent?.landed() }
        // A resumed position may already stand in check; its rings pulse
        // as they first appear.
        motion.boardAppeared()
    }

    /// The seam the game speaks through: the core, unless a debug launch asked
    /// for the refusing stand-in so the save-failure state can be produced on a
    /// real screen.
    private static func rules(over core: Core) -> Rules {
        #if DEBUG
        if DebugLaunch.contains("-mxq-refuse-saves") {
            return RefusingRules(core, refuses: true)
        }
        #endif
        return core
    }

    // MARK: - Suspension

    /// docs/engine-integration.md, "Accepted backgrounding and teardown
    /// behavior": on the platform's own suspension or memory-pressure signal —
    /// never a loss of focus — the search is cancelled and the transposition
    /// table released. Re-preparation happens when a search is next owed.
    private func watchForSuspension() {
        suspension = Suspension { [weak self] event in
            switch event {
            case .suspend: self?.opponent?.suspend()
            case .resume: self?.opponent?.resume()
            case .memoryPressure: self?.opponent?.memoryPressure()
            }
        }
    }

    #if DEBUG
    /// The line `-mxq-replay a1a2,b7b5,…` names, played before first display so
    /// a UI test can start from a position it would otherwise have to click its
    /// way to. Debug only, and no move of it bypasses the core.
    private static var launchReplayLine: [String] {
        (DebugLaunch.argument(after: "-mxq-replay") ?? "")
            .split(separator: ",")
            .map(String.init)
    }

    /// The games `-mxq-history a1a2,b7b5;…;…` names, each played and filed
    /// before the board opens, so that a screenshot of the History list has a
    /// library to show and a UI test has records to act on. Games are separated
    /// by `;` and plies by `,`.
    ///
    /// Each one goes through the same path a person's game does — created by its
    /// own configuration, every ply committed by the core, the finished game
    /// filed by its own terminal commit — so nothing seeded here is a record the
    /// app could not have made. A line the core refuses stops the seeding rather
    /// than filing a half-game, and the launch continues: the failure then shows
    /// as a shorter list than the test asked for, where a test can see it.
    private func fileLaunchHistory() {
        let lines = (DebugLaunch.argument(after: "-mxq-history") ?? "")
            .split(separator: ";")
            .map { $0.split(separator: ",").map(String.init) }
        guard !lines.isEmpty else { return }
        for line in lines {
            core.endSession()
            guard (try? core.create(.freePlay)) != nil,
                  let game = try? Game(rules: core), (try? game.replay(line)) != nil
            else { return }
            if game.evaluation.claimAvailable {
                game.claimDraw()
            } else if game.isFinished {
                try? game.file()
            }
        }
        core.endSession()
    }
    #endif
}
