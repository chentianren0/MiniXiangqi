// Reduce Motion is one rule, written once: position, scale and rotation become
// a brief crossfade; opacity, colour, stroke weight and shadow are unchanged,
// since none is motion; a surviving spring loses its overshoot, not its
// duration; pulses are removed, not converted; order is untouched. States
// always survive; only travel disappears.

import SwiftUI

struct MotionPolicy: Equatable {
    var reduceMotion: Bool

    var crossfade: Animation { .linear(duration: Motion.crossfade) }

    /// Whoever draws the animated thing consults `reduceMotion` to render a
    /// dissolve in place of the travel, so the states still arrive.
    func movement(_ animation: Animation) -> Animation {
        reduceMotion ? crossfade : animation
    }

    /// Not motion, so left exactly as given.
    func fade(_ animation: Animation) -> Animation {
        animation
    }

    /// Nil under Reduce Motion, and the caller skips the pulse: the persistent
    /// treatment it decorated already says everything.
    func pulse(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// A movement that has no crossfade to fall back to — an animated scroll
    /// is the one in use — arrives immediately instead.
    func scroll(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Scale is motion, so under Reduce Motion the notice crossfades in at full
    /// size.
    var appear: Animation {
        reduceMotion ? crossfade : Motion.noticeAnimation
    }
}

extension EnvironmentValues {
    /// For views that animate without a controller in reach.
    @Entry var motionPolicy = MotionPolicy(reduceMotion: false)
}
