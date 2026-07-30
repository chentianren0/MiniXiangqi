// A clock and a delay, as a seam.
//
// `MotionAnimator` already lets a test stand inside a transition for as long as
// it likes; this is the same idea for the two waits that are not animations —
// the floor the opponent's reply departs no earlier than, and the interval a
// search must run before its activity is worth showing. Both are named
// durations in `Motion`, and both would otherwise be tested by sleeping, which
// is how a suite becomes slow and flaky at once.
//
// The clock is `systemUptime` rather than `Date`: the floor is an elapsed
// interval, and an interval measured against a wall clock is an interval a
// time-zone change or an NTP step can make negative.

import Foundation

@MainActor
struct MotionTimer {
    var now: () -> TimeInterval
    var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let live = MotionTimer(
        now: { ProcessInfo.processInfo.systemUptime },
        after: { delay, body in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated(body)
            }
        })
}
