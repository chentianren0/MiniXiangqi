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
 * 63 functions, three opaque handles.
 *
 * The core plays four games — Mini Xiangqi, Xiangqi, Gomoku and Renju — and
 * MxqGameKind is the axis that names which. Every rules question is asked of one
 * game: the board, the move notation, the starting position, the adjudication
 * rules and the engine it is played on all follow from it, and nothing infers it
 * from a position.
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
 *     defined over a game, an initial position and a complete move history —
 *     never a bare FEN, because repetition and violation state derive from
 *     history, and never without the game, because the rules are not a property
 *     of the position.
 *
 * Each function below states the thread it may be called from and whether it
 * blocks, and every function that delivers a callback states which thread
 * delivers it, as docs/architecture.md requires of this boundary.
 *
 * Reserved fields exist only to keep every struct free of implicit padding, so
 * that the layout is identical under every supported compiler. They must be
 * written as zero and must be ignored when read — which is also what lets a
 * later minor version give one a name and a meaning: nothing moves, and no
 * caller could have been reading a value there.
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
#define MXQ_API_VERSION_MAJOR 3
#define MXQ_API_VERSION_MINOR 2
#define MXQ_API_VERSION_PATCH 0

/* ------------------------------------------------------------------------- */
/* Capacities                                                                */
/* ------------------------------------------------------------------------- */

/* A move, in whichever of the two grammars its game has. A square is a file
 * letter and a rank written in decimal, so it is two characters on a board of
 * seven ranks and up to three on one of ten or fifteen. A movement game spells
 * "<from><to>" and reaches six characters at "a9a10"; a placement game spells
 * one square and reaches three at "o15". 8 leaves room for the NUL and keeps the
 * struct 4-aligned. No move suffix exists in any ruleset. */
#define MXQ_MOVE_TEXT_CAP 8

/*
 * A 6-field FEN of any game, NUL-terminated. Fixed rather than per-game so that
 * MxqPosition has one layout.
 *
 * Sized for the largest board this core may plausibly ever carry rather than for
 * the largest it carries today, so that a bigger game later costs no second
 * change to this struct's size. The arithmetic, at 19x19 — the largest square
 * board any of these games is played on anywhere:
 *
 *     board field   19 characters per rank x 19 ranks, plus 18 separators = 379
 *     the suffixes  " w - - 361 181" at their longest = 14
 *     the NUL       1
 *                                                        total = 394
 *
 * 512 is the next power of two above that and leaves 118 bytes spare. Today's
 * widest is a full 15x15 placement board: 239 characters of field, and 12 of
 * suffix — " b - - 0 113", the fullmove number of a 225-ply game running to
 * three digits.
 */
#define MXQ_FEN_CAP 512

/* One square of a game's board, NUL-terminated: a file letter followed by a
 * rank in decimal without a leading zero. Three characters at "a10" and "o15",
 * so 4 carries the NUL and keeps a struct holding one 4-aligned. It is wide
 * enough for any board this core may plausibly carry, a rank of two digits
 * reaching 99. MxqSetupViolation is what needs it: a violation the caller can
 * point at is a violation at a square. */
#define MXQ_SQUARE_TEXT_CAP 4

/* MxqError.detail: a short English diagnostic. Final, and measured: the longest
 * fixed diagnostic in the core is 112 bytes, so every path-free diagnostic fits
 * whole. Diagnostics that embed a caller-supplied filesystem path are unbounded
 * by nature and are composed diagnosis-first, so what truncation costs is the
 * path rather than the fact. See docs/core-interface.md, "Capacity constants". */
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

/* The two identifiers a nearby game's wire session is held by. Both are opaque
 * to the core, which stores and returns them and compares neither: the session
 * identifier is the proposer-minted string the two peers compare byte-wise, and
 * the peer identifier is the transport's own name for the paired device. The
 * caps are the smallest that hold a UUID and a transport-prefixed one with room
 * to spare; a longer value is MXQ_ERR_ARG_RANGE rather than a truncation. */
#define MXQ_NEARBY_SESSION_ID_CAP 128
#define MXQ_NEARBY_PEER_ID_CAP 128

/* ------------------------------------------------------------------------- */
/* Status codes                                                              */
/* ------------------------------------------------------------------------- */

/*
 * MxqStatus codes are grouped in 1000-blocks. mxq_status_domain returns the
 * block. Frontends select their presentation family by domain and their copy by
 * exact code, and must tolerate an unknown code within a known domain: every
 * switch over MxqStatus requires a default arm.
 *
 * Programming errors assert in debug builds, return their code in release
 * builds, and never change state. What makes a status one is reachability, not
 * its domain: a caller that had every fact it needed could not have reached it
 * except by its own defect. Those are a null required pointer, a handle this
 * core never issued, a struct_size this build cannot interpret, an incompatible
 * MXQ_API_VERSION, a value outside a closed vocabulary the frontend itself owns
 * (a square its own board does not have, a game configuration of neither
 * accepted shape, a pinned that is not 0 or 1), a second mxq_core_init, a core
 * handle that is not the live instance, and any call requiring a mutable
 * session made on a detached read-only one — a mutation, or a hint.
 *
 * Four argument-domain statuses are deliberately not programming errors and
 * never assert, because each is an answer the core promises rather than a
 * caller it catches: MXQ_ERR_ARG_BUFFER_TOO_SMALL, the routine way to ask for a
 * size; MXQ_ERR_ARG_INVALID_HANDLE from a session handle outstanding across
 * mxq_core_shutdown, which the shutdown rule requires it to answer;
 * MXQ_ERR_ARG_CONCURRENT_USE, which reports a detected race rather than
 * aborting on a timing accident; and MXQ_ERR_ARG_REENTRANT, which the body of a
 * callback must be able to receive. MXQ_ERR_ARG_RANGE splits on the same test
 * rather than by code — see mxq_game_position_at, mxq_search_start and
 * mxq_search_start_hint, which return it without asserting.
 *
 * Every other status is ordinary control flow and leaves the last committed
 * state intact.
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
    MXQ_ERR_RULES_MALFORMED_MOVE   = 3001, /* not a move of the game's own board.
                                            * A square is a file letter and a
                                            * rank in decimal without a leading
                                            * zero; how many squares a move is
                                            * follows from the game and never
                                            * from the text's length. A movement
                                            * game spells two — ^([a-g][1-7]){2}$
                                            * in Mini Xiangqi,
                                            * ^([a-i](10|[1-9])){2}$ in Xiangqi —
                                            * and a placement game spells one:
                                            * ^[a-o](1[0-5]|[1-9])$ in Gomoku and
                                            * Renju */
    MXQ_ERR_RULES_ILLEGAL_MOVE     = 3002, /* well-formed but not legal here */
    MXQ_ERR_RULES_INVALID_FEN      = 3003, /* fails the frozen structural
                                            * encoding of the game it was asked
                                            * about */
    MXQ_ERR_RULES_ILLEGAL_POSITION = 3004, /* structurally a position of this
                                            * game's board, but not one the game
                                            * may be set up in. The setup
                                            * question's refusal wherever it is
                                            * asked: from
                                            * mxq_rules_validate_setup, from
                                            * mxq_game_create for a start the
                                            * game will not begin from, and from
                                            * mxq_archive_validate and
                                            * mxq_store_import for a document
                                            * whose start the predicate refuses.
                                            * MxqSetupViolation carries which
                                            * rule it breaks where the entry
                                            * offers one */
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
/*
 * The two sides, named for the xiangqi pieces and meaning "the side that moves
 * first" and "the other" in every game. The placement games call their sides
 * black and white stones and Black moves first, so MXQ_COLOR_RED is the black
 * stone there: the core keeps one colour axis and one first-mover rule, and what
 * a side is drawn and called is the frontend's, exactly as "minixiangqi" naming
 * MXQ_GAME_KIND_MINI_XIANGQI is.
 */
