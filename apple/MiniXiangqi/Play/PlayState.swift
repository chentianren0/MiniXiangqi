// The game the app is playing, the state before there is one, and the
// presentation state that belongs to the game rather than to the screen showing
// it.
//
// It lives **above** the navigation container, and that placement is the whole
// point of the type. The container keeps one destination's content alive at a
// time: leaving Play tears the play screen down, and returning to it builds a
// fresh one. The view state that says the player has already put the result
// notice away would be rebuilt with that screen, so a notice they closed would
// come back; the contract is explicit that it does not present itself again for
// the same result, and that is the app's state rather than a tab's.
//
// **The session, though, is the board's.** Issue #133's decision of 2026-08-05:
// the Play home reads the store's sessionless active-game summary, and the
// session, the engine's preparation and any owed search are opened when the
// board surface is entered and put down when it is left. So a game's motion and
// its sounds exist only while its board does, and a reply landing on a screen
// the player is not looking at is not something this app can do. Nothing is
// lost in the putting down: every move was committed as it was made, and a
// board entered again reads the same game back and thinks again about what it
// still owes.
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

/// One immutable destination from the Play home. Which game is played and how
/// it is played are independent axes, and both must survive every transient
/// step between choosing a row and committing the new active game.
struct PlaySelection: Equatable {
    var game: GameKind
    var mode: PlayMode
}

/// Whatever is holding the library's active game while it is a nearby one.
///
/// The library holds one active game, and nearby play is one of the ways to
/// have one; the wire session it is being played over is held above this
/// object. So the paths that take the active game away say so first, and the
/// session goes with the game rather than being left writing to one that is
/// gone.
@MainActor
protocol ActiveGameHolder: AnyObject {
    func giveUpActiveGame()
}

/// Making room in a library that holds one active game, as the nearby surfaces
/// need it: a nearby game is created the moment two devices agree to play one,
/// and there is no room for it until whatever stands is filed.
@MainActor
protocol NearbyRoom: AnyObject {
    /// The nearby game the library is holding, where the one active game is
    /// one. It is what tells a nearby entry row that the way in is back into
    /// the interrupted game rather than on to a new proposal.
    var standingNearbyGame: GameKind? { get }

    /// Ask for the active-game slot. `then` runs once it is free — at once
    /// where it already was, and after the accepted 保存并继续 otherwise. It
    /// does not run at all if the player cancels or the archive is refused.
    func makeRoom(for game: GameKind, then: @escaping @MainActor () -> Void)
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

    /// Which of the destination's pages is showing. The home is the root and
    /// the rest are pushed over it, so this is also the navigation path:
    /// everything that changes it is a navigation.
    ///
    /// **The initial value is the launch rule.** docs/interaction-design.md,
    /// "Navigation": a fresh launch opens at the home in every mode, and the
    /// game already going is continued from the card there. Opening the app
    /// moves this for nothing.
    ///
    /// `Equatable` and nothing more. It was `Hashable` while a
    /// `NavigationStack` path carried it; the destination draws the page
    /// directly now, and all that is left to ask of it is which page this is.
    enum Page: Equatable {
        /// The Play home: what to play, and the active game if there is one.
        /// No board anywhere on it.
        case home
        /// That game and mode's pre-start state, over its noninteractive
        /// starting-position preview.
        case setup(PlaySelection)
        /// The Custom Scene editor: a pre-start state of its own, over an empty
        /// interactive board. What it starts is an ordinary Free Play game of
        /// Xiangqi from the position composed in it.
        case customScene
        /// The board.
        case board
    }

    private(set) var page: Page = .home

    private(set) var game: Game?
    private(set) var motion: PlayMotion?
    private(set) var opponent: Opponent?

    /// The suggestion the player may ask the engine for. It belongs to the
    /// board exactly as the opponent does — it is opened with the game and put
    /// down with it — and it is the local board's alone: the nearby board is a
    /// separate screen and builds none.
    private(set) var hint: Hint?

