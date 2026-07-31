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

    /// <summary>The complete legal-move set in the current position.</summary>
    public IReadOnlyList<string> LegalMoves() =>
        ReadMoves(static (game, buffer, cap, count, err) =>
            Mxq.mxq_game_legal_moves(game, buffer, cap, count, err));

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

    /// <summary>The raw handle, for the calls this wrapper does not cover.</summary>
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

        string[] text = new string[(int)count];
        for (int i = 0; i < text.Length; i++)
        {
            MxqMove move = moves[i];
            text[i] = Utf8.Read(move.text);
        }

        return text;
    }
}
