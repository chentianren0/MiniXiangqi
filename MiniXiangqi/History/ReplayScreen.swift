// The board is read-only: no move input, no Undo, no way to start a game from
// the shown position, and no held piece, so the check rings alone carry check.

import SwiftUI

struct ReplayScreen: View {
    let record: GameRecord
    let library: HistoryLibrary

    @State private var replay: Replay?
    @State private var failure: CoreError?

    /// Whether the stacked shape's on-demand captured-pieces surface is up.
    @State private var capturedShown = false
    /// Measured as the play screen measures its own: a GeometryReader at a
    /// sheet's root has no ideal size, and on macOS the sheet takes exactly its
    /// content's ideal.
    @State private var capturedWidth: CGFloat = 0

    /// Measured rather than assumed: at an accessibility text size the header is
    /// taller than any constant. Starts at the default text size's height so the
    /// first frame is right; nothing it measures depends on the board.
    @State private var headerHeight: CGFloat = 69

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        Group {
            if let replay {
                layout(replay)
            } else if let failure {
                // The core's diagnostic text, not localized.
                ContentUnavailableView("failure.gameDidNotStart",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(verbatim: failure.description).monospaced())
            } else {
                ProgressView()
            }
        }
        .environment(\.motionPolicy, policy)
        // The back control already names the destination, so the title says
        // which game this is. System date formatting, so verbatim.
        .navigationTitle(Text(verbatim: record.whenText))
        // Inline: a large title is most of the height the stacked shape spends
        // on the board.
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // A board screen hides the destination bar where it is a bar across the
        // bottom: its rows are worth more to the page.
        #if os(iOS)
        .toolbar(hidesDestinationBar(widthClass) ? .hidden : .automatic, for: .tabBar)
        #endif
        .onAppear {
            guard replay == nil else { return }
            switch library.replay(of: record, policy: policy) {
            case .success(let opened): replay = opened
            case .failure(let error): failure = error
            }
        }
        .onChange(of: policy) { _, updated in replay?.policy = updated }
        .onDisappear {
            replay?.close()
            replay = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { replay?.pause() }
        }
    }

    private func layout(_ replay: Replay) -> some View {
        GeometryReader { proxy in
            switch BoardLayout.shape(in: proxy.size, game: record.kind) {
            case .sideBySide:
                HStack(spacing: 0) {
                    board(replay, BoardLayout.geometry(in: proxy.size,
                                                       game: record.kind))
                    panel(replay, beside: true, edge: .top)
                        .frame(width: BoardLayout.panelWidth)
                }
            case .stacked:
                stacked(replay, in: proxy.size)
            }
        }
        // Declared here rather than in the stacked branch: a sheet inside one
        // branch is re-presented every time the layout returns to that branch.
        .sheet(isPresented: $capturedShown) { capturedSheet(replay) }
        #if os(macOS)
        .frame(minWidth: BoardLayout.minimumWidth, minHeight: BoardLayout.minimumHeight)
        #endif
    }

    /// The header above the board, the board, the panel beneath it. Replay keeps
    /// its move list on screen in this shape too, so the chrome tightens instead.
    ///
    /// The header is inside the chrome's grant rather than beside it, so the
    /// board cannot be drawn over either. `stackedChrome` reserves the board's
    /// floor first and hands the chrome the rest; where the grant is short the
    /// panel gives way, since the list can be read a row at a time.
    private func stacked(_ replay: Replay, in size: CGSize) -> some View {
        let chrome = BoardLayout.stackedChrome(in: size, game: record.kind,
                                               asking: headerHeight + panelHeight)
        let geometry = BoardLayout.stackedGeometry(in: size, game: record.kind,
                                                   chrome: chrome)
        return VStack(spacing: 0) {
            headerBlock(replay, airBelow: 0)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }

            // Where the width sized the board, its surface meets the glass
            // rather than leaving a sliver of page beside it.
            board(replay, geometry,
                  bleed: BoardLayout.surfaceBleed(in: size.width, board: geometry))

            panel(replay, beside: false, edge: .bottom)
                .frame(height: max(0, chrome - headerHeight))
        }
        .toolbar {
            // Reached rather than resident in this shape: the board's floor and
            // the list's room come before a third resident block.
            if record.kind.conceals {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        capturedShown = true
                    } label: {
                        Label("captured.title", systemImage: "tray.full")
                    }
                    .accessibilityIdentifier("replay-captured")
                }
            }
        }
    }

    /// The panel's ask beneath the board, settled against rendered screens. On
    /// a phone every point of it comes out of the board's pitch; 200 is the
    /// smallest ask that still draws a fourth row of moves whole.
    private var panelHeight: CGFloat { 200 }

    private func board(_ replay: Replay, _ geometry: BoardGeometry,
                       bleed: CGFloat = 0) -> some View {
        let disclosure: Double = replay.disclosesTheDeal ? 1 : 0
        return BoardView(geometry: geometry,
                  placement: replay.placement,
                  flipped: replay.flipped,
                  lastMove: replay.lastMove,
                  checkedGeneral: replay.checkedGeneral,
                  transit: replay.transit,
                  transitFade: replay.transitFade,
                  transitReveal: replay.transitReveal,
                  disclosure: disclosure,
                  policy: policy,
                  surfaceBleed: bleed,
                  onTravelArrival: { replay.travelArrived() },
                  onFadeArrival: { replay.fadeArrived() })
            .boardHaptics(landings: replay.landings)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(policy.fade(Motion.stateFadeAnimation), value: disclosure)
    }

    /// `edge` is the window edge its material runs to. Beside the board the
    /// panel's top is the page's top, so the header and a resident captured
    /// section are in it; beneath the board the header sits above the board and
    /// the captured surface is reached from the toolbar.
    private func panel(_ replay: Replay, beside: Bool, edge: Edge.Set) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if beside {
                headerBlock(replay, airBelow: 20)

                Divider()
            }

            if beside && replay.game.conceals {
                // Sized by its rows rather than scrolling: the list below keeps
                // its own scroll.
                captured(replay)
                    .padding(.horizontal, BoardLayout.panelInset)
                    .padding(.vertical, 8)

                Divider()
            }

            // Resident rather than on demand: replay's list marks the shown
            // move and lets one be selected.
            MoveList(notation: replay.notation,
                     firstMover: replay.firstMover,
                     currentMove: replay.ply > 0 ? replay.ply - 1 : nil,
                     onSelect: { replay.show(move: $0 + 1) })
                .padding(.horizontal, BoardLayout.panelInset)
                .frame(maxHeight: .infinity)

            Divider()

            ReplayTransport(isAtStart: replay.isAtStart,
                            isAtEnd: replay.isAtEnd,
                            autoplaying: replay.autoplaying,
                            carriesFlip: replay.carriesFlip,
                            goToStart: { replay.goToStart() },
                            stepBack: { replay.stepBack() },
                            toggleAutoplay: { replay.toggleAutoplay() },
                            stepForward: { replay.stepForward() },
                            goToEnd: { replay.goToEnd() },
                            flip: { withAnimation(policy.movement(Motion.flipAnimation)) {
                                replay.flipped.toggle()
                            } })
                .padding(BoardLayout.panelInset)
        }
        .frame(maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(.container, edges: edge)
        }
    }

    private func captured(_ replay: Replay,
                          pitch: CGFloat = BoardLayout.capturedDiscPitch) -> some View {
        CapturedPiecesView(captured: replay.captured,
                           game: replay.game,
                           throughPly: replay.ply,
                           viewer: nil,
                           disclosed: true,
                           pitch: pitch)
    }

    private func capturedSheet(_ replay: Replay) -> some View {
        NavigationStack {
            // The pitch a board of the sheet's own width would carry.
            ScrollView {
                captured(replay,
                         pitch: BoardLayout.capturedSheetPitch(in: capturedWidth,
                                                               game: replay.game))
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

    /// The insets the play screen's turn status comes to (16 beside, 20 above),
    /// stated directly since this header has no background padding of its own,
    /// so a game's and a record's first lines start at the same place.
    ///
    /// Beneath the board `airBelow` is 0: the board's own allowance already
    /// follows, and any air here would come out of the board.
    private func headerBlock(_ replay: Replay, airBelow: CGFloat) -> some View {
        header(replay)
            .padding(.horizontal, BoardLayout.panelInset)
            .padding(.top, 20)
            .padding(.bottom, airBelow)
    }

    /// Replay has no side-to-move line: a finished game is nobody's turn. The
    /// record's metadata and the progress stand in its place.
    private func header(_ replay: Replay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: String(localized: "replay.progress"),
                        replay.ply, replay.moves.count))
                .font(.title3.weight(.medium).monospacedDigit())
                .accessibilityIdentifier("replay-progress")

            Text(record.metadataLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("replay-metadata")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
