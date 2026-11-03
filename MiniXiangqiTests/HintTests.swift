import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@Suite("The hint", .retiringItsCores)
@MainActor
struct HintTests {
    private static let board = GameKind.miniXiangqi.board

    private static let shuffleLine = ["b1b2", "b7b6", "b2b1", "b6b7",
                                      "b1b2", "b7b6", "b2b1", "b6b7"]

    private func point(_ name: String) -> Square { Square(name, on: Self.board)! }

    private struct Apparatus {
        let hint: Hint
        let opponent: Opponent
        let game: Game
        let motion: PlayMotion
        let engine: TestEngine
        let clock: TestTimer
        let animator: ManualAnimator
    }

    private func makeApparatus(_ configuration: GameConfiguration,
                               engine: TestEngine = TestEngine(),
                               reduceMotion: Bool = false) throws -> Apparatus {
        let library = try TestLibraries.fresh()
        try library.create(configuration)
        return try makeApparatus(over: library, engine: engine, reduceMotion: reduceMotion)
    }

    private func makeApparatus(over library: GameLibrary, engine: TestEngine = TestEngine(),
                               reduceMotion: Bool = false) throws -> Apparatus {
        let game = try Game(library: library)
        let animator = ManualAnimator()
        let motion = PlayMotion(game: game,
                                policy: MotionPolicy(reduceMotion: reduceMotion),
                                animator: animator.animator,
                                feedback: FeedbackRecorder().feedback)
        let clock = TestTimer()
        let opponent = Opponent(engine: engine, game: game, motion: motion,
                                timer: clock.timer)
        let hint = Hint(engine: engine, game: game, motion: motion,
                        timer: clock.timer)
        motion.committed = { [weak opponent, weak hint] in
            hint?.cancel()
            opponent?.gameChanged()
        }
        motion.landed = { [weak opponent] in opponent?.landed() }
        return Apparatus(hint: hint, opponent: opponent, game: game, motion: motion,
                         engine: engine, clock: clock, animator: animator)
    }

    private func humanVersusAI(level: AiLevel = .fast, humanSide: Side = .red)
        -> GameConfiguration {
        .humanVersusAI(game: .miniXiangqi, humanSide: humanSide, level: level)
    }

    private func play(_ from: String, _ to: String, _ apparatus: Apparatus) {
        apparatus.motion.tap(point(from))
        apparatus.motion.tap(point(to))
        apparatus.animator.completeAll()
    }

    @Test("A hint is offered on the player's own live turn and at no other moment")
    func offeredOnlyOnThePlayersOwnLiveTurn() throws {
        let apparatus = try makeApparatus(humanVersusAI())
        #expect(apparatus.hint.isOffered, "the human is Red and moves first")

        play("b1", "b4", apparatus)
        #expect(apparatus.game.searchExpected, "the premise: the AI owes a move")
        #expect(!apparatus.hint.isOffered,
                "and the machine's turn is not the player's to be advised on")

        apparatus.engine.answer(searchResult(.move, move: "a6a5"))
        apparatus.clock.advance(by: 5)
        apparatus.animator.completeAll()
        #expect(apparatus.hint.isOffered, "the turn came back, and so did the offer")

