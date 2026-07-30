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
// where it stood, and the concluding action files a finished one in History
// before the destination returns to its pre-start state.
//
// This is the board and only the board. The Play destination's other two pages
// are the home, where what to play is chosen, and each mode's pre-start state;
// PlayDestination is what holds the three. Going back from here reaches the
// home and ends nothing — the game stays active and its card there is the way
// back in.

import SwiftUI

struct PlayScreen: View {
    /// The game, and the presentation state that belongs to it. Held above the
    /// navigation container, because the container rebuilds this screen every
    /// time the player comes back to it and the game is not the screen's to
    /// create twice.
    let play: PlayState

    /// Opens one History record's replay. The screen it opens on is not this
    /// one, so the container above both is what performs it; 回放 on a recorded
    /// result is the only thing that asks.
    var replay: (UInt64) -> Void

    @State private var claimPresented = false
    @State private var resignPresented = false

    /// Whether the save-failure capsule is up. Raised when a ply's commit is
    /// refused, and transient: it answers the touch and withdraws by itself.
    /// View state, and rightly so — it has a four-second life and nothing to
    /// say to a screen that is not on show.
    @State private var saveFailureShown = false

    /// The terminal commit the store refused — the draw claim, 认输, the
    /// notice's 保存, or the filing that the concluding action owes — held
    /// while the accepted 无法保存对局 retry is on screen, so Try Again repeats
    /// exactly the act that failed rather than the nearest one to it. The game
    /// stays active and unchanged underneath any of them.
    private enum FailedFiling { case claim, resign, save, file, finish }
    @State private var failedFiling: FailedFiling?

    @Environment(\.motionPolicy) private var policy

    var body: some View {
        Group {
            if let game = play.game, let motion = play.motion {
                layout(game, motion)
            } else {
                // Nothing reaches the board without a game — the page and the
                // game are set together — so this is the honest nothing rather
                // than a state to design.
                ProgressView()
            }
        }
    }

    /// The concluding action on a finished board: the filing, then the
    /// finished game's own mode's pre-start page. The filing is the state's;
    /// what is decided here is only what a refusal looks like on screen.
    private func startNewGame() {
        if !play.startNewGame() { failedFiling = .file }
    }

    /// 完成 on the recorded notice: back to the Play home, filing nothing a
    /// second time.
    private func finish() {
        if !play.finish() { failedFiling = .finish }
    }

