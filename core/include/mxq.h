/*
 * mxq.h — the complete public C interface of the Mini Xiangqi shared core.
 *
 * This header is the single input from which both platform bindings are generated:
 * the Swift module map on Apple platforms and the ClangSharp-generated C#
 * declarations on Windows. It is therefore plain C: no C++, no anonymous unions,
 * no bitfields, no function-like behaviour hidden in macros, and nothing that is
 * not blittable.
 *
 * It transcribes the accepted contract in docs/core-interface.md. Six groups,
 * 54 functions, three opaque handles.
 *
 * Conventions, all from that contract:
 *
 *   - Functions are mxq_<module>_<verb>, types are Mxq<Noun>, constants are
 *     MXQ_<SNAKE>.
 *   - Every fallible function returns MxqStatus and takes an optional
 *     MxqError *err out-parameter for detail. There is no thread-local
 *     last-error. Passing NULL for err is always legal.
 *   - Every value struct begins with uint32_t struct_size, which the caller sets
 *     to sizeof(the struct it compiled against) before the call. Structs grow
 *     append-only behind that guard.
 *   - Enumerated vocabularies are exactly 32 bits wide and carry explicit
 *     values, and they grow append-only. They are spelled as an int32_t typedef
 *     plus named constants rather than as a C enum type, so that a value the
 *     caller's build does not know about — which the contract requires
 *     frontends to tolerate within a known domain — is a defined value of the
 *     type rather than an out-of-range enumerator.
 *   - Booleans are uint8_t, 0 or 1.
 *   - Strings are UTF-8. Bounded strings are carried by value in fixed-capacity
 *     NUL-terminated arrays so every struct is trivially copyable, blittable in
 *     C#, and Sendable in Swift. Unbounded strings (paths) cross as
 *     const char * borrowed for the duration of the call.
 *   - The caller never frees core memory. Outputs are copies into caller
 *     storage; the only pointer into core memory is mxq_blob_bytes, valid until
 *     mxq_blob_release.
 *   - Moves use the frozen canonical notation <from><to> and positions the
 *     frozen 6-field FEN, per docs/xiangqi-rules.md. Every rules query is
 *     defined over an initial position plus complete move history, never a bare
 *     FEN, because repetition and violation state derive from history.
 *
 * Each function below states the thread it may be called from and whether it
 * blocks, and every function that delivers a callback states which thread
 * delivers it, as docs/architecture.md requires of this boundary.
 *
 * Reserved fields exist only to keep every struct free of implicit padding, so
 * that the layout is identical under every supported compiler. They must be
 * written as zero and must be ignored when read.
 */

#ifndef MXQ_H
#define MXQ_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#  define MXQ_CALL __cdecl
#else
#  define MXQ_CALL
#endif

#if defined(_WIN32)
#  if defined(MXQ_BUILD_SHARED)
#    define MXQ_API __declspec(dllexport)
#  elif defined(MXQ_USE_SHARED)
#    define MXQ_API __declspec(dllimport)
#  else
#    define MXQ_API
#  endif
#elif defined(__GNUC__)
#  define MXQ_API __attribute__((visibility("default")))
#else
#  define MXQ_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------- */
/* API version                                                               */
/* ------------------------------------------------------------------------- */

/*
 * MXQ_API_VERSION is compiled into this header, reported by mxq_core_version,
 * and checked at mxq_core_init. Within a major version there are no removals,
 * renames, signature changes, enum renumbering, struct-field changes, or
 * thread-rule tightening; additions are new functions, appended enum constants,
 * and appended struct fields behind struct_size.
 *
 * This is one of four independent axes. The other three — the archive format
 * version, the store schema version, and the engine profile — are reported
 * separately by MxqVersion and are never conflated with this one.
 */
#define MXQ_API_VERSION_MAJOR 1
#define MXQ_API_VERSION_MINOR 4
#define MXQ_API_VERSION_PATCH 0

/* ------------------------------------------------------------------------- */
/* Capacities                                                                */
/* ------------------------------------------------------------------------- */

/* "<from><to>" is four characters; 8 leaves room for the NUL and keeps the
 * struct 4-aligned. No move suffix exists in this ruleset. */
#define MXQ_MOVE_TEXT_CAP 8

/* A 6-field Mini Xiangqi FEN, NUL-terminated. */
#define MXQ_FEN_CAP 96

/* MxqError.detail: a short English diagnostic. Provisional; docs/core-interface.md
 * leaves the concrete capacity to be finalised against measured worst cases. */
#define MXQ_DETAIL_CAP 128

/* A version 7 UUID in canonical lowercase text: 36 characters plus the NUL. */
#define MXQ_GAME_ID_CAP 40

/* Lowercase hexadecimal SHA-256: 64 characters plus the NUL. */
#define MXQ_SHA256_HEX_CAP 72

/* A git revision in full hexadecimal: 40 characters plus the NUL. */
#define MXQ_REVISION_CAP 48

/* An engine variant identifier, for example "minixiangqiaxf". */
#define MXQ_VARIANT_ID_CAP 32

/* An engine profile identifier, recorded with saved diagnostics so a move can
 * be attributed to the configuration that produced it. */
#define MXQ_PROFILE_ID_CAP 64

/* ------------------------------------------------------------------------- */
/* Status codes                                                              */
/* ------------------------------------------------------------------------- */

/*
 * MxqStatus codes are grouped in 1000-blocks. mxq_status_domain returns the
 * block. Frontends select their presentation family by domain and their copy by
 * exact code, and must tolerate an unknown code within a known domain: every
 * switch over MxqStatus requires a default arm.
 *
 * Programming errors — the argument domain except MXQ_ERR_ARG_BUFFER_TOO_SMALL,
 * plus the not-initialised, already-initialised and read-only-session
 * violations — assert in debug builds, return their code in release builds, and
 * never change state. Every other status is ordinary control flow and leaves
 * the last committed state intact.
 */
typedef int32_t MxqStatus;

enum {
    MXQ_OK = 0,

    /* Domains. mxq_status_domain returns one of these. */
    MXQ_DOMAIN_OK       = 0,
    MXQ_DOMAIN_ARGUMENT = 1000,
    MXQ_DOMAIN_STATE    = 2000,
    MXQ_DOMAIN_RULES    = 3000,
    MXQ_DOMAIN_STORE    = 4000,
    MXQ_DOMAIN_ARCHIVE  = 5000,
    MXQ_DOMAIN_ENGINE   = 6000,
    MXQ_DOMAIN_RESOURCE = 7000,
    MXQ_DOMAIN_INTERNAL = 9000,

    /* Argument domain: 1000. */
    MXQ_ERR_ARG_NULL              = 1001, /* a required pointer was NULL */
    MXQ_ERR_ARG_INVALID_HANDLE    = 1002, /* handle is not live; also returned by
                                           * every handle outstanding after
                                           * mxq_core_shutdown */
    MXQ_ERR_ARG_STRUCT_SIZE       = 1003, /* struct_size is not a size this build
                                           * can interpret */
    MXQ_ERR_ARG_API_VERSION       = 1004, /* the caller's MXQ_API_VERSION is not
                                           * compatible with this core */
    MXQ_ERR_ARG_BUFFER_TOO_SMALL  = 1005, /* routine, not a programming error;
                                           * MxqError.required_size carries the
                                           * size the call needs */
    MXQ_ERR_ARG_ENCODING          = 1006, /* a string was not valid UTF-8, or not
                                           * NUL-terminated within its capacity */
    MXQ_ERR_ARG_RANGE             = 1007, /* a numeric argument was out of range */
    MXQ_ERR_ARG_WRONG_THREAD      = 1008, /* called from a thread class this
                                           * function forbids */
    MXQ_ERR_ARG_CONCURRENT_USE    = 1009, /* two owners of one thing: two
                                           * threads inside one session, or a
                                           * second mxq_game_resume_active
                                           * while a session is already
                                           * attached to the active game */
    MXQ_ERR_ARG_REENTRANT         = 1010, /* called from inside a search callback,
                                           * where the legal calls are the
                                           * status and blob helpers and the
                                           * four pure queries that take no core
                                           * instance: see MxqSearchCallback */

