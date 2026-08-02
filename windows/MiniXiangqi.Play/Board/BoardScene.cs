// Everything the board draws, as one value.
//
// docs/interaction-design.md, "Game-state markers": the board shows the
// position and the states of the position, and nothing else. So this carries a
// placement and the states of it, and nothing about turns, saves, or the
// engine — those are the turn status's, and the reason the board is never read
// for two kinds of information at once is that it is never told them.
//
// It is a value rather than a view model on purpose: the painter is a pure
// function of it, which is what lets the same drawing code produce the window's
// board and the offscreen PNGs the pull request carries as evidence.

using System.Collections.Immutable;
using MiniXiangqi.Core;

namespace MiniXiangqi.Play;

public sealed record BoardScene
{
    public required Placement Placement { get; init; }

    /// <summary>The explicit game and topology carried by the placement.</summary>
    public GameKind Game => Placement.Game;

    public BoardDefinition Board => Placement.Board;

    /// <summary>Red at the bottom unless this says otherwise.</summary>
    public bool Flipped { get; init; }

    /// <summary>The held piece: the disc lifts and takes the solid selection ring.</summary>
    public Square? Selected { get; init; }

    /// <summary>Legal empty destinations — a filled dot in active ink.</summary>
    public ImmutableHashSet<Square> Destinations { get; init; } = [];

    /// <summary>Legal captures — a dashed ring in active ink around the enemy disc.</summary>
    public ImmutableHashSet<Square> Captures { get; init; } = [];

    /// <summary>
    /// The move that produced the position on screen. No brackets at an initial
    /// position, and an Undo moves them to the move that is now last.
    /// </summary>
    public Move? LastMove { get; init; }

    /// <summary>
    /// The general the core reports in check. Hidden while that general is
    /// held: the selection ring and the check rings occupy the same band and
    /// cannot both be drawn, and the turn status's 将军 token carries the state
    /// through the gap.
    /// </summary>
    public Square? CheckedGeneral { get; init; }

    /// <summary>
    /// Where the pointer is. It reports where an input device is, never what
    /// the game is doing, which is why it is rectangular and why it never
    /// previews a piece's legal destinations.
    /// </summary>
    public Square? Hovered { get; init; }

    public static BoardScene Of(Placement placement) => new() { Placement = placement };
}
