// The 图标 symbol set: seven glyphs, drawn for this board.
//
// docs/interaction-design.md § Piece symbols is the contract. These are
// original drawings rather than an adopted set, for the reason recorded there:
// no freely-licensed, culturally-right, small-size-legible pictorial Xiangqi
// set exists to adopt. They are in the East-Asian pictorial convention —
// helmet, canopied cart, horse head, raised barrel, arrowhead — the convention
// every surveyed set in that visual language agrees on, and they carry the
// separation rule the contract records:
//
//   - **The wheel belongs to exactly one piece.** The chariot has the only
//     circle in the set; the cannon has no wheel at all. Every set that wheels
//     both pieces loses the pair at our symbol size, and this is the single
//     strongest lever there is.
//   - **The two envelopes differ in axis.** The chariot is upright and
//     bilaterally symmetric; the cannon is wide, diagonal, and one-sided.
//   - **The cannon is directional and the cart is not**: mass at the lower
//     left, muzzle raised to the upper right, against a cart drawn symmetric
//     about its wheel.
//
// Three independent channels, so the pair survives losing any one of them.
//
// Two rules of execution, both from the same evidence. **Solid silhouettes,
// never outline art**: at `symbolSize` — 17 points at Xiangqi's 34-point pitch
// floor — line work turns to a grey smudge, which is how the one outlined set
// in the survey failed. And **internal detail is at least 2 points at that size
// or it is not drawn**: spokes, mane hatching, and an eye are all wasted ink
// there, so the horse has neither eye nor mane and the wheel has one hub and no
// spokes.
//
// Each glyph is a single ink with knocked-out holes, filled even-odd, in the
// piece's own role colour exactly as its character is — so the 4.5:1
// symbol-contrast obligation carries over untouched, and the choice of
// characters or icons changes nothing else about a disc. Both sides share one
// glyph, per the contract: an icon never carries the side. Nothing here is ever
// rotated, so a glyph is upright in either board orientation for the same
// reason a character is.

import SwiftUI

/// Which symbol set the discs carry.
///
/// The accepted Settings preference, `pieces.symbols`. Read at the moment of
/// use rather than cached at launch — the `Feedback.soundIsEnabled` pattern —
/// so a change in Settings reaches the next frame the board draws. Absent, the
/// state of every first launch, means 汉字, which is the accepted default.
enum PieceSymbols: String {
    case hanzi
    case icons

    static let key = "pieces.symbols"

    /// What a stored value means. Absent means the default, and so does a value
    /// this build does not recognise: the preference is a string in a plist
    /// anyone can write to, and a board that refuses to draw because it found
    /// nonsense there is a worse outcome than a board that draws the default.
    static func named(_ stored: String?) -> PieceSymbols {
        stored.flatMap(PieceSymbols.init(rawValue:)) ?? .hanzi
    }

    static func current(in defaults: UserDefaults = .standard) -> PieceSymbols {
        named(defaults.string(forKey: key))
    }
}

