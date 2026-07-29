// The board's vocabulary: points, pieces, and the position a FEN denotes.
//
// This file reads FEN; it never judges one. Legality, adjudication, and the
// legal-move set all come from the core, and nothing here re-derives them.

import Foundation

/// One of the 49 points, named `a1` through `g7`: files `a`–`g` from Red's
/// left, ranks `1`–`7` from Red's back rank.
struct Square: Hashable {
    var file: Int   // 0...6, a...g
    var rank: Int   // 0...6, rank 1...rank 7

    static let count = 7

    var name: String {
        String(UnicodeScalar(UInt8(97 + file))) + String(rank + 1)
    }

    init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    init?(_ name: some StringProtocol) {
        let characters = Array(name)
        guard characters.count == 2,
              let file = characters[0].asciiValue.map({ Int($0) - 97 }),
              let rank = characters[1].wholeNumberValue.map({ $0 - 1 }),
              (0..<Self.count).contains(file), (0..<Self.count).contains(rank)
        else { return nil }
        self.init(file: file, rank: rank)
    }
}

enum PieceKind: Character, CaseIterable {
    case general = "k"
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
    /// The character is the argument rather than the string, because the ten
    /// piece characters are game content: they are never translated and never
    /// enter the String Catalog. The Chinese half of each of these keys is the
    /// placeholder that lets the character through; the English half is a name
    /// that ignores it.
    func name(for side: Side) -> String {
        let name = switch self {
        case .general: String(localized: "piece.general")
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
    private var pieces: [Square: Piece] = [:]

    subscript(square: Square) -> Piece? { pieces[square] }

    /// Parses the piece-placement field, which lists rank 7 first and rank 1
    /// last. A malformed field yields an empty board rather than a crash: the
    /// FEN came from the core, so a failure here is a bug to see on screen.
    init(fen: String) {
        guard let placement = fen.split(separator: " ").first else { return }
        for (row, line) in placement.split(separator: "/", omittingEmptySubsequences: false).enumerated() {
            let rank = Square.count - 1 - row
            var file = 0
            for character in line {
                if let skip = character.wholeNumberValue {
                    file += skip
                    continue
                }
                let side: Side = character.isUppercase ? .red : .black
                if let kind = PieceKind(rawValue: Character(character.lowercased())),
                   (0..<Square.count).contains(file), (0..<Square.count).contains(rank) {
                    pieces[Square(file: file, rank: rank)] = Piece(kind: kind, side: side)
                }
                file += 1
            }
        }
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

    init?(text: some StringProtocol) {
        guard text.count == 4,
              let from = Square(text.prefix(2)),
              let to = Square(text.suffix(2))
        else { return nil }
        self.init(from: from, to: to)
    }
}
