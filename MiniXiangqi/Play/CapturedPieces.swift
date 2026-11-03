// Only Jieqi shows captured pieces: in a wholly public game what remains is on
// the board, but in Jieqi a capture takes knowledge off it. A captured hidden
// piece is disclosed to its capturer alone, and to both players once the game
// ends by any ending; its owner sees only a count.

import Foundation

/// One piece taken off the board.
struct CapturedPiece: Hashable {
    /// The ply that took it, so a replay can show the game as far as it stands.
    var ply: Int
    /// Whose piece it was.
    var side: Side
    /// Known from the record even for a face-down piece; who may be shown it is
    /// the panel's question.
    var kind: PieceKind
    var wasFaceDown: Bool
}

/// Everything one game has taken, in the order it was taken.
struct CapturedPieces: Equatable {
    var taken: [CapturedPiece] = []

    var isEmpty: Bool { taken.isEmpty }

    /// One side's losses, as one reader is entitled to see them.
    struct Panel: Equatable {
    /// One loss this reader may see.
        struct Shown: Hashable {
            var kind: PieceKind
            var side: Side
            var wasFaceDown: Bool
        }

        var side: Side
        var pieces: [Shown]
    /// How many of that side's losses this reader may not see.
        var hidden: Int
    }

    /// What a reader sees of one side's losses.
    ///
    /// `viewer` is nil where one person holds both hands, as in Free Play.
    /// `disclosed` is whether the game has ended.
    func panel(of side: Side, throughPly ply: Int, seenBy viewer: Side?,
               disclosed: Bool) -> Panel {
        var pieces: [Panel.Shown] = []
        var hidden = 0
        for capture in taken where capture.side == side && capture.ply < ply {
            // A hidden loss is shown to whoever took it, and to both players
            // once the game has ended.
            let shown = !capture.wasFaceDown || disclosed || viewer != side
            if shown {
                pieces.append(Panel.Shown(kind: capture.kind, side: capture.side,
                                          wasFaceDown: capture.wasFaceDown))
            } else {
                hidden += 1
            }
        }
        return Panel(side: side, pieces: pieces, hidden: hidden)
    }

    /// What one ply took, given the position it was played into.
    ///
    /// The victim's identity comes from the record: a face-down disc's `kind`
    /// is the role its square gives it, not what the piece is.
    static func capture(atPly ply: Int, by move: Move,
                        in before: Placement) -> CapturedPiece? {
        guard let victim = before[move.to] else { return nil }
        guard victim.isFaceDown else {
            guard let kind = victim.kind else { return nil }
            return CapturedPiece(ply: ply, side: victim.side, kind: kind,
                                 wasFaceDown: false)
        }
        guard let identity = before.concealedIdentity(at: move.to) else { return nil }
        return CapturedPiece(ply: ply, side: victim.side, kind: identity,
                             wasFaceDown: true)
    }

    /// What every ply of a recorded line took.
    ///
    /// Walked like the move list's reading, from the core's replayed positions,
    /// so a resumed game and a replayed record show the same. An unreadable
    /// stored move fails the walk: skipping it would quietly drop that ply's
    /// capture.
    static func line(for moves: [String], on game: GameKind,
                     placementAt: (Int) throws -> Placement) throws -> CapturedPieces {
        var captured = CapturedPieces()
        guard game.conceals else { return captured }
        for (ply, text) in moves.enumerated() {
            guard let move = Move(text: text, on: game.board) else {
                throw MoveReading.UnreadableStoredMove(ply: ply)
            }
            if let capture = try capture(atPly: ply, by: move,
                                         in: placementAt(ply)) {
                captured.taken.append(capture)
            }
        }
        return captured
    }

    /// Drops everything a retraction took back.
    mutating func removePlies(from ply: Int) {
        taken.removeAll { $0.ply >= ply }
    }
}
