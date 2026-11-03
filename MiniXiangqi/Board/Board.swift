// This file reads FEN; it never judges one. Legality, adjudication and the
// legal-move set all come from the core.

import Foundation

/// The dimensions and fixed markings of one game's board.
nonisolated struct BoardDefinition: Hashable, Sendable {
    struct Palace: Hashable, Sendable {
        let files: ClosedRange<Int>
        let ranks: ClosedRange<Int>
    }

    /// What everything above branches on: what stands on a point, how many
    /// squares a move spells, how the edges are labelled. The board's rather
    /// than the game's because every consumer already holds a `BoardDefinition`.
    enum Play: Hashable, Sendable {
        /// A piece is taken up and put down somewhere else — the xiangqi games.
        case movement
        /// A stone is placed on an empty point and never moves again.
        case placement
    }

    let fileCount: Int
    let rankCount: Int
    let palaces: [Palace]
    /// The zero-based rank below the river. `nil` means the board has no river.
    let riverAfterRank: Int?
    /// Drawn in the grid's ink. Empty on the xiangqi boards, whose starting
    /// points are deliberately unmarked so nothing competes with live markers.
    let starPoints: [Square]
    let play: Play

    var squareCount: Int { fileCount * rankCount }

    func contains(_ square: Square) -> Bool {
        (0..<fileCount).contains(square.file) && (0..<rankCount).contains(square.rank)
    }
}

extension GameKind {
    nonisolated var isPlacement: Bool { board.play == .placement }

    nonisolated var board: BoardDefinition {
        switch self {
        case .miniXiangqi:
            BoardDefinition(fileCount: 7, rankCount: 7,
                            palaces: [
                                .init(files: 2...4, ranks: 0...2),
                                .init(files: 2...4, ranks: 4...6),
                            ],
                            riverAfterRank: nil,
                            starPoints: [],
                            play: .movement)
        case .xiangqi, .jieqi:
            BoardDefinition(fileCount: 9, rankCount: 10,
                            palaces: [
                                .init(files: 3...5, ranks: 0...2),
                                .init(files: 3...5, ranks: 7...9),
                            ],
                            riverAfterRank: 4,
                            starPoints: [],
                            play: .movement)
        // The five star points a printed 15-line board carries.
        case .gomoku15, .renju:
            BoardDefinition(fileCount: 15, rankCount: 15,
                            palaces: [],
                            riverAfterRank: nil,
                            starPoints: [Square(file: 3, rank: 3),
                                         Square(file: 3, rank: 11),
                                         Square(file: 7, rank: 7),
                                         Square(file: 11, rank: 3),
                                         Square(file: 11, rank: 11)],
                            play: .placement)
        }
    }
}