    /* State domain: 2000. */
    MXQ_ERR_STATE_NOT_INITIALIZED     = 2001,
    MXQ_ERR_STATE_ALREADY_INITIALIZED = 2002, /* a second mxq_core_init before
                                               * shutdown */
    MXQ_ERR_STATE_SHUTTING_DOWN       = 2003,
    MXQ_ERR_STATE_ACTIVE_GAME_EXISTS  = 2004,
    MXQ_ERR_STATE_ACTIVE_GAME_MISSING = 2005,
    MXQ_ERR_STATE_SESSION_READ_ONLY   = 2006, /* a mutation on a detached replay
                                               * or import-preview session */
    MXQ_ERR_STATE_SESSION_ARCHIVED    = 2007, /* a mutation after a terminal
                                               * commit or archive-and-clear */
    MXQ_ERR_STATE_GAME_OVER           = 2008,
    MXQ_ERR_STATE_UNDO_UNAVAILABLE    = 2009,
    MXQ_ERR_STATE_CLAIM_UNAVAILABLE   = 2010,
    MXQ_ERR_STATE_RESIGN_UNAVAILABLE  = 2011,
    MXQ_ERR_STATE_CONFIRM_UNAVAILABLE = 2014, /* mxq_game_confirm_result on a
                                               * position with no natural
                                               * result to confirm. The third
                                               * of the same family as the two
                                               * above: the action this
                                               * function performs is not
                                               * available in this state, and
                                               * MXQ_ERR_STATE_GAME_OVER is its
                                               * opposite rather than its
                                               * equivalent */
    MXQ_ERR_STATE_SEARCH_IN_PROGRESS  = 2012, /* engine reconfiguration
                                               * serialises behind search */
    MXQ_ERR_STATE_ENGINE_NOT_READY    = 2013,

    /* Rules domain: 3000. Malformed and illegal are always distinguished. */
    MXQ_ERR_RULES_MALFORMED_MOVE   = 3001, /* not ^[a-g][1-7][a-g][1-7]$ */
    MXQ_ERR_RULES_ILLEGAL_MOVE     = 3002, /* well-formed but not legal here */
    MXQ_ERR_RULES_INVALID_FEN      = 3003, /* fails the frozen structural
                                            * encoding */
    MXQ_ERR_RULES_ILLEGAL_POSITION = 3004, /* reserved: in version 1 no setup-
                                            * legality predicate is defined, so
                                            * this code is never returned */
    MXQ_ERR_RULES_INVALID_HISTORY  = 3005, /* MxqError.detail_index carries the
                                            * first illegal move's index */

    /* Store domain: 4000. */
    MXQ_ERR_STORE_IO                = 4001,
    MXQ_ERR_STORE_CORRUPT           = 4002,
    MXQ_ERR_STORE_BUSY              = 4003,
    MXQ_ERR_STORE_FULL              = 4004,
    MXQ_ERR_STORE_NOT_FOUND         = 4005,
    MXQ_ERR_STORE_IDENTITY_CONFLICT = 4006, /* same game_id, differing content */
    MXQ_ERR_STORE_MIGRATION_FAILED  = 4007,
    MXQ_ERR_STORE_SCHEMA_TOO_NEW    = 4008, /* written by a newer build */

    /* Archive domain: 5000. */
    MXQ_ERR_ARCHIVE_MALFORMED            = 5001, /* every well-formedness and
                                                  * field-validity refusal:
                                                  * encoding, syntax, envelope,
                                                  * vocabulary, cross-field */
    MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION  = 5002, /* version dispatch refused the
                                                  * file: created by a newer
                                                  * version, or older than the
                                                  * minimum this build reads.
                                                  * Never presented as
                                                  * corruption, and the newer
                                                  * case says so distinctly. An
                                                  * archive_version that is not
                                                  * a positive integer is no
                                                  * version at all and is
                                                  * MXQ_ERR_ARCHIVE_MALFORMED */
    MXQ_ERR_ARCHIVE_TOO_LARGE            = 5003, /* a documented import bound of
                                                  * docs/game-data.md: file
                                                  * size, plies, JSON nesting
                                                  * depth, members per object,
                                                  * or string length. The file
                                                  * may be well formed; it is
                                                  * refused for its size */
    MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY  = 5004, /* the initial position is not
                                                  * the frozen one, or a move is
                                                  * not legal at its turn and
                                                  * MxqError.detail_index
                                                  * carries its index */
    MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH    = 5005, /* the recorded terminal pair
                                                  * disagrees with the replayed
                                                  * adjudication */

    /* Engine domain: 6000. */
    MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY   = 6001, /* the calculated Hash budget is
                                                  * below MXQ_ENGINE_MIN_HASH_MIB;
                                                  * nothing was initialised */
    MXQ_ERR_ENGINE_ASSET_MISSING         = 6002,
    MXQ_ERR_ENGINE_ASSET_MISMATCH        = 6003, /* hash, byte length, or the
                                                  * effective NNUE state after
                                                  * configuration */
    MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED   = 6004,
    MXQ_ERR_ENGINE_HASH_ALLOCATION_FAILED = 6005, /* the transposition table
                                                   * could not be allocated at
                                                   * the plan's size. Reachable
                                                   * since the fork's
                                                   * recoverable Hash change
                                                   * landed; mxq_engine_prepare
                                                   * returns it and never
                                                   * substitutes a smaller
                                                   * Hash */
    MXQ_ERR_ENGINE_NO_MOVE               = 6006,
    MXQ_ERR_ENGINE_ILLEGAL_RESULT        = 6007,
    MXQ_ERR_ENGINE_FAULTED               = 6008,
    MXQ_ERR_ENGINE_NOT_PREPARED          = 6009, /* the engine was torn down or
                                                  * faulted between a search's
                                                  * acceptance and its run, so
                                                  * the search ran against no
                                                  * prepared engine. The typed
                                                  * failure a delivered
                                                  * MXQ_SEARCH_FAILED carries is
                                                  * engine-domain by contract;
                                                  * the synchronous refusal at
                                                  * mxq_search_start remains
                                                  * MXQ_ERR_STATE_ENGINE_NOT_READY */

    /* Resource domain: 7000. */
    MXQ_ERR_RESOURCE_ALLOCATION_FAILED = 7001,
    MXQ_ERR_RESOURCE_LIMIT_EXCEEDED    = 7002, /* a documented limit, including
                                                * the import time budget */

    /* Internal domain: 9000. Invariant violations; reportable bugs. */
    MXQ_ERR_INTERNAL_INVARIANT = 9001
};

/* ------------------------------------------------------------------------- */
/* Enumerated vocabularies                                                   */
/* ------------------------------------------------------------------------- */

/*
 * MxqColor, MxqPlayMode, MxqAiLevel and MxqFirstMoverChoice correspond
 * one-to-one to the serialised vocabulary in docs/game-data.md. MXQ_COLOR_NONE,
 * MXQ_AI_LEVEL_NONE and MXQ_FIRST_MOVER_NONE have no serialised counterpart:
 * they are the in-band absence that a fixed-size struct needs where the archive
 * simply omits the member, and they appear only where the configuration has no
 * such value — that is, in Free Play.
 */
typedef int32_t MxqColor;
enum {
    MXQ_COLOR_NONE  = -1,
    MXQ_COLOR_RED   = 0, /* uppercase pieces, moves first */
    MXQ_COLOR_BLACK = 1  /* lowercase pieces */
};

typedef int32_t MxqPlayMode;
enum {
    MXQ_PLAY_MODE_HUMAN_VS_AI = 0, /* serialised "human-vs-ai" */
    MXQ_PLAY_MODE_FREE_PLAY   = 1  /* serialised "free-play" */
};

typedef int32_t MxqAiLevel;
enum {
    MXQ_AI_LEVEL_NONE     = -1,
    MXQ_AI_LEVEL_FAST     = 0, /* serialised "fast" */
    MXQ_AI_LEVEL_STANDARD = 1, /* serialised "standard" */
    MXQ_AI_LEVEL_DEEP     = 2  /* serialised "deep" */
};

typedef int32_t MxqFirstMoverChoice;
enum {
    MXQ_FIRST_MOVER_NONE        = -1,
    MXQ_FIRST_MOVER_HUMAN_FIRST = 0, /* serialised "human-first" */
    MXQ_FIRST_MOVER_AI_FIRST    = 1, /* serialised "ai-first" */
    MXQ_FIRST_MOVER_RANDOM      = 2  /* serialised "random" */
};

/*
 * The live game state. These are exactly the fixture state identifiers.
 * MXQ_GAME_ONGOING and MXQ_GAME_CLAIMABLE_DRAW can never be a committed
 * outcome; see MxqOutcome.
 */
typedef int32_t MxqGameState;
enum {
    MXQ_GAME_ONGOING        = 0, /* fixture "ongoing" */
    MXQ_GAME_CLAIMABLE_DRAW = 1, /* fixture "claimable-draw" */
    MXQ_GAME_RED_WINS       = 2, /* fixture "red-wins" */
    MXQ_GAME_BLACK_WINS     = 3, /* fixture "black-wins" */
    MXQ_GAME_DRAW           = 4  /* fixture "draw" */
};

/*
 * The committed outcome of a stored record, matching the archive's serialised
 * outcome vocabulary. This is deliberately not MxqGameState: live states can
 * never be a committed outcome, and MXQ_OUTCOME_NONE — a game ended early, with
 * no competitive result — is never a live state.
 */
