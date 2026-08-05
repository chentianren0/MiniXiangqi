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

    /// What stands after `plies`.
    func standing(after plies: [String], of rulesID: String) -> RulesStanding

    /// Whether `text` is lawful as the next ply after `plies`.
    func verdict(for text: String, after plies: [String], of rulesID: String) -> PlyVerdict
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

    /// The two games this peer plays, under the `rules_id` the protocol names
    /// them by. A `rules_id` outside this table is a game it does not know.
    private static let games: [String: GameKind] = [
        "minixiangqi": .miniXiangqi,
        "xiangqi": .xiangqi,
    ]

    /// The rules contract's interpretation version in decimal, which is the
    /// string the wire compares byte-wise. It is one value because
    /// docs/xiangqi-rules.md owns one interpretation for both games.
    private static let interpretationVersion = "1"

    func version(of rulesID: String) -> String? {
        Self.games[rulesID] == nil ? nil : Self.interpretationVersion
    }

    func standing(after plies: [String], of rulesID: String) -> RulesStanding {
        guard let game = Self.games[rulesID] else {
            preconditionFailure("a session's game is one this peer plays")
        }
        // A claim ends the game where it lands, and the plies before it are
        // what the core replays.
        if plies.last == TurnAction.claim {
            return .decided(.draw, .threefoldRepetition)
        }
        guard let standing = replay(plies, of: game) else {
            preconditionFailure("a session holds only plies the rules accepted")
        }
        return standing
    }

    func verdict(for text: String, after plies: [String], of rulesID: String) -> PlyVerdict {
        let before = standing(after: plies, of: rulesID)
        // Nothing is in sequence once the plies have decided the game — which
        // is the whole of what makes a claim the last ply of its game.
        if case .decided = before { return .unlawful }

        if text == TurnAction.claim {
            return before == .claimable
                ? .lawful(.decided(.draw, .threefoldRepetition))
                : .unlawful
        }
        guard let game = Self.games[rulesID],
              let after = replay(plies + [text], of: game)
        else { return .unlawful }
        return .lawful(after)
    }

    // MARK: - The core call

    /// The game state after replaying `moves` from the game's frozen start, or
    /// nil where the core refused the line.
    private func replay(_ moves: [String], of game: GameKind) -> RulesStanding? {
        var status = MxqGameStatus()
        status.struct_size = UInt32(MemoryLayout<MxqGameStatus>.size)

        let result = Self.startFEN(of: game).withCString { start in
            withMoveArray(moves) { texts, count in
                mxq_rules_evaluate(core, game.raw, start, texts, count,
                                   nil, &status, nil, nil)
            }
        }
        guard result == MXQ_OK else { return nil }

        // Red is the first mover in both games, by the rules contract's own
        // starting positions; the protocol hears only the mover.
        switch GameState(status.state) {
        case .ongoing: return .ongoing
        case .claimableDraw: return .claimable
        case .redWins: return .decided(.moverWins(.first), EndReason(status.reason))
        case .blackWins: return .decided(.moverWins(.second), EndReason(status.reason))
        case .draw: return .decided(.draw, EndReason(status.reason))
        }
    }

    private static func startFEN(of game: GameKind) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MXQ_FEN_CAP))
        var length = 0
        let status = mxq_rules_start_fen(game.raw, &buffer, buffer.count, &length, nil)
        precondition(status == MXQ_OK, "the starting FEN does not fit MXQ_FEN_CAP")
        return String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)),
                      as: UTF8.self)
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
