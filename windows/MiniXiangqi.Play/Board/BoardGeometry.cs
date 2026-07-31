// Every board dimension as a multiple of the cell pitch `p`.
//
// The values are apple/MiniXiangqi/Board/BoardGeometry.swift's, deliberately
// and to the digit: docs/interaction-design.md fixes the *relationships* and
// the gates — a marker stays inside its own cell, a style's decoration stays
// inside the disc, the 44-point floor and the 720-point ceiling — and says
// plainly that the exact dimensions are settled against a rendered board
// rather than in prose. They were settled once, on a rendered board, and
// "the board, pieces, and game-state markers form one shared visual identity
// across platforms" is what makes re-settling them here wrong rather than
// merely wasteful.
//
// Two things differ from the Mac, and only two. Both are consequences of the
// Windows MVP's move record being the core's canonical coordinate text rather
// than a notation rendering, and both are described in the pull request that
// introduced them:
//
//   * the edge labels are the canonical coordinates — files a–g and ranks 1–7
//     — rather than the two file-numeral strips, because the strips exist so a
//     player can map the record to the board, and a 一二三 edge maps to nothing
//     in `d1d3`;
//   * so there are four strips rather than two, and the board block is square.
//
// Nothing in the motion vocabulary is here: this frontend draws states rather
// than travel, per issue #80's trimmed scope, so the emphasis and swell
// functions the Mac's geometry carries have no caller yet.

namespace MiniXiangqi.Play;

