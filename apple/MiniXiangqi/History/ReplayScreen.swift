// A History record, read back.
//
// docs/interaction-design.md, "History replay": the board is read-only —
// replay offers no move input, no Undo, and no way to start a game from the
// displayed position — so this screen hands `BoardView` a position, the two
// states that are facts about it, and the step it is drawing, and nothing
// else. There is no selection, no legal destination, and no held piece
// anywhere in it, which is why the check rings alone carry check here: they
// are never hidden, because nothing is ever in the player's hand.
//
// The step is drawn by the same canvas that draws a played move, from the same
// transit state, and reports its arrival on the same two wires: a replayed
// game moves like a game.
//
// The same side-by-side shape play uses, with a different panel in it: what the
// game was, where in it the board is, the list, and the transport.
//
// **The header is the top of the page in both shapes.** Beside the board it is
// the first thing in the panel, which is already the top; beneath the board it
// is above the board rather than under it, which is where the play screen puts
// its own status and what the contract's stacked arrangement describes. The
// owner asked for exactly that from the iPhone (2026-07-30): the result line
// goes to the top of the page and the room it leaves goes to the move list.

import SwiftUI

struct ReplayScreen: View {
    let record: RecordSummary
    let library: HistoryLibrary

    @State private var replay: Replay?
    @State private var failure: CoreError?

