import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@Suite("The Play home", .retiringItsCores)
@MainActor
struct PlayHomeTests {

    private static let miniAI = PlaySelection(game: .miniXiangqi, mode: .humanVersusAI)
    private static let miniFreePlay = PlaySelection(game: .miniXiangqi, mode: .freePlay)
    private static let xiangqiAI = PlaySelection(game: .xiangqi, mode: .humanVersusAI)

    /// A state on the home over an active Free Play game, its archive held.
    private func stateOverAGame(_ core: Core) throws -> (PlayState, HeldArchive) {
        let state = PlayState(core: core)
        let archive = HeldArchive(holding: state)
        try core.create(.freePlay(game: .miniXiangqi))
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home)
        return (state, archive)
    }

    @Test("With no game a mode entry opens its pre-start page")
    func aModeEntryWithNoGameOpensTheSetup() throws {
        let state = PlayState(core: try TestCores.fresh())
        state.choose(Self.miniFreePlay)
        #expect(state.page == .setup(Self.miniFreePlay))
        #expect(state.modeSwitch == nil)
    }

    @Test("With a game a mode entry confirms instead of navigating")
    func aModeEntryWithAGameConfirms() throws {
        let core = try TestCores.fresh()
        let (state, archive) = try stateOverAGame(core)

        state.choose(Self.miniAI)
        #expect(state.modeSwitch == .confirming(Self.miniAI))
        #expect(state.page == .home)
        #expect(archive.requests == 0)

        state.dismissConfirmation()
        #expect(state.modeSwitch == nil)
        #expect(try core.activeGameExists())
        #expect(try core.historyCount() == 0, "cancelling files nothing")
    }

    @Test("保存并继续 archives before it navigates, and keeps the chosen game and mode")
    func saveAndContinueArchivesThenOpensTheSelection() throws {
        let (state, archive) = try stateOverAGame(try TestCores.fresh())

        state.choose(Self.xiangqiAI)
        state.saveAndContinue()
        #expect(archive.requests == 1)
        #expect(state.modeSwitch == .saving(Self.xiangqiAI))
        #expect(state.page == .home, "nothing opens until the archive commits")
        state.dismissConfirmation()
        #expect(state.modeSwitch == .saving(Self.xiangqiAI), "dismissing the alert keeps the archive")

        archive.answer(.success(1))
        #expect(state.page == .setup(Self.xiangqiAI))
        #expect(state.modeSwitch == nil)
    }

    @Test("A refused archive keeps the game, and 重试 asks again")
    func aRefusedArchiveKeepsTheGame() throws {
        let core = try TestCores.fresh()
        let (state, archive) = try stateOverAGame(core)

        state.choose(Self.miniAI)
        state.saveAndContinue()
        archive.answer(.failure(CoreError(status: MxqStatus(MXQ_ERR_STORE_IO), detail: "refused")))
        #expect(state.modeSwitch == .failed(Self.miniAI))
        #expect(state.page == .home)
        #expect(try core.activeGameExists())

        state.saveAndContinue()
        #expect(archive.requests == 2)
        archive.answer(.success(1))
        #expect(state.page == .setup(Self.miniAI))
    }

    @Test("An archive still in flight is asked for once, however often it is pressed")
    func anArchiveInFlightIsNotStartedTwice() throws {
        let (state, archive) = try stateOverAGame(try TestCores.fresh())
        state.choose(Self.miniFreePlay)
        state.saveAndContinue()
        state.saveAndContinue()
        state.saveAndContinue()
        #expect(archive.requests == 1)
        archive.answer(.success(1))
        #expect(state.page == .setup(Self.miniFreePlay))
    }

    @Test("The real archive files the game and leaves no active game")
    func theRealArchiveFilesTheGame() async throws {
        let directory = TestCores.scratchDirectory()
        let core = try TestCores.open(at: directory)
        try core.create(.freePlay(game: .miniXiangqi))
        let game = try Game(core: core)
        try game.replay(["b1b3", "b7b6"])

        let answer = ArchiveAnswer()
        core.archiveActiveAndClear { answer.record($0) }
        // Shut down before suspending, so no other test can take the core
        // slot while this one waits; the shutdown drains the archive queue.
        TestCores.retire(keeping: directory)
        await answer.arrive()
        #expect(try answer.result?.get() != nil)

        let reopened = try TestCores.open(at: directory)
        #expect(try !reopened.activeGameExists())
        #expect(try reopened.historyCount() == 1)
    }

    @Test("A nearby active game is never opened on the local board")
    func theLocalBoardRefusesANearbyGame() throws {
        let core = try TestCores.fresh()
        try core.createNearby(.nearby(game: .miniXiangqi, localSide: .red),
                              wire: NearbyWireSession(sessionID: "S", peerID: "P",
                                                      proposedLocally: true))
        core.endSession()
        let state = PlayState(core: core)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        var resumed: [GameKind] = []
        state.resumeNetworkedGame = { _, game in resumed.append(game) }

        state.resume(policy: MotionPolicy(reduceMotion: true))
        state.enterBoard(policy: MotionPolicy(reduceMotion: true))
        #expect(resumed == [.miniXiangqi], "the card hands it to its own board")
        #expect(state.game == nil)
        #expect(state.page == .home)
        #expect(!core.hasSession)
        #expect(state.activeSummary?.mode == .nearby)
    }
}

/// Where an archive's answer lands, a main-actor turn after it was asked for.
@MainActor
final class ArchiveAnswer {
    private(set) var result: Result<UInt64, CoreError>?

    func record(_ result: Result<UInt64, CoreError>) { self.result = result }

    func arrive(within timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while result == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
