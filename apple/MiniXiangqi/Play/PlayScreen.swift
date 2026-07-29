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

    /// The air around the board, and an allowance rather than a padding: it is
    /// taken off the space the board is fitted into, and the board is then
    /// centred in the whole of it. At the minimum window that comes to exactly
    /// 24 points on every side, which is what the number is chosen for. Above
    /// the minimum the centring hands the board more than 24, and that is
    /// accepted — the surplus a window has beyond the board it can carry
    /// belongs around the board rather than inside it.
    private static let boardPadding: CGFloat = 24

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        Group {
            if let game, let motion {
                layout(game, motion)
            } else if let startFailure {
                // The description under the title is the core's own diagnostic
                // text: not copy, and not localized.
                ContentUnavailableView("failure.gameDidNotStart",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(verbatim: startFailure.description).monospaced())
            } else {
                ProgressView()
            }
        }
        .environment(\.motionPolicy, policy)
        #if DEBUG
        // The floor is the product's; `-mxq-no-minimum` takes it off so a
        // screenshot can show what the layout does below it.
        .frame(minWidth: Self.liftsWindowMinimum ? nil : Self.minimumWidth,
               minHeight: Self.liftsWindowMinimum ? nil : Self.minimumHeight)
        .preferredColorScheme(Self.launchColorScheme)
        #if os(macOS)
        .background(LaunchWindowSizer(contentSize: Self.launchWindowSize))
        #endif
        #else
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
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

    /// The size `-mxq-window 900x700` names, handed to AppKit as the window's
    /// content size — which on this window is the whole frame, title bar
    /// included, since the content view runs the full height of it. A
    /// screenshot series about layout has to state the size each frame was
    /// taken at, and a window a test resized by dragging its corner cannot.
    private static var launchWindowSize: CGSize? {
        guard let text = launchArgument(after: "-mxq-window") else { return nil }
        let sides = text.split(separator: "x").compactMap { Double($0) }
        guard sides.count == 2, sides.allSatisfy({ $0 > 0 }) else { return nil }
        return CGSize(width: sides[0], height: sides[1])
    }

    /// Whether `-mxq-no-minimum` was given. The window's floor is the thing
    /// under discussion, so it has to be possible to photograph below it.
    private static var liftsWindowMinimum: Bool {
        ProcessInfo.processInfo.arguments.contains("-mxq-no-minimum")
    }
    #endif

    /// Whether the board carries its file-numeral strips. Always, except when
    /// `-mxq-hide-numerals` takes them off: what the strips cost the layout is
    /// a question a pair of screenshots answers and prose does not.
    private static var showsNumerals: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-mxq-hide-numerals")
        #else
        true
        #endif
    }

    private func layout(_ game: Game, _ motion: PlayMotion) -> some View {
        GeometryReader { proxy in
            let geometry = boardGeometry(in: proxy.size)
            HStack(spacing: 0) {
                ZStack {
                    BoardView(geometry: geometry,
                              placement: game.placement,
                              flipped: game.flipped,
                              showsNumerals: Self.showsNumerals,
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
                              onFadeArrival: { motion.fadeArrived() },
                              onFlipArrival: { motion.flipArrived() })

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
    /// committing transition is discarded, never queued. What is decided here
    /// is only the one thing that is not about the position: a finished board
    /// is not inert, so a tap closes the result notice standing in front of
    /// the position it produced, and that tap is an accepted input rather than
    /// a rejected one, so it gets no beat. Everything else — including that a
    /// board with nothing left to play answers a tap with the acknowledgment
    /// beat — goes through PlayMotion, which asks the game.
    private func tap(_ square: Square, in game: Game, _ motion: PlayMotion) {
        guard !motion.isCommitting else { return }
        if game.isFinished, !resultDismissed {
            withAnimation(policy.fade(Motion.stateFadeAnimation)) { resultDismissed = true }
            return
        }
        motion.tap(square)
    }

    /// The panel's three sections read down one edge, so they begin on one
    /// edge: `panelInset` from the panel's own. Each of them brings its own
    /// interior — the status line's background is inset within it, the move
    /// list's number column is right-aligned within it — and the outer padding
    /// here is what makes the three agree. The status line therefore takes 4,
    /// because its own background already accounts for the other 12.
    private static let panelInset: CGFloat = 16

    private func panel(_ game: Game, _ motion: PlayMotion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TurnStatus(state: game.presentedState,
                       reason: game.evaluation.reason,
                       sideToMove: game.evaluation.sideToMove,
                       inCheck: game.evaluation.inCheck,
                       beatEmphasis: motion.beatEmphasis)
                .padding(.horizontal, Self.panelInset - 12)
                .padding(.vertical, 8)

            Divider()

            MoveList(notation: game.notation)
                .padding(.horizontal, Self.panelInset)
                .frame(maxHeight: .infinity)

            Divider()

            // Where all three fit at their full width they keep it; where the
            // other two's labels leave no room — the concluding action in
            // Chinese, every cluster state in English at the minimum window —
            // the flip control falls back to its symbol, which carries the
            // same accessibility label either way.
            ViewThatFits(in: .horizontal) {
                controls(game, motion, compactFlip: false)
                controls(game, motion, compactFlip: true)
            }
            .padding(Self.panelInset)
            // The blocking notice the contract gives the claim, presented when
            // the player invokes it rather than the moment it becomes
            // available: in Free Play the enabled control and the status line's
            // 可判和 already stand for the offer.
            //
            // The accepted sentence is one sentence and stays one, but it is
            // said in the two roles an alert has: what has happened is the
            // title, and what can be done about it is the message. The halves
            // are separate keys and are never recombined into a single title.
            //
            // Confirming goes through PlayMotion, as everything that changes
            // the game does: the claim is the one result that arrives with no
            // piece moving, and the sound a result makes belongs beside the
            // ones the landings make rather than in a button here.
            .alert("alert.claimDraw.title", isPresented: $claimPresented) {
                Button("control.keepPlaying", role: .cancel) { }
                Button("control.endAsDraw") { motion.claimDraw() }
            } message: {
                Text("alert.claimDraw.message")
            }
        }
        .frame(maxHeight: .infinity)
        // The material runs to the window's top edge, behind the title bar, so
        // the panel reads as one surface from the top of the window down. Only
        // the material goes up there: the sections keep their own inset and
        // stay clear of the title bar's controls.
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(.container, edges: .top)
        }
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
    ///
    /// Each carries an identifier beside its label, in the cluster's own
    /// namespace. A label is copy and changes with the interface language; an
    /// identifier does not, so it is what a test addresses a control by.
    private func controls(_ game: Game, _ motion: PlayMotion, compactFlip: Bool) -> some View {
        HStack(spacing: 8) {
            // Unavailable until a running transition completes — its own
            // Undo's included, which is what makes a second Undo wait its
            // turn rather than queue.
            Button("control.undo") { motion.undo() }
                .buttonStyle(.glass)
                .disabled(!motion.canUndo)
                .accessibilityIdentifier("cluster-undo")

            if game.isFinished {
                // Prominent once it is the only one: while the notice stands in
                // front of the board it carries the tinted copy of this action,
                // and two tinted buttons for one action is one too many.
                concludingAction(prominent: resultDismissed)
            } else {
                Button("control.claimDraw") { claimPresented = true }
                    .buttonStyle(.glass)
                    .disabled(!game.evaluation.claimAvailable)
                    .accessibilityIdentifier("cluster-claim")
            }

            Button {
                motion.flip()
            } label: {
                if compactFlip {
                    Label("control.flipBoard", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                } else {
                    Label("control.flipBoard", systemImage: "arrow.up.arrow.down")
                }
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("control.flipBoard"))
            .accessibilityIdentifier("cluster-flip")

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func concludingAction(prominent: Bool) -> some View {
        let action = Button("control.newGame") { start(replayingLaunchLine: false) }
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

#if DEBUG && os(macOS)
/// Applies `-mxq-window`'s size to the window, once there is a window to apply
/// it to. Debug only, and it asks AppKit for the size rather than asserting it:
/// the window's own minimum still clamps the request, which is how a test
/// measures what that minimum actually comes to.
private struct LaunchWindowSizer: NSViewRepresentable {
    var contentSize: CGSize?

    func makeNSView(context: Context) -> NSView { Sizer(contentSize: contentSize) }
    func updateNSView(_ view: NSView, context: Context) { }

    private final class Sizer: NSView {
        private let contentSize: CGSize?

        init(contentSize: CGSize?) {
            self.contentSize = contentSize
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not from a nib") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let contentSize else { return }
            // On the next pass, after AppKit has restored the saved frame and
            // SwiftUI has handed the window the content's minimum: either one
            // arriving afterwards would undo this.
            DispatchQueue.main.async { [weak window] in
                window?.setContentSize(contentSize)
                window?.center()
            }
        }
    }
}
#endif
