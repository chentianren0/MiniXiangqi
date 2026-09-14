// Reports the frame an animated progress arrives at its authored target.
//
// withAnimation's completion reports the whole transaction, and a committing
// move's transaction carries whatever the move caused. On this toolchain the
// transaction of a move that finishes the game — swapping the play controls,
// rewriting the turn status — never reports logical completion at all, which
// would leave the transition gate shut forever. The board cannot afford a
// completion that is allowed to be wrong: the gate opens at the landing.
//
// So the landing is reported by the one thing that cannot be wrong about it —
// the animated value itself, on the frame SwiftUI interpolates it onto its
// target. The transaction completion stays wired as a backstop for the case
// this cannot see, an animation skipped because nothing drew it, and the two
// paths meet in PlayMotion, which accepts whichever arrives first and ignores
// the other.

import SwiftUI

struct ArrivalReporter: ViewModifier, Animatable {
    private var target: Double
    private let arrived: () -> Void

    var animatableData: Double {
        didSet {
            // The setter runs only while SwiftUI interpolates, each frame
            // starting from the authored value — so `oldValue` is always the
            // target and only the new value says anything. The frame that
            // lands exactly on the target is the arrival; PlayMotion accepts
            // an arrival once, so a stray report answers to nothing.
            guard animatableData == target else { return }
            let arrived = arrived
            // After the frame, never during it: the arrival opens the gate,
            // which is state the current view update may not touch.
            DispatchQueue.main.async { arrived() }
        }
    }

    init(progress: Double, arrived: @escaping () -> Void) {
        self.animatableData = progress
        self.target = progress
        self.arrived = arrived
    }

    func body(content: Content) -> some View { content }
}
