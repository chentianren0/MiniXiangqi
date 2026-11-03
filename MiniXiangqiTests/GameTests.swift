import Testing
@testable import MiniXiangqi

@Suite("Finishing a game", .retiringItsCores)
@MainActor
struct GameTests {
    static let mateLine = ["b1b3", "b7b6", "b3d3"]

    static let shuffleLine = ["b1b2", "b7b6", "b2b1", "b6b7",
                              "b1b2", "b7b6", "b2b1", "b6b7"]

    static let checkLine = ["b1b3", "d6d5", "b3d3"]

    static let captureLine = ["d2d3", "d6d5", "d3d4", "d5d4"]

    static let capturingCheckLine = ["c2c3", "a6a5", "c1d3", "c6c5", "d3c5"]

    private func game(playing line: [String] = []) throws -> (game: Game, core: Core) {
        let core = try TestCores.fresh()
        let game = try openGame(on: core)
        try game.replay(line)
        return (game, core)
    }

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
        #expect(game.lastMove == Move(text: "b1b4", on: GameKind.miniXiangqi.board))

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
        #expect(game.evaluation.reason == .threefoldRepetition)
        #expect(!game.canUndo, "the player confirmed this result")

        #expect(game.filedRecordID != nil)
        #expect(try core.historyCount() == 1)
        #expect(try !core.activeGameExists())

        game.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        #expect(game.selected == nil, "a finished game accepts no input")
    }

    @Test("The pinned check line checks without mating")
    func theCheckLineChecks() throws {
        let (game, _) = try game(playing: Self.checkLine)
        #expect(game.evaluation.inCheck)
        #expect(game.evaluation.state == .ongoing, "the general still has d6")
        #expect(game.checkedGeneral == Square("d7", on: GameKind.miniXiangqi.board))
    }

    @Test("The pinned capture line takes the red soldier on d4")
    func theCaptureLineCaptures() throws {
        let (game, _) = try game(playing: Self.captureLine)
        #expect(game.placement[Square("d4", on: GameKind.miniXiangqi.board)!] == Piece(kind: .soldier, side: .black))
        #expect(game.placement[Square("d5", on: GameKind.miniXiangqi.board)!] == nil)
        #expect(game.lastMove == Move(text: "d5d4", on: GameKind.miniXiangqi.board))
        #expect(game.evaluation.state == .ongoing)
    }

    @Test("The pinned capturing-check line takes a piece and gives check at once")
    func theCapturingCheckLineDoesBoth() throws {
        let (game, _) = try game(playing: Self.capturingCheckLine)
        #expect(game.placement[Square("c5", on: GameKind.miniXiangqi.board)!] == Piece(kind: .horse, side: .red),
                "the horse stands where the soldier stood")
        #expect(game.evaluation.inCheck)
        #expect(game.checkedGeneral == Square("d7", on: GameKind.miniXiangqi.board))
        #expect(game.evaluation.state == .ongoing,
                "a check and not a mate: the d6 soldier steps across to c6 and blocks the leg")
    }

    @Test("The pinned line is a checkmate")
    func theMateLineMates() throws {
        let (game, _) = try game(playing: Self.mateLine)

        #expect(game.evaluation.state == .redWins)
        #expect(game.evaluation.reason == .checkmate)
        #expect(game.isFinished)
        #expect(game.presentedState == .redWins)
    }

    @Test("An illegal move is refused by the core and leaves the game unchanged")
    func anIllegalMoveIsRefused() throws {
        let core = try TestCores.fresh()
        let game = try openGame(on: core)
        try game.replay(["b1b4"])
        let before = game.evaluation

        #expect(throws: CoreError.self) { try core.apply("a6a3") }
        #expect(try core.moveHistory() == ["b1b4"])
        let after = try core.evaluation()
        #expect(after.fen == before.fen)
        #expect(after.positionRevision == before.positionRevision)
        #expect(after.sideToMove == .black)

        try game.replay(["a6a5"])
        #expect(game.moves == ["b1b4", "a6a5"], "and the game plays on")
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
}
