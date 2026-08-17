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
//
// **The room it leaves is shared, and the share leans to the board**, which is
// the owner's second look at the same screen (2026-07-31): the first round gave
// the whole of it to the list and the board paid three points of pitch for it.

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
    @State private var headerHeight: CGFloat = 69

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(iOS)
    /// Whether the navigation container is presenting as a bar across the
    /// bottom, which is what the rule below is about. See `hidesDestinationBar`.
    @Environment(\.horizontalSizeClass) private var widthClass
    #endif

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
        // docs/interaction-design.md, "Navigation": a board screen hides the
        // destination bar where that bar is a bar across the bottom, and this
        // is one of the two. It is the owner's own recommendation from the
        // device pass (2026-07-31), made for this screen first: the bar's rows
        // are worth more to the page than the bar is under it.
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
            switch BoardLayout.shape(in: proxy.size, game: record.game) {
            case .sideBySide:
                HStack(spacing: 0) {
                    board(replay, BoardLayout.geometry(in: proxy.size,
                                                       game: record.game))
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
    /// the board is the owner's own iPhone feedback (2026-07-30), and the room
    /// that move frees is **shared, leaning to the board** — the owner's second
    /// look at the same screen (2026-07-31), after a first round that gave the
    /// whole of it to the list and charged the board three points of pitch for
    /// it. Two things pay the board back: the panel asks for less beneath the
    /// board than it does beside it, and the header claims no air below itself
    /// here, because the board's own allowance is already that air.
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
    /// `BoardLayout.stackedChrome(in:game:asking:)` reserves the board's floor first
    /// and hands the chrome the rest, on every platform: the reachable Mac
    /// windows that take this shape start at 535 points of content height, and
    /// an iPadOS window is sized by the system with no floor of the app's to
    /// stop it. Where the grant is short the panel is what gives way, because
    /// the header is a fact about the game and the list below it is what can be
    /// read a row at a time.
    private func stacked(_ replay: Replay, in size: CGSize) -> some View {
        let chrome = BoardLayout.stackedChrome(in: size, game: record.game,
                                               asking: headerHeight + panelHeight)
        let geometry = BoardLayout.stackedGeometry(in: size, game: record.game,
                                                   chrome: chrome)
        return VStack(spacing: 0) {
            headerBlock(replay, airBelow: 0)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }

            // A stacked board screen, so the same full-width fitting and the
            // same surface behind it: where the width is what sized this board,
            // it meets the glass rather than leaving a sliver of page beside it.
            board(replay, geometry,
                  bleed: BoardLayout.surfaceBleed(in: size.width, board: geometry))

            panel(replay, showsHeader: false, edge: .bottom)
                .frame(height: max(0, chrome - headerHeight))
        }
    }

    /// What the panel beneath the board asks for: the list and the transport,
    /// in the height the transport needs plus room for four rows of the game.
    ///
    /// **This is the one number the owner's buy-back decision moves**
    /// (2026-07-31), and it is settled against rendered screens rather than
    /// reasoned about here. The panel used to ask beneath the board for exactly
    /// what it asks beside it, and on a phone that ask is refused anyway — the
    /// grant below is the whole of what is left once a floor-sized board is
    /// reserved, so asking for more than the phone has just pins the board on
    /// its floor. Asking for less is what hands the board its pitch back, and
    /// every point of it costs the list a point of the same height, so the
    /// number is exactly where the two stop: **200** leaves a 402-point iPhone
    /// a 52-point pitch under the full-width fitting, and is the smallest ask
    /// that still draws the seven-ply game's fourth row whole beneath it. What
    /// binds this board is that height rather than the width — the panel is
    /// granted its room before the board is fitted — so the full-width pitches
    /// the play board reaches are not this screen's. Beside the
    /// board there is no such contest and the panel is the width it always was.
    /// Plus the captured surface's own grant where the record's game carries
    /// one, so the board is sized around the chrome that is really there rather
    /// than around the chrome every other game has.
    private var panelHeight: CGFloat {
        record.game.conceals ? 200 + BoardLayout.capturedSurfaceHeight : 200
    }

    private func board(_ replay: Replay, _ geometry: BoardGeometry,
                       bleed: CGFloat = 0) -> some View {
        // The ending discloses the deal, so the position the game ended in
        // shows every identity it was still concealing — and a walk back out of
        // it shows the game as it was played, which is what the record holds at
        // that ply. One settle, by opacity, as on the board that played it.
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(policy.fade(Motion.stateFadeAnimation), value: disclosure)
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
                headerBlock(replay, airBelow: 20)

                Divider()
            }

            // The captured-pieces surface, in the game that has one. **A record
            // is a game already over**, so what it shows is the disclosed
            // surface both players read the same — and it follows the walk, so
            // it shows what had been taken by the position on screen.
            if replay.record.game.conceals {
                // Inside its own grant, and scrolling there: beneath the board
                // this panel is a fixed height shared with the list and the
                // transport, and a side that has lost a whole complement must
                // not take the room the list is standing in.
                ScrollView {
                    CapturedPiecesView(captured: replay.captured,
                                       game: replay.record.game,
                                       throughPly: replay.ply,
                                       viewer: nil,
                                       disclosed: true)
                        .padding(.horizontal, BoardLayout.panelInset)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: BoardLayout.capturedSurfaceHeight)

                Divider()
            }

            // Replay is the exception to the on-demand move list: its accepted
            // behaviour needs the list to indicate the shown move and to let
            // one be selected, so the list is part of the screen rather than
            // something reached from it.
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

    /// The header with the air around it: the one leading edge both shapes use,
    /// and the air above it that both shapes use too.
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
    ///
    /// `airBelow` is the one inset the two shapes disagree about, because what
    /// follows the header differs: beside the board a `Divider` follows and the
    /// header states its own 20-point gap to it, as it states the gap above.
    /// Beneath the board the **board's own allowance** follows —
    /// `BoardLayout.boardPadding`, 24 points of air already reserved above the
    /// block — and a gap stated here as well would be a second one drawn on top
    /// of the first. It would also be a gap the board paid for: beneath the
    /// board the header sits inside the chrome the board is sized around, so
    /// every point of air here is a point of board. That is the half of the
    /// owner's buy-back (2026-07-31) that the panel's own ask does not reach.
    private func headerBlock(_ replay: Replay, airBelow: CGFloat) -> some View {
        header(replay)
            .padding(.horizontal, BoardLayout.panelInset)
            .padding(.top, 20)
            .padding(.bottom, airBelow)
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
