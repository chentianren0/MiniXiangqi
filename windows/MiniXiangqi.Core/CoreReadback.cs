namespace MiniXiangqi.Core;

/// <summary>
/// The four independent version axes, read back from <c>mxq_core_version</c>.
/// The engine-profile fields are load-bearing rather than diagnostics: a saved
/// diagnostic must be able to name the build that produced it.
/// </summary>
public readonly record struct CoreVersion(
    uint ApiMajor,
    uint ApiMinor,
    uint ApiPatch,
    uint ArchiveVersionCurrent,
    uint ArchiveVersionMinReadable,
    uint StoreSchemaVersion,
    string CoreRevision,
    string ForkRevision,
    string VariantId,
    string NnueSha256)
{
    public string ApiVersion => $"{ApiMajor}.{ApiMinor}.{ApiPatch}";
}

/// <summary>A session's current position, exactly as the core reports it.</summary>
public readonly record struct BoardPosition(
    string Fen,
    int SideToMove,
    uint PlyCount,
    ulong PositionRevision,
    bool InCheck);

/// <summary>
/// The live game state and the derived affordances. Nothing above the C
/// interface re-derives any of them.
/// </summary>
public readonly record struct GameState(
    int State,
    int EndReason,
    uint AtOccurrence,
    uint UndoPlies,
    bool ClaimAvailable,
    bool UndoAvailable,
    bool ResignAvailable,
    bool SearchExpected);

/// <summary>
/// A game's frozen configuration. <c>HumanSide</c>, <c>AiLevel</c>,
/// <c>FirstMoverChoice</c> and <c>MovetimeMs</c> are meaningful only in
/// human-versus-AI play; in Free Play they read as the NONE constants and zero,
/// matching the archive, which simply omits them.
/// </summary>
public readonly record struct GameConfiguration(
    int Mode,
    int HumanSide,
    int AiLevel,
    int FirstMoverChoice,
    uint MovetimeMs);

/// <summary>
/// One search's answer, copied out of core storage. An inert value: applying
/// the move is a separate explicit call, and no path exists from here to
/// committed state.
/// </summary>
public readonly record struct SearchAnswer(
    int Outcome,
    string Move,
    ulong Ticket,
    string GameId,
    ulong PositionRevision,
    int Status,
    uint Depth,
    ulong Nodes,
    int ScoreCp,
    uint ElapsedMs,
    string ProfileId);

/// <summary>
/// What a filed game committed. The outcome and the reason are the core's
/// classification, derived from committed state and never from a caller.
/// </summary>
public readonly record struct RecordSummary(
    ulong RecordId,
    int Outcome,
    int EndReason,
    uint MoveCount,
    string GameId);

/// <summary>The plan the accepted Hash-budget arithmetic yields.</summary>
public readonly record struct EnginePlan(
    uint Threads,
    uint HashMib,
    bool Sufficient,
    ulong ReserveBytes,
    ulong UsableBytes,
    ulong BudgetBytes);