typedef int32_t MxqColor;
enum {
    MXQ_COLOR_NONE  = -1,
    MXQ_COLOR_RED   = 0, /* uppercase pieces and stones, moves first */
    MXQ_COLOR_BLACK = 1  /* lowercase pieces and stones */
};

typedef int32_t MxqPlayMode;
enum {
    MXQ_PLAY_MODE_HUMAN_VS_AI = 0, /* serialised "human-vs-ai" */
    MXQ_PLAY_MODE_FREE_PLAY   = 1, /* serialised "free-play" */
    MXQ_PLAY_MODE_NEARBY      = 2  /* serialised "nearby": one game played by
                                    * two devices. Like Free Play it carries
                                    * none of the four human-versus-AI members;
                                    * unlike either local mode it can end by an
                                    * agreement between the two players, which
                                    * is what the last two MxqEndReason values
                                    * record */
};

/*
 * Which game is being played: the board, the move notation, the starting
 * position, the adjudication rules and the engine all follow from it. It is the
 * archive's rules_id, and it is deliberately not MxqPlayMode: how a game is
 * played against whom is a different question from which game it is, and every
 * combination of the two exists.
 *
 * A game's kind is frozen at creation and is never inferred from a position.
 * Gomoku and Renju share a board exactly, and the two xiangqi boards differ in
 * size — so a FEN happens to imply one of those two, and implies nothing at all
 * about the other pair. The ruleset is not a property of the board, and a core
 * that read it off the position would be guessing.
 *
 * A rules-and-size combination is its own game rather than an option of one:
 * Gomoku and Renju differ in what Black may play and in what wins, which is not
 * a setting a game can carry mid-line.
 *
 * The vocabulary is the header's; which of it a build carries is the build's. A
 * core compiled without the engine a game is played on does not carry that game,
 * and every entry taking MxqGameKind answers MXQ_ERR_ARG_RANGE for it exactly as
 * for a value outside the vocabulary. Every shipped build carries all four.
 */
typedef int32_t MxqGameKind;
enum {
    MXQ_GAME_KIND_MINI_XIANGQI = 0, /* serialised "minixiangqi"; 7x7 */
    MXQ_GAME_KIND_XIANGQI      = 1, /* serialised "xiangqi"; 9x10 */
    MXQ_GAME_KIND_GOMOKU_15    = 2, /* serialised "gomoku-15"; 15x15 freestyle */
    MXQ_GAME_KIND_RENJU        = 3  /* serialised "renju"; 15x15, with Black's
                                     * forbidden moves */
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
 * The rule reasons are the fixture reason identifiers; the rest are the ends a
 * player or a pair of players decide. In both rulesets threefold repetition is
 * always a claim and every other rule reason is automatic, so the reason
 * determines the mechanism and no claimed-versus-automatic flag exists.
 *
 * A declared end never records who declared it as a person or a device — the
 * archive is device-portable (docs/game-data.md) — and never needs to: a
 * resignation's outcome names the winner, so the side that resigned is its
 * opposite, and the two draws name no side at all.
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
    MXQ_END_REASON_ENDED_EARLY            = 9, /* "ended-early" */
    MXQ_END_REASON_FIFTY_MOVE_RULE        = 10, /* "fifty-move-rule"; a draw, and
                                                 * Xiangqi's alone: Mini Xiangqi
                                                 * has no move-count rule, so
                                                 * this reason cannot arise
                                                 * there. Automatic, like every
                                                 * rule reason but the neutral
                                                 * repetition */
    MXQ_END_REASON_AGREED_DRAW            = 11, /* "agreed-draw"; a draw, and
                                                 * MXQ_PLAY_MODE_NEARBY's alone:
                                                 * the two players agreed to it */
    MXQ_END_REASON_MUTUAL_RESIGNATION     = 12, /* "mutual-resignation"; a draw,
                                                 * and nearby's alone: both
                                                 * players resigned, which is a
                                                 * draw rather than two losses */
    MXQ_END_REASON_FIVE_IN_A_ROW          = 13, /* "five-in-a-row"; the placement
                                                 * games' win, and theirs alone.
                                                 * What counts as one is the
                                                 * game's: Gomoku wins with five
                                                 * or more, and Renju with five
                                                 * or more for White and exactly
                                                 * five for Black */
    MXQ_END_REASON_BOARD_FULL             = 14  /* "board-full"; a draw, and the
                                                 * placement games' alone: every
                                                 * point is taken and no line of
                                                 * five was made. Automatic, like
                                                 * every rule reason but the
                                                 * neutral repetition */
};

