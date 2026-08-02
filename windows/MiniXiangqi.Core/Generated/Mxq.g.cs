using System;
using System.CodeDom.Compiler;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

[assembly: GeneratedCode("ClangSharp", "21.1.8.4")]
[assembly: DisableRuntimeMarshalling]

namespace MiniXiangqi.Core.Interop;

public partial struct MxqCore
{
}

public partial struct MxqGame
{
}

public partial struct MxqBlob
{
}

public partial struct MxqError
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("MxqStatus")]
    public int status;

    [NativeTypeName("int32_t")]
    public int subsystem_code;

    [NativeTypeName("uint32_t")]
    public uint reserved0;

    [NativeTypeName("uint64_t")]
    public ulong required_size;

    [NativeTypeName("uint64_t")]
    public ulong detail_index;

    [NativeTypeName("char[128]")]
    public _detail_e__FixedBuffer detail;

    [InlineArray(128)]
    public partial struct _detail_e__FixedBuffer
    {
        public sbyte e0;
    }
}

public partial struct MxqVersion
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("uint32_t")]
    public uint api_major;

    [NativeTypeName("uint32_t")]
    public uint api_minor;

    [NativeTypeName("uint32_t")]
    public uint api_patch;

    [NativeTypeName("uint32_t")]
    public uint archive_version_current;

    [NativeTypeName("uint32_t")]
    public uint archive_version_min_readable;

    [NativeTypeName("uint32_t")]
    public uint store_schema_version;

    [NativeTypeName("uint32_t")]
    public uint reserved0;

    [NativeTypeName("char[48]")]
    public _core_revision_e__FixedBuffer core_revision;

    [NativeTypeName("char[48]")]
    public _fork_revision_e__FixedBuffer fork_revision;

    [InlineArray(48)]
    public partial struct _core_revision_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(48)]
    public partial struct _fork_revision_e__FixedBuffer
    {
        public sbyte e0;
    }
}

public partial struct MxqGameProfile
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("MxqGameKind")]
    public int game;

    [NativeTypeName("char[32]")]
    public _variant_id_e__FixedBuffer variant_id;

    [NativeTypeName("char[72]")]
    public _nnue_sha256_e__FixedBuffer nnue_sha256;

    [InlineArray(32)]
    public partial struct _variant_id_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(72)]
    public partial struct _nnue_sha256_e__FixedBuffer
    {
        public sbyte e0;
    }
}

public unsafe partial struct MxqCoreConfig
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("uint32_t")]
    public uint api_major;

    [NativeTypeName("uint32_t")]
    public uint api_minor;

    [NativeTypeName("uint32_t")]
    public uint api_patch;

    [NativeTypeName("uint32_t")]
    public uint flags;

    [NativeTypeName("uint32_t")]
    public uint reserved0;

    [NativeTypeName("const char *")]
    public sbyte* store_directory;

    [NativeTypeName("const char *")]
    public sbyte* asset_directory;
}

public partial struct MxqMove
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("char[8]")]
    public _text_e__FixedBuffer text;

    [InlineArray(8)]
    public partial struct _text_e__FixedBuffer
    {
        public sbyte e0;
    }
}

public partial struct MxqPosition
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("uint32_t")]
    public uint ply_count;

    [NativeTypeName("uint64_t")]
    public ulong position_revision;

    [NativeTypeName("MxqColor")]
    public int side_to_move;

    [NativeTypeName("uint8_t")]
    public byte in_check;

    [NativeTypeName("uint8_t[3]")]
    public _reserved0_e__FixedBuffer reserved0;

    [NativeTypeName("char[96]")]
    public _fen_e__FixedBuffer fen;

    [InlineArray(3)]
    public partial struct _reserved0_e__FixedBuffer
    {
        public byte e0;
    }

    [InlineArray(96)]
    public partial struct _fen_e__FixedBuffer
    {
        public sbyte e0;
    }
}

