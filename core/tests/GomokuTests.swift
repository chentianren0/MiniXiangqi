import MiniXiangqiCore
import Testing

/// The placement games: the core's notation for them, and the legality and
/// adjudication Rapfi answers for them.
extension Core {
    @Suite struct Gomoku {
        static let empty = "15/15/15/15/15/15/15/15/15/15/15/15/15/15/15 w - - 0 1"
        static let games = [MXQ_GAME_KIND_GOMOKU_15, MXQ_GAME_KIND_RENJU]

        /// Interleave two sides' stones, the first mover first.
        static func alternating(_ first: [String], _ second: [String]) -> [String] {
            (0..<max(first.count, second.count)).flatMap { index in
                [first.indices.contains(index) ? first[index] : nil,
                 second.indices.contains(index) ? second[index] : nil].compactMap { $0 }
            }
        }

        /// A move grammar that measured moves by text length would accept
        /// "h8h9" here, where both halves are squares.
        @Test func aMoveIsOneSquare() throws {
            try withCore { core throws in
                #expect(startFEN(MXQ_GAME_KIND_GOMOKU_15) == Self.empty)
                #expect(startFEN(MXQ_GAME_KIND_RENJU) == Self.empty)
                for game in Self.games {
                    #expect(evaluate(core, game, Self.empty, ["a1"]).status == MXQ_OK)
                    #expect(evaluate(core, game, Self.empty, ["o15"]).status == MXQ_OK)
                    for malformed in ["h8h9", "p1", "o16", "h0", "h08", "h", "8h", ""] {
                        #expect(evaluate(core, game, Self.empty, [malformed]).status == MXQ_ERR_RULES_INVALID_HISTORY,
                                "\(malformed) is not a move of this board")
                    }
                }
            }
        }

