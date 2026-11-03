// Lives above the navigation container, which keeps one destination alive at a
// time: a result notice the player closed must not come back when Play is
// rebuilt. The game itself is the board's: taken up when the board is entered
// and put down when it is left, so nothing plays or sounds off screen. Every
// move is saved as it is made, so nothing is lost by putting it down.

import Foundation
import Observation

/// The Settings defaults a new human-versus-AI game's setup opens with, stored
/// under their archive names.
extension FirstMoverChoice {
    static let key = "defaults.firstMover"
    static var stored: FirstMoverChoice {
        UserDefaults.standard.string(forKey: key).flatMap(Self.init(name:)) ?? .humanFirst
    }
}

extension AiLevel {
    static let key = "defaults.aiLevel"
    static var stored: AiLevel {
        UserDefaults.standard.string(forKey: key).flatMap(Self.init(name:)) ?? .standard
    }
}

/// A draft only: never autosaved, never written back to the Settings defaults,
/// and gone as soon as the player leaves the page.
struct SetupDraft: Equatable {
    var firstMover: FirstMoverChoice
    var level: AiLevel

    static func fromDefaults() -> SetupDraft {
        SetupDraft(firstMover: .stored, level: .stored)
    }

    /// Called only after preparation succeeds, and committed only by a
    /// successful create, so a retry draws again.
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

struct PlaySelection: Equatable {
    var game: GameKind
    var mode: PlayMode
}

/// Room in a library that holds one active game: a game between two devices is
/// created the moment they agree to play, so whatever stands is filed first.
@MainActor
protocol NearbyRoom: AnyObject {
    /// Tells an entry row the way in is back into the interrupted game. Asked
    /// per mode: an online game standing is not one the nearby row may walk into.
    func standingGame(in mode: PlayMode) -> GameKind?

    /// `then` runs once the slot is free: at once, or after 保存并继续. It does
    /// not run if the player cancels or the archive is refused.
    func makeRoom(for game: GameKind, in mode: PlayMode,
                  then: @escaping @MainActor () -> Void)
}

@Observable
final class PlayState {
    private let library: GameLibrary
    private let core: Core

    /// A seam because a working engine will not refuse to prepare on request.
    private let engine: AIEngine

    /// The home is the root and the rest are pushed over it, so this is also the
    /// navigation path. The initial value is the launch rule: a fresh launch
    /// opens at the home in every mode.
    enum Page: Equatable {
        case home
        /// Over a noninteractive preview of the starting position.
        case setup(PlaySelection)
        /// Over an empty interactive board; it starts a Free Play game of
        /// Xiangqi from the composed position.
        case customScene
        case board
    }

    private(set) var page: Page = .home

    private(set) var game: Game?
    private(set) var motion: PlayMotion?
    private(set) var opponent: Opponent?

    /// Opened and put down with the game. The nearby board builds none.
    private(set) var hint: Hint?

    /// Feeds the home's card and the confirmation's metadata line. A filed game
    /// is not in it: filing ends the game in play, even while its result still
    /// stands on the board.
    private(set) var activeSummary: ActiveGameSummary?

    /// The pre-start controls' draft. Meaningful only while `page` is
    /// `.setup`, and replaced afresh on every entry.
    var draft = SetupDraft.fromDefaults()

    /// Made afresh on every entry: a game whose start is dealt has no constant
    /// to read.
    private(set) var preview: String = ""

    /// In memory only: dropping it is the whole of discarding it.
    private(set) var scene: CustomScene?

    /// Why the last **开始对局** created nothing. The page and the draft stay,
    /// and the control is enabled again.
    enum CreationFailure: Equatable {
        /// 无法启动 AI 对手: the budget was below the minimum, or the allocation
        /// failed at a budget that was not.
        case aiUnavailable
        /// The game could not be persisted. Nothing was created, and anything
        /// prepared for it has been released.
        case notSaved(CoreError)
    }

