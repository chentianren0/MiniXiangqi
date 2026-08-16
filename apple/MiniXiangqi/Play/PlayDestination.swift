// The Play destination, and the pages inside it.
//
// docs/interaction-design.md, "Starting and configuring a game" and "Saving the
// active game before choosing a new mode": the home is the root, each mode's
// pre-start state and the board are pages over it, and the board can be left for
// the home without ending anything — which is how a player reaches the mode
// entries mid-game.
//
// **The page on screen is `PlayState.page`, drawn directly, with a back control
// in the toolbar over the two pages that have one.** A navigation stack driving
// its own path was tried first and is not usable here, for a reason measured on
// the running app rather than guessed at: a `navigationDestination` registration
// does not survive the destination being torn down and rebuilt, which is exactly
// what switching to another tab and back does. After that round trip a stack
// asked for a page arrives at SwiftUI's own no-matching-destination placeholder
// — a warning triangle on an empty page — and, worse, it then *clears its own
// path*, which reaches the app looking exactly like the player having gone back:
// a game walked away from and returned to came back at the home rather than at
// its board. Rebuilding the stack per visit fixed the first symptom and not the
// second. Drawing the page is what this destination actually needs: one window,
// one game, a handful of pages, and no history to keep.
//
// What that costs is the system's own back button and the gestures around it,
// and what it buys is a destination that is where the state says it is. The
// control below is the same chevron in the same place, and it says where it goes
// the way the platform's own does — by naming the page it returns to.
//
// The play content's floor is the destination's rather than the board's, and it
// is the same number on every page, so that walking between them cannot resize
// the window.

import SwiftUI

struct PlayDestination: View {
    /// The game, and the presentation state that belongs to it. Held above the
    /// navigation container, because the container rebuilds this destination
    /// every time the player comes back to it and the game is not a tab's to
    /// create twice.
    let play: PlayState

    /// Opens one History record's replay. The screen it opens on is not in this
    /// destination, so the container above both is what performs it; 回放 on a
    /// recorded result is the only thing that asks.
    var replay: (UInt64) -> Void

    /// The nearby feature, where this device has one. Its board is a page over
    /// this destination like the other two, and it is drawn from here for the
    /// same reason they are — but the session behind it belongs to the peer and
    /// outlives every page, so nothing about leaving this destination touches
    /// it.
    var nearby: NearbyFlow?

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
                // The frames before the launch resume has answered. Nothing is
                // drawn rather than a home without the card the resume is about
                // to put on it.
                Color.clear
            }
        }
        .environment(\.motionPolicy, policy)
        .playContentFloor()
        .task {
            play.startIfNeeded(policy: policy)
            // The board surface owns the session, the engine and any owed
            // search, and this destination is rebuilt on every visit — so a
            // return to a board that was left standing opens its game again.
            // A board that already holds one asks the store for nothing, which
            // is what makes this safe to run on every appearance.
            play.enterBoard(policy: policy)
        }
        // Leaving the destination altogether discards a pre-start draft and
        // invalidates an attempt in flight. The container tears this down on
        // every switch away, which is exactly the event the contract means by
        // leaving the page; going *deeper* is not, and does not come through
        // here.
        //
        // **Putting the game itself down does not belong here.** This fires
        // when SwiftUI disposes the view, and SwiftUI disposes it at moments
        // that are not the player leaving: the container builds and drops tab
        // content while the window is coming up, and a game torn down there is
        // torn down under a board that is still on screen. What the session's
        // life hangs on is state the app owns — the selected destination, above
        // this view, and the page below it — never a view's lifecycle.
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
                // The root carries the platform's large title and the two pages
                // over it carry the inline one, which is what iOS does with a
                // stack: a large title announces a destination you have arrived
                // at, and a page you walked into is titled beside the control
                // that walks back out. It is also what the board can afford —
                // a large title is most of a phone's spare height, and the
                // stacked shape spends that height on the board.
                //
                // **The title itself belongs to the page**, because a board page
                // in the stacked shape has none: its bar centre carries the turn
                // status in the title's place, per docs/interaction-design.md
                // § Turn status. A title set here would stand over that one and
                // name a page nobody needs named.
                #if !os(macOS)
                .navigationBarTitleDisplayMode(showsBackControl ? .inline : .large)
                #endif
                .toolbar {
                    if showsBackControl {
                        ToolbarItem(placement: .navigation) {
                            // Named for where it goes, which is how the
                            // platform's own back control names itself: it
                            // carries the previous page's title. Here that is
                            // always the Play home.
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

    @ViewBuilder
    private var page: some View {
        #if os(iOS)
        if let nearby, nearby.boardSessionID != nil {
            // A nearby game is over every page of this destination, because it
            // is the game this device is playing: the local pages are still
            // there underneath it, exactly where the player left them.
            NearbyBoardScreen(flow: nearby)
        } else {
            playPage
        }
        #else
        playPage
        #endif
    }

    @ViewBuilder
    private var playPage: some View {
        switch play.page {
        case .home:
            PlayHome(play: play, nearby: nearby)
                .navigationTitle("nav.play")
        case .setup(let selection):
            SetupScreen(play: play, selection: selection)
                .navigationTitle("nav.play")
        // The Custom Scene editor: a pre-start page like the one above it, over
        // an interactive board rather than a preview.
        //
        // **It is titled with its own name rather than with Play's.** A
        // pre-start page for a mode is a page about that mode, and this one is
        // the only page in the destination that is a *place* rather than a
        // step: it is where a position is composed, it stands alone with the
        // destination bar hidden, and a title reading 对局 over it named the
        // destination the reader had already left.
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

    /// Whether the page on screen is one over the home, whichever kind it is.
    private var showsBackControl: Bool {
        #if os(iOS)
        if nearby?.boardSessionID != nil { return true }
        #endif
        return play.page != .home
    }

    private func leaveTopPage() {
        #if os(iOS)
        if let nearby, nearby.boardSessionID != nil {
            nearby.leaveBoard()
            return
        }
        #endif
        play.leaveTopPage()
    }
}

private extension View {
    /// The play content's accepted floor, 616 by 416 —
    /// docs/interaction-design.md, "Layout shapes", where the height is
    /// Xiangqi's and the width Mini Xiangqi's.
    ///
    /// It belongs to the destination rather than to the board alone: a window
    /// that could be shrunk on one page and then walked to another is a window
    /// that clips the board, so every page carries the same number and the
    /// minimum never changes underneath the player. `-mxq-no-minimum` takes it
    /// off so a screenshot can show what the layout does below it.
    ///
    /// **It is a window's floor, so it is macOS's.** What a minimum does is stop
    /// a resize; iOS and iPadOS have no resize to stop — the screen is the size
    /// it is, and a multitasking iPad is sized by the system rather than by the
    /// app. A 616-point minimum on a 440-point phone would not widen anything.
    /// It would only tell SwiftUI the content is wider than the screen, and the
    /// stacked shape exists precisely so that it is not.
    func playContentFloor() -> some View {
        #if os(macOS)
        #if DEBUG
        let lifted = DebugLaunch.contains("-mxq-no-minimum")
        return frame(minWidth: lifted ? nil : BoardLayout.minimumWidth,
                     minHeight: lifted ? nil : BoardLayout.minimumHeight)
        #else
        return frame(minWidth: BoardLayout.minimumWidth,
                     minHeight: BoardLayout.minimumHeight)
        #endif
        #else
        return self
        #endif
    }
}
