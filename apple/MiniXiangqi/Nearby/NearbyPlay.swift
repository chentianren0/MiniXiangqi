// A nearby game as its board shows it: the position the session's plies
// produce, the transitions between them, and the one ply this device may add.
//
// It is the third consumer of the shared motion language, beside play and
// replay, and it takes exactly what they take: TransitMotion for the travelling
// disc, Motion for every duration, Feedback for what is heard and felt. Nothing
// about a disc crossing a board is decided here — a nearby move is a move, and a
// second copy of that would be a second thing to keep right.
//
// What is only true of a nearby board is the rest of this file. **A ply travels,
// a ply taken back reverses, anything else cuts** — the rule replay already
// states, and the honest one here: an opponent's move arrives as one ply and is
// shown travelling, a retraction the two players agreed on is the board's own
// Undo with a second person in it, while a reconnection that truncates or
// resends a line is a change of position rather than a move, and nobody wants to
// watch it replayed. **The turn is the protocol's**: the board accepts a tap
// only while the session is in play and the ply is this device's, so a
// connection that has idled out between moves locks the board quietly until the
// driver has it back.
//
// **The negotiations are the engine's law, read.** Whether a draw may be
// offered, whether a retraction may be asked for, what may be accepted, and
// whether the claim stands are questions with one answer each, and it is the
// engine's; every one of them is read off the session it publishes or asked of
// the driver. Nothing is re-derived, and nothing is remembered: an offer the
// engine voids because a ply landed on it disappears from this object at the
// same instant, because this object never held it.
//
// **The session is not this object's.** It lives in the engine, above every
// page, and this is a presentation of it that is built when the board opens and
// let go of when it closes. That is also what keeps a nearby move's sound with
// the board that is showing it: a move arriving while the player is somewhere
// else in the app is drawn — silently — when they come back to it.

import Foundation
import Observation
import SwiftUI

/// A finished nearby game, in the vocabulary the result surfaces already speak.
nonisolated struct NearbyEnd: Equatable, Sendable {
    var state: GameState
    var reason: EndReason
    /// Whether the two players agreed the draw between themselves.
    var byAgreement: Bool

    /// The protocol names movers and the core names the side that moves first,
    /// which is what `Side.red` is in every game the app carries — the same
    /// equation the rules oracle makes on its side, and the same reason neither
    /// of them names a colour. What the first mover's stones or pieces are
    /// called is the game's, and every surface asks `GameKind` for it.
    init(_ end: BoardGameEnd) {
        state = switch end.result {
        case .moverWins(.first): .redWins
        case .moverWins(.second): .blackWins
        case .draw: .draw
        }
        reason = switch end.ending {
        case .rulesDecided(let reason): reason
        case .resignation, .bothResigned: .resignation
        // An agreed draw is nothing the position decided, so the core has no
        // word for it and this carries its own below.
        case .agreedDraw: .none
        }
        byAgreement = end.ending == .agreedDraw
    }
}

@MainActor
@Observable
final class NearbyPlay {
    let sessionID: String
    let game: GameKind
    /// The position this session's game begins from, where its start is dealt
    /// rather than frozen. It is fixed for the session's whole life — a deal is
    /// what the game is being played over — and it never leaves this device.
    private let dealtStart: String?

    private let driver: any NearbyDriving
    private let positions: any NearbyPositions
    private let transits: TransitMotion
    private let animator: MotionAnimator
    private let feedback: Feedback

    var policy: MotionPolicy

    /// The session as the engine last published it. The authority for whose turn
    /// it is, whether the game is bound to a connection, and how it ended.
    private(set) var session: BoardGameSession

    /// The plies the board is drawing, which trail the session's own by exactly
    /// the length of a transition.
    private(set) var shown: [String]

    private(set) var placement: Placement
    private(set) var legalMoves: [Move] = []
    private(set) var lastMove: Move?
    /// What this game has taken off the board, as far as the board is drawing
    /// it. **Jieqi displays them, because there the reasoning does not hold:
    /// what a capture takes off the board is knowledge, and knowledge is that
    /// game's material.** Empty in every other game, which displays none.
    private(set) var captured = CapturedPieces()
    /// The core's evaluation of the drawn position: whose turn it is on the
    /// board, whether that side is in check, and what the position itself
    /// decides.
    private(set) var evaluation: Evaluation

