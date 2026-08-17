// The rules question the session engine asks, and the core's answer to it.
//
// The protocol defines no game's rules, so the engine holds no rule of its own:
// it holds the ply list and asks this. The one implementation that ships is the
// core's, over the session-free rules facade — the same authority the app's own
// games are decided by, so a nearby game and a local game cannot disagree about
// what is legal or about how a game ended.
//
// The claim action is the one piece of move text this file maps itself. It
// moves no piece, so there is nothing for the core to replay; the rules
// contract gives it its meaning, and it never crosses the C interface.

import Foundation
import MiniXiangqiCore

/// The rules contract's turn actions: move text that is not a board move.
nonisolated enum TurnAction {
    /// The claimed draw, spelled as the rules contract spells it.
    static let claim = "claim"
}

/// A finished game's result in the protocol's own vocabulary. The protocol
/// names movers, never colours: which colour a mover plays belongs to the
/// game's `rules_id`.
nonisolated enum GameResult: Sendable, Equatable {
    case moverWins(Mover)
    case draw
}

/// An end the game's own rules decided, which needs no message and outranks
/// every other ending.
nonisolated struct RulesDecision: Sendable, Equatable {
    var result: GameResult
    var reason: EndReason
}

/// What stands after a list of plies.
nonisolated enum RulesStanding: Sendable, Equatable {
    case ongoing
    /// Ongoing, and the claim is lawful as the next ply.
    case claimable
    case decided(GameResult, EndReason)

    var decision: RulesDecision? {
        guard case .decided(let result, let reason) = self else { return nil }
        return RulesDecision(result: result, reason: reason)
    }
}

/// Whether one move text is lawful as the next ply.
nonisolated enum PlyVerdict: Sendable, Equatable {
    /// Lawful, and this is what stands once it has landed.
    case lawful(RulesStanding)
    /// Not a lawful next ply of this game — an illegal move, a claim with
    /// nothing to claim, or text of no shape at all.
    case unlawful
}

/// Everything the session engine asks about a game.
nonisolated protocol BoardGameRules: Sendable {
    /// The interpretation version this peer implements for the named game, or
    /// nil where it does not implement the game at all. The proposal's own
    /// version is compared against this byte-wise.
    func version(of rulesID: String) -> String?

    /// Whether the named game's session opens with the deal handshake — which
    /// is the protocol's own pairing: a **hidden-information game** is "one
    /// whose start is dealt and whose play discloses that deal in pieces; its
    /// session opens with the handshake", and every other game's does not.
    ///
    /// Asked of the rules because the core is the only rules authority. What
    /// answers it below is the core's own fact about the game, never a table of
    /// names kept above the interface.
    func dealsItsStart(_ rulesID: String) -> Bool

    /// The deal a seed and a nonce derive for the named game: the position it
    /// produced, the commitment the seed binds to, and the deal's own digest.
    ///
    /// Nil for a game with no deal, and for values it cannot derive one from.
    /// The two ends must compute one identical deal from what crossed the wire,
    /// which is why one implementation answers this for both.
    func deal(seed: String, nonce: String, of rulesID: String) -> BoardGameDeal?

    /// What stands after `plies` of a game begun from `start` — the deal a
    /// hidden-information session derived, and nil for a game whose rules
    /// freeze a start of their own.
    func standing(after plies: [String], from start: String?,
                  of rulesID: String) -> RulesStanding

    /// Whether `text` is lawful as the next ply after `plies`, in a game begun
    /// from `start`.
    func verdict(for text: String, after plies: [String], from start: String?,
                 of rulesID: String) -> PlyVerdict
}

