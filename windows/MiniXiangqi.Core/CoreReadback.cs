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

/// <summary>The plan the accepted Hash-budget arithmetic yields.</summary>
public readonly record struct EnginePlan(
    uint Threads,
    uint HashMib,
    bool Sufficient,
    ulong ReserveBytes,
    ulong UsableBytes,
    ulong BudgetBytes);
