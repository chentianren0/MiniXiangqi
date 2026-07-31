// The headless smoke harness for the Windows core interface.
//
// It is the proof docs/core-interface.md's Windows consumer paragraph asks for:
// the ClangSharp-generated declarations, called against the real mxqcore.dll,
// exercising every shape the boundary has — fixed-capacity char arrays,
// size_t as nuint, the two-call buffer protocol, the error taxonomy, a blob,
// an array of value structs, and an [UnmanagedCallersOnly] callback delivered
// on the core's own engine thread.
//
// Sections 1 to 16 deliberately call the generated declarations directly rather
// than the wrapper types beside them. A wrapper proves the wrapper; this proves
// the ABI.
//
// Sections 17 to 19 are the play screen's. A WinUI 3 process cannot be launched
// from an SSH session, so the Windows frontend's behaviour would otherwise be
// runnable on no machine this project owns. The screen's logic lives in
// MiniXiangqi.Play with no window attached to it, and this plays whole games
// through it: every move committed by clicking a point and then another point,
// the AI answering through the same marshalled callback the window uses, and
// the strings it shows checked against docs/copy.md.

using System.Diagnostics;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;
using MiniXiangqi.Play;

namespace MiniXiangqi.Smoke;

internal static unsafe class Program
{
    private static int _checks;
    private static int _failures;

    private static int Main(string[] args)
    {
        string assets = Argument(args, "--assets") ?? Path.Combine(AppContext.BaseDirectory, "assets");
        string store = Argument(args, "--store")
            ?? Path.Combine(Path.GetTempPath(), "mxq-smoke-" + Guid.NewGuid().ToString("N"));
        bool keepStore = Argument(args, "--store") is not null;
        string? copyTable = Argument(args, "--copy-table");

        Console.OutputEncoding = Encoding.UTF8;
        Console.WriteLine("Mini Xiangqi — Windows core interface smoke harness");
        Console.WriteLine("===================================================");
        Console.WriteLine($"runtime        {RuntimeInformation.FrameworkDescription}");
        Console.WriteLine($"process        {RuntimeInformation.ProcessArchitecture}");
        Console.WriteLine($"assets         {assets}");
        Console.WriteLine($"store          {store}");
        Console.WriteLine();

        try
        {
            Layout();
            BeforeInitialisation(assets);
            MxqEngineBudget budget = Probe();
            Run(store, assets, budget);
            WhatTheWindowDoes(store, assets);
            CopyTable(copyTable);
            ThePlayScreen(store, assets);
        }
        catch (Exception ex)
        {
            Console.WriteLine();
            Console.WriteLine($"UNHANDLED  {ex.GetType().Name}: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
            _failures++;
        }

        if (!keepStore && _failures == 0)
        {
            try
            {
                Directory.Delete(store, recursive: true);
            }
            catch (IOException)
            {
                // The store is a scratch directory; failing to remove it is not
                // a result.
            }
        }

        Console.WriteLine();
        Console.WriteLine($"{_checks} checks, {_failures} failed");
        Console.WriteLine(_failures == 0 ? "MXQ_SMOKE_OK" : "MXQ_SMOKE_FAILED");
        return _failures == 0 ? 0 : 1;
    }

    // ---------------------------------------------------------------------
    // 1. Layout — what the C# side believes the boundary's structs measure.
    // ---------------------------------------------------------------------
    private static void Layout()
    {
        Section("1. Struct layout as the generated bindings declare it");
        Console.WriteLine($"    MxqError            {sizeof(MxqError),4} bytes");
        Console.WriteLine($"    MxqVersion          {sizeof(MxqVersion),4} bytes");
        Console.WriteLine($"    MxqCoreConfig       {sizeof(MxqCoreConfig),4} bytes");
        Console.WriteLine($"    MxqMove             {sizeof(MxqMove),4} bytes");
        Console.WriteLine($"    MxqPosition         {sizeof(MxqPosition),4} bytes");
        Console.WriteLine($"    MxqGameStatus       {sizeof(MxqGameStatus),4} bytes");
        Console.WriteLine($"    MxqGameConfig       {sizeof(MxqGameConfig),4} bytes");
        Console.WriteLine($"    MxqRecordSummary    {sizeof(MxqRecordSummary),4} bytes");
        Console.WriteLine($"    MxqArchiveInfo      {sizeof(MxqArchiveInfo),4} bytes");
        Console.WriteLine($"    MxqEngineBudget     {sizeof(MxqEngineBudget),4} bytes");
        Console.WriteLine($"    MxqEnginePlan       {sizeof(MxqEnginePlan),4} bytes");
        Console.WriteLine($"    MxqSearchRequest    {sizeof(MxqSearchRequest),4} bytes");
        Console.WriteLine($"    MxqSearchResult     {sizeof(MxqSearchResult),4} bytes");
        Console.WriteLine($"    size_t              {sizeof(nuint),4} bytes (nuint)");

        // Every one of them is unmanaged, which is what "blittable by
        // construction" means in C#: no reference, no auto layout, nothing the
        // runtime would have to marshal. The bindings assembly also carries
        // [assembly: DisableRuntimeMarshalling], so a P/Invoke that was not
        // blittable could not be called at all.
        Check("every boundary struct is unmanaged", AllUnmanaged());

        // The trailing fixed-capacity arrays are where a layout disagreement
        // would show first, so their offsets are stated rather than trusted.
        MxqPosition position = default;
        MxqSearchResult result = default;
        Console.WriteLine($"    MxqPosition.fen at offset      {Offset(ref position, ref position.fen)}");
        Console.WriteLine($"    MxqSearchResult.profile_id at  {Offset(ref result, ref result.profile_id)}");
    }

    private static bool AllUnmanaged() =>
        !RuntimeHelpers.IsReferenceOrContainsReferences<MxqError>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqVersion>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqMove>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqPosition>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqGameStatus>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqGameConfig>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqRecordSummary>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqArchiveInfo>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqEngineBudget>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqEnginePlan>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqSearchRequest>()
        && !RuntimeHelpers.IsReferenceOrContainsReferences<MxqSearchResult>();

    private static nint Offset<TStruct, TField>(ref TStruct value, ref TField field)
        where TStruct : unmanaged
        where TField : unmanaged
    {
        return (nint)Unsafe.ByteOffset(ref Unsafe.As<TStruct, byte>(ref value), ref Unsafe.As<TField, byte>(ref field));
    }

    // ---------------------------------------------------------------------
    // 2. The queries that take no core instance.
    // ---------------------------------------------------------------------
    private static void BeforeInitialisation(string assets)
    {
        Section("2. Before mxq_core_init");

        MxqVersion version = default;
        version.struct_size = (uint)sizeof(MxqVersion);
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_core_version(&version, &err), in err, nameof(Mxq.mxq_core_version));

        string coreRevision = Utf8.Read(version.core_revision);
        string forkRevision = Utf8.Read(version.fork_revision);
        string variantId = Utf8.Read(version.variant_id);
        string nnueSha = Utf8.Read(version.nnue_sha256);

        Console.WriteLine($"    api                 {version.api_major}.{version.api_minor}.{version.api_patch}");
        Console.WriteLine($"    archive             current {version.archive_version_current}, min readable {version.archive_version_min_readable}");
        Console.WriteLine($"    store schema        {version.store_schema_version}");
        Console.WriteLine($"    core revision       {coreRevision}");
        Console.WriteLine($"    fork revision       {forkRevision}");
        Console.WriteLine($"    variant             {variantId}");
        Console.WriteLine($"    nnue sha256         {nnueSha}");

        Check("api version is the one this binding compiled against",
            version.api_major == (uint)Mxq.MXQ_API_VERSION_MAJOR
            && version.api_minor == (uint)Mxq.MXQ_API_VERSION_MINOR
            && version.api_patch == (uint)Mxq.MXQ_API_VERSION_PATCH);

        // MxqVersion's four fixed-capacity arrays are its last four fields, so
        // reading all of them correctly is an end-to-end statement about the
        // whole struct's layout rather than about its prefix.
        Check("fork revision is a full hexadecimal revision", IsHex(forkRevision, 40));
        Check("nnue sha256 is lowercase hexadecimal", IsHex(nnueSha, 64));
        Check("variant identifier is the pinned one", variantId == "minixiangqiaxf");

        // And the network the core says it was built against is the network
        // staged beside this executable, which is the only claim here that
        // reaches outside the process.
        string stagedSha = StagedNetworkSha(assets);
        Console.WriteLine($"    staged nnue sha256  {stagedSha}");
        Check("the staged network is the one the core reports", stagedSha == nnueSha);

        sbyte* fenBuffer = stackalloc sbyte[Mxq.MXQ_FEN_CAP];
        nuint fenLength;
        err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_rules_start_fen(fenBuffer, (nuint)Mxq.MXQ_FEN_CAP, &fenLength, &err),
            in err,
            nameof(Mxq.mxq_rules_start_fen));
        string startFen = Utf8.Read(new ReadOnlySpan<sbyte>(fenBuffer, (int)fenLength));
        Console.WriteLine($"    start fen           {startFen}");
        Check("start fen has six fields", startFen.Split(' ').Length == 6);
        Check("start fen length agrees with out_len", (int)fenLength == startFen.Length);

