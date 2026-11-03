/* The one place the core touches Rapfi; nothing above this header sees a Rapfi
 * type. Shaped like mxq_engine_bridge.hpp: a rules side that answers legality
 * and adjudication from the engine's own board, and a search side. Both share
 * the engine's process-global state and the mutex that serialises its mutation.
 *
 * The rules side asks the engine's own tables (Board::checkForbiddenPoint, the
 * per-rule pattern for the point being played) rather than reimplementing them,
 * so there is one implementation of each rule.
 *
 * The engine reports failure by throwing; every entry point catches and returns
 * a typed failure so no exception leaves the core. The engine's worker threads
 * have no handler, and startThinking clones the board and sets up root moves on
 * them, so a bad allocation there terminates the process.
 */

#ifndef MXQ_RAPFI_BRIDGE_HPP
#define MXQ_RAPFI_BRIDGE_HPP

#include "mxq.h"

/* Included directly: libc++ pulls <atomic> in behind <string> and <vector>, but
 * other standard libraries do not. */
#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

namespace mxq {
namespace rapfi {

/* Both games are 15x15, and the renju weight pair covers 15 alone. */
constexpr int kBoardSize = 15;

/* A closed set so the engine rule and the weight files are pinned to each one.
 * The product identifiers are `gomoku-15` and `renju`. */
enum class Rules {
    Gomoku15, /* freestyle: five or more in a row wins, and nothing is forbidden */
    Renju,    /* five exactly for Black, with the forbidden-move restrictions */
};

/* The product's identifier for one of them. */
const char *rules_id(Rules rules);

/* MxqGameKind is what the product offers, Rules is what the engine can run; the
 * mapping is this function, not an assumption that the enumerators line up. */
Rules rules_of(MxqGameKind game);

/* The engine's own name for a rule at this board size, reported as the variant
 * in MxqGameProfile. */
const char *rules_variant_id(Rules rules);

/* That rule's network, as its file name carries it: the first twelve
 * hexadecimal digits of its SHA-256. Where a rule pins a network per side it is
 * the one Black plays with, which names the pair. */
const char *rules_network_id(Rules rules);

/* The vendored Rapfi revision, carried by a placement game's profile
 * identifier. */
const char *fork_revision();

/* A point in the engine's coordinates: x across, y up, both zero-based, both
 * below kBoardSize. */
struct Point {
    uint8_t x = 0;
    uint8_t y = 0;
};

/* Written only by configure() and deconfigure(); read without a lock, as the
 * tables they build are. */
Rules active_rules();
bool  is_configured();

/* ------------------------------------------------------------------------- */
/* The rules side of the bridge                                              */
/* ------------------------------------------------------------------------- */

/*
 * The engine's per-point pattern and forbidden-point predicate translated once
 * into MxqGameStatus terms. at_occurrence is absent: no placement position ever
 * occurs twice, since every ply adds a stone and none is removed.
 */
struct Adjudication {
    MxqGameState state;
    MxqEndReason reason;
};

/* Why a replay did not complete. Typed rather than parsed from the detail
 * string, because move text from imported files could contain the word a
 * caller matched on. */
enum class ReplayError {
    None,
    StartFenInvalid, /* not a position of this game, or not the one it begins
                      * from */
    IllegalMove,     /* first_illegal is the offending index */
    Faulted,         /* the engine threw building or playing the board */
};

/*
 * Replay a placement game's line from its starting position, and report where it
 * arrived. The rule and the notation both follow from the game.
 *
 * Needs no prepared engine: the pattern tables are built at static
 * initialisation and the board is local, so rules queries work whether or not
 * an engine is up.
 *
 * start_fen must be the empty board, the only position these games begin from.
 *
 * out_legal_moves, when asked for, is every point a legal placement may go on,
 * rank 1 upward, file a rightward. A finished game has none.
 *
 * On anything but ReplayError::None the outputs are unspecified. Takes g_mutex
 * for the replay, since it reads state configure() and deconfigure() write.
 */
ReplayError replay(MxqGameKind game, const char *start_fen,
                   const char *const *moves, size_t move_count,
                   std::string &out_fen, uint32_t &out_ply,
                   Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal, std::string &detail);

/* Why configure() refused. Each maps onto one engine-domain status. */
enum class ConfigureError {
    None,
    AssetMissing,         /* a weight file this rule needs is not there */
    AssetMismatch,        /* the effective evaluator after configuration */
    RulesLoadFailed,      /* the engine could not be brought up for this rule */
    HashAllocationFailed, /* the transposition table could not be allocated */
};

/*
 * Apply the rules, search profile, weights, thread count and transposition
 * table. The rules become the active ones until the next configure() or
 * deconfigure().
 *
 *   - The engine's state is process-global (Search::Engine, Search::TT,
 *     Config::GeneralCfg, Evaluation::EvalCfg), so there is one instance per
 *     process and both games share this bridge.
 *   - configure() and deconfigure() are the only mutators. Both run on the
 *     facade's engine thread, are refused while a search is outstanding, and
 *     take the same mutex.
 *   - A rules switch is a full reconfiguration: the board is begun again and the
 *     transposition table flushed, because entries keyed under one rule's
 *     zobrist and pattern tables mean something else under the other's.
 *   - search_run() does not hold the mutex, so a search does not stall every
 *     other bridge call.
 *
 * Two preflights, in order:
 *
 *   1. Selection: freestyle has one weight file for both sides; renju has one
 *      per side, because its forbidden moves apply to Black alone.
 *   2. The effective evaluator, checked after the whole configuration. A weight
 *      set that does not cover the rule or board size throws
 *      UnsupportedRuleError or UnsupportedBoardSizeError, which the engine's
 *      evaluator maker swallows, silently falling back to classical evaluation.
 *      This asks the engine what evaluator it actually has and refuses if none.
 *
 * On any refusal the engine is unwound whole to the deconfigured state.
 *
 * Caller: the facade's engine thread only, with no search outstanding.
 */
ConfigureError configure(Rules rules, uint32_t threads, uint32_t hash_mib,
                         const std::string &assets_dir, std::string &detail);

/* Release the transposition table and return the engine to its unprepared
 * state: no threads, no evaluator, no table. Caller: the facade's engine thread
 * with no search outstanding, or the core's shutdown after that thread joined. */
void deconfigure();

/* Why search_run() produced no point. */
enum class SearchError {
    None,
    NotConfigured, /* no engine was prepared, or one was released under it */
    ReplayFailed,  /* a move in the line is not playable; the caller must pass
                    * a legal line */
    NoMove,        /* the engine reported no best point at all */
    Faulted,       /* the engine threw: an allocation it could not meet, a
                    * thread the system would not create */
};

/* What one completed search reports, in bounded diagnostic terms. */
struct SearchOutput {
    Point    point;
    int32_t  score_cp = 0;
    uint32_t depth = 0;
    uint64_t nodes = 0;
};

/*
 * Replay `moves` onto an empty board under the active rules, then think for
 * movetime_ms. Switching rules is a reconfiguration, so they are not a
 * parameter.
 *
 * `moves` is the whole line, Black first and alternating; the side to move
 * follows from its length. Every point must be on the board and empty.
 *
 * cancelled is re-checked after the engine's stop flag is re-armed, so a
 * cancellation racing the start is not lost. Blocks until the engine finishes
 * or is stopped. Caller: the facade's engine thread only.
 */
SearchError search_run(const std::vector<Point> &moves, uint32_t movetime_ms,
                       const std::atomic<bool> &cancelled, SearchOutput &out,
                       std::string &detail);

/* Ask the running search to stop, cooperatively and promptly. Any thread. */
void search_abort();

} /* namespace rapfi */
} /* namespace mxq */

#endif /* MXQ_RAPFI_BRIDGE_HPP */
