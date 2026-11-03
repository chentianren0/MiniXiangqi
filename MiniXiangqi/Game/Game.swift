// A game in progress, as the screen needs it. Every rule question is the
// core's replay of the record's moves. Here are the game's policy above the
// rules (how much one Undo takes back, whose turn owes the AI a search, when
// resignation is on offer) and the screen's reading of the game, refreshed
// after every change rather than kept as a second truth.

import Foundation
import Observation

@Observable
final class Game {
    private let library: GameLibrary
    private let core: Core

    /// The position the moves are replayed from.
    let start: String

    /// The record's line, read back after every mutation.
    private(set) var moves: [String] = []

    /// Bumped by every change to the line or the result. A search answers the
    /// line it was asked about, so a result whose revision is not this one is
    /// about a position the game has left.
    private(set) var revision = 0

    private(set) var evaluation: Evaluation
    private(set) var placement: Placement
    private(set) var legalMoves: [Move] = []
    private(set) var lastMove: Move?

    /// Each played move as the player reads it, in both notations. Recorded
    /// when the move is played, since a reading depends on the placement before
    /// it, and recomputed the same way when a stored game resumes. The 记谱法
    /// preference picks a reading where the list is drawn.
    private(set) var notation: [MoveReading] = []

    /// What the game has taken off the board, kept like the notation: appended
    /// as a ply lands, shortened when one is taken back, recomputed on resume.
    /// Empty in every game but Jieqi.
    private(set) var captured = CapturedPieces()

    /// The last failed core call. A refused move or Undo did not happen; the
    /// position is unchanged and the player may try again.
    private(set) var failure: CoreError?

    /// The same refusal when the ply was the AI's reply. Kept apart because a
    /// refused AI reply raises nothing: the retry is the app's, not the
    /// player's.
    private(set) var opponentFailure: CoreError?

    /// Decided once, at creation.
    private(set) var configuration: GameConfiguration

    /// Whose move ply 0 is. A composed game may open with Black, so the move
    /// list pairs and numbers from this rather than from parity.
    let firstMover: Side

    /// The last claim or filing the library refused. Separate from `failure`
    /// because a refused ply is a transient capsule and a refused filing is a
    /// blocking retry.
    private(set) var filingFailure: CoreError?

    /// Whether the player's draw claim has been filed. A resumed game is never
    /// a claimed one: the claim filed it.
    private(set) var claimedDraw = false

    /// Whether the player conceded, a result no position produces. A resumed
    /// game is never a resigned one: resigning filed it.
    private(set) var resigned = false

    /// The History record the game became, once it is filed.
    private(set) var filedRecordID: UUID?

    var selected: Square?
    var flipped = false

    /// Opens the game in play the library holds; creating or resuming it is
    /// the caller's act.
    init(library: GameLibrary) throws {
        guard let record = library.attached else {
            throw CoreError(wrapping: LibraryRefusal.noGameInPlay)
        }
        let core = library.core
        let configuration = record.configuration
        let game = configuration.game
        let start = record.start
        let moves = record.moves
        let position = { (ply: Int) in
            Placement(fen: try core.evaluate(game, from: start, moves: Array(moves.prefix(ply))).fen,
                      game: game)
        }
        let notation = try Self.notation(reading: moves, game: game, at: position)
        let lastMove = try moves.last.map { try Self.move(reading: $0, on: game.board) }
        let captured = try Self.captured(reading: moves, game: game, at: position)
        let evaluation = try core.evaluate(game, from: start, moves: moves)
        let firstMover = try core.evaluate(game, from: start, moves: []).sideToMove
        self.library = library
        self.core = core
        self.start = start
        self.moves = moves
        self.notation = notation
        self.captured = captured
        self.lastMove = lastMove
        self.evaluation = evaluation
        self.configuration = configuration
        self.firstMover = firstMover
        self.placement = Placement(fen: evaluation.fen, game: game)
        // In human-versus-AI play the human's side is at the bottom; Free Play
        // opens unflipped. A placement board has no orientation, so it never
        // flips.
        self.flipped = !game.isPlacement && configuration.humanSide == .black
        refreshLegalMoves()
    }

    /// The stored line, read the way a History replay reads it, so a relaunch
    /// and a replay say the same words.
    private static func notation(reading moves: [String], game: GameKind,
                                 at position: (Int) throws -> Placement) throws -> [MoveReading] {
        do {
            return try MoveReading.line(for: moves, on: game, placementAt: position)
        } catch {
            throw CoreError(wrapping: error)
        }
    }

