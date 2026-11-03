import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@MainActor
final class TestEngine: AIEngine {
    var budget = EngineBudget(activeProcessorCount: 8,
                              availableBytes: 8 << 30,
                              physicalBytes: 16 << 30)
    var preparationRefusal: CoreError?
    var holdsPreparation = false
    var startRefusal: CoreError?
    var hintStartRefusal: CoreError?

    private(set) var probes = 0
    private(set) var preparations = 0
    private(set) var teardowns = 0
    private(set) var cancelledTickets: [UInt64] = []
    private(set) var cancelAlls = 0
    private(set) var startedSearches = 0
    private(set) var startedHintSearches = 0
    private(set) var lastMovetime: UInt32?
    private(set) var lastHintMovetime: UInt32?
    private(set) var lastLine: SearchLine?
    private(set) var lastBudget: EngineBudget?
    private(set) var lastPreparedGame: GameKind?
    private(set) var preparedGame: GameKind?

    enum Event: Equatable {
        case prepare(GameKind), search(UInt32), hint(UInt32)
        case cancel(UInt64), cancelAll, teardown
    }

    private(set) var events: [Event] = []

    private var held: (game: GameKind, budget: EngineBudget,
                       completion: @MainActor (Result<EnginePlan, CoreError>) -> Void)?
    private var completion: (@MainActor (SearchResult) -> Void)?
    private var hintCompletion: (@MainActor (SearchResult) -> Void)?
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
        events.append(.prepare(game))
        guard !holdsPreparation else {
            held = (game, budget, completion)
            return
        }
        answerPreparation(for: game, budget, completion)
    }

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
        completion(.success(Self.emptyPlan))
    }

    func markReady(for game: GameKind) { preparedGame = game }

    private static let emptyPlan = EnginePlan(MxqEnginePlan())

    func teardownEngine(then next: (@MainActor () -> Void)?) {
        teardowns += 1
        preparedGame = nil
        events.append(.teardown)
        next?()
    }

    func startSearch(_ line: SearchLine, movetimeMilliseconds: UInt32,
                     completion: @escaping @MainActor (SearchResult) -> Void) throws -> UInt64 {
        if let startRefusal {
            self.startRefusal = nil
            unprepareIfReadinessRefusal(startRefusal)
            throw startRefusal
        }
        startedSearches += 1
        lastMovetime = movetimeMilliseconds
        lastLine = line
        self.completion = completion
        ticket += 1
        events.append(.search(movetimeMilliseconds))
        return ticket
    }

    func startHintSearch(_ line: SearchLine, movetimeMilliseconds: UInt32,
                         completion: @escaping @MainActor (SearchResult) -> Void) throws -> UInt64 {
        if let hintStartRefusal {
            self.hintStartRefusal = nil
            unprepareIfReadinessRefusal(hintStartRefusal)
            throw hintStartRefusal
        }
        startedHintSearches += 1
        lastHintMovetime = movetimeMilliseconds
        lastLine = line
        hintCompletion = completion
        ticket += 1
        events.append(.hint(movetimeMilliseconds))
        return ticket
    }

    private func unprepareIfReadinessRefusal(_ refusal: CoreError) {
        if refusal.status == MxqStatus(MXQ_ERR_ENGINE_NOT_PREPARED)
            || refusal.status == MxqStatus(MXQ_ERR_STATE_ENGINE_NOT_READY) {
            preparedGame = nil
        }
    }

    func cancelSearch(_ ticket: UInt64) {
        cancelledTickets.append(ticket)
        events.append(.cancel(ticket))
    }

    func cancelAllSearches() {
        cancelAlls += 1
        events.append(.cancelAll)
    }

    func answer(_ result: SearchResult) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }

    func answerHint(_ result: SearchResult) {
        let completion = hintCompletion
        hintCompletion = nil
        completion?(result)
    }

    var hasOutstandingSearch: Bool { completion != nil }
    var hasOutstandingHintSearch: Bool { hintCompletion != nil }
}

@MainActor
final class TestTimer {
    private(set) var now: TimeInterval = 1000
    private var pending: [(due: TimeInterval, body: @MainActor () -> Void)] = []

    var timer: MotionTimer {
        MotionTimer(now: { self.now },
                    after: { delay, body in
                        self.pending.append((self.now + delay, body))
                    })
    }

    func advance(by interval: TimeInterval) {
        now += interval
        while let index = pending.firstIndex(where: { $0.due <= now }) {
            let entry = pending.remove(at: index)
            entry.body()
        }
    }

    var pendingCount: Int { pending.count }
}

