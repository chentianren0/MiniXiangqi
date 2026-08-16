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

/* <atomic> for the search's cancellation flag below. It is included here
 * rather than relied upon transitively: libc++ pulls it in behind <string>
 * and <vector>, and the MSVC STL does not, so a header that used
 * std::atomic without saying so compiled on Apple platforms and failed to
 * parse at all under MSVC — taking the rest of this header's declarations
 * down with it. */
#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

namespace mxq {
namespace engine {

/* The variants this build can run, and there are exactly two.
 *
 * They are a closed set rather than a string a caller supplies, because
 * everything that follows a variant here is pinned to it one for one: an
 * identifier the engine knows, a network whose basename must begin with that
 * identifier, and that network's byte length and SHA-256. A string parameter
 * would make three of those four unpinnable, and the engine answers a variant
 * it does not know with a silent no-op rather than an error.
 *
 * MiniXiangqi is the app's pinned custom variant, defined in the bundled
 * configuration; Xiangqi is the engine's own built-in 9x10 game, registered
 * before any configuration is parsed. */
enum class Variant {
    MiniXiangqi,
    Xiangqi,
};

/* The variant one game is played under. The two vocabularies are deliberately
 * separate: MxqGameKind is a ruleset the product offers and an archive records,
 * engine::Variant is a configuration this engine can be asked to run, and the
 * mapping between them is this one function rather than an assumption that the
 * enumerators line up. */
Variant variant_of(MxqGameKind game);

/* The variant the engine's process-global tables are built for. Its default is
 * MiniXiangqi, which ensure_initialised establishes and deconfigure() restores;
 * configure() is the only thing that changes it. See the serialisation design
 * below for why that is not a matter of style. */
Variant active_variant();

/* The engine's identifier for a variant: what UCI_Variant is set to, and the
 * prefix its network's basename must begin with. */
const char *variant_id(Variant variant);

/* The SHA-256 pinned for that variant's network, lowercase hexadecimal. Half of
 * what identifies the configuration a move was produced by, and the half that
 * is per-variant. */
const char *variant_nnue_sha256(Variant variant);

/* Adjudication as the rules contract describes it, independent of how the
 * engine happens to report it. The engine returns one side-to-move-relative
 * Value, a flag, and which optional-end rule fired; docs/xiangqi-rules.md wants
 * a state, a reason, and the occurrence an outcome attached at. Translating
 * once, here, keeps every caller from re-deriving it — and re-deriving it
 * inconsistently is exactly how a repetition outcome gets attributed to the
 * wrong side. */
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
    VariantLoadFailed,  /* it parses, but a pinned variant is not in it */
};

/* Prepare the engine's process-global state and load the bundled variant
 * configuration. Idempotent; the first call does the work. Fills detail on
 * anything but None — which is a packaging failure, not a rules failure.
 *
 * Both variants must be in the variant map when this returns: the configuration
 * defines the custom one and the engine registers the built-in one, but the
 * registration is inside the engine's LARGEBOARDS guard, so "built in" is a
 * property of this build's defines rather than of the engine. A build that lost
 * that define would otherwise present a variant axis with one working end. */
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

/*
 * Replay moves from start_fen under `variant`, whichever variant the engine is
 * configured for.
 *
 * The variant is a parameter here and not in search_run(), and the difference
 * is which engine state each one needs. A search reads the process-global
 * tables a configuration builds — the PSQT and the evaluation those tables
 * feed — so it can only run in the active variant. A replay reads the variant
 * OBJECT for geometry, mobility regions, palace, river and adjudication, and
 * the only globals it touches besides are the ones UCI::init_variant builds:
 * pieceMap and the piece attack bitboards. Those are identical for both
 * variants of this build — pieceMap.init() defines every standard piece type
 * the same way whatever variant it is handed, neither game declares a custom
 * piece, and the attack tables are computed over the maximal board rather than
 * the variant's — so a replay of either game is correct against the tables the
 * other one left. That is what lets a Xiangqi rules query be answered while the
 * engine is prepared for Mini Xiangqi, without a table rebuild that would race
 * a running search.
 *
 * On anything but ReplayError::None the outputs are unspecified, exactly as
 * mxq_rules_evaluate documents. A history is replayed rather than a bare
 * position evaluated, because repetition and violation state derive from
 * history: docs/xiangqi-rules.md, "A bare position carries no prior
 * occurrences."
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

/* Structural FEN validation only, per mxq_rules_validate_fen: the frozen
 * encoding of `variant`'s own board, and never a judgment of setup legality. A
 * position of the other board fails it, because a board is part of what the
 * encoding fixes. */
bool validate_fen(Variant variant, const char *fen, std::string &detail);

/* Why the check probe below could not answer. */
enum class ProbeError {
    None,
    NotInitialised,
    FenInvalid,      /* not a position of this variant's board */
};

/*
 * Whether the side to move in `fen` stands in check.
 *
 * It exists so that the setup predicate can ask the question of the side that
 * is NOT to move without ever constructing a move: the caller flips the side to
 * move and asks this. That is not a stylistic preference. A position offering a
 * general capture is exactly what the predicate refuses, and the engine's
 * do_move asserts that no capture is of a KING — so any route to the answer
 * that applied a move would abort the process on the very input this exists to
 * judge. Nothing here applies one: the position is set and its checkers read,
 * which is state the engine computes at set() time. No move is generated and
 * none is made.
 *
 * The answer is the engine's ordinary attack relation and does NOT include the
 * flying-general one: the engine keeps that in legal() rather than in the
 * checkers it computes for a position, so two generals facing on an empty file
 * are not checkers of each other here. The caller owns that rule, which is
 * board arithmetic and needs no engine at all.
 *
 * Takes the same g_mutex a replay does, and for the same reason: it reads the
 * variant object and the tables a configuration builds.
 */
ProbeError side_to_move_in_check(Variant variant, const char *fen,
                                 bool &out_in_check, std::string &detail);

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
 *   - The variant, piece and bitboard tables are built for ONE variant at a
 *     time. There is no per-call variant: setting UCI_Variant rewrites
 *     pieceMap, the piece bitboards and the PSQT in place, so two variants
 *     cannot be live at once however the calls are arranged. ensure_initialised
 *     builds them for MiniXiangqi, and configure() and deconfigure() are the
 *     only things that rebuild them — configure() for the variant it is asked
 *     to prepare, deconfigure() back to MiniXiangqi. replay() reads them and
 *     never re-initialises them: re-running UCI::init_variant per replay
 *     rewrote process-global tables, identical values or not, under any
 *     concurrent reader. A table rebuilt only under the exclusion below is read
 *     by both sides and races with nothing.
 *   - configure() and deconfigure() are the only mutators of Options, the
 *     active variant, the pool size and the transposition table. Both run on
 *     the facade's engine thread, both are refused by the facade while a search
 *     is outstanding (MXQ_ERR_STATE_SEARCH_IN_PROGRESS — reconfiguration
 *     serialises behind search), and both take the same g_mutex the rules
 *     replay holds, so a replay never observes the tables, the active variant,
 *     the pool or the TT mid-mutation. A variant switch is therefore never
 *     concurrent with a search: it is exactly a reconfiguration, and it takes
 *     the reconfiguration's exclusion.
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
    VariantLoadFailed,     /* the requested variant is not loadable */
    HashAllocationFailed,  /* the transposition table could not be allocated */
};

