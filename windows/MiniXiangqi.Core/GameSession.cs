using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Core;

/// <summary>
/// A game session. Single-owner by contract: a session may move between
/// threads, but only one thread may be inside it at a time, and a detected race
/// is <c>MXQ_ERR_ARG_CONCURRENT_USE</c> rather than a silent serialisation.
/// Nothing here enforces that; this type is thin, and the caller owns the
/// context it drives the session from.
/// </summary>
public sealed unsafe class GameSession : IDisposable
{
    private MxqGame* _game;

    internal GameSession(MxqGame* game)
    {
        _game = game;
    }

    /// <summary>The stable identity frozen at creation: a version 7 UUID.</summary>
    public string Id
    {
        get
        {
            sbyte* buffer = stackalloc sbyte[Mxq.MXQ_GAME_ID_CAP];
            nuint length;
            MxqError err = MxqCall.Error();
            MxqCall.Check(
                Mxq.mxq_game_id(Live, buffer, (nuint)Mxq.MXQ_GAME_ID_CAP, &length, &err),
                in err,
                nameof(Mxq.mxq_game_id));
            return Utf8.Read(new ReadOnlySpan<sbyte>(buffer, (int)length));
        }
    }

    /// <summary>The session's current position.</summary>
    public BoardPosition Position()
    {
        MxqPosition position = default;
        position.struct_size = (uint)sizeof(MxqPosition);
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_game_position(Live, &position, &err), in err, nameof(Mxq.mxq_game_position));