/*
 * Which setup rule a position breaks, as mxq_rules_validate_setup reports it.
 *
 * It is a closed vocabulary of classes rather than a sentence, because the
 * frontend that shows the player why a set-up position is refused must localise
 * that sentence: a core that composed one would be composing display copy, and
 * MxqError.detail is deliberately never that. One class plus a side and, where
 * there is one, a square is everything such a sentence is built from.
 *
 * The classes are the rules of docs/xiangqi-rules.md read as a set-up
 * predicate, one class per rule that a position can break on its own:
 *
 *   PIECE_COUNT        a side has more of a piece than the game gives it — or,
 *                      for the general, other than the one it has
 *   PALACE             a general or an advisor stands outside its own palace
 *   ELEPHANT_SIDE      an elephant stands off its own side's seven points,
 *                      which is where "an elephant never crosses the river"
 *                      leaves it
 *   SOLDIER_RANK       a soldier stands behind its own starting soldier rank,
 *                      which it can never move back to
 *   FACING_GENERALS    the two generals face each other on an otherwise empty
 *                      file. It is its own class rather than a case of the one
 *                      below because the relation is symmetric and belongs to
 *                      neither side, and because it is the one refusal a player
 *                      reads as a rule about generals rather than about check
 *   OPPONENT_IN_CHECK  the side that is NOT to move stands in check, which no
 *                      position a game could be played from ever does. The side
 *                      that IS to move may stand in check: it answers as its
 *                      first move
 *   NOT_FROZEN_START   the game accepts only its frozen starting position, and
 *                      this is another. Every game but Xiangqi is that game
 *
 * MXQ_SETUP_RULE_NONE is the legal setup, and the value MxqSetupViolation
 * carries whenever mxq_rules_validate_setup does not return
 * MXQ_ERR_RULES_ILLEGAL_POSITION — on MXQ_OK, and on the structural refusal
 * that never reaches these rules at all.
 */
typedef int32_t MxqSetupRule;
enum {
    MXQ_SETUP_RULE_NONE              = 0,
    MXQ_SETUP_RULE_PIECE_COUNT       = 1, /* fixture "piece-count" */
    MXQ_SETUP_RULE_PALACE            = 2, /* fixture "palace" */
    MXQ_SETUP_RULE_ELEPHANT_SIDE     = 3, /* fixture "elephant-side" */
    MXQ_SETUP_RULE_SOLDIER_RANK      = 4, /* fixture "soldier-rank" */
    MXQ_SETUP_RULE_FACING_GENERALS   = 5, /* fixture "facing-generals" */
    MXQ_SETUP_RULE_OPPONENT_IN_CHECK = 6, /* fixture "opponent-in-check" */
    MXQ_SETUP_RULE_NOT_FROZEN_START  = 7  /* fixture "not-frozen-start" */
};

/* How a record entered this library. Local metadata, never an archive field. */
typedef int32_t MxqProvenance;
enum {
    MXQ_PROVENANCE_LOCALLY_PLAYED = 0, /* "locally-played" */
    MXQ_PROVENANCE_IMPORTED       = 1, /* "imported" */
    MXQ_PROVENANCE_DERIVED        = 2  /* "derived"; reserved, and rejected by
                                        * archive version 5. A game composed
                                        * from a position is identified by that
                                        * position, which start_fen already
                                        * carries, so nothing writes this */
};

/*
 * The terminal a nearby peer has sent for its session, which the BoardGame
 * protocol's resume exchange states and which decides whether that peer holds
 * the session settled. MXQ_NEARBY_TERMINAL_NONE is "this device has sent none",
 * and it is what a session in ordinary play carries.
 */
typedef int32_t MxqNearbyTerminal;
enum {
    MXQ_NEARBY_TERMINAL_NONE        = 0,
    MXQ_NEARBY_TERMINAL_RESIGN      = 1, /* stored "resign" */
    MXQ_NEARBY_TERMINAL_ACCEPT_DRAW = 2  /* stored "accept_draw" */
};

/*
 * Which peer proposed a nearby session — the only asymmetry a session ever has,
 * and the reason it is worth a column: the resume exchange completes on the
 * connection the *proposer* chose, so a peer that forgot which it was could not
 * re-bind a session it had held for days. Every other asymmetry a session needs
 * is the mover, and the mover is MxqGameConfig.local_side.
 */
typedef int32_t MxqNearbyProposer;
enum {
    MXQ_NEARBY_PROPOSER_LOCAL = 0, /* stored "local": this device proposed */
    MXQ_NEARBY_PROPOSER_PEER  = 1  /* stored "peer" */
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

/* The thinking times of the levels the product offers, one of them frozen with
 * a created human-versus-AI game. A game keeps what it froze however these are
 * retuned later, so a game's own frozen value is not always one of them:
 * mxq_search_start_hint, which takes a thinking time as a value, accepts one of
 * these or the attached session's frozen value where that is positive. */
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
 * The four independent version axes, and the two build revisions that are facts
 * about this core rather than about either game. The revisions are load-bearing
 * rather than diagnostics: conformance depends on a fork build, so every test
 * report and saved diagnostic must be able to name the build that produced it.
 *
 * What a game binds — its engine variant and that variant's network — is not
 * here, because there are two of each and one field cannot carry both. It is
 * MxqGameProfile, asked per game.
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
} MxqVersion;

/*
 * What one game binds to: the engine variant its rules are played under and the
 * network that variant is searched with. Both are pinned per game, and reading
 * a network against the other game's pins would verify it against nothing —
 * which is why this is one struct rather than two parallel lookups.
 *
 * variant_id is the identifier the game's own engine knows it by. nnue_sha256 is
 * the network pinned for it; where a game pins a network per side — Renju does,
 * its two sides being trained apart — this is the one Black plays with, and the
 * pins move together, so it names the pinned set rather than only itself.
 */
typedef struct MxqGameProfile {
    uint32_t    struct_size;
    MxqGameKind game;
    char        variant_id[MXQ_VARIANT_ID_CAP]; /* the pinned engine variant */
    char        nnue_sha256[MXQ_SHA256_HEX_CAP]; /* lowercase hexadecimal */
} MxqGameProfile;

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
 *
 * The FEN is six fields for every game. The xiangqi games' encoding is the
 * frozen one of docs/xiangqi-rules.md. The placement games take the same shape,
 * and the shape is the whole of what they share with it:
 *
 *     <board> <side to move> - - <halfmove clock> <fullmove number>
 *
 * The board field is fifteen ranks separated by '/', highest rank first and file
 * a leftmost within each, exactly as the xiangqi games write theirs. A run of
 * empty points is its count in decimal; a stone is one letter, and the letter is
 * a stone's kind while its case is its side — 'S' for the first mover's stone
 * and 's' for the other's, which is the convention the xiangqi games' piece
 * letters already follow. It is deliberately not 'b' and 'w' for the black and
 * white stones the player sees: the case already carries the side, the side-to-
 * move field already spells the first mover 'w', and a board field naming the
 * first mover 'b' beside it would read as its own contradiction.
 *
 * The third and fourth fields are '-' in these games, which have neither of the
 * things they record, and the halfmove clock is always 0: nothing is ever
 * captured and no placement is reversible, so no move-count rule can exist to
 * count toward. They are carried rather than dropped so that one FEN shape
 * serves every game and nothing above this interface parses two.
 *
 * in_check is 0 in the placement games, which have no check to be in.
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
    /* Whose turn it is in the position this line has reached, derived from the
     * start position and the plies. It is here as well as on MxqPosition
     * because mxq_store_active_summary reports a status and no position, and
     * the Play home's side-to-move line is read rather than worked out: a game
     * whose start has Black to move has Black making ply 0, so a frontend
     * counting plies would name the wrong side. Both are one replay's answer,
     * never a stored flag. */
    MxqColor     side_to_move;
} MxqGameStatus;