    /// What the store says about the active game — the home's card, the
    /// confirmation's metadata line, and the whole of what either knows.
    ///
    /// **Read without a session**, from `mxq_store_active_summary`, which the C
    /// interface built for this surface. A filed game is not in it and cannot
    /// be: the terminal commit that made the record cleared the active-game
    /// reference, so the store simply stops reporting one. What is left on the
    /// board after a filing is the result standing where it was reached, which
    /// is presentation rather than an active game.
    private(set) var activeSummary: ActiveGameSummary?

    /// The pre-start controls' draft. Meaningful only while `page` is
    /// `.setup`, and replaced afresh on every entry.
    var draft = SetupDraft.fromDefaults()

    /// The position the pre-start page previews. Meaningful only while `page` is
    /// `.setup`, and made afresh on every entry, exactly as the draft is.
    ///
    /// It is here rather than in the page because a game whose start is dealt
    /// has no constant to read: there is one start for every deal. See
    /// `previewStart(of:)`.
    private(set) var preview: String = ""

    /// The Custom Scene editor's draft, while that page is up. **In memory and
    /// nowhere else**: it is made when the editor opens and dropped when it is
    /// left, which is the whole of discarding it.
    private(set) var scene: CustomScene?

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
        case confirming(PlaySelection)
        /// 保存并继续 was pressed and the archive is running.
        case saving(PlaySelection)
        /// The store refused it. The accepted 无法保存对局 retry is up, and the
        /// game is exactly as it stood.
        case failed(PlaySelection)