public partial struct MxqGameStatus
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("MxqGameState")]
    public int state;

    [NativeTypeName("MxqEndReason")]
    public int reason;

    [NativeTypeName("uint32_t")]
    public uint at_occurrence;

    [NativeTypeName("uint32_t")]
    public uint undo_plies;

    [NativeTypeName("uint8_t")]
    public byte claim_available;

    [NativeTypeName("uint8_t")]
    public byte undo_available;

    [NativeTypeName("uint8_t")]
    public byte resign_available;

    [NativeTypeName("uint8_t")]
    public byte search_expected;
}

public partial struct MxqGameConfig
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("MxqPlayMode")]
    public int mode;

    [NativeTypeName("MxqColor")]
    public int human_side;

    [NativeTypeName("MxqAiLevel")]
    public int ai_level;

    [NativeTypeName("MxqFirstMoverChoice")]
    public int first_mover_choice;

    [NativeTypeName("uint32_t")]
    public uint ai_movetime_ms;

    [NativeTypeName("MxqGameKind")]
    public int game;
}

public partial struct MxqRecordSummary
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("uint32_t")]
    public uint move_count;

    [NativeTypeName("uint64_t")]
    public ulong record_id;

    [NativeTypeName("int64_t")]
    public long started_at_ms;

    [NativeTypeName("int64_t")]
    public long ended_at_ms;

    [NativeTypeName("int64_t")]
    public long added_at_ms;

    [NativeTypeName("MxqPlayMode")]
    public int mode;

    [NativeTypeName("MxqColor")]
    public int human_side;

    [NativeTypeName("MxqAiLevel")]
    public int ai_level;

    [NativeTypeName("uint32_t")]
    public uint ai_movetime_ms;

    [NativeTypeName("MxqOutcome")]
    public int outcome;

    [NativeTypeName("MxqEndReason")]
    public int end_reason;

    [NativeTypeName("MxqProvenance")]
    public int provenance;

    [NativeTypeName("uint8_t")]
    public byte pinned;

    [NativeTypeName("uint8_t")]
    public byte is_active;

    [NativeTypeName("uint8_t[2]")]
    public _reserved0_e__FixedBuffer reserved0;

    [NativeTypeName("char[40]")]
    public _game_id_e__FixedBuffer game_id;

    [NativeTypeName("MxqGameKind")]
    public int game;

    [NativeTypeName("uint32_t")]
    public uint reserved1;

    [InlineArray(2)]
    public partial struct _reserved0_e__FixedBuffer
    {
        public byte e0;
    }

    [InlineArray(40)]
    public partial struct _game_id_e__FixedBuffer
    {
        public sbyte e0;
    }
}

public partial struct MxqArchiveInfo
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("uint32_t")]
    public uint archive_version;

    [NativeTypeName("uint32_t")]
    public uint move_count;

    [NativeTypeName("MxqPlayMode")]
    public int mode;

    [NativeTypeName("MxqColor")]
    public int human_side;

    [NativeTypeName("MxqOutcome")]
    public int outcome;

    [NativeTypeName("MxqEndReason")]
    public int end_reason;

    [NativeTypeName("MxqGameKind")]
    public int game;

    [NativeTypeName("int64_t")]
    public long started_at_ms;

    [NativeTypeName("int64_t")]
    public long ended_at_ms;

    [NativeTypeName("char[40]")]
    public _game_id_e__FixedBuffer game_id;

    [InlineArray(40)]
    public partial struct _game_id_e__FixedBuffer
    {
        public sbyte e0;
    }
}

public partial struct MxqEngineBudget
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("uint32_t")]
    public uint active_processor_count;

    [NativeTypeName("uint64_t")]
    public ulong available_bytes;

    [NativeTypeName("uint64_t")]
    public ulong physical_bytes;
}

