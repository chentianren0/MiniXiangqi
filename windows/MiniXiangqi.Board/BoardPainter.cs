// The board picture.
//
// One function of one value: given a BoardScene, a geometry and a style, this
// draws the board and nothing else. That is what lets the window's board and
// the offscreen PNGs in docs/evidence/pr87/ be the same picture
// rather than two pictures that agree — a CanvasControl hands this its drawing
// session, a CanvasRenderTarget hands it one too, and neither knows which it
// is.
//
// Win2D was chosen over XAML shapes for exactly that reason. The board is a
// picture, not forty-nine views: it has a grid, two palaces, up to twenty-four
// discs and four families of state marker, all of them derived from one pitch,
// and the marker vocabulary in docs/interaction-design.md is stated in strokes,
// radii and dash patterns rather than in elements. Immediate-mode drawing takes
// that description literally. XAML shapes would mean a retained tree that has
// to be diffed against the position on every change, a second place for the
// geometry to live, and — decisively — no way to produce a picture of the board
// without a desktop session, which is the one thing this project could not
// otherwise have.
//
// The accepted layering, bottom to top, is docs/interaction-design.md's and is
// followed exactly: the style's board surface; the grid and palace diagonals;
// the pointer hover fill; last-move brackets; destination dots; resting discs
// with their style resting shadows; rings around resting discs; the held disc
// with its lift shadow and attached selection ring. Rings are drawn above
// resting discs so that no disc can clip one.

using System.Numerics;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Effects;
using Microsoft.Graphics.Canvas.Geometry;
using Microsoft.Graphics.Canvas.Text;
using MiniXiangqi.Play;
using Windows.Foundation;
using Windows.UI;
using Windows.UI.Text;

namespace MiniXiangqi.Board;

public static class BoardPainter
{
    /// <summary>
    /// The family every piece character resolves through on Windows. The
    /// accepted characters are Chinese, and this is the system's Simplified
    /// Chinese UI family — present on every Windows 11 installation rather than
    /// a font pack, which is what the requirement that the pieces render at one
    /// consistent size comes to here.
    /// </summary>
    public const string PieceFontFamily = "Microsoft YaHei";

    /// <summary>The coordinate strips are interface text, so they take the platform's own.</summary>
    public const string LabelFontFamily = "Segoe UI";

    /// <summary>
    /// Draw the whole board block — the core and its four coordinate strips —
    /// with its top-left corner at the origin of
    /// <paramref name="session"/>'s current transform.
    /// </summary>
    public static void Draw(
        CanvasDrawingSession session,
        BoardScene scene,
        BoardGeometry geometry,
        BoardStyle style)
    {
        float block = (float)geometry.BlockSide;
        session.FillRectangle(new Rect(0, 0, block, block), Convert(style.BoardSurface));

        DrawCoordinates(session, scene, geometry, style);

        Matrix3x2 outer = session.Transform;
        session.Transform = Matrix3x2.CreateTranslation((float)geometry.StripExtent, (float)geometry.StripExtent) * outer;
        try
        {
            DrawGrid(session, geometry, style);
            DrawHover(session, scene, geometry, style);
            DrawLastMove(session, scene, geometry, style);
            DrawDestinations(session, scene, geometry, style);
            DrawDiscs(session, scene, geometry, style, lifted: false);
            DrawRings(session, scene, geometry, style);
            DrawDiscs(session, scene, geometry, style, lifted: true);
        }
        finally
        {
            session.Transform = outer;
        }
    }

    // The grid.

