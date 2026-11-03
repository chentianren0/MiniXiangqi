import CoreGraphics
import Testing
@testable import MiniXiangqi

@Suite("The placement games' board")
@MainActor
struct PlacementBoardTests {
    @Test("A fitted placement board's block fits the space it was given",
          arguments: [CGSize(width: 402, height: 874),   // iPhone, stacked
                      CGSize(width: 834, height: 1210),  // iPad portrait
                      CGSize(width: 320, height: 620)])  // barely enough
    func fittedBlocksFitBothWays(size: CGSize) throws {
        let board = GameKind.gomoku15.board
        let fitted = try #require(BoardGeometry.fitting(size, board: board))
        #expect(fitted.blockSize.width <= size.width)
        #expect(fitted.blockSize.height <= size.height)
        let larger = BoardGeometry(board: board, pitch: fitted.pitch + 1)
        #expect(larger.blockSize.width > size.width
                || larger.blockSize.height > size.height
                || fitted.pitch == BoardGeometry.maximumPitch(for: board))
    }

    @Test("A stone and a forbidden cross are contained by their own cells")
    func bodiesStayInsideTheirCells() {
        for pitch in [CGFloat(20), 33, 47] {
            let geometry = BoardGeometry(board: GameKind.renju.board, pitch: pitch)
            #expect(geometry.stoneDiameter / 2 <= geometry.markerOuterLimit)
            let reach = geometry.forbiddenArm * 2.0.squareRoot()
                + geometry.forbiddenStroke / 2
            #expect(reach < geometry.markerOuterLimit)
        }
    }

    @Test("The placement FEN's letter is a stone and its case is the side")
    func stonesParseFromTheFEN() throws {
        let start = frozenStart(.gomoku15)
        let empty = Placement(fen: start, game: .gomoku15)
        #expect(start.split(separator: " ").first?.contains("15") == true,
                "the empty board is written as fifteen two-digit runs")
        #expect((0..<225).allSatisfy {
            empty[Square(file: $0 % 15, rank: $0 / 15)] == nil
        }, "the placement games open on an empty board")
        let far = Placement(fen: "14S/15/15/15/15/15/15/15/15/15/15/15/15/15/15 b - - 0 1",
                            game: .gomoku15)
        #expect(far[Square(file: 14, rank: 14)] == .stone(.red))

        let played = Placement(fen: "15/15/15/15/15/15/7s7/7S7/15/15/15/15/15/15/15 b - - 0 2",
                               game: .gomoku15)
        let first = try #require(played[Square(file: 7, rank: 7)])
        let second = try #require(played[Square(file: 7, rank: 8)])
        #expect(first.side == .red, "uppercase is the side that moves first")
        #expect(first.isStone)
        #expect(second.side == .black)
        #expect(second.isStone)
        #expect(first.kind == nil, "a stone carries no kind and therefore no symbol")
    }

    @Test("A placement move is one square, and reads as its coordinate")
    func placementMoveGrammarAndReading() throws {
        let board = GameKind.renju.board
        let move = try #require(Move(text: "h8", on: board))
        #expect(move.from == nil)
        #expect(move.to == Square(file: 7, rank: 7))
        #expect(move.text == "h8")

        #expect(Move(text: "o15", on: board)?.to == Square(file: 14, rank: 14))
        #expect(Move(text: "h8h9", on: board) == nil, "two squares are not a placement")
        #expect(Move(text: "p8", on: board) == nil, "the board stops at o")
        #expect(Move(text: "h16", on: board) == nil)

        let reading = MoveReading(of: move, in: Placement(fen: frozenStart(.renju),
                                                          game: .renju))
        #expect(reading.traditional == "h8")
        #expect(reading.wxf == "h8")
    }

    @Test("The file letters run a through o with nothing skipped")
    func fileLettersFollowTheCore() {
        let letters = (0..<15).map { Square(file: $0, rank: 0).fileLetter }
        #expect(letters == ["a", "b", "c", "d", "e", "f", "g", "h",
                            "i", "j", "k", "l", "m", "n", "o"])
    }

    private func openingMoves(forbidding forbidden: Set<Square> = [],
                              occupied: Set<Square> = []) -> [Move] {
        (0..<225).map { Square(file: $0 % 15, rank: $0 / 15) }
            .filter { !forbidden.contains($0) && !occupied.contains($0) }
            .map { Move(placing: $0) }
    }

    private func position(occupied: [Square: Side] = [:]) -> Placement {
        var field = Array(repeating: Array(repeating: Character("."), count: 15),
                          count: 15)
        for (square, side) in occupied {
            field[square.rank][square.file] = side == .red ? "S" : "s"
        }
        let ranks = field.reversed().map { row -> String in
            var text = "", run = 0
            for character in row {
                if character == "." { run += 1; continue }
                if run > 0 { text += String(run); run = 0 }
                text.append(character)
            }
            if run > 0 { text += String(run) }
            return text
        }
        return Placement(fen: ranks.joined(separator: "/") + " w - - 0 1", game: .renju)
    }

    @Test("Without confirmation a tap on a legal point plays it")
    func plainTapPlays() {
        let stone = Square(file: 7, rank: 7)
        let forbidden = Square(file: 3, rank: 3)
        let placement = position(occupied: [stone: .black])
        let legal = openingMoves(forbidding: [forbidden], occupied: [stone])

        func effect(_ square: Square, selected: Square? = nil) -> Game.TapEffect {
            Game.effect(ofTapAt: square, in: placement, legalMoves: legal,
                        sideToMove: .red, selected: selected, acceptsInput: true)
        }

        #expect(effect(Square(file: 0, rank: 0)) == .play(Move(placing: Square(file: 0, rank: 0))))
        #expect(effect(stone) == .unavailable, "a point with a stone on it offers nothing")
        #expect(effect(forbidden) == .unavailable, "and neither does one Black may not play")
        #expect(Game.effect(ofTapAt: Square(file: 0, rank: 0), in: placement,
                            legalMoves: legal, sideToMove: .red, selected: nil,
                            acceptsInput: false) == .unavailable,
                "a board waiting on the machine accepts nothing")
    }

    @Test("With confirmation the mark is placed, moved, and committed")
    func pendingStoneStateMachine() {
        let stone = Square(file: 3, rank: 3)
        let placement = position(occupied: [stone: .black])
        let legal = openingMoves(occupied: [stone])
        let first = Square(file: 7, rank: 7)
        let second = Square(file: 8, rank: 8)

        func effect(_ square: Square, selected: Square?) -> Game.TapEffect {
            Game.effect(ofTapAt: square, in: placement, legalMoves: legal,
                        sideToMove: .red, selected: selected, acceptsInput: true,
                        confirmsPlacement: true)
        }

        #expect(effect(first, selected: nil) == .select(first))
        #expect(effect(first, selected: first) == .play(Move(placing: first)))
        #expect(effect(second, selected: first) == .select(second))
        #expect(effect(stone, selected: first) == .unavailable)
    }
}

