// The Play destination, and the three pages inside it.
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
// one game, three pages, and no history to keep.
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
                // drawn rather than a home the launch is about to leave: a
                // launch with a game to resume opens at the board.
                Color.clear
            }
        }
        .environment(\.motionPolicy, policy)
        .playContentFloor()
        .task {
            play.startIfNeeded(policy: policy)
        }
        // Leaving the destination altogether discards a pre-start draft and
        // invalidates an attempt in flight. The container tears this down on
        // every switch away, which is exactly the event the contract means by
        // leaving the page; going *deeper* is not, and does not come through
        // here.
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
                .navigationTitle("nav.play")
                .toolbar {
                    if play.page != .home {
                        ToolbarItem(placement: .navigation) {
                            // Named for where it goes, which is how the
                            // platform's own back control names itself: it
                            // carries the previous page's title. Here that is
                            // always the Play home.
                            Button {
                                play.leaveTopPage()
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
        switch play.page {
        case .home:
            PlayHome(play: play)
        case .setup(let mode):
            SetupScreen(play: play, mode: mode)
        case .board:
            PlayScreen(play: play, replay: replay)
        }
    }
}

private extension View {
    /// The play content's accepted floor, 616 by 388.
    ///
    /// It belongs to the destination rather than to the board alone: a window
    /// that could be shrunk on one page and then walked to another is a window
    /// that clips the board, so every page carries the same number and the
    /// minimum never changes underneath the player. `-mxq-no-minimum` takes it
    /// off so a screenshot can show what the layout does below it.
    func playContentFloor() -> some View {
        #if DEBUG
        let lifted = DebugLaunch.contains("-mxq-no-minimum")
        return frame(minWidth: lifted ? nil : BoardLayout.minimumWidth,
                     minHeight: lifted ? nil : BoardLayout.minimumHeight)
        #else
        return frame(minWidth: BoardLayout.minimumWidth,
                     minHeight: BoardLayout.minimumHeight)
        #endif
    }
}
