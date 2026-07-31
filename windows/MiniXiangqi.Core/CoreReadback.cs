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
/// What a filed game committed, and the local library metadata beside it.
///
/// The outcome and the reason are the core's classification, derived from
/// committed state and never from a caller. The three instants are epoch
/// milliseconds, exactly as the store's derived columns hold them: when the game
/// began, when it ended, and when this library added it. They are three
/// different facts and the History destination shows two of them for two
/// different reasons — the row states the game's own end, and the order the core
/// returns records in is by the added time.
///
/// <c>Pinned</c> and <c>Provenance</c> are local library metadata rather than
/// archive content: neither is in the file, and neither affects content
/// equality.
/// </summary>
public readonly record struct RecordSummary(
    ulong RecordId,
    int Mode,
    int HumanSide,
    int AiLevel,
    int Outcome,
    int EndReason,
    int Provenance,
    bool Pinned,
    uint MoveCount,
    long StartedAtMs,
    long EndedAtMs,
    long AddedAtMs,
    string GameId);

/// <summary>
/// What an import did, when it did anything: the core's own outcome, plus the
/// record it created or the one it found already holding this identity and these
/// bytes.
/// </summary>
public readonly record struct ImportResult(int Outcome, ulong RecordId, RecordSummary Summary);

/// <summary>
/// One page of History, with the library revision the core answered it at.
///
/// The revision is the accepted answer to library-change observation — a
/// monotonic counter bumped by every committed store mutation, with no
/// notification mechanism in the MVP — and it is what lets a two-call read say
/// whether the two calls saw the same library.
/// </summary>
public readonly record struct HistoryPage(IReadOnlyList<RecordSummary> Records, ulong Revision);

/// <summary>The plan the accepted Hash-budget arithmetic yields.</summary>
public readonly record struct EnginePlan(
    uint Threads,
    uint HashMib,
    bool Sufficient,
    ulong ReserveBytes,
    ulong UsableBytes,
    ulong BudgetBytes);
