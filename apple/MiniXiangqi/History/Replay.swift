// A History record, walked.
//
// docs/interaction-design.md, "History replay": replay begins at the game's
// initial position, the board is read-only, and the controls provide jump to
// beginning, one move back, play or pause, one move forward, and jump to end.
//
// The walk is the core's. Nothing here applies a move or maintains a position:
// every ply asks `mxq_game_position_at` what the position *was*, on a detached
// read-only session that refuses mutation by construction. So there is no
// second copy of the game to drift from the recorded one, and no rule above the
// interface deciding what a replayed board may do.
//
// A step is *shown* the way play shows a move — the same distance-scaled
// travel, the same disc giving way to a capture, the same landing sounding
// what the arrived position means — through the same TransitMotion and the
// same Feedback play uses. A replayed game should move like a game. What
// replay does not take from play is the committing gate: there is nothing here
// to commit, so a step arriving during a step re-targets rather than waits.

import Foundation
import Observation

@Observable
final class Replay {
    let record: RecordSummary

    /// The recorded line in canonical notation, and the same line as the player
    /// reads it — recomputed exactly as a resumed active game's is, through the
    /// one reading in `MoveReading`, in both notations, so that the 记谱法
    /// preference selects a replayed game's words exactly as it selects a live
    /// game's.
    let moves: [String]
    let notation: [MoveReading]

    /// How many plies are shown: 0 is the initial position, `moves.count` the
    /// final one.
    private(set) var ply = 0

    private(set) var position: ReplayPosition
    private(set) var placement: Placement

    /// Presentation only, exactly as it is during play. Human-versus-AI replay
    /// opens on the original human player's side; Free Play opens Red at the
    /// bottom.
    var flipped: Bool {
        didSet { if flipped != oldValue { pause() } }
    }

    private(set) var autoplaying = false
    private var playback: Task<Void, Never>?

    /// Reduce Motion, held rather than derived, because the screen owns the
    /// environment and this owns the animations. The screen keeps it current.
    var policy: MotionPolicy

    /// The travelling disc — the same one the play screen shows, drawn by the
    /// same canvas from the same state.
    private let transits: TransitMotion
    private let feedback: Feedback

    private let session: ReplaySession

    /// One speed, which is what a first replay screen needs. The accepted
    /// 0.5×/1×/2× set waits for someone to want it: a speed control is three
    /// more controls on the transport and a preference to carry, and nobody has
    /// yet watched a game back and wished it faster.
    ///
    /// The interval is a *settle*: how long an arrived position stands still
    /// before the next ply departs. Measured from the landing rather than from
    /// the departure, so the walk can never ask for a ply while the last one is
    /// still travelling — the contract's "waits for each move animation to
    /// finish before advancing", held by construction rather than by two
    /// numbers happening not to collide. Travel and settle together are
    /// 780–840 ms, which is the calm cadence this screen already walked at.
    private static let settle = Duration.milliseconds(600)

    /// When the next ply departs, measured from this one's departure: this
    /// one's own travel, and then the settle.
    static func interval(afterTravelling travel: TimeInterval) -> Duration {
        .seconds(travel) + settle
    }

    init(record: RecordSummary,
         session: ReplaySession,
         policy: MotionPolicy = MotionPolicy(reduceMotion: false),
         animator: MotionAnimator = .live,
         feedback: Feedback = .live) throws {
        self.record = record
        self.session = session
        self.policy = policy
        self.feedback = feedback
        self.transits = TransitMotion(animator: animator)
        self.moves = try session.moves()
        self.notation = try MoveReading.line(for: moves, on: record.game.board) {
            Placement(fen: try session.position(atPly: $0).fen, game: record.game)
        }
        let start = try session.position(atPly: 0)
        self.position = start
        self.placement = Placement(fen: start.fen, game: record.game)
        // The accepted history orientation: the human's own side at the bottom
        // where there was a human side, Red at the bottom otherwise.
        self.flipped = record.humanSide == .black
        // Unowned: the transit belongs to this object and cannot outlive it.
        transits.arrived = { [unowned self] in announceLanding() }
    }

    // MARK: - What the board shows

    /// The brackets always mark the move that produced the position on screen,
    /// so they follow the walk and the initial position carries none.
    var lastMove: Move? {
        ply > 0 ? Move(text: moves[ply - 1], on: record.game.board) : nil
    }

    /// The checked general, so the board can ring it. In replay no piece is
    /// ever held, so the rings alone carry check — there is no side-to-move
    /// line here to put a 将军 token on.
    var checkedGeneral: Square? {
        guard position.inCheck else { return nil }
        return placement.general(of: position.sideToMove)
    }

    /// The step the board is drawing, if one is travelling, and the progress of
    /// the disc fading beside it.
    var transit: Transit? { transits.transit }
    var transitFade: Double { transits.fade }

    var isAtStart: Bool { ply == 0 }
    var isAtEnd: Bool { ply == moves.count }

    /// Whether the position on screen is where the game ended. The record's
    /// last ply is where it stopped; whether it *concluded* there is the
    /// record's own committed outcome — the core's adjudication as it was
    /// filed, read back rather than re-derived here. A game that was ended
    /// early stopped without a result, so its last ply is a landing like any
    /// other.
    var isFinalPosition: Bool { isAtEnd && record.outcome != .none }

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

