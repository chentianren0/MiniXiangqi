// The placement games' own board: what it measures, what a tap on it means,
// and how a move on it reads.
//
// Everything here is about the two things a placement board does differently
// from the boards that came before it — a stone stands on a point instead of a
// piece moving between two, and the edges are lettered instead of numbered. The
// rules are the core's throughout: the tap grammar below is asked of a
// legal-move set handed to it, and nothing in this file knows what a
// five-in-a-row or a double three is.

import CoreGraphics
import Testing
@testable import MiniXiangqi

@Suite("The placement games' board")
@MainActor
struct PlacementBoardTests {

    // MARK: - Geometry

    /// The floor the shared width band gives fifteen files, and the block that
    /// carries the Go-style coordinates around it.
    ///
    /// It would catch a change to the band, to the floor arithmetic, or to the
    /// side strip that left a placement board unable to be drawn at its own
    /// floor — the pitch the owner ratifies the tap targets at.
    @Test("Fifteen files take the derived floor of 20 and the shared ceiling")
    func placementPitchBand() {
        for game in [GameKind.gomoku15, .renju] {
            let board = game.board
            #expect(board.fileCount == 15 && board.rankCount == 15)
            #expect(BoardGeometry.minimumPitch(for: board) == 20)
            #expect(BoardGeometry.maximumPitch(for: board) == 47)

            let floor = BoardGeometry(board: board,
                                      pitch: BoardGeometry.minimumPitch(for: board))
            #expect(floor.coreSize == CGSize(width: 300, height: 300))
            // The block is the core plus one strip on each of two edges, and it
            // is what everything fitting a board asks about.
            #expect(floor.blockSize.width == floor.coreSize.width + floor.stripWidth)
            #expect(floor.blockSize.height == floor.coreSize.height + floor.stripHeight)
        }
    }