typedef int32_t MxqOutcome;
enum {
    MXQ_OUTCOME_NONE       = 0, /* serialised "none"; exactly when the reason is
                                 * MXQ_END_REASON_ENDED_EARLY */
    MXQ_OUTCOME_RED_WINS   = 1, /* serialised "red-wins" */
    MXQ_OUTCOME_BLACK_WINS = 2, /* serialised "black-wins" */
    MXQ_OUTCOME_DRAW       = 3  /* serialised "draw" */
};

/*
 * The rule reasons are the fixture reason identifiers; the last two are
 * user-scoped. In this ruleset threefold repetition is always a user claim and
 * every other rule reason is automatic, so the reason determines the mechanism
 * and no claimed-versus-automatic flag exists.
 */
typedef int32_t MxqEndReason;
enum {
    MXQ_END_REASON_NONE                   = 0,
    MXQ_END_REASON_CHECKMATE              = 1, /* "checkmate" */
    MXQ_END_REASON_STALEMATE              = 2, /* "stalemate" */
    MXQ_END_REASON_THREEFOLD_REPETITION   = 3, /* "threefold-repetition" */
    MXQ_END_REASON_PERPETUAL_CHECK        = 4, /* "perpetual-check" */
    MXQ_END_REASON_PERPETUAL_CHASE        = 5, /* "perpetual-chase" */
    MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK = 6, /* "mutual-perpetual-check";
                                                * reserved for the deferred
                                                * mutual-violation tranche */
    MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE = 7, /* "mutual-perpetual-chase";
                                                * reserved likewise */
    MXQ_END_REASON_RESIGNATION            = 8, /* "resignation"; human-vs-AI only */
    MXQ_END_REASON_ENDED_EARLY            = 9  /* "ended-early" */
};

/* How a record entered this library. Local metadata, never an archive field. */
typedef int32_t MxqProvenance;
enum {
    MXQ_PROVENANCE_LOCALLY_PLAYED = 0, /* "locally-played" */
    MXQ_PROVENANCE_IMPORTED       = 1, /* "imported" */
    MXQ_PROVENANCE_DERIVED        = 2  /* "derived"; reserved for a future
                                        * start-from-position feature and
                                        * rejected by archive version 1 */
};

/* The result of a successful mxq_store_import. */
typedef int32_t MxqImportOutcome;
enum {
    MXQ_IMPORT_CREATED  = 0, /* a new immutable History record was inserted */
    MXQ_IMPORT_EXISTING = 1  /* an exact duplicate; the existing record is
                              * returned. Success, not an error. */
};

/* The engine's observable lifecycle state. */
typedef int32_t MxqEngineState;
enum {
    MXQ_ENGINE_STATE_UNINITIALIZED = 0, /* also the state after
                                         * mxq_engine_teardown and after the
                                         * platform's suspension signal */
    MXQ_ENGINE_STATE_READY         = 1,
    MXQ_ENGINE_STATE_FAULTED       = 2
};

/*
 * The outcome of one search, after the rejection ladder has been applied in
 * order: cancelled, then stale, then malformed, then illegal under the rules
 * facade. Only a move surviving all four arrives as MXQ_SEARCH_MOVE.
 */
typedef int32_t MxqSearchOutcome;
enum {
    MXQ_SEARCH_MOVE      = 0, /* MxqSearchResult.move is meaningful */
    MXQ_SEARCH_CANCELLED = 1,
    MXQ_SEARCH_STALE     = 2, /* (game_id, position_revision) no longer match */
    MXQ_SEARCH_MALFORMED = 3,
    MXQ_SEARCH_ILLEGAL   = 4,
    MXQ_SEARCH_FAILED    = 5  /* MxqSearchResult.status carries the typed
                               * engine-domain failure */
};

/* ------------------------------------------------------------------------- */
/* Engine budget constants                                                   */
/* ------------------------------------------------------------------------- */

/* The accepted adaptive Hash allocation policy, in the terms mxq_engine_plan
 * implements. UCI Hash is an integer count of MiB. */
#define MXQ_ENGINE_MIN_HASH_MIB          256u
#define MXQ_ENGINE_MAX_HASH_MIB          4096u
#define MXQ_ENGINE_HASH_GRANULARITY_MIB  64u
#define MXQ_ENGINE_RESERVE_PERCENT       20u
#define MXQ_ENGINE_MIN_RESERVE_BYTES     (134217728u)  /* 128 MiB */
#define MXQ_ENGINE_PHYSICAL_PERCENT      50u

/* The accepted thinking times, frozen with a created game. */
#define MXQ_MOVETIME_FAST_MS     1000u
#define MXQ_MOVETIME_STANDARD_MS 3000u
#define MXQ_MOVETIME_DEEP_MS     5000u

/* ------------------------------------------------------------------------- */
/* Opaque handles                                                            */
/* ------------------------------------------------------------------------- */

/*
 * Exactly three. Everything else crossing this boundary is a plain-old-data
 * value struct copied into caller storage.
 */

/* The core. Handle-shaped but singleton-enforced: a second mxq_core_init before
 * shutdown returns MXQ_ERR_STATE_ALREADY_INITIALIZED, because the embedded
 * engine's process-global state admits one instance. */
typedef struct MxqCore MxqCore;

/*
 * A game session. Sessions are store-attached when created or resumed and
 * detached read-only when opened for replay or import preview.
 *
 * Sessions are single-owner: a session may move between threads, but only one
 * thread may be inside it at a time, and a detected race returns
 * MXQ_ERR_ARG_CONCURRENT_USE rather than silently serialising. Distinct
 * sessions are independent. Every function taking an MxqGame * — including
 * mxq_search_start, mxq_archive_encode and mxq_store_archive_and_clear — counts
 * as being inside that session for this rule.
 */
typedef struct MxqGame MxqGame;

/* An immutable byte buffer owned by the core. */
typedef struct MxqBlob MxqBlob;

/* ------------------------------------------------------------------------- */
/* Value structs                                                             */
/* ------------------------------------------------------------------------- */

/*
 * Error detail. Optional everywhere: passing NULL is always legal, and the
 * status alone is the contract. Detail strings are short English diagnostics,
 * never localised copy and never private game data.
 */
typedef struct MxqError {
    uint32_t  struct_size;
    MxqStatus status;          /* the same value the function returned */
    int32_t   subsystem_code;  /* raw SQLite result, FEN validation cause, and
                                * the like: diagnostics only, never branched on */
    uint32_t  reserved0;
    uint64_t  required_size;   /* meaningful for MXQ_ERR_ARG_BUFFER_TOO_SMALL:
                                * the element or byte count the call needs */
    uint64_t  detail_index;    /* meaningful for MXQ_ERR_RULES_INVALID_HISTORY
                                * and for the illegal-move case of
                                * MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY: the
                                * index of the first illegal move */
    char      detail[MXQ_DETAIL_CAP]; /* UTF-8, NUL-terminated */
} MxqError;

/*
 * The four independent version axes. The engine-profile fields are load-bearing
 * rather than diagnostics: conformance depends on a fork build, so every test
 * report and saved diagnostic must be able to name the build that produced it.
 */
typedef struct MxqVersion {
    uint32_t struct_size;
    uint32_t api_major;
    uint32_t api_minor;
    uint32_t api_patch;
    uint32_t archive_version_current;
    uint32_t archive_version_min_readable;
    uint32_t store_schema_version;
    uint32_t reserved0;
    char     core_revision[MXQ_REVISION_CAP];
    char     fork_revision[MXQ_REVISION_CAP];   /* the pinned Fairy-Stockfish
                                                 * fork revision */
    char     variant_id[MXQ_VARIANT_ID_CAP];    /* the pinned engine variant */
    char     nnue_sha256[MXQ_SHA256_HEX_CAP];   /* lowercase hexadecimal */
} MxqVersion;

/*
 * MxqCoreConfig.flags values. Flags are appended here as they are defined,
 * like every other constant vocabulary.
 */
#define MXQ_CORE_FLAG_NONE 0u

/*
 * A test affordance, never product behaviour: with this flag the core's one
 * clock and identity provider becomes deterministic, so store round-trip
 * fixtures and archive golden files can be byte-stable across runs and
 * machines. Production callers never set it; without it the provider reads the
 * real clock and generates real version 7 UUIDs from a cryptographically
 * seeded source.
 *
 * The deterministic behaviour, exactly:
 *
 *   - The clock starts at 2026-01-01T00:00:00.000Z (epoch millisecond
 *     1767225600000). The first read returns that instant and every further
 *     read returns 1000 ms more than the previous one — time advances one
 *     second per observation and never else.
 *   - Game identifiers are version-7-shaped UUIDs from a counter that starts
 *     at 0 at mxq_core_init. The nth identifier carries epoch millisecond
 *     1767225600000 + n in its 48-bit time field, version nibble 7, zero
 *     rand_a, RFC 9562 variant bits, and n in its final 62 bits; the counter
 *     is independent of the clock above. The 0th is therefore exactly
 *     "019b76da-a800-7000-8000-000000000000" and the 1st
 *     "019b76da-a801-7000-8000-000000000001".
 *
 * Both sequences reset at mxq_core_init, so two runs of the same test perform
 * identical writes. The flag changes identity and time generation only; it
 * changes no rule, no schema, and no store behaviour.
 */
