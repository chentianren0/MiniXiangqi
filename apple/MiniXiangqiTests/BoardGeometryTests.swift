// The board's placement of points, and the bounds it must stay inside.
//
// The centre of a point and the point a location addresses are inverses of one
// another. A review reintroduced a half-cell inset in the tap overlay and every
// test stayed green, because the overlay was self-consistent: it agreed with
// itself while disagreeing with the drawn board. These check the geometry both
// of them now share.

import CoreGraphics
import Testing
@testable import MiniXiangqi

@Suite("Board geometry")
@MainActor
struct BoardGeometryTests {
    let geometry = BoardGeometry(pitch: BoardGeometry.minimumPitch)

    @Test("A point's centre and the point at that location are inverses",
          arguments: [false, true])
    func centreAndHitTestAgree(flipped: Bool) {
        for rank in 0..<Square.count {
            for file in 0..<Square.count {
                let square = Square(file: file, rank: rank)
                let centre = geometry.center(of: square, flipped: flipped)
                #expect(geometry.square(at: centre, flipped: flipped) == square)
            }
        }
    }

    @Test("Every point sits on the grid the board draws", arguments: [false, true])
    func pointsSitOnTheGrid(flipped: Bool) {
        // The half-cell margin is the outer half of the outermost cells, so the
        // first centre is at 0.5 p and each next one a whole pitch along. An
        // inset anywhere would break this.
        for index in 0..<Square.count {
            let square = flipped ? Square(file: Square.count - 1 - index, rank: 0)
                                 : Square(file: index, rank: 0)
            let centre = geometry.center(of: square, flipped: flipped)
            #expect(abs(centre.x - (geometry.margin + CGFloat(index) * geometry.pitch)) < 0.001)
        }
    }

    @Test("Markers on adjacent points cannot collide")
    func markersStayInsideTheirCell() {
        // Every marker is contained within its point's 1 p by 1 p cell, so the
        // outer limit is half a pitch and two adjacent points' markers meet at
        // most at a boundary.
        #expect(geometry.markerOuterLimit <= geometry.pitch / 2)
        #expect(geometry.markerInnerLimit < geometry.markerOuterLimit)
        // The outermost points' markers are contained by the half-cell margin,
        // so they never reach the numeral strips outside it.
        #expect(geometry.markerOuterLimit <= geometry.margin)
    }

    @Test("The last move reads in the direction it was played, and stays in its cells")
    func lastMoveBracketsAreDirectionalAndContained() {
        // The origin's brackets are the destination's at less weight — same
        // shape, same ink, same inset — so the pair says which way the move
        // went. Ink is not what carries it: record ink has a contrast floor to
        // hold, and Increase Contrast promotes ink and leaves weight alone.
        #expect(geometry.lastMoveOriginStroke < geometry.lastMoveStroke)
        // Softer, never fainter than the board itself: a marker that draws
        // lighter than the grid it lies on has stopped being a marker. This is
        // the floor under the factor, and the smallest board is where it bites.
        for pitch in [BoardGeometry.minimumPitch, 60, BoardGeometry.maximumPitch] {
            let board = BoardGeometry(pitch: pitch)
            #expect(board.lastMoveOriginStroke > board.gridStroke)
        }
        // Both weights stay inside the cell, which is what keeps two adjacent
        // cells' brackets visibly separate — a one-step move puts them side by
        // side. The heavier one is the one to check.
        let reach = geometry.pitch / 2 - geometry.lastMoveInset + geometry.lastMoveStroke / 2
        #expect(reach < geometry.pitch / 2)
        // And the arms stay clear of the disc: brackets are the one marker
        // family that lives in the cell's corners.
        let corner = geometry.pitch / 2 - geometry.lastMoveInset
        let nearest = (pow(corner - geometry.lastMoveArm, 2) + pow(corner, 2)).squareRoot()
        #expect(nearest - geometry.lastMoveStroke / 2 > geometry.markerInnerLimit)
    }

    @Test("The flip's path starts and ends exactly on the two orientations")
    func flipPathEndsOnItsOrientations() {
        for rank in 0..<Square.count {
            for file in 0..<Square.count {
                let square = Square(file: file, rank: rank)
                #expect(geometry.center(of: square, flip: 0)
                    == geometry.center(of: square, flipped: false))
                #expect(geometry.center(of: square, flip: 1)
                    == geometry.center(of: square, flipped: true))
            }
        }
    }

    @Test("No disc leaves the board core at any instant of the flip")
    func flipStaysInsideTheCore() {
        // The contained rotation holds the outermost points on the outer grid
        // lines, so every disc keeps its at-rest clearance from the core's
        // edge — a disc reaches 0.40 p past its point, the margin is 0.50 p.
        let mid = geometry.coreSide / 2
        let outermost = 3 * geometry.pitch
        for rank in 0..<Square.count {
            for file in 0..<Square.count {
                let square = Square(file: file, rank: rank)
                for step in 0...200 {
                    let centre = geometry.center(of: square, flip: Double(step) / 200)
                    #expect(abs(centre.x - mid) <= outermost + 0.0001)
                    #expect(abs(centre.y - mid) <= outermost + 0.0001)
                }
            }
        }
    }

    @Test("The flip cannot collide two discs: distances from the centre scale together")
    func flipPreservesConcentricity() {
        // Every point rides its own ring, and every ring is scaled by the
        // same factor at the same instant, so two discs' separation can fall
        // no faster than the rings themselves — adjacent rings stay disjoint.
        let mid = geometry.coreSide / 2
        for step in 0...100 {
            let flip = Double(step) / 100
            let inner = geometry.center(of: Square("d3")!, flip: flip)
            let outer = geometry.center(of: Square("d1")!, flip: flip)
            let innerRadius = hypot(inner.x - mid, inner.y - mid)
            let outerRadius = hypot(outer.x - mid, outer.y - mid)
            #expect(outerRadius - innerRadius > geometry.pitch,
                    "rings three pitches apart at rest stay clear of each other")
        }
    }

    @Test("The board honours its floor and its ceiling")
    func fittingStaysWithinBounds() {
        #expect(BoardGeometry.fitting(CGSize(width: 100, height: 100)) == nil)

        let tiny = BoardGeometry.fitting(CGSize(width: 320, height: 360))
        #expect(tiny == nil || tiny!.pitch >= BoardGeometry.minimumPitch)

        // The ceiling is a size the board actually reaches, not a bound it
        // stays under: given more room than it can use, the board comes back at
        // exactly the ceiling. Asserting only `<=` here is what let the board
        // stop six points short of it without anything noticing.
        let huge = BoardGeometry.fitting(CGSize(width: 3000, height: 3000))
        #expect(huge != nil)
        #expect(huge!.pitch == BoardGeometry.maximumPitch)
        #expect(huge!.pitch == 102)
        #expect(huge!.coreSide == 714)
    }

    @Test("A fitted board always fits what it was given",
          arguments: [CGSize(width: 400, height: 500), CGSize(width: 900, height: 700),
                      CGSize(width: 1600, height: 1200), CGSize(width: 700, height: 420)])
    func fittedBoardsFit(size: CGSize) {
        guard let fitted = BoardGeometry.fitting(size) else { return }
        #expect(fitted.blockSize.width <= size.width)
        #expect(fitted.blockSize.height <= size.height)
        #expect(fitted.pitch >= BoardGeometry.minimumPitch)
    }
}
