/* The one place the core touches Fairy-Stockfish. Everything above this header
 * speaks in mxq_ types; everything below it in Stockfish types, so the engine
 * stays invisible through the C interface. */

#ifndef MXQ_ENGINE_BRIDGE_HPP
#define MXQ_ENGINE_BRIDGE_HPP

#include "mxq.h"

#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

namespace mxq {
namespace engine {

/* A closed set rather than a caller-supplied string: each variant is pinned to
 * an engine identifier and a network whose basename begins with it, and the
 * engine answers an unknown variant with a silent no-op rather than an error.
 *
 * MiniXiangqi is defined in the bundled configuration; Xiangqi is the engine's
 * own built-in 9x10 game. */
enum class Variant {
    MiniXiangqi,
    Xiangqi,
};

/* The mapping from ruleset to engine configuration lives here rather than in
 * an assumption that the enumerators line up. */
Variant variant_of(MxqGameKind game);

/* The variant the engine's process-global tables are built for. MiniXiangqi by
 * default, restored by deconfigure(); only configure() changes it. */
Variant active_variant();

/* The engine's identifier for a variant: what UCI_Variant is set to, and the
 * prefix its network's basename must begin with. */
const char *variant_id(Variant variant);

/* That variant's network, as its file name carries it: the first twelve
 * hexadecimal digits of its SHA-256. */
const char *variant_network_id(Variant variant);

/* The engine reports one side-to-move-relative Value, a flag, and which
 * optional-end rule fired; callers want a state, a reason, and the occurrence
 * an outcome attached at. Translating once here keeps a repetition outcome from
 * being attributed to the wrong side. */
struct Adjudication {
    MxqGameState state;
    MxqEndReason reason;
    uint32_t     at_occurrence;   /* 0 unless the outcome is repetition-based */
};

enum class InitError {
    None,
    AssetMissing,       /* the bundled configuration cannot be opened */
    VariantLoadFailed,  /* it parses, but a pinned variant is not in it */
};

/* Prepare the engine's process-global state and load the bundled variant
 * configuration. Idempotent. Fills detail on anything but None.
 *
 * Both variants must be in the variant map when this returns: the built-in one
 * is registered inside the engine's LARGEBOARDS guard, so a build without that
 * define would silently lack Xiangqi. */
InitError ensure_initialised(const char *assets_dir, std::string &detail);

/* Returned rather than inferred from the detail string: move text comes from
 * imported game files and could contain whatever word a caller matched on. */
enum class ReplayError {
    None,
    NotInitialised,
    StartFenInvalid,
    IllegalMove,     /* first_illegal is the offending index */
};

/*
 * Replay moves from start_fen under `variant`, whichever variant the engine is
 * configured for.
 *
 * A search reads the tables a configuration builds (the PSQT and the
 * evaluation), so it can only run in the active variant. A replay reads the
 * variant object for geometry and adjudication, and besides that only pieceMap
 * and the piece attack bitboards. Those are identical for both variants:
 * pieceMap.init() defines every standard piece the same way, neither game
 * declares a custom piece, and the attack tables cover the maximal board. So a
 * replay of either game is correct against the tables the other left, and a
 * Xiangqi rules query needs no table rebuild that would race a running search.
 *
 * On anything but ReplayError::None the outputs are unspecified. A history is
 * replayed rather than a bare position evaluated because repetition and
 * violation state derive from history.
 */
ReplayError replay(Variant variant, const char *start_fen,
                   const char *const *moves, size_t move_count,
                   std::string &out_fen,
                   bool &out_in_check,
                   uint32_t &out_ply,
                   Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal,
                   std::string &detail);

/* Structural FEN validation of `variant`'s own board, never a judgment of
 * setup legality. A position of the other board fails. */
bool validate_fen(Variant variant, const char *fen, std::string &detail);

enum class ProbeError {
    None,
    NotInitialised,
    FenInvalid,      /* not a position of this variant's board */
};

/*
 * Whether the side to move in `fen` stands in check.
 *
 * The setup predicate flips the side to move and asks this, to judge the side
 * NOT to move without constructing a move: the engine's do_move asserts that no
 * capture is of a KING, so applying a move to a position offering a general
 * capture would abort the process on exactly the input being judged. Here the
 * position is set and its checkers read; no move is generated or made.
 *
 * The answer does NOT include the flying-general relation: the engine keeps
 * that in legal() rather than in a position's checkers. The caller handles it
 * with board arithmetic.
 *
 * Takes g_mutex, as a replay does.
 */
ProbeError side_to_move_in_check(Variant variant, const char *fen,
                                 bool &out_in_check, std::string &detail);

/* ------------------------------------------------------------------------- */
/* The search side of the bridge                                             */
/* ------------------------------------------------------------------------- */

/*
 * The operations the search facade's one engine thread drives. The facade in
 * mxq_search.cpp holds the thread, queue, tickets and results; these functions
 * hold every Stockfish global the search needs.
 *
 * Serialisation. Search shares the engine's process-global state with the
 * rules bridge: Options, the thread pool, the transposition table, and the
 * variant, piece and bitboard tables. A rules query can land mid-search (undo
 * while thinking; cancellation is cooperative), so rules queries must never
 * block behind a multi-second search, and a search must never trip over a
 * concurrent replay:
 *
 *   - The variant, piece and bitboard tables are built for ONE variant at a
 *     time: setting UCI_Variant rewrites pieceMap, the piece bitboards and the
 *     PSQT in place. ensure_initialised builds them for MiniXiangqi; only
 *     configure() and deconfigure() rebuild them. replay() only reads them —
 *     re-running UCI::init_variant per replay would rewrite process-global
 *     tables under concurrent readers.
 *   - configure() and deconfigure() are the only mutators of Options, the
 *     active variant, the pool size and the TT. Both run on the engine thread,
 *     both are refused while a search is outstanding
 *     (MXQ_ERR_STATE_SEARCH_IN_PROGRESS), and both take the g_mutex a replay
 *     holds, so a replay never sees any of these mid-mutation and a variant
 *     switch is never concurrent with a search.
 *   - search_run() does NOT hold g_mutex: it only reads tables a replay also
 *     only reads, its Position is its own, and no rules path touches the TT —
 *     a replay's do_move only prefetches a TT address. Holding the mutex for a
 *     search would stall every board query for seconds.
 *   - Tolerated: a Position must name a Thread, replay names Threads.main(), and
 *     do_move counts a node on it, so a replay concurrent with a search
 *     inflates the reported node count. The counter is atomic and diagnostic
 *     only.
 *
 * Pool size: ensure_initialised holds the pool at 1, which replay needs
 * (Threads.main() must exist). configure() sizes it from the plan; deconfigure()
 * restores 1. Nothing sets it to 0 before process shutdown.
 */

/* Each maps onto one engine-domain status. */
enum class ConfigureError {
    None,
    AssetMissing,          /* no network file for the variant */
    AssetMismatch,         /* the effective NNUE state after configuration */
    VariantLoadFailed,     /* the requested variant is not loadable */
    HashAllocationFailed,  /* the transposition table could not be allocated */
};

/*
 * Apply the plan: the requested variant, the shared search profile, the
 * networks, the thread count, and the Hash. The requested variant becomes the
 * active one until the next configure() or deconfigure().
 *
 * EvalFile is a LIST: the engine takes networks separated by UCI::SepChar and
 * picks the first whose basename begins with the current variant's identifier.
 * Every pinned network present is handed over, the requested variant's first,
 * so the engine can be re-prepared for the other variant.
 *
 * The requested network is checked afterwards against the engine's effective
 * NNUE state, because a basename not matching the variant clears the engine's
 * internal flag silently while the option still reads true. The check compares
 * against the token the engine would have SELECTED, never the whole option
 * value: a failed load leaves eval_file_loaded stale, and the engine's own
 * check only asks whether that name appears anywhere in the list. On any
 * refusal the engine is unwound whole to the deconfigured posture.
 *
 * Caller: the engine thread only, with no search outstanding.
 */
ConfigureError configure(Variant variant, uint32_t threads, uint32_t hash_mib,
                         const std::string &assets_dir, std::string &detail);

/* Release the transposition table and restore the rules posture: pool of 1,
 * minimal options, and the default variant's tables. Caller: the engine thread
 * with no search outstanding, or mxq_core_shutdown after that thread joined. */
void deconfigure();

enum class SearchError {
    None,
    ReplayFailed,  /* the line does not replay; the caller must pass a legal
                    * line */
    NoMove,        /* the engine reported no best move at all */
};

struct SearchOutput {
    std::string move;      /* canonical <from><to> */
    int32_t     score_cp = 0;
    uint32_t    depth = 0;
    uint64_t    nodes = 0;
};

/*
 * Run one search over the line in the active variant: replay moves from
 * start_fen, then think for movetime_ms. A line of another variant fails to
 * replay and returns ReplayFailed rather than being searched under the wrong
 * rules. cancelled is re-checked after the engine's stop flag is re-armed, so a
 * cancellation racing the start is not lost. Blocks until the engine finishes
 * or is stopped. Caller: the engine thread only.
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
