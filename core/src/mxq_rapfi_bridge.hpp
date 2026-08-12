/* The one place the core touches Rapfi.
 *
 * Everything above this header speaks in mxq_ types; everything below it speaks
 * in Rapfi types. Keeping the boundary in one file is what makes the dependency
 * direction in docs/architecture.md checkable rather than aspirational: the
 * engine is an internal, replaceable component and must not be visible through
 * the C interface. It is the counterpart of mxq_engine_bridge.hpp for the second
 * engine, and it is deliberately shaped like it.
 *
 * What this stage does NOT contain is as deliberate as what it does. There is no
 * legality answer, no result adjudication, no forbidden-point query and no
 * notation: those are the rules adapter, and they are a stage of their own. This
 * is search alone — prepare, think, cancel, release — and the vocabulary it
 * needs for that is a rule, a list of points already played, a thinking time,
 * and a point to play.
 *
 * This engine reports failure by throwing, and docs/architecture.md forbids an
 * exception crossing the core's boundary, so every entry point below contains
 * one and returns a typed failure instead. One bound on that is accepted rather
 * than claimed away: the engine's worker threads have no handler of their own,
 * and startThinking dispatches the board clone and the root-move setup onto
 * them, so a bad allocation there terminates the process and no handler here
 * can see it. That is the same practical posture as the first engine, which is
 * compiled without exceptions at all and whose allocation failure would
 * terminate too. A guard inside the fork's thread loop is a possible focused
 * change if evidence ever asks for one.
 *
 * Compiled only when MXQ_ENABLE_GOMOKU_FACADE is ON.
 */

#ifndef MXQ_RAPFI_BRIDGE_HPP
#define MXQ_RAPFI_BRIDGE_HPP

#include "mxq.h"

/* <atomic> for the search's cancellation flag below, included here rather than
 * relied upon transitively for the reason mxq_engine_bridge.hpp records: libc++
 * pulls it in behind <string> and <vector> and the MSVC STL does not. */
#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