/// One point, named by a file from Red's left and a rank from Red's back rank.
nonisolated struct Square: Hashable, Sendable {
    var file: Int
    var rank: Int

    /// Also the Go-style edge label. No letter is skipped, because the core
    /// skips none and the edge must agree with every move the list prints.
    var fileLetter: String { String(UnicodeScalar(UInt8(97 + file))) }

    var name: String { fileLetter + String(rank + 1) }

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

    /// Every type has a distinct Red and Black form, so the sides are told
    /// apart by glyph and never by colour alone.
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

    /// For accessibility labels and Help, never a board label. Chinese names a
    /// piece by its character, English by its name: `b1 红 炮 已选择` is
    /// `b1 Red Cannon Selected`. The characters are game content and never
    /// enter the String Catalog, so the Chinese value of each key is the
    /// placeholder that lets the character through and the English one ignores it.
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

/// A stone's `kind` is nil: stones carry no symbol. A face-down piece's `kind`
/// is the role its square gives it, which both players can see, never its
/// hidden identity. No `Piece` ever holds that identity, so nothing that draws
/// or names a piece can leak it; `Placement.concealedIdentity(at:)` is the one
/// place a disclosed identity is read from.
struct Piece: Hashable {
    var kind: PieceKind?
    var side: Side
    /// Jieqi only.
    var isFaceDown = false

    static func stone(_ side: Side) -> Piece { Piece(kind: nil, side: side) }

    var isStone: Bool { kind == nil && !isFaceDown }
}

/// The placement a FEN denotes. Only the placement: the side to move, the
/// counters, and every rule question belong to the core's evaluation.
struct Placement {
    let game: GameKind
    private var pieces: [Square: Piece] = [:]
    /// What the record holds under each face-down disc. Kept out of `Piece` so
    /// nothing that draws a board or composes a label can reach it.
    private var concealed: [Square: PieceKind] = [:]

    var board: BoardDefinition { game.board }

    subscript(square: Square) -> Piece? { pieces[square] }

    /// Only for a piece a capture took off the board and disclosed; nothing on
    /// the board is ever described from this.
    func concealedIdentity(at square: Square) -> PieceKind? { concealed[square] }

    /// Not a rule: the core says whether a side is in check, and this only says
    /// which disc to draw the rings around.
    func general(of side: Side) -> Square? {
        pieces.first { $0.value.kind == .general && $0.value.side == side }?.key
    }

    /// Parses the piece-placement field, highest rank first. A malformed field
    /// yields an empty board rather than a crash: the FEN came from the core, so
    /// a failure here is a bug to see on screen.
    ///
    /// A placement game writes `S`, its case the side. Jieqi writes a face-down
    /// piece as its identity letter followed by `~`; the two are one point.
    init(fen: String, game: GameKind) {
        self.game = game
        guard let placement = fen.split(separator: " ").first else { return }
        let lines = placement.split(separator: "/", omittingEmptySubsequences: false)
        guard lines.count == board.rankCount else { return }

        var parsed: [Square: Piece] = [:]
        var hidden: [Square: PieceKind] = [:]
        for (row, line) in lines.enumerated() {
            let rank = board.rankCount - 1 - row
            var file = 0
            // Runs are decimal: a 15-file board writes an empty rank as `15`.
            var run: Int?
            func closeRun() -> Bool {
                guard let skip = run else { return true }
                guard skip > 0, file + skip <= board.fileCount else { return false }
                file += skip
                run = nil
                return true
            }

            for character in line {
                if character.isASCII, let digit = character.wholeNumberValue {
                    run = (run ?? 0) * 10 + digit
                    continue
                }
                // The mark belongs to the letter before it and never advances
                // the file.
                if character == "~" {
                    let square = Square(file: file - 1, rank: rank)
                    // A doubled mark would bury the identity the record spelled,
                    // so it is malformed.
                    guard game.conceals, parsed[square]?.isFaceDown == false,
                          let identity = parsed[square]?.kind,
                          let role = Self.role(of: square, on: board)
                    else { return }
                    parsed[square]?.kind = role
                    parsed[square]?.isFaceDown = true
                    hidden[square] = identity
                    continue
                }
                guard closeRun() else { return }
                let side: Side = character.isUppercase ? .red : .black
                guard let piece = Self.piece(letter: Character(character.lowercased()),
                                             side: side, on: board),
                      file < board.fileCount else { return }
                parsed[Square(file: file, rank: rank)] = piece
                file += 1
            }
            guard closeRun(), file == board.fileCount else { return }
        }
        pieces = parsed
        concealed = hidden
    }

    /// A face-down piece has never moved, so it stands on its start square and
    /// moves as the Xiangqi piece that starts there. Read from Xiangqi's start
    /// position, since Jieqi's start squares are Xiangqi's; it only names
    /// pieces in the move list and decides nothing about legality.
    private static let squareRoles: [Square: PieceKind] = {
        guard let start = Core.frozenStartFEN(for: .xiangqi) else { return [:] }
        var roles: [Square: PieceKind] = [:]
        let placement = Placement(fen: start, game: .xiangqi)
        for rank in 0..<GameKind.xiangqi.board.rankCount {
            for file in 0..<GameKind.xiangqi.board.fileCount {
                let square = Square(file: file, rank: rank)
                roles[square] = placement[square]?.kind
            }
        }
        return roles
    }()

    private static func role(of square: Square, on board: BoardDefinition) -> PieceKind? {
        guard board == GameKind.xiangqi.board else { return nil }
        return squareRoles[square]
    }

    /// What one lowercased FEN letter denotes on this board.
    private static func piece(letter: Character, side: Side,
                              on board: BoardDefinition) -> Piece? {
        switch board.play {
        case .movement:
            return PieceKind(rawValue: letter).map { Piece(kind: $0, side: side) }
        case .placement:
            return letter == "s" ? .stone(side) : nil
        }
    }
}

/// A move in the canonical notation. No ruleset here has a suffix. A placement
/// spells only the point the stone arrives at, so `from` is nil.
struct Move: Hashable {
    var from: Square?
    var to: Square

    var text: String { (from?.name ?? "") + to.name }

    init(from: Square, to: Square) {
        self.from = from
        self.to = to
    }

    init(placing square: Square) {
        self.from = nil
        self.to = square
    }

    init?(text: some StringProtocol, on board: BoardDefinition) {
        switch board.play {
        case .placement:
            guard let square = Square(text, on: board) else { return nil }
            self.init(placing: square)
        case .movement:
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
}