/*
 * What mxq_rules_validate_setup found: the first violation, or none.
 *
 * The first is enough. A position with two faults is refused either way, and a
 * player fixing the one named will be told about the next; a list would be a
 * second thing to keep in step with the classes for no decision it changes.
 *
 * rule is which setup rule broke. side is the side the violation belongs to,
 * and square the point it stands at, where either is meaningful:
 *
 *   PIECE_COUNT        side is the over-supplied side; square is empty, because
 *                      a count is a property of a side and not of a point
 *   PALACE             side and square are the offending piece's
 *   ELEPHANT_SIDE      likewise
 *   SOLDIER_RANK       likewise
 *   FACING_GENERALS    side is MXQ_COLOR_NONE and square is empty: the relation
 *                      is between the two generals and belongs to neither side,
 *                      and the frontend knows where both stand
 *   OPPONENT_IN_CHECK  side is the checked side, which is the side not to move;
 *                      square is its general's
 *   NOT_FROZEN_START   side is MXQ_COLOR_NONE and square is empty: what is
 *                      refused is the whole position
 *   NONE               side is MXQ_COLOR_NONE and square is empty
 *
 * square is a NUL-terminated square of the game's own board, or "" where the
 * class has none. Every field is always written, so a caller reads them without
 * first branching on the class.
 */
typedef struct MxqSetupViolation {
    uint32_t     struct_size;
    MxqSetupRule rule;
    MxqColor     side;
    char         square[MXQ_SQUARE_TEXT_CAP]; /* UTF-8, NUL-terminated */
} MxqSetupViolation;

/*
 * A game's frozen configuration. human_side, ai_level, ai_movetime_ms and
 * first_mover_choice are meaningful only when mode is
 * MXQ_PLAY_MODE_HUMAN_VS_AI; in Free Play they read as the NONE constants and
 * zero, matching the archive, which simply omits them.
 *
 * human_side is the resolved side: it is MXQ_COLOR_RED or MXQ_COLOR_BLACK in a
 * human-versus-AI game even when first_mover_choice is MXQ_FIRST_MOVER_RANDOM,
 * which is retained only because it cannot be reconstructed later.
 *
 * game is frozen with the rest and is what every later question about this
 * session is asked under: its starting position, its move notation, its
 * legality and its adjudication. It is required in every mode — every game is
 * some game.
 *
 * local_side is the one member that is not archive content. It is the side this
 * device's player took, meaningful exactly in MXQ_PLAY_MODE_NEARBY and
 * MXQ_COLOR_NONE everywhere else, and the archive never writes it: which side
 * is local is true of a device rather than of the game, and the portability law
 * in docs/game-data.md keeps that out of a file two devices could exchange. The
 * store holds it as library metadata beside pin state and provenance, and it is
 * what MxqRecordSummary.local_side reads back.
 *
 * start_fen is the position the game begins from, and the empty string is that
 * game's frozen start. A non-empty value is asked the three questions
 * mxq_game_create documents, and the core keeps the member canonical: a start
 * that is the frozen one reads back empty, so one committed game answers one
 * way whether it was just created or resumed from the store.
 */
typedef struct MxqGameConfig {
    uint32_t            struct_size;
    MxqPlayMode         mode;
    MxqColor            human_side;
    MxqAiLevel          ai_level;
    MxqFirstMoverChoice first_mover_choice;
    uint32_t            ai_movetime_ms; /* the exact frozen movetime */
    MxqGameKind         game;
    MxqColor            local_side;
    char                start_fen[MXQ_FEN_CAP]; /* "" is the frozen start */
} MxqGameConfig;

/*
 * The wire session a nearby active game is being played over, as
 * docs/game-data.md's nearby_session table holds it.
 *
 * It is not archive content and it is not a game's configuration: it is what the
 * BoardGame protocol needs to continue an interrupted session after this
 * application has been relaunched, and the portability law keeps every one of
 * these values out of a file two devices could exchange. The core stores and
 * returns it and interprets none of it except claimed, which is a ply count, and
 * the closed vocabularies below.
 *
 *   session_id  the proposer-minted identifier the two peers compare byte-wise
 *   peer_id     the transport's own name for the paired device on the other end
 *   proposer    which peer proposed, which decides the completing connection of
 *               a resume exchange
 *   undos       accepted retractions, zero at birth
 *   keep        the surviving ply count of the last accepted retraction, and
 *               zero while undos is zero and there has been none. It is
 *               deliberately not the session's own count there: the protocol's
 *               resume echoes the count in that case and reads this only when
 *               undos is above zero, and a value that moved with every ply
 *               would make every ply a second transaction
 *   sent_end    the terminal this device has sent, if it has sent one
 *   claimed     1 when the session's last ply is the rules contract's claim turn
 *               action, which the archive deliberately does not record: an
 *               unfinished game has no terminal trio to derive it from, and a
 *               peer that resumed a ply short of its opponent would be sent that
 *               ply back on a turn that is not the sender's — a violation, and a
 *               claimed draw lost
 *
 * A resumed session's mover is MxqGameConfig.local_side and is not repeated
 * here: one fact, one place.
 *
 * The two identifiers are NUL-terminated on the way out. On the way in they are
 * borrowed for the duration of the call, must be non-empty, and must fit their
 * capacity.
 */
typedef struct MxqNearbySession {
    uint32_t          struct_size;
    MxqNearbyProposer proposer;
    uint32_t          undos;
    uint32_t          keep;
    MxqNearbyTerminal sent_end;
    uint8_t           claimed;
    uint8_t           reserved0[3];
    char              session_id[MXQ_NEARBY_SESSION_ID_CAP];
    char              peer_id[MXQ_NEARBY_PEER_ID_CAP];
} MxqNearbySession;