public readonly record struct BoardGeometry(double Pitch)
{
    /// <summary>The accepted floor on every interactive board, on every platform.</summary>
    public const double MinimumPitch = 44;

    /// <summary>
    /// The largest whole-point pitch inside the contract's 720-point bound on
    /// the board core: 102, for a core of 714.
    /// </summary>
    public const double MaximumPitch = 102;

    // The board itself.

    /// <summary>
    /// The half-cell margin beyond the outer points, which is what keeps an
    /// edge disc from being clipped and contains the outermost points' markers.
    /// </summary>
    public double Margin => 0.5 * Pitch;

    /// <summary>7 points plus a half-cell margin on each side.</summary>
    public double CoreSide => 7 * Pitch;

    /// <summary>
    /// <c>0.026 p</c>, clamped to between 0.80 and 1.60 points, so the lines
    /// never coarsen as the board grows. The palace diagonals match it exactly.
    /// </summary>
    public double GridStroke => Math.Clamp(0.026 * Pitch, 0.80, 1.60);

    // Pieces.

    public double DiscDiameter => 0.80 * Pitch;

    public double SymbolSize => 0.50 * Pitch;

    /// <summary>
    /// The centre-line radius of a disc's edge stroke. The stroke is drawn
    /// inside the disc's own edge rather than centred on it, which is what
    /// keeps a heavy edge — 传统's Black disc carries one — from reaching past
    /// the style-decoration limit and into the band markers occupy.
    /// </summary>
    public double DiscEdgeRadius(double stroke) => (DiscDiameter / 2) - (stroke / 2);

    // Markers.

    /// <summary>No marker's ink falls inside this radius on an occupied point.</summary>
    public double MarkerInnerLimit => 0.42 * Pitch;

    /// <summary>Every marker is contained by its own cell.</summary>
    public double MarkerOuterLimit => 0.50 * Pitch;

    public double SelectionRingRadius => 0.440 * Pitch;

    public double SelectionRingStroke => 0.030 * Pitch;

    public double SelectionLift => 1.05;

    public double DestinationDotDiameter => 0.22 * Pitch;

    public double CaptureRingStroke => 0.055 * Pitch;

    /// <summary>
    /// Outer edge exactly at the cell boundary, so the centre line sits half a
    /// stroke inside it.
    /// </summary>
    public double CaptureRingRadius(double stroke) => MarkerOuterLimit - (stroke / 2);

    /// <summary>
    /// Twelve dashes of 18 degrees separated by 12-degree gaps. Fixing the
    /// count rather than a length keeps the pattern identical at every pitch.
    /// </summary>
    public const int CaptureDashCount = 12;

    public const double CaptureDashDegrees = 18;

    public double CheckRingStroke => 0.025 * Pitch;

    public double CheckRingInnerRadius => 0.4325 * Pitch;

    public double CheckRingOuterRadius => 0.4875 * Pitch;

    public double LastMoveArm => 0.13 * Pitch;

    public double LastMoveStroke => 0.045 * Pitch;

    /// <summary>
    /// The origin's brackets: the destination's shape, ink, inset, and
    /// containment, at 0.6 of the weight, so the pair says which way the move
    /// went rather than only which two points it touched.
    /// </summary>
    public double LastMoveOriginStroke => 0.6 * LastMoveStroke;

    public double LastMoveInset => 0.05 * Pitch;

    public double HoverSide => 0.90 * Pitch;

    public double HoverCornerRadius => 0.12 * Pitch;

    // Edge coordinates.

    /// <summary><c>0.32 p</c>, rounded to the nearest point and clamped to between 13 and 20.</summary>
    public double LabelSize => Math.Clamp(Math.Round(0.32 * Pitch), 13, 20);

    /// <summary>
    /// <c>0.08 p + 0.887 s</c>: the first term is clear space between the
    /// board's outer line and the tallest label. One extent for all four
    /// strips, which is what keeps the board block square.
    /// </summary>
    public double StripExtent => Math.Round((0.08 * Pitch) + (0.887 * LabelSize));

    /// <summary>
    /// The board core together with its four coordinate strips — the rectangle
    /// no resident surface may intersect.
    /// </summary>
    public double BlockSide => CoreSide + (2 * StripExtent);

    // Placing points.

    /// <summary>
    /// The centre of a point within the board core, with the board core's own
    /// origin at (0, 0). <paramref name="flipped"/> puts Black at the bottom.
    /// </summary>
    public (double X, double Y) Center(Square square, bool flipped)
    {
        int file = flipped ? Square.Count - 1 - square.File : square.File;
        int rank = flipped ? square.Rank : Square.Count - 1 - square.Rank;
        return (Margin + (file * Pitch), Margin + (rank * Pitch));
    }

    /// <summary>
    /// The point a click at (<paramref name="x"/>, <paramref name="y"/>)
    /// addresses, or null when it fell outside every cell — the half-cell
    /// margin means every location inside the board core belongs to exactly one
    /// point.
    /// </summary>
    public Square? SquareAt(double x, double y, bool flipped)
    {
        int column = (int)Math.Round((x - Margin) / Pitch, MidpointRounding.AwayFromZero);
        int row = (int)Math.Round((y - Margin) / Pitch, MidpointRounding.AwayFromZero);
        if ((uint)column >= Square.Count || (uint)row >= Square.Count)
        {
            return null;
        }

        return new Square(
            flipped ? Square.Count - 1 - column : column,
            flipped ? row : Square.Count - 1 - row);
    }

    /// <summary>
    /// The largest pitch whose board block fits a square of
    /// <paramref name="side"/>, bounded by the accepted floor and ceiling. The
    /// block is square here, so this is arithmetic rather than the Mac's
    /// step-down search over a height that depends on the pitch.
    /// </summary>
    public static BoardGeometry Fitting(double side)
    {
        // block = 7p + 2 * round(0.08p + 0.887 * clamp(round(0.32p), 13, 20)),
        // which rises monotonically with p, so stepping down from the pitch the
        // core alone would allow lands on the largest that fits.
        double pitch = Math.Min(Math.Floor(side / 7), MaximumPitch);
        while (pitch > MinimumPitch && new BoardGeometry(pitch).BlockSide > side)
        {
            pitch -= 1;
        }

        return new BoardGeometry(Math.Max(pitch, MinimumPitch));
    }
}