    /// What the stored line took off the board, by the same walk as the
    /// notation. Empty in every game but Jieqi.
    private static func captured(reading moves: [String], game: GameKind,
                                 at position: (Int) throws -> Placement) throws -> CapturedPieces {
        do {
            return try CapturedPieces.line(for: moves, on: game, placementAt: position)
        } catch {
            throw CoreError(wrapping: error)
        }
    }

    private static func move(reading text: String, on board: BoardDefinition) throws -> Move {
        guard let move = Move(text: text, on: board) else {
            throw UnreadableCoreMove(text: text)
        }
        return move
    }

    // MARK: - Derived board state

    var destinations: Set<Square> {
        guard let selected else { return [] }
        return Set(legalMoves.filter { $0.from == selected }.map(\.to))
    }

    var captures: Set<Square> {
        Set(destinations.filter { placement[$0] != nil })
    }

    /// Renju's forbidden points, marked while Black is to move.
    var forbiddenPoints: Set<Square> {
        Self.forbiddenPoints(of: kind, in: placement, legalMoves: legalMoves,
                             sideToMove: evaluation.sideToMove, isOver: isFinished)
    }

    /// Static because there are two boards, and a second copy would be a second
    /// place for them to mark different points.
    ///
    /// Derived from the legal-move set alone: a placement game's legal moves
    /// are its empty points less what is forbidden to the side to move, so the
    /// difference is the forbidden set and the core alone decides it. Renju's
    /// forbidden points are Black's (`.red`, the first mover) alone.
    static func forbiddenPoints(of game: GameKind, in placement: Placement,
                                legalMoves: [Move], sideToMove: Side,
                                isOver: Bool) -> Set<Square> {
        guard game == .renju, sideToMove == .red, !isOver else { return [] }
        let legal = Set(legalMoves.map(\.to))
        let board = game.board
        var forbidden: Set<Square> = []
        for rank in 0..<board.rankCount {
            for file in 0..<board.fileCount {
                let square = Square(file: file, rank: rank)
                guard placement[square] == nil, !legal.contains(square) else { continue }
                forbidden.insert(square)
            }
        }
        return forbidden
    }

    /// The checked general, for the board to ring. The side to move is the
    /// side in check.
    var checkedGeneral: Square? {
        guard evaluation.inCheck else { return nil }
        return placement.general(of: evaluation.sideToMove)
    }

    // MARK: - Result

    /// Adjudicated by the core, claimed by the player, or conceded. All three
    /// stop input; only the first can be taken back.
    var isFinished: Bool { evaluation.isOver || claimedDraw || resigned }

    /// A claimed draw is a draw and a resignation the opponent's win, whatever
    /// the rules still call the position.
    var presentedState: GameState {
        if claimedDraw { return .draw }
        if resigned { return humanSide == .red ? .blackWins : .redWins }
        return evaluation.state
    }

    /// A resignation's position has no verdict, so the reason is the act. A
    /// claimed draw keeps the reason the core reports.
    var presentedReason: EndReason { resigned ? .resignation : evaluation.reason }

    /// How many plies one Undo takes back: 1 or 2, and 0 where there is nothing
    /// to take back. Free Play takes back one ply. Against the AI, with the
    /// human's move last that move comes off; with the AI's reply last, the
    /// reply and the move before it come off together; an AI-first game after
    /// the AI's opening move has nothing to return to. A networked game has no
    /// unilateral undo, and a filed game nothing left. A result the rules
    /// decided stays undoable until it is filed.
    var undoPlies: Int {
        guard filedRecordID == nil, !moves.isEmpty, !mode.isNetworked else { return 0 }
        guard isHumanVersusAI, let humanSide else { return 1 }
        if mover(ofPly: moves.count - 1) == humanSide { return 1 }
        return moves.count >= 2 ? 2 : 0
    }

    var canUndo: Bool { undoPlies > 0 }

    /// Which side made ply `index`.
    func mover(ofPly index: Int) -> Side {
        index % 2 == 0 ? firstMover : firstMover.opponent
    }

    /// Whether the deal this game conceals is disclosed now: every hidden
    /// identity is shown to both players when the game ends, by any ending.
    /// It says whether, not when; the board waits for the ending ply to finish
    /// being shown.
    var disclosesTheDeal: Bool { kind.conceals && isFinished }

    // MARK: - The opponent, where there is one

