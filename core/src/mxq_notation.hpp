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
 *     move   ::= square square    in a movement game
 *              | square           in a placement game
 *
 * A rank is therefore one character in Mini Xiangqi (1..7) and one or two in
 * Xiangqi (1..10) and in the placement games (1..15), so a square is two or
 * three characters, a movement move four to six and a placement move two or
 * three. Nothing in this notation is a suffix: no game promotes a piece by
 * choice, so a move is its squares and nothing else.
 *
 * How many squares a move is comes from the game and never from the text's
 * length. A placement game's board has fifteen files, so `a1a1` is four
 * characters of legal squares there and is not a move of it at all — a length
 * test would read it as one, and the day two grammars share a board is the day
 * that becomes silent.
 *
 * Parsing is unambiguous without lookahead because a file is never a digit: the
 * digit run after a file character ends exactly where the next square begins.
 * `a1a10` is a1 then a10 and can be read no other way.
 *
 * The placement games' position encoding is this module's too, because nothing
 * below it owns one: their engine holds a board and has no notation for it. The
 * shape is the xiangqi games', which mxq.h documents on MxqPosition and
 * docs/xiangqi-rules.md fixes for those two — six fields, ranks separated by
 * '/' with the highest first, empty runs written as counts, and one letter per
 * stone whose case is its side.
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

/* What a move of one game is made of. A game has one of these for its whole
 * life; it is not a property of a position or of a move's text. */
enum class MoveClass {
    Movement,  /* a piece leaves a square and arrives at another: <from><to> */
    Placement, /* a stone arrives on an empty point and nothing moves: <at> */
};

/* Whether game is a value this build defines. A game outside the closed
 * vocabulary is a caller's mistake, and every function below is defined only
 * for one that is inside it. Which games a build defines is the build's: the
 * placement games need the engine that plays them, and a core compiled without
 * it does not carry them. */
bool known_game(MxqGameKind game);

Board board_of(MxqGameKind game);

MoveClass move_class_of(MxqGameKind game);

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

/* ------------------------------------------------------------------------- */
/* The placement games' position encoding                                     */
/* ------------------------------------------------------------------------- */

/*
 * Whether the whole NUL-terminated string is a position of this placement
 * game's board, judged against the frozen structural encoding and nothing else:
 * it says nothing about whether the game may be set up there, which is
 * mxq_rules_validate_setup's question and answers MXQ_ERR_RULES_ILLEGAL_POSITION
 * for every position of these games but their frozen start.
 *
 * Structural includes having exactly one spelling. An empty run may not follow
 * another empty run and may not be written with a leading zero, the third and
 * fourth fields are the '-' these games have nothing to put in, and the halfmove
 * clock is 0 — nothing is captured and no placement is reversible, so there is
 * no move-count rule for it to count toward and no other value it could take.
 *
 * detail receives the reason on a refusal, for MxqError.
 */
bool well_formed_placement(MxqGameKind game, const char *fen,
                           std::string &detail);

/*
 * The position a placement game's line has reached, in that encoding.
 *
 * `cells` is one entry per point of the board — MXQ_COLOR_NONE where empty —
 * indexed rank-major from rank 1 with file a first, so index i is file
 * i % files and rank i / files + 1. The side to move and both counters derive
 * from ply_count, because these games begin from one position: the first mover
 * has the even plies, a full move completes on every second one, and the
 * halfmove clock is 0 for as long as the game lasts.
 */
std::string write_placement(MxqGameKind game, const MxqColor *cells,
                            size_t cell_count, uint32_t ply_count);

/* The zero-based file and rank of the square this text names, for a game whose
 * moves are one square. False when the text is not a square of that board. */
bool point_of_square(MxqGameKind game, const char *text, int32_t &out_file,
                     int32_t &out_rank);

/* That square's text, from the same zero-based indices. */
std::string square_of_point(MxqGameKind game, int32_t file, int32_t rank);

} /* namespace notation */
} /* namespace mxq */

#endif /* MXQ_NOTATION_HPP */
