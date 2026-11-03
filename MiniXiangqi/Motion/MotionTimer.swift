// A seam for the two waits that are not animations, the reply floor and the
// search-activity delay, so they are tested without sleeping. `systemUptime`
// rather than `Date`: a wall-clock interval can go negative on a time-zone
// change or an NTP step.

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