    var selected: Square?
    private(set) var flipped: Bool

    private(set) var checkEmphasis: Double = 0
    private(set) var markerEmphasis: Double = 0
    private(set) var beatEmphasis: Double = 0

    /// Whether the board is turning round. A flip is presentational, but it
    /// holds board input for its 350 ms for the reason play's does: the tap
    /// targets stand where the board is turning *to* while the canvas is still
    /// part way round.
    private(set) var isFlipping = false
    private var flipGeneration = 0

    /// Whether the conclusion has been sounded. A result that arrives with no
    /// piece moving — a resignation, the peer's or this device's — has no
    /// landing to sound at, so it sounds at the moment the session gains its
    /// end, once.
    private var soundedConclusion = false

    /// - Parameter flipped: which way round to draw the board, where the player
    ///   has already turned it. The orientation rule below is what answers when
    ///   they have not.
    init?(session: BoardGameSession,
          driver: any NearbyDriving,
          positions: any NearbyPositions,
          flipped: Bool? = nil,
          policy: MotionPolicy = MotionPolicy(reduceMotion: false),
          animator: MotionAnimator = .live,
          feedback: Feedback = .live) {
        guard let game = GameKind(rulesID: session.rulesID),
              let standing = positions.standing(of: game, from: session.dealtStart,
                                                after: session.plies)
        else { return nil }

        self.sessionID = session.id
        self.game = game
        self.dealtStart = session.dealtStart
        self.session = session
        self.driver = driver
        self.positions = positions
        self.policy = policy
        self.feedback = feedback
        self.animator = animator
        self.transits = TransitMotion(animator: animator)
        self.shown = session.plies
        self.evaluation = standing.evaluation
        self.placement = Placement(fen: standing.evaluation.fen, game: game)
        // The accepted orientation rule, applied to the side this device is
        // playing: your own pieces are at the bottom, and the first mover at the
        // bottom is the unflipped board. Where it starts and not where it must
        // stay — the flip control turns it over, and a board turned round stays
        // turned round across leaving it, which is what the given value carries.
        //
        // A placement board has no orientation to have, which is why these games
        // carry no flip control: stones say nothing a player could read the
        // wrong way up. So it opens, and stays, as it is drawn — the same
        // sentence the local board's own initialiser makes.
        self.flipped = game.isPlacement ? false : (flipped ?? (session.localMover == .second))
        self.captured = Self.captures(of: game, from: session.dealtStart,
                                      after: session.plies, positions)
        adopt(standing)
        self.lastMove = shown.last.flatMap { Move(text: $0, on: game.board) }
        soundedConclusion = session.end != nil
        // Unowned: the transit belongs to this object and cannot outlive it.
        transits.arrived = { [unowned self] in announceLanding() }
        transits.ended = { [unowned self] in pulseCheckIfNeeded() }
        pulseCheckIfNeeded()
        watchTheLink()
    }

    // MARK: - What the board shows

    var transit: Transit? { transits.transit }
    var transitFade: Double { transits.fade }
    /// How far a revealed identity has come up on the travelling disc.
    var transitReveal: Double { transits.reveal }
    var isCommitting: Bool { transits.isRunning }

    /// Whether every hidden identity is now this player's to see. "When the game
    /// ends, every hidden identity is disclosed to both players — by any
    /// ending, a resignation and an agreed draw included", and a session that
    /// went away without a result is an ending for this board too.
    var disclosesTheDeal: Bool { game.conceals && isOver }

    var destinations: Set<Square> {
        guard let selected else { return [] }
        return Set(legalMoves.filter { $0.from == selected }.map(\.to))
    }

    var captures: Set<Square> {
        Set(destinations.filter { placement[$0] != nil })
    }

    /// The points the side to move may not play — Renju's, marked while Black is
    /// to move. Asked of the one place that derives them, over this board's own
    /// position: a nearby game sits on both sides of the board exactly as Free
    /// Play does, so the marks appear and go with the turn.
    ///
    /// **A finished position is over for this purpose the instant the position
    /// says so**, ahead of the session saying it — which is the local board's
    /// own rule and matters more here, because this device lands its own ply
    /// before the engine publishes what it decided. A finished position has no
    /// legal moves at all, and a derivation that ran over one would read every
    /// empty point on the board as forbidden.
    var forbiddenPoints: Set<Square> {
        Game.forbiddenPoints(of: game, in: placement, legalMoves: legalMoves,
                             sideToMove: evaluation.sideToMove,
                             isOver: isOver || evaluation.isOver)
    }

