/*
 * mxq.h — the C interface of the core: rules, the Jieqi deal, engine
 * preparation and search. The core is stateless: every rules question is asked
 * of a game, a start position and a complete move line, and the app owns the
 * game in play and the library.
 *
 * Conventions:
 *
 *   - Every fallible function returns MxqStatus and takes an optional
 *     MxqError *err for a short English diagnostic. Passing NULL is legal.
 *   - Every value struct begins with uint32_t struct_size, which the caller
 *     sets to sizeof the struct before the call.
 *   - Vocabularies are int32_t typedefs with named constants.
 *   - Booleans are uint8_t, 0 or 1. Strings are UTF-8 and NUL-terminated.
 *   - Moves are "<from><to>" in the movement games and one square in the
 *     placement games; positions are six-field FENs (docs/xiangqi-rules.md).
 *   - The rules are a property of the game, never of a position: a Jieqi
 *     position with nothing face down is spelled exactly as a Xiangqi one, and
 *     Gomoku and Renju share a board.
 */

#ifndef MXQ_H
#define MXQ_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#  define MXQ_API __attribute__((visibility("default")))
#else
#  define MXQ_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------- */
/* Capacities                                                                */
/* ------------------------------------------------------------------------- */

/* A move: at most "a9a10" on the boards this core plays. */
#define MXQ_MOVE_TEXT_CAP 8

/* A FEN of any game. A full 15x15 placement board is the widest, at 251
 * characters. */
#define MXQ_FEN_CAP 512

/* One square, such as "a10" or "o15". */
#define MXQ_SQUARE_TEXT_CAP 4

/* MxqError.detail. */
#define MXQ_DETAIL_CAP 128

/* An engine profile identifier: the engine revision, variant and network a
 * search runs under. */
#define MXQ_PROFILE_ID_CAP 64

/* A deal value: sixty-four lowercase hexadecimal digits and the NUL. */
#define MXQ_DEAL_HEX_CAP 65

/* ------------------------------------------------------------------------- */
/* Status codes                                                              */
/* ------------------------------------------------------------------------- */

/* A caller error asserts in a debug build and returns its code in a release
 * one; every other status is ordinary control flow. */
typedef int32_t MxqStatus;

enum {
    MXQ_OK = 0,

    MXQ_ERR_ARG_NULL              = 1001,
    MXQ_ERR_ARG_STRUCT_SIZE       = 1003,
    MXQ_ERR_ARG_BUFFER_TOO_SMALL  = 1005, /* routine: MxqError.required_size
                                           * carries the count the call needs */
    MXQ_ERR_ARG_RANGE             = 1007,
    MXQ_ERR_ARG_REENTRANT         = 1010, /* called from inside a search
                                           * callback */

    MXQ_ERR_STATE_NOT_INITIALIZED     = 2001,
    MXQ_ERR_STATE_ALREADY_INITIALIZED = 2002,
    MXQ_ERR_STATE_SHUTTING_DOWN       = 2003,
    MXQ_ERR_STATE_SEARCH_IN_PROGRESS  = 2012, /* preparation and teardown wait
                                               * for no search; cancel first */
    MXQ_ERR_STATE_ENGINE_NOT_READY    = 2013, /* not prepared for this game */

    MXQ_ERR_RULES_INVALID_FEN      = 3003, /* not a position of this game's
                                            * board */
    MXQ_ERR_RULES_ILLEGAL_POSITION = 3004, /* a position of the board that the
                                            * game may not be set up in */
    MXQ_ERR_RULES_INVALID_HISTORY  = 3005, /* a move that is malformed or not
                                            * legal at its turn;
                                            * MxqError.detail_index carries its
                                            * index */

    MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY    = 6001, /* the Hash budget is below
                                                   * MXQ_ENGINE_MIN_HASH_MIB */
    MXQ_ERR_ENGINE_ASSET_MISSING          = 6002,
    MXQ_ERR_ENGINE_ASSET_MISMATCH         = 6003, /* the network the engine
                                                   * loaded is not the pinned
                                                   * one */
    MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED    = 6004,
    MXQ_ERR_ENGINE_HASH_ALLOCATION_FAILED = 6005,
    MXQ_ERR_ENGINE_NO_MOVE                = 6006, /* the position has no move */
    MXQ_ERR_ENGINE_FAULTED                = 6008,
    MXQ_ERR_ENGINE_NOT_PREPARED           = 6009, /* torn down between a
                                                   * search's start and its
                                                   * run */

    MXQ_ERR_RESOURCE_ALLOCATION_FAILED = 7001,

    MXQ_ERR_INTERNAL_INVARIANT = 9001
};

/* ------------------------------------------------------------------------- */
/* Vocabularies                                                              */
/* ------------------------------------------------------------------------- */

/* The side that moves first and the other, in every game: in the placement
 * games MXQ_COLOR_RED is the black stone. */
typedef int32_t MxqColor;
enum {
    MXQ_COLOR_NONE  = -1,
    MXQ_COLOR_RED   = 0,
    MXQ_COLOR_BLACK = 1
};

typedef int32_t MxqGameKind;
enum {
    MXQ_GAME_KIND_MINI_XIANGQI = 0, /* 7x7 */
    MXQ_GAME_KIND_XIANGQI      = 1, /* 9x10 */
    MXQ_GAME_KIND_GOMOKU_15    = 2, /* 15x15 freestyle */
    MXQ_GAME_KIND_RENJU        = 3, /* 15x15, with Black's forbidden moves */
    MXQ_GAME_KIND_JIEQI        = 4  /* 9x10, pieces dealt face down */
};

/* The state the rules give a line: the fixture state identifiers. */
typedef int32_t MxqGameState;
enum {
    MXQ_GAME_ONGOING        = 0,
    MXQ_GAME_CLAIMABLE_DRAW = 1, /* threefold repetition, which is a claim */
    MXQ_GAME_RED_WINS       = 2,
    MXQ_GAME_BLACK_WINS     = 3,
    MXQ_GAME_DRAW           = 4
};

/* Why the rules ended a line, or why a draw is claimable. */
typedef int32_t MxqEndReason;
enum {
    MXQ_END_REASON_NONE                   = 0,
    MXQ_END_REASON_CHECKMATE              = 1,
    MXQ_END_REASON_STALEMATE              = 2,
    MXQ_END_REASON_THREEFOLD_REPETITION   = 3,
    MXQ_END_REASON_PERPETUAL_CHECK        = 4,
    MXQ_END_REASON_PERPETUAL_CHASE        = 5,
    MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK = 6,
    MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE = 7,
    MXQ_END_REASON_FIFTY_MOVE_RULE        = 10, /* Xiangqi's */
    MXQ_END_REASON_FIVE_IN_A_ROW          = 13, /* the placement games' */
    MXQ_END_REASON_BOARD_FULL             = 14, /* the placement games' */
    MXQ_END_REASON_FORTY_MOVE_RULE        = 15  /* Jieqi's: forty moves without
                                                 * a capture */
};

/* Which setup rule a position breaks, as mxq_rules_validate_setup reports it:
 * the rules of docs/xiangqi-rules.md read as a set-up predicate, plus the
 * answers of the games that begin from one position or from a deal. */
typedef int32_t MxqSetupRule;
enum {
    MXQ_SETUP_RULE_NONE              = 0,
    MXQ_SETUP_RULE_PIECE_COUNT       = 1,
    MXQ_SETUP_RULE_PALACE            = 2,
    MXQ_SETUP_RULE_ELEPHANT_SIDE     = 3,
    MXQ_SETUP_RULE_SOLDIER_RANK      = 4,
    MXQ_SETUP_RULE_FACING_GENERALS   = 5,
    MXQ_SETUP_RULE_OPPONENT_IN_CHECK = 6,
    MXQ_SETUP_RULE_NOT_FROZEN_START  = 7,
    MXQ_SETUP_RULE_NOT_DEALT_START   = 8
};

