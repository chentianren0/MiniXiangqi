using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Core;

/// <summary>
/// A live core instance: <c>mxq_core_init</c> at construction,
/// <c>mxq_core_shutdown</c> at disposal.
///
/// Handle-shaped but singleton-enforced, as the C interface is — a second
/// <c>mxq_core_init</c> before shutdown returns
/// <c>MXQ_ERR_STATE_ALREADY_INITIALIZED</c>, because the embedded engine's
/// process-global state admits one instance.
/// </summary>
public sealed unsafe class MiniXiangqiCore : IDisposable
{
    private MxqCore* _core;

    private MiniXiangqiCore(MxqCore* core)
    {
        _core = core;
    }

    /// <summary>
    /// The four version axes. Callable before any core exists, as the C
    /// interface makes it.
    /// </summary>
    public static CoreVersion Version
    {
        get
        {
            MxqVersion version = default;
            version.struct_size = (uint)sizeof(MxqVersion);
            MxqError err = MxqCall.Error();
            MxqCall.Check(Mxq.mxq_core_version(&version, &err), in err, nameof(Mxq.mxq_core_version));

            return new CoreVersion(
                version.api_major,
                version.api_minor,
                version.api_patch,
                version.archive_version_current,
                version.archive_version_min_readable,
                version.store_schema_version,
                Utf8.Read(version.core_revision),
                Utf8.Read(version.fork_revision),
                Utf8.Read(version.variant_id),
                Utf8.Read(version.nnue_sha256));
        }
    }

    /// <summary>
    /// The frozen starting FEN. A constant of the ruleset rather than of any
    /// core instance, so this too is callable before initialisation.
    /// </summary>
    public static string StartFen
    {
        get
        {
            sbyte* buffer = stackalloc sbyte[Mxq.MXQ_FEN_CAP];
            nuint length;
            MxqError err = MxqCall.Error();
            MxqCall.Check(
                Mxq.mxq_rules_start_fen(buffer, (nuint)Mxq.MXQ_FEN_CAP, &length, &err),
                in err,
                nameof(Mxq.mxq_rules_start_fen));
            return Utf8.Read(new ReadOnlySpan<sbyte>(buffer, (int)length));
        }
    }