    private static void DrawGrid(CanvasDrawingSession session, BoardGeometry geometry, BoardStyle style)
    {
        Color ink = Convert(style.Grid);
        float stroke = (float)geometry.GridStroke;

        for (int index = 0; index < Square.Count; index++)
        {
            Vector2 rankStart = Point(geometry, new Square(0, index));
            Vector2 rankEnd = Point(geometry, new Square(Square.Count - 1, index));
            session.DrawLine(rankStart, rankEnd, ink, stroke);

            Vector2 fileStart = Point(geometry, new Square(index, 0));
            Vector2 fileEnd = Point(geometry, new Square(index, Square.Count - 1));
            session.DrawLine(fileStart, fileEnd, ink, stroke);
        }

        // Each palace is a 3-by-3 block of points, its two diagonals drawn
        // corner point to corner point at the same stroke weight as the grid,
        // so the palace reads as part of the board rather than as decoration.
        foreach (int start in (int[])[0, 4])
        {
            session.DrawLine(
                Point(geometry, new Square(2, start)),
                Point(geometry, new Square(4, start + 2)),
                ink,
                stroke);
            session.DrawLine(
                Point(geometry, new Square(4, start)),
                Point(geometry, new Square(2, start + 2)),
                ink,
                stroke);
        }
    }

    // Markers.

    private static void DrawHover(
        CanvasDrawingSession session, BoardScene scene, BoardGeometry geometry, BoardStyle style)
    {
        if (scene.Hovered is not { } square)
        {
            return;
        }

        Vector2 centre = Point(geometry, square, scene.Flipped);
        float side = (float)geometry.HoverSide;
        float radius = (float)geometry.HoverCornerRadius;
        Rect box = new(centre.X - (side / 2), centre.Y - (side / 2), side, side);
        session.FillRoundedRectangle(box, radius, radius, Convert(style.ActiveInk, 0.10));
    }

    private static void DrawLastMove(
        CanvasDrawingSession session, BoardScene scene, BoardGeometry geometry, BoardStyle style)
    {
        if (scene.LastMove is not { } move)
        {
            return;
        }

        // One marker at two points, and the origin's half of it is drawn
        // lighter, so the pair says which way the move went rather than only
        // which two points it touched.
        (Square Square, double Stroke)[] ends =
        [
            (move.From, geometry.LastMoveOriginStroke),
            (move.To, geometry.LastMoveStroke),
        ];
        foreach ((Square square, double stroke) in ends)
        {
            using CanvasGeometry brackets = Brackets(session, geometry, Point(geometry, square, scene.Flipped));
            session.DrawGeometry(brackets, Convert(style.RecordInk), (float)stroke, RoundCap);
        }
    }

    /// <summary>Four L-shaped corner brackets on the cell, inset from each corner.</summary>
    private static CanvasGeometry Brackets(
        CanvasDrawingSession session, BoardGeometry geometry, Vector2 centre)
    {
        float half = (float)((0.5 * geometry.Pitch) - geometry.LastMoveInset);
        float arm = (float)geometry.LastMoveArm;

        using CanvasPathBuilder path = new(session);
        foreach (float x in (float[])[-1, 1])
        {
            foreach (float y in (float[])[-1, 1])
            {
                Vector2 corner = new(centre.X + (x * half), centre.Y + (y * half));
                path.BeginFigure(corner.X - (x * arm), corner.Y);
                path.AddLine(corner.X, corner.Y);
                path.AddLine(corner.X, corner.Y - (y * arm));
                path.EndFigure(CanvasFigureLoop.Open);
            }
        }

        return CanvasGeometry.CreatePath(path);
    }

    private static void DrawDestinations(
        CanvasDrawingSession session, BoardScene scene, BoardGeometry geometry, BoardStyle style)
    {
        // The two sets are disjoint by construction: a destination is an empty
        // point and a capture is an occupied one, and whichever built them
        // decided that before the painter saw either.
        float radius = (float)(geometry.DestinationDotDiameter / 2);
        Color ink = Convert(style.ActiveInk);
        foreach (Square square in scene.Destinations)
        {
            session.FillCircle(Point(geometry, square, scene.Flipped), radius, ink);
        }
    }