    /// A fitted board's whole block fits the space it was fitted into — both
    /// ways, which is what the side strip made a live question.
    ///
    /// It would catch a fitting that sized the pitch from the file count alone
    /// and let the numbers up the side hang off the edge of the screen.
    @Test("A fitted placement board's block fits the space it was given",
          arguments: [CGSize(width: 402, height: 874),   // iPhone, stacked
                      CGSize(width: 834, height: 1210),  // iPad portrait
                      CGSize(width: 320, height: 620)])  // barely enough
    func fittedBlocksFitBothWays(size: CGSize) throws {
        let board = GameKind.gomoku15.board
        let fitted = try #require(BoardGeometry.fitting(size, board: board))
        #expect(fitted.blockSize.width <= size.width)
        #expect(fitted.blockSize.height <= size.height)
        // And it is the largest such pitch: one more would not have fitted.
        let larger = BoardGeometry(board: board, pitch: fitted.pitch + 1)
        #expect(larger.blockSize.width > size.width
                || larger.blockSize.height > size.height
                || fitted.pitch == BoardGeometry.maximumPitch(for: board))
    }

    /// The five star points a 15-line board prints, and that they are part of
    /// the board rather than marks on it.
    ///
    /// It would catch a topology row that lost them, or that put them somewhere
    /// other than the fourth line in and the centre — which is the one thing
    /// about this board a Go player will check first.
    @Test("A 15-line board carries the five conventional star points")
    func starPoints() {
        let expected: Set<Square> = [Square(file: 3, rank: 3), Square(file: 3, rank: 11),
                                     Square(file: 7, rank: 7),
                                     Square(file: 11, rank: 3), Square(file: 11, rank: 11)]
        #expect(Set(GameKind.gomoku15.board.starPoints) == expected)
        #expect(Set(GameKind.renju.board.starPoints) == expected)
        #expect(GameKind.xiangqi.board.starPoints.isEmpty)
        #expect(GameKind.miniXiangqi.board.starPoints.isEmpty)
    }

    /// A stone stays inside its own cell, so two neighbours never overlap, and
    /// the forbidden cross stays inside one too.
    ///
    /// It would catch a stone or a cross grown past the containment rule every
    /// mark on this board is held to.
    @Test("A stone and a forbidden cross are contained by their own cells")
    func bodiesStayInsideTheirCells() {
        for pitch in [CGFloat(20), 33, 47] {
            let geometry = BoardGeometry(board: GameKind.renju.board, pitch: pitch)
            #expect(geometry.stoneDiameter / 2 <= geometry.markerOuterLimit)
            // The cross is drawn on the diagonals, so its reach is the arm
            // times the root of two.
            let reach = geometry.forbiddenArm * 2.0.squareRoot()
                + geometry.forbiddenStroke / 2
            #expect(reach < geometry.markerOuterLimit)
        }
    }

    // MARK: - The board's vocabulary

    /// The core's own placement FEN, read back as stones.
    ///
    /// It would catch a parse that took `S` for a piece letter, or that lost the
    /// case-is-the-side rule and drew both players the same colour — and it
    /// already caught the one this board was the first to reach: **a run of
    /// empty points is a decimal number**, and a parser taking its digits one at
    /// a time reads a whole empty 15-file rank as 1 then 5. Every rank of every
    /// position in these games is then short of nine points and rejected, and
    /// the board draws empty however many stones are on it.
    @Test("The placement FEN's letter is a stone and its case is the side")
    func stonesParseFromTheFEN() {
        let start = Core.startFEN(for: .gomoku15)
        let empty = Placement(fen: start, game: .gomoku15)
        #expect(start.split(separator: " ").first?.contains("15") == true,
                "the empty board is written as fifteen two-digit runs")
        #expect((0..<225).allSatisfy {
            empty[Square(file: $0 % 15, rank: $0 / 15)] == nil
        }, "the placement games open on an empty board")
        // A stone after a two-digit run, which is where the digits have to have
        // been accumulated for the point to land in the right file.
        let far = Placement(fen: "14S/15/15/15/15/15/15/15/15/15/15/15/15/15/15 b - - 0 1",
                            game: .gomoku15)
        #expect(far[Square(file: 14, rank: 14)] == .stone(.red))

        // One stone of each side, on h8 and i9 of a 15-rank field.
        let played = Placement(fen: "15/15/15/15/15/15/7s7/7S7/15/15/15/15/15/15/15 b - - 0 2",
                               game: .gomoku15)
        let first = try? #require(played[Square(file: 7, rank: 7)])
        let second = try? #require(played[Square(file: 7, rank: 8)])
        #expect(first?.side == .red, "uppercase is the side that moves first")
        #expect(first?.isStone == true)
        #expect(second?.side == .black)
        #expect(second?.isStone == true)
        #expect(first?.kind == nil, "a stone carries no kind and therefore no symbol")
    }

    /// A move on a placement board is one square, and it reads as that square.
    ///
    /// It would catch a parser that kept the two-square grammar — the map's own
    /// warning, since a `nil` there silently kills the board's last-move marker
    /// and its legal-move mapping — and a reading that ran a placement through
    /// one of the xiangqi notations.
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

        // The reading is the coordinate in both notations, so the 记谱法
        // preference selects between two identical strings and is inert.
        let reading = MoveReading(of: move, in: Placement(fen: Core.startFEN(for: .renju),
                                                          game: .renju))
        #expect(reading.traditional == "h8")
        #expect(reading.wxf == "h8")
    }

    /// No letter is skipped: the edge spells what the core spells.
    ///
    /// It would catch the Go convention of leaving `i` out being applied to a
    /// board whose moves are written `i9` — an edge that would send a reader to
    /// the wrong line for six of the fifteen files.
    @Test("The file letters run a through o with nothing skipped")
    func fileLettersFollowTheCore() {
        let letters = (0..<15).map { Square(file: $0, rank: 0).fileLetter }
        #expect(letters == ["a", "b", "c", "d", "e", "f", "g", "h",
                            "i", "j", "k", "l", "m", "n", "o"])
    }

    // MARK: - The tap grammar

    /// Every empty point of a 15×15 board, as the core would answer for an
    /// opening position — less whatever this case wants forbidden.
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

    /// The default grammar: a tap on a legal point plays it, and a tap on a
    /// point that carries no legal move is answered by the turn status rather
    /// than by the board, which has no destinations to strengthen.
    ///
    /// It would catch the confirmation defaulting to on, and an occupied or
    /// forbidden point being taken for a move.
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

    /// The pending stone, end to end: mark, move the mark, commit it.
    ///
    /// It would catch any of the four transitions being lost — most of all the
    /// second tap on the mark committing, which is the whole of what the switch
    /// buys, and a mark that could not be moved without first being cancelled.
    @Test("With confirmation the mark is placed, moved, and committed")
    func pendingStoneStateMachine() {
        let placement = position()
        let legal = openingMoves()
        let first = Square(file: 7, rank: 7)
        let second = Square(file: 8, rank: 8)

        func effect(_ square: Square, selected: Square?) -> Game.TapEffect {
            Game.effect(ofTapAt: square, in: placement, legalMoves: legal,
                        sideToMove: .red, selected: selected, acceptsInput: true,
                        confirmsPlacement: true)
        }

        // Nothing marked: the first tap marks rather than plays.
        #expect(effect(first, selected: nil) == .select(first))
        // The mark stands: tapping it is the confirmation.
        #expect(effect(first, selected: first) == .play(Move(placing: first)))
        // Another legal point moves the mark instead of playing either.
        #expect(effect(second, selected: first) == .select(second))
        // Tapping off the board is the screen's own cancel, which is the same
        // act that puts a held piece down; a point that offers nothing is
        // answered without disturbing the mark.
        #expect(effect(Square(file: 7, rank: 7), selected: first)
                == .play(Move(placing: first)))
    }

    /// The forbidden set is the empty points the core did not offer.
    ///
    /// It would catch a second implementation of the renju rule appearing above
    /// the interface — the derivation here is subtraction and nothing else — and
    /// a marker set that stayed on the board through White's turn, when the
    /// points it names are not forbidden to anybody.
    @Test("Forbidden points are the empty points the core left out")
    func forbiddenPointsAreTheDifference() {
        let stone = Square(file: 7, rank: 7)
        let forbidden: Set<Square> = [Square(file: 3, rank: 3), Square(file: 4, rank: 5)]
        let placement = position(occupied: [stone: .red])
        let legal = Set(openingMoves(forbidding: forbidden, occupied: [stone]).map(\.to))

        var derived: Set<Square> = []
        for index in 0..<225 {
            let square = Square(file: index % 15, rank: index / 15)
            guard placement[square] == nil, !legal.contains(square) else { continue }
            derived.insert(square)
        }
        #expect(derived == forbidden)
    }
}

