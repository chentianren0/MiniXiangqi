// `BoardLayout.shape(in:game:)` chooses between the side-by-side and stacked
// shapes; this screen only draws both. Every board input passes PlayMotion's
// gate, so input during a committing transition is discarded, not queued.

import SwiftUI

struct PlayScreen: View {
    /// Held above the navigation container, which rebuilds this screen every
    /// time the player comes back to it.
    let play: PlayState

    /// Performed by the container above, because the replay opens on another
    /// screen.
    var replay: (UUID) -> Void

    @State private var claimPresented = false
    @State private var resignPresented = false

    /// Transient: it answers the touch and withdraws by itself.
    @State private var saveFailureShown = false

    /// The refused terminal commit, held while the retry is up so Try Again
    /// repeats exactly the act that failed. The game stays unchanged underneath.
    private enum FailedFiling { case claim, resign, save, file, finish }
    @State private var failedFiling: FailedFiling?

    @State private var moveListShown = false

    @State private var capturedShown = false
    /// The captured sheet's own width, measured rather than read through a
    /// GeometryReader at the sheet's root: a reader there has no ideal size,
    /// and on macOS the sheet takes exactly its content's ideal. Zero until
    /// the first measurement, which the pitch fallback answers with the floor.
    @State private var capturedWidth: CGFloat = 0

    /// Measured: at an accessibility text size the status stands above the
    /// board and is taller than the shape rule's allowance. It starts at the
    /// allowance's share so the first frame is already the right size.
    @State private var statusHeight = BoardLayout.stackedChromeHeight / 2

    /// One cluster row; the reserved slot is two. A row rather than the
    /// cluster, because the board must not follow the cluster's own height.
    @State private var controlRow = BoardLayout.clusterRowHeight

    @Environment(\.motionPolicy) private var policy

    /// Decides where the turn status stands in the stacked shape.
    @Environment(\.dynamicTypeSize) private var typeSize

    #if os(iOS)
    /// See `hidesDestinationBar`.
    @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    var body: some View {
        Group {
            if let game = play.game, let motion = play.motion {
                layout(game, motion)
            } else {
                // The frame before the board has its game: a destination
                // rebuilt with the board as its page opens the session from
                // `.task`, a frame later.
                ProgressView()
            }
        }
        // A board screen hides a bottom tab bar. On the Group so the frame
        // before the game arrives is already without it, and a launch resume
        // never shows the bar appear and then leave.
        #if os(iOS)
        .toolbar(hidesDestinationBar(widthClass) ? .hidden : .automatic, for: .tabBar)
        #endif
    }

    /// The filing is the state's; this decides only what a refusal looks like
    /// on screen.
    private func startNewGame() {
        if !play.startNewGame() { failedFiling = .file }
    }

    /// 完成 on the recorded notice.
    private func finish() {
        if !play.finish() { failedFiling = .finish }
    }

    /// 保存 on a finished board: the same filing, without the reset.
    private func save() {
        if !play.save() { failedFiling = .save }
    }