    private(set) var creationFailure: CreationFailure?

    /// The destination is carried inside the flow, so it cannot outlive the
    /// confirmation or its retry.
    enum ModeSwitch: Equatable {
        /// The 开始新对局？ confirmation is up.
        case confirming(PlaySelection)
        /// 保存并继续 was pressed and the archive is running.
        case saving(PlaySelection)
        /// The 无法保存对局 retry is up, and the game is exactly as it stood.
        case failed(PlaySelection)

        var selection: PlaySelection {
            switch self {
            case .confirming(let selection), .saving(let selection), .failed(let selection):
                selection
            }
        }
    }

    private(set) var modeSwitch: ModeSwitch?

    /// Where a surface asked for the room rather than a mode row: a nearby
    /// proposal, or the Custom Scene editor. Discarded with the flow.
    private var pendingOpening: (@MainActor () -> Void)?

    /// Called before any path takes the active game away, so the wire session
    /// held above this object goes with the game rather than writing to one
    /// that is gone. Nil where no such layer exists.
    var giveUpNetworkedGame: (@MainActor (PlayMode) -> Void)?

    /// 开始对局 cannot be invoked again while this is true.
    private(set) var creating = false

    /// The attempt in flight, and the invalidation of every earlier one.
    /// Leaving the pre-start state bumps it, which is what stops a late
    /// completion from committing after the draft is discarded.
    private var attempt = 0

    /// Shown rather than swallowed: a game that will not start is a bug or a
    /// packaging failure, never a rules outcome.
    private(set) var startFailure: CoreError?

    /// The game's presentation, not the screen's: the notice does not come back
    /// for a result already seen. A result still unfiled at quit does present
    /// again at the next launch.
    var resultDismissed = false

    /// The destination draws nothing until this is true, so the home does not
    /// appear without the active game's card and then grow one.
    private(set) var started = false

    private var suspension: Suspension?

    /// The filing step of 保存并继续, replaceable so a test can hold it in flight.
    @ObservationIgnored
    var archiveActiveGame: (@escaping @MainActor (Result<UUID, CoreError>) -> Void) -> Void

    init(library: GameLibrary, engine: AIEngine? = nil) {
        self.library = library
        self.core = library.core
        self.engine = engine ?? library.core
        self.archiveActiveGame = { [library] in library.archiveActiveAndClear(completion: $0) }
    }

    func startIfNeeded(policy: MotionPolicy) {
        guard !started else { return }
        started = true
        watchForSuspension()
        openAtLaunch(policy: policy)
    }

    // MARK: - The home

    /// With a game active the confirmation presents instead, and the
    /// destination waits inside it.
    func choose(_ selection: PlaySelection) {
        guard page == .home, modeSwitch == nil else { return }
        if activeSummary != nil {
            modeSwitch = .confirming(selection)
            return
        }
        openSetup(selection)
    }

    /// With a game active it presents the same confirmation, and the editor
    /// opens only once that archive has committed.
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

    /// Clears the confirmation and nothing else, because the alert's own
    /// dismissal arrives after the button's action: 保存并继续 would otherwise
    /// be followed by a cancel that discarded the archive it had just started.
    func dismissConfirmation() {
        if case .confirming = modeSwitch {
            modeSwitch = nil
            pendingOpening = nil
        }
    }

    /// Clears the failure and nothing else, for the same reason: 重试 must
    /// survive its own alert going away. The pending opening goes too, or it
    /// would run on the next mode switch that succeeded.
    func dismissArchiveFailure() {
        if case .failed = modeSwitch {
            modeSwitch = nil
            pendingOpening = nil
        }
    }

