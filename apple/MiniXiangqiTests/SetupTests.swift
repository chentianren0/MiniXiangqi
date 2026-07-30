// The state before there is a game: the draft, the ordering that creates one,
// and the memory budget the ordering's first gate is computed from.
//
// docs/engine-integration.md, "Accepted preparation ordering": prepare, resolve,
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
        state.choose(.humanVersusAI)
        state.draft = SetupDraft(firstMover: .aiFirst, level: .deep)
        #expect(state.phase == .setup(.humanVersusAI))

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.preparations == 1, "preparation came first")
        #expect(engine.probes == 1, "from a fresh probe")
        #expect(state.phase == .playing, "and the game exists")
        let game = try #require(state.game)
        #expect(game.configuration?.humanSide == .black, "AI 先手 resolved the human as Black")
        #expect(game.configuration?.aiLevel == .deep)
        #expect(game.configuration?.movetimeMilliseconds == 5000, "frozen with the game")
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
        state.choose(.humanVersusAI)

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(state.creationFailure == .aiUnavailable,
                "the accepted notice, for the situation the user can act on")
        #expect(state.phase == .setup(.humanVersusAI), "the page and the draft stay")
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
        #expect(state.phase == .playing)
    }

    @Test("开始对局 cannot be invoked again while creation is in progress")
    func creationIsSingleFlight() throws {
        let engine = TestEngine()
        engine.holdsPreparation = true
        let (state, _, _) = try makeState(engine: engine)
        state.choose(.humanVersusAI)

        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(state.creating, "the attempt is in flight")
        state.startGame(policy: MotionPolicy(reduceMotion: true))
        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(engine.preparations == 1, "a second press does nothing at all")

        engine.holdsPreparation = false
        engine.releasePreparation()
        #expect(state.phase == .playing)
        #expect(!state.creating)
    }

    @Test("Leaving invalidates the attempt: no game, and a late completion commits nothing")
    func leavingInvalidatesTheAttempt() throws {
        let engine = TestEngine()
        engine.holdsPreparation = true
        let (state, core, _) = try makeState(engine: engine)
        state.choose(.humanVersusAI)
        state.draft = SetupDraft(firstMover: .aiFirst, level: .deep)

        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(state.creating)

        state.leavePage()
        #expect(state.phase == .start, "the page is left and the draft discarded")

        // The preparation completes afterwards. It must create nothing, and
        // what it prepared must be released.
        engine.holdsPreparation = false
        engine.releasePreparation()

        #expect(state.game == nil, "a late completion creates no game")
        #expect(state.phase == .start)
        #expect(try !core.activeGameExists())
        #expect(engine.teardowns == 1, "and anything prepared for it is released")

        // The draft is taken afresh on the next entry rather than remembered.
        state.choose(.humanVersusAI)
        #expect(state.draft == SetupDraft.fromDefaults())
    }

    @Test("A persistence failure releases the prepared engine and creates nothing")
    func aFailedCreateReleasesTheEngine() throws {
        let engine = TestEngine()
        let core = try TestCores.fresh()
        // A game already active is what makes `mxq_game_create` refuse, which is
        // the store-domain refusal this path has to survive.
        try core.create(.freePlay)
        core.endSession()
        let state = PlayState(core: core, engine: engine)
        state.choose(.humanVersusAI)

        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.preparations == 1, "preparation succeeded")
        if case .notSaved = state.creationFailure {} else {
            Issue.record("a refused create is the not-saved failure, not the AI one")
        }
        #expect(state.game == nil, "and no game exists")
        #expect(state.phase == .setup(.humanVersusAI))
        #expect(engine.teardowns == 1, "the engine prepared for it is released")
    }

    @Test("Free Play creates without an engine at all")
    func freePlayPreparesNothing() throws {
        let (state, core, engine) = try makeState()
        state.choose(.freePlay)
        state.startGame(policy: MotionPolicy(reduceMotion: true))

        #expect(engine.preparations == 0, "Free Play has no opponent to prepare")
        #expect(state.phase == .playing)
        #expect(state.game?.mode == .freePlay)
        #expect(state.game?.humanSide == nil)
        #expect(try core.activeGameExists())
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

    @Test("The macOS probe reports two plausible numbers")
    func theProbeAnswers() {
        let budget = EngineBudget.probe()
        #expect(budget.physicalBytes > 0, "the machine has memory")
        #expect(budget.activeProcessorCount > 0)
        #expect(budget.availableBytes <= budget.physicalBytes,
                "available memory cannot exceed the memory that exists")
    }
}
