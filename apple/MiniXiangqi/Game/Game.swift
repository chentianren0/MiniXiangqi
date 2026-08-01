// A game in progress, as the screen needs it.
//
// Every rule question — what is legal, whether a side is in check, whether the
// game is over and why, whether Undo is on offer — is answered by the core,
// which since the move onto sessions also owns the game itself: the moves, the
// commit of every accepted one, and the History record a finished game becomes.
// What lives here is the screen's own reading of that session — the placement,
// the selection, the notation, the orientation — refreshed from the core after
// every change rather than maintained as a second truth.

import MiniXiangqiCore
import Observation

/// The rules, as this type asks them. `Core` is the only implementation the app
/// ever runs, and this is not an abstraction over rule engines: it exists
/// because a core call that fails is a state this type must handle — the ply
/// refused, the position unchanged, the failure recorded, the transition above
/// abandoned — and a working core will not produce one on request. A stand-in
/// may refuse a call; it may never answer a rules question itself.
///
/// The seam now speaks to a session. Mutations — beginning a game, a move, an
/// Undo, the two terminal commits — are what a stand-in refuses, because each
/// one is a store commit that can genuinely fail; the queries beneath them are
/// projections of the same session and pass through untouched.
protocol Rules: AnyObject {
    /// Whether a session is attached. Creation or resume attaches one;
    /// everything the board asks speaks to that real game.
    var hasSession: Bool { get }

    /// Attach the stored active game, if the library holds one. Absence is
    /// `false` and not an error: an untouched board has nothing to resume.
    func resumeActive() throws -> Bool

    /// Create and persist the active game from its frozen configuration. It is
    /// its own act: 开始对局 creates the game, and the first move follows on a
    /// board that already exists.
    func create(_ configuration: GameConfiguration) throws

    /// The created game's frozen configuration — mode, resolved human side,
    /// level, and exact thinking time.
    func configuration() throws -> GameConfiguration

    /// The session's stable identity, one half of the staleness comparison a
    /// search result is judged by.
    func gameID() throws -> String

    /// Commit the human's loss. The third terminal commit, legal exactly when
    /// `resign_available` reads 1.
    func resign() throws -> UInt64

    /// Apply one move and commit it before returning.
    func apply(_ move: String) throws

    /// Take back one decision and commit, returning the plies removed.
    func undo() throws -> Int

    /// Commit the claimable repetition as the game's draw. The terminal
    /// commit: the record is in History when this returns.
    func claimDraw() throws -> UInt64

    /// Commit an unconfirmed natural result as what it is. The other terminal
    /// commit, made when the player files the game rather than takes it back.
    func confirmResult() throws -> UInt64

    /// Archive the active game by its own current state and clear it, in one
    /// transaction. The fourth archiving path, and the only one that may record
    /// a game as ended early — what the state is worth is the core's to decide
    /// and never this app's to supply.
    ///
    /// It answers rather than returns because it runs off the UI thread, unlike
    /// every other mutation here: the threading contract keeps this one outside
    /// the active game's main-actor exception.
    func archiveActiveAndClear(
        completion: @escaping @MainActor (Result<UInt64, CoreError>) -> Void)

    /// The attached session's position and state.
    func evaluation() throws -> Evaluation

    /// The attached session's complete retained line.
    func moveHistory() throws -> [String]

    /// The legal moves of the current position.
    func legalMoves() throws -> [String]

    /// The position after the first `ply` plies, for reading the line back.
    func fen(atPly ply: Int) throws -> String
}

@Observable
final class Game {
    private let rules: Rules

    /// The retained line, as the core holds it: read back after every
    /// mutation, never maintained as a second copy.
    private(set) var moves: [String] = []

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

    /// The created game's frozen configuration. Which game, mode, resolved
    /// human side, level and thinking time are decided once, at creation, and
    /// never re-derived above the interface.
    private(set) var configuration: GameConfiguration

    /// The session's stable identity, frozen at creation. Half of the pair a
    /// search result is checked against before its move is applied.
    private(set) var identity: String

    /// The last claim or filing the store refused. Separate from `failure`
    /// because the contract routes the two differently: a refused ply is the
    /// transient capsule, a refused terminal commit is the blocking retry.
    private(set) var filingFailure: CoreError?

