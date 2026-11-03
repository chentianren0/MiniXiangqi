// A networked game as its board shows it: the position the game's moves
// produce, the transitions between them, and the one move this device may add.
//
// It takes the shared motion language exactly as play and replay do. A move
// travels, a move taken back reverses, anything else cuts: a resume that
// brings a different line is a change of position rather than a move. The
// turn, the offers and the claim are the engine's, read off the game it
// publishes.

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class NearbyPlay {
    let gameID: UUID
    let game: GameKind
    /// Where the moves are replayed from: the frozen start, or the deal.
    private let start: String

    private let engine: PeerEngine
    private let positions: any NearbyPositions
    /// What a link that has gone means here, which decides both when the one
    /// quiet line appears and what it says.
    private let interruption: LinkInterruption
    private let transits: TransitMotion
    private let animator: MotionAnimator
    private let feedback: Feedback

    /// Counts the board screen triggers its haptics on: every landing, and
    /// every touch the game could not act on.
    private(set) var landings = 0
    private(set) var refusals = 0

    var policy: MotionPolicy

    /// The game as the engine last published it: whose turn it is, whether the
    /// devices are in touch, and how it ended.
    private(set) var current: PeerGame

    /// The moves the board is drawing, which trail the game's own by exactly
    /// the length of a transition.
    private(set) var shown: [String]

    private(set) var placement: Placement
    private(set) var legalMoves: [Move] = []
    private(set) var lastMove: Move?
    /// What the drawn line has captured, kept in Jieqi alone, where a capture
    /// discloses a hidden piece; empty in every other game.
    private(set) var captured = CapturedPieces()
    private(set) var evaluation: Evaluation

    var selected: Square?
    private(set) var flipped: Bool

    private(set) var checkEmphasis: Double = 0
    private(set) var markerEmphasis: Double = 0
    private(set) var beatEmphasis: Double = 0

    /// Whether the board is turning round. Input waits for it, because the tap
    /// targets stand where the board is turning to while the canvas is still
    /// part way round.
    private(set) var isFlipping = false
    private var flipGeneration = 0

    /// Whether the conclusion has been sounded. A result that arrives with no
    /// piece moving, such as a resignation, has no landing to sound at.
    private var soundedConclusion = false

    /// - Parameter flipped: which way round the player last turned the board,
    ///   if they did.
    init?(game current: PeerGame,
          engine: PeerEngine,
          positions: any NearbyPositions,
          interruption: LinkInterruption,
          flipped: Bool? = nil,
          policy: MotionPolicy = MotionPolicy(reduceMotion: false),
          animator: MotionAnimator = .live,
          feedback: Feedback = .live) {
        let game = current.kind
        guard let standing = positions.standing(of: game, from: current.start,
                                                after: current.moves)
        else { return nil }

        self.gameID = current.id
        self.game = game
        self.start = current.start
        self.current = current
        self.engine = engine
        self.positions = positions
        self.interruption = interruption
        self.policy = policy
        self.feedback = feedback
        self.animator = animator
        self.transits = TransitMotion(animator: animator)
        self.shown = current.moves
        self.evaluation = standing.evaluation
        self.placement = Placement(fen: standing.evaluation.fen, game: game)
        // Your own pieces at the bottom, until the player turns the board. A
        // placement board has no orientation.
        self.flipped = game.isPlacement ? false : (flipped ?? (current.localSide == .black))
        self.captured = Self.captures(of: game, from: current.start,
                                      after: current.moves, positions)
        adopt(standing)
        self.lastMove = shown.last.flatMap { Move(text: $0, on: game.board) }
        soundedConclusion = current.isOver
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

    /// Every hidden identity is disclosed when the game ends, however it ends.
    var disclosesTheDeal: Bool { game.conceals && isOver }

    var destinations: Set<Square> {
        guard let selected else { return [] }
        return Set(legalMoves.filter { $0.from == selected }.map(\.to))
    }

    var captures: Set<Square> {
        Set(destinations.filter { placement[$0] != nil })
    }

    /// Renju's forbidden points while Black is to move. A finished position has
    /// no legal moves, so it is over here as soon as the position says so.
    var forbiddenPoints: Set<Square> {
        Game.forbiddenPoints(of: game, in: placement, legalMoves: legalMoves,
                             sideToMove: evaluation.sideToMove,
                             isOver: isOver || evaluation.isOver)
    }

    var checkedGeneral: Square? {
        guard evaluation.inCheck, current.outcome == nil else { return nil }
        return placement.general(of: evaluation.sideToMove)
    }

    var voided: NearbyVoid? { current.voided }

    /// A result, or a game that went away without one.
    var isOver: Bool { current.isOver }

    /// The result, as the status element and the notice name it.
    var endState: GameState? {
        switch current.outcome {
        case .redWins: .redWins
        case .blackWins: .blackWins
        case .draw: .draw
        case .none?, nil: nil
        }
    }

    /// A finished game's result; otherwise the position, with the claim
    /// standing only where the engine says this player may make it.
    var statusState: GameState {
        if let endState { return endState }
        guard evaluation.state == .claimableDraw else { return evaluation.state }
        return claimStands ? .claimableDraw : .ongoing
    }

    var reasonText: String? { current.reason?.text }

    var controller: TurnStatus.Controller { current.localTurn ? .you : .peer }

    /// Whose eyes the captured surface is drawn for.
    var localSide: Side { current.localSide }

    var acceptsInput: Bool { current.inPlay && current.localTurn }

    /// Resigning is open while the game goes on, connected or not.
    var canResign: Bool { !isOver }

    // MARK: - The offers

    var canOfferDraw: Bool {
        current.inPlay && !current.localTurn && current.offer == nil
    }

    var canRequestUndo: Bool { canOfferDraw && !current.moves.isEmpty }

    /// What the other player has offered, if anything stands.
    var standingOffer: PeerOffer.Kind? {
        guard current.inPlay, let offer = current.offer, offer.fromPeer else { return nil }
        return offer.kind
    }

    var claimStands: Bool { current.claimable }

    func offerDraw() {
        engine.offer(.draw)
    }

    func requestUndo() {
        engine.offer(.takeback)
    }

    func accept() {
        engine.acceptOffer()
    }

    func claimDraw() {
        engine.claimDraw()
    }

    /// Whether to say anything about the connection. Nothing in ordinary play;
    /// one quiet line where the link is costing the player something: an
    /// ending of theirs has not arrived, the link will not come back by itself,
    /// or their own turn has waited long enough to need explaining.
    var isWaitingOnConnection: Bool {
        guard voided == nil, !isLinked else { return false }
        if current.undelivered { return true }
        guard current.outcome == nil else { return false }
        switch interruption {
        case .lasting: return true
        case .passing: return current.localTurn && blocked
        }
    }

    var interruptionKey: String { interruption.messageKey }

    private var isLinked: Bool { current.linked }

    /// The player's own turn has been blocked past the stretch, or they reached
    /// for the board and found it locked.
    private var blocked: Bool { blockedLongEnough || reachedForABlockedBoard }

    private var blockedLongEnough = false
    private var reachedForABlockedBoard = false
    private var stretch: Task<Void, Never>?

    /// Well past a reconnection, so nothing routine reaches it.
    private static let connectionStretch = Duration.seconds(20)

    // MARK: - The game moving underneath

    /// The engine published. One added move travels and one taken back
    /// reverses; anything else arrives as the position it is.
    func sync(with game: PeerGame) {
        let ended = !current.isOver && game.isOver
        let wasLinked = isLinked
        current = game
        if isLinked != wasLinked { watchTheLink() }
        if ended {
            selected = nil
            soundConclusionIfNeeded()
        }
        let plies = game.moves

        guard plies != shown else { return }
        guard !transits.isRunning,
              let standing = positions.standing(of: self.game, from: start, after: plies)
        else {
            cut(to: plies)
            return
        }

        if plies.count == shown.count + 1, plies.dropLast() == shown,
           let text = plies.last, let move = Move(text: text, on: self.game.board) {
            // A ply with no origin is a stone, which came from off the board and
            // has nothing to cross it: it appears on its point with the
            // position, which is what a placed stone does.
            guard let origin = move.from else {
                return place(plies, standing, lastMove: move)
            }
            if let piece = placement[origin] {
                return advance(move, piece, to: plies, standing)
            }
        }
        if shown.count == plies.count + 1, shown.dropLast() == plies,
           let text = shown.last, let move = Move(text: text, on: self.game.board) {
            // And a stone taken back goes back off the board rather than home,
            // so the same nothing travels.
            guard move.from != nil else {
                return place(plies, standing,
                             lastMove: plies.last
                                 .flatMap { Move(text: $0, on: self.game.board) })
            }
            if let mover = placement[move.to] {
                return reverse(move, mover, to: plies, standing)
            }
        }
        cut(to: plies)
    }

    /// A ply arriving, shown crossing the board.
    private func advance(_ move: Move, _ piece: Piece, to plies: [String],
                         _ standing: NearbyStanding) {
        let captured = placement[move.to]
        // What the ply turned up, read off the position it produced: the deal
        // is on this device already, and nothing about the identity travels
        // with the move.
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

    /// One ply taken back, drawn as the local board's Undo draws one: the mover
    /// travels home and whatever it took reappears as it goes.
    private func reverse(_ move: Move, _ mover: Piece, to plies: [String],
                         _ standing: NearbyStanding) {
        guard let origin = move.from else { return }
        let before = Placement(fen: standing.evaluation.fen, game: game)
        let restored = before[move.to]
        // A takeback conceals again: a piece the ply revealed goes home face
        // down.
        let returned = before[origin].flatMap { $0.isFaceDown ? $0 : nil }
        let travel = Motion.travel(distance: Motion.distance(of: move), on: game.board)
        transits.run(policy.movement(Motion.travelAnimation(travel))) { [self] in
            land(plies, standing,
                 lastMove: plies.last.flatMap { Move(text: $0, on: game.board) })
            return Transit(kind: .undo, move: Move(from: move.to, to: origin),
                           piece: mover, fading: restored.map { ($0, move.to) },
                           revealed: returned)
        }
        guard !policy.reduceMotion else { return }
        transits.raiseReveal(Motion.revealAnimation(travel: travel))
        transits.raiseFade(Motion.restoreFadeAnimation)
    }

    /// One stone put down or taken back, on either device. Nothing travels, so
    /// the position changes over the state fade and the feedback fires at once.
    private func place(_ plies: [String], _ standing: NearbyStanding, lastMove move: Move?) {
        markerEmphasis = 0
        animator.run(policy.fade(Motion.stateFadeAnimation)) { [self] in
            land(plies, standing, lastMove: move)
        } completion: { }
        announceLanding(stone: true)
    }

    /// The position, arrived at rather than travelled to. Nothing lands, so
    /// nothing sounds.
    private func cut(to plies: [String]) {
        guard let standing = positions.standing(of: game, from: start, after: plies)
        else { return }
        transits.cut()
        animator.run(policy.fade(Motion.stateFadeAnimation)) { [self] in
            land(plies, standing,
                 lastMove: plies.last.flatMap { Move(text: $0, on: game.board) })
        } completion: { }
        pulseCheckIfNeeded()
    }

    // MARK: - Input

    func tap(_ square: Square) {
        guard !isCommitting, !isFlipping else { return }
        // A player who reaches for a board locked by the link on their own
        // turn sees the connection line at once, without waiting out the
        // stretch.
        if !isOver, current.localTurn, !isLinked {
            reachedForABlockedBoard = true
        }
        // Confirm Before Placing applies here as on the local board.
        switch Game.effect(ofTapAt: square, in: placement, legalMoves: legalMoves,
                           sideToMove: evaluation.sideToMove, selected: selected,
                           acceptsInput: acceptsInput,
                           confirmsPlacement: UserDefaults.standard.bool(forKey: "placementConfirmation.enabled")) {
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

    /// This device's own move, sent by the engine inside the transition that
    /// draws it. A move the engine refuses is not drawn: from here that is the
    /// connection going away between the tap and the send, which the
    /// connection line already says.
    private func commit(_ move: Move) {
        guard let standing = positions.standing(of: game, from: start,
                                                after: shown + [move.text])
        else { return }
        // A stone, as `sync` tells one: a ply with no origin.
        guard let origin = move.from else {
            guard engine.play(move.text) else { return }
            place(shown + [move.text], standing, lastMove: move)
            return
        }
        guard let piece = placement[origin] else { return }
        let captured = placement[move.to]
        let arrived = piece.isFaceDown
            ? Placement(fen: standing.evaluation.fen, game: game)[move.to] : nil
        let travel = Motion.travel(distance: Motion.distance(of: move), on: game.board)
        markerEmphasis = 0
        transits.run(policy.movement(Motion.travelAnimation(travel)),
                     drawingRemoval: captured != nil && !policy.reduceMotion) { [self] in
            guard engine.play(move.text) else { return nil }
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

    /// The result arrives through the engine's publication like every other
    /// change.
    func resign() {
        guard canResign else { return }
        engine.resign()
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
        // A link that is not coming back has nothing to wait out: the line is
        // already up.
        guard interruption == .passing, !blockedLongEnough else { return }
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

    /// What the arriving line took: a ply added took what stood on its
    /// destination in the position before it, where a face-down victim's
    /// identity stands; a shorter line gives back what its retracted plies
    /// took; any other line is read again whole.
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
        captured = Self.captures(of: game, from: start, after: plies, positions)
    }

    /// What every ply of a whole line took. A line the core will not replay
    /// answers with nothing rather than with a surface missing a capture.
    private static func captures(of game: GameKind, from start: String,
                                 after plies: [String],
                                 _ positions: any NearbyPositions) -> CapturedPieces {
        guard game.conceals else { return CapturedPieces() }
        let played = plies
        let read = try? CapturedPieces.line(for: played, on: game) { ply in
            guard let standing = positions.standing(of: game, from: start,
                                                    after: Array(played.prefix(ply)))
            else { throw UnreplayableLine(ply: ply) }
            return Placement(fen: standing.evaluation.fen, game: game)
        }
        return read ?? CapturedPieces()
    }

    /// A position the core would not replay. The engine holds only moves the
    /// core accepted, so this is a bug rather than a state to design for.
    private struct UnreplayableLine: Error {
        var ply: Int
    }

    private func adopt(_ standing: NearbyStanding) {
        evaluation = standing.evaluation
        placement = Placement(fen: standing.evaluation.fen, game: game)
        legalMoves = standing.legalMoves.compactMap { Move(text: $0, on: game.board) }
    }

    /// One sound per landing, chosen by what the arrived position means.
    /// `stone` says what a placed stone cannot: it arrives with no transit.
    private func announceLanding(stone: Bool = false) {
        landings += 1
        feedback.play(.ofTheLanding(transit, stone: stone,
                                    finished: current.outcome != nil || evaluation.isOver,
                                    inCheck: checkedGeneral != nil))
        soundedConclusion = soundedConclusion || current.outcome != nil || evaluation.isOver
    }

    /// A result that arrived with nothing moving sounds when the game ends.
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
        refusals += 1
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

    /// The acknowledgment beat, for input the game cannot accept.
    private func acknowledge() {
        refusals += 1
        withAnimation(policy.fade(.easeOut(duration: Motion.beatRise))) {
            beatEmphasis = 1
        } completion: { [self] in
            withAnimation(policy.fade(.easeInOut(duration: Motion.beatFall))) {
                beatEmphasis = 0
            }
        }
    }
}
