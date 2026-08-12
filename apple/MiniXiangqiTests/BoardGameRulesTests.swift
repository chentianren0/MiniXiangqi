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

    /// Black's five along the eighth rank, White answering down the a-file and
    /// reaching nothing. Nine plies, so the ply that decides it is the first
    /// mover's — which is what makes the mapping below testable at all.
    static let fiveLine = ["d8", "a1", "e8", "a2", "f8", "a3", "g8", "a4", "h8"]

    /// A double three at h8: Black holds the two points either side of it on the
    /// rank and the two either side on the file, so placing there would make two
    /// open threes at once. White's stones sit in the corners, out of every
    /// line. Eight plies, so it is the first mover's turn — which is when
    /// Renju's restriction is the one that applies.
    static let doubleThreeLine = ["g8", "a1", "i8", "a15", "h7", "o1", "h9", "o15"]

    // MARK: - The games this peer plays

    @Test("Every game the app carries answers with the interpretation version")
    func theGamesItPlays() throws {
        let rules = try rules()
        #expect(rules.version(of: "minixiangqi") == "1")
        #expect(rules.version(of: "xiangqi") == "1")
        #expect(rules.version(of: "gomoku-15") == "1")
        #expect(rules.version(of: "renju") == "1")
    }

    @Test("Any other rules_id is a game this peer does not know")
    func everyOtherGameIsUnknown() throws {
        let rules = try rules()
        #expect(rules.version(of: "go-19") == nil)
        #expect(rules.version(of: "MiniXiangqi") == nil, "the identifier is lowercase and exact")
        #expect(rules.version(of: "gomoku") == nil, "the size is part of the name")
        #expect(rules.version(of: "renju-15") == nil, "and this one carries none")
        #expect(rules.version(of: "") == nil)
    }

    // MARK: - What stands

    @Test("A game with no plies is ongoing, in every game")
    func theStartIsOngoing() throws {
        let rules = try rules()
        #expect(rules.standing(after: [], of: "minixiangqi") == .ongoing)
        #expect(rules.standing(after: [], of: "xiangqi") == .ongoing)
        #expect(rules.standing(after: [], of: "gomoku-15") == .ongoing)
        #expect(rules.standing(after: [], of: "renju") == .ongoing)
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

    // MARK: - The games stones are placed in

    /// One stone is a whole ply, and the two-square grammar is not a ply at all.
    ///
    /// It would catch a module that reached the wire with the movement games'
    /// move text — the shape that would make every placement ply a violation on
    /// the other device.
    @Test("A placement ply is one point, and two points are not a ply")
    func aPlacementPlyIsOnePoint() throws {
        let rules = try rules()
        #expect(rules.verdict(for: "h8", after: [], of: "gomoku-15") == .lawful(.ongoing))
        #expect(rules.verdict(for: "h8", after: [], of: "renju") == .lawful(.ongoing))
        #expect(rules.verdict(for: "h8h9", after: [], of: "gomoku-15") == .unlawful)
        #expect(rules.verdict(for: "p8", after: [], of: "gomoku-15") == .unlawful,
                "the board stops at o")
        #expect(rules.verdict(for: "h8", after: ["h8"], of: "gomoku-15") == .unlawful,
                "a point with a stone on it is not empty")
        #expect(rules.verdict(for: "", after: [], of: "renju") == .unlawful)
    }

    /// **The wire's first mover is the black stone, and nothing had to be told
    /// so.** The protocol names movers; the core names the side that moves
    /// first; and the ply that wins here is the ninth, which is the first
    /// mover's. A module that had inverted the pivot would report the other one.
    ///
    /// It would catch exactly the inversion this stage's map warned about — a
    /// win landing on the wrong device's side of the protocol, which is the one
    /// error a nearby game cannot recover from.
    @Test("Five in a row is a rules-decided win for the mover that placed it")
    func fiveInARowIsDecidedForTheFirstMover() throws {
        let rules = try rules()
        #expect(rules.standing(after: Array(Self.fiveLine.dropLast()), of: "gomoku-15")
                == .ongoing)
        #expect(rules.verdict(for: "h8", after: Array(Self.fiveLine.dropLast()),
                              of: "gomoku-15")
                == .lawful(.decided(.moverWins(.first), .fiveInARow)))
        #expect(rules.standing(after: Self.fiveLine, of: "gomoku-15")
                == .decided(.moverWins(.first), .fiveInARow))
        #expect(rules.verdict(for: "b2", after: Self.fiveLine, of: "gomoku-15") == .unlawful,
                "nothing is in sequence once the plies have decided the game")
    }

    /// Renju's restriction reaches the wire as the core's own answer: a
    /// forbidden point is not a lawful ply, and the same point in the freestyle
    /// game is.
    ///
    /// It would catch a module that judged a placement ply by emptiness — which
    /// would accept a ply the other device is bound to refuse, and close the
    /// connection over a game the two peers had agreed on.
    @Test("A point Renju forbids is not a lawful ply, and Gomoku forbids none")
    func aForbiddenPointIsNotALawfulPly() throws {
        let rules = try rules()
        #expect(rules.standing(after: Self.doubleThreeLine, of: "renju") == .ongoing)
        #expect(rules.verdict(for: "h8", after: Self.doubleThreeLine, of: "renju") == .unlawful)
        #expect(rules.verdict(for: "b2", after: Self.doubleThreeLine, of: "renju")
                == .lawful(.ongoing),
                "and an ordinary point is still a ply")
        #expect(rules.verdict(for: "h8", after: Self.doubleThreeLine, of: "gomoku-15")
                == .lawful(.ongoing),
                "the restriction is Renju's own")
    }

    /// There is no repetition to claim in these games, so the claim is not a ply
    /// of theirs — anywhere along one.
    ///
    /// It would catch the claim leaking into a game that has none, which would
    /// end a nearby placement game as a draw nothing decided.
    @Test("The claim is not a ply of a placement game")
    func theClaimIsNotAPlacementPly() throws {
        let rules = try rules()
        #expect(rules.verdict(for: TurnAction.claim, after: [], of: "gomoku-15") == .unlawful)
        #expect(rules.verdict(for: TurnAction.claim, after: Self.doubleThreeLine, of: "renju")
                == .unlawful)
    }
}