@Suite("The opponent", .retiringItsCores)
@MainActor
struct OpponentTests {
    private func makeOpponent(humanSide: Side = .red, level: AiLevel = .fast)
        throws -> (Opponent, Game, PlayMotion, TestEngine, TestTimer, ManualAnimator) {
        let library = try TestLibraries.fresh()
        try library.create(.humanVersusAI(game: .miniXiangqi, humanSide: humanSide, level: level))
        let game = try Game(library: library)
        let animator = ManualAnimator()
        let motion = PlayMotion(game: game, animator: animator.animator,
                                feedback: FeedbackRecorder().feedback)
        let engine = TestEngine()
        let clock = TestTimer()
        let opponent = Opponent(engine: engine, game: game, motion: motion,
                                timer: clock.timer)
        motion.committed = { [weak opponent] in opponent?.gameChanged() }
        motion.landed = { [weak opponent] in opponent?.landed() }
        return (opponent, game, motion, engine, clock, animator)
    }

    @Test("A search is prepared and started exactly when one is owed")
    func aSearchIsOwedOrItIsNot() throws {
        let (opponent, game, motion, engine, _, animator) = try makeOpponent()

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
        #expect(engine.lastLine == SearchLine(game: .miniXiangqi, start: frozenStart(.miniXiangqi),
                                              moves: ["b1b4"]),
                "over the game's own line")
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

        #expect(game.effect(ofTapAt: Square("a2", on: GameKind.miniXiangqi.board)!) == .unavailable,
                "a piece of the player's own is not selectable on the machine's turn")
        #expect(game.effect(ofTapAt: Square("a6", on: GameKind.miniXiangqi.board)!) == .unavailable,
                "nor is one of the machine's")
        #expect(game.effect(ofTapAt: Square("d4", on: GameKind.miniXiangqi.board)!) == .unavailable, "nor an empty point")
        motion.tap(Square("a2", on: GameKind.miniXiangqi.board)!)
        #expect(game.selected == nil, "and a tap selects nothing")

        opponent.cancelSearch()
        engine.answer(searchResult(.failed, move: ""))
        #expect(game.effect(ofTapAt: Square("a2", on: GameKind.miniXiangqi.board)!) == .unavailable)

        engine.answer(searchResult(.move, move: "a6a5"))
        _ = animator
    }

    @Test("A reply to a line the game has left applies nothing")
    func aReplyToAnOldLineIsRejected() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()
        #expect(engine.startedSearches == 1)

        // The line changes under the search, and nobody tells the opponent:
        // the same position again, at a later revision.
        game.undo()
        game.play(Move(text: "b1b4", on: GameKind.miniXiangqi.board)!)
        engine.answer(searchResult(.move, move: "a6a5", ticket: 1))
        clock.advance(by: 5)
        animator.completeAll()
        #expect(game.moves == ["b1b4"], "a reply asked of another line applies nothing")

        opponent.gameChanged()
        #expect(engine.startedSearches == 2, "the premise: a search is running again")
        engine.answer(searchResult(.move, move: "a6a5", ticket: 2))
        clock.advance(by: 5)
        animator.completeAll()
        #expect(game.moves == ["b1b4", "a6a5"])
    }

    @Test("A reply to the game's own line is played through the board")
    func aMatchingResultIsPlayed() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        _ = opponent
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()   // the player's move lands

        engine.answer(searchResult(.move, move: "a6a5"))
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

        engine.answer(searchResult(.move, move: "a6a5"))
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
        engine.answer(searchResult(.move, move: "a6a5"))
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
        engine.answer(searchResult(.move, move: "a6a5"))
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

        engine.answer(searchResult(.move, move: "a6a5"))
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

    @Test("Undo takes back a whole exchange, not half of one")
    func undoTakesBackTheCycle() throws {
        let (opponent, game, motion, engine, clock, animator) = try makeOpponent()
        _ = opponent
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        animator.completeAll()
        engine.answer(searchResult(.move, move: "a6a5"))
        clock.advance(by: 5)
        animator.completeAll()
        #expect(game.moves == ["b1b4", "a6a5"], "the premise: a complete cycle")

        #expect(game.undoPlies == 2, "the game counts the decision cycle")
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
        #expect(game.undoPlies == 1,
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

        engine.answer(searchResult(.move, move: "b1b4"))
        clock.advance(by: 5)
        animator.completeAll()

        #expect(game.moves == ["b1b4"])
        #expect(!game.canUndo, "there is no Undo: there is no decision to return to")
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

        opponent.cancelSearch()
        motion.undo()
        animator.completeAll()

        #expect(game.moves.isEmpty, "the player's move is back in their hands")
        #expect(opponent.activity == .idle,
                "and the stalled state does not outlive the search it was about")
    }

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
