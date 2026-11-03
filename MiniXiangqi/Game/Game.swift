// A game in progress, as the screen needs it.
//
// The game is its GameRecord in the library: the moves, saved as each is
// played, and the result a finished game is filed with. Every rule question —
// what is legal, whether a side is in check, whether the game is over and why —
// is the core's replay of those moves. What lives here is the game's own policy
// above the rules — how much one Undo takes back, whose turn owes the AI a
// search, when resignation is on offer — and the screen's reading of the game:
// the placement, the selection, the notation, the orientation, refreshed after
// every change rather than maintained as a second truth.

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

    /// Each played move as the player reads it, in both notations. Recorded when
    /// the move is played — a reading depends on the placement *before* it — and
    /// recomputed the same way when a stored game resumes, so a relaunch reads
    /// exactly as the sitting it interrupted did. The 记谱法 preference selects
    /// between the two readings where the list is drawn, not here: a preference
    /// change re-renders the game on screen rather than recomputing it.
    private(set) var notation: [MoveReading] = []

    /// What the game has taken off the board, for the one game that displays it.
    ///
    /// Kept exactly as the notation is — appended as a ply lands, shortened by
    /// the core's own count when one is taken back, and read back the same way
    /// when a stored game resumes — because it is the same kind of fact: a
    /// property of the line, recomputed from the positions the core replays and
    /// never maintained as a second truth. Empty in every game whose position is
    /// wholly public, which is every game but Jieqi.
    private(set) var captured = CapturedPieces()

    /// The last attempt's failed core call, recorded rather than swallowed. A
    /// refused ply is the accepted save-failure state: the move or Undo did
    /// not happen, the position is unchanged, and a new attempt starts clean —
    /// the user may simply try again.
    private(set) var failure: CoreError?

    /// The same refusal, when the ply that failed was the AI's reply. Kept
    /// apart from `failure` because the contract answers the two differently:
    /// a refused move of the player's own raises the capsule, and a refused AI
    /// reply raises nothing at all — the retry is the app's, not the user's, so
    /// there is nothing to tell them and nothing for them to do.
    private(set) var opponentFailure: CoreError?

    /// The created game's configuration. Which game, mode, resolved human side
    /// and level are decided once, at creation.
    private(set) var configuration: GameConfiguration

    /// Whose move ply 0 is — the start position's own side, read from the core
    /// once. A game composed in the Custom Scene editor may open with Black, so
    /// the move list pairs and numbers from this rather than from a parity.
    let firstMover: Side

    /// The last claim or filing the store refused. Separate from `failure`
    /// because the contract routes the two differently: a refused ply is the
    /// transient capsule, a refused terminal commit is the blocking retry.
    private(set) var filingFailure: CoreError?

    /// Whether the player's draw claim has been filed. A resumed game is never
    /// a claimed one: the claim filed it.
    private(set) var claimedDraw = false

    /// Whether the player conceded. Like a claimed draw, this is a result no
    /// position produces: the position is still ongoing, and the result is the
    /// record's. A resumed game is never a resigned one, for the same reason.
    private(set) var resigned = false

    /// The History record the game became, once it is filed.
    private(set) var filedRecordID: UUID?

    var selected: Square?
    var flipped = false

    /// Opens the game in play the library holds. Creating or resuming it is
    /// the caller's act, so there is no default game for an absent one to
    /// invent.
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
        // The accepted orientation rule, applied once: in human-versus-AI play
        // the human's own side is at the bottom, and Red at the bottom is the
        // unflipped board. Free Play opens unflipped and keeps its flip control.
        //
        // A placement board has no orientation to have: stones carry nothing a
        // player could read the wrong way up, which is why these games drop the
        // flip control altogether — so it opens, and stays, as it is drawn.
        self.flipped = !game.isPlacement && configuration.humanSide == .black
        refreshLegalMoves()
    }

    /// The stored line, read as it was written — the same reading a History
    /// record's replay gets, so a relaunch and a replay say the same words
    /// about the same game.
    private static func notation(reading moves: [String], game: GameKind,
                                 at position: (Int) throws -> Placement) throws -> [MoveReading] {
        do {
            return try MoveReading.line(for: moves, on: game, placementAt: position)
        } catch {
            throw CoreError(wrapping: error)
        }
    }

    /// What the stored line took off the board — the same walk the reading
    /// above makes, over the same positions, so a resumed game's surface and a
    /// replayed record's are one answer. Nothing at all for a game that
    /// displays no captured pieces, which is every game but Jieqi.
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

    /// The empty points the side to move may not play — Renju's forbidden
    /// points, marked on the board while Black is to move.
    var forbiddenPoints: Set<Square> {
        Self.forbiddenPoints(of: kind, in: placement, legalMoves: legalMoves,
                             sideToMove: evaluation.sideToMove, isOver: isFinished)
    }

    /// The same question asked of a position rather than of this game, for the
    /// reason `effect(ofTapAt:)` below is: there are two boards, and a second
    /// copy of this would be a second place for them to mark different points.
    ///
    /// **Derived from the legal-move set and from nothing else.** A placement
    /// game's legal moves are its empty points less whatever is forbidden to the
    /// side to move, so the difference between the two *is* the forbidden set,
    /// and the core — which asks the engine's own board machinery — remains the
    /// only thing that decided it. Nothing here knows what a double three is.
    ///
    /// Asked only where the answer can be non-empty: Renju is the one game with
    /// forbidden points, and they are Black's alone. Free Play and a nearby game
    /// both sit on both sides of the board, so the marks appear and go with the
    /// turn there exactly as they do against the machine.
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

    /// The checked general, so the board can ring it. The side to move is the
    /// side in check: the core reports check for the position on screen.
    var checkedGeneral: Square? {
        guard evaluation.inCheck else { return nil }
        return placement.general(of: evaluation.sideToMove)
    }

    // MARK: - Result

    /// Over one way or the other: adjudicated by the core, claimed by the
    /// player, or conceded by them. All three stop input; only the first can be
    /// taken back.
    var isFinished: Bool { evaluation.isOver || claimedDraw || resigned }

    /// The result to present. A claimed draw is a draw and a resignation is the
    /// opponent's win, whatever the rules still call the position — the result
    /// is the record's, and the act is what filed it.
    var presentedState: GameState {
        if claimedDraw { return .draw }
        if resigned { return humanSide == .red ? .blackWins : .redWins }
        return evaluation.state
    }

    /// The reason to present. A claimed draw needs none of its own — the one
    /// the core reports is the one the claim was available for — but a
    /// resignation does: the position it was made in has no verdict, so the
    /// core reports no reason, and the reason is the act.
    var presentedReason: EndReason { resigned ? .resignation : evaluation.reason }

    /// How many plies one Undo takes back: 1 or 2, by the decision-cycle rule,
    /// and 0 where there is nothing to take back.
    ///
    /// Free Play takes back one ply, down to the start. Human-versus-AI play
    /// proceeds by the human's decisions: with the human's own move last, that
    /// move is what an Undo takes back; with the AI's reply last, the reply and
    /// the move that triggered it come off together. An AI-first game after the
    /// AI's opening move has no decision of the human's to return to. A
    /// networked game has no unilateral undo — a retraction there is the two
    /// players' agreement — and a filed game has nothing left to take back. A
    /// result the rules decided stays undoable until it is filed.
    var undoPlies: Int {
        guard filedRecordID == nil, !moves.isEmpty, !mode.isNetworked else { return 0 }
        guard isHumanVersusAI, let humanSide else { return 1 }
        if mover(ofPly: moves.count - 1) == humanSide { return 1 }
        return moves.count >= 2 ? 2 : 0
    }

    var canUndo: Bool { undoPlies > 0 }

    /// Which side made ply `index`: the start's side to move, and the other in
    /// turn.
    func mover(ofPly index: Int) -> Side {
        index % 2 == 0 ? firstMover : firstMover.opponent
    }

    /// Whether the deal this game conceals is disclosed now.
    ///
    /// docs/jieqi-rules.md: **when the game ends, every hidden identity is
    /// disclosed to both players** — by any ending, a resignation and an agreed
    /// draw included. So the position's concealment ends with the game: the
    /// board shows every piece it was still hiding, and the captured surface
    /// resolves its counts into the pieces they were counting. Nothing but a
    /// game that conceals has anything to disclose.
    ///
    /// It says *whether*, not *when*: the board waits for the ply that ended the
    /// game to finish being shown, exactly as the result notice does, and that
    /// is the screen's own beat rather than a fact about the game.
    var disclosesTheDeal: Bool { kind.conceals && isFinished }

    // MARK: - The opponent, where there is one

    var kind: GameKind { configuration.game }
    var mode: PlayMode { configuration.mode }
    var isHumanVersusAI: Bool { mode == .humanVersusAI }

    /// The side the player controls, in human-versus-AI play. Free Play has
    /// none: the same person controls both.
    var humanSide: Side? { isHumanVersusAI ? configuration.humanSide : nil }

    /// Whether the AI owes a move here: a human-versus-AI game that is still
    /// running, with the AI's side to move.
    var searchExpected: Bool {
        isHumanVersusAI && !isFinished && evaluation.sideToMove != humanSide
    }

    /// Whether 认输 is on offer: a human-versus-AI game with no result of its
    /// own. A claimable repetition is not a result.
    var canResign: Bool { isHumanVersusAI && filedRecordID == nil && !evaluation.isOver }

    /// The line the AI and the hint search.
    var searchLine: SearchLine { SearchLine(game: kind, start: start, moves: moves) }

    // MARK: - Input

    /// What a tap on a point means. One home for the board's whole affordance:
    /// whether a point offers a move, a piece, or nothing is a question about
    /// the position, and the position is here. The motion above asks this and
    /// adds only the animation — an own-side test or an unavailable-input
    /// guard written a second time up there is a second place for the board to
    /// disagree with itself.
    enum TapEffect: Equatable {
        /// Put the held piece down: it was tapped again.
        case cancelSelection
        /// A legal move, ready to play.
        case play(Move)
        /// Take up this piece — or, where the game places rather than moves and
        /// the player has asked to confirm, mark this point for the stone.
        case select(Square)
        /// A point the held piece cannot reach. It moves nothing and keeps the
        /// selection, so the correction is one tap away; the answer — the
        /// legal destinations strengthening once — is PlayMotion's, not a game
        /// state.
        case illegal
        /// Nothing this game can act on: a point that offers nothing with
        /// nothing held, or a board with nothing left to play.
        case unavailable
    }

    func effect(ofTapAt square: Square) -> TapEffect {
        // A finished game accepts no input, and nor does a board waiting on the
        // opponent. The core says whose turn it is by expecting a search, so the
        // rule is read rather than re-derived from the mode and the side to
        // move — and it holds for the whole time the AI owes a move, whether the
        // search is running, still to be started, or stalled behind a
        // preparation that has not succeeded yet.
        Self.effect(ofTapAt: square, in: placement, legalMoves: legalMoves,
                    sideToMove: evaluation.sideToMove, selected: selected,
                    acceptsInput: !isFinished && !searchExpected,
                    confirmsPlacement: UserDefaults.standard.bool(forKey: "placementConfirmation.enabled"))
    }

    /// The same question asked of a position rather than of this game: what a
    /// tap on a point means, given what stands there, what the core says is
    /// legal, and whether this board is accepting input at all.
    ///
    /// It is written once because there are two boards now. A nearby game's
    /// position comes from the protocol engine's plies rather than from the
    /// library, and whose turn it is comes from the protocol rather
    /// than from a search being expected — but *what a tap means* is the same
    /// question about the same board, and a second copy of it would be a second
    /// place for the two to disagree. Nothing here decides a rule: the legal
    /// moves are the core's answer, and this only reads them.
    static func effect(ofTapAt square: Square, in placement: Placement,
                       legalMoves: [Move], sideToMove: Side, selected: Square?,
                       acceptsInput: Bool,
                       confirmsPlacement: Bool = false) -> TapEffect {
        // Refused here rather than by each caller: a board with nothing left to
        // play, or one whose turn it is not, has nothing to offer at any point
        // on it.
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

    /// The same question on a board a stone is placed on.
    ///
    /// There is no piece to take up and no destination to send it to, so the
    /// select-then-destination grammar above has nothing to say here. What
    /// replaces it is one of two grammars, chosen by the player:
    ///
    /// - **Plain**, the default: a tap on a legal point plays it, under exactly
    ///   the committing rules, sounds and haptics a move goes through.
    /// - **Confirmed**, where the accepted Settings switch is on: the first tap
    ///   marks the point, tapping the mark commits it, tapping another legal
    ///   point moves the mark, and tapping off the board cancels it — which is
    ///   `PlayMotion.cancelSelection`, the same act that puts a held piece down.
    ///   Never an alert, and Undo remains the recovery either way.
    ///
    /// A point that carries no legal move is occupied or forbidden to the side
    /// to move. Either way it offers nothing, and — unlike a movement board,
    /// where an illegal tap answers by strengthening the destinations the held
    /// piece *does* have — this board draws no destinations, so there is nothing
    /// to strengthen and nothing to say on the board at all. That is exactly the
    /// unavailable case: the turn status takes it with the acknowledgment beat
    /// and the same lightest feedback an illegal tap gets, and the mark, if one
    /// stands, is left alone.
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

    /// Takes back one decision. The library saves the shortened game before
    /// returning, so an Undo it cannot complete does not happen: the game
    /// stays exactly as it was saved and the failure is recorded.
    func undo() {
        failure = nil
        opponentFailure = nil
        guard canUndo else { return }
        do {
            try library.undo(undoPlies)
            moves = try library.moveHistory()
            revision += 1
            // Cut to the line rather than shortened by the count, so a reading
            // that has fallen behind is repaired instead of compounded: the
            // saved line is what a game's readings are of, and after a refused
            // read there can be a ply saved with no reading beside it.
            notation = Array(notation.prefix(moves.count))
            // A retraction returns whatever those plies took, exactly as it
            // returns the position they produced.
            captured.removePlies(from: moves.count)
            try refresh()
            // The brackets always mark the move that produced the position on
            // screen, so an Undo moves them to the move that is now last, and
            // an initial position carries none.
            lastMove = try moves.last.map { try Self.move(reading: $0, on: kind.board) }
            selected = nil
            refreshLegalMoves()
        } catch {
            failure = CoreError(wrapping: error)
        }
    }

    /// Ends the game as a draw on the repetition the rules are offering, which
    /// files it: the record is in History when it succeeds. Only the rules
    /// decide whether the claim exists; this decides nothing but that the
    /// player took it — and a filing the library refused leaves the game
    /// running and claimable exactly as it stood.
    func claimDraw() {
        filingFailure = nil
        guard evaluation.claimAvailable, !claimedDraw else { return }
        do {
            filedRecordID = try library.claimDraw()
            claimedDraw = true
            selected = nil
            revision += 1
            // The position is unchanged; what changes is the affordances, which
            // a filed game no longer offers.
            try refresh()
            refreshLegalMoves()
        } catch {
            filingFailure = CoreError(wrapping: error)
        }
    }

    /// Concedes the game, which files it: the record is in History when it
    /// succeeds, the loss recorded against the human's own side. A filing the
    /// library refused leaves the game running exactly as it stood.
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

    /// The position after the first `ply` plies, as the core replays it. The
    /// undo of a decision cycle is what asks: both plies rewind in one gesture,
    /// and the disc that made the first of them — together with whatever the
    /// reply took from it — is read off the position *between* the two moves,
    /// which is this.
    func placement(atPly ply: Int) -> Placement? {
        guard let position = try? core.evaluate(kind, from: start,
                                                moves: Array(moves.prefix(ply))) else { return nil }
        return Placement(fen: position.fen, game: kind)
    }

    /// Files the finished game in History: what the notice's 保存 does on its
    /// own, and what 开始新对局 does before anything resets. A result the rules
    /// decided is filed as what it is; a game that is already a record — filed
    /// by a claim, or by a 保存 the player has already pressed — is not filed a
    /// second time. A refusal leaves the game exactly as it stood, in play and
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
        // What changes is the affordances: a filed game has nothing left to
        // take back, so the controls stop offering it. The result itself is
        // untouched — the state is still the position's own verdict. A read
        // that fails out here is the ordinary refused-read state rather than a
        // refused filing: the record exists either way.
        do {
            try refresh()
        } catch {
            failure = CoreError(wrapping: error)
        }
        refreshLegalMoves()
    }

    /// The opponent's reply, played through the same legal-move boundary a
    /// person's move goes through. A search result is never what commits a
    /// move: this is, and the library refuses it exactly as it would refuse a
    /// bad move of the player's own.
    func playOpponent(_ move: Move) {
        play(move, byOpponent: true)
    }

    func play(_ move: Move, byOpponent: Bool = false) {
        if byOpponent { opponentFailure = nil } else { failure = nil }
        // The position the ply is leaving, kept because the reading is of it —
        // and read only once the ply has been committed and the position it
        // produced is in hand, since what a Jieqi ply turned up is a fact about
        // the position afterwards.
        let before = placement
        let ply = moves.count
        do {
            try library.apply(move.text)
            moves = try library.moveHistory()
            revision += 1
            try refresh()
            notation.append(MoveReading(of: move, in: before, after: placement))
            // What the ply took, read off the position it was played into —
            // where a face-down victim's identity still stands in the record,
            // which is what the capture disclosed to whoever made it.
            if kind.conceals,
               let capture = CapturedPieces.capture(atPly: ply, by: move, in: before) {
                captured.taken.append(capture)
            }
            lastMove = move
            selected = nil
            refreshLegalMoves()
        } catch {
            let refusal = CoreError(wrapping: error)
            // A refused save leaves the game exactly as it was saved either
            // way. Which of the two it is recorded as decides what the
            // screen says: the player's own move raises the capsule, and the
            // AI's reply raises nothing, because the retry is the app's.
            if byOpponent { opponentFailure = refusal } else { failure = refusal }
        }
    }

    /// The projection: the position and state are the core's answers for the
    /// saved line, asked again after every change.
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
