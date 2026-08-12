// The state before there is a game: the draft, the ordering that creates one,
// and the memory budget the ordering's first gate is computed from.
//
// docs/engine-integration.md, "Preparation ordering": prepare, resolve,
// create, search, each a gate on the next. Every failure point of that sequence
// is a state the app has to survive and a working engine will not produce on
// request, so the engine here is the same seam the opponent's tests use.

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

    private func makeState(engine: TestEngine = TestEngine()) throws -> (PlayState, Core, TestEngine) {
        let core = try TestCores.fresh()
        let state = PlayState(core: core, engine: engine)
        return (state, core, engine)
    }

    // MARK: - The draft

    @Test("The draft opens from the persistent defaults and writes nothing back")
    func theDraftReadsTheDefaults() throws {
        let defaults = try ScratchDefaults.make()
        #expect(Preferences.defaultFirstMover(in: defaults) == .humanFirst,
                "a new installation selects 我先手")
        #expect(Preferences.defaultAiLevel(in: defaults) == .standard, "and 标准")

        Preferences.defaultFirstMover.set("random", in: defaults)
        Preferences.defaultAiLevel.set("deep", in: defaults)
        #expect(Preferences.defaultFirstMover(in: defaults) == .random)
        #expect(Preferences.defaultAiLevel(in: defaults) == .deep)

        // A stored name nothing recognises is the accepted default rather than
        // a failure: a preference file is editable by hand and read by more
        // than one frontend.
        defaults.set("sideways", forKey: "defaults.firstMover")
        defaults.set(17, forKey: "defaults.aiLevel")
        #expect(Preferences.defaultFirstMover(in: defaults) == .humanFirst)
        #expect(Preferences.defaultAiLevel(in: defaults) == .standard)
        ScratchDefaults.clear()
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
        // A drawn side is one of the two, and over enough draws it is both.
        let draws = (0..<200).map { _ in
            SetupDraft(firstMover: .random, level: .fast).resolveHumanSide()
        }
        #expect(draws.contains(.red) && draws.contains(.black),
                "随机 draws a side rather than always answering the same one")
    }

    // MARK: - The ordering

    @Test("开始对局 prepares, resolves, creates, and then searches")
    func theOrderingRunsInOrder() throws {
        let (state, core, engine) = try makeState()
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
        #expect(game.configuration.movetimeMilliseconds == 5000, "frozen with the game")
        #expect(game.flipped, "the human's own side is at the bottom")
        #expect(try core.activeGameExists())
        #expect(engine.startedSearches == 1, "the resolved first mover is the AI, so it searches")
        #expect(engine.lastMovetime == 5000)
    }

    @Test("A preparation that fails creates nothing and resolves nothing")
    func aFailedPreparationCreatesNothing() throws {
        let engine = TestEngine()
        engine.preparationRefusal = CoreError(status: MxqStatus(MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY),
                                              detail: "not enough")
        let (state, core, _) = try makeState(engine: engine)
        state.choose(Self.miniAI)

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(state.creationFailure == .aiUnavailable,
                "the accepted notice, for the situation the user can act on")
        #expect(state.page == .setup(Self.miniAI), "the page and the draft stay")
        #expect(!state.creating, "and 开始对局 is on offer again")
        #expect(state.game == nil)
        #expect(try !core.activeGameExists(), "nothing was created")
        #expect(engine.startedSearches == 0)

        // 取消 dismisses without leaving; the draft is untouched.
        state.draft = SetupDraft(firstMover: .aiFirst, level: .deep)
        state.dismissCreationFailure()
        #expect(state.creationFailure == nil)
        #expect(state.draft == SetupDraft(firstMover: .aiFirst, level: .deep))

        // Every retry re-probes.
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
        let (state, core, _) = try makeState(engine: engine)
        state.choose(Self.miniAI)
        state.draft = SetupDraft(firstMover: .aiFirst, level: .deep)

        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(state.creating)

        state.leavePage()
        #expect(state.page == .home, "the page is left and the draft discarded")

        // The preparation completes afterwards. It must create nothing, and
        // what it prepared must be released.
        engine.holdsPreparation = false
        engine.releasePreparation()

        #expect(state.game == nil, "a late completion creates no game")
        #expect(state.page == .home)
        #expect(try !core.activeGameExists())
        #expect(engine.teardowns == 1, "and anything prepared for it is released")

        // The draft is taken afresh on the next entry rather than remembered.
        state.choose(Self.miniAI)
        #expect(state.draft == SetupDraft.fromDefaults())
    }

    @Test("A persistence failure releases the prepared engine and creates nothing")
    func aFailedCreateReleasesTheEngine() throws {
        let engine = TestEngine()
        let core = try TestCores.fresh()
        // A game already active is what makes `mxq_game_create` refuse, which is
        // the store-domain refusal this path has to survive.
        try core.create(.freePlay(game: .miniXiangqi))
        core.endSession()
        let state = PlayState(core: core, engine: engine)
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
        let (state, core, engine) = try makeState()
        state.choose(Self.miniFreePlay)
        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.preparations == 0, "Free Play has no opponent to prepare")
        #expect(state.page == .board)
        #expect(state.game?.kind == .miniXiangqi)
        #expect(state.game?.mode == .freePlay)
        #expect(state.game?.humanSide == nil)
        #expect(try core.activeGameExists())
    }

    @Test("Free Play creation carries Xiangqi through to the core session")
    func xiangqiFreePlayCarriesTheSelection() throws {
        let (state, core, engine) = try makeState()
        let selection = PlaySelection(game: .xiangqi, mode: .freePlay)
        state.choose(selection)

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.preparations == 0)
        #expect(state.game?.kind == .xiangqi)
        #expect(try core.configuration().game == .xiangqi,
                "the selected game, not a hidden Mini default, reaches creation")
    }

    @Test("Xiangqi setup preparation carries the selected game")
    func xiangqiPreparationCarriesTheSelection() throws {
        let engine = TestEngine()
        engine.preparationRefusal = CoreError(status: MxqStatus(MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY),
                                              detail: "not enough")
        let (state, core, _) = try makeState(engine: engine)
        let selection = PlaySelection(game: .xiangqi, mode: .humanVersusAI)
        state.choose(selection)

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.lastPreparedGame == .xiangqi)
        #expect(state.page == .setup(selection))
        #expect(state.game == nil)
        #expect(try !core.activeGameExists())
    }

    /// Readiness is a comparison of two strings the core states, and this is the
    /// frontend's side of it: that the identifier reaches Swift for **every**
    /// game, that no two games collapse to one, and that a profile match alone
    /// is not readiness.
    ///
    /// The placement games are what this would catch. Nothing above the C
    /// interface can compose their identifiers — a profile names the revision of
    /// the engine its own game is played on, and `MxqVersion` reports only the
    /// first engine's — so a frontend that went back to assembling one would
    /// answer here with two games sharing a string, which is the readiness check
    /// silently passing for a board the engine is not prepared for.
    @Test("Every game's readiness profile reaches Swift, and each is its own")
    func everyGamesProfileIsItsOwn() throws {
        let core = try TestCores.fresh()
        let query = try core.engineQuery()
        let profiles = try GameKind.allCases.map { try core.engineProfileID(for: $0) }

        #expect(query.state == .uninitialized)
        #expect(profiles.allSatisfy { !$0.isEmpty })
        #expect(Set(profiles).count == profiles.count,
                "no two games may collapse to one readiness profile")
        #expect(query.profileID == profiles[GameKind.allCases.firstIndex(of: .miniXiangqi)!],
                "the core's initial rules posture is Mini Xiangqi")
        #expect(!core.engineIsReady(for: .miniXiangqi),
                "a matching profile is still not ready before preparation")
    }

    // MARK: - The budget the first gate is computed from

    @Test("The probe's values reach the accepted arithmetic, at every boundary")
    func theBudgetPlumbingIsTheAcceptedArithmetic() throws {
        let mib: UInt64 = 1 << 20

        // A zero probe reports insufficient and initialises nothing.
        let empty = try Core.plan(for: EngineBudget(activeProcessorCount: 4,
                                                    availableBytes: 0,
                                                    physicalBytes: 16 << 30))
        #expect(!empty.sufficient)
        #expect(empty.hashMiB == 0)

        // The reserve is the greater of 20% and 128 MiB, so a small probe is
        // bounded by the fixed floor rather than by the percentage.
        let small = try Core.plan(for: EngineBudget(activeProcessorCount: 4,
                                                    availableBytes: 512 * mib,
                                                    physicalBytes: 16 << 30))
        #expect(small.reserveBytes == 128 * mib, "128 MiB beats 20% of 512")
        #expect(small.usableBytes == 384 * mib)
        #expect(small.hashMiB == 384, "already a multiple of 64")
        #expect(small.sufficient)

        // Just under the minimum: 448 MiB available leaves 320 usable, and a
        // probe below that lands under 256.
        let below = try Core.plan(for: EngineBudget(activeProcessorCount: 4,
                                                    availableBytes: 380 * mib,
                                                    physicalBytes: 16 << 30))
        #expect(below.hashMiB == 192, "252 MiB rounds down to 192")
        #expect(!below.sufficient, "and below 256 the engine is not initialised")

        // Exactly the minimum.
        let exact = try Core.plan(for: EngineBudget(activeProcessorCount: 4,
                                                    availableBytes: 384 * mib,
                                                    physicalBytes: 16 << 30))
        #expect(exact.hashMiB == 256)
        #expect(exact.sufficient)

        // Half of physical is a bound of its own.
        let physicalBound = try Core.plan(for: EngineBudget(activeProcessorCount: 4,
                                                            availableBytes: 8 << 30,
                                                            physicalBytes: 2 << 30))
        #expect(physicalBound.hashMiB == 1024, "50% of 2 GiB")

        // And 4 GiB is the cap, whatever the machine offers.
        let huge = try Core.plan(for: EngineBudget(activeProcessorCount: 16,
                                                   availableBytes: 200 << 30,
                                                   physicalBytes: 512 << 30))
        #expect(huge.hashMiB == 4096, "the accepted cap")
        #expect(huge.threads == 16, "Threads is the processor count the frontend reported")
    }

    /// docs/engine-integration.md names a different probe per platform —
    /// `host_statistics64` on macOS, `os_proc_available_memory()` on iOS and
    /// iPadOS — and docs/testing.md asks for each to be verified on its own
    /// platform. This is one test rather than two because what has to hold of
    /// the answer is the same either way, and because the bundle now runs on
    /// both: whichever probe the platform compiled in is the one this exercises.
    ///
    /// What it cannot do is stand in for the on-device re-measurement the phase
    /// still owes. A Simulator's process limit is the host Mac's memory, not a
    /// phone's, so this says the probe answers plausibly rather than that it
    /// answers the right number on an 8 GB device.
    @Test("The platform's own probe reports two plausible numbers")
    func theProbeAnswers() {
        let budget = EngineBudget.probe()
        #expect(budget.physicalBytes > 0, "the machine has memory")
        #expect(budget.activeProcessorCount > 0)
        #expect(budget.availableBytes <= budget.physicalBytes,
                "available memory cannot exceed the memory that exists")
    }
}
