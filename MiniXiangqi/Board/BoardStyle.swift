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
// Only 传统 is implemented so far. 现代 and 高对比度 are accepted and still to
// come, which is why every value a view reads goes through this type.

import SwiftUI

struct BoardStyle {
    var boardSurface: Color
    var grid: Color

    var discFace: Color
    var discEdge: (Side) -> Color
    var discEdgeStroke: (Side) -> CGFloat   // as a multiple of the pitch
    var symbol: (Side) -> Color

    /// A stone's face, which is where the placement games' two sides part
    /// company: a disc's two sides share one face and are told apart by the
    /// character on it, and a stone carries no symbol at all, so its colour is
    /// the whole of what says whose it is.
    ///
    /// `Side` is the core's axis — the side that moves first, and the other — so
    /// on these boards the first mover's stone is the black one. Nothing here
    /// renames a side; it only says what each is drawn in.
    var stoneFace: (Side) -> Color
    /// The stone's boundary against the board. It carries the same 3:1 the
    /// disc's edge does, and it is what carries it: a light stone's face is
    /// close to the board surface, and the edge is the only thing that can
    /// separate them.
    var stoneEdge: (Side) -> Color
    /// One weight for both, as a multiple of the pitch. The disc's edge takes a
    /// weight per side because both discs share a face and the heavier ring is a
    /// second non-colour channel; two stones of different colours need no such
    /// channel, so the edge here is a boundary and nothing else.
    var stoneEdgeStroke: CGFloat

    /// One marker ink at two strengths. Never a Red or Black role colour: those
    /// belong to the sides.
    var activeInk: Color
    var recordInk: Color

    /// The marker ink `muted` of the way from its active strength to its record
    /// strength. While a suggestion stands the rest of the held piece's
    /// destinations drop to record ink, so that the suggested marker is the one
    /// active-ink mark the selection shows; they cross between the two strengths
    /// rather than switching, because the drop rides the suggestion's own phase.
    /// Mixed in the device's own space, which is the space the two strengths are
    /// stated in and the space a wash composites over the board in.
    ///
    /// A muted marker is the one place record strength is itself the live
    /// distinction, so Increase Contrast leaves it where it is: promoting it to
    /// active-ink values would erase the only thing the muting says.
    func markerInk(muted: Double) -> Color {
        activeInk.mix(with: recordInk, by: min(max(muted, 0), 1), in: .device)
    }

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
    ///
    /// The stones are the same set's other box: a slate black and a shell white,
    /// on the same board surface, in the same material language — a body with a
    /// boundary and the resting shadow beneath it, and no symbol on either.
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
        // The first mover's stone is the black one, which is the whole of what
        // this pair has to know about the sides.
        stoneFace: { $0 == .red
            ? Color(red: 0.102, green: 0.094, blue: 0.086)
            : Color(red: 0.965, green: 0.949, blue: 0.918) },
        // The black stone's boundary is its own body against the wood. The white
        // stone's is the set's own brown, the same edge the Red disc carries,
        // because the shell white and the board surface are too near each other
        // to be a boundary by themselves.
        stoneEdge: { $0 == .red
            ? Color(red: 0.055, green: 0.051, blue: 0.047)
            : Color(red: 0.478, green: 0.384, blue: 0.259) },
        stoneEdgeStroke: 0.020,
        activeInk: Color(red: 0.075, green: 0.294, blue: 0.278),
        recordInk: Color(red: 0.302, green: 0.451, blue: 0.435),
        restingShadow: Shadow(opacity: 0.22, radius: 0.030, y: 0.018),
        liftShadow: Shadow(opacity: 0.30, radius: 0.075, y: 0.045))
}