    var checkedGeneral: Square? {
        guard evaluation.inCheck, end == nil else { return nil }
        return placement.general(of: evaluation.sideToMove)
    }

    /// How the game ended, if it has. The session's answer and never the
    /// position's alone: a resignation is an outcome no position produces.
    var end: NearbyEnd? { session.end.map(NearbyEnd.init) }

    /// Why the session went away, where it went away without a result. A void
    /// session is gone from the engine, so nothing more will arrive for it and
    /// nothing this board could ask of it would be answered.
    private(set) var voided: NearbyVoid?

    /// Whether there is any more play in this board: a game with a result, or a
    /// session that is not there any more.
    var isOver: Bool { end != nil || voided != nil }

    /// Bound, exchanged, free to play, and still held. The engine's own answer
    /// with the one thing it cannot say added: a session it has parted with is
    /// not in the list this board's copy came from.
    private var isInPlay: Bool { voided == nil && session.isInPlay }

    /// The game went away under the board. It says so and stops.
    func wentAway(_ reason: NearbyVoid) {
        guard voided == nil else { return }
        voided = reason
        selected = nil
        stretch?.cancel()
        stretch = nil
    }

    /// What the status element describes. A finished game's result; otherwise
    /// the position — with the claim standing only where the *engine* says it
    /// stands for this device's player, which is not something a position
    /// decides on its own.
    var statusState: GameState {
        if let end { return end.state }
        guard evaluation.state == .claimableDraw else { return evaluation.state }
        return claimStands ? .claimableDraw : .ongoing
    }

    /// The line under the result: the shared vocabulary for every ending. A
    /// draw two players agreed is not a verdict on a position, and the core is
    /// asked about positions, so the live board names it from the ending rather
    /// than from an adjudication that reports none.
    var reasonText: String? {
        guard let end else { return nil }
        return end.byAgreement ? String(localized: "reason.agreedDraw") : end.reason.text
    }

    /// Who owns the turn — this device's player, or the other one. It is the
    /// protocol's answer, from the mover this device holds and the ply parity,
    /// rather than anything derived from the board.
    var controller: TurnStatus.Controller { session.isLocalTurn ? .you : .peer }

    /// Whose eyes this board is drawn for: this device's own player.
    ///
    /// It is what a nearby game adds to the captured surface. Free Play has one
    /// person holding both hands and shows both panels whole; here the two
    /// players' surfaces are not the same surface, and this device draws its
    /// player's. The protocol names movers and the core names the side that
    /// moves first, which is what `Side.red` is in every game the app carries —
    /// the same equation `NearbyEnd` makes for a result.
    var localSide: Side { session.localMover == .first ? .red : .black }

    /// Whether the board takes a tap: the game is on, the session is bound and
    /// exchanged, and the ply is this device's.
    var acceptsInput: Bool {
        isInPlay && session.isLocalTurn && !isOver
    }

    /// Whether 认输 is on offer. The engine's own law, read rather than
    /// re-derived: a resignation is valid from either peer at any point of an
    /// active session, and one made while the link is down is held and rides the
    /// next resume rather than being refused.
    var canResign: Bool { voided == nil && session.state == .active }

    // MARK: - The negotiations

    /// Whether 提和 may be pressed. The engine's `open` law, read: an offer is
    /// the off-turn peer's, in a session that is bound and exchanged, and only
    /// where nothing else stands.
    var canOfferDraw: Bool {
        isInPlay && !session.isLocalTurn && session.item == nil
    }

    /// The `keep` a take-back asks for: the engine's count less one at the
    /// moment of the request, which off turn is this device's own last ply.
    private var undoKeep: Int { session.count - 1 }

    /// Whether 悔棋 may be pressed — the same law, plus the range the engine
    /// states for `keep`.
    var canRequestUndo: Bool {
        canOfferDraw && (0..<session.count).contains(undoKeep)
    }

    /// What the other player has standing for this device to answer, if
    /// anything. It is the engine's own item: it appears when the engine
    /// records one and goes when the engine voids one — a landing ply, a
    /// resume — with nothing held here to go stale.
    var standingItem: NegotiationItem.Kind? {
        guard isInPlay, let item = session.item, item.opener == .peer else { return nil }
        return item.kind
    }

