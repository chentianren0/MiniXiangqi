// How a Jieqi move is read.
//
// docs/interaction-design.md, "The Jieqi board": "The move list's rendering is
// deliberately not fixed here, and this is what settles it. No convention for
// reading a Jieqi move exists to follow, so the rendering is designed rather
// than transcribed, and it is settled with the surface that draws it rather
// than in prose ahead of it." Two things bound it, and both hold below: the
// canonical `"<from><to>"` notation is what archives, fixtures and the core
// interface store and exchange, and nothing here ever reaches them; and a
// rendering may show only what the player reading it is entitled to know.
//
// **One rendering, not two.** That document's notation section says Jieqi's
// board edges follow the 记谱法 preference and its move list does not, for the
// reason above: the preference chooses between two transcribed conventions for
// a game that has them, and this game's reading is designed here. So a Jieqi
// game reads the same whichever way the preference stands, exactly as a
// placement game's coordinate reading does.
//
// **The shape is WXF's — a letter, a file, a direction, a value.** Three
// reasons, in the order they decided it:
//
//   - A Jieqi move has to carry two facts a Xiangqi move does not: that the
//     mover was face down, and what it turned up as. The cell that draws it is
//     the cell a Xiangqi move gets, and the traditional reading's characters are
//     square: four of them already fill that cell, and a reading with six would
//     wrap every row of the list. Letters and digits fit, which is what
//     "settled with the surface that draws it" means here.
//   - One rendering has to serve both readers. The Chinese reading is a language
//     as well as a notation; the letters and digits are the international
//     Xiangqi notation and are the same for a reader of either interface, which
//     is the fairer answer for a reading nobody has learned yet.
//   - Its files are numbered from each player's own right in Arabic for both
//     sides, which is exactly what the board's edge strips show under the WXF
//     preference and what Black's edge shows under the traditional one. Red's
//     traditional edge reads 八 where the list reads 8 — the same file, in the
//     script that edge is in.
//
// Two additions to that shape, and nothing else:
//
//   - **A face-down mover is named by the role its square gives it, marked
//     `~`** — `H~8+7`. The role is what the move's geometry is written in: a
//     hidden piece moves as the piece that starts on its square, and `+7` means
//     a destination file for a horse where it would mean a count of ranks for a
//     chariot, so naming the piece by the identity it turned up as would make
//     the rest of the move read wrongly. The role is public — the square says
//     it, and both players see the square — and the mark is the one the position
//     record itself uses for a face-down piece.
//   - **The reveal is the last of the ply, after a colon** — `H~8+7:C`. Every
//     move of a face-down piece flips it, always, so no word is needed to say
//     that a reveal happened; what a reader needs is what it turned up as, and
//     it is read off the piece standing face up at the destination afterwards.
//     A move that reveals nothing carries no colon, so the two never blur.
//
// A revealed piece's move is the WXF move, unchanged: a revealed piece is a
// piece of that kind moving on a Xiangqi board, and it reads as one.

import Foundation

enum JieqiNotation {

    /// The move as the player reads it: the placement before it, and the
    /// placement it produced.
    ///
    /// The reveal is taken from `after` rather than from what the record holds
    /// under the face-down disc in `before`. The two are the same identity, and
    /// this is the one that cannot be read early: the piece is face up in the
    /// position afterwards, and a face-up piece's identity is public.
    static func text(for move: Move, in before: Placement, after: Placement?) -> String {
        let text = WXFNotation.text(for: move, in: before)
        guard let revealed = reveal(of: move, in: before, after: after) else {
            return text
        }
        return text + ":" + WXFNotation.letter(revealed)
    }

    /// What the ply turned up, where it turned anything up: the kind of the
    /// piece standing face up at the destination once a face-down piece has
    /// moved there.
    ///
    /// Answers nil where the mover was already face up, and where the position
    /// afterwards was not given — a line being read back one ply at a time
    /// reaches the last ply with a position after it, and a caller that has
    /// none has nothing to disclose either.
    private static func reveal(of move: Move, in before: Placement,
                               after: Placement?) -> PieceKind? {
        guard let origin = move.from, before[origin]?.isFaceDown == true,
              let arrived = after?[move.to], !arrived.isFaceDown
        else { return nil }
        return arrived.kind
    }
}
