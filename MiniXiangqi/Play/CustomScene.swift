// The draft lives in memory only: leaving the editor drops it, and the game
// exists only once `PlayState.startScene` creates it. Every rule is the core's:
// setup legality is asked of every change, playability after it, and even the
// palette's standard set is read off the game's frozen start.

import Foundation
import Observation

@Observable
final class CustomScene {
    /// Xiangqi is the one game whose rules define a setup-legality predicate;
    /// every other game begins from its frozen start.
    static let game = GameKind.xiangqi

    private let core: Core

    /// A dictionary because a draft is edited; `fen` turns it into a position.
    private(set) var pieces: [Square: Piece] = [:]

    var sideToMove: Side = .red {
        didSet { if sideToMove != oldValue { validate() } }
    }

    /// The palette entry the next tap puts down, where one is chosen.
    private(set) var held: Piece?

    /// What the core says about the draft, recomputed on every change.
    private(set) var verdict: Verdict = .incomplete

    /// The refusal the last tap met, until the page has shown it.
    private(set) var refusal: Refusal?

    /// A point that would not take the piece offered to it, and why.
    ///
    /// The reason is the standing reason line's sentence, so the page shows at
    /// the attempt what it would have shown had the piece landed. `attempt`
    /// makes two refusals at one point two events; without it the page would
    /// answer the second tap with nothing.
    struct Refusal: Equatable {
        var square: Square
        var piece: Piece
        var reason: String
        var attempt: Int
    }

    private var attempts = 0

    enum Verdict: Equatable {
        /// Legal to set up in and a game to play.
        case startable
        /// The first rule the predicate found broken.
        case violation(SetupViolation)
        /// A side still lacks its general. The core reports this as the count
        /// clause, but it is the state every draft passes through, not a refusal.
        case incomplete
        /// Legal, but the position already has a result, so there is nothing to
        /// play from it.
        case decided
    }

    init(core: Core) {
        self.core = core
        validate()
    }

    // MARK: - The palette

    /// Each side's pieces by kind, Red first, read off the frozen start so the
    /// palette offers exactly what the game's opening array holds.
    static let entries: [Piece] = {
        [Side.red, .black].flatMap { side in
            PieceKind.allCases.compactMap { kind in
                let piece = Piece(kind: kind, side: side)
                return standardSet[piece] == nil ? nil : piece
            }
        }
    }()

    /// How many of each piece the standard set holds.
    private static let standardSet: [Piece: Int] = {
        // Xiangqi freezes a start, so the fallback is unreachable; it would give
        // an empty palette.
        let start = Placement(fen: Core.frozenStartFEN(for: game) ?? "", game: game)
        let board = game.board
        var counted: [Piece: Int] = [:]
        for rank in 0..<board.rankCount {
            for file in 0..<board.fileCount {
                guard let piece = start[Square(file: file, rank: rank)] else { continue }
                counted[piece, default: 0] += 1
            }
        }
        return counted
    }()

    func remaining(_ piece: Piece) -> Int {
        (Self.standardSet[piece] ?? 0) - pieces.values.count { $0 == piece }
    }

    func isHeld(_ piece: Piece) -> Bool { held == piece }

    func pick(_ piece: Piece) {
        guard remaining(piece) > 0 else { return }
        held = piece
    }

    // MARK: - The board

    /// A tap removes the piece on an occupied point, or puts the held entry on
    /// an empty one. Where the core refuses that point, the draft does not
    /// change and the piece stays held.
    func tap(_ square: Square) {
        if pieces[square] != nil {
            pieces[square] = nil
        } else if let held, remaining(held) > 0 {
            if let refused = refusal(of: held, at: square) {
                attempts += 1
                refusal = Refusal(square: square, piece: held,
                                  reason: refused, attempt: attempts)
                return
            }
            pieces[square] = held
            if remaining(held) == 0 { self.held = nil }
        } else {
            return
        }
        refusal = nil
        validate()
    }

    /// Called once the page has shown a refusal, so the next one is a new event.
    func clearRefusal() { refusal = nil }

    /// Why this point would not take this piece, or nil where it would.
    ///
    /// The candidate position goes to the core's setup-legality predicate, and
    /// the refusal stands only where it names a placement class at this very
    /// point; nothing here knows what a palace is. The predicate reports point
    /// classes before the count class, so a point refuses a piece even before
    /// the generals are down. Facing generals and a side left in check are
    /// whole-position properties a composer builds through, so they stay
    /// placeable and the reason line reports them.
    private func refusal(of piece: Piece, at square: Square) -> String? {
        var candidate = pieces
        candidate[square] = piece
        let fen = Self.fen(of: candidate, sideToMove: sideToMove, game: Self.game)
        guard case .illegal(let violation) = core.setupVerdict(of: fen, game: Self.game),
              Self.placementRules.contains(violation.rule),
              violation.square == square.name
        else { return nil }
        return violation.reason(refusing: piece.kind)
    }

