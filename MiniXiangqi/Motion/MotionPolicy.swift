// Reduce Motion is one rule, not per-feature flags.
//
// docs/interaction-design.md, "Motion and visual effects": anything that
// animates position, scale, or rotation becomes a brief crossfade; anything
// that animates opacity, colour, stroke weight, or shadow is unchanged,
// because none of those is motion; any spring that survives loses its
// overshoot rather than its duration; pulses are removed rather than
// converted; and the order in which things happen is untouched. States always
// survive — only travel disappears.
//
// The rule is written here once, and every animation consults it, so every
// future animation inherits it rather than re-deciding it.

import SwiftUI

struct MotionPolicy: Equatable {
    var reduceMotion: Bool

    /// The brief crossfade that stands in for removed travel.
    var crossfade: Animation { .linear(duration: Motion.crossfade) }

    /// An animation of position, scale, or rotation. Under Reduce Motion it
    /// becomes the crossfade; whoever draws the animated thing consults
    /// `reduceMotion` to render a dissolve in place of the travel, so the
    /// states still arrive — without movement.
    func movement(_ animation: Animation) -> Animation {
        reduceMotion ? crossfade : animation
    }

    /// An animation of opacity, colour, stroke weight, or shadow — not motion,
    /// so the rule leaves it exactly as given.
    func fade(_ animation: Animation) -> Animation {
        animation
    }

    /// A pulse: removed under Reduce Motion, never converted. The caller skips
    /// the pulse entirely when this is nil — the persistent treatment it
    /// decorated already says everything.
    func pulse(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// A movement that has no crossfade to fall back to — an animated scroll
    /// is the one in use — arrives immediately instead.
    func scroll(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// The result notice's entrance: a low-bounce spring on scale and opacity.
    /// Scale is motion, so under Reduce Motion the spring does not survive and
    /// the notice crossfades in at full size.
    var appear: Animation {
        reduceMotion ? crossfade : Motion.noticeAnimation
    }
}

extension EnvironmentValues {
    /// The policy the play screen derives from the system's Reduce Motion
    /// setting, for views that animate without a controller in reach.
    @Entry var motionPolicy = MotionPolicy(reduceMotion: false)
}