/*
 * The queryable summary of one stored game: the History list's metadata, plus
 * the identity and timestamps.
 *
 * Every field is exactly recomputable from the stored archive blob except the
 * four the blob does not decide, which are local library metadata: provenance,
 * pinned, added_at_ms, and local_side. local_side is MXQ_COLOR_RED or
 * MXQ_COLOR_BLACK exactly for a locally played MXQ_PLAY_MODE_NEARBY record and
 * MXQ_COLOR_NONE for every other row, an imported nearby record included — an
 * imported game had no local player.
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
    MxqGameKind   game;            /* which game this record is of; a History
                                    * list holds both */
    MxqColor      local_side;      /* the side this device's player took, in a
                                    * locally played nearby record; otherwise
                                    * MXQ_COLOR_NONE */
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
    MxqGameKind  game;          /* the file's rules_id, decoded: which game it
                                 * is a record of */
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
 *
 * movetime_ms is a cross-check rather than an input, and deliberately so: the
 * core already holds the only legal value, but the caller computes its own from
 * the AI level the player chose, and the two disagreeing is the one bug that
 * would otherwise be silent and permanent — a move thought for a time the
 * archive does not record. See docs/core-interface.md, the search facade.
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
 * mxq_blob_release — together with the six pure queries that take no core
 * instance and no lock: mxq_core_version, mxq_core_game_profile,
 * mxq_rules_start_fen, mxq_engine_plan, mxq_engine_profile_id and
 * mxq_archive_supported_versions.
 * Every other core function that can report
 * returns MXQ_ERR_ARG_REENTRANT, before it judges any handle it was passed;
 * mxq_game_release returns void and so has nothing to report with, and is
 * forbidden here by the single-owner rule instead, a callback not being the
 * session's owner. It must not block, because the engine thread is the resource
 * it would deadlock. Its whole job is to hand the result to the frontend's
 * dispatcher.
 *
 * result points into core storage and is valid only for the duration of the
 * call. user_data is the pointer passed to the entry that started this
 * search — mxq_search_start or mxq_search_start_hint — untouched.
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
 * Report the four independent version axes and the two build revisions.
 * Callable before mxq_core_init, as are the other queries that take no core
 * instance: mxq_core_game_profile, mxq_rules_start_fen, mxq_engine_plan,
 * mxq_engine_profile_id and mxq_archive_supported_versions.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_core_version(MxqVersion *out, MxqError *err);

