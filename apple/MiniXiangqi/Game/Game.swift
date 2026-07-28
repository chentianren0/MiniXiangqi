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

    /// A core call that failed. Shown rather than swallowed: every one of them
    /// is a bug in this app or a packaging failure, never a rules outcome.
    private(set) var failure: CoreError?

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

    // MARK: - Input

    func tap(_ square: Square) {
        guard !evaluation.isOver else { return }

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

    private func play(_ move: Move) {
        moves.append(move.text)
        do {
            evaluation = try core.evaluate(from: startFEN, moves: moves)
            placement = Placement(fen: evaluation.fen)
            lastMove = move
            selected = nil
            refreshLegalMoves()
        } catch let error as CoreError {
            moves.removeLast()
            failure = error
        } catch {
            moves.removeLast()
        }
    }

    private func refreshLegalMoves() {
        do {
            legalMoves = try core.legalMoves(from: startFEN, moves: moves)
                .compactMap(Move.init(text:))
        } catch let error as CoreError {
            legalMoves = []
            failure = error
        } catch {
            legalMoves = []
        }
    }
}
