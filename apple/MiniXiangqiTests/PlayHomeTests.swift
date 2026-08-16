// The Play home: what its card says, and what choosing a mode does over a game.
//
// docs/interaction-design.md, "Saving the active game before choosing a new
// mode": the destination shows the active game's metadata and a direct Resume,
// all four game-and-mode entries stay interactive while a game exists, and selecting one
// presents the one fixed confirmation. 保存并继续 archives the game by its own
// current state before the selected mode's pre-start page opens; a refusal keeps
// the game exactly as it stood and offers the accepted retry; 取消 discards the
// remembered destination and changes nothing.
//
// The metadata assertions are about **composition** — which facts appear, in
// what order, joined by the accepted format — rather than about the words. The
// words are the catalog's, and they are asserted against it in CopyTests and
// photographed in both languages by the UI suite. Composing the
// expectation from the same catalog is what keeps this suite honest about which
// of the two it is testing.

// The archive itself is the one seam that cannot answer inside its own call:
// docs/core-interface.md's threading contract keeps `mxq_store_archive_and_clear`
// off the UI thread, so it answers from a queue. A test that awaited that answer
// would suspend while holding the one core this suite shares, and the suite's
// whole coordination is that no test ever does — an await lets the next test in,
// and the next test's first act is to shut this one's core down. So the archive
// is parked here and answered by the test, exactly as ManualAnimator parks an
// animation's completion. What the parked seam proves is the wiring.
//
// What the core itself does — detaching the session with the call, putting it
// back when the archive is refused, and hopping the answer onto this actor — is
// the second suite in this file, driven through the real
// `Core.archiveActiveAndClear` with the seam let go of. Those tests have to
// suspend, because the answer is a main-actor turn away and only a suspension
// gives the actor that turn; a nested run loop does not, since the turn is a
// main-queue block and one main-queue block cannot drain the next. So they obey
// the rule the other way round: each shuts its own core down *before* it
// suspends, and holds nothing while the next test runs.

import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

/// The archive seam, held open. Every other question is the real core's.
@MainActor
final class ParkedArchive: Rules {
    private let real: Rules

    /// How many archives have been asked for. The retry asks again, and asking
    /// twice for one press would be the bug this counts.
    private(set) var requests = 0

    private var parked: (@MainActor (Result<UInt64, CoreError>) -> Void)?

    var isPending: Bool { parked != nil }

    init(_ real: Rules) { self.real = real }

    func archiveActiveAndClear(
        completion: @escaping @MainActor (Result<UInt64, CoreError>) -> Void
    ) {
        requests += 1
        parked = completion
    }

    /// Answers the archive in flight, as the queue would.
    func answer(_ result: Result<UInt64, CoreError>) {
        let completion = parked
        parked = nil
        completion?(result)
    }

    /// The store-domain refusal the accepted 无法保存对局 retry is for.
    func answerWithRefusal() {
        answer(.failure(CoreError(wrapping: RefusedByTheCore())))
    }

    var hasSession: Bool { real.hasSession }
    func resumeActive() throws -> Bool { try real.resumeActive() }
    func create(_ configuration: GameConfiguration) throws { try real.create(configuration) }
    func configuration() throws -> GameConfiguration { try real.configuration() }
    func gameID() throws -> String { try real.gameID() }
    func resign() throws -> UInt64 { try real.resign() }
    func apply(_ move: String) throws { try real.apply(move) }
    func undo() throws -> Int { try real.undo() }
    func claimDraw() throws -> UInt64 { try real.claimDraw() }
    func confirmResult() throws -> UInt64 { try real.confirmResult() }
    func evaluation() throws -> Evaluation { try real.evaluation() }
    func moveHistory() throws -> [String] { try real.moveHistory() }
    func legalMoves() throws -> [String] { try real.legalMoves() }
    func fen(atPly ply: Int) throws -> String { try real.fen(atPly: ply) }
    func firstMover() throws -> Side { try real.firstMover() }
}

