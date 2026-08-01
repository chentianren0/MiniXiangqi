// The opponent, the pre-start state, and the budget the two of them stand on.
//
// The engine is a seam here for exactly the reason the rules are one: a working
// engine will not refuse a preparation on request, and the states the app has to
// survive — a preparation that fails, a search that comes back cancelled or
// stale, a result that arrives after the position has moved on — are precisely
// the ones it refuses to produce. Nothing in this file decides a rule or a
// budget; the games are real games on real cores, and the arithmetic is asked of
// `mxq_engine_plan`, which is pure and needs no engine at all.

import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

// MARK: - The seams

/// The engine as the opponent sees it, with every refusal on a switch.
@MainActor
final class TestEngine: AIEngine {
    var budget = EngineBudget(activeProcessorCount: 8,
                              availableBytes: 8 << 30,
                              physicalBytes: 16 << 30)
    /// What preparation does. Nil succeeds.
    var preparationRefusal: CoreError?
    /// Whether a preparation waits for the test to let it finish.
    var holdsPreparation = false
    /// What `startSearch` throws, if anything.
    var startRefusal: CoreError?

    private(set) var probes = 0
    private(set) var preparations = 0
    private(set) var teardowns = 0
    private(set) var cancelledTickets: [UInt64] = []
    private(set) var cancelAlls = 0
    private(set) var startedSearches = 0
    private(set) var lastMovetime: UInt32?
    private(set) var lastBudget: EngineBudget?
    private(set) var lastPreparedGame: GameKind?
    private(set) var preparedGame: GameKind?

    private var held: (game: GameKind, budget: EngineBudget,
                       completion: @MainActor (Result<EnginePlan, CoreError>) -> Void)?
    private var completion: (@MainActor (SearchResult) -> Void)?
    private var ticket: UInt64 = 0

    func memoryBudget() -> EngineBudget {
        probes += 1
        return budget
    }

    func engineIsReady(for game: GameKind) -> Bool { preparedGame == game }

    func prepareEngine(for game: GameKind, _ budget: EngineBudget,
                       completion: @escaping @MainActor (Result<EnginePlan, CoreError>) -> Void) {
        preparations += 1
        lastPreparedGame = game
        lastBudget = budget
        guard !holdsPreparation else {
            held = (game, budget, completion)
            return
        }
        answerPreparation(for: game, budget, completion)
    }

    /// Lets a held preparation finish.
    func releasePreparation() {
        let held = held
        self.held = nil
        if let held { answerPreparation(for: held.game, held.budget, held.completion) }
    }

    private func answerPreparation(for game: GameKind, _ budget: EngineBudget,
                                   _ completion: @MainActor (Result<EnginePlan, CoreError>) -> Void) {
        if let preparationRefusal {
            preparedGame = nil
            completion(.failure(preparationRefusal))
            return
        }
        preparedGame = game
        completion(.success((try? Core.plan(for: budget)) ?? Self.emptyPlan))
    }

    func markReady(for game: GameKind) { preparedGame = game }

    private static let emptyPlan = EnginePlan(MxqEnginePlan())

    func teardownEngine(then next: (@MainActor () -> Void)?) {
        teardowns += 1
        preparedGame = nil
        next?()
    }

    func startSearch(movetimeMilliseconds: UInt32,
                     completion: @escaping @MainActor (SearchResult) -> Void) throws -> UInt64 {
        if let startRefusal {
            self.startRefusal = nil
            preparedGame = nil
            throw startRefusal
        }
        startedSearches += 1
        lastMovetime = movetimeMilliseconds
        self.completion = completion
        ticket += 1
        return ticket
    }

    func cancelSearch(_ ticket: UInt64) { cancelledTickets.append(ticket) }
    func cancelAllSearches() { cancelAlls += 1 }

    /// Answers the outstanding search, exactly as the core's callback would
    /// once it has hopped to the main actor.
    func answer(_ result: SearchResult) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }

    var hasOutstandingSearch: Bool { completion != nil }
}