    /// An ongoing game or an unclaimed claimable repetition is filed as ended
    /// early; a result the rules decided keeps its result and reason. A refusal
    /// commits nothing, and the retry presents over the game as it stood.
    func saveAndContinue() {
        guard let selection = modeSwitch?.selection, activeSummary != nil else { return }
        guard modeSwitch != .saving(selection) else { return }
        modeSwitch = .saving(selection)
        // Given up before the filing, so the session does not keep writing to a
        // game that is gone.
        if let mode = activeSummary?.mode, mode.isNetworked {
            giveUpNetworkedGame?(mode)
        }
        archiveActiveGame { [weak self] result in
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

    /// Not while a mode switch is in flight: both of its alerts belong to the
    /// home, and this guard makes `modeSwitch != nil` imply `page == .home`.
    func resume(policy: MotionPolicy) {
        guard page == .home, modeSwitch == nil, let summary = activeSummary else { return }
        // A networked game is continued on its own board, over its session.
        if summary.mode.isNetworked {
            resumeNetworkedGame?(summary.mode, summary.game)
            return
        }
        page = .board
        enterBoard(policy: policy)
    }

    /// Nil where there are no such surfaces; the card then does nothing rather
    /// than open the game on a local board.
    var resumeNetworkedGame: (@MainActor (PlayMode, GameKind) -> Void)?

    private func openSetup(_ selection: PlaySelection) {
        draft = SetupDraft.fromDefaults()
        creationFailure = nil
        preview = previewStart(of: selection.game)
        page = .setup(selection)
    }

    /// A dealt game previews a deal of its own, not the one it will be played
    /// from: every deal looks the same from outside. A deal the core refuses
    /// previews an empty board; the game is dealt again when it is created.
    private func previewStart(of game: GameKind) -> String {
        if let frozen = Core.frozenStartFEN(for: game) { return frozen }
        return (try? core.deal(game).startFEN) ?? ""
    }

    private func openCustomScene() {
        creationFailure = nil
        scene = CustomScene(core: core)
        page = .customScene
    }

    /// From the board, the game stays committed and the home's card is the way
    /// back; the session, the engine and any owed search are put down.
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

    /// Called by 回到对局, and again whenever the destination is rebuilt.
    /// Idempotent: a board that already holds its game asks the library for
    /// nothing.
    func enterBoard(policy: MotionPolicy) {
        guard page == .board, game == nil, startFailure == nil else { return }
        do {
            if !library.hasSession {
                guard try library.resumeActive() else {
                    activeSummary = nil
                    page = .home
                    return
                }
                // A networked game is played on a board of its own, which the
                // home's card opens.
                if try library.configuration().mode.isNetworked {
                    library.endSession()
                    page = .home
                    refreshActiveSummary()
                    return
                }
            }
            adopt(try Game(library: library), policy: policy)
            opponent?.begin()
        } catch {
            game = nil
            motion = nil
            opponent = nil
                // The resume succeeded but the game would not open: end the
                // session so nothing stands behind the failure screen.
            library.endSession()
            startFailure = CoreError(wrapping: error)
        }
    }

    /// Nothing is lost: every move was saved as it was made. A filed game does
    /// not come back, so its board is let go of with the surface.
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

    /// On macOS a closed window is not the app going away. The engine stays:
    /// releasing gigabytes of Hash because a window closed is the mistake
    /// `Suspension` exists to avoid.
    func windowClosed() {
        guard game != nil else { return }
        putDownGame(releasingTheEngine: false)
        page = .home
        refreshActiveSummary()
    }

    /// A nearby board is drawn over every page, so while it is up the local
    /// board is not on screen and gives up its game, engine and search.
    func nearbyBoardPresented(_ isPresented: Bool, policy: MotionPolicy) {
        if isPresented {
            leaveBoard()
        } else {
            enterBoard(policy: policy)
        }
    }

    /// The draft is discarded and an attempt in flight is invalidated, so a late
    /// completion commits nothing. The Custom Scene editor leaves the same way.
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

    /// 取消 on the creation-failure notice; the draft is untouched.
    func dismissCreationFailure() {
        creationFailure = nil
    }

    /// Prepare, resolve, create, search, each a gate on the next. A Random side
    /// is drawn only after preparation succeeds and committed only by the
    /// create, so a retry draws again; a persistence failure releases the
    /// prepared engine.
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

        // A fresh probe at every attempt: the retry after the insufficient-memory
        // notice exists to see the memory the user just freed.
        engine.prepareEngine(for: selection.game, engine.memoryBudget()) { [weak self] result in
            guard let self else { return }
            guard token == attempt else {
                // Stale: the player left, or a newer attempt owns the engine.
                // Release only when nothing newer relies on it.
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
                                  level: draft.level),
                   policy: policy, token: token)
        }
    }

