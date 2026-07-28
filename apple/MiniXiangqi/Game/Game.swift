// A game in progress, as the screen needs it.
//
// Every rule question — what is legal, whether a side is in check, whether the
// game is over and why — is answered by the core. This type holds the history,
// the selection, and the board orientation, and asks again after every change.

import Observation

@Observable
final class Game {
    private let core: Core

    let startFEN: String
    private(set) var moves: [String] = []

    private(set) var evaluation: Evaluation
    private(set) var placement: Placement
    private(set) var legalMoves: [Move] = []
    private(set) var lastMove: Move?

    /// Each played move as the player reads it. Recorded when the move is
    /// played, because traditional notation depends on the placement *before*
    /// it — including whether a second piece of the same type stood on the
    /// same file, which the move itself may change.
    private(set) var notation: [String] = []

    /// A core call that failed. Shown rather than swallowed: every one of them
    /// is a bug in this app or a packaging failure, never a rules outcome.
    private(set) var failure: CoreError?

    /// Whether the player has claimed the draw the core offered. The claim is
    /// the player's, not the core's: a neutral threefold repetition leaves the
    /// game running until somebody ends it.
    private(set) var claimedDraw = false

    var selected: Square?
    var flipped = false

    init(core: Core) throws {
        self.core = core
        let startFEN = Core.startFEN
        let evaluation = try core.evaluate(from: startFEN, moves: [])
        self.startFEN = startFEN
        self.evaluation = evaluation
        self.placement = Placement(fen: evaluation.fen)
        refreshLegalMoves()
    }

    // MARK: - Derived board state

    var destinations: Set<Square> {
        guard let selected else { return [] }
        return Set(legalMoves.filter { $0.from == selected }.map(\.to))
    }

    var captures: Set<Square> {
        Set(destinations.filter { placement[$0] != nil })
    }

    /// The checked general, so the board can ring it. The side to move is the
    /// side in check: the core reports check for the position on screen.
    var checkedGeneral: Square? {
        guard evaluation.inCheck else { return nil }
        for rank in 0..<Square.count {
            for file in 0..<Square.count {
                let square = Square(file: file, rank: rank)
                if let piece = placement[square],
                   piece.kind == .general, piece.side == evaluation.sideToMove {
                    return square
                }
            }
        }
        return nil
    }

    // MARK: - Result

    /// Over one way or the other: adjudicated by the core, or claimed by the
    /// player. Both stop input; only one of them can be taken back.
    var isFinished: Bool { evaluation.isOver || claimedDraw }

    /// The result to present. A claimed draw is a draw whatever the core still
    /// calls the position, and it needs no separate reason: the reason the core
    /// already reports is the one the claim was available for.
    var presentedState: GameState { claimedDraw ? .draw : evaluation.state }

    /// docs/interaction-design.md, "Undo and result confirmation": Free Play
    /// removes one move per action and can repeat back to the initial position,
    /// and a natural result stays undoable while its presentation is
    /// unconfirmed. A claimed draw is not a natural result — the player
    /// confirmed it — so it is the one finish this cannot walk back.
    var canUndo: Bool { !moves.isEmpty && !claimedDraw && failure == nil }

    // MARK: - Input

    func tap(_ square: Square) {
        guard !isFinished else { return }

        if square == selected {
            selected = nil
            return
        }
        if let selected, let move = legalMoves.first(where: {
            $0.from == selected && $0.to == square
        }) {
            play(move)
            return
        }
        if placement[square]?.side == evaluation.sideToMove {
            selected = square
            return
        }
        // An illegal tap moves nothing and keeps the selection, so the
        // correction is one tap away. Its feedback — the legal destinations
        // pulsing once — is still to come.
    }

    /// Takes back one ply. The shortened history is evaluated before anything
    /// is committed, so an Undo the core cannot complete does not happen: the
    /// game stays exactly at the pre-action state and the failure is recorded.
    func undo() {
        guard canUndo else { return }
        let shortened = Array(moves.dropLast())
        do {
            let evaluation = try core.evaluate(from: startFEN, moves: shortened)
            moves = shortened
            notation.removeLast()
            self.evaluation = evaluation
            placement = Placement(fen: evaluation.fen)
            // The brackets always mark the move that produced the position on
            // screen, so an Undo moves them to the move that is now last, and
            // an initial position carries none.
            lastMove = shortened.last.flatMap { Move(text: $0) }
            selected = nil
            refreshLegalMoves()
        } catch {
            failure = CoreError(wrapping: error)
        }
    }

    /// Ends the game as a draw on the repetition the core is offering. Only the
    /// core decides whether the claim exists; this decides nothing but that the
    /// player took it.
    func claimDraw() {
        guard evaluation.claimAvailable, !claimedDraw else { return }
        claimedDraw = true
        selected = nil
    }

    private func play(_ move: Move) {
        let read = MoveNotation.text(for: move, in: placement)
        moves.append(move.text)
        notation.append(read)
        do {
            evaluation = try core.evaluate(from: startFEN, moves: moves)
            placement = Placement(fen: evaluation.fen)
            lastMove = move
            selected = nil
            refreshLegalMoves()
        } catch {
            moves.removeLast()
            notation.removeLast()
            failure = CoreError(wrapping: error)
        }
    }

    private func refreshLegalMoves() {
        do {
            legalMoves = try core.legalMoves(from: startFEN, moves: moves)
                .compactMap(Move.init(text:))
        } catch {
            legalMoves = []
            failure = CoreError(wrapping: error)
        }
    }
}

#if DEBUG
/// A move a replay line asked for and the core will not play.
private struct RefusedReplayMove: Error, CustomStringConvertible {
    var text: String
    var description: String { "the replay line's move \(text) is not legal here" }
}

extension Game {
    /// Plays a recorded line before the game is first shown, so a UI test can
    /// start from a position that would otherwise take a dozen clicks to reach.
    /// It goes through the same path a person's move does — nothing here knows
    /// a rule the core has not been asked. A refused move is a bug in the line
    /// rather than a rules outcome, so it is raised rather than skipped.
    ///
    /// Debug only: it is a test affordance, not a product one.
    func replay(_ line: [String]) throws {
        for text in line {
            guard let move = Move(text: text), legalMoves.contains(move) else {
                throw CoreError(wrapping: RefusedReplayMove(text: text))
            }
            play(move)
            if let failure { throw failure }
        }
    }
}
#endif
