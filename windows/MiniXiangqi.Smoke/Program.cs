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
// Sections 17 to 28 are the Play destination's and 29 to 33 the History
// destination's. A WinUI 3 process cannot be launched from an SSH session, so
// the Windows frontend's behaviour would otherwise be runnable on no machine
// this project owns. Its logic lives in MiniXiangqi.Play with no window attached
// to it — PlayFlow, PlaySession, HistoryFlow and ReplayViewer — and this drives
// all of it: every move committed by clicking a point and then another point,
// the AI answering through the same marshalled callback the window uses, every
// page reached the way a person reaches it, a filed game exported to a real file
// and imported back from it, and the strings shown along the way checked against
// docs/copy.md.
//
// Two things in this frontend a headless process cannot reach, and both are
// named where they happen rather than implied: the two file pickers, which need
// the window's own handle — so the harness names a file where the window would
// have picked one — and the store refusals that no honest seam produces.

using System.Diagnostics;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
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
            TheFlows(store, assets);
            // Each of these opens its own core, and the core is singleton-enforced
            // — a second mxq_core_init before shutdown is
            // MXQ_ERR_STATE_ALREADY_INITIALIZED — so they are sequential rather
            // than nested. The two with their own store directory want a library
            // of a known size, which is what the shared one cannot be by the time
            // they run.
            TheHistoryDestination(store, assets);
            ThePagedLibrary(assets);
            TheSettingsDestination(assets);

            // Arithmetic and one string, so it needs no core and opens none.
            TheBoardsSpace();
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
        Check("the board starts with the human's own side at the bottom", !play.Scene.Flipped);
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

        // The reported Windows defect — selecting a piece appeared to need a
        // double click — was a point's tap reaching the board's background
        // handler behind its own Click, so a cancel arrived behind the selection
        // the same click had made. Its fix is in BoardView, where the pointer
        // routing lives, and **nothing here can run it**: a WinUI 3 window
        // cannot be launched without an interactive desktop, and the two calls
        // this file could make are already checked above as the separate acts
        // they are. Restating them as a pair would be a check about this file
        // rather than about the defect. The owner's re-test is the evidence.

        // 翻转棋盘, in human-versus-AI (owner recommendation, 2026-07-31;
        // docs/interaction-design.md § Play controls and § Board orientation).
        // What is checked is that it is presentation and nothing else — the same
        // claim Free Play's own flip is checked for in section 19, made here
        // where the machine is also holding an opinion about the position.
        bool uprightBeforeTheFlip = play.Scene.Flipped;
        uint plyAtTheFlip = play.Position.PlyCount;
        int recordAtTheFlip = play.MoveRecord.Count;
        int sideAtTheFlip = play.Position.SideToMove;
        bool acceptedInputAtTheFlip = play.AcceptsInput;

        play.FlipBoard();
        Console.WriteLine($"    after 翻转棋盘       Black at the bottom: {play.Scene.Flipped}");
        Check("human-versus-AI offers 翻转棋盘 too",
            play.Scene.Flipped != uprightBeforeTheFlip);
        Check("flipping changes presentation only",
            play.Position.SideToMove == sideAtTheFlip
            && play.Position.SideToMove == game.Position().SideToMove
            && play.Position.PlyCount == plyAtTheFlip
            && play.MoveRecord.Count == recordAtTheFlip
            && play.AcceptsInput == acceptedInputAtTheFlip);

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
        Check("the orientation survived every move and every reply the AI made",
            play.Scene.Flipped != uprightBeforeTheFlip);

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
                + $"{Strings.Get("control.resign")} · {Strings.Get("control.flipBoard")} · "
                + $"{play.NoticeTitle()}");
        }

        Strings.PrefersChinese = true;

        if (play.IsOver)
        {
            Check("a finished game shows the result notice", play.Notice == ResultNotice.Result);
            play.SaveResult();
            Console.WriteLine($"    after 保存           {play.NoticeTitle()}");
            Check("保存 files the game and the notice says so", play.Notice == ResultNotice.Recorded);
            Check("a filed game can no longer be taken back", !play.CanUndo);

            // A game already filed is never filed again. What the concluding
            // actions do *after* the filing is the destination's rather than
            // this screen's, and section 25 is where it is run: 开始新对局 opens
            // that game's own mode's pre-start state, and 完成 returns to the
            // Play home.
            Check("filing a filed game files nothing further", play.FileIfNeeded());
            Check("and the record is still the one it made", play.Notice == ResultNotice.Recorded);
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

        Check("Free Play starts with Red at the bottom", !play.Scene.Flipped);
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

    // ---------------------------------------------------------------------
    // 22-27. The Play destination's flows: the home, the two pre-start states,
    //        and every path between them.
    //
    // Same reason as the sections above — a WinUI 3 process cannot be launched
    // over SSH — and the same shape: PlayFlow has no window, so a game is
    // created here exactly as 开始对局 creates one, a mode is chosen exactly as
    // a row on the home chooses one, and the confirmations are answered exactly
    // as their dialogs answer them.
    // ---------------------------------------------------------------------
    private static void TheFlows(string store, string assets)
    {
        using MiniXiangqiCore core = MiniXiangqiCore.Start(store, assets);
        PumpScheduler scheduler = new();

        // One game is active at a time, so anything the sections above left
        // standing is filed first.
        using (GameSession? standing = core.ResumeActive())
        {
            if (standing is not null)
            {
                core.ArchiveAndClear(standing);
            }
        }

        TheDefaults();
        HomeToSetupToBoard(core, scheduler);
        SaveAndContinue(core, scheduler);
        TheConcludingActions(core, scheduler);
        NoMemoryForTheAi(core, scheduler);
        TheCreationTheStoreRefused(core, scheduler);
    }

    /// <summary>
    /// 22. The two Settings defaults the pre-start controls are initialized
    ///     from, read from the keys the Apple frontend stores them under.
    ///
    /// This is the reading half and its fallbacks. The writing half is section
    /// 36, where the Settings screen writes these same two keys and this same
    /// draft opens on what it wrote — the two sections are the two ends of one
    /// circle, and they are apart because a fallback is a claim about a reader
    /// and needs no writer to make it.
    /// </summary>
    private static void TheDefaults()
    {
        Section("22. The Settings defaults, and the draft they initialize");

        SetupDraft fresh = SetupDraft.FromDefaults(NoPreferences.Instance);
        Console.WriteLine($"    nothing stored      {fresh.FirstMover} / {fresh.Level}");
        Check("a new installation is 我先手 and 标准",
            fresh is { FirstMover: FirstMoverChoice.HumanFirst, Level: AiLevel.Standard });

        StubPreferences stored = new()
        {
            ["defaults.firstMover"] = "ai-first",
            ["defaults.aiLevel"] = "deep",
        };
        SetupDraft chosen = SetupDraft.FromDefaults(stored);
        Console.WriteLine($"    ai-first / deep     {chosen.FirstMover} / {chosen.Level}");
        Check("a stored preference is what the draft opens on",
            chosen is { FirstMover: FirstMoverChoice.AiFirst, Level: AiLevel.Deep });
        Check("AI 先手 previews the human as Black", chosen.PreviewsHumanAsBlack);
        Check("AI 先手 resolves to Black", chosen.ResolveHumanSide() == Side.Black);

        StubPreferences nonsense = new()
        {
            ["defaults.firstMover"] = "whoever-feels-like-it",
            ["defaults.aiLevel"] = "42",
        };
        SetupDraft fallback = SetupDraft.FromDefaults(nonsense);
        Console.WriteLine($"    unrecognised        {fallback.FirstMover} / {fallback.Level}");
        Check("a name nothing recognises reads as the accepted default",
            fallback is { FirstMover: FirstMoverChoice.HumanFirst, Level: AiLevel.Standard });

        // 随机 remains unresolved and previews Red at the bottom; only a
        // successful creation can flip the board.
        SetupDraft random = new(FirstMoverChoice.Random, AiLevel.Fast);
        Check("随机 previews Red at the bottom", !random.PreviewsHumanAsBlack);

        // That it draws *both* sides is the claim worth making — a resolution
        // that always answered Red would satisfy every type in the program and
        // silently give the player one side forever.
        HashSet<Side> drawn = [];
        for (int draw = 0; draw < 200; draw++)
        {
            drawn.Add(random.ResolveHumanSide());
        }

        Check("随机 draws both sides", drawn.Count == 2);

        // The product path: the JSON file every pre-start entry actually reads.
        // The three stores above are stand-ins for a reader; this is the reader.
        TheStoredFile();

        Console.WriteLine(
            $"    movetimes           {AiLevel.Fast.MovetimeMs()} / "
            + $"{AiLevel.Standard.MovetimeMs()} / {AiLevel.Deep.MovetimeMs()} ms");
        Check("each level carries the core's own movetime",
            AiLevel.Fast.MovetimeMs() == Mxq.MXQ_MOVETIME_FAST_MS
            && AiLevel.Standard.MovetimeMs() == Mxq.MXQ_MOVETIME_STANDARD_MS
            && AiLevel.Deep.MovetimeMs() == Mxq.MXQ_MOVETIME_DEEP_MS);
        Check("the serialized names are the archive's vocabulary",
            FirstMoverChoice.Random.Name() == "random" && AiLevel.Deep.Name() == "deep");
    }

    /// <summary>
    /// The preferences file itself: <c>FilePreferenceStore</c> over a real file
    /// on disk, which is what every entry to a pre-start page reads through.
    ///
    /// The stores above are stand-ins for a reader and prove the fallbacks; this
    /// proves the reader. Every claim windows/README.md makes about it is one
    /// line here — a stored name is read, an absent file is nothing stored, a
    /// malformed one is nothing stored, and a value of the wrong kind is not a
    /// value. The last three matter because a preferences file is editable by
    /// hand and read by more than one frontend, and the page still has to open.
    /// </summary>
    private static void TheStoredFile()
    {
        string directory = Path.Combine(
            Path.GetTempPath(), "mxq-prefs-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        string path = Path.Combine(directory, "preferences.json");
        FilePreferenceStore store = new(path);

        try
        {
            Console.WriteLine($"    preferences file    {path}");

            Check("an absent file is nothing stored",
                store.Read(Preferences.DefaultFirstMoverKey) is null
                && Preferences.DefaultFirstMover(store) == FirstMoverChoice.HumanFirst
                && Preferences.DefaultAiLevel(store) == AiLevel.Standard);

            File.WriteAllText(
                path,
                """{"defaults.firstMover":"random","defaults.aiLevel":"fast"}""");
            SetupDraft stored = SetupDraft.FromDefaults(store);
            Console.WriteLine($"    stored              {stored.FirstMover} / {stored.Level}");
            Check("a stored file is what the draft opens on",
                stored is { FirstMover: FirstMoverChoice.Random, Level: AiLevel.Fast });

            File.WriteAllText(path, "{ this is not json");
            Check("a malformed file is nothing stored",
                store.Read(Preferences.DefaultFirstMoverKey) is null
                && Preferences.DefaultFirstMover(store) == FirstMoverChoice.HumanFirst);

            // A key holding something that is not a string is not a preference
            // this reader has: a number, an object and an array all read as
            // absent rather than as text somebody could coerce them into.
            File.WriteAllText(
                path,
                """{"defaults.firstMover":2,"defaults.aiLevel":{"level":"deep"},"other":[1]}""");
            Check("a value of the wrong kind is not a value",
                store.Read(Preferences.DefaultFirstMoverKey) is null
                && store.Read(Preferences.DefaultAiLevelKey) is null
                && Preferences.DefaultAiLevel(store) == AiLevel.Standard);

            // A file that is fine but holds nothing this build knows.
            File.WriteAllText(path, """{"defaults.aiLevel":"glacial"}""");
            Check("a name nothing recognises in a real file reads as the default",
                Preferences.DefaultAiLevel(store) == AiLevel.Standard);
        }
        finally
        {
            try
            {
                Directory.Delete(directory, recursive: true);
            }
            catch (IOException)
            {
                // A scratch directory; failing to remove it is not a result.
            }
        }
    }

    /// <summary>
    /// 23. The entry path: the home, a mode entry, the pre-start state, and
    ///     开始对局.
    /// </summary>
    private static void HomeToSetupToBoard(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("23. Home → 人机对弈 pre-start → 开始对局 → the board");

        using PlayFlow flow = new(core, scheduler, NoPreferences.Instance);
        flow.Start();

        Console.WriteLine($"    at launch           {flow.Page}");
        Check("a launch with nothing to resume opens on the home", flow.Page == PlayPage.Home);
        Check("and creates nothing", flow.Session is null && flow.ActiveGame is null);
        Check("so the home has no current game to describe", flow.ActiveGameLine is null);

        flow.Choose(PlayMode.HumanVersusAi);
        Console.WriteLine($"    after 人机对弈       {flow.Page} / {flow.SetupMode}");
        Check("choosing a mode opens that mode's pre-start state",
            flow is { Page: PlayPage.Setup, SetupMode: PlayMode.HumanVersusAi });
        Check("the pre-start state is not an active game", flow.Session is null);
        Check("the draft is the Settings defaults",
            flow.Draft is { FirstMover: FirstMoverChoice.HumanFirst, Level: AiLevel.Standard });
        Placement frozen = new(MiniXiangqiCore.StartFen);
        bool previewsTheStart = true;
        for (int rank = 0; rank < Square.Count && previewsTheStart; rank++)
        {
            for (int file = 0; file < Square.Count && previewsTheStart; file++)
            {
                Square point = new(file, rank);
                previewsTheStart = flow.PreviewScene.Placement[point] == frozen[point];
            }
        }

        Check("the preview is the frozen initial position", previewsTheStart);
        Check("and it shows Red at the bottom", !flow.PreviewScene.Flipped);

        flow.ChooseFirstMover(FirstMoverChoice.AiFirst);
        Check("AI 先手 flips the preview", flow.PreviewScene.Flipped);
        flow.ChooseFirstMover(FirstMoverChoice.Random);
        Check("随机 previews Red until it is resolved", !flow.PreviewScene.Flipped);

        // The back control, and what leaving a pre-start page discards.
        flow.ChooseLevel(AiLevel.Deep);
        flow.LeaveTopPage();
        Check("the back control returns to the home", flow.Page == PlayPage.Home);
        Check("and no game was created", flow.Session is null);
        flow.Choose(PlayMode.HumanVersusAi);
        Console.WriteLine($"    re-entered          {flow.Draft.FirstMover} / {flow.Draft.Level}");
        Check("the draft is discarded on leaving and afresh on entry",
            flow.Draft is { FirstMover: FirstMoverChoice.HumanFirst, Level: AiLevel.Standard });

        // An attempt the player walks out of commits nothing, even though the
        // preparation it started will succeed.
        flow.StartGame();
        Check("开始对局 cannot be invoked again while creation is in progress", flow.Creating);
        flow.StartGame();
        Check("and a second press changes nothing", flow.Page == PlayPage.Setup);
        flow.LeaveTopPage();
        scheduler.PumpUntil(() => false, TimeSpan.FromSeconds(3));
        Console.WriteLine($"    left mid-attempt    {flow.Page}, session {flow.Session is not null}");
        Check("leaving invalidates the attempt and creates no game",
            flow is { Page: PlayPage.Home, Session: null, Creating: false });

        // And the real thing: 我先手 at 快速, so the human moves first and the
        // section below has a game to leave standing.
        flow.Choose(PlayMode.HumanVersusAi);
        flow.ChooseLevel(AiLevel.Fast);
        flow.StartGame();
        bool opened = scheduler.PumpUntil(
            () => flow.Page == PlayPage.Board || flow.Alert != FlowAlert.None,
            TimeSpan.FromSeconds(30));

        Console.WriteLine($"    after 开始对局       {flow.Page}, alert {flow.Alert}");
        Check("开始对局 creates the game and opens the board",
            opened && flow is { Page: PlayPage.Board, Alert: FlowAlert.None });
        Check("and the game is now the active one", flow.ActiveGame is not null);

        if (flow.Session is not { } play)
        {
            Check("the board has a session", false);
            return;
        }

        Console.WriteLine($"    configuration       mode {play.Configuration.Mode}, "
            + $"human {play.Configuration.HumanSide}, level {play.Configuration.AiLevel}, "
            + $"movetime {play.Configuration.MovetimeMs} ms");
        Check("the created game froze the draft",
            play.Configuration.Mode == Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI
            && play.Configuration.HumanSide == Mxq.MXQ_COLOR_RED
            && play.Configuration.AiLevel == Mxq.MXQ_AI_LEVEL_FAST
            && play.Configuration.FirstMoverChoice == Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST
            && play.Configuration.MovetimeMs == Mxq.MXQ_MOVETIME_FAST_MS);
        Check("the human's own side is at the bottom", !play.Scene.Flipped);
        Check("the board is playable", play.AcceptsInput);

        // One move, so the game the next section files has something in it.
        if (Choose(play, new Random(20260731)) is { } move)
        {
            play.Tap(move.From);
            play.Tap(move.To);
        }

        // Leaving the board for the home ends nothing.
        flow.LeaveTopPage();
        Console.WriteLine($"    left the board      {flow.Page}, active {flow.ActiveGame is not null}");
        Check("leaving the board for the home ends nothing",
            flow is { Page: PlayPage.Home } && flow.ActiveGame is not null);
        Console.WriteLine($"    当前对局             {flow.ActiveGameLine}");
        Check("the home's card describes the game the core is holding",
            flow.ActiveGameLine is { Length: > 0 } line
            && line.Contains(Strings.Get("mode.humanVersusAI"), StringComparison.Ordinal)
            && line.Contains(Strings.Get("metadata.youRed"), StringComparison.Ordinal)
            && line.Contains(Strings.Get("metadata.inProgress"), StringComparison.Ordinal));

        // 步 is invariant and *move* is not, and a one-ply line is exactly the
        // case the plural pattern exists for — the one this frontend selects
        // itself, because it has no String Catalog to select for it.
        foreach (bool chinese in (bool[])[true, false])
        {
            Strings.PrefersChinese = chinese;
            Console.WriteLine($"    {(chinese ? "中文" : "en  ")}                {flow.ActiveGameLine}");
        }

        Strings.PrefersChinese = false;
        Check("one ply takes the English singular",
            flow.ActiveGameLine?.EndsWith("1 move", StringComparison.Ordinal) == true);
        Strings.PrefersChinese = true;
        Check("and 步 is invariant beside it",
            flow.ActiveGameLine?.EndsWith("1 步", StringComparison.Ordinal) == true);

        flow.Resume();
        Check("回到对局 opens the board on the game exactly as it was left",
            flow.Page == PlayPage.Board && flow.Session?.MoveRecord.Count == 1);
    }

    /// <summary>
    /// 24. The one save-and-continue confirmation, for every combination of old
    ///     mode, new mode and active-game state.
    /// </summary>
    private static void SaveAndContinue(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("24. 开始新对局？ — saving the active game before choosing a new mode");

        using PlayFlow flow = new(core, scheduler, NoPreferences.Instance);
        flow.Start();

        Console.WriteLine($"    at launch           {flow.Page}");
        Check("a launch with a game to resume opens at the board, not at the home",
            flow.Page == PlayPage.Board);
        Check("the resumed game is the one the last section left", flow.ActiveGame is not null);

        uint before = HistoryCount(core);

        flow.LeaveTopPage();
        flow.Choose(PlayMode.FreePlay);
        Console.WriteLine($"    after 自由对弈       page {flow.Page}, alert {flow.Alert}");
        Check("a mode entry with an active game presents the confirmation",
            flow.Alert == FlowAlert.NewGame);
        Check("and opens nothing", flow.Page == PlayPage.Home);

        flow.DismissAlert();
        Check("取消 leaves the active game completely unchanged",
            flow is { Alert: FlowAlert.None, Page: PlayPage.Home } && flow.ActiveGame is not null);

        flow.Choose(PlayMode.FreePlay);
        flow.SaveAndContinue();
        bool archived = scheduler.PumpUntil(
            () => flow.Page == PlayPage.Setup || flow.Alert == FlowAlert.ArchiveFailed,
            TimeSpan.FromSeconds(10));

        uint after = HistoryCount(core);
        Console.WriteLine($"    after 保存并继续      page {flow.Page} / {flow.SetupMode}, "
            + $"history {before} → {after}");
        Check("保存并继续 archives the active game and opens the selected mode's pre-start state",
            archived && flow is { Page: PlayPage.Setup, SetupMode: PlayMode.FreePlay });
        Check("the game went to History", after == before + 1);
        Check("and it created no new game", flow.Session is null && flow.ActiveGame is null);

        MxqRecordSummary filed = LatestRecord(core);
        Console.WriteLine($"    filed as            outcome {filed.outcome}, "
            + $"reason {filed.end_reason}, {filed.move_count} ply");
        Check("an ordinary ongoing game is archived as ended early without a result",
            filed.outcome == Mxq.MXQ_OUTCOME_NONE
            && filed.end_reason == Mxq.MXQ_END_REASON_ENDED_EARLY);

        // The Free Play pre-start state: the same preview, no 本局设置 group,
        // and the line that says what Free Play is.
        Check("Free Play previews Red at the bottom", !flow.PreviewScene.Flipped);
        Console.WriteLine($"    explanation         {Strings.Get("setup.freePlayExplanation")}");

        flow.StartGame();
        bool started = scheduler.PumpUntil(
            () => flow.Page == PlayPage.Board || flow.Alert != FlowAlert.None,
            TimeSpan.FromSeconds(10));
        Console.WriteLine($"    after 开始对局       {flow.Page}, alert {flow.Alert}");
        Check("开始对局 commits the active Free Play game", started && flow.Page == PlayPage.Board);

        if (flow.Session is { } play)
        {
            Check("Free Play starts with Red at the bottom and cannot resign",
                !play.Scene.Flipped && !play.CanResign);
            Check("the board is interactive and Red is to move",
                play.AcceptsInput && play.SideToMove == Side.Red);
            Console.WriteLine($"    当前对局             {flow.ActiveGameLine}");
            Check("Free Play's card carries no 执子 token",
                flow.ActiveGameLine is { } line
                && !line.Contains(Strings.Get("metadata.youRed"), StringComparison.Ordinal)
                && !line.Contains(Strings.Get("metadata.youBlack"), StringComparison.Ordinal));

            // The plural's other side, at both ends of the one-ply case: none
            // played, and two played.
            Strings.PrefersChinese = false;
            Check("no plies takes the English plural",
                flow.ActiveGameLine?.EndsWith("0 moves", StringComparison.Ordinal) == true);

            Random rng = new(20260731);
            for (int ply = 0; ply < 2; ply++)
            {
                if (Choose(play, rng) is { } step)
                {
                    play.Tap(step.From);
                    play.Tap(step.To);
                }
            }

            Console.WriteLine($"    two plies           {flow.ActiveGameLine}");
            Check("two plies takes it too",
                flow.ActiveGameLine?.EndsWith("2 moves", StringComparison.Ordinal) == true);
            Strings.PrefersChinese = true;
        }

        // Leave the store with no active game, so the next section starts from
        // nothing.
        Retire(flow, scheduler);
    }

    /// <summary>
    /// 25. Where the concluding actions go: 开始新对局 opens that game's own
    ///     mode's pre-start state, and 完成 returns to the Play home.
    /// </summary>
    private static void TheConcludingActions(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("25. 开始新对局 and 完成, from a finished game");

        using PlayFlow flow = new(core, scheduler, NoPreferences.Instance);
        flow.Start();
        Check("the home is where a launch with nothing to resume opens",
            flow is { Page: PlayPage.Home, Session: null });

        flow.Choose(PlayMode.HumanVersusAi);
        flow.ChooseLevel(AiLevel.Fast);
        flow.StartGame();
        scheduler.PumpUntil(() => flow.Page == PlayPage.Board, TimeSpan.FromSeconds(30));
        if (flow.Session is not { } play)
        {
            Check("a game was created to conclude", false);
            return;
        }

        // Turned over before it is concluded, so that the next game can be asked
        // whether it inherited the orientation. It must not: 翻转棋盘 is the
        // board's presentation of *this* game, a game is a session, and the
        // contract has each mode starting the board its own way up.
        play.FlipBoard();
        Check("翻转棋盘 turns this game's board over", play.Scene.Flipped);

        // 认输 is the cheapest finish there is, and it files on the way.
        play.RequestResign();
        play.ConfirmResign();
        Console.WriteLine($"    after 认输           {play.PrimaryStatus()}, notice {play.Notice}");
        Check("认输 files the game and the notice arrives recorded",
            play.IsFiled && play.Notice == ResultNotice.Recorded);
        Check("a filed game is not an active game", flow.ActiveGame is null);

        // 开始新对局 files the game and opens that game's own mode's pre-start
        // state. It does not deal the next game.
        flow.StartNewGame();
        Console.WriteLine($"    after 开始新对局      {flow.Page} / {flow.SetupMode}, "
            + $"session {flow.Session is not null}");
        Check("开始新对局 opens the finished game's own mode's pre-start state",
            flow is { Page: PlayPage.Setup, SetupMode: PlayMode.HumanVersusAi });
        Check("and deals no game", flow.Session is null && flow.ActiveGame is null);
        Check("the side and the level are chosen again rather than inherited",
            flow.Draft is { FirstMover: FirstMoverChoice.HumanFirst, Level: AiLevel.Standard });

        // And 完成, from a game filed the other way: 保存 on the notice.
        flow.ChooseLevel(AiLevel.Fast);
        flow.StartGame();
        scheduler.PumpUntil(() => flow.Page == PlayPage.Board, TimeSpan.FromSeconds(30));
        if (flow.Session is not { } second)
        {
            Check("a second game was created", false);
            return;
        }

        Check("a new game starts the right way up rather than inheriting the flip",
            !second.Scene.Flipped);

        second.RequestResign();
        second.ConfirmResign();
        flow.Finish();
        Console.WriteLine($"    after 完成           {flow.Page}, session {flow.Session is not null}");
        Check("完成 returns to the Play home", flow.Page == PlayPage.Home);
        Check("and lets the filed game go", flow.Session is null && flow.ActiveGameLine is null);

        // A game already filed is never filed again: the two conclusions above
        // committed one record each and no more.
        uint records = HistoryCount(core);
        Console.WriteLine($"    history             {records} record(s)");
        Check("the two finishes filed one record each", records >= 2);
    }

    /// <summary>
    /// 26 and 27. 无法启动 AI 对手, in both of its forms.
    ///
    /// The probe is the seam. docs/engine-integration.md fixes the arithmetic in
    /// the core and the probe in the frontend, so handing the frontend a probe
    /// that reports a starved machine reaches the accepted refusal through the
    /// core's own budget calculation rather than around it — which is the only
    /// way this path runs at all on a machine with memory to spare.
    /// </summary>
    private static void NoMemoryForTheAi(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("26. 无法启动 AI 对手 at 开始对局");

        bool starved = true;
        using PlayFlow flow = new(
            core, scheduler, NoPreferences.Instance,
            () => starved ? Starved() : WindowsMemoryProbe.Current());
        flow.Start();

        EnginePlan refused = MiniXiangqiCore.PlanFor(Starved());
        Console.WriteLine($"    starved plan        {refused.HashMib} MiB, sufficient {refused.Sufficient}");
        Check("the starved probe is below the accepted minimum", !refused.Sufficient);

        flow.Choose(PlayMode.HumanVersusAi);
        flow.ChooseLevel(AiLevel.Fast);
        flow.StartGame();
        bool refusedGame = scheduler.PumpUntil(
            () => flow.Alert != FlowAlert.None, TimeSpan.FromSeconds(30));

        Console.WriteLine($"    after 开始对局       alert {flow.Alert}, page {flow.Page}");
        Check("insufficient memory is the accepted 无法启动 AI 对手 notice",
            refusedGame && flow.Alert == FlowAlert.AiUnavailable);
        Check("a preparation failure creates nothing", flow.Session is null);
        Check("the page and the draft remain, and 开始对局 is enabled again",
            flow is { Page: PlayPage.Setup, Creating: false, Draft.Level: AiLevel.Fast });

        Console.WriteLine($"    message             {Strings.Get("alert.aiUnavailable.message")}");
        Check("the pre-start message promises nothing about a saved game",
            !Strings.Get("alert.aiUnavailable.message").Contains("对局已保存", StringComparison.Ordinal));

        flow.DismissAlert();
        Check("取消 dismisses without leaving the page",
            flow is { Alert: FlowAlert.None, Page: PlayPage.Setup, Draft.Level: AiLevel.Fast });

        // 重试 obtains a fresh value from the platform memory probe and
        // recalculates the budget; the prior value is not cached.
        starved = false;
        flow.StartGame();
        bool created = scheduler.PumpUntil(
            () => flow.Page == PlayPage.Board || flow.Alert != FlowAlert.None,
            TimeSpan.FromSeconds(30));
        Console.WriteLine($"    after 重试           {flow.Page}, alert {flow.Alert}");
        Check("a retry re-probes and the game is created", created && flow.Page == PlayPage.Board);

        Section("27. 无法启动 AI 对手 mid-game, and the stalled slot behind it");

        if (flow.Session is not { } play)
        {
            Check("there is a game to stall", false);
            return;
        }

        // The engine is ready from the creation above, so a search would never
        // reach a probe. Releasing it is what puts the game back in the state a
        // suspension leaves it in: saved, owing a search, with no engine.
        core.TeardownEngine();
        starved = true;

        if (Choose(play, new Random(20260731)) is not { } move)
        {
            Check("there is a move to make", false);
            return;
        }

        play.Tap(move.From);
        play.Tap(move.To);
        bool stalled = scheduler.PumpUntil(
            () => play.Alert != PlayAlert.None, TimeSpan.FromSeconds(30));

        Console.WriteLine($"    owing a search      alert {play.Alert}, ply {play.Position.PlyCount}");
        Check("a mid-game preparation failure is the same notice under the same title",
            stalled && play.Alert == PlayAlert.EngineMemory);
        Check("the game is saved and unchanged", play.Position.PlyCount == 1 && !play.IsFiled);
        Check("the mid-game message adds the saved-game guarantee",
            Strings.Get("alert.aiUnavailable.resumeMessage")
                .Contains("对局已保存", StringComparison.Ordinal));

        play.DeferEngine();
        Console.WriteLine($"    after 稍后           activity {play.Activity}, alert {play.Alert}");
        Check("稍后 moves the stalled state to the turn status's own slot",
            play is { Alert: PlayAlert.None, Activity: AiActivity.Stalled });
        Check("and Undo remains available, which is itself a way out", play.CanUndo);
        Console.WriteLine($"    the slot says       {Strings.Get("status.aiUnavailable")} · "
            + Strings.Get("control.tryAgain"));

        starved = false;
        play.RetryEngine();
        bool answered = scheduler.PumpUntil(
            () => play.MoveRecord.Count > 1 || play.Alert != PlayAlert.None,
            TimeSpan.FromSeconds(30));
        Console.WriteLine($"    after 重试           activity {play.Activity}, "
            + $"record {string.Join(' ', play.MoveRecord)}");
        Check("every retry re-probes fresh, and this one lets the AI answer",
            answered && play.MoveRecord.Count > 1 && play.Activity == AiActivity.Idle);

        Retire(flow, scheduler);
    }

    /// <summary>
    /// Files whatever is still active and comes back to the home, so the next
    /// section starts from nothing. It is the save-and-continue flow, used as
    /// the flow rather than around it.
    /// </summary>
    private static void Retire(PlayFlow flow, PumpScheduler scheduler)
    {
        if (flow.Page != PlayPage.Home)
        {
            flow.LeaveTopPage();
        }

        if (flow.ActiveGame is null)
        {
            return;
        }

        flow.Choose(PlayMode.FreePlay);
        flow.SaveAndContinue();
        scheduler.PumpUntil(() => flow.Page == PlayPage.Setup, TimeSpan.FromSeconds(10));
        flow.LeaveTopPage();
    }

    private static uint HistoryCount(MiniXiangqiCore core)
    {
        uint count;
        ulong revision;
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_store_history_count(core.Handle, &count, &revision, &err),
            in err,
            nameof(Mxq.mxq_store_history_count));
        return count;
    }

    /// <summary>
    /// The most recently recorded History entry. The order is the core's, most
    /// recent first, and this reads the head of it.
    /// </summary>
    private static MxqRecordSummary LatestRecord(MiniXiangqiCore core)
    {
        MxqRecordSummary[] page = new MxqRecordSummary[1];
        nuint written;
        ulong revision;
        fixed (MxqRecordSummary* buffer = page)
        {
            MxqError err = MxqCall.Error();
            MxqCall.Check(
                Mxq.mxq_store_history_page(core.Handle, 0, 1, buffer, 1, &written, &revision, &err),
                in err,
                nameof(Mxq.mxq_store_history_page));
        }

        return page[0];
    }

    /// <summary>
    /// 28. 无法开始对局 — the creation failure that is not about memory.
    ///
    /// **The refusal is the core's own, and the route to it is one the app
    /// cannot take.** `mxq_game_create` answers
    /// MXQ_ERR_STATE_ACTIVE_GAME_EXISTS when the library already holds an active
    /// game, and PlayFlow's own release-before-OpenSetup invariant means it
    /// never asks in that state. So this puts a game there behind a flow's back
    /// and drives the flow into the refusal. What is under test is the
    /// **answer** rather than the cause — `Create`'s catch does not discriminate
    /// between MxqExceptions, so the flow behaves identically whichever store or
    /// state refusal arrives — and the answer is what had no run at all.
    ///
    /// Its sibling, the accepted 无法保存对局 retry after a refused archive, has
    /// no such route: making `mxq_store_archive_and_clear` fail needs the store
    /// itself to fail, and there is no honest seam for that short of a stand-in
    /// replacing the call under test. It is stated as unrun in the pull request
    /// and in windows/README.md rather than dressed up.
    /// </summary>
    private static void TheCreationTheStoreRefused(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("28. 无法开始对局 — a creation the core would not make");

        // A game standing in the library, held open, so the flow's own create
        // has something to collide with. Deliberately not through the flow: the
        // flow cannot reach this state, which is the point.
        using GameSession standing = core.Create(
            Mxq.MXQ_PLAY_MODE_FREE_PLAY,
            Mxq.MXQ_COLOR_NONE,
            Mxq.MXQ_AI_LEVEL_NONE,
            Mxq.MXQ_FIRST_MOVER_NONE,
            0);

        // Start() is deliberately not called: it would resume the game above and
        // open the board on it, and what this needs is a destination on its home
        // page that does not know the library is occupied.
        using PlayFlow flow = new(core, scheduler, NoPreferences.Instance);
        flow.Choose(PlayMode.FreePlay);
        Check("the pre-start page opened", flow.Page == PlayPage.Setup);

        flow.StartGame();
        Console.WriteLine($"    after 开始对局       alert {flow.Alert}, page {flow.Page}");
        Check("a creation the core refuses is the accepted 无法开始对局 notice",
            flow.Alert == FlowAlert.GameNotStarted);
        Check("it created nothing", flow.Session is null);
        Check("the page and the draft remain, and 开始对局 is enabled again",
            flow is { Page: PlayPage.Setup, Creating: false });
        Console.WriteLine($"    message             {Strings.Get("alert.gameNotStarted.message")}");
        Check("its message does not promise that a current game is unchanged",
            Strings.Get("alert.gameNotStarted.message")
                != Strings.Get("alert.saveFailed.message"));

        flow.DismissAlert();
        Check("取消 dismisses without leaving the page",
            flow is { Alert: FlowAlert.None, Page: PlayPage.Setup });

        // The same refusal again through 重试, which repeats the whole attempt.
        flow.StartGame();
        Check("重试 repeats the attempt and meets the same refusal",
            flow.Alert == FlowAlert.GameNotStarted && flow.Session is null);
        flow.DismissAlert();
        flow.LeaveTopPage();

        core.ArchiveAndClear(standing);
        Console.WriteLine("    (the standing game filed; the library is empty again)");
    }

    // ---------------------------------------------------------------------
    // 29 to 35. The History destination, its step-through viewer, and import.
    //
    // Everything below is driven through HistoryFlow and ReplayViewer — the same
    // objects the window drives — with one deliberate exception named where it
    // happens: the file picker, which needs the window's own handle, so the
    // harness names a file directly where the window would have picked one.
    // Every byte those files hold was written by mxq_store_export on this
    // machine, so the interchange path below is the real one rather than a
    // fixture standing in for it.
    // ---------------------------------------------------------------------
    private static void TheHistoryDestination(string store, string assets)
    {
        // Its own core, over a store directory that has never been written, and
        // shut down before this section opens one of its own.
        TheEmptyLibrary(assets);

        Section("30. The History destination: the list, its sections, and its rows");

        using MiniXiangqiCore core = MiniXiangqiCore.Start(store, assets);
        PumpScheduler scheduler = new();

        // Whatever the earlier sections left active is filed first: one game is
        // active at a time, and a History list is what this section is about.
        using (GameSession? standing = core.ResumeActive())
        {
            if (standing is not null)
            {
                core.ArchiveAndClear(standing);
            }
        }

        // Two games of known shape, so the row vocabulary can be stated rather
        // than described. The first is played to a resignation — a result whose
        // reason a row must keep — and the second is filed as it stands, which is
        // the ended-early record whose result slot carries its own reason.
        ulong resigned = FileAResignation(core, scheduler);
        ulong endedEarly = FileAnEndedEarlyFreePlayGame(core);

        using HistoryFlow history = new(core, scheduler, NoPreferences.Instance);
        history.Load();

        Console.WriteLine($"    records             {history.Records.Count}");
        Console.WriteLine($"    pinned              {history.PinnedCount}");
        Check("the library was read", history is { Loaded: true, LoadFailure: null });
        Check("both filed games are in it", history.Records.Count >= 2);
        Check("nothing is pinned, so the list is one unheaded section",
            history.PinnedCount == 0 && !history.Records[0].Pinned);
        Check("the order is the core's, most recently added first",
            history.Records[0].RecordId == endedEarly && history.Records[1].RecordId == resigned);
        Check("an empty state is not claimed for a library that has games", !history.IsEmpty);

        RecordSummary loss = history.Records.First(record => record.RecordId == resigned);
        RecordSummary early = history.Records.First(record => record.RecordId == endedEarly);

        Console.WriteLine($"    resigned row        {loss.WhenLine()}");
        Console.WriteLine($"                        {loss.MetadataLine()}");
        Console.WriteLine($"    ended-early row     {early.WhenLine()}");
        Console.WriteLine($"                        {early.MetadataLine()}");

        Check("a human-versus-AI row names the mode and the human's side",
            loss.MetadataLine().StartsWith(
                Strings.Join(Strings.Get("mode.humanVersusAI"), Strings.Get("metadata.youRed")),
                StringComparison.Ordinal));
        Check("a resignation keeps its reason beside the result",
            loss.MetadataLine().Contains(Strings.Get("reason.resignation"), StringComparison.Ordinal)
            && loss.MetadataLine().Contains(Strings.Get("result.blackWins"), StringComparison.Ordinal));
        Check("a Free Play row omits 执子",
            !early.MetadataLine().Contains(Strings.Get("metadata.youRed"), StringComparison.Ordinal)
            && !early.MetadataLine().Contains(Strings.Get("metadata.youBlack"), StringComparison.Ordinal));
        Check("an ended-early row says 提前结束 once, in the result slot",
            Occurrences(early.MetadataLine(), Strings.Get("reason.endedEarly")) == 1);
        Check("every row ends with the move count",
            loss.MetadataLine().EndsWith(loss.MoveCountText(), StringComparison.Ordinal)
            && early.MetadataLine().EndsWith(early.MoveCountText(), StringComparison.Ordinal));
        Check("a locally played row carries no imported marker",
            !loss.WhenLine().Contains(Strings.Get("metadata.imported"), StringComparison.Ordinal));

        // The accepted reason the time is on the line at all: "it is what tells
        // two games played on one day apart". So two instants one hour apart on
        // one day are rendered, and what the check states is that they read
        // differently — which is the clause, rather than the shape of a string.
        long noon = DateTimeOffset
            .ParseExact("2026-07-31T12:00:00Z", "yyyy-MM-dd'T'HH:mm:ss'Z'",
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal)
            .ToUnixTimeMilliseconds();
        CultureInfo reader = CultureInfo.GetCultureInfo("en-GB");
        string earlier = HistoryText.Moment(noon, reader);
        string later = HistoryText.Moment(noon + (60 * 60 * 1000), reader);
        Console.WriteLine($"    two instants        {earlier}   /   {later}");
        Check("two games filed on one day are told apart by the time", earlier != later);
        Check("and the row's date carries a four-digit year",
            earlier.Contains("2026", StringComparison.Ordinal));
        Check("a two-digit year in a culture's own short date is widened to four",
            HistoryText.WithFourDigitYear("dd/MM/yy") == "dd/MM/yyyy"
            && HistoryText.WithFourDigitYear("M/d/yyyy") == "M/d/yyyy"
            && HistoryText.WithFourDigitYear("'yy'/yy") == "'yy'/yyyy");

        // Pinning is ordering rather than decoration: the row moves between the
        // two sections, and that movement is the whole report.
        history.SetPinned(resigned, true);
        Console.WriteLine($"    after 置顶           pinned {history.PinnedCount}, "
            + $"head {history.Records[0].RecordId}");
        Check("a pinned record moves to the head of the list",
            history.PinnedCount == 1 && history.Records[0].RecordId == resigned);
        Check("and the two sections are the prefix and the rest",
            history.Pinned.Single().RecordId == resigned
            && history.Others.All(record => !record.Pinned));

        history.SetPinned(resigned, false);
        Check("取消置顶 puts it back", history.PinnedCount == 0);

        TheUnreadableLibrary(history);
        TheViewer(history, endedEarly, resigned);
        TheDeleteGate(core, scheduler, history);
        TheImportAnswers(core, scheduler, history);
    }

    /// <summary>
    /// 29. What the destination says with nothing in it — which is the first
    /// thing every new installation shows, and until now the only screen in this
    /// frontend nothing had ever run.
    ///
    /// It gets a store directory that has never been written, because that is the
    /// state it is about: an empty library is not the same thing as a library
    /// emptied by deletions, and the core creates the store's leading directories
    /// itself.
    /// </summary>
    private static void TheEmptyLibrary(string assets)
    {
        Section("29. A library with nothing in it");

        string fresh = Path.Combine(Path.GetTempPath(), "mxq-empty-" + Guid.NewGuid().ToString("N"));
        try
        {
            using MiniXiangqiCore core = MiniXiangqiCore.Start(fresh, assets);
            using HistoryFlow history = new(core, new PumpScheduler(), NoPreferences.Instance);
            history.Load();

            Console.WriteLine($"    records             {history.Records.Count}");
            Console.WriteLine($"    empty               {history.IsEmpty}");
            Console.WriteLine($"    title               {Strings.Get("history.empty.title")}");
            Console.WriteLine($"    description         {Strings.Get("history.empty.description")}");

            Check("a store that has never been written reads as an empty library",
                history is { Loaded: true, LoadFailure: null } && history.Records.Count == 0);
            Check("an empty library is the empty state rather than a failure", history.IsEmpty);
            Check("it has neither section, so the list reads as a plain list",
                history.PinnedCount == 0 && !history.Pinned.Any() && !history.Others.Any());
            Check("还没有历史对局 and its one line are what it says",
                Strings.Table["history.empty.title"].Chinese == "还没有历史对局"
                && Strings.Table["history.empty.description"].Chinese == "对局结束后会保存到这里。");

            // The empty state gains no import button — it says what it says and
            // offers nothing else to do — and 导入… is above it either way, which
            // is the toolbar item the window draws on this page whatever the list
            // holds.
            Check("导入… is the destination's own item and does not belong to the list",
                Strings.Get("control.import").Length > 0);
        }
        finally
        {
            try
            {
                Directory.Delete(fresh, recursive: true);
            }
            catch (IOException)
            {
                // A scratch store; failing to remove it is not a result.
            }
        }
    }

    /// <summary>
    /// A library the frontend could not read, which is the other screen this
    /// destination has and the other one nothing had run.
    ///
    /// The route is a record identifier the store never issued: every one of
    /// `_get`, `_open`, `_set_pinned` and `_delete` answers
    /// MXQ_ERR_STORE_NOT_FOUND for one, "as an identifier that was never issued
    /// is". What is under test is the **answer** — that a library which cannot be
    /// read says so in the failure-screen family rather than showing an empty
    /// list it has no evidence for — rather than the cause, and the answer is
    /// what had no run at all.
    /// </summary>
    private static void TheUnreadableLibrary(HistoryFlow history)
    {
        Section("历史未能载入 — the screen a library that cannot be read shows");

        int before = history.Records.Count;
        history.Open(ulong.MaxValue);

        Console.WriteLine($"    diagnostic          {history.LoadFailure?.Replace('\n', ' ')}");
        Check("a record the store never issued is a library that did not load",
            history.LoadFailure is { Length: > 0 });
        Check("the diagnostic is the core's own, named and coded",
            history.LoadFailure!.Contains("MXQ_ERR_STORE_NOT_FOUND", StringComparison.Ordinal)
            && history.LoadFailure.Contains(
                Mxq.MXQ_ERR_STORE_NOT_FOUND.ToString(CultureInfo.InvariantCulture),
                StringComparison.Ordinal));
        Check("it opened no viewer", history is { Viewer: null, Page: HistoryPageKind.List });
        Check("and it is not an alert: there is no action to offer",
            history.Alert == HistoryAlert.None);

        // It is one destination's screen rather than the window's, so reading the
        // library again is what puts it away.
        history.Load();
        Check("a library that reads again clears it",
            history.LoadFailure is null && history.Records.Count == before);
    }

    /// <summary>
    /// 35. A library that does not fit in one page.
    ///
    /// `AllHistory`'s paging loop is the only code in this frontend a small
    /// library never reaches: with fewer than 200 records the second call is
    /// never made, so `offset > 0` had never executed and neither had the
    /// short-page exit. Filing 201 games is a few hundred store commits and a
    /// second or two, which is proportionate for a loop that would otherwise
    /// first run on somebody's real library.
    ///
    /// Its own store, because it wants a library of a known size and every other
    /// section shares one.
    /// </summary>
    private static void ThePagedLibrary(string assets)
    {
        Section("35. A library larger than one page");

        const int wanted = MiniXiangqiCore.HistoryPageSize + 1;
        string fresh = Path.Combine(Path.GetTempPath(), "mxq-paged-" + Guid.NewGuid().ToString("N"));
        try
        {
            using MiniXiangqiCore core = MiniXiangqiCore.Start(fresh, assets);

            Stopwatch clock = Stopwatch.StartNew();
            for (int index = 0; index < wanted; index++)
            {
                using GameSession game = core.Create(
                    Mxq.MXQ_PLAY_MODE_FREE_PLAY,
                    Mxq.MXQ_COLOR_NONE,
                    Mxq.MXQ_AI_LEVEL_NONE,
                    Mxq.MXQ_FIRST_MOVER_NONE,
                    0);
                core.ArchiveAndClear(game);
            }

            clock.Stop();
            Console.WriteLine($"    filed               {wanted} games in {clock.ElapsedMilliseconds} ms");

            using HistoryFlow history = new(core, new PumpScheduler(), NoPreferences.Instance);
            history.Load();

            Console.WriteLine($"    page size           {MiniXiangqiCore.HistoryPageSize}");
            Console.WriteLine($"    records             {history.Records.Count}");

            Check("the whole library is read, not the first page of it",
                history is { LoadFailure: null } && history.Records.Count == wanted);
            Check("the second page is the one record beyond the first",
                history.Records.Count == MiniXiangqiCore.HistoryPageSize + 1);
            Check("every record is distinct, so no page was read twice",
                history.Records.Select(record => record.RecordId).Distinct().Count() == wanted);
            Check("the order is still the core's, newest first and strictly descending",
                history.Records.Zip(history.Records.Skip(1))
                    .All(pair => pair.First.RecordId > pair.Second.RecordId));

            // And the page call itself, at an offset the whole-library read
            // reaches only through its loop.
            HistoryPage second = core.HistoryPageAt(
                MiniXiangqiCore.HistoryPageSize, (uint)MiniXiangqiCore.HistoryPageSize);
            Console.WriteLine($"    page at offset {MiniXiangqiCore.HistoryPageSize}  {second.Records.Count} record(s)");
            Check("a page past the first returns the remainder and stops",
                second.Records.Count == 1
                && second.Records[0].RecordId == history.Records[^1].RecordId);
        }
        finally
        {
            try
            {
                Directory.Delete(fresh, recursive: true);
            }
            catch (IOException)
            {
                // A scratch store; failing to remove it is not a result.
            }
        }
    }

    /// <summary>
    /// 31. The step-through viewer.
    ///
    /// Every position below is `mxq_game_position_at`'s answer about the ply
    /// asked for, on the detached read-only session `mxq_store_history_open`
    /// returned. Nothing here applies or unapplies a move.
    /// </summary>
    private static void TheViewer(HistoryFlow history, ulong freePlay, ulong versusAi)
    {
        Section("31. The step-through viewer");

        history.Open(freePlay);
        if (history.Viewer is not { } viewer)
        {
            Check("the record opened", false);
            return;
        }

        Console.WriteLine($"    page                {history.Page}");
        Console.WriteLine($"    plies               {viewer.Plies}");
        Console.WriteLine($"    progress            {viewer.Progress}");
        Console.WriteLine($"    metadata            {viewer.MetadataLine}");
        Console.WriteLine($"    record              {string.Join(' ', viewer.MoveRecord)}");

        Check("opening a record opens the viewer page", history.Page == HistoryPageKind.Viewer);
        Check("replay begins at the game's initial position", viewer.Ply == 0 && viewer.IsAtStart);
        Check("the initial position is the frozen starting FEN",
            viewer.Position.Fen == MiniXiangqiCore.StartFen);
        Check("no move produced the initial position", viewer.Scene.LastMove is null);
        Check("the record is the core's own canonical coordinate text",
            viewer.MoveRecord.Count > 0 && viewer.MoveRecord.All(IsCanonicalMove));
        Check("the record's length is the record's move count",
            viewer.MoveRecord.Count == (int)viewer.Record.MoveCount);

        // The separator is the same in both languages and no word in the pair is
        // translated, so the expected string can be spelled out here rather than
        // built from the call under test.
        Check("progress is shown ply over recorded plies",
            viewer.Progress == $"0 / {viewer.Plies}");
        Check("Free Play history opens with Red at the bottom", !viewer.Flipped);

        // The board is read-only: nothing on the scene is an affordance.
        Check("the replay board offers nothing to interact with",
            viewer.Scene.Selected is null
            && viewer.Scene.Destinations.IsEmpty
            && viewer.Scene.Captures.IsEmpty
            && viewer.Scene.Hovered is null);

        string startFen = viewer.Position.Fen;
        viewer.Next();
        Console.WriteLine($"    after 下一步          {viewer.Progress}  last {viewer.Scene.LastMove?.Text}");
        Check("下一步 advances one ply", viewer.Ply == 1 && !viewer.IsAtStart);
        Check("and the position changed", viewer.Position.Fen != startFen);
        Check("the move that produced it is the ply just played",
            viewer.Scene.LastMove?.Text == viewer.MoveRecord[0]);

        viewer.Previous();
        Check("上一步 goes back to exactly the position that was there",
            viewer.Ply == 0 && viewer.Position.Fen == startFen && viewer.Scene.LastMove is null);

        viewer.Last();
        Console.WriteLine($"    after 跳到最后        {viewer.Progress}");
        Check("跳到最后 shows the last recorded position",
            viewer.IsAtEnd && viewer.Ply == viewer.Plies);
        Check("the last position is the ply count the record holds",
            viewer.Position.PlyCount == viewer.Record.MoveCount);

        viewer.Next();
        Check("下一步 at the end moves nothing", viewer.Ply == viewer.Plies);

        viewer.First();
        Check("回到开始 returns to the initial position",
            viewer.IsAtStart && viewer.Position.Fen == startFen);

        viewer.Previous();
        Check("上一步 at the start moves nothing", viewer.Ply == 0);

        // Selecting a move in the list jumps to it, which is what the accepted
        // move-list behaviour asks of replay and of replay alone.
        int middle = Math.Max(1, viewer.Plies / 2);
        viewer.Show(middle);
        Check("selecting a move shows that move's position",
            viewer.Ply == middle && viewer.Scene.LastMove?.Text == viewer.MoveRecord[middle - 1]);

        bool before = viewer.Flipped;
        string standing = viewer.Position.Fen;
        viewer.FlipBoard();
        Check("the orientation control is available and changes presentation only",
            viewer.Flipped != before
            && viewer.Scene.Flipped == viewer.Flipped
            && viewer.Ply == middle
            && viewer.Position.Fen == standing);

        history.CloseViewer();
        Check("the back control returns to the list",
            history is { Page: HistoryPageKind.List, Viewer: null });

        // A human-versus-AI record opens on the original human player's own
        // perspective, which for a Red human is Red at the bottom.
        history.Open(versusAi);
        Check("human-versus-AI history opens on the human's own side",
            history.Viewer is { Flipped: false });
        Check("a resigned record's committed outcome is the store's, not the position's",
            history.Viewer!.Record.Outcome == Mxq.MXQ_OUTCOME_BLACK_WINS
            && history.Viewer.Record.EndReason == Mxq.MXQ_END_REASON_RESIGNATION);
        history.CloseViewer();
    }

    /// <summary>
    /// 32. 删除前确认, both ways round, and the deletion behind it.
    /// </summary>
    private static void TheDeleteGate(
        MiniXiangqiCore core, PumpScheduler scheduler, HistoryFlow standing)
    {
        Section("32. 删除 and the 删除前确认 preference, both paths");

        // The preference is read at the moment of use, so each path below is a
        // destination over a store that holds one answer.
        StubPreferences asks = new();
        StubPreferences doesNot = new();
        doesNot[Preferences.DeleteConfirmationKey] = "false";

        Check("the preference defaults to on where nothing is stored",
            Preferences.ConfirmsDeletion(NoPreferences.Instance));
        Check("a stored no is honoured", !Preferences.ConfirmsDeletion(doesNot));
        Check("a value that is not a flag reads as on, because false is the "
            + "dangerous answer here",
            Preferences.ConfirmsDeletion(Nonsense()));

        // And the reader every deletion actually runs, over a real file: a JSON
        // boolean, which is what a Settings screen would write.
        string file = Path.Combine(Path.GetTempPath(), "mxq-prefs-" + Guid.NewGuid().ToString("N") + ".json");
        File.WriteAllText(file, "{\"deleteConfirmation.enabled\":false}");
        Check("FilePreferenceStore reads a JSON boolean",
            !Preferences.ConfirmsDeletion(new FilePreferenceStore(file)));
        File.WriteAllText(file, "{\"deleteConfirmation.enabled\":\"true\"}");
        Check("and the string spelling of one",
            Preferences.ConfirmsDeletion(new FilePreferenceStore(file)));
        File.Delete(file);

        ulong first = FileAnEndedEarlyFreePlayGame(core);
        ulong second = FileAnEndedEarlyFreePlayGame(core);

        using (HistoryFlow gated = new(core, scheduler, asks))
        {
            gated.Load();
            int before = gated.Records.Count;

            gated.RequestDelete(first);
            Console.WriteLine($"    with the preference on   alert {gated.Alert}");
            Check("删除 presents the accepted confirmation", gated.Alert == HistoryAlert.ConfirmDelete);
            Check("and the record remains in the list until it is answered",
                gated.Records.Count == before && gated.Records.Any(r => r.RecordId == first));

            gated.DismissAlert();
            Check("取消 leaves the record exactly where it was",
                gated.Alert == HistoryAlert.None
                && gated.Records.Any(r => r.RecordId == first));

            gated.RequestDelete(first);
            gated.ConfirmDelete();
            Console.WriteLine($"    after 删除               records {gated.Records.Count}");
            Check("删除 on the confirmation removes the record permanently",
                gated.Alert == HistoryAlert.None
                && gated.Records.All(r => r.RecordId != first));
            Check("and the core no longer holds it", !Exists(core, first));
        }

        using (HistoryFlow immediate = new(core, scheduler, doesNot))
        {
            immediate.Load();
            immediate.RequestDelete(second);
            Console.WriteLine($"    with the preference off  alert {immediate.Alert}");
            Check("with 删除前确认 off the deletion happens immediately",
                immediate.Alert == HistoryAlert.None
                && immediate.Records.All(r => r.RecordId != second));
            Check("and the core no longer holds that one either", !Exists(core, second));
        }

        // The preference is read at the moment of use rather than cached, which
        // is the rule every preference in this frontend shares and the reason a
        // switch takes effect at the next deletion rather than at the next run.
        // One store, changed between two deletions on one destination.
        StubPreferences switched = new();
        ulong third = FileAnEndedEarlyFreePlayGame(core);
        ulong fourth = FileAnEndedEarlyFreePlayGame(core);
        using (HistoryFlow live = new(core, scheduler, switched))
        {
            live.Load();
            live.RequestDelete(third);
            Check("the same destination asks first while the preference says so",
                live.Alert == HistoryAlert.ConfirmDelete);
            live.ConfirmDelete();

            switched[Preferences.DeleteConfirmationKey] = "false";
            live.RequestDelete(fourth);
            Check("and stops asking the moment it is switched off, without a relaunch",
                live.Alert == HistoryAlert.None && !Exists(core, fourth));
        }

        standing.Load();

        // The refusal has no honest seam either — making mxq_store_history_delete
        // fail needs the store itself to fail — so what is stated here is the
        // mapping, and the pull request says so rather than dressing it up.
        Console.WriteLine("    (无法删除这盘棋 needs a store that refuses a delete; no seam, stated unrun)");
    }

    /// <summary>
    /// 33 and 34. Import: the interchange promise, driven with real bytes.
    ///
    /// Every file below came out of `mxq_store_export` on this machine, written
    /// to disk and handed back to `HistoryFlow.ImportFile` exactly as the picker
    /// would hand it one. What the harness stands in for is the picker and
    /// nothing else.
    /// </summary>
    private static void TheImportAnswers(
        MiniXiangqiCore core, PumpScheduler scheduler, HistoryFlow history)
    {
        Section("33. Export and import: one game out to a file and back in");

        string directory = Path.Combine(Path.GetTempPath(), "mxq-interchange-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);

        ulong source = history.Records[0].RecordId;
        RecordSummary exported = history.Records[0];
        string path = Path.Combine(directory, exported.SuggestedFileName());

        Console.WriteLine($"    suggested name      {exported.SuggestedFileName()}");
        Check("the exported name is built from the game's own end, machine-ordered",
            exported.SuggestedFileName().StartsWith("minixiangqi-", StringComparison.Ordinal)
            && exported.SuggestedFileName().EndsWith(".mxq", StringComparison.Ordinal)
            && exported.SuggestedFileName().Length == "minixiangqi-2026-07-30-2133.mxq".Length);

        history.ExportTo(source, path);
        bool written = scheduler.PumpUntil(() => !history.Transferring, TimeSpan.FromSeconds(30));
        byte[] bytes = File.ReadAllBytes(path);
        string document = Encoding.UTF8.GetString(bytes);
        Console.WriteLine($"    exported            {bytes.Length:N0} bytes to {Path.GetFileName(path)}");

        Check("共享 wrote the record out as one game file", written && !history.ExportRefused);
        Check("the file is the accepted archive envelope",
            document.StartsWith("{\"archive_format\":\"minixiangqi-game\"", StringComparison.Ordinal));
        Check("it carries this game's frozen identity",
            document.Contains(exported.GameId, StringComparison.Ordinal));
        Check("it is one canonical line", !document.Contains('\n') && !document.Contains('\r'));
        Check("it is inside the accepted import bound", bytes.Length <= HistoryFlow.ImportSizeLimit);

        // 1. The duplicate. The record is still there, so the same bytes are the
        //    same game with the same content: a success that deliberately does
        //    not meet the expectation a first import sets.
        Answer(history, scheduler, path, HistoryAlert.ImportDuplicate, "an unchanged file re-imported is the duplicate answer");
        Check("the duplicate answer names the record it found",
            history.DuplicateRecord == source);
        Check("and nothing was added", history.Records.Count(r => r.RecordId == source) == 1);
        history.DismissAlert();

        // 2. The conflict: the same game_id with different content. `started_at`
        //    is a content member, so shifting it by a second changes the hash
        //    while leaving the move line, the terminal trio and every cross-field
        //    rule exactly as they were.
        string conflicting = Path.Combine(directory, "conflict.mxq");
        File.WriteAllBytes(conflicting, Encoding.UTF8.GetBytes(ShiftStartedAt(document)));
        Answer(history, scheduler, conflicting, HistoryAlert.ImportConflict, "the same game with different content is an identity conflict");
        history.DismissAlert();

        // 3. A file created by a newer version. The archive version is dispatched
        //    on explicitly, and this is the one message the data contract requires
        //    to be distinct.
        string newer = Path.Combine(directory, "newer.mxq");
        File.WriteAllBytes(newer, Encoding.UTF8.GetBytes(
            document.Replace("\"archive_version\":1", "\"archive_version\":2", StringComparison.Ordinal)));
        Answer(history, scheduler, newer, HistoryAlert.ImportNewerVersion, "a newer archive version is its own answer");
        history.DismissAlert();

        // 4. Files that cannot be read: a document that is not one of ours, one
        //    that is not JSON at all, an empty one, and one over the accepted
        //    bound. The taxonomy deliberately does not tell a foreign file from a
        //    damaged one.
        string foreign = Path.Combine(directory, "foreign.mxq");
        File.WriteAllText(foreign, "{\"archive_format\":\"something-else\",\"archive_version\":1}");
        Answer(history, scheduler, foreign, HistoryAlert.ImportUnreadable, "a file that is not ours cannot be read");
        history.DismissAlert();

        string garbage = Path.Combine(directory, "garbage.mxq");
        File.WriteAllText(garbage, "this is not a game file");
        Answer(history, scheduler, garbage, HistoryAlert.ImportUnreadable, "nor can a file that is not JSON");
        history.DismissAlert();

        string empty = Path.Combine(directory, "empty.mxq");
        File.WriteAllBytes(empty, []);
        Answer(history, scheduler, empty, HistoryAlert.ImportUnreadable, "nor an empty one, which reaches the core with a length of zero");
        history.DismissAlert();

        // The size gate is the frontend's, and it is checked before the bytes are
        // read: an oversized file is declined without allocating for it, and the
        // core is never asked.
        string huge = Path.Combine(directory, "huge.mxq");
        File.WriteAllBytes(huge, new byte[HistoryFlow.ImportSizeLimit + 1]);
        history.ImportFile(huge);
        Console.WriteLine($"    oversized file      alert {history.Alert}, transferring {history.Transferring}");
        Check("a file over the accepted 1 MiB bound is declined without reading it",
            history.Alert == HistoryAlert.ImportUnreadable && !history.Transferring);
        history.DismissAlert();

        history.ImportFile(Path.Combine(directory, "there-is-no-such-file.mxq"));
        Check("and so is a file that is not there", history.Alert == HistoryAlert.ImportUnreadable);
        history.DismissAlert();

        // An export that failed leaves no file behind: the picker creates the
        // file before the flow gets it, so a refusal that left it there would
        // leave a `.mxq` of nothing under a name somebody would try to import.
        // The refusal here is the filesystem's — a path inside a file — because
        // the store's own refusal has no seam.
        string impossible = Path.Combine(path, "inside-a-file.mxq");
        history.ExportTo(source, impossible);
        scheduler.PumpUntil(() => !history.Transferring, TimeSpan.FromSeconds(30));
        Console.WriteLine($"    export to a bad path  refused {history.ExportRefused}");
        Check("an export the filesystem refuses is reported as refused", history.ExportRefused);
        Check("and leaves no file of nothing behind", !File.Exists(impossible));

        // Neither a deletion nor a second export begins while one is inside the
        // core: both would commit under a call that is off this thread by
        // contract, and the row is still there a moment later.
        //
        // Transferring is raised synchronously by the call and lowered only when
        // the scheduler delivers the answer, so between the two the destination
        // is in exactly the state this is about, and nothing has been pumped.
        string busy = Path.Combine(directory, "busy.mxq");
        history.ExportTo(source, busy);
        bool inFlight = history.Transferring;

        history.RequestDelete(source);
        bool deletionRefused = history.Alert == HistoryAlert.None;

        string second = Path.Combine(directory, "second.mxq");
        history.ExportTo(source, second);

        scheduler.PumpUntil(() => !history.Transferring, TimeSpan.FromSeconds(30));
        Console.WriteLine($"    during a transfer   delete began {!deletionRefused}, "
            + $"second export began {File.Exists(second)}");
        Check("a deletion asked for during a transfer does not begin",
            inFlight && deletionRefused && Exists(core, source));
        Check("nor does a second export", !File.Exists(second) && File.Exists(busy));

        Section("34. A filed game deleted and read back from its own file");

        // The whole promise in one move: the record is removed, and the file
        // written before it was removed puts the same game back.
        int identical = history.Records.Count;
        core.DeleteHistoryRecord(source);
        history.Load();
        Check("the record is gone", history.Records.All(r => r.RecordId != source));

        history.ImportFile(path);
        bool imported = scheduler.PumpUntil(
            () => !history.Transferring, TimeSpan.FromSeconds(30));
        Console.WriteLine($"    after 导入…          alert {history.Alert}, "
            + $"highlighted {history.Highlighted}");

        Check("a valid import says nothing: the row is the answer",
            imported && history.Alert == HistoryAlert.None && history.Highlighted is not null);
        Check("the list is back to its length", history.Records.Count == identical);

        RecordSummary restored = history.Records.First(r => r.RecordId == history.Highlighted);
        Console.WriteLine($"    restored row        {restored.WhenLine()}");
        Console.WriteLine($"                        {restored.MetadataLine()}");
        Check("the stable identity survived the round trip", restored.GameId == exported.GameId);
        Check("so did the result, the reason and the move count",
            restored.Outcome == exported.Outcome
            && restored.EndReason == exported.EndReason
            && restored.MoveCount == exported.MoveCount
            && restored.EndedAtMs == exported.EndedAtMs);
        Check("the record is marked imported", restored.IsImported());
        Check("and its row says so, on the date line",
            restored.WhenLine().StartsWith(Strings.Get("metadata.imported"), StringComparison.Ordinal));
        Check("provenance is local library metadata and was never in the file",
            !document.Contains("provenance", StringComparison.Ordinal)
            && !document.Contains("pinned", StringComparison.Ordinal));

        // The move line the file carried is the move line the viewer walks.
        history.Open(restored.RecordId);
        Check("the imported game replays from its own file's move line",
            history.Viewer is { } replay
            && replay.MoveRecord.Count == (int)exported.MoveCount
            && document.Contains(replay.MoveRecord[0], StringComparison.Ordinal));
        history.CloseViewer();

        // The light decays on its own, on the destination's own clock rather than
        // on a window's, so it is waited for rather than cleared.
        bool decayed = scheduler.PumpUntil(
            () => history.Highlighted is null, HistoryFlow.HighlightDuration + TimeSpan.FromSeconds(5));
        Check("the highlight decays on its own", decayed && history.Highlighted is null);

        // The two answers with no seam. Their mapping is a pure function of the
        // status and its domain, so the whole of it is stated here even where the
        // core cannot be driven to produce the status.
        Section("The import answers that have no seam, as the mapping they are");
        Check("a damaged stored record is its own answer",
            HistoryFlow.AnswerFor(Mxq.MXQ_ERR_STORE_CORRUPT, Mxq.MXQ_DOMAIN_STORE)
                == HistoryAlert.ImportDamagedRecord);
        Check("a store that would not write it is 无法保存导入的对局",
            HistoryFlow.AnswerFor(Mxq.MXQ_ERR_STORE_IO, Mxq.MXQ_DOMAIN_STORE)
                == HistoryAlert.ImportSaveFailed
            && HistoryFlow.AnswerFor(Mxq.MXQ_ERR_STORE_FULL, Mxq.MXQ_DOMAIN_STORE)
                == HistoryAlert.ImportSaveFailed);
        Check("every other archive-domain refusal is 无法读取这个对局文件",
            HistoryFlow.AnswerFor(Mxq.MXQ_ERR_ARCHIVE_MALFORMED, Mxq.MXQ_DOMAIN_ARCHIVE)
                == HistoryAlert.ImportUnreadable
            && HistoryFlow.AnswerFor(Mxq.MXQ_ERR_ARCHIVE_TOO_LARGE, Mxq.MXQ_DOMAIN_ARCHIVE)
                == HistoryAlert.ImportUnreadable
            && HistoryFlow.AnswerFor(Mxq.MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH, Mxq.MXQ_DOMAIN_ARCHIVE)
                == HistoryAlert.ImportUnreadable);
        Check("an unknown status inside a known domain still has an answer",
            HistoryFlow.AnswerFor(4999, Mxq.MXQ_DOMAIN_STORE) == HistoryAlert.ImportSaveFailed
            && HistoryFlow.AnswerFor(5999, Mxq.MXQ_DOMAIN_ARCHIVE) == HistoryAlert.ImportUnreadable);
        // Those messages say 历史没有改变 explicitly, because no persistent change
        // is the guarantee the core makes and a reader has no other way to know
        // it held. **The damaged record is the one exception**, and it is stated
        // here rather than skipped: that answer is about the library rather than
        // about the file, and a guarantee about a library the same message has
        // just called damaged would be a guarantee worth nothing.
        // docs/interaction-design.md's sentence claimed all of them and is
        // corrected in this pull request to match docs/copy.md's table, which
        // wins by that document's own rule. The normative Chinese is what carries
        // the phrase, so that is the half this reads.
        Check("every import refusal about a file says 历史没有改变",
            new[]
            {
                "alert.importConflict.message",
                "alert.importNewerVersion.message",
                "alert.importUnreadable.message",
                "alert.importSaveFailed.message",
            }.All(key => Strings.Table[key].Chinese.Contains("历史没有改变", StringComparison.Ordinal)));
        Check("and the one refusal about the library deliberately does not",
            !Strings.Table["alert.importDamagedRecord.message"].Chinese
                .Contains("历史没有改变", StringComparison.Ordinal));

        try
        {
            Directory.Delete(directory, recursive: true);
        }
        catch (IOException)
        {
            // A scratch directory; failing to remove it is not a result.
        }
    }

    /// <summary>Import one file and state which answer it gave.</summary>
    private static void Answer(
        HistoryFlow history, PumpScheduler scheduler, string path, HistoryAlert expected, string what)
    {
        int before = history.Records.Count;
        history.ImportFile(path);
        scheduler.PumpUntil(() => !history.Transferring, TimeSpan.FromSeconds(30));
        Console.WriteLine($"    {Path.GetFileName(path),-20} {history.Alert}");
        Check(what, history.Alert == expected);
        Check($"and {Path.GetFileName(path)} changed nothing", history.Records.Count == before);
    }

    /// <summary>
    /// A human-versus-AI game the human resigns: a committed result that the
    /// replayed position does not carry, which is exactly what makes it worth
    /// filing here — the row and the viewer both have to read it from the
    /// store's own summary rather than from the position.
    ///
    /// It is resigned before a move is played, deliberately: the human's own
    /// side moves first, so nothing is owed to the engine, and a section about
    /// the History list should not need one prepared.
    /// </summary>
    private static ulong FileAResignation(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        GameSession game = core.Create(
            Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI,
            Mxq.MXQ_COLOR_RED,
            Mxq.MXQ_AI_LEVEL_FAST,
            Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST,
            Mxq.MXQ_MOVETIME_FAST_MS);

        using PlaySession play = new(core, game, scheduler);
        play.RequestResign();
        play.ConfirmResign();
        return play.FiledRecordId ?? 0;
    }

    /// <summary>
    /// A Free Play game filed as it stands, which the core classifies as ended
    /// early with no competitive result.
    /// </summary>
    private static ulong FileAnEndedEarlyFreePlayGame(MiniXiangqiCore core)
    {
        using GameSession game = core.Create(
            Mxq.MXQ_PLAY_MODE_FREE_PLAY,
            Mxq.MXQ_COLOR_NONE,
            Mxq.MXQ_AI_LEVEL_NONE,
            Mxq.MXQ_FIRST_MOVER_NONE,
            0);

        for (int ply = 0; ply < 6; ply++)
        {
            List<string> legal = [.. game.LegalMoves()];
            legal.Sort(StringComparer.Ordinal);
            if (legal.Count == 0)
            {
                break;
            }

            game.ApplyMove(legal[0]);
        }

        return core.ArchiveAndClear(game);
    }

    private static bool Exists(MiniXiangqiCore core, ulong recordId)
    {
        try
        {
            core.HistoryRecord(recordId);
            return true;
        }
        catch (MxqException)
        {
            return false;
        }
    }

    private static int Occurrences(string text, string token)
    {
        int count = 0;
        for (int index = text.IndexOf(token, StringComparison.Ordinal);
             index >= 0;
             index = text.IndexOf(token, index + token.Length, StringComparison.Ordinal))
        {
            count++;
        }

        return count;
    }

    /// <summary>
    /// Shift a document's <c>started_at</c> back by one second, which changes the
    /// content hash and nothing else about whether the document is valid.
    /// </summary>
    private static string ShiftStartedAt(string document)
    {
        const string member = "\"started_at\":\"";
        int at = document.IndexOf(member, StringComparison.Ordinal) + member.Length;
        string instant = document.Substring(at, "2026-07-30T21:33:00.000Z".Length);
        string shifted = DateTimeOffset
            .ParseExact(instant, "yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal)
            .AddSeconds(-1)
            .ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
        return document[..at] + shifted + document[(at + instant.Length)..];
    }

    /// <summary>A preference store holding a value that is not a flag at all.</summary>
    private static IPreferenceStore Nonsense()
    {
        StubPreferences nonsense = new();
        nonsense[Preferences.DeleteConfirmationKey] = "maybe";
        return nonsense;
    }

    /// <summary>
    /// A probe reporting a machine with nothing to spare. 64 MiB available is
    /// below the accepted 128 MiB minimum reserve, so the usable amount is zero
    /// and the core's own arithmetic answers MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY.
    /// </summary>
    private static MxqEngineBudget Starved() => new()
    {
        struct_size = (uint)sizeof(MxqEngineBudget),
        active_processor_count = (uint)Environment.ProcessorCount,
        available_bytes = 64UL * 1024 * 1024,
        physical_bytes = 64UL * 1024 * 1024,
    };

    /// <summary>A preference store holding exactly what a test put in it.</summary>
    private sealed class StubPreferences : IPreferenceStore
    {
        private readonly Dictionary<string, string> _values = new(StringComparer.Ordinal);

        internal string this[string key]
        {
            set => _values[key] = value;
        }

        public string? Read(string key) => _values.GetValueOrDefault(key);
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
    // 36 and 37. The Settings destination, and the board's four voices.
    //
    // Its own core over its own store directory, because the core is
    // singleton-enforced and because the games played here are for their sound
    // rather than for a library anybody reads afterwards.
    //
    // What the *screen* looks like is not here and cannot be: it is XAML, and a
    // WinUI 3 process fail-fasts in session 0. What is here is everything the
    // screen decides — which keys it writes, in which vocabulary, and what the
    // surfaces that read those keys make of them afterwards. **And the audible
    // half of section 37 is the owner's tour**: a harness can state which event
    // asked for which voice, and only an ear can say the voices are right.
    // ---------------------------------------------------------------------
    private static void TheSettingsDestination(string assets)
    {
        string store = Path.Combine(
            Path.GetTempPath(), "mxq-settings-" + Guid.NewGuid().ToString("N"));

        try
        {
            using MiniXiangqiCore core = MiniXiangqiCore.Start(store, assets);
            PumpScheduler scheduler = new();

            TheSettingsRoundTrip(core, scheduler);
            TheFourVoices(core, scheduler);
        }
        finally
        {
            try
            {
                Directory.Delete(store, recursive: true);
            }
            catch (IOException)
            {
                // A scratch directory; failing to remove it is not a result.
            }
        }
    }

    /// <summary>
    /// 36. The Settings screen, and the surfaces that read what it wrote.
    ///
    /// **The circle closes here.** Section 22 proved the reader: a pre-start
    /// draft opens on `defaults.firstMover` and `defaults.aiLevel` with the
    /// accepted fallbacks. This proves the writer against that same reader, over
    /// the same `FilePreferenceStore` and the same file on disk — the screen
    /// writes, the raw JSON is read back to confirm the key and the vocabulary,
    /// and then a real `PlayFlow` walks to a pre-start page and opens on it.
    /// Neither half is a stand-in for the other.
    ///
    /// **Eight keys are absent and that is scope, not a gap** — 棋盘's group
    /// header, the two rows of a label and two options each that stood under it,
    /// and 触感's switch. The string table is where that is stated mechanically
    /// below: the keys this screen draws are there, and those eight are not.
    /// </summary>
    private static void TheSettingsRoundTrip(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("36. The Settings screen: what it writes, and who reads it back");

        string directory = Path.Combine(
            Path.GetTempPath(), "mxq-settings-prefs-" + Guid.NewGuid().ToString("N"));
        string path = Path.Combine(directory, "preferences.json");
        FilePreferenceStore stored = new(path);
        SettingsScreen settings = new(stored);

        int published = 0;
        settings.Changed += () => published++;

        try
        {
            Console.WriteLine($"    preferences file    {path}");

            // Neither the file nor the directory above it exists yet, which is
            // the state of every first launch.
            Check("a screen over nothing stored opens on the accepted defaults",
                settings is
                {
                    DefaultFirstMover: FirstMoverChoice.HumanFirst,
                    DefaultAiLevel: AiLevel.Standard,
                    Sound: true,
                    ConfirmsDeletion: true,
                });

            settings.ChooseDefaultFirstMover(FirstMoverChoice.AiFirst);
            settings.ChooseDefaultAiLevel(AiLevel.Deep);
            settings.SetSound(false);
            settings.SetDeleteConfirmation(false);

            Check("a first write creates the file and the directory above it",
                File.Exists(path));
            Console.WriteLine($"    written             {File.ReadAllText(path).ReplaceLineEndings(" ")}");

            // The raw document, because the *key* and the *vocabulary* are the
            // interface between the two frontends and a reader of our own could
            // agree with a writer of our own about a spelling neither of them
            // shares with the Apple app.
            Check("the keys and their vocabulary are the contract's own",
                Stored(path, "defaults.firstMover") == "\"ai-first\""
                && Stored(path, "defaults.aiLevel") == "\"deep\""
                && Stored(path, "sound.enabled") == "false"
                && Stored(path, "deleteConfirmation.enabled") == "false");

            Check("a flag is written as a flag, not as its spelling",
                stored.ReadFlag(Preferences.SoundKey) == false
                && stored.Read(Preferences.SoundKey) is null);

            Check("the screen reads back exactly what it wrote",
                settings is
                {
                    DefaultFirstMover: FirstMoverChoice.AiFirst,
                    DefaultAiLevel: AiLevel.Deep,
                    Sound: false,
                    ConfirmsDeletion: false,
                });

            // The first end of the circle: the reader section 22 proved, over the
            // file this screen just wrote.
            SetupDraft draft = SetupDraft.FromDefaults(new FilePreferenceStore(path));
            Console.WriteLine($"    the draft opens on  {draft.FirstMover} / {draft.Level}");
            Check("the pre-start draft opens on what Settings wrote",
                draft is { FirstMover: FirstMoverChoice.AiFirst, Level: AiLevel.Deep });

            // And the other end: the destination itself, walking the home to a
            // pre-start page exactly as a click on a mode entry walks it.
            using (PlayFlow flow = new(core, scheduler, new FilePreferenceStore(path)))
            {
                flow.Start();
                flow.Choose(PlayMode.HumanVersusAi);
                Console.WriteLine(
                    $"    the page opens on   {flow.Draft.FirstMover} / {flow.Draft.Level}, "
                    + $"preview flipped {flow.PreviewScene.Flipped}");
                Check("and so does the pre-start page a mode entry opens",
                    flow.Page == PlayPage.Setup
                    && flow.Draft is { FirstMover: FirstMoverChoice.AiFirst, Level: AiLevel.Deep });
                Check("AI 先手 previews the human as Black on that page",
                    flow.PreviewScene.Flipped);
                flow.LeaveTopPage();
            }

            // The other two keys reach their own readers — the gate in front of
            // the four voices, and the one in front of a permanent deletion.
            Check("声音 off is what the sound gate reads",
                !Preferences.Sound(new FilePreferenceStore(path)));
            Check("删除前确认 off is what the deletion gate reads",
                !Preferences.ConfirmsDeletion(new FilePreferenceStore(path)));

            // Read at the moment of use, on this screen as much as anywhere else:
            // a preference changed underneath it — by hand, or by another
            // frontend over a shared profile — is what it shows next.
            File.WriteAllText(path, """{"defaults.aiLevel":"fast","sound.enabled":true}""");
            Check("the screen shows what is stored rather than what it last wrote",
                settings is { DefaultAiLevel: AiLevel.Fast, Sound: true });
            Check("and a key that went with it reads as the accepted default",
                settings.ConfirmsDeletion);

            // A value that is already the stored value is not written again: a
            // XAML selector reports the value a refresh gives it, and a screen
            // that wrote on every such report would rewrite the file every time
            // it drew.
            published = 0;
            settings.ChooseDefaultAiLevel(AiLevel.Fast);
            settings.SetSound(true);
            Check("choosing what is already chosen writes nothing", published == 0);

            // **The keys no surface here reads survive a write.** This file is
            // not this screen's private state: 记谱法, 棋子符号 and 触感 belong
            // to the Apple frontend, they are absent from this platform by
            // issue #80's trim rather than by disagreement, and a screen that
            // rewrote the object from the four rows it draws would silently
            // delete a preference somebody set on another machine.
            File.WriteAllText(
                path,
                """{"notation.style":"wxf","sound.enabled":true,"pieces.symbols":"icons","haptics.enabled":false}""");
            settings.SetSound(false);
            Console.WriteLine($"    after one write     {File.ReadAllText(path).ReplaceLineEndings(" ")}");
            Check("a preference this platform has no surface for is left exactly as it was",
                Stored(path, "notation.style") == "\"wxf\""
                && Stored(path, "pieces.symbols") == "\"icons\""
                && Stored(path, "haptics.enabled") == "false"
                && Stored(path, "sound.enabled") == "false");

            // And their order with them, the written key's own place included:
            // this is a file a person may open, and one whose members reshuffled
            // on every switch would be a file nobody could read a diff of.
            Check("and so is the order they were in",
                Keys(path) is ["notation.style", "sound.enabled", "pieces.symbols", "haptics.enabled"]);

            // A file nothing can parse is replaced by one that holds the choice
            // just made, rather than leaving a screen whose switches do nothing
            // until somebody deletes a file by hand.
            File.WriteAllText(path, "{ this is not json");
            settings.SetDeleteConfirmation(false);
            Console.WriteLine($"    after the malformed {File.ReadAllText(path).ReplaceLineEndings(" ")}");
            Check("a malformed file is replaced by a well-formed one holding the new value",
                Stored(path, "deleteConfirmation.enabled") == "false"
                && !settings.ConfirmsDeletion);

            // **A write the file system refuses, and the whole of what answers
            // it.** The accepted design here is that there is no alert — a
            // preference that could not be written is a control that visibly did
            // not move — and that is two things holding together rather than one:
            // the screen reads the *stored* value, and `Changed` fires whether or
            // not the write landed, which is the only thing that redraws the
            // control back to it. A refactor announcing only on success would
            // leave a switch showing a value nobody stored, and every check above
            // this one would stay green. So it is driven rather than described.
            //
            // A file standing where the directory should be is what refuses it,
            // deterministically and on every write: `Directory.CreateDirectory`
            // will not make a directory over a file.
            string blocked = Path.Combine(directory, "blocked");
            File.WriteAllText(blocked, "a file where the directory should be");
            SettingsScreen refused = new(new FilePreferenceStore(
                Path.Combine(blocked, "preferences.json")));

            int announced = 0;
            refused.Changed += () => announced++;

            Check("a preference that cannot be read at all is the accepted default",
                refused.Sound);
            refused.SetSound(false);
            Console.WriteLine(
                $"    a refused write     声音 reads {refused.Sound}, {announced} announcement(s)");
            Check("a write the file system refused leaves the value where it was",
                refused.Sound);
            Check("and it announces anyway, which is the only thing that snaps the control back",
                announced == 1);

            // The trim, stated over the string table rather than described. Every
            // row this screen draws is a row of docs/copy.md — section 17 checks
            // that for the whole table — and the rows it deliberately does not
            // draw carry no key at all.
            Check("the screen's own rows are in the string table",
                Strings.Table.ContainsKey("nav.settings")
                && Strings.Table.ContainsKey("settings.defaults.group")
                && Strings.Table.ContainsKey("settings.defaults.firstMover")
                && Strings.Table.ContainsKey("settings.defaults.aiLevel")
                && Strings.Table.ContainsKey("settings.defaults.footer")
                && Strings.Table.ContainsKey("settings.sound.label")
                && Strings.Table.ContainsKey("settings.confirmDelete.label")
                && Strings.Table.ContainsKey("settings.confirmDelete.footer"));
            string[] trimmed =
            [
                "settings.section.board",
                "settings.symbols.label", "settings.symbols.hanzi", "settings.symbols.icons",
                "settings.notation.label", "settings.notation.traditional", "settings.notation.wxf",
                "settings.haptics.label",
            ];
            Check("and the eight trimmed keys carry no string on this platform",
                trimmed.All(key => !Strings.Table.ContainsKey(key)));

            string[] footers =
                [.. Strings.Table.Keys.Where(key => key.StartsWith("settings.", StringComparison.Ordinal)
                    && key.EndsWith(".footer", StringComparison.Ordinal))];
            Console.WriteLine($"    footers             {string.Join(", ", footers.Order(StringComparer.Ordinal))}");
            Check("there are two footers on the screen, and only two", footers.Length == 2);
        }
        finally
        {
            try
            {
                Directory.Delete(directory, recursive: true);
            }
            catch (IOException)
            {
                // A scratch directory; failing to remove it is not a result.
            }
        }
    }

    /// <summary>
    /// 37. The four voices: which event asks for which, and the switch in front
    ///     of them.
    ///
    /// **The felt-and-heard separation cuts this section in two, and only half of
    /// it can run here.** What a landing *asks for* is a decision — a pure
    /// function of the position that arrived — and it is stated below over its
    /// whole truth table and then driven through a real game. Whether the four
    /// samples sound right, and whether the level sits under the system alert
    /// where the contract puts it, is an ear's answer and is **the owner's tour**:
    /// this machine has no audio endpoint and nobody is logged into it.
    ///
    /// The samples themselves are checked for presence rather than for sound, in
    /// the way apple/MiniXiangqi/Motion/BoardSounds.swift's `missing` is: a board
    /// that cannot find its samples is quiet rather than broken, so a file that
    /// fell out of the build is invisible in use and has to be caught here.
    /// </summary>
    private static void TheFourVoices(MiniXiangqiCore core, PumpScheduler scheduler)
    {
        Section("37. The board's four voices, and the 声音 switch in front of them");

        Console.WriteLine($"    samples             {BoardSoundAssets.Directory}");
        foreach (BoardSound sound in BoardSounds.All)
        {
            string file = BoardSoundAssets.PathFor(sound);
            Console.WriteLine(
                $"      {sound,-11} {(File.Exists(file) ? new FileInfo(file).Length + " bytes" : "ABSENT"),-13}"
                + $"{BoardSoundAssets.DurationOf(sound)?.TotalMilliseconds.ToString("0", CultureInfo.InvariantCulture) ?? "?"} ms");
        }

        Check("every sample the code names reached the build",
            BoardSoundAssets.Missing.Count == 0);

        TimeSpan?[] durations = [.. BoardSounds.All.Select(BoardSoundAssets.DurationOf)];
        Check("each is a readable PCM sample", durations.All(length => length is not null));

        // The bounds are the Apple suite's own — `BoardSoundsTests.swift` holds
        // these same four files to them — because what they encode is the
        // contract's character rather than either platform's: a landing is an
        // impact, and the game settling is not another tock. The same numbers on
        // both sides is also what makes the copied bundle checkable as one set:
        // a retune that pushed a sample out of its length would fail in both
        // places rather than in whichever one thought to look.
        Check("a landing is an impact: the three are all inside 150 ms",
            new[] { BoardSound.Plain, BoardSound.Capture, BoardSound.Check }.All(
                sound => BoardSoundAssets.DurationOf(sound) is { TotalSeconds: > 0 and <= 0.150 }));
        Check("and the game settling is a gesture: over 150 ms and inside 450",
            BoardSoundAssets.DurationOf(BoardSound.Conclusion)
                is { TotalSeconds: > 0.150 and <= 0.450 });

        // The rule itself, over everything it can be asked. Precedence is
        // conclusion, then capture, then check, then the plain landing — so a
        // capturing check is a capture and a checkmating capture is a conclusion,
        // which are the two rows a rule written in the wrong order gets wrong.
        Console.WriteLine("    captured finished inCheck   voice");
        bool ranked = true;
        for (int bits = 0; bits < 8; bits++)
        {
            bool captured = (bits & 1) != 0;
            bool finished = (bits & 2) != 0;
            bool inCheck = (bits & 4) != 0;
            BoardSound voice = BoardSounds.OfTheLanding(captured, finished, inCheck);
            BoardSound expected = finished ? BoardSound.Conclusion
                : captured ? BoardSound.Capture
                : inCheck ? BoardSound.Check
                : BoardSound.Plain;
            ranked &= voice == expected;
            Console.WriteLine($"    {captured,-9}{finished,-9}{inCheck,-10}{voice}");
        }

        Check("the higher meaning is the only one heard, in the accepted order", ranked);

        // The gate, held over a recorder: exactly what the app would have
        // silenced, and read at the moment the sound would fire rather than when
        // the gate was composed.
        StubPreferences switchable = new();
        List<BoardSound> gated = [];
        Feedback feedback = Feedback.Gating(switchable, gated.Add);

        feedback.Play(BoardSound.Plain);
        Check("nothing stored means the board is heard", gated.Count == 1);

        switchable[Preferences.SoundKey] = "false";
        feedback.Play(BoardSound.Capture);
        Check("声音 off silences it", gated.Count == 1);

        switchable[Preferences.SoundKey] = "true";
        feedback.Play(BoardSound.Check);
        Check("and back on again, without a relaunch and on the same object",
            gated is [BoardSound.Plain, BoardSound.Check]);

        Check("a board with no player attached is quiet rather than broken",
            Silently(() => Feedback.Silent.Play(BoardSound.Conclusion)));

        // The seam itself, through the session the window drives. Free Play,
        // because every landing here is one the harness commits and no engine is
        // owed; the rule is about the position that arrived and knows nothing
        // about who moved.
        List<BoardSound> heard = [];
        Feedback recording = Feedback.Gating(NoPreferences.Instance, heard.Add);

        GameSession game = core.Create(
            Mxq.MXQ_PLAY_MODE_FREE_PLAY,
            Mxq.MXQ_COLOR_NONE,
            Mxq.MXQ_AI_LEVEL_NONE,
            Mxq.MXQ_FIRST_MOVER_NONE,
            0);

        using (PlaySession play = new(core, game, scheduler, probe: null, feedback: recording))
        {
            play.Begin();

            // A capture-preferring line with a fixed seed, so the game is the
            // same game on every run and every machine. Each landing is checked
            // against what the board itself says happened — the piece that was
            // standing on the destination, and the position that arrived — rather
            // than against the rule under test.
            Random rng = new(20260731);
            bool everyLandingAgrees = true;
            int plies = 0;
            for (; plies < 200 && !play.IsOver; plies++)
            {
                if (Preferring(play, rng) is not { } move)
                {
                    break;
                }

                bool captured = play.Scene.Placement[move.To] is not null;
                int before = heard.Count;

                play.Tap(move.From);
                play.Tap(move.To);

                BoardSound expected = play.IsOver ? BoardSound.Conclusion
                    : captured ? BoardSound.Capture
                    : play.Position.InCheck ? BoardSound.Check
                    : BoardSound.Plain;
                everyLandingAgrees &= heard.Count == before + 1 && heard[^1] == expected;
            }

            Console.WriteLine($"    played              {plies} plies, {heard.Count} landings heard");
            foreach (BoardSound voice in BoardSounds.All)
            {
                Console.WriteLine($"      {voice,-11}{heard.Count(sounded => sounded == voice)}");
            }

            Check("one sound per landing, and no landing silent",
                heard.Count == plies && plies > 0);
            Check("every landing sounded what the arrived position says it should",
                everyLandingAgrees);
            Check("a played game reaches all four voices",
                BoardSounds.All.All(heard.Contains));
            Check("the game's own ending is one conclusion and no more",
                play.IsOver && heard.Count(voice => voice == BoardSound.Conclusion) == 1);
            Check("and it replaced the landing rather than joining it",
                heard[^1] == BoardSound.Conclusion);

            // 保存 confirms a result that already sounded when it was reached. A
            // second conclusion here would be one ending heard twice.
            int settled = heard.Count;
            play.SaveResult();
            Console.WriteLine($"    after 保存           {heard.Count - settled} further sounds");
            Check("保存 files the game and says nothing",
                play.IsFiled && heard.Count == settled);

            // An Undo's return is a landing, and never a capture: the disc that
            // reappears is a restoration rather than a take. A filed game cannot
            // be taken back, so this one is asked of a fresh game.
        }

        TheUndoAndTheTwoQuietEndings(core, scheduler, heard);

        Check("Settings itself is silent, structurally: it holds no Feedback at all",
            typeof(SettingsScreen).GetFields(
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
                .All(field => field.FieldType != typeof(Feedback)));
        Check("and so is the viewer, for the reason a cut has no landing",
            typeof(ReplayViewer).GetFields(
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
                .All(field => field.FieldType != typeof(Feedback)));

        Console.WriteLine("    (whether the four voices sound right is an ear's answer: the owner's tour)");
    }

    /// <summary>
    /// The three landings the played game above could not ask for: a move taken
    /// back, a draw the player claims, and a resignation. The last two are the
    /// results that arrive with **nothing moving**, so their conclusion cannot
    /// wait for a landing and sounds at the commit instead.
    /// </summary>
    private static void TheUndoAndTheTwoQuietEndings(
        MiniXiangqiCore core, PumpScheduler scheduler, List<BoardSound> heard)
    {
        // The repetition shuffle section 20 uses: two cannons step off their own
        // file and back until the starting position stands for the third time.
        GameSession repeating = core.Create(
            Mxq.MXQ_PLAY_MODE_FREE_PLAY,
            Mxq.MXQ_COLOR_NONE,
            Mxq.MXQ_AI_LEVEL_NONE,
            Mxq.MXQ_FIRST_MOVER_NONE,
            0);

        heard.Clear();
        Feedback recording = Feedback.Gating(NoPreferences.Instance, heard.Add);

        using (PlaySession play = new(core, repeating, scheduler, probe: null, feedback: recording))
        {
            play.Begin();

            // One quiet move and its Undo, before the shuffle: neither is a
            // capture, and the position either arrives at is an ordinary one.
            if (Preferring(play, new Random(20260731)) is { } opening)
            {
                play.Tap(opening.From);
                play.Tap(opening.To);
                heard.Clear();
                play.Undo();
            }

            Console.WriteLine($"    after 悔棋           {string.Join(", ", heard)}");
            Check("a move taken back is a disc landing on a point, and never a take",
                heard is [BoardSound.Plain] or [BoardSound.Check]);

            string[] shuffle = ["b1b2", "b7b6", "b2b1", "b6b7"];
            bool reached = false;
            for (int cycle = 0; cycle < 2 && !reached; cycle++)
            {
                foreach (string text in shuffle)
                {
                    if (Move.Parse(text) is not { } move || !play.LegalMoves().Contains(text))
                    {
                        Check("the repetition shuffle is playable", false);
                        core.ArchiveAndClear(repeating);
                        return;
                    }

                    play.Tap(move.From);
                    play.Tap(move.To);
                    reached = play.CanClaimDraw;
                }
            }

            heard.Clear();
            play.RequestClaimDraw();
            Check("presenting the claim's confirmation is silent", heard.Count == 0);

            play.ConfirmClaimDraw();
            Console.WriteLine($"    after 以和棋结束      {string.Join(", ", heard)}");
            Check("a claimed draw settles the game at the confirmation, with nothing moving",
                play.ResultState == Mxq.MXQ_GAME_DRAW && heard is [BoardSound.Conclusion]);
        }

        // A resignation, on a human-versus-AI game the human moves first in — so
        // no search is ever owed and no engine is ever prepared. What is under
        // test is the commit, not the opponent.
        GameSession conceding = core.Create(
            Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI,
            Mxq.MXQ_COLOR_RED,
            Mxq.MXQ_AI_LEVEL_FAST,
            Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST,
            Mxq.MXQ_MOVETIME_FAST_MS);

        heard.Clear();
        using PlaySession resigning = new(
            core, conceding, scheduler, probe: null,
            feedback: Feedback.Gating(NoPreferences.Instance, heard.Add));

        resigning.RequestResign();
        Check("presenting 认输's confirmation is silent", heard.Count == 0);

        resigning.ConfirmResign();
        Console.WriteLine($"    after 认输           {string.Join(", ", heard)}");
        Check("a resignation settles the game at the commit too",
            resigning.IsOver && heard is [BoardSound.Conclusion]);
    }

    // ---------------------------------------------------------------------
    // 38. The board's space: the floor the window keeps for it, and the line
    //     it shows when it has not got it.
    //
    // Everything here is arithmetic and one string, so it opens no core and
    // touches no store — which is the point. The numbers used to live inside
    // MainWindow, where a WinUI 3 process that cannot be launched over SSH is
    // the only thing that could have run them; they are BoardSpace's and
    // WindowFloor's now, and this is the run.
    // ---------------------------------------------------------------------
    private static void TheBoardsSpace()
    {
        Section("38. The board's space, and the line that asks for more of it");

        double block = WindowFloor.BoardBlockAtFloor;
        Console.WriteLine($"    board block at 44   {block}");
        Console.WriteLine($"    content floor       {WindowFloor.ContentWidth} x {WindowFloor.ContentHeight}");
        Console.WriteLine($"    window floor        {WindowFloor.WindowWidth} x {WindowFloor.WindowHeight}");

        // The block the whole floor is derived from. It is 340 rather than the
        // Mac's 308 because this board carries the canonical coordinates on four
        // edges, and the contract's Windows clause states that number.
        Check("the board block at the accepted pitch floor is 340 square", block == 340);
        Check("the play content's floor is 648 by 388",
            WindowFloor.ContentWidth == 648
            && WindowFloor.ContentHeight - WindowFloor.NavigationBarHeight == 388);
        Check("the window's floor is the content's plus the rail and the navigation row",
            WindowFloor.WindowWidth == 696 && WindowFloor.WindowHeight == 432);

        // The floor's own promise, read the way the window reads it: at the
        // minimum window the board host gets exactly the block, and the board
        // fits at exactly the accepted pitch.
        double hostAtTheFloor = WindowFloor.WindowWidth - WindowFloor.CompactRailWidth
            - WindowFloor.PanelWidth - (2 * WindowFloor.Air);
        BoardSpace atTheFloor = BoardSpace.Of(hostAtTheFloor, hostAtTheFloor);
        Console.WriteLine($"    host at the floor   {hostAtTheFloor}  pitch {atTheFloor.Board?.Pitch}");
        Check("at the window's floor the board fits, at the accepted pitch floor",
            hostAtTheFloor == block
            && atTheFloor.Board is { } floored
            && floored.Pitch == BoardGeometry.MinimumPitch);

        // **The pane cannot squeeze it.** The shell's display mode is the
        // platform's own and this app sets none of it, so what matters is the
        // platform's own numbers: a full-width inline pane appears only at or
        // above the expanded threshold, and below that an opened pane overlays
        // the content rather than taking width from it. At the narrowest window
        // that produces an inline pane the content still clears its floor, which
        // is why the floor pays for the 48-point rail and not for a 320-point
        // pane it can never meet.
        Console.WriteLine(
            $"    inline pane at {WindowFloor.ExpandedModeThresholdWidth} leaves "
            + $"{WindowFloor.ContentAtExpandedThreshold} of content");
        Check("the expanded pane cannot take the content below its floor",
            WindowFloor.ContentAtExpandedThreshold >= WindowFloor.ContentWidth);
        Check("and the rail the floor does pay for is the narrower arrangement",
            WindowFloor.CompactRailWidth < WindowFloor.OpenPaneLength
            && WindowFloor.CompactModeThresholdWidth < WindowFloor.ExpandedModeThresholdWidth);

        // One point under the block is where the refusal begins, and the refusal
        // is what the notice answers. The board is not drawn small; it is not
        // drawn.
        BoardSpace justUnder = BoardSpace.Of(block - 1, block);
        BoardSpace tooShort = BoardSpace.Of(block, block - 1);
        BoardSpace none = BoardSpace.Of(0, 0);
        Console.WriteLine($"    at {block - 1} wide         board {justUnder.ShowsBoard}");
        Check("one point under the block, no board is drawn",
            !justUnder.ShowsBoard && justUnder.Board is null);
        Check("the height bounds it exactly as the width does", !tooShort.ShowsBoard);
        Check("a host with no room at all is the same answer", !none.ShowsBoard);
        Check("and a host that has the room still gets its board", atTheFloor.ShowsBoard);

        // The line itself, published by the state rather than fetched beside it.
        // **A key with no row answers with itself**, which is the one thing this
        // value can never legitimately be — the test the Apple catalog suite
        // makes about its own register — so this catches an absent row and a row
        // filled in one language only. Section 17 is where the pair is checked
        // against docs/copy.md.
        string? inChinese = null;
        string? inEnglish = null;
        foreach (bool chinese in (bool[])[true, false])
        {
            Strings.PrefersChinese = chinese;
            string? line = justUnder.Notice;
            Console.WriteLine($"    {(chinese ? "中文" : "en  ")}                {line}");
            if (chinese)
            {
                inChinese = line;
            }
            else
            {
                inEnglish = line;
            }
        }

        Strings.PrefersChinese = true;
        Check("the too-small state publishes the notice in both languages",
            inChinese is { Length: > 0 } && inEnglish is { Length: > 0 }
            && inChinese != "board.tooSmall" && inEnglish != "board.tooSmall"
            && inChinese != inEnglish);
        Check("and a drawn board publishes none", atTheFloor.Notice is null);
    }

    /// <summary>
    /// A legal move, captures first, with a fixed seed among equals so the game
    /// is the same game every run. Preferring captures is what makes one played
    /// game reach every voice rather than most of them.
    /// </summary>
    private static Move? Preferring(PlaySession play, Random rng)
    {
        List<string> legal = [.. play.LegalMoves()];
        legal.Sort(StringComparer.Ordinal);
        if (legal.Count == 0)
        {
            return null;
        }

        List<Move> captures = [.. legal
            .Select(Move.Parse)
            .Where(move => move is { } candidate && play.Scene.Placement[candidate.To] is not null)
            .Select(move => move!.Value)];

        return captures.Count > 0
            ? captures[rng.Next(captures.Count)]
            : Move.Parse(legal[rng.Next(legal.Count)]);
    }

    /// <summary>The file's members, in the order they are written.</summary>
    private static string[] Keys(string path)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(File.ReadAllText(path));
            return [.. document.RootElement.EnumerateObject().Select(member => member.Name)];
        }
        catch (Exception failure) when (failure is IOException or JsonException)
        {
            return [];
        }
    }

    /// <summary>The raw JSON text stored under one key, or null where there is none.</summary>
    private static string? Stored(string path, string key)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(File.ReadAllText(path));
            return document.RootElement.TryGetProperty(key, out JsonElement value)
                ? value.GetRawText()
                : null;
        }
        catch (Exception failure) when (failure is IOException or JsonException)
        {
            return null;
        }
    }

    /// <summary>Answers whether <paramref name="work"/> ran without raising.</summary>
    private static bool Silently(Action work)
    {
        try
        {
            work();
            return true;
        }
        catch (Exception)
        {
            return false;
        }
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