/// The catalog's answer in whatever language the host is running, which is the
/// language the composition under test will have used.
private func text(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// The accepted metadata join, applied repeatedly — the same composition
/// `metadataLine` performs, built here from the parts it should have chosen.
private func joined(_ parts: String...) -> String {
    parts.dropFirst().reduce(parts[0]) { String(format: text("metadata.join"), $0, $1) }
}

private func moves(_ count: Int) -> String {
    String(format: text("metadata.moveCount"), count)
}

@Suite("The Play home", .retiringItsCores)
@MainActor
struct PlayHomeTests {

    private static let miniAI = PlaySelection(game: .miniXiangqi,
                                              mode: .humanVersusAI)
    private static let miniFreePlay = PlaySelection(game: .miniXiangqi,
                                                    mode: .freePlay)
    private static let xiangqiAI = PlaySelection(game: .xiangqi,
                                                 mode: .humanVersusAI)

    /// The start position a third time, which is what makes the draw claimable.
    private static let shuffleLine = ["b1b2", "b7b6", "b2b1", "b6b7",
                                      "b1b2", "b7b6", "b2b1", "b6b7"]

    /// The shortest checkmate from the start position.
    private static let mateLine = ["b1b3", "b7b6", "b3d3"]

    // MARK: - What the card says

    @Test("Both games have one localized display name")
    func bothGamesHaveDisplayNames() {
        #expect(GameKind.xiangqi.localizedName == text("game.xiangqi"))
        #expect(GameKind.miniXiangqi.localizedName == text("game.miniXiangqi"))
    }

    /// What the home reads: the store's summary of the active game, with no
    /// session attached to it. The session that played the line is ended first,
    /// so what these tests assert is what the card can actually see.
    private func cardLine(on core: Core) throws -> String {
        core.endSession()
        let summary = try #require(try core.activeGameSummary(),
                                   "the store should hold the active game")
        return summary.metadataLine
    }

    @Test("An ongoing game reads as its mode, that it is going, and whose turn it is")
    func anOngoingGameReadsAsItsTurn() throws {
        let core = try TestCores.fresh()
        _ = try openGame(on: core)

        #expect(try cardLine(on: core) == joined(text("game.miniXiangqi"),
                                                 text("mode.freePlay"),
                                                 text("metadata.inProgress"),
                                                 text("status.redToMove"),
                                                 moves(0)))

        let resumed = try openGame(on: core)
        try resumed.replay(["b1b3"])
        #expect(try cardLine(on: core) == joined(text("game.miniXiangqi"),
                                                 text("mode.freePlay"),
                                                 text("metadata.inProgress"),
                                                 text("status.blackToMove"),
                                                 moves(1)),
                "one ply on the turn has passed, which is the ply count's parity")
    }

    @Test("A human-versus-AI game names the side the player is holding")
    func aHumanVersusAIGameNamesTheHumanSide() throws {
        let core = try TestCores.fresh()
        try core.create(.humanVersusAI(game: .miniXiangqi, humanSide: .red,
                                       level: .standard, choice: .humanFirst))
        #expect(try cardLine(on: core) == joined(text("game.miniXiangqi"),
                                                 text("mode.humanVersusAI"),
                                                 text("metadata.youRed"),
                                                 text("metadata.inProgress"),
                                                 text("status.redToMove"),
                                                 moves(0)))

        let other = try TestCores.fresh()
        try other.create(.humanVersusAI(game: .miniXiangqi, humanSide: .black,
                                        level: .fast, choice: .aiFirst))
        #expect(try cardLine(on: other) == joined(text("game.miniXiangqi"),
                                                  text("mode.humanVersusAI"),
                                                  text("metadata.youBlack"),
                                                  text("metadata.inProgress"),
                                                  text("status.redToMove"),
                                                  moves(0)),
                "the side the human holds is not the side to move")
    }

    @Test("A claimable repetition is still going, and says the claim is there")
    func aClaimableRepetitionCarriesTheStandingOffer() throws {
        let core = try TestCores.fresh()
        let game = try openGame(on: core)
        try game.replay(Self.shuffleLine)
        #expect(game.evaluation.claimAvailable, "the line should have made the claim available")

        #expect(try cardLine(on: core) == joined(text("game.miniXiangqi"),
                                                 text("mode.freePlay"),
                                                 text("metadata.inProgress"),
                                                 text("status.drawAvailable"),
                                                 moves(8)),
                "the claim takes the side-to-move slot, as the accepted example line does")
    }

    @Test("A terminal game reads as its result and the reason for it")
    func aTerminalGameReadsAsItsResult() throws {
        let core = try TestCores.fresh()
        let game = try openGame(on: core)
        try game.replay(Self.mateLine)
        #expect(game.isFinished)

        #expect(try cardLine(on: core) == joined(text("game.miniXiangqi"),
                                                 text("mode.freePlay"),
                                                 text("result.redWins"),
                                                 text("reason.checkmate"),
                                                 moves(3)),
                "the longer result register, and the reason beside it")
    }

    // MARK: - Choosing a mode

    @Test("With no game a mode entry opens its pre-start page")
    func aModeEntryWithNoGameOpensTheSetup() throws {
        let core = try TestCores.fresh()
        let state = PlayState(core: core)

        state.choose(Self.miniFreePlay)

        #expect(state.page == .setup(Self.miniFreePlay))
        #expect(state.modeSwitch == nil, "nothing to confirm with no game to keep")
    }

    @Test("With a game a mode entry confirms instead of navigating")
    func aModeEntryWithAGameConfirms() throws {
        let core = try TestCores.fresh()
        let state = PlayState(core: core)
        try core.create(.freePlay(game: .miniXiangqi))
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home, "a fresh launch opens at the home")
        #expect(state.activeSummary != nil, "over the game it resumed, still running")

        state.choose(Self.miniAI)

        #expect(state.modeSwitch == .confirming(Self.miniAI))
        #expect(state.page == .home, "the confirmation stands between the press and the page")
        #expect(state.activeSummary != nil, "and nothing has happened to the game yet")
    }

    @Test("取消 discards the remembered destination and changes nothing")
    func cancellingDiscardsTheDestination() throws {
        let core = try TestCores.fresh()
        let state = try stateOverAGame(core)
        state.choose(Self.miniAI)
        #expect(state.modeSwitch != nil)

        state.dismissConfirmation()

        #expect(state.modeSwitch == nil, "the destination lives no longer than the flow")
        #expect(state.page == .home)
        #expect(state.activeSummary != nil)
        #expect(try core.activeGameExists())
        #expect(try core.historyCount() == 0, "cancelling files nothing")
    }

    @Test("保存并继续 archives before it navigates, and keeps the chosen game and mode")
    func saveAndContinueArchivesThenOpensTheSelection() throws {
        let core = try TestCores.fresh()
        let (state, archive) = try parkedStateOverAGame(core)

        state.choose(Self.xiangqiAI)
        state.saveAndContinue()

        #expect(archive.requests == 1, "one press, one archive")
        #expect(archive.isPending)
        #expect(state.modeSwitch == .saving(Self.xiangqiAI))
        #expect(state.page == .home, "nothing opens until the archive has committed")
        // The press is answered before the archive is, and answering it must
        // not discard the archive it started.
        state.dismissConfirmation()
        #expect(state.modeSwitch == .saving(Self.xiangqiAI))

        archive.answer(.success(1))

        #expect(state.page == .setup(Self.xiangqiAI),
                "the selected game's pre-start page, with no hidden Mini default")
        #expect(state.modeSwitch == nil, "and the remembered destination is spent")
        #expect(state.game == nil && !core.hasSession,
                "the whole flow stood on the home, which holds neither")
    }

    @Test("A refused archive keeps the game, and 重试 asks for the same thing again")
    func aRefusedArchiveKeepsTheGame() throws {
        let core = try TestCores.fresh()
        let (state, archive) = try parkedStateOverAGame(core)

        state.choose(Self.miniAI)
        state.saveAndContinue()
        archive.answerWithRefusal()

        #expect(state.modeSwitch == .failed(Self.miniAI), "the accepted retry presents")
        #expect(state.page == .home, "the pre-start page did not open")
        #expect(state.activeSummary != nil, "the game is still here")
        #expect(try core.activeGameExists(), "and still the store's active game")
        #expect(try core.historyCount() == 0, "nothing was filed")

        state.saveAndContinue()

        #expect(archive.requests == 2, "重试 repeats the same atomic operation")
        #expect(state.modeSwitch == .saving(Self.miniAI),
                "over the destination the confirmation remembered")
        archive.answer(.success(1))
        #expect(state.page == .setup(Self.miniAI))
    }

    @Test("取消 on the refusal discards the destination and leaves the game")
    func cancellingTheRefusalDiscardsTheDestination() throws {
        let core = try TestCores.fresh()
        let (state, archive) = try parkedStateOverAGame(core)

        state.choose(Self.miniFreePlay)
        state.saveAndContinue()
        archive.answerWithRefusal()
        #expect(state.modeSwitch == .failed(Self.miniFreePlay))

        state.dismissArchiveFailure()

        #expect(state.modeSwitch == nil, "the destination goes with the flow that held it")
        #expect(state.page == .home)
        #expect(state.activeSummary != nil)
        #expect(try core.activeGameExists(), "the game the retry was about is still active")
        #expect(try core.historyCount() == 0)

        // And a fresh choice starts a fresh flow rather than resuming the old
        // one: nothing was left behind to archive.
        state.choose(Self.miniAI)
        #expect(state.modeSwitch == .confirming(Self.miniAI))
        #expect(archive.requests == 1, "the discarded flow asked for nothing more")
    }

    @Test("An archive still in flight is asked for once, however often it is pressed")
    func anArchiveInFlightIsNotStartedTwice() throws {
        let core = try TestCores.fresh()
        let (state, archive) = try parkedStateOverAGame(core)

        state.choose(Self.miniFreePlay)
        state.saveAndContinue()
        state.saveAndContinue()
        state.saveAndContinue()

        #expect(archive.requests == 1)
        archive.answer(.success(1))
        #expect(state.page == .setup(Self.miniFreePlay))
    }

    // MARK: - Resuming, and the game that is no longer active

    @Test("回到对局 opens the board, and the session with it, on the game that was left")
    func resumeOpensTheBoard() throws {
        let core = try TestCores.fresh()
        let played = try openGame(on: core)
        try played.replay(["b1b3"])
        core.endSession()

        let state = PlayState(core: core)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home)
        #expect(state.game == nil, "the home describes the game rather than holding it")
        #expect(!core.hasSession)

        state.resume(policy: MotionPolicy(reduceMotion: true))

        #expect(state.page == .board)
        #expect(core.hasSession, "the board is what opens the session")
        #expect(state.game?.moves == ["b1b3"], "the same game, exactly where it was left")
    }

    @Test("Leaving the board puts down the session, the engine and the search it opened")
    func leavingTheBoardPutsDownWhatItOpened() throws {
        let core = try TestCores.fresh()
        let engine = TestEngine()
        let state = PlayState(core: core, engine: engine)
        // A game the machine opens, so that entering its board is what makes
        // the machine think and leaving it is what stops it.
        try core.create(.humanVersusAI(game: .miniXiangqi, humanSide: .black,
                                       level: .fast, choice: .aiFirst))
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home)
        #expect(!core.hasSession, "a launch opens no session")
        #expect(engine.preparations == 0, "and prepares nothing")

        state.resume(policy: MotionPolicy(reduceMotion: true))
        #expect(core.hasSession, "the board opens the session")
        #expect(engine.preparations == 1, "prepares the engine")
        #expect(engine.startedSearches == 1, "and asks for the reply the game owes")

        state.leaveTopPage()

        #expect(state.page == .home)
        #expect(engine.cancelledTickets.count == 1, "leaving cancels the search")
        #expect(engine.cancelAlls == 1,
                "quiesces the engine, the teardown behind it refusing rather than waiting")
        #expect(engine.teardowns == 1, "releases the engine")
        #expect(!core.hasSession, "and ends the session")
        #expect(state.game == nil, "the game went with the board it was on")
        #expect(try core.activeGameExists(),
                "while the game itself stays committed and active")
        #expect(state.activeSummary?.moveCount == 0,
                "and the home's card describes it from the store, having no session to ask")
    }

    @Test("A nearby board over the local pages takes the local game down with it")
    func aNearbyBoardTakesTheLocalGameDown() throws {
        let core = try TestCores.fresh()
        let engine = TestEngine()
        let state = PlayState(core: core, engine: engine)
        try core.create(.humanVersusAI(game: .miniXiangqi, humanSide: .black,
                                       level: .fast, choice: .aiFirst))
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        state.resume(policy: MotionPolicy(reduceMotion: true))
        #expect(core.hasSession)
        #expect(engine.startedSearches == 1, "the machine is thinking on the local board")

        // A nearby game's board is drawn over every page of this destination,
        // so the local board is no longer the board on screen.
        state.nearbyBoardPresented(true, policy: MotionPolicy(reduceMotion: true))

        #expect(!core.hasSession, "the local session goes with the board it was on")
        #expect(engine.cancelledTickets.count == 1)
        #expect(engine.cancelAlls == 1)
        #expect(engine.teardowns == 1, "and the machine stops thinking about it")
        #expect(state.game == nil)
        #expect(state.page == .board, "the local page is still standing underneath")
        #expect(try core.activeGameExists(), "the local game is committed and untouched")

        // And when the nearby board comes down, the page underneath is a board
        // again.
        state.nearbyBoardPresented(false, policy: MotionPolicy(reduceMotion: true))

        #expect(core.hasSession, "which opens its game again")
        #expect(state.game != nil)
        #expect(engine.startedSearches == 2,
                "and asks again for the reply that game still owes")
    }

    @Test("回到对局 is no way off the home while a mode switch is in flight")
    func resumeIsRefusedWhileTheSwitchRuns() throws {
        let core = try TestCores.fresh()
        let (state, archive) = try parkedStateOverAGame(core)

        state.choose(Self.miniAI)
        state.resume(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home, "the confirmation is up and the page it is on stays")

        state.saveAndContinue()
        #expect(state.modeSwitch == .saving(Self.miniAI))
        state.resume(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home,
                "and an archive in flight is not something to walk away from")

        // Which is the whole reason for the guard: both of this flow's alerts
        // belong to the home, so a refusal that arrived over the board would
        // have no page to present the accepted retry on.
        archive.answerWithRefusal()
        #expect(state.modeSwitch == .failed(Self.miniAI))
        #expect(state.page == .home)

        // And once the flow is spent, 回到对局 is exactly what it always was.
        state.dismissArchiveFailure()
        state.resume(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .board)
        #expect(state.activeSummary != nil, "over the game that was never archived")
    }

    @Test("A filed game is not an active game, and the home does not offer it")
    func aFiledGameIsNotOffered() throws {
        let core = try TestCores.fresh()
        let state = PlayState(core: core)
        try core.create(.freePlay(game: .miniXiangqi))
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home)
        state.resume(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .board, "the card is the way into the game")
        try state.game?.replay(Self.mateLine)
        #expect(state.save(), "保存 files it")
        #expect(state.game != nil, "the board still stands at the result it reached")

        #expect(state.activeSummary == nil, "but the store's active game is gone")

        // Going back to the home lets it go, and a mode entry then opens its
        // pre-start page with no confirmation: there is nothing left to save.
        state.leaveTopPage()
        #expect(state.page == .home)
        #expect(state.game == nil)
        state.choose(Self.miniFreePlay)
        #expect(state.modeSwitch == nil)
        #expect(state.page == .setup(Self.miniFreePlay))
        #expect(try core.historyCount() == 1, "and the game it filed is filed once")
    }

    // MARK: - The one active game, when it is a nearby one

    @Test("The card leads back into a nearby game on its own board, not this one")
    func aNearbyActiveGameIsResumedByItsOwnBoard() throws {
        let core = try TestCores.fresh()
        let state = try nearbyStateOverAGame(core)
        let asked = Asked()
        state.resumeNearby = { game in asked.record(game) }

        state.resume(policy: MotionPolicy(reduceMotion: true))
        #expect(asked.games == [.miniXiangqi])
        #expect(state.page == .home, "the local board is not where a nearby game is played")
        #expect(state.game == nil)
        #expect(!core.hasSession, "and no session was opened over it")
    }

    @Test("A nearby active game is never opened on the local board")
    func theLocalBoardRefusesANearbyGame() throws {
        let core = try TestCores.fresh()
        let state = try nearbyStateOverAGame(core)

        // The board coming back with its container, which is the one path that
        // enters it without going through the card.
        state.resume(policy: MotionPolicy(reduceMotion: true))
        state.enterBoard(policy: MotionPolicy(reduceMotion: true))

        #expect(state.game == nil)
        #expect(state.page == .home)
        #expect(!core.hasSession)
        #expect(state.activeSummary?.mode == .nearby, "and the game is still there")
    }

    @Test("Making room for a nearby game is the accepted confirmation")
    func makingRoomIsTheAcceptedFlow() throws {
        let core = try TestCores.fresh()
        let (state, archive) = try parkedStateOverAGame(core)
        let opened = Asked()

        state.makeRoom(for: .xiangqi) { opened.record(.xiangqi) }
        #expect(state.modeSwitch == .confirming(PlaySelection(game: .xiangqi, mode: .nearby)))
        #expect(opened.games.isEmpty, "nothing opens until the game is filed")

        state.saveAndContinue()
        archive.answer(.success(1))
        #expect(opened.games == [.xiangqi])
        #expect(state.page == .home, "and no pre-start page opened over it")
        #expect(state.modeSwitch == nil)
    }

    @Test("Cancelling the confirmation makes no room and opens nothing")
    func cancellingMakesNoRoom() throws {
        let core = try TestCores.fresh()
        let state = try stateOverAGame(core)
        let opened = Asked()

        state.makeRoom(for: .xiangqi) { opened.record(.xiangqi) }
        state.dismissConfirmation()
        #expect(state.modeSwitch == nil)
        #expect(opened.games.isEmpty)
        #expect(state.activeSummary != nil, "and the game is exactly as it stood")
    }

    @Test("A cancelled save failure leaves no act to hijack the next switch")
    func aCancelledSaveFailureTakesThePendingActWithIt() throws {
        let core = try TestCores.fresh()
        let (state, archive) = try parkedStateOverAGame(core)
        let opened = Asked()

        // Room asked for, the archive refused, and the accepted retry cancelled.
        state.makeRoom(for: .miniXiangqi) { opened.record(.miniXiangqi) }
        state.saveAndContinue()
        archive.answerWithRefusal()
        #expect(state.modeSwitch == .failed(PlaySelection(game: .miniXiangqi,
                                                          mode: .nearby)))
        state.dismissArchiveFailure()
        #expect(state.modeSwitch == nil)

        // A different mode chosen afterwards opens *its* page, not the surface
        // the abandoned flow was going to.
        state.choose(Self.xiangqiAI)
        state.saveAndContinue()
        archive.answer(.success(1))
        #expect(opened.games.isEmpty, "the abandoned act did not come back")
        #expect(state.page == .setup(Self.xiangqiAI),
                "and the page the player asked for opened")
    }

    @Test("With nothing in the library, the room is already made")
    func anEmptyLibraryNeedsNoRoomMaking() throws {
        let core = try TestCores.fresh()
        let state = PlayState(core: core)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        let opened = Asked()

        state.makeRoom(for: .miniXiangqi) { opened.record(.miniXiangqi) }
        #expect(opened.games == [.miniXiangqi])
        #expect(state.modeSwitch == nil)
    }

    // MARK: -

    /// A state holding an active *nearby* game, sitting on the home. The game is
    /// created the way the nearby layer creates one, because what these cases
    /// are about is what the home does with a game of that mode.
    private func nearbyStateOverAGame(_ core: Core) throws -> PlayState {
        try core.createNearby(.nearby(game: .miniXiangqi, localSide: .red),
                              wire: NearbyWireSession(sessionID: "S", peerID: "P",
                                                      proposedLocally: true))
        core.endSession()
        let state = PlayState(core: core)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.activeSummary?.mode == .nearby)
        return state
    }

    /// A state holding an active Free Play game, sitting on the home — which is
    /// what every launch over a stored game has.
    private func stateOverAGame(_ core: Core) throws -> PlayState {
        let state = PlayState(core: core)
        try core.create(.freePlay(game: .miniXiangqi))
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home)
        return state
    }

    /// The same, with the archive held open so the test decides when — and
    /// whether — it commits.
    private func parkedStateOverAGame(_ core: Core) throws -> (PlayState, ParkedArchive) {
        let archive = ParkedArchive(core)
        let state = PlayState(core: core, rules: archive)
        try core.create(.freePlay(game: .miniXiangqi))
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home)
        return (state, archive)
    }
}

