// Finishing a game: taking a move back, claiming the draw, and being mated.
//
// Every expectation here is the core's answer read back through the game, not
// a rule restated in Swift. The two hardcoded lines below are what the core
// itself produced when it was driven mechanically from the frozen start
// position, and pinning them is the point: a line that stops being a checkmate,
// or a shuffle that stops repeating, is a change in the core that the app must
// hear about.
//
// Each test plays on the real core over a scratch store of its own — the same
// sessions the app commits through, pointed somewhere disposable.

import Testing
@testable import MiniXiangqi

@Suite("Finishing a game")
@MainActor
struct GameTests {

    /// The shortest checkmate available from the start position: Red's cannon
    /// reaches the general's file, screened by Black's own soldier, and Black's
    /// general is walled in by its own horses.
    static let mateLine = ["b1b3", "b7b6", "b3d3"]

    /// The start position a third time. Both cannons step out and back twice,
    /// which is the shortest repetition this ruleset offers from the start.
    static let shuffleLine = ["b1b2", "b7b6", "b2b1", "b6b7",
                              "b1b2", "b7b6", "b2b1", "b6b7"]

    /// A check that is only a check: the cannon reaches the general's file
    /// behind the soldier Black advanced, and the vacated d6 is the escape.
    static let checkLine = ["b1b3", "d6d5", "b3d3"]

    /// The quickest capture: the soldiers meet on the d-file and Black takes.
    static let captureLine = ["d2d3", "d6d5", "d3d4", "d5d4"]

    /// A capture that is also a check, which the board has to sound as one
    /// event rather than two: Red's soldier steps off c2 to free the horse, the
    /// horse comes to d3, and when Black's c-file soldier advances the horse
    /// takes it on c5 — arriving at the one point from which it attacks d7,
    /// through the leg the soldier itself has just vacated.
    static let capturingCheckLine = ["c2c3", "a6a5", "c1d3", "c6c5", "d3c5"]

    private func game(playing line: [String] = []) throws -> (game: Game, core: Core) {
        let core = try TestCores.fresh()
        let game = try Game(rules: core)
        try game.replay(line)
        return (game, core)
    }

    // MARK: - Undo

    @Test("Undo removes exactly one ply and nothing else")
    func undoRemovesOnePly() throws {
        let (game, core) = try game(playing: ["b1b4", "a6a5"])
        game.undo()

        #expect(game.notation.count == 1)
        #expect(game.notation.map(\.traditional) == ["炮六进三"])
        #expect(game.notation.map(\.wxf) == ["C6+3"],
                "both readings shorten together — a reading is one value")
        #expect(game.moves == ["b1b4"], "the line is the session's own, read back")
        #expect(game.evaluation.sideToMove == .black)
        #expect(game.lastMove == Move(text: "b1b4"))