        var selection: PlaySelection {
            switch self {
            case .confirming(let selection), .saving(let selection), .failed(let selection):
                selection
            }
        }
    }

    private(set) var modeSwitch: ModeSwitch?

    /// The surface the room is being made for, where one asked for it rather
    /// than a mode row: a nearby proposal, or the Custom Scene editor. It lives
    /// inside the flow exactly as the remembered destination does, and is
    /// discarded with it.
    private var pendingOpening: (@MainActor () -> Void)?

    /// Whatever holds the active game while it is a nearby one. Set by the
    /// destination that assembles both; absent on macOS and in the tests that
    /// have no nearby layer.
    weak var nearbyHolder: (any ActiveGameHolder)?

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

    /// Whether the once-per-launch start has run — and so whether the store's
    /// answer is in. Read by the destination, which draws nothing until it is
    /// true: the home the launch opens carries the active game's card, and a
    /// home drawn before the store has answered would appear without it and
    /// then grow one.
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

    /// Reads the launch's answer, once.
    func startIfNeeded(policy: MotionPolicy) {
        guard !started else { return }
        started = true
        #if DEBUG
        fileLaunchHistory()
        #endif
        watchForSuspension()
        openAtLaunch(policy: policy)
    }

    // MARK: - The home

    /// A mode entry was chosen on the home.
    ///
    /// With no active game it opens that mode's pre-start page. With one it
    /// opens nothing at all: the accepted confirmation presents instead, and
    /// the destination waits inside it. What the store reports is the whole of
    /// the question — a filed game is not one, and the home holds no game of
    /// its own to consult.
    func choose(_ selection: PlaySelection) {
        guard page == .home, modeSwitch == nil else { return }
        if activeSummary != nil {
            modeSwitch = .confirming(selection)
            return
        }
        openSetup(selection)
    }

    /// **Custom Scene** was chosen on the home.
    ///
    /// docs/interaction-design.md, "Custom Scene": the row is a game-and-mode
    /// entry like every other, so with a game active it presents the same
    /// confirmation and the editor opens only once that archive has committed.
    /// What it will create is a Free Play game of Xiangqi, which is what the
    /// confirmation's remembered destination says — and the editor is what
    /// opens over it rather than that mode's own pre-start page.
    func chooseCustomScene() {
        guard page == .home, modeSwitch == nil else { return }
        guard activeSummary != nil else {
            openCustomScene()
            return
        }
        pendingOpening = { [weak self] in self?.openCustomScene() }
        modeSwitch = .confirming(PlaySelection(game: CustomScene.game,
                                               mode: .freePlay))
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
        if case .confirming = modeSwitch {
            modeSwitch = nil
            pendingOpening = nil
        }
    }

    /// 取消 on the accepted 无法保存对局 retry, and the dismissal that follows
    /// every answer to it. It clears the failure and nothing else, for the
    /// reason above: 重试 starts the same archive again and must survive its own
    /// alert going away.
    ///
    /// It clears the pending nearby act with it, for the reason the
    /// confirmation's own dismissal does: the act was remembered only for the
    /// flow that asked for it, and a flow the player cancelled is over. A
    /// closure left standing here would run on the *next* mode switch that
    /// succeeded, and open a surface nobody asked for.
    func dismissArchiveFailure() {
        if case .failed = modeSwitch {
            modeSwitch = nil
            pendingOpening = nil
        }
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
    ///
    /// The whole flow stands on the home, where there is no session, no engine
    /// and no search — the archive opens the handle its own transaction needs
    /// and releases it. So there is nothing here to cancel and nothing to pick
    /// back up: what the machine was thinking about was put down when the board
    /// was left.
    func saveAndContinue() {
        guard let selection = modeSwitch?.selection, activeSummary != nil else { return }
        guard modeSwitch != .saving(selection) else { return }
        modeSwitch = .saving(selection)
        // The game about to be archived may be one two devices are playing, and
        // the session it is played over is held above this object. It is given
        // up before the transaction rather than left writing to a game that is
        // gone.
        if activeSummary?.mode == .nearby { nearbyHolder?.giveUpActiveGame() }
        rules.archiveActiveAndClear { [weak self] result in
            guard let self, modeSwitch == .saving(selection) else { return }
            refreshActiveSummary()
            switch result {
            case .success:
                modeSwitch = nil
                if let opening = pendingOpening {
                    pendingOpening = nil
                    opening()
                } else {
                    openSetup(selection)
                }
            case .failure:
                modeSwitch = .failed(selection)
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
    ///
    /// This is where the game becomes live: the board it opens is what opens
    /// the session, prepares the engine and asks for the reply the game owes.
    func resume(policy: MotionPolicy) {
        guard page == .home, modeSwitch == nil, let summary = activeSummary else { return }
        // A nearby game is continued on its own board, over the session it was
        // played on: the card is the one way back into the active game whatever
        // mode it is, and which board that is follows from the mode.
        if summary.mode == .nearby {
            resumeNearby?(summary.game)
            return
        }
        page = .board
        enterBoard(policy: policy)
    }

    /// How a nearby active game is come back into. Set by the destination that
    /// assembles the nearby layer; absent where there is none, and then the
    /// card simply does nothing rather than opening a nearby game on a local
    /// board.
    var resumeNearby: (@MainActor (GameKind) -> Void)?

    private func openSetup(_ selection: PlaySelection) {
        draft = SetupDraft.fromDefaults()
        creationFailure = nil
        preview = previewStart(of: selection.game)
        page = .setup(selection)
    }

    /// What the pre-start page shows a game beginning from.
    ///
    /// A game whose rules freeze a start previews that constant, which is also
    /// the position it will be created from. **A game whose start is dealt
    /// previews a deal of its own**, and it is a different deal from the one the
    /// game will be played from — which shows nothing and hides nothing, because
    /// every deal looks the same from outside: the two generals face up on their
    /// own points and thirty discs face down on theirs, which is the whole of
    /// what either player will see when the board opens. Nobody is being shown a
    /// position they will play; they are being shown what this game looks like.
    ///
    /// A deal the core will not make previews an empty board, which is what a
    /// malformed position draws anywhere in this app. Nothing follows from it:
    /// the game is dealt again when it is created, and a refusal there is the
    /// creation failure that page already presents.
    private func previewStart(of game: GameKind) -> String {
        if let frozen = Core.frozenStartFEN(for: game) { return frozen }
        return (try? core.deal(game).startFEN) ?? ""
    }

    /// The editor, over an empty board and a draft nothing has been written of.
    private func openCustomScene() {
        creationFailure = nil
        scene = CustomScene(core: core)
        page = .customScene
    }

    /// The player navigated back to the home from whichever page was over it.
    ///
    /// From a pre-start page that is leaving it, with everything leaving it
    /// means. From the board it is leaving the board: the game stays committed
    /// and the card on the home is the way back into it, while the session, the
    /// engine and any search it owed are put down with the surface they
    /// belonged to.
    func leaveTopPage() {
        switch page {
        case .home: break
        case .setup, .customScene: leavePage()
        case .board:
            leaveBoard()
            page = .home
        }
    }

    // MARK: - The board surface, and what belongs to it

    /// The board is showing: the session, the engine's preparation and any owed
    /// search are opened here, because they are the board's and nothing else's.
    ///
    /// Called by 回到对局, and again by the destination whenever the board comes
    /// back with the container — the play destination is torn down and rebuilt
    /// on every visit, and the game the player was looking at is read again
    /// from the store it was committed to.
    ///
    /// It is idempotent: a board that already holds its game asks the store for
    /// nothing.
    func enterBoard(policy: MotionPolicy) {
        guard page == .board, game == nil, startFailure == nil else { return }
        do {
            if !rules.hasSession {
                guard try rules.resumeActive() else {
                    // The store holds no active game to open. Nothing to show,
                    // and the home is where that is said.
                    activeSummary = nil
                    page = .home
                    return
                }
                // A nearby game is not played on this board: it is played over
                // a session with another device, on a board of its own, and the
                // home's card is what opens it. Asked of the game rather than of
                // the summary because this is the answer that decides whether a
                // session stays attached.
                if try rules.configuration().mode == .nearby {
                    core.endSession()
                    page = .home
                    refreshActiveSummary()
                    return
                }
            }
            adopt(try Game(rules: rules), policy: policy)
            opponent?.begin()
        } catch {
            game = nil
            motion = nil
            opponent = nil
            // A resume that succeeded and a game that then would not open
            // leaves a session attached to a board there is none of. The
            // failure screen is what shows, and no session stands behind it.
            core.endSession()
            startFailure = CoreError(wrapping: error)
        }
    }

    /// The board has gone — back to the home, or away with the whole
    /// destination when the player switches to another one.
    ///
    /// docs/engine-integration.md, "Search lifecycle": leaving the relevant
    /// state cancels the work outstanding in it. So the search is cancelled,
    /// the engine released and the session ended. **Nothing is lost by that**:
    /// every move was committed as it was made, so a board entered again reads
    /// the same game back and thinks again about whatever it still owes.
    ///
    /// A game that has been filed is the one thing that does not come back. Its
    /// record is immutable History and the store reports no active game, so the
    /// board it was standing on is let go of with the surface, exactly as
    /// walking back from it to the home always let it go.
    func leaveBoard() {
        guard game != nil else { return }
        if game?.filedRecordID != nil {
            release()
            page = .home
        } else {
            putDownGame()
            refreshActiveSummary()
        }
    }

    /// The window holding this game has closed.
    ///
    /// The navigation exclusions give the app one main window, so a window that
    /// closes is the board going away — and on macOS that is not the app going
    /// away, which is why this exists at all. What goes with it is the session
    /// and any search owed to it, per the engine contract's cancellation
    /// clause. **The engine does not**: a window closing is not sleep, not
    /// termination and not memory pressure, and releasing gigabytes of Hash
    /// because somebody closed a window is the mistake
    /// docs/engine-integration.md exists to forbid.
    ///
    /// The game is untouched. Every ply was committed as it was made, so the
    /// store still holds it and the home's card is the way back into it —
    /// which is where a window opened again lands, in every mode.
    func windowClosed() {
        guard game != nil else { return }
        putDownGame(releasingTheEngine: false)
        page = .home
        refreshActiveSummary()
    }

    /// A nearby game's board went up over the local pages, or came down off
    /// them.
    ///
    /// A nearby board is drawn over *every* page of the Play destination, so
    /// while one is up the local game's board is not the board on screen — and
    /// the session, the engine and any owed search belong to the board that is.
    /// Coming down leaves the player on the page that was standing underneath,
    /// which is where the local game opens again.
    func nearbyBoardPresented(_ isPresented: Bool, policy: MotionPolicy) {
        if isPresented {
            leaveBoard()
        } else {
            enterBoard(policy: policy)
        }
    }

    /// The player left a pre-start page — by going back to the home, or by
    /// leaving the destination altogether. The draft is discarded, an attempt in
    /// flight is invalidated, and no game is created: a completion arriving
    /// afterwards commits nothing.
    ///
    /// The Custom Scene editor is a pre-start page and leaves the same way: its
    /// composed position and side to move were only ever this object's, so
    /// dropping the draft is the whole of discarding it and nothing was written
    /// to undo.
    func leavePage() {
        switch page {
        case .setup, .customScene: break
        case .home, .board: return
        }
        attempt += 1
        creating = false
        creationFailure = nil
        scene = nil
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
        guard case .setup(let selection) = page, !creating else { return }
        creating = true
        creationFailure = nil
        attempt += 1
        let token = attempt

        guard selection.mode == .humanVersusAI else {
            createFreePlay(selection.game, policy: policy, token: token)
            return
        }

        // A fresh probe at every attempt. The prior value is never cached: the
        // retry that follows the insufficient-memory notice exists precisely to
        // see the memory the user just freed.
        engine.prepareEngine(for: selection.game, engine.memoryBudget()) { [weak self] result in
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
            create(.humanVersusAI(game: selection.game, humanSide: human,
                                  level: draft.level, choice: draft.firstMover),
                   policy: policy, token: token)
        }
    }

    /// **开始对局** in Free Play. Nothing is prepared and nothing is searched —
    /// Free Play owes no search — so the game is created and that is the whole
    /// of it.
    ///
    /// **A game whose start is dealt is dealt here**, at the moment it is
    /// created and not before: the deal *is* the game, so it is drawn in the act
    /// that commits one and never left standing beside a page nobody pressed
    /// 开始对局 on. The entropy is this app's, from the platform's cryptographic
    /// source, and the derivation is the core's; nothing here is kept, because
    /// nothing verifies a local game against itself and the dealt start in the
    /// record is the deal.
    ///
    /// A deal the core will not make creates nothing and presents the same
    /// notice a creation the store refused presents: no game exists either way,
    /// the page and the draft stand, and what a reader does about it is press
    /// 重试.
    private func createFreePlay(_ game: GameKind, policy: MotionPolicy, token: Int) {
        guard Core.frozenStartFEN(for: game) == nil else {
            create(.freePlay(game: game), policy: policy, token: token)
            return
        }
        do {
            let deal = try core.deal(game)
            create(.freePlay(game: game, startFEN: deal.startFEN),
                   policy: policy, token: token)
        } catch {
            creating = false
            creationFailure = .notSaved(CoreError(wrapping: error))
        }
    }

    /// **开始对局** in the Custom Scene editor.
    ///
    /// The scene game *is* a Free Play game of Xiangqi that began elsewhere, so
    /// this is the Free Play creation with the composed position as its start
    /// and nothing else added: no engine is prepared, because Free Play owes no
    /// search, and the composed FEN is what the core is asked to begin from.
    ///
    /// It asks the draft first, as the control does: a position the core would
    /// refuse is one 开始对局 is disabled on, and the guard is what makes the
    /// disabling the rule rather than the appearance of one — a call that got
    /// past it would meet `MXQ_ERR_STATE_GAME_OVER` and report it as a game
    /// that could not be saved, which is not what happened.
    ///
    /// Creation can still refuse past it — the store can decline to persist —
    /// and then it creates nothing, keeps the page and the draft, and presents
    /// the same notice the other pre-start pages present.
    func startScene(policy: MotionPolicy) {
        guard page == .customScene, let scene, scene.canStart, !creating else { return }
        creating = true
        creationFailure = nil
        attempt += 1
        create(.freePlay(game: CustomScene.game, startFEN: scene.fen),
               policy: policy, token: attempt)
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
            // A draft that has become a game is no longer a draft, and the
            // editor is not a page to come back to from the board: the way back
            // is the home, exactly as it is from every other pre-start page.
            scene = nil
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
        return file(game)
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
        let selection = PlaySelection(game: game.kind, mode: game.mode)
        guard file(game) else { return false }
        release()
        openSetup(selection)
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
            // The terminal commit took the store's active-game reference with
            // it, so what the home would offer has changed even though the
            // board is still standing on the result.
            refreshActiveSummary()
            return true
        } catch {
            return false
        }
    }

    /// Puts the board's game down: the search cancelled, the engine released,
    /// the session ended. The order is the contract's — cancel, then release,
    /// because teardown refuses rather than stalls while a search is
    /// outstanding.
    ///
    /// It says nothing about whether the game is over. Everything it holds is
    /// the board surface's, and everything the game *is* was committed as it
    /// was played.
    ///
    /// - Parameter releasingTheEngine: whether the engine goes with the board.
    ///   It does when the board is left, because the search was owed to a
    ///   surface that is gone. It does *not* when the window closes:
    ///   docs/engine-integration.md's teardown trigger is the platform's own
    ///   suspension or memory-pressure signal and never a window coming or
    ///   going, and `Suspension` already owns those three. The session and the
    ///   search are the board's; the Hash is the app's.
    private func putDownGame(releasingTheEngine: Bool = true) {
        let wasHumanVersusAI = game?.isHumanVersusAI ?? false
        // An engine standing is an engine to release, whatever mode asked for
        // one: a Free Play game that asked for a hint has prepared exactly the
        // table a human-versus-AI game prepares, and leaving its board owes the
        // same release. Asked of the engine rather than tracked here, so the
        // answer is what stands rather than a note about what happened.
        let enginePrepared = game.map { engine.engineIsReady(for: $0.kind) } ?? false
        hint?.cancel()
        hint = nil
        opponent?.cancelSearch()
        opponent = nil
        motion = nil
        game = nil
        core.endSession()
        if wasHumanVersusAI || enginePrepared, releasingTheEngine {
            // **The quiesce between the cancel and the teardown**, which is
            // what the suspension path does and what this needs for the same
            // reason: `mxq_search_cancel` is cooperative and returns before the
            // search has stopped, and `mxq_engine_teardown` refuses with
            // SEARCH_IN_PROGRESS rather than waiting. Without this the engine
            // survives the board that prepared it — up to 4 GiB of Hash — with
            // no opponent left to release it. Both calls are queued on the
            // engine's own serial queue, so the order holds without blocking
            // this actor.
            engine.cancelAllSearches()
            engine.teardownEngine(then: nil)
        }
    }

    /// Lets go of a game that is not coming back — filed, or archived by
    /// 保存并继续 — and re-reads what the store has left to offer.
    private func release() {
        putDownGame()
        resultDismissed = false
        refreshActiveSummary()
    }

    /// Re-reads the store's answer for the home. Called wherever the active
    /// game can have changed under it: the launch, a board put down, an archive
    /// committed or refused.
    private func refreshActiveSummary() {
        do {
            activeSummary = try core.activeGameSummary()
        } catch {
            // A store that cannot say what its active game is has failed in the
            // way the failure screen exists for, and an empty home would hide
            // it.
            activeSummary = nil
            startFailure = CoreError(wrapping: error)
        }
    }

    /// Keeps the running motion on the current policy when Reduce Motion
    /// changes under it.
    func adopt(_ policy: MotionPolicy) {
        motion?.policy = policy
    }

    /// Re-reads the store's answer from outside, for the surfaces that change
    /// the active game without going through this object: a nearby game is
    /// created, filed and given up above it, and the home's card is drawn from
    /// what the store says.
    func activeGameChanged() {
        refreshActiveSummary()
    }

    // MARK: - Launch

    /// What a launch opens: the home, and the store's description of the game
    /// waiting on it.
    ///
    /// docs/interaction-design.md, "Navigation": the app opens at the home in
    /// every mode, and 回到对局 on the card is how the game is continued. **No
    /// session is opened here, and none is left over from before.** The
    /// session, the engine's preparation and any owed search belong to the
    /// board, so a launch that opens no board opens none of them; what the home
    /// shows is `mxq_store_active_summary`, which the C interface built for
    /// exactly this.
    private func openAtLaunch(policy: MotionPolicy) {
        startFailure = nil
        resultDismissed = false
        // Nothing may hold a session while the home is the page, and the launch
        // is the first of those moments. Release is not a saving act — the core
        // committed everything as it happened.
        core.endSession()
        #if DEBUG
        if openLaunchFixture(policy: policy) { return }
        #endif
        refreshActiveSummary()
    }

    #if DEBUG
    /// The one launch that opens a board, and it is a test affordance rather
    /// than product behaviour: `-mxq-replay` exists so a run can start at a
    /// stated position instead of clicking its way to one, and the position is
    /// the whole of what it is for. No release build compiles this, and nothing
    /// a player can do reaches it.
    ///
    /// A launch line names its game as well as its moves. The Free Play game it
    /// belongs to is created here, exactly as 开始对局 would create it; no debug
    /// fixture gets a hidden default game. Answers whether this launch was the
    /// fixture's — a line the core refuses is still the fixture's launch, and
    /// says so on the failure screen.
    private func openLaunchFixture(policy: MotionPolicy) -> Bool {
        do {
            guard let line = try Self.launchReplay() else { return false }
            if try !core.activeGameExists() {
                try rules.create(.freePlay(game: line.game))
            }
            if !rules.hasSession {
                guard try rules.resumeActive() else { return false }
            }
            let fixture = try Game(rules: rules)
            try fixture.replay(line.moves)
            adopt(fixture, policy: policy)
            page = .board
            opponent?.begin()
            return true
        } catch {
            game = nil
            motion = nil
            opponent = nil
            startFailure = CoreError(wrapping: error)
            return true
        }
    }
    #endif

    /// Takes a game onto the screen: its motion, its opponent where it has one,
    /// and the wires between them.
    private func adopt(_ game: Game, policy: MotionPolicy) {
        self.game = game
        let motion = PlayMotion(game: game, policy: policy)
        self.motion = motion
        let opponent = Opponent(engine: engine, game: game, motion: motion)
        self.opponent = opponent
        // **A game no engine plays has no hint to offer**, and the absence is a
        // capability that is not there rather than an act momentarily
        // impossible: docs/interaction-design.md, "Play controls" — nothing in
        // the app plays it, so there is nobody to ask what they would play. The
        // object is not built, which is what takes the control off the cluster;
        // the answer is the core's, per `Core.isPlayedByAnEngine`.
        let hint = Core.isPlayedByAnEngine(game.kind)
            ? Hint(engine: engine, game: game, motion: motion) : nil
        self.hint = hint
        // The search starts at the commit and the reply departs after the
        // landing, so the opponent listens at both.
        //
        // **The hint is put down first**, before the reply is asked for. The
        // core's engine thread runs one search at a time and queues the rest,
        // so a hint still running when the player moves would put the AI's
        // reply behind a whole thinking time of work about a position the game
        // has already left.
        motion.committed = { [weak opponent, weak hint] in
            hint?.cancel()
            opponent?.gameChanged()
        }
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
            // The hint goes down first on both release paths, for the reason
            // the contract gives the order: the release cancels every search
            // and then tears the table down, and a hint whose own state
            // outlived that would be a suggestion about a board the engine has
            // been taken out from under.
            case .suspend:
                self?.hint?.cancel()
                self?.opponent?.suspend()
            case .resume:
                self?.opponent?.resume()
            case .memoryPressure:
                self?.hint?.cancel()
                self?.opponent?.memoryPressure()
            }
        }
    }

    #if DEBUG
    /// The line `-mxq-replay minixiangqi:a1a2,b7b5,…` names, played before
    /// first display so a UI test can start from a position it would otherwise
    /// have to click its way to. The game name is mandatory: a fixture is not
    /// allowed to make Mini Xiangqi an implicit default. Debug only, and no
    /// move of it bypasses the core.
    private static func launchReplay() throws -> LaunchLine? {
        guard let argument = DebugLaunch.argument(after: "-mxq-replay") else {
            return nil
        }
        guard let line = LaunchLine(argument) else {
            throw InvalidLaunchLine(argument: argument)
        }
        return line
    }

    /// The games `-mxq-history minixiangqi:a1a2,b7b5;gomoku-15:h8,i9,…` names,
    /// each played and filed before the board opens, so that a screenshot of
    /// the History list has a library to show and a UI test has records to act
    /// on. Games are separated by `;`, every game name is mandatory, and plies
    /// are separated by `,`.
    ///
    /// Each one goes through the same path a person's game does — created by its
    /// own configuration, every ply committed by the core, the finished game
    /// filed by its own terminal commit — so nothing seeded here is a record the
    /// app could not have made. A line the core refuses stops the seeding rather
    /// than filing a half-game, and the launch continues: the failure then shows
    /// as a shorter list than the test asked for, where a test can see it.
    private func fileLaunchHistory() {
        let requested = (DebugLaunch.argument(after: "-mxq-history") ?? "")
            .split(separator: ";")
        let lines = requested.compactMap { LaunchLine($0) }
        guard !lines.isEmpty, lines.count == requested.count else { return }
        for line in lines {
            core.endSession()
            guard (try? core.create(.freePlay(game: line.game))) != nil,
                  let game = try? Game(rules: core), (try? game.replay(line.moves)) != nil
            else { return }
            if game.evaluation.claimAvailable {
                game.claimDraw()
            } else if game.isFinished {
                try? game.file()
            }
        }
        core.endSession()
    }

    /// One explicit debug fixture line. Its game names are the data contract's
    /// own spellings, so a fixture and the record it produces use one
    /// vocabulary.
    ///
    /// **A game whose start is dealt names none of them**, and a line asking for
    /// one is refused rather than dealt a start of its own: a fixture exists so
    /// a run can begin at a *stated* position, and a line whose position was
    /// drawn from the platform's randomness states nothing. Such a fixture would
    /// have to carry the deal it was played from, and none does.
    private struct LaunchLine {
        var game: GameKind
        var moves: [String]

        init?(_ text: some StringProtocol) {
            let parts = text.split(separator: ":", maxSplits: 1,
                                   omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            switch parts[0] {
            case "minixiangqi": game = .miniXiangqi
            case "xiangqi": game = .xiangqi
            case "gomoku-15": game = .gomoku15
            case "renju": game = .renju
            default: return nil
            }
            moves = String(parts[1]).split(separator: ",").map(String.init)
        }
    }

    private struct InvalidLaunchLine: Error, CustomStringConvertible {
        var argument: String
        var description: String {
            "debug replay line must name a game this app carries: \(argument)"
        }
    }
    #endif
}

// MARK: - The one active game, and nearby play's claim on it

extension PlayState: NearbyRoom {
    var standingNearbyGame: GameKind? {
        guard let activeSummary, activeSummary.mode == .nearby else { return nil }
        return activeSummary.game
    }

    /// The accepted flow, asked for by a nearby surface rather than by a mode
    /// row: the library holds one active game, so a nearby game that is about to
    /// exist needs whatever stands to be filed first, and the confirmation that
    /// files it is the one the contract already accepts.
    ///
    /// The board is left before the asking, because both of that flow's alerts
    /// belong to the home — the same invariant 回到对局 relies on.
    func makeRoom(for game: GameKind, then opening: @escaping @MainActor () -> Void) {
        guard modeSwitch == nil else { return }
        if page == .board {
            leaveBoard()
            page = .home
        }
        guard activeSummary != nil else {
            opening()
            return
        }
        pendingOpening = opening
        modeSwitch = .confirming(PlaySelection(game: game, mode: .nearby))
    }
}