typedef int32_t MxqEngineState;
enum {
    MXQ_ENGINE_STATE_UNINITIALIZED = 0,
    MXQ_ENGINE_STATE_READY         = 1,
    MXQ_ENGINE_STATE_FAULTED       = 2
};

/* A search's answer. Only a move that is well formed and legal in the searched
 * line arrives as MXQ_SEARCH_MOVE. */
typedef int32_t MxqSearchOutcome;
enum {
    MXQ_SEARCH_MOVE      = 0,
    MXQ_SEARCH_CANCELLED = 1,
    MXQ_SEARCH_MALFORMED = 2,
    MXQ_SEARCH_ILLEGAL   = 3,
    MXQ_SEARCH_FAILED    = 4  /* MxqSearchResult.status carries why */
};

/* ------------------------------------------------------------------------- */
/* Engine budget                                                             */
/* ------------------------------------------------------------------------- */

/* The Hash plan mxq_engine_prepare applies:
 *
 *   reserve = max(MXQ_ENGINE_RESERVE_PERCENT% of available,
 *                 MXQ_ENGINE_MIN_RESERVE_BYTES)
 *   usable  = max(0, available - reserve)
 *   budget  = min(MXQ_ENGINE_MAX_HASH_MIB MiB,
 *                 MXQ_ENGINE_PHYSICAL_PERCENT% of physical, usable)
 *   hash    = budget in MiB, rounded down to MXQ_ENGINE_HASH_GRANULARITY_MIB
 *
 * and below MXQ_ENGINE_MIN_HASH_MIB it prepares nothing. */
#define MXQ_ENGINE_MIN_HASH_MIB          256u
#define MXQ_ENGINE_MAX_HASH_MIB          4096u
#define MXQ_ENGINE_HASH_GRANULARITY_MIB  64u
#define MXQ_ENGINE_RESERVE_PERCENT       20u
#define MXQ_ENGINE_MIN_RESERVE_BYTES     (134217728u)  /* 128 MiB */
#define MXQ_ENGINE_PHYSICAL_PERCENT      50u

/* ------------------------------------------------------------------------- */
/* Types                                                                     */
/* ------------------------------------------------------------------------- */

/* The core. One per process: the engines' state is process-global. */
typedef struct MxqCore MxqCore;

typedef struct MxqError {
    uint32_t  struct_size;
    MxqStatus status;
    uint64_t  required_size; /* for MXQ_ERR_ARG_BUFFER_TOO_SMALL */
    uint64_t  detail_index;  /* for MXQ_ERR_RULES_INVALID_HISTORY */
    char      detail[MXQ_DETAIL_CAP];
} MxqError;

typedef struct MxqCoreConfig {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char *asset_directory; /* the variant configuration and the networks;
                                  * borrowed for the call */
} MxqCoreConfig;

typedef struct MxqMove {
    uint32_t struct_size;
    char     text[MXQ_MOVE_TEXT_CAP];
} MxqMove;

/* A position. in_check is 0 in the placement games. */
typedef struct MxqPosition {
    uint32_t struct_size;
    uint32_t ply_count;
    MxqColor side_to_move;
    uint8_t  in_check;
    uint8_t  reserved0[3];
    char     fen[MXQ_FEN_CAP];
} MxqPosition;

/* The rules' verdict on a line. */
typedef struct MxqGameStatus {
    uint32_t     struct_size;
    MxqGameState state;
    MxqEndReason reason;        /* MXQ_END_REASON_NONE while ongoing */
    uint32_t     at_occurrence; /* the occurrence a repetition attached at */
    MxqColor     side_to_move;
} MxqGameStatus;

/* The first setup rule a position breaks. side and square are MXQ_COLOR_NONE
 * and "" where the rule names neither: a piece count names a side only, the
 * facing generals and a refused start name neither. */
typedef struct MxqSetupViolation {
    uint32_t     struct_size;
    MxqSetupRule rule;
    MxqColor     side;
    char         square[MXQ_SQUARE_TEXT_CAP];
} MxqSetupViolation;

