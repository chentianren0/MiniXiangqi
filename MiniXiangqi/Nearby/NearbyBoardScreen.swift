// The networked board: the game two people are playing, on the board the app
// already has. It is the local game's screen in every visible respect and
// differs where the game does: the turn is the engine's, the opponent is a
// person, and the controls are the offers of whoever's turn it is.
//
// There is no connection chrome; one quiet line appears where the link is
// costing the player something. A game that goes away without a result says
// why in the notice a result is announced in.

import SwiftUI

struct NearbyBoardScreen: View {
    let flow: NearbyFlow

    /// The board's own model, built for the game the flow is showing.
    @State private var play: NearbyPlay?
    @State private var resignPresented = false
    @State private var claimPresented = false

    /// Whether the stacked shape's on-demand captured-pieces surface is up.
    @State private var capturedShown = false
    /// The captured sheet's own width; on macOS the measurement is what keeps
    /// a sheet sized.
    @State private var capturedWidth: CGFloat = 0

    /// The stacked shape's chrome: the status above the board measured, and
    /// the cluster below it reserved at its tallest arrangement.
    @State private var statusHeight = BoardLayout.stackedChromeHeight / 2
    @State private var controlRow = BoardLayout.clusterRowHeight

    @Environment(\.motionPolicy) private var policy