#define MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY (1u << 0)

/*
 * Core configuration. Both directories are supplied by the frontend — the
 * core never derives a platform path — and both pointers are borrowed for the
 * duration of the mxq_core_init call only.
 */
typedef struct MxqCoreConfig {
    uint32_t    struct_size;
    uint32_t    api_major;   /* the caller's MXQ_API_VERSION_MAJOR */
    uint32_t    api_minor;   /* the caller's MXQ_API_VERSION_MINOR */
    uint32_t    api_patch;   /* the caller's MXQ_API_VERSION_PATCH */
    uint32_t    flags;       /* MXQ_CORE_FLAG_* bitmask; 0 for defaults */
    uint32_t    reserved0;
    const char *store_directory; /* UTF-8, NUL-terminated */
    const char *asset_directory; /* UTF-8, NUL-terminated */
} MxqCoreConfig;

/* One move in the frozen canonical notation "<from><to>", for example "b1b4". */
typedef struct MxqMove {
    uint32_t struct_size;
    char     text[MXQ_MOVE_TEXT_CAP]; /* UTF-8, NUL-terminated */
} MxqMove;

/*
 * A position. position_revision is a per-session monotonic counter bumped by
 * every accepted mutation, and it is the staleness authority: an in-flight
 * search result whose revision no longer matches is rejected even if no one
 * cancelled it.
 */
typedef struct MxqPosition {
    uint32_t struct_size;
    uint32_t ply_count;
    uint64_t position_revision;
    MxqColor side_to_move;
    uint8_t  in_check;
    uint8_t  reserved0[3];
    char     fen[MXQ_FEN_CAP];  /* the frozen 6-field FEN */
} MxqPosition;

/*
 * The live game state and the derived affordances, so that frontends never
 * re-derive rules policy.
 */
typedef struct MxqGameStatus {
    uint32_t     struct_size;
    MxqGameState state;
    MxqEndReason reason;        /* MXQ_END_REASON_NONE while ongoing */
    uint32_t     at_occurrence; /* the occurrence the outcome attached at, for
                                 * repetition-based states; 0 otherwise */
    uint32_t     undo_plies;    /* 1 or 2, per the decision-cycle rule; 0 when
                                 * undo_available is 0 */
    uint8_t      claim_available;
    uint8_t      undo_available;
    uint8_t      resign_available;
    uint8_t      search_expected;
} MxqGameStatus;

/*
 * A game's frozen configuration. human_side, ai_level, ai_movetime_ms and
 * first_mover_choice are meaningful only when mode is
 * MXQ_PLAY_MODE_HUMAN_VS_AI; in Free Play they read as the NONE constants and
 * zero, matching the archive, which simply omits them.
 *
 * human_side is the resolved side: it is MXQ_COLOR_RED or MXQ_COLOR_BLACK in a
 * human-versus-AI game even when first_mover_choice is MXQ_FIRST_MOVER_RANDOM,
 * which is retained only because it cannot be reconstructed later.
 */
typedef struct MxqGameConfig {
    uint32_t            struct_size;
    MxqPlayMode         mode;
    MxqColor            human_side;
    MxqAiLevel          ai_level;
    MxqFirstMoverChoice first_mover_choice;
    uint32_t            ai_movetime_ms; /* the exact frozen movetime */
} MxqGameConfig;

/*
 * The queryable summary of one stored game: the History list's metadata, plus
 * the identity and timestamps. Every field is exactly recomputable from the
 * stored archive blob.
 */
typedef struct MxqRecordSummary {
    uint32_t      struct_size;
    uint32_t      move_count;      /* plies */
    uint64_t      record_id;
    int64_t       started_at_ms;   /* epoch milliseconds, UTC */
    int64_t       ended_at_ms;     /* 0 when the game has no committed end */
    int64_t       added_at_ms;     /* the local History-added time that orders
                                    * the list; 0 for the active game */
    MxqPlayMode   mode;
    MxqColor      human_side;
    MxqAiLevel    ai_level;
    uint32_t      ai_movetime_ms;
    MxqOutcome    outcome;
    MxqEndReason  end_reason;
    MxqProvenance provenance;
    uint8_t       pinned;
    uint8_t       is_active;       /* 1 for the single active game, which has no
                                    * committed outcome */
    uint8_t       reserved0[2];
    char          game_id[MXQ_GAME_ID_CAP]; /* version 7 UUID, canonical
                                             * lowercase */
} MxqRecordSummary;

/*
 * The decoded summary the store indexes, from an archive's bytes.
 *
 * An archive that records no end — an active game's stored content, which omits
 * outcome, end_reason and ended_at — reads as end_reason MXQ_END_REASON_NONE
 * and ended_at_ms 0. MxqOutcome has no absent constant, so outcome then reads
 * MXQ_OUTCOME_NONE, which is also the committed outcome of a game ended early:
 * end_reason is the field that separates the two, and it is
 * MXQ_END_REASON_ENDED_EARLY for the ended-early record.
 *
 * human_side is MXQ_COLOR_NONE in Free Play, matching the archive, which simply
 * omits the member.
 */
typedef struct MxqArchiveInfo {
    uint32_t     struct_size;
    uint32_t     archive_version;
    uint32_t     move_count;
    MxqPlayMode  mode;
    MxqColor     human_side;
    MxqOutcome   outcome;
    MxqEndReason end_reason;
    uint32_t     reserved0;
    int64_t      started_at_ms; /* epoch milliseconds, UTC */
    int64_t      ended_at_ms;   /* 0 when the archive records no end */
    char         game_id[MXQ_GAME_ID_CAP];
} MxqArchiveInfo;

/*
 * The frontend-supplied probe values the Hash budget is computed from. The
 * frontend takes a fresh probe at each calculation: os_proc_available_memory()
 * on iOS and iPadOS, the selected system-availability probes on macOS and
 * Windows.
 */
typedef struct MxqEngineBudget {
    uint32_t struct_size;
    uint32_t active_processor_count; /* what Threads is initialised from */
    uint64_t available_bytes;        /* the fresh probe value */
    uint64_t physical_bytes;         /* the device's physical memory */
} MxqEngineBudget;

/*
 * The plan the accepted arithmetic yields. The intermediate values are reported
 * so that every budget boundary is directly testable without an engine.
 *
 * reserve_bytes = max(MXQ_ENGINE_RESERVE_PERCENT% of available_bytes,
 *                     MXQ_ENGINE_MIN_RESERVE_BYTES)
 * usable_bytes  = max(0, available_bytes - reserve_bytes)
 * budget_bytes  = min(MXQ_ENGINE_MAX_HASH_MIB MiB,
 *                     MXQ_ENGINE_PHYSICAL_PERCENT% of physical_bytes,
 *                     usable_bytes)
 * hash_mib      = budget_bytes in MiB, rounded down to a multiple of
 *                 MXQ_ENGINE_HASH_GRANULARITY_MIB
 * sufficient    = hash_mib >= MXQ_ENGINE_MIN_HASH_MIB
 */
typedef struct MxqEnginePlan {
    uint32_t struct_size;
    uint32_t threads;       /* the applied Threads value */
    uint32_t hash_mib;      /* the applied UCI Hash value in MiB */
    uint8_t  sufficient;    /* 0 means mxq_engine_prepare would report
                             * MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY */
    uint8_t  reserved0[3];
    uint64_t reserve_bytes;
    uint64_t usable_bytes;
    uint64_t budget_bytes;
} MxqEnginePlan;

/*
 * A search request. The session supplies everything else: mxq_search_start does
 * not retain the session, it snapshots the initial FEN, the complete move list,
 * the game_id, the position_revision, and the session's frozen movetime.
 */
typedef struct MxqSearchRequest {
    uint32_t struct_size;
    uint32_t movetime_ms; /* must equal the session's frozen ai_movetime_ms */
} MxqSearchRequest;

/*
 * An inert value struct. Applying the move is a separate explicit
 * mxq_game_apply_move; no path exists from search output to committed state.
 *
 * game_id and position_revision are carried so the frontend can compare
 * staleness again before applying. That second comparison is required: the core
 * compares before delivery and the frontend compares before applying, because
 * neither check alone covers both race directions.
 */
typedef struct MxqSearchResult {
    uint32_t         struct_size;
    MxqSearchOutcome outcome;
    uint64_t         ticket;
    uint64_t         position_revision; /* the revision the search started from */
    uint64_t         nodes;
    int32_t          score_cp;    /* diagnostic only; adjudication never derives
                                   * from a search score */
    uint32_t         depth;       /* diagnostic only */
    uint32_t         elapsed_ms;
    MxqStatus        status;      /* the typed failure, for MXQ_SEARCH_FAILED */
    MxqMove          move;        /* meaningful only for MXQ_SEARCH_MOVE */
    char             game_id[MXQ_GAME_ID_CAP];
    char             profile_id[MXQ_PROFILE_ID_CAP];
    uint32_t         reserved0;
} MxqSearchResult;

