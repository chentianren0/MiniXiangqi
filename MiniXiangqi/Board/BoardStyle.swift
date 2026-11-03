// Contrast floors every style must meet: the symbol 4.5:1 against its disc
// face, the disc's boundary 3:1 against the board surface, marker active ink
// 4.5:1 and record ink 3:1 against the board surface.

import SwiftUI

struct BoardStyle {
    var boardSurface: Color
    var grid: Color

    var discFace: Color
    var discEdge: (Side) -> Color
    var discEdgeStroke: (Side) -> CGFloat   // as a multiple of the pitch
    var symbol: (Side) -> Color

    /// A stone carries no symbol, so its colour is all that says whose it is.
    /// `Side` is the core's axis, so the first mover's stone is the black one.
    var stoneFace: (Side) -> Color
    /// Carries the 3:1 boundary: a light stone's face is close to the board
    /// surface, and only the edge separates them.
    var stoneEdge: (Side) -> Color
    /// One weight for both sides, as a multiple of the pitch: unlike the discs,
    /// the stones' colours already tell them apart.
    var stoneEdgeStroke: CGFloat

    /// One marker ink at two strengths. Never a Red or Black role colour: those
    /// belong to the sides.
    var activeInk: Color
    var recordInk: Color

    /// The marker ink `muted` of the way from its active strength to its record
    /// strength, mixed in device space, the space both strengths are stated in.
    /// Increase Contrast leaves a muted marker alone: record strength is the
    /// whole of what the muting says.
    func markerInk(muted: Double) -> Color {
        activeInk.mix(with: recordInk, by: min(max(muted, 0), 1), in: .device)
    }

    /// Held as components so the lift can blend between the resting and lift
    /// shadows rather than snap.
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

    /// 传统, the default. Both sides share one disc face, as a physical set
    /// does; the Black disc's heavier ring is a second non-colour channel.
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
        stoneFace: { $0 == .red
            ? Color(red: 0.102, green: 0.094, blue: 0.086)
            : Color(red: 0.965, green: 0.949, blue: 0.918) },
        // Shell white is too close to the board surface to be a boundary by
        // itself, so the white stone takes the Red disc's brown edge.
        stoneEdge: { $0 == .red
            ? Color(red: 0.055, green: 0.051, blue: 0.047)
            : Color(red: 0.478, green: 0.384, blue: 0.259) },
        stoneEdgeStroke: 0.020,
        activeInk: Color(red: 0.075, green: 0.294, blue: 0.278),
        recordInk: Color(red: 0.302, green: 0.451, blue: 0.435),
        restingShadow: Shadow(opacity: 0.22, radius: 0.030, y: 0.018),
        liftShadow: Shadow(opacity: 0.30, radius: 0.075, y: 0.045))
}