    /// Whether the claimed draw stands for this device's player. The driver's
    /// answer, which is the rules oracle the engine itself asks when the claim
    /// is played — never the position's `claimAvailable` alone, which knows
    /// nothing about whose turn it is in a session.
    var claimStands: Bool { voided == nil && driver.claimStands(in: session) }

    /// 提和. Nothing is drawn for it: an offer is a thing the other player now
    /// has, and this device's side of it is the control going quiet.
    func offerDraw() {
        guard canOfferDraw else { return }
        try? driver.offerDraw(in: sessionID)
    }

    /// 悔棋 — asking for this device's own last ply back. The count is read at
    /// the moment of the request, and the engine owns whether it is valid.
    func requestUndo() {
        guard canRequestUndo else { return }
        try? driver.requestUndo(keeping: undoKeep, in: sessionID)
    }

    /// 接受, for whichever of the two the other player has standing. The
    /// engine's own item decides what accepting means, so this asks it rather
    /// than being told: an accepted draw becomes the session's result, and an
    /// accepted retraction becomes a shorter line, both through the ordinary
    /// publication.
    func accept() {
        switch standingItem {
        case .drawOffer: try? driver.acceptDraw(in: sessionID)
        case .undoRequest: try? driver.acceptUndo(in: sessionID)
        case nil: return
        }
    }

    /// 判和. It is a ply like any other and travels as one, and the draw it
    /// produces is the rules' own rather than an agreement.
    func claimDraw() {
        guard claimStands else { return }
        try? driver.claim(in: sessionID)
    }

    /// Whether to say anything at all about the connection.
    ///
    /// **In ordinary play there is no connection chrome.** Connections idle out
    /// between moves by the radio's own design and the driver brings them back
    /// beneath the game, so a board that reported either would be reporting
    /// weather. What is worth one quiet line is the case where the link is
    /// actually costing the player something: what they did is waiting to reach
    /// the other device, or their own turn has been blocked long enough that the
    /// silence needs explaining. It withdraws by itself the moment the link is
    /// back.
    var isWaitingOnConnection: Bool {
        // A session that went away is not waiting for anything, and the notice
        // in front of the board has already said what became of it.
        guard voided == nil, !isLinked else { return false }
        // A terminal this device took that the other one has not answered for.
        // The engine holds it and it rides the next resume, which is the one
        // thing the player has done that has demonstrably not arrived. Once the
        // exchange has settled it there is nothing owed, and a link that idles
        // out afterwards is a finished board's own quiet.
        if !session.settled, session.localTerminal != nil { return true }
        return session.state == .active && session.isLocalTurn && blocked
    }

    /// Whether the session is bound to a connection at all, which is the whole
    /// of what "the two devices are talking" means here.
    private var isLinked: Bool { session.connection != nil }

    /// Whether the player's own turn has been blocked long enough to be worth
    /// saying: the stretch has passed, or they have already reached for the
    /// board and found it locked.
    private var blocked: Bool { blockedLongEnough || reachedForABlockedBoard }

    private var blockedLongEnough = false
    private var reachedForABlockedBoard = false
    private var stretch: Task<Void, Never>?

    /// How long an interruption on this device's own turn stays invisible.
    ///
    /// A re-dial takes a few seconds, and an idle-out is measured in tens of
    /// them, so this is well past both: nothing routine reaches it, and a link
    /// that has not come back by now is a silence the player is already
    /// wondering about.
    private static let connectionStretch = Duration.seconds(20)

    // MARK: - The session moving underneath