    private static void DrawRings(
        CanvasDrawingSession session, BoardScene scene, BoardGeometry geometry, BoardStyle style)
    {
        Color ink = Convert(style.ActiveInk);

        // A dashed ring around an enemy disc the player may take. Twelve dashes
        // of 18 degrees separated by 12-degree gaps: fixing the count rather
        // than a length keeps the pattern identical at every pitch. Direct2D
        // measures a dash in multiples of the stroke width, so the arc lengths
        // are divided by it here and nowhere else.
        if (!scene.Captures.IsEmpty)
        {
            float stroke = (float)geometry.CaptureRingStroke;
            float radius = (float)geometry.CaptureRingRadius(stroke);
            double circumference = 2 * Math.PI * radius;
            double dash = circumference * BoardGeometry.CaptureDashDegrees / 360;
            double gap = (circumference / BoardGeometry.CaptureDashCount) - dash;
            using CanvasStrokeStyle dashed = new()
            {
                CustomDashStyle = [(float)(dash / stroke), (float)(gap / stroke)],
                DashCap = CanvasCapStyle.Flat,
                StartCap = CanvasCapStyle.Flat,
                EndCap = CanvasCapStyle.Flat,
            };

            foreach (Square square in scene.Captures)
            {
                session.DrawCircle(Point(geometry, square, scene.Flipped), radius, ink, stroke, dashed);
            }
        }

        // A double ring around a checked general. The scene has already hidden
        // it if that general is held: the two rings and the selection ring
        // occupy the same band and cannot both be drawn.
        if (scene.CheckedGeneral is { } general)
        {
            Vector2 centre = Point(geometry, general, scene.Flipped);
            float stroke = (float)geometry.CheckRingStroke;
            session.DrawCircle(centre, (float)geometry.CheckRingInnerRadius, ink, stroke);
            session.DrawCircle(centre, (float)geometry.CheckRingOuterRadius, ink, stroke);
        }
    }

    // Discs.

    private static void DrawDiscs(
        CanvasDrawingSession session,
        BoardScene scene,
        BoardGeometry geometry,
        BoardStyle style,
        bool lifted)
    {
        List<(Square Square, Piece Piece)> discs = [];
        for (int rank = 0; rank < Square.Count; rank++)
        {
            for (int file = 0; file < Square.Count; file++)
            {
                Square square = new(file, rank);
                bool held = scene.Selected == square;
                if (held == lifted && scene.Placement[square] is { } piece)
                {
                    discs.Add((square, piece));
                }
            }
        }

        if (discs.Count == 0)
        {
            return;
        }

        double scale = lifted ? geometry.SelectionLift : 1;
        BoardShadow shadow = lifted ? style.LiftShadow : style.RestingShadow;
        float diameter = (float)(geometry.DiscDiameter * scale);

        // The style's shadow, drawn under every disc of this pass at once: one
        // blur rather than one per disc, and identical either way because the
        // discs do not overlap.
        using (CanvasCommandList silhouette = new(session))
        {
            using (CanvasDrawingSession shape = silhouette.CreateDrawingSession())
            {
                foreach ((Square square, _) in discs)
                {
                    shape.FillCircle(
                        Point(geometry, square, scene.Flipped),
                        diameter / 2,
                        Color.FromArgb(255, 0, 0, 0));
                }
            }

            using ShadowEffect blur = new()
            {
                Source = silhouette,
                BlurAmount = (float)(shadow.Radius * geometry.Pitch),
                ShadowColor = Color.FromArgb((byte)Math.Round(shadow.Opacity * 255), 0, 0, 0),
            };
            session.DrawImage(blur, 0, (float)(shadow.Y * geometry.Pitch));
        }

        using CanvasTextFormat format = new()
        {
            FontFamily = PieceFontFamily,
            FontSize = (float)(geometry.SymbolSize * scale),
            FontWeight = new FontWeight { Weight = 500 },
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center,
            WordWrapping = CanvasWordWrapping.NoWrap,
        };

        foreach ((Square square, Piece piece) in discs)
        {
            Vector2 centre = Point(geometry, square, scene.Flipped);
            session.FillCircle(centre, diameter / 2, Convert(style.DiscFace));

            float edge = (float)(style.DiscEdgeStroke(piece.Side) * geometry.Pitch);
            session.DrawCircle(
                centre,
                (float)(geometry.DiscEdgeRadius(edge) * scale),
                Convert(style.DiscEdge(piece.Side)),
                edge);

            DrawSymbol(session, piece, centre, format, Convert(style.Symbol(piece.Side)));
        }

        // The solid selection ring, attached to the piece. Lift and shadow may
        // not carry selection alone — a shadow weakens under Increase Contrast
        // and a small scale change is not absolutely readable — so the ring is
        // what makes the state certain.
        if (lifted && scene.Selected is { } held2)
        {
            session.DrawCircle(
                Point(geometry, held2, scene.Flipped),
                (float)geometry.SelectionRingRadius,
                Convert(style.ActiveInk),
                (float)geometry.SelectionRingStroke);
        }
    }