/*
 * Report what one game binds to: its engine variant and that variant's pinned
 * network. A game outside the closed vocabulary is a programming error and
 * returns MXQ_ERR_ARG_RANGE. Callable before mxq_core_init: these are build
 * facts, not properties of a core instance.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_core_game_profile(MxqGameKind game,
                                                 MxqGameProfile *out,
                                                 MxqError *err);

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
 * rather than opened, and one recording any other schema version is refused
 * too — one version is defined and there is no migration into it, per
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
 * zero in Free Play and nearby play, matching the archive, which omits them;
 * local_side is the mirror rule, required in MXQ_PLAY_MODE_NEARBY and
 * MXQ_COLOR_NONE in the two local modes. A configuration that is none of the
 * three shapes is a programming error and returns MXQ_ERR_ARG_RANGE, as is a
 * game outside the closed vocabulary.
 *
 * The single-active-game rule spans every game and every mode: the library
 * holds one active game, so creating one while any is active returns
 * MXQ_ERR_STATE_ACTIVE_GAME_EXISTS.
 *
 * A session begins from its game's frozen start unless the configuration names
 * another position. An empty start_fen is that frozen start, and so is the
 * frozen start spelled out — the member is canonical, and either reads back
 * empty from mxq_game_config. A composed start belongs to
 * MXQ_PLAY_MODE_FREE_PLAY and to no other mode: any other mode carrying one is
 * MXQ_ERR_ARG_RANGE, a programming error like the configuration shape it is
 * part of. A composed start is asked three questions in order, and creation
 * refuses at the first that fails:
 *
 *   structure       MXQ_ERR_RULES_INVALID_FEN. The frozen encoding of this
 *                   game's board, and the counters a start carries — halfmove 0
 *                   and fullmove 1, a game beginning from a position having no
 *                   plies behind it to count. Any other counters are refused on
 *                   this rung with everything else about the position's
 *                   spelling
 *   setup legality  MXQ_ERR_RULES_ILLEGAL_POSITION, exactly as
 *                   mxq_rules_validate_setup answers it. Xiangqi is the one
 *                   game whose rules define a predicate; every other game
 *                   refuses here for any position but its frozen start
 *   startability    MXQ_ERR_STATE_GAME_OVER. Creation's own question and not
 *                   the predicate's: a position that already has a result of
 *                   its own is no game to play
 *
 * Ply 0 is the first move played from that position, by whichever side it has
 * to move, and every mover this core reports derives from the start position
 * and the ply rather than from the ply's parity.
 *
 * A session is store-attached, so a game the store cannot hold cannot have one:
 * a game outside the archive format's own rules_id vocabulary returns
 * MXQ_ERR_ARG_RANGE without asserting, which is the same split
 * MxqSearchRequest.movetime_ms takes — it reports two parts of this core at
 * different stages of one widening, not a caller outside a vocabulary it owns.
 * The rules facade answers for such a game in full; only persistence refuses it.
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
 * Create a nearby active game and the wire session it is being played over, in
 * one transaction.
 *
 * It is mxq_game_create with the second row, and it exists because the two are
 * one event: an active nearby game whose wire session the store does not hold
 * cannot be resumed after a relaunch, and a wire session with no game is
 * nothing at all. Every refusal mxq_game_create makes it makes, and the
 * configuration must be MXQ_PLAY_MODE_NEARBY's — any other mode is a
 * programming error and returns MXQ_ERR_ARG_RANGE.
 *
 * The session state must be the shape of a session at birth: undos and claimed
 * zero, keep zero, sent_end MXQ_NEARBY_TERMINAL_NONE. Anything else is
 * MXQ_ERR_ARG_RANGE — a game with no plies has retracted nothing and declared
 * nothing.
 *
 * A nearby game begins from its game's frozen start and from no other: the
 * protocol in docs/boardgame-protocol.md carries no start position, so a
 * composed one is a game the two devices could not be playing. A composed
 * start_fen is therefore MXQ_ERR_ARG_RANGE here, beside the mode's own refusal
 * and for the same reason — a configuration this entry cannot honour. The
 * frozen start spelled out is not one, here as everywhere.
 *
 * Thread and blocking: mxq_game_create's.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_create_nearby(MxqCore *core,
                                                  const MxqGameConfig *config,
                                                  const MxqNearbySession *session,
                                                  MxqGame **out_game,
                                                  MxqError *err);

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
 * recorded for it, judged for the position it begins from, and replayed, all
 * before a session exists, so a row this build can no longer read or no longer
 * reproduce is refused as MXQ_ERR_STORE_CORRUPT rather than as an archive
 * rejection: nothing was imported, and the answer is about the library rather
 * than about a file the user chose. The start is judged before the replay
 * rather than after it because a damaged one can be a position offering the
 * capture of a general, which the engine asserts against rather than
 * adjudicates. The import size bounds are deliberately not applied here — a
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
 * The legal moves originating at from_square, a square name such as "d1" or
 * "e10". Same buffer convention as mxq_game_legal_moves. A well-formed square
 * with no legal move yields *out_count 0 and MXQ_OK; a string that is not a
 * square of THIS session's game — see MXQ_ERR_RULES_MALFORMED_MOVE for the
 * grammar — is a programming error and returns MXQ_ERR_ARG_RANGE, because a
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
 * The nearby retraction: keep the first `keep` plies of the move line, drop
 * every ply beyond them, and rewrite the wire session in the same transaction.
 * Commits before returning, like every other mutation.
 *
 * It is not mxq_game_undo with an argument. Undo is one player taking a move
 * back by the decision-cycle rule; this is what two players agreed to keep, and
 * the count they agreed on is the protocol's, arrived at by a negotiation or by
 * the resume exchange's reconciliation. So the caller states the surviving
 * count, and the session state that arrives with it — the raised undos, the keep
 * it survived to — is written beside the shortened line rather than after it: a
 * store holding a line one transaction and a retraction count the next would
 * reconcile the next resume to a line neither player played.
 *
 * Legal only on a MXQ_PLAY_MODE_NEARBY session, which is the mirror of
 * mxq_game_undo refusing on one; otherwise MXQ_ERR_STATE_UNDO_UNAVAILABLE.
 * `keep` must be below the session's own move count — retracting nothing is not
 * a retraction — and is otherwise MXQ_ERR_ARG_RANGE. A store-domain failure
 * leaves the game exactly at its pre-mutation committed state.
 *
 * Thread: the session's owner; never inside a search callback. Off the UI
 * thread, except for the store-attached active game, whose own calls
 * docs/core-interface.md's threading contract documents as the one
 * exception.
 * Blocking: yes — the commit happens inside the call.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_retract_nearby(MxqGame *game, uint32_t keep,
                                                   const MxqNearbySession *session,
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

/*
 * Commit the end two nearby players declared to each other. Same atomic
 * transaction and same archived-session consequence as mxq_game_claim_draw.
 *
 * The three reasons this accepts are the explicit ends the BoardGame protocol
 * carries, already reconciled by the caller's session:
 *
 *   MXQ_END_REASON_RESIGNATION        resigning_side resigned; the outcome is
 *                                     the win for the other side
 *   MXQ_END_REASON_MUTUAL_RESIGNATION both resigned; a draw
 *   MXQ_END_REASON_AGREED_DRAW        a draw by agreement
 *
 * resigning_side is MXQ_COLOR_RED or MXQ_COLOR_BLACK for the first and
 * MXQ_COLOR_NONE for the other two. Any other reason, and any other pairing of
 * reason and side, is a programming error and returns MXQ_ERR_ARG_RANGE.
 *
 * The caller states which end the two players reached; the core still derives
 * the outcome from it, so no caller ever asserts a result. Legal only on a
 * MXQ_PLAY_MODE_NEARBY session — otherwise MXQ_ERR_STATE_RESIGN_UNAVAILABLE —
 * and only while the game has no result of its own: an end the rules decided
 * outranks one the players declared, so a terminal position is
 * MXQ_ERR_STATE_GAME_OVER, and the archive refuses such a record for the same
 * reason. A claimable neutral repetition is not a result, and either end is
 * lawful over it.
 *
 * Thread: the session's owner; never inside a search callback. Off the UI
 * thread, except for the store-attached active game, whose own calls
 * docs/core-interface.md's threading contract documents as the one
 * exception.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_commit_nearby_end(MxqGame *game,
                                                      MxqEndReason reason,
                                                      MxqColor resigning_side,
                                                      uint64_t *out_record_id,
                                                      MxqError *err);

/*
 * Rewrite the wire session of a nearby active game, and commit before
 * returning.
 *
 * Most of what this state records moves with the move line and is written by the
 * mutation that moved it: a ply carries the session it did not change, and
 * mxq_game_retract_nearby carries the one it did. One change happens on a beat
 * the game does not have — this device sending a terminal, which ends nothing
 * until the resume exchange settles it — and this is the call for that.
 *
 * Legal only on a MXQ_PLAY_MODE_NEARBY session; otherwise
 * MXQ_ERR_STATE_RESIGN_UNAVAILABLE, the same refusal the other nearby-only
 * ending makes. The session identifier and the peer identifier are frozen: a
 * value differing from the one the game was created with is MXQ_ERR_ARG_RANGE,
 * because a session's identity is not something a later call revises.
 *
 * Thread: the session's owner; never inside a search callback. Off the UI
 * thread, except for the store-attached active game, whose own calls
 * docs/core-interface.md's threading contract documents as the one
 * exception.
 * Blocking: yes — the commit happens inside the call.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_set_nearby_session(MxqGame *game,
                                                       const MxqNearbySession *session,
                                                       MxqError *err);

/*
 * Read back the wire session of a nearby active game: what a relaunched
 * application needs to rebuild the protocol session it was playing over.
 *
 * *out_exists is 0, and MXQ_OK is returned, where the game carries none — a
 * local game, an imported nearby record, a replay, or a nearby game whose
 * session the store no longer holds. Absence is an ordinary answer, not a
 * failure.
 *
 * Thread: the session's owner; never inside a search callback.
 * Blocking: no — a session carries this in memory once it is attached.
 */
MXQ_API MxqStatus MXQ_CALL mxq_game_nearby_session(const MxqGame *game,
                                                   MxqNearbySession *out,
                                                   uint8_t *out_exists,
                                                   MxqError *err);

/* ------------------------------------------------------------------------- */
/* Rules facade, session-free — mxq_rules_                                   */
/* ------------------------------------------------------------------------- */