// MARK: - The archive the core really performs

/// Where the answer lands. The seam's completion crosses a queue to reach this
/// actor, so it is a sendable closure, and a sendable closure has no business
/// writing into a test's local variable — this is the box it writes into.
@MainActor
final class ArchiveAnswer {
    private(set) var result: Result<UInt64, CoreError>?

    var arrived: Bool { result != nil }

    func record(_ result: Result<UInt64, CoreError>) { self.result = result }

    /// Lets this actor run until the answer lands. Bounded, so a hop that was
    /// never made fails the test instead of hanging the run.
    func arrive(within timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while result == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

/// Asks `core` for the archive, shuts it down, and then lets the answer arrive.
///
/// The order is the suite's own rule rather than tidiness. The answer is a
/// main-actor turn away and only a suspension gives the actor that turn, so
/// something has to be awaited; and a suspension with a live core in hand is
/// what this suite is arranged never to do — it lets the next test in, and the
/// next test's first act is to open a core the singleton refuses while this one
/// lives. Shutting down first also proves what `Core.shutdown` is for: its
/// barrier drains the archive queue, so the transaction is finished by the time
/// `retire` returns and only the answer is still owed.
@MainActor
private func archive(on core: Core, keeping directory: URL) async -> ArchiveAnswer {
    let answer = ArchiveAnswer()
    core.archiveActiveAndClear { answer.record($0) }
    #expect(!answer.arrived,
            "no answer inside the call that asked for it: the store call is off this actor")
    #expect(!core.hasSession, "and the session goes with the call")
    TestCores.retire(keeping: directory)
    await answer.arrive()
    return answer
}

/// `Core.archiveActiveAndClear` itself: the transaction off this actor, the
/// session detached with the call and put back when the core refuses it, and
/// the answer arriving on a later turn either way.
///
/// The suite above holds that seam open to prove what the screen does with each
/// answer. This one lets go of it, because the detach and the restore are the
/// core's own and nothing else in the app performs them. Serialized because
/// these are the only tests here that suspend, and two of them suspending at
/// once would be two tests reaching for the one core between them.
@Suite("The archive the core performs", .serialized, .retiringItsCores)
@MainActor
struct CoreArchiveTests {

