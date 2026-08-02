// What the board needs from the window, and what a board host shows when the
// space it has is not enough.
//
// Two things live here that used to live in MainWindow, and they are here for
// the reason everything else in this assembly is: a WinUI 3 process cannot be
// launched over SSH, so a number derived inside the window is a number no run on
// this project's Windows machine can check. MiniXiangqi.Smoke drives every one
// of them.
//
// **The notice is not the fix for the owner's tour finding; it is the floor
// under whatever is left.** That finding had a mechanism, and it was neither the
// navigation pane nor this refusal:
//
//   * the window's own minimum was computed from the content alone, while the
//     message it answers is about the *window* rectangle, so at the hard minimum
//     the client area came up 16 points short across and 40 short down — enough
//     to put the board host under the 340 the block needs;
//   * BoardGeometry.Fitting then refused, as it should, and the window's old
//     answer to a refusal was to draw the board at the floor anyway — assigning
//     a pitch-44 geometry that was *the same value* BoardView had been
//     constructed with, so its setter's equality guard returned early and the
//     view was never given a width or a height at all. Unsized and centred, it
//     measured nothing and painted nothing.
//
// Both are fixed where they live: the floor allows for the frame, and a board
// view is born at the size its geometry says. What remains for this file is the
// honest residue — a display scale that rounds badly, a platform default that
// moves — where the refusal is right and silence is not.

using MiniXiangqi.Core;

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
    /// The selected game's own rectangular profile is fitted against both
    /// dimensions, so Xiangqi's ten-rank board never overflows a short host.
    /// </summary>
    public static BoardSpace Of(double width, double height, GameKind game) =>
        Of(width, height, BoardDefinition.For(game));

    public static BoardSpace Of(double width, double height, BoardDefinition board) =>
        new(width > 0 && height > 0
            ? BoardGeometry.Fitting(width, height, board)
            : null);
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

    /// <summary>
    /// The widest floor-sized block across both games: Mini Xiangqi's 340.
    /// </summary>
    public static double BoardBlockWidthAtFloor => BoardDefinition.All.Max(board =>
        new BoardGeometry(board, BoardGeometry.MinimumPitch(board)).BlockWidth);

    /// <summary>
    /// The tallest floor-sized block across both games: Xiangqi's 368.
    /// </summary>
    public static double BoardBlockHeightAtFloor => BoardDefinition.All.Max(board =>
        new BoardGeometry(board, BoardGeometry.MinimumPitch(board)).BlockHeight);

    /// <summary>
    /// The play content's floor on Windows: **648** wide. Mini Xiangqi supplies
    /// the maximum floor-width block; the four coordinate strips make it 340.
    /// </summary>
    public static double ContentWidth => BoardBlockWidthAtFloor + (2 * Air) + PanelWidth;

    /// <summary>
    /// The play content's floor in height: **416**. Xiangqi supplies the
    /// maximum floor-height block: 340 points of core plus two 14-point strips.
    /// </summary>
    public static double ContentHeight => BoardBlockHeightAtFloor + (2 * Air);

    /// <summary>
    /// The window's own floor in device-independent pixels, before the display
    /// scale and before the frame the presenter's minimum includes: 696 by 460.
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
