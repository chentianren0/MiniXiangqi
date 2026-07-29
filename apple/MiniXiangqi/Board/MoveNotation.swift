// Traditional Xiangqi notation, for the move list and anything else the player
// reads.
//
// This is presentation only. The canonical `"<from><to>"` notation frozen in
// docs/xiangqi-rules.md remains what archives, fixtures, and the core interface
// store and exchange; nothing here ever reaches them.
//
// The rules are docs/interaction-design.md, "User-visible notation": a move
// names the piece, its file, a direction, and a value. Files are numbered from
// each player's own right, so the two sides number them in opposite directions,
// and Red writes its numbers as Chinese numerals while Black writes Arabic —
// every number in the move, not only the file. The one word outside that rule
// is the ordinal that numbers four or more on a file: it continues 前/中/后
// rather than counting anything, and is Chinese for both sides.

import Foundation

enum MoveNotation {

    /// A stored line, read as it was written: each move's notation from the
    /// placement before it, which the core supplies ply by ply.
    ///
    /// This is the one way a recorded game becomes words, and both readers of a
    /// stored game go through it — the resumed active game and a History
    /// record's replay — so a relaunch and a replay read a sitting exactly as
    /// the sitting itself did. Quadratic in the line's length, because each
    /// placement is a walk from the start; a game's own length is the measure
    /// of what reading it is worth.
    static func line(for moves: [String],
                     placementBefore: (Int) throws -> Placement) throws -> [String] {
        try moves.enumerated().map { ply, text in
            guard let move = Move(text: text) else {
                throw UnreadableStoredMove(ply: ply)
            }
            return self.text(for: move, in: try placementBefore(ply))
        }
    }

    /// A stored move this app cannot read, which a stored line can never
    /// legitimately contain: the core validated the whole of it before any
    /// session over it existed.
    struct UnreadableStoredMove: Error, CustomStringConvertible {
        var ply: Int
        var description: String { "the stored line holds no move at ply \(ply)" }
    }

    /// The move as the player reads it, given the placement *before* it.
    static func text(for move: Move, in placement: Placement) -> String {
        guard let piece = placement[move.from] else { return move.text }

        // A disambiguator opens the move and the piece name follows it —
        // 前炮退二, not 炮前退二 — and it replaces the file rather than joining
        // it. A file, when there is one, follows the piece name instead.
        let name = piece.kind.character(for: piece.side)
        let opening: String
        if let marker = disambiguation(for: piece, at: move.from, in: placement) {
            // With a second file doubled, the leading word alone no longer
            // says which piece moved, so the origin file returns after the
            // name — 前兵六进一, 后卒3进1. Pieces alone on their file never
            // reach here and keep the plain form.
            opening = doubledFiles(of: piece, in: placement) > 1
                ? marker + name + number(file: move.from.file, for: piece.side)
                : marker + name
        } else {
            opening = name + number(file: move.from.file, for: piece.side)
        }

        // 进 is toward the opponent, which is up the board for Red and down for
        // Black; 平 is across, and carries the destination file rather than a
        // distance.
        let forward = piece.side == .red ? move.to.rank > move.from.rank
                                         : move.to.rank < move.from.rank
        if move.to.rank == move.from.rank {
            return opening + "平" + number(file: move.to.file, for: piece.side)
        }

        let direction = forward ? "进" : "退"
        // A horse does not move along a line, so what follows its direction is
        // the destination file rather than a number of ranks.
        let value = piece.kind == .horse
            ? number(file: move.to.file, for: piece.side)
            : numeral(abs(move.to.rank - move.from.rank), for: piece.side)
        return opening + direction + value
    }

    /// What replaces the file when more than one piece of the same type stands
    /// on it. Ordered from the opponent's end towards the mover's own, so the
    /// sense is relative to the moving side and unaffected by which way the
    /// board is facing: 前 is nearest the opponent, 后 nearest home. Three take
    /// 前, 中 and 后; four or more are numbered from the front — reachable
    /// here, with five sideways-capable soldiers a side.
    private static func disambiguation(for piece: Piece, at square: Square,
                                       in placement: Placement) -> String? {
        let sameFile = (0..<Square.count)
            .map { Square(file: square.file, rank: $0) }
            .filter { placement[$0] == piece }
        guard sameFile.count > 1, let index = sameFile.firstIndex(of: square) else {
            return nil
        }

        // Red's own side is rank 1, so for Red the front of the file is the
        // highest rank; for Black it is the lowest.
        let fromFront = piece.side == .red
            ? sameFile.count - 1 - index
            : index

        switch (sameFile.count, fromFront) {
        case (2, 0): return "前"
        case (2, _): return "后"
        case (3, 0): return "前"
        case (3, 1): return "中"
        case (3, _): return "后"
        // The ordinal continues 前/中/后 rather than counting anything, so it
        // is Chinese for both sides: 一卒进1, never 1卒进1.
        default: return chineseNumeral(fromFront + 1)
        }
    }

    /// How many of the mover's files carry two or more of this piece. One is
    /// ordinary disambiguation; two or more restores the file — reachable only
    /// for soldiers, as 2-2 or 3-2, and never together with the numbered form,
    /// which needs four on a single file.
    private static func doubledFiles(of piece: Piece, in placement: Placement) -> Int {
        (0..<Square.count).count { file in
            (0..<Square.count).count { rank in
                placement[Square(file: file, rank: rank)] == piece
            } >= 2
        }
    }

    /// Files are numbered from each player's own right: Red's right is file g,
    /// Black's is file a.
    private static func number(file: Int, for side: Side) -> String {
        numeral(side == .red ? Square.count - file : file + 1, for: side)
    }

    private static func numeral(_ value: Int, for side: Side) -> String {
        side == .red ? chineseNumeral(value) : String(value)
    }

    private static func chineseNumeral(_ value: Int) -> String {
        let chinese = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return (0..<chinese.count).contains(value) ? chinese[value] : String(value)
    }
}
