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

    /// How a game reaches the board, which is what everything above this type
    /// branches on: what stands on a point, how many squares a move spells, and
    /// how the edges are labelled.
    ///
    /// It is the board's rather than the game's because those three questions
    /// are all about the board, and because every consumer here already holds a
    /// `BoardDefinition` and would otherwise have to be handed the game beside
    /// it. The core makes the same division: `MXQ_ERR_RULES_MALFORMED_MOVE`
    /// spells one grammar per game and says how many squares a move is "follows
    /// from the game and never from the text's length".
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
    /// The board's own printed reference points, drawn in the grid's ink as part
    /// of the grid. Empty where a board has none — the xiangqi boards, whose
    /// starting points are deliberately unmarked so that nothing competes with
    /// the markers carrying live information.
    let starPoints: [Square]
    let play: Play

    var squareCount: Int { fileCount * rankCount }

    func contains(_ square: Square) -> Bool {
        (0..<fileCount).contains(square.file) && (0..<rankCount).contains(square.rank)
    }
}

extension GameKind {
    /// Whether this game places stones rather than moving pieces — asked often
    /// enough that it is written once instead of spelling `board.play` at each
    /// site, and here rather than beside the game's other names because it is a
    /// fact about the board.
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
        // Jieqi's board, palaces, river and start squares are Xiangqi's exactly,
        // per docs/jieqi-rules.md — so the definition is Xiangqi's, written out
        // rather than shared through a fallthrough, because what makes the two
        // agree is that statement about the games and not a line of code either
        // of them could move.
        case .xiangqi, .jieqi:
            BoardDefinition(fileCount: 9, rankCount: 10,
                            palaces: [
                                .init(files: 3...5, ranks: 0...2),
                                .init(files: 3...5, ranks: 7...9),
                            ],
                            riverAfterRank: 4,
                            starPoints: [],
                            play: .movement)
        // The two placement boards are one board: fifteen lines each way, no
        // palace, no river, and the five star points a 15-line board carries —
        // the four at the fourth line in from each corner and the one at the
        // centre, which is where a printed set puts them.
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

    /// The file's letter, which is also what a Go-style edge is labelled with.
    /// No letter is skipped: this is the core's own spelling, and an edge that
    /// left one out would disagree with every move the list prints.
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
    /// docs/interaction-design.md § Piece representation: the accessibility
    /// representation switches with the language.
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

/// What stands on a point.
///
/// A movement game's piece carries a kind, and the kind is what the disc shows;
/// a placement game's stone carries nothing but its side, because the accepted
/// design gives stones no symbols at all. So the kind is optional rather than
/// gaining a fourteenth-and-a-half member: a stone is not one of the piece
/// characters, and every place that draws or names a kind has to answer for the
/// stone anyway.
///
/// **A face-down piece is the third body, and it is honest state rather than an
/// absent kind.** docs/interaction-design.md, "The Jieqi board": the style's
/// disc with its side ring and nothing on its face, saying whose piece it is
/// and no more. Its `kind` is therefore **the role its square gives it** — the
/// piece that starts on the square it stands on, which is public, both players
/// seeing the square — and never the identity the position holds under it.
/// **This app never holds that identity in a `Piece` at all**, so no surface
/// that draws or names one can leak it; where a capture discloses an identity,
/// `Placement.concealedIdentity(at:)` is the one place it is read from.
struct Piece: Hashable {
    /// `nil` on a stone, which has no kind to carry. On a face-down piece it is
    /// the square's role and not the concealed identity.
    var kind: PieceKind?
    var side: Side
    /// Whether the piece stands face down — Jieqi's, and no other game's.
    var isFaceDown = false

    static func stone(_ side: Side) -> Piece { Piece(kind: nil, side: side) }