        // The position is the core's own answer for the shortened history —
        // the session's replay of its whole line — rather than the previous
        // position remembered here.
        #expect(game.evaluation.fen == (try core.fen(atPly: 1)))
        #expect(game.failure == nil)
    }

    @Test("Undo repeats back to the initial position and stops there")
    func undoRepeatsToTheStart() throws {
        let (game, core) = try game(playing: ["b1b4", "a6a5", "b4b6"])
        #expect(game.canUndo)

        game.undo()
        game.undo()
        game.undo()

        #expect(game.moves.isEmpty)
        #expect(game.notation.isEmpty)
        #expect(game.lastMove == nil)
        #expect(game.evaluation.sideToMove == .red)

        #expect(game.evaluation.fen == (try core.fen(atPly: 0)))
        #expect(!game.canUndo, "there is nothing left to take back")
    }

    // MARK: - The claimable draw

    @Test("The start position a third time offers the claim, and claiming it ends the game")
    func theShuffleReachesAClaimableDraw() throws {
        let (game, core) = try game(playing: Self.shuffleLine)

        #expect(game.evaluation.claimAvailable)
        #expect(game.evaluation.state == .claimableDraw)
        #expect(game.evaluation.reason == .threefoldRepetition)
        #expect(!game.isFinished, "a claimable repetition is still an ongoing game")

        game.claimDraw()

        #expect(game.claimedDraw)
        #expect(game.isFinished)
        #expect(game.presentedState == .draw)
        // The reason needs no override: the one the core reports is the one the
        // claim was available for.
        #expect(game.evaluation.reason == .threefoldRepetition)
        #expect(!game.canUndo, "the player confirmed this result")

        // The claim was the terminal commit: the game is in History and no
        // active game remains — quitting here would resume nothing.
        #expect(game.filedRecordID != nil)
        #expect(try core.historyCount() == 1)
        #expect(try !core.activeGameExists())

        game.tap(Square("b1")!)
        #expect(game.selected == nil, "a finished game accepts no input")
    }

    // MARK: - Check and capture, pinned for the motion evidence

    @Test("The pinned check line checks without mating")
    func theCheckLineChecks() throws {
        let (game, _) = try game(playing: Self.checkLine)
        #expect(game.evaluation.inCheck)
        #expect(game.evaluation.state == .ongoing, "the general still has d6")
        #expect(game.checkedGeneral == Square("d7"))
    }

    @Test("The pinned capture line takes the red soldier on d4")
    func theCaptureLineCaptures() throws {
        let (game, _) = try game(playing: Self.captureLine)
        #expect(game.placement[Square("d4")!] == Piece(kind: .soldier, side: .black))
        #expect(game.placement[Square("d5")!] == nil)
        #expect(game.lastMove == Move(text: "d5d4"))
        #expect(game.evaluation.state == .ongoing)
    }

    @Test("The pinned capturing-check line takes a piece and gives check at once")
    func theCapturingCheckLineDoesBoth() throws {
        let (game, _) = try game(playing: Self.capturingCheckLine)
        #expect(game.placement[Square("c5")!] == Piece(kind: .horse, side: .red),
                "the horse stands where the soldier stood")
        #expect(game.evaluation.inCheck)
        #expect(game.checkedGeneral == Square("d7"))
        #expect(game.evaluation.state == .ongoing,
                "a check and not a mate: the d6 soldier steps across to c6 and blocks the leg")
    }

    // MARK: - Checkmate

    @Test("The pinned line is a checkmate")
    func theMateLineMates() throws {
        let (game, _) = try game(playing: Self.mateLine)

        #expect(game.evaluation.state == .redWins)
        #expect(game.evaluation.reason == .checkmate)
        #expect(game.isFinished)
        #expect(game.presentedState == .redWins)
    }

    @Test("A natural result stays undoable, and Undo resumes the game")
    func undoResumesAfterANaturalResult() throws {
        let (game, _) = try game(playing: Self.mateLine)
        #expect(game.canUndo, "a natural result is undoable while it is unconfirmed")

        game.undo()

        #expect(game.evaluation.state == .ongoing)
        #expect(!game.isFinished)
        #expect(game.notation.count == 2)
        #expect(game.evaluation.sideToMove == .red)
    }

    // MARK: - A failure describes the last attempt

    @Test("A refused action leaves the game unchanged, and trying again works")
    func aFailureClearsOnTheNextAttempt() throws {
        let rules = RefusingRules(try TestCores.fresh())
        let game = try Game(rules: rules)
        try game.replay(["b1b4", "a6a5"])

        rules.refuses = true
        game.undo()
        #expect(game.failure != nil, "the refused Undo records its failure")
        #expect(game.notation.count == 2, "an Undo the core refused did not happen")
        #expect(game.canUndo, "a failed attempt does not take the control away — the contract says the user may simply try again")

        rules.refuses = false
        game.undo()
        #expect(game.failure == nil, "a new attempt starts clean")
        #expect(game.notation.count == 1, "the retry is an ordinary Undo")

        rules.refuses = true
        game.tap(Square(file: 0, rank: 5))
        game.tap(Square(file: 0, rank: 4))
        #expect(game.failure != nil, "the refused move records its failure")
        #expect(game.notation.count == 1, "a move the core refused did not happen")

        rules.refuses = false
        game.tap(Square(file: 0, rank: 4))
        #expect(game.failure == nil, "the retried move plays clean")
        #expect(game.notation.count == 2)
    }
}