public partial struct MxqEnginePlan
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("uint32_t")]
    public uint threads;

    [NativeTypeName("uint32_t")]
    public uint hash_mib;

    [NativeTypeName("uint8_t")]
    public byte sufficient;

    [NativeTypeName("uint8_t[3]")]
    public _reserved0_e__FixedBuffer reserved0;

    [NativeTypeName("uint64_t")]
    public ulong reserve_bytes;

    [NativeTypeName("uint64_t")]
    public ulong usable_bytes;

    [NativeTypeName("uint64_t")]
    public ulong budget_bytes;

    [InlineArray(3)]
    public partial struct _reserved0_e__FixedBuffer
    {
        public byte e0;
    }
}

public partial struct MxqSearchRequest
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("uint32_t")]
    public uint movetime_ms;
}

public partial struct MxqSearchResult
{
    [NativeTypeName("uint32_t")]
    public uint struct_size;

    [NativeTypeName("MxqSearchOutcome")]
    public int outcome;

    [NativeTypeName("uint64_t")]
    public ulong ticket;

    [NativeTypeName("uint64_t")]
    public ulong position_revision;

    [NativeTypeName("uint64_t")]
    public ulong nodes;

    [NativeTypeName("int32_t")]
    public int score_cp;

    [NativeTypeName("uint32_t")]
    public uint depth;

    [NativeTypeName("uint32_t")]
    public uint elapsed_ms;

    [NativeTypeName("MxqStatus")]
    public int status;

    public MxqMove move;

    [NativeTypeName("char[40]")]
    public _game_id_e__FixedBuffer game_id;

    [NativeTypeName("char[64]")]
    public _profile_id_e__FixedBuffer profile_id;

    [NativeTypeName("uint32_t")]
    public uint reserved0;

    [InlineArray(40)]
    public partial struct _game_id_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(64)]
    public partial struct _profile_id_e__FixedBuffer
    {
        public sbyte e0;
    }
}

