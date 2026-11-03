/*
 * The rules facade's one dispatch: which engine answers for which game. The
 * entry points in mxq_rules.cpp and the search facade judging the engine's move
 * both ask here, so they cannot disagree.
 *
 * The choice follows from the game alone, never from the position, the board
 * size or the move text. Jieqi goes to the Pikafish slice, since
 * Fairy-Stockfish knows nothing of face-down pieces; the placement games go to
 * Rapfi; the movement engine answers for the rest.
 */

#ifndef MXQ_RULES_HPP
#define MXQ_RULES_HPP

#include "mxq.h"


#include "mxq_engine_bridge.hpp"

#include <cstddef>
#include <string>
#include <vector>

namespace mxq {
namespace rules {

/*
 * at_occurrence is meaningful only for a repetition, which no placement game
 * has: no stone is ever removed, so no position occurs twice.
 */
using Adjudication = engine::Adjudication;

/* Why a replay did not complete. */
enum class ReplayError {
    None,
    NotInitialised,  /* the engine that plays this game was never brought up */
    StartFenInvalid, /* not a position of this game, or not one it may begin
                      * from */
    IllegalMove,     /* first_illegal is the offending index */
    Faulted,         /* the engine threw: an allocation it could not meet */
};

/*
 * Replay `moves` from `start_fen` under `game`'s rules, and report where the
 * line arrived: the position, whether the side to move is in check, the ply
 * count, the adjudication, and — when asked for — every legal move there.
 *
 * A history is replayed rather than a bare position evaluated, because the
 * outcome of a line is not always a function of its final position: repetition
 * and violation state derive from history in the xiangqi games, and in the
 * placement games a line that already ended cannot be played past.
 *
 * out_in_check is false in every placement game. On anything but
 * ReplayError::None the outputs are unspecified.
 */
ReplayError replay(MxqGameKind game, const char *start_fen,
                   const char *const *moves, size_t move_count,
                   std::string &out_fen, bool &out_in_check, uint32_t &out_ply,
                   Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal, std::string &detail);

/* Structural validation of one position against `game`'s own board, never a
 * judgment of setup legality: a position of another board fails it. */
bool validate_fen(MxqGameKind game, const char *fen, std::string &detail);

} /* namespace rules */
} /* namespace mxq */


#endif /* MXQ_RULES_HPP */
