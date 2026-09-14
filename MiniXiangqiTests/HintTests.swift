// The hint: when it is on offer, what it thinks with, what it shows, and every
// event that takes it away again.
//
// The engine is the same seam the opponent's tests hold, for the same reason: a
// working engine will not refuse a preparation on request, and the states the
// app has to survive — a preparation that fails, a suggestion that arrives
// after the position has moved on, a start refused because a cancelled search
// has not retired yet — are exactly the ones it refuses to produce. The games
// are real games on real cores, and nothing here decides a rule: whether a
// piece may be taken up is asked of the game, and whether a hint is owed is
// asked of the core's own search-expected flag.

import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@Suite("The hint", .retiringItsCores)
@MainActor
struct HintTests {

    private static let board = GameKind.miniXiangqi.board

    /// The start position a third time, which is what makes the draw
    /// claimable: both cannons step out and back twice, taking nothing and
    /// checking nothing, so the repetition is the neutral one.
    private static let shuffleLine = ["b1b2", "b7b6", "b2b1", "b6b7",
                                      "b1b2", "b7b6", "b2b1", "b6b7"]

    private func point(_ name: String) -> Square { Square(name, on: Self.board)! }

    /// A board, its opponent and its hint, wired exactly as PlayState wires
    /// them — the commit order included, since that order is what keeps a hint
    /// search out of the AI's turn. That the order holds is asserted against
    /// PlayState's own wiring rather than against this copy of it: a fixture
    /// cannot answer for the closure it imitates, and one that tried would
    /// stay green with the production cancel deleted.
    private struct Apparatus {
        let hint: Hint
        let opponent: Opponent
        let game: Game
        let motion: PlayMotion
        let engine: TestEngine
        let clock: TestTimer
        let animator: ManualAnimator
        let defaults: UserDefaults
    }

    private func makeApparatus(_ configuration: GameConfiguration,
                               engine: TestEngine = TestEngine(),
                               settingsLevel: AiLevel? = nil,
                               reduceMotion: Bool = false) throws -> Apparatus {
        let core = try TestCores.fresh()
        try core.create(configuration)
        return try makeApparatus(over: core, engine: engine,
                                 settingsLevel: settingsLevel, reduceMotion: reduceMotion)
    }

    private func makeApparatus(over rules: Rules, engine: TestEngine = TestEngine(),
                               settingsLevel: AiLevel? = nil,
                               reduceMotion: Bool = false) throws -> Apparatus {
        // One scratch domain for both readers, made once: `make()` clears the
        // suite, so a second call here would wipe the level just written into
        // it.
        let defaults = try ScratchDefaults.make()
        if let settingsLevel {
            Preferences.defaultAiLevel.set(settingsLevel.name, in: defaults)
        }
        let game = try Game(rules: rules)
        let animator = ManualAnimator()
        let motion = PlayMotion(game: game,
                                policy: MotionPolicy(reduceMotion: reduceMotion),
                                animator: animator.animator,
                                feedback: FeedbackRecorder(defaults: defaults).feedback)
        let clock = TestTimer()
        let opponent = Opponent(engine: engine, game: game, motion: motion,
                                timer: clock.timer)
        let hint = Hint(engine: engine, game: game, motion: motion,
                        timer: clock.timer, defaults: defaults)
        motion.committed = { [weak opponent, weak hint] in
            hint?.cancel()
            opponent?.gameChanged()
        }
        motion.landed = { [weak opponent] in opponent?.landed() }
        return Apparatus(hint: hint, opponent: opponent, game: game, motion: motion,
                         engine: engine, clock: clock, animator: animator,
                         defaults: defaults)
    }

    private func humanVersusAI(level: AiLevel = .fast, humanSide: Side = .red)
        -> GameConfiguration {
        .humanVersusAI(game: .miniXiangqi, humanSide: humanSide, level: level,
                       choice: humanSide == .red ? .humanFirst : .aiFirst)
    }

    /// Plays one move through the board, the way a person does.
    private func play(_ from: String, _ to: String, _ apparatus: Apparatus) {
        apparatus.motion.tap(point(from))
        apparatus.motion.tap(point(to))
        apparatus.animator.completeAll()
    }

    // MARK: - Whether there is a hint to ask for