public static unsafe partial class Mxq
{
    public const int MXQ_OK = 0;
    public const int MXQ_DOMAIN_OK = 0;
    public const int MXQ_DOMAIN_ARGUMENT = 1000;
    public const int MXQ_DOMAIN_STATE = 2000;
    public const int MXQ_DOMAIN_RULES = 3000;
    public const int MXQ_DOMAIN_STORE = 4000;
    public const int MXQ_DOMAIN_ARCHIVE = 5000;
    public const int MXQ_DOMAIN_ENGINE = 6000;
    public const int MXQ_DOMAIN_RESOURCE = 7000;
    public const int MXQ_DOMAIN_INTERNAL = 9000;
    public const int MXQ_ERR_ARG_NULL = 1001;
    public const int MXQ_ERR_ARG_INVALID_HANDLE = 1002;
    public const int MXQ_ERR_ARG_STRUCT_SIZE = 1003;
    public const int MXQ_ERR_ARG_API_VERSION = 1004;
    public const int MXQ_ERR_ARG_BUFFER_TOO_SMALL = 1005;
    public const int MXQ_ERR_ARG_ENCODING = 1006;
    public const int MXQ_ERR_ARG_RANGE = 1007;
    public const int MXQ_ERR_ARG_WRONG_THREAD = 1008;
    public const int MXQ_ERR_ARG_CONCURRENT_USE = 1009;
    public const int MXQ_ERR_ARG_REENTRANT = 1010;
    public const int MXQ_ERR_STATE_NOT_INITIALIZED = 2001;
    public const int MXQ_ERR_STATE_ALREADY_INITIALIZED = 2002;
    public const int MXQ_ERR_STATE_SHUTTING_DOWN = 2003;
    public const int MXQ_ERR_STATE_ACTIVE_GAME_EXISTS = 2004;
    public const int MXQ_ERR_STATE_ACTIVE_GAME_MISSING = 2005;
    public const int MXQ_ERR_STATE_SESSION_READ_ONLY = 2006;
    public const int MXQ_ERR_STATE_SESSION_ARCHIVED = 2007;
    public const int MXQ_ERR_STATE_GAME_OVER = 2008;
    public const int MXQ_ERR_STATE_UNDO_UNAVAILABLE = 2009;
    public const int MXQ_ERR_STATE_CLAIM_UNAVAILABLE = 2010;
    public const int MXQ_ERR_STATE_RESIGN_UNAVAILABLE = 2011;
    public const int MXQ_ERR_STATE_CONFIRM_UNAVAILABLE = 2014;
    public const int MXQ_ERR_STATE_SEARCH_IN_PROGRESS = 2012;
    public const int MXQ_ERR_STATE_ENGINE_NOT_READY = 2013;
    public const int MXQ_ERR_RULES_MALFORMED_MOVE = 3001;
    public const int MXQ_ERR_RULES_ILLEGAL_MOVE = 3002;
    public const int MXQ_ERR_RULES_INVALID_FEN = 3003;
    public const int MXQ_ERR_RULES_ILLEGAL_POSITION = 3004;
    public const int MXQ_ERR_RULES_INVALID_HISTORY = 3005;
    public const int MXQ_ERR_STORE_IO = 4001;
    public const int MXQ_ERR_STORE_CORRUPT = 4002;
    public const int MXQ_ERR_STORE_BUSY = 4003;
    public const int MXQ_ERR_STORE_FULL = 4004;
    public const int MXQ_ERR_STORE_NOT_FOUND = 4005;
    public const int MXQ_ERR_STORE_IDENTITY_CONFLICT = 4006;
    public const int MXQ_ERR_STORE_MIGRATION_FAILED = 4007;
    public const int MXQ_ERR_STORE_SCHEMA_TOO_NEW = 4008;
    public const int MXQ_ERR_ARCHIVE_MALFORMED = 5001;
    public const int MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION = 5002;
    public const int MXQ_ERR_ARCHIVE_TOO_LARGE = 5003;
    public const int MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY = 5004;
    public const int MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH = 5005;
    public const int MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY = 6001;
    public const int MXQ_ERR_ENGINE_ASSET_MISSING = 6002;
    public const int MXQ_ERR_ENGINE_ASSET_MISMATCH = 6003;
    public const int MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED = 6004;
    public const int MXQ_ERR_ENGINE_HASH_ALLOCATION_FAILED = 6005;
    public const int MXQ_ERR_ENGINE_NO_MOVE = 6006;
    public const int MXQ_ERR_ENGINE_ILLEGAL_RESULT = 6007;
    public const int MXQ_ERR_ENGINE_FAULTED = 6008;
    public const int MXQ_ERR_ENGINE_NOT_PREPARED = 6009;
    public const int MXQ_ERR_RESOURCE_ALLOCATION_FAILED = 7001;
    public const int MXQ_ERR_RESOURCE_LIMIT_EXCEEDED = 7002;
    public const int MXQ_ERR_INTERNAL_INVARIANT = 9001;

    public const int MXQ_COLOR_NONE = -1;
    public const int MXQ_COLOR_RED = 0;
    public const int MXQ_COLOR_BLACK = 1;

    public const int MXQ_PLAY_MODE_HUMAN_VS_AI = 0;
    public const int MXQ_PLAY_MODE_FREE_PLAY = 1;

    public const int MXQ_GAME_KIND_MINI_XIANGQI = 0;
    public const int MXQ_GAME_KIND_XIANGQI = 1;

    public const int MXQ_AI_LEVEL_NONE = -1;
    public const int MXQ_AI_LEVEL_FAST = 0;
    public const int MXQ_AI_LEVEL_STANDARD = 1;
    public const int MXQ_AI_LEVEL_DEEP = 2;

    public const int MXQ_FIRST_MOVER_NONE = -1;
    public const int MXQ_FIRST_MOVER_HUMAN_FIRST = 0;
    public const int MXQ_FIRST_MOVER_AI_FIRST = 1;
    public const int MXQ_FIRST_MOVER_RANDOM = 2;

    public const int MXQ_GAME_ONGOING = 0;
    public const int MXQ_GAME_CLAIMABLE_DRAW = 1;
    public const int MXQ_GAME_RED_WINS = 2;
    public const int MXQ_GAME_BLACK_WINS = 3;
    public const int MXQ_GAME_DRAW = 4;

