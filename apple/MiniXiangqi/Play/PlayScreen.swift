// The play screen.
//
// docs/interaction-design.md, "Layout shapes": two arrangements, chosen by the
// available space rather than by device identity. **Side by side** — the board
// on one side, with a panel beside it carrying the turn status, the move list,
// and controls that do not need to sit under the thumb — is what ordinary Mac
// windows and a landscape iPad take. **Stacked** — the turn status in the bar's
// centre, the play controls below the board, and the board fitted to the full
// width in the height between them — is what an iPhone and a portrait iPad
// take, and what a Mac window narrow enough for the panel to cost the board
// more than it returns takes too. `BoardLayout.shape(in:game:)` is the rule;
// this screen only draws both answers.
//
// In the stacked shape the move list is reached on demand rather than shown by
// default, so neither the board nor the controls give up space to something
// consulted occasionally. What reaches it is a toolbar item over a sheet: a
// sheet is the surface the contract already allows to cover the board, because
// the player asked for it and the player dismisses it.
//
// The selected game's square or tall board is sized to the largest instance of
// its own aspect ratio fitting both the available width and the height left
// after the chrome. Mini Xiangqi uses its 44-point pitch floor and Xiangqi its
// 34-point floor; both stop at the same approximate maximum-width footprint.
// Surplus space goes to the layout rather than to the board. When space is short
// the chrome tightens first, and the window stops resizing where either would go
// below its floor.
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

    /// Whether the stacked shape's on-demand move list is up.
    @State private var moveListShown = false

    /// What the stacked shape's chrome actually came to, measured rather than
    /// assumed: the controls below the board, and the status above it at an
    /// accessibility text size, where the bar cannot hold it and it is taller
    /// than the allowance the shape rule spends. They start at the allowance so
    /// the first frame is already the right size.
    @State private var statusHeight = BoardLayout.stackedChromeHeight / 2
    @State private var controlsHeight = BoardLayout.stackedChromeHeight / 2

    @Environment(\.motionPolicy) private var policy

    /// Whether the reader is at one of the accessibility text sizes, which is
    /// what decides where the turn status stands in the stacked shape.
    @Environment(\.dynamicTypeSize) private var typeSize

    #if os(iOS)
    /// Whether the navigation container is presenting as a bar across the
    /// bottom, which is what the rule below is about. See `hidesDestinationBar`.
    @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    var body: some View {
        Group {
            if let game = play.game, let motion = play.motion {
                layout(game, motion)
            } else {
                // The frame before the board has its game. 回到对局 opens the
                // session inside the same turn that sets the page, so that
                // path never draws this; a destination rebuilt with the board
                // as its page opens the session from `.task`, which is a frame
                // later, and this is that frame.
                ProgressView()
            }
        }
        // docs/interaction-design.md, "Navigation": a board screen hides the
        // destination bar where that bar is a bar across the bottom. It is on
        // the Group rather than on the layout so that the frame before the game
        // arrives is already without it, and a board opening from a launch
        // resume never shows the bar appearing and then leaving.
        #if os(iOS)
        .toolbar(hidesDestinationBar(widthClass) ? .hidden : .automatic, for: .tabBar)
        #endif
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
            switch BoardLayout.shape(in: proxy.size, game: game.kind) {
            case .sideBySide: sideBySide(game, motion, in: proxy.size)
            case .stacked: stacked(game, motion, in: proxy.size)
            }
        }
        // The two confirmations belong to the screen rather than to one of its
        // shapes: the controls that raise them are in the panel in one shape
        // and under the board in the other, and an alert declared inside either
        // would be an alert the other shape does not have.
        //
        // The blocking notice the contract gives the claim, presented when
        // the player invokes it rather than the moment it becomes available.
        // Issue #71's decision 1 settles that this holds in human-versus-AI
        // play too: a confirmation that presents itself inverts the accepted
        // announcement/confirmation grammar, so the standing offer stays the
        // enabled 判和 control and the status line's 可判和 — one vocabulary
        // across both modes.
        //
        // The accepted sentence is one sentence and stays one, but it is said
        // in the two roles an alert has: what has happened is the title, and
        // what can be done about it is the message. The halves are separate
        // keys and are never recombined into a single title.
        //
        // Confirming goes through PlayMotion, as everything that changes the
        // game does: the claim is the one result that arrives with no piece
        // moving, and the sound a result makes belongs beside the ones the
        // landings make rather than in a button here.
        .alert("alert.claimDraw.title", isPresented: $claimPresented) {
            Button("control.keepPlaying", role: .cancel) { }
            Button("control.endAsDraw") { claimDraw(game, motion) }
        } message: {
            Text("alert.claimDraw.message")
        }
        // 认输 ends the game against the player and cannot be undone, so it is
        // confirmed — a system alert, blocking until it is answered, because
        // the act itself does not happen until they answer.
        .alert("alert.resign.title", isPresented: $resignPresented) {
            Button("control.cancel", role: .cancel) { }
            Button("control.resign", role: .destructive) { resign(game, motion) }
        } message: {
            Text("alert.resign.message")
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
        // A hint the engine could not be prepared for. The situation's own
        // name, because the reader asked for a hint rather than for an
        // opponent — Free Play has none to fail to start — over the same
        // message the pre-start notice carries and the same 取消 / 重试, every
        // retry re-probing fresh. Only the memory failures take that message:
        // a damaged installation is a different situation, and naming the wrong
        // cause is worse than naming none. What it takes instead is the hint's
        // own body, which names neither the cause nor an opponent: the AI's
        // stalled line belongs to the AI's own slot, and a Free Play game that
        // asked for a hint has no opponent for a notice to speak about.
        .alert("alert.hintUnavailable.title",
               isPresented: Binding(get: { play.hint?.preparationFailure != nil },
                                    set: { if !$0 { play.hint?.dismissPreparationFailure() } })) {
            Button("control.cancel", role: .cancel) { play.hint?.dismissPreparationFailure() }
            Button("control.tryAgain") { play.hint?.retryPreparation() }
        } message: {
            Text(play.hint?.preparationFailureNamesMemory ?? true
                 ? LocalizedStringKey("alert.aiUnavailable.message")
                 : LocalizedStringKey("alert.hintUnavailable.message"))
        }
        // The suggestion, announced as it appears — composed from the board's
        // own point vocabulary, so a reader who cannot see the strengthened
        // marker hears the same fact in the same words the points are described
        // in. It is an announcement rather than a focus move: the board stays
        // exactly where the reader had it, and the suggested point carries its
        // own **建议** token for whoever navigates to it.
        .onChange(of: motion.suggested) { _, destination in
            guard let destination, let origin = game.selected,
                  let piece = game.placement[origin] else { return }
            AccessibilityNotification
                .Announcement(BoardView.hintAnnouncement(piece: piece, from: origin,
                                                         to: destination))
                .post()
        }
        // The move list's sheet belongs to the screen for the same reason the
        // alerts do, and for one more: `moveListShown` is the screen's state,
        // so a sheet declared inside the stacked branch alone is a sheet that
        // is re-presented every time the layout comes back to that branch. An
        // iPad opened to the list, rotated to landscape and rotated back would
        // find it up again, in a shape whose toolbar has nothing to raise it
        // and nothing to say it should be there.
        .sheet(isPresented: $moveListShown) { moveListSheet(game) }
    }

    // MARK: - The two shapes

    /// The board on one side, the panel beside it.
    ///
    /// This shape's board page is a page like any other and carries the inline
    /// title beside the control that walks back out. Only the stacked shape
    /// spends the bar's centre on the turn status instead.
    private func sideBySide(_ game: Game, _ motion: PlayMotion, in size: CGSize) -> some View {
        HStack(spacing: 0) {
            boardBlock(game, motion, BoardLayout.geometry(in: size, game: game.kind))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Tapping outside the board cancels the selection.
                .contentShape(Rectangle())
                .onTapGesture { motion.cancelSelection() }

            panel(game, motion)
                .frame(width: BoardLayout.panelWidth)
        }
        .navigationTitle("nav.play")
    }

    /// The turn status in the bar's centre, the play controls below the board,
    /// and the board fitted to the full width in the height between them.
    ///
    /// The chrome's height is measured and handed to the geometry rather than
    /// assumed, so the board is sized around what the chrome actually came to.
    /// Nothing in it depends on the board's size, so there is no loop in the
    /// two reading each other.
    ///
    /// At an accessibility text size the element returns to its place above the
    /// board — the bar cannot hold it there — and the bar centre stays empty,
    /// because a page over a board still needs no name.
    private func stacked(_ game: Game, _ motion: PlayMotion, in size: CGSize) -> some View {
        VStack(spacing: 0) {
            if !statusStandsInBar {
                turnStatus(game, motion, placement: .block)
                    .padding(.horizontal, BoardLayout.panelInset - 12)
                    .padding(.vertical, 8)
                    // The capsule the contract anchors to the turn status, hung
                    // just beneath the element it answers for — the same place
                    // it hangs in the panel, where the move list is what it
                    // passes in front of. Here there is no list to pass in
                    // front of, so it passes in front of the air above the
                    // board.
                    .overlay(alignment: .bottom) {
                        if saveFailureShown {
                            saveFailureCapsule
                                .alignmentGuide(.bottom) { $0[.top] }
                                .transition(.opacity)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { statusHeight = $0 }
            }

            board(game, motion, in: size)

            controlCluster(game, motion)
                .padding(.horizontal, BoardLayout.panelInset)
                .padding(.vertical, 8)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { controlsHeight = $0 }
        }
        .toolbar {
            // The status in the title's place, which a board page does not
            // spend on a name.
            if statusStandsInBar {
                ToolbarItem(placement: .principal) {
                    turnStatus(game, motion, placement: .bar)
                }
            }
            // The list is consulted occasionally, so it is reached rather than
            // resident — from the same toolbar the page's own back control is
            // in.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    moveListShown = true
                } label: {
                    Label("nav.moveList", systemImage: "list.number")
                }
                .accessibilityIdentifier("play-move-list")
            }
        }
    }

    /// Whether the turn status is in the bar rather than above the board. At an
    /// accessibility text size it is not: the element is then taller than a bar
    /// centre, and the contract puts it back where it can be that tall.
    private var statusStandsInBar: Bool { !typeSize.isAccessibilitySize }

    /// The board in the stacked shape, with the lines the bar cannot hold in
    /// front of the air above it.
    ///
    /// They hang exactly where they hang beneath the status block: the
    /// save-failure capsule, and the stalled slot with the retry that answers
    /// it. The overlay is applied outside the board's own tap area so that the
    /// retry is pressed rather than the board behind it.
    private func board(_ game: Game, _ motion: PlayMotion, in size: CGSize) -> some View {
        let chrome = (statusStandsInBar ? 0 : statusHeight) + controlsHeight
        let geometry = BoardLayout.stackedGeometry(in: size, game: game.kind, chrome: chrome)
        return boardBlock(game, motion, geometry,
                          bleed: BoardLayout.surfaceBleed(in: size.width, board: geometry))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { motion.cancelSelection() }
            .overlay(alignment: .top) {
                if statusStandsInBar { hungLines }
            }
    }

    /// What hangs just beneath the bar, in front of the air above the board.
    @ViewBuilder
    private var hungLines: some View {
        VStack(spacing: 6) {
            if play.opponent?.activity == .stalled {
                TurnStatus.StalledSlot { play.opponent?.retryPreparation() }
                    .padding(.horizontal, BoardLayout.panelInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if saveFailureShown {
                saveFailureCapsule
                    .transition(.opacity)
            }
        }
        .padding(.top, 6)
    }

    /// The on-demand move list, on the surface the contract already allows to
    /// cover the board: a sheet the player asked for and the player dismisses.
    /// Half height by default, because half of it is the board they are
    /// consulting the list about.
    private func moveListSheet(_ game: Game) -> some View {
        NavigationStack {
            MoveList(notation: game.notation)
                .padding(.horizontal, BoardLayout.panelInset)
                .navigationTitle("nav.moveList")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("control.done") { moveListShown = false }
                            .accessibilityIdentifier("move-list-done")
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    /// The board, and the notice that stands in front of it. One block, drawn
    /// the same way in both shapes: what differs between them is the size it is
    /// given and what surrounds it.
    private func boardBlock(_ game: Game, _ motion: PlayMotion,
                            _ geometry: BoardGeometry,
                            bleed: CGFloat = 0) -> some View {
        ZStack {
            BoardView(geometry: geometry,
                      placement: game.placement,
                      flipped: game.flipped,
                      showsNumerals: Self.showsNumerals,
                      selected: game.selected,
                      destinations: game.destinations,
                      captures: game.captures,
                      suggested: motion.suggested,
                      lastMove: game.lastMove,
                      checkedGeneral: game.checkedGeneral,
                      transit: motion.transit,
                      companion: motion.transitCompanion,
                      transitFade: motion.transitFade,
                      checkEmphasis: motion.checkEmphasis,
                      markerEmphasis: motion.markerEmphasis,
                      hintEmphasis: motion.hintEmphasis,
                      policy: motion.policy,
                      surfaceBleed: bleed,
                      onTap: { tap($0, in: game, motion) },
                      onTravelArrival: { motion.travelArrived() },
                      onFadeArrival: { motion.fadeArrived() },
                      onFlipArrival: { motion.flipArrived() })

            // The notice waits for the landing: a result arrives with a move,
            // and the move has to finish being shown before an announcement
            // stands in front of it.
            if game.isFinished, !play.resultDismissed, !motion.isCommitting {
                ResultNotice(state: game.presentedState,
                             reason: game.presentedReason,
                             // A filed game is a History record, and the notice
                             // reads as one: the claimed draw, whose claim was
                             // the commit, and now the natural result the
                             // notice's own 保存 has just filed without
                             // resetting anything. Which is why this is asked of
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
        // A hint outstanding over a game that has just ended answers to nothing
        // either, and the two results that arrive with no piece moving are the
        // ones no commit cancels for them.
        play.hint?.cancel()
        motion.claimDraw()
        if game.filingFailure != nil { failedFiling = .claim }
    }

    /// 认输, confirmed. The terminal commit that records the loss against the
    /// player's own side, with the search stopped first for the same reason the
    /// claim stops it.
    private func resign(_ game: Game, _ motion: PlayMotion) {
        play.opponent?.cancelSearch()
        play.hint?.cancel()
        motion.resign()
        if game.filingFailure != nil { failedFiling = .resign }
    }

    /// 悔棋. In human-versus-AI play an Undo while the machine is thinking
    /// cancels the search and removes the human move that triggered it, and
    /// after a reply it removes the whole exchange — how many plies that is, is
    /// the core's answer, consumed rather than counted here.
    private func undo(_ motion: PlayMotion) {
        play.opponent?.cancelSearch()
        // Before the transition rather than at its commit: an Undo is asked for
        // while a hint may be on the board about the position it is taking
        // away, and the suggestion goes with it whether or not the core accepts
        // the Undo.
        play.hint?.cancel()
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
            turnStatus(game, motion, placement: .block)
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

            // Where the row fits at full width it keeps it; where the words
            // leave no room — every cluster state in English at the minimum
            // window — 翻转棋盘 drops beneath the others first, and the row
            // gives up all of its words together only where the wrap was not
            // enough. Every arrangement carries the same accessibility labels.
            controlCluster(game, motion)
                .padding(BoardLayout.panelInset)
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

    /// The turn status, wherever this shape stands it. One call for the two
    /// places, because the element is the same element: what the placement
    /// decides is the room it has, not what it says.
    ///
    /// The retry is passed only where the element draws the stalled slot
    /// itself. In the bar the slot hangs beneath, with `hungLines`.
    private func turnStatus(_ game: Game, _ motion: PlayMotion,
                            placement: TurnStatus.Placement) -> some View {
        TurnStatus(placement: placement,
                   state: game.presentedState,
                   reason: game.presentedReason,
                   sideToMove: game.evaluation.sideToMove,
                   inCheck: game.evaluation.inCheck,
                   controller: controller(of: game),
                   activity: play.opponent?.activity ?? .idle,
                   retry: placement == .block ? { play.opponent?.retryPreparation() } : nil,
                   beatEmphasis: motion.beatEmphasis)
    }

    /// Who owns the turn. Free Play has no answer and shows none: the same
    /// person controls both sides.
    private func controller(of game: Game) -> TurnStatus.Controller? {
        guard let humanSide = game.humanSide else { return nil }
        return game.evaluation.sideToMove == humanSide ? .you : .ai
    }

    /// Whether 提示 can be pressed right now.
    ///
    /// The control is present throughout the live scene and greys where a hint
    /// is not possible: on the machine's turn, and while a transition is
    /// committing — a suggestion about a position the board is still leaving is
    /// a suggestion about nothing. What "possible" means is the game's own
    /// answer rather than a second derivation of the mode and the side to move.
    private func canHint(_ motion: PlayMotion) -> Bool {
        guard let hint = play.hint else { return false }
        return hint.isOffered && !motion.isCommitting
    }

    /// The transient save-failure capsule, which the nearby board raises too:
    /// the shape is shared, and what is this screen's is when it goes up.
    private var saveFailureCapsule: some View {
        SaveFailureCapsule { saveFailureShown = false }
    }

    /// The play control cluster: the one custom glass surface on screen during
    /// ordinary play. It carries no tint during play, because saturated colour
    /// on the play screen means which side a piece belongs to.
    ///
    /// The accepted compositions, by mode. Human versus AI is 提示, 悔棋, 判和,
    /// 认输 and 翻转棋盘; Free Play is 提示, 悔棋, 判和, 翻转棋盘 — it cannot
    /// resign, having no opponent to resign to. 提示 leads because it is the one
    /// control about the next move rather than about the game around it.
    ///
    /// **The cluster is a scene's fixed set, and inside a scene nothing comes or
    /// goes.** A control whose act is momentarily impossible is disabled where
    /// it stands: 提示 greys through the machine's turn, 判和 until a claim
    /// stands, 悔棋 while a transition runs. A greyed control is a promise the
    /// scene keeps — it will be pressable again without anything moving — where
    /// a control that leaves and returns makes the row a different row each time
    /// a thumb reaches for it.
    ///
    /// A finished board is a scene of its own: no draw left to judge and no hint
    /// left to ask, so that slot carries the concluding action instead — the one
    /// obvious next action, and therefore the one thing on screen the tint rule
    /// allows — and 认输 goes with the game it could have ended. The finished
    /// cluster is 悔棋, the concluding action and 翻转棋盘 in both modes.
    ///
    /// Each control carries one symbol and an identifier beside its label. A
    /// label is copy and changes with the interface language; an identifier does
    /// not, so it is what a test addresses a control by. The concluding action
    /// is the one control that is its word alone, in every arrangement: it is
    /// the moment's single tinted act, and a word is what a moment like that
    /// gets.
    ///
    /// `worded` is the row's answer to the width it was given, and it is the
    /// whole row's: where the words fit every control carries one, and where
    /// they do not every control gives up its word at once and stands as its
    /// symbol, with the word as its accessibility label either way. No row mixes
    /// the two forms.
    private func controls(_ game: Game, _ motion: PlayMotion,
                          worded: Bool, carriesFlip: Bool) -> some View {
        HStack(spacing: 8) {
            if !game.isFinished {
                hintControl(motion, worded: worded)
                    .transition(.opacity)
            }

            // Unavailable until a running transition completes — its own
            // Undo's included, which is what makes a second Undo wait its
            // turn rather than queue.
            Button {
                undo(motion)
            } label: {
                clusterLabel("control.undo", "arrow.uturn.backward", worded: worded)
            }
            .buttonStyle(.glass)
            .disabled(!motion.canUndo)
            .accessibilityLabel(Text("control.undo"))
            .accessibilityIdentifier("cluster-undo")

            if game.isFinished {
                // Prominent once it is the only one: while the notice stands in
                // front of the board it carries the moment's tinted action, and
                // the tint rule allows a single obvious next step rather than
                // two competing for the eye.
                concludingAction(prominent: play.resultDismissed)
                    .transition(.opacity)
            } else {
                Button {
                    claimPresented = true
                } label: {
                    clusterLabel("control.claimDraw", "equal", worded: worded)
                }
                .buttonStyle(.glass)
                .disabled(!game.evaluation.claimAvailable)
                .accessibilityLabel(Text("control.claimDraw"))
                .accessibilityIdentifier("cluster-claim")
                .transition(.opacity)
            }

            if game.isHumanVersusAI, !game.isFinished {
                // 认输 ends the game and cannot be undone, so the symbol is the
                // one every board game uses for it, and the alert still stands
                // between the control and the act.
                Button {
                    resignPresented = true
                } label: {
                    clusterLabel("control.resign", "flag.fill", worded: worded)
                }
                .buttonStyle(.glass)
                .disabled(!game.canResign)
                .accessibilityLabel(Text("control.resign"))
                .accessibilityIdentifier("cluster-resign")
                .transition(.opacity)
            }

            if carriesFlip { flipControl(motion, worded: worded) }

            Spacer(minLength: 0)
        }
    }

    /// 提示, and the activity a hint search shows once it has run long enough to
    /// be worth showing — the AI activity slot's own threshold, for the AI
    /// activity slot's own reason.
    ///
    /// The indicator stands in the symbol's own place rather than beside the
    /// control, so the row does not change width while a search runs. To a
    /// screen reader the button is one element and keeps its word; that a search
    /// is running is its value, which is where a state that is not the control's
    /// name belongs.
    private func hintControl(_ motion: PlayMotion, worded: Bool) -> some View {
        let thinking = play.hint?.activity == .thinking
        return Button {
            play.hint?.request()
        } label: {
            hintLabel(thinking: thinking, worded: worded)
        }
        .buttonStyle(.glass)
        .disabled(!canHint(motion))
        .accessibilityLabel(Text("control.hint"))
        .accessibilityValue(thinking ? Text("status.hintThinking") : Text(verbatim: ""))
        .accessibilityIdentifier("hint-request")
    }

    /// The lamp, or the indicator standing in its place, and the word beside
    /// either where the row carries words.
    @ViewBuilder
    private func hintLabel(thinking: Bool, worded: Bool) -> some View {
        let label = Label {
            Text("control.hint")
        } icon: {
            if thinking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("hint-thinking")
            } else {
                Image(systemName: "lightbulb")
            }
        }
        if worded {
            label
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            label.labelStyle(.iconOnly)
        }
    }

    /// 翻转棋盘. One control, one key, one identifier, in both modes and in
    /// either arrangement below — which is what makes the mode it is in
    /// invisible to a test, to a screen reader, and to the person pressing it.
    private func flipControl(_ motion: PlayMotion, worded: Bool) -> some View {
        Button {
            motion.flip()
        } label: {
            clusterLabel("control.flipBoard", "arrow.up.arrow.down", worded: worded)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(Text("control.flipBoard"))
        .accessibilityIdentifier("cluster-flip")
    }

    /// The cluster at whichever of its arrangements fits, in one place because
    /// both shapes carry the same cluster: the panel puts it under the move
    /// list, the stacked shape puts it under the board, and neither of them
    /// decides what is in it.
    ///
    /// The candidates in order: one row with every word, the same row wrapped
    /// with 翻转棋盘 beneath, one row of symbols, and that row wrapped. Words
    /// outrank one-rowness — a wrap costs a line of height the stacked shape has
    /// and the panel is glad to spend, where a symbol costs the reader the name
    /// of the act — and the second row keeps its word either way, because the
    /// row it arrives on has the whole width. Uniformity is a row's rule rather
    /// than an arrangement's, which is what replay's cluster already reads as:
    /// its five symbols over one worded 翻转棋盘.
    ///
    /// The candidates differ in every composition the cluster has — both modes,
    /// and a finished board as well as a running one — which is what makes the
    /// fallback worth measuring. Two candidates that rendered the same would
    /// leave `ViewThatFits` measuring nothing and the cluster simply
    /// overflowing wherever it did not fit.
    ///
    /// **A scene change is one drawn transition.** The controls the two scenes
    /// share hold their identity and their places, departing controls fade as
    /// their width closes, and arriving ones fade in — which is what the
    /// structure above buys, each scene's own members being what comes and goes
    /// around them. It rides whatever changed the scene: the landing of a move
    /// that finished the game, or the moment a claim or a resignation is
    /// confirmed, which lands nothing and is drawn all the same. Under Reduce
    /// Motion the two sets crossfade as wholes instead, nothing sliding and
    /// nothing collapsing.
    @ViewBuilder
    private func controlCluster(_ game: Game, _ motion: PlayMotion) -> some View {
        let arrangements = ViewThatFits(in: .horizontal) {
            controls(game, motion, worded: true, carriesFlip: true)
            wrappedControls(game, motion, worded: true)
            controls(game, motion, worded: false, carriesFlip: true)
            wrappedControls(game, motion, worded: false)
        }
        if policy.reduceMotion {
            arrangements
                .id(game.isFinished)
                .animation(policy.crossfade, value: game.isFinished)
        } else {
            arrangements
                .animation(Motion.stateFadeAnimation, value: game.isFinished)
        }
    }

    /// The cluster over two rows: the play controls above, 翻转棋盘 beneath with
    /// its word intact — the row it left is what was short of width, and the
    /// row it arrives on has the whole of it.
    private func wrappedControls(_ game: Game, _ motion: PlayMotion,
                                 worded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            controls(game, motion, worded: worded, carriesFlip: false)
            HStack(spacing: 8) {
                flipControl(motion, worded: true)
                Spacer(minLength: 0)
            }
        }
    }

    /// A cluster control's label: its symbol and its word, or its symbol alone
    /// where the row has given the words up. The word is the accessibility label
    /// either way, which each control states for itself.
    ///
    /// **A word is drawn whole or not at all**, which is what makes the
    /// arrangement the answer to a narrow row rather than the control. Left
    /// free to compress, a label wraps over two lines or truncates and the row
    /// reports that it fits — so `ViewThatFits` would never reach the
    /// arrangement that actually holds the cluster. Fixed at its own width the
    /// row asks for what the words need, and a row that cannot have it is the
    /// row that is passed over.
    @ViewBuilder
    private func clusterLabel(_ key: LocalizedStringKey, _ symbol: String,
                              worded: Bool) -> some View {
        if worded {
            Label(key, systemImage: symbol)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Label(key, systemImage: symbol).labelStyle(.iconOnly)
        }
    }

    /// The concluding action, which is the one control that is its word alone —
    /// in every arrangement, symbol-only rows included. It is the moment's
    /// single tinted act, and a word is what a moment like that gets.
    @ViewBuilder
    private func concludingAction(prominent: Bool) -> some View {
        let action = Button("control.newGame") { startNewGame() }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("cluster-new-game")
        if prominent {
            action.buttonStyle(.glassProminent)
        } else {
            action.buttonStyle(.glass)
        }
    }

}