/*
 * Write one game's frozen starting FEN and its length. Callable before
 * mxq_core_init: it is a constant of the ruleset, not of any core instance. A
 * cap below the required size returns MXQ_ERR_ARG_BUFFER_TOO_SMALL with
 * MxqError.required_size set; MXQ_FEN_CAP is always sufficient. A game outside
 * the closed vocabulary is a programming error and returns MXQ_ERR_ARG_RANGE.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_rules_start_fen(MxqGameKind game, char *out,
                                               size_t cap, size_t *out_len,
                                               MxqError *err);

/*
 * Validate a FEN as a position of game. This applies the frozen structural
 * encoding only, returning MXQ_ERR_RULES_INVALID_FEN on failure, and never
 * MXQ_ERR_RULES_ILLEGAL_POSITION: whether a structurally valid position is one
 * the game may be set up in is mxq_rules_validate_setup's question, and this
 * one is its precondition. A FEN of the other game's board fails the encoding
 * here, which is what makes the game a question rather than a hint.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_rules_validate_fen(MxqCore *core,
                                                  MxqGameKind game,
                                                  const char *fen,
                                                  MxqError *err);

/*
 * Whether game may be set up in the position fen states: the setup-legality
 * predicate, asked directly. It is the same predicate mxq_game_create and the
 * archive's rules tier ask, which is why they answer with this entry's own
 * MXQ_ERR_RULES_ILLEGAL_POSITION rather than a code of their own.
 *
 * MXQ_OK is a legal setup and MXQ_ERR_RULES_ILLEGAL_POSITION an illegal one.
 * Structural validity is the precondition rather than part of the answer, so a
 * FEN that is not a position of this game's board at all fails as it does from
 * mxq_rules_validate_fen, with MXQ_ERR_RULES_INVALID_FEN and that code's
 * meaning.
 *
 * out_violation is optional and, when supplied, is always written, whichever of
 * the three answers comes back: the rule is the one that broke on an illegal
 * position, and MXQ_SETUP_RULE_NONE on MXQ_OK and on the structural refusal
 * alike — a position of no board breaks no rule of this game, so there is none
 * to name, and side and square are then MXQ_COLOR_NONE and "".
 *
 * Which positions a game may be set up in is the game's own, and today exactly
 * one game has more than a single answer. Xiangqi's predicate is the rules of
 * docs/xiangqi-rules.md read as a set-up question — the piece the game gives a
 * side, the palace, the elephant's own seven points, the soldier's own starting
 * rank, the generals not facing, and the side not to move not in check. Every
 * other game accepts its frozen starting position and nothing else, and answers
 * MXQ_SETUP_RULE_NOT_FROZEN_START for anything else, the comparison being
 * against the whole frozen FEN and so against its side to move as well.
 *
 * Two things this deliberately does NOT answer.
 *
 * The first is whether a legal setup is one a game can be begun from. A position
 * that is already decided — a checkmate, a stalemate — breaks no rule of setting
 * up, and refusing it is the creating caller's question rather than this one;
 * docs/core-interface.md keeps validation and startability distinct
 * deliberately, and this entry is the validation half.
 *
 * The second is the two counters. Xiangqi accepts a position whatever its
 * halfmove clock and fullmove number read, because neither is a rule about where
 * pieces may stand; that a composed scene carries 0 and 1 is a rule about what
 * creation writes, and creation is where it is enforced. The frozen-start
 * comparison above is not an exception to this: it compares the whole FEN
 * because what it is asking is whether this is that one position.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_rules_validate_setup(MxqCore *core,
                                                    MxqGameKind game,
                                                    const char *fen,
                                                    MxqSetupViolation *out_violation,
                                                    MxqError *err);

/*
 * Replay moves from start_fen under game's rules and report the resulting
 * position and game state. This, with mxq_rules_legal_moves, is exactly the
 * surface the approved conformance fixtures replay through: every assertion in
 * a fixture maps onto these outputs.
 *
 * moves is an array of move_count NUL-terminated strings in canonical notation;
 * move_count 0 evaluates start_fen itself and moves may then be NULL. When a
 * move is not legal at its turn the function returns
 * MXQ_ERR_RULES_INVALID_HISTORY and sets *out_first_illegal_index to its index;
 * out_position and out_status are then unspecified. out_position, out_status
 * and out_first_illegal_index are each optional.
 *
 * Which start_fen this entry replays from is the game's, and the two classes
 * differ. A movement game takes any position mxq_rules_validate_fen accepts,
 * which is what lets a fixture state a position and replay from it — including
 * positions mxq_rules_validate_setup refuses, because a fixture pins the rules
 * of play over a position and never proposes to begin a game there. A placement
 * game takes its own frozen starting position and no other, returning
 * MXQ_ERR_RULES_INVALID_FEN for anything else: those games have exactly one
 * position that is not reached by play, and every other is reached by a line
 * this entry is being handed instead of. So a placement position that validates
 * is not necessarily one this entry will replay from, and the two questions
 * stay distinct on purpose.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_rules_evaluate(MxqCore *core, MxqGameKind game,
                                              const char *start_fen,
                                              const char *const *moves,
                                              size_t move_count,
                                              MxqPosition *out_position,
                                              MxqGameStatus *out_status,
                                              size_t *out_first_illegal_index,
                                              MxqError *err);

/*
 * The complete legal-move set in the position reached by replaying moves from
 * start_fen under game's rules. Same history and buffer conventions as
 * mxq_rules_evaluate and mxq_game_legal_moves.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_rules_legal_moves(MxqCore *core,
                                                 MxqGameKind game,
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
 * Recompute the same plan and apply it for one game: threads, Hash, that game's
 * pinned engine variant, and its pinned network. Below MXQ_ENGINE_MIN_HASH_MIB
 * it returns MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY without initialising anything,
 * and never substitutes a smaller Hash. The network is preflighted against the
 * engine's observable load state — the effective NNUE state after
 * configuration, not merely that the file exists and parses — so the engine's
 * own fatal verification path is never reached.
 *
 * Which engine is prepared follows from the game and is not otherwise visible:
 * the movement games and the placement games are searched by different engines,
 * and a preparation for one releases the other, because one memory plan is
 * computed and applied at a time.
 *
 * The engine is prepared for exactly one game at a time, because the tables a
 * search reads are that game's. Preparing for another game is an ordinary
 * second call; a search on a session of a game the engine is not prepared for is
 * refused with MXQ_ERR_STATE_ENGINE_NOT_READY.
 *
 * Returns MXQ_ERR_STATE_SEARCH_IN_PROGRESS rather than stalling if a search is
 * outstanding, and MXQ_ERR_ARG_RANGE for a game outside the closed vocabulary.
 *
 * Thread: any non-UI thread except inside a search callback; the work executes
 * marshalled on the engine thread.
 * Blocking: yes.
 */
