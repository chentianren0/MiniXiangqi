// Display only; the canonical `"<from><to>"` notation is what is stored.
// Pieces on a shared file are identified exactly as the traditional reading
// identifies them, so flipping 记谱法 changes only how a move is written.

import Foundation

enum WXFNotation {

    /// The move as the player reads it, given the placement *before* it.
    static func text(for move: Move, in placement: Placement) -> String {
        // Only movement moves reach here; `MoveReading` answers placement games.
        guard let source = move.from, let piece = placement[source],
              let kind = piece.kind
        else { return move.text }
        let board = placement.board

        // Only one of the letter and the file is ever substituted. A face-down
        // piece carries `~`, the position record's own mark, after a letter that
        // is the role its square gives it.
        let mark = piece.isFaceDown ? "~" : ""
        let opening: String
        switch origin(of: piece, at: source, in: placement) {
        case .file:
            opening = letter(kind) + mark + number(file: source.file, for: piece.side,
                                                   on: board)
        case .marker(let marker):
            // The marker replaces the file, after the letter: R+=3, not +R=3.
            opening = letter(kind) + mark + marker
        case .index(let index):
            opening = String(index) + mark + number(file: source.file, for: piece.side,
                                                    on: board)
        }

        let direction: String
        if move.to.rank == source.rank {
            direction = "="
        } else {
            let forward = piece.side == .red ? move.to.rank > source.rank
                                             : move.to.rank < source.rank
            direction = forward ? "+" : "-"
        }

        // Geometry rather than piece type, so every piece that leaves its file
        // is covered without a branch.
        let value = move.to.file == source.file
            ? String(abs(move.to.rank - source.rank))
            : number(file: move.to.file, for: piece.side, on: board)
        return opening + direction + value
    }

    private enum Origin {
        case file
        /// `+` or `-` where the file was.
        case marker(String)
        /// The index where the letter was.
        case index(Int)
    }

    /// Front is nearer the opponent, so index 1 is the frontmost whichever way
    /// the board faces.
    ///
    /// `Piece` equality includes the face-down state, so face-down pieces are
    /// compared only with each other, and one never reaches a substituted form:
    /// no file has two start squares of the same role.
    private static func origin(of piece: Piece, at square: Square,
                               in placement: Placement) -> Origin {
        let onFile = (0..<placement.board.rankCount)
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

    /// Two or more promote every pair on a doubled file to the indexed form;
    /// only soldiers reach it.
    private static func doubledFiles(of piece: Piece, in placement: Placement) -> Int {
        (0..<placement.board.fileCount).count { file in
            (0..<placement.board.rankCount).count { rank in
                placement[Square(file: file, rank: rank)] == piece
            } >= 2
        }
    }

    /// One letter per type for both sides. K and P are WXF's own (King, Pawn);
    /// G and S would break with every WXF-conformant reader and tool.
    static func letter(_ kind: PieceKind) -> String {
        switch kind {
        case .general: "K"
        case .advisor: "A"
        case .elephant: "E"
        case .chariot: "R"
        case .horse: "H"
        case .cannon: "C"
        case .soldier: "P"
        }
    }

    /// Numbered from each player's own right, in Arabic for both sides.
    private static func number(file: Int, for side: Side,
                               on board: BoardDefinition) -> String {
        String(side == .red ? board.fileCount - file : file + 1)
    }
}