    /// Free Play owes no search, so nothing is prepared. A dealt game is dealt
    /// here, at creation and not before: the deal is the game. Nothing of it is
    /// kept, because the dealt start in the record is the deal. A refused deal
    /// presents the same notice as a refused save.
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

    /// A Free Play game of Xiangqi from the composed position. The `canStart`
    /// guard makes the disabled control the rule: past it the core would answer
    /// `MXQ_ERR_STATE_GAME_OVER`, reported wrongly as a save failure.
    func startScene(policy: MotionPolicy) {
        guard page == .customScene, let scene, scene.canStart, !creating else { return }
        creating = true
        creationFailure = nil
        attempt += 1
        create(.freePlay(game: CustomScene.game, startFEN: scene.fen),
               policy: policy, token: attempt)
    }

    /// By code, not domain: insufficient memory and a failed Hash allocation are
    /// one situation to the player. Other engine failures (a missing network, a
    /// faulted engine) take the cause-free notice; telling someone to close
    /// other apps about a damaged installation is worse than telling them
    /// nothing.
    private static func creationFailure(for failure: CoreError) -> CreationFailure {
        failure.isInsufficientMemory ? .aiUnavailable : .notSaved(failure)
    }

    private func create(_ configuration: GameConfiguration, policy: MotionPolicy,
                        token: Int) {
        do {
            library.endSession()
            try library.create(configuration)
            adopt(try Game(library: library), policy: policy)
            creating = false
            // The editor is not a page to come back to from the board; the way
            // back is the home.
            scene = nil
            page = .board
            opponent?.begin()
        } catch {
            creating = false
            creationFailure = .notSaved(CoreError(wrapping: error))
            library.endSession()
            // The engine was prepared for a game that does not exist.
            if configuration.mode == .humanVersusAI {
                engine.teardownEngine(then: nil)
            }
        }
    }

    // MARK: - Concluding a game

    /// The filing and nothing else; the board stays on the result. A refused
    /// filing answers `false` and the game stays in play as it stood.
    func save() -> Bool {
        guard let game else { return true }
        return file(game)
    }

    /// Files first (a claimed draw or a saved result is not filed twice), then
    /// opens the game's own mode's pre-start page, so the next game's side and
    /// level are chosen rather than inherited. A refused filing resets nothing
    /// and answers `false`.
    func startNewGame() -> Bool {
        guard let game else { return true }
        let selection = PlaySelection(game: game.kind, mode: game.mode)
        guard file(game) else { return false }
        release()
        openSetup(selection)
        return true
    }

