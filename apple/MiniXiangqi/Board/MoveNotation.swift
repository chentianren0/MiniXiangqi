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

        let name = piece.kind.character(for: piece.side)
        let origin = disambiguation(for: piece, at: move.from, in: placement)
            ?? number(file: move.from.file, for: piece.side)

        // 进 is toward the opponent, which is up the board for Red and down for
        // Black; 平 is across, and carries the destination file rather than a
        // distance.
        let forward = piece.side == .red ? move.to.rank > move.from.rank
                                         : move.to.rank < move.from.rank
        if move.to.rank == move.from.rank {
            return name + origin + "平" + number(file: move.to.file, for: piece.side)
        }

        let direction = forward ? "进" : "退"
        // A horse does not move along a line, so what follows its direction is
        // the destination file rather than a number of ranks.
        let value = piece.kind == .horse
            ? number(file: move.to.file, for: piece.side)
            : numeral(abs(move.to.rank - move.from.rank), for: piece.side)
        return name + origin + direction + value
    }

    /// 前 or 后 in place of the file, when two pieces of the same type stand on
    /// one file. 后 names the piece nearer its own side and 前 the one nearer
    /// the opponent — a sense relative to the moving side, and therefore
    /// unaffected by which way the board is facing.
    private static func disambiguation(for piece: Piece, at square: Square,
                                       in placement: Placement) -> String? {
        let sameFile = (0..<Square.count)
            .map { Square(file: square.file, rank: $0) }
            .filter { placement[$0] == piece }
        guard sameFile.count == 2 else { return nil }

        let ownSideIsLow = piece.side == .red     // Red's own side is rank 1
        let nearer = ownSideIsLow ? sameFile.min(by: { $0.rank < $1.rank })
                                  : sameFile.max(by: { $0.rank < $1.rank })
        return square == nearer ? "后" : "前"
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
