/* The one place the core touches Fairy-Stockfish.
 *
 * Everything above this header speaks in mxq_ types; everything below it speaks
 * in Stockfish types. Keeping the boundary in one file is what makes the
 * dependency direction in docs/architecture.md checkable rather than aspirational:
 * the engine is an internal, replaceable component and must not be visible
 * through the C interface.
 *
 * Compiled only when MXQ_ENABLE_RULES_FACADE is ON. */

#ifndef MXQ_ENGINE_BRIDGE_HPP
#define MXQ_ENGINE_BRIDGE_HPP

#include "mxq.h"

#include <cstdint>
#include <string>
#include <vector>

namespace mxq {
namespace engine {

/* Adjudication as the rules contract describes it, independent of how the
 * engine happens to report it. The engine returns one side-to-move-relative
 * Value plus a flag; docs/xiangqi-rules.md wants a state, a reason, and the
 * occurrence an outcome attached at. Translating once, here, keeps every caller
 * from re-deriving it — and re-deriving it inconsistently is exactly how a
 * repetition outcome gets attributed to the wrong side. */
/* One recorded ply: who moved, and whether the move gave check. Both halves are
 * needed — a unilateral perpetual check is one side checking at every one of
 * ITS moves, and the victim's replies of course give no check. Recording only
 * "did this ply give check" makes every perpetual check look like a chase. */
struct Ply {
    bool by_red;
    bool gives_check;
};

struct Adjudication {
    MxqGameState state;
    MxqEndReason reason;
    uint32_t     at_occurrence;   /* 0 unless the outcome is repetition-based */
};

/* Why ensure_initialised refused. A configuration file that is not there and
 * one that is there but does not yield the pinned variant are different
 * packaging failures, and the error taxonomy carries one code for each. */
enum class InitError {
    None,
    AssetMissing,       /* the bundled configuration cannot be opened */
    VariantLoadFailed,  /* it parses, but the pinned variant is not in it */
};

/* Prepare the engine's process-global state and load the bundled variant
 * configuration. Idempotent; the first call does the work. Fills detail on
 * anything but None — which is a packaging failure, not a rules failure. */
InitError ensure_initialised(const char *assets_dir, std::string &detail);

/* Why a replay did not complete. Returned rather than inferred from the detail
 * string: move text reaches this function from imported archives, so a history
 * could otherwise name itself into the wrong error by containing the word the
 * caller was matching on. */
enum class ReplayError {
    None,
    NotInitialised,
    StartFenInvalid,
    IllegalMove,     /* first_illegal is the offending index */
};

/* Replay moves from start_fen under the target variant.
 *
 * On anything but ReplayError::None the outputs are unspecified, exactly as
 * mxq_rules_evaluate documents. A history is replayed rather than a bare
 * position evaluated, because repetition and violation state derive from
 * history: docs/xiangqi-rules.md, "A bare position carries no prior
 * occurrences." */
ReplayError replay(const char *start_fen,
                   const char *const *moves, size_t move_count,
                   std::string &out_fen,
                   bool &out_in_check,
                   uint32_t &out_ply,
                   Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal,
                   std::string &detail);

/* Structural FEN validation only, per mxq_rules_validate_fen: version 1 applies
 * the frozen encoding and never judges setup legality. */
bool validate_fen(const char *fen, std::string &detail);

/* ------------------------------------------------------------------------- */
/* The search side of the bridge                                             */
/* ------------------------------------------------------------------------- */

/*
 * The four operations the search facade's one engine thread drives, kept here
 * because this file is the only place the core touches Fairy-Stockfish. The
 * facade in mxq_search.cpp owns the thread, the queue, the tickets and the
 * results, and speaks mxq_ types only; these functions own every Stockfish
 * global the search needs.
 *
 * The serialisation design, in one place because the race is real:
 *
 * Search shares the engine's process-global state with the rules bridge —
 * Options, the thread pool, the transposition table, and the variant, piece
 * and bitboard tables. A rules query or a session mutation can land while a
 * search runs: undo-while-thinking is an accepted product flow, and the
 * frontend cancels before it mutates, but cancellation is cooperative and a
 * plain query can land mid-search with nothing cancelled at all. The rules
 * bridge therefore must never block behind a multi-second search, and the
 * search must never trip over a concurrent replay. The reconciliation:
 *
 *   - The variant, piece and bitboard tables are built once, for the one
 *     pinned variant, by ensure_initialised, and never rebuilt outside
 *     configure(). replay() reads them and no longer re-initialises them per
 *     call — re-running UCI::init_variant per replay rewrote process-global
 *     tables, identical values or not, under any concurrent reader. A stable
 *     table read by both sides races with nothing.
 *   - configure() and deconfigure() are the only mutators of Options, the
 *     pool size and the transposition table. Both run on the facade's engine
 *     thread, both are refused by the facade while a search is outstanding
 *     (MXQ_ERR_STATE_SEARCH_IN_PROGRESS — reconfiguration serialises behind
 *     search), and both take the same g_mutex the rules replay holds, so a
 *     replay never observes the tables, the pool or the TT mid-mutation.
 *   - search_run() deliberately does NOT hold g_mutex: it only reads the
 *     stable tables a replay also only reads, its Position is its own, and
 *     the TT it fills is touched by no rules path — a replay's do_move only
 *     prefetches a TT address, which is a hint and not an access, and the
 *     fork's TT keeps a scratch cluster for the released state. Holding the
 *     mutex for the length of a search would turn every board query into a
 *     five-second stall, which the threading contract forbids.
 *   - One diagnostic wrinkle is accepted rather than hidden: a Position must
 *     name a Thread, replay names Threads.main(), and do_move counts a node
 *     on it, so a replay concurrent with a search inflates the reported node
 *     count by the replay's length. The counter is atomic and diagnostic
 *     only; no adjudication or move derives from it.
 *
 * The pool-size reconciliation: ensure_initialised holds the pool at 1, which
 * is the rules posture — replay needs Threads.main() to exist and searches
 * never run before configure(). configure() owns the count while the engine
 * is prepared, sizing it from the applied plan; deconfigure() restores 1, so
 * the bridge's rules answers keep working after teardown exactly as before
 * preparation. Nothing ever sets the pool to 0 before process shutdown.
 */

/* Why configure() refused. Each maps onto one engine-domain status. */
enum class ConfigureError {
    None,
    AssetMissing,          /* no network file to preflight */
    AssetMismatch,         /* byte length, SHA-256, or the effective NNUE
                            * state after configuration */
    VariantLoadFailed,     /* the pinned variant is not loadable */
    HashAllocationFailed,  /* the transposition table could not be allocated */
};

/*
 * Apply the plan: the pinned variant, the accepted shared search profile, the
 * NNUE, the thread count, and the Hash. The network is preflighted twice —
 * its bytes against the pinned byte length and SHA-256 before the engine sees
 * a path, and the engine's effective NNUE state after configuration, because
 * a basename that does not begin with the variant identifier clears the
 * engine's internal flag silently while the option still reads true. On any
 * refusal the engine is unwound whole to the deconfigured posture; it never
 * keeps a partial configuration.
 *
 * Caller: the facade's engine thread only, with no search outstanding.
 */
ConfigureError configure(uint32_t threads, uint32_t hash_mib,
                         const std::string &assets_dir, std::string &detail);

/* Release the transposition table whole and restore the rules posture: pool
 * of 1, minimal option floor. Caller: the facade's engine thread with no
 * search outstanding, or mxq_core_shutdown after the engine thread joined. */
void deconfigure();

/* Why search_run() produced no move. */
enum class SearchError {
    None,
    ReplayFailed,  /* the snapshot no longer replays: an invariant breach,
                    * because it was legal when the session accepted it */
    NoMove,        /* the engine reported no best move at all */
};

/* What one completed search reports, in the bounded diagnostic terms
 * MxqSearchResult carries. */
struct SearchOutput {
    std::string move;      /* canonical <from><to> */
    int32_t     score_cp = 0;
    uint32_t    depth = 0;
    uint64_t    nodes = 0;
};

/*
 * Run one search over the snapshot: replay moves from start_fen, then think
 * for movetime_ms under the accepted shared profile. cancelled is re-checked
 * after the engine's own stop flag is re-armed, so a cancellation racing the
 * start is still prompt rather than lost. Blocks until the engine finishes or
 * is stopped. Caller: the facade's engine thread only.
 */
SearchError search_run(const std::string &start_fen,
                       const std::vector<std::string> &moves,
                       uint32_t movetime_ms,
                       const std::atomic<bool> &cancelled,
                       SearchOutput &out, std::string &detail);

/* Ask the running search to stop, cooperatively and promptly. Any thread. */
void search_abort();

} /* namespace engine */
} /* namespace mxq */

#endif /* MXQ_ENGINE_BRIDGE_HPP */
