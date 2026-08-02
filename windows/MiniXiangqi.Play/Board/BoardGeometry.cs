// Every board dimension as a multiple of the cell pitch `p`.
//
// The values are apple/MiniXiangqi/Board/BoardGeometry.swift's, deliberately
// and to the digit: docs/interaction-design.md fixes the relationships and the
// gates, and the two games share one approximate width footprint. Mini Xiangqi
// uses a 44...102 point pitch; Xiangqi fits nine files into the same footprint
// with a 34...79 point pitch.
//
// Windows carries canonical coordinates on all four edges while its record is
// canonical coordinate text. Its block therefore adds the same strip extent to
// all four sides, but the block is not necessarily square: Xiangqi's ten ranks
// make it taller than its nine-file width.

using MiniXiangqi.Core;

namespace MiniXiangqi.Play;

public readonly record struct BoardGeometry(BoardDefinition Board, double Pitch)
{
    /// <summary>The accepted shared approximate core-width range.</summary>
    public const double MinimumCoreWidth = 308;

    public const double MaximumCoreWidth = 714;

    public BoardGeometry(GameKind game, double pitch)
        : this(BoardDefinition.For(game), pitch)
    {
    }

    public static double MinimumPitch(BoardDefinition board) =>
        Math.Floor(MinimumCoreWidth / board.FileCount);

    public static double MaximumPitch(BoardDefinition board) =>
        Math.Floor(MaximumCoreWidth / board.FileCount);

    // The board itself.

    /// <summary>
    /// The half-cell margin beyond the outer points, which is what keeps an
    /// edge disc from being clipped and contains the outermost points' markers.
    /// </summary>
    public double Margin => 0.5 * Pitch;

    /// <summary>Every point plus a half-cell margin on each outer edge.</summary>
    public double CoreWidth => Board.FileCount * Pitch;

    public double CoreHeight => Board.RankCount * Pitch;

    public (double Width, double Height) CoreSize => (CoreWidth, CoreHeight);

    /// <summary>
    /// <c>0.026 p</c>, clamped to between 0.80 and 1.60 points, so the lines
    /// never coarsen as the board grows. The palace diagonals match it exactly.
    /// </summary>
    public double GridStroke => Math.Clamp(0.026 * Pitch, 0.80, 1.60);

    // Pieces.

    public double DiscDiameter => 0.80 * Pitch;

    public double SymbolSize => 0.50 * Pitch;

    /// <summary>A style's own rings and edge strokes live at or inside <c>0.40 p</c>.</summary>
    public double StyleDecorationLimit => 0.40 * Pitch;

    /// <summary>
    /// The centre-line radius of a disc's edge stroke. The stroke is drawn
    /// inside the disc's own edge rather than centred on it.
    /// </summary>
    public double DiscEdgeRadius(double stroke) => (DiscDiameter / 2) - (stroke / 2);

    public double DecorationExtent(double edgeStroke) =>
        DiscEdgeRadius(edgeStroke) + (edgeStroke / 2);

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
    /// The origin's brackets have the destination's shape and ink at 0.6 of
    /// its weight, so the pair says which way the move went.
    /// </summary>
    public double LastMoveOriginStroke => 0.6 * LastMoveStroke;

    public double LastMoveInset => 0.05 * Pitch;

    public double HoverSide => 0.90 * Pitch;

    public double HoverCornerRadius => 0.12 * Pitch;

    // Edge coordinates.

    /// <summary><c>0.32 p</c>, rounded and clamped to between 13 and 20.</summary>
    public double LabelSize => Math.Clamp(
        Math.Round(0.32 * Pitch, MidpointRounding.AwayFromZero),
        13,
        20);

    /// <summary>
    /// <c>0.08 p + 0.887 s</c>: clear space between the outer line and label.
    /// One extent serves all four coordinate strips.
    /// </summary>
    public double StripExtent => Math.Round(
        (0.08 * Pitch) + (0.887 * LabelSize),
        MidpointRounding.AwayFromZero);

    /// <summary>The board core together with its four coordinate strips.</summary>
    public double BlockWidth => CoreWidth + (2 * StripExtent);

    public double BlockHeight => CoreHeight + (2 * StripExtent);

    public (double Width, double Height) BlockSize => (BlockWidth, BlockHeight);

    // Placing points.

    /// <summary>
    /// The centre of a point within the board core, with the board core's own
    /// origin at (0, 0). <paramref name="flipped"/> puts Black at the bottom.
    /// </summary>
    public (double X, double Y) Center(Square square, bool flipped)
    {
        int file = flipped ? Board.FileCount - 1 - square.File : square.File;
        int rank = flipped ? square.Rank : Board.RankCount - 1 - square.Rank;
        return (Margin + (file * Pitch), Margin + (rank * Pitch));
    }

    /// <summary>
    /// The point a click at (<paramref name="x"/>, <paramref name="y"/>)
    /// addresses, or null when it fell outside every cell.
    /// </summary>
    public Square? SquareAt(double x, double y, bool flipped)
    {
        int column = (int)Math.Round((x - Margin) / Pitch, MidpointRounding.AwayFromZero);
        int row = (int)Math.Round((y - Margin) / Pitch, MidpointRounding.AwayFromZero);
        if ((uint)column >= (uint)Board.FileCount || (uint)row >= (uint)Board.RankCount)
        {
            return null;
        }

        return new Square(
            flipped ? Board.FileCount - 1 - column : column,
            flipped ? row : Board.RankCount - 1 - row);
    }

    /// <summary>
    /// The largest whole-point pitch whose rectangular board block fits both
    /// dimensions, or null when even this board's accepted floor does not fit.
    /// </summary>
    public static BoardGeometry? Fitting(
        double width,
        double height,
        BoardDefinition board,
        double? floor = null)
    {
        double acceptedFloor = floor ?? MinimumPitch(board);
        double pitch = Math.Min(Math.Floor(width / board.FileCount), MaximumPitch(board));
        while (pitch >= acceptedFloor)
        {
            BoardGeometry candidate = new(board, pitch);
            if (candidate.BlockWidth <= width && candidate.BlockHeight <= height)
            {
                return candidate;
            }

            pitch -= 1;
        }

        return null;
    }

    public static BoardGeometry? Fitting(
        double width,
        double height,
        GameKind game,
        double? floor = null) =>
        Fitting(width, height, BoardDefinition.For(game), floor);
}
