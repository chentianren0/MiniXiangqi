/*
 * The setup-legality predicate: whether a position could be a game's first
 * one, as a composed scene or an imported record's start must be.
 *
 *   - The answer is a class, not a sentence: which rule broke, whose it is, and
 *     where, so the app can localise the telling.
 *   - The answer must be reachable for a position no game could be played from.
 *     That rules out making a move: the engine asserts that no capture is of a
 *     general, and a position offering that capture is one of the things being
 *     judged. Counts and zones are board arithmetic; whether a side is in check
 *     is asked by setting a position and reading it, never by playing.
 */

#ifndef MXQ_SETUP_HPP
#define MXQ_SETUP_HPP

#include "mxq.h"


#include <string>

namespace mxq {
namespace setup {

/* side is MXQ_COLOR_NONE and square empty where the rule names neither. */
struct Violation {
    MxqSetupRule rule = MXQ_SETUP_RULE_NONE;
    MxqColor     side = MXQ_COLOR_NONE;
    std::string  square;
};

/* Why the predicate could not answer at all, as distinct from answering that
 * the position is illegal. */
enum class Error {
    None,
    NotInitialised,  /* the engine that plays this game was never brought up */
    FenInvalid,      /* not a position of this game's board at all */
};

/*
 * Judge `fen` as a position `game` may be set up in.
 *
 * On Error::None, out_violation's rule is MXQ_SETUP_RULE_NONE for a legal setup
 * and the first rule broken otherwise. A FEN that is not a position of this
 * game's board at all returns Error::FenInvalid, and `detail` says so.
 *
 * For Xiangqi the structural reading is this module's own rather than the
 * engine's validator, which wants a general a side: a board short of one is
 * what a composer has before the second tap, and it answers under the piece
 * count rule. Every other game keeps the validator as its precondition and
 * accepts its frozen start, or for Jieqi a dealt start, and nothing else.
 *
 * `detail` is filled on a refusal of either kind.
 */
Error evaluate(MxqGameKind game, const char *fen, Violation &out_violation,
               std::string &detail);

} /* namespace setup */
} /* namespace mxq */


#endif /* MXQ_SETUP_HPP */
