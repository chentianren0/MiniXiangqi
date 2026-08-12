// The nearby board: the game two people are playing, on the board the app
// already has.
//
// docs/interaction-design.md, "Layout shapes" and "Nearby play". It is the local
// game's own screen in every visible respect — the same two arrangements, the
// same turn status in the bar's centre or beside the board, the same board and
// the same motion language, the same result notice in front of it — and it
// differs only where the game itself differs: the turn belongs to the protocol
// rather than to a search, the opponent is a person rather than the machine, and
// the play controls are the ones a nearby game has, which is every mode's cluster
// less the hint and with the negotiations of whoever's turn it is.
//
// **There is no connection chrome.** Connections idle out between moves by the
// radio's own design and the driver brings them back underneath; a board that
// announced either would be announcing the weather. One quiet line appears where
// the link is actually costing the player something — what they did has not
// reached the other device, or their own turn has been blocked past a real
// stretch — and it goes when the link comes back.
//
// **A game that goes away says why it went.** Three things take a session from
// the peer it belongs to — the other device no longer holding it, a connection
// closed on a violation, a fresh proposal retiring it — and each has one
// sentence, in the same notice a result is announced in. Nothing else is said
// about any of it, and nothing anywhere describes what the app did about it.
//
// The session is the engine's, not this screen's. Leaving the board is the
// interruption the protocol already models, and the model below is a
// presentation built when the board opens and let go of when it closes — which
// is also what keeps a nearby move's sound with the board that is showing it.

#if os(iOS)

import SwiftUI

struct NearbyBoardScreen: View {
    let flow: NearbyFlow

    /// The board's own model, built for the session the flow is showing.
    @State private var play: NearbyPlay?
    @State private var resignPresented = false
    @State private var claimPresented = false

    /// What the stacked shape's chrome actually came to, measured rather than
    /// assumed, exactly as the play screen measures its own.
    @State private var statusHeight = BoardLayout.stackedChromeHeight / 2
    @State private var controlsHeight = BoardLayout.stackedChromeHeight / 2

    /// Whether the save-failure capsule is up. Raised when the library refuses
    /// a ply of this device's player's own, and transient: it answers the touch
    /// and withdraws by itself. View state, and rightly so — it has a
    /// four-second life and nothing to say to a screen that is not on show.
    @State private var saveFailureShown = false

    @Environment(\.motionPolicy) private var policy
    @Environment(\.horizontalSizeClass) private var widthClass