    /// Whether the player's draw claim has been committed. The claim is the
    /// player's, not the core's — but committing it is the core's, so this is
    /// true exactly when `claimDraw` returned with the game filed. A resumed
    /// game is never a claimed one: the claim archived it.
    private(set) var claimedDraw = false

    /// Whether the player conceded. Like a claimed draw, this is an outcome no
    /// position produces: the position the session still answers for is
    /// ongoing, and the result is the store's. A resumed game is never a
    /// resigned one, for the same reason — resigning archived it.
    private(set) var resigned = false

    /// The History record the terminal commit created, once one has.
    private(set) var filedRecordID: UInt64?

    var selected: Square?
    var flipped = false

    /// Opens the game the session holds.
    ///
    /// A `Game` is a real attached session, never the absence of one. The
    /// creation flow attaches before calling this initializer, and the launch
    /// flow explicitly resumes before calling it. Keeping those two acts above
    /// this type leaves no default game, starting position, configuration or
    /// identity for an absent session to invent.
    init(rules: Rules) throws {
        guard rules.hasSession else {
            throw CoreError(status: MxqStatus(MXQ_ERR_STATE_ACTIVE_GAME_MISSING),
                            detail: "Game requires an attached session")
        }
        let configuration = try rules.configuration()
        let identity = try rules.gameID()
        let moves = try rules.moveHistory()
        let notation = try Self.notation(reading: moves, from: rules)
        let lastMove = moves.last.flatMap { Move(text: $0) }
        let evaluation = try rules.evaluation()
        self.rules = rules
        self.moves = moves
        self.notation = notation
        self.lastMove = lastMove
        self.evaluation = evaluation
        self.configuration = configuration
        self.identity = identity
        self.placement = Placement(fen: evaluation.fen)
        // The accepted orientation rule, applied once: in human-versus-AI play
        // the human's own side is at the bottom, and Red at the bottom is the
        // unflipped board. Free Play opens unflipped and keeps its flip control.
        self.flipped = configuration.humanSide == .black
        refreshLegalMoves()
    }

    /// The stored line, read as it was written — the same reading a History
    /// record's replay gets, so a relaunch and a replay say the same words
    /// about the same game.
    private static func notation(reading moves: [String],
                                 from rules: Rules) throws -> [MoveReading] {
        do {
            return try MoveReading.line(for: moves) {
                Placement(fen: try rules.fen(atPly: $0))
            }
        } catch {
            throw CoreError(wrapping: error)
        }
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
        return placement.general(of: evaluation.sideToMove)
    }

    // MARK: - Result

    /// Over one way or the other: adjudicated by the core, claimed by the
    /// player, or conceded by them. All three stop input; only the first can be
    /// taken back.
    var isFinished: Bool { evaluation.isOver || claimedDraw || resigned }

    /// The result to present. A claimed draw is a draw and a resignation is the
    /// opponent's win, whatever the session still calls the position — the
    /// committed outcome is the store's, and the act is what committed it.
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

    /// The core's own answer, which already says everything this used to work
    /// out: a natural result stays undoable while its presentation is
    /// unconfirmed, and a claimed draw — an archived session — offers nothing.
    var canUndo: Bool { evaluation.undoAvailable }

    // MARK: - The opponent, where there is one

    var kind: GameKind { configuration.game }
    var mode: PlayMode { configuration.mode }
    var isHumanVersusAI: Bool { mode == .humanVersusAI }

    /// The side the player controls, in human-versus-AI play. Free Play has
    /// none: the same person controls both.
    var humanSide: Side? { isHumanVersusAI ? configuration.humanSide : nil }

    /// Whether the AI owes a move here. The core's own flag, and the whole
    /// definition of "a search is owed": nothing above the interface works it
    /// out from the mode and the side to move.
    var searchExpected: Bool { evaluation.searchExpected && !isFinished }

    /// Whether 认输 is on offer, which is exactly when the core will accept it.
    var canResign: Bool { evaluation.resignAvailable }

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
        /// Take up this piece.
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
        // A finished game accepts no input, and it is refused here rather than
        // by each caller: a board that has nothing left to play has nothing
        // left to offer at any point on it.
        guard !isFinished else { return .unavailable }
        // Nor does a board waiting on the opponent. The core says whose turn it
        // is by expecting a search, so the rule is read rather than re-derived
        // from the mode and the side to move — and it holds for the whole time
        // the AI owes a move, whether the search is running, still to be
        // started, or stalled behind a preparation that has not succeeded yet.
        guard !searchExpected else { return .unavailable }