        apparatus.game.resign()
        #expect(apparatus.game.isFinished)
        #expect(!apparatus.hint.isOffered)
    }

    @Test("Free Play is offered a hint on either turn, because both are the player's")
    func freePlayOffersAHintOnEitherTurn() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        #expect(apparatus.hint.isOffered, "Red to move, and Red is the player")

        play("b1", "b4", apparatus)
        #expect(apparatus.game.evaluation.sideToMove == .black)
        #expect(apparatus.hint.isOffered,
                "and so is Black: one person controls both sides")
    }

    @Test("A nearby game is never offered a hint")
    func nearbyPlayIsNeverOfferedAHint() throws {
        let library = try TestLibraries.fresh()
        _ = try library.createNetworked(.nearby(game: .miniXiangqi, localSide: .red),
                                        id: UUID(), peer: "P")
        _ = try library.resumeActive()
        let apparatus = try makeApparatus(over: library)

        #expect(!apparatus.hint.isOffered,
                """
                a suggestion engine on one side of a game between two people is \
                not this product's nearby play
                """)
        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 0)
        #expect(apparatus.engine.preparations == 0)
    }

    @Test("A claimable repetition nobody has claimed has its hint like any other position")
    func aClaimableRepetitionIsOfferedAHint() throws {
        let library = try TestLibraries.fresh()
        try library.create(.freePlay(game: .miniXiangqi))
        let apparatus = try makeApparatus(over: library)
        try apparatus.game.replay(Self.shuffleLine)
        apparatus.engine.markReady(for: .miniXiangqi)

        #expect(apparatus.game.evaluation.claimAvailable, "the premise: the claim is standing")
        #expect(!apparatus.game.isFinished,
                "and an unclaimed repetition is an ongoing game, not a result")

        #expect(apparatus.hint.isOffered)
        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 1,
                "a standing offer to end the game is not a reason to refuse advice about it")

        apparatus.engine.answerHint(searchResult(.move, move: "b1b2"))
        #expect(apparatus.motion.suggested == point("b2"), "and the suggestion arrives")
    }

    @Test("A human-versus-AI hint thinks the time the game itself froze",
          arguments: [(AiLevel.fast, UInt32(1000)), (.standard, 3000), (.deep, 5000)])
    func theHintTakesTheGamesOwnFrozenTime(_ level: AiLevel, _ movetime: UInt32) throws {
        let apparatus = try makeApparatus(humanVersusAI(level: level))
        apparatus.engine.markReady(for: .miniXiangqi)

        apparatus.hint.request()

        #expect(apparatus.engine.startedHintSearches == 1)
        #expect(apparatus.engine.lastHintMovetime == movetime,
                """
                a Deep game gives deeper hints, and the hint is never a different \
                opponent from the one playing
                """)
    }

    @Test("Free Play prepares the engine at the first request, from a fresh probe")
    func freePlayPreparesLazily() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        #expect(apparatus.engine.preparations == 0,
                "a Free Play game that never asks costs nothing")

        apparatus.hint.request()

        #expect(apparatus.engine.preparations == 1)
        #expect(apparatus.engine.probes == 1, "from a probe taken at the attempt")
        #expect(apparatus.engine.lastPreparedGame == .miniXiangqi)
        #expect(apparatus.engine.startedHintSearches == 1, "and then searches")

        apparatus.hint.request()
        #expect(apparatus.engine.preparations == 1)
        #expect(apparatus.engine.startedHintSearches == 1)
    }

    @Test("A preparation that fails raises the hint's own notice, and every retry re-probes")
    func aFailedPreparationRaisesTheNotice() throws {
        let engine = TestEngine()
        engine.preparationRefusal = CoreError(status: MxqStatus(MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY),
                                              detail: "not enough")
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi), engine: engine)

        apparatus.hint.request()

        #expect(apparatus.hint.preparationFailure != nil, "the notice is what a failure raises")
        #expect(apparatus.hint.preparationFailureNamesMemory,
                "and this one is the situation the accepted message is about")
        #expect(engine.startedHintSearches == 0, "nothing searched")

        apparatus.hint.dismissPreparationFailure()
        #expect(apparatus.hint.preparationFailure == nil)

        engine.preparationRefusal = nil
        apparatus.hint.retryPreparation()
        #expect(engine.probes == 2, "the retry took a fresh probe")
        #expect(engine.startedHintSearches == 1, "and the hint is being thought about")
    }

    @Test("A failure that is not about memory names no cause")
    func aDamagedInstallationNamesNoCause() throws {
        let engine = TestEngine()
        engine.preparationRefusal = CoreError(status: MxqStatus(MXQ_ERR_ENGINE_ASSET_MISMATCH),
                                              detail: "the network does not match")
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi), engine: engine)

        apparatus.hint.request()

        #expect(apparatus.hint.preparationFailure != nil,
                "the player pressed a control and is owed an answer")
        #expect(!apparatus.hint.preparationFailureNamesMemory,
                """
                but closing other apps will not fix a damaged installation, and \
                naming the wrong cause is worse than naming none
                """)
    }

    @Test("A suggestion is the board's own selection plus one strengthened destination")
    func theSuggestionIsDrawnInTheBoardsOwnLanguage() throws {
        let apparatus = try makeApparatus(humanVersusAI())
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.hint.request()

        apparatus.engine.answerHint(searchResult(.move, move: "b1b4"))

        #expect(apparatus.game.selected == point("b1"),
                "the suggested piece is taken up exactly as a tap takes one up")
        #expect(apparatus.game.destinations.contains(point("b4")),
                "so its legal destinations are on the board")
        #expect(apparatus.motion.suggested == point("b4"))
        #expect(apparatus.motion.hintEmphasis == 1, "and that one is strengthened")
        #expect(apparatus.hint.activity == .idle)

        apparatus.animator.completeAll()
        #expect(apparatus.motion.hintEmphasis == 1,
                """
                and stays strengthened: the swell is how the state arrives, not \
                something the state relaxes back out of — unlike the illegal-tap \
                pulse, which has the markers themselves to fall back to
                """)

        apparatus.motion.tap(point("b4"))
        apparatus.animator.completeAll()
        #expect(apparatus.game.moves == ["b1b4"])
        #expect(apparatus.motion.suggested == nil)
        #expect(apparatus.motion.hintEmphasis == 0)
    }

    @Test("On a board that places, the suggestion is the pending stone itself")
    func aPlacementSuggestionIsThePendingStone() throws {
        let apparatus = try makeApparatus(.freePlay(game: .gomoku15))
        let suggested = Square("h8", on: GameKind.gomoku15.board)!
        apparatus.engine.markReady(for: .gomoku15)
        apparatus.hint.request()

        apparatus.engine.answerHint(searchResult(.move, move: "h8"))

        #expect(apparatus.game.selected == suggested,
                "the mark is the game's own pending state, not a second mechanism")
        #expect(apparatus.motion.suggested == suggested)
        #expect(apparatus.motion.hintEmphasis == 1)
        #expect(apparatus.game.placement[suggested] == nil,
                "and nothing is committed by showing it")
        apparatus.animator.completeAll()

        apparatus.motion.tap(suggested)
        apparatus.animator.completeAll()
        #expect(apparatus.game.moves == ["h8"])
        #expect(apparatus.game.placement[suggested]?.side == .red,
                "the first mover's stone, which these games draw black")
        #expect(apparatus.game.selected == nil)
        #expect(apparatus.motion.suggested == nil)
        #expect(apparatus.motion.hintEmphasis == 0)
    }

    @Test("Under Reduce Motion the strengthened state arrives without the swell")
    func reduceMotionKeepsTheStateAndDropsThePulse() throws {
        let apparatus = try makeApparatus(humanVersusAI(), reduceMotion: true)
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.hint.request()

        apparatus.engine.answerHint(searchResult(.move, move: "b1b4"))

        #expect(apparatus.game.selected == point("b1"), "the piece is still held")
        #expect(apparatus.motion.suggested == point("b4"))
        #expect(apparatus.motion.hintEmphasis == 1,
                "the strengthened state arrives; only the swell goes")
        apparatus.animator.completeAll()
        #expect(apparatus.motion.hintEmphasis == 1)
    }

    @Test("Every ordinary selection interaction takes the suggestion off the board")
    func aSelectionThatMovedTakesTheSuggestionWithIt() throws {
        let apparatus = try makeApparatus(humanVersusAI())
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.hint.request()
        apparatus.engine.answerHint(searchResult(.move, move: "b1b4"))
        #expect(apparatus.motion.suggested == point("b4"))

        apparatus.motion.tap(point("a1"))
        #expect(apparatus.game.selected == point("a1"))
        #expect(apparatus.motion.suggested == nil)
        #expect(apparatus.motion.hintEmphasis == 0)

        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 1, "which the cache answers")
        #expect(apparatus.motion.suggested == point("b4"))
        apparatus.motion.cancelSelection()
        #expect(apparatus.game.selected == nil)
        #expect(apparatus.motion.suggested == nil)
    }

    @Test("A repeated request on one position re-shows the answer it already has")
    func theAnswerIsCachedWithItsPosition() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.hint.request()
        apparatus.engine.answerHint(searchResult(.move, move: "b1b4"))
        apparatus.motion.cancelSelection()

        apparatus.hint.request()

        #expect(apparatus.engine.startedHintSearches == 1,
                "an unchanged position is not thought about twice")
        #expect(apparatus.motion.suggested == point("b4"), "and the answer is back")

        apparatus.motion.tap(point("b4"))
        apparatus.animator.completeAll()
        #expect(apparatus.game.moves == ["b1b4"])

        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 2,
                "a position the game has left has no answer to reuse")
    }

    @Test("An answer about a line the game has left shows nothing")
    func aStaleAnswerShowsNothing() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        apparatus.engine.markReady(for: .miniXiangqi)

        apparatus.hint.request()
        // The line moves under the search, and nobody tells the hint.
        apparatus.game.play(Move(text: "b1b4", on: Self.board)!)
        apparatus.engine.answerHint(searchResult(.move, move: "a6a5"))
        #expect(apparatus.motion.suggested == nil, "a revision the game has left behind")

        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 2)
    }

    @Test("Activity shows only once a hint search has run long enough to be worth showing")
    func theIndicatorWaitsItsThreshold() throws {
        let apparatus = try makeApparatus(humanVersusAI())
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.hint.request()

        #expect(apparatus.hint.activity == .idle, "a search just started shows nothing")
        apparatus.clock.advance(by: Motion.thinkingIndicatorDelay - 0.05)
        #expect(apparatus.hint.activity == .idle)
        apparatus.clock.advance(by: 0.1)
        #expect(apparatus.hint.activity == .thinking, "and past the threshold it does")

        apparatus.engine.answerHint(searchResult(.move, move: "b1b4"))
        #expect(apparatus.hint.activity == .idle, "the indicator is gone with the answer")
    }

    @Test("The player's own commit cancels the hint before the reply is asked for")
    func theCommitCancelsTheHintBeforeTheReply() throws {
        let library = try TestLibraries.fresh()
        let engine = TestEngine()
        let state = PlayState(library: library, engine: engine)
        state.choose(PlaySelection(game: .miniXiangqi, mode: .humanVersusAI))
        state.draft = SetupDraft(firstMover: .humanFirst, level: .fast)
        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .board)

        let hint = try #require(state.hint)
        let motion = try #require(state.motion)
        hint.request()
        #expect(engine.startedHintSearches == 1)

        motion.tap(point("b1"))
        motion.tap(point("b4"))

        #expect(engine.cancelledTickets == [1], "the hint search was cancelled")
        let cancelled = try #require(engine.events.firstIndex(of: .cancel(1)))
        let replyRequested = try #require(engine.events.firstIndex(of: .search(1000)))
        #expect(cancelled < replyRequested,
                """
                and cancelled before the reply was requested: the engine thread runs \
                one search at a time, and a reply queued behind a hint waits for it
                """)
        #expect(hint.activity == .idle)
        #expect(motion.suggested == nil)
    }

    @Test("Undo cancels the hint and takes the suggestion with it")
    func undoCancelsTheHint() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        apparatus.engine.markReady(for: .miniXiangqi)
        play("b1", "b4", apparatus)
        apparatus.hint.request()
        apparatus.engine.answerHint(searchResult(.move, move: "a6a5"))
        #expect(apparatus.motion.suggested == point("a5"))

        apparatus.hint.cancel()
        apparatus.motion.undo()
        apparatus.animator.completeAll()

        #expect(apparatus.game.moves.isEmpty)
        #expect(apparatus.motion.suggested == nil)
        #expect(apparatus.engine.cancelledTickets.isEmpty,
                "the search had already answered; there was nothing left to cancel")

        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 2)
    }

    @Test("Suspension puts a running hint down whole")
    func suspensionPutsTheHintDown() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.hint.request()
        apparatus.clock.advance(by: Motion.thinkingIndicatorDelay + 0.1)
        #expect(apparatus.hint.activity == .thinking)

        apparatus.hint.cancel()
        apparatus.opponent.suspend()

        #expect(apparatus.engine.cancelledTickets == [1])
        #expect(apparatus.engine.cancelAlls == 1)
        #expect(apparatus.engine.teardowns == 1, "the table is released whole")
        #expect(apparatus.hint.activity == .idle)
        #expect(apparatus.motion.suggested == nil)

        apparatus.engine.answerHint(searchResult(.move, move: "b1b4"))
        #expect(apparatus.motion.suggested == nil)
    }

    @Test("Memory pressure puts a running hint down with the table it was thinking on")
    func memoryPressurePutsTheHintDown() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.hint.request()
        apparatus.clock.advance(by: Motion.thinkingIndicatorDelay + 0.1)
        #expect(apparatus.hint.activity == .thinking)

        apparatus.hint.cancel()
        apparatus.opponent.memoryPressure()

        #expect(apparatus.engine.cancelledTickets == [1])
        #expect(apparatus.engine.cancelAlls == 1)
        #expect(apparatus.engine.teardowns == 1, "the table is released whole")
        #expect(apparatus.hint.activity == .idle)
        #expect(apparatus.motion.suggested == nil)

        apparatus.engine.answerHint(searchResult(.move, move: "b1b4"))
        #expect(apparatus.motion.suggested == nil)

        apparatus.hint.request()
        #expect(apparatus.engine.preparations == 1)
        #expect(apparatus.engine.startedHintSearches == 2)
    }

    @Test("Leaving the board puts the hint down and releases the engine it prepared")
    func leavingTheBoardReleasesAFreePlayEngine() throws {
        let library = try TestLibraries.fresh()
        let engine = TestEngine()
        let state = PlayState(library: library, engine: engine)
        state.choose(PlaySelection(game: .miniXiangqi, mode: .freePlay))
        state.startGame(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .board)
        #expect(engine.preparations == 0, "Free Play creates without an engine at all")

        let hint = try #require(state.hint)
        hint.request()
        #expect(engine.preparations == 1, "the first request prepares one")
        #expect(engine.startedHintSearches == 1)

        state.leaveTopPage()

        #expect(state.hint == nil, "the hint belongs to the board that is gone")
        #expect(engine.cancelledTickets == [1], "its search was cancelled")
        #expect(engine.cancelAlls == 1)
        #expect(engine.teardowns == 1,
                "and the table a hint prepared is released like any other")
    }

    @Test("A readiness refusal prepares the game and asks again")
    func aReadinessRefusalPrepares() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.engine.hintStartRefusal =
            CoreError(status: MxqStatus(MXQ_ERR_STATE_ENGINE_NOT_READY),
                      detail: "the engine went away")

        apparatus.hint.request()

        #expect(apparatus.engine.preparations == 1,
                "the engine was torn down under the request, so it is prepared again")
        #expect(apparatus.engine.startedHintSearches == 1)
    }
}