    /// A face-down piece is never a stone: its kind is nil too — concealment,
    /// not stonehood — and the face-down body is its own third drawing.
    var isStone: Bool { kind == nil && !isFaceDown }
}

/// The placement a FEN denotes. Only the placement: the side to move, the
/// counters, and every rule question belong to the core's evaluation.
struct Placement {
    let game: GameKind
    private var pieces: [Square: Piece] = [:]
    /// What the record holds under each face-down disc.
    ///
    /// **It is not drawn and not named anywhere.** A position record is the
    /// objective position and holds every hidden identity, and it is never what
    /// a player is shown; this is that half of the record, kept out of `Piece`
    /// so that nothing which draws a board or composes a label can reach it.
    /// Exactly one surface reads it, through `concealedIdentity(at:)`: the
    /// captured-pieces surface, for a piece whose capture disclosed it.
    private var concealed: [Square: PieceKind] = [:]

    var board: BoardDefinition { game.board }

    subscript(square: Square) -> Piece? { pieces[square] }

    /// The identity the record holds under the face-down piece on `square`, or
    /// nil where nothing face down stands there.
    ///
    /// The caller is answering for a piece a capture has taken off the board and
    /// disclosed to whoever took it — docs/jieqi-rules.md's disclosure section —
    /// and nothing on the board is ever described from this.
    func concealedIdentity(at square: Square) -> PieceKind? { concealed[square] }

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
    ///
    /// A run of empty points is its count in decimal in every game. What the
    /// letters mean is the game's: a movement game writes one of the seven piece
    /// letters, and a placement game writes `S` alone — the core's own encoding,
    /// where the letter is the stone's kind and its case is its side, and
    /// deliberately not `b`/`w`, which would contradict the side-to-move field
    /// beside it.
    ///
    /// **One letter is one point in every game but Jieqi**, whose record writes
    /// a face-down piece as its identity letter followed by `~` —
    /// docs/jieqi-rules.md, "Positions, coordinates, and notation". So the
    /// letter is read first and the mark after it, and the two together are one
    /// point: the identity goes to `concealed`, where nothing draws it, and what
    /// stands on the board is a face-down piece of the role its square gives it.
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
            // A run of empty points is its count in **decimal**, so its digits
            // are accumulated rather than taken one at a time: a 15-file board
            // writes a whole empty rank as `15`, and reading that as a 1 and a 5
            // would leave nine points unaccounted for and the whole rank
            // rejected. The boards that came before never reached ten.
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
                // The face-down mark belongs to the letter before it rather
                // than to a point of its own, so it is applied to the piece
                // already standing and never advances the file.
                if character == "~" {
                    let square = Square(file: file - 1, rank: rank)
                    // One mark to a letter: a second would read the role it
                    // already wrote as an identity and bury the one the record
                    // spelled, so a doubled mark is a malformed field like any
                    // other.
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

    /// The role a square gives whatever stands face down on it: the piece that
    /// starts there.
    ///
    /// docs/jieqi-rules.md: a hidden piece moves and captures exactly as the
    /// xiangqi piece that starts on the square it stands on, it has never moved,
    /// so that square is always its own start square — and both players see the
    /// square, which is why the role is public where the identity is not.
    ///
    /// **The table is read from the core rather than written here**, out of the
    /// one ruleset that states these squares: Jieqi's start squares are
    /// Xiangqi's exactly, so Xiangqi's frozen start says which piece each of
    /// them belongs to. Nothing about legality is derived from it — the legal
    /// moves are the core's answer, and this only decides which piece a move
    /// list names.
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

/// A move in the frozen canonical notation. There is no suffix in any of these
/// rulesets: no promotion, castling, en passant, drop, or gating.
///
/// **How many squares a move spells follows from the game**, exactly as the core
/// says it does: a movement game writes `"<from><to>"` and a placement game
/// writes the one point the stone arrives at. So a placement carries no origin,
/// and `from` is optional rather than a second square standing for the same
/// point — a stone comes from off the board, and an origin invented here would
/// be a square the notation never named.
struct Move: Hashable {
    /// The point the mover leaves. `nil` for a placement.
    var from: Square?
    var to: Square

    var text: String { (from?.name ?? "") + to.name }

    init(from: Square, to: Square) {
        self.from = from
        self.to = to
    }

    /// A stone arriving on an empty point.
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