    /// Whether the reader is at one of the accessibility text sizes, which is
    /// what decides where the turn status stands in the stacked shape.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if let play {
                layout(play)
            } else {
                // Nothing reaches this screen without a session, so this is the
                // honest nothing rather than a state to design.
                ProgressView()
            }
        }
        // docs/interaction-design.md, "Navigation": a board screen hides the
        // destination bar where that bar stands across the bottom.
        .toolbar(hidesDestinationBar(widthClass) ? .hidden : .automatic, for: .tabBar)
        .task(id: flow.boardSessionID) { open() }
        .onChange(of: flow.boardSession) { _, session in
            // A session that went away under the board leaves the board where it
            // is: the position is still worth looking at, and the notice in
            // front of it says what became of the game.
            guard let session else { return }
            play?.sync(with: session)
        }
        .onChange(of: flow.boardVoid) { _, _ in wentAway() }
        // The library refusing a move of the player's own. The count only
        // grows, so a second refusal raises a second capsule rather than
        // extending the first.
        .onChange(of: flow.driver.ownMoveRefusals) { _, _ in
            withAnimation(policy.fade(Motion.stateFadeAnimation)) {
                saveFailureShown = true
            }
        }
        .onChange(of: policy) { play?.policy = policy }
        // A board turned round stays turned round: the model is rebuilt on
        // every entry, so which way the player last had it is remembered where
        // the game is rather than where the page is.
        .onChange(of: play?.flipped) { _, flipped in
            guard let flipped, let session = flow.boardSessionID else { return }
            flow.setOrientation(flipped, of: session)
        }
        .onDisappear { play?.close() }
    }

    private func open() {
        play?.close()
        play = flow.boardSession.flatMap {
            NearbyPlay(session: $0, driver: flow.driver, positions: flow.positions,
                       flipped: flow.orientation(of: $0.id), policy: policy)
        }
        wentAway()
    }

    /// The game went away under the board, if it did.
    ///
    /// The flow's last-held session is applied first, because the update that
    /// took the session away can be the same one that ended it: two publications
    /// land between two redraws and this view sees only the second. Applying it
    /// is what makes the result win wherever there was one — so the void
    /// sentence speaks only for a game that genuinely ended without a result.
    private func wentAway() {
        guard let void = flow.boardVoid else { return }
        if let held = flow.boardHeld { play?.sync(with: held) }
        play?.wentAway(void)
    }

    private func layout(_ play: NearbyPlay) -> some View {
        GeometryReader { proxy in
            switch BoardLayout.shape(in: proxy.size, game: play.game) {
            case .sideBySide: sideBySide(play, in: proxy.size)
            case .stacked: stacked(play, in: proxy.size)
            }
        }
        // 认输 ends the game against the player and cannot be undone, so it is
        // confirmed — the same alert, in the same words, the local game uses.
        .alert("alert.resign.title", isPresented: $resignPresented) {
            Button("control.cancel", role: .cancel) { }
            Button("control.resign", role: .destructive) { play.resign() }
        } message: {
            Text("alert.resign.message")
        }
        // And 判和 is the local game's claim, presented the way the local game
        // presents it: the same confirmation, the same two answers, the same
        // words. A claim here travels as a ply and the draw is the rules' own,
        // which is exactly what it is on a board with nobody else at it.
        .alert("alert.claimDraw.title", isPresented: $claimPresented) {
            Button("control.keepPlaying", role: .cancel) { }
            Button("control.endAsDraw") { play.claimDraw() }
        } message: {
            Text("alert.claimDraw.message")
        }
    }

    // MARK: - The two shapes

    /// The board on one side, the panel beside it. This shape's board page is a
    /// page like any other and carries the inline title beside the control that
    /// walks back out.
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
            // The panel is outside the board too: a tap on its quiet parts
            // cancels the selection.
            .contentShape(Rectangle())
            .onTapGesture { play.cancelSelection() }
            .frame(width: BoardLayout.panelWidth)
        }
        .navigationTitle("nav.play")
    }

    /// The turn status in the bar's centre, the play controls below the board,
    /// and the board fitted to the full width in the height between them.
    ///
    /// At an accessibility text size the element returns to its place above the
    /// board, exactly as it does on the local board, and the bar centre stays
    /// empty: a page over a board needs no name either way.
    private func stacked(_ play: NearbyPlay, in size: CGSize) -> some View {
        let chrome = (statusStandsInBar ? 0 : statusHeight) + controlsHeight
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
                // The lines the bar cannot hold, hung just beneath it in front
                // of the air above the board — where they hang beneath the
                // status block in the other arrangement.
                .overlay(alignment: .top) {
                    if statusStandsInBar {
                        quietLines(play)
                            // The page's one leading edge, 16 points in: each
                            // line brings 12 of its own, exactly as it does
                            // inside the status block, and this is the rest.
                            .padding(.horizontal, BoardLayout.panelInset - 12)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

            controls(play)
                .padding(.horizontal, BoardLayout.panelInset)
                .padding(.vertical, 8)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { controlsHeight = $0 }
        }
        .toolbar {
            if statusStandsInBar {
                ToolbarItem(placement: .principal) {
                    turnStatus(play, placement: .bar)
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
                   state: play.statusState,
                   reason: play.end?.reason ?? play.evaluation.reason,
                   reasonText: play.reasonText,
                   sideToMove: play.evaluation.sideToMove,
                   inCheck: play.evaluation.inCheck,
                   controller: play.controller,
                   beatEmphasis: play.beatEmphasis)
    }

    /// What the other player is asking for, the one line that is ever said
    /// about the link, and the save-failure capsule.
    ///
    /// The offer and the request are named here rather than on a control,
    /// because a control says what pressing it does and this says what somebody
    /// else has done — which is the same division the claim already keeps
    /// between 判和 and 可判和, in the same quiet register, in the same place.
    private func quietLines(_ play: NearbyPlay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let asking = play.standingItem {
                Text(Self.asked(asking))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
                    .accessibilityIdentifier("nearby-asking")
            }

            if play.isWaitingOnConnection {
                Text("nearby.connecting")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
                    .accessibilityIdentifier("nearby-connection")
            }

            // The accepted brief save-failure feedback, in the place this
            // board keeps its quiet lines: beneath the turn status, which is
            // where the contract anchors it, and in the same shape the local
            // board raises. What it reports here is not a move to try again —
            // a nearby ply has already gone to the other device and stands —
            // but that this device's own library did not keep it.
            if saveFailureShown {
                SaveFailureCapsule { saveFailureShown = false }
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(policy.fade(Motion.stateFadeAnimation), value: play.isWaitingOnConnection)
        .animation(policy.fade(Motion.stateFadeAnimation), value: play.standingItem)
    }

    /// What the other player has asked for, in words. The item's own two kinds,
    /// so a third would not compile rather than reaching the screen unnamed.
    private static func asked(_ kind: NegotiationItem.Kind) -> LocalizedStringKey {
        switch kind {
        case .drawOffer: "nearby.theyOfferDraw"
        case .undoRequest: "nearby.theyAskUndo"
        }
    }

    // MARK: - The board

    private func boardBlock(_ play: NearbyPlay, _ geometry: BoardGeometry,
                            bleed: CGFloat = 0) -> some View {
        ZStack {
            BoardView(geometry: geometry,
                      placement: play.placement,
                      flipped: play.flipped,
                      selected: play.selected,
                      destinations: play.destinations,
                      captures: play.captures,
                      lastMove: play.lastMove,
                      checkedGeneral: play.checkedGeneral,
                      transit: play.transit,
                      transitFade: play.transitFade,
                      checkEmphasis: play.checkEmphasis,
                      markerEmphasis: play.markerEmphasis,
                      policy: play.policy,
                      surfaceBleed: bleed,
                      onTap: { tap($0, play) },
                      onTravelArrival: { play.travelArrived() },
                      onFadeArrival: { play.fadeArrived() },
                      onFlipArrival: { play.flipArrived() })

            // The notice waits for the landing: a result arrives with a move,
            // and the move has to finish being shown before an announcement
            // stands in front of it.
            if let end = play.end, showsResult, !play.isCommitting {
                NearbyNotice(title: Self.title(of: end.state),
                             detail: play.reasonText ?? "",
                             done: { flow.leaveBoard() },
                             close: { dismissResult() })
                    .transition(.opacity)
            } else if let void = play.voided, showsResult, !play.isCommitting {
                // The same notice, because it is the same moment: the game is
                // over and the board behind it is the one worth looking at. It
                // says why it ended, in one sentence, and nothing about what the
                // app did next.
                NearbyNotice(title: String(localized: "nearby.ended.title"),
                             detail: void.message,
                             done: { flow.leaveBoard() },
                             close: { dismissResult() })
                    .transition(.opacity)
            }
        }
    }

    /// The fuller wording the notice has room for, which is the same vocabulary
    /// the local game's notice uses for the same three results.
    private static func title(of state: GameState) -> String {
        switch state {
        case .redWins: String(localized: "result.redWins")
        case .blackWins: String(localized: "result.blackWins")
        case .draw, .ongoing, .claimableDraw: String(localized: "result.draw")
        }
    }

    private var showsResult: Bool {
        flow.dismissedResultOf != flow.boardSessionID
    }

    private func dismissResult() {
        guard let session = flow.boardSessionID else { return }
        withAnimation(policy.fade(Motion.stateFadeAnimation)) {
            flow.dismissResult(of: session)
        }
    }

    /// A finished board is not inert: a tap puts the notice away, and that tap
    /// is an accepted input rather than a rejected one, so it gets no beat.
    /// Everything else goes through the model, which asks the position.
    private func tap(_ square: Square, _ play: NearbyPlay) {
        guard !play.isCommitting else { return }
        if play.isOver, showsResult {
            dismissResult()
            return
        }
        play.tap(square)
    }

    // MARK: - The controls

    /// The nearby cluster.
    ///
    /// **The negotiations belong to whose turn it is**, because the protocol's
    /// own do: an offer and a request are the off-turn peer's to open, a claim
    /// is a turn action of the side to move, and an acceptance answers something
    /// that arrived on this device's turn. So off turn the cluster carries 提和
    /// and 悔棋, and on turn it carries 判和 — with 接受 in the claim's own place
    /// while the other player has something standing, which is the one moment a
    /// claim is not what the turn is about. Each is disabled exactly when the
    /// engine would refuse it, which is the same grammar the local cluster keeps
    /// for 判和 and 悔棋: a control that will be available on the next ply stays
    /// on screen rather than coming and going with it.
    ///
    /// **认输 and 翻转棋盘 stand at the trailing end and therefore never move**,
    /// with the negotiations leading and the space between them: the turn
    /// passing changes the leading side of the row and leaves the two controls
    /// that are true of the whole game exactly where a thumb last found them.
    /// The way out replaces 认输 once the game is over, in 认输's own place —
    /// the same controls, keys and identifiers the other boards carry.
    private func controls(_ play: NearbyPlay, worded: Bool, carriesFlip: Bool) -> some View {
        let over = Self.scene(of: play) == .over
        return HStack(spacing: 8) {
            if !over {
                negotiations(play, worded: worded)
            }

            Spacer(minLength: 0)

            if over {
                // The one obvious next action once the game is over, and
                // therefore the one thing on screen the tint rule allows —
                // prominent only once the notice carrying it has been closed.
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

            if carriesFlip { flipControl(play, worded: worded) }
        }
    }

    /// The two or one this side of the turn has.
    @ViewBuilder
    private func negotiations(_ play: NearbyPlay, worded: Bool) -> some View {
        if let asking = play.standingItem {
            // Answering what the other player asked for. It follows something
            // the status line is already naming and is the player's own
            // deliberate answer to it, so nothing stands between the press and
            // the act — there is no second confirmation of a confirmation.
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
            // The claim, presented the way the local game presents it.
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
        } else {
            // 提和 asks for the equal rather than taking it, and the two
            // figures are as near a handshake as the platform's symbols come:
            // the act belongs to the pair rather than to this device.
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

    /// 翻转棋盘, in the one arrangement or the other — the same control, key and
    /// identifier the play screen's cluster carries.
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

    /// A cluster control's label: its symbol and its word, or its symbol alone
    /// where the row has given the words up. The word is the accessibility label
    /// either way, which each control states for itself, and it stays on one
    /// line: these are one-act labels, and a control whose word wrapped would
    /// make its row taller than the arrangement it was chosen as.
    @ViewBuilder
    private func clusterLabel(_ key: LocalizedStringKey, _ symbol: String,
                              worded: Bool) -> some View {
        if worded {
            Label(key, systemImage: symbol).lineLimit(1)
        } else {
            Label(key, systemImage: symbol).labelStyle(.iconOnly)
        }
    }

    /// The cluster at whichever of its arrangements fits: one row with every
    /// word, the same row wrapped with 翻转棋盘 beneath, one row of symbols, and
    /// that row wrapped. Words outrank one-rowness, and no row mixes the two
    /// forms — the play screen's own grammar, in the same words.
    ///
    /// **The turn passing is one drawn transition.** 认输 and 翻转棋盘 hold their
    /// identity and their trailing places across it while the leading acts swap:
    /// the departing ones fade as their width closes and the arriving ones fade
    /// in, riding the landing of the ply that passed the turn — or, where
    /// nothing lands, the moment the game ended. Under Reduce Motion the two
    /// sets crossfade as wholes, nothing sliding and nothing collapsing.
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

    /// The cluster over two rows, with 翻转棋盘 beneath the two controls that
    /// never move: the row above is anchored at its trailing end, so the row
    /// below is anchored there too.
    private func wrappedControls(_ play: NearbyPlay, worded: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            controls(play, worded: worded, carriesFlip: false)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                flipControl(play, worded: true)
            }
        }
    }

    /// The scenes this cluster has: a stretch of play whose acts are stable.
    /// Two of them are the two sides of the turn, one is answering what the
    /// other player asked for, and the last is a game that is over.
    ///
    /// **The finished scene waits for the landing**, which is the guard the
    /// result notice in front of the board already keeps: the ply that ends the
    /// game is still travelling when the session says it is over, and a cluster
    /// that swapped there would swap ahead of the move that changed it. The
    /// other three follow the session as it stands, having no landing of their
    /// own to wait for.
    private enum Scene: Equatable { case onTurn, offTurn, answering, over }

    private static func scene(of play: NearbyPlay) -> Scene {
        if play.isOver, !play.isCommitting { return .over }
        if play.standingItem != nil { return .answering }
        return play.controller == .you ? .onTurn : .offTurn
    }

    /// The way out, which is the one control that is its word alone in every
    /// arrangement — the same rule the local board's concluding action keeps.
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

/// What a nearby game says when it is over — whichever way it ended.
///
/// docs/interaction-design.md, "Natural result presentation": the same notice in
/// front of the same undimmed board, dismissible for the same reason — the
/// squares worth studying are the ones underneath it.
///
/// One notice for a result and for a game that went away, because they are the
/// same moment for the person looking at it: the game is over, this is what
/// became of it, and here is the way out. A second shape for the second case
/// would be a second thing on screen saying the same size of thing.
///
/// Its actions are the ones a nearby game has. Every action the local notice
/// carries is a filing act — 保存, 保存并开始新对局, 回放 — and a nearby game is
/// filed by nobody: it goes into History the moment the two devices have
/// settled on how it ended, because a result one player confirms and the other
/// does not would be two libraries disagreeing about one game. What is left is
/// the way out, which is 完成. A fresh proposal is the rematch, so nothing here
/// offers one.
private struct NearbyNotice: View {
    /// The result, or the fact that the game ended. Resolved by the caller,
    /// because a screen reader is told this sentence as well as shown it.
    var title: String
    /// The line beneath: a result's reason, or the one sentence about why a game
    /// went away. Empty where there is nothing to add.
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

#endif