/*
 * The search completion callback.
 *
 * Delivered on: the core's engine thread, always — never the calling thread and
 * never a platform queue.
 *
 * It must copy and return. Inside it the legal calls are the status and blob
 * helpers — mxq_status_domain, mxq_status_name, mxq_blob_bytes, mxq_blob_len,
 * mxq_blob_release — together with the four pure queries that take no core
 * instance and no lock: mxq_core_version, mxq_rules_start_fen, mxq_engine_plan
 * and mxq_archive_supported_versions. Every other core function returns
 * MXQ_ERR_ARG_REENTRANT. It must not block,
 * because the engine thread is the resource it would deadlock. Its whole job is
 * to hand the result to the frontend's dispatcher.
 *
 * result points into core storage and is valid only for the duration of the
 * call. user_data is the pointer passed to mxq_search_start, untouched.
 */
typedef void(MXQ_CALL *MxqSearchCallback)(const MxqSearchResult *result,
                                          void *user_data);

/* ------------------------------------------------------------------------- */
/* Common prelude                                                            */
/* ------------------------------------------------------------------------- */

/*
 * Return the 1000-block domain of status: one of the MXQ_DOMAIN_* constants.
 * An unrecognised code still yields its block, so a frontend can route an
 * unknown code by domain.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_status_domain(MxqStatus status);

/*
 * Return a stable ASCII name for status, for logs and diagnostics — never
 * user-facing copy. The returned pointer is an immortal literal: it is never
 * freed and stays valid for the process lifetime. Never returns NULL.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API const char *MXQ_CALL mxq_status_name(MxqStatus status);

/*
 * The blob's bytes. This is the only pointer into core memory this interface
 * hands out; it is valid until mxq_blob_release. Returns NULL when blob is NULL.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API const uint8_t *MXQ_CALL mxq_blob_bytes(const MxqBlob *blob);

/*
 * The blob's length in bytes. Returns 0 when blob is NULL.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API size_t MXQ_CALL mxq_blob_len(const MxqBlob *blob);

/*
 * Release a blob. NULL-safe. After this call, any pointer previously returned
 * by mxq_blob_bytes for this blob is dangling.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API void MXQ_CALL mxq_blob_release(MxqBlob *blob);

/* ------------------------------------------------------------------------- */
/* Core lifecycle — mxq_core_                                                */
/* ------------------------------------------------------------------------- */

/*
 * Report the four independent version axes. Callable before mxq_core_init, as
 * are the other queries that take no core instance: mxq_rules_start_fen,
 * mxq_engine_plan and mxq_archive_supported_versions.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_core_version(MxqVersion *out, MxqError *err);

/*
 * Initialise the core and open the store. Returns
 * MXQ_ERR_STATE_ALREADY_INITIALIZED if a core is live, and
 * MXQ_ERR_ARG_API_VERSION if the caller's compiled-in API version is not
 * compatible with this build.
 *
 * The store opens — creating the database file and schema on first run — under
 * config->store_directory, whose leading directories are created as needed. A
 * store that cannot be opened or created fails with its store-domain status;
 * one written by a newer build is refused with MXQ_ERR_STORE_SCHEMA_TOO_NEW
 * rather than opened, per the forward-only migration rule in
 * docs/game-data.md.
 *
 * Thread: the UI or setup thread; never inside a search callback.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_core_init(const MxqCoreConfig *config,
                                         MxqCore **out_core, MxqError *err);

/*
 * Cancel every outstanding search cooperatively. This is the backgrounding and
 * memory-pressure path: callbacks still fire, with MXQ_SEARCH_CANCELLED. The
 * committed game is never affected.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: yes, until the engine quiesces.
 */
MXQ_API MxqStatus MXQ_CALL mxq_core_cancel_all(MxqCore *core, MxqError *err);

/*
 * Deterministic teardown, without relying on process termination: cancel all
 * work, join the engine thread, close the store, and invalidate every
 * outstanding handle, which afterwards returns MXQ_ERR_ARG_INVALID_HANDLE
 * instead of touching freed memory.
 *
 * Thread: the UI or setup thread; never inside a search callback.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_core_shutdown(MxqCore *core, MxqError *err);

/* ------------------------------------------------------------------------- */
/* Rules facade, sessions — mxq_game_                                        */
/* ------------------------------------------------------------------------- */

/*
 * Create and persist a new store-attached active game, freezing the supplied
 * configuration. Returns MXQ_ERR_STATE_ACTIVE_GAME_EXISTS when the library
 * already holds an active game.
 *
 * The configuration arrives resolved: a MXQ_FIRST_MOVER_RANDOM choice is
 * resolved into human_side by the frontend before this call, because only
 * successful creation commits a resolved side and the core never invents a
 * value the frontend owns. The four human-versus-AI members must be present
 * exactly in MXQ_PLAY_MODE_HUMAN_VS_AI and must read as the NONE constants and
 * zero in Free Play, matching the archive, which omits them; a configuration
 * that is neither shape is a programming error and returns MXQ_ERR_ARG_RANGE.
 *
 * Thread: any non-UI thread except inside a search callback — except the
 * store-attached active game, whose own calls docs/core-interface.md's
 * threading contract documents as the one exception to "off the UI thread".
 * Blocking: yes — store work.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_create(MxqCore *core,
                                           const MxqGameConfig *config,
                                           MxqGame **out_game, MxqError *err);

/*
 * Resume the single active game as a store-attached session. Sets *out_exists
 * to 0 and *out_game to NULL, and returns MXQ_OK, when there is no active game:
 * absence is not an error. A library reference naming a row that is not there
 * is not absence; it is MXQ_ERR_STORE_CORRUPT.
 *
 * There is at most one session per active game. A second resume while the
 * first is still live returns MXQ_ERR_ARG_CONCURRENT_USE and produces no
 * session, because two sessions over one row would commit over one another
 * with no diagnosis at all — the same "two owners of one thing" the
 * single-owner rule refuses, asked of the row rather than of the session.
 *
 * The stored record is decoded, checked against the content hash the library
 * recorded for it, and replayed, all before a session exists, so a row this
 * build can no longer read or no longer reproduce is refused as
 * MXQ_ERR_STORE_CORRUPT rather than as an archive rejection: nothing was
 * imported, and the answer is about the library rather than about a file the
 * user chose. The import size bounds are deliberately not applied here — a
 * locally produced game longer than they allow must always resume.
 *
 * Thread: any non-UI thread except inside a search callback — except the
 * store-attached active game, whose own calls docs/core-interface.md's
 * threading contract documents as the one exception to "off the UI thread".
 * Blocking: yes — store work.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_resume_active(MxqCore *core,
                                                  MxqGame **out_game,
                                                  uint8_t *out_exists,
                                                  MxqError *err);

/*
 * Open archive bytes as a detached read-only session, for import preview. The
 * bytes are borrowed for the duration of the call and are untrusted input.
 * Mutations on the resulting session return MXQ_ERR_STATE_SESSION_READ_ONLY.
 *
 * The bytes are fully validated first — everything mxq_archive_validate does,
 * with every import bound applied — because a preview that shows a replayable
 * board must be able to replay it, and because a preview must accept exactly
 * the files mxq_store_import accepts: one that displayed a game the import then
 * refused would be the worst of both answers. The refusals are therefore that
 * function's, class for class and status for status, including the refusal of a
 * file recording no end, which is not a game an import could file.
 *
 * No store row is involved: the session's record identity is not a record, the
 * library is neither read nor written, and releasing it changes nothing.
 *
 * Thread: any non-UI thread except inside a search callback.
 * Blocking: yes — decode and replay work.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_open_archive(MxqCore *core,
                                                 const uint8_t *bytes,
                                                 size_t len, MxqGame **out_game,
                                                 MxqError *err);

/*
 * Release a session. NULL-safe. Required after a terminal commit or an
 * archive-and-clear as much as after any other use.
 *
 * Thread: the session's owner.
 * Blocking: no.
 */
MXQ_API void MXQ_CALL mxq_game_release(MxqGame *game);

