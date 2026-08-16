/*
 * The setup-legality predicate: whether a game may be set up in a position.
 *
 * It is a different question from every other one this core answers about a
 * position, and the difference is what earns it a module. The rules facade asks
 * what may be played over a position and what a line has arrived at; this asks
 * whether a position could be a game's first one at all — the question a player
 * composing a scene is really asking, and the one an imported record with a
 * start of its own has to survive.
 *
 * Two things follow from that and shape everything here:
 *
 *   - The answer is a class, not a sentence. The frontend that tells the player
 *     why must localise the telling, so the predicate reports which rule broke,
 *     whose it is, and where — never prose. mxq.h owns that vocabulary.
 *   - The answer must be reachable for a position no game could be played from.
 *     That rules out anything built on making a move: the engine asserts that no
 *     capture is of a general, and a position offering that capture is precisely
 *     one of the things being judged. Counts and zones are board arithmetic and
 *     ask no engine; the one question that needs the engine — is a side in
 *     check — is asked by setting a position and reading it, never by playing.
 *
 * Compiled only when MXQ_ENABLE_RULES_FACADE is ON, like the rest of the
 * facade: the check question is the engine's to answer.
 */

#ifndef MXQ_SETUP_HPP
#define MXQ_SETUP_HPP

#include "mxq.h"

#if defined(MXQ_ENABLE_RULES_FACADE)

#include <string>

namespace mxq {
namespace setup {

/* What one violation is: which rule broke, whose it is, and where. side is
 * MXQ_COLOR_NONE and square empty where the rule has no such thing, exactly as
 * MxqSetupViolation documents. */
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
 * For Xiangqi that reading is this module's own, taken against the frozen
 * encoding rather than against the engine's structural validator. The validator
 * wants a general a side, and a board short of one is exactly what a composer
 * has in front of them before the second tap: this predicate answers for it,
 * under the count clause, rather than declining to. Every other game keeps the
 * validator as its precondition, having one position to compare against and no
 * clauses to reach.
 *
 * `detail` is filled on a refusal of either kind, as the short English
 * diagnostic MxqError carries.
 */
Error evaluate(MxqGameKind game, const char *fen, Violation &out_violation,
               std::string &detail);

/* ------------------------------------------------------------------------- */
/* The per-game start policy                                                  */
/* ------------------------------------------------------------------------- */

/* What judge_start found. The three refusals are ordered as they are declared,
 * because a position that fails two must be refused by the earlier one however
 * it was reached. */
enum class StartError {
    None,
    NotInitialised, /* the engine that plays this game was never brought up */
    Structural,     /* not this game's board, or counters a start cannot carry */
    Illegal,        /* a position of this game, but not one to set up in */
};

/*
 * Whether `game` may **begin** from `fen`, which is one question above the
 * predicate rather than a second copy of it.
 *
 * Three callers ask it — creating a session, validating an archive's start, and
 * resuming a stored row — and each spells the answer in its own domain's codes,
 * which is why this reports a class and not a status. The rungs:
 *
 *   1. the counters, halfmove 0 and fullmove 1, and the six fields that having
 *      a fifth and a sixth to read means: a game beginning from a position has
 *      no plies behind it to count, so no other value is a start at all. They
 *      are a start's spelling rather than a position's, which is why they are
 *      asked here and not among the predicate's clauses;
 *   2. `evaluate` above — the game's own setup-legality predicate, which is
 *      total over every game and answers NOT_FROZEN_START for the three whose
 *      rules define none. The rest of the structure is read there, and a FEN it
 *      cannot read at all is Structural here.
 *
 * out_violation carries the predicate's answer, and is the empty violation for
 * every other outcome. `detail` is filled on every refusal.
 */
StartError judge_start(MxqGameKind game, const char *fen,
                       Violation &out_violation, std::string &detail);

} /* namespace setup */
} /* namespace mxq */

#endif /* MXQ_ENABLE_RULES_FACADE */

#endif /* MXQ_SETUP_HPP */
