// A nearby game as its board shows it: the position the session's plies
// produce, the transitions between them, and the one ply this device may add.
//
// It is the third consumer of the shared motion language, beside play and
// replay, and it takes exactly what they take: TransitMotion for the travelling
// disc, Motion for every duration, Feedback for what is heard and felt. Nothing
// about a disc crossing a board is decided here — a nearby move is a move, and a
// second copy of that would be a second thing to keep right.
//
// What is only true of a nearby board is the rest of this file. **A ply travels;
// anything else cuts** — the rule replay already states, and the honest one
// here: an opponent's move arrives as one ply and is shown travelling, while a
// reconnection that truncates or resends a line is a change of position rather
// than a move, and nobody wants to watch it replayed. **The turn is the
// protocol's**: the board accepts a tap only while the session is in play and
// the ply is this device's, so a connection that has idled out between moves
// locks the board quietly until the driver has it back.
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

    /// The protocol names movers and the app names colours. Red is the first
    /// mover in both games, by the rules contract's own starting positions,
    /// which is the same sentence the rules oracle makes on its side.
    init(_ end: BoardGameEnd) {
        state = switch end.result {
        case .moverWins(.first): .redWins
        case .moverWins(.second): .blackWins
        case .draw: .draw
        }
        reason = switch end.ending {
        case .rulesDecided(let reason): reason
        case .resignation, .bothResigned: .resignation
        // An agreed draw is the one ending the app has no word for yet: the
        // draw-offer surface, and the word that goes with it, are the next
        // slice's. The result itself is unaffected — a draw is a draw — and the
        // reason line is simply absent, exactly as it is for any result the core
        // reports no reason for.
        case .agreedDraw: .none
        }
    }
}

@MainActor
@Observable
final class NearbyPlay {
    let sessionID: String
    let game: GameKind

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

    init?(session: BoardGameSession,
          driver: any NearbyDriving,
          positions: any NearbyPositions,
          policy: MotionPolicy = MotionPolicy(reduceMotion: false),
          animator: MotionAnimator = .live,
          feedback: Feedback = .live) {
        guard let game = GameKind(rulesID: session.rulesID),
              let standing = positions.standing(of: game, after: session.plies)
        else { return nil }

        self.sessionID = session.id
        self.game = game
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
        // playing: your own pieces are at the bottom, and Red at the bottom is
        // the unflipped board. Where it starts and not where it must stay — the
        // flip control turns it over.
        self.flipped = session.localMover == .second
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
    var isCommitting: Bool { transits.isRunning }

    var destinations: Set<Square> {
        guard let selected else { return [] }
        return Set(legalMoves.filter { $0.from == selected }.map(\.to))
    }

    var captures: Set<Square> {
        Set(destinations.filter { placement[$0] != nil })
    }

    var checkedGeneral: Square? {
        guard evaluation.inCheck, end == nil else { return nil }
        return placement.general(of: evaluation.sideToMove)
    }

    /// How the game ended, if it has. The session's answer and never the
    /// position's alone: a resignation is an outcome no position produces.
    var end: NearbyEnd? { session.end.map(NearbyEnd.init) }

    /// Who owns the turn — this device's player, or the other one. It is the
    /// protocol's answer, from the mover this device holds and the ply parity,
    /// rather than anything derived from the board.
    var controller: TurnStatus.Controller { session.isLocalTurn ? .you : .peer }

    /// Whether the board takes a tap: the game is on, the session is bound and
    /// exchanged, and the ply is this device's.
    var acceptsInput: Bool {
        session.isInPlay && session.isLocalTurn && end == nil
    }

    /// Whether 认输 is on offer. The engine's own law, read rather than
    /// re-derived: a resignation is valid from either peer at any point of an
    /// active session, and one made while the link is down is held and rides the
    /// next resume rather than being refused.
    var canResign: Bool { session.state == .active }

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
        guard !isLinked else { return false }
        // A terminal this device took while there was nowhere to send it. The
        // engine holds it and it rides the next resume, which is the one thing
        // the player has done that has demonstrably not reached the other
        // device. A settlement still owed is *not* that: it is the protocol's
        // own bookkeeping over a game whose moves all arrived.
        if session.localTerminal != nil { return true }
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

    /// The engine published. One added ply travels; anything else — a
    /// truncation, a resend, a line that came back different after a
    /// reconnection — arrives as the position it is.
    func sync(with session: BoardGameSession) {
        let ended = self.session.end == nil && session.end != nil
        let wasLinked = isLinked
        self.session = session
        if isLinked != wasLinked { watchTheLink() }
        defer { if ended { soundConclusionIfNeeded() } }

        guard session.plies != shown else { return }
        guard !transits.isRunning,
              session.plies.count == shown.count + 1,
              session.plies.dropLast() == shown,
              let text = session.plies.last,
              let move = Move(text: text, on: game.board),
              let piece = placement[move.from],
              let standing = positions.standing(of: game, after: session.plies)
        else {
            cut(to: session.plies)
            return
        }

        let captured = placement[move.to]
        let travel = Motion.travel(distance: Motion.distance(of: move), on: game.board)
        transits.run(policy.movement(Motion.travelAnimation(travel)),
                     drawingRemoval: captured != nil && !policy.reduceMotion) { [self] in
            land(session.plies, standing, lastMove: move)
            return Transit(kind: .move, move: move, piece: piece,
                           fading: captured.map { ($0, move.to) })
        }
        guard transits.drawsRemoval else { return }
        transits.raiseFade(Motion.captureFadeAnimation(travel: travel))
    }

    /// The position, arrived at rather than travelled to. Nothing lands, so
    /// nothing sounds: a board catching up with a line it was away from is not a
    /// move being made.
    private func cut(to plies: [String]) {
        guard let standing = positions.standing(of: game, after: plies) else { return }
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
        switch Game.effect(ofTapAt: square, in: placement, legalMoves: legalMoves,
                           sideToMove: evaluation.sideToMove, selected: selected,
                           acceptsInput: acceptsInput) {
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
        guard let piece = placement[move.from],
              let standing = positions.standing(of: game, after: shown + [move.text])
        else { return }
        let captured = placement[move.to]
        let travel = Motion.travel(distance: Motion.distance(of: move), on: game.board)
        markerEmphasis = 0
        transits.run(policy.movement(Motion.travelAnimation(travel)),
                     drawingRemoval: captured != nil && !policy.reduceMotion) { [self] in
            guard (try? driver.play(move.text, in: sessionID)) != nil else { return nil }
            land(shown + [move.text], standing, lastMove: move)
            return Transit(kind: .move, move: move, piece: piece,
                           fading: captured.map { ($0, move.to) })
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
        shown = plies
        adopt(standing)
        lastMove = move
        selected = nil
    }

    private func adopt(_ standing: NearbyStanding) {
        evaluation = standing.evaluation
        placement = Placement(fen: standing.evaluation.fen, game: game)
        legalMoves = standing.legalMoves.compactMap { Move(text: $0, on: game.board) }
    }

    /// The disc has met the board. One sound per landing, chosen by what the
    /// arrived position means, through the same seam play and replay use.
    private func announceLanding() {
        feedback.perform(.landing)
        feedback.play(.ofTheLanding(transit,
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