    /// What the header above the board actually came to, measured rather than
    /// assumed — the same thing the play screen does with its turn status, and
    /// for the same reason: at an accessibility text size it is taller than any
    /// constant here, and the board is sized around what it really is. It
    /// starts at the height the default text size comes to, so the first frame
    /// is already the right size, and nothing it measures depends on the board.
    @State private var headerHeight: CGFloat = 66

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        Group {
            if let replay {
                layout(replay)
            } else if let failure {
                // The description under the title is the core's own diagnostic
                // text: not copy, and not localized.
                ContentUnavailableView("failure.gameDidNotStart",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(verbatim: failure.description).monospaced())
            } else {
                ProgressView()
            }
        }
        .environment(\.motionPolicy, policy)
        // The record's own instant names the screen: the destination is already
        // named by the back control beside it, and what a reader wants there is
        // which game this is. The words are the system's date formatting rather
        // than copy, so they are verbatim.
        .navigationTitle(Text(verbatim: record.whenText))
        // A page walked into from the list is titled beside the control that
        // walks back out, which is what iOS does with a pushed page — and what
        // the board on a phone can afford, since a large title is most of the
        // height the stacked shape spends on the board.
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            guard replay == nil else { return }
            switch library.replay(of: record, policy: policy) {
            case .success(let opened): replay = opened
            case .failure(let error): failure = error
            }
        }
        // Reduce Motion switched under a walk takes effect on the next step,
        // exactly as it does on the play screen.
        .onChange(of: policy) { _, updated in replay?.policy = updated }
        .onDisappear {
            // The detached session is the core's to hold open only for as long
            // as this screen wants it.
            replay?.close()
            replay = nil
        }
        // The app leaving the foreground pauses playback, as the accepted
        // behaviour asks: a game walking itself forward behind another app is
        // a game nobody is watching.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { replay?.pause() }
        }
    }

    private func layout(_ replay: Replay) -> some View {
        GeometryReader { proxy in
            switch BoardLayout.shape(in: proxy.size) {
            case .sideBySide:
                HStack(spacing: 0) {
                    board(replay, BoardLayout.geometry(in: proxy.size))
                    panel(replay, showsHeader: true, edge: .top)
                        .frame(width: BoardLayout.panelWidth)
                }
            case .stacked:
                stacked(replay, in: proxy.size)
            }
        }
        #if os(macOS)
        .frame(minWidth: BoardLayout.minimumWidth, minHeight: BoardLayout.minimumHeight)
        #endif
    }

    /// The header above the board, the board, the panel beneath it.
    ///
    /// The same three-part arrangement the play screen takes in this shape —
    /// what is true of the game above the board, the board, the controls below
    /// it — which is what the contract's stacked arrangement describes. The
    /// header used to be the first section *inside* the panel; moving it above
    /// the board is the owner's own iPhone feedback (2026-07-30), and what the
    /// panel does with the room is nothing: it keeps asking for the same 260
    /// points, so the whole of the header's former slot goes to the move list.
    ///
    /// Replay is the exception to the on-demand move list: its accepted
    /// behaviour needs the list to indicate the shown move and to let one be
    /// selected, so in this shape the list is on screen too and the
    /// surrounding chrome is what tightens to make room.
    ///
    /// The chrome's height is what it is *granted* rather than what it asks
    /// for, and the header is inside that grant rather than beside it: header
    /// plus panel is exactly the chrome the board is sized around, so the board
    /// cannot be drawn over either of them. A fixed block taken whole out of a
    /// short space would leave the board a slot its own floor does not fit in,
    /// which is a board drawn over the panel rather than a smaller one.
    /// `BoardLayout.stackedChrome(in:asking:)` reserves the board's floor first
    /// and hands the chrome the rest, on every platform: the reachable Mac
    /// windows that take this shape start at 535 points of content height, and
    /// an iPadOS window is sized by the system with no floor of the app's to
    /// stop it. Where the grant is short the panel is what gives way, because
    /// the header is a fact about the game and the list below it is what can be
    /// read a row at a time.
    private func stacked(_ replay: Replay, in size: CGSize) -> some View {
        let chrome = BoardLayout.stackedChrome(in: size,
                                               asking: headerHeight + panelHeight)
        return VStack(spacing: 0) {
            headerBlock(replay)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }

            board(replay, BoardLayout.stackedGeometry(in: size, chrome: chrome))

            panel(replay, showsHeader: false, edge: .bottom)
                .frame(height: max(0, chrome - headerHeight))
        }
    }

    /// What the panel beneath the board asks for: the list and the transport,
    /// in the height the transport needs plus room for six or seven rows of the
    /// game. It is the same number it asked for when the header was in it —
    /// which is the point, and the owner's: the header left and the list got
    /// its slot.
    private var panelHeight: CGFloat { 260 }

    private func board(_ replay: Replay, _ geometry: BoardGeometry) -> some View {
        BoardView(geometry: geometry,
                  placement: replay.placement,
                  flipped: replay.flipped,
                  lastMove: replay.lastMove,
                  checkedGeneral: replay.checkedGeneral,
                  transit: replay.transit,
                  transitFade: replay.transitFade,
                  policy: policy,
                  onTravelArrival: { replay.travelArrived() },
                  onFadeArrival: { replay.fadeArrived() })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The panel, beside the board or beneath it. `edge` is the window edge its
    /// material runs to — the top beside the board, where the title bar draws
    /// over it, and the bottom beneath the board, which is the edge this shape
    /// puts it on.
    ///
    /// `showsHeader` is what the two shapes disagree about, and only that:
    /// beside the board the panel's own top *is* the top of the page, so the
    /// header is in it; beneath the board the header is above the board
    /// instead, and the panel begins at the list.
    private func panel(_ replay: Replay, showsHeader: Bool, edge: Edge.Set) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                headerBlock(replay)

                Divider()
            }

            // Replay is the exception to the on-demand move list: its accepted
            // behaviour needs the list to indicate the shown move and to let
            // one be selected, so the list is part of the screen rather than
            // something reached from it.
            MoveList(notation: replay.notation,
                     currentMove: replay.ply > 0 ? replay.ply - 1 : nil,
                     onSelect: { replay.show(move: $0 + 1) })
                .padding(.horizontal, BoardLayout.panelInset)
                .frame(maxHeight: .infinity)

            Divider()

            ReplayTransport(isAtStart: replay.isAtStart,
                            isAtEnd: replay.isAtEnd,
                            autoplaying: replay.autoplaying,
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

    /// The header with the air around it, in the one set of insets both shapes
    /// use.
    ///
    /// They are the play screen's turn-status insets, arrived at from the other
    /// side: that element carries 12 points of its own padding — it has a
    /// background to fill — and the screen adds `panelInset - 12` beside it and
    /// 8 above and below, which comes to 16 and 20. This header has no
    /// background and therefore no padding of its own, so it states the same
    /// two numbers directly. The first line of a game and the first line of a
    /// record then start at the same place, which is what a reader walking
    /// between the two screens sees; what follows differs because a status line
    /// and a record's metadata are different sentences, not because the air
    /// around them was chosen twice.
    private func headerBlock(_ replay: Replay) -> some View {
        header(replay)
            .padding(.horizontal, BoardLayout.panelInset)
            .padding(.vertical, 20)
    }

    /// What the game was, and where in it the board is.
    ///
    /// Replay has no side-to-move line: describing a finished game's position
    /// as somebody's turn would be describing a game that is not being played.
    /// What stands in that place is the record's own metadata — the same line
    /// the History row carries — and the progress through it. The pair reads
    /// down the page's own leading edge, as every other block on this screen
    /// does; the title above it is the platform's and is centred or leading by
    /// the platform's own rule, not by this screen's.
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
