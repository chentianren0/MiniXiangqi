import Foundation
import MiniXiangqiCore
import Testing

/// One case of fixtures/rules, as its README defines the format.
struct RulesFixture: Decodable, CustomTestStringConvertible {
    struct Setup: Decodable {
        var status: String
        var rule: String?
        var side: String?
        var square: String?
    }

    struct Probe: Decodable {
        var move: String
        var result_fen: String
        var in_check: Bool
    }

    struct GameState: Decodable {
        var state: String
        var reason: String?
        var at_occurrence: Int?
    }

    struct Assertions: Decodable {
        var in_check: Bool
        var result_fen: String
        var legal_moves: [String]?
        var rejected_moves: [String]?
        var applied: [Probe]?
        var game_state: GameState
    }

    struct Boundary: Decodable {
        var prefix_len: Int
        var expect: String
    }

    var id: String
    var variant: String
    var start_fen: String
    var setup: Setup?
    var moves: [String]?
    var assertions: Assertions?
    var boundary: Boundary?

    var testDescription: String { id }

    var game: Int {
        switch variant {
        case "minixiangqi": MXQ_GAME_KIND_MINI_XIANGQI
        case "xiangqi": MXQ_GAME_KIND_XIANGQI
        default: MXQ_GAME_KIND_JIEQI
        }
    }

    static let all: [RulesFixture] = {
        let directory = repository.appending(path: "fixtures/rules")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap {
            try? JSONDecoder().decode(RulesFixture.self, from: Data(contentsOf: directory.appending(path: $0)))
        }
    }()
}

extension Core {
    @Suite struct RulesFixtures {
        @Test func everyFixtureLoads() throws {
            let directory = repository.appending(path: "fixtures/rules")
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
            #expect(files.count == RulesFixture.all.count)
            #expect(files.count > 100)
        }

        @Test(arguments: RulesFixture.all)
        func fixture(_ fixture: RulesFixture) throws {
            try withCore { core throws in
                if let setup = fixture.setup {
                    check(setup, of: fixture, core)
                } else {
                    try check(play: fixture, core)
                }
            }
        }

        /// A setup fixture is checked whole, rule, side and square included:
        /// the status alone would pass a core refusing for the wrong reason.
        private func check(_ setup: RulesFixture.Setup, of fixture: RulesFixture, _ core: OpaquePointer) {
            var violation = MxqSetupViolation()
            violation.struct_size = UInt32(MemoryLayout<MxqSetupViolation>.size)
            var err = freshError()
            let status = mxq_rules_validate_setup(core, MxqGameKind(fixture.game), fixture.start_fen, &violation, &err)
            let expected = switch setup.status {
            case "ok": MXQ_OK
            case "invalid-fen": MXQ_ERR_RULES_INVALID_FEN
            default: MXQ_ERR_RULES_ILLEGAL_POSITION
            }
            #expect(Int(status) == expected, "status: \(describe(status, err))")
            #expect(ruleName(violation.rule) == setup.rule)
            #expect(colorName(violation.side) == setup.side)
            #expect(nonEmpty(string(of: violation.square)) == setup.square)
        }

        private func check(play fixture: RulesFixture, _ core: OpaquePointer) throws {
            let assertions = try #require(fixture.assertions)
            let moves = fixture.moves ?? []
            let arrival = evaluate(core, fixture.game, fixture.start_fen, moves)
            try #require(arrival.status == MXQ_OK,
                         "the history does not replay: \(statusName(arrival.status)) at \(arrival.firstIllegal) \(arrival.detail)")
            #expect(arrival.fen == assertions.result_fen)
            #expect((arrival.position.in_check != 0) == assertions.in_check)
            #expect(stateName(arrival.state.state) == assertions.game_state.state)
            #expect(reasonName(arrival.state.reason) == assertions.game_state.reason)
            if let occurrence = assertions.game_state.at_occurrence {
                #expect(Int(arrival.state.at_occurrence) == occurrence)
            }

