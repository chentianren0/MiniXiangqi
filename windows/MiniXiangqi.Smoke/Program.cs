// The headless smoke harness for the Windows core interface.
//
// It is the proof docs/core-interface.md's Windows consumer paragraph asks for:
// the ClangSharp-generated declarations, called against the real mxqcore.dll,
// exercising every shape the boundary has — fixed-capacity char arrays,
// size_t as nuint, the two-call buffer protocol, the error taxonomy, a blob,
// an array of value structs, and an [UnmanagedCallersOnly] callback delivered
// on the core's own engine thread.
//
// It deliberately calls the generated declarations directly rather than the
// wrapper types beside them. A wrapper proves the wrapper; this proves the ABI.

using System.Diagnostics;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;

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
        MxqCall.Check(Mxq.mxq_game_legal_moves(game, null, 0, &count, &err), in err, "legal-move count");
        Console.WriteLine($"    count-only call     {count} moves");

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
        MxqCall.Check(Mxq.mxq_game_move_history(game, null, 0, &count, &err), in err, "history count");
        Console.WriteLine($"    move history        {count} ply");
        Check("the retained line holds the one move", count == 1);

        Section("9. The error taxonomy across the boundary");
        ExpectRefusal(game, "zzzz", Mxq.MXQ_ERR_RULES_MALFORMED_MOVE);
        ExpectRefusal(game, moveText[0], Mxq.MXQ_ERR_RULES_ILLEGAL_MOVE);

        Section("10. mxq_engine_prepare");
        MxqEnginePlan applied = default;
        applied.struct_size = (uint)sizeof(MxqEnginePlan);
        err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_engine_prepare(core.Handle, &budget, &applied, &err),
            in err,
            nameof(Mxq.mxq_engine_prepare));
        Console.WriteLine($"    applied threads     {applied.threads}");
        Console.WriteLine($"    applied hash        {applied.hash_mib} MiB");

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