        @Test func aPositionHasOneSpelling() throws {
            try withCore { core throws in
                let valid = "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0 1"
                #expect(mxq_rules_validate_setup(core, MxqGameKind(MXQ_GAME_KIND_GOMOKU_15), valid, nil, nil)
                    == MXQ_ERR_RULES_ILLEGAL_POSITION, "a position of the board that is not its start")
                let rejected = [
                    "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15 b - - 0 1",
                    "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15/15 b - - 0 1",
                    "15/15/15/15/15/15/15/7S8/15/15/15/15/15/15/15 b - - 0 1",
                    "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0 1 1",
                    "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/015 b - - 0 1",
                    "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 x - - 0 1",
                    "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b K - 0 1",
                    "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 1 1",
                    "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0 0",
                    "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0",
                    "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1",
                ]
                for fen in rejected {
                    #expect(mxq_rules_validate_setup(core, MxqGameKind(MXQ_GAME_KIND_GOMOKU_15), fen, nil, nil) == MXQ_ERR_RULES_INVALID_FEN, "\(fen)")
                }
                #expect(mxq_rules_validate_setup(core, MxqGameKind(MXQ_GAME_KIND_XIANGQI), valid, nil, nil) == MXQ_ERR_RULES_INVALID_FEN)
            }
        }

        @Test func everyEmptyPointIsAPlacement() throws {
            try withCore { core throws in
                let opening = try legalMoves(core, MXQ_GAME_KIND_GOMOKU_15, Self.empty)
                #expect(opening.count == 225)
                #expect(opening.contains("a1") && opening.contains("o15") && opening.contains("h8"))

                let after = evaluate(core, MXQ_GAME_KIND_GOMOKU_15, Self.empty, ["h8"])
                #expect(after.status == MXQ_OK)
                #expect(after.fen == "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0 1")
                #expect(after.position.ply_count == 1)
                #expect(after.position.side_to_move == MXQ_COLOR_BLACK)
                #expect(after.position.in_check == 0)
                #expect(stateName(after.state.state) == "ongoing")

                let narrowed = try legalMoves(core, MXQ_GAME_KIND_GOMOKU_15, Self.empty, ["h8"])
                #expect(narrowed.count == 224 && !narrowed.contains("h8"))

                let occupied = evaluate(core, MXQ_GAME_KIND_GOMOKU_15, Self.empty, ["h8", "h8"])
                #expect(occupied.status == MXQ_ERR_RULES_INVALID_HISTORY)
                #expect(occupied.firstIllegal == 1)
            }
        }

        @Test func fiveInARowWins() throws {
            try withCore { core throws in
                let line = Self.alternating(["d8", "e8", "f8", "g8", "h8"], ["a1", "c1", "e1", "g1"])
                for game in Self.games {
                    let arrived = evaluate(core, game, Self.empty, line)
                    #expect(arrived.status == MXQ_OK)
                    #expect(arrived.state.state == MXQ_GAME_RED_WINS)
                    #expect(reasonName(arrived.state.reason) == "five-in-a-row")
                    #expect(try legalMoves(core, game, Self.empty, line).isEmpty)
                    let beyond = evaluate(core, game, Self.empty, line + ["a15"])
                    #expect(beyond.status == MXQ_ERR_RULES_INVALID_HISTORY)
                    #expect(beyond.firstIllegal == line.count)
                }
            }
        }

        /// h8 makes two open threes at once, f8-g8-h8 and h6-h7-h8.
        @Test func aDoubleThreeIsForbiddenForRenjusBlackAlone() throws {
            try withCore { core throws in
                let shape = ["f8", "g8", "h6", "h7"]
                let blackToPlay = Self.alternating(shape, ["a1", "c1", "e1", "g1"])
                let whiteToPlay = Self.alternating(["a1", "c1", "e1", "g1", "i1"], shape)

                let refused = evaluate(core, MXQ_GAME_KIND_RENJU, Self.empty, blackToPlay + ["h8"])
                #expect(refused.status == MXQ_ERR_RULES_INVALID_HISTORY)
                #expect(refused.firstIllegal == blackToPlay.count)
                let offered = try legalMoves(core, MXQ_GAME_KIND_RENJU, Self.empty, blackToPlay)
                #expect(!offered.contains("h8") && offered.contains("a15"))

                let freestyle = evaluate(core, MXQ_GAME_KIND_GOMOKU_15, Self.empty, blackToPlay + ["h8"])
                #expect(freestyle.status == MXQ_OK && freestyle.state.state == MXQ_GAME_ONGOING)
                #expect(evaluate(core, MXQ_GAME_KIND_RENJU, Self.empty, whiteToPlay + ["h8"]).status == MXQ_OK)
                #expect(try legalMoves(core, MXQ_GAME_KIND_RENJU, Self.empty, whiteToPlay).contains("h8"))
            }
        }

        /// h8 makes a four, e8-f8-g8-h8, and an open three, h6-h7-h8.
        @Test func aFourThreeIsLegalForBlack() throws {
            try withCore { core throws in
                let line = Self.alternating(["e8", "f8", "g8", "h6", "h7"], ["a1", "c1", "e1", "g1", "i1"]) + ["h8"]
                let arrived = evaluate(core, MXQ_GAME_KIND_RENJU, Self.empty, line)
                #expect(arrived.status == MXQ_OK && arrived.state.state == MXQ_GAME_ONGOING)
            }
        }

        /// Filling f8 between c8-d8-e8 and g8-h8 makes six.
        @Test func anOverlineIsForbiddenForRenjusBlackAndWinsOtherwise() throws {
            try withCore { core throws in
                let shape = ["c8", "d8", "e8", "g8", "h8"]
                let firstMover = Self.alternating(shape, ["a1", "c1", "e1", "g1", "i1"])

                let renjuBlack = evaluate(core, MXQ_GAME_KIND_RENJU, Self.empty, firstMover + ["f8"])
                #expect(renjuBlack.status == MXQ_ERR_RULES_INVALID_HISTORY)
                #expect(renjuBlack.firstIllegal == firstMover.count)

                let freestyle = evaluate(core, MXQ_GAME_KIND_GOMOKU_15, Self.empty, firstMover + ["f8"])
                #expect(freestyle.status == MXQ_OK && freestyle.state.state == MXQ_GAME_RED_WINS)
                #expect(reasonName(freestyle.state.reason) == "five-in-a-row")

                let secondMover = Self.alternating(["a1", "c1", "e1", "g1", "i1", "k1"], shape) + ["f8"]
                let renjuWhite = evaluate(core, MXQ_GAME_KIND_RENJU, Self.empty, secondMover)
                #expect(renjuWhite.status == MXQ_OK && renjuWhite.state.state == MXQ_GAME_BLACK_WINS)
                #expect(reasonName(renjuWhite.state.reason) == "five-in-a-row")
            }
        }

        /// The first mover takes the points where (file + 2 × rank) mod 8 ≥ 4:
        /// no five of either colour in any direction, 113 points against 112.
        @Test func aFullBoardWithNoFiveIsADraw() throws {
            try withCore { core throws in
                var first: [String] = []
                var second: [String] = []
                for rank in 0..<15 {
                    for file in 0..<15 {
                        let point = "\(Character(UnicodeScalar(UInt8(97 + file))))\(rank + 1)"
                        if (file + 2 * rank) % 8 >= 4 { first.append(point) } else { second.append(point) }
                    }
                }
                #expect(first.count == 113 && second.count == 112)
                let line = Self.alternating(first, second)

                let nearly = evaluate(core, MXQ_GAME_KIND_GOMOKU_15, Self.empty, Array(line.dropLast()))
                #expect(nearly.status == MXQ_OK && nearly.state.state == MXQ_GAME_ONGOING)

                let full = evaluate(core, MXQ_GAME_KIND_GOMOKU_15, Self.empty, line)
                #expect(full.status == MXQ_OK && full.state.state == MXQ_GAME_DRAW)
                #expect(reasonName(full.state.reason) == "board-full")
                #expect(full.position.ply_count == 225)
                // The widest position this interface carries.
                #expect(full.fen.count == 251)
                #expect(full.fen.hasSuffix(" b - - 0 113"))
                #expect(full.fen.count < Int(MXQ_FEN_CAP))
                #expect(mxq_rules_validate_setup(core, MxqGameKind(MXQ_GAME_KIND_GOMOKU_15), full.fen, nil, nil)
                    != MXQ_ERR_RULES_INVALID_FEN, "the widest position is one of the board")
            }
        }
    }
}
