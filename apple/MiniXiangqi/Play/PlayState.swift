// The game the app is playing, and the presentation state that belongs to the
// game rather than to the screen showing it.
//
// It lives **above** the navigation container, and that placement is the whole
// point of the type. The container keeps one destination's content alive at a
// time: leaving Play tears the play screen down, and returning to it builds a
// fresh one. A game held inside that screen would therefore be resumed again on
// every visit — a full decode-and-replay of the stored line each time — and,
// worse, the view state that says the player has already put the result notice
// away would be rebuilt with it, so a notice they closed would come back. The
// contract is explicit that it does not present itself again for the same
// result, and a game is the app's state rather than a tab's.
//
// So resuming happens exactly once per launch, here, and the play screen
// re-renders against a living object it did not create.

import Observation

@Observable
final class PlayState {
    private let core: Core

    private(set) var game: Game?
    private(set) var motion: PlayMotion?

    /// The start attempt that failed, if one did. A game that will not start is
    /// shown rather than swallowed — it is a bug in this app or a packaging
    /// failure, never a rules outcome.
    private(set) var startFailure: CoreError?

    /// Whether the player has closed the result notice. It is presentation and
    /// not game state — closing the notice changes nothing about the game — but
    /// it is the *game's* presentation, not the screen's: the notice does not
    /// come back for a result already seen, and walking to History and back is
    /// not seeing a new result. A result still unconfirmed at quit does present
    /// its notice again at the next launch, because the finished, unfiled game
    /// is exactly what resumed.
    var resultDismissed = false

    /// Whether the once-per-launch start has run.
    private var started = false

    init(core: Core) {
        self.core = core
    }

    /// Opens the stored active game, once. Every later visit to the play
    /// destination finds the game already here.
    func startIfNeeded(policy: MotionPolicy) {
        guard !started else { return }
        started = true
        #if DEBUG
        fileLaunchHistory()
        #endif
        start(policy: policy, replayingLaunchLine: true)
    }

    /// What 保存 does on a finished board: the terminal commit and nothing
    /// else. The game becomes a History record and the board stays exactly
    /// where the result left it — the notice above reads the filing off the
    /// game and becomes the recorded one, which is the whole of the change on
    /// screen. A filing the store refuses files nothing and answers `false`:
    /// the accepted retry presents, and the game stays active as it stood.
    func save() -> Bool {
        guard let game else { return true }
        do {
            try game.file()
            return true
        } catch {
            return false
        }
    }

    /// What 开始新对局 does on a finished board: the same filing first — a
    /// claimed draw and an already-saved result were both filed before this
    /// was pressed, and neither is filed twice — and only then does the board
    /// reset. A filing the store refuses resets nothing and answers `false`:
    /// the accepted retry presents, and the game stays exactly as it stood.
    func startNewGame(policy: MotionPolicy) -> Bool {
        guard let game else { return true }
        do {
            try game.file()
            start(policy: policy, replayingLaunchLine: false)
            return true
        } catch {
            return false
        }
    }

    /// Keeps the running motion on the current policy when Reduce Motion
    /// changes under it.
    func adopt(_ policy: MotionPolicy) {
        motion?.policy = policy
    }

    /// Opens the game the library holds, or the empty board when it holds none:
    /// launch is a resume, and an untouched board creates nothing.
    ///
    /// The launch line is replayed only by the once-per-launch start. Replaying
    /// it again onto a game that already has it would be a second attempt at
    /// moves the position has left behind, which the core refuses — the failure
    /// this fix was found by.
    private func start(policy: MotionPolicy, replayingLaunchLine: Bool) {
        startFailure = nil
        resultDismissed = false
        // Whatever session the previous game held is over: filed if it
        // finished, released either way. Release before resume is the
        // single-session rule's precondition, not a saving act — the core
        // committed everything as it happened.
        core.endSession()
        do {
            let game = try Game(rules: Self.rules(over: core))
            #if DEBUG
            if replayingLaunchLine { try game.replay(Self.launchReplayLine) }
            #endif
            self.game = game
            let motion = PlayMotion(game: game, policy: policy)
            self.motion = motion
            // A resumed position may already stand in check; its rings pulse
            // as they first appear.
            motion.boardAppeared()
        } catch {
            game = nil
            motion = nil
            startFailure = CoreError(wrapping: error)
        }
    }

    /// The seam the game speaks through: the core, unless a debug launch asked
    /// for the refusing stand-in so the save-failure state can be produced on a
    /// real screen.
    private static func rules(over core: Core) -> Rules {
        #if DEBUG
        if DebugLaunch.contains("-mxq-refuse-saves") {
            return RefusingRules(core, refuses: true)
        }
        #endif
        return core
    }

    #if DEBUG
    /// The line `-mxq-replay a1a2,b7b5,…` names, played before first display so
    /// a UI test can start from a position it would otherwise have to click its
    /// way to. Debug only, and no move of it bypasses the core.
    private static var launchReplayLine: [String] {
        (DebugLaunch.argument(after: "-mxq-replay") ?? "")
            .split(separator: ",")
            .map(String.init)
    }

    /// The games `-mxq-history a1a2,b7b5;…;…` names, each played and filed
    /// before the board opens, so that a screenshot of the History list has a
    /// library to show and a UI test has records to act on. Games are separated
    /// by `;` and plies by `,`.
    ///
    /// Each one goes through the same path a person's game does — every ply
    /// committed by the core, the finished game filed by its own terminal
    /// commit — so nothing seeded here is a record the app could not have made.
    /// A line the core refuses stops the seeding rather than filing a
    /// half-game, and the launch continues: the failure then shows as a shorter
    /// list than the test asked for, where a test can see it.
    private func fileLaunchHistory() {
        let lines = (DebugLaunch.argument(after: "-mxq-history") ?? "")
            .split(separator: ";")
            .map { $0.split(separator: ",").map(String.init) }
        guard !lines.isEmpty else { return }
        for line in lines {
            core.endSession()
            guard let game = try? Game(rules: core), (try? game.replay(line)) != nil
            else { return }
            if game.evaluation.claimAvailable {
                game.claimDraw()
            } else if game.isFinished {
                try? game.file()
            }
        }
        core.endSession()
    }
    #endif
}