        // The routine buffer-too-small answer, which is not a programming error
        // and carries the size the call needs.
        sbyte* tiny = stackalloc sbyte[4];
        nuint ignored;
        err = MxqCall.Error();
        int status = Mxq.mxq_rules_start_fen(tiny, 4, &ignored, &err);
        Console.WriteLine($"    undersized buffer   {MxqCall.StatusName(status)}, required_size {err.required_size}");
        Check("an undersized buffer is MXQ_ERR_ARG_BUFFER_TOO_SMALL",
            status == Mxq.MXQ_ERR_ARG_BUFFER_TOO_SMALL && err.required_size == (ulong)(startFen.Length + 1));

        uint minReadable;
        uint current;
        err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_archive_supported_versions(&minReadable, &current, &err),
            in err,
            nameof(Mxq.mxq_archive_supported_versions));
        Console.WriteLine($"    archive versions    min readable {minReadable}, current {current}");

    }

    // ---------------------------------------------------------------------
    // 3. The Windows memory probe, and the plan it yields.
    // ---------------------------------------------------------------------
    private static MxqEngineBudget Probe()
    {
        Section("3. GlobalMemoryStatusEx, and mxq_engine_plan over it");

        MxqEngineBudget budget = WindowsMemoryProbe.Current();
        Console.WriteLine($"    processors          {budget.active_processor_count}");
        Console.WriteLine($"    available           {Mib(budget.available_bytes)}");
        Console.WriteLine($"    physical            {Mib(budget.physical_bytes)}");

        EnginePlan plan = MiniXiangqiCore.PlanFor(budget);
        Console.WriteLine($"    threads             {plan.Threads}");
        Console.WriteLine($"    hash                {plan.HashMib} MiB");
        Console.WriteLine($"    reserve / usable    {Mib(plan.ReserveBytes)} / {Mib(plan.UsableBytes)}");
        Console.WriteLine($"    sufficient          {plan.Sufficient}");

        Check("the probe reported a physical memory size", budget.physical_bytes > 0);
        Check("the plan is sufficient on this machine", plan.Sufficient);
        Check("hash is a multiple of the granularity",
            plan.HashMib % Mxq.MXQ_ENGINE_HASH_GRANULARITY_MIB == 0);
        return budget;
    }

    // ---------------------------------------------------------------------
    // 4-10. A whole game's worth of the boundary, against a live core.
    // ---------------------------------------------------------------------
    private static void Run(string store, string assets, MxqEngineBudget budget)
    {
        Section("4. mxq_core_init");
        using MiniXiangqiCore core = MiniXiangqiCore.Start(store, assets);
        Console.WriteLine("    core initialised, store opened");
        Check("the store directory now exists", Directory.Exists(store));

        Section("5. mxq_game_create — human versus AI, red, fast");
        MxqGameConfig config = default;
        config.struct_size = (uint)sizeof(MxqGameConfig);
        config.mode = Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI;
        config.human_side = Mxq.MXQ_COLOR_RED;
        config.ai_level = Mxq.MXQ_AI_LEVEL_FAST;
        config.first_mover_choice = Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST;
        config.ai_movetime_ms = Mxq.MXQ_MOVETIME_FAST_MS;

        MxqGame* game;
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_game_create(core.Handle, &config, &game, &err), in err, nameof(Mxq.mxq_game_create));

        sbyte* idBuffer = stackalloc sbyte[Mxq.MXQ_GAME_ID_CAP];
        nuint idLength;
        err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_game_id(game, idBuffer, (nuint)Mxq.MXQ_GAME_ID_CAP, &idLength, &err),
            in err,
            nameof(Mxq.mxq_game_id));
        string gameId = Utf8.Read(new ReadOnlySpan<sbyte>(idBuffer, (int)idLength));
        Console.WriteLine($"    game id             {gameId}");
        Check("the game id is a canonical UUID", Guid.TryParseExact(gameId, "D", out _));

        Section("6. Position and state readback");
        MxqPosition position = ReadPosition(game);
        MxqGameStatus status = ReadStatus(game);
        Console.WriteLine($"    fen                 {Utf8.Read(position.fen)}");
        Console.WriteLine($"    side to move        {ColorName(position.side_to_move)}");
        Console.WriteLine($"    ply / revision      {position.ply_count} / {position.position_revision}");
        Console.WriteLine($"    in check            {position.in_check != 0}");
        Console.WriteLine($"    state / reason      {status.state} / {status.reason}");
        Console.WriteLine($"    affordances         claim {status.claim_available}, undo {status.undo_available}, resign {status.resign_available}, search expected {status.search_expected}");

        Check("a new game starts at the frozen starting position",
            Utf8.Read(position.fen) == MiniXiangqiCore.StartFen);
        Check("red moves first", position.side_to_move == Mxq.MXQ_COLOR_RED);
        Check("a new game is ongoing", status.state == Mxq.MXQ_GAME_ONGOING);
        Check("resignation is available in human-versus-AI play", status.resign_available == 1);
        Check("nothing to undo yet", status.undo_available == 0);

        Section("7. mxq_game_legal_moves — both halves of the buffer protocol");
        nuint count;
        err = MxqCall.Error();
        int probe = Mxq.mxq_game_legal_moves(game, null, 0, &count, &err);
        Console.WriteLine($"    count-only call     {count} moves, {MxqCall.StatusName(probe)}, required_size {err.required_size}");

        // The probe answers with the routine buffer-too-small status rather
        // than MXQ_OK, because a cap of 0 genuinely could not hold the answer.
        // Only an empty list answers MXQ_OK. Both are the protocol working.
        Check("the count probe answers MXQ_ERR_ARG_BUFFER_TOO_SMALL with the count",
            probe == Mxq.MXQ_ERR_ARG_BUFFER_TOO_SMALL && count > 0
            && err.required_size == count);

        MxqMove[] moves = new MxqMove[(int)count];
        fixed (MxqMove* buffer = moves)
        {
            err = MxqCall.Error();
            MxqCall.Check(Mxq.mxq_game_legal_moves(game, buffer, count, &count, &err), in err, "legal moves");
        }

        string[] moveText = new string[(int)count];
        for (int i = 0; i < moveText.Length; i++)
        {
            MxqMove move = moves[i];
            moveText[i] = Utf8.Read(move.text);
        }

        Array.Sort(moveText, StringComparer.Ordinal);
        Console.WriteLine($"    moves               {string.Join(' ', moveText)}");
        Check("the two calls agree on the count", moveText.Length == (int)count);
        Check("every move is canonical <from><to>", Array.TrueForAll(moveText, IsCanonicalMove));

        Section("8. mxq_game_apply_move");
        string chosen = moveText[0];
        MxqPosition after = default;
        after.struct_size = (uint)sizeof(MxqPosition);
        MxqGameStatus afterStatus = default;
        afterStatus.struct_size = (uint)sizeof(MxqGameStatus);
        byte[] encoded = Utf8.Encode(chosen);
        err = MxqCall.Error();
        fixed (byte* text = encoded)
        {
            MxqCall.Check(
                Mxq.mxq_game_apply_move(game, (sbyte*)text, &after, &afterStatus, &err),
                in err,
                nameof(Mxq.mxq_game_apply_move));
        }

        Console.WriteLine($"    applied             {chosen}");
        Console.WriteLine($"    fen                 {Utf8.Read(after.fen)}");
        Console.WriteLine($"    side to move        {ColorName(after.side_to_move)}");
        Console.WriteLine($"    ply / revision      {after.ply_count} / {after.position_revision}");
        Console.WriteLine($"    search expected     {afterStatus.search_expected}");
        Check("the ply count advanced", after.ply_count == position.ply_count + 1);
        Check("the position revision advanced", after.position_revision > position.position_revision);
        Check("it is now black to move", after.side_to_move == Mxq.MXQ_COLOR_BLACK);
        Check("the AI is now expected to answer", afterStatus.search_expected == 1);

        err = MxqCall.Error();
        MxqCall.CheckCountProbe(
            Mxq.mxq_game_move_history(game, null, 0, &count, &err), in err, "history count");
        Console.WriteLine($"    move history        {count} ply");
        Check("the retained line holds the one move", count == 1);

        Section("9. The error taxonomy across the boundary");
        ExpectRefusal(game, "zzzz", Mxq.MXQ_ERR_RULES_MALFORMED_MOVE);
        ExpectRefusal(game, moveText[0], Mxq.MXQ_ERR_RULES_ILLEGAL_MOVE);

        Section("10. mxq_engine_prepare");

        // Through the wrapper rather than through the generated declaration
        // directly. The wrapper shadows this call exactly, so calling the raw
        // one here would leave the helper the frontend will actually use with
        // no run behind it.
        EnginePlan applied = core.PrepareEngine(budget);
        Console.WriteLine($"    applied threads     {applied.Threads}");
        Console.WriteLine($"    applied hash        {applied.HashMib} MiB");

        int engineState;
        sbyte* profileBuffer = stackalloc sbyte[Mxq.MXQ_PROFILE_ID_CAP];
        nuint profileLength;
        err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_engine_query(core.Handle, &engineState, profileBuffer, (nuint)Mxq.MXQ_PROFILE_ID_CAP, &profileLength, &err),
            in err,
            nameof(Mxq.mxq_engine_query));
        Console.WriteLine($"    engine state        {engineState}");
        Console.WriteLine($"    profile             {Utf8.Read(new ReadOnlySpan<sbyte>(profileBuffer, (int)profileLength))}");
        Check("the engine is ready", engineState == Mxq.MXQ_ENGINE_STATE_READY);

        Section("11. mxq_search_start with an [UnmanagedCallersOnly] callback");
        string aiMove = Search(core, game, gameId, after.position_revision);

        Section("12. Applying the engine's move");
        encoded = Utf8.Encode(aiMove);
        MxqPosition afterAi = default;
        afterAi.struct_size = (uint)sizeof(MxqPosition);
        MxqGameStatus afterAiStatus = default;
        afterAiStatus.struct_size = (uint)sizeof(MxqGameStatus);
        err = MxqCall.Error();
        fixed (byte* text = encoded)
        {
            MxqCall.Check(
                Mxq.mxq_game_apply_move(game, (sbyte*)text, &afterAi, &afterAiStatus, &err),
                in err,
                nameof(Mxq.mxq_game_apply_move));
        }

        Console.WriteLine($"    fen                 {Utf8.Read(afterAi.fen)}");
        Console.WriteLine($"    ply / revision      {afterAi.ply_count} / {afterAi.position_revision}");
        Check("two plies have been played", afterAi.ply_count == 2);
        Check("it is red to move again", afterAi.side_to_move == Mxq.MXQ_COLOR_RED);

        Section("13. mxq_archive_encode — the one pointer into core memory");
        MxqBlob* blob;
        err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_archive_encode(core.Handle, game, &blob, &err), in err, nameof(Mxq.mxq_archive_encode));
        nuint length = Mxq.mxq_blob_len(blob);
        byte* bytes = Mxq.mxq_blob_bytes(blob);
        string document = Encoding.UTF8.GetString(bytes, (int)length);
        Console.WriteLine($"    blob length         {length} bytes");
        Console.WriteLine($"    first line          {document.Split('\n')[0]}");
        Check("the archive carries this game's identity", document.Contains(gameId, StringComparison.Ordinal));
        Check("the archive carries both moves",
            document.Contains(chosen, StringComparison.Ordinal) && document.Contains(aiMove, StringComparison.Ordinal));
        Mxq.mxq_blob_release(blob);

        Section("14. mxq_store_archive_and_clear, and the History readback");
        ulong recordId;
        err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_store_archive_and_clear(core.Handle, game, &recordId, &err),
            in err,
            nameof(Mxq.mxq_store_archive_and_clear));
        Console.WriteLine($"    record id           {recordId}");

        uint historyCount;
        ulong libraryRevision;
        err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_store_history_count(core.Handle, &historyCount, &libraryRevision, &err),
            in err,
            nameof(Mxq.mxq_store_history_count));
        Console.WriteLine($"    history             {historyCount} record(s), library revision {libraryRevision}");
        Check("the game is in History", historyCount == 1);

        MxqRecordSummary[] page = new MxqRecordSummary[4];
        nuint written;
        fixed (MxqRecordSummary* pageBuffer = page)
        {
            err = MxqCall.Error();
            MxqCall.Check(
                Mxq.mxq_store_history_page(core.Handle, 0, 4, pageBuffer, 4, &written, &libraryRevision, &err),
                in err,
                nameof(Mxq.mxq_store_history_page));
        }

        MxqRecordSummary summary = page[0];
        string summaryId = Utf8.Read(summary.game_id);
        Console.WriteLine($"    summary game id     {summaryId}");
        Console.WriteLine($"    summary moves       {summary.move_count}");
        Console.WriteLine($"    summary outcome     {summary.outcome}, end reason {summary.end_reason}");
        Console.WriteLine($"    summary provenance  {summary.provenance}, pinned {summary.pinned}, active {summary.is_active}");
        Check("the page wrote one record", written == 1);
        Check("the summary names the game just archived", summaryId == gameId);
        Check("the summary counts both plies", summary.move_count == 2);
        Check("an early save records no competitive result",
            summary.outcome == Mxq.MXQ_OUTCOME_NONE && summary.end_reason == Mxq.MXQ_END_REASON_ENDED_EARLY);
        Check("the record is locally played", summary.provenance == Mxq.MXQ_PROVENANCE_LOCALLY_PLAYED);

        Section("15. Release and shutdown");
        Mxq.mxq_game_release(game);
        core.Dispose();
        Console.WriteLine("    session released, core shut down");
    }

    // ---------------------------------------------------------------------
    // 16. Everything the window does, minus the XAML.
    //
    // A WinUI 3 process cannot be launched from an SSH session — session 0 has
    // no interactive desktop and the Windows App SDK's input stack fail-fasts
    // before any of this project's code runs — so the window's own evidence is
    // that it builds. What it would otherwise leave unproven is the wrapper
    // between it and the generated bindings, which is real code with real
    // callers. So the harness drives exactly the calls MainWindow makes, in
    // the order it makes them, headlessly.
    // ---------------------------------------------------------------------
    private static void WhatTheWindowDoes(string store, string assets)
    {
        Section("16. The wrapper the window uses, over a second core lifetime");

        CoreVersion version = MiniXiangqiCore.Version;
        Console.WriteLine($"    api                 {version.ApiVersion}");
        Console.WriteLine($"    variant             {version.VariantId}");

        using MiniXiangqiCore core = MiniXiangqiCore.Start(store, assets);
        Console.WriteLine("    core re-initialised over the same store");

        // The previous section archived its game, so the library holds no
        // active one and this is the create half of resume-or-create.
        using GameSession session = core.ResumeOrCreate(
            humanSide: Mxq.MXQ_COLOR_RED,
            aiLevel: Mxq.MXQ_AI_LEVEL_FAST,
            firstMoverChoice: Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST,
            movetimeMs: Mxq.MXQ_MOVETIME_FAST_MS);

        BoardPosition position = session.Position();
        GameState state = session.State();
        IReadOnlyList<string> legal = session.LegalMoves();
        IReadOnlyList<string> history = session.MoveHistory();

        Console.WriteLine($"    game id             {session.Id}");
        Console.WriteLine($"    fen                 {position.Fen}");
        Console.WriteLine($"    ply / revision      {position.PlyCount} / {position.PositionRevision}");
        Console.WriteLine($"    state / reason      {state.State} / {state.EndReason}");
        Console.WriteLine($"    legal moves         {legal.Count}");
        Console.WriteLine($"    history             {history.Count}");

        Check("a second core opened over the same store", position.Fen == MiniXiangqiCore.StartFen);
        Check("the wrapper read the legal-move set", legal.Count > 0);
        Check("a new game has no retained line", history.Count == 0);

        BoardPosition after = session.ApplyMove(legal[0]);
        IReadOnlyList<string> historyAfter = session.MoveHistory();
        Console.WriteLine($"    applied             {legal[0]}");
        Console.WriteLine($"    fen                 {after.Fen}");
        Console.WriteLine($"    history             {historyAfter.Count}: {string.Join(' ', historyAfter)}");

        Check("the wrapper applied a move", after.PlyCount == 1);
        Check("the retained line holds it", historyAfter.Count == 1 && historyAfter[0] == legal[0]);

        // The wrapper's refusal path, which is the window's only error surface:
        // its catch reads StatusName, Status, Domain and Detail straight onto
        // the view. All four have to arrive populated and agreeing with each
        // other, and the detail has to survive MxqError's caller-supplied-out
        // guard, so the refusal is taken through the wrapper rather than around
        // it.
        MxqException? refusal = null;
        try
        {
            session.ApplyMove("zzzz");
        }
        catch (MxqException ex)
        {
            refusal = ex;
        }

        Console.WriteLine($"    refused             {refusal?.StatusName} ({refusal?.Status}), domain {refusal?.Domain}");
        Console.WriteLine($"    detail              {refusal?.Detail}");
        Console.WriteLine($"    message             {refusal?.Message}");

        Check("a malformed move through the wrapper throws MxqException", refusal is not null);
        Check("the exception carries the typed status",
            refusal?.Status == Mxq.MXQ_ERR_RULES_MALFORMED_MOVE);
        Check("the exception carries the status name",
            refusal?.StatusName == "MXQ_ERR_RULES_MALFORMED_MOVE");
        Check("the exception carries the domain", refusal?.Domain == Mxq.MXQ_DOMAIN_RULES);
        Check("the exception carries the core's own diagnostic",
            refusal is not null && refusal.Detail.Length > 0);
        Check("the message names the operation and the diagnostic",
            refusal is not null
            && refusal.Message.Contains(nameof(Mxq.mxq_game_apply_move), StringComparison.Ordinal)
            && refusal.Message.Contains(refusal.Detail, StringComparison.Ordinal));
        Check("the refused move committed nothing", session.MoveHistory().Count == 1);

        // The other half of resume-or-create is not reachable in one process:
        // a second mxq_game_resume_active while the first session is live is
        // MXQ_ERR_ARG_CONCURRENT_USE by contract, so the resume path is what
        // the window exercises at its second launch.
        Console.WriteLine("    (the resume half of resume-or-create belongs to a second launch)");
    }

    // ---------------------------------------------------------------------
    // 17. The string table against docs/copy.md.
    //
    // docs/copy.md's localization process asks for "one check that this table
    // and the String Catalog agree in both languages — the same key set, the
    // same values, and no user-facing key in the catalog that is absent here",
    // and says it joins CI when CI exists. CI exists. This is that check for
    // the Windows frontend's own table, and the Windows workflow passes it the
    // path to the contract.
    // ---------------------------------------------------------------------
    private static void CopyTable(string? path)
    {
        Section("17. The string table against docs/copy.md");
        if (path is null)
        {
            Console.WriteLine("    (no --copy-table given; the contract was not read)");
            return;
        }

        Dictionary<string, (string Chinese, string English)> contract = ReadCopyTable(path);
        Console.WriteLine($"    contract rows       {contract.Count}");
        Console.WriteLine($"    frontend keys       {Strings.Table.Count}");

        List<string> missing = [];
        List<string> disagreeing = [];
        foreach ((string key, LocalizedString row) in Strings.Table)
        {
            if (!contract.TryGetValue(key, out (string Chinese, string English) approved))
            {
                missing.Add(key);
                continue;
            }

            // The piece names are the one row shape whose Chinese cell is a
            // description rather than a value — docs/copy.md writes
            // "帅 (red) / 将 (black)", because the string itself is the
            // placeholder that lets the character through, and the ten piece
            // characters are game content that never enters a string table.
            // Its English half is a value like any other.
            bool chineseIsDescription = key.StartsWith("piece.", StringComparison.Ordinal);

            if (row.English != Placeholders(approved.English)
                || (!chineseIsDescription && row.Chinese != Placeholders(approved.Chinese)))
            {
                disagreeing.Add(key);
            }
        }

        foreach (string key in missing)
        {
            Console.WriteLine($"    absent from copy.md {key}");
        }

        foreach (string key in disagreeing)
        {
            Console.WriteLine($"    disagrees           {key}");
            Console.WriteLine($"      contract          {contract[key].Chinese} / {contract[key].English}");
            Console.WriteLine($"      frontend          {Strings.Table[key].Chinese} / {Strings.Table[key].English}");
        }

        Check("every string the screen shows is a row of docs/copy.md", missing.Count == 0);
        Check("every row agrees with the contract in both languages", disagreeing.Count == 0);
    }

    /// <summary>
    /// docs/copy.md's format specifiers are the platform's — <c>%1$@</c>,
    /// <c>%lld</c> — because the Apple frontend is where they are live. .NET
    /// composes with <c>{0}</c>. The check translates rather than either side
    /// pretending the other's spelling.
    /// </summary>
    private static string Placeholders(string value) => value
        .Replace("%1$@", "{0}", StringComparison.Ordinal)
        .Replace("%2$@", "{1}", StringComparison.Ordinal)
        .Replace("%1$lld", "{0}", StringComparison.Ordinal)
        .Replace("%2$lld", "{1}", StringComparison.Ordinal)
        .Replace("%lld", "{0}", StringComparison.Ordinal)
        .Replace("%@", "{0}", StringComparison.Ordinal);

    private static Dictionary<string, (string Chinese, string English)> ReadCopyTable(string path)
    {
        Dictionary<string, (string, string)> rows = new(StringComparer.Ordinal);
        foreach (string line in File.ReadLines(path))
        {
            string trimmed = line.Trim();
            if (!trimmed.StartsWith('|'))
            {
                continue;
            }

            string[] cells = trimmed.Trim('|').Split('|');
            if (cells.Length < 5)
            {
                continue;
            }

            string key = Cell(cells[0]).Replace("*(proposed)*", string.Empty, StringComparison.Ordinal).Trim();
            key = key.Trim('`');
            if (key.Length == 0 || key == "Key" || key.StartsWith('-'))
            {
                continue;
            }

            rows[key] = (Cell(cells[1]), Cell(cells[2]));
        }

        return rows;

        static string Cell(string value) => value.Trim().Trim('`').Trim();
    }

    // ---------------------------------------------------------------------
    // 18. The play screen itself: a whole game against the AI, and a game of
    //     Free Play, driven through the same session the window drives.
    //
    // A WinUI 3 process cannot be launched from an SSH session, so this is
    // where the Windows play screen's behaviour is actually run. Every move
    // below is committed by clicking a point and then another point, through
    // PlaySession.Tap — the same call the window's board makes — and every
    // answer comes back through the same scheduler the window supplies.
    // ---------------------------------------------------------------------
    private static void ThePlayScreen(string store, string assets)
    {
        Section("18. A game against the AI, through the play screen's own session");

        using MiniXiangqiCore core = MiniXiangqiCore.Start(store, assets);
        PumpScheduler scheduler = new();

        // Section 16 left its game active, and one game is active at a time, so
        // it is filed before this one is created — which is the same
        // archive-and-clear the save-and-continue flow performs.
        using (GameSession? standing = core.ResumeActive())
        {
            if (standing is not null)
            {
                Console.WriteLine($"    filed the standing  {core.ArchiveAndClear(standing)}");
            }
        }

        GameSession game = core.Create(
            Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI,
            Mxq.MXQ_COLOR_RED,
            Mxq.MXQ_AI_LEVEL_FAST,
            Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST,
            Mxq.MXQ_MOVETIME_FAST_MS);

        using PlaySession play = new(core, game, scheduler);
        Console.WriteLine($"    game id             {play.GameId}");
        Console.WriteLine($"    mode                human versus AI, human red, 快速");
        Console.WriteLine($"    status              {play.PrimaryStatus()} / {play.SecondaryStatus()}");

        Check("the human moves first, so the board accepts input", play.AcceptsInput);
        Check("the board starts with Red at the bottom", !play.Scene.Flipped);
        Check("no board-flip control in human-versus-AI play", !play.CanFlip);
        Check("resignation is offered", play.CanResign);
        Check("there is nothing to undo yet", !play.CanUndo);

        play.Begin();

        // A selection, and what it reveals. The set is the core's answer about
        // one point; nothing here filters a complete set down to a square.
        Square opening = FirstMover(play);
        play.Tap(opening);
        Console.WriteLine(
            $"    selected {opening.Name}         {play.Scene.Destinations.Count} destination(s), "
            + $"{play.Scene.Captures.Count} capture(s)");
        Check("selecting a piece reveals its legal destinations",
            play.Scene.Selected == opening
            && play.Scene.Destinations.Count + play.Scene.Captures.Count > 0);

        play.Tap(opening);
        Check("tapping the selected piece again cancels the selection", play.Scene.Selected is null);

        Random rng = new(20260731);
        int plies = 0;
        int humanMoves = 0;
        int aiMoves = 0;
        bool sawThinking = false;
        bool sawClaimable = false;
        const int cap = 80;

        while (!play.IsOver && plies < cap)
        {
            if (play.AcceptsInput)
            {
                if (Choose(play, rng) is not { } move)
                {
                    break;
                }

                play.Tap(move.From);
                play.Tap(move.To);
                humanMoves++;
            }
            else
            {
                int before = play.MoveRecord.Count;
                bool answered = scheduler.PumpUntil(
                    () =>
                    {
                        sawThinking |= play.Activity == AiActivity.Thinking;
                        return play.MoveRecord.Count > before || play.IsOver
                            || play.Activity == AiActivity.Stalled
                            || play.Alert != PlayAlert.None;
                    },
                    TimeSpan.FromSeconds(30));

                if (!answered || play.Activity == AiActivity.Stalled || play.Alert != PlayAlert.None)
                {
                    Console.WriteLine($"    the AI stopped      activity {play.Activity}, alert {play.Alert}");
                    break;
                }

                aiMoves++;
            }

            sawClaimable |= play.CanClaimDraw;
            plies = play.MoveRecord.Count;
        }

        Console.WriteLine($"    plies played        {plies} ({humanMoves} human, {aiMoves} AI)");
        Console.WriteLine($"    record              {string.Join(' ', play.MoveRecord)}");
        Console.WriteLine($"    final status        {play.PrimaryStatus()} / {play.SecondaryStatus()}");
        Console.WriteLine($"    notice              {play.Notice}");
        Console.WriteLine($"    claim seen          {sawClaimable}");

        Check("the AI answered every human move", aiMoves > 0 && aiMoves >= humanMoves - 1);
        Check("the record is the core's own canonical coordinate text",
            play.MoveRecord.Count == plies && play.MoveRecord.All(IsCanonicalMove));
        Check("the record is what the core retained",
            play.MoveRecord.SequenceEqual(game.MoveHistory()));
        Check("a search ran long enough to show the thinking indicator", sawThinking);
        Check("the game reached a conclusion or the move cap", play.IsOver || plies >= cap);

        // Both languages, for the lines the screen actually composes. Nothing
        // on the board itself is copy — the coordinates are ASCII and the piece
        // characters are game content — so the panel is where the two languages
        // are visible, and this is where they are read.
        foreach (bool chinese in (bool[])[true, false])
        {
            Strings.PrefersChinese = chinese;
            Console.WriteLine($"    {(chinese ? "中文" : "en  ")}                "
                + $"{play.PrimaryStatus()} / {play.SecondaryStatus()} · "
                + $"{Strings.Get("control.undo")} · {Strings.Get("control.claimDraw")} · "
                + $"{Strings.Get("control.resign")} · {play.NoticeTitle()}");
        }

        Strings.PrefersChinese = true;

        if (play.IsOver)
        {
            Check("a finished game shows the result notice", play.Notice == ResultNotice.Result);
            play.SaveResult();
            Console.WriteLine($"    after 保存           {play.NoticeTitle()}");
            Check("保存 files the game and the notice says so", play.Notice == ResultNotice.Recorded);
            Check("a filed game can no longer be taken back", !play.CanUndo);

            // The concluding action, which has no other run: it files the
            // finished game — already filed here — and deals another with the
            // same frozen configuration, because there is no pre-start page to
            // open yet.
            string filed = play.GameId;
            GameConfiguration was = play.Configuration;
            play.NewGame();
            Console.WriteLine($"    after 开始新对局      {play.GameId}");
            Check("开始新对局 deals a different game", play.GameId != filed);
            Check("the new game starts from the initial position",
                play.MoveRecord.Count == 0 && play.Position.PlyCount == 0 && !play.IsOver);
            Check("the new game keeps the finished game's configuration",
                play.Configuration == was);
            Check("the new game is playable", play.AcceptsInput || play.Status.SearchExpected);
        }
        else
        {
            // The game is unfinished, so it is filed the way an unfinished game
            // is filed, leaving the store with no active game for the next
            // section.
            core.ArchiveAndClear(game);
            Console.WriteLine("    (unfinished at the cap; archived as ended early)");
        }

        // Release the session and leave the store with no active game, so the
        // sections below can create their own.
        play.Dispose();
        using (GameSession? standing = core.ResumeActive())
        {
            if (standing is not null)
            {
                core.ArchiveAndClear(standing);
            }
        }

        FreePlay(core, scheduler);
        Races(core, scheduler);
    }

    /// <summary>
    /// Free Play, which falls out of the same board: two humans at one screen,
    /// no AI, and the flip control the accepted orientation behaviour gives it.
    /// It has no entry point until the flows pull request builds one, so this
    /// is where it is exercised.
    /// </summary>
    private static void FreePlay(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("19. Free Play, through the same session");

        GameSession game = core.Create(
            Mxq.MXQ_PLAY_MODE_FREE_PLAY,
            Mxq.MXQ_COLOR_NONE,
            Mxq.MXQ_AI_LEVEL_NONE,
            Mxq.MXQ_FIRST_MOVER_NONE,
            0);

        using PlaySession play = new(core, game, scheduler);
        play.Begin();

        Check("Free Play offers a board-flip control", play.CanFlip);
        Check("Free Play has no controller label", play.SecondaryStatus() is null);
        Check("Free Play never owes a search", !play.Status.SearchExpected);

        Random rng = new(20260731);
        for (int ply = 0; ply < 6; ply++)
        {
            if (Choose(play, rng) is not { } move)
            {
                break;
            }

            play.Tap(move.From);
            play.Tap(move.To);
        }

        Console.WriteLine($"    record              {string.Join(' ', play.MoveRecord)}");
        Console.WriteLine($"    status              {play.PrimaryStatus()}");
        Check("both sides moved", play.MoveRecord.Count == 6);
        Check("the same person controls both sides", play.AcceptsInput);

        bool flipped = play.Scene.Flipped;
        play.FlipBoard();
        Check("the flip control changes the orientation", play.Scene.Flipped != flipped);
        Check("flipping changes presentation only",
            play.Position.SideToMove == game.Position().SideToMove
            && play.MoveRecord.Count == 6);

        uint before = play.Position.PlyCount;
        play.Undo();
        Console.WriteLine($"    after 悔棋           {play.Position.PlyCount} ply");
        Check("Free Play removes one move per Undo", play.Position.PlyCount == before - 1);

        // An illegal point: it moves nothing and it cancels nothing. The
        // question a learner is asking is where this piece may go, and taking
        // the piece out of their hand does not answer it.
        Square held = Busiest(play);
        play.Tap(held);
        int recorded = play.MoveRecord.Count;
        Square illegal = Illegal(play);
        play.Tap(illegal);
        Console.WriteLine($"    tapped {illegal.Name} holding {held.Name}");
        Check("an illegal point moves nothing", play.MoveRecord.Count == recorded);
        Check("an illegal point cancels nothing", play.Scene.Selected == held);
        play.Tap(held);
        Check("tapping the held piece again does cancel", play.Scene.Selected is null);

        core.ArchiveAndClear(game);
        play.Dispose();

        Repetition(core, scheduler);
    }

    /// <summary>
    /// The claimable threefold repetition, which is cheap to reach: two cannons
    /// step off their own file and back twice, so the starting position stands
    /// on the board for the third time. Free Play, because the claim is the same
    /// claim in both modes and this one needs no engine.
    /// </summary>
    private static void Repetition(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("20. A repetition, claimed");

        GameSession game = core.Create(
            Mxq.MXQ_PLAY_MODE_FREE_PLAY,
            Mxq.MXQ_COLOR_NONE,
            Mxq.MXQ_AI_LEVEL_NONE,
            Mxq.MXQ_FIRST_MOVER_NONE,
            0);

        using PlaySession play = new(core, game, scheduler);
        play.Begin();

        string[] shuffle = ["b1b2", "b7b6", "b2b1", "b6b7"];
        bool reached = false;
        for (int cycle = 0; cycle < 2 && !reached; cycle++)
        {
            foreach (string text in shuffle)
            {
                if (Move.Parse(text) is not { } move || !play.LegalMoves().Contains(text))
                {
                    Console.WriteLine($"    {text} is not legal here; the shuffle does not reach a repetition");
                    core.ArchiveAndClear(game);
                    Check("the repetition shuffle is playable", false);
                    return;
                }

                play.Tap(move.From);
                play.Tap(move.To);
                reached = play.CanClaimDraw;
            }
        }

        Console.WriteLine($"    record              {string.Join(' ', play.MoveRecord)}");
        Console.WriteLine($"    status              {play.PrimaryStatus()} / {play.SecondaryStatus()}");
        Check("a threefold repetition becomes claimable", play.CanClaimDraw);
        Check("the turn status carries the standing offer",
            play.SecondaryStatus()?.Contains(Strings.Get("status.drawAvailable"), StringComparison.Ordinal) == true);
        Check("the repetition does not end the game by itself", !play.IsOver);

        // The claim is the player's to invoke, and its notice never presents
        // itself unbidden.
        play.RequestClaimDraw();
        Check("判和 presents the confirmation", play.Alert == PlayAlert.ClaimDraw);
        play.ConfirmClaimDraw();

        Console.WriteLine($"    after 以和棋结束      {play.PrimaryStatus()} / {play.SecondaryStatus()} / {play.NoticeTitle()}");
        Check("the claim ends the game as a draw", play.ResultState == Mxq.MXQ_GAME_DRAW);

        // The committed outcome is not a property of the position — the board a
        // claimed draw stands on is still somebody's to move — so the screen has
        // to read it from the record rather than from the session's status.
        Check("the turn status says the result rather than whose turn it is",
            play.PrimaryStatus() == Strings.Get("status.draw"));
        Check("the reason beside it is the claim's own",
            play.ResultReason == Mxq.MXQ_END_REASON_THREEFOLD_REPETITION);
        Check("it is recorded on the way, not afterwards", play.Notice == ResultNotice.Recorded);
        Check("a claimed draw offers nothing further", !play.CanClaimDraw && !play.CanUndo);
    }

    /// <summary>
    /// The two places a confirmation and a search can arrive in either order.
    ///
    /// A system dialog does not block the dispatcher, so the AI's reply can land
    /// while the player is reading the confirmation — and an act confirmed after
    /// that lands on a game that has moved on, or on a session a terminal commit
    /// has already archived. Both are exercised here rather than reasoned about,
    /// because the first version of this screen reasoned about them and was
    /// wrong.
    /// </summary>
    private static void Races(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("21. Undo and 认输 against a search in flight");

        GameSession game = core.Create(
            Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI,
            Mxq.MXQ_COLOR_RED,
            Mxq.MXQ_AI_LEVEL_DEEP,
            Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST,
            Mxq.MXQ_MOVETIME_DEEP_MS);

        using PlaySession play = new(core, game, scheduler);
        play.Begin();

        Random rng = new(20260731);

        // 1. Undo while the AI is thinking. It cancels the search and removes
        //    the human move that triggered it, and the indicator stops with it.
        Move opening = Choose(play, rng)!.Value;
        play.Tap(opening.From);
        play.Tap(opening.To);
        Check("the human's move is expected to be answered", play.Status.SearchExpected);

        scheduler.PumpUntil(() => play.Activity == AiActivity.Thinking, TimeSpan.FromSeconds(3));
        Console.WriteLine($"    while thinking      activity {play.Activity}, ply {play.Position.PlyCount}");
        Check("the indicator appears while a 深思 search runs", play.Activity == AiActivity.Thinking);

        play.Undo();
        Console.WriteLine($"    after 悔棋           activity {play.Activity}, ply {play.Position.PlyCount}");
        Check("Undo removes the move that triggered the search", play.Position.PlyCount == 0);
        Check("Undo stops the indicator with it", play.Activity == AiActivity.Idle);
        Check("nothing is owed at the player's own decision point", !play.Status.SearchExpected);

        // The cancelled search's callback still fires. Pump for long enough to
        // receive it and confirm it decided nothing.
        scheduler.PumpUntil(() => false, TimeSpan.FromSeconds(2));
        Check("the cancelled search's answer changes nothing", play.Position.PlyCount == 0);
        Check("and starts nothing", !play.Status.SearchExpected && play.Alert == PlayAlert.None);

        // 2. 认输 confirmed with a search genuinely in flight. What must not
        //    happen is an escape: the resignation either commits, or the core
        //    refuses it because the game moved on and the refusal is absorbed.
        Move again = Choose(play, rng)!.Value;
        play.Tap(again.From);
        play.Tap(again.To);
        scheduler.PumpUntil(() => play.Activity == AiActivity.Thinking, TimeSpan.FromSeconds(3));
        Check("a search is in flight again", play.Activity == AiActivity.Thinking);

        play.RequestResign();
        Check("认输 presents the confirmation", play.Alert == PlayAlert.Resign);
        play.ConfirmResign();

        Console.WriteLine($"    after 认输           {play.PrimaryStatus()} / {play.SecondaryStatus()}");
        Console.WriteLine($"    notice              {play.Notice}, alert {play.Alert}");
        Check("认输 records the human's loss by resignation",
            play.ResultState == Mxq.MXQ_GAME_BLACK_WINS
            && play.ResultReason == Mxq.MXQ_END_REASON_RESIGNATION);
        Check("the turn status says the result rather than whose turn it is",
            play.PrimaryStatus() == Strings.Get("status.blackWins"));
        Check("the notice arrives already recorded", play.Notice == ResultNotice.Recorded);
        Check("the confirmation is gone", play.Alert == PlayAlert.None);

        // 3. The same acts again, on a session the commit has already archived.
        //    This is the shape of the answer that arrives after the situation
        //    moved on — the core refuses it, and the refusal must be absorbed
        //    where it happens rather than thrown out of a dialog's completion,
        //    which has no caller to catch it.
        play.ConfirmResign();
        play.ConfirmClaimDraw();
        play.SaveResult();
        Console.WriteLine($"    confirmed again     {play.PrimaryStatus()}, alert {play.Alert}");
        Check("confirming a filed game again is absorbed rather than thrown",
            play.ResultState == Mxq.MXQ_GAME_BLACK_WINS && play.Alert == PlayAlert.None);

        // The search that was in flight is still going to answer. It must find
        // an archived session and do nothing with it.
        uint plies = play.Position.PlyCount;
        scheduler.PumpUntil(() => false, TimeSpan.FromSeconds(8));
        Console.WriteLine($"    after the reply     ply {play.Position.PlyCount}, result {play.ResultState}");
        Check("the reply to a resigned game moves nothing", play.Position.PlyCount == plies);
        Check("and nothing is left thinking", play.Activity == AiActivity.Idle);
    }

    /// <summary>A point with no legal move to it from the piece the player holds.</summary>
    private static Square Illegal(PlaySession play)
    {
        for (int rank = 0; rank < Square.Count; rank++)
        {
            for (int file = 0; file < Square.Count; file++)
            {
                Square square = new(file, rank);
                if (!play.Scene.Destinations.Contains(square)
                    && !play.Scene.Captures.Contains(square)
                    && play.Scene.Placement[square] is null)
                {
                    return square;
                }
            }
        }

        return new Square(0, 0);
    }

    /// <summary>The mover's own piece with the most legal moves.</summary>
    private static Square Busiest(PlaySession play)
    {
        Dictionary<Square, int> counts = [];
        foreach (string text in play.LegalMoves())
        {
            if (Move.Parse(text) is { } move)
            {
                counts[move.From] = counts.GetValueOrDefault(move.From) + 1;
            }
        }

        return counts.OrderByDescending(entry => entry.Value)
            .ThenBy(entry => entry.Key.Name, StringComparer.Ordinal)
            .First()
            .Key;
    }

    /// <summary>A legal move, chosen with a fixed seed so the game is the same game every run.</summary>
    private static Move? Choose(PlaySession play, Random rng)
    {
        List<string> legal = [.. play.LegalMoves()];
        legal.Sort(StringComparer.Ordinal);
        return legal.Count == 0 ? null : Move.Parse(legal[rng.Next(legal.Count)]);
    }

    private static Square FirstMover(PlaySession play)
    {
        List<string> legal = [.. play.LegalMoves()];
        legal.Sort(StringComparer.Ordinal);
        return Move.Parse(legal[0])!.Value.From;
    }

    // ---------------------------------------------------------------------
    // The callback. Delivered on the core's engine thread — never the calling
    // thread and never a platform queue — so this is the one place the binding
    // asks the runtime to attach a thread it did not create.
    // ---------------------------------------------------------------------
    private sealed class SearchState
    {
        public readonly ManualResetEventSlim Fired = new(false);
        public MxqSearchResult Result;
        public int ManagedThreadId;
        public bool IsThreadPoolThread;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static void OnSearchComplete(MxqSearchResult* result, void* userData)
    {
        // Copy and return. Nothing else is legal here, and nothing else is
        // attempted: no core call, no blocking, no allocation the caller would
        // wait on.
        SearchState state = (SearchState)GCHandle.FromIntPtr((nint)userData).Target!;
        state.Result = *result;
        state.ManagedThreadId = Environment.CurrentManagedThreadId;
        state.IsThreadPoolThread = Thread.CurrentThread.IsThreadPoolThread;
        state.Fired.Set();
    }

    private static string Search(MiniXiangqiCore core, MxqGame* game, string gameId, ulong revision)
    {
        SearchState state = new();
        GCHandle handle = GCHandle.Alloc(state);
        try
        {
            MxqSearchRequest request = default;
            request.struct_size = (uint)sizeof(MxqSearchRequest);
            request.movetime_ms = Mxq.MXQ_MOVETIME_FAST_MS;

            ulong ticket;
            MxqError err = MxqCall.Error();
            Stopwatch clock = Stopwatch.StartNew();
            MxqCall.Check(
                Mxq.mxq_search_start(
                    core.Handle,
                    game,
                    &request,
                    &OnSearchComplete,
                    (void*)GCHandle.ToIntPtr(handle),
                    &ticket,
                    &err),
                in err,
                nameof(Mxq.mxq_search_start));
            Console.WriteLine($"    ticket              {ticket}");
            Console.WriteLine($"    calling thread      {Environment.CurrentManagedThreadId}");

            // Both consumers, because the contract says they are equivalent:
            // the callback, and the ticket the caller waits on.
            MxqSearchResult waited = default;
            waited.struct_size = (uint)sizeof(MxqSearchResult);
            byte ready;
            err = MxqCall.Error();
            MxqCall.Check(
                Mxq.mxq_search_wait(core.Handle, ticket, 30_000, &waited, &ready, &err),
                in err,
                nameof(Mxq.mxq_search_wait));
            clock.Stop();

            bool fired = state.Fired.Wait(TimeSpan.FromSeconds(5));
            MxqSearchResult delivered = state.Result;
            string move = Utf8.Read(delivered.move.text);
            string profile = Utf8.Read(delivered.profile_id);
            string deliveredGameId = Utf8.Read(delivered.game_id);

            Console.WriteLine($"    callback fired      {fired}");
            Console.WriteLine($"    callback thread     {state.ManagedThreadId} (thread pool: {state.IsThreadPoolThread})");
            Console.WriteLine($"    outcome             {OutcomeName(delivered.outcome)}");
            Console.WriteLine($"    move                {move}");
            Console.WriteLine($"    depth / nodes       {delivered.depth} / {delivered.nodes}");
            Console.WriteLine($"    score (cp)          {delivered.score_cp}");
            Console.WriteLine($"    elapsed (core)      {delivered.elapsed_ms} ms");
            Console.WriteLine($"    elapsed (wall)      {clock.ElapsedMilliseconds} ms");
            Console.WriteLine($"    profile             {profile}");
            Console.WriteLine($"    game id             {deliveredGameId}");

            Check("the callback was delivered", fired);
            Check("the callback ran on a thread the caller was not on",
                state.ManagedThreadId != Environment.CurrentManagedThreadId);
            Check("the callback ran on a thread the runtime did not own",
                !state.IsThreadPoolThread);
            Check("the wait consumer also saw the result", ready == 1);
            Check("both consumers report the same outcome and move",
                waited.outcome == delivered.outcome && Utf8.Read(waited.move.text) == move);
            Check("the search produced a move", delivered.outcome == Mxq.MXQ_SEARCH_MOVE);
            Check("the result is not stale", delivered.position_revision == revision);
            Check("the result names this game", deliveredGameId == gameId);
            Check("the result carries a profile identifier", profile.Length > 0);
            Check("the move is canonical <from><to>", IsCanonicalMove(move));

            return move;
        }
        finally
        {
            handle.Free();
        }
    }

    // ---------------------------------------------------------------------
    // Helpers.
    // ---------------------------------------------------------------------
    private static void ExpectRefusal(MxqGame* game, string move, int expected)
    {
        MxqError err = MxqCall.Error();
        byte[] encoded = Utf8.Encode(move);
        int status;
        fixed (byte* text = encoded)
        {
            status = Mxq.mxq_game_apply_move(game, (sbyte*)text, null, null, &err);
        }

        MxqError copy = err;
        Console.WriteLine($"    \"{move}\" -> {MxqCall.StatusName(status)} (domain {Mxq.mxq_status_domain(status)})");
        Console.WriteLine($"      detail            {Utf8.Read(copy.detail)}");
        Check($"\"{move}\" is refused as {MxqCall.StatusName(expected)}", status == expected);
        Check($"\"{move}\" refusal is rules-domain", Mxq.mxq_status_domain(status) == Mxq.MXQ_DOMAIN_RULES);
        Check($"\"{move}\" refusal carries a diagnostic", Utf8.Read(copy.detail).Length > 0);
        Check($"\"{move}\" refusal echoes its own status in MxqError", copy.status == status);
    }

    private static MxqPosition ReadPosition(MxqGame* game)
    {
        MxqPosition position = default;
        position.struct_size = (uint)sizeof(MxqPosition);
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_game_position(game, &position, &err), in err, nameof(Mxq.mxq_game_position));
        return position;
    }

    private static MxqGameStatus ReadStatus(MxqGame* game)
    {
        MxqGameStatus status = default;
        status.struct_size = (uint)sizeof(MxqGameStatus);
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_game_status(game, &status, &err), in err, nameof(Mxq.mxq_game_status));
        return status;
    }

    private static string StagedNetworkSha(string assets)
    {
        string[] networks = Directory.Exists(assets)
            ? Directory.GetFiles(assets, "*.nnue")
            : [];
        if (networks.Length != 1)
        {
            return $"<{networks.Length} networks in {assets}>";
        }

        using FileStream file = File.OpenRead(networks[0]);
        return Convert.ToHexStringLower(SHA256.HashData(file));
    }

    private static bool IsCanonicalMove(string move) =>
        move.Length == 4
        && move[0] is >= 'a' and <= 'g'
        && move[1] is >= '1' and <= '7'
        && move[2] is >= 'a' and <= 'g'
        && move[3] is >= '1' and <= '7';

    private static bool IsHex(string value, int length) =>
        value.Length == length && value.All(c => c is (>= '0' and <= '9') or (>= 'a' and <= 'f'));

    private static string ColorName(int color) => color switch
    {
        Mxq.MXQ_COLOR_RED => "red",
        Mxq.MXQ_COLOR_BLACK => "black",
        _ => "none",
    };

    private static string OutcomeName(int outcome) => outcome switch
    {
        Mxq.MXQ_SEARCH_MOVE => "MXQ_SEARCH_MOVE",
        Mxq.MXQ_SEARCH_CANCELLED => "MXQ_SEARCH_CANCELLED",
        Mxq.MXQ_SEARCH_STALE => "MXQ_SEARCH_STALE",
        Mxq.MXQ_SEARCH_MALFORMED => "MXQ_SEARCH_MALFORMED",
        Mxq.MXQ_SEARCH_ILLEGAL => "MXQ_SEARCH_ILLEGAL",
        Mxq.MXQ_SEARCH_FAILED => "MXQ_SEARCH_FAILED",
        _ => outcome.ToString(CultureInfo.InvariantCulture),
    };

    private static string Mib(ulong bytes) =>
        (bytes / (1024.0 * 1024.0)).ToString("N0", CultureInfo.InvariantCulture) + " MiB";

    private static string? Argument(string[] args, string name)
    {
        int index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }

    private static void Section(string title)
    {
        Console.WriteLine();
        Console.WriteLine(title);
        Console.WriteLine(new string('-', title.Length));
    }

    private static void Check(string what, bool passed)
    {
        _checks++;
        if (!passed)
        {
            _failures++;
        }

        Console.WriteLine($"    [{(passed ? "ok" : "FAIL")}] {what}");
    }
}
