// The Play home: what its card says, and what choosing a mode does over a game.
//
// docs/interaction-design.md, "Saving the active game before choosing a new
// mode": the destination shows the active game's metadata and a direct Resume,
// both mode entries stay interactive while a game exists, and selecting one
// presents the one fixed confirmation. 保存并继续 archives the game by its own
// current state before the selected mode's pre-start page opens; a refusal keeps
// the game exactly as it stood and offers the accepted retry; 取消 discards the
// remembered destination and changes nothing.
//
// The metadata assertions are about **composition** — which facts appear, in
// what order, joined by the accepted format — rather than about the words. The
// words are docs/copy.md's, and they are asserted against the catalog in
// CopyTests and photographed in both languages by the UI suite. Composing the
// expectation from the same catalog is what keeps this suite honest about which
// of the two it is testing.

import Foundation
import Testing
@testable import MiniXiangqi

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

@Suite("The Play home")
@MainActor
struct PlayHomeTests {

    /// The start position a third time, which is what makes the draw claimable.
    private static let shuffleLine = ["b1b2", "b7b6", "b2b1", "b6b7",
                                      "b1b2", "b7b6", "b2b1", "b6b7"]

    /// The shortest checkmate from the start position.
    private static let mateLine = ["b1b3", "b7b6", "b3d3"]

    // MARK: - What the card says