    /// Two ordinary plies, so the record has a line in it.
    private static let openingLine = ["b1b3", "b7b6"]

    /// The shortest checkmate from the start position.
    private static let mateLine = ["b1b3", "b7b6", "b3d3"]

    @Test("It commits off this actor, files the game, and leaves the core no session")
    func theArchiveCommitsAndClears() async throws {
        let directory = TestCores.scratchDirectory()
        let core = try TestCores.open(at: directory)
        try core.create(.freePlay(game: .miniXiangqi))
        let game = try Game(rules: core)
        try game.replay(Self.openingLine)
        #expect(core.hasSession)

        let answer = await archive(on: core, keeping: directory)

        switch try #require(answer.result) {
        case .success(let recordID):
            #expect(recordID != 0, "the record the transaction wrote")
        case .failure(let error):
            Issue.record("the archive was refused: \(error)")
        }
        #expect(!core.hasSession, "a committed archive leaves no session behind")
        #expect(throws: CoreError.self) { try core.attachedSession() }

        // The store as the next core to open it finds it, which is what
        // quitting and relaunching is.
        let reopened = try TestCores.open(at: directory)
        #expect(try reopened.historyCount() == 1, "the transaction committed the record")
        #expect(try !reopened.activeGameExists(),
                "and cleared the active-game reference in the same one")
        TestCores.retire()
    }

    /// The refusal path, driven through the core rather than around it.
    ///
    /// The refusal a test can ask a working store for is the archived session:
    /// a game filed by its own terminal commit is an immutable History record,
    /// and the core answers `MXQ_ERR_STATE_SESSION_ARCHIVED` to anything that
    /// would archive it again. A store that will not write is not something a
    /// test can arrange — which is why what this proves is the branch rather
    /// than the disk: the session the call detached is put back, nothing is
    /// filed twice, and the next archive commits as any other would.
    @Test("A refused archive puts the session back and commits nothing")
    func aRefusedArchiveRestoresTheSession() async throws {
        let directory = TestCores.scratchDirectory()
        let core = try TestCores.open(at: directory)
        try core.create(.freePlay(game: .miniXiangqi))
        let game = try Game(rules: core)
        try game.replay(Self.mateLine)
        try game.file()
        #expect(try core.historyCount() == 1)
        #expect(core.hasSession, "the filed game's session still stands, as the board does")

        let answer = await archive(on: core, keeping: directory)

        switch try #require(answer.result) {
        case .success:
            Issue.record("a game already filed is not archivable a second time")
        case .failure(let error):
            #expect(error.status == MxqStatus(MXQ_ERR_STATE_SESSION_ARCHIVED),
                    "the core's own refusal rather than one composed above it — \(error)")
        }
        #expect(core.hasSession, "and the session the call took is put back")
        #expect(throws: Never.self) { try core.attachedSession() }

        // Nothing was filed a second time, and the next archive commits — which
        // is what makes the accepted 重试 worth offering.
        let reopened = try TestCores.open(at: directory)
        #expect(try reopened.historyCount() == 1)
        try reopened.create(.freePlay(game: .miniXiangqi))
        let next = try Game(rules: reopened)
        try next.replay(Self.openingLine)

        let retry = await archive(on: reopened, keeping: directory)
        #expect(retry.result?.isSuccess == true, "the archive after a refusal commits")

        let last = try TestCores.open(at: directory)
        #expect(try last.historyCount() == 2, "and the retry's record is in History")
        #expect(try !last.activeGameExists())
        TestCores.retire()
    }

    @Test("With nothing to archive it refuses, and that answer is asynchronous too")
    func theEmptyRefusalIsAsynchronousToo() async throws {
        let directory = TestCores.scratchDirectory()
        let core = try TestCores.open(at: directory)
        #expect(!core.hasSession, "no game, so nothing is attached")

        // The guard is the one path that could have answered inside the call,
        // and a caller handling one answer synchronously and the other from a
        // queue would be handling two different calls.
        let answer = await archive(on: core, keeping: directory)

        switch try #require(answer.result) {
        case .success:
            Issue.record("there was no active game to archive")
        case .failure(let error):
            #expect(error.status == MxqStatus(MXQ_ERR_STATE_ACTIVE_GAME_MISSING))
        }

        let reopened = try TestCores.open(at: directory)
        #expect(try reopened.historyCount() == 0, "and it filed nothing on the way")
        #expect(try !reopened.activeGameExists())
        TestCores.retire()
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { true } else { false }
    }
}

/// What a callback was asked for. A box rather than a local, because the
/// callbacks these cases set are escaping and a local would be captured by
/// value.
@MainActor
final class Asked {
    private(set) var games: [GameKind] = []

    func record(_ game: GameKind) { games.append(game) }
}
