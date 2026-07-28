// The play screen.
//
// docs/interaction-design.md, "Layout shapes": ordinary Mac windows use the
// side-by-side shape — the board on one side, with a panel beside it carrying
// the turn status, the move list, and controls that do not need to sit under
// the thumb. The stacked shape, for narrow windows and iPhone, comes with iOS.
//
// The board is square and sized to the largest square fitting both the
// available width and the height left after the chrome, never below the
// 44-point floor and never above the 720-point ceiling; surplus space goes to
// the layout rather than to the board. When space is short the chrome tightens
// first, and the window stops resizing where either would go below its floor.
//
// Motion runs through PlayMotion: every board input passes its gate, so input
// during a committing transition is discarded here rather than queued, and the
// controls that a running transition makes unavailable say so.

import SwiftUI

struct PlayScreen: View {
    @State private var game: Game?
    @State private var motion: PlayMotion?
    @State private var startFailure: CoreError?
    @State private var claimPresented = false

    /// Whether the player has closed the result notice. It is view state and
    /// not game state: closing the notice changes nothing about the game, and
    /// the notice does not come back for a result already seen.
    @State private var resultDismissed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let core: Core

    private static let panelWidth: CGFloat = 260
    private static let boardPadding: CGFloat = 24

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        Group {
            if let game, let motion {
                layout(game, motion)
            } else if let startFailure {
                ContentUnavailableView("The game did not start",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(startFailure.description).monospaced())
            } else {
                ProgressView()
            }
        }
        .environment(\.motionPolicy, policy)
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        #if DEBUG
        .preferredColorScheme(Self.launchColorScheme)
        #endif
        .task {
            guard game == nil else { return }
            start(replayingLaunchLine: true)
        }
        .onChange(of: reduceMotion) {
            motion?.policy = policy
        }
    }

    /// A game that will not start is shown rather than swallowed: it is a bug
    /// in this app or a packaging failure, never a rules outcome.
    private func start(replayingLaunchLine: Bool) {
        startFailure = nil
        resultDismissed = false
        do {
            let game = try Game(core: core)
            #if DEBUG
            if replayingLaunchLine { try game.replay(Self.launchReplayLine) }
            #endif
            self.game = game
            let motion = PlayMotion(game: game, policy: policy)
            self.motion = motion
            // A replayed position may already stand in check; its rings pulse
            // as they first appear.
            motion.boardAppeared()
        } catch {
            game = nil
            motion = nil
            startFailure = CoreError(wrapping: error)
        }
    }

    #if DEBUG
    private static func launchArgument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.index(after: index) < arguments.endIndex
        else { return nil }
        return arguments[arguments.index(after: index)]
    }

    /// The line `-mxq-replay a1a2,b7b5,…` names, played before first display so
    /// a UI test can start from a position it would otherwise have to click its
    /// way to. Debug only, and no move of it bypasses the core.
    private static var launchReplayLine: [String] {
        (launchArgument(after: "-mxq-replay") ?? "")
            .split(separator: ",")
            .map(String.init)
    }

    /// The appearance `-mxq-appearance dark` names. AppKit no longer takes
    /// `-AppleInterfaceStyle` from a launch argument, and glass has to be
    /// looked at in both appearances rather than reasoned about in one.
    private static var launchColorScheme: ColorScheme? {
        launchArgument(after: "-mxq-appearance") == "dark" ? .dark : nil
    }
    #endif

    private func layout(_ game: Game, _ motion: PlayMotion) -> some View {
        GeometryReader { proxy in
            let geometry = boardGeometry(in: proxy.size)
            HStack(spacing: 0) {
                ZStack {
                    BoardView(geometry: geometry,
                              placement: game.placement,
                              flipped: game.flipped,
                              selected: game.selected,
                              destinations: game.destinations,
                              captures: game.captures,
                              lastMove: game.lastMove,
                              checkedGeneral: game.checkedGeneral,
                              transit: motion.transit,
                              transitFade: motion.transitFade,
                              checkEmphasis: motion.checkEmphasis,
                              markerEmphasis: motion.markerEmphasis,
                              policy: motion.policy,
                              onTap: { tap($0, in: game, motion) },
                              onTravelArrival: { motion.travelArrived() },
                              onFadeArrival: { motion.fadeArrived() })

                    // The notice waits for the landing: a result arrives with
                    // a move, and the move has to finish being shown before
                    // an announcement stands in front of it.
                    if game.isFinished, !resultDismissed, !motion.isCommitting {
                        ResultNotice(state: game.presentedState,
                                     reason: game.evaluation.reason,
                                     canUndo: motion.canUndo,
                                     undo: { motion.undo() },
                                     startNewGame: { start(replayingLaunchLine: false) },
                                     close: { withAnimation(policy.fade(Motion.stateFadeAnimation)) { resultDismissed = true } })
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Tapping outside the board cancels the selection.
                .contentShape(Rectangle())
                .onTapGesture { motion.cancelSelection() }

                panel(game, motion)
                    .frame(width: Self.panelWidth)
            }
        }
        // A game that resumes has a result to show again if it reaches one.
        .onChange(of: game.isFinished) { _, finished in
            if !finished { resultDismissed = false }
        }
    }

    /// Every board tap answers through the gate first: input during a
    /// committing transition is discarded, never queued. A finished board is
    /// not inert — it has nothing left to play, so a tap closes the notice
    /// standing in front of the position it produced; once the notice is away
    /// there is nothing left for a tap to do, and the acknowledgment beat is
    /// its answer. The notice-closing tap is an accepted input, not a rejected
    /// one, and gets no beat.
    private func tap(_ square: Square, in game: Game, _ motion: PlayMotion) {
        guard !motion.isCommitting else { return }
        guard game.isFinished else {
            motion.tap(square)
            return
        }
        if resultDismissed {
            motion.acknowledge()
        } else {
            withAnimation(policy.fade(Motion.stateFadeAnimation)) { resultDismissed = true }
        }
    }

    private func panel(_ game: Game, _ motion: PlayMotion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TurnStatus(state: game.presentedState,
                       reason: game.evaluation.reason,
                       sideToMove: game.evaluation.sideToMove,
                       inCheck: game.evaluation.inCheck,
                       beatEmphasis: motion.beatEmphasis)
                .padding(8)

            Divider()

            MoveList(notation: game.notation)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)

            Divider()

            // Where all three fit at their full width they keep it; where the
            // concluding action's longer label leaves no room, the flip control
            // falls back to its symbol, which carries the same label either way.
            ViewThatFits(in: .horizontal) {
                controls(game, motion, compactFlip: false)
                controls(game, motion, compactFlip: true)
            }
            .padding(16)
            // The blocking notice the contract gives the claim, presented when
            // the player invokes it rather than the moment it becomes
            // available: in Free Play the enabled control and the status line's
            // 可判和 already stand for the offer.
            .alert("局面已三次重复，可以和棋结束。", isPresented: $claimPresented) {
                Button("继续对局", role: .cancel) { }
                Button("以和棋结束") { withAnimation(policy.fade(Motion.stateFadeAnimation)) { game.claimDraw() } }
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        // The panel is outside the board too: a tap on its quiet parts
        // cancels the selection. Its controls keep their own taps.
        .contentShape(Rectangle())
        .onTapGesture { motion.cancelSelection() }
    }

    /// The play control cluster: the one custom glass surface on screen during
    /// ordinary play. It carries no tint during play, because saturated colour
    /// on the play screen means which side a piece belongs to. Free Play's
    /// three, in the accepted order — it cannot resign, having no opponent to
    /// resign to, and it is the mode the accepted orientation behaviour gives a
    /// flip control.
    ///
    /// A finished game has nothing to judge a draw in, so that slot carries the
    /// concluding action instead — the one obvious next action, and therefore
    /// the one thing on screen the tint rule allows.
    private func controls(_ game: Game, _ motion: PlayMotion, compactFlip: Bool) -> some View {
        HStack(spacing: 8) {
            // Unavailable until a running transition completes — its own
            // Undo's included, which is what makes a second Undo wait its
            // turn rather than queue.
            Button("悔棋") { motion.undo() }
                .buttonStyle(.glass)
                .disabled(!motion.canUndo)

            if game.isFinished {
                // Prominent once it is the only one: while the notice stands in
                // front of the board it carries the tinted copy of this action,
                // and two tinted buttons for one action is one too many.
                concludingAction(prominent: resultDismissed)
            } else {
                Button("判和") { claimPresented = true }
                    .buttonStyle(.glass)
                    .disabled(!game.evaluation.claimAvailable)
            }

            Button {
                motion.flip()
            } label: {
                if compactFlip {
                    Label("翻转棋盘", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                } else {
                    Label("翻转棋盘", systemImage: "arrow.up.arrow.down")
                }
            }
            .buttonStyle(.glass)
            .accessibilityLabel("翻转棋盘")

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func concludingAction(prominent: Bool) -> some View {
        let action = Button("开始新对局") { start(replayingLaunchLine: false) }
            .accessibilityIdentifier("cluster-new-game")
        if prominent {
            action.buttonStyle(.glassProminent)
        } else {
            action.buttonStyle(.glass)
        }
    }

    /// The largest board that fits beside the panel, bounded by the accepted
    /// floor and ceiling.
    private func boardGeometry(in size: CGSize) -> BoardGeometry {
        let available = CGSize(width: size.width - Self.panelWidth - 2 * Self.boardPadding,
                               height: size.height - 2 * Self.boardPadding)
        let fitted = BoardGeometry.fitting(available)
            ?? BoardGeometry(pitch: BoardGeometry.minimumPitch)
        return BoardGeometry(pitch: min(fitted.pitch, BoardGeometry.maximumPitch))
    }

    /// Both the board and the chrome have floors, so the window has one too.
    static var minimumWidth: CGFloat {
        BoardGeometry(pitch: BoardGeometry.minimumPitch).coreSide
            + panelWidth + 2 * boardPadding
    }

    static var minimumHeight: CGFloat {
        BoardGeometry(pitch: BoardGeometry.minimumPitch).blockSize.height
            + 2 * boardPadding
    }
}
