// The board canvas and the Custom Scene palette draw pieces through this one
// routine, so the two can never drift apart. Every dimension is a multiple of
// the pitch.

import SwiftUI

struct PieceDrawing {
    var geometry: BoardGeometry
    var style: BoardStyle
    var symbols: PieceSymbols = .hanzi

    private var p: CGFloat { geometry.pitch }

    /// The context arrives by value, so the disc's opacity composes with
    /// whatever the caller already set.
    /// - Parameter symbolOpacity: a Jieqi reveal is the arriving piece with its
    ///   symbol coming up, not two discs dissolving; at 0 it is exactly the
    ///   face-down body.
    func draw(_ piece: Piece, at centre: CGPoint, lift: Double,
              scale externalScale: CGFloat = 1, opacity: Double = 1,
              symbolOpacity: Double = 1,
              in context: GraphicsContext) {
        var context = context
        context.opacity *= opacity

        let scale = (1 + (geometry.selectionLift - 1) * lift) * externalScale
        let shadow = style.restingShadow.blended(toward: style.liftShadow, by: lift)
        let stone = piece.isStone
        let body = stone ? geometry.stoneDiameter : geometry.discDiameter
        let diameter = body * scale
        let box = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2,
                         width: diameter, height: diameter)
        let edge = (stone ? style.stoneEdgeStroke : style.discEdgeStroke(piece.side)) * p
        let face = stone ? style.stoneFace(piece.side) : style.discFace

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: shadow.color,
                                    radius: shadow.radius * p,
                                    y: shadow.y * p))
            layer.fill(Path(ellipseIn: box), with: .color(face))
        }
        // The stroke sits inside the body's edge, so a heavy edge grows inward.
        // A stone's edge reaches past the 0.40 p marker limit, which is sound:
        // no marker stands on an occupied point of a placement board, and the
        // last-move bracket's ink sits outside the stone.
        context.stroke(circle(at: centre,
                              radius: geometry.edgeRadius(body: body, stroke: edge) * scale),
                       with: .color(stone ? style.stoneEdge(piece.side)
                                          : style.discEdge(piece.side)),
                       lineWidth: edge)

        guard symbolOpacity > 0 else { return }
        context.opacity *= symbolOpacity
        drawSymbol(of: piece, at: centre, scale: scale, in: &context)
    }

    /// An icon is never rotated, as a character is never rotated, so both stand
    /// upright throughout a flip.
    private func drawSymbol(of piece: Piece, at centre: CGPoint, scale: CGFloat,
                            in context: inout GraphicsContext) {
        // A face-down piece carries no symbol; its ring alone says whose it is.
        guard !piece.isFaceDown else { return }
        // A stone carries none: its colour is what says whose it is.
        guard let kind = piece.kind else { return }
        let size = geometry.symbolSize * scale
        let ink = style.symbol(piece.side)
        switch symbols {
        case .hanzi:
            var symbol = context.resolve(
                Text(kind.character(for: piece.side))
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(ink))
            symbol.shading = .color(ink)
            context.draw(symbol, at: centre)
        case .icons:
            let box = CGRect(x: centre.x - size / 2, y: centre.y - size / 2,
                             width: size, height: size)
            context.fill(PieceIcon.path(for: kind, in: box),
                         with: .color(ink), style: FillStyle(eoFill: true))
        }
    }

    private func circle(at centre: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                               width: radius * 2, height: radius * 2))
    }
}

/// One piece away from a board: a Custom Scene palette entry, or the disc a
/// refused placement shakes off. It fills one cell of `pitch`, as on the board.
struct PieceDisc: View {
    var piece: Piece
    var pitch: CGFloat
    var board: BoardDefinition
    var style: BoardStyle = .traditional
    var symbols: PieceSymbols = .hanzi
    /// The captured surface holds it midway to say a piece left the board face
    /// down.
    var symbolOpacity: Double = 1

    var body: some View {
        Canvas { context, size in
            PieceDrawing(geometry: BoardGeometry(board: board, pitch: pitch),
                         style: style, symbols: symbols)
                .draw(piece, at: CGPoint(x: size.width / 2, y: size.height / 2),
                      lift: 0, symbolOpacity: symbolOpacity, in: context)
        }
        .frame(width: pitch, height: pitch)
        .accessibilityHidden(true)
    }
}