MXQ_API MxqStatus MXQ_CALL mxq_engine_prepare(MxqCore *core, MxqGameKind game,
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
 * identifies the configuration a move would be produced by — which names the
 * game the engine is prepared for, since the variant and its network are half
 * of what a profile is. Before any preparation it names the rules posture's
 * game, MXQ_GAME_KIND_MINI_XIANGQI. Same buffer convention as
 * mxq_rules_start_fen; MXQ_PROFILE_ID_CAP is always sufficient.
 *
 * Thread: any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_engine_query(MxqCore *core,
                                            MxqEngineState *out_state,
                                            char *out_profile_id, size_t cap,
                                            size_t *out_len, MxqError *err);

/*
 * Report the profile identifier a search of this game would run under: exactly
 * what mxq_engine_query reports once this game is prepared, and what every
 * result of such a search names. It is to mxq_engine_query what mxq_engine_plan
 * is to mxq_engine_prepare — the answer without the act — and it exists because
 * the parts an identifier is composed of are not all reported anywhere else: a
 * game names the revision of the engine *it* is played on, and there is more
 * than one engine, so no caller can assemble this from mxq_core_version and
 * mxq_core_game_profile. A caller that assembled it from those would be right
 * for the games one engine plays and silently wrong for the rest.
 *
 * Whether the engine is ready for a game is therefore this value against
 * mxq_engine_query's, compared whole: one identifier stated by the core against
 * another stated by the core, with nothing reconstructed in between.
 *
 * A game outside the closed vocabulary is a programming error and returns
 * MXQ_ERR_ARG_RANGE. Callable before mxq_core_init: this is a build fact, not a
 * property of a core instance. Same buffer convention as mxq_rules_start_fen;
 * MXQ_PROFILE_ID_CAP is always sufficient.
 *
 * Thread: any thread, including inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_engine_profile_id(MxqGameKind game, char *out,
                                                 size_t cap, size_t *out_len,
                                                 MxqError *err);

/* ------------------------------------------------------------------------- */
/* Search facade — mxq_search_                                               */
/* ------------------------------------------------------------------------- */

/*
 * Start a search and return its ticket. Does not retain the session: it
 * snapshots the initial FEN, the complete move list, the game_id, the
 * position_revision and the session's frozen movetime before returning.
 * request->movetime_ms must equal that frozen movetime, or MXQ_ERR_ARG_RANGE.
 * That check does not assert: what it reports is a disagreement between two
 * independently-built components, not a caller that could not have got here
 * honestly. A Free Play session freezes no movetime and owes no search, so a
 * zero never passes it.
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
 * Start a hint search and return its ticket: the engine's move for the side to
 * move in this session's current position, to be shown to the player rather
 * than played. It commits nothing, ever — like every search result, the value
 * it delivers is inert, and applying it is a separate explicit
 * mxq_game_apply_move the player asks for.
 *
 * It is mxq_search_start in every respect but three, each of which is what a
 * hint is rather than a variation on the AI's reply. Everything else is that
 * function's: the same snapshot, the same ticket space and cancellation, the
 * same (game_id, position_revision) staleness identity, the same rejection
 * ladder including the legality check against the rules facade, the same
 * retention under the ticket until the next search, and the same callback on
 * the engine thread.
 *
 * First, movetime_ms is the thinking time itself rather than a cross-check. It
 * must be one of MXQ_MOVETIME_FAST_MS, MXQ_MOVETIME_STANDARD_MS and
 * MXQ_MOVETIME_DEEP_MS, or equal to this session's frozen ai_movetime_ms where
 * that is positive; any other value is MXQ_ERR_ARG_RANGE. That refusal reports
 * and does not assert, exactly like mxq_search_start's: a game keeps the
 * thinking time it froze at creation however the levels are retuned afterwards,
 * so a value outside the levels can be a resumed game's own — two
 * independently-built components disagreeing about which pairing is current,
 * not a caller that could not have got here honestly. What is NOT done here is
 * requiring agreement with the frozen value the way mxq_search_start does, and
 * that is the whole reason this entry exists: a Free Play session freezes none,
 * has nothing for a request to equal, and is owed a hint all the same — at one
 * of the levels, since zero is never an accepted thinking time.
 *
 * Second, it refuses while any search is outstanding, its own kind included,
 * with MXQ_ERR_STATE_SEARCH_IN_PROGRESS. The engine thread runs one search at a
 * time, and a hint queued behind another one would be answered against a
 * position the player has left; the caller cancels what is running or asks
 * again later. Cancellation is asynchronous: mxq_search_cancel asks the engine
 * thread to stop, and this refusal can outlive that call until the thread has
 * retired the cancelled search, so a caller cancels and then asks again rather
 * than expecting the next call to be admitted.
 *
 * Third, it demands a session that could still take the move it proposes, which
 * is mxq_game_apply_move's own state gate: a detached replay is
 * MXQ_ERR_STATE_SESSION_READ_ONLY, a game one of the archiving paths has ended
 * is MXQ_ERR_STATE_SESSION_ARCHIVED, and a position with a result of its own is
 * MXQ_ERR_STATE_GAME_OVER. The first of those asserts in a debug build, as
 * every call requiring a mutable session does: no surface offers a hint on a
 * detached replay, so a caller that reaches it has broken its own discipline.
 * The other two are ordinary control flow. A claimable neutral repetition is
 * not a result of its own and has its hint like any other ongoing position.
 *
 * As with mxq_search_start, the engine must be prepared for this session's game
 * or the call is MXQ_ERR_STATE_ENGINE_NOT_READY; callback may be NULL, leaving
 * mxq_search_poll and mxq_search_wait as the consumers; and taking an MxqGame *
 * counts as being inside that session for the single-owner rule.
 *
 * Callback delivered on: the core's engine thread. See MxqSearchCallback for
 * what is legal inside it.
 *
 * Thread: the session's owner; any thread except inside a search callback.
 * Blocking: no.
 */
MXQ_API MxqStatus MXQ_CALL mxq_search_start_hint(MxqCore *core,
                                                 const MxqGame *game,
                                                 uint32_t movetime_ms,
                                                 MxqSearchCallback callback,
                                                 void *user_data,
                                                 uint64_t *out_ticket,
                                                 MxqError *err);

/*
 * Cancel one search cooperatively, whichever entry started it. Its callback
 * still fires, with MXQ_SEARCH_CANCELLED. Cancelling an unknown or
 * already-finished ticket is MXQ_OK.
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
 * position must be exactly the frozen starting FEN of the game the file names,
 * every move must be legal in sequence, and the recorded terminal pair must
 * agree with the replayed adjudication. Touches no persistent state.
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