/// A clock the test moves by hand, so the reply floor and the indicator's
/// threshold are observed rather than slept through.
@MainActor
final class TestTimer {
    private(set) var now: TimeInterval = 1000
    private var pending: [(due: TimeInterval, body: @MainActor () -> Void)] = []

    /// Captured strongly on purpose: the value is handed to an opponent that
    /// outlives the local binding in tests that do not name the clock, and an
    /// unowned capture there is a dangling read rather than a test failure.
    var timer: MotionTimer {
        MotionTimer(now: { self.now },
                    after: { delay, body in
                        self.pending.append((self.now + delay, body))
                    })
    }

    /// Moves the clock and fires everything that came due, in order.
    func advance(by interval: TimeInterval) {
        now += interval
        while let index = pending.firstIndex(where: { $0.due <= now }) {
            let entry = pending.remove(at: index)
            entry.body()
        }
    }

    var pendingCount: Int { pending.count }
}

// MARK: - What a search's answer looks like

@MainActor
private func result(_ outcome: SearchOutcome, move: String, game: Game,
                    ticket: UInt64 = 1, revision: UInt64? = nil,
                    identity: String? = nil) -> SearchResult {
    var raw = MxqSearchResult()
    raw.struct_size = UInt32(MemoryLayout<MxqSearchResult>.size)
    raw.outcome = switch outcome {
    case .move: MxqSearchOutcome(MXQ_SEARCH_MOVE)
    case .cancelled: MxqSearchOutcome(MXQ_SEARCH_CANCELLED)
    case .stale: MxqSearchOutcome(MXQ_SEARCH_STALE)
    case .malformed: MxqSearchOutcome(MXQ_SEARCH_MALFORMED)
    case .illegal: MxqSearchOutcome(MXQ_SEARCH_ILLEGAL)
    case .failed: MxqSearchOutcome(MXQ_SEARCH_FAILED)
    }
    raw.ticket = ticket
    raw.position_revision = revision ?? game.evaluation.positionRevision
    withUnsafeMutableBytes(of: &raw.move.text) { buffer in
        for (index, byte) in move.utf8.enumerated() { buffer[index] = byte }
    }
    withUnsafeMutableBytes(of: &raw.game_id) { buffer in
        for (index, byte) in (identity ?? game.identity).utf8.enumerated() {
            buffer[index] = byte
        }
    }
    return SearchResult(raw)
}

// MARK: - The opponent

@Suite("The opponent", .retiringItsCores)
@MainActor
struct OpponentTests {

    /// A human-versus-AI game with the human on the given side, and the whole
    /// apparatus around it wired the way PlayState wires it.
    private func makeOpponent(humanSide: Side = .red, level: AiLevel = .fast)
        throws -> (Opponent, Game, PlayMotion, TestEngine, TestTimer, ManualAnimator) {
        let core = try TestCores.fresh()
        try core.create(.humanVersusAI(game: .miniXiangqi, humanSide: humanSide,
                                       level: level,
                                       choice: humanSide == .red ? .humanFirst : .aiFirst))
        let game = try Game(rules: core)
        let animator = ManualAnimator()
        let motion = PlayMotion(game: game, animator: animator.animator,
                                feedback: FeedbackRecorder(defaults: try ScratchDefaults.make()).feedback)
        let engine = TestEngine()
        let clock = TestTimer()
        let opponent = Opponent(engine: engine, game: game, motion: motion,
                                timer: clock.timer)
        motion.committed = { [weak opponent] in opponent?.gameChanged() }
        motion.landed = { [weak opponent] in opponent?.landed() }
        return (opponent, game, motion, engine, clock, animator)
    }

    // MARK: - Preparing when a search is owed

