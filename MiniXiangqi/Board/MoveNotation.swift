// Display only; the canonical `"<from><to>"` notation is what is stored.
// Red writes every number in a move as a Chinese numeral, Black as Arabic.

import Foundation

enum MoveNotation {

    /// The move as the player reads it, given the placement *before* it.
    static func text(for move: Move, in placement: Placement) -> String {
        // Only movement moves reach here; `MoveReading` answers placement games.
        guard let origin = move.from, let piece = placement[origin],
              let kind = piece.kind
        else { return move.text }
        let board = placement.board

        // A disambiguator replaces the file and precedes the name: 前炮退二.
        let name = kind.character(for: piece.side)
        let opening: String
        if let marker = disambiguation(for: piece, at: origin, in: placement) {
            // With a second file doubled, the origin file returns after the
            // name: 前兵六进一, 后卒3进1.
            opening = doubledFiles(of: piece, in: placement) > 1
                ? marker + name + number(file: origin.file, for: piece.side, on: board)
                : marker + name
        } else {
            opening = name + number(file: origin.file, for: piece.side, on: board)
        }

        let forward = piece.side == .red ? move.to.rank > origin.rank
                                         : move.to.rank < origin.rank
        if move.to.rank == origin.rank {
            return opening + "平" + number(file: move.to.file, for: piece.side, on: board)
        }

        let direction = forward ? "进" : "退"
        // Pieces that do not move along a file give the destination file.
        let value = switch kind {
        case .horse, .advisor, .elephant:
            number(file: move.to.file, for: piece.side, on: board)
        case .general, .chariot, .cannon, .soldier:
            numeral(abs(move.to.rank - origin.rank), for: piece.side)
        }
        return opening + direction + value
    }

    /// Counted from the opponent's end, so it does not depend on board
    /// orientation. Four or more on a file (five soldiers can do it) are
    /// numbered from the front.
    private static func disambiguation(for piece: Piece, at square: Square,
                                       in placement: Placement) -> String? {
        let sameFile = (0..<placement.board.rankCount)
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

    /// Two or more doubled files restore the origin file. Only soldiers reach
    /// it, and never together with the numbered form, which needs four on a file.
    private static func doubledFiles(of piece: Piece, in placement: Placement) -> Int {
        (0..<placement.board.fileCount).count { file in
            (0..<placement.board.rankCount).count { rank in
                placement[Square(file: file, rank: rank)] == piece
            } >= 2
        }
    }

    /// Numbered from each player's own right, from the board's file count.
    private static func number(file: Int, for side: Side,
                               on board: BoardDefinition) -> String {
        numeral(side == .red ? board.fileCount - file : file + 1, for: side)
    }

    private static func numeral(_ value: Int, for side: Side) -> String {
        side == .red ? chineseNumeral(value) : String(value)
    }

    private static func chineseNumeral(_ value: Int) -> String {
        let chinese = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return (0..<chinese.count).contains(value) ? chinese[value] : String(value)
    }
}