    /// The engine published. One added ply travels and one ply taken back
    /// reverses; anything else — a longer truncation, a resend, a line that came
    /// back different after a reconnection — arrives as the position it is.
    func sync(with session: BoardGameSession) {
        let ended = self.session.end == nil && session.end != nil
        let wasLinked = isLinked
        self.session = session
        if isLinked != wasLinked { watchTheLink() }
        defer { if ended { soundConclusionIfNeeded() } }

        guard session.plies != shown else { return }
        guard !transits.isRunning,
              let standing = positions.standing(of: game, from: dealtStart,
                                                after: session.plies)
        else {
            cut(to: session.plies)
            return
        }

        if session.plies.count == shown.count + 1, session.plies.dropLast() == shown,
           let text = session.plies.last, let move = Move(text: text, on: game.board) {
            // A ply with no origin is a stone, which came from off the board and
            // has nothing to cross it: it appears on its point with the
            // position, which is what a placed stone does.
            guard let origin = move.from else {
                return place(session.plies, standing, lastMove: move)
            }
            if let piece = placement[origin] {
                return advance(move, piece, to: session.plies, standing)
            }
        }
        if shown.count == session.plies.count + 1, shown.dropLast() == session.plies,
           let text = shown.last, let move = Move(text: text, on: game.board) {
            // And a stone taken back goes back off the board rather than home,
            // so the same nothing travels.
            guard move.from != nil else {
                return place(session.plies, standing,
                             lastMove: session.plies.last
                                 .flatMap { Move(text: $0, on: game.board) })
            }
            if let mover = placement[move.to] {
                return reverse(move, mover, to: session.plies, standing)
            }
        }
        cut(to: session.plies)
    }

    /// A ply arriving, shown crossing the board.
    private func advance(_ move: Move, _ piece: Piece, to plies: [String],
                         _ standing: NearbyStanding) {
        let captured = placement[move.to]
        // What the ply turned up, read off the position it produced — which is
        // the deal this device already holds, derived rather than disclosed:
        // nothing about the identity travelled with the move. It is the same
        // sentence the local board makes, and deliberately, because a reveal
        // arriving from the other device is the same event as one made here.
        let arrived = piece.isFaceDown
            ? Placement(fen: standing.evaluation.fen, game: game)[move.to] : nil
        let travel = Motion.travel(distance: Motion.distance(of: move), on: game.board)
        transits.run(policy.movement(Motion.travelAnimation(travel)),
                     drawingRemoval: captured != nil && !policy.reduceMotion) { [self] in
            land(plies, standing, lastMove: move)
            return Transit(kind: .move, move: move, piece: piece,
                           fading: captured.map { ($0, move.to) },
                           revealed: arrived)
        }
        // The identity comes up over the last stretch of the journey and is
        // there as the disc lands. Under Reduce Motion it rides the dissolve the
        // travel becomes, which the canvas draws from the travel's own progress.
        if !policy.reduceMotion {
            transits.raiseReveal(Motion.revealAnimation(travel: travel))
        }
        guard transits.drawsRemoval else { return }
        transits.raiseFade(Motion.captureFadeAnimation(travel: travel))
    }

    /// One ply taken back, drawn the way this board's own Undo draws one: the
    /// mover travels home and whatever it took reappears as it goes. The same
    /// motion because it is the same act — a retraction two players agreed on is
    /// an Undo with a second person in it.
    private func reverse(_ move: Move, _ mover: Piece, to plies: [String],
                         _ standing: NearbyStanding) {
        guard let origin = move.from else { return }
        // What the ply took, and what it had turned up, are both read off the
        // position it is going back to — the core's answer rather than a
        // placement worked out here.
        let before = Placement(fen: standing.evaluation.fen, game: game)
        let restored = before[move.to]
        // **A retraction returns the position's concealment**, so a ply that
        // revealed a piece puts it back face down where it came from. The face
        // the disc arrives home with is the one standing at the origin again,
        // and it is nil wherever nothing was turned back over.
        let returned = before[origin].flatMap { $0.isFaceDown ? $0 : nil }
        let travel = Motion.travel(distance: Motion.distance(of: move), on: game.board)
        transits.run(policy.movement(Motion.travelAnimation(travel))) { [self] in
            land(plies, standing,
                 lastMove: plies.last.flatMap { Move(text: $0, on: game.board) })
            return Transit(kind: .undo, move: Move(from: move.to, to: origin),
                           piece: mover, fading: restored.map { ($0, move.to) },
                           revealed: returned)
        }
        // The restored piece returns as the mover departs, inside the travel, so
        // the reversal stays within one ply's time.
        guard !policy.reduceMotion else { return }
        // The identity goes as the disc returns home, on the same schedule a
        // reveal arrives on.
        transits.raiseReveal(Motion.revealAnimation(travel: travel))
        transits.raiseFade(Motion.restoreFadeAnimation)
    }

