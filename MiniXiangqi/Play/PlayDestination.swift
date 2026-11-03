// The page on screen is `PlayState.page`, drawn directly, not a navigation
// stack's path: a `navigationDestination` registration does not survive the
// destination being torn down and rebuilt, as a tab switch does, and the stack
// then clears its own path, which looks exactly like the player going back. So
// the back control below is this file's own chevron, labelled with the page it
// returns to.

import SwiftUI

struct PlayDestination: View {
    /// Held above the navigation container, which rebuilds this destination on
    /// every return; the game is not a tab's to create twice.
    let play: PlayState

    /// The replay screen lives outside this destination, so the container above
    /// both performs it.
    var replay: (UUID) -> Void

    /// The peer session behind a nearby or online board outlives every page, so
    /// leaving this destination never touches it.
    var nearby: NearbyFlow?
    var online: NearbyFlow?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        Group {
            if let startFailure = play.startFailure {
                // The description under the title is the core's own diagnostic
                // text: not copy, and not localized.
                ContentUnavailableView("failure.gameDidNotStart",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(verbatim: startFailure.description).monospaced())
            } else if play.started {
                pages
            } else {
                // Before the launch resume has answered: nothing rather than a
                // home missing the card the resume is about to put on it.
                Color.clear
            }
        }
        .environment(\.motionPolicy, policy)
        .playContentFloor()
        .task {
            play.startIfNeeded(policy: policy)
            // This destination is rebuilt on every visit, so a return to a board
            // left standing opens its game again. A board that already holds one
            // asks the library for nothing, so this is safe on every appearance.
            play.enterBoard(policy: policy)
        }
        // Discards a pre-start draft and invalidates an attempt in flight.
        //
        // The game itself is not put down here: SwiftUI also disposes this view
        // while the window is coming up, under a board still on screen. The
        // session's life hangs on state the app owns, never a view's lifecycle.
        .onDisappear {
            play.leavePage()
        }
        .onChange(of: reduceMotion) {
            play.adopt(policy)
        }
    }

    private var pages: some View {
        NavigationStack {
            page
                .playContentFloor()
                // A large title for the root, inline for the pages over it: a
                // large title is most of a phone's spare height, which the
                // stacked board needs. Each page sets its own title, because a
                // stacked board page puts the turn status in the title's place.
                #if !os(macOS)
                .navigationBarTitleDisplayMode(showsBackControl ? .inline : .large)
                #endif
                .toolbar {
                    if showsBackControl {
                        ToolbarItem(placement: .navigation) {
                            // Labelled with where it goes, as the platform's
                            // back control is: always the Play home.
                            Button {
                                leaveTopPage()
                            } label: {
                                Image(systemName: "chevron.backward")
                            }
                            .accessibilityLabel(Text("nav.play"))
                            .accessibilityIdentifier("play-back")
                        }
                    }
                }
        }
    }

    /// At most one flow ever has a board: a networked game is the library's one
    /// active game, and a flow must get the active-game slot before opening a
    /// board. So the order here settles nothing.
    ///
    /// It asks the flows rather than the platform: with no flow, or one that
    /// never opens a board, the local page is drawn without a gate.
    private var board: NearbyFlow? {
        [nearby, online].compactMap { $0 }.first { $0.boardSessionID != nil }
    }

    @ViewBuilder
    private var page: some View {
        if let board {
            // A game with somebody covers every page; the local pages stay
            // underneath, exactly where the player left them.
            NearbyBoardScreen(flow: board)
        } else {
            playPage
        }
    }

    @ViewBuilder
    private var playPage: some View {
        switch play.page {
        case .home:
            PlayHome(play: play, nearby: nearby, online: online)
                .navigationTitle("nav.play")
        case .setup(let selection):
            SetupScreen(play: play, selection: selection)
                .navigationTitle("nav.play")
        // Titled with its own name: it is a place where a position is composed,
        // standing alone with the destination bar hidden, not a step under Play.
        case .customScene:
            if let scene = play.scene {
                CustomSceneScreen(play: play, scene: scene)
                    .navigationTitle("mode.customScene")
            }
        // The board titles itself, and in the stacked shape it does not: what
        // stands in the bar's centre there is the turn status.
        case .board:
            PlayScreen(play: play, replay: replay)
        }
    }

    private var showsBackControl: Bool {
        board != nil || play.page != .home
    }

    private func leaveTopPage() {
        if let board {
            board.leaveBoard()
            return
        }
        play.leaveTopPage()
    }
}

private extension View {
    /// Xiangqi's height and the placement board's width, the same on every page
    /// so that walking between pages never clips the board.
    ///
    /// macOS only: iOS has no window resize to stop, and a minimum wider than a
    /// phone would only tell SwiftUI the content is wider than the screen.
    func playContentFloor() -> some View {
        #if os(macOS)
        return frame(minWidth: BoardLayout.minimumWidth,
                     minHeight: BoardLayout.minimumHeight)
        #else
        return self
        #endif
    }
}
