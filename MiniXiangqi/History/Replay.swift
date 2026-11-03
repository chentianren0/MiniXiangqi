// Every position is the core's replay of the record's moves, asked once when
// the replay opens, so there is no second copy of the game to drift. Steps are
// shown through the same TransitMotion and Feedback play uses, but with no
// committing gate: a step arriving during a step re-targets rather than waits.

import Foundation
import Observation

nonisolated struct ReplayPosition: Sendable {
    var fen: String
    var sideToMove: Side
    var inCheck: Bool
}

@Observable
final class Replay {
    let record: GameRecord
    let game: GameKind

    /// Read through the same `MoveReading` a resumed game uses, in both
    /// notations, so 记谱法 selects a replayed game's words as it does a live one's.
    let moves: [String]
    let notation: [MoveReading]

    /// A record is a game already over, so every captured piece is shown
    /// disclosed; what the walk shows at a ply is what had been taken by then.
    let captured: CapturedPieces

    /// How many plies are shown: 0 is the initial position, `moves.count` the
    /// final one.
    private(set) var ply = 0

    /// A record from a composed position may open with Black, so the move list
    /// pairs and numbers from this rather than from parity.
    let firstMover: Side

    private(set) var position: ReplayPosition
    private(set) var placement: Placement

    var flipped: Bool {
        didSet { if flipped != oldValue { pause() } }
    }

    /// A placement board has none: a stone carries nothing a player could read
    /// the wrong way up.
    var carriesFlip: Bool { !game.isPlacement }

    private(set) var autoplaying = false
    private var playback: Task<Void, Never>?

    /// Held rather than derived: the screen reads the environment, this runs the
    /// animations. The screen keeps it current.
    var policy: MotionPolicy

    private let transits: TransitMotion
    private let feedback: Feedback

    /// The count the replay screen triggers its landing haptic on.
    private(set) var landings = 0

    /// Every position of the record, the start first.
    private let positions: [ReplayPosition]

    /// How long an arrived position stands still before the next ply departs.
    /// Measured from the landing, not the departure, so the walk never asks for
    /// a ply while the last one is still travelling.
    private static let settle = Duration.milliseconds(600)

    static func interval(afterTravelling travel: TimeInterval) -> Duration {
        .seconds(travel) + settle
    }

    init(record: GameRecord,
         core: Core,
         policy: MotionPolicy = MotionPolicy(reduceMotion: false),
         animator: MotionAnimator = .live,
         feedback: Feedback = .live) throws {
        let game = record.kind
        let moves = record.moves
        let start = record.start
        let positions = try (0...moves.count).map { ply in
            let evaluation = try core.evaluate(game, from: start, moves: Array(moves.prefix(ply)))
            return ReplayPosition(fen: evaluation.fen, sideToMove: evaluation.sideToMove,
                                  inCheck: evaluation.inCheck)
        }
        self.record = record
        self.game = game
        self.positions = positions
        self.policy = policy
        self.feedback = feedback
        self.transits = TransitMotion(animator: animator)
        self.moves = moves
        self.notation = try MoveReading.line(for: moves, on: game) {
            Placement(fen: positions[$0].fen, game: game)
        }
        self.captured = try CapturedPieces.line(for: moves, on: game) {
            Placement(fen: positions[$0].fen, game: game)
        }
        self.position = positions[0]
        self.placement = Placement(fen: positions[0].fen, game: game)
        self.firstMover = positions[0].sideToMove
        self.flipped = !game.isPlacement && record.humanSide == .black
        // Unowned: the transit belongs to this object and cannot outlive it.
        transits.arrived = { [unowned self] in announceLanding() }
    }

    // MARK: - What the board shows

    /// The move that produced the position on screen.
    var lastMove: Move? {
        ply > 0 ? Move(text: moves[ply - 1], on: game.board) : nil
    }

    /// In replay no piece is ever held and there is no status line, so the
    /// rings alone carry check.
    var checkedGeneral: Square? {
        guard position.inCheck else { return nil }
        return placement.general(of: position.sideToMove)
    }

    var transit: Transit? { transits.transit }
    var transitFade: Double { transits.fade }
    var transitReveal: Double { transits.reveal }

    var isAtStart: Bool { ply == 0 }
    var isAtEnd: Bool { ply == moves.count }

    /// Whether the game concluded here is the record's own result. A game ended
    /// early has none, so its last ply is a landing like any other.
    var isFinalPosition: Bool { isAtEnd && (record.result ?? .none) != .none }

    /// The ending discloses, so only a concluded record's last position shows
    /// the deal; every earlier ply keeps the concealment the players had then.
    /// The captured surface does not ask this: it is disclosed throughout.
    var disclosesTheDeal: Bool { game.conceals && isFinalPosition }

