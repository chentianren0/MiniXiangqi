// A game in progress, as the screen needs it.
//
// Every rule question — what is legal, whether a side is in check, whether the
// game is over and why, whether Undo is on offer — is answered by the core,
// which since the move onto sessions also owns the game itself: the moves, the
// commit of every accepted one, and the History record a finished game becomes.
// What lives here is the screen's own reading of that session — the placement,
// the selection, the notation, the orientation — refreshed from the core after
// every change rather than maintained as a second truth.

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
    /// Whether a session is attached. The first move of a fresh board begins
    /// one; everything after speaks to it.
    var hasSession: Bool { get }

    /// Attach the stored active game, if the library holds one. Absence is
    /// `false` and not an error: an untouched board has nothing to resume.
    func resumeActive() throws -> Bool

    /// Create the active game and play its first move — one user-visible
    /// action, so a refusal of either half is one refusal of the move.
    func begin(with move: String) throws

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

    /// The position and state — the session's, or the frozen start's before a
    /// session exists.
    func evaluation() throws -> Evaluation

    /// The session's complete retained line; empty before a session exists.
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

    /// Each played move as the player reads it. Recorded when the move is
    /// played — traditional notation depends on the placement *before* it —
    /// and recomputed the same way when a stored game resumes, so a relaunch
    /// reads exactly as the sitting it interrupted did.
    private(set) var notation: [String] = []

    /// The last attempt's failed core call, recorded rather than swallowed. A
    /// refused ply is the accepted save-failure state: the move or Undo did
    /// not happen, the position is unchanged, and a new attempt starts clean —
    /// the user may simply try again.
    private(set) var failure: CoreError?

    /// The last claim or filing the store refused. Separate from `failure`
    /// because the contract routes the two differently: a refused ply is the
    /// transient capsule, a refused terminal commit is the blocking retry.
    private(set) var filingFailure: CoreError?

    /// Whether the player's draw claim has been committed. The claim is the
    /// player's, not the core's — but committing it is the core's, so this is
    /// true exactly when `claimDraw` returned with the game filed. A resumed
    /// game is never a claimed one: the claim archived it.
    private(set) var claimedDraw = false

    /// The History record the terminal commit created, once one has.
    private(set) var filedRecordID: UInt64?

    var selected: Square?
    var flipped = false

    /// Resumes the stored active game if there is one, or opens the empty
    /// board without creating anything: a session begins at the first move,
    /// so an untouched board persists nothing.
    init(rules: Rules) throws {
        var moves: [String] = []
        var notation: [String] = []
        var lastMove: Move?
        if try rules.resumeActive() {
            moves = try rules.moveHistory()
            notation = try Self.notation(reading: moves, from: rules)
            lastMove = moves.last.flatMap { Move(text: $0) }
        }
        let evaluation = try rules.evaluation()
        self.rules = rules
        self.moves = moves
        self.notation = notation
        self.lastMove = lastMove
        self.evaluation = evaluation
        self.placement = Placement(fen: evaluation.fen)
        refreshLegalMoves()
    }

    /// The stored line, read as it was written — the same reading a History
    /// record's replay gets, so a relaunch and a replay say the same words
    /// about the same game.
    private static func notation(reading moves: [String],
                                 from rules: Rules) throws -> [String] {
        do {
            return try MoveNotation.line(for: moves) {
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

    /// Over one way or the other: adjudicated by the core, or claimed by the
    /// player. Both stop input; only one of them can be taken back.
    var isFinished: Bool { evaluation.isOver || claimedDraw }

    /// The result to present. A claimed draw is a draw whatever the session
    /// still calls the position — the committed outcome is the store's, and
    /// the claim is what committed it — and it needs no separate reason: the
    /// one the core reports is the one the claim was available for.
    var presentedState: GameState { claimedDraw ? .draw : evaluation.state }

    /// The core's own answer, which already says everything this used to work
    /// out: a natural result stays undoable while its presentation is
    /// unconfirmed, and a claimed draw — an archived session — offers nothing.
    var canUndo: Bool { evaluation.undoAvailable }

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

    private func play(_ move: Move) {
        failure = nil
        let read = MoveNotation.text(for: move, in: placement)
        do {
            // The session begins at the first move — creation and the move are
            // one user-visible action — and every later move speaks to it.
            if rules.hasSession {
                try rules.apply(move.text)
            } else {
                try rules.begin(with: move.text)
            }
            moves = try rules.moveHistory()
            notation.append(read)
            try refresh()
            lastMove = move
            selected = nil
            refreshLegalMoves()
        } catch {
            failure = CoreError(wrapping: error)
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
    /// It goes through the same path a person's move does — the session is
    /// created at the first move and every ply commits — so nothing here knows
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

    func begin(with move: String) throws {
        try refuseIfAsked()
        try real.begin(with: move)
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

    func evaluation() throws -> Evaluation { try real.evaluation() }
    func moveHistory() throws -> [String] { try real.moveHistory() }
    func legalMoves() throws -> [String] { try real.legalMoves() }
    func fen(atPly ply: Int) throws -> String { try real.fen(atPly: ply) }
}
#endif
