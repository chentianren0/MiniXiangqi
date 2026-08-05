// The rules oracle the session engine asks, against the real core.
//
// Nothing here restates a rule: every expectation is the core's own answer to
// the same question the engine will ask it during a nearby game. The claim is
// the one piece of move text this layer maps itself, so the position it is
// lawful in is verified against the core rather than asserted from the line
// that reaches it.

import Testing
@testable import MiniXiangqi

@Suite("The nearby rules oracle", .retiringItsCores)
@MainActor
struct BoardGameRulesTests {

    /// The shortest checkmate from the Mini Xiangqi start: Red's cannon reaches
    /// the general's file behind Black's own soldier.
    static let mateLine = ["b1b3", "b7b6", "b3d3"]

    /// The start position a third time: both cannons out and back twice.
    static let shuffleLine = ["b1b2", "b7b6", "b2b1", "b6b7",
                              "b1b2", "b7b6", "b2b1", "b6b7"]

    /// The same on the 9×10 board: both horses out and back twice, capturing
    /// nothing and checking nothing, so the repetition is the neutral one.
    static let xiangqiShuffleLine = ["b1c3", "b10c8", "c3b1", "c8b10",
                                     "b1c3", "b10c8", "c3b1", "c8b10"]

    private func rules() throws -> CoreBoardGameRules {
        try TestCores.fresh().boardGameRules
    }

    // MARK: - The games this peer plays

    @Test("The two games answer with the rules contract's interpretation version")
    func theGamesItPlays() throws {
        let rules = try rules()
        #expect(rules.version(of: "minixiangqi") == "1")
        #expect(rules.version(of: "xiangqi") == "1")
    }

    @Test("Any other rules_id is a game this peer does not know")
    func everyOtherGameIsUnknown() throws {
        let rules = try rules()
        #expect(rules.version(of: "go-19") == nil)
        #expect(rules.version(of: "MiniXiangqi") == nil, "the identifier is lowercase and exact")
        #expect(rules.version(of: "") == nil)
    }

    // MARK: - What stands

    @Test("A game with no plies is ongoing, in either game")
    func theStartIsOngoing() throws {
        let rules = try rules()
        #expect(rules.standing(after: [], of: "minixiangqi") == .ongoing)
        #expect(rules.standing(after: [], of: "xiangqi") == .ongoing)
    }

    @Test("A mate is a rules-decided end for the mover that delivered it")
    func aMateIsDecided() throws {
        let rules = try rules()
        #expect(rules.standing(after: Self.mateLine, of: "minixiangqi")
                == .decided(.moverWins(.first), .checkmate))
    }

    @Test("The shuffle reaches the claimable neutral repetition")
    func theShuffleIsClaimable() throws {
        let rules = try rules()
        // Every earlier position along the line is still an ordinary game, so
        // the claim is lawful exactly where the third occurrence lands.
        #expect(rules.standing(after: Array(Self.shuffleLine.prefix(7)), of: "minixiangqi")
                == .ongoing)
        #expect(rules.standing(after: Self.shuffleLine, of: "minixiangqi") == .claimable)
    }

    // MARK: - One ply

    @Test("A legal opening ply is lawful in both games")
    func alawfulPly() throws {
        let rules = try rules()
        #expect(rules.verdict(for: "b1b2", after: [], of: "minixiangqi") == .lawful(.ongoing))
        #expect(rules.verdict(for: "a4a5", after: [], of: "xiangqi") == .lawful(.ongoing))
    }

    @Test("A move that is not legal at its turn, and text of no shape at all, are both unlawful")
    func unlawfulPlies() throws {
        let rules = try rules()
        #expect(rules.verdict(for: "b1b7", after: [], of: "minixiangqi") == .unlawful,
                "a cannon capture wants exactly one screen, and the file is empty")
        #expect(rules.verdict(for: "a1a3", after: [], of: "minixiangqi") == .unlawful,
                "the chariot's own soldier blocks the file")
        #expect(rules.verdict(for: "b7b6", after: [], of: "minixiangqi") == .unlawful,
                "the other mover's ply, out of turn")
        #expect(rules.verdict(for: "a1a9", after: [], of: "minixiangqi") == .unlawful,
                "no such square on this board")
        #expect(rules.verdict(for: "hello", after: [], of: "minixiangqi") == .unlawful)
        #expect(rules.verdict(for: "", after: [], of: "minixiangqi") == .unlawful)
    }

    @Test("The mating ply is lawful and carries the end it decides")
    func theMatingPlyDecides() throws {
        let rules = try rules()
        let before = Array(Self.mateLine.dropLast())
        #expect(rules.verdict(for: "b3d3", after: before, of: "minixiangqi")
                == .lawful(.decided(.moverWins(.first), .checkmate)))
    }

    @Test("Nothing is in sequence once the plies have decided the game")
    func nothingFollowsADecidedGame() throws {
        let rules = try rules()
        #expect(rules.verdict(for: "a6a5", after: Self.mateLine, of: "minixiangqi") == .unlawful)
        #expect(rules.verdict(for: TurnAction.claim, after: Self.mateLine, of: "minixiangqi")
                == .unlawful)
    }

    // MARK: - The claim

    @Test("The claim is lawful exactly where the claimable repetition stands")
    func theClaimIsLawfulWhereItStands() throws {
        let rules = try rules()
        #expect(rules.verdict(for: TurnAction.claim, after: Self.shuffleLine, of: "minixiangqi")
                == .lawful(.decided(.draw, .threefoldRepetition)))
        #expect(rules.verdict(for: TurnAction.claim, after: [], of: "minixiangqi") == .unlawful)
        #expect(rules.verdict(for: TurnAction.claim,
                              after: Array(Self.shuffleLine.prefix(7)), of: "minixiangqi")
                == .unlawful,
                "one occurrence short is not claimable")
    }

    @Test("The claim is lawful on the 9×10 board too, and ends that game as the draw it claims")
    func theClaimOnTheLargerBoard() throws {
        let rules = try rules()
        #expect(rules.standing(after: Array(Self.xiangqiShuffleLine.prefix(7)), of: "xiangqi")
                == .ongoing)
        #expect(rules.standing(after: Self.xiangqiShuffleLine, of: "xiangqi") == .claimable)
        #expect(rules.verdict(for: TurnAction.claim, after: Self.xiangqiShuffleLine,
                              of: "xiangqi")
                == .lawful(.decided(.draw, .threefoldRepetition)))
        #expect(rules.standing(after: Self.xiangqiShuffleLine + [TurnAction.claim],
                               of: "xiangqi")
                == .decided(.draw, .threefoldRepetition))
    }

    @Test("A claimed game stands as the draw it claimed, and nothing is in sequence after it")
    func aClaimEndsTheGame() throws {
        let rules = try rules()
        let claimed = Self.shuffleLine + [TurnAction.claim]
        #expect(rules.standing(after: claimed, of: "minixiangqi")
                == .decided(.draw, .threefoldRepetition))
        #expect(rules.verdict(for: "b1b2", after: claimed, of: "minixiangqi") == .unlawful)
        #expect(rules.verdict(for: TurnAction.claim, after: claimed, of: "minixiangqi") == .unlawful)
    }
}