    public const int MXQ_OUTCOME_NONE = 0;
    public const int MXQ_OUTCOME_RED_WINS = 1;
    public const int MXQ_OUTCOME_BLACK_WINS = 2;
    public const int MXQ_OUTCOME_DRAW = 3;

    public const int MXQ_END_REASON_NONE = 0;
    public const int MXQ_END_REASON_CHECKMATE = 1;
    public const int MXQ_END_REASON_STALEMATE = 2;
    public const int MXQ_END_REASON_THREEFOLD_REPETITION = 3;
    public const int MXQ_END_REASON_PERPETUAL_CHECK = 4;
    public const int MXQ_END_REASON_PERPETUAL_CHASE = 5;
    public const int MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK = 6;
    public const int MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE = 7;
    public const int MXQ_END_REASON_RESIGNATION = 8;
    public const int MXQ_END_REASON_ENDED_EARLY = 9;
    public const int MXQ_END_REASON_FIFTY_MOVE_RULE = 10;

    public const int MXQ_PROVENANCE_LOCALLY_PLAYED = 0;
    public const int MXQ_PROVENANCE_IMPORTED = 1;
    public const int MXQ_PROVENANCE_DERIVED = 2;

    public const int MXQ_IMPORT_CREATED = 0;
    public const int MXQ_IMPORT_EXISTING = 1;

    public const int MXQ_ENGINE_STATE_UNINITIALIZED = 0;
    public const int MXQ_ENGINE_STATE_READY = 1;
    public const int MXQ_ENGINE_STATE_FAULTED = 2;

