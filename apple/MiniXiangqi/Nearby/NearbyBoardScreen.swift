// The nearby board: the game two people are playing, on the board the app
// already has.
//
// docs/interaction-design.md, "Layout shapes" and "Nearby play". It is the local
// game's own screen in every visible respect — the same two arrangements, the
// same turn status above or beside the board, the same board and the same motion
// language, the same result notice in front of it — and it differs only where
// the game itself differs: the turn belongs to the protocol rather than to a
// search, the opponent is a person rather than the machine, and the play
// controls are the ones a nearby game has.
//
// **There is no connection chrome.** Connections idle out between moves by the
// radio's own design and the driver brings them back underneath; a board that
// announced either would be announcing the weather. One quiet line appears where
// the link is actually costing the player something — what they did has not
// reached the other device, or their own turn has been blocked past a real
// stretch — and it goes when the link comes back.
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

    /// What the stacked shape's chrome actually came to, measured rather than
    /// assumed, exactly as the play screen measures its own.
    @State private var statusHeight = BoardLayout.stackedChromeHeight / 2
    @State private var controlsHeight = BoardLayout.stackedChromeHeight / 2

    @Environment(\.motionPolicy) private var policy
    @Environment(\.horizontalSizeClass) private var widthClass

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
            // A session that went away under the board — voided by a violation,
            // or retired by a fresh proposal — takes the board with it.
            guard let session else {
                flow.leaveBoard()
                return
            }
            play?.sync(with: session)
        }
        .onChange(of: policy) { play?.policy = policy }
        .onDisappear { play?.close() }
    }

    private func open() {
        play?.close()
        play = flow.boardSession.flatMap {
            NearbyPlay(session: $0, driver: flow.driver, positions: flow.positions,
                       policy: policy)
        }
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
    }

    // MARK: - The two shapes

    private func sideBySide(_ play: NearbyPlay, in size: CGSize) -> some View {
        HStack(spacing: 0) {
            boardBlock(play, BoardLayout.geometry(in: size, game: play.game))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { play.cancelSelection() }

            VStack(alignment: .leading, spacing: 0) {
                status(play)
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
    }

    private func stacked(_ play: NearbyPlay, in size: CGSize) -> some View {
        VStack(spacing: 0) {
            status(play)
                .padding(.horizontal, BoardLayout.panelInset - 12)
                .padding(.vertical, 8)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { statusHeight = $0 }

            boardBlock(play,
                       BoardLayout.stackedGeometry(in: size, game: play.game,
                                                   chrome: statusHeight + controlsHeight))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { play.cancelSelection() }

            controls(play)
                .padding(.horizontal, BoardLayout.panelInset)
                .padding(.vertical, 8)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { controlsHeight = $0 }
        }
    }

    // MARK: - The status

    /// The turn status, and the one line that is ever said about the link.
    private func status(_ play: NearbyPlay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TurnStatus(state: play.end?.state ?? play.evaluation.state,
                       reason: play.end?.reason ?? play.evaluation.reason,
                       sideToMove: play.evaluation.sideToMove,
                       inCheck: play.evaluation.inCheck,
                       controller: play.controller,
                       beatEmphasis: play.beatEmphasis)

            if play.isWaitingOnConnection {
                Text("nearby.connecting")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
                    .accessibilityIdentifier("nearby-connection")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(policy.fade(Motion.stateFadeAnimation), value: play.isWaitingOnConnection)
    }

    // MARK: - The board

    private func boardBlock(_ play: NearbyPlay, _ geometry: BoardGeometry) -> some View {
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
                      onTap: { tap($0, play) },
                      onTravelArrival: { play.travelArrived() },
                      onFadeArrival: { play.fadeArrived() },
                      onFlipArrival: { play.flipArrived() })

            // The notice waits for the landing: a result arrives with a move,
            // and the move has to finish being shown before an announcement
            // stands in front of it.
            if let end = play.end, showsResult, !play.isCommitting {
                NearbyResultNotice(state: end.state, reason: end.reason,
                                   done: { flow.leaveBoard() },
                                   close: { dismissResult() })
                    .transition(.opacity)
            }
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
        if play.end != nil, showsResult {
            dismissResult()
            return
        }
        play.tap(square)
    }

    // MARK: - The controls

    /// The nearby cluster: 认输 while the game is on, the way out once it is
    /// over, and 翻转棋盘 throughout — the same control, the same key and the
    /// same identifier the other boards carry.
    ///
    /// 悔棋 and 判和 are the negotiations, and they arrive with the surfaces that
    /// ask the other player for them.
    private func controls(_ play: NearbyPlay) -> some View {
        HStack(spacing: 8) {
            if play.end == nil {
                Button("control.resign") { resignPresented = true }
                    .buttonStyle(.glass)
                    .disabled(!play.canResign)
                    .accessibilityIdentifier("cluster-resign")
            } else {
                // The one obvious next action once the game is over, and
                // therefore the one thing on screen the tint rule allows —
                // prominent only once the notice carrying it has been closed.
                concluding(prominent: !showsResult)
            }

            Button {
                play.flip()
            } label: {
                Label("control.flipBoard", systemImage: "arrow.up.arrow.down")
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("control.flipBoard"))
            .accessibilityIdentifier("cluster-flip")

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func concluding(prominent: Bool) -> some View {
        let action = Button("control.done") { flow.leaveBoard() }
            .accessibilityIdentifier("cluster-done")
        if prominent {
            action.buttonStyle(.glassProminent)
        } else {
            action.buttonStyle(.glass)
        }
    }
}

/// What a nearby game says when it is over.
///
/// docs/interaction-design.md, "Natural result presentation": the same notice in
/// front of the same undimmed board, dismissible for the same reason — the
/// squares worth studying are the ones underneath it.
///
/// Its actions are the ones a nearby game has. Every action the local notice
/// carries is a filing act — 保存, 保存并开始新对局, 回放 — and a nearby game is
/// filed by nothing until the stage that gives it archives; what is left is the
/// way out, which is 完成. A fresh proposal is the rematch, so nothing here
/// offers one.
private struct NearbyResultNotice: View {
    var state: GameState
    var reason: EndReason
    var done: () -> Void
    var close: () -> Void

    @Environment(\.motionPolicy) private var policy
    @State private var settled = false

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("result-title")

            if !reason.text.isEmpty {
                Text(reason.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                                     title, reason.text))
                .post()
        }
    }

    /// The fuller wording the notice has room for, which is the same vocabulary
    /// the local game's notice uses for the same three results.
    private var title: String {
        switch state {
        case .redWins: String(localized: "result.redWins")
        case .blackWins: String(localized: "result.blackWins")
        case .draw, .ongoing, .claimableDraw: String(localized: "result.draw")
        }
    }
}

#endif