/*
 * Write the session's stable identity — the version 7 UUID frozen at creation —
 * and its length. Same buffer convention as mxq_rules_start_fen;
 * MXQ_GAME_ID_CAP is always sufficient.
 *
 * A session must be able to state its own identity: the staleness comparison
 * MxqSearchResult prescribes is against (game_id, position_revision), and a
 * detached replay or import-preview session has no other route to the value at
 * all.
 *
 * Thread: the session's owner.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_id(const MxqGame *game, char *out,
                                       size_t cap, size_t *out_len,
                                       MxqError *err);

/*
 * The session's current position.
 *
 * Thread: the session's owner.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_position(const MxqGame *game,
                                             MxqPosition *out, MxqError *err);

/*
 * The session's live state and derived affordances.
 *
 * Thread: the session's owner.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_status(const MxqGame *game,
                                           MxqGameStatus *out, MxqError *err);

/*
 * The session's frozen configuration.
 *
 * Thread: the session's owner.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_config(const MxqGame *game,
                                           MxqGameConfig *out, MxqError *err);

/*
 * The complete legal-move set in the current position. Writes at most cap
 * elements and always sets *out_count to the number available; when cap is too
 * small, returns MXQ_ERR_ARG_BUFFER_TOO_SMALL with MxqError.required_size set,
 * which is routine rather than a programming error. Passing out as NULL with
 * cap 0 is the legal way to ask for the count alone.
 *
 * Thread: the session's owner.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_legal_moves(const MxqGame *game,
                                                MxqMove *out, size_t cap,
                                                size_t *out_count,
                                                MxqError *err);

/*
 * The legal moves originating at from_square, a two-character square name such
 * as "d1". Same buffer convention as mxq_game_legal_moves. A well-formed square
 * with no legal move yields *out_count 0 and MXQ_OK; a string that is not
 * ^[a-g][1-7]$ is a programming error and returns MXQ_ERR_ARG_RANGE, because a
 * frontend asking about a square its own board does not have is a frontend
 * bug.
 *
 * Thread: the session's owner.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_legal_moves_from(const MxqGame *game,
                                                     const char *from_square,
                                                     MxqMove *out, size_t cap,
                                                     size_t *out_count,
                                                     MxqError *err);

/*
 * The session's complete retained main line, index 0 first. Same buffer
 * convention as mxq_game_legal_moves.
 *
 * Thread: the session's owner.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_move_history(const MxqGame *game,
                                                 MxqMove *out, size_t cap,
                                                 size_t *out_count,
                                                 MxqError *err);

/*
 * The position after the first ply plies, for replay scrubbing. ply 0 is the
 * initial position; ply beyond the retained line returns MXQ_ERR_ARG_RANGE,
 * which a scrubber may legitimately provoke by probing an end and which
 * therefore does not assert. position_revision reports the session's current
 * revision whichever ply is asked for: it identifies the session's state, not
 * the position walked to.
 *
 * Thread: the session's owner.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_position_at(const MxqGame *game,
                                                uint32_t ply, MxqPosition *out,
                                                MxqError *err);

/*
 * Apply one move in canonical notation and commit the updated active game
 * before returning. There is no separate save operation.
 *
 * A malformed move returns MXQ_ERR_RULES_MALFORMED_MOVE and an illegal one
 * MXQ_ERR_RULES_ILLEGAL_MOVE. A game that already has a result of its own
 * returns MXQ_ERR_STATE_GAME_OVER; a claimable neutral repetition is not such a
 * result, because play continues there unless the claim is made. A store-domain
 * failure leaves the game exactly at its pre-mutation committed state; the move
 * did not happen.
 *
 * Thread: the session's owner; never inside a search callback. Off the UI
 * thread, except for the store-attached active game, whose own calls
 * docs/core-interface.md's threading contract documents as the one
 * exception.
 * Blocking: yes — the commit happens inside the call.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_apply_move(MxqGame *game, const char *move,
                                               MxqPosition *out_after,
                                               MxqGameStatus *out_status,
                                               MxqError *err);

/*
 * Undo, and commit the updated active game before returning.
 * *out_plies_removed is 1 or 2 per the decision-cycle rule, and matches the
 * undo_plies MxqGameStatus reported before the call. Undo with nothing to
 * remove returns MXQ_ERR_STATE_UNDO_UNAVAILABLE, which is exactly when
 * MxqGameStatus.undo_available reads 0. A store-domain failure leaves the game
 * exactly at its pre-mutation committed state.
 *
 * Thread: the session's owner; never inside a search callback. Off the UI
 * thread, except for the store-attached active game, whose own calls
 * docs/core-interface.md's threading contract documents as the one
 * exception.
 * Blocking: yes — the commit happens inside the call.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_undo(MxqGame *game,
                                         uint32_t *out_plies_removed,
                                         MxqError *err);

/*
 * Claim the neutral threefold repetition as a draw. Legal only in the
 * claimable state; otherwise MXQ_ERR_STATE_CLAIM_UNAVAILABLE.
 *
 * One atomic transaction: commit the outcome with reason
 * MXQ_END_REASON_THREEFOLD_REPETITION, insert the immutable History record, and
 * clear the active-game reference. On success the session is archived and
 * further mutations return MXQ_ERR_STATE_SESSION_ARCHIVED; the caller still
 * releases the handle. On a store-domain failure the game remains active and
 * unchanged and no History record exists.
 *
 * An archived session keeps answering every query — a frontend holding the
 * handle of a game that has just ended still has a board to show — and every
 * derived affordance then reads 0, because there is no longer an action to
 * offer. mxq_archive_encode on it produces the finished document the History
 * record holds, which is the same bytes mxq_store_history_open would return.
 *
 * Thread: the session's owner; never inside a search callback. Off the UI
 * thread, except for the store-attached active game, whose own calls
 * docs/core-interface.md's threading contract documents as the one
 * exception.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_claim_draw(MxqGame *game,
                                               uint64_t *out_record_id,
                                               MxqError *err);

/*
 * Resign for the human side, with reason MXQ_END_REASON_RESIGNATION, and the
 * outcome the win for the side opposite human_side. Same atomic transaction and
 * same archived-session consequence as mxq_game_claim_draw.
 *
 * Legal only in human-versus-AI play, and only while the game has no result of
 * its own — which is exactly when MxqGameStatus.resign_available reads 1.
 * Either refusal is MXQ_ERR_STATE_RESIGN_UNAVAILABLE, so the affordance and
 * the refusal are one rule: a resignation recorded over a natural result would
 * lose the result the game actually has, and the archive refuses it for the
 * same reason.
 *
 * Thread: the session's owner; never inside a search callback. Off the UI
 * thread, except for the store-attached active game, whose own calls
 * docs/core-interface.md's threading contract documents as the one
 * exception.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_resign(MxqGame *game,
                                           uint64_t *out_record_id,
                                           MxqError *err);

/*
 * Commit an unconfirmed natural terminal state as its actual result and exact
 * termination reason. Same atomic transaction and same archived-session
 * consequence as mxq_game_claim_draw.
 *
 * There must be a result to confirm: a position that is not terminal returns
 * MXQ_ERR_STATE_CONFIRM_UNAVAILABLE. A claimable neutral repetition is not
 * such a result — the game continues there unless the claim is made, and
 * making it is mxq_game_claim_draw's decision rather than this one's.
 *
 * Thread: the session's owner; never inside a search callback. Off the UI
 * thread, except for the store-attached active game, whose own calls
 * docs/core-interface.md's threading contract documents as the one
 * exception.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_confirm_result(MxqGame *game,
                                                   uint64_t *out_record_id,
                                                   MxqError *err);

/* ------------------------------------------------------------------------- */
/* Rules facade, session-free — mxq_rules_                                   */
/* ------------------------------------------------------------------------- */

/*
 * Write the frozen starting FEN and its length. Callable before
 * mxq_core_init: it is a constant of the ruleset, not of any core instance.
 * A cap below the required size returns MXQ_ERR_ARG_BUFFER_TOO_SMALL with
 * MxqError.required_size set; MXQ_FEN_CAP is always sufficient.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_rules_start_fen(char *out, size_t cap,
                                               size_t *out_len, MxqError *err);

/*
 * Validate a FEN. In version 1 this applies the frozen structural encoding
 * only, returning MXQ_ERR_RULES_INVALID_FEN on failure;
 * MXQ_ERR_RULES_ILLEGAL_POSITION is reserved for a future setup-legality
 * predicate and is never returned.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_rules_validate_fen(MxqCore *core,
                                                  const char *fen,
                                                  MxqError *err);

/*
 * Replay moves from start_fen and report the resulting position and game state.
 * This, with mxq_rules_legal_moves, is exactly the surface the approved
 * conformance fixtures replay through: every assertion in a fixture maps onto
 * these outputs.
 *
 * moves is an array of move_count NUL-terminated strings in canonical notation;
 * move_count 0 evaluates start_fen itself and moves may then be NULL. When a
 * move is not legal at its turn the function returns
 * MXQ_ERR_RULES_INVALID_HISTORY and sets *out_first_illegal_index to its index;
 * out_position and out_status are then unspecified. out_position, out_status
 * and out_first_illegal_index are each optional.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_rules_evaluate(MxqCore *core,
                                              const char *start_fen,
                                              const char *const *moves,
                                              size_t move_count,
                                              MxqPosition *out_position,
                                              MxqGameStatus *out_status,
                                              size_t *out_first_illegal_index,
                                              MxqError *err);

/*
 * The complete legal-move set in the position reached by replaying moves from
 * start_fen. Same history and buffer conventions as mxq_rules_evaluate and
 * mxq_game_legal_moves.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_rules_legal_moves(MxqCore *core,
                                                 const char *start_fen,
                                                 const char *const *moves,
                                                 size_t move_count,
                                                 MxqMove *out, size_t cap,
                                                 size_t *out_count,
                                                 MxqError *err);

/* ------------------------------------------------------------------------- */
/* Search facade, preparation — mxq_engine_                                  */
/* ------------------------------------------------------------------------- */

