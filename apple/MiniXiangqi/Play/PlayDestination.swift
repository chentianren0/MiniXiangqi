// The Play destination, and the three pages inside it.
//
// docs/interaction-design.md, "Starting and configuring a game" and "Saving the
// active game before choosing a new mode": the home is the root, each mode's
// pre-start state and the board are pages over it, and the board can be left for
// the home without ending anything — which is how a player reaches the mode
// entries mid-game.
//
// **A navigation stack is what says that, and it is the platform's own way of
// saying it.** The back control, the title, the keyboard and pointer gestures
// that go with going back, and the animation between the pages are all the
// system's; the app decides only what the pages are. It is the same container
// History and Settings already use, so the destinations are built alike.
//
// The stack's path is `PlayState.page` and nothing else, because where the
// player is and what the app is doing are one fact: a created game *is* the
// board, and a filed one *is* the way back to the home. A pop is the only change
// the stack makes for itself, and it is handed back to the state to interpret —
// leaving a pre-start page discards its draft, and leaving the board leaves the
// game running.
//
// The window's own floor sits here rather than on any one page, so that walking
// between them cannot resize the window.

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
                stack
            } else {
                // The frames before the launch resume has answered. The
                // navigation is deliberately not built yet: a stack built at the
                // home and then handed the board would *push* to it, and a launch
                // with a game to resume opens at the board rather than travelling
                // there. Nothing is drawn rather than something that would then
                // have to be taken away.
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

    private var stack: some View {
        NavigationStack(path: path) {
            PlayHome(play: play)
                .navigationDestination(for: PlayState.Page.self) { page in
                    pushed(page)
                        // The floor again, because a pushed page does not
                        // inherit the one outside the stack: measured on the
                        // running app, a window that clamps to the minimum on
                        // the home shrinks past it the moment the board is
                        // pushed. Both floors are the same number, so the
                        // window's minimum is the same on every page and
                        // walking between them cannot resize the window.
                        .playContentFloor()
                }
        }
    }

    @ViewBuilder
    private func pushed(_ page: PlayState.Page) -> some View {
        switch page {
        case .home:
            // Unreachable: the home is the root and never a destination over
            // itself.
            EmptyView()
        case .setup(let mode):
            SetupScreen(play: play, mode: mode)
        case .board:
            PlayScreen(play: play, replay: replay)
        }
    }

    /// The path is the page, and the page is the path. The only change the stack
    /// makes on its own is a pop, and what a pop means is the state's to say.
    private var path: Binding<[PlayState.Page]> {
        Binding(get: { play.page == .home ? [] : [play.page] },
                set: { if $0.isEmpty { play.leaveTopPage() } })
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
