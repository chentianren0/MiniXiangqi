// The board's placement of points, and the bounds it must stay inside.

import CoreGraphics
import Testing
@testable import MiniXiangqi

@Suite("Board geometry")
@MainActor
struct BoardGeometryTests {
    @Test("A point's centre and the point at that location are inverses",
          arguments: GameKind.allCases, [false, true])
    func centreAndHitTestAgree(game: GameKind, flipped: Bool) {
        let geometry = floorGeometry(for: game)
        for rank in 0..<game.board.rankCount {
            for file in 0..<game.board.fileCount {
                let square = Square(file: file, rank: rank)
                let centre = geometry.center(of: square, flipped: flipped)
                #expect(geometry.square(at: centre, flipped: flipped) == square)
            }
        }
    }

    @Test("Every point sits on the grid the board draws",
          arguments: GameKind.allCases, [false, true])
    func pointsSitOnTheGrid(game: GameKind, flipped: Bool) {
        let geometry = floorGeometry(for: game)
        for index in 0..<game.board.fileCount {
            let square = flipped
                ? Square(file: game.board.fileCount - 1 - index, rank: 0)
                : Square(file: index, rank: 0)
            let centre = geometry.center(of: square, flipped: flipped)
            #expect(abs(centre.x - (geometry.margin + CGFloat(index) * geometry.pitch)) < 0.001)
        }
    }

    @Test("The two board cores have the accepted integer-pitch footprints")
    func boardCoreSizes() {
        let mini = floorGeometry(for: .miniXiangqi)
        let xiangqi = floorGeometry(for: .xiangqi)
        #expect(mini.pitch == 44)
        #expect(mini.coreSize == CGSize(width: 308, height: 308))
        #expect(xiangqi.pitch == 34)
        #expect(xiangqi.coreSize == CGSize(width: 306, height: 340))
        #expect(abs(mini.coreSize.width - xiangqi.coreSize.width) <= 2)
    }

    @Test("Markers on adjacent points cannot collide", arguments: GameKind.allCases)
    func markersStayInsideTheirCell(game: GameKind) {
        let geometry = floorGeometry(for: game)
        #expect(geometry.markerOuterLimit <= geometry.pitch / 2)
        #expect(geometry.markerInnerLimit < geometry.markerOuterLimit)
        #expect(geometry.markerOuterLimit <= geometry.margin)
    }

    @Test("The last move is directional and stays in its cells", arguments: GameKind.allCases)
    func lastMoveBracketsAreDirectionalAndContained(game: GameKind) {
        let board = game.board
        for pitch in [BoardGeometry.minimumPitch(for: board),
                      (BoardGeometry.minimumPitch(for: board)
                       + BoardGeometry.maximumPitch(for: board)) / 2,
                      BoardGeometry.maximumPitch(for: board)] {
            let geometry = BoardGeometry(board: board, pitch: pitch)
            #expect(geometry.lastMoveOriginStroke > geometry.gridStroke)
            #expect(geometry.lastMoveOriginStroke < geometry.lastMoveStroke)
            let reach = geometry.pitch / 2 - geometry.lastMoveInset
                + geometry.lastMoveStroke / 2
            #expect(reach < geometry.pitch / 2)
            let corner = geometry.pitch / 2 - geometry.lastMoveInset
            let nearest = hypot(corner - geometry.lastMoveArm, corner)
            #expect(nearest - geometry.lastMoveStroke / 2 > geometry.markerInnerLimit)
        }
    }

    @Test("The hint halo fills the space its point has free and no more",
          arguments: GameKind.allCases)
    func haloStaysInTheSpaceThePointHasFree(game: GameKind) {
        let geometry = floorGeometry(for: game)
        let p = geometry.pitch

        // An empty point has its whole cell, so the washes are bounded by the
        // cell alone — and by each other: they stack outermost first, so each
        // must be smaller than the one it is drawn over.
        var previous = geometry.markerOuterLimit
        for wash in BoardGeometry.haloWashes {
            #expect(wash.radius * p <= geometry.markerOuterLimit)
            #expect(wash.radius * p < previous)
            previous = wash.radius * p
        }
        #expect(BoardGeometry.haloPeakOpacity < 0.5,
                "a wash is a wash: the stack never approaches the ink itself")