    // MARK: - The transport

    func goToStart() {
        pause()
        show(ply: 0)
    }

    func stepBack() {
        pause()
        show(ply: ply - 1)
    }

    func stepForward() {
        pause()
        show(ply: ply + 1)
    }

    func goToEnd() {
        pause()
        show(ply: moves.count)
    }

    func show(move ply: Int) {
        pause()
        show(ply: ply)
    }

    func toggleAutoplay() {
        if autoplaying {
            pause()
        } else {
            play()
        }
    }

    /// A step already travelling still lands: pausing declines the next ply, it
    /// does not snatch back the last.
    func pause() {
        playback?.cancel()
        playback = nil
        autoplaying = false
    }

    private func play() {
        guard !isAtEnd else { return }
        autoplaying = true
        playback = Task { [weak self] in
            // Nothing is travelling before the first ply, so the first wait is
            // the settle alone.
            var travel: TimeInterval = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval(afterTravelling: travel))
                guard !Task.isCancelled, let self, self.autoplaying else { return }
                travel = self.show(ply: self.ply + 1)
                if self.isAtEnd { return self.pause() }
            }
        }
    }

    /// Out-of-range is clamped, since the screen already disables the controls
    /// at the bounds. Returns how long the step takes to arrive, which autoplay
    /// waits out.
    ///
    /// One ply travels; a jump cuts, because nobody asking for the twentieth
    /// position wants to watch nineteen moves go past. A step arriving while one
    /// travels cuts it rather than queuing: the abandoned disc neither lands,
    /// sounds nor leaves a mark.
    @discardableResult
    private func show(ply target: Int) -> TimeInterval {
        let target = min(max(target, 0), moves.count)
        guard target != ply else { return 0 }
        let forward = target > ply
        guard abs(target - ply) == 1, !transits.isRunning,
              let played = Move(text: moves[min(ply, target)], on: game.board),
              // A placement has no origin and nothing travels, so it walks
              // like a jump.
              let origin = played.from,
              // The mover, read from the position it is leaving: forward it
              // stands at the move's origin, backward at its destination.
              let mover = placement[forward ? origin : played.to]
        else {
            transits.cut()
            walk(to: target)
            return 0
        }

        let victim = forward ? placement[played.to] : nil
        let travel = Motion.travel(distance: Motion.distance(of: played),
                                   on: game.board)
        transits.run(policy.movement(Motion.travelAnimation(travel)),
                     drawingRemoval: victim != nil && !policy.reduceMotion) { [self] in
            guard walk(to: target) else { return nil }
            // Read off the position walked to. Stepping back through a reveal
            // puts the piece face down again.
            let landing = placement[forward ? played.to : origin]
            let arrived = landing.flatMap {
                $0.isFaceDown == mover.isFaceDown ? nil : $0
            }
            return forward
                ? Transit(kind: .move, move: played, piece: mover,
                          fading: victim.map { ($0, played.to) },
                          revealed: arrived)
                // A step back is drawn as play draws an Undo.
                : Transit(kind: .undo,
                          move: Move(from: played.to, to: origin),
                          piece: mover,
                          fading: placement[played.to].map { ($0, played.to) },
                          revealed: arrived)
        }
        // Under Reduce Motion the canvas takes the reveal from the dissolve's
        // own progress.
        if !policy.reduceMotion {
            transits.raiseReveal(Motion.revealAnimation(travel: travel))
        }
        if transits.drawsRemoval {
            transits.raiseFade(Motion.captureFadeAnimation(travel: travel))
        } else if !forward, !policy.reduceMotion {
            transits.raiseFade(Motion.restoreFadeAnimation)
        }
        return policy.reduceMotion ? Motion.crossfade : travel
    }

    /// False, with nothing changed, where there is no such ply.
    @discardableResult
    private func walk(to target: Int) -> Bool {
        guard positions.indices.contains(target) else { return false }
        ply = target
        position = positions[target]
        placement = Placement(fen: position.fen, game: game)
        return true
    }

    // MARK: - Landings

    /// One sound and haptic per landing, chosen by what the arrived position
    /// means, by the same rule and **sound.enabled** gate as play's landings.
    private func announceLanding() {
        landings += 1
        feedback.play(.ofTheLanding(transit,
                                    finished: isFinalPosition,
                                    inCheck: position.inCheck))
    }

    /// See ArrivalReporter for why the transaction completion alone cannot be
    /// trusted with either.
    func travelArrived() { transits.travelArrived() }
    func fadeArrived() { transits.fadeArrived() }

    // MARK: - Lifetime

    func close() {
        pause()
        transits.cut()
    }
}
