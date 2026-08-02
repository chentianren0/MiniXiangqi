// The board's vocabulary: points, pieces, and the position a FEN denotes.
//
// This file reads FEN; it never judges one. Legality, adjudication, and the
// legal-move set all come from the core, and nothing here re-derives them.

import Foundation

/// The dimensions and fixed markings of one game's board. Rules and legality
/// still belong to the core; this is only the topology the Apple UI presents.
nonisolated struct BoardDefinition: Hashable, Sendable {
    struct Palace: Hashable, Sendable {
        let files: ClosedRange<Int>
        let ranks: ClosedRange<Int>
    }

    let fileCount: Int
    let rankCount: Int
    let palaces: [Palace]
    /// The zero-based rank below the river. `nil` means the board has no river.
    let riverAfterRank: Int?

    var squareCount: Int { fileCount * rankCount }

    func contains(_ square: Square) -> Bool {
        (0..<fileCount).contains(square.file) && (0..<rankCount).contains(square.rank)
    }
}

extension GameKind {
    nonisolated var board: BoardDefinition {
        switch self {
        case .miniXiangqi:
            BoardDefinition(fileCount: 7, rankCount: 7,
                            palaces: [
                                .init(files: 2...4, ranks: 0...2),
                                .init(files: 2...4, ranks: 4...6),
                            ],
                            riverAfterRank: nil)
        case .xiangqi:
            BoardDefinition(fileCount: 9, rankCount: 10,
                            palaces: [
                                .init(files: 3...5, ranks: 0...2),
                                .init(files: 3...5, ranks: 7...9),
                            ],
                            riverAfterRank: 4)
        }
    }
}

/// One point, named by a file from Red's left and a rank from Red's back rank.
nonisolated struct Square: Hashable, Sendable {
    var file: Int
    var rank: Int

    var name: String {
        String(UnicodeScalar(UInt8(97 + file))) + String(rank + 1)
    }

    init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    init?(_ name: some StringProtocol, on board: BoardDefinition) {
        let characters = Array(name)
        let rankText = String(characters.dropFirst())
        guard characters.count >= 2,
              let file = characters[0].asciiValue.map({ Int($0) - 97 }),
              rankText.first != "0", let displayedRank = Int(rankText)
        else { return nil }
        let square = Square(file: file, rank: displayedRank - 1)
        guard board.contains(square) else { return nil }
        self = square
    }
}

enum PieceKind: Character, CaseIterable {
    case general = "k"
    case advisor = "a"
    case elephant = "b"
    case chariot = "r"
    case horse = "n"
    case cannon = "c"
    case soldier = "p"

    /// The accepted piece characters. Every type has a distinct Red and Black
    /// form, so the sides are told apart by glyph and never by colour alone.
    func character(for side: Side) -> String {
        switch (self, side) {
        case (.general, .red): "帅"
        case (.general, .black): "将"
        case (.advisor, .red): "仕"
        case (.advisor, .black): "士"
        case (.elephant, .red): "相"
        case (.elephant, .black): "象"
        case (.chariot, .red): "俥"
        case (.chariot, .black): "车"
        case (.horse, .red): "傌"
        case (.horse, .black): "马"
        case (.cannon, .red): "炮"
        case (.cannon, .black): "砲"
        case (.soldier, .red): "兵"
        case (.soldier, .black): "卒"
        }
    }

    /// How the piece is named where words are used rather than the board's own
    /// glyph — an accessibility label, a line of Help — and never as a board
    /// label in any language.
    ///
    /// docs/copy.md, "Where the two languages deliberately do not match one to
    /// one": the accessibility representation switches with the language.
    /// Chinese names a piece by the character it carries, because that is what
    /// the board shows and what the reader is learning; English names it by its
    /// piece name and never by the character. So `b1 红 炮 已选择` is
    /// `b1 Red Cannon Selected` and not `b1 Red 炮 Selected`.
    ///
    /// The character is the argument rather than the string, because the fourteen
    /// piece characters are game content: they are never translated and never
    /// enter the String Catalog. The Chinese half of each of these keys is the
    /// placeholder that lets the character through; the English half is a name
    /// that ignores it.
    func name(for side: Side) -> String {
        let name = switch self {
        case .general: String(localized: "piece.general")
        case .advisor: String(localized: "piece.advisor")
        case .elephant: String(localized: "piece.elephant")
        case .chariot: String(localized: "piece.chariot")
        case .horse: String(localized: "piece.horse")
        case .cannon: String(localized: "piece.cannon")
        case .soldier: String(localized: "piece.soldier")
        }
        return String(format: name, character(for: side))
    }
}

struct Piece: Hashable {
    var kind: PieceKind
    var side: Side
}

/// The placement a FEN denotes. Only the placement: the side to move, the
/// counters, and every rule question belong to the core's evaluation.
struct Placement {
    let game: GameKind
    private var pieces: [Square: Piece] = [:]

    var board: BoardDefinition { game.board }

    subscript(square: Square) -> Piece? { pieces[square] }

    /// Where a side's general stands. Not a rule and not an adjudication — the
    /// core says whether a side is in check, and this only says which disc to
    /// draw the rings around — but it is asked from two places now, play and
    /// replay, so it is written once.
    func general(of side: Side) -> Square? {
        pieces.first { $0.value.kind == .general && $0.value.side == side }?.key
    }

    /// Parses the piece-placement field, which lists the highest rank first and
    /// rank 1 last. A malformed field yields an empty board rather than a crash: the
    /// FEN came from the core, so a failure here is a bug to see on screen.
    init(fen: String, game: GameKind) {
        self.game = game
        guard let placement = fen.split(separator: " ").first else { return }
        let lines = placement.split(separator: "/", omittingEmptySubsequences: false)
        guard lines.count == board.rankCount else { return }

        var parsed: [Square: Piece] = [:]
        for (row, line) in lines.enumerated() {
            let rank = board.rankCount - 1 - row
            var file = 0
            for character in line {
                if let skip = character.wholeNumberValue {
                    guard skip > 0, file + skip <= board.fileCount else { return }
                    file += skip
                    continue
                }
                let side: Side = character.isUppercase ? .red : .black
                guard let kind = PieceKind(rawValue: Character(character.lowercased())),
                      file < board.fileCount else { return }
                parsed[Square(file: file, rank: rank)] = Piece(kind: kind, side: side)
                file += 1
            }
            guard file == board.fileCount else { return }
        }
        pieces = parsed
    }
}

/// A move in the frozen canonical notation, `"<from><to>"`. There is no suffix:
/// this ruleset has no promotion, castling, en passant, drop, or gating.
struct Move: Hashable {
    var from: Square
    var to: Square

    var text: String { from.name + to.name }

    init(from: Square, to: Square) {
        self.from = from
        self.to = to
    }

    init?(text: some StringProtocol, on board: BoardDefinition) {
        let characters = Array(text)
        guard (4...6).contains(characters.count) else { return nil }

        let candidates = [2, 3].compactMap { split -> (Square, Square)? in
            guard split < characters.count,
                  let from = Square(String(characters[..<split]), on: board),
                  let to = Square(String(characters[split...]), on: board)
            else { return nil }
            return (from, to)
        }
        guard candidates.count == 1, let (from, to) = candidates.first else { return nil }
        self.init(from: from, to: to)
    }
}