    /// One stone put down or taken back, on either device.
    ///
    /// **Nothing travels, because nothing travelled to arrive.** A stone comes
    /// from off the board and goes back there, so there is no disc to carry and
    /// no committing transition to hold a gate for: the position changes over
    /// the ordinary state fade and the board is immediately the board again. It
    /// is the local board's own placement transition, in the one thing that
    /// differs here — the ply may be the other player's, and a stone the two
    /// players agreed to take back is drawn exactly as one going down is,
    /// because a retraction on this board is an Undo with a second person in it.
    ///
    /// The landing is the change, so the feedback fires with it rather than
    /// waiting for an arrival that never comes.
    private func place(_ plies: [String], _ standing: NearbyStanding, lastMove move: Move?) {
        markerEmphasis = 0
        animator.run(policy.fade(Motion.stateFadeAnimation)) { [self] in
            land(plies, standing, lastMove: move)
        } completion: { }
        announceLanding(stone: true)
    }

    /// The position, arrived at rather than travelled to. Nothing lands, so
    /// nothing sounds: a board catching up with a line it was away from is not a
    /// move being made.
    private func cut(to plies: [String]) {
        guard let standing = positions.standing(of: game, from: dealtStart, after: plies)
        else { return }
        transits.cut()
        animator.run(policy.fade(Motion.stateFadeAnimation)) { [self] in
            land(plies, standing,
                 lastMove: plies.last.flatMap { Move(text: $0, on: game.board) })
        } completion: { }
        pulseCheckIfNeeded()
    }

    // MARK: - Input

    /// A tap on a point. What it means is the board's question and is asked in
    /// one place for both boards; what is added here is the motion that carries
    /// it out.
    func tap(_ square: Square) {
        guard !isCommitting, !isFlipping else { return }
        // Reaching for the board on your own turn and finding it locked is the
        // moment the link stops being the app's business and starts being
        // yours, so the line that explains it does not wait out the stretch.
        if session.state == .active, session.isLocalTurn, !isLinked {
            reachedForABlockedBoard = true
        }
        // The board's whole grammar, asked in one place for both boards — the
        // optional pending-stone confirmation included. It is the board's own
        // rather than a mode's: a player who asked to confirm their stones asked
        // it of the board they place them on, and a nearby board is that board.
        switch Game.effect(ofTapAt: square, in: placement, legalMoves: legalMoves,
                           sideToMove: evaluation.sideToMove, selected: selected,
                           acceptsInput: acceptsInput,
                           confirmsPlacement: Preferences.placementConfirmation.value()) {
        case .cancelSelection: cancelSelection()
        case .play(let move): commit(move)
        case .select: select(square)
        case .illegal: answerIllegalTap()
        case .unavailable: acknowledge()
        }
    }

    func cancelSelection() {
        guard !isCommitting, selected != nil else { return }
        animator.run(policy.movement(Motion.liftAnimation)) { [self] in
            selected = nil
            markerEmphasis = 0
        } completion: { }
    }

    private func select(_ square: Square) {
        animator.run(policy.movement(Motion.liftAnimation)) { [self] in
            selected = square
            markerEmphasis = 0
        } completion: { }
    }