        return new BoardPosition(
            Utf8.Read(position.fen),
            position.side_to_move,
            position.ply_count,
            position.position_revision,
            position.in_check != 0);
    }

    /// <summary>The live state and the derived affordances.</summary>
    public GameState State()
    {
        MxqGameStatus status = default;
        status.struct_size = (uint)sizeof(MxqGameStatus);
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_game_status(Live, &status, &err), in err, nameof(Mxq.mxq_game_status));

        return new GameState(
            status.state,
            status.reason,
            status.at_occurrence,
            status.undo_plies,
            status.claim_available != 0,
            status.undo_available != 0,
            status.resign_available != 0,
            status.search_expected != 0);
    }

    /// <summary>The frozen configuration this game was created with.</summary>
    public GameConfiguration Configuration()
    {
        MxqGameConfig config = default;
        config.struct_size = (uint)sizeof(MxqGameConfig);
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_game_config(Live, &config, &err), in err, nameof(Mxq.mxq_game_config));

        return new GameConfiguration(
            config.mode,
            config.human_side,
            config.ai_level,
            config.first_mover_choice,
            config.ai_movetime_ms);
    }

    /// <summary>The complete legal-move set in the current position.</summary>
    public IReadOnlyList<string> LegalMoves() =>
        ReadMoves(static (game, buffer, cap, count, err) =>
            Mxq.mxq_game_legal_moves(game, buffer, cap, count, err));

    /// <summary>
    /// The legal moves originating at one point, which is the board's
    /// selection affordance. The core answers it; nothing above the C interface
    /// filters the complete set down to a square, because doing so would be
    /// re-deriving an affordance the core owns.
    /// </summary>
    public IReadOnlyList<string> LegalMovesFrom(string square)
    {
        MxqGame* game = Live;
        byte[] encoded = Utf8.Encode(square);
        fixed (byte* from = encoded)
        {
            nuint count;
            MxqError err = MxqCall.Error();
            MxqCall.CheckCountProbe(
                Mxq.mxq_game_legal_moves_from(game, (sbyte*)from, null, 0, &count, &err),
                in err,
                nameof(Mxq.mxq_game_legal_moves_from));
            if (count == 0)
            {
                return Array.Empty<string>();
            }

            MxqMove[] moves = new MxqMove[(int)count];
            fixed (MxqMove* buffer = moves)
            {
                err = MxqCall.Error();
                MxqCall.Check(
                    Mxq.mxq_game_legal_moves_from(game, (sbyte*)from, buffer, count, &count, &err),
                    in err,
                    nameof(Mxq.mxq_game_legal_moves_from));
            }

            return Text(moves, (int)count);
        }
    }

    /// <summary>
    /// The position after <paramref name="ply"/> plies of the retained line —
    /// ply 0 being the initial position. This is replay scrubbing: every step
    /// asks the core what the position *was*, and nothing above the interface
    /// applies or unapplies a move to work it out.
    ///
    /// A ply beyond the retained line is <c>MXQ_ERR_ARG_RANGE</c> and is
    /// deliberately **not** a programming error — a scrubber may legitimately
    /// probe an end — so it arrives as an ordinary <c>MxqException</c> rather
    /// than as an assertion.
    /// </summary>
    public BoardPosition PositionAt(uint ply)
    {
        MxqPosition position = default;
        position.struct_size = (uint)sizeof(MxqPosition);
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_game_position_at(Live, ply, &position, &err),
            in err,
            nameof(Mxq.mxq_game_position_at));

        return new BoardPosition(
            Utf8.Read(position.fen),
            position.side_to_move,
            position.ply_count,
            position.position_revision,
            position.in_check != 0);
    }

    /// <summary>The complete retained main line, index 0 first.</summary>
    public IReadOnlyList<string> MoveHistory() =>
        ReadMoves(static (game, buffer, cap, count, err) =>
            Mxq.mxq_game_move_history(game, buffer, cap, count, err));

    /// <summary>
    /// Apply one move in the frozen canonical notation and commit the updated
    /// active game before returning. There is no separate save.
    /// </summary>
    public BoardPosition ApplyMove(string move)
    {
        byte[] encoded = Utf8.Encode(move);
        MxqPosition after = default;
        after.struct_size = (uint)sizeof(MxqPosition);
        MxqGameStatus status = default;
        status.struct_size = (uint)sizeof(MxqGameStatus);
        MxqError err = MxqCall.Error();

        fixed (byte* text = encoded)
        {
            MxqCall.Check(
                Mxq.mxq_game_apply_move(Live, (sbyte*)text, &after, &status, &err),
                in err,
                nameof(Mxq.mxq_game_apply_move));
        }

        return new BoardPosition(
            Utf8.Read(after.fen),
            after.side_to_move,
            after.ply_count,
            after.position_revision,
            after.in_check != 0);
    }

    /// <summary>
    /// Take back one ply or one decision cycle, and commit. How many plies a
    /// decision is, is the core's answer and never a count taken above it: the
    /// returned figure is what it removed.
    /// </summary>
    public uint Undo()
    {
        uint removed;
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_game_undo(Live, &removed, &err), in err, nameof(Mxq.mxq_game_undo));
        return removed;
    }

    /// <summary>
    /// Claim the neutral threefold repetition as a draw. One atomic
    /// transaction: the outcome is committed, the History record inserted, and
    /// the active-game reference cleared. The session is archived afterwards
    /// and still answers every query, which is what leaves the finished board
    /// on screen.
    /// </summary>
    public ulong ClaimDraw() =>
        Commit(static (game, record, err) => Mxq.mxq_game_claim_draw(game, record, err),
            nameof(Mxq.mxq_game_claim_draw));

    /// <summary>Resign for the human side. Same transaction and consequence.</summary>
    public ulong Resign() =>
        Commit(static (game, record, err) => Mxq.mxq_game_resign(game, record, err),
            nameof(Mxq.mxq_game_resign));

    /// <summary>
    /// Commit an unconfirmed natural terminal state as its actual result and
    /// exact termination reason. Same transaction and consequence.
    /// </summary>
    public ulong ConfirmResult() =>
        Commit(static (game, record, err) => Mxq.mxq_game_confirm_result(game, record, err),
            nameof(Mxq.mxq_game_confirm_result));

    /// <summary>
    /// The raw handle, for the calls this wrapper does not cover — of which
    /// <c>mxq_search_start</c> is the one the play screen makes. Every function
    /// taking an <c>MxqGame *</c> counts as being inside the session for the
    /// single-owner rule, so a caller of this owes the same context.
    /// </summary>
    public MxqGame* Handle => Live;

    /// <summary>Release the session. Required after a terminal commit too.</summary>
    public void Dispose()
    {
        if (_game is null)
        {
            return;
        }

        MxqGame* game = _game;
        _game = null;
        Mxq.mxq_game_release(game);
    }

    private MxqGame* Live =>
        _game is null ? throw new ObjectDisposedException(nameof(GameSession)) : _game;

    private delegate int MoveReader(MxqGame* game, MxqMove* buffer, nuint cap, nuint* count, MxqError* err);

    private delegate int TerminalCommit(MxqGame* game, ulong* record, MxqError* err);

    // The three terminal commits differ only in which one they are: the same
    // atomic transaction, the same archived-session consequence, the same
    // record identifier out. Writing that once is what stops the third one from
    // quietly acquiring a fourth behaviour.
    private ulong Commit(TerminalCommit commit, string operation)
    {
        ulong record;
        MxqError err = MxqCall.Error();
        MxqCall.Check(commit(Live, &record, &err), in err, operation);
        return record;
    }

    // The core's buffer protocol, both halves: a NULL buffer with cap 0 asks for
    // the count, and the second call fills. There is no legal-move capacity
    // constant in mxq.h and this is why one is not needed.
    private IReadOnlyList<string> ReadMoves(MoveReader read)
    {
        MxqGame* game = Live;
        nuint count;
        MxqError err = MxqCall.Error();
        MxqCall.CheckCountProbe(read(game, null, 0, &count, &err), in err, "move readback");
        if (count == 0)
        {
            return Array.Empty<string>();
        }

        MxqMove[] moves = new MxqMove[(int)count];
        fixed (MxqMove* buffer = moves)
        {
            err = MxqCall.Error();
            MxqCall.Check(read(game, buffer, count, &count, &err), in err, "move readback");
        }

        return Text(moves, (int)count);
    }

    private static string[] Text(MxqMove[] moves, int count)
    {
        string[] text = new string[count];
        for (int i = 0; i < count; i++)
        {
            MxqMove move = moves[i];
            text[i] = Utf8.Read(move.text);
        }

        return text;
    }
}
