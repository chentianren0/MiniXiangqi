// The explicit game axis at the board-model boundary.

import Testing
@testable import MiniXiangqi

@Suite("Board model")
@MainActor
struct BoardModelTests {
    @Test("Each game publishes its complete board topology")
    func boardDefinitions() {
        let mini = GameKind.miniXiangqi.board
        #expect(mini.fileCount == 7)
        #expect(mini.rankCount == 7)
        #expect(mini.squareCount == 49)
        #expect(mini.riverAfterRank == nil)
        #expect(mini.palaces == [
            .init(files: 2...4, ranks: 0...2),
            .init(files: 2...4, ranks: 4...6),
        ])

        let xiangqi = GameKind.xiangqi.board
        #expect(xiangqi.fileCount == 9)
        #expect(xiangqi.rankCount == 10)
        #expect(xiangqi.squareCount == 90)
        #expect(xiangqi.riverAfterRank == 4)
        #expect(xiangqi.palaces == [
            .init(files: 3...5, ranks: 0...2),
            .init(files: 3...5, ranks: 7...9),
        ])
    }

    @Test("Coordinates are validated against the explicit game")
    func squareParsing() {
        let mini = GameKind.miniXiangqi.board
        #expect(Square("a1", on: mini)?.name == "a1")
        #expect(Square("g7", on: mini)?.name == "g7")
        #expect(Square("h1", on: mini) == nil)
        #expect(Square("a10", on: mini) == nil)
        #expect(Square("f10", on: mini) == nil)

        let xiangqi = GameKind.xiangqi.board
        #expect(Square("a1", on: xiangqi)?.name == "a1")
        #expect(Square("i10", on: xiangqi)?.name == "i10")
        #expect(Square("j1", on: xiangqi) == nil)
        #expect(Square("a11", on: xiangqi) == nil)
        #expect(Square("a01", on: xiangqi) == nil)
    }

    @Test("Canonical moves span four through six characters")
    func moveParsing() {
        let mini = GameKind.miniXiangqi.board
        #expect(Move(text: "a1g7", on: mini)?.text == "a1g7")
        #expect(Move(text: "a1f10", on: mini) == nil)

        let xiangqi = GameKind.xiangqi.board
        #expect(Move(text: "a1b2", on: xiangqi)?.text == "a1b2")
        #expect(Move(text: "a9a10", on: xiangqi)?.text == "a9a10")
        #expect(Move(text: "a10i10", on: xiangqi)?.text == "a10i10")
    }

    @Test("Xiangqi FEN supplies all seven piece kinds on a 9-by-10 board")
    func xiangqiPlacement() {
        let fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1"
        let placement = Placement(fen: fen, game: .xiangqi)
        #expect(placement.game == .xiangqi)
        #expect(placement.board == GameKind.xiangqi.board)
        #expect(placement[Square("c1", on: placement.board)!]
                == Piece(kind: .elephant, side: .red))
        #expect(placement[Square("d1", on: placement.board)!]
                == Piece(kind: .advisor, side: .red))
        #expect(placement[Square("c10", on: placement.board)!]
                == Piece(kind: .elephant, side: .black))
        #expect(placement[Square("d10", on: placement.board)!]
                == Piece(kind: .advisor, side: .black))
        #expect(placement[Square("i10", on: placement.board)!]
                == Piece(kind: .chariot, side: .black))
    }

    @Test("Advisor and elephant keep side-distinct characters")
    func xiangqiCharacters() {
        #expect(PieceKind.advisor.character(for: .red) == "仕")
        #expect(PieceKind.advisor.character(for: .black) == "士")
        #expect(PieceKind.elephant.character(for: .red) == "相")
        #expect(PieceKind.elephant.character(for: .black) == "象")
    }
}
