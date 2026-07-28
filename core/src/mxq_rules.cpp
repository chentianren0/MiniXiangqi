/* The session-free rules facade.
 *
 * Only mxq_rules_start_fen is implemented at this stage: it is a constant of
 * the ruleset rather than of any core instance. mxq_rules_validate_fen,
 * mxq_rules_evaluate and mxq_rules_legal_moves need the pinned Fairy-Stockfish
 * fork. It is now vendored under core/third_party/fairy-stockfish and links
 * with -DMXQ_ENABLE_RULES_FACADE=ON, but these three are still deliberately
 * left undefined rather than stubbed — the error taxonomy has no
 * not-implemented code, and a stub that returned one would be inventing
 * contract vocabulary. Until they exist, the fixture runner reports NOT
 * IMPLEMENTED. */

#include "mxq_internal.hpp"

extern "C" {

MxqStatus MXQ_CALL mxq_rules_start_fen(char *out, size_t cap, size_t *out_len,
                                       MxqError *err) {
    return mxq::write_string(MXQ_START_FEN, out, cap, out_len, err);
}

} /* extern "C" */
