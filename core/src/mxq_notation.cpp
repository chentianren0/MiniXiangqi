/* The square-and-move-text authority. See mxq_notation.hpp for the grammar. */

#include "mxq_notation.hpp"

#include <cassert>
#include <cstring>

namespace mxq {
namespace notation {
namespace {

/* One row per game: the board, and the position it starts from. Both are
 * constants of the ruleset rather than of any core instance, which is why they
 * live beside the grammar that reads them rather than in the engine bridge that
 * plays them. */
struct GameRow {
    Board       board;
    const char *start_fen;
};

constexpr GameRow kGames[] = {
    /* MXQ_GAME_KIND_MINI_XIANGQI */
    {{'g', 7}, "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"},
    /* MXQ_GAME_KIND_XIANGQI */
    {{'i', 10},
     "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1"},
};

constexpr size_t kGameCount = sizeof(kGames) / sizeof(kGames[0]);

/* The enumerators are the row indices, and the two facts are asserted rather
 * than trusted: a game added to the vocabulary without a row here would
 * otherwise read one row past the table. */
static_assert(kGameCount == 2, "one row per MxqGameKind");
static_assert(MXQ_GAME_KIND_MINI_XIANGQI == 0 && MXQ_GAME_KIND_XIANGQI == 1,
              "the game vocabulary indexes this table");

const GameRow &row_of(MxqGameKind game) {
    assert(known_game(game) && "a game outside the closed vocabulary");
    return kGames[known_game(game) ? static_cast<size_t>(game) : 0u];
}

bool is_digit(char c) { return c >= '0' && c <= '9'; }

} /* namespace */

bool known_game(MxqGameKind game) {
    return game >= 0 && static_cast<size_t>(game) < kGameCount;
}

Board board_of(MxqGameKind game) { return row_of(game).board; }

const char *start_fen(MxqGameKind game) { return row_of(game).start_fen; }

size_t square_length(MxqGameKind game, const char *text, size_t len) {
    if (text == nullptr || len == 0) {
        return 0;
    }
    const Board board = board_of(game);
    if (text[0] < 'a' || text[0] > board.last_file) {
        return 0;
    }

    /* The whole digit run, never a prefix of it: a rank is bounded by the next
     * file character or by the end of the text, so stopping early would read
     * "a1" out of "a10" and call the rest a second square.
     *
     * The accumulator is bounded inside the loop rather than after it, and the
     * reason is that this text is untrusted: an archive's move strings reach
     * here from a file, and the format's string limit lets a caller spell a
     * digit run long enough to overflow an int32_t. Signed overflow is
     * undefined, and where it wrapped it would also invent spellings this
     * notation says it does not have — a rank that came back into range modulo
     * 2^32 would make "a4294967297" a square. Ranks only grow as digits are
     * appended, so a run that has passed the last rank can never return to
     * one, and stopping at that point is both the range test and the bound. */
    size_t digits = 0;
    int32_t rank = 0;
    while (1 + digits < len && is_digit(text[1 + digits])) {
        rank = rank * 10 + (text[1 + digits] - '0');
        ++digits;
        if (rank > board.last_rank) {
            return 0;
        }
    }
    if (digits == 0 || text[1] == '0') {
        /* No rank at all, or one spelled with a leading zero — which would give
         * a second spelling of a square this notation has exactly one of. */
        return 0;
    }
    /* Both bounds hold here without a further test: the loop returned for
     * anything above the last rank, and a run that begins with a digit other
     * than '0' is at least 1. */
    return 1 + digits;
}

bool well_formed_square(MxqGameKind game, const char *text) {
    if (text == nullptr) {
        return false;
    }
    const size_t len = std::strlen(text);
    /* The empty string is not a square, and the length test is what says so:
     * square_length answers 0 for it, and 0 == 0 would otherwise accept it. */
    return len != 0 && square_length(game, text, len) == len;
}

bool well_formed_move(MxqGameKind game, const char *text) {
    if (text == nullptr) {
        return false;
    }
    return well_formed_move(game, std::string(text));
}

bool well_formed_move(MxqGameKind game, const std::string &text) {
    const size_t from = square_length(game, text.data(), text.size());
    if (from == 0) {
        return false;
    }
    const size_t to =
        square_length(game, text.data() + from, text.size() - from);
    return to != 0 && from + to == text.size();
}

bool move_begins_at(MxqGameKind game, const std::string &move,
                    const char *from_square) {
    if (from_square == nullptr) {
        return false;
    }
    const size_t from = square_length(game, move.data(), move.size());
    if (from == 0) {
        return false;
    }
    /* Length first, then bytes: "a1" is a prefix of "a10" and a comparison of
     * the shorter one's characters alone would call a move from the tenth rank
     * a move from the first. */
    return std::strlen(from_square) == from &&
           move.compare(0, from, from_square) == 0;
}

} /* namespace notation */
} /* namespace mxq */
