/*
 * The rules facade's one dispatch: which engine answers for which game.
 *
 * Four surfaces ask the same rules question — the session-free entry points in
 * mxq_rules.cpp, a session replaying its retained line, the archive validator
 * replaying a file, and the search facade judging the engine's own move — and
 * every one of them used to name an engine to ask. Two engines make that a
 * choice, and a choice made in four places is made differently in four places
 * the day a third game arrives. This is where it is made.
 *
 * The choice follows from the game and from nothing else, and it is one axis
 * rather than a property of the position, the board size or the move text — the
 * header's own rule about MxqGameKind, applied to the one decision that would
 * otherwise be tempted to guess.
 *
 * Three engines answer here, and the axis is no longer the move class alone.
 * Jieqi is a movement game whose rules authority is neither of the other two:
 * it is played on Xiangqi's board with the pieces face down, which
 * Fairy-Stockfish's xiangqi variant knows nothing about, so the vendored
 * Pikafish slice answers for it and for nothing else. The dispatch is therefore
 * a game-to-authority answer with the move class behind it: Jieqi's own, then
 * the placement games' by move class, then the movement engine for the rest.
 *
 * Compiled only when MXQ_ENABLE_RULES_FACADE is ON, with the placement arm
 * compiled only when MXQ_ENABLE_GOMOKU_FACADE is too. A build without the second
 * engine does not carry the placement games at all — notation::known_game is
 * where that is said, and every entry point taking a game passes through it —
 * so the arm's absence is unreachable rather than merely unlikely. The jieqi
 * slice shares the first engine's switch, so its arm is present whenever this
 * file is.
 */

#ifndef MXQ_RULES_HPP
#define MXQ_RULES_HPP

#include "mxq.h"

#if defined(MXQ_ENABLE_RULES_FACADE)

#include "mxq_engine_bridge.hpp"

#include <cstddef>
#include <string>
#include <vector>

namespace mxq {
namespace rules {

/*
 * Adjudication as the rules contracts describe it. It is the first engine's
 * shape because that shape is the wider one: at_occurrence is meaningful only
 * for a repetition-based outcome, which no placement game has — every ply there
 * adds a stone and none is ever removed, so no position of one occurs twice.
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
 * out_in_check is false in every placement game, which has no check to be in.
 *
 * On anything but ReplayError::None the outputs are unspecified, exactly as
 * mxq_rules_evaluate documents.
 */
ReplayError replay(MxqGameKind game, const char *start_fen,
                   const char *const *moves, size_t move_count,
                   std::string &out_fen, bool &out_in_check, uint32_t &out_ply,
                   Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal, std::string &detail);

/* Structural validation of one position against the frozen encoding of `game`'s
 * own board, and never a judgment of setup legality: a position of another
 * board fails it, which is what makes the game a question rather than a hint. */
bool validate_fen(MxqGameKind game, const char *fen, std::string &detail);

} /* namespace rules */
} /* namespace mxq */

#endif /* MXQ_ENABLE_RULES_FACADE */

#endif /* MXQ_RULES_HPP */
