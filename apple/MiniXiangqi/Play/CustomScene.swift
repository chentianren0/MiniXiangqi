// The Custom Scene editor's draft: the position being composed, the side that
// will move first, and what the core says about the pair of them.
//
// docs/interaction-design.md, "Custom Scene": the board is empty and
// interactive, the palette holds the standard set with how many of each remain,
// a tap places and a tap removes, the side to move is a choice on the page,
// validation is live and says one thing, and 开始对局 is enabled on a position
// that is both legal and playable and on nothing else.
//
// **The draft is in memory and nowhere else.** Nothing here writes: leaving the
// editor drops this object, which is the whole of discarding it, and the game
// only ever exists once `PlayState.startScene` has created it.
//
// **No rule is decided here.** Which positions may be set up in is the core's
// setup-legality predicate, asked of every change; whether an accepted position
// is one to play is the core's session-free evaluation, asked after it; and
// even the standard set the palette offers is read off the game's own frozen
// start rather than written out. What this file owns is the draft, the FEN it
// spells, and which of the core's answers the page shows.

import Foundation
import Observation

@Observable
final class CustomScene {
    /// Xiangqi's alone: it is the one game whose rules define a
    /// setup-legality predicate, and every other game begins from its own
    /// frozen start. The core refuses the rest; this states it.
    static let game = GameKind.xiangqi

    private let core: Core

    /// The pieces put down so far. A dictionary rather than a `Placement`
    /// because a draft is edited and a placement is read: the FEN below is what
    /// turns one into the other.
    private(set) var pieces: [Square: Piece] = [:]

    /// The side whose move the game's first ply will be.
    var sideToMove: Side = .red {
        didSet { if sideToMove != oldValue { validate() } }
    }

    /// The palette entry the next tap puts down, where one is chosen.
    private(set) var held: Piece?

    /// What the core says about the draft as it stands. Recomputed on every
    /// change, which is what makes the page's one reason live.
    private(set) var verdict: Verdict = .incomplete

    /// The three ways a draft is not a game to start, and the one way it is.
    enum Verdict: Equatable {
        /// Legal to set up in and a game to play: 开始对局 is enabled on this
        /// and on nothing else.
        case startable
        /// The predicate refused it, and this is the first rule it broke.
        case violation(SetupViolation)
        /// The structural refusal, which a position composed here reaches for
        /// exactly one reason: the engine's own validator wants one general a
        /// side, so a board still missing one is refused before any clause of
        /// the predicate is reached.
        case incomplete
        /// A legal setup that is not a game: the position already has a result
        /// of its own, so there is nothing to play from it.
        case decided
    }

    init(core: Core) {
        self.core = core
        validate()
    }

    // MARK: - The palette

    /// The standard set, in the order the palette shows it: each side's pieces
    /// by kind, Red first.
    ///
    /// **Read off the frozen start rather than written out here.** What a
    /// xiangqi set contains is the start position's own complement, and the
    /// core is what spells that position — so a palette entry exists because a
    /// piece stands in the game's opening array, not because this file says so.
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
        let start = Placement(fen: Core.startFEN(for: game), game: game)
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

    /// How many of this piece are still in the palette. An entry with none left
    /// has nothing to offer and cannot be picked up.
    func remaining(_ piece: Piece) -> Int {
        (Self.standardSet[piece] ?? 0) - pieces.values.count { $0 == piece }
    }

    func isHeld(_ piece: Piece) -> Bool { held == piece }

    /// Picks a palette entry up: it is what the next tap puts down, and picking
    /// it again is picking the same thing. An entry with none remaining has
    /// nothing to offer and is not selectable.
    func pick(_ piece: Piece) {
        guard remaining(piece) > 0 else { return }
        held = piece
    }

    // MARK: - The board

    /// A tap places and a tap removes: an empty point takes the entry the
    /// player is holding, and a point with a piece on it gives that piece back
    /// to the palette.
    func tap(_ square: Square) {
        if pieces[square] != nil {
            pieces[square] = nil
        } else if let held, remaining(held) > 0 {
            pieces[square] = held
            // An entry the last of which has just gone down has nothing left to
            // offer, so it is not left standing as the held one.
            if remaining(held) == 0 { self.held = nil }
        } else {
            return
        }
        validate()
    }

    /// The draft as a position record: the placement, the side to move, and the
    /// counters a named start carries — halfmove 0 and fullmove 1, which are
    /// not the caller's to choose and which the core refuses any other value of.
    var fen: String {
        Self.fen(of: pieces, sideToMove: sideToMove, game: Self.game)
    }

    /// The same composition as a function of its parts, so that what the page
    /// spells can be read without an editor around it.
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

    /// Whether the composed position is one 开始对局 may create a game from.
    var canStart: Bool { verdict == .startable }

    /// The two questions, in the order the interface says to ask them: setup
    /// legality first, and startability only of a position the predicate has
    /// already accepted. That ordering is the engine-safety guard — a position
    /// offering a general capture must never reach the engine — and it is why
    /// the second question is not asked of a draft the first refused.
    private func validate() {
        switch core.setupVerdict(of: fen, game: Self.game) {
        case .legal:
            verdict = core.isPlayable(fen, game: Self.game) ? .startable : .decided
        case .illegal(let violation):
            verdict = .violation(violation)
        case .malformed:
            verdict = .incomplete
        }
    }
}

// MARK: - The one plain reason

extension CustomScene.Verdict {
    /// The single reason the page carries while the draft is not one to start
    /// from. Never a rule identifier, never a diagnostic, and never a second
    /// reason beside the first: the core reports the first violation it found,
    /// and this names it.
    ///
    /// `nil` where there is nothing to say — a startable position, and the one
    /// refusal class this editor cannot be shown. `notFrozenStart` is a game's
    /// answer for accepting only its frozen start, which Xiangqi is not, so no
    /// sentence is written for a surface that cannot exist.
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
    /// The violation as one plain sentence, in the class's own terms and with
    /// whatever the class names in it: the side where it belongs to one, the
    /// point where it stands at one, and the piece where the class is about one
    /// kind. The sides and the pieces are the board's own words, so a sentence
    /// and a screen reader name both the same way — which for a piece means the
    /// side's own character in Chinese, 相 against 象 and 兵 against 卒.
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

    /// The offending piece in the words of the side whose it is. Both classes
    /// that use it are about one side's own piece and the core names that side,
    /// so the fallback is a shape the interface never reaches.
    private func pieceName(_ kind: PieceKind) -> String {
        kind.name(for: side ?? .red)
    }
}