    public const int MXQ_SEARCH_MOVE = 0;
    public const int MXQ_SEARCH_CANCELLED = 1;
    public const int MXQ_SEARCH_STALE = 2;
    public const int MXQ_SEARCH_MALFORMED = 3;
    public const int MXQ_SEARCH_ILLEGAL = 4;
    public const int MXQ_SEARCH_FAILED = 5;

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_status_domain([NativeTypeName("MxqStatus")] int status);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("const char *")]
    public static extern sbyte* mxq_status_name([NativeTypeName("MxqStatus")] int status);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("const uint8_t *")]
    public static extern byte* mxq_blob_bytes([NativeTypeName("const MxqBlob *")] MxqBlob* blob);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("size_t")]
    public static extern nuint mxq_blob_len([NativeTypeName("const MxqBlob *")] MxqBlob* blob);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    public static extern void mxq_blob_release(MxqBlob* blob);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_core_version(MxqVersion* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_core_game_profile([NativeTypeName("MxqGameKind")] int game, MxqGameProfile* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_core_init([NativeTypeName("const MxqCoreConfig *")] MxqCoreConfig* config, MxqCore** out_core, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_core_cancel_all(MxqCore* core, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_core_shutdown(MxqCore* core, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_create(MxqCore* core, [NativeTypeName("const MxqGameConfig *")] MxqGameConfig* config, MxqGame** out_game, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_resume_active(MxqCore* core, MxqGame** out_game, [NativeTypeName("uint8_t *")] byte* out_exists, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_open_archive(MxqCore* core, [NativeTypeName("const uint8_t *")] byte* bytes, [NativeTypeName("size_t")] nuint len, MxqGame** out_game, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    public static extern void mxq_game_release(MxqGame* game);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_id([NativeTypeName("const MxqGame *")] MxqGame* game, [NativeTypeName("char *")] sbyte* @out, [NativeTypeName("size_t")] nuint cap, [NativeTypeName("size_t *")] nuint* out_len, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_position([NativeTypeName("const MxqGame *")] MxqGame* game, MxqPosition* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_status([NativeTypeName("const MxqGame *")] MxqGame* game, MxqGameStatus* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_config([NativeTypeName("const MxqGame *")] MxqGame* game, MxqGameConfig* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_legal_moves([NativeTypeName("const MxqGame *")] MxqGame* game, MxqMove* @out, [NativeTypeName("size_t")] nuint cap, [NativeTypeName("size_t *")] nuint* out_count, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_legal_moves_from([NativeTypeName("const MxqGame *")] MxqGame* game, [NativeTypeName("const char *")] sbyte* from_square, MxqMove* @out, [NativeTypeName("size_t")] nuint cap, [NativeTypeName("size_t *")] nuint* out_count, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_move_history([NativeTypeName("const MxqGame *")] MxqGame* game, MxqMove* @out, [NativeTypeName("size_t")] nuint cap, [NativeTypeName("size_t *")] nuint* out_count, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_position_at([NativeTypeName("const MxqGame *")] MxqGame* game, [NativeTypeName("uint32_t")] uint ply, MxqPosition* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_apply_move(MxqGame* game, [NativeTypeName("const char *")] sbyte* move, MxqPosition* out_after, MxqGameStatus* out_status, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_undo(MxqGame* game, [NativeTypeName("uint32_t *")] uint* out_plies_removed, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_claim_draw(MxqGame* game, [NativeTypeName("uint64_t *")] ulong* out_record_id, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_resign(MxqGame* game, [NativeTypeName("uint64_t *")] ulong* out_record_id, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_game_confirm_result(MxqGame* game, [NativeTypeName("uint64_t *")] ulong* out_record_id, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_rules_start_fen([NativeTypeName("MxqGameKind")] int game, [NativeTypeName("char *")] sbyte* @out, [NativeTypeName("size_t")] nuint cap, [NativeTypeName("size_t *")] nuint* out_len, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_rules_validate_fen(MxqCore* core, [NativeTypeName("MxqGameKind")] int game, [NativeTypeName("const char *")] sbyte* fen, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_rules_evaluate(MxqCore* core, [NativeTypeName("MxqGameKind")] int game, [NativeTypeName("const char *")] sbyte* start_fen, [NativeTypeName("const char *const *")] sbyte** moves, [NativeTypeName("size_t")] nuint move_count, MxqPosition* out_position, MxqGameStatus* out_status, [NativeTypeName("size_t *")] nuint* out_first_illegal_index, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_rules_legal_moves(MxqCore* core, [NativeTypeName("MxqGameKind")] int game, [NativeTypeName("const char *")] sbyte* start_fen, [NativeTypeName("const char *const *")] sbyte** moves, [NativeTypeName("size_t")] nuint move_count, MxqMove* @out, [NativeTypeName("size_t")] nuint cap, [NativeTypeName("size_t *")] nuint* out_count, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_engine_plan([NativeTypeName("const MxqEngineBudget *")] MxqEngineBudget* budget, MxqEnginePlan* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_engine_prepare(MxqCore* core, [NativeTypeName("MxqGameKind")] int game, [NativeTypeName("const MxqEngineBudget *")] MxqEngineBudget* budget, MxqEnginePlan* out_applied, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_engine_teardown(MxqCore* core, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_engine_query(MxqCore* core, [NativeTypeName("MxqEngineState *")] int* out_state, [NativeTypeName("char *")] sbyte* out_profile_id, [NativeTypeName("size_t")] nuint cap, [NativeTypeName("size_t *")] nuint* out_len, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_search_start(MxqCore* core, [NativeTypeName("const MxqGame *")] MxqGame* game, [NativeTypeName("const MxqSearchRequest *")] MxqSearchRequest* request, [NativeTypeName("MxqSearchCallback")] delegate* unmanaged[Cdecl]<MxqSearchResult*, void*, void> callback, void* user_data, [NativeTypeName("uint64_t *")] ulong* out_ticket, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_search_cancel(MxqCore* core, [NativeTypeName("uint64_t")] ulong ticket, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_search_cancel_all(MxqCore* core, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_search_poll(MxqCore* core, [NativeTypeName("uint64_t")] ulong ticket, MxqSearchResult* @out, [NativeTypeName("uint8_t *")] byte* out_ready, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_search_wait(MxqCore* core, [NativeTypeName("uint64_t")] ulong ticket, [NativeTypeName("uint32_t")] uint timeout_ms, MxqSearchResult* @out, [NativeTypeName("uint8_t *")] byte* out_ready, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_archive_probe(MxqCore* core, [NativeTypeName("const uint8_t *")] byte* bytes, [NativeTypeName("size_t")] nuint len, MxqArchiveInfo* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_archive_validate(MxqCore* core, [NativeTypeName("const uint8_t *")] byte* bytes, [NativeTypeName("size_t")] nuint len, MxqArchiveInfo* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_archive_encode(MxqCore* core, [NativeTypeName("const MxqGame *")] MxqGame* game, MxqBlob** out_blob, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_archive_supported_versions([NativeTypeName("uint32_t *")] uint* out_min_readable, [NativeTypeName("uint32_t *")] uint* out_current, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_active_exists(MxqCore* core, [NativeTypeName("uint8_t *")] byte* out_exists, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_active_summary(MxqCore* core, MxqRecordSummary* @out, MxqGameStatus* out_status, [NativeTypeName("uint8_t *")] byte* out_exists, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_archive_and_clear(MxqCore* core, MxqGame* active, [NativeTypeName("uint64_t *")] ulong* out_record_id, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_history_count(MxqCore* core, [NativeTypeName("uint32_t *")] uint* out_count, [NativeTypeName("uint64_t *")] ulong* out_library_revision, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_history_page(MxqCore* core, [NativeTypeName("uint32_t")] uint offset, [NativeTypeName("uint32_t")] uint limit, MxqRecordSummary* @out, [NativeTypeName("size_t")] nuint cap, [NativeTypeName("size_t *")] nuint* out_count, [NativeTypeName("uint64_t *")] ulong* out_library_revision, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_history_get(MxqCore* core, [NativeTypeName("uint64_t")] ulong record_id, MxqRecordSummary* @out, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_history_open(MxqCore* core, [NativeTypeName("uint64_t")] ulong record_id, MxqGame** out_replay, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_history_set_pinned(MxqCore* core, [NativeTypeName("uint64_t")] ulong record_id, [NativeTypeName("uint8_t")] byte pinned, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_history_delete(MxqCore* core, [NativeTypeName("uint64_t")] ulong record_id, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_export(MxqCore* core, [NativeTypeName("uint64_t")] ulong record_id, MxqBlob** out_blob, MxqError* err);

    [DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    [return: NativeTypeName("MxqStatus")]
    public static extern int mxq_store_import(MxqCore* core, [NativeTypeName("const uint8_t *")] byte* bytes, [NativeTypeName("size_t")] nuint len, [NativeTypeName("MxqImportOutcome *")] int* out_outcome, [NativeTypeName("uint64_t *")] ulong* out_record_id, MxqRecordSummary* out_summary, MxqError* err);

    [NativeTypeName("#define MXQ_API_VERSION_MAJOR 2")]
    public const int MXQ_API_VERSION_MAJOR = 2;

    [NativeTypeName("#define MXQ_API_VERSION_MINOR 0")]
    public const int MXQ_API_VERSION_MINOR = 0;

    [NativeTypeName("#define MXQ_API_VERSION_PATCH 0")]
    public const int MXQ_API_VERSION_PATCH = 0;

    [NativeTypeName("#define MXQ_MOVE_TEXT_CAP 8")]
    public const int MXQ_MOVE_TEXT_CAP = 8;

    [NativeTypeName("#define MXQ_FEN_CAP 96")]
    public const int MXQ_FEN_CAP = 96;

    [NativeTypeName("#define MXQ_DETAIL_CAP 128")]
    public const int MXQ_DETAIL_CAP = 128;

    [NativeTypeName("#define MXQ_GAME_ID_CAP 40")]
    public const int MXQ_GAME_ID_CAP = 40;

    [NativeTypeName("#define MXQ_SHA256_HEX_CAP 72")]
    public const int MXQ_SHA256_HEX_CAP = 72;

    [NativeTypeName("#define MXQ_REVISION_CAP 48")]
    public const int MXQ_REVISION_CAP = 48;

    [NativeTypeName("#define MXQ_VARIANT_ID_CAP 32")]
    public const int MXQ_VARIANT_ID_CAP = 32;

    [NativeTypeName("#define MXQ_PROFILE_ID_CAP 64")]
    public const int MXQ_PROFILE_ID_CAP = 64;

    [NativeTypeName("#define MXQ_ENGINE_MIN_HASH_MIB 256u")]
    public const uint MXQ_ENGINE_MIN_HASH_MIB = 256U;

    [NativeTypeName("#define MXQ_ENGINE_MAX_HASH_MIB 4096u")]
    public const uint MXQ_ENGINE_MAX_HASH_MIB = 4096U;

    [NativeTypeName("#define MXQ_ENGINE_HASH_GRANULARITY_MIB 64u")]
    public const uint MXQ_ENGINE_HASH_GRANULARITY_MIB = 64U;

    [NativeTypeName("#define MXQ_ENGINE_RESERVE_PERCENT 20u")]
    public const uint MXQ_ENGINE_RESERVE_PERCENT = 20U;

    [NativeTypeName("#define MXQ_ENGINE_MIN_RESERVE_BYTES (134217728u)")]
    public const uint MXQ_ENGINE_MIN_RESERVE_BYTES = (134217728U);

    [NativeTypeName("#define MXQ_ENGINE_PHYSICAL_PERCENT 50u")]
    public const uint MXQ_ENGINE_PHYSICAL_PERCENT = 50U;

    [NativeTypeName("#define MXQ_MOVETIME_FAST_MS 1000u")]
    public const uint MXQ_MOVETIME_FAST_MS = 1000U;

    [NativeTypeName("#define MXQ_MOVETIME_STANDARD_MS 3000u")]
    public const uint MXQ_MOVETIME_STANDARD_MS = 3000U;

    [NativeTypeName("#define MXQ_MOVETIME_DEEP_MS 5000u")]
    public const uint MXQ_MOVETIME_DEEP_MS = 5000U;

    [NativeTypeName("#define MXQ_CORE_FLAG_NONE 0u")]
    public const uint MXQ_CORE_FLAG_NONE = 0U;

    [NativeTypeName("#define MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY (1u << 0)")]
    public const uint MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY = (1U << 0);
}

/// <summary>Defines the type of a member as it was used in the native signature.</summary>
[AttributeUsage(AttributeTargets.Struct | AttributeTargets.Enum | AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter | AttributeTargets.ReturnValue, AllowMultiple = false, Inherited = true)]
[Conditional("DEBUG")]
internal sealed partial class NativeTypeNameAttribute : Attribute
{
    private readonly string _name;

    /// <summary>Initializes a new instance of the <see cref="NativeTypeNameAttribute" /> class.</summary>
    /// <param name="name">The name of the type that was used in the native signature.</param>
    public NativeTypeNameAttribute(string name)
    {
        _name = name;
    }

    /// <summary>Gets the name of the type that was used in the native signature.</summary>
    public string Name => _name;
}

/// <summary>Defines the annotation found in a native declaration.</summary>
[AttributeUsage(AttributeTargets.Struct | AttributeTargets.Enum | AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter | AttributeTargets.ReturnValue, AllowMultiple = true, Inherited = false)]
[Conditional("DEBUG")]
internal sealed partial class NativeAnnotationAttribute : Attribute
{
    private readonly string _annotation;

    /// <summary>Initializes a new instance of the <see cref="NativeAnnotationAttribute" /> class.</summary>
    /// <param name="annotation">The annotation that was used in the native declaration.</param>
    public NativeAnnotationAttribute(string annotation)
    {
        _annotation = annotation;
    }

    /// <summary>Gets the annotation that was used in the native declaration.</summary>
    public string Annotation => _annotation;
}