    @Test("A hint is offered on the player's own live turn and at no other moment")
    func offeredOnlyOnThePlayersOwnLiveTurn() throws {
        let apparatus = try makeApparatus(humanVersusAI())
        #expect(apparatus.hint.isOffered, "the human is Red and moves first")

        play("b1", "b4", apparatus)
        #expect(apparatus.game.searchExpected, "the premise: the AI owes a move")
        #expect(!apparatus.hint.isOffered,
                "and the machine's turn is not the player's to be advised on")

        apparatus.engine.answer(searchResult(.move, move: "a6a5", game: apparatus.game))
        apparatus.clock.advance(by: 5)
        apparatus.animator.completeAll()
        #expect(apparatus.hint.isOffered, "the turn came back, and so did the offer")

        // A finished game has nothing left to suggest.
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
        let core = try TestCores.fresh()
        try core.createNearby(.nearby(game: .miniXiangqi, localSide: .red),
                              wire: NearbyWireSession(sessionID: "S", peerID: "P",
                                                      proposedLocally: true))
        let apparatus = try makeApparatus(over: core)

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
        let core = try TestCores.fresh()
        try core.create(.freePlay(game: .miniXiangqi))
        let apparatus = try makeApparatus(over: core)
        try apparatus.game.replay(Self.shuffleLine)
        apparatus.engine.markReady(for: .miniXiangqi)

