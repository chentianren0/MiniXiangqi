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

    /// The dealt-start vector `fixtures/store/jieqi-nearby-dealt.json` pins:
    /// one seed, one nonce, and the commitment, digest and start the core
    /// derives from them. Bound to rather than restated — the derivation is one
    /// implementation, and two devices playing one dealt game depend on it
    /// answering the same bytes everywhere.
    static let seed = String(repeating: "0", count: 64)
    static let nonce =
        "a144410000000000000000000000000000000000000000000000000000000000"
    static let commit =
        "66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925"
    static let digest =
        "98ec20c5cd254471f1b321de793bdb85683135b940e2a00558228637ea001baa"
    static let dealtStart =
        "r~r~c~b~kp~n~n~b~/9/1p~5a~1/c~1p~1p~1p~1a~/9/9/"
        + "P~1P~1C~1B~1R~/1P~5B~1/9/C~A~P~N~KA~P~R~N~ w - - 0 1"

    /// The corpus's own two plies over that deal.
    static let dealtLine = ["b1c3", "b8e8"]

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
        #expect(rules.version(of: "jieqi") == "1",
                "the dealt game is played over the wire like any other")
    }

    @Test("Jieqi is the game whose session opens with the deal handshake, and the only one")
    func onlyTheDealtGameOpensWithTheHandshake() throws {
        let rules = try rules()
        #expect(rules.dealsItsStart("jieqi"))
        for game in ["minixiangqi", "xiangqi", "gomoku-15", "renju"] {
            #expect(!rules.dealsItsStart(game), "\(game) freezes a start of its own")
        }
        #expect(!rules.dealsItsStart("go-19"), "and a game this peer does not know deals nothing")
    }

    // MARK: - The deal

    @Test("One seed and one nonce derive the corpus's own deal")
    func theDealIsTheCorpusVector() throws {
        let rules = try rules()
        let deal = try #require(rules.deal(seed: Self.seed, nonce: Self.nonce, of: "jieqi"))
        #expect(deal.commit == Self.commit)
        #expect(deal.digest == Self.digest)
        #expect(deal.start == Self.dealtStart)
        #expect(deal.seed == Self.seed)
        #expect(deal.nonce == Self.nonce)
    }

    @Test("The commitment this peer computes is the one the deriving entry reports")
    func theCommitmentIsOneValue() throws {
        // The dealer needs it before any nonce exists, so it is computed from
        // the seed alone — and it has to be the same value the core answers
        // with once there is a deal to derive, or no seed would ever open a
        // commitment.
        #expect(DealHex.commitment(for: Self.seed) == Self.commit)
        let rules = try rules()
        #expect(rules.deal(seed: Self.seed, nonce: Self.nonce, of: "jieqi")?.commit
                == DealHex.commitment(for: Self.seed))
    }

    @Test("No other game has a deal, and no value of another shape derives one")
    func nothingElseDerivesADeal() throws {
        let rules = try rules()
        for game in ["minixiangqi", "xiangqi", "gomoku-15", "renju", "go-19"] {
            #expect(rules.deal(seed: Self.seed, nonce: Self.nonce, of: game) == nil)
        }
        #expect(rules.deal(seed: Self.commit.uppercased(), nonce: Self.nonce, of: "jieqi") == nil,
                "the spelling is part of the value")
        #expect(rules.deal(seed: String(Self.seed.dropLast()), nonce: Self.nonce,
                           of: "jieqi") == nil)
        #expect(rules.deal(seed: Self.seed, nonce: "", of: "jieqi") == nil)
    }

    @Test("A dealt game's plies are judged over the deal its session holds")
    func theDealtGamePlaysFromItsOwnStart() throws {
        let rules = try rules()
        #expect(rules.standing(after: [], from: Self.dealtStart, of: "jieqi") == .ongoing)
        #expect(rules.verdict(for: "b1c3", after: [], from: Self.dealtStart, of: "jieqi")
                == .lawful(.ongoing), "a hidden piece moves as the square's own role")
        #expect(rules.verdict(for: "b1b3", after: [], from: Self.dealtStart, of: "jieqi")
                == .unlawful, "and by no other role")
        #expect(rules.standing(after: Self.dealtLine, from: Self.dealtStart, of: "jieqi")
                == .ongoing)
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
        #expect(rules.standing(after: [], from: nil, of: "minixiangqi") == .ongoing)
        #expect(rules.standing(after: [], from: nil, of: "xiangqi") == .ongoing)
        #expect(rules.standing(after: [], from: nil, of: "gomoku-15") == .ongoing)
        #expect(rules.standing(after: [], from: nil, of: "renju") == .ongoing)
    }

    @Test("A mate is a rules-decided end for the mover that delivered it")
    func aMateIsDecided() throws {
        let rules = try rules()
        #expect(rules.standing(after: Self.mateLine, from: nil, of: "minixiangqi")
                == .decided(.moverWins(.first), .checkmate))
    }

    @Test("The shuffle reaches the claimable neutral repetition")
    func theShuffleIsClaimable() throws {
        let rules = try rules()
        // Every earlier position along the line is still an ordinary game, so
        // the claim is lawful exactly where the third occurrence lands.
        #expect(rules.standing(after: Array(Self.shuffleLine.prefix(7)), from: nil, of: "minixiangqi")
                == .ongoing)
        #expect(rules.standing(after: Self.shuffleLine, from: nil, of: "minixiangqi") == .claimable)
    }

    // MARK: - One ply

    @Test("A legal opening ply is lawful in both games")
    func alawfulPly() throws {
        let rules = try rules()
        #expect(rules.verdict(for: "b1b2", after: [], from: nil, of: "minixiangqi") == .lawful(.ongoing))
        #expect(rules.verdict(for: "a4a5", after: [], from: nil, of: "xiangqi") == .lawful(.ongoing))
    }

    @Test("A move that is not legal at its turn, and text of no shape at all, are both unlawful")
    func unlawfulPlies() throws {
        let rules = try rules()
        #expect(rules.verdict(for: "b1b7", after: [], from: nil, of: "minixiangqi") == .unlawful,
                "a cannon capture wants exactly one screen, and the file is empty")
        #expect(rules.verdict(for: "a1a3", after: [], from: nil, of: "minixiangqi") == .unlawful,
                "the chariot's own soldier blocks the file")
        #expect(rules.verdict(for: "b7b6", after: [], from: nil, of: "minixiangqi") == .unlawful,
                "the other mover's ply, out of turn")
        #expect(rules.verdict(for: "a1a9", after: [], from: nil, of: "minixiangqi") == .unlawful,
                "no such square on this board")
        #expect(rules.verdict(for: "hello", after: [], from: nil, of: "minixiangqi") == .unlawful)
        #expect(rules.verdict(for: "", after: [], from: nil, of: "minixiangqi") == .unlawful)
    }

    @Test("The mating ply is lawful and carries the end it decides")
    func theMatingPlyDecides() throws {
        let rules = try rules()
        let before = Array(Self.mateLine.dropLast())
        #expect(rules.verdict(for: "b3d3", after: before, from: nil, of: "minixiangqi")
                == .lawful(.decided(.moverWins(.first), .checkmate)))
    }

    @Test("Nothing is in sequence once the plies have decided the game")
    func nothingFollowsADecidedGame() throws {
        let rules = try rules()
        #expect(rules.verdict(for: "a6a5", after: Self.mateLine, from: nil,
                              of: "minixiangqi") == .unlawful)
        #expect(rules.verdict(for: TurnAction.claim, after: Self.mateLine, from: nil, of: "minixiangqi")
                == .unlawful)
    }

    // MARK: - The claim

    @Test("The claim is lawful exactly where the claimable repetition stands")
    func theClaimIsLawfulWhereItStands() throws {
        let rules = try rules()
        #expect(rules.verdict(for: TurnAction.claim, after: Self.shuffleLine,
                              from: nil, of: "minixiangqi")
                == .lawful(.decided(.draw, .threefoldRepetition)))
        #expect(rules.verdict(for: TurnAction.claim, after: [], from: nil,
                              of: "minixiangqi") == .unlawful)
        #expect(rules.verdict(for: TurnAction.claim,
                              after: Array(Self.shuffleLine.prefix(7)),
                              from: nil, of: "minixiangqi")
                == .unlawful,
                "one occurrence short is not claimable")
    }

    @Test("The claim is lawful on the 9×10 board too, and ends that game as the draw it claims")
    func theClaimOnTheLargerBoard() throws {
        let rules = try rules()
        #expect(rules.standing(after: Array(Self.xiangqiShuffleLine.prefix(7)), from: nil, of: "xiangqi")
                == .ongoing)
        #expect(rules.standing(after: Self.xiangqiShuffleLine, from: nil, of: "xiangqi") == .claimable)
        #expect(rules.verdict(for: TurnAction.claim, after: Self.xiangqiShuffleLine,
                              from: nil, of: "xiangqi")
                == .lawful(.decided(.draw, .threefoldRepetition)))
        #expect(rules.standing(after: Self.xiangqiShuffleLine + [TurnAction.claim],
                               from: nil, of: "xiangqi")
                == .decided(.draw, .threefoldRepetition))
    }

    @Test("A claimed game stands as the draw it claimed, and nothing is in sequence after it")
    func aClaimEndsTheGame() throws {
        let rules = try rules()
        let claimed = Self.shuffleLine + [TurnAction.claim]
        #expect(rules.standing(after: claimed, from: nil, of: "minixiangqi")
                == .decided(.draw, .threefoldRepetition))
        #expect(rules.verdict(for: "b1b2", after: claimed, from: nil, of: "minixiangqi") == .unlawful)
        #expect(rules.verdict(for: TurnAction.claim, after: claimed, from: nil,
                              of: "minixiangqi") == .unlawful)
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
        #expect(rules.verdict(for: "h8", after: [], from: nil, of: "gomoku-15") == .lawful(.ongoing))
        #expect(rules.verdict(for: "h8", after: [], from: nil, of: "renju") == .lawful(.ongoing))
        #expect(rules.verdict(for: "h8h9", after: [], from: nil, of: "gomoku-15") == .unlawful)
        #expect(rules.verdict(for: "p8", after: [], from: nil, of: "gomoku-15") == .unlawful,
                "the board stops at o")
        #expect(rules.verdict(for: "h8", after: ["h8"], from: nil, of: "gomoku-15") == .unlawful,
                "a point with a stone on it is not empty")
        #expect(rules.verdict(for: "", after: [], from: nil, of: "renju") == .unlawful)
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
        #expect(rules.standing(after: Array(Self.fiveLine.dropLast()), from: nil, of: "gomoku-15")
                == .ongoing)
        #expect(rules.verdict(for: "h8", after: Array(Self.fiveLine.dropLast()),
                              from: nil, of: "gomoku-15")
                == .lawful(.decided(.moverWins(.first), .fiveInARow)))
        #expect(rules.standing(after: Self.fiveLine, from: nil, of: "gomoku-15")
                == .decided(.moverWins(.first), .fiveInARow))
        #expect(rules.verdict(for: "b2", after: Self.fiveLine, from: nil, of: "gomoku-15") == .unlawful,
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
        #expect(rules.standing(after: Self.doubleThreeLine, from: nil, of: "renju") == .ongoing)
        #expect(rules.verdict(for: "h8", after: Self.doubleThreeLine, from: nil,
                              of: "renju") == .unlawful)
        #expect(rules.verdict(for: "b2", after: Self.doubleThreeLine, from: nil, of: "renju")
                == .lawful(.ongoing),
                "and an ordinary point is still a ply")
        #expect(rules.verdict(for: "h8", after: Self.doubleThreeLine, from: nil, of: "gomoku-15")
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
        #expect(rules.verdict(for: TurnAction.claim, after: [], from: nil, of: "gomoku-15") == .unlawful)
        #expect(rules.verdict(for: TurnAction.claim, after: Self.doubleThreeLine, from: nil, of: "renju")
                == .unlawful)
    }
}