    var kind: GameKind { configuration.game }
    var mode: PlayMode { configuration.mode }
    var isHumanVersusAI: Bool { mode == .humanVersusAI }

    /// The side the player controls, in human-versus-AI play. Free Play has
    /// none: the same person controls both.
    var humanSide: Side? { isHumanVersusAI ? configuration.humanSide : nil }

    /// Whether the AI owes a move here.
    var searchExpected: Bool {
        isHumanVersusAI && !isFinished && evaluation.sideToMove != humanSide
    }

    /// Whether 认输 is on offer: a human-versus-AI game with no result of its
    /// own. A claimable repetition is not a result.
    var canResign: Bool { isHumanVersusAI && filedRecordID == nil && !evaluation.isOver }

    /// The line the AI and the hint search.
    var searchLine: SearchLine { SearchLine(game: kind, start: start, moves: moves) }

    // MARK: - Input

    /// What a tap on a point means. The one home for the board's affordance:
    /// the motion layer asks this and adds only the animation, so the board
    /// cannot disagree with itself.
    enum TapEffect: Equatable {
        /// Put the held piece down: it was tapped again.
        case cancelSelection
        /// A legal move, ready to play.
        case play(Move)
        /// Take up this piece or, on a placement board with confirmation on,
        /// mark this point for the stone.
        case select(Square)
        /// A point the held piece cannot reach. It keeps the selection, so the
        /// correction is one tap away.
        case illegal
        /// Nothing to act on: a point that offers nothing with nothing held, or
        /// a board with nothing left to play.
        case unavailable
    }

    func effect(ofTapAt square: Square) -> TapEffect {
        // Read from whether a search is expected rather than re-derived from
        // the mode and side to move, so input stays refused for as long as the
        // AI owes a move, even behind a preparation that has not succeeded.
        Self.effect(ofTapAt: square, in: placement, legalMoves: legalMoves,
                    sideToMove: evaluation.sideToMove, selected: selected,
                    acceptsInput: !isFinished && !searchExpected,
                    confirmsPlacement: UserDefaults.standard.bool(forKey: "placementConfirmation.enabled"))
    }

    /// The same question asked of a position rather than of this game, written
    /// once because there are two boards: a nearby game's position and turn
    /// come from the protocol rather than the library.
    static func effect(ofTapAt square: Square, in placement: Placement,
                       legalMoves: [Move], sideToMove: Side, selected: Square?,
                       acceptsInput: Bool,
                       confirmsPlacement: Bool = false) -> TapEffect {
        guard acceptsInput else { return .unavailable }

        guard placement.board.play == .movement else {
            return placementEffect(ofTapAt: square, legalMoves: legalMoves,
                                   selected: selected, confirming: confirmsPlacement)
        }

        if square == selected { return .cancelSelection }
        if let selected, let move = legalMoves.first(where: {
            $0.from == selected && $0.to == square
        }) {
            return .play(move)
        }
        if placement[square]?.side == sideToMove { return .select(square) }
        return selected == nil ? .unavailable : .illegal
    }

    /// The same question on a board a stone is placed on. Plain, the default: a
    /// tap on a legal point plays it. Confirmed, when the Settings switch is on:
    /// the first tap marks the point, tapping the mark commits it, tapping
    /// another legal point moves the mark, and tapping off the board cancels it.
    ///
    /// A point with no legal move is occupied or forbidden, and this board draws
    /// no destinations to strengthen, so it is `unavailable` and a standing mark
    /// is left alone.
    private static func placementEffect(ofTapAt square: Square, legalMoves: [Move],
                                        selected: Square?,
                                        confirming: Bool) -> TapEffect {
        guard let move = legalMoves.first(where: { $0.to == square }) else {
            return .unavailable
        }
        guard confirming, square != selected else { return .play(move) }
        return .select(square)
    }

    func tap(_ square: Square) {
        switch effect(ofTapAt: square) {
        case .cancelSelection: selected = nil
        case .play(let move): play(move)
        case .select(let square): selected = square
        case .illegal, .unavailable: break
        }
    }

    /// Takes back one decision. An Undo the library cannot save does not
    /// happen, and the failure is recorded.
    func undo() {
        failure = nil
        opponentFailure = nil
        guard canUndo else { return }
        do {
            try library.undo(undoPlies)
            moves = try library.moveHistory()
            revision += 1
            // Cut to the line rather than shortened by the count, so a reading
            // that fell behind after a refused read is repaired, not compounded.
            notation = Array(notation.prefix(moves.count))
            captured.removePlies(from: moves.count)
            try refresh()
            // The brackets mark the move that produced the position on screen;
            // an initial position carries none.
            lastMove = try moves.last.map { try Self.move(reading: $0, on: kind.board) }
            selected = nil
            refreshLegalMoves()
        } catch {
            failure = CoreError(wrapping: error)
        }
    }

