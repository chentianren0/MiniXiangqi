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
// every number in the move, not only the file.

import Foundation

enum MoveNotation {

    /// The move as the player reads it, given the placement *before* it.
    static func text(for move: Move, in placement: Placement) -> String {
        guard let piece = placement[move.from] else { return move.text }

        // A disambiguator opens the move and the piece name follows it —
        // 前炮退二, not 炮前退二 — and it replaces the file rather than joining
        // it. A file, when there is one, follows the piece name instead.
        let name = piece.kind.character(for: piece.side)
        let opening: String
        if let marker = disambiguation(for: piece, at: move.from, in: placement) {
            opening = marker + name
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
    /// board is facing: 前 is nearest the opponent, 后 nearest home.
    ///
    /// The accepted contract covers two pieces only. Three is reachable in this
    /// variant — five soldiers a side, moving sideways from the first move — so
    /// it takes 中 for the middle one, which is the same rule and the ordinary
    /// form. Four or more is numbered from the front, again the ordinary form.
    /// Both are noted in issue #37 for confirmation rather than left to fail
    /// silently as an ambiguous file.
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
        default: return numeral(fromFront + 1, for: piece.side)
        }
    }

    /// Files are numbered from each player's own right: Red's right is file g,
    /// Black's is file a.
    private static func number(file: Int, for side: Side) -> String {
        numeral(side == .red ? Square.count - file : file + 1, for: side)
    }

    private static func numeral(_ value: Int, for side: Side) -> String {
        guard side == .red else { return String(value) }
        let chinese = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return (0..<chinese.count).contains(value) ? chinese[value] : String(value)
    }
}
