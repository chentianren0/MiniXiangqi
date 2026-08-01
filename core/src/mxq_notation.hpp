/*
 * The one authority on what a square and a move look like, and on the board
 * each game is played on.
 *
 * Square and move text crosses this core at four places — the session surface
 * judging a caller, the archive codec judging a file, the search facade judging
 * the engine's own output, and the fixture harness — and each of them used to
 * carry its own copy of the grammar. Three copies of one regular expression
 * agree until the day a second board exists, and then they disagree one at a
 * time: this module exists so that the board is a parameter rather than a
 * constant repeated.
 *
 * The grammar, whole:
 *
 *     square ::= file rank
 *     file   ::= 'a' .. the game's last file
 *     rank   ::= a decimal integer, 1 .. the game's last rank, no leading zero
 *     move   ::= square square
 *
 * A rank is therefore one character in Mini Xiangqi (1..7) and one or two in
 * Xiangqi (1..10), so a square is two or three characters and a move four to
 * six. Nothing in this notation is a suffix: neither game promotes a piece by
 * choice, so `<from><to>` is the whole move.
 *
 * Parsing is unambiguous without lookahead because a file is never a digit: the
 * digit run after a file character ends exactly where the next square begins.
 * `a1a10` is a1 then a10 and can be read no other way.
 */

#ifndef MXQ_NOTATION_HPP
#define MXQ_NOTATION_HPP

#include "mxq.h"

#include <cstddef>
#include <string>

namespace mxq {
namespace notation {

/* The board one game is played on: the two bounds every square is judged
 * against. */
struct Board {
    char    last_file;
    int32_t last_rank;
};

/* Whether game is a value this build defines. A game outside the closed
 * vocabulary is a caller's mistake, and every function below is defined only
 * for one that is inside it. */
bool known_game(MxqGameKind game);

Board board_of(MxqGameKind game);

/* The frozen starting position of one game, in the frozen 6-field FEN. */
const char *start_fen(MxqGameKind game);

/*
 * How many characters of `text` the square beginning at its start occupies, or
 * 0 when no square begins there. len bounds the read; text need not be
 * NUL-terminated.
 *
 * This is the primitive the other three are written in terms of, and it is
 * exposed because one caller needs it directly: asking whether a move begins at
 * a given square is a comparison over the first square's own length, and
 * comparing a fixed two characters is exactly the bug a 10th rank introduces.
 */
size_t square_length(MxqGameKind game, const char *text, size_t len);

/* Whether the whole NUL-terminated string is one square of this game's board.
 * A null pointer is not. */
bool well_formed_square(MxqGameKind game, const char *text);

/* Whether the whole string is one move of this game's board. */
bool well_formed_move(MxqGameKind game, const char *text);
bool well_formed_move(MxqGameKind game, const std::string &text);

/* Whether `move` — which the caller has already established is well formed —
 * begins at the square `from_square` names. */
bool move_begins_at(MxqGameKind game, const std::string &move,
                    const char *from_square);

} /* namespace notation */
} /* namespace mxq */

#endif /* MXQ_NOTATION_HPP */
