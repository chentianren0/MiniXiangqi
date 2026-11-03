// The 图标 symbol set. Rules that keep it legible at `symbolSize` (17 points
// at Xiangqi's smallest pitch):
//
//   - The chariot has the only circle; the cannon has no wheel.
//   - The chariot is upright and symmetric; the cannon is wide, diagonal and
//     directional. With the wheel, three channels separate the pair, so it
//     survives losing any one.
//   - Solid silhouettes, never outline art: line work turns to a grey smudge.
//   - Internal detail is at least 2 points at that size or it is not drawn.
//
// Each glyph is one ink with knocked-out holes, filled even-odd in the role
// colour, so the symbol contrast floor carries over. Both sides share a glyph,
// and none is ever rotated.

import SwiftUI

/// Which symbol set the discs carry: the 棋子符号 preference.
enum PieceSymbols: String {
    case hanzi
    case icons

    static let key = "pieces.symbols"
}

/// Fill it even-odd: that is what knocks the wheel's hub out of the wheel.
/// Nonisolated because SwiftUI asks a `Shape` for its path wherever it likes.
nonisolated struct PieceIcon: Shape {
    var kind: PieceKind

    func path(in rect: CGRect) -> Path {
        PieceIcon.path(for: kind, in: rect)
    }

    /// One design box for all seven keeps their sizes relative to one another.
    /// `y` runs down, as on the canvas.
    static let designSide: CGFloat = 100

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

    /// The only glyph drawn as two masses. The band is a separate mass rather
    /// than a slot: a slot this thin closes up at 17 points, while the gap
    /// between masses, just over 2 points, survives.
    static var general: Path {
        var path = Path()

        // Steep shoulders, so the dome reads as a helmet rather than a bowl.
        path.move(to: CGPoint(x: 10, y: 62))
        path.addQuadCurve(to: CGPoint(x: 38, y: 37), control: CGPoint(x: 12, y: 42))
        path.addLine(to: CGPoint(x: 50, y: 20))                           // the crest
        path.addLine(to: CGPoint(x: 62, y: 37))
        path.addQuadCurve(to: CGPoint(x: 90, y: 62), control: CGPoint(x: 88, y: 42))
        path.closeSubpath()

        path.move(to: CGPoint(x: 16, y: 74))
        path.addLine(to: CGPoint(x: 84, y: 74))
        path.addLine(to: CGPoint(x: 96, y: 92))
        path.addLine(to: CGPoint(x: 4, y: 92))
        path.closeSubpath()

        return path
    }

    // MARK: - 仕 / 士 — the ceremonial tablet

    /// The court advisor's 笏板, a ceremonial tablet.
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

    /// An elephant head in profile; every feature lives in the silhouette.
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

    /// A war cart in side view. No mast, the usual convention: at 17 points the
    /// mast and canopy read as a wrench. Symmetric about the wheel with no
    /// draw-pole, so it is not directional. One hub and no spokes, which would
    /// smear at this size.
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

    /// A horse head in profile, facing right.
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

    /// No wheel, so the chariot keeps the only circle. The direction is carried
    /// by the whole envelope, heavy at the lower left and rising to the right,
    /// which survives downsampling where a muzzle detail would not.
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

        // The breech is buried in the wedge; where the barrel's edges meet the
        // wedge's top is solved, so the two are one mass at any elevation.
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

    /// The barbs' long edges are slightly concave, which says arrowhead rather
    /// than triangle without any internal detail.
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