/// The same board, against the real core.
///
/// The suite above works on legal-move sets handed to it, which is right for a
/// grammar; this one asks the engine, because two of the claims this stage makes
/// are claims about what the core answers — that a renju position really does
/// leave a point out of its legal moves, and that a placement game plays end to
/// end through the same session every other game commits through.
@Suite("A placement game on the real core", .retiringItsCores)
@MainActor
struct PlacementGameTests {

    /// A double three at h8, built the plainest way there is: Black holds the
    /// two points either side of it on the rank and the two either side of it on
    /// the file, so placing there would make two open threes at once. White's
    /// four stones sit in the corners, out of every line.
    ///
    /// Eight plies, so it is Black to move — which is when renju's forbidden
    /// points are Black's to see.
    static let doubleThreeLine = ["g8", "a1", "i8", "a15", "h7", "o1", "h9", "o15"]

    private func game(_ kind: GameKind, playing line: [String] = []) throws -> Game {
        let core = try TestCores.fresh()
        try core.create(.freePlay(game: kind))
        let game = try Game(rules: core)
        try game.replay(line)
        return game
    }

    /// A stone goes down and stays down, and the board reads it back.
    ///
    /// It would catch the whole placement path coming apart at any of its
    /// joints — the tap grammar, the single-square move text the core is handed,
    /// the FEN read back as stones, or the coordinate reading in the move list.
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

    /// The engine's own forbidden points, reached through subtraction alone.
    ///
    /// It would catch the derivation inverting — marking the legal points
    /// instead — and, more usefully, a future in which the core stopped
    /// answering renju's restriction at all: nothing above the interface knows
    /// what a double three is, so if the legal-move set stopped leaving h8 out,
    /// the board would silently stop marking it.
    @Test("Renju's forbidden points are the core's answer, and Black's alone")
    func renjuForbiddenPointsComeFromTheCore() throws {
        let game = try game(.renju, playing: Self.doubleThreeLine)
        let doubleThree = Square(file: 7, rank: 7)
        #expect(game.evaluation.sideToMove == .red, "eight plies leaves Black to move")
        #expect(game.forbiddenPoints.contains(doubleThree))
        #expect(!game.legalMoves.contains { $0.to == doubleThree })
        #expect(game.effect(ofTapAt: doubleThree) == .unavailable,
                "a forbidden point offers nothing, and the board has nothing to draw")

        // The same position in the freestyle game has no restriction at all, so
        // the marks are Renju's own rather than the placement board's.
        let free = try game_freestyle()
        #expect(free.forbiddenPoints.isEmpty)
    }

    private func game_freestyle() throws -> Game {
        try game(.gomoku15, playing: PlacementGameTests.doubleThreeLine)
    }

    /// White's turn carries no marks: the restriction is Black's.
    ///
    /// It would catch a marker set left standing through the other side's turn,
    /// which would tell White that points they may perfectly well play are
    /// forbidden to them.
    @Test("Forbidden points are off the board while White is to move")
    func forbiddenPointsAreBlacksAlone() throws {
        let game = try game(.renju, playing: Self.doubleThreeLine + ["b2"])
        #expect(game.evaluation.sideToMove == .black, "now White")
        #expect(game.forbiddenPoints.isEmpty)
    }
}