@Suite("A placement game on the real core", .retiringItsCores)
@MainActor
struct PlacementGameTests {
    static let doubleThreeLine = ["g8", "a1", "i8", "a15", "h7", "o1", "h9", "o15"]

    private func game(_ kind: GameKind, playing line: [String] = []) throws -> Game {
        let core = try TestCores.fresh()
        try core.create(.freePlay(game: kind))
        let game = try Game(core: core)
        try game.replay(line)
        return game
    }

    @Test("A tap places a stone that the position, the line and the list all carry")
    func aStonePlaysThroughTheSession() throws {
        let game = try game(.gomoku15)
        let point = Square(file: 7, rank: 7)
        #expect(game.legalMoves.count == 225, "every point of an empty board is legal")
        #expect(game.effect(ofTapAt: point) == .play(Move(placing: point)))

        game.tap(point)
        #expect(game.moves == ["h8"])
        #expect(game.placement[point] == .stone(.red))
        #expect(game.lastMove == Move(placing: point))
        #expect(game.notation.map(\.traditional) == ["h8"])
        #expect(game.notation.map(\.wxf) == ["h8"])
        #expect(game.evaluation.sideToMove == .black)
        #expect(game.evaluation.inCheck == false, "a placement game has no check")
        #expect(game.failure == nil)

        game.undo()
        #expect(game.moves.isEmpty)
        #expect(game.placement[point] == nil)
        #expect(game.lastMove == nil)
    }

    @Test("Renju's forbidden points are the core's answer, and Black's alone")
    func renjuForbiddenPointsComeFromTheCore() throws {
        let game = try game(.renju, playing: Self.doubleThreeLine)
        let doubleThree = Square(file: 7, rank: 7)
        #expect(game.evaluation.sideToMove == .red, "eight plies leaves Black to move")
        #expect(game.forbiddenPoints.contains(doubleThree))
        #expect(!game.legalMoves.contains { $0.to == doubleThree })
        #expect(game.effect(ofTapAt: doubleThree) == .unavailable,
                "a forbidden point offers nothing, and the board has nothing to draw")

        let free = try game_freestyle()
        #expect(free.forbiddenPoints.isEmpty)
    }

    private func game_freestyle() throws -> Game {
        try game(.gomoku15, playing: PlacementGameTests.doubleThreeLine)
    }

    @Test("Forbidden points are off the board while White is to move")
    func forbiddenPointsAreBlacksAlone() throws {
        let game = try game(.renju, playing: Self.doubleThreeLine + ["b2"])
        #expect(game.evaluation.sideToMove == .black, "now White")
        #expect(game.forbiddenPoints.isEmpty)
    }
}
