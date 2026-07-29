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
//
// The game on screen is the stored active game: launch resumes it exactly
// where it stood, and 开始新对局 files a finished one in History before the
// board resets — quitting the app stopped being the end of the game.

import SwiftUI

struct PlayScreen: View {
    /// The game, and the presentation state that belongs to it. Held above the
    /// navigation container, because the container rebuilds this screen every
    /// time the player comes back to it and the game is not the screen's to
    /// create twice.
    let play: PlayState

    @State private var claimPresented = false

    /// Whether the save-failure capsule is up. Raised when a ply's commit is
    /// refused, and transient: it answers the touch and withdraws by itself.
    /// View state, and rightly so — it has a four-second life and nothing to
    /// say to a screen that is not on show.
    @State private var saveFailureShown = false

    /// The terminal commit the store refused — the draw claim, or the filing
    /// that 开始新对局 owes — held while the accepted 无法保存对局 retry is on
    /// screen, so Try Again repeats exactly the act that failed. The game
    /// stays active and unchanged underneath either.
    private enum FailedFiling { case claim, file }
    @State private var failedFiling: FailedFiling?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        Group {
            if let game = play.game, let motion = play.motion {
                layout(game, motion)
            } else if let startFailure = play.startFailure {
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
        // screenshot can show what the layout does below it. It stays on the
        // destination's own content rather than on the container, so that the
        // navigation chrome adds to the board's floor instead of eating it.
        .frame(minWidth: Self.liftsWindowMinimum ? nil : BoardLayout.minimumWidth,
               minHeight: Self.liftsWindowMinimum ? nil : BoardLayout.minimumHeight)
        #else
        .frame(minWidth: BoardLayout.minimumWidth, minHeight: BoardLayout.minimumHeight)
        #endif
        .task {
            play.startIfNeeded(policy: policy)
        }
        .onChange(of: reduceMotion) {
            play.adopt(policy)
        }
    }

    /// 开始新对局 on a finished board. The filing is the state's; what is
    /// decided here is only what a refusal looks like on screen.
    private func startNewGame() {
        if !play.startNewGame(policy: policy) { failedFiling = .file }
    }

    #if DEBUG
    /// Whether `-mxq-no-minimum` was given. The window's floor is the thing
    /// under discussion, so it has to be possible to photograph below it.
    private static var liftsWindowMinimum: Bool {
        DebugLaunch.contains("-mxq-no-minimum")
    }
    #endif

    /// Whether the board carries its file-numeral strips. Always, except when
    /// `-mxq-hide-numerals` takes them off: what the strips cost the layout is
    /// a question a pair of screenshots answers and prose does not.
    private static var showsNumerals: Bool {
        #if DEBUG
        !DebugLaunch.contains("-mxq-hide-numerals")
        #else
        true
        #endif
    }

    private func layout(_ game: Game, _ motion: PlayMotion) -> some View {
        GeometryReader { proxy in
            let geometry = BoardLayout.geometry(in: proxy.size)
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
                    if game.isFinished, !play.resultDismissed, !motion.isCommitting {
                        ResultNotice(state: game.presentedState,
                                     reason: game.evaluation.reason,
                                     canUndo: motion.canUndo,
                                     undo: { motion.undo() },
                                     startNewGame: { startNewGame() },
                                     close: { withAnimation(policy.fade(Motion.stateFadeAnimation)) { play.resultDismissed = true } })
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Tapping outside the board cancels the selection.
                .contentShape(Rectangle())
                .onTapGesture { motion.cancelSelection() }

                panel(game, motion)
                    .frame(width: BoardLayout.panelWidth)
            }
        }
        // A game that resumes has a result to show again if it reaches one.
        .onChange(of: game.isFinished) { _, finished in
            if !finished { play.resultDismissed = false }
        }
        // The capsule follows the recorded failure: raised when a ply's save
        // is refused, cleared the moment a new attempt starts. Its withdrawal
        // by timer is its own, below.
        .onChange(of: game.failure) { _, failure in
            withAnimation(policy.fade(Motion.stateFadeAnimation)) {
                saveFailureShown = failure != nil
            }
        }
        // The blocking retry the contract gives a refused terminal commit —
        // one presentation for both, because it is one promise: the current
        // game is unchanged.
        .alert("alert.saveFailed.title",
               isPresented: Binding(get: { failedFiling != nil },
                                    set: { if !$0 { failedFiling = nil } })) {
            Button("control.cancel", role: .cancel) { }
            Button("control.tryAgain") { retryFiling(game, motion) }
        } message: {
            Text("alert.saveFailed.message")
        }
    }

    private func retryFiling(_ game: Game, _ motion: PlayMotion) {
        switch failedFiling {
        case .claim: claimDraw(game, motion)
        case .file: startNewGame()
        case nil: break
        }
    }

    /// The player confirmed the claim; committing it is the core's. A commit
    /// the store refused changed nothing, and says so through the retry.
    private func claimDraw(_ game: Game, _ motion: PlayMotion) {
        motion.claimDraw()
        if game.filingFailure != nil { failedFiling = .claim }
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
        if game.isFinished, !play.resultDismissed {
            withAnimation(policy.fade(Motion.stateFadeAnimation)) { play.resultDismissed = true }
            return
        }
        motion.tap(square)
    }

    /// The panel's three sections read down one edge, so they begin on one
    /// edge: `BoardLayout.panelInset` from the panel's own. Each of them brings
    /// its own interior — the status line's background is inset within it, the
    /// move list's number column is right-aligned within it — and the outer
    /// padding here is what makes the three agree. The status line therefore
    /// takes 4, because its own background already accounts for the other 12.
    private func panel(_ game: Game, _ motion: PlayMotion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TurnStatus(state: game.presentedState,
                       reason: game.evaluation.reason,
                       sideToMove: game.evaluation.sideToMove,
                       inCheck: game.evaluation.inCheck,
                       beatEmphasis: motion.beatEmphasis)
                .padding(.horizontal, BoardLayout.panelInset - 12)
                .padding(.vertical, 8)

            Divider()

            MoveList(notation: game.notation)
                .padding(.horizontal, BoardLayout.panelInset)
                .frame(maxHeight: .infinity)
                // The transient capsule the contract anchors to the turn
                // status: hung just beneath the element it answers for, over
                // the list rather than in it, because it is feedback passing
                // in front of the surface and not a row of the record.
                .overlay(alignment: .top) {
                    if saveFailureShown {
                        saveFailureCapsule
                            .padding(.top, 6)
                            .transition(.opacity)
                    }
                }

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
            .padding(BoardLayout.panelInset)
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
                Button("control.endAsDraw") { claimDraw(game, motion) }
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

    /// The transient save-failure capsule: the accepted words, a warning
    /// symbol in place of the warning haptic a Mac does not have, and nothing
    /// modal about it. The board shows nothing because the position did not
    /// change; this small surface at the status element is the whole report.
    /// It withdraws by itself, and a screen reader hears it arrive rather
    /// than having to catch it.
    private var saveFailureCapsule: some View {
        Label("status.saveFailed", systemImage: "exclamationmark.triangle")
            .font(.callout)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .accessibilityIdentifier("save-failure")
            .onAppear {
                AccessibilityNotification
                    .Announcement(String(localized: "status.saveFailed"))
                    .post()
            }
            .task {
                // Transient by its own clock: long enough to read twice, gone
                // without being asked. A retry that fails again re-raises it —
                // the failure passes through nil as the new attempt starts, so
                // a fresh capsule gets a fresh withdrawal.
                try? await Task.sleep(for: .seconds(4))
                withAnimation(policy.fade(Motion.stateFadeAnimation)) {
                    saveFailureShown = false
                }
            }
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
                concludingAction(prominent: play.resultDismissed)
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
        let action = Button("control.newGame") { startNewGame() }
            .accessibilityIdentifier("cluster-new-game")
        if prominent {
            action.buttonStyle(.glassProminent)
        } else {
            action.buttonStyle(.glass)
        }
    }

}