    private func layout(_ game: Game, _ motion: PlayMotion) -> some View {
        GeometryReader { proxy in
            switch BoardLayout.shape(in: proxy.size, game: game.kind) {
            case .sideBySide: sideBySide(game, motion, in: proxy.size)
            case .stacked: stacked(game, motion, in: proxy.size)
            }
        }
        // The alerts belong to the screen rather than to one shape: the
        // controls that raise them sit in the panel in one shape and under the
        // board in the other.
        //
        // The claim confirmation presents only when the player invokes it, in
        // every mode. Its title and message are separate keys, never
        // recombined. Confirming goes through PlayMotion, so the claim's sound
        // sits beside the landings' sounds.
        .alert("alert.claimDraw.title", isPresented: $claimPresented) {
            Button("control.keepPlaying", role: .cancel) { }
            Button("control.endAsDraw") { claimDraw(game, motion) }
        } message: {
            Text("alert.claimDraw.message")
        }
        // 认输 cannot be undone, so it is confirmed.
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
        // Only the player's own ply raises the capsule: a refused AI reply
        // shows nothing, because its retry is the app's.
        .onChange(of: game.failure) { _, failure in
            withAnimation(policy.fade(Motion.stateFadeAnimation)) {
                saveFailureShown = failure != nil
            }
        }
        // One retry for every refused terminal commit; the game is unchanged.
        .alert("alert.saveFailed.title",
               isPresented: Binding(get: { failedFiling != nil },
                                    set: { if !$0 { failedFiling = nil } })) {
            Button("control.cancel", role: .cancel) { }
            Button("control.tryAgain") { retryFiling(game, motion) }
        } message: {
            Text("alert.saveFailed.message")
        }
        // 稍后 leaves the stalled state in the turn status's activity slot,
        // with the retry beside it; every retry re-probes fresh.
        .alert("alert.aiUnavailable.title",
               isPresented: Binding(get: { play.opponent?.preparationFailure != nil },
                                    set: { if !$0 { play.opponent?.deferPreparation() } })) {
            Button("control.later", role: .cancel) { play.opponent?.deferPreparation() }
            Button("control.tryAgain") { play.opponent?.retryPreparation() }
        } message: {
            Text("alert.aiUnavailable.resumeMessage")
        }
        // Only the memory failures take the AI-unavailable message: naming the
        // wrong cause for a damaged installation is worse than naming none. The
        // hint's own message names no opponent, since Free Play has none.
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
        // Announced rather than moving focus, so the board stays where the
        // reader had it; worded in the board's own point vocabulary.
        .onChange(of: motion.suggested) { _, destination in
            guard let destination else { return }
            // A board that places says the point and nothing else.
            guard !game.kind.isPlacement else {
                AccessibilityNotification
                    .Announcement(BoardView.hintAnnouncement(point: destination))
                    .post()
                return
            }
            guard let origin = game.selected, let piece = game.placement[origin],
                  let kind = piece.kind else { return }
            AccessibilityNotification
                .Announcement(BoardView.hintAnnouncement(game: game.kind,
                                                         side: piece.side, kind: kind,
                                                         from: origin,
                                                         to: destination))
                .post()
        }
        // On the screen rather than in the stacked branch: `moveListShown` is
        // the screen's state, so a sheet inside the branch would present again
        // whenever the layout came back to it, as on an iPad rotated and back.
        .sheet(isPresented: $moveListShown) { moveListSheet(game) }
        // In the stacked shape the captured pieces are reached rather than
        // resident, because the board's pitch floor comes first.
        .sheet(isPresented: $capturedShown) { capturedSheet(game) }
    }

    /// Drawn for the game's own viewer: nil in Free Play, where one person
    /// holds both hands, else the local side. Everything discloses at the end.
    private func captured(_ game: Game,
                          pitch: CGFloat = BoardLayout.capturedDiscPitch) -> some View {
        CapturedPiecesView(captured: game.captured,
                           game: game.kind,
                           throughPly: game.moves.count,
                           viewer: game.configuration.localSide,
                           disclosed: game.isFinished,
                           pitch: pitch)
    }