    #if os(iOS)
    /// Whether the navigation container presents as a bar across the bottom.
    @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    /// Whether the reader is at one of the accessibility text sizes, which is
    /// what decides where the turn status stands in the stacked shape.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if let play {
                layout(play)
            } else {
                // The modifiers below need a view to hang on: on an empty
                // group `.task(id:)` never runs, so the model is never built.
                Color.clear
            }
        }
        // A board screen hides the destination bar where it stands across the
        // bottom; on macOS the container is a sidebar.
        #if os(iOS)
        .toolbar(hidesDestinationBar(widthClass) ? .hidden : .automatic, for: .tabBar)
        #endif
        .task(id: flow.boardGameID) { open() }
        .onChange(of: flow.boardGame) { _, game in
            guard let game else { return }
            guard let play else { return open() }
            play.sync(with: game)
        }
        .onChange(of: policy) { play?.policy = policy }
        // The model is rebuilt on every entry, so the flow remembers which way
        // the player last turned the board.
        .onChange(of: play?.flipped) { _, flipped in
            guard let flipped, let game = flow.boardGameID else { return }
            flow.setOrientation(flipped, of: game)
        }
        .onDisappear { play?.close() }
    }

    private func open() {
        play?.close()
        play = flow.boardGame.flatMap {
            NearbyPlay(game: $0, engine: flow.engine, positions: flow.positions,
                       interruption: flow.carrier.interruption,
                       flipped: flow.orientation(of: $0.id), policy: policy)
        }
    }

    private func layout(_ play: NearbyPlay) -> some View {
        GeometryReader { proxy in
            switch BoardLayout.shape(in: proxy.size, game: play.game) {
            case .sideBySide: sideBySide(play, in: proxy.size)
            case .stacked: stacked(play, in: proxy.size)
            }
        }
        .alert("alert.resign.title", isPresented: $resignPresented) {
            Button("control.cancel", role: .cancel) { }
            Button("control.resign", role: .destructive) { play.resign() }
        } message: {
            Text("alert.resign.message")
        }
        .alert("alert.claimDraw.title", isPresented: $claimPresented) {
            Button("control.keepPlaying", role: .cancel) { }
            Button("control.endAsDraw") { play.claimDraw() }
        } message: {
            Text("alert.claimDraw.message")
        }
        // Declared here rather than in the stacked branch, which would present
        // it again every time the layout came back to that branch.
        .sheet(isPresented: $capturedShown) { capturedSheet(play) }
    }

    // MARK: - What the captures took

    /// The captured pieces as this device's player may see them, until the
    /// game ends and discloses everything.
    private func captured(_ play: NearbyPlay,
                          pitch: CGFloat = BoardLayout.capturedDiscPitch) -> some View {
        CapturedPiecesView(captured: play.captured,
                           game: play.game,
                           throughPly: play.shown.count,
                           viewer: play.localSide,
                           disclosed: play.disclosesTheDeal,
                           pitch: pitch)
    }

    /// The same surface in a sheet, at a pitch fitted to the sheet's width.
    private func capturedSheet(_ play: NearbyPlay) -> some View {
        NavigationStack {
            ScrollView {
                captured(play,
                         pitch: BoardLayout.capturedSheetPitch(in: capturedWidth,
                                                               game: play.game))
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

    private func sideBySide(_ play: NearbyPlay, in size: CGSize) -> some View {
        HStack(spacing: 0) {
            boardBlock(play, BoardLayout.geometry(in: size, game: play.game))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { play.cancelSelection() }

            VStack(alignment: .leading, spacing: 0) {
                statusBlock(play)
                    .padding(.horizontal, BoardLayout.panelInset - 12)
                    .padding(.vertical, 8)

                Divider()

                if play.game.conceals {
                    captured(play)
                        .padding(.horizontal, BoardLayout.panelInset)
                        .padding(.vertical, 8)

                    Divider()
                }

                Spacer(minLength: 0)
                Divider()

                controls(play)
                    .padding(BoardLayout.panelInset)
            }
            .frame(maxHeight: .infinity)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea(.container, edges: .top)
            }
            // A tap on the panel's quiet parts cancels the selection too.
            .contentShape(Rectangle())
            .onTapGesture { play.cancelSelection() }
            .frame(width: BoardLayout.panelWidth)
        }
        .navigationTitle("nav.play")
    }

    /// The turn status in the bar's centre, or above the board at an
    /// accessibility text size; the controls below the board; the board fitted
    /// between them.
    ///
    /// The cluster's slot is reserved at its tallest arrangement: the turn
    /// passing swaps the offers for the claim, which may wrap differently, and
    /// the board stands still while they trade places.
    private func stacked(_ play: NearbyPlay, in size: CGSize) -> some View {
        let status = statusStandsInBar ? 0 : statusHeight
        let chrome = BoardLayout.stackedChrome(
            in: size, game: play.game,
            asking: status + BoardLayout.stackedCluster(row: controlRow))
        let geometry = BoardLayout.stackedGeometry(in: size, game: play.game, chrome: chrome)
        return VStack(spacing: 0) {
            if !statusStandsInBar {
                statusBlock(play)
                    .padding(.horizontal, BoardLayout.panelInset - 12)
                    .padding(.vertical, 8)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { statusHeight = $0 }
            }

            boardBlock(play, geometry,
                       bleed: BoardLayout.surfaceBleed(in: size.width, board: geometry))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { play.cancelSelection() }
                // The lines the bar cannot hold, hung just beneath it.
                .overlay(alignment: .top) {
                    if statusStandsInBar {
                        quietLines(play)
                            // Each line brings 12 points of inset; this makes
                            // the page's 16.
                            .padding(.horizontal, BoardLayout.panelInset - 12)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

            controls(play)
                .padding(.horizontal, BoardLayout.panelInset)
                .padding(.vertical, BoardLayout.clusterAir)
                .frame(height: max(0, chrome - status), alignment: .bottom)
        }
        // One cluster row, measured out of sight for the reservation.
        .background { BoardLayout.ClusterRow { controlRow = $0 } }
        .toolbar {
            if statusStandsInBar {
                ToolbarItem(placement: .principal) {
                    turnStatus(play, placement: .bar)
                }
            }
            // No room beside the board here, so the captured pieces are a
            // toolbar button away.
            if play.game.conceals {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        capturedShown = true
                    } label: {
                        Label("captured.title", systemImage: "tray.full")
                    }
                    .accessibilityIdentifier("nearby-captured")
                }
            }
        }
    }

    /// Whether the turn status is in the bar rather than above the board.
    private var statusStandsInBar: Bool { !typeSize.isAccessibilitySize }

    // MARK: - The status

    /// The turn status and the quiet lines beneath it, where the element stands
    /// above the board or beside it.
    private func statusBlock(_ play: NearbyPlay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            turnStatus(play, placement: .block)
            quietLines(play)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func turnStatus(_ play: NearbyPlay,
                            placement: TurnStatus.Placement) -> some View {
        TurnStatus(placement: placement,
                   game: play.game,
                   state: play.statusState,
                   reason: play.current.reason ?? play.evaluation.reason,
                   reasonText: play.reasonText,
                   sideToMove: play.evaluation.sideToMove,
                   inCheck: play.evaluation.inCheck,
                   controller: play.controller,
                   beatEmphasis: play.beatEmphasis)
    }

    /// What the other player is asking for, and the one line that is ever said
    /// about the link.
    private func quietLines(_ play: NearbyPlay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let asking = play.standingOffer {
                Text(Self.asked(asking))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
                    .accessibilityIdentifier("nearby-asking")
            }

            if play.isWaitingOnConnection {
                Text(LocalizedStringKey(play.interruptionKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
                    .accessibilityIdentifier("nearby-connection")
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(policy.fade(Motion.stateFadeAnimation), value: play.isWaitingOnConnection)
        .animation(policy.fade(Motion.stateFadeAnimation), value: play.standingOffer)
    }

    private static func asked(_ kind: PeerOffer.Kind) -> LocalizedStringKey {
        switch kind {
        case .draw: "nearby.theyOfferDraw"
        case .takeback: "nearby.theyAskUndo"
        }
    }

    // MARK: - The board

    private func boardBlock(_ play: NearbyPlay, _ geometry: BoardGeometry,
                            bleed: CGFloat = 0) -> some View {
        // The ending discloses the deal once the last ply has landed, by
        // opacity, so Reduce Motion draws it as full motion does.
        let disclosure: Double = play.disclosesTheDeal && !play.isCommitting ? 1 : 0
        return ZStack {
            BoardView(geometry: geometry,
                      placement: play.placement,
                      flipped: play.flipped,
                      selected: play.selected,
                      destinations: play.destinations,
                      captures: play.captures,
                      forbidden: play.forbiddenPoints,
                      lastMove: play.lastMove,
                      checkedGeneral: play.checkedGeneral,
                      transit: play.transit,
                      transitFade: play.transitFade,
                      transitReveal: play.transitReveal,
                      disclosure: disclosure,
                      checkEmphasis: play.checkEmphasis,
                      markerEmphasis: play.markerEmphasis,
                      policy: play.policy,
                      surfaceBleed: bleed,
                      onTap: { tap($0, play) },
                      onTravelArrival: { play.travelArrived() },
                      onFadeArrival: { play.fadeArrived() },
                      onFlipArrival: { play.flipArrived() })
                .boardHaptics(landings: play.landings, refusals: play.refusals)

            // The notice waits for the move that brought the result to land.
            if let state = play.endState, showsResult, !play.isCommitting {
                NearbyNotice(title: Self.title(of: state, in: play.game),
                             detail: play.reasonText ?? "",
                             done: { flow.leaveBoard() },
                             close: { dismissResult() })
                    .transition(.opacity)
            } else if let void = play.voided, showsResult, !play.isCommitting {
                NearbyNotice(title: String(localized: "nearby.ended.title"),
                             detail: void.message,
                             done: { flow.leaveBoard() },
                             close: { dismissResult() })
                    .transition(.opacity)
            }
        }
        // The board's other phases are driven by their transitions.
        .animation(play.policy.fade(Motion.stateFadeAnimation), value: disclosure)
    }

    private static func title(of state: GameState, in game: GameKind) -> String {
        switch state {
        case .redWins: game.resultText(.red)
        case .blackWins: game.resultText(.black)
        case .draw, .ongoing, .claimableDraw: String(localized: "result.draw")
        }
    }

    private var showsResult: Bool {
        flow.dismissedResultOf != flow.boardGameID
    }

    private func dismissResult() {
        guard let game = flow.boardGameID else { return }
        withAnimation(policy.fade(Motion.stateFadeAnimation)) {
            flow.dismissResult(of: game)
        }
    }

    /// On a finished board a tap puts the notice away, with no refusal beat.
    private func tap(_ square: Square, _ play: NearbyPlay) {
        guard !play.isCommitting else { return }
        if play.isOver, showsResult {
            dismissResult()
            return
        }
        play.tap(square)
    }

    // MARK: - The controls

    /// The networked cluster. Off turn it carries 提和 and 悔棋; on turn 判和,
    /// or 接受 while the other player has something standing. Each is disabled
    /// where the engine would refuse it. 认输 and 翻转棋盘 stand at the trailing
    /// end so the turn passing never moves them, and 完成 takes 认输's place
    /// once the game is over. The placement games have no 判和 and no 翻转棋盘.
    private func controls(_ play: NearbyPlay, worded: Bool, carriesFlip: Bool) -> some View {
        let over = Self.scene(of: play) == .over
        return HStack(spacing: 8) {
            if !over {
                negotiations(play, worded: worded)
            }

            Spacer(minLength: 0)

            if over {
                // Prominent only once the notice carrying it has been closed.
                concluding(prominent: !showsResult)
                    .transition(.opacity)
            } else {
                Button {
                    resignPresented = true
                } label: {
                    clusterLabel("control.resign", "flag.fill", worded: worded)
                }
                .buttonStyle(.glass)
                .disabled(!play.canResign)
                .accessibilityLabel(Text("control.resign"))
                .accessibilityIdentifier("cluster-resign")
                .transition(.opacity)
            }

            if carriesFlip, !play.game.isPlacement {
                flipControl(play, worded: worded)
            }
        }
    }

    /// The offers this side of the turn has; none on a placement game's own
    /// turn.
    @ViewBuilder
    private func negotiations(_ play: NearbyPlay, worded: Bool) -> some View {
        if let asking = play.standingOffer {
            // No confirmation: accepting is already the answer to a request.
            Button {
                play.accept()
            } label: {
                clusterLabel("control.accept", "checkmark", worded: worded)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("control.accept"))
            .accessibilityIdentifier("cluster-accept")
            .accessibilityHint(Text(Self.asked(asking)))
            .transition(.opacity)
        } else if play.controller == .you {
            if !play.game.isPlacement {
                Button {
                    claimPresented = true
                } label: {
                    clusterLabel("control.claimDraw", "equal", worded: worded)
                }
                .buttonStyle(.glass)
                .disabled(!play.claimStands)
                .accessibilityLabel(Text("control.claimDraw"))
                .accessibilityIdentifier("cluster-claim")
                .transition(.opacity)
            }
        } else {
            Button {
                play.offerDraw()
            } label: {
                clusterLabel("control.offerDraw", "figure.2.left.holdinghands",
                             worded: worded)
            }
            .buttonStyle(.glass)
            .disabled(!play.canOfferDraw)
            .accessibilityLabel(Text("control.offerDraw"))
            .accessibilityIdentifier("cluster-offer-draw")
            .transition(.opacity)

            Button {
                play.requestUndo()
            } label: {
                clusterLabel("control.undo", "arrow.uturn.backward", worded: worded)
            }
            .buttonStyle(.glass)
            .disabled(!play.canRequestUndo)
            .accessibilityLabel(Text("control.undo"))
            .accessibilityIdentifier("cluster-undo")
            .transition(.opacity)
        }
    }

    private func flipControl(_ play: NearbyPlay, worded: Bool) -> some View {
        Button {
            play.flip()
        } label: {
            clusterLabel("control.flipBoard", "arrow.up.arrow.down", worded: worded)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(Text("control.flipBoard"))
        .accessibilityIdentifier("cluster-flip")
    }

    /// A control's symbol and word, or its symbol alone. The word stays on one
    /// line, or the row would grow taller than the arrangement chosen for it.
    @ViewBuilder
    private func clusterLabel(_ key: LocalizedStringKey, _ symbol: String,
                              worded: Bool) -> some View {
        if worded {
            Label(key, systemImage: symbol).lineLimit(1)
        } else {
            Label(key, systemImage: symbol).labelStyle(.iconOnly)
        }
    }

    /// The cluster at the first arrangement that fits: one row of words, that
    /// row wrapped with 翻转棋盘 beneath, one row of symbols, and that row
    /// wrapped. Under Reduce Motion the turn passing crossfades the sets whole.
    @ViewBuilder
    private func controls(_ play: NearbyPlay) -> some View {
        let scene = Self.scene(of: play)
        let arrangements = ViewThatFits(in: .horizontal) {
            controls(play, worded: true, carriesFlip: true)
            wrappedControls(play, worded: true)
            controls(play, worded: false, carriesFlip: true)
            wrappedControls(play, worded: false)
        }
        if policy.reduceMotion {
            arrangements
                .id(scene)
                .animation(policy.crossfade, value: scene)
        } else {
            arrangements
                .animation(Motion.stateFadeAnimation, value: scene)
        }
    }

    /// The cluster over two rows, with 翻转棋盘 beneath, trailing.
    @ViewBuilder
    private func wrappedControls(_ play: NearbyPlay, worded: Bool) -> some View {
        VStack(alignment: .trailing, spacing: BoardLayout.clusterAir) {
            controls(play, worded: worded, carriesFlip: false)
            if !play.game.isPlacement {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    flipControl(play, worded: true)
                }
            }
        }
    }

    /// The stretches of play whose controls are stable. The finished scene
    /// waits for the ending ply to land, as the result notice does.
    private enum Scene: Equatable { case onTurn, offTurn, answering, over }

    private static func scene(of play: NearbyPlay) -> Scene {
        if play.isOver, !play.isCommitting { return .over }
        if play.standingOffer != nil { return .answering }
        return play.controller == .you ? .onTurn : .offTurn
    }

    /// The way out, a word alone in every arrangement.
    @ViewBuilder
    private func concluding(prominent: Bool) -> some View {
        let action = Button("control.done") { flow.leaveBoard() }
            .lineLimit(1)
            .accessibilityIdentifier("cluster-done")
        if prominent {
            action.buttonStyle(.glassProminent)
        } else {
            action.buttonStyle(.glass)
        }
    }
}

/// What a networked game says when it is over, with a result or without.
///
/// Its one action is 完成: the game is already in History on both devices, so
/// none of the local notice's filing actions applies, and a fresh proposal is
/// the rematch. A result one player confirmed and the other did not would leave
/// the two libraries disagreeing about one game.
private struct NearbyNotice: View {
    /// The result, or the fact that the game ended.
    var title: String
    /// A result's reason, or why a game went away; empty for nothing.
    var detail: String
    var done: () -> Void
    var close: () -> Void

    @Environment(\.motionPolicy) private var policy
    @State private var settled = false

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("result-title")

            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("result-reason")
            }

            Button("control.done", action: done)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("result-done")
                .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .overlay(alignment: .topTrailing) {
            Button(role: .close) { close() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("result-close")
                .padding(8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .scaleEffect(settled || policy.reduceMotion ? 1 : 0.92)
        .opacity(settled ? 1 : 0)
        .onAppear {
            withAnimation(policy.appear) { settled = true }
            AccessibilityNotification
                .Announcement(String(format: String(localized: "result.announcement"),
                                     title, detail))
                .post()
        }
    }
}