namespace mxq {
namespace rapfi {

/* The board these games are played on. One size, and it is not a parameter: the
 * campaign's decision is that a rules-and-size combination is its own game, and
 * both games this engine plays are 15x15. It matters beyond the geometry —
 * every pinned weight file declares the sizes it covers in its own header, and
 * the renju pair covers 15 alone. */
constexpr int kBoardSize = 15;

/* The games this engine plays, and there are exactly two.
 *
 * They are a closed set rather than a string a caller supplies, for the reason
 * the first engine's Variant enumeration gives: everything that follows from one
 * here is pinned to it one for one — the engine's own rule, and the weight files
 * with their byte lengths and SHA-256s. A string parameter would make most of
 * that unpinnable.
 *
 * The identifiers the product uses for them are `gomoku-15` and `renju`. */
enum class Rules {
    Gomoku15, /* freestyle: five or more in a row wins, and nothing is forbidden */
    Renju,    /* five exactly for Black, with the forbidden-move restrictions */
};

/* The product's identifier for one of them, which is also the manifest key its
 * weights are pinned under. */
const char *rules_id(Rules rules);

/* A point on the board, in the engine's own coordinates: x across, y up, both
 * zero-based, both below kBoardSize. The core's own notation for these games is
 * the rules adapter's business and is not decided here. */
struct Point {
    uint8_t x = 0;
    uint8_t y = 0;
};

/* The rules the engine's process-global state is currently prepared for, and
 * whether it is prepared at all. Written only by configure() and deconfigure();
 * read without a lock, exactly as the tables they build are. */
Rules active_rules();
bool  is_configured();

/* Why configure() refused. Each maps onto one engine-domain status of the error
 * taxonomy in docs/core-interface.md. */
enum class ConfigureError {
    None,
    InsufficientMemory,   /* the planned budget is below the accepted minimum;
                           * nothing was configured. Only prepare() returns it */
    AssetMissing,         /* a weight file this rule needs is not there */
    AssetMismatch,        /* byte length, SHA-256, or the effective evaluator
                           * after configuration */
    RulesLoadFailed,      /* the engine could not be brought up for this rule */
    HashAllocationFailed, /* the transposition table could not be allocated */
};

/*
 * The whole of preparation, from the frontend's own probe values: compute the
 * accepted memory plan, refuse below its minimum without configuring anything,
 * and otherwise configure with the threads and the table size the plan yields.
 *
 * There is exactly one memory policy in this core and this is a second consumer
 * of it, not a second copy: the arithmetic is mxq_engine_plan's — reserve the
 * greater of a fifth of the probe or 128 MiB, cap the byte budget at 4 GiB and
 * at half the physical memory, round down to a 64 MiB multiple, refuse below
 * 256 MiB — and it is called here rather than restated. It is a pure function of
 * the probe values, which is what lets every boundary of it be tested without
 * an engine, and what lets this call it without one either.
 *
 * out_applied receives the plan whether or not it was applied, so a caller can
 * report the budget that was refused. Caller: the facade's engine thread only,
 * with no search outstanding.
 */
ConfigureError prepare(Rules rules, const MxqEngineBudget &budget,
                       const std::string &assets_dir, MxqEnginePlan &out_applied,
                       std::string &detail);

/*
 * Apply the plan: the requested rules, the accepted shared search profile, the
 * weights, the thread count, and the transposition table. The requested rules
 * become the active ones, and searches run under them until the next
 * configure() or deconfigure().
 *
 * The serialisation design is the first engine's, for the same reasons, and the
 * differences are only where this engine differs:
 *
 *   - The engine's whole state is process-global — Search::Engine, Search::TT,
 *     Config::GeneralCfg, Evaluation::EvalCfg — so there is one engine instance
 *     per process and both games serialise through this one bridge. That is not
 *     a simplification: two instances are not expressible.
 *   - configure() and deconfigure() are the only mutators of that state. Both
 *     run on the facade's engine thread, both are refused by the facade while a
 *     search is outstanding, and both take the same mutex, so nothing observes
 *     the engine mid-mutation.
 *   - A rules switch is exactly a reconfiguration and takes the
 *     reconfiguration's exclusion. It is not free: the board is begun again and
 *     the transposition table is flushed whole, because entries keyed under one
 *     rule's zobrist and pattern tables mean something else under the other's.
 *     That is the protocol layer's own handling of an `INFO RULE` change, and it
 *     is right for the same reason.
 *   - search_run() deliberately does NOT hold the mutex. Holding it for the
 *     length of a search would stall every other bridge call behind a whole
 *     thinking time.
 *
 * Three preflights run in order, and the third is the one that exists because
 * this engine fails quietly:
 *
 *   1. Selection — which files this rule needs. Freestyle has one, which serves
 *      both sides; renju has one per side, because its forbidden-move rules
 *      apply to Black alone and the two sides are trained apart.
 *   2. Bytes — every selected file's length and SHA-256 against its own pins,
 *      before the engine is given a path. A weight file carries a structural
 *      header the engine checks and no content hash at all, so the manifest pins
 *      are the whole of the integrity check.
 *   3. The effective evaluator, after the whole configuration and never instead
 *      of it. A weight set that does not cover the rule or the board size throws
 *      UnsupportedRuleError or UnsupportedBoardSizeError, which the engine's own
 *      evaluator maker swallows — leaving the engine playing on classical
 *      evaluation with nothing reported anywhere. This gate asks the engine what
 *      evaluator it actually has for this rule at this size, and refuses if the
 *      answer is none. It is fatal at preparation, never a warning, and never
 *      reaches a search.
 *
 * On any refusal the engine is unwound whole to the deconfigured posture; it
 * never keeps a partial configuration.
 *
 * Caller: the facade's engine thread only, with no search outstanding.
 */
ConfigureError configure(Rules rules, uint32_t threads, uint32_t hash_mib,
                         const std::string &assets_dir, std::string &detail);

/* Release the transposition table whole and return the engine to the state it
 * was in before any preparation: no threads, no evaluator, no table. Caller: the
 * facade's engine thread with no search outstanding, or the core's shutdown
 * after that thread joined. */
void deconfigure();

/* Why search_run() produced no point. */
enum class SearchError {
    None,
    NotConfigured, /* no engine was prepared, or one was released under it */
    ReplayFailed,  /* a move in the snapshot is not playable: an invariant
                    * breach, because it was legal when it was accepted */
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
 * Run one search over the snapshot, under the active rules: replay `moves` onto
 * an empty board — these games have no other starting position — then think for
 * movetime_ms. The rules are not a parameter for the reason the first engine's
 * variant is not: the tables and the loaded weights are the prepared rule's, and
 * switching them is a reconfiguration.
 *
 * `moves` is the whole line in order, Black first and alternating; the engine
 * derives the side to move from its length, exactly as the board does. Every
 * point must be on the board and empty, which is the caller's own guarantee: it
 * accepted each of them as a move.
 *
 * cancelled is re-checked after the engine's own stop flag is re-armed, so a
 * cancellation racing the start is still prompt rather than lost. Blocks until
 * the engine finishes or is stopped. Caller: the facade's engine thread only.
 */
SearchError search_run(const std::vector<Point> &moves, uint32_t movetime_ms,
                       const std::atomic<bool> &cancelled, SearchOutput &out,
                       std::string &detail);

/* Ask the running search to stop, cooperatively and promptly. Any thread. */
void search_abort();

} /* namespace rapfi */
} /* namespace mxq */

#endif /* MXQ_RAPFI_BRIDGE_HPP */