        // An occupied point has only the marker band. What the band owes the
        // geometry is the two bounds: clear of the disc's own face, inside the
        // cell. Where between them it sits — today a hair inside the marker
        // floor, which a wash beneath the pieces may be — is the tuning's.
        let inner = geometry.haloBandRadius - geometry.haloBandStroke / 2
        let outer = geometry.haloBandRadius + geometry.haloBandStroke / 2
        #expect(inner >= geometry.discDiameter / 2)
        #expect(outer <= geometry.markerOuterLimit)

        // It sits behind the dashed capture ring so that the ring's dashes have
        // something to show through them, at rest and strengthened alike.
        for emphasis in [0.0, 1.0] {
            let stroke = geometry.captureRingStroke(emphasis: emphasis)
            let ring = geometry.captureRingRadius(stroke: stroke)
            #expect(inner <= ring - stroke / 2)
            #expect(outer > ring - stroke / 2)
        }

        // Record ink never stands on the halo: the last move's brackets are in
        // the cell's corners, and both washes stop well short of them. It is
        // why the composited measurement is about active ink alone.
        let corner = p / 2 - geometry.lastMoveInset
        let nearest = hypot(corner - geometry.lastMoveArm, corner)
            - geometry.lastMoveStroke / 2
        #expect(nearest > outer)
    }

    @Test("The flip starts and ends exactly on the two orientations",
          arguments: GameKind.allCases)
    func flipPathEndsOnItsOrientations(game: GameKind) {
        let geometry = floorGeometry(for: game)
        for rank in 0..<game.board.rankCount {
            for file in 0..<game.board.fileCount {
                let square = Square(file: file, rank: rank)
                #expect(geometry.center(of: square, flip: 0)
                    == geometry.center(of: square, flipped: false))
                #expect(geometry.center(of: square, flip: 1)
                    == geometry.center(of: square, flipped: true))
            }
        }
    }

    @Test("No disc leaves either rectangular board core during a flip",
          arguments: GameKind.allCases)
    func flipStaysInsideTheCore(game: GameKind) {
        let geometry = floorGeometry(for: game)
        let radius = geometry.discDiameter / 2
        for rank in 0..<game.board.rankCount {
            for file in 0..<game.board.fileCount {
                let square = Square(file: file, rank: rank)
                for step in 0...100 {
                    let centre = geometry.center(of: square, flip: Double(step) / 100)
                    #expect(centre.x - radius >= -0.0001)
                    #expect(centre.y - radius >= -0.0001)
                    #expect(centre.x + radius <= geometry.coreSize.width + 0.0001)
                    #expect(centre.y + radius <= geometry.coreSize.height + 0.0001)
                }
            }
        }
    }

    @Test("The flip transform never merges distinct points", arguments: GameKind.allCases)
    func flipKeepsPointsDistinct(game: GameKind) {
        let geometry = floorGeometry(for: game)
        let first = Square(file: 0, rank: 0)
        let next = Square(file: 0, rank: 1)
        for step in 0...100 {
            let flip = Double(step) / 100
            let a = geometry.center(of: first, flip: flip)
            let b = geometry.center(of: next, flip: flip)
            #expect(hypot(a.x - b.x, a.y - b.y) > 0)
        }
    }

    @Test("Fitting honours each game's floor and ceiling", arguments: GameKind.allCases)
    func fittingStaysWithinBounds(game: GameKind) {
        let board = game.board
        #expect(BoardGeometry.fitting(CGSize(width: 100, height: 100), board: board) == nil)

        let huge = BoardGeometry.fitting(CGSize(width: 3000, height: 3000), board: board)
        #expect(huge != nil)
        #expect(huge?.pitch == BoardGeometry.maximumPitch(for: board))
        #expect(huge?.coreSize.width
                == CGFloat(board.fileCount) * BoardGeometry.maximumPitch(for: board))
    }

    @Test("A fitted board always fits what it was given",
          arguments: GameKind.allCases,
          [CGSize(width: 400, height: 500), CGSize(width: 900, height: 900),
           CGSize(width: 1600, height: 1200), CGSize(width: 700, height: 420)])
    func fittedBoardsFit(game: GameKind, size: CGSize) {
        guard let fitted = BoardGeometry.fitting(size, board: game.board) else { return }
        #expect(fitted.blockSize.width <= size.width)
        #expect(fitted.blockSize.height <= size.height)
        #expect(fitted.pitch >= BoardGeometry.minimumPitch(for: game.board))
    }

    private func floorGeometry(for game: GameKind) -> BoardGeometry {
        BoardGeometry(board: game.board,
                      pitch: BoardGeometry.minimumPitch(for: game.board))
    }
}
