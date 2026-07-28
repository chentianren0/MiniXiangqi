// The board: a 7-by-7 grid of *points*, never a checkerboard of squares.
//
// Everything is drawn from BoardGeometry, so the board scales without any
// dimension being re-tuned. The layering is the accepted one, from the board
// upward: board surface; grid and palace diagonals; last-move brackets;
// destination dots; resting discs with their shadows; rings around resting
// discs; the held disc with its lift shadow and attached selection ring.

import SwiftUI

struct BoardView: View {
    var geometry: BoardGeometry
    var placement: Placement
    var flipped: Bool = false

    var selected: Square?
    var destinations: Set<Square> = []
    var captures: Set<Square> = []
    var lastMove: Move?
    var checkedGeneral: Square?

    var style: BoardStyle = .traditional
    var onTap: (Square) -> Void = { _ in }

    private var p: CGFloat { geometry.pitch }

    var body: some View {
        VStack(spacing: 0) {
            numeralStrip(forRedPlayer: flipped)
            core
            numeralStrip(forRedPlayer: !flipped)
        }
        .frame(width: geometry.blockSize.width, height: geometry.blockSize.height)
    }

    // MARK: - The board core

    private var core: some View {
        Canvas { context, _ in
            drawGrid(in: &context)
            drawLastMove(in: &context)
            drawDestinations(in: &context)
            drawPieces(in: &context)
            drawRings(in: &context)
            drawHeldPiece(in: &context)
        }
        .frame(width: geometry.coreSide, height: geometry.coreSide)
        .background(style.boardSurface)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture(coordinateSpace: .local).onEnded { value in
            if let square = geometry.square(at: value.location, flipped: flipped) {
                onTap(square)
            }
        })
    }

    private func point(_ square: Square) -> CGPoint {
        geometry.center(of: square, flipped: flipped)
    }

    // MARK: - Grid

    private func drawGrid(in context: inout GraphicsContext) {
        var path = Path()
        for index in 0..<Square.count {
            let alongRank = point(Square(file: 0, rank: index))
            let toRank = point(Square(file: Square.count - 1, rank: index))
            path.move(to: alongRank)
            path.addLine(to: toRank)

            let alongFile = point(Square(file: index, rank: 0))
            let toFile = point(Square(file: index, rank: Square.count - 1))
            path.move(to: alongFile)
            path.addLine(to: toFile)
        }
        // Each palace is a 3-by-3 block of points, its two diagonals drawn
        // corner point to corner point at the same stroke weight as the grid,
        // so the palace reads as part of the board rather than as decoration.
        for base in [0, 4] {
            path.move(to: point(Square(file: 2, rank: base)))
            path.addLine(to: point(Square(file: 4, rank: base + 2)))
            path.move(to: point(Square(file: 4, rank: base)))
            path.addLine(to: point(Square(file: 2, rank: base + 2)))
        }
        context.stroke(path, with: .color(style.grid), lineWidth: geometry.gridStroke)
    }

    // MARK: - Markers

    private func drawLastMove(in context: inout GraphicsContext) {
        guard let lastMove else { return }
        for square in [lastMove.from, lastMove.to] {
            context.stroke(bracketPath(at: point(square)),
                           with: .color(style.recordInk),
                           style: StrokeStyle(lineWidth: geometry.lastMoveStroke,
                                              lineCap: .round))
        }
    }

    /// Four L-shaped corner brackets on the cell, inset from each corner.
    private func bracketPath(at centre: CGPoint) -> Path {
        let half = 0.5 * p - geometry.lastMoveInset
        let arm = geometry.lastMoveArm
        var path = Path()
        for x in [-1.0, 1.0] as [CGFloat] {
            for y in [-1.0, 1.0] as [CGFloat] {
                let corner = CGPoint(x: centre.x + x * half, y: centre.y + y * half)
                path.move(to: CGPoint(x: corner.x - x * arm, y: corner.y))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x, y: corner.y - y * arm))
            }
        }
        return path
    }

    private func drawDestinations(in context: inout GraphicsContext) {
        let diameter = geometry.destinationDotDiameter
        for square in destinations where !captures.contains(square) {
            let centre = point(square)
            let box = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2,
                             width: diameter, height: diameter)
            context.fill(Path(ellipseIn: box), with: .color(style.activeInk))
        }
    }

    private func drawPieces(in context: inout GraphicsContext) {
        for rank in 0..<Square.count {
            for file in 0..<Square.count {
                let square = Square(file: file, rank: rank)
                guard let piece = placement[square], square != selected else { continue }
                draw(piece, at: point(square), scale: 1, in: &context,
                     shadow: style.restingShadow)
            }
        }
    }

    private func drawRings(in context: inout GraphicsContext) {
        // A dashed ring around an enemy disc the player may take.
        for square in captures {
            let radius = geometry.captureRingRadius
            let dash = CGFloat.pi * radius * 2 * (Self.captureDashFraction)
            let gap = CGFloat.pi * radius * 2 * (1 / CGFloat(BoardGeometry.captureDashCount)) - dash
            context.stroke(circle(at: point(square), radius: radius),
                           with: .color(style.activeInk),
                           style: StrokeStyle(lineWidth: geometry.captureRingStroke,
                                              lineCap: .butt, dash: [dash, gap]))
        }
        // A double ring around a checked general, hidden while it is held.
        if let checkedGeneral, checkedGeneral != selected {
            for radius in [geometry.checkRingInnerRadius, geometry.checkRingOuterRadius] {
                context.stroke(circle(at: point(checkedGeneral), radius: radius),
                               with: .color(style.activeInk),
                               lineWidth: geometry.checkRingStroke)
            }
        }
    }

    /// Twelve dashes of 18 degrees separated by 12-degree gaps.
    private static var captureDashFraction: CGFloat {
        BoardGeometry.captureDashDegrees / 360
    }

    private func drawHeldPiece(in context: inout GraphicsContext) {
        guard let selected, let piece = placement[selected] else { return }
        let centre = point(selected)
        draw(piece, at: centre, scale: geometry.selectionLift, in: &context,
             shadow: style.liftShadow)
        context.stroke(circle(at: centre, radius: geometry.selectionRingRadius),
                       with: .color(style.activeInk),
                       lineWidth: geometry.selectionRingStroke)
    }

    private func circle(at centre: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                               width: radius * 2, height: radius * 2))
    }

    // MARK: - Discs

    private func draw(_ piece: Piece, at centre: CGPoint, scale: CGFloat,
                      in context: inout GraphicsContext,
                      shadow: (color: Color, radius: CGFloat, y: CGFloat)) {
        let diameter = geometry.discDiameter * scale
        let box = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2,
                         width: diameter, height: diameter)
        let edge = style.discEdgeStroke(piece.side) * p

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: shadow.color,
                                    radius: shadow.radius * p,
                                    y: shadow.y * p))
            layer.fill(Path(ellipseIn: box), with: .color(style.discFace))
        }
        context.stroke(circle(at: centre, radius: geometry.discEdgeRadius(stroke: edge) * scale),
                       with: .color(style.discEdge(piece.side)), lineWidth: edge)

        var symbol = context.resolve(
            Text(piece.kind.character(for: piece.side))
                .font(.system(size: geometry.symbolSize * scale, weight: .medium))
                .foregroundStyle(style.symbol(piece.side)))
        symbol.shading = .color(style.symbol(piece.side))
        context.draw(symbol, at: centre)
    }

    // MARK: - File numerals

    /// One strip per side, showing the numerals of the player it faces —
    /// Chinese for Red, Arabic for Black — following the board's orientation.
    private func numeralStrip(forRedPlayer isRed: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<Square.count, id: \.self) { column in
                let file = flipped ? Square.count - 1 - column : column
                Text(numeral(file: file, forRedPlayer: isRed))
                    .font(.system(size: geometry.numeralSize,
                                  weight: isRed ? .semibold : .bold))
                    .foregroundStyle(style.grid)
                    .frame(width: p)
            }
        }
        .frame(width: geometry.coreSide, height: geometry.stripHeight)
        .background(style.boardSurface)
    }

    /// Files are numbered from each player's own right: Red's right is file g,
    /// Black's is file a.
    private func numeral(file: Int, forRedPlayer isRed: Bool) -> String {
        let index = isRed ? Square.count - 1 - file : file
        return isRed ? ["一", "二", "三", "四", "五", "六", "七"][index]
                     : String(index + 1)
    }
}