    /// 保存 on a finished board: the same terminal commit, without the reset.
    /// The board keeps the result it is standing at, and the notice becomes the
    /// recorded one because the game it reads is now a History record.
    private func save() {
        if !play.save() { failedFiling = .save }
    }

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
                              companion: motion.transitCompanion,
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
                                     reason: game.presentedReason,
                                     // A filed game is a History record, and
                                     // the notice reads as one: the claimed
                                     // draw, whose claim was the commit, and
                                     // now the natural result the notice's own
                                     // 保存 has just filed without resetting
                                     // anything. Which is why this is asked of
                                     // the game rather than tracked here.
                                     recorded: game.filedRecordID != nil,
                                     save: { save() },
                                     startNewGame: { startNewGame() },
                                     finish: { finish() },
                                     replay: { if let record = game.filedRecordID { replay(record) } },
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
        // by timer is its own, below. Only the player's own ply raises it: a
        // refused AI reply shows nothing at all, because the retry is the
        // app's rather than the user's, which is why the game keeps the two
        // refusals apart.
        .onChange(of: game.failure) { _, failure in
            withAnimation(policy.fade(Motion.stateFadeAnimation)) {
                saveFailureShown = failure != nil
            }
        }
        // The blocking retry the contract gives a refused terminal commit —
        // one presentation for all of them, because it is one promise: the
        // current game is unchanged.
        .alert("alert.saveFailed.title",
               isPresented: Binding(get: { failedFiling != nil },
                                    set: { if !$0 { failedFiling = nil } })) {
            Button("control.cancel", role: .cancel) { }
            Button("control.tryAgain") { retryFiling(game, motion) }
        } message: {
            Text("alert.saveFailed.message")
        }
        // Issue #71's decision 2: the mid-game preparation failure keeps the
        // situation's name — memory is not available right now — and adds the
        // one guarantee the pre-start case has no need of. 稍后 leaves the
        // stalled state in the turn status's own activity slot, with the retry
        // beside it; every retry re-probes fresh.
        .alert("alert.aiUnavailable.title",
               isPresented: Binding(get: { play.opponent?.preparationFailure != nil },
                                    set: { if !$0 { play.opponent?.deferPreparation() } })) {
            Button("control.later", role: .cancel) { play.opponent?.deferPreparation() }
            Button("control.tryAgain") { play.opponent?.retryPreparation() }
        } message: {
            Text("alert.aiUnavailable.resumeMessage")
        }
    }

    private func retryFiling(_ game: Game, _ motion: PlayMotion) {
        switch failedFiling {
        case .claim: claimDraw(game, motion)
        case .resign: resign(game, motion)
        case .save: save()
        case .file: startNewGame()
        case .finish: finish()
        case nil: break
        }
    }

    /// The player confirmed the claim; committing it is the core's. A commit
    /// the store refused changed nothing, and says so through the retry.
    ///
    /// The claim is legal exactly when the core says it is, whatever the
    /// machine happens to be doing: if the state allows it, the search is
    /// cancelled before the terminal commit, because a search outstanding over
    /// a game that has just ended answers to nothing.
    private func claimDraw(_ game: Game, _ motion: PlayMotion) {
        play.opponent?.cancelSearch()
        motion.claimDraw()
        if game.filingFailure != nil { failedFiling = .claim }
    }

    /// 认输, confirmed. The terminal commit that records the loss against the
    /// player's own side, with the search stopped first for the same reason the
    /// claim stops it.
    private func resign(_ game: Game, _ motion: PlayMotion) {
        play.opponent?.cancelSearch()
        motion.resign()
        if game.filingFailure != nil { failedFiling = .resign }
    }

    /// 悔棋. In human-versus-AI play an Undo while the machine is thinking
    /// cancels the search and removes the human move that triggered it, and
    /// after a reply it removes the whole exchange — how many plies that is, is
    /// the core's answer, consumed rather than counted here.
    private func undo(_ motion: PlayMotion) {
        play.opponent?.cancelSearch()
        motion.undo()
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
                       reason: game.presentedReason,
                       sideToMove: game.evaluation.sideToMove,
                       inCheck: game.evaluation.inCheck,
                       controller: controller(of: game),
                       activity: play.opponent?.activity ?? .idle,
                       retry: { play.opponent?.retryPreparation() },
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
            // available. Issue #71's decision 1 settles that this holds in
            // human-versus-AI play too: a confirmation that presents itself
            // inverts the accepted announcement/confirmation grammar, so the
            // standing offer stays the enabled 判和 control and the status
            // line's 可判和 — one vocabulary across both modes.
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
            // 认输 ends the game against the player and cannot be undone, so it
            // is confirmed — a system alert, blocking until it is answered,
            // because the act itself does not happen until they answer.
            .alert("alert.resign.title", isPresented: $resignPresented) {
                Button("control.cancel", role: .cancel) { }
                Button("control.resign", role: .destructive) { resign(game, motion) }
            } message: {
                Text("alert.resign.message")
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

    /// Who owns the turn. Free Play has no answer and shows none: the same
    /// person controls both sides.
    private func controller(of game: Game) -> TurnStatus.Controller? {
        guard let humanSide = game.humanSide else { return nil }
        return game.evaluation.sideToMove == humanSide ? .you : .ai
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
    /// on the play screen means which side a piece belongs to.
    ///
    /// The accepted compositions, by mode. Human versus AI is 悔棋, 判和, 认输,
    /// and there is no board-flip control here: the orientation behaviour
    /// already puts the human's own side at the bottom, and moving one's own
    /// side to the top is disorienting rather than useful when the player
    /// controls one side. Free Play is 悔棋, 判和, 翻转棋盘 — it cannot resign,
    /// having no opponent to resign to.
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
            Button("control.undo") { undo(motion) }
                .buttonStyle(.glass)
                .disabled(!motion.canUndo)
                .accessibilityIdentifier("cluster-undo")

            if game.isFinished {
                // Prominent once it is the only one: while the notice stands in
                // front of the board it carries the moment's tinted action, and
                // the tint rule allows a single obvious next step rather than
                // two competing for the eye.
                concludingAction(prominent: play.resultDismissed)
            } else {
                Button("control.claimDraw") { claimPresented = true }
                    .buttonStyle(.glass)
                    .disabled(!game.evaluation.claimAvailable)
                    .accessibilityIdentifier("cluster-claim")
            }

            if game.isHumanVersusAI {
                Button("control.resign") { resignPresented = true }
                    .buttonStyle(.glass)
                    .disabled(!game.canResign)
                    .accessibilityIdentifier("cluster-resign")
            } else {
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
            }

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