    /// Discs at the pitch a board of the sheet's width would carry, which on
    /// the phone is the board behind it.
    private func capturedSheet(_ game: Game) -> some View {
        NavigationStack {
            ScrollView {
                captured(game,
                         pitch: BoardLayout.capturedSheetPitch(in: capturedWidth,
                                                               game: game.kind))
                    .padding(.horizontal, BoardLayout.panelInset)
                    .padding(.vertical, 8)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                capturedWidth = $0
            }
            .navigationTitle("captured.title")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("control.done") { capturedShown = false }
                        .accessibilityIdentifier("captured-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - The two shapes

    /// Keeps the inline title; only the stacked shape spends the bar's centre
    /// on the turn status.
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

    /// The cluster's slot is reserved at its tallest arrangement and the board
    /// is sized around the reservation, so a cluster that wraps never moves the
    /// board under the thumb. The drawn arrangement is anchored at the slot's
    /// bottom, where a thumb last found it.
    ///
    /// The height is what the chrome is granted, not what it asks for; where
    /// the grant is short the cluster gives way. Nothing in the chrome depends
    /// on the board's size, so the two never read each other in a loop.
    ///
    /// At an accessibility text size the status returns above the board and the
    /// bar centre stays empty.
    private func stacked(_ game: Game, _ motion: PlayMotion, in size: CGSize) -> some View {
        let status = statusStandsInBar ? 0 : statusHeight
        let chrome = BoardLayout.stackedChrome(
            in: size, game: game.kind,
            asking: status + BoardLayout.stackedCluster(row: controlRow))
        return VStack(spacing: 0) {
            if !statusStandsInBar {
                turnStatus(game, motion, placement: .block)
                    .padding(.horizontal, BoardLayout.panelInset - 12)
                    .padding(.vertical, 8)
                    // Hung just beneath the turn status, as in the panel.
                    .overlay(alignment: .bottom) {
                        if saveFailureShown {
                            saveFailureCapsule
                                .alignmentGuide(.bottom) { $0[.top] }
                                .transition(.opacity)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { statusHeight = $0 }
            }

            board(game, motion, in: size, chrome: chrome)

            controlCluster(game, motion)
                .padding(.horizontal, BoardLayout.panelInset)
                .padding(.vertical, BoardLayout.clusterAir)
                .frame(height: max(0, chrome - status), alignment: .bottom)
        }
        // The row the reservation is two of, measured behind the whole layout,
        // where it costs nothing and cannot be reached.
        .background { BoardLayout.ClusterRow { controlRow = $0 } }
        .toolbar {
            // The status in the title's place, which a board page does not
            // spend on a name.
            if statusStandsInBar {
                ToolbarItem(placement: .principal) {
                    turnStatus(game, motion, placement: .bar)
                }
            }
            // Consulted occasionally, so reached rather than resident.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    moveListShown = true
                } label: {
                    Label("nav.moveList", systemImage: "list.number")
                }
                .accessibilityIdentifier("play-move-list")
            }
            if game.kind.conceals {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        capturedShown = true
                    } label: {
                        Label("captured.title", systemImage: "tray.full")
                    }
                    .accessibilityIdentifier("play-captured")
                }
            }
        }
    }

    /// At an accessibility text size the element is taller than a bar centre
    /// can hold, so it stands above the board.
    private var statusStandsInBar: Bool { !typeSize.isAccessibilitySize }

    /// The overlay sits outside the board's own tap area, so the retry is
    /// pressed rather than the board behind it.
    private func board(_ game: Game, _ motion: PlayMotion, in size: CGSize,
                       chrome: CGFloat) -> some View {
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

    /// Half height by default, because the other half is the board the list is
    /// consulted about.
    private func moveListSheet(_ game: Game) -> some View {
        NavigationStack {
            MoveList(notation: game.notation, firstMover: game.firstMover)
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

    private func boardBlock(_ game: Game, _ motion: PlayMotion,
                            _ geometry: BoardGeometry,
                            bleed: CGFloat = 0) -> some View {
        // The ending discloses the deal after the landing, as the notice and the
        // cluster wait for it: the ply that ended the game finishes being shown
        // first. By opacity, so Reduce Motion draws it the same.
        let disclosure: Double = game.disclosesTheDeal
            && showsFinishedScene(game, motion) ? 1 : 0
        return ZStack {
            BoardView(geometry: geometry,
                      placement: game.placement,
                      flipped: game.flipped,
                      selected: game.selected,
                      destinations: game.destinations,
                      captures: game.captures,
                      forbidden: game.forbiddenPoints,
                      suggested: motion.suggested,
                      lastMove: game.lastMove,
                      checkedGeneral: game.checkedGeneral,
                      transit: motion.transit,
                      companion: motion.transitCompanion,
                      transitFade: motion.transitFade,
                      transitReveal: motion.transitReveal,
                      disclosure: disclosure,
                      checkEmphasis: motion.checkEmphasis,
                      markerEmphasis: motion.markerEmphasis,
                      hintEmphasis: motion.hintEmphasis,
                      policy: motion.policy,
                      surfaceBleed: bleed,
                      onTap: { tap($0, in: game, motion) },
                      onTravelArrival: { motion.travelArrived() },
                      onFadeArrival: { motion.fadeArrived() },
                      onFlipArrival: { motion.flipArrived() })
                .boardHaptics(landings: motion.landings, refusals: motion.refusals)

            // Waits for the landing: the move that brought the result has to
            // finish being shown first.
            if game.isFinished, !play.resultDismissed, !motion.isCommitting {
                ResultNotice(game: game.kind,
                             state: game.presentedState,
                             reason: game.presentedReason,
                             // Asked of the game rather than tracked here: a
                             // claimed draw and a saved result are both filed.
                             recorded: game.filedRecordID != nil,
                             save: { save() },
                             startNewGame: { startNewGame() },
                             finish: { finish() },
                             replay: { if let record = game.filedRecordID { replay(record) } },
                             close: { withAnimation(policy.fade(Motion.stateFadeAnimation)) { play.resultDismissed = true } })
                    .transition(.opacity)
            }
        }
        // The board's own phases are driven by their transitions; this animates
        // the one value they do not.
        .animation(policy.fade(Motion.stateFadeAnimation), value: disclosure)
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

    /// A refused commit changed nothing and says so through the retry. The
    /// search is cancelled first: over a game that has just ended it answers to
    /// nothing.
    private func claimDraw(_ game: Game, _ motion: PlayMotion) {
        play.opponent?.cancelSearch()
        // Results that arrive with no piece moving are the ones no commit
        // cancels the hint for.
        play.hint?.cancel()
        motion.claimDraw()
        if game.filingFailure != nil { failedFiling = .claim }
    }

    /// 认输, confirmed. The search stops first, as for the claim.
    private func resign(_ game: Game, _ motion: PlayMotion) {
        play.opponent?.cancelSearch()
        play.hint?.cancel()
        motion.resign()
        if game.filingFailure != nil { failedFiling = .resign }
    }

    /// While the machine is thinking, Undo cancels the search and removes the
    /// human move; after a reply it removes the whole exchange. How many plies
    /// that is, is the core's answer.
    private func undo(_ motion: PlayMotion) {
        play.opponent?.cancelSearch()
        // Before the transition rather than at its commit: the suggestion goes
        // whether or not the core accepts the Undo.
        play.hint?.cancel()
        motion.undo()
    }

    /// Input during a committing transition is discarded, never queued. On a
    /// finished board a tap closes the result notice; that is an accepted
    /// input, so it gets no beat.
    private func tap(_ square: Square, in game: Game, _ motion: PlayMotion) {
        guard !motion.isCommitting else { return }
        if game.isFinished, !play.resultDismissed {
            withAnimation(policy.fade(Motion.stateFadeAnimation)) { play.resultDismissed = true }
            return
        }
        motion.tap(square)
    }

    /// The panel's sections begin on one edge, `BoardLayout.panelInset` from the
    /// panel's own. The status line's own background accounts for 12 of that, so
    /// its outer padding takes the rest.
    private func panel(_ game: Game, _ motion: PlayMotion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            turnStatus(game, motion, placement: .block)
                .padding(.horizontal, BoardLayout.panelInset - 12)
                .padding(.vertical, 8)

            // Beside the board, never over it: the board keeps its pitch floor
            // before this surface is given room.
            if game.kind.conceals {
                Divider()

                captured(game)
                    .padding(.horizontal, BoardLayout.panelInset)
                    .padding(.vertical, 8)
            }

            Divider()

            MoveList(notation: game.notation, firstMover: game.firstMover)
                .padding(.horizontal, BoardLayout.panelInset)
                .frame(maxHeight: .infinity)
                // Over the list rather than in it: feedback passing in front,
                // not a row of the record.
                .overlay(alignment: .top) {
                    if saveFailureShown {
                        saveFailureCapsule
                            .padding(.top, 6)
                            .transition(.opacity)
                    }
                }

            Divider()

            // Where the words leave no room, 翻转棋盘 drops beneath the others
            // first, and the row gives up all its words only where the wrap is
            // not enough.
            controlCluster(game, motion)
                .padding(BoardLayout.panelInset)
        }
        .frame(maxHeight: .infinity)
        // The material runs behind the title bar so the panel reads as one
        // surface; the sections keep their inset, clear of the title bar's
        // controls.
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

    /// The retry is passed only where the element draws the stalled slot
    /// itself; in the bar the slot hangs beneath, in `hungLines`.
    private func turnStatus(_ game: Game, _ motion: PlayMotion,
                            placement: TurnStatus.Placement) -> some View {
        TurnStatus(placement: placement,
                   game: game.kind,
                   state: game.presentedState,
                   reason: game.presentedReason,
                   sideToMove: game.evaluation.sideToMove,
                   inCheck: game.evaluation.inCheck,
                   controller: controller(of: game),
                   activity: play.opponent?.activity ?? .idle,
                   retry: placement == .block ? { play.opponent?.retryPreparation() } : nil,
                   beatEmphasis: motion.beatEmphasis)
    }

    /// Free Play shows none: the same person controls both sides.
    private func controller(of game: Game) -> TurnStatus.Controller? {
        guard let humanSide = game.humanSide else { return nil }
        return game.evaluation.sideToMove == humanSide ? .you : .ai
    }

    /// Present throughout the live scene, and greyed on the machine's turn and
    /// while a transition is committing.
    private func canHint(_ motion: PlayMotion) -> Bool {
        guard let hint = play.hint else { return false }
        return hint.isOffered && !motion.isCommitting
    }

    /// The nearby board raises the same capsule; when it goes up is this
    /// screen's.
    private var saveFailureCapsule: some View {
        SaveFailureCapsule { saveFailureShown = false }
    }

    /// The one custom glass surface during ordinary play, untinted because
    /// saturated colour on the play screen means a side. 提示 leads: it is the
    /// one control about the next move rather than the game around it.
    ///
    /// Absence says a capability is not there; disabling says it is momentarily
    /// impossible. The placement games have no 判和 (no repetition) and no
    /// 翻转棋盘 (a stone has no orientation). Inside a scene nothing comes or
    /// goes, so the row stays the same row under the thumb. A finished board
    /// puts the concluding action, the one tinted act, in the hint's slot.
    ///
    /// `worded` is the whole row's answer: no row mixes words and bare symbols.
    private func controls(_ game: Game, _ motion: PlayMotion,
                          worded: Bool, carriesFlip: Bool) -> some View {
        let finished = showsFinishedScene(game, motion)
        return HStack(spacing: 8) {
            // A game no engine plays has no `Hint`, so no 提示 at all: absence,
            // not a greyed promise.
            if !finished, play.hint != nil {
                hintControl(motion, worded: worded)
                    .transition(.opacity)
            }

            // Disabled until a running transition completes, its own Undo's
            // included, so a second Undo waits rather than queues.
            Button {
                undo(motion)
            } label: {
                clusterLabel("control.undo", "arrow.uturn.backward", worded: worded)
            }
            .buttonStyle(.glass)
            .disabled(!motion.canUndo)
            .accessibilityLabel(Text("control.undo"))
            .accessibilityIdentifier("cluster-undo")

            if finished {
                // Prominent only once the notice is dismissed: while the notice
                // stands, it carries the tinted action.
                concludingAction(prominent: play.resultDismissed)
                    .transition(.opacity)
            } else if !game.kind.isPlacement {
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

            if game.isHumanVersusAI, !finished {
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

            if carriesFlip, !game.kind.isPlacement {
                flipControl(motion, worded: worded)
            }
        }
    }

    /// The indicator stands in the symbol's place so the row keeps its width.
    /// To a screen reader the running search is the button's value.
    @ViewBuilder
    private func hintControl(_ motion: PlayMotion, worded: Bool) -> some View {
        let thinking = play.hint?.activity == .thinking
        let control = Button {
            play.hint?.request()
        } label: {
            hintLabel(thinking: thinking, worded: worded)
        }
        .buttonStyle(.glass)
        .disabled(!canHint(motion))
        .accessibilityLabel(Text("control.hint"))
        .accessibilityIdentifier("hint-request")
        // An empty value is a value all the same, so none while idle.
        if thinking {
            control.accessibilityValue(Text("status.hintThinking"))
        } else {
            control
        }
    }

    /// The lamp is laid out in both states, hidden under the indicator while
    /// thinking, so the control measures the same and the row's arrangement does
    /// not change when a search starts.
    @ViewBuilder
    private func hintLabel(thinking: Bool, worded: Bool) -> some View {
        let label = Label {
            Text("control.hint")
        } icon: {
            Image(systemName: "lightbulb")
                .opacity(thinking ? 0 : 1)
                .overlay {
                    if thinking {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityIdentifier("hint-thinking")
                    }
                }
        }
        if worded {
            label.lineLimit(1)
        } else {
            label.labelStyle(.iconOnly)
        }
    }

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

    /// In one place because both shapes carry the same cluster.
    ///
    /// The candidates in order: one row with every word, the same row wrapped
    /// with 翻转棋盘 beneath, one row of symbols, and that row wrapped. Words
    /// outrank one-rowness: a wrap costs height, a symbol costs the reader the
    /// name of the act. The candidates must differ in every composition, or
    /// `ViewThatFits` measures nothing and the cluster just overflows.
    ///
    /// Shared controls keep their identity across a scene change, so departing
    /// ones fade out and arriving ones fade in. Under Reduce Motion the two sets
    /// crossfade as wholes.
    @ViewBuilder
    private func controlCluster(_ game: Game, _ motion: PlayMotion) -> some View {
        let finished = showsFinishedScene(game, motion)
        // All but the last arrangement are drawn at their own width. An
        // `HStack` proposes shares of its width rather than what each child
        // asks for, and does not iterate, so the last control can be truncated
        // while the row still has room.
        //
        // The last arrangement is left compressible on purpose: drawn when
        // nothing fits (an accessibility text size, mainly), it must not run
        // past the edge of the screen.
        let arrangements = ViewThatFits(in: .horizontal) {
            atItsOwnWidth(controls(game, motion, worded: true, carriesFlip: true))
            atItsOwnWidth(wrappedControls(game, motion, worded: true))
            atItsOwnWidth(controls(game, motion, worded: false, carriesFlip: true))
            wrappedControls(game, motion, worded: false)
        }
        // Placed at the leading edge from outside rather than by a spacer,
        // which would be one more child to divide the width among.
        .frame(maxWidth: .infinity, alignment: .leading)
        if policy.reduceMotion {
            arrangements
                .id(finished)
                .animation(policy.crossfade, value: finished)
        } else {
            arrangements
                .animation(Motion.stateFadeAnimation, value: finished)
        }
    }

    /// The row is fixed, not the labels: a fixed label could not give way in
    /// the arrangement drawn when nothing fits.
    private func atItsOwnWidth(_ row: some View) -> some View {
        row.fixedSize(horizontal: true, vertical: false)
    }

    /// Waits for the landing, as the result notice does, so the cluster does not
    /// swap ahead of the move that ended the game. A claim or a resignation has
    /// no travel, and swaps the moment it is confirmed.
    private func showsFinishedScene(_ game: Game, _ motion: PlayMotion) -> Bool {
        game.isFinished && !motion.isCommitting
    }

    /// The play controls above, 翻转棋盘 beneath with its word: the row it
    /// arrives on has the whole width.
    private func wrappedControls(_ game: Game, _ motion: PlayMotion,
                                 worded: Bool) -> some View {
        VStack(alignment: .leading, spacing: BoardLayout.clusterAir) {
            controls(game, motion, worded: worded, carriesFlip: false)
            // A cluster with no 翻转棋盘 has nothing to wrap.
            if !game.kind.isPlacement { flipControl(motion, worded: true) }
        }
    }

    /// The word is the accessibility label either way, set by each control. One
    /// line, so a control never makes its row taller than the arrangement it
    /// was chosen as.
    @ViewBuilder
    private func clusterLabel(_ key: LocalizedStringKey, _ symbol: String,
                              worded: Bool) -> some View {
        if worded {
            Label(key, systemImage: symbol).lineLimit(1)
        } else {
            Label(key, systemImage: symbol).labelStyle(.iconOnly)
        }
    }

    /// Its word alone in every arrangement: the moment's single tinted act.
    @ViewBuilder
    private func concludingAction(prominent: Bool) -> some View {
        let action = Button("control.newGame") { startNewGame() }
            .lineLimit(1)
            .accessibilityIdentifier("cluster-new-game")
        if prominent {
            action.buttonStyle(.glassProminent)
        } else {
            action.buttonStyle(.glass)
        }
    }

}
