import Foundation
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
    private func stateOverAGame(_ library: GameLibrary) throws -> (PlayState, HeldArchive) {
        let state = PlayState(library: library)
        let archive = HeldArchive(holding: state)
        try library.create(.freePlay(game: .miniXiangqi))
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .home)
        return (state, archive)
    }

    @Test("With no game a mode entry opens its pre-start page")
    func aModeEntryWithNoGameOpensTheSetup() throws {
        let state = PlayState(library: try TestLibraries.fresh())
        state.choose(Self.miniFreePlay)
        #expect(state.page == .setup(Self.miniFreePlay))
        #expect(state.modeSwitch == nil)
    }

    @Test("With a game a mode entry confirms instead of navigating")
    func aModeEntryWithAGameConfirms() throws {
        let library = try TestLibraries.fresh()
        let (state, archive) = try stateOverAGame(library)

        state.choose(Self.miniAI)
        #expect(state.modeSwitch == .confirming(Self.miniAI))
        #expect(state.page == .home)
        #expect(archive.requests == 0)

        state.dismissConfirmation()
        #expect(state.modeSwitch == nil)
        #expect(try library.activeGameExists())
        #expect(try library.historyCount() == 0, "cancelling files nothing")
    }

    @Test("保存并继续 archives before it navigates, and keeps the chosen game and mode")
    func saveAndContinueArchivesThenOpensTheSelection() throws {
        let (state, archive) = try stateOverAGame(try TestLibraries.fresh())

        state.choose(Self.xiangqiAI)
        state.saveAndContinue()
        #expect(archive.requests == 1)
        #expect(state.modeSwitch == .saving(Self.xiangqiAI))
        #expect(state.page == .home, "nothing opens until the archive commits")
        state.dismissConfirmation()
        #expect(state.modeSwitch == .saving(Self.xiangqiAI), "dismissing the alert keeps the archive")

        archive.answer(.success(UUID()))
        #expect(state.page == .setup(Self.xiangqiAI))
        #expect(state.modeSwitch == nil)
    }

    @Test("A refused archive keeps the game, and 重试 asks again")
    func aRefusedArchiveKeepsTheGame() throws {
        let library = try TestLibraries.fresh()
        let (state, archive) = try stateOverAGame(library)

        state.choose(Self.miniAI)
        state.saveAndContinue()
        archive.answer(.failure(CoreError(wrapping: LibraryRefusal.unavailable)))
        #expect(state.modeSwitch == .failed(Self.miniAI))
        #expect(state.page == .home)
        #expect(try library.activeGameExists())

        state.saveAndContinue()
        #expect(archive.requests == 2)
        archive.answer(.success(UUID()))
        #expect(state.page == .setup(Self.miniAI))
    }

    @Test("An archive still in flight is asked for once, however often it is pressed")
    func anArchiveInFlightIsNotStartedTwice() throws {
        let (state, archive) = try stateOverAGame(try TestLibraries.fresh())
        state.choose(Self.miniFreePlay)
        state.saveAndContinue()
        state.saveAndContinue()
        state.saveAndContinue()
        #expect(archive.requests == 1)
        archive.answer(.success(UUID()))
        #expect(state.page == .setup(Self.miniFreePlay))
    }

    @Test("The real archive files the game and leaves no game in play")
    func theRealArchiveFilesTheGame() async throws {
        let url = TestLibraries.scratchURL()
        let library = try TestLibraries.open(at: url)
        try library.create(.freePlay(game: .miniXiangqi))
        let game = try Game(library: library)
        try game.replay(["b1b3", "b7b6"])

        let answer = ArchiveAnswer()
        library.archiveActiveAndClear { answer.record($0) }
        await answer.arrive()
        let filed = try #require(try answer.result?.get())

        let reopened = try TestLibraries.open(at: url, core: library.core)
        #expect(try !reopened.activeGameExists())
        #expect(try reopened.historyCount() == 1)
        let record = try #require(try reopened.record(filed))
        #expect(record.result == Outcome.none)
        #expect(record.reason == EndReason.endedEarly, "an ordinary ongoing game is filed as ended early")
        #expect(record.moves == ["b1b3", "b7b6"])
    }

    @Test("A nearby active game is never opened on the local board")
    func theLocalBoardRefusesANearbyGame() throws {
        let library = try TestLibraries.fresh()
        try library.createNearby(.nearby(game: .miniXiangqi, localSide: .red),
                                 wire: NearbyWireSession(sessionID: "S", peerID: "P",
                                                         proposedLocally: true))
        library.endSession()
        let state = PlayState(library: library)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        var resumed: [GameKind] = []
        state.resumeNetworkedGame = { _, game in resumed.append(game) }

        state.resume(policy: MotionPolicy(reduceMotion: true))
        state.enterBoard(policy: MotionPolicy(reduceMotion: true))
        #expect(resumed == [.miniXiangqi], "the card hands it to its own board")
        #expect(state.game == nil)
        #expect(state.page == .home)
        #expect(!library.hasSession)
        #expect(state.activeSummary?.mode == .nearby)
    }
}

/// Where an archive's answer lands, a main-actor turn after it was asked for.
@MainActor
final class ArchiveAnswer {
    private(set) var result: Result<UUID, CoreError>?

    func record(_ result: Result<UUID, CoreError>) { self.result = result }

    func arrive(within timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while result == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
