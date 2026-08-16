/* The one place the core touches Rapfi.
 *
 * Everything above this header speaks in mxq_ types; everything below it speaks
 * in Rapfi types. Keeping the boundary in one file is what makes the dependency
 * direction in docs/architecture.md checkable rather than aspirational: the
 * engine is an internal, replaceable component and must not be visible through
 * the C interface. It is the counterpart of mxq_engine_bridge.hpp for the second
 * engine, and it is deliberately shaped like it.
 *
 * It has two sides, exactly as the first bridge does: a rules side that answers
 * legality and adjudication from the engine's own board machinery, and a search
 * side that prepares, thinks, cancels and releases. They share the engine's
 * process-global state and the mutex that serialises every mutation of it.
 *
 * The rules side is an adapter and not an implementation. Every question it
 * answers is put to the engine's own tables — a forbidden point to
 * Board::checkForbiddenPoint, a completed five to the per-rule pattern the board
 * already maintains for the point being played — because the vendored engine is
 * the rules authority for these games exactly as the vendored fork is for the
 * xiangqi ones. A second reading here would be a second implementation, and two
 * implementations of a rule disagree the day one of them is corrected.
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

/* The rules one game is played under. The two vocabularies are deliberately
 * separate, for the reason the first bridge's variant_of gives: MxqGameKind is a
 * ruleset the product offers and an archive records, Rules is a configuration
 * this engine can be asked to run, and the mapping is this function rather than
 * an assumption that the enumerators line up. */
Rules rules_of(MxqGameKind game);

/* The engine's own name for a rule at this board size — what MxqGameProfile
 * reports as the variant, and what a saved diagnostic names the configuration a
 * move came from by. */
const char *rules_variant_id(Rules rules);

/* The SHA-256 pinned for that rule's network, lowercase hexadecimal. Where a
 * rule pins a network per side it is the one Black plays with: the pins move
 * together in the manifest, so one of them names the pair. */
const char *rules_nnue_sha256(Rules rules);

/* The revision this engine is vendored at. The core reports one fork revision
 * through MxqVersion and it is the first engine's; this is the second's, and it
 * is what a placement game's profile identifier carries. */
const char *fork_revision();

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

/* ------------------------------------------------------------------------- */
/* The rules side of the bridge                                              */
/* ------------------------------------------------------------------------- */

/*
 * Adjudication as the core's contract describes it, independent of how the
 * engine happens to hold it. The engine keeps a per-point, per-side, per-rule
 * pattern and a forbidden-point predicate; MxqGameStatus wants a state and a
 * reason. Translating once, here, keeps every caller from re-deriving it.
 *
 * at_occurrence is not among these: no outcome of a placement game is
 * repetition-based, because no position of one ever occurs twice — every ply
 * adds a stone and none is ever removed.
 */
struct Adjudication {
    MxqGameState state;
    MxqEndReason reason;
};

/* Why a replay did not complete. Returned rather than inferred from the detail
 * string, for the reason the first bridge gives: move text reaches this from
 * imported archives, so a history could otherwise name itself into the wrong
 * error by containing the word the caller was matching on. */
enum class ReplayError {
    None,
    StartFenInvalid, /* not a position of this game, or not the one it begins
                      * from */
    IllegalMove,     /* first_illegal is the offending index */
    Faulted,         /* the engine threw building or playing the board */
};

/*
 * Replay a placement game's line from its starting position, and report where it
 * arrived.
 *
 * The game is the parameter rather than the rule, because a rules answer is a
 * game's: the rule the engine is asked for and the notation the answer is
 * spelled in both follow from it, and deriving them here is what stops a caller
 * pairing one game's board with another's rule.
 *
 * It takes no prepared engine and no configuration. The pattern tables it reads
 * are built once at static initialisation and are constants of the rule; the
 * board is local to the call. So a rules query is answerable before any
 * preparation and after any teardown, which is what the session surface needs —
 * a game is played, undone and replayed whether or not an engine is up.
 *
 * start_fen must be the position this game begins from. These games have exactly
 * one, and it is the empty board: the facade's whole contract is a starting
 * position plus a complete history, and a board with stones on it is a position
 * reached by play rather than one to begin from. It is the same answer
 * mxq_rules_validate_setup gives for these games — the frozen start and no
 * other — said here because a replay is handed the line instead.
 *
 * out_legal_moves, when asked for, is every point a legal placement may go on,
 * in a fixed order: rank 1 upward, file a rightward. A finished game has none,
 * exactly as a checkmated position has none.
 *
 * On anything but ReplayError::None the outputs are unspecified, as
 * mxq_rules_evaluate documents. Takes g_mutex: it reads state configure() and
 * deconfigure() write, and holds it for a board replay rather than for a think.
 */
ReplayError replay(MxqGameKind game, const char *start_fen,
                   const char *const *moves, size_t move_count,
                   std::string &out_fen, uint32_t &out_ply,
                   Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal, std::string &detail);

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