    /// Jumping to a move from the move list, which the contract asks the list
    /// to allow. Manual navigation pauses playback, as every other manual
    /// navigation does.
    func show(move ply: Int) {
        pause()
        show(ply: ply)
    }

    /// Playback starts only after a user action, and stops at the final
    /// position rather than wrapping.
    func toggleAutoplay() {
        if autoplaying {
            pause()
        } else {
            play()
        }
    }

    /// Pauses, whatever asked: the transport, a manual step, a flip, or the app
    /// leaving the foreground. A step already travelling still lands: pausing
    /// is declining to ask for the next ply, not snatching back the last one.
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

    /// The walk itself, and how it is shown. Out-of-range is clamped rather
    /// than refused: every caller here is a control whose bounds the screen
    /// already disables, and a clamp is the honest answer to the one that
    /// slips through.
    ///
    /// Answers how long the step it started takes to arrive, which is what
    /// autoplay waits out: the travel, the crossfade that stands in for it
    /// under Reduce Motion, or nothing at all where the position cuts.
    ///
    /// **One ply travels; anything further cuts.** A jump — a row in the move
    /// list, either end of the transport — is a presentational cut rather than
    /// a cascade: nobody asking for the twentieth position wants to watch
    /// nineteen moves go past on the way, and animating only the last ply of a
    /// jump would draw one move to explain a change of twenty. It is the same
    /// judgement play makes when it discards rather than queues.
    ///
    /// **A step arriving while one travels re-targets rather than queues**, and
    /// re-targeting a travel means cutting it: the position asked for arrives
    /// at once, and the abandoned disc is not drawn landing anywhere, so it
    /// neither sounds nor leaves a mark. Replay commits nothing and has no gate
    /// to hold — and pressing forward faster than a step can be drawn is asking
    /// for the position rather than for the film of it.
    @discardableResult
    private func show(ply target: Int) -> TimeInterval {
        let target = min(max(target, 0), moves.count)
        guard target != ply else { return 0 }
        let forward = target > ply
        guard abs(target - ply) == 1, !transits.isRunning,
              let played = Move(text: moves[min(ply, target)], on: record.game.board),
              // A placement has no origin and nothing travels: the stone is on
              // the point or it is not, so a step through one walks rather than
              // draws, which is the same answer a jump gets.
              let origin = played.from,
              // The mover, read from the position it is leaving: forward it
              // stands at the move's origin, backward at its destination.
              let mover = placement[forward ? origin : played.to]
        else {
            transits.cut()
            walk(to: target)
            return 0
        }

        let captured = forward ? placement[played.to] : nil
        let travel = Motion.travel(distance: Motion.distance(of: played),
                                   on: record.game.board)
        transits.run(policy.movement(Motion.travelAnimation(travel)),
                     drawingRemoval: captured != nil && !policy.reduceMotion) { [self] in
            // A ply the session will not answer for leaves the board exactly
            // where it was, with nothing travelling.
            guard walk(to: target) else { return nil }
            return forward
                ? Transit(kind: .move, move: played, piece: mover,
                          fading: captured.map { ($0, played.to) })
                // A step back is the move read in reverse, which is what an
                // Undo draws during play: the mover returns the way it came,
                // and whatever it took reappears where it stood.
                : Transit(kind: .undo,
                          move: Move(from: played.to, to: origin),
                          piece: mover,
                          fading: placement[played.to].map { ($0, played.to) })
        }
        if transits.drawsRemoval {
            // The captured disc gives way under the arriving mover, leading
            // the arrival by 60 ms and finishing 50 ms after it.
            transits.raiseFade(Motion.captureFadeAnimation(travel: travel))
        } else if !forward, !policy.reduceMotion {
            // The restored piece returns as the mover departs — the capture
            // read backwards — inside the travel.
            transits.raiseFade(Motion.restoreFadeAnimation)
        }
        return policy.reduceMotion ? Motion.crossfade : travel
    }

    /// The position at one ply, asked of the core. Answers whether it came.
    @discardableResult
    private func walk(to target: Int) -> Bool {
        guard let position = try? session.position(atPly: target) else { return false }
        ply = target
        self.position = position
        placement = Placement(fen: position.fen, game: record.game)
        return true
    }

    // MARK: - Landings

    /// The disc has met the board. One sound per landing, chosen by what the
    /// arrived position means — the same rule, through the same seam and the
    /// same **sound.enabled** gate, that play's landings answer to. A replayed
    /// landing is a landing; there is no second rule for it.
    ///
    /// The haptic comes with it for the same reason: every landing there is
    /// takes the alignment pattern, and this is one.
    private func announceLanding() {
        feedback.perform(.landing)
        feedback.play(.ofTheLanding(transit,
                                    finished: isFinalPosition,
                                    inCheck: position.inCheck))
    }

    /// The board's own arrival wires — see ArrivalReporter for why the
    /// transaction completion alone cannot be trusted with either of them.
    func travelArrived() { transits.travelArrived() }
    func fadeArrived() { transits.fadeArrived() }

    // MARK: - Lifetime

    /// Releases the detached session. The screen calls this as it closes: the
    /// core is holding a session open for this screen and nothing else will.
    func close() {
        pause()
        transits.cut()
        session.close()
    }
}