    @Test("A search is prepared and started exactly when the core says one is owed")
    func aSearchIsOwedOrItIsNot() throws {
        let (opponent, game, motion, engine, _, animator) = try makeOpponent()

        // The human is Red and moves first, so nothing is owed at the start.
        opponent.begin()
        #expect(engine.preparations == 0, "a game waiting on the player prepares nothing")
        #expect(engine.startedSearches == 0)

        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        #expect(game.searchExpected, "the premise: the AI now owes a move")
        #expect(engine.preparations == 1, "and a search that is owed prepares first")
        #expect(engine.probes == 1, "from a probe taken at the attempt")
        #expect(engine.lastPreparedGame == .miniXiangqi)
        #expect(engine.startedSearches == 1, "then searches")
        #expect(engine.lastMovetime == 1000, "at the level the game froze")
        animator.completeAll()
    }

    @Test("Readiness for another game does not satisfy the active game")
    func readinessIsGameSpecific() throws {
        let (opponent, _, _, engine, _, _) = try makeOpponent(humanSide: .black)
        engine.markReady(for: .xiangqi)

        opponent.begin()

        #expect(engine.preparations == 1)
        #expect(engine.lastPreparedGame == .miniXiangqi)
        #expect(engine.startedSearches == 1)
    }

    @Test("A synchronous readiness refusal prepares the active game and retries",
          arguments: [MxqStatus(MXQ_ERR_ENGINE_NOT_PREPARED),
                      MxqStatus(MXQ_ERR_STATE_ENGINE_NOT_READY)])
    func aReadinessRaceReprepares(_ status: MxqStatus) throws {
        let (opponent, _, _, engine, _, _) = try makeOpponent(humanSide: .black)
        engine.markReady(for: .miniXiangqi)
        engine.startRefusal = CoreError(status: status, detail: "readiness changed")

        opponent.begin()

        #expect(engine.preparations == 1)
        #expect(engine.lastPreparedGame == .miniXiangqi)
        #expect(engine.startedSearches == 1)
        #expect(engine.hasOutstandingSearch)
    }

