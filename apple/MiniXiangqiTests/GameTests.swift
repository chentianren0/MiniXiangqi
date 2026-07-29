// Finishing a game: taking a move back, claiming the draw, and being mated.
//
// Every expectation here is the core's answer read back through the game, not
// a rule restated in Swift. The two hardcoded lines below are what the core
// itself produced when it was driven mechanically from the frozen start
// position, and pinning them is the point: a line that stops being a checkmate,
// or a shuffle that stops repeating, is a change in the core that the app must
// hear about.

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

    private func game(playing line: [String] = []) throws -> Game {
        let game = try Game(core: Core.shared.get())
        try game.replay(line)
        return game
    }

    // MARK: - Undo

    @Test("Undo removes exactly one ply and nothing else")
    func undoRemovesOnePly() throws {
        let game = try game(playing: ["b1b4", "a6a5"])
        game.undo()

        #expect(game.notation.count == 1)
        #expect(game.notation == ["炮六进三"])
        #expect(game.evaluation.sideToMove == .black)
        #expect(game.lastMove == Move(text: "b1b4"))

        // The position is the core's own answer for the shortened history,
        // rather than the previous position remembered here.
        let fresh = try Core.shared.get().evaluate(from: Core.startFEN, moves: ["b1b4"])
        #expect(game.evaluation.fen == fresh.fen)
        #expect(game.failure == nil)
    }

    @Test("Undo repeats back to the initial position and stops there")
    func undoRepeatsToTheStart() throws {
        let game = try game(playing: ["b1b4", "a6a5", "b4b6"])
        #expect(game.canUndo)

        game.undo()
        game.undo()
        game.undo()

        #expect(game.moves.isEmpty)
        #expect(game.notation.isEmpty)
        #expect(game.lastMove == nil)
        #expect(game.evaluation.sideToMove == .red)

        let initial = try Core.shared.get().evaluate(from: Core.startFEN, moves: [])
        #expect(game.evaluation.fen == initial.fen)
        #expect(!game.canUndo, "there is nothing left to take back")
    }

    // MARK: - The claimable draw

    @Test("The start position a third time offers the claim, and claiming it ends the game")
    func theShuffleReachesAClaimableDraw() throws {
        let game = try game(playing: Self.shuffleLine)

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

        game.tap(Square("b1")!)
        #expect(game.selected == nil, "a finished game accepts no input")
    }

    // MARK: - Check and capture, pinned for the motion evidence

    @Test("The pinned check line checks without mating")
    func theCheckLineChecks() throws {
        let game = try game(playing: Self.checkLine)
        #expect(game.evaluation.inCheck)
        #expect(game.evaluation.state == .ongoing, "the general still has d6")
        #expect(game.checkedGeneral == Square("d7"))
    }

    @Test("The pinned capture line takes the red soldier on d4")
    func theCaptureLineCaptures() throws {
        let game = try game(playing: Self.captureLine)
        #expect(game.placement[Square("d4")!] == Piece(kind: .soldier, side: .black))
        #expect(game.placement[Square("d5")!] == nil)
        #expect(game.lastMove == Move(text: "d5d4"))
        #expect(game.evaluation.state == .ongoing)
    }

    // MARK: - Checkmate

    @Test("The pinned line is a checkmate")
    func theMateLineMates() throws {
        let game = try game(playing: Self.mateLine)

        #expect(game.evaluation.state == .redWins)
        #expect(game.evaluation.reason == .checkmate)
        #expect(game.isFinished)
        #expect(game.presentedState == .redWins)
    }

    @Test("A natural result stays undoable, and Undo resumes the game")
    func undoResumesAfterANaturalResult() throws {
        let game = try game(playing: Self.mateLine)
        #expect(game.canUndo, "a natural result is undoable while it is unconfirmed")

        game.undo()

        #expect(game.evaluation.state == .ongoing)
        #expect(!game.isFinished)
        #expect(game.notation.count == 2)
        #expect(game.evaluation.sideToMove == .red)
    }
}