/*
 * Compute the engine plan for the supplied probe values. A pure function: it
 * touches no core state, initialises nothing, and is callable before
 * mxq_core_init, so every budget boundary is testable without an engine.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_engine_plan(const MxqEngineBudget *budget,
                                           MxqEnginePlan *out, MxqError *err);

/*
 * Recompute the same plan and apply it: threads, Hash, the pinned variant
 * configuration, and the NNUE. Below MXQ_ENGINE_MIN_HASH_MIB it returns
 * MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY without initialising anything, and never
 * substitutes a smaller Hash. The network is preflighted against the engine's
 * observable load state — the effective NNUE state after configuration, not
 * merely that the file exists and parses — so the engine's own fatal
 * verification path is never reached.
 *
 * Returns MXQ_ERR_STATE_SEARCH_IN_PROGRESS rather than stalling if a search is
 * outstanding.
 *
 * Thread: any non-UI thread except inside a search callback; the work executes
 * marshalled on the engine thread.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_engine_prepare(MxqCore *core,
                                              const MxqEngineBudget *budget,
                                              MxqEnginePlan *out_applied,
                                              MxqError *err);

/*
 * Release the transposition table and return the engine to
 * MXQ_ENGINE_STATE_UNINITIALIZED. Releases whole; it never shrinks Hash in
 * place. Returns MXQ_ERR_STATE_SEARCH_IN_PROGRESS rather than stalling if a
 * search is outstanding.
 *
 * Thread: any non-UI thread except inside a search callback; the work executes
 * marshalled on the engine thread.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_engine_teardown(MxqCore *core, MxqError *err);

/*
 * Report the engine's observable state and the profile identifier that
 * identifies the configuration a move would be produced by. Same buffer
 * convention as mxq_rules_start_fen; MXQ_PROFILE_ID_CAP is always sufficient.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_engine_query(MxqCore *core,
                                            MxqEngineState *out_state,
                                            char *out_profile_id, size_t cap,
                                            size_t *out_len, MxqError *err);

/* ------------------------------------------------------------------------- */
/* Search facade — mxq_search_                                               */
/* ------------------------------------------------------------------------- */

/*
 * Start a search and return its ticket. Does not retain the session: it
 * snapshots the initial FEN, the complete move list, the game_id, the
 * position_revision and the session's frozen movetime before returning.
 * request->movetime_ms must equal that frozen movetime, or MXQ_ERR_ARG_RANGE.
 *
 * callback may be NULL, in which case mxq_search_poll or mxq_search_wait is the
 * only consumer.
 *
 * Callback delivered on: the core's engine thread. See MxqSearchCallback for
 * what is legal inside it.
 *
 * Because this takes an MxqGame *, it counts as being inside that session for
 * the single-owner rule.
 *
 * Thread: the session's owner; any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_search_start(MxqCore *core, const MxqGame *game,
                                            const MxqSearchRequest *request,
                                            MxqSearchCallback callback,
                                            void *user_data,
                                            uint64_t *out_ticket,
                                            MxqError *err);

/*
 * Cancel one search cooperatively. Its callback still fires, with
 * MXQ_SEARCH_CANCELLED. Cancelling an unknown or already-finished ticket is
 * MXQ_OK.
 *
 * Cancellation is a correctness requirement rather than only a promptness
 * optimisation: a cancellation that follows no mutation leaves the position
 * revision matching, so the cancelled rung of the rejection ladder is the only
 * one that rejects the late result.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_search_cancel(MxqCore *core, uint64_t ticket,
                                             MxqError *err);

/*
 * Cancel every outstanding search cooperatively. Callbacks still fire.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_search_cancel_all(MxqCore *core, MxqError *err);

/*
 * Poll a ticket. Sets *out_ready to 1 and fills out when the result is
 * available, 0 otherwise. The result is retained under its ticket until the
 * next search or shutdown. Equivalent to the callback as a consumer; both may
 * be used.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_search_poll(MxqCore *core, uint64_t ticket,
                                           MxqSearchResult *out,
                                           uint8_t *out_ready, MxqError *err);

/*
 * Wait for a ticket, up to timeout_ms. Sets *out_ready to 0 on timeout, which
 * is MXQ_OK rather than an error.
 *
 * Thread: any non-UI thread except inside a search callback.
 * Blocking: yes, bounded by timeout_ms.
 */
MXQ_API MxqStatus MXQ_CALL mxq_search_wait(MxqCore *core, uint64_t ticket,
                                           uint32_t timeout_ms,
                                           MxqSearchResult *out,
                                           uint8_t *out_ready, MxqError *err);

/* ------------------------------------------------------------------------- */
/* Archive codec boundary — mxq_archive_                                     */
/* ------------------------------------------------------------------------- */

/*
 * Structural probe only: transport, size, syntax, envelope, version dispatch,
 * field validity — the closed vocabularies and the cross-field rules included.
 * It performs no rules replay, so it accepts a file whose move line
 * mxq_archive_validate would refuse; structural validity is all it claims. The
 * bytes are borrowed for the duration of the call and are untrusted input.
 *
 * out carries a decoded archive only on MXQ_OK. On every rejection it has been
 * zeroed and its struct_size rewritten to the size this build could interpret,
 * which is the core-wide convention for an out struct: every field the caller
 * can read is written exactly once, whether or not the call succeeds.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: CPU-bound; keep off the UI thread.
 */
MXQ_API MxqStatus MXQ_CALL mxq_archive_probe(MxqCore *core,
                                             const uint8_t *bytes, size_t len,
                                             MxqArchiveInfo *out,
                                             MxqError *err);

/*
 * Full validation: everything mxq_archive_probe does — and on success it fills
 * out identically — then rules replay through the rules facade: the initial
 * position must be exactly the frozen starting FEN in version 1, every move
 * must be legal in sequence, and the recorded terminal pair must agree with the
 * replayed adjudication. Touches no persistent state.
 *
 * An archive that records no end has no terminal pair to agree with: an
 * unconfirmed natural terminal position remains the active game, so it is as
 * valid there as an ongoing one.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: CPU-bound; keep off the UI thread.
 */
MXQ_API MxqStatus MXQ_CALL mxq_archive_validate(MxqCore *core,
                                                const uint8_t *bytes,
                                                size_t len,
                                                MxqArchiveInfo *out,
                                                MxqError *err);

/*
 * Encode a session as canonical archive bytes. The classification — outcome and
 * end reason — derives from the committed game state and never from the caller.
 * The caller releases the blob with mxq_blob_release.
 *
 * The bytes are a pure function of that committed state, the export event's own
 * origin member included: encoding one session twice, or encoding it again
 * after resuming it in another process, reproduces the same bytes, and they are
 * the bytes the store holds for an attached session. That is what lets a
 * content hash be compared rather than recomputed and a golden file be
 * compared byte for byte.
 *
 * Because this takes an MxqGame *, it counts as being inside that session for
 * the single-owner rule.
 *
 * Thread: the session's owner; any thread except inside a search callback.
 * Blocking: CPU-bound; keep off the UI thread.
 */
MXQ_API MxqStatus MXQ_CALL mxq_archive_encode(MxqCore *core,
                                              const MxqGame *game,
                                              MxqBlob **out_blob,
                                              MxqError *err);

/*
 * The archive format versions this build reads and writes. Callable before
 * mxq_core_init.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_archive_supported_versions(
    uint32_t *out_min_readable, uint32_t *out_current, MxqError *err);

/* ------------------------------------------------------------------------- */
/* Library store, active game — mxq_store_                                   */
/* ------------------------------------------------------------------------- */

