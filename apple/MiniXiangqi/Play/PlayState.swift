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
// longer created by its first move. The Play destination's root is the home
// page, where what to play is chosen; choosing a mode opens that mode's
// pre-start state, whose controls are an in-memory draft initialized afresh from
// the Settings defaults and discarded the moment the player leaves. 开始对局 is
// what creates the game, and for human-versus-AI it runs the accepted ordering —
// prepare, resolve, create, search — with each step a gate on the next.
//
// docs/interaction-design.md, "Saving the active game before choosing a new
// mode": the mode entries stay interactive while a game is active, and choosing
// one presents the accepted confirmation instead of navigating. 保存并继续
// archives the active game by its own current state and clears it — one atomic
// core call, off this actor — and only then opens the selected mode's pre-start
// state. The destination it remembers lives no longer than that flow.

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

    /// Which of the destination's three pages is showing. The home is the root
    /// and the other two are pushed over it, so this is also the navigation
    /// path: everything that changes it is a navigation.
    ///
    /// `Equatable` and nothing more. It was `Hashable` while a
    /// `NavigationStack` path carried it; the destination draws the page
    /// directly now, and all that is left to ask of it is which page this is.
    enum Page: Equatable {
        /// The Play home: what to play, and the active game if there is one.
        /// No board anywhere on it.
        case home
        /// That mode's pre-start state, over a noninteractive preview.
        case setup(PlayMode)
        /// The board.
        case board
    }

    private(set) var page: Page = .home

    private(set) var game: Game?
    private(set) var motion: PlayMotion?
    private(set) var opponent: Opponent?

    /// The game the store still holds — the one the home's card is about, and
    /// the one the save-and-continue confirmation would archive.
    ///
    /// A game that has been filed is not one of them. Its record is immutable
    /// History and the active-game reference was cleared by the terminal commit
    /// that made it; what is left on the board is the result standing where it
    /// was reached, which is presentation rather than an active game.
    var activeGame: Game? {
        guard let game, game.filedRecordID == nil else { return nil }
        return game
    }

    /// The pre-start controls' draft. Meaningful only while `page` is
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

    /// The mode the player asked for while a game was active, and how far the
    /// asking has got. The requested destination is carried *inside* the flow
    /// rather than beside it, which is the accepted rule made structural: it is
    /// remembered only while the confirmation or its retry exists, and there is
    /// nowhere for it to survive them.
    enum ModeSwitch: Equatable {
        /// The accepted 开始新对局？ confirmation is up.
        case confirming(PlayMode)
        /// 保存并继续 was pressed and the archive is running.
        case saving(PlayMode)
        /// The store refused it. The accepted 无法保存对局 retry is up, and the
        /// game is exactly as it stood.
        case failed(PlayMode)

        var mode: PlayMode {
            switch self {
            case .confirming(let mode), .saving(let mode), .failed(let mode): mode
            }
        }
    }

    private(set) var modeSwitch: ModeSwitch?

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

    /// Whether the once-per-launch start has run — and so whether `page` is yet
    /// an answer. Read by the destination, which does not build its navigation
    /// until it is true: a launch with a game to resume must *open* at the board
    /// rather than push its way there, and a stack built before the resume has
    /// answered would have to.
    private(set) var started = false

    /// The platform's suspension signals, watched for as long as this lives.
    private var suspension: Suspension?

    /// The seams are the two things a working core will not do on request: an
    /// engine that refuses to prepare, and a store that refuses to commit. Both
    /// default to the core itself, which is what the application always runs.
    init(core: Core, engine: AIEngine? = nil, rules: Rules? = nil) {
        self.core = core
        self.rules = rules ?? Self.rules(over: core)
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

    // MARK: - The home

    /// A mode entry was chosen on the home.
    ///
    /// With no active game it opens that mode's pre-start page. With one it
    /// opens nothing at all: the accepted confirmation presents instead, and
    /// the destination waits inside it. A game already filed is neither — it is
    /// a History record the board was still showing, so it is let go of here
    /// and the pre-start page opens as it would have with no game at all.
    func choose(_ mode: PlayMode) {
        guard page == .home, modeSwitch == nil else { return }
        if activeGame != nil {
            modeSwitch = .confirming(mode)
            return
        }
        if game != nil { release() }
        openSetup(mode)
    }

    /// 取消 on the confirmation, and the dismissal that follows every answer to
    /// it. The remembered destination goes with the flow that held it, and the
    /// active game is untouched — it can be resumed and taken back or claimed on
    /// the board, as it always could.
    ///
    /// It clears the confirmation and nothing else, because the alert's own
    /// dismissal arrives *after* the button's action: 保存并继续 would otherwise
    /// be followed by a cancel that discarded the archive it had just started.
    func dismissConfirmation() {
        if case .confirming = modeSwitch { modeSwitch = nil }
    }

    /// 取消 on the accepted 无法保存对局 retry, and the dismissal that follows
    /// every answer to it. It clears the failure and nothing else, for the
    /// reason above: 重试 starts the same archive again and must survive its own
    /// alert going away.
    func dismissArchiveFailure() {
        if case .failed = modeSwitch { modeSwitch = nil }
    }

    /// **保存并继续**, and the 重试 that repeats it.
    ///
    /// The archive is one atomic core call and the classification inside it is
    /// entirely the core's: an ordinary ongoing game and an unclaimed claimable
    /// repetition are recorded as ended early, and an unconfirmed natural
    /// terminal keeps its actual result and its exact reason. Only when it has
    /// committed does the selected mode's pre-start page open, and no new game
    /// exists until 开始对局 succeeds there.
    ///
    /// A refusal commits nothing: the old game is still active, still exactly
    /// as it stood, and the accepted retry presents over it.
    func saveAndContinue() {
        guard let mode = modeSwitch?.mode, activeGame != nil else { return }
        guard modeSwitch != .saving(mode) else { return }
        modeSwitch = .saving(mode)
        // What the machine is thinking about is about to stop being the game,
        // and a search outstanding over an archived game answers to nothing.
        opponent?.cancelSearch()
        rules.archiveActiveAndClear { [weak self] result in
            guard let self, modeSwitch == .saving(mode) else { return }
            switch result {
            case .success:
                release()
                modeSwitch = nil
                openSetup(mode)
            case .failure:
                modeSwitch = .failed(mode)
                // The game is unchanged and still owes whatever it owed, so the
                // machine picks its search back up.
                opponent?.begin()
            }
        }
    }

    /// **回到对局** on the home's current-game card: the board, and the game
    /// exactly as it was left.
    ///
    /// Not while a mode switch is anywhere in it. Both of that flow's alerts
    /// belong to the home, so leaving the page with an archive in flight would
    /// leave a refusal with no page to present the accepted 无法保存对局 retry
    /// on — and a success would take the player off the board they had just
    /// asked for and onto a pre-start page they never asked to see. The guard
    /// is what makes `modeSwitch != nil` imply `page == .home` everywhere,
    /// which is the invariant the two alerts' placement relies on.
    func resume() {
        guard page == .home, modeSwitch == nil, activeGame != nil else { return }
        page = .board
    }

    private func openSetup(_ mode: PlayMode) {
        draft = SetupDraft.fromDefaults()
        creationFailure = nil
        page = .setup(mode)
    }

    /// The player navigated back to the home from whichever page was over it.
    ///
    /// From a pre-start page that is leaving it, with everything leaving it
    /// means. From the board it is only a navigation: the game stays active and
    /// the card on the home is the way back to it — unless it has been filed,
    /// in which case the record is in History and the board was showing nothing
    /// the home has any use for.
    func leaveTopPage() {
        switch page {
        case .home: break
        case .setup: leavePage()
        case .board:
            if game?.filedRecordID != nil { release() }
            page = .home
        }
    }

    /// The player left the pre-start page — by going back to the home, or by
    /// leaving the destination altogether. The draft is discarded, an attempt in
    /// flight is invalidated, and no game is created: a completion arriving
    /// afterwards commits nothing.
    func leavePage() {
        guard case .setup = page else { return }
        attempt += 1
        creating = false
        creationFailure = nil
        page = .home
    }

    /// Dismisses the creation failure without leaving the page: 取消 on the
    /// accepted notice. The draft is untouched and 开始对局 is on offer again.
    func dismissCreationFailure() {
        creationFailure = nil
    }

    /// **开始对局**.
    ///
    /// docs/engine-integration.md, "Preparation ordering": prepare,
    /// resolve, create, search, each a gate on the next. A preparation failure
    /// creates nothing and resolves nothing; a Random choice is drawn only after
    /// preparation succeeds and is committed only by the create that follows, so
    /// a retry draws again; a persistence failure releases the prepared engine
    /// and creates nothing.
    func startGame(policy: MotionPolicy) {
        guard case .setup(let mode) = page, !creating else { return }
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
            page = .board
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
        openSetup(mode)
        return true
    }

    /// 完成 on the recorded notice: back to the Play home, with nothing filed a
    /// second time on the way.
    func finish() -> Bool {
        guard let game else { return true }
        guard file(game) else { return false }
        release()
        page = .home
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

    /// Opens the game the library holds, or the home when it holds none: launch
    /// is a resume, and a resumed human-versus-AI game owing a move prepares and
    /// searches for it exactly as a fresh one would. A launch that has a game to
    /// open goes straight to the board rather than by way of the home, which is
    /// the accepted resume-at-launch behaviour and is what the home being a
    /// navigable root has to leave untouched.
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
                page = .home
                return
            }
            #if DEBUG
            try resumed.replay(Self.launchReplayLine)
            #endif
            adopt(resumed, policy: policy)
            page = .board
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

    /// docs/engine-integration.md, "Backgrounding and teardown":
    /// on the platform's own suspension or memory-pressure signal —
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