/// One glyph, as a `Shape` — for a preview, a test, or anywhere a view is
/// wanted rather than a path. `BoardCanvas` asks for the path directly.
///
/// Fill it **even-odd**: that is what knocks the wheel's hub out of the wheel.
///
/// Nonisolated because a `Shape` is asked for its path wherever SwiftUI likes,
/// and because a drawing that reads nothing and touches nothing has no business
/// being tied to an actor.
nonisolated struct PieceIcon: Shape {
    var kind: PieceKind

    func path(in rect: CGRect) -> Path {
        PieceIcon.path(for: kind, in: rect)
    }

    /// The side of the square design box every glyph below is drawn in, `y`
    /// down as the canvas is. Holding all seven in one box is what keeps their
    /// sizes relative to one another wherever they are drawn.
    static let designSide: CGFloat = 100

    /// The glyph, scaled into `rect` and centred in it.
    static func path(for kind: PieceKind, in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / designSide
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.midX - side / 2,
                                             y: rect.midY - side / 2))
        return design(for: kind).applying(transform)
    }

    static func design(for kind: PieceKind) -> Path {
        switch kind {
        case .general: general
        case .advisor: advisor
        case .elephant: elephant
        case .chariot: chariot
        case .horse: horse
        case .cannon: cannon
        case .soldier: soldier
        }
    }

    // MARK: - 帅 / 将 — the general's helmet

    /// A general's helmet seen from the front: a low dome with a crest at its
    /// peak, standing on a band that flares out below it. The widest envelope in
    /// the set, and the only glyph drawn as two separated masses — which is what
    /// makes it unmistakable at a glance, before its shape is even read.
    ///
    /// The band is the one internal feature. It is a separate mass with air
    /// above it rather than a slot cut into one: a slot this thin closes up at
    /// 17 points, while the gap between two solid masses survives, and the
    /// contract's floor is 2 points — the gap is just over 2.
    static var general: Path {
        var path = Path()

        // The dome, its shoulders rising steeply from a narrow base so the
        // helmet reads as a helmet rather than as a bowl, and the crest at the
        // top of it traced into the same outline.
        path.move(to: CGPoint(x: 10, y: 62))
        path.addQuadCurve(to: CGPoint(x: 38, y: 37), control: CGPoint(x: 12, y: 42))
        path.addLine(to: CGPoint(x: 50, y: 20))                           // the crest
        path.addLine(to: CGPoint(x: 62, y: 37))
        path.addQuadCurve(to: CGPoint(x: 90, y: 62), control: CGPoint(x: 88, y: 42))
        path.closeSubpath()

        // The band, flaring downward, so the helmet stands on a base instead of
        // tapering away into the disc.
        path.move(to: CGPoint(x: 16, y: 74))
        path.addLine(to: CGPoint(x: 84, y: 74))
        path.addLine(to: CGPoint(x: 96, y: 92))
        path.addLine(to: CGPoint(x: 4, y: 92))
        path.closeSubpath()

        return path
    }

    // MARK: - 仕 / 士 — the ceremonial tablet

    /// The court advisor's 笏板: a tall ceremonial tablet held before the body.
    /// Its gently bowed sides, rounded crown, and small foot are one solid mass,
    /// deliberately spare enough to remain a tablet at the smallest pitch.
    static var advisor: Path {
        var path = Path()
        path.move(to: CGPoint(x: 36, y: 96))
        path.addLine(to: CGPoint(x: 29, y: 87))
        path.addQuadCurve(to: CGPoint(x: 34, y: 15), control: CGPoint(x: 27, y: 50))
        path.addQuadCurve(to: CGPoint(x: 50, y: 3), control: CGPoint(x: 38, y: 4))
        path.addQuadCurve(to: CGPoint(x: 66, y: 15), control: CGPoint(x: 62, y: 4))
        path.addQuadCurve(to: CGPoint(x: 71, y: 87), control: CGPoint(x: 73, y: 50))
        path.addLine(to: CGPoint(x: 64, y: 96))
        path.addLine(to: CGPoint(x: 57, y: 90))
        path.addLine(to: CGPoint(x: 43, y: 90))
        path.closeSubpath()
        return path
    }

    // MARK: - 相 / 象 — the elephant head

    /// An elephant head in profile: domed forehead, broad ear, one tusk, and a
    /// trunk curling forward. All identifying features live in the silhouette;
    /// there is no eye or other internal line to disappear under downsampling.
    static var elephant: Path {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: 88))                               // trunk tip
        path.addQuadCurve(to: CGPoint(x: 22, y: 64), control: CGPoint(x: 8, y: 75))
        path.addQuadCurve(to: CGPoint(x: 18, y: 40), control: CGPoint(x: 18, y: 53))
        path.addQuadCurve(to: CGPoint(x: 50, y: 14), control: CGPoint(x: 27, y: 20))
        path.addQuadCurve(to: CGPoint(x: 82, y: 27), control: CGPoint(x: 70, y: 14))
        path.addQuadCurve(to: CGPoint(x: 94, y: 55), control: CGPoint(x: 98, y: 41))
        path.addQuadCurve(to: CGPoint(x: 70, y: 75), control: CGPoint(x: 91, y: 70))
        path.addLine(to: CGPoint(x: 88, y: 88))                           // tusk
        path.addQuadCurve(to: CGPoint(x: 61, y: 81), control: CGPoint(x: 76, y: 90))
        path.addQuadCurve(to: CGPoint(x: 35, y: 72), control: CGPoint(x: 48, y: 84))
        path.addQuadCurve(to: CGPoint(x: 25, y: 89), control: CGPoint(x: 34, y: 83))
        path.addQuadCurve(to: CGPoint(x: 8, y: 88), control: CGPoint(x: 15, y: 94))
        path.closeSubpath()
        return path
    }

    // MARK: - 俥 / 车 — the canopied cart

    /// A two-wheeled war cart in side view: a canopy overhanging the cart bed
    /// on both sides, and the one wheel the whole set is allowed, emerging from
    /// under the bed. Three plain masses — a wide slab, a box, a disc — because
    /// that is what survives 17 points; an earlier drawing hung the canopy on a
    /// mast, which is the convention, and at the gate size the mast and the
    /// canopy's arch together read as a wrench.
    ///
    /// Drawn symmetric about the wheel, because the contract's third separation
    /// channel is that the cart is *not* directional while the cannon is — so
    /// there is no draw-pole, which would have made it one.
    ///
    /// The wheel is a filled disc with a single hub rather than a spoked one:
    /// twelve spokes at this size are twelve grey smears, which is exactly how
    /// the wheeled sets in the survey lost this pair. The hub is 2.4 points
    /// across at the gate size and the rim around it 2.4 — both clear of the
    /// 2-point floor.
    static var chariot: Path {
        let hub = CGPoint(x: 50, y: 74)
        let wheelRadius: CGFloat = 21
        let hubRadius: CGFloat = 7
        // Where the wheel crosses the bed's underside, so the outline can run
        // around the wheel and back without either shape overlapping the other
        // — an overlap is what even-odd would knock a hole in.
        let bedBottom: CGFloat = 58
        let crossing = (wheelRadius * wheelRadius - (hub.y - bedBottom) * (hub.y - bedBottom))
            .squareRoot()
        let entry = Angle.radians(atan2(bedBottom - hub.y, crossing))

        var path = Path()
        path.move(to: CGPoint(x: 16, y: 4))                               // the canopy
        path.addLine(to: CGPoint(x: 84, y: 4))
        path.addLine(to: CGPoint(x: 90, y: 18))                           // its right eave
        path.addLine(to: CGPoint(x: 74, y: 18))
        path.addLine(to: CGPoint(x: 70, y: bedBottom))                    // the bed, right side
        path.addLine(to: CGPoint(x: hub.x + crossing, y: bedBottom))
        path.addArc(center: hub, radius: wheelRadius,                      // the wheel
                    startAngle: entry, endAngle: .degrees(180) - entry,
                    clockwise: false)
        path.addLine(to: CGPoint(x: 30, y: bedBottom))
        path.addLine(to: CGPoint(x: 26, y: 18))                           // the bed, left side
        path.addLine(to: CGPoint(x: 10, y: 18))
        path.closeSubpath()                                                // its left eave

        // The hub, knocked out.
        path.addEllipse(in: CGRect(x: hub.x - hubRadius, y: hub.y - hubRadius,
                                   width: 2 * hubRadius, height: 2 * hubRadius))

        return path
    }

    // MARK: - 傌 / 马 — the horse's head

    /// A horse head in profile, facing right: the one glyph every pictorial set
    /// in the survey draws the same way, east and west, and the most robust of
    /// the five at any size. No mane hatching and no eye — both fall below the
    /// 2-point floor at 17 points, and the silhouette needs neither.
    static var horse: Path {
        var path = Path()
        path.move(to: CGPoint(x: 16, y: 96))                              // the neck, behind
        path.addQuadCurve(to: CGPoint(x: 30, y: 34), control: CGPoint(x: 14, y: 66))
        path.addLine(to: CGPoint(x: 39, y: 5))                            // the ear
        path.addLine(to: CGPoint(x: 48, y: 28))
        path.addQuadCurve(to: CGPoint(x: 82, y: 54), control: CGPoint(x: 64, y: 34))
        path.addQuadCurve(to: CGPoint(x: 92, y: 66), control: CGPoint(x: 92, y: 58))
        path.addLine(to: CGPoint(x: 74, y: 74))                           // the mouth
        path.addQuadCurve(to: CGPoint(x: 54, y: 71), control: CGPoint(x: 64, y: 79))
        path.addQuadCurve(to: CGPoint(x: 54, y: 96), control: CGPoint(x: 58, y: 84))
        path.closeSubpath()
        return path
    }

    // MARK: - 炮 / 砲 — the barrel on its wedge

    /// A barrel on a plain wedge, muzzle raised to the upper right, and **no
    /// wheel**. The wheel-less cannon is not an invention of ours: it is the
    /// variant pychess's janggi `intlblue` and `intlwooden` draw, and it is the
    /// variant that separates, because it leaves the cart the only circle.
    ///
    /// Drawn as one outline from the barrel's own geometry, so the breech and
    /// the wedge it stands in are a single mass with no seam between them. The
    /// direction is carried by the whole envelope rather than by a muzzle
    /// detail: heavy at the lower left, rising to the right. That reading
    /// survives any amount of downsampling, which a muzzle band would not.
    static var cannon: Path {
        let elevation = Angle.degrees(-27)
        let axis = CGPoint(x: cos(elevation.radians), y: sin(elevation.radians))
        let normal = CGPoint(x: -axis.y, y: axis.x)                       // below the barrel
        let breech = CGPoint(x: 24, y: 64)
        let muzzle = CGPoint(x: breech.x + 74 * axis.x, y: breech.y + 74 * axis.y)

        /// A point `distance` to one side of the barrel's axis.
        func beside(_ point: CGPoint, _ distance: CGFloat) -> CGPoint {
            CGPoint(x: point.x + distance * normal.x, y: point.y + distance * normal.y)
        }

        // The wedge is a plain horizontal block, and the breech stands buried in
        // it. Where each edge of the barrel meets the wedge's top is solved
        // rather than guessed, so the two are one mass at any elevation.
        let wedgeTop: CGFloat = 66
        let wedgeBottom: CGFloat = 94
        func meetingTheWedge(_ from: CGPoint, _ towards: CGPoint) -> CGPoint {
            let along = (wedgeTop - from.y) / (towards.y - from.y)
            return CGPoint(x: from.x + along * (towards.x - from.x), y: wedgeTop)
        }
        let breechAbove = beside(breech, -11)
        let breechBelow = beside(breech, 11)
        let muzzleBelow = beside(muzzle, 9.5)

        var path = Path()
        path.move(to: CGPoint(x: 4, y: wedgeBottom))                      // the wedge
        path.addLine(to: CGPoint(x: 66, y: wedgeBottom))
        path.addLine(to: CGPoint(x: 58, y: wedgeTop))
        path.addLine(to: meetingTheWedge(breechBelow, muzzleBelow))
        path.addLine(to: muzzleBelow)                                     // up the underside
        path.addLine(to: beside(muzzle, -9.5))                            // the muzzle's face
        path.addLine(to: breechAbove)                                     // back along the top
        path.addLine(to: meetingTheWedge(breechAbove, breechBelow))       // the breech's face
        path.addLine(to: CGPoint(x: 14, y: wedgeTop))
        path.closeSubpath()
        return path
    }

    // MARK: - 兵 / 卒 — the arrowhead

    /// An arrowhead over a flared base — a spear standing in the ground, which
    /// is the East-Asian form, and the most legible glyph in the survey: a
    /// filled triangle cannot be mistaken for anything at any size. The barbs'
    /// long edges are drawn slightly concave, which says arrowhead rather than
    /// triangle and costs no internal detail at all.
    static var soldier: Path {
        var path = Path()
        path.move(to: CGPoint(x: 50, y: 4))                               // the point
        path.addQuadCurve(to: CGPoint(x: 16, y: 54), control: CGPoint(x: 36, y: 32))
        path.addLine(to: CGPoint(x: 39, y: 54))                           // under the left barb
        path.addLine(to: CGPoint(x: 39, y: 74))                           // the shaft
        path.addLine(to: CGPoint(x: 20, y: 96))                           // the flared base
        path.addLine(to: CGPoint(x: 80, y: 96))
        path.addLine(to: CGPoint(x: 61, y: 74))
        path.addLine(to: CGPoint(x: 61, y: 54))
        path.addLine(to: CGPoint(x: 84, y: 54))                           // under the right barb
        path.addQuadCurve(to: CGPoint(x: 50, y: 4), control: CGPoint(x: 64, y: 32))
        path.closeSubpath()
        return path
    }
}