    @Test("An ongoing game reads as its mode, that it is going, and whose turn it is")
    func anOngoingGameReadsAsItsTurn() throws {
        let core = try TestCores.fresh()
        let game = try openGame(on: core)

        #expect(game.metadataLine == joined(text("mode.freePlay"),
                                            text("metadata.inProgress"),
                                            text("status.redToMove"),
                                            moves(0)))

        try game.replay(["b1b3"])
        #expect(game.metadataLine == joined(text("mode.freePlay"),
                                            text("metadata.inProgress"),
                                            text("status.blackToMove"),
                                            moves(1)),
                "the side to move and the count are the game's own, read after every ply")
    }

    @Test("A human-versus-AI game names the side the player is holding")
    func aHumanVersusAIGameNamesTheHumanSide() throws {
        let core = try TestCores.fresh()
        try core.create(.humanVersusAI(humanSide: .red, level: .standard,
                                       choice: .humanFirst))
        let red = try Game(rules: core)
        #expect(red.metadataLine == joined(text("mode.humanVersusAI"),
                                           text("metadata.youRed"),
                                           text("metadata.inProgress"),
                                           text("status.redToMove"),
                                           moves(0)))

        let other = try TestCores.fresh()
        try other.create(.humanVersusAI(humanSide: .black, level: .fast,
                                        choice: .aiFirst))
        let black = try Game(rules: other)
        #expect(black.metadataLine == joined(text("mode.humanVersusAI"),
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

        #expect(game.metadataLine == joined(text("mode.freePlay"),
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

        #expect(game.metadataLine == joined(text("mode.freePlay"),
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

        state.choose(.freePlay)

        #expect(state.page == .setup(.freePlay))
        #expect(state.modeSwitch == nil, "nothing to confirm with no game to keep")
    }

    @Test("With a game a mode entry confirms instead of navigating")
    func aModeEntryWithAGameConfirms() throws {
        let core = try TestCores.fresh()
        let state = PlayState(core: core)
        try core.create(.freePlay)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .board, "a launch with a game to resume opens at the board")

        state.leaveTopPage()
        #expect(state.page == .home)
        #expect(state.activeGame != nil, "leaving the board leaves the game running")

        state.choose(.humanVersusAI)

        #expect(state.modeSwitch == .confirming(.humanVersusAI))
        #expect(state.page == .home, "the confirmation stands between the press and the page")
        #expect(state.activeGame != nil, "and nothing has happened to the game yet")
    }

    @Test("取消 discards the remembered destination and changes nothing")
    func cancellingDiscardsTheDestination() throws {
        let core = try TestCores.fresh()
        let state = try stateOverAGame(core)
        state.choose(.humanVersusAI)
        #expect(state.modeSwitch != nil)

        state.dismissConfirmation()

        #expect(state.modeSwitch == nil, "the destination lives no longer than the flow")
        #expect(state.page == .home)
        #expect(state.activeGame != nil)
        #expect(try core.activeGameExists())
        #expect(try core.historyCount() == 0, "cancelling files nothing")
    }

    @Test("保存并继续 files the game as ended early and opens the chosen mode")
    func saveAndContinueFilesTheGameAndOpensTheMode() async throws {
        let core = try TestCores.fresh()
        let state = try stateOverAGame(core)
        try state.game?.replay(["b1b3", "b7b6"])

        state.choose(.humanVersusAI)
        state.saveAndContinue()
        await settle("the archive to commit") { state.modeSwitch == nil }

        #expect(state.page == .setup(.humanVersusAI), "the selected mode's pre-start page")
        #expect(state.game == nil, "the game it archived is let go of")
        #expect(try !core.activeGameExists(), "and the active game is cleared")

        let records = try core.history.all().records
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.outcome == .none, "an ongoing game keeps no competitive result")
        #expect(record.reason == .endedEarly, "it is recorded as ended early")
        #expect(record.mode == .freePlay, "the game that was filed is the one that was going")
        #expect(record.moveCount == 2)
    }

    @Test("An unconfirmed natural result keeps its own result when it is filed this way")
    func aTerminalGameKeepsItsResult() async throws {
        let core = try TestCores.fresh()
        let state = try stateOverAGame(core)
        try state.game?.replay(Self.mateLine)

        state.choose(.freePlay)
        state.saveAndContinue()
        await settle("the archive to commit") { state.modeSwitch == nil }

        let record = try #require(try core.history.all().records.first)
        #expect(record.outcome == .redWins, "the classification is the core's, not the app's")
        #expect(record.reason == .checkmate)
    }

    @Test("A refused archive keeps the game and offers the accepted retry")
    func aRefusedArchiveKeepsTheGame() async throws {
        let core = try TestCores.fresh()
        let refusing = RefusingRules(core, refuses: true)
        let state = PlayState(core: core, rules: refusing)
        try core.create(.freePlay)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        state.leaveTopPage()

        state.choose(.humanVersusAI)
        state.saveAndContinue()
        await settle("the refusal") { state.modeSwitch == .failed(.humanVersusAI) }

        #expect(state.page == .home, "the pre-start page did not open")
        #expect(state.activeGame != nil, "the game is still here")
        #expect(try core.activeGameExists(), "and still the store's active game")
        #expect(try core.historyCount() == 0, "nothing was filed")

        // 重试 repeats the same atomic operation rather than something near it.
        refusing.refuses = false
        state.saveAndContinue()
        await settle("the retry to commit") { state.modeSwitch == nil }

        #expect(state.page == .setup(.humanVersusAI), "the destination survived the retry flow")
        #expect(try !core.activeGameExists())
        #expect(try core.historyCount() == 1)
    }

    @Test("取消 on the refusal discards the destination and leaves the game")
    func cancellingTheRefusalDiscardsTheDestination() async throws {
        let core = try TestCores.fresh()
        let refusing = RefusingRules(core, refuses: true)
        let state = PlayState(core: core, rules: refusing)
        try core.create(.freePlay)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        state.leaveTopPage()

        state.choose(.freePlay)
        state.saveAndContinue()
        await settle("the refusal") { state.modeSwitch == .failed(.freePlay) }

        state.dismissArchiveFailure()

        #expect(state.modeSwitch == nil)
        #expect(state.page == .home)
        #expect(try core.activeGameExists(), "the game the retry was about is still active")
        #expect(try core.historyCount() == 0)
    }

    // MARK: - Resuming, and the game that is no longer active

    @Test("回到对局 opens the board on the game that was left")
    func resumeOpensTheBoard() throws {
        let core = try TestCores.fresh()
        let state = try stateOverAGame(core)
        try state.game?.replay(["b1b3"])

        state.resume()

        #expect(state.page == .board)
        #expect(state.game?.moves == ["b1b3"], "the same game, exactly where it was left")
    }

    @Test("A filed game is not an active game, and the home does not offer it")
    func aFiledGameIsNotOffered() throws {
        let core = try TestCores.fresh()
        let state = PlayState(core: core)
        try core.create(.freePlay)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .board)
        try state.game?.replay(Self.mateLine)
        try state.game?.file()
        #expect(state.game != nil, "the board still stands at the result it reached")

        #expect(state.activeGame == nil, "but the store's active game is gone")

        // Going back to the home lets it go, and a mode entry then opens its
        // pre-start page with no confirmation: there is nothing left to save.
        state.leaveTopPage()
        #expect(state.page == .home)
        #expect(state.game == nil)
        state.choose(.freePlay)
        #expect(state.modeSwitch == nil)
        #expect(state.page == .setup(.freePlay))
        #expect(try core.historyCount() == 1, "and the game it filed is filed once")
    }

    // MARK: -

    /// A state holding an active Free Play game, sitting on the home — which is
    /// what a player who walked back from the board has.
    private func stateOverAGame(_ core: Core) throws -> PlayState {
        let state = PlayState(core: core)
        try core.create(.freePlay)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        state.leaveTopPage()
        #expect(state.page == .home)
        return state
    }
}
