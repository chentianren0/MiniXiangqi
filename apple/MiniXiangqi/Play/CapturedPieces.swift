// What a game has taken off the board, and what each player may be shown of it.
//
// docs/interaction-design.md, "Captured pieces": in every game whose position is
// wholly public, captured pieces are not displayed — what remains is visible on
// the board, and a second inventory would compete with the primary position
// without changing any action. **Jieqi displays them, because there the
// reasoning does not hold: what a capture takes off the board is knowledge, and
// knowledge is that game's material.**
//
// Each part of the surface says exactly what docs/jieqi-rules.md entitles the
// player looking at it to know, and that document's disclosure section is the
// whole of the rule below:
//
//   - A captured **revealed** piece was public to both players on the board, and
//     taking it changes nothing about that.
//   - A captured **hidden** piece is disclosed to its **capturer** alone. Its
//     owner learns only that a piece is gone, so on their own side of the
//     surface that loss is a count and nothing more.
//   - **When the game ends, every hidden identity is disclosed to both
//     players**, by any ending, so every count resolves into the pieces it was
//     counting.
//
// The two players' surfaces are therefore not the same surface, and both are
// right. Free Play is the one place one person sees both: they made every
// capture on the board, so every disclosure is theirs and nothing there is ever
// a count.
//
// **Nothing here decides a rule and nothing re-derives one.** What was taken is
// read off the two positions the core reports for a ply — a capture is a
// destination that was occupied — and what the victim was is read off the
// record, which holds every hidden identity. Who may see it is the disclosure
// rule above, applied to a reader this type is told about.

import Foundation

/// One piece taken off the board.
struct CapturedPiece: Hashable {
    /// The ply that took it, so a surface can show a game as far as it stands
    /// — which is what a replay walking through one needs.
    var ply: Int
    /// Whose piece it was.
    var side: Side
    /// What it was. The record holds this whether the piece stood face up or
    /// face down; who may be shown it is the panel's question and not this
    /// value's.
    var kind: PieceKind
    /// Whether it left the board face down, which is what makes its identity a
    /// disclosure to one player rather than a fact both hold.
    var wasFaceDown: Bool
}

/// Everything one game has taken, in the order it was taken.
struct CapturedPieces: Equatable {
    var taken: [CapturedPiece] = []

    var isEmpty: Bool { taken.isEmpty }

    /// One side's losses, as one reader is entitled to see them.
    struct Panel: Equatable {
        /// Whose losses these are.
        var side: Side
        /// The discs to draw, in the order they were taken.
        var pieces: [Piece]
        /// How many of that side's losses this reader may not see. Zero
        /// wherever the reader is the capturer, and zero everywhere once the
        /// game has disclosed.
        var hidden: Int
    }

    /// What a reader sees of one side's losses.
    ///
    /// - Parameters:
    ///   - side: whose losses are being shown.
    ///   - ply: how far into the game the surface stands. A live board is at
    ///     its own last ply; a replay is wherever it has walked to.
    ///   - viewer: whose eyes these are, or nil where one person holds both
    ///     hands — Free Play, where every capture on the board was theirs.
    ///   - disclosed: whether the game has ended, which discloses everything to
    ///     both players.
    func panel(of side: Side, throughPly ply: Int, seenBy viewer: Side?,
               disclosed: Bool) -> Panel {
        var pieces: [Piece] = []
        var hidden = 0
        for capture in taken where capture.side == side && capture.ply < ply {
            // A hidden loss is shown to whoever took it, to both players once
            // the game has ended, and to nobody else — its owner learns only
            // that a piece is gone.
            let shown = !capture.wasFaceDown || disclosed || viewer != side
            if shown {
                pieces.append(Piece(kind: capture.kind, side: capture.side))
            } else {
                hidden += 1
            }
        }
        return Panel(side: side, pieces: pieces, hidden: hidden)
    }

    /// What one ply took, given the position it was played into. Nil where it
    /// took nothing.
    ///
    /// The victim's identity comes from the record rather than from the disc:
    /// a face-down piece's `kind` is the role its square gives it, and what the
    /// capture discloses is what the record holds under it.
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

    /// A whole recorded line, read back: what every ply of it took.
    ///
    /// Walked exactly as the move list's own reading is walked, from the
    /// positions the core replays, so a resumed game and a replayed record
    /// answer with the same surface. It is asked only of a game that conceals —
    /// every other game displays nothing, and the walk is what that costs.
    ///
    /// A stored move this app cannot read fails the walk, exactly as it fails
    /// the reading beside it: a line the core validated before any session over
    /// it existed cannot legitimately hold one, and a surface that skipped it
    /// would quietly show a game missing whatever that ply took.
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

    /// Drops everything a retraction took back: the plies from `ply` on are no
    /// longer part of the game.
    mutating func removePlies(from ply: Int) {
        taken.removeAll { $0.ply >= ply }
    }
}