        if square == selected { return .cancelSelection }
        if let selected, let move = legalMoves.first(where: {
            $0.from == selected && $0.to == square
        }) {
            return .play(move)
        }
        if placement[square]?.side == evaluation.sideToMove { return .select(square) }
        return selected == nil ? .unavailable : .illegal
    }

    func tap(_ square: Square) {
        switch effect(ofTapAt: square) {
        case .cancelSelection: selected = nil
        case .play(let move): play(move)
        case .select(let square): selected = square
        case .illegal, .unavailable: break
        }
    }

    /// Takes back one decision. The core commits the shortened game before
    /// returning, so an Undo it cannot complete does not happen: the game
    /// stays exactly at the pre-action committed state and the failure is
    /// recorded.
    func undo() {
        failure = nil
        opponentFailure = nil
        guard canUndo else { return }
        do {
            let removed = try rules.undo()
            moves = try rules.moveHistory()
            notation.removeLast(removed)
            try refresh()
            // The brackets always mark the move that produced the position on
            // screen, so an Undo moves them to the move that is now last, and
            // an initial position carries none.
            lastMove = moves.last.flatMap { Move(text: $0) }
            selected = nil
            refreshLegalMoves()
        } catch {
            failure = CoreError(wrapping: error)
        }
    }

    /// Ends the game as a draw on the repetition the core is offering, which
    /// is the terminal commit: the record is in History when it succeeds. Only
    /// the core decides whether the claim exists; this decides nothing but
    /// that the player took it — and a commit the store refused leaves the
    /// game running and claimable exactly as it stood.
    func claimDraw() {
        filingFailure = nil
        guard evaluation.claimAvailable, !claimedDraw else { return }
        do {
            filedRecordID = try rules.claimDraw()
            claimedDraw = true
            selected = nil
            // The archived session still answers every query; what changes is
            // the affordances, which now all read 0.
            try refresh()
            refreshLegalMoves()
        } catch {
            filingFailure = CoreError(wrapping: error)
        }
    }

    /// Concedes the game. The third terminal commit: the record is in History
    /// when it succeeds, the loss recorded against the human's own side. Only
    /// the core decides whether resignation is on offer, and a commit the store
    /// refused leaves the game running exactly as it stood.
    func resign() {
        filingFailure = nil
        guard canResign, filedRecordID == nil else { return }
        do {
            filedRecordID = try rules.resign()
            resigned = true
            selected = nil
            // The archived session still answers every query; what changes is
            // the affordances, which now all read 0.
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
        guard let fen = try? rules.fen(atPly: ply) else { return nil }
        return Placement(fen: fen)
    }

    /// Files the finished game in History: what the notice's 保存 does on its
    /// own, and what 开始新对局 does before anything resets. An unconfirmed
    /// natural result is committed as what it is; a game that is already a
    /// record — filed by a claim, or by a 保存 the player has already pressed —
    /// is not filed a second time, and asking the archived session to confirm
    /// again would be asking for a refusal the app would then have to explain.
    /// A refusal of the real thing leaves the game exactly as it stood, active
    /// and resumable.
    func file() throws {
        assert(isFinished, "only a finished game is filed here")
        filingFailure = nil
        guard filedRecordID == nil else { return }
        do {
            filedRecordID = try rules.confirmResult()
        } catch {
            let failure = CoreError(wrapping: error)
            filingFailure = failure
            throw failure
        }
        // The archived session still answers every query, and what changes is
        // the affordances: a filed game has nothing left to take back, so the
        // controls stop offering it. The result itself is untouched — the state
        // the core reports is still the position's own verdict. A read that
        // fails out here is the ordinary refused-read state rather than a
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
    /// move: this is, and the core refuses it exactly as it would refuse a bad
    /// move of the player's own.
    func playOpponent(_ move: Move) {
        play(move, byOpponent: true)
    }

    private func play(_ move: Move, byOpponent: Bool = false) {
        if byOpponent { opponentFailure = nil } else { failure = nil }
        let read = MoveReading(of: move, in: placement)
        do {
            try rules.apply(move.text)
            moves = try rules.moveHistory()
            notation.append(read)
            try refresh()
            lastMove = move
            selected = nil
            refreshLegalMoves()
        } catch {
            let refusal = CoreError(wrapping: error)
            // A refused save leaves the game exactly at the pre-mutation state
            // either way. Which of the two it is recorded as decides what the
            // screen says: the player's own move raises the capsule, and the
            // AI's reply raises nothing, because the retry is the app's.
            if byOpponent { opponentFailure = refusal } else { failure = refusal }
        }
    }

    /// The projection: the position and state are the core's answers for the
    /// committed game, asked again after every change.
    private func refresh() throws {
        evaluation = try rules.evaluation()
        placement = Placement(fen: evaluation.fen)
    }

    private func refreshLegalMoves() {
        do {
            legalMoves = try rules.legalMoves().compactMap(Move.init(text:))
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
    /// It goes through the same path a person's move does — the session already
    /// exists and every ply commits — so nothing here knows a rule the core has
    /// not been asked. A refused move is a bug in the line rather than a rules
    /// outcome, so it is raised rather than skipped.
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

/// The refusal the seam exists for.
struct RefusedByTheCore: Error { }

/// The real core, with a switch that makes it refuse. Every answer here is the
/// core's own — nothing decides a rule — and refusing is the only way to reach
/// the state a failed commit leaves behind, which everything above has to
/// survive: the ply refused, the position unchanged, a transition holding
/// nothing to draw, the capsule saying so. It refuses the mutations, because
/// those are the commits that can genuinely fail; the queries beneath them
/// keep answering, as a live core's would while its disk does not.
///
/// In the app it stands behind `-mxq-refuse-saves`, so a screenshot of the
/// save-failure state can come from the real screen; in the unit suite it is
/// the stand-in the failure tests hold.
final class RefusingRules: Rules {
    private let real: Rules
    var refuses: Bool

    init(_ real: Rules, refuses: Bool = false) {
        self.real = real
        self.refuses = refuses
    }

    private func refuseIfAsked() throws {
        if refuses { throw CoreError(wrapping: RefusedByTheCore()) }
    }

    var hasSession: Bool { real.hasSession }
    func resumeActive() throws -> Bool { try real.resumeActive() }
    func configuration() throws -> GameConfiguration { try real.configuration() }
    func gameID() throws -> String { try real.gameID() }

    /// Creation is deliberately *not* refused. `-mxq-refuse-saves` exists to
    /// photograph the refused-ply state, and a stand-in that would not let a
    /// game be created could never reach a ply to refuse.
    func create(_ configuration: GameConfiguration) throws {
        try real.create(configuration)
    }

    func resign() throws -> UInt64 {
        try refuseIfAsked()
        return try real.resign()
    }

    func apply(_ move: String) throws {
        try refuseIfAsked()
        try real.apply(move)
    }

    func undo() throws -> Int {
        try refuseIfAsked()
        return try real.undo()
    }

    func claimDraw() throws -> UInt64 {
        try refuseIfAsked()
        return try real.claimDraw()
    }

    func confirmResult() throws -> UInt64 {
        try refuseIfAsked()
        return try real.confirmResult()
    }

    /// The refusal answers on the next turn rather than inside the call, which
    /// is the one thing this stand-in has to copy about the real one: the real
    /// archive runs on a queue and can never answer before the press that asked
    /// for it has finished being handled. An answer that arrived inside the
    /// press would reach an alert that is still dismissing itself.
    func archiveActiveAndClear(
        completion: @escaping @MainActor (Result<UInt64, CoreError>) -> Void
    ) {
        guard refuses else {
            real.archiveActiveAndClear(completion: completion)
            return
        }
        Task { @MainActor in completion(.failure(CoreError(wrapping: RefusedByTheCore()))) }
    }

    func evaluation() throws -> Evaluation { try real.evaluation() }
    func moveHistory() throws -> [String] { try real.moveHistory() }
    func legalMoves() throws -> [String] { try real.legalMoves() }
    func fen(atPly ply: Int) throws -> String { try real.fen(atPly: ply) }
}
#endif