    /// This device's own ply: sent by the driver inside the transition that
    /// draws it, exactly as a local game commits inside its own.
    ///
    /// A ply the engine refuses did not happen, and nothing is drawn for it. The
    /// refusals reachable from here are all the same situation — the connection
    /// went away between the tap and the send — and the connection line already
    /// says so, quietly, which is the whole of what this stage's presentation
    /// owes an idle radio.
    private func commit(_ move: Move) {
        guard let standing = positions.standing(of: game, from: dealtStart,
                                                after: shown + [move.text])
        else { return }
        // **Whether this is a stone is one question, asked the one way**: a ply
        // with no origin, which is what the parser answers for a placement board
        // and never for a movement one. `sync` discriminates on exactly this, and
        // two sites answering it differently would be two answers to have.
        //
        // A stone of this device's player's own: the driver is asked first,
        // exactly as it is below, and a ply it refuses is a ply that did not
        // happen — nothing is sent and nothing is drawn.
        guard let origin = move.from else {
            guard (try? driver.play(move.text, in: sessionID)) != nil else { return }
            place(shown + [move.text], standing, lastMove: move)
            return
        }
        // A move whose origin carries nothing is not a move this board can draw,
        // and it is not a stone either.
        guard let piece = placement[origin] else { return }
        let captured = placement[move.to]
        // This device's own ply turns a face up on this device exactly as the
        // other device's does, and from the same source: the position the ply
        // produced, which the deal already held.
        let arrived = piece.isFaceDown
            ? Placement(fen: standing.evaluation.fen, game: game)[move.to] : nil
        let travel = Motion.travel(distance: Motion.distance(of: move), on: game.board)
        markerEmphasis = 0
        transits.run(policy.movement(Motion.travelAnimation(travel)),
                     drawingRemoval: captured != nil && !policy.reduceMotion) { [self] in
            guard (try? driver.play(move.text, in: sessionID)) != nil else { return nil }
            land(shown + [move.text], standing, lastMove: move)
            return Transit(kind: .move, move: move, piece: piece,
                           fading: captured.map { ($0, move.to) },
                           revealed: arrived)
        }
        if !policy.reduceMotion {
            transits.raiseReveal(Motion.revealAnimation(travel: travel))
        }
        guard transits.drawsRemoval else { return }
        transits.raiseFade(Motion.captureFadeAnimation(travel: travel))
    }

    /// 认输. The engine records the terminal and sends it; the result that
    /// follows is the session's, and it arrives here through the ordinary
    /// publication like every other change.
    func resign() {
        guard canResign else { return }
        try? driver.resign(in: sessionID)
    }

    /// Applied at once between transitions, deferred across none: this board
    /// runs one transition at a time and the flip is offered only between them.
    func flip() {
        guard !isCommitting else { return }
        flipGeneration += 1
        let token = flipGeneration
        isFlipping = true
        withAnimation(policy.movement(Motion.flipAnimation)) {
            flipped.toggle()
        } completion: { [self] in
            guard flipGeneration == token else { return }
            flipArrived()
        }
    }

    func flipArrived() {
        isFlipping = false
    }

    func travelArrived() { transits.travelArrived() }
    func fadeArrived() { transits.fadeArrived() }

    // MARK: - The link

    /// Starts or stops the stretch the quiet line waits out. A link that comes
    /// back takes the whole state with it: the count, the line, and the fact
    /// that anybody reached for a locked board.
    private func watchTheLink() {
        stretch?.cancel()
        stretch = nil
        guard !isLinked else {
            blockedLongEnough = false
            reachedForABlockedBoard = false
            return
        }
        guard !blockedLongEnough else { return }
        stretch = Task { [weak self] in
            try? await Task.sleep(for: Self.connectionStretch)
            guard !Task.isCancelled else { return }
            self?.blockedLongEnough = true
        }
    }

    /// The board is closing. The watch is this object's and goes with it.
    func close() {
        stretch?.cancel()
        stretch = nil
    }

    // MARK: - Landings, pulses and beats

    /// One position adopted: the plies the board is drawing, everything the core
    /// says about them, and the brackets on the move that produced it.
    private func land(_ plies: [String], _ standing: NearbyStanding, lastMove move: Move?) {
        take(plies, leaving: placement)
        shown = plies
        adopt(standing)
        lastMove = move
        selected = nil
    }

    /// What the arriving line took, kept up as the line moves.
    ///
    /// The same three cases the board itself draws, and in the same order: a ply
    /// added took whatever stood on its destination, a line that got shorter
    /// gives back what its retracted plies took, and anything else — a resend, a
    /// line that came back different after a reconnection — is the whole line
    /// read again. It is the local game's own bookkeeping over a session's plies
    /// instead of a store's: appended as a ply lands, dropped as a retraction
    /// lands, read whole where neither is what happened.
    ///
    /// The position it reads is the one the ply was played into, which is the
    /// board's own before it adopts the new one — a face-down victim's identity
    /// stands there, and that is what the capture disclosed to whoever made it.
    private func take(_ plies: [String], leaving before: Placement) {
        guard game.conceals else { return }
        if plies.count == shown.count + 1, plies.dropLast() == shown {
            guard let text = plies.last, let move = Move(text: text, on: game.board),
                  let capture = CapturedPieces.capture(atPly: shown.count, by: move,
                                                       in: before)
            else { return }
            captured.taken.append(capture)
            return
        }
        if plies.count < shown.count, shown.starts(with: plies) {
            captured.removePlies(from: plies.count)
            return
        }
        captured = Self.captures(of: game, from: dealtStart, after: plies, positions)
    }

