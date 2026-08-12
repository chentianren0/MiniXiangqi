// What a nearby game's board draws, asked of the core.
//
// A nearby session is a list of plies held by the protocol engine, and nothing
// else. So the board behind it is projected rather than attached — the position
// and the legal moves after those plies, from `mxq_rules_evaluate` and
// `mxq_rules_legal_moves`, which are the core's *session-free* rules facade and
// take exactly `(game, start_fen, moves[])`.
//
// **The library is elsewhere, and deliberately.** A nearby game does live in
// the store, but a ply reaches it through the driver's own publication rather
// than through the board — plies land while the board is down — so what draws
// the game and what records it are two paths from one authority, and this one
// asks without a session in between.
//
// **Nothing here decides a rule.** The position, the legality, the check and the
// result are the core's answers; what this file adds is the call and the type
// they come back in.

import Foundation
import MiniXiangqiCore

/// The position a session's plies produce, and what may be played into it.
nonisolated struct NearbyStanding: Sendable {
    /// The core's own evaluation of the projected position — the same type an
    /// attached session answers with, from the same two structs.
    var evaluation: Evaluation
    /// The legal moves of that position, in canonical notation.
    var legalMoves: [String]
}

/// Everything the nearby board asks about a position. A protocol because a test
/// of the board's own behaviour is not a test of the rules, and the core is a
/// singleton a unit suite must not hold while another suite is running.
nonisolated protocol NearbyPositions: Sendable {
    /// The standing after those plies, or nil where the core refused the line —
    /// which is a bug above it, since the engine holds only plies its own oracle
    /// accepted.
    func standing(of game: GameKind, after plies: [String]) -> NearbyStanding?
}

/// The core's answers, over the session-free rules facade.
///
/// `@unchecked Sendable` for the reason `CoreBoardGameRules` is: what makes the
/// handle safe to send is the C contract above it — `mxq_rules_*` is callable
/// from any thread except inside a search callback — which Swift cannot read.
nonisolated struct CoreNearbyPositions: NearbyPositions, @unchecked Sendable {
    private let core: OpaquePointer

    init(core: OpaquePointer) {
        self.core = core
    }

    func standing(of game: GameKind, after plies: [String]) -> NearbyStanding? {
        // A claim moves no piece, so there is nothing for the core to replay:
        // the board it decides is the board before it, and the end it produces
        // is the session's rather than the position's. It can only be the last
        // ply of its game, and dropping it is what lets a claimed session still
        // draw the position it was claimed in.
        let played = Array(plies.prefix { $0 != TurnAction.claim })

        var position = MxqPosition()
        position.struct_size = UInt32(MemoryLayout<MxqPosition>.size)
        var status = MxqGameStatus()
        status.struct_size = UInt32(MemoryLayout<MxqGameStatus>.size)
        // The one buffer bound this app has, which `Core` derives from the
        // widest board it carries. It is the same constant an attached session's
        // own call sizes by, because it is the same question asked of the same
        // core — and an undersized buffer here would be a board quietly missing
        // the points it could be played on rather than failing.
        var moves = [MxqMove](repeating: MxqMove(), count: Core.legalMoveCapacity)
        var count = 0

        let start = Core.startFEN(for: game)
        let answered: Bool = start.withCString { startFEN in
            withMoveArray(played) { texts, given in
                guard mxq_rules_evaluate(core, game.raw, startFEN, texts, given,
                                         &position, &status, nil, nil) == MXQ_OK
                else { return false }
                return mxq_rules_legal_moves(core, game.raw, startFEN, texts, given,
                                             &moves, moves.count, &count, nil) == MXQ_OK
            }
        }
        guard answered,
              let evaluation = try? Core.evaluation(position: position, status: status)
        else { return nil }
        return NearbyStanding(
            evaluation: evaluation,
            legalMoves: moves.prefix(count).map {
                string(of: $0.text, capacity: MXQ_MOVE_TEXT_CAP)
            })
    }

    /// The move list as the C array of NUL-terminated strings the facade takes.
    /// Copied rather than borrowed from the Swift strings: `withCString` lends
    /// one buffer per call and nesting it over a whole game would be a recursion
    /// the length of the line.
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
    /// The positions the nearby board draws, over this core.
    var nearbyPositions: CoreNearbyPositions { CoreNearbyPositions(core: handle) }
}
