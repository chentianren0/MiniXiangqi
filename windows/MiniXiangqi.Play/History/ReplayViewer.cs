// The step-through viewer: one filed game, read-only, one ply at a time.
//
// **This is deliberately a viewer rather than the replay experience.** Issue
// #80's trimmed Windows scope, owner-decided 2026-07-30, makes replay on this
// platform "a simple step-through viewer" — History and reading Mac-saved games
// are the stage's promise and they stay; the motion language, the autoplay
// transport and its pause are what the trim removes, and they arrive with the
// post-Windows appearance pass. So the accepted five transport controls are four
// here — 回到开始, 上一步, 下一步, 跳到最后 — and the 自动播放/暂停 pair carries no
// code and no string. docs/interaction-design.md § History replay describes the
// whole experience; the Windows clause under it says which part of it this is.
//
// What the trim does *not* touch is where every fact comes from, and that is the
// whole of this file:
//
//   * the move line is `mxq_game_move_history`, read once from the detached
//     session `mxq_store_history_open` returned;
//   * every position is `mxq_game_position_at` — the core is asked what the
//     position *was* at that ply, and nothing here applies or unapplies a move to
//     work one out;
//   * the record's own classification — the result, the reason, the count — is
//     the summary the store answered with, never the replayed position's verdict,
//     because a resignation and an ended-early record are not properties of a
//     position at all.

using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Play;

public sealed class ReplayViewer : IDisposable
{
    private readonly GameSession _replay;
    private bool _flipped;

    internal ReplayViewer(RecordSummary record, GameSession replay)
    {
        Record = record;
        _replay = replay;
        MoveRecord = replay.MoveHistory();

        // Human-versus-AI history replay defaults to the original human player's
        // perspective; Free Play and *imported* history default to Red at the
        // bottom. An imported human-versus-AI game therefore opens Red-down: the
        // original human player is not the person reading it.
        _flipped = record.Mode == Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI
            && record.Provenance != Mxq.MXQ_PROVENANCE_IMPORTED
            && record.HumanSide == Mxq.MXQ_COLOR_BLACK;

        Show(0);
    }

    /// <summary>The record this is a replay of, as the store classified it.</summary>
    public RecordSummary Record { get; }

    /// <summary>
    /// The retained main line in the core's own canonical coordinate text, index
    /// 0 first.
    ///
    /// Issue #80's trim makes this the Windows MVP's record in both languages —
    /// the 记谱法 preference and the two proper renderings arrive together
    /// post-MVP — so what the archive holds and what the panel shows are the same
    /// string, and no formatter stands between them.
    /// </summary>
    public IReadOnlyList<string> MoveRecord { get; }

    /// <summary>Which ply is shown: 0 is the initial position.</summary>
    public int Ply { get; private set; }

    /// <summary>How many plies the record holds.</summary>
    public int Plies => MoveRecord.Count;

    /// <summary>The board, read-only: no selection, no destinations, no hover.</summary>
    public BoardScene Scene { get; private set; } = BoardScene.Of(Placement.Empty);

    /// <summary>The position the core reported at <see cref="Ply"/>.</summary>
    public BoardPosition Position { get; private set; }

    public bool IsAtStart => Ply == 0;

    public bool IsAtEnd => Ply == Plies;

    /// <summary>
    /// Progress through the game as *shown ply / recorded plies*, which is the
    /// accepted separate move-progress and playback state. There is no
    /// side-to-move line beside it, because a finished game is not anybody's
    /// turn.
    /// </summary>
    public string Progress => Strings.Format("replay.progress", Ply, Plies);

    /// <summary>The record's own metadata — the same line its History row carries.</summary>
    public string MetadataLine => Record.MetadataLine();

    /// <summary>
    /// Board orientation. Flipping changes presentation only: it moves no piece,
    /// changes no coordinate, and the record underneath is untouched.
    /// </summary>
    public bool Flipped => _flipped;

    public void FlipBoard()
    {
        _flipped = !_flipped;
        Compose();
    }

    /// <summary>回到开始.</summary>
    public void First() => Show(0);

    /// <summary>上一步.</summary>
    public void Previous() => Show(Ply - 1);

    /// <summary>下一步.</summary>
    public void Next() => Show(Ply + 1);

    /// <summary>跳到最后.</summary>
    public void Last() => Show(Plies);

    /// <summary>
    /// Show one ply, clamped to the record. The clamp is here rather than left to
    /// the core's own <c>MXQ_ERR_ARG_RANGE</c> because a transport button at an
    /// end is disabled rather than refused, and the move list can only select a
    /// move the list has.
    /// </summary>
    public void Show(int ply)
    {
        int target = Math.Clamp(ply, 0, Plies);
        Position = _replay.PositionAt((uint)target);
        Ply = target;
        Compose();
    }

    /// <summary>
    /// The move that produced the position on screen — the ply just played, and
    /// nothing at all at the initial position.
    /// </summary>
    private void Compose()
    {
        Placement placement = new(Position.Fen);
        Move? last = Ply > 0 ? Move.Parse(MoveRecord[Ply - 1]) : null;
        Side toMove = Position.SideToMove == Mxq.MXQ_COLOR_BLACK ? Side.Black : Side.Red;

        Scene = new BoardScene
        {
            Placement = placement,
            Flipped = _flipped,
            LastMove = last,

            // The core said whether the side to move is in check; this only says
            // which disc the rings go around.
            CheckedGeneral = Position.InCheck ? placement.General(toMove) : null,
        };
    }

    /// <summary>
    /// Release the detached session. It holds a decoded archive and a replayed
    /// line, and the core's shutdown promise puts quiescence on the caller.
    /// </summary>
    public void Dispose() => _replay.Dispose();
}