    /// A whole line read back: what every ply of it took.
    ///
    /// Walked over the positions the core replays, exactly as the local game's
    /// stored line and a record's replay are walked, so a nearby board and the
    /// record it becomes answer with one surface. It is asked only of a game
    /// that conceals — every other displays nothing, and the walk is what that
    /// costs.
    ///
    /// **A claim takes nothing**: it moves no piece and can only be a line's
    /// last ply, so the walk stops where the core's own replay of the line
    /// stops. A line this board cannot read fails whole rather than partly, and
    /// answers with an empty surface: one missing a capture would be a surface
    /// quietly saying something else about the game.
    private static func captures(of game: GameKind, from start: String?,
                                 after plies: [String],
                                 _ positions: any NearbyPositions) -> CapturedPieces {
        guard game.conceals else { return CapturedPieces() }
        let played = Array(plies.prefix { $0 != TurnAction.claim })
        let read = try? CapturedPieces.line(for: played, on: game) { ply in
            guard let standing = positions.standing(of: game, from: start,
                                                    after: Array(played.prefix(ply)))
            else { throw UnreplayableLine(ply: ply) }
            return Placement(fen: standing.evaluation.fen, game: game)
        }
        return read ?? CapturedPieces()
    }

    /// A position the core would not replay, which the walk above cannot go on
    /// without. It is a bug above the core rather than a state to design for:
    /// the engine holds only plies its own oracle accepted.
    private struct UnreplayableLine: Error {
        var ply: Int
    }

    private func adopt(_ standing: NearbyStanding) {
        evaluation = standing.evaluation
        placement = Placement(fen: standing.evaluation.fen, game: game)
        legalMoves = standing.legalMoves.compactMap { Move(text: $0, on: game.board) }
    }

    /// The disc has met the board — or the stone has. One sound per landing,
    /// chosen by what the arrived position means, through the same seam play and
    /// replay use; `stone` is the one thing the arrival itself has to say, since
    /// a placed stone reaches its point with no transit to read it off.
    private func announceLanding(stone: Bool = false) {
        feedback.perform(.landing)
        feedback.play(.ofTheLanding(transit, stone: stone,
                                    finished: end != nil || evaluation.isOver,
                                    inCheck: checkedGeneral != nil))
        soundedConclusion = soundedConclusion || end != nil || evaluation.isOver
    }

    /// A result that arrived with nothing moving — a resignation on either
    /// device — sounds at the moment the game ends, which is the same rule the
    /// claimed draw follows during play.
    private func soundConclusionIfNeeded() {
        guard !soundedConclusion, !transits.isRunning else { return }
        soundedConclusion = true
        feedback.play(.conclusion)
    }

    private func pulseCheckIfNeeded() {
        guard checkedGeneral != nil,
              let rise = policy.pulse(.easeOut(duration: Motion.checkPulseRise)) else { return }
        withAnimation(rise) {
            checkEmphasis = 1
        } completion: { [self] in
            withAnimation(.easeInOut(duration: Motion.checkPulseFall)) {
                checkEmphasis = 0
            }
        }
    }

    /// The illegal-tap answer: no board mark, the legal destinations strengthen,
    /// and the lightest feedback answers the touch.
    private func answerIllegalTap() {
        feedback.perform(.acknowledgement)
        guard let rise = policy.pulse(.easeOut(duration: Motion.markerPulseRise)) else {
            markerEmphasis = 1
            return
        }
        withAnimation(rise) {
            markerEmphasis = 1
        } completion: { [self] in
            withAnimation(.easeInOut(duration: Motion.markerPulseFall)) {
                markerEmphasis = 0
            }
        }
    }

    /// The acknowledgment beat, for input the game cannot accept — which on this
    /// board is most often the other player's turn, and the status line above it
    /// is already saying so.
    private func acknowledge() {
        feedback.perform(.acknowledgement)
        withAnimation(policy.fade(.easeOut(duration: Motion.beatRise))) {
            beatEmphasis = 1
        } completion: { [self] in
            withAnimation(policy.fade(.easeInOut(duration: Motion.beatFall))) {
                beatEmphasis = 0
            }
        }
    }
}