/* A Jieqi deal: the dealt start, the commitment the seed binds to (the SHA-256
 * of the seed's bytes), and the digest of the deal, which binds the seed, the
 * nonce and the derivation. */
typedef struct MxqDeal {
    uint32_t struct_size;
    char     start_fen[MXQ_FEN_CAP];
    char     commit[MXQ_DEAL_HEX_CAP];
    char     digest[MXQ_DEAL_HEX_CAP];
    uint8_t  reserved0[2];
} MxqDeal;

/* The probe the Hash budget is computed from, fresh at every preparation. */
typedef struct MxqEngineBudget {
    uint32_t struct_size;
    uint32_t active_processor_count;
    uint64_t available_bytes;
    uint64_t physical_bytes;
} MxqEngineBudget;

/* The plan a preparation applied. */
typedef struct MxqEnginePlan {
    uint32_t struct_size;
    uint32_t threads;
    uint32_t hash_mib;
    uint8_t  sufficient;
    uint8_t  reserved0[3];
    uint64_t reserve_bytes;
    uint64_t usable_bytes;
    uint64_t budget_bytes;
} MxqEnginePlan;

/* One search's answer. Nothing applies it: the caller does, after checking
 * that the line it searched is still the game's. */
typedef struct MxqSearchResult {
    uint32_t         struct_size;
    MxqSearchOutcome outcome;
    uint64_t         ticket;
    uint64_t         nodes;
    int32_t          score_cp;
    uint32_t         depth;
    uint32_t         elapsed_ms;
    MxqStatus        status;     /* why, for MXQ_SEARCH_FAILED */
    MxqMove          move;       /* for MXQ_SEARCH_MOVE */
    char             profile_id[MXQ_PROFILE_ID_CAP];
} MxqSearchResult;

/* Delivered on the core's engine thread, exactly once per started search. It
 * must copy the result, which is valid only during the call, and return;
 * every core function called from inside it returns MXQ_ERR_ARG_REENTRANT. */
typedef void (*MxqSearchCallback)(const MxqSearchResult *result,
                                  void *user_data);

/* ------------------------------------------------------------------------- */
/* The core                                                                  */
/* ------------------------------------------------------------------------- */

/* Start the core and load the variant configuration from the asset directory.
 * A second call before shutdown is MXQ_ERR_STATE_ALREADY_INITIALIZED. */
MXQ_API MxqStatus mxq_core_init(const MxqCoreConfig *config, MxqCore **out_core,
                                MxqError *err);

/* Cancel every search, join the engine thread and release the engines.
 * Outstanding callbacks fire, cancelled, before it returns. */
MXQ_API MxqStatus mxq_core_shutdown(MxqCore *core, MxqError *err);

/* Cancel every search and block until the engine thread is idle. Callbacks
 * fire, cancelled, before it returns. */
MXQ_API MxqStatus mxq_core_cancel_all(MxqCore *core, MxqError *err);

/* ------------------------------------------------------------------------- */
/* Rules                                                                     */
/* ------------------------------------------------------------------------- */

/* A game's frozen starting FEN and its length. Jieqi has none — it begins from
 * a deal — and answers MXQ_ERR_ARG_RANGE. Needs no core. */
MXQ_API MxqStatus mxq_rules_start_fen(MxqGameKind game, char *out, size_t cap,
                                      size_t *out_len, MxqError *err);

/* Whether game may be set up in fen. MXQ_OK is a legal setup;
 * MXQ_ERR_RULES_ILLEGAL_POSITION names the first rule broken in
 * out_violation; MXQ_ERR_RULES_INVALID_FEN is no position of this board.
 * Xiangqi has a setup predicate, Jieqi accepts a dealt start, and every other
 * game accepts its frozen start alone. A position that already has a result
 * breaks no setup rule: whether it can be played from is
 * mxq_rules_evaluate's. out_violation is optional and always written. */
MXQ_API MxqStatus mxq_rules_validate_setup(MxqCore *core, MxqGameKind game,
                                           const char *fen,
                                           MxqSetupViolation *out_violation,
                                           MxqError *err);

