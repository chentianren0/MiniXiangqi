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

/* Prepare the engine's process-global state and load the bundled variant
 * configuration. Idempotent; the first call does the work. Returns false and
 * fills detail when the configuration cannot be loaded or the target variant is
 * absent from it — which is a packaging failure, not a rules failure. */
bool ensure_initialised(const char *assets_dir, std::string &detail);

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

} /* namespace engine */
} /* namespace mxq */

#endif /* MXQ_ENGINE_BRIDGE_HPP */
