// WXF move notation, for the move list and the board's numeral strips whenever
// the 记谱法 preference selects it.
//
// Presentation only, exactly as the traditional reading beside it is: the
// canonical `"<from><to>"` notation frozen in docs/xiangqi-rules.md remains what
// archives, fixtures, and the core interface store and exchange. Nothing here
// ever reaches them, and a game reads the same whichever notation is selected.
//
// The rules are docs/interaction-design.md, "WXF rendering" — clauses W1 to W8,
// and the readings recorded beneath them. A move is `[piece][origin][direction]
// [value]` with no spaces. The piece letters are K, R, H, C and P. Files are
// numbered 1 to 7 from each player's own right, in Arabic numerals for both
// sides — which is where WXF parts company with the traditional reading's 一 to
// 七 for Red. The directions are `+` advance, `-` retreat and `=` traverse. The
// value is the number of ranks moved when the move stays on its file, and the
// destination file when it does not.
//
// Pieces are identified exactly as the traditional reading identifies them: in
// the mover's own frame, with the front of a file the end nearer the opponent,
// and with the identification applied whenever more than one of a type stands
// on a file rather than only when a move would otherwise be ambiguous. So a
// player who flips 记谱法 sees the same move identified the same way in
// different clothes. What changes is the clothes — a marker or an index stands
// where a Chinese word would, and it follows the piece letter rather than
// opening the move.

import Foundation

enum WXFNotation {

    /// The move as the player reads it, given the placement *before* it.
    static func text(for move: Move, in placement: Placement) -> String {
        guard let piece = placement[move.from] else { return move.text }

        // W1's first two slots. The piece slot carries the type's letter unless
        // an index has replaced it; the origin slot carries the file unless a
        // marker has replaced it. Only one of the two is ever substituted.
        let opening: String
        switch origin(of: piece, at: move.from, in: placement) {
        case .file:
            opening = letter(piece.kind) + number(file: move.from.file, for: piece.side)
        case .marker(let marker):
            // W3: the marker stands in the file's own slot, after the letter —
            // R+=3, not +R=3 — and the file itself goes.
            opening = letter(piece.kind) + marker
        case .index(let index):
            // W4 and W5: the index stands in the letter's slot instead, and the
            // file stays where it was.
            opening = String(index) + number(file: move.from.file, for: piece.side)
        }

        // `+` is toward the opponent, which is up the board for Red and down for
        // Black; `=` is across, and a move across is the one that cannot be a
        // move along a file.
        let direction: String
        if move.to.rank == move.from.rank {
            direction = "="
        } else {
            let forward = piece.side == .red ? move.to.rank > move.from.rank
                                             : move.to.rank < move.from.rank
            direction = forward ? "+" : "-"
        }

        // W2 is geometry rather than a list of piece types: a move that stays on
        // its file counts the ranks it crossed, and a move that leaves its file
        // names the file it arrived on. On this board the horse is the only
        // piece that leaves its file while changing rank, so it is the only one
        // that names a file after `+` or `-` — but the clause never has to say
        // so.
        let value = move.to.file == move.from.file
            ? String(abs(move.to.rank - move.from.rank))
            : number(file: move.to.file, for: piece.side)
        return opening + direction + value
    }

    /// What stands in the origin slot, and whether it displaced the piece
    /// letter on the way.
    private enum Origin {
        /// The plain form: the letter, then the origin file.
        case file
        /// W3's marker form: the letter, then `+` or `-` where the file was.
        case marker(String)
        /// W4 and W5's indexed form: the index where the letter was, then the
        /// origin file.
        case index(Int)
    }

    /// The implementation condition the clause table states: the indexed form
    /// whenever three or more of the mover's pieces of the type stand on the
    /// file, or two of the mover's files each carry two or more — where a bare
    /// marker would no longer say which file moved; the marker form when exactly
    /// two stand on the file and it is the type's only doubled file; the plain
    /// form otherwise.
    ///
    /// Ordered from the opponent's end towards the mover's own, so front means
    /// nearer the opponent and index 1 is the frontmost, and the sense is
    /// unaffected by which way the board is facing.
    private static func origin(of piece: Piece, at square: Square,
                               in placement: Placement) -> Origin {
        let onFile = (0..<Square.count)
            .map { Square(file: square.file, rank: $0) }
            .filter { placement[$0] == piece }
        guard onFile.count > 1, let index = onFile.firstIndex(of: square) else {
            return .file
        }

        // Red's own side is rank 1, so for Red the front of a file is the
        // highest rank; for Black it is the lowest.
        let fromFront = piece.side == .red ? onFile.count - 1 - index : index

        if onFile.count > 2 || doubledFiles(of: piece, in: placement) > 1 {
            return .index(fromFront + 1)
        }
        return .marker(fromFront == 0 ? "+" : "-")
    }

    /// How many of the mover's files carry two or more of this piece. One is an
    /// ordinary marker; two or more promotes every pair on a doubled file to the
    /// indexed form — reachable only for soldiers, as 2-2 or 3-2, since two
    /// doubled files is this board's maximum. A soldier alone on its file is
    /// never counted and keeps the plain form.
    private static func doubledFiles(of piece: Piece, in placement: Placement) -> Int {
        (0..<Square.count).count { file in
            (0..<Square.count).count { rank in
                placement[Square(file: file, rank: rank)] == piece
            } >= 2
        }
    }

    /// The standard's letters, one per type and the same for both sides: which
    /// side moved is carried by the direction the files are numbered in and by
    /// the list's own two columns, never by the letter.
    ///
    /// K and P are the standard's own mnemonics — King and Pawn — where this
    /// app's prose says General and Soldier. The tension is recorded in the
    /// contract and deliberately not reconciled: G and S are attested by no WXF
    /// document, and G means Guard in the computer ecosystem's own letter set,
    /// so either substitution would break with every WXF-conformant reader and
    /// tool.
    private static func letter(_ kind: PieceKind) -> String {
        switch kind {
        case .general: "K"
        case .chariot: "R"
        case .horse: "H"
        case .cannon: "C"
        case .soldier: "P"
        }
    }

    /// Files are numbered from each player's own right: Red's right is file g,
    /// Black's is file a. Arabic for both sides — unlike the traditional
    /// reading, WXF has no second script for Red.
    private static func number(file: Int, for side: Side) -> String {
        String(side == .red ? Square.count - file : file + 1)
    }
}