        #expect(apparatus.game.evaluation.claimAvailable, "the premise: the claim is standing")
        #expect(!apparatus.game.isFinished,
                "and an unclaimed repetition is an ongoing game, not a result")

        #expect(apparatus.hint.isOffered)
        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 1,
                "a standing offer to end the game is not a reason to refuse advice about it")

        apparatus.engine.answerHint(searchResult(.move, move: "b1b2", game: apparatus.game))
        #expect(apparatus.motion.suggested == point("b2"), "and the suggestion arrives")
    }

    // MARK: - What it thinks with

    @Test("A human-versus-AI hint thinks the time the game itself froze",
          arguments: [(AiLevel.fast, UInt32(1000)), (.standard, 3000), (.deep, 5000)])
    func theHintTakesTheGamesOwnFrozenTime(_ level: AiLevel, _ movetime: UInt32) throws {
        // A Settings default deliberately unlike the game's, so a hint that read
        // the preference instead of the game would be visible here.
        let apparatus = try makeApparatus(humanVersusAI(level: level),
                                          settingsLevel: level == .fast ? .deep : .fast)
        apparatus.engine.markReady(for: .miniXiangqi)

        apparatus.hint.request()

        #expect(apparatus.engine.startedHintSearches == 1)
        #expect(apparatus.engine.lastHintMovetime == movetime,
                """
                a Deep game gives deeper hints, and the hint is never a different \
                opponent from the one playing
                """)
    }

    @Test("A Free Play hint thinks the Settings default level's time",
          arguments: [(AiLevel.fast, UInt32(1000)), (.standard, 3000), (.deep, 5000)])
    func freePlayHintsTakeTheSettingsDefaultLevel(_ level: AiLevel,
                                                  _ movetime: UInt32) throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi),
                                          settingsLevel: level)
        apparatus.engine.markReady(for: .miniXiangqi)

        apparatus.hint.request()

        #expect(apparatus.engine.lastHintMovetime == movetime,
                "the level the player has called theirs, with no new preference row")
    }

    @Test("An unset Settings level is the accepted default, as everywhere else")
    func anAbsentPreferenceIsStandard() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        apparatus.engine.markReady(for: .miniXiangqi)

        apparatus.hint.request()

        #expect(apparatus.engine.lastHintMovetime == 3000, "标准, on a new installation")
    }

    // MARK: - Preparing for one

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

        // A second press while the first is still thinking asks for nothing.
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

        // 取消 puts it away and creates nothing.
        apparatus.hint.dismissPreparationFailure()
        #expect(apparatus.hint.preparationFailure == nil)

        // Every retry obtains a fresh probe, which is the whole point of retrying.
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

    // MARK: - What it shows

    @Test("A suggestion is the board's own selection plus one strengthened destination")
    func theSuggestionIsDrawnInTheBoardsOwnLanguage() throws {
        let apparatus = try makeApparatus(humanVersusAI())
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.hint.request()

        apparatus.engine.answerHint(searchResult(.move, move: "b1b4", game: apparatus.game))

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

        // Tapping it commits through the ordinary input path, and the
        // suggestion goes with the position it was about.
        apparatus.motion.tap(point("b4"))
        apparatus.animator.completeAll()
        #expect(apparatus.game.moves == ["b1b4"])
        #expect(apparatus.motion.suggested == nil)
        #expect(apparatus.motion.hintEmphasis == 0)
    }

    /// The pending stone standing at the suggested point, which is the whole of
    /// the presentation on a board that places: there is no piece to take up,
    /// and the mark is the game's own — so tapping it plays the move through the
    /// ordinary input path, with nothing knowing the mark came from the engine.
    ///
    /// What this would catch is the presentation going back to the movement
    /// grammar. A hint mechanic that assumes a mover shows nothing at all here,
    /// and it shows nothing *silently*: the control is pressable, the search
    /// runs, the answer arrives, and the board never changes.
    @Test("On a board that places, the suggestion is the pending stone itself")
    func aPlacementSuggestionIsThePendingStone() throws {
        let apparatus = try makeApparatus(.freePlay(game: .gomoku15))
        let suggested = Square("h8", on: GameKind.gomoku15.board)!
        apparatus.engine.markReady(for: .gomoku15)
        apparatus.hint.request()

        apparatus.engine.answerHint(searchResult(.move, move: "h8", game: apparatus.game))

        #expect(apparatus.game.selected == suggested,
                "the mark is the game's own pending state, not a second mechanism")
        #expect(apparatus.motion.suggested == suggested)
        #expect(apparatus.motion.hintEmphasis == 1)
        #expect(apparatus.game.placement[suggested] == nil,
                "and nothing is committed by showing it")
        apparatus.animator.completeAll()

        // Tapping the mark plays it, through the ordinary apply — the same tap
        // that commits a mark the player raised themselves.
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

        apparatus.engine.answerHint(searchResult(.move, move: "b1b4", game: apparatus.game))

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
        apparatus.engine.answerHint(searchResult(.move, move: "b1b4", game: apparatus.game))
        #expect(apparatus.motion.suggested == point("b4"))

        // Taking up another piece of the player's own.
        apparatus.motion.tap(point("a1"))
        #expect(apparatus.game.selected == point("a1"))
        #expect(apparatus.motion.suggested == nil)
        #expect(apparatus.motion.hintEmphasis == 0)

        // And a tap outside the board, over a suggestion shown again.
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
        apparatus.engine.answerHint(searchResult(.move, move: "b1b4", game: apparatus.game))
        apparatus.motion.cancelSelection()

        apparatus.hint.request()

        #expect(apparatus.engine.startedHintSearches == 1,
                "an unchanged position is not thought about twice")
        #expect(apparatus.motion.suggested == point("b4"), "and the answer is back")

        // The cache dies with the position — and the move that kills it is the
        // suggestion itself, played by tapping the point it is shown on.
        apparatus.motion.tap(point("b4"))
        apparatus.animator.completeAll()
        #expect(apparatus.game.moves == ["b1b4"])

        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 2,
                "a position the game has left has no answer to reuse")
    }

    @Test("An answer from another position or another game shows nothing")
    func aStaleAnswerShowsNothing() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        apparatus.engine.markReady(for: .miniXiangqi)

        apparatus.hint.request()
        apparatus.engine.answerHint(
            searchResult(.move, move: "b1b4", game: apparatus.game,
                         revision: apparatus.game.evaluation.positionRevision + 1))
        #expect(apparatus.motion.suggested == nil, "a revision the position has left behind")

        apparatus.hint.request()
        apparatus.engine.answerHint(
            searchResult(.move, move: "b1b4", game: apparatus.game, ticket: 2,
                         identity: "00000000-0000-7000-8000-000000000000"))
        #expect(apparatus.motion.suggested == nil, "and an identity that is not this game's")

        // Neither was cached, so the next request is a real search.
        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 3)
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

        apparatus.engine.answerHint(searchResult(.move, move: "b1b4", game: apparatus.game))
        #expect(apparatus.hint.activity == .idle, "the indicator is gone with the answer")
    }

    // MARK: - Everything that takes it away

    @Test("The player's own commit cancels the hint before the reply is asked for")
    func theCommitCancelsTheHintBeforeTheReply() throws {
        // Driven through PlayState rather than through the apparatus, because
        // the ordering is a property of the wiring the application ships:
        // asserted against the fixture's own copy of that wiring, this stays
        // green with the production cancel deleted, which is the one thing it
        // exists to catch. So the game is created the way 开始对局 creates one,
        // and the move is played on the board that creation put up.
        let core = try TestCores.fresh()
        let engine = TestEngine()
        let state = PlayState(core: core, engine: engine)
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
        apparatus.engine.answerHint(searchResult(.move, move: "a6a5", game: apparatus.game))
        #expect(apparatus.motion.suggested == point("a5"))

        // Exactly what the screen does: the control cancels the hint and runs
        // the transition.
        apparatus.hint.cancel()
        apparatus.motion.undo()
        apparatus.animator.completeAll()

        #expect(apparatus.game.moves.isEmpty)
        #expect(apparatus.motion.suggested == nil)
        #expect(apparatus.engine.cancelledTickets.isEmpty,
                "the search had already answered; there was nothing left to cancel")

        // The suggestion is not reused on the position the Undo arrived at.
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

        // What the suspension handler calls, in the order it calls it: the hint
        // first, then the opponent's own cancel-and-release.
        apparatus.hint.cancel()
        apparatus.opponent.suspend()

        #expect(apparatus.engine.cancelledTickets == [1])
        #expect(apparatus.engine.cancelAlls == 1)
        #expect(apparatus.engine.teardowns == 1, "the table is released whole")
        #expect(apparatus.hint.activity == .idle)
        #expect(apparatus.motion.suggested == nil)

        // A late answer to the cancelled search shows nothing.
        apparatus.engine.answerHint(searchResult(.move, move: "b1b4", game: apparatus.game))
        #expect(apparatus.motion.suggested == nil)
    }

    @Test("Memory pressure puts a running hint down with the table it was thinking on")
    func memoryPressurePutsTheHintDown() throws {
        let apparatus = try makeApparatus(.freePlay(game: .miniXiangqi))
        apparatus.engine.markReady(for: .miniXiangqi)
        apparatus.hint.request()
        apparatus.clock.advance(by: Motion.thinkingIndicatorDelay + 0.1)
        #expect(apparatus.hint.activity == .thinking)

        // What the memory-pressure handler calls, in the order it calls it —
        // the same order the suspension takes, and for the same reason: the
        // release cancels every search and then tears the table down, and a
        // hint whose own state outlived that would be a suggestion about a
        // board the engine has been taken out from under.
        apparatus.hint.cancel()
        apparatus.opponent.memoryPressure()

        #expect(apparatus.engine.cancelledTickets == [1])
        #expect(apparatus.engine.cancelAlls == 1)
        #expect(apparatus.engine.teardowns == 1, "the table is released whole")
        #expect(apparatus.hint.activity == .idle)
        #expect(apparatus.motion.suggested == nil)

        // A late answer to the cancelled search shows nothing.
        apparatus.engine.answerHint(searchResult(.move, move: "b1b4", game: apparatus.game))
        #expect(apparatus.motion.suggested == nil)

        // And nothing of the hint's outlived the release: the next request
        // finds no engine standing and prepares one, from a fresh probe.
        apparatus.hint.request()
        #expect(apparatus.engine.preparations == 1)
        #expect(apparatus.engine.startedHintSearches == 2)
    }

    @Test("Leaving the board puts the hint down and releases the engine it prepared")
    func leavingTheBoardReleasesAFreePlayEngine() throws {
        let core = try TestCores.fresh()
        let engine = TestEngine()
        let state = PlayState(core: core, engine: engine)
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

    // MARK: - The refusals a cancellation leaves behind

    @Test("A hint refused for a search still retiring is asked again")
    func anOutstandingSearchRefusalIsAskedAgain() throws {
        let apparatus = try makeApparatus(humanVersusAI())
        apparatus.engine.markReady(for: .miniXiangqi)
        // Cancellation is asynchronous: the core can refuse a hint for a search
        // that has already been told to stop, and its own instruction for that
        // is to ask again rather than to expect the next call to be admitted.
        apparatus.engine.hintStartRefusal =
            CoreError(status: MxqStatus(MXQ_ERR_STATE_SEARCH_IN_PROGRESS),
                      detail: "a search is outstanding")

        apparatus.hint.request()
        #expect(apparatus.engine.startedHintSearches == 0, "refused, for now")

        apparatus.clock.advance(by: 0.1)
        #expect(apparatus.engine.startedHintSearches == 1, "and asked again once")

        apparatus.engine.answerHint(searchResult(.move, move: "b1b4", game: apparatus.game))
        #expect(apparatus.motion.suggested == point("b4"))
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