/* Replay moves from start_fen under game's rules: the position reached and
 * the rules' verdict on the line. Applying a move is evaluating the line one
 * move longer. A move that is malformed or not legal at its turn is
 * MXQ_ERR_RULES_INVALID_HISTORY with its index in *out_first_illegal_index.
 * A movement game replays from any position of its board; a placement game
 * only from its frozen start. moves may be NULL when move_count is 0; the
 * three outputs are optional. */
MXQ_API MxqStatus mxq_rules_evaluate(MxqCore *core, MxqGameKind game,
                                     const char *start_fen,
                                     const char *const *moves,
                                     size_t move_count,
                                     MxqPosition *out_position,
                                     MxqGameStatus *out_status,
                                     size_t *out_first_illegal_index,
                                     MxqError *err);

/* The legal moves at the end of the line. *out_count is always the number
 * available; a cap below it is MXQ_ERR_ARG_BUFFER_TOO_SMALL. A placement
 * board's empty points bound the count. */
MXQ_API MxqStatus mxq_rules_legal_moves(MxqCore *core, MxqGameKind game,
                                        const char *start_fen,
                                        const char *const *moves,
                                        size_t move_count, MxqMove *out,
                                        size_t cap, size_t *out_count,
                                        MxqError *err);

/* Derive the Jieqi deal a seed and a nonce produce, each sixty-four lowercase
 * hexadecimal digits. The same two values deal the same game on every device;
 * the caller draws them from a cryptographic source. Any other game is
 * MXQ_ERR_ARG_RANGE. */
MXQ_API MxqStatus mxq_rules_deal(MxqCore *core, MxqGameKind game,
                                 const char *seed, const char *nonce,
                                 MxqDeal *out, MxqError *err);

/* ------------------------------------------------------------------------- */
/* Engines                                                                   */
/* ------------------------------------------------------------------------- */

/* Prepare the engine game is played on with the plan the budget yields: its
 * threads, Hash, variant and network. One game is prepared at a time, and
 * preparing one releases the other engine. Below the minimum Hash it is
 * MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY and nothing is prepared. Blocks; call it
 * off the main thread. */
MXQ_API MxqStatus mxq_engine_prepare(MxqCore *core, MxqGameKind game,
                                     const MxqEngineBudget *budget,
                                     MxqEnginePlan *out_applied,
                                     MxqError *err);

/* Release the engines and their Hash. Blocks. */
MXQ_API MxqStatus mxq_engine_teardown(MxqCore *core, MxqError *err);

/* The engine's state and the profile it would search under now. */
MXQ_API MxqStatus mxq_engine_query(MxqCore *core, MxqEngineState *out_state,
                                   char *out_profile_id, size_t cap,
                                   size_t *out_len, MxqError *err);

/* The profile a search of game runs under. A game no engine plays — Jieqi —
 * answers MXQ_ERR_ARG_RANGE. Needs no core. */
MXQ_API MxqStatus mxq_engine_profile_id(MxqGameKind game, char *out,
                                        size_t cap, size_t *out_len,
                                        MxqError *err);

/* ------------------------------------------------------------------------- */
/* Search                                                                    */
/* ------------------------------------------------------------------------- */

/* Search the position at the end of the line for movetime_ms and return a
 * ticket. The line is copied before this returns. The engine must be prepared
 * for game. Searches run one at a time, in order, on the engine thread, and
 * deliver to callback. */
MXQ_API MxqStatus mxq_search_start(MxqCore *core, MxqGameKind game,
                                   const char *start_fen,
                                   const char *const *moves, size_t move_count,
                                   uint32_t movetime_ms,
                                   MxqSearchCallback callback, void *user_data,
                                   uint64_t *out_ticket, MxqError *err);

/* Cancel one search. Its callback still fires, cancelled. An unknown or
 * finished ticket is MXQ_OK. */
MXQ_API MxqStatus mxq_search_cancel(MxqCore *core, uint64_t ticket,
                                    MxqError *err);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* MXQ_H */