    /// <summary>
    /// The character the disc carries, centred on its own ink rather than on
    /// its line box, so that every glyph sits on the point's centre whatever
    /// its ascent and descent are.
    /// </summary>
    private static void DrawSymbol(
        CanvasDrawingSession session, Piece piece, Vector2 centre, CanvasTextFormat format, Color ink)
    {
        string character = piece.Kind.Character(piece.Side);
        using CanvasTextLayout layout = new(session, character, format, 0, 0);
        Rect bounds = layout.DrawBounds;
        session.DrawTextLayout(
            layout,
            centre.X - (float)(bounds.Left + (bounds.Width / 2)),
            centre.Y - (float)(bounds.Top + (bounds.Height / 2)),
            ink);
    }

    // The coordinate strips.

    private static void DrawCoordinates(
        CanvasDrawingSession session, BoardScene scene, BoardGeometry geometry, BoardStyle style)
    {
        using CanvasTextFormat format = new()
        {
            FontFamily = LabelFontFamily,
            FontSize = (float)geometry.LabelSize,
            FontWeight = new FontWeight { Weight = 700 },
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center,
            WordWrapping = CanvasWordWrapping.NoWrap,
        };

        Color ink = Convert(style.Grid);
        float strip = (float)geometry.StripExtent;
        float pitch = (float)geometry.Pitch;
        float margin = (float)geometry.Margin;

        for (int index = 0; index < Square.Count; index++)
        {
            // A coordinate is absolute: a1 is a1 whichever way the board is
            // facing, so flipping re-orders the labels and never renames them.
            string file = ((char)('a' + (scene.Flipped ? Square.Count - 1 - index : index))).ToString();
            string rank = ((scene.Flipped ? index : Square.Count - 1 - index) + 1)
                .ToString(System.Globalization.CultureInfo.InvariantCulture);

            float along = strip + margin + (index * pitch);
            Label(session, file, new Rect(along - (pitch / 2), 0, pitch, strip), ink, format);
            Label(session, file, new Rect(along - (pitch / 2), strip + (float)geometry.CoreSide, pitch, strip), ink, format);
            Label(session, rank, new Rect(0, along - (pitch / 2), strip, pitch), ink, format);
            Label(session, rank, new Rect(strip + (float)geometry.CoreSide, along - (pitch / 2), strip, pitch), ink, format);
        }
    }

    private static void Label(
        CanvasDrawingSession session, string text, Rect box, Color ink, CanvasTextFormat format) =>
        session.DrawText(text, box, ink, format);

    // Helpers.

    private static readonly CanvasStrokeStyle RoundCap = new()
    {
        StartCap = CanvasCapStyle.Round,
        EndCap = CanvasCapStyle.Round,
        LineJoin = CanvasLineJoin.Round,
    };

    private static Vector2 Point(BoardGeometry geometry, Square square, bool flipped = false)
    {
        (double x, double y) = geometry.Center(square, flipped);
        return new Vector2((float)x, (float)y);
    }

    private static Color Convert(Rgb colour) => Color.FromArgb(255, colour.R, colour.G, colour.B);

    private static Color Convert(Rgb colour, double opacity) =>
        Color.FromArgb((byte)Math.Round(opacity * 255), colour.R, colour.G, colour.B);
}
