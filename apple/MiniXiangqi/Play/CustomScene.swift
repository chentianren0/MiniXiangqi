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

    /// The refusal the last tap met, until the page has shown it. Absent
    /// whenever the last tap changed the draft, which is every tap but this
    /// one.
    private(set) var refusal: Refusal?

    /// A point that would not take the piece offered to it, and why.
    ///
    /// The reason is composed here, from the class the core reported and in the
    /// same words the standing reason line uses, because it *is* that sentence:
    /// what the page shows at the moment of the attempt is what it would have
    /// gone on showing had the piece landed.
    ///
    /// The `attempt` is what makes two refusals at the same point two events:
    /// the state is otherwise identical, and a page that could not tell them
    /// apart would answer the second tap by doing nothing.
    struct Refusal: Equatable {
        var square: Square
        var piece: Piece
        var reason: String
        var attempt: Int
    }

    /// How many refusals this draft has met. Only its changes are read.
    private var attempts = 0

    /// The three ways a draft is not a game to start, and the one way it is.
    enum Verdict: Equatable {
        /// Legal to set up in and a game to play: 开始对局 is enabled on this
        /// and on nothing else.
        case startable
        /// The predicate refused it, and this is the first rule it broke.
        case violation(SetupViolation)
        /// A draft still short of a general for one side or both — the state
        /// every draft passes through, and not a refusal to answer about it.
        /// The core reports it as the count clause, naming the side whose
        /// complement the game does not give; what makes it this verdict
        /// rather than a violation to fix is that the draft has not been given
        /// its generals yet.
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
    ///
    /// **A point the piece may not stand on refuses it instead**, and the draft
    /// does not change: the piece stays held, and the page is handed the
    /// refusal to answer with. Which points those are is `refusal(of:at:)`'s
    /// question, and it is the core's answer.
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
            // An entry the last of which has just gone down has nothing left to
            // offer, so it is not left standing as the held one.
            if remaining(held) == 0 { self.held = nil }
        } else {
            return
        }
        refusal = nil
        validate()
    }

    /// The page having shown a refusal, so the next one is a new event.
    func clearRefusal() { refusal = nil }

    /// Why this point would not take this piece, or nil where it would.
    ///
    /// **The whole question is the core's, and it is asked before anything is
    /// committed**: the candidate position — the draft with the piece on the
    /// point — is offered to the setup-legality predicate, and the refusal
    /// stands only where the predicate names one of the three classes that are
    /// about *where a piece may stand* and names this very point as the fault.
    ///
    /// Nothing here knows what a palace, an elephant's points or a soldier's
    /// rank are; it knows only that the core reported that class at that
    /// square. A refusal keyed on anything else would be a rule re-derived
    /// above the core.
    ///
    /// **It answers from the first piece down.** The predicate reports the
    /// classes that name a point before the one that counts a side, so a point
    /// refuses a piece over a board that has no generals on it yet — which is
    /// every board the first few taps compose.
    ///
    /// **The other refusal classes are not refusals here, deliberately.** Two
    /// generals facing each other and the waiting side left in check are
    /// properties of the whole position rather than of the point just touched,
    /// and a composer builds through both of them — so they remain placeable,
    /// and the standing reason line is what reports them. The count class names
    /// no point the palette would let this tap reach.
    ///
    /// It asks the predicate and nothing else. The session-free evaluation is
    /// never reached from here: the interface's ordering has setup legality as
    /// the first question, and a candidate this refuses is a candidate the
    /// engine is never shown.
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

    /// The classes that are about where one piece may stand. Read off the
    /// core's own vocabulary — these are its names for them — and never a
    /// statement of what the rules are.
    private static let placementRules: [SetupRule] = [
        .palace, .elephantSide, .soldierRank,
    ]

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
            // The count clause over a draft that has not been given its
            // generals yet is the ordinary state of composing, not a mistake to
            // report: the core says which side's complement is wrong and the
            // draft's own material says the piece is still in the palette. Both
            // halves are needed — a count violation with both generals down is
            // some other piece over its cap, which the palette's own counts
            // never deal, so that arm is the core's to reach and not this
            // editor's; it is a violation like any other all the same.
            verdict = violation.rule == .pieceCount && !hasBothGenerals
                ? .incomplete : .violation(violation)
        case .malformed:
            // Unreachable from here: what this editor spells is the frozen
            // encoding by construction, whatever stands on the board. A draft
            // the core will not read is no position to report on, so it says
            // what a draft that is not finished says.
            verdict = .incomplete
        }
    }

    /// Whether both sides have their general down, read off the draft's own
    /// material. It is not a rule — which position may be set up in is the
    /// core's — but a fact about what the palette has left to offer.
    private var hasBothGenerals: Bool {
        [Side.red, .black].allSatisfy { side in
            pieces.values.contains(Piece(kind: .general, side: side))
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

    /// The same sentence, for a refusal of one piece the player is offering to
    /// a point — which is where the kind is known and `reason` alone is not
    /// enough.
    ///
    /// One class covers two kinds whose points differ. The palace holds the
    /// general on all nine of its points and the advisor on five of them, so
    /// "outside the palace" is false of the four an advisor is refused inside
    /// it, while the advisor's own sentence is true of every point it is
    /// refused at, outside the palace included. A general keeps the palace
    /// sentence, which is the whole of its rule.
    func reason(refusing kind: PieceKind?) -> String? {
        guard rule == .palace, kind == .advisor else { return reason }
        let sideName = side.map { CustomScene.game.sideName($0) } ?? ""
        return String(format: String(localized: "scene.reason.advisorPoint"),
                      sideName, square, pieceName(.advisor))
    }

    /// The offending piece in the words of the side whose it is. Every class
    /// that uses it is about one side's own piece and the core names that side,
    /// so the fallback is a shape the interface never reaches.
    private func pieceName(_ kind: PieceKind) -> String {
        kind.name(for: side ?? .red)
    }
}
