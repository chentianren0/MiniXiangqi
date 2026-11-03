// withAnimation's completion reports the whole transaction, and the transaction
// of a move that finishes the game never reports logical completion, which
// would leave the transition gate shut forever. So the landing is reported by
// the animated value itself, on the frame it reaches its target. The
// transaction completion stays wired as a backstop for an animation skipped
// because nothing drew it; PlayMotion accepts whichever arrives first.

import SwiftUI

struct ArrivalReporter: ViewModifier, Animatable {
    private var target: Double
    private let arrived: () -> Void

    var animatableData: Double {
        didSet {
            // The setter runs only while SwiftUI interpolates, each frame
            // starting from the authored value, so `oldValue` is always the
            // target. PlayMotion accepts an arrival once, so a stray report
            // answers to nothing.
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