/// Every game, under the `rules_id` the protocol and the archive both name it
/// by. One table, in both directions: the oracle reads it to answer what an
/// arriving `rules_id` means, and the surfaces read it to say which game a
/// proposal is for. A `rules_id` outside it is not a game at all.
///
/// Knowing a name is not the same as playing the game: which of these this peer
/// carries over the wire is `version(of:)`'s answer below.
nonisolated extension GameKind {
    var rulesID: String {
        switch self {
        case .miniXiangqi: "minixiangqi"
        case .xiangqi: "xiangqi"
        case .gomoku15: "gomoku-15"
        case .renju: "renju"
        case .jieqi: "jieqi"
        }
    }

    init?(rulesID: String) {
        guard let match = Self.allCases.first(where: { $0.rulesID == rulesID }) else {
            return nil
        }
        self = match
    }
}

/// The core's answers, over the session-free rules facade.
///
/// `@unchecked Sendable` for the reason `HistoryStore` is: what makes the
/// handle safe to send is the C contract above it — `mxq_rules_*` is callable
/// from any thread except inside a search callback — which Swift cannot read.
nonisolated struct CoreBoardGameRules: BoardGameRules, @unchecked Sendable {
    private let core: OpaquePointer

    init(core: OpaquePointer) {
        self.core = core
    }

    /// The interpretation version in decimal, which is the string the wire
    /// compares byte-wise. It is one value for every game this peer plays, and
    /// that is a fact about where each of them stands rather than a claim that
    /// they share one interpretation: each game starts at "1" and each would
    /// move on its own, so a single constant is exact for as long as no game has
    /// moved off it. The first game to gain a second version is the one that
    /// makes this a table.
    ///
    /// Readable beyond this oracle because a session rebuilt from the library
    /// states it too, and a resumed session that named a second value would be
    /// a session neither peer proposed.
    static let interpretationVersion = "1"

    func version(of rulesID: String) -> String? {
        // A `rules_id` outside the table is a game this peer does not know,
        // which is what nil says and what the wire's `unknown_game` refusal
        // answers with. Every game the app carries it carries over the wire:
        // the whole of what a game module is here is this file's answers, and
        // they are the core's.
        guard GameKind(rulesID: rulesID) != nil else { return nil }
        return Self.interpretationVersion
    }

    /// **Derived from the core, and from nothing kept here.** A game with no
    /// frozen start is a game whose start is dealt — `mxq_rules_start_fen`
    /// answers `MXQ_ERR_ARG_RANGE` for exactly that game, "there being no
    /// frozen start to report" — and a game whose start is dealt is the
    /// hidden-information game whose session opens with the handshake. Naming
    /// the game here instead would put a rules fact above the interface that
    /// owns it.
    func dealsItsStart(_ rulesID: String) -> Bool {
        guard let game = GameKind(rulesID: rulesID) else { return false }
        return Self.startFEN(of: game) == nil
    }

    func deal(seed: String, nonce: String, of rulesID: String) -> BoardGameDeal? {
        guard let game = GameKind(rulesID: rulesID) else { return nil }
        var derived = MxqDeal()
        derived.struct_size = UInt32(MemoryLayout<MxqDeal>.size)
        let status = seed.withCString { seed in
            nonce.withCString { nonce in
                mxq_rules_deal(core, game.raw, seed, nonce, &derived, nil)
            }
        }
        // A game with no deal, or a value of a shape the entry will not take,
        // is `MXQ_ERR_ARG_RANGE` — which is nil here rather than a trap: the
        // seed and the nonce reaching this can have come off the wire.
        guard status == MXQ_OK else { return nil }
        return BoardGameDeal(
            commit: string(of: derived.commit, capacity: MXQ_DEAL_HEX_CAP),
            nonce: nonce, seed: seed,
            digest: string(of: derived.digest, capacity: MXQ_DEAL_HEX_CAP),
            start: string(of: derived.start_fen, capacity: MXQ_FEN_CAP))
    }

    func standing(after plies: [String], from start: String?,
                  of rulesID: String) -> RulesStanding {
        guard let game = GameKind(rulesID: rulesID) else {
            preconditionFailure("a session's game is one this peer plays")
        }
        // A claim ends the game where it lands, and the plies before it are
        // what the core replays.
        if plies.last == TurnAction.claim {
            return .decided(.draw, .threefoldRepetition)
        }
        guard let standing = replay(plies, from: start, of: game) else {
            preconditionFailure("a session holds only plies the rules accepted")
        }
        return standing
    }

    func verdict(for text: String, after plies: [String], from start: String?,
                 of rulesID: String) -> PlyVerdict {
        let before = standing(after: plies, from: start, of: rulesID)
        // Nothing is in sequence once the plies have decided the game — which
        // is the whole of what makes a claim the last ply of its game.
        if case .decided = before { return .unlawful }

        if text == TurnAction.claim {
            return before == .claimable
                ? .lawful(.decided(.draw, .threefoldRepetition))
                : .unlawful
        }
        guard let game = GameKind(rulesID: rulesID),
              let after = replay(plies + [text], from: start, of: game)
        else { return .unlawful }
        return .lawful(after)
    }

    // MARK: - The core call

    /// The game state after replaying `moves` from the session's own start —
    /// the deal a hidden-information session derived, or the game's frozen
    /// start where its rules freeze one. Nil where the core refused the line,
    /// and where a dealt game was asked without its deal.
    private func replay(_ moves: [String], from start: String?,
                        of game: GameKind) -> RulesStanding? {
        var status = MxqGameStatus()
        status.struct_size = UInt32(MemoryLayout<MxqGameStatus>.size)

        guard let start = start ?? Self.startFEN(of: game) else { return nil }
        let result = start.withCString { start in
            withMoveArray(moves) { texts, count in
                mxq_rules_evaluate(core, game.raw, start, texts, count,
                                   nil, &status, nil, nil)
            }
        }
        guard result == MXQ_OK else { return nil }

        // **The protocol hears only the mover, and `Side` already is one.**
        // `MXQ_COLOR_RED` is the core's word for the side that moves first in
        // whatever game it is asked about — the red piece where a game moves,
        // the black stone where it places — so the equation below is the same
        // equation for all four games and names no colour. Which stone the first
        // mover puts down is the `rules_id`'s business, exactly as the protocol
        // says, and it is answered where every other surface asks it:
        // `GameKind.sideName(_:)` and its registers.
        switch GameState(status.state) {
        case .ongoing: return .ongoing
        case .claimableDraw: return .claimable
        case .redWins: return .decided(.moverWins(.first), EndReason(status.reason))
        case .blackWins: return .decided(.moverWins(.second), EndReason(status.reason))
        case .draw: return .decided(.draw, EndReason(status.reason))
        }
    }

    /// The position a game of this ruleset begins from, where its rules freeze
    /// one. Nil for a game whose start is dealt rather than frozen — asked here
    /// rather than assumed, because the entry answers a refusal for such a game
    /// and a `precondition` over it would trap a release build. It is also what
    /// `dealsItsStart` reads: the absence *is* the fact.
    private static func startFEN(of game: GameKind) -> String? {
        Core.frozenStartFEN(for: game)
    }

    /// The move list as the C array of NUL-terminated strings the facade takes.
    /// Copied rather than borrowed from the Swift strings: `withCString` lends
    /// one buffer per call and nesting it over a whole game would be a
    /// recursion the length of the line.
    private func withMoveArray<Result>(
        _ moves: [String],
        _ body: (UnsafePointer<UnsafePointer<CChar>?>?, Int) -> Result
    ) -> Result {
        var copies = moves.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        return copies.withUnsafeMutableBufferPointer { buffer in
            buffer.withMemoryRebound(to: UnsafePointer<CChar>?.self) { texts in
                body(texts.baseAddress, moves.count)
            }
        }
    }
}

extension Core {
    /// The rules the nearby session engine asks, over this core.
    var boardGameRules: CoreBoardGameRules { CoreBoardGameRules(core: handle) }
}