/*
 * Apply the plan: the requested variant, the accepted shared search profile,
 * the networks, the thread count, and the Hash. The requested variant becomes
 * the active one, and searches run in it until the next configure() or
 * deconfigure().
 *
 * EvalFile is a LIST rather than a path — the engine accepts several networks
 * separated by UCI::SepChar and picks the first whose basename begins with the
 * current variant's identifier — so every pinned network present in the asset
 * directory is handed over, with the requested variant's own first. That is
 * what lets one prepared engine be re-prepared for the other variant without
 * the asset directory changing shape.
 *
 * Every network handed over is preflighted, and the requested variant's twice:
 * every one's bytes against ITS OWN pinned byte length and SHA-256 before the
 * engine sees a path, and then the engine's effective NNUE state after
 * configuration, because a basename that does not begin with the active
 * variant's identifier clears the engine's internal flag silently while the
 * option still reads true. That second check compares against the token the
 * engine would have SELECTED, never against the whole option value: the engine
 * leaves eval_file_loaded untouched when a load fails, and its own verification
 * asks only whether that stale name appears anywhere in the list — which, once
 * the list holds more than one network, it does. On any refusal the engine is
 * unwound whole to the deconfigured posture; it never keeps a partial
 * configuration.
 *
 * Caller: the facade's engine thread only, with no search outstanding.
 */
ConfigureError configure(Variant variant, uint32_t threads, uint32_t hash_mib,
                         const std::string &assets_dir, std::string &detail);

/* Release the transposition table whole and restore the rules posture: pool
 * of 1, minimal option floor, and the default variant's tables, so that the
 * bridge answers rules queries after a teardown exactly as it did before any
 * preparation whichever variant was prepared. Caller: the facade's engine
 * thread with no search outstanding, or mxq_core_shutdown after the engine
 * thread joined. */
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
 * Run one search over the snapshot, in the active variant: replay moves from
 * start_fen, then think for movetime_ms under the accepted shared profile. The
 * variant is not a parameter because it cannot be one — the tables the search
 * reads are the active variant's, and switching them is a reconfiguration —
 * so a snapshot of another variant fails to replay and returns ReplayFailed
 * rather than being searched under the wrong rules. cancelled is re-checked
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