    /// Ends the game as a draw on the repetition the rules offer, which files
    /// it. A refused filing leaves the game running and claimable.
    func claimDraw() {
        filingFailure = nil
        guard evaluation.claimAvailable, !claimedDraw else { return }
        do {
            filedRecordID = try library.claimDraw()
            claimedDraw = true
            selected = nil
            revision += 1
            // The position is unchanged, but a filed game offers less.
            try refresh()
            refreshLegalMoves()
        } catch {
            filingFailure = CoreError(wrapping: error)
        }
    }

    /// Concedes the game, which files it as a loss for the human's side. A
    /// refused filing leaves the game running.
    func resign() {
        filingFailure = nil
        guard canResign, filedRecordID == nil else { return }
        do {
            filedRecordID = try library.resign()
            resigned = true
            selected = nil
            revision += 1
            try refresh()
            refreshLegalMoves()
        } catch {
            filingFailure = CoreError(wrapping: error)
        }
    }

    /// The position after the first `ply` plies. Undoing a decision cycle reads
    /// the disc that made the first ply, and what the reply took from it, off
    /// the position between the two moves.
    func placement(atPly ply: Int) -> Placement? {
        guard let position = try? core.evaluate(kind, from: start,
                                                moves: Array(moves.prefix(ply))) else { return nil }
        return Placement(fen: position.fen, game: kind)
    }

    /// Files the finished game in History: the notice's 保存, and what 开始新对局
    /// does before anything resets. A game already filed by a claim or an
    /// earlier 保存 is not filed again. A refusal leaves the game in play and
    /// resumable.
    func file() throws {
        assert(isFinished, "only a finished game is filed here")
        filingFailure = nil
        guard filedRecordID == nil else { return }
        do {
            filedRecordID = try library.confirmResult()
            revision += 1
        } catch {
            let failure = CoreError(wrapping: error)
            filingFailure = failure
            throw failure
        }
        // A filed game has nothing left to take back. A read that fails here
        // is an ordinary refused read, not a refused filing: the record exists.
        do {
            try refresh()
        } catch {
            failure = CoreError(wrapping: error)
        }
        refreshLegalMoves()
    }

    /// The AI's reply, through the same legal-move boundary as the player's
    /// moves; the library refuses a bad one the same way.
    func playOpponent(_ move: Move) {
        play(move, byOpponent: true)
    }

    func play(_ move: Move, byOpponent: Bool = false) {
        if byOpponent { opponentFailure = nil } else { failure = nil }
        // The reading is of the position the ply leaves, but it is made only
        // once the ply is committed: what a Jieqi ply turned up is a fact about
        // the position afterwards.
        let before = placement
        let ply = moves.count
        do {
            try library.apply(move.text)
            moves = try library.moveHistory()
            revision += 1
            try refresh()
            notation.append(MoveReading(of: move, in: before, after: placement))
            // Read off the position the ply was played into, where a face-down
            // victim's identity still stands: what the capture disclosed.
            if kind.conceals,
               let capture = CapturedPieces.capture(atPly: ply, by: move, in: before) {
                captured.taken.append(capture)
            }
            lastMove = move
            selected = nil
            refreshLegalMoves()
        } catch {
            let refusal = CoreError(wrapping: error)
            // The player's own refused move raises the capsule; a refused AI
            // reply raises nothing, because the retry is the app's.
            if byOpponent { opponentFailure = refusal } else { failure = refusal }
        }
    }

    /// The position and state, asked of the core again after every change.
    private func refresh() throws {
        evaluation = try core.evaluate(kind, from: start, moves: moves)
        placement = Placement(fen: evaluation.fen, game: kind)
    }

    private func refreshLegalMoves() {
        do {
            legalMoves = try core.legalMoves(kind, from: start, moves: moves).map {
                try Self.move(reading: $0, on: kind.board)
            }
        } catch {
            legalMoves = []
            failure = CoreError(wrapping: error)
        }
    }
}

private struct UnreadableCoreMove: Error, CustomStringConvertible {
    var text: String
    var description: String { "the core returned an unreadable move: \(text)" }
}
