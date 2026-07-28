// A piece style: the disc, its resting shadow, and the board surface beneath
// it, as one coherent look.
//
// docs/interaction-design.md fixes the *requirements* on these colours — the
// symbol at 4.5:1 against its own disc face, the disc's boundary at 3:1 against
// the board surface, marker active ink at 4.5:1 and record ink at 3:1 against
// the board surface — and leaves the values themselves to each style's colour
// work. The values below satisfy those ratios; `BoardStyleTests` measures them
// rather than trusting this comment.
//
// Only 传统 is implemented so far. 现代 and 高对比 are accepted and still to
// come, which is why every value a view reads goes through this type.

import SwiftUI

struct BoardStyle {
    var boardSurface: Color
    var grid: Color

    var discFace: Color
    var discEdge: (Side) -> Color
    var discEdgeStroke: (Side) -> CGFloat   // as a multiple of the pitch
    var symbol: (Side) -> Color

    /// One marker ink at two strengths. Never a Red or Black role colour: those
    /// belong to the sides.
    var activeInk: Color
    var recordInk: Color

    /// A disc shadow, held as components so the lift can blend between the
    /// resting and lift shadows: the shadow rises with the scale, per the
    /// accepted selection transition, rather than snapping between two looks.
    struct Shadow {
        var opacity: Double
        var radius: CGFloat   // as a multiple of the pitch
        var y: CGFloat        // as a multiple of the pitch

        var color: Color { .black.opacity(opacity) }

        func blended(toward other: Shadow, by progress: Double) -> Shadow {
            Shadow(opacity: opacity + (other.opacity - opacity) * progress,
                   radius: radius + (other.radius - radius) * progress,
                   y: y + (other.y - y) * progress)
        }
    }

    var restingShadow: Shadow
    var liftShadow: Shadow

    /// 传统 — the default. Both sides use the same warm light disc face, as a
    /// physical set does, with the symbols themselves in the Red and Black role
    /// colours. The Black disc carries a heavier ring, so a second non-colour
    /// channel is always present.
    static let traditional = BoardStyle(
        boardSurface: Color(red: 0.910, green: 0.847, blue: 0.741),
        grid: Color(red: 0.361, green: 0.286, blue: 0.192),
        discFace: Color(red: 0.973, green: 0.937, blue: 0.851),
        discEdge: { $0 == .red
            ? Color(red: 0.478, green: 0.384, blue: 0.259)
            : Color(red: 0.114, green: 0.102, blue: 0.086) },
        discEdgeStroke: { $0 == .red ? 0.014 : 0.028 },
        symbol: { $0 == .red
            ? Color(red: 0.616, green: 0.129, blue: 0.098)
            : Color(red: 0.086, green: 0.078, blue: 0.067) },
        activeInk: Color(red: 0.075, green: 0.294, blue: 0.278),
        recordInk: Color(red: 0.302, green: 0.451, blue: 0.435),
        restingShadow: Shadow(opacity: 0.22, radius: 0.030, y: 0.018),
        liftShadow: Shadow(opacity: 0.30, radius: 0.075, y: 0.045))
}