    /// <summary>
    /// The plan for a probe, without an engine and without a core. A pure
    /// function, so every budget boundary is answerable before anything is
    /// initialised.
    /// </summary>
    public static EnginePlan PlanFor(MxqEngineBudget budget)
    {
        MxqEnginePlan plan = default;
        plan.struct_size = (uint)sizeof(MxqEnginePlan);
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_engine_plan(&budget, &plan, &err), in err, nameof(Mxq.mxq_engine_plan));
        return Describe(plan);
    }

    /// <summary>
    /// Initialise the core and open the store. Both directories are supplied by
    /// the frontend; the core never derives a platform path.
    /// </summary>
    public static MiniXiangqiCore Start(string storeDirectory, string assetDirectory)
    {
        byte[] store = Utf8.Encode(storeDirectory);
        byte[] assets = Utf8.Encode(assetDirectory);

        fixed (byte* storePtr = store)
        fixed (byte* assetPtr = assets)
        {
            MxqCoreConfig config = default;
            config.struct_size = (uint)sizeof(MxqCoreConfig);
            config.api_major = (uint)Mxq.MXQ_API_VERSION_MAJOR;
            config.api_minor = (uint)Mxq.MXQ_API_VERSION_MINOR;
            config.api_patch = (uint)Mxq.MXQ_API_VERSION_PATCH;
            config.flags = Mxq.MXQ_CORE_FLAG_NONE;
            config.store_directory = (sbyte*)storePtr;
            config.asset_directory = (sbyte*)assetPtr;

            MxqCore* core;
            MxqError err = MxqCall.Error();
            MxqCall.Check(Mxq.mxq_core_init(&config, &core, &err), in err, nameof(Mxq.mxq_core_init));
            return new MiniXiangqiCore(core);
        }
    }

    /// <summary>
    /// Resume the single active game, or create one with the supplied frozen
    /// configuration when there is none. A <c>MXQ_FIRST_MOVER_RANDOM</c> choice
    /// is resolved into <paramref name="humanSide"/> before this call, because
    /// only successful creation commits a resolved side.
    /// </summary>
    public GameSession ResumeOrCreate(
        int humanSide,
        int aiLevel,
        int firstMoverChoice,
        uint movetimeMs,
        int mode = Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI)
    {
        return ResumeActive() ?? Create(mode, humanSide, aiLevel, firstMoverChoice, movetimeMs);
    }

    /// <summary>
    /// The single active game, or null when there is none. Its own session:
    /// resuming twice while the first is live is
    /// <c>MXQ_ERR_ARG_CONCURRENT_USE</c> by contract.
    /// </summary>
    public GameSession? ResumeActive()
    {
        MxqGame* game;
        byte exists;
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_game_resume_active(Live, &game, &exists, &err),
            in err,
            nameof(Mxq.mxq_game_resume_active));
        return exists != 0 ? new GameSession(game) : null;
    }

    /// <summary>
    /// Apply the plan for a fresh probe: threads, Hash, the pinned variant
    /// configuration, and the NNUE.
    /// </summary>
    public EnginePlan PrepareEngine(MxqEngineBudget budget)
    {
        MxqEnginePlan applied = default;
        applied.struct_size = (uint)sizeof(MxqEnginePlan);
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_engine_prepare(Live, &budget, &applied, &err),
            in err,
            nameof(Mxq.mxq_engine_prepare));
        return Describe(applied);
    }

    /// <summary>
    /// Release the engine's resources. Refuses with
    /// <c>MXQ_ERR_STATE_SEARCH_IN_PROGRESS</c> rather than stalling if a search
    /// is outstanding, so the caller cancels first.
    /// </summary>
    public void TeardownEngine()
    {
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_engine_teardown(Live, &err), in err, nameof(Mxq.mxq_engine_teardown));
    }

    /// <summary>
    /// Whether the engine is prepared, and which build answered — the profile
    /// identifier a saved diagnostic has to be able to name.
    /// </summary>
    public (int State, string Profile) Engine
    {
        get
        {
            int state;
            sbyte* buffer = stackalloc sbyte[Mxq.MXQ_PROFILE_ID_CAP];
            nuint length;
            MxqError err = MxqCall.Error();
            MxqCall.Check(
                Mxq.mxq_engine_query(Live, &state, buffer, (nuint)Mxq.MXQ_PROFILE_ID_CAP, &length, &err),
                in err,
                nameof(Mxq.mxq_engine_query));
            return (state, Utf8.Read(new ReadOnlySpan<sbyte>(buffer, (int)length)));
        }
    }

    /// <summary>
    /// Create a game with the supplied frozen configuration. A
    /// <c>MXQ_FIRST_MOVER_RANDOM</c> choice is resolved into
    /// <paramref name="humanSide"/> before this call, because only successful
    /// creation commits a resolved side.
    /// </summary>
    public GameSession Create(int mode, int humanSide, int aiLevel, int firstMoverChoice, uint movetimeMs)
    {
        MxqGameConfig config = default;
        config.struct_size = (uint)sizeof(MxqGameConfig);
        config.mode = mode;
        config.human_side = humanSide;
        config.ai_level = aiLevel;
        config.first_mover_choice = firstMoverChoice;
        config.ai_movetime_ms = movetimeMs;

        MxqGame* game;
        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_game_create(Live, &config, &game, &err), in err, nameof(Mxq.mxq_game_create));
        return new GameSession(game);
    }

    /// <summary>
    /// Archive the active game according to its factual current state and clear
    /// the active-game reference, atomically. Outside the UI-thread exception
    /// the active game's own calls enjoy: this one stays off it.
    /// </summary>
    public ulong ArchiveAndClear(GameSession game)
    {
        ulong record;
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_store_archive_and_clear(Live, game.Handle, &record, &err),
            in err,
            nameof(Mxq.mxq_store_archive_and_clear));
        return record;
    }

    /// <summary>The raw handle, for the calls this wrapper does not cover.</summary>
    public MxqCore* Handle => Live;

    /// <summary>
    /// Deterministic teardown: cancel all work, join the engine thread, close
    /// the store, and invalidate every outstanding handle.
    /// </summary>
    public void Dispose()
    {
        if (_core is null)
        {
            return;
        }

        MxqCore* core = _core;
        _core = null;

        MxqError err = MxqCall.Error();
        MxqCall.Check(Mxq.mxq_core_shutdown(core, &err), in err, nameof(Mxq.mxq_core_shutdown));
    }

    private MxqCore* Live =>
        _core is null ? throw new ObjectDisposedException(nameof(MiniXiangqiCore)) : _core;

    private static EnginePlan Describe(MxqEnginePlan plan)
    {
        return new EnginePlan(
            plan.threads,
            plan.hash_mib,
            plan.sufficient != 0,
            plan.reserve_bytes,
            plan.usable_bytes,
            plan.budget_bytes);
    }
}
