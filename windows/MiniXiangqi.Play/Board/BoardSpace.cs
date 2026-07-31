// What the board needs from the window, and what a board host shows when the
// space it has is not enough.
//
// Two things live here that used to live in MainWindow, and they are here for
// the reason everything else in this assembly is: a WinUI 3 process cannot be
// launched over SSH, so a number derived inside the window is a number no run on
// this project's Windows machine can check. MiniXiangqi.Smoke drives every one
// of them.
//
// **The notice is the owner's tour finding.** Below a certain space the board's
// geometry refuses rather than clamping — a board under the accepted 44-point
// floor is a decision, and BoardGeometry says why it declines to make one
// quietly — and until now the window answered that refusal by drawing the board
// at the floor anyway, into a host too small to hold it. What the owner saw was
// the consequence: a page whose whole point is a board, showing no board and
// saying nothing. The refusal now reaches the screen as a sentence.

namespace MiniXiangqi.Play;

/// <summary>
/// What a board host shows for the space it has: the board at the largest pitch
/// that fits, or the line that asks for a larger window.
/// </summary>
public readonly record struct BoardSpace
{
    private BoardSpace(BoardGeometry? board) => Board = board;

    /// <summary>
    /// The board this host draws, or null when it cannot draw one at the
    /// accepted floor.
    /// </summary>
    public BoardGeometry? Board { get; }

    public bool ShowsBoard => Board is not null;

    /// <summary>
    /// The line shown in the board's place, or null while the board is shown.
    /// One string, from the string of record, so the two frontends cannot
    /// disagree about what this state says.
    /// </summary>
    public string? Notice => Board is null ? Strings.Get("board.tooSmall") : null;

    /// <summary>
    /// What a host of this inner size — its padding already taken off — shows.
    ///
    /// The board is square and is sized to the largest square fitting **both**
    /// the width and the height, which is the accepted rule and is why a short
    /// window bounds it exactly as a narrow one does.
    /// </summary>
    public static BoardSpace Of(double width, double height)
    {
        double side = Math.Min(width, height);
        return new BoardSpace(side > 0 ? BoardGeometry.Fitting(side) : null);
    }
}

/// <summary>
/// The window's own floor, derived rather than written down, so that a geometry
/// change moves it.
/// </summary>
public static class WindowFloor
{
    /// <summary>The air a board host keeps around the board, on each side.</summary>
    public const double Air = 24;

    /// <summary>The panel beside the board on every page that has one.</summary>
    public const double PanelWidth = 260;

    /// <summary>The navigation row above every page, inside the shell's content.</summary>
    public const double NavigationBarHeight = 44;

    /// <summary>
    /// The compact rail the shell shows beside the content, and what the
    /// window's floor pays for on top of the content's own.
    /// </summary>
    public const double CompactRailWidth = 48;

    /// <summary>
    /// <c>NavigationView</c>'s own documented defaults, which this app does not
    /// set: the pane is an inline full-width pane at or above
    /// <see cref="ExpandedModeThresholdWidth"/>, the compact rail between that
    /// and 641, and hidden below it. <see cref="OpenPaneLength"/> is what the
    /// full-width pane measures.
    ///
    /// They are here because the floor has to survive them and because the
    /// arithmetic that says it does is worth checking rather than asserting.
    /// **An opened pane below the expanded threshold overlays the content and
    /// costs it no width at all**; only the inline pane takes any, and it exists
    /// only where there is width to spare.
    /// </summary>
    public const double ExpandedModeThresholdWidth = 1008;

    public const double CompactModeThresholdWidth = 641;

    public const double OpenPaneLength = 320;

    /// <summary>The board block at the accepted pitch floor: 340 square.</summary>
    public static double BoardBlockAtFloor => new BoardGeometry(BoardGeometry.MinimumPitch).BlockSide;

    /// <summary>
    /// The play content's floor on Windows: **648** wide.
    ///
    /// Not the 616 docs/interaction-design.md § Layout shapes states, because
    /// this board block is 340 wide rather than 308 — the Windows board carries
    /// the canonical coordinates on four edges rather than the file numerals on
    /// two.
    /// </summary>
    public static double ContentWidth => BoardBlockAtFloor + (2 * Air) + PanelWidth;

    /// <summary>The play content's floor in height: **388**, the board host alone.</summary>
    public static double ContentHeight => BoardBlockAtFloor + (2 * Air);

    /// <summary>
    /// The window's own floor in device-independent pixels, before the display
    /// scale and before the frame the presenter's minimum includes: 696 by 432.
    /// The content's floor plus the chrome around it — the rail, which costs
    /// width, and the navigation row, which costs height.
    /// </summary>
    public static double WindowWidth => ContentWidth + CompactRailWidth;

    public static double WindowHeight => ContentHeight + NavigationBarHeight;

    /// <summary>
    /// What the content keeps where the shell's pane is inline rather than a
    /// rail — the one arrangement that takes width from the content — measured
    /// at the narrowest window that produces it.
    ///
    /// It is <see cref="ExpandedModeThresholdWidth"/> minus
    /// <see cref="OpenPaneLength"/>, and it clears <see cref="ContentWidth"/>
    /// with room over. That is the whole answer to whether the expanded pane can
    /// squeeze the board: it cannot, because the platform only expands the pane
    /// where the window is wide enough to pay for it.
    /// </summary>
    public static double ContentAtExpandedThreshold =>
        ExpandedModeThresholdWidth - OpenPaneLength;
}
