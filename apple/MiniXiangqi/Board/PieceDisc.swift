// One piece, drawn: the body, its edge, its shadow, and the symbol on its face.
//
// It is one routine because there is one piece. The board draws thirty-two of
// them into a single canvas and the Custom Scene palette draws fourteen more
// beside it, and a palette whose discs were assembled out of a `Text` and a
// `Circle` would be a second answer to *what a piece looks like* — one that
// would drift from the board's the first time a style value moved. So the
// drawing lives here, the canvas calls it per point, and the palette calls it
// once per entry through the view below.
//
// Everything it needs arrives in `BoardGeometry` and `BoardStyle`: every
// dimension is a multiple of the pitch, so the same routine draws a disc at a
// board's own pitch and a palette entry at whatever pitch the panel can spare.

import SwiftUI

/// How this document's pieces are drawn, at one pitch, in one style.
struct PieceDrawing {
    var geometry: BoardGeometry
    var style: BoardStyle
    /// Which symbol set the discs carry. Characters unless told otherwise: the
    /// accepted default, and the reason a caller that says nothing about
    /// symbols draws exactly the board it drew before icons existed.
    var symbols: PieceSymbols = .hanzi

    private var p: CGFloat { geometry.pitch }

    /// One disc, `lift` of the way from resting to raised: scale and shadow
    /// rise together, and nothing else changes. The context arrives by value
    /// — a copy draws into the same canvas — so the disc's opacity composes
    /// with whatever the caller already set.
    /// - Parameter symbolOpacity: how far the disc's own face has arrived,
    ///   which is the whole of a Jieqi reveal: a face-down piece and the piece
    ///   it turns up as are the same body, the same ring and the same face, and
    ///   they differ by the symbol alone. So a reveal is drawn as the arriving
    ///   piece with its symbol coming up rather than as two discs dissolving
    ///   into each other, and at 0 it is exactly the face-down body.
    func draw(_ piece: Piece, at centre: CGPoint, lift: Double,
              scale externalScale: CGFloat = 1, opacity: Double = 1,
              symbolOpacity: Double = 1,
              in context: GraphicsContext) {
        var context = context
        context.opacity *= opacity

        let scale = (1 + (geometry.selectionLift - 1) * lift) * externalScale
        let shadow = style.restingShadow.blended(toward: style.liftShadow, by: lift)
        // A stone is the same body drawn in the two things that differ: it is
        // wider for its cell, its face is its side, and it carries no symbol.
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
        // The stroke is drawn inside the body's own edge rather than centred on
        // it, so a heavy edge grows inward instead of past the body it draws.
        //
        // **What contains it differs between the two bodies.** A disc is 0.80 p
        // across, so its edge stays inside the 0.40 p style-decoration limit and
        // clear of the band markers occupy — the rule that limit exists for. A
        // stone is 0.88 p and reaches 0.44 p, past it, and that is sound here
        // rather than an oversight: the limit keeps marker ink off a piece, and
        // on these boards no marker ever stands on one. The only mark a
        // placement board draws on an *occupied* point is the last-move bracket,
        // whose ink sits at ≈0.53 p from the centre, outside the stone; the
        // selection ring marks the point a stone is not on yet; and every legal
        // point is empty by the rule that makes it legal. It stays inside its
        // own cell, which is the containment that applies to a body.
        context.stroke(circle(at: centre,
                              radius: geometry.edgeRadius(body: body, stroke: edge) * scale),
                       with: .color(stone ? style.stoneEdge(piece.side)
                                          : style.discEdge(piece.side)),
                       lineWidth: edge)

        guard symbolOpacity > 0 else { return }
        context.opacity *= symbolOpacity
        drawSymbol(of: piece, at: centre, scale: scale, in: &context)
    }

    /// What the disc carries: the piece's character, or its icon.
    ///
    /// One place, so the two sets are drawn at the same size, on the same
    /// centre, in the same role ink — and so every disc drawn gets them, the
    /// resting one, the held one, the one in transit and the palette's alike. An
    /// icon is never rotated, exactly as a character is never rotated, so both
    /// stand upright throughout a flip.
    private func drawSymbol(of piece: Piece, at centre: CGPoint, scale: CGFloat,
                            in context: inout GraphicsContext) {
        // **A face-down piece carries none either**, and that is the whole of
        // what makes it the third body: docs/interaction-design.md, "The Jieqi
        // board" — the style's disc with its side ring and nothing on its face,
        // saying whose piece it is and no more, which is the whole of what
        // either player knows about it. The body above it is the ordinary disc,
        // so the side is carried by the ring alone — the style's own non-hue
        // channel, which each style already answers for the symbols, there
        // being no symbol here to help carry it.
        //
        // Its face is settled against a rendered board, as every other visual
        // specific in that document is.
        guard !piece.isFaceDown else { return }
        // A stone carries none, in either set: its colour is what says whose it
        // is, and a symbol on it would be inventing a distinction the game does
        // not make.
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

/// One piece on its own, away from a board: the Custom Scene palette's entries,
/// and the disc a refused placement shakes off the point it was offered to.
///
/// It occupies exactly one cell of the pitch it is given, which is what a piece
/// occupies on the board — so a disc drawn here and a disc drawn there are the
/// same size for the same pitch, and the air around it is the air the board
/// leaves around a point.
struct PieceDisc: View {
    var piece: Piece
    /// The cell this disc is drawn into. A palette's pitch is whatever the panel
    /// can spare rather than the board's own, and every dimension of the disc
    /// follows it.
    var pitch: CGFloat
    var board: BoardDefinition
    var style: BoardStyle = .traditional
    var symbols: PieceSymbols = .hanzi

    var body: some View {
        Canvas { context, size in
            PieceDrawing(geometry: BoardGeometry(board: board, pitch: pitch),
                         style: style, symbols: symbols)
                .draw(piece, at: CGPoint(x: size.width / 2, y: size.height / 2),
                      lift: 0, in: context)
        }
        .frame(width: pitch, height: pitch)
        .accessibilityHidden(true)
    }
}