    /// The classes about where one piece may stand.
    private static let placementRules: [SetupRule] = [
        .palace, .elephantSide, .soldierRank,
    ]

    /// Halfmove 0 and fullmove 1: the core refuses any other counters for a
    /// setup.
    var fen: String {
        Self.fen(of: pieces, sideToMove: sideToMove, game: Self.game)
    }

    static func fen(of pieces: [Square: Piece], sideToMove: Side,
                    game: GameKind) -> String {
        let board = game.board
        var ranks: [String] = []
        for rank in stride(from: board.rankCount - 1, through: 0, by: -1) {
            var line = ""
            var empty = 0
            for file in 0..<board.fileCount {
                guard let piece = pieces[Square(file: file, rank: rank)],
                      let kind = piece.kind
                else {
                    empty += 1
                    continue
                }
                if empty > 0 {
                    line += String(empty)
                    empty = 0
                }
                let letter = String(kind.rawValue)
                line += piece.side == .red ? letter.uppercased() : letter
            }
            if empty > 0 { line += String(empty) }
            ranks.append(line)
        }
        return ranks.joined(separator: "/") + " " + (sideToMove == .red ? "w" : "b")
            + " - - 0 1"
    }

    // MARK: - What the core says about it

    var canStart: Bool { verdict == .startable }

    /// Setup legality first, and playability only of a position it accepted:
    /// a position offering a general capture must never reach the engine.
    private func validate() {
        switch core.setupVerdict(of: fen, game: Self.game) {
        case .legal:
            verdict = core.isPlayable(fen, game: Self.game) ? .startable : .decided
        case .illegal(let violation):
            // A count violation before both generals are down is ordinary
            // composing, not a mistake. With both down it is some other piece
            // over its cap, which the palette never deals, and it is reported.
            verdict = violation.rule == .pieceCount && !hasBothGenerals
                ? .incomplete : .violation(violation)
        case .malformed:
            // Unreachable: this editor always spells a well-formed FEN.
            verdict = .incomplete
        }
    }

    private var hasBothGenerals: Bool {
        [Side.red, .black].allSatisfy { side in
            pieces.values.contains(Piece(kind: .general, side: side))
        }
    }
}

// MARK: - The one plain reason

extension CustomScene.Verdict {
    /// The single reason the page shows while the draft cannot start: the
    /// first violation the core found. `notFrozenStart` cannot arise for
    /// Xiangqi, so it has no sentence.
    var reason: String? {
        switch self {
        case .startable: nil
        case .incomplete: String(localized: "scene.reason.generals")
        case .decided: String(localized: "scene.reason.decided")
        case .violation(let violation): violation.reason
        }
    }
}

extension SetupViolation {
    /// Sides and pieces use the board's own words, so the sentence and a
    /// screen reader agree: 相 against 象, 兵 against 卒.
    var reason: String? {
        let sideName = side.map { CustomScene.game.sideName($0) } ?? ""
        switch rule {
        case .pieceCount:
            return String(format: String(localized: "scene.reason.pieceCount"), sideName)
        case .palace:
            // The class covers a general or an advisor, and the core names
            // neither, so the sentence names the point rather than the piece.
            return String(format: String(localized: "scene.reason.palace"),
                          sideName, square)
        case .elephantSide:
            return String(format: String(localized: "scene.reason.elephantSide"),
                          sideName, square, pieceName(.elephant))
        case .soldierRank:
            return String(format: String(localized: "scene.reason.soldierRank"),
                          sideName, square, pieceName(.soldier))
        case .facingGenerals:
            return String(localized: "scene.reason.facingGenerals")
        case .opponentInCheck:
            return String(format: String(localized: "scene.reason.opponentInCheck"),
                          sideName)
        case .notFrozenStart:
            return nil
        }
    }

    /// For a refusal of a known piece. The palace class covers the general on
    /// all nine palace points but the advisor on five, so "outside the palace"
    /// would be false of the four an advisor is refused inside it; the advisor
    /// gets its own sentence.
    func reason(refusing kind: PieceKind?) -> String? {
        guard rule == .palace, kind == .advisor else { return reason }
        let sideName = side.map { CustomScene.game.sideName($0) } ?? ""
        return String(format: String(localized: "scene.reason.advisorPoint"),
                      sideName, square, pieceName(.advisor))
    }

    /// The core names a side for every class that uses this, so the fallback
    /// is never reached.
    private func pieceName(_ kind: PieceKind) -> String {
        kind.name(for: side ?? .red)
    }
}