            if assertions.legal_moves != nil || assertions.rejected_moves != nil {
                let legal = Set(try legalMoves(core, fixture.game, fixture.start_fen, moves))
                if let expected = assertions.legal_moves {
                    #expect(legal == Set(expected),
                            "missing \(Set(expected).subtracting(legal).sorted()), unexpected \(legal.subtracting(expected).sorted())")
                }
                for move in assertions.rejected_moves ?? [] {
                    #expect(!legal.contains(move), "\(move) must be illegal")
                }
            }

            for probe in assertions.applied ?? [] {
                let after = evaluate(core, fixture.game, fixture.start_fen, moves + [probe.move])
                #expect(after.status == MXQ_OK, "applied \(probe.move): \(statusName(after.status)) \(after.detail)")
                #expect(after.fen == probe.result_fen, "applied \(probe.move)")
                #expect((after.position.in_check != 0) == probe.in_check, "applied \(probe.move)")
            }

            // One repetition cycle earlier the outcome must not have attached yet.
            if let boundary = fixture.boundary {
                let earlier = evaluate(core, fixture.game, fixture.start_fen, Array(moves.prefix(boundary.prefix_len)))
                #expect(earlier.status == MXQ_OK)
                #expect(stateName(earlier.state.state) != assertions.game_state.state,
                        "at \(boundary.prefix_len) plies: expected \(boundary.expect)")
            }
        }
    }
}

func stateName(_ state: MxqGameState) -> String {
    switch Int(state) {
    case MXQ_GAME_ONGOING: "ongoing"
    case MXQ_GAME_CLAIMABLE_DRAW: "claimable-draw"
    case MXQ_GAME_RED_WINS: "red-wins"
    case MXQ_GAME_BLACK_WINS: "black-wins"
    case MXQ_GAME_DRAW: "draw"
    default: "unknown(\(state))"
    }
}

func reasonName(_ reason: MxqEndReason) -> String? {
    switch Int(reason) {
    case MXQ_END_REASON_NONE: nil
    case MXQ_END_REASON_CHECKMATE: "checkmate"
    case MXQ_END_REASON_STALEMATE: "stalemate"
    case MXQ_END_REASON_THREEFOLD_REPETITION: "threefold-repetition"
    case MXQ_END_REASON_PERPETUAL_CHECK: "perpetual-check"
    case MXQ_END_REASON_PERPETUAL_CHASE: "perpetual-chase"
    case MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK: "mutual-perpetual-check"
    case MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE: "mutual-perpetual-chase"
    case MXQ_END_REASON_FIFTY_MOVE_RULE: "fifty-move-rule"
    case MXQ_END_REASON_FORTY_MOVE_RULE: "forty-move-rule"
    case MXQ_END_REASON_FIVE_IN_A_ROW: "five-in-a-row"
    case MXQ_END_REASON_BOARD_FULL: "board-full"
    default: "unknown(\(reason))"
    }
}

private func ruleName(_ rule: MxqSetupRule) -> String? {
    switch Int(rule) {
    case MXQ_SETUP_RULE_NONE: nil
    case MXQ_SETUP_RULE_PIECE_COUNT: "piece-count"
    case MXQ_SETUP_RULE_PALACE: "palace"
    case MXQ_SETUP_RULE_ELEPHANT_SIDE: "elephant-side"
    case MXQ_SETUP_RULE_SOLDIER_RANK: "soldier-rank"
    case MXQ_SETUP_RULE_FACING_GENERALS: "facing-generals"
    case MXQ_SETUP_RULE_OPPONENT_IN_CHECK: "opponent-in-check"
    case MXQ_SETUP_RULE_NOT_FROZEN_START: "not-frozen-start"
    case MXQ_SETUP_RULE_NOT_DEALT_START: "not-dealt-start"
    default: "unknown(\(rule))"
    }
}

private func colorName(_ color: MxqColor) -> String? {
    switch Int(color) {
    case MXQ_COLOR_RED: "red"
    case MXQ_COLOR_BLACK: "black"
    default: nil
    }
}

private func nonEmpty(_ text: String) -> String? {
    text.isEmpty ? nil : text
}
