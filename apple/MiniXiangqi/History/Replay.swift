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

import Observation

@Observable
final class Replay {
    let record: RecordSummary

    /// The recorded line in canonical notation, and the same line as the player
    /// reads it — recomputed exactly as a resumed active game's is, through the
    /// one reading in `MoveNotation`.
    let moves: [String]
    let notation: [String]

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

    private let session: ReplaySession

    /// One speed, which is what a first replay screen needs. The accepted
    /// 0.5×/1×/2× set waits for someone to want it: a speed control is three
    /// more controls on the transport and a preference to carry, and nobody has
    /// yet watched a game back and wished it faster.
    private static let step = Duration.milliseconds(800)

    init(record: RecordSummary, session: ReplaySession) throws {
        self.record = record
        self.session = session
        self.moves = try session.moves()
        self.notation = try MoveNotation.line(for: moves) {
            Placement(fen: try session.position(atPly: $0).fen)
        }
        let start = try session.position(atPly: 0)
        self.position = start
        self.placement = Placement(fen: start.fen)
        // The accepted history orientation: the human's own side at the bottom
        // where there was a human side, Red at the bottom otherwise.
        self.flipped = record.humanSide == .black
    }

    // MARK: - What the board shows

    /// The brackets always mark the move that produced the position on screen,
    /// so they follow the walk and the initial position carries none.
    var lastMove: Move? {
        ply > 0 ? Move(text: moves[ply - 1]) : nil
    }

    /// The checked general, so the board can ring it. In replay no piece is
    /// ever held, so the rings alone carry check — there is no side-to-move
    /// line here to put a 将军 token on.
    var checkedGeneral: Square? {
        guard position.inCheck else { return nil }
        return placement.general(of: position.sideToMove)
    }

    var isAtStart: Bool { ply == 0 }
    var isAtEnd: Bool { ply == moves.count }

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
    /// leaving the foreground.
    func pause() {
        playback?.cancel()
        playback = nil
        autoplaying = false
    }

    private func play() {
        guard !isAtEnd else { return }
        autoplaying = true
        playback = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.step)
                guard !Task.isCancelled, let self, self.autoplaying else { return }
                self.show(ply: self.ply + 1)
                if self.isAtEnd { return self.pause() }
            }
        }
    }

    /// The walk itself. Out-of-range is clamped rather than refused: every
    /// caller here is a control whose bounds the screen already disables, and a
    /// clamp is the honest answer to the one that slips through.
    private func show(ply target: Int) {
        let target = min(max(target, 0), moves.count)
        guard target != ply, let position = try? session.position(atPly: target) else { return }
        ply = target
        self.position = position
        placement = Placement(fen: position.fen)
    }

    // MARK: - Lifetime

    /// Releases the detached session. The screen calls this as it closes: the
    /// core is holding a session open for this screen and nothing else will.
    func close() {
        pause()
        session.close()
    }
}
