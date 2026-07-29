// The game that survives the app: created at the first move, committed as it
// is played, resumed exactly where it stood, and filed when a new one starts.
//
// These are the decided Stage 3 semantics from issue #50, each driven through
// Game against the real core — shut down and reopened over the same store
// where a test is about what quitting keeps, because that is what quitting is.
// Nothing asserts a rule; every expectation is the store's or the session's
// own answer read back.

import Testing
@testable import MiniXiangqi

@Suite("The persistent game")
@MainActor
struct GameSessionTests {

    // MARK: - Lazy creation

    @Test("An untouched board persists nothing, and the first move creates the game")
    func theFirstMoveCreatesTheGame() throws {
        let core = try TestCores.fresh()
        let game = try Game(rules: core)

        #expect(try !core.activeGameExists(),
                "opening the app is not starting a game")
        #expect(!core.hasSession, "no session either: there is nothing to attach")

        game.tap(Square("b1")!)
        game.tap(Square("b4")!)

        #expect(game.moves == ["b1b4"])
        #expect(core.hasSession)
        #expect(try core.activeGameExists(),
                "the first move and the game's creation are one action")
    }

    @Test("A move is committed when it is accepted, with no separate save")
    func everyMoveCommits() throws {
        let directory = TestCores.scratchDirectory()
        var core = try TestCores.open(at: directory)
        let game = try Game(rules: core)
        try game.replay(["b1b4", "a6a5"])

        // Quit without warning: no teardown beyond the core's own, exactly as
        // a terminated process would leave the store.
        core = try TestCores.open(at: directory)
        let resumed = try Game(rules: core)
        #expect(resumed.moves == ["b1b4", "a6a5"],
                "both plies were committed as they were played")
    }

    // MARK: - Resume

    @Test("A stored game resumes exactly: position, history, notation, turn")
    func aStoredGameResumesExactly() throws {
        let directory = TestCores.scratchDirectory()
        var core = try TestCores.open(at: directory)
        let played = try Game(rules: core)
        try played.replay(GameTests.captureLine)
        let fen = played.evaluation.fen
        let notation = played.notation
        #expect(notation == ["兵四进一", "卒4进1", "兵四进一", "卒4进1"],
                "the premise: the sitting recorded these words")

        core = try TestCores.open(at: directory)
        let resumed = try Game(rules: core)

        #expect(resumed.moves == GameTests.captureLine)
        #expect(resumed.evaluation.fen == fen, "the position is the same position")
        #expect(resumed.notation == notation,
                "the notation reads back through the same rules that wrote it")
        #expect(resumed.lastMove == Move(text: "d5d4"),
                "the brackets mark the move that produced the position")
        #expect(resumed.evaluation.sideToMove == .red)
        #expect(resumed.canUndo, "the resumed game is the same game to play on")
        #expect(!resumed.flipped,
                "orientation is the sitting's, not the game's: a fresh launch opens red-at-bottom")
    }

    @Test("With nothing stored, launch is the empty board and creates nothing")
    func absenceIsTheEmptyBoard() throws {
        let core = try TestCores.fresh()
        let game = try Game(rules: core)

        #expect(game.moves.isEmpty)
        #expect(game.notation.isEmpty)
        #expect(!game.isFinished)
        #expect(!core.hasSession, "absence resumes no session")
        #expect(try !core.activeGameExists(), "and creates none")
    }

    @Test("An unconfirmed mate resumes finished, still undoable, and Undo resumes play")
    func anUnconfirmedResultResumesFinished() throws {
        let directory = TestCores.scratchDirectory()
        var core = try TestCores.open(at: directory)
        let mated = try Game(rules: core)
        try mated.replay(GameTests.mateLine)
        #expect(mated.isFinished)

        core = try TestCores.open(at: directory)
        let resumed = try Game(rules: core)

        #expect(resumed.isFinished, "the unconfirmed result is the game's state")
        #expect(resumed.presentedState == .redWins)
        #expect(resumed.evaluation.reason == .checkmate)
        #expect(resumed.canUndo,
                "unconfirmed is unconfirmed across a relaunch: the core still offers Undo")

        resumed.undo()
        #expect(resumed.failure == nil, "the core accepted the undo")
        #expect(!resumed.isFinished, "and the game is running again")
        #expect(resumed.moves == ["b1b3", "b7b6"])
    }

    // MARK: - Filing

    @Test("Starting anew confirms the natural result into History and the next move creates fresh")
    func filingConfirmsTheResult() throws {
        let core = try TestCores.fresh()
        let game = try Game(rules: core)
        try game.replay(GameTests.mateLine)

        try game.file()
        #expect(game.filedRecordID != nil)
        #expect(try core.historyCount() == 1, "the finished game is a History record")
        #expect(try !core.activeGameExists(), "and no longer the active game")

        // The screen then releases the session and opens the empty board;
        // the next first move begins a game of its own.
        core.endSession()
        let next = try Game(rules: core)
        #expect(next.moves.isEmpty)
        next.tap(Square("b1")!)
        next.tap(Square("b4")!)
        #expect(try core.activeGameExists())
        #expect(try core.historyCount() == 1, "playing on files nothing further")
    }

    @Test("A claimed draw needs no filing: the claim already was one")
    func aClaimedDrawIsAlreadyFiled() throws {
        let core = try TestCores.fresh()
        let game = try Game(rules: core)
        try game.replay(GameTests.shuffleLine)

        game.claimDraw()
        #expect(game.claimedDraw)
        #expect(try core.historyCount() == 1)

        try game.file()
        #expect(try core.historyCount() == 1,
                "filing a claimed draw commits nothing twice")
    }

    // MARK: - Refusals

    @Test("A refused first move leaves no game the next launch resumes as played")
    func aRefusedFirstMoveIsOneRefusedAction() throws {
        let rules = RefusingRules(try TestCores.fresh(), refuses: true)
        let game = try Game(rules: rules)

        game.tap(Square("b1")!)
        game.tap(Square("b4")!)

        #expect(game.failure != nil, "creation and the first move refuse as one action")
        #expect(game.moves.isEmpty, "the move did not happen")
        #expect(game.notation.isEmpty)

        rules.refuses = false
        game.tap(Square("b4")!)
        #expect(game.failure == nil, "the retry is the same first move")
        #expect(game.moves == ["b1b4"])
    }

    @Test("A refused claim leaves the game running, claimable, and unfiled")
    func aRefusedClaimChangesNothing() throws {
        let rules = RefusingRules(try TestCores.fresh())
        let game = try Game(rules: rules)
        try game.replay(GameTests.shuffleLine)

        rules.refuses = true
        game.claimDraw()

        #expect(!game.claimedDraw, "a claim the store refused did not end the game")
        #expect(game.filingFailure != nil, "and the refusal is recorded for the retry")
        #expect(!game.isFinished)
        #expect(game.evaluation.claimAvailable, "the claim still stands to take")

        rules.refuses = false
        game.claimDraw()
        #expect(game.claimedDraw, "the retry is the ordinary claim")
        #expect(game.filingFailure == nil)
    }

    @Test("A refused filing leaves the finished game active to resume")
    func aRefusedFilingChangesNothing() throws {
        let rules = RefusingRules(try TestCores.fresh())
        let game = try Game(rules: rules)
        try game.replay(GameTests.mateLine)

        rules.refuses = true
        #expect(throws: CoreError.self) { try game.file() }
        #expect(game.filingFailure != nil)
        #expect(game.isFinished, "the game is exactly as it stood: finished, unfiled")
        #expect(game.filedRecordID == nil)

        rules.refuses = false
        try game.file()
        #expect(game.filedRecordID != nil, "the retry files it")
    }
}
