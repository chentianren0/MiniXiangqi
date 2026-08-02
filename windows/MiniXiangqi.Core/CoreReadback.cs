namespace MiniXiangqi.Core;

/// <summary>The closed rules vocabulary shared with the native core.</summary>
public enum GameKind
{
    MiniXiangqi,
    Xiangqi,
}

/// <summary>
/// The one translation between managed game identity and the C boundary.
/// An unknown native value is a broken boundary and never means Mini Xiangqi.
/// </summary>
public static class GameVocabulary
{
    public static int Code(this GameKind game) => game switch
    {
        GameKind.MiniXiangqi => Interop.Mxq.MXQ_GAME_KIND_MINI_XIANGQI,
        GameKind.Xiangqi => Interop.Mxq.MXQ_GAME_KIND_XIANGQI,
        _ => throw new ArgumentOutOfRangeException(nameof(game), game, "Unknown game kind"),
    };

    public static GameKind Kind(int code) => code switch
    {
        Interop.Mxq.MXQ_GAME_KIND_MINI_XIANGQI => GameKind.MiniXiangqi,
        Interop.Mxq.MXQ_GAME_KIND_XIANGQI => GameKind.Xiangqi,
        _ => throw new InvalidDataException($"The core returned unknown game kind {code}"),
    };
}

/// <summary>
/// The four independent version axes and two build revisions, read back from
/// <c>mxq_core_version</c>. Per-game engine facts live in
/// <see cref="GameProfile"/> rather than being collapsed into one value here.
/// </summary>
public readonly record struct CoreVersion(
    uint ApiMajor,
    uint ApiMinor,
    uint ApiPatch,
    uint ArchiveVersionCurrent,
    uint ArchiveVersionMinReadable,
    uint StoreSchemaVersion,
    string CoreRevision,
    string ForkRevision)
{
    public string ApiVersion => $"{ApiMajor}.{ApiMinor}.{ApiPatch}";
}

/// <summary>The pinned engine variant and network for one game.</summary>
public readonly record struct GameProfile(
    GameKind Game,
    string VariantId,
    string NnueSha256)
{
    /// <summary>The exact identifier reported by a prepared engine.</summary>
    public string Identifier(CoreVersion version) =>
        $"{Prefix(version.CoreRevision)}-{Prefix(version.ForkRevision)}-{VariantId}-{Prefix(NnueSha256)}";

    private static string Prefix(string value) => value[..Math.Min(12, value.Length)];
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
    GameKind Game,
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
    GameKind Game,
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