    /// 完成 on the recorded notice.
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
            // The board still stands on the result, but the game in play has
            // ended.
            refreshActiveSummary()
            return true
        } catch {
            return false
        }
    }

    /// Cancel, then release: teardown refuses rather than stalls while a search
    /// is outstanding.
    ///
    /// - Parameter releasingTheEngine: false when the window closes. Only the
    ///   platform's suspension and memory-pressure signals release the Hash,
    ///   which is the app's rather than the board's.
    private func putDownGame(releasingTheEngine: Bool = true) {
        let wasHumanVersusAI = game?.isHumanVersusAI ?? false
        // A Free Play game that asked for a hint has prepared the same table,
        // so the engine is asked rather than the mode.
        let enginePrepared = game.map { engine.engineIsReady(for: $0.kind) } ?? false
        hint?.cancel()
        hint = nil
        opponent?.cancelSearch()
        opponent = nil
        motion = nil
        game = nil
        library.endSession()
        if wasHumanVersusAI || enginePrepared, releasingTheEngine {
            // `mxq_search_cancel` returns before the search has stopped, and
            // `mxq_engine_teardown` refuses with SEARCH_IN_PROGRESS rather than
            // waiting. Without the cancel, up to 4 GiB of Hash outlives the
            // board. Both calls are queued on the engine's own serial queue, so
            // the order holds without blocking this actor.
            engine.cancelAllSearches()
            engine.teardownEngine(then: nil)
        }
    }

    /// Lets go of a game that is not coming back — filed, or archived by
    /// 保存并继续 — and re-reads what the library has left to offer.
    private func release() {
        putDownGame()
        resultDismissed = false
        refreshActiveSummary()
    }

    /// Called wherever the game in play can have changed: the launch, a board
    /// put down, a filing saved or refused.
    private func refreshActiveSummary() {
        do {
            activeSummary = try library.activeGameSummary()
        } catch {
            // A library that cannot say what its game in play is needs the
            // failure screen; an empty home would hide it.
            activeSummary = nil
            startFailure = CoreError(wrapping: error)
        }
    }

    /// Keeps the running motion on the current policy when Reduce Motion
    /// changes under it.
    func adopt(_ policy: MotionPolicy) {
        motion?.policy = policy
    }

    /// For surfaces that change the game in play without going through this
    /// object, such as a nearby game created or filed above it.
    func activeGameChanged() {
        refreshActiveSummary()
    }

    // MARK: - Launch

    /// No game is taken up at launch: the game, the engine and any owed search
    /// belong to the board.
    private func openAtLaunch(policy: MotionPolicy) {
        startFailure = nil
        resultDismissed = false
        library.endSession()
        refreshActiveSummary()
    }

    private func adopt(_ game: Game, policy: MotionPolicy) {
        self.game = game
        let motion = PlayMotion(game: game, policy: policy)
        self.motion = motion
        let opponent = Opponent(engine: engine, game: game, motion: motion)
        self.opponent = opponent
        // A game no engine plays has no hint: the object is not built, which
        // takes the control off the cluster.
        let hint = Core.isPlayedByAnEngine(game.kind)
            ? Hint(engine: engine, game: game, motion: motion) : nil
        self.hint = hint
        // The search starts at the commit and the reply departs after the
        // landing. The hint is cancelled first: the engine thread runs one
        // search at a time, so a running hint would delay the reply by a whole
        // thinking time.
        motion.committed = { [weak opponent, weak hint] in
            hint?.cancel()
            opponent?.gameChanged()
        }
        motion.landed = { [weak opponent] in opponent?.landed() }
        // A resumed position may already stand in check; its rings pulse
        // as they first appear.
        motion.boardAppeared()
    }

    // MARK: - Suspension

    private func watchForSuspension() {
        suspension = Suspension { [weak self] event in
            switch event {
            // The hint goes down first on both release paths, so it does not
            // outlive the engine taken out from under it.
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

}

// MARK: - The one active game, and the claim playing somebody has on it

extension PlayState: NearbyRoom {
    func standingGame(in mode: PlayMode) -> GameKind? {
        guard let activeSummary, activeSummary.mode == mode else { return nil }
        return activeSummary.game
    }

    /// The library holds one active game, so whatever stands is filed first,
    /// through the same confirmation. The board is left before the asking,
    /// because both of that flow's alerts belong to the home.
    func makeRoom(for game: GameKind, in mode: PlayMode,
                  then opening: @escaping @MainActor () -> Void) {
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
        modeSwitch = .confirming(PlaySelection(game: game, mode: mode))
    }
}
