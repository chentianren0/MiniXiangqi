import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@Suite("The pre-start state", .retiringItsCores)
@MainActor
struct SetupTests {
    private static let miniAI = PlaySelection(game: .miniXiangqi,
                                              mode: .humanVersusAI)
    private static let miniFreePlay = PlaySelection(game: .miniXiangqi,
                                                    mode: .freePlay)

    private func makeState(engine: TestEngine = TestEngine()) throws -> (PlayState, GameLibrary, TestEngine) {
        let library = try TestLibraries.fresh()
        let state = PlayState(library: library, engine: engine)
        return (state, library, engine)
    }

    @Test("随机 previews Red and resolves only when it is drawn")
    func randomPreviewsRed() {
        #expect(!SetupDraft(firstMover: .random, level: .fast).previewsHumanAsBlack,
                "随机 remains unresolved and previews Red at the bottom")
        #expect(!SetupDraft(firstMover: .humanFirst, level: .fast).previewsHumanAsBlack)
        #expect(SetupDraft(firstMover: .aiFirst, level: .fast).previewsHumanAsBlack,
                "AI 先手 previews Black at the bottom")

        #expect(SetupDraft(firstMover: .humanFirst, level: .fast).resolveHumanSide() == .red)
        #expect(SetupDraft(firstMover: .aiFirst, level: .fast).resolveHumanSide() == .black)
        let draws = (0..<200).map { _ in
            SetupDraft(firstMover: .random, level: .fast).resolveHumanSide()
        }
        #expect(draws.contains(.red) && draws.contains(.black),
                "随机 draws a side rather than always answering the same one")
    }

    @Test("开始对局 prepares, resolves, creates, and then searches")
    func theOrderingRunsInOrder() throws {
        let (state, library, engine) = try makeState()
        state.choose(Self.miniAI)
        state.draft = SetupDraft(firstMover: .aiFirst, level: .deep)
        #expect(state.page == .setup(Self.miniAI))

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.preparations == 1, "preparation came first")
        #expect(engine.probes == 1, "from a fresh probe")
        #expect(engine.lastPreparedGame == .miniXiangqi)
        #expect(state.page == .board, "and the game exists")
        let game = try #require(state.game)
        #expect(game.kind == .miniXiangqi)
        #expect(game.configuration.humanSide == .black, "AI 先手 resolved the human as Black")
        #expect(game.configuration.aiLevel == .deep)
        #expect(game.configuration.movetimeMilliseconds == 5000, "the level's thinking time")
        #expect(game.flipped, "the human's own side is at the bottom")
        #expect(try library.activeGameExists())
        #expect(engine.startedSearches == 1, "the resolved first mover is the AI, so it searches")
        #expect(engine.lastMovetime == 5000)
    }

    @Test("A preparation that fails creates nothing and resolves nothing")
    func aFailedPreparationCreatesNothing() throws {
        let engine = TestEngine()
        engine.preparationRefusal = CoreError(status: MxqStatus(MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY),
                                              detail: "not enough")
        let (state, library, _) = try makeState(engine: engine)
        state.choose(Self.miniAI)

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(state.creationFailure == .aiUnavailable,
                "the accepted notice, for the situation the user can act on")
        #expect(state.page == .setup(Self.miniAI), "the page and the draft stay")
        #expect(!state.creating, "and 开始对局 is on offer again")
        #expect(state.game == nil)
        #expect(try !library.activeGameExists(), "nothing was created")
        #expect(engine.startedSearches == 0)

        state.draft = SetupDraft(firstMover: .aiFirst, level: .deep)
        state.dismissCreationFailure()
        #expect(state.creationFailure == nil)
        #expect(state.draft == SetupDraft(firstMover: .aiFirst, level: .deep))

        engine.preparationRefusal = nil
        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(engine.probes == 2, "the retry took a fresh probe")
        #expect(state.page == .board)
    }

    @Test("开始对局 cannot be invoked again while creation is in progress")
    func creationIsSingleFlight() throws {
        let engine = TestEngine()
        engine.holdsPreparation = true
        let (state, _, _) = try makeState(engine: engine)
        state.choose(Self.miniAI)

        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(state.creating, "the attempt is in flight")
        state.startGame(policy: MotionPolicy(reduceMotion: true))
        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(engine.preparations == 1, "a second press does nothing at all")

        engine.holdsPreparation = false
        engine.releasePreparation()
        #expect(state.page == .board)
        #expect(!state.creating)
    }

    @Test("Leaving invalidates the attempt: no game, and a late completion commits nothing")
    func leavingInvalidatesTheAttempt() throws {
        let engine = TestEngine()
        engine.holdsPreparation = true
        let (state, library, _) = try makeState(engine: engine)
        state.choose(Self.miniAI)
        state.draft = SetupDraft(firstMover: .aiFirst, level: .deep)

        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(state.creating)

        state.leavePage()
        #expect(state.page == .home, "the page is left and the draft discarded")

        engine.holdsPreparation = false
        engine.releasePreparation()

        #expect(state.game == nil, "a late completion creates no game")
        #expect(state.page == .home)
        #expect(try !library.activeGameExists())
        #expect(engine.teardowns == 1, "and anything prepared for it is released")

        state.choose(Self.miniAI)
        #expect(state.draft == SetupDraft.fromDefaults())
    }

    @Test("A persistence failure releases the prepared engine and creates nothing")
    func aFailedCreateReleasesTheEngine() throws {
        let engine = TestEngine()
        let library = try TestLibraries.fresh()
        try library.create(.freePlay(game: .miniXiangqi))
        library.endSession()
        let state = PlayState(library: library, engine: engine)
        state.choose(Self.miniAI)

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.preparations == 1, "preparation succeeded")
        if case .notSaved = state.creationFailure {} else {
            Issue.record("a refused create is the not-saved failure, not the AI one")
        }
        #expect(state.game == nil, "and no game exists")
        #expect(state.page == .setup(Self.miniAI))
        #expect(engine.teardowns == 1, "the engine prepared for it is released")
    }

    @Test("Free Play creates without an engine at all")
    func freePlayPreparesNothing() throws {
        let (state, library, engine) = try makeState()
        state.choose(Self.miniFreePlay)
        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.preparations == 0, "Free Play has no opponent to prepare")
        #expect(state.page == .board)
        #expect(state.game?.kind == .miniXiangqi)
        #expect(state.game?.mode == .freePlay)
        #expect(state.game?.humanSide == nil)
        #expect(try library.activeGameExists())
    }

    @Test("Free Play creation carries Xiangqi through to the record")
    func xiangqiFreePlayCarriesTheSelection() throws {
        let (state, library, engine) = try makeState()
        let selection = PlaySelection(game: .xiangqi, mode: .freePlay)
        state.choose(selection)

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.preparations == 0)
        #expect(state.game?.kind == .xiangqi)
        #expect(try library.configuration().game == .xiangqi,
                "the selected game, not a hidden Mini default, reaches creation")
    }

    @Test("Xiangqi setup preparation carries the selected game")
    func xiangqiPreparationCarriesTheSelection() throws {
        let engine = TestEngine()
        engine.preparationRefusal = CoreError(status: MxqStatus(MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY),
                                              detail: "not enough")
        let (state, library, _) = try makeState(engine: engine)
        let selection = PlaySelection(game: .xiangqi, mode: .humanVersusAI)
        state.choose(selection)

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.lastPreparedGame == .xiangqi)
        #expect(state.page == .setup(selection))
        #expect(state.game == nil)
        #expect(try !library.activeGameExists())
    }

    @Test("Every played game's readiness profile reaches Swift, and each is its own")
    func everyGamesProfileIsItsOwn() throws {
        let core = try TestCores.fresh()
        let query = try core.engineQuery()
        let played = GameKind.allCases.filter { Core.isPlayedByAnEngine($0) }
        let profiles = try played.map { try core.engineProfileID(for: $0) }

        #expect(query.state == .uninitialized)
        #expect(profiles.allSatisfy { !$0.isEmpty })
        #expect(Set(profiles).count == profiles.count,
                "no two games may collapse to one readiness profile")
        #expect(query.profileID == profiles[played.firstIndex(of: .miniXiangqi)!],
                "the core's initial rules posture is Mini Xiangqi")
        #expect(!core.engineIsReady(for: .miniXiangqi),
                "a matching profile is still not ready before preparation")

        #expect(played == [.miniXiangqi, .xiangqi, .gomoku15, .renju],
                "Jieqi is the one game no engine here plays")
        #expect(throws: CoreError.self) { try core.engineProfileID(for: .jieqi) }
        #expect(!core.engineIsReady(for: .jieqi))
    }
}