/*
 * Whether the library holds an active game. A reference naming a row that is
 * not there is MXQ_ERR_STORE_CORRUPT rather than an answer of 0.
 *
 * Thread: any thread except inside a search callback, off the UI thread.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_active_exists(MxqCore *core,
                                                   uint8_t *out_exists,
                                                   MxqError *err);

/*
 * The active game's summary and live state without materialising a session,
 * which is what the Play destination and the save-and-continue confirmation
 * need. Sets *out_exists to 0 and returns MXQ_OK when there is no active game.
 * out and out_status are each optional.
 *
 * The summary of an active game has no committed outcome: added_at_ms is 0,
 * end_reason is MXQ_END_REASON_NONE, outcome reads MXQ_OUTCOME_NONE for want
 * of an absent constant, pinned is 0, and is_active is 1. The live state comes
 * from replaying the stored line, exactly as a session's does; no state flag
 * is persisted.
 *
 * Thread: any thread except inside a search callback, off the UI thread.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_active_summary(MxqCore *core,
                                                    MxqRecordSummary *out,
                                                    MxqGameStatus *out_status,
                                                    uint8_t *out_exists,
                                                    MxqError *err);

/*
 * Place the active game in History and clear the active-game reference in one
 * atomic transaction. This is the save-before-mode path and the only one that
 * may record MXQ_END_REASON_ENDED_EARLY; the classification is derived from the
 * committed state, never supplied. An unconfirmed natural terminal state keeps
 * its actual result and exact reason; every other state — an ordinary ongoing
 * game, and an unclaimed claimable repetition, which is still one — is
 * recorded as ended early with no competitive result.
 *
 * The one required pointer here is the active game itself, so its absence is a
 * state rather than a programming error, and the three absent shapes stay
 * distinguishable: a NULL session returns MXQ_ERR_STATE_ACTIVE_GAME_MISSING;
 * a session already archived returns MXQ_ERR_STATE_SESSION_ARCHIVED, because
 * archived and missing are different facts; and a live session whose row the
 * library no longer names as active returns MXQ_ERR_STORE_NOT_FOUND. Each
 * changes nothing.
 *
 * On success the passed session is marked archived and later mutations on it
 * return MXQ_ERR_STATE_SESSION_ARCHIVED; the caller still releases the handle.
 * On failure the previously committed active game is intact and unchanged.
 *
 * Because this takes an MxqGame *, it counts as being inside that session for
 * the single-owner rule.
 *
 * Thread: the session's owner; any thread except inside a search callback, off
 * the UI thread.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_archive_and_clear(MxqCore *core,
                                                       MxqGame *active,
                                                       uint64_t *out_record_id,
                                                       MxqError *err);

/* ------------------------------------------------------------------------- */
/* Library store, history — mxq_store_                                       */
/* ------------------------------------------------------------------------- */

/*
 * The number of History records, and the library revision: a monotonic counter
 * bumped by every committed store mutation. Return values plus this cheap
 * staleness check are the accepted answer to library-change observation; there
 * is no notification mechanism.
 *
 * Thread: any thread except inside a search callback, off the UI thread —
 * except from the app's own History surface, which docs/core-interface.md's
 * threading contract documents alongside the active game's calls.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_history_count(
    MxqCore *core, uint32_t *out_count, uint64_t *out_library_revision,
    MxqError *err);

/*
 * One page of History, in the accepted order — pinned first, then newest
 * History-added time within each group, then record_id descending. The order
 * is a core guarantee; frontends never re-sort.
 *
 * The buffer convention is not mxq_game_legal_moves': there the count is the
 * answer and a small buffer is a routine way to ask for it, while here the
 * caller chose the page size itself. cap below limit is therefore a caller bug
 * — MXQ_ERR_ARG_BUFFER_TOO_SMALL with MxqError.required_size set to limit, and
 * nothing written. *out_count is the number of records written, which is fewer
 * than limit only at the end of the list; use mxq_store_history_count for the
 * total. limit 0 writes nothing and is not an error. On any failure *out_count
 * is 0 and the buffer's contents are unspecified — a corrupt record fails the
 * call at its own element, after earlier elements were already written. Each written element's
 * struct_size is stamped by the core rather than read, as mxq_game_legal_moves
 * stamps a move's: an array is indexed by an element size the two sides have
 * already agreed on.
 *
 * Thread: any thread except inside a search callback, off the UI thread —
 * except from the app's own History surface, which docs/core-interface.md's
 * threading contract documents alongside the active game's calls.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_history_page(
    MxqCore *core, uint32_t offset, uint32_t limit, MxqRecordSummary *out,
    size_t cap, size_t *out_count, uint64_t *out_library_revision,
    MxqError *err);

/*
 * One History record's summary. Returns MXQ_ERR_STORE_NOT_FOUND for an unknown
 * record_id, and for the active game's, which is not a History record; is_active
 * therefore always reads 0 here.
 *
 * Thread: any thread except inside a search callback, off the UI thread.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_history_get(MxqCore *core,
                                                 uint64_t record_id,
                                                 MxqRecordSummary *out,
                                                 MxqError *err);

/*
 * Open a History record as a detached read-only session for replay. Every query
 * answers as it does on any session — the position at each ply, the move line,
 * the frozen configuration, the identity — while every derived affordance reads
 * 0, because a finished game offers no action. Mutations on it return
 * MXQ_ERR_STATE_SESSION_READ_ONLY. Returns MXQ_ERR_STORE_NOT_FOUND for an
 * unknown record_id, and MXQ_ERR_STORE_CORRUPT for a row this build can no
 * longer read, hash-match, or reproduce.
 *
 * MxqGameStatus.state is still the replayed position's verdict, which for a
 * resignation or an ended-early record is not the committed outcome at all:
 * that is MxqOutcome, and mxq_store_history_get is where it is read.
 *
 * Thread: any non-UI thread except inside a search callback — except from
 * the app's own History surface, which docs/core-interface.md's threading
 * contract documents alongside the active game's calls. This is the one
 * of those whose cost rises with the game's own length.
 * Blocking: yes — store work.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_history_open(MxqCore *core,
                                                  uint64_t record_id,
                                                  MxqGame **out_replay,
                                                  MxqError *err);

/*
 * Set or clear a record's pin state, the only mutable field of a History
 * record. pinned is 0 or 1; any other value is a programming error and returns
 * MXQ_ERR_ARG_RANGE. An unknown record_id, and the active game's — which the
 * schema forbids pinning — are MXQ_ERR_STORE_NOT_FOUND.
 *
 * Thread: any thread except inside a search callback, off the UI thread —
 * except from the app's own History surface, which docs/core-interface.md's
 * threading contract documents alongside the active game's calls.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_history_set_pinned(MxqCore *core,
                                                        uint64_t record_id,
                                                        uint8_t pinned,
                                                        MxqError *err);

/*
 * Permanently delete a History record, whole. There is no soft delete and no
 * undo. A failed deletion leaves the existing record intact. An unknown
 * record_id, and the active game's, are MXQ_ERR_STORE_NOT_FOUND. A record_id is
 * never issued again after its record is deleted, so a stale one held across a
 * deletion dangles rather than resolving to some later game.
 *
 * Thread: any thread except inside a search callback, off the UI thread —
 * except from the app's own History surface, which docs/core-interface.md's
 * threading contract documents alongside the active game's calls.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_history_delete(MxqCore *core,
                                                    uint64_t record_id,
                                                    MxqError *err);

/* ------------------------------------------------------------------------- */
/* Library store, interchange — mxq_store_                                   */
/* ------------------------------------------------------------------------- */

/*
 * Export one immutable History record as portable archive bytes. The caller
 * releases the blob with mxq_blob_release. The active game is not a History
 * record, so its record_id is MXQ_ERR_STORE_NOT_FOUND exactly as an identifier
 * that was never issued is.
 *
 * One member of the document is regenerated and no other: origin describes the
 * export event, so it names this one. The content — the moves, the frozen
 * configuration, the identity, the ending — and therefore the content hash are
 * the record's own, unchanged, which is what lets an exported file be compared
 * with the row it came from and with another export of the same record.
 *
 * Thread: any thread except inside a search callback, off the UI thread.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_export(MxqCore *core, uint64_t record_id,
                                            MxqBlob **out_blob, MxqError *err);

/*
 * Import one game file. Nothing touches the database until validation
 * completes, and a game is never partially imported. A successful import always
 * creates an immutable History record and never creates or replaces the active
 * game.
 *
 * An exact duplicate — same game_id, same archive version, same content hash
 * and bytes — sets *out_outcome to MXQ_IMPORT_EXISTING and returns the existing
 * record: success, not an error, and nothing is written, so the library
 * revision does not move either. The same identity with differing content is
 * MXQ_ERR_STORE_IDENTITY_CONFLICT. Every other rejection class returns its own
 * typed error. out_outcome, out_record_id and out_summary are each optional,
 * and out_outcome is meaningful only on MXQ_OK.
 *
 * The record is marked imported by the library rather than by the file: origin
 * is stored as the file gave it, because it describes an export event that
 * really happened, and it is never what sets provenance. The History-added time
 * that orders the list is the import, not the game's own dates.
 *
 * The bytes are borrowed for the duration of the call and are untrusted input.
 *
 * Thread: any thread except inside a search callback, off the UI thread.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_store_import(MxqCore *core, const uint8_t *bytes,
                                            size_t len,
                                            MxqImportOutcome *out_outcome,
                                            uint64_t *out_record_id,
                                            MxqRecordSummary *out_summary,
                                            MxqError *err);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* MXQ_H */