    @Test("The board takes no input for as long as the AI owes a move")
    func inputIsRefusedWhileTheAIOwesAMove() throws {
        let (opponent, game, motion, engine, _, animator) = try makeOpponent()
        _ = opponent

        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        #expect(game.selected == Square("b1", on: GameKind.miniXiangqi.board), "the player's own turn takes input")
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()
        #expect(game.searchExpected, "the premise: the AI owes a move")

        // Every point, not only the ones that would have been legal: a board
        // waiting on the opponent has nothing to offer anywhere on it.
        #expect(game.effect(ofTapAt: Square("a2", on: GameKind.miniXiangqi.board)!) == .unavailable,
                "a piece of the player's own is not selectable on the machine's turn")
        #expect(game.effect(ofTapAt: Square("a6", on: GameKind.miniXiangqi.board)!) == .unavailable,
                "nor is one of the machine's")
        #expect(game.effect(ofTapAt: Square("d4", on: GameKind.miniXiangqi.board)!) == .unavailable, "nor an empty point")
        motion.tap(Square("a2", on: GameKind.miniXiangqi.board)!)
        #expect(game.selected == nil, "and a tap selects nothing")

        // It stays refused while a preparation is stalled, which is the state
        // the accepted mid-game presentation leaves behind: the AI still owes
        // the move, whatever is stopping it.
        opponent.cancelSearch()
        engine.answer(result(.failed, move: "", game: game))
        #expect(game.effect(ofTapAt: Square("a2", on: GameKind.miniXiangqi.board)!) == .unavailable)

        // And is handed back the moment the reply lands.
        engine.answer(result(.move, move: "a6a5", game: game))
        _ = animator
    }

    @Test("The frontend compares staleness again before applying")
    func theSecondStalenessComparisonRejectsAWrongResult() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()
        #expect(engine.startedSearches == 1)

        // The pair is checked, not one of it. The core compares before delivery
        // and this compares before applying, because neither alone covers both
        // race directions — and neither *half* of the pair alone covers both
        // collisions either.

        // A revision the position has left behind.
        engine.answer(result(.move, move: "a6a5", game: game, ticket: 1,
                             revision: game.evaluation.positionRevision + 1))
        clock.advance(by: 5)
        animator.completeAll()
        #expect(game.moves == ["b1b4"], "a result from another position applies nothing")

        // And an identity that is not this game's, carrying a revision that
        // matches perfectly. A released-and-resumed session can hold the same
        // counter, which is the collision the identity half exists for and the
        // one the revision cannot see.
        opponent.gameChanged()
        #expect(engine.startedSearches == 2, "the premise: a search is running again")
        engine.answer(result(.move, move: "a6a5", game: game, ticket: 2,
                             identity: "00000000-0000-7000-8000-000000000000"))
        clock.advance(by: 5)
        animator.completeAll()
        #expect(game.moves == ["b1b4"], "a result from another game applies nothing either")

        // The same move, from the game and the position it belongs to, is
        // played — which is what says the two refusals above were the
        // comparison rather than anything about the move.
        opponent.gameChanged()
        #expect(engine.startedSearches == 3)
        engine.answer(result(.move, move: "a6a5", game: game, ticket: 3))
        clock.advance(by: 5)
        animator.completeAll()
        #expect(game.moves == ["b1b4", "a6a5"])
    }

    @Test("A result whose identity and revision match is played through the board")
    func aMatchingResultIsPlayed() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        _ = opponent
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()   // the player's move lands

        engine.answer(result(.move, move: "a6a5", game: game))
        clock.advance(by: Motion.replyFloor + 0.01)
        animator.completeAll()   // the reply travels and lands

        #expect(game.moves == ["b1b4", "a6a5"], "the reply arrived through the board")
        #expect(!game.searchExpected, "and the turn is the player's again")
    }

    @Test("The reply has a floor: it departs no earlier than the player's arrival plus one")
    func theReplyWaitsForTheFloor() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        _ = opponent
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)

        // The search answers **while the player's move is still travelling**,
        // which is the case the floor is really for: a forced mate comes back in
        // milliseconds, and there is no arrival yet to measure a floor from. It
        // is measured from the arrival when the arrival happens.
        engine.answer(result(.move, move: "a6a5", game: game))
        #expect(game.moves == ["b1b4"], "nothing departs during the player's own move")

        animator.completeAll()   // the arrival the floor is measured from
        #expect(game.moves == ["b1b4"],
                "and not at the landing either: a reply that beat the arrival still waits")

        clock.advance(by: Motion.replyFloor - 0.05)
        #expect(game.moves == ["b1b4"], "still inside the floor")

        clock.advance(by: 0.1)
        animator.completeAll()
        #expect(game.moves == ["b1b4", "a6a5"], "and departs once the floor has passed")
    }

    @Test("A reply that arrives after the landing keeps the floor from that landing")
    func theFloorHoldsForAReplyAfterTheArrival() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        _ = opponent
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()   // the arrival first, this time

        clock.advance(by: 0.1)   // a search shorter than the floor
        engine.answer(result(.move, move: "a6a5", game: game))
        #expect(game.moves == ["b1b4"], "a near-instant reply does not twitch")

        clock.advance(by: Motion.replyFloor - 0.15)
        #expect(game.moves == ["b1b4"], "still inside the floor")

        clock.advance(by: 0.1)
        animator.completeAll()
        #expect(game.moves == ["b1b4", "a6a5"], "and departs once the floor has passed")
    }

    @Test("A slow search is unaffected by the floor")
    func aSlowSearchDoesNotWait() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        _ = opponent
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()

        clock.advance(by: 3)     // the search thinks for three seconds
        engine.answer(result(.move, move: "a6a5", game: game))
        animator.completeAll()
        #expect(game.moves == ["b1b4", "a6a5"], "the floor had long since passed")
    }

    @Test("Activity shows only once a search has run long enough to be worth showing")
    func theIndicatorWaitsItsThreshold() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()

        #expect(opponent.activity == .idle, "a search just started shows nothing")
        clock.advance(by: Motion.thinkingIndicatorDelay - 0.05)
        #expect(opponent.activity == .idle)
        clock.advance(by: 0.1)
        #expect(opponent.activity == .thinking, "and past the threshold it does")

        engine.answer(result(.move, move: "a6a5", game: game))
        #expect(opponent.activity == .idle, "the indicator is gone when the reply lands")
        clock.advance(by: 5)
        animator.completeAll()
        _ = game
    }

    @Test("A search cancelled before the threshold never shows activity at all")
    func aCancelledSearchShowsNothing() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()

        opponent.cancelSearch()
        #expect(engine.cancelledTickets == [1], "the search was cancelled by ticket")
        clock.advance(by: 5)
        #expect(opponent.activity == .idle)
        _ = game
    }

    // MARK: - The decision cycle

    @Test("Undo consumes the core's own ply count: a whole exchange, not half of one")
    func undoTakesBackTheCycle() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        _ = opponent
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()
        engine.answer(result(.move, move: "a6a5", game: game))
        clock.advance(by: 5)
        animator.completeAll()
        #expect(game.moves == ["b1b4", "a6a5"], "the premise: a complete cycle")

        #expect(game.evaluation.undoPlies == 2,
                "the core counts the decision cycle; nothing above it does")
        motion.undo()
        animator.completeAll()
        #expect(game.moves.isEmpty, "one Undo removed the reply and the move that invited it")
        #expect(game.notation.isEmpty)
    }

    @Test("Undo while the machine is thinking cancels the search and removes one ply")
    func undoWhileThinkingCancels() throws {
        let (opponent, game, motion, engine, _, animator) = try makeOpponent()
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()
        #expect(engine.startedSearches == 1)
        #expect(game.evaluation.undoPlies == 1,
                "with no reply yet there is only the player's own move to remove")

        opponent.cancelSearch()
        motion.undo()
        animator.completeAll()

        #expect(engine.cancelledTickets == [1], "the search was cancelled")
        #expect(game.moves.isEmpty, "and the move that triggered it is gone")
        #expect(!game.searchExpected, "so nothing is owed")
    }

    @Test("The AI's opening move alone cannot be undone")
    func theOpeningMoveIsNotACycle() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent(humanSide: .black)
        opponent.begin()
        #expect(engine.startedSearches == 1, "the AI moves first, so it owes the opening")

        engine.answer(result(.move, move: "b1b4", game: game))
        clock.advance(by: 5)
        animator.completeAll()

        #expect(game.moves == ["b1b4"])
        #expect(!game.canUndo, "the core offers no Undo: there is no decision to return to")
    }

    // MARK: - Refusals

    @Test("A refused AI reply asks for a new search and shows nothing")
    func aRefusedReplyRetriesSilently() throws {
        let core = try TestCores.fresh()
        let rules = RefusingRules(core)
        try rules.create(.humanVersusAI(game: .miniXiangqi, humanSide: .red,
                                       level: .fast, choice: .humanFirst))
        let game = try Game(rules: rules)
        let animator = ManualAnimator()
        let motion = PlayMotion(game: game, animator: animator.animator,
                                feedback: FeedbackRecorder(defaults: try ScratchDefaults.make()).feedback)
        let engine = TestEngine()
        let clock = TestTimer()
        let opponent = Opponent(engine: engine, game: game, motion: motion, timer: clock.timer)
        motion.committed = { [weak opponent] in opponent?.gameChanged() }
        motion.landed = { [weak opponent] in opponent?.landed() }

        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()
        #expect(engine.startedSearches == 1)

        rules.refuses = true
        engine.answer(result(.move, move: "a6a5", game: game))
        clock.advance(by: 5)
        animator.completeAll()

        #expect(game.moves == ["b1b4"], "the reply did not happen")
        #expect(game.failure == nil, "and raises no capsule: the retry is the app's")
        #expect(game.opponentFailure != nil)
        #expect(engine.startedSearches == 2,
                "so a new search is requested from the unchanged position")
    }

    @Test("A preparation that fails raises the mid-game alert, and 稍后 leaves the stalled slot")
    func aFailedPreparationStallsWithARetry() throws {
        let (opponent, game, motion, engine, _, animator) = try makeOpponent()
        engine.preparationRefusal = CoreError(status: MxqStatus(MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY),
                                              detail: "not enough")
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()

        #expect(opponent.preparationFailure != nil, "the alert is what a failure raises first")
        #expect(engine.startedSearches == 0, "and nothing searched")

        opponent.deferPreparation()
        #expect(opponent.preparationFailure == nil, "稍后 puts the alert away")
        #expect(opponent.activity == .stalled,
                "and leaves the state where things about the game live")

        // Every retry re-probes fresh.
        engine.preparationRefusal = nil
        opponent.retryPreparation()
        #expect(engine.probes == 2, "the retry took a fresh probe")
        #expect(engine.startedSearches == 1, "and the machine is thinking again")
        #expect(opponent.activity == .idle)
        _ = game
    }

    @Test("Undo is the other way out of a stalled preparation")
    func undoClearsTheStall() throws {
        let (opponent, game, motion, engine, _, animator) = try makeOpponent()
        engine.preparationRefusal = CoreError(status: MxqStatus(MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY),
                                              detail: "not enough")
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()
        opponent.deferPreparation()
        #expect(opponent.activity == .stalled)

        // Exactly what the screen does, and nothing more: the Undo control
        // cancels the search and runs the transition. Nothing tells the
        // opponent afterwards — PlayMotion's own committed wire is what does,
        // and a test that called `gameChanged()` by hand would pass with that
        // wire cut.
        opponent.cancelSearch()
        motion.undo()
        animator.completeAll()

        #expect(game.moves.isEmpty, "the player's move is back in their hands")
        #expect(opponent.activity == .idle,
                "and the stalled state does not outlive the search it was about")
    }

    // MARK: - Suspension

    @Test("Suspension cancels and releases whole, and prepares nothing until it is back")
    func suspensionReleasesAndWaits() throws {
        let (opponent, game, motion, engine, _, animator) = try makeOpponent()
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()
        #expect(engine.startedSearches == 1)

        opponent.suspend()
        #expect(engine.cancelledTickets == [1], "the running search was cancelled")
        #expect(engine.cancelAlls == 1, "and every outstanding one with it")
        #expect(engine.teardowns == 1, "the transposition table is released whole")

        opponent.gameChanged()
        #expect(engine.preparations == 1, "nothing is prepared while it is away")

        opponent.resume()
        #expect(engine.preparations == 2,
                "and coming back prepares, because a search is owed")
        #expect(engine.startedSearches == 2)
        _ = game
    }

    @Test("Memory pressure releases and then asks again, because nothing will say it passed")
    func memoryPressureIsNotASuspension() throws {
        let (opponent, game, motion, engine, _, animator) = try makeOpponent()
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()

        opponent.memoryPressure()

        #expect(engine.cancelAlls == 1)
        #expect(engine.teardowns == 1, "the same cancel-and-release, whole")
        #expect(engine.preparations == 2,
                "and the owed search is asked again, from a fresh probe")
        #expect(engine.probes == 2)
        _ = game
    }

    @Test("A resumed game that owes nothing prepares nothing")
    func nothingOwedPreparesNothing() throws {
        let (opponent, game, motion, engine, _, _) = try makeOpponent()
        _ = motion
        opponent.suspend()
        opponent.resume()
        #expect(engine.preparations == 0,
                "a game waiting on the player is one of the states that owes nothing")
        _ = game
    }
}
