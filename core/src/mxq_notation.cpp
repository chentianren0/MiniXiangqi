#include "mxq_notation.hpp"

#include <cassert>
#include <cstring>

namespace mxq {
namespace notation {
namespace {

/* One row per game, indexed by MxqGameKind. start_fen is null for a game with
 * no frozen start. */
struct GameRow {
    Board       board;
    MoveClass   move_class;
    const char *start_fen;
    bool        carried;
    bool        searched; /* the engine axis, not the ruleset: see searched() */
};

/* The empty 15x15 board, where both placement games begin. */
constexpr const char *kPlacementStart =
    "15/15/15/15/15/15/15/15/15/15/15/15/15/15/15 w - - 0 1";

constexpr bool kPlacementCarried = true;

constexpr GameRow kGames[] = {
    /* MXQ_GAME_KIND_MINI_XIANGQI */
    {{'g', 7}, MoveClass::Movement,
     "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1", true, true},
    /* MXQ_GAME_KIND_XIANGQI */
    {{'i', 10}, MoveClass::Movement,
     "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1",
     true, true},
    /* MXQ_GAME_KIND_GOMOKU_15. Fifteen files spelled a..o with no letter
     * skipped, as renju notation writes them. */
    {{'o', 15}, MoveClass::Placement, kPlacementStart, kPlacementCarried, true},
    /* MXQ_GAME_KIND_RENJU. Gomoku's board and notation; what Black may play and
     * what wins differ, and no position or move text shows it. */
    {{'o', 15}, MoveClass::Placement, kPlacementStart, kPlacementCarried, true},
    /* MXQ_GAME_KIND_JIEQI. Xiangqi's board and move class; a move carries no
     * reveal, since the deal makes every reveal derivable. No frozen start and
     * no search. */
    {{'i', 10}, MoveClass::Movement, nullptr, true, false},
};

constexpr size_t kGameCount = sizeof(kGames) / sizeof(kGames[0]);

/* A game added to the vocabulary without a row here would read past the
 * table. */
static_assert(MXQ_GAME_KIND_MINI_XIANGQI == 0 && MXQ_GAME_KIND_XIANGQI == 1 &&
                  MXQ_GAME_KIND_GOMOKU_15 == 2 && MXQ_GAME_KIND_RENJU == 3 &&
                  MXQ_GAME_KIND_JIEQI == 4,
              "the game vocabulary indexes this table");
static_assert(kGameCount == 5, "one row per MxqGameKind, whatever a build runs");

const GameRow &row_of(MxqGameKind game) {
    assert(known_game(game) && "a game outside the closed vocabulary");
    return kGames[known_game(game) ? static_cast<size_t>(game) : 0u];
}

bool is_digit(char c) { return c >= '0' && c <= '9'; }

/* The two stone letters of a placement game's board field: the case is the
 * side, as in the xiangqi games. */
constexpr char kFirstMoverStone = 'S';
constexpr char kSecondMoverStone = 's';

int32_t file_count_of(const Board &board) {
    return board.last_file - 'a' + 1;
}

/*
 * One rank of a placement game's board field, from `text` up to the next '/' or
 * the end. Returns the number of characters consumed, or 0 when the rank is not
 * one this encoding spells.
 *
 * A rank has exactly one spelling:
 *
 *   - the rank must total exactly the file count, so no prefix of one is a rank
 *     and no rank runs past its own board;
 *   - digit consumption is greedy, so two adjacent runs are not spellable at
 *     all: "1" then "14" is read as 114, past the file count;
 *   - a run may not have a leading zero, so "07" is not a second "7".
 */
size_t placement_rank_length(const Board &board, const char *text, size_t len) {
    const int32_t files = file_count_of(board);
    int32_t       filled = 0;
    size_t        i = 0;
    while (i < len && text[i] != '/') {
        if (is_digit(text[i])) {
            if (text[i] == '0') {
                return 0;
            }
            int32_t run = 0;
            while (i < len && is_digit(text[i])) {
                run = run * 10 + (text[i] - '0');
                ++i;
                if (run > files) {
                    return 0;
                }
            }
            filled += run;
        } else if (text[i] == kFirstMoverStone || text[i] == kSecondMoverStone) {
            ++filled;
            ++i;
        } else {
            return 0;
        }
        if (filled > files) {
            return 0;
        }
    }
    return filled == files ? i : 0;
}

/* A field of a decimal counter: the whole of `text`, no leading zero unless the
 * value is exactly "0". */
bool well_formed_counter(const std::string &text) {
    if (text.empty()) {
        return false;
    }
    for (const char c : text) {
        if (!is_digit(c)) {
            return false;
        }
    }
    return text.size() == 1 || text[0] != '0';
}

/* The six fields, split on single spaces. False unless there are exactly six
 * and none is empty, which also refuses a doubled or trailing space. */
bool split_fields(const char *fen, std::string out[6]) {
    const std::string text(fen);
    size_t            begin = 0;
    for (size_t field = 0; field < 6; ++field) {
        const size_t space = text.find(' ', begin);
        const size_t end = (field == 5) ? text.size() : space;
        if (field < 5 && space == std::string::npos) {
            return false;
        }
        if (field == 5 && space != std::string::npos) {
            return false;
        }
        if (end <= begin) {
            return false;
        }
        out[field] = text.substr(begin, end - begin);
        begin = end + 1;
    }
    return true;
}

} /* namespace */

bool known_game(MxqGameKind game) {
    return game >= 0 && static_cast<size_t>(game) < kGameCount &&
           kGames[static_cast<size_t>(game)].carried;
}

Board board_of(MxqGameKind game) { return row_of(game).board; }

MoveClass move_class_of(MxqGameKind game) { return row_of(game).move_class; }

bool has_frozen_start(MxqGameKind game) {
    return row_of(game).start_fen != nullptr;
}

bool searched(MxqGameKind game) { return row_of(game).searched; }

const char *start_fen(MxqGameKind game) {
    /* The empty string keeps a caller that did not ask has_frozen_start from
     * dereferencing null, and compares unequal to every position. */
    const char *frozen = row_of(game).start_fen;
    assert(frozen != nullptr && "this game has no frozen start to report");
    return frozen != nullptr ? frozen : "";
}

size_t square_length(MxqGameKind game, const char *text, size_t len) {
    if (text == nullptr || len == 0) {
        return 0;
    }
    const Board board = board_of(game);
    if (text[0] < 'a' || text[0] > board.last_file) {
        return 0;
    }

    /* The whole digit run, never a prefix of it, so "a10" is not "a1" and a
     * second square.
     *
     * The accumulator is bounded inside the loop because the text is
     * untrusted: a long digit run would overflow int32_t, and a wrapped rank
     * could make "a4294967297" a square. A run past the last rank never
     * returns to one, so stopping there is both the range test and the
     * bound. */
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
        /* No rank at all, or a leading zero, which would be a second spelling
         * of a square. */
        return 0;
    }
    /* Both bounds hold: the loop returned for anything above the last rank,
     * and a run that does not begin with '0' is at least 1. */
    return 1 + digits;
}

bool well_formed_square(MxqGameKind game, const char *text) {
    if (text == nullptr) {
        return false;
    }
    const size_t len = std::strlen(text);
    /* The length test refuses the empty string, for which 0 == 0. */
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
    /* How many squares to demand is the game's answer, never the text's
     * length. */
    if (move_class_of(game) == MoveClass::Placement) {
        return from == text.size();
    }
    const size_t to =
        square_length(game, text.data() + from, text.size() - from);
    return to != 0 && from + to == text.size();
}

/* ------------------------------------------------------------------------- */
/* The placement games' position encoding                                     */
/* ------------------------------------------------------------------------- */

bool well_formed_placement(MxqGameKind game, const char *fen,
                           std::string &detail) {
    assert(move_class_of(game) == MoveClass::Placement &&
           "a placement position of a movement game");
    if (fen == nullptr) {
        detail = "the position was null";
        return false;
    }

    std::string fields[6];
    if (!split_fields(fen, fields)) {
        detail = "a position is six fields separated by single spaces";
        return false;
    }

    const Board   board = board_of(game);
    const int32_t ranks = board.last_rank;
    size_t        begin = 0;
    for (int32_t rank = 0; rank < ranks; ++rank) {
        const size_t consumed = placement_rank_length(
            board, fields[0].data() + begin, fields[0].size() - begin);
        if (consumed == 0) {
            detail = "rank " + std::to_string(ranks - rank) +
                     " of the board is not " + std::to_string(ranks) +
                     " points of this game's own encoding";
            return false;
        }
        begin += consumed;
        const bool last = (rank + 1 == ranks);
        if (last) {
            if (begin != fields[0].size()) {
                detail = "the board has more than " + std::to_string(ranks) +
                         " ranks";
                return false;
            }
        } else {
            if (begin >= fields[0].size() || fields[0][begin] != '/') {
                detail = "the board has fewer than " + std::to_string(ranks) +
                         " ranks";
                return false;
            }
            ++begin;
        }
    }

    if (fields[1] != "w" && fields[1] != "b") {
        detail = "the side to move is \"w\" or \"b\"";
        return false;
    }
    if (fields[2] != "-" || fields[3] != "-") {
        detail = "this game records nothing in the third and fourth fields, "
                 "which are \"-\"";
        return false;
    }
    if (fields[4] != "0") {
        detail = "this game has no move-count rule, so its halfmove clock is 0";
        return false;
    }
    if (!well_formed_counter(fields[5]) || fields[5] == "0") {
        detail = "the fullmove number is a positive decimal integer without a "
                 "leading zero";
        return false;
    }
    return true;
}

std::string write_placement(MxqGameKind game, const MxqColor *cells,
                            size_t cell_count, uint32_t ply_count) {
    const Board   board = board_of(game);
    const int32_t files = file_count_of(board);
    const int32_t ranks = board.last_rank;
    assert(move_class_of(game) == MoveClass::Placement &&
           "a placement position of a movement game");
    assert(cells != nullptr &&
           cell_count == static_cast<size_t>(files) * static_cast<size_t>(ranks) &&
           "one cell per point of this board");
    (void)cell_count;

    std::string out;
    /* The board field at its widest is one character per point plus a
     * separator between ranks; the suffixes are twelve more at 15x15, where the
     * fullmove number runs to three digits. MXQ_FEN_CAP is derived from this
     * bound. */
    out.reserve(static_cast<size_t>(files) * static_cast<size_t>(ranks) +
                static_cast<size_t>(ranks) + 16u);
    for (int32_t rank = ranks; rank >= 1; --rank) {
        int32_t run = 0;
        for (int32_t file = 0; file < files; ++file) {
            const MxqColor cell =
                cells[static_cast<size_t>(rank - 1) * static_cast<size_t>(files) +
                      static_cast<size_t>(file)];
            if (cell == MXQ_COLOR_NONE) {
                ++run;
                continue;
            }
            if (run > 0) {
                out += std::to_string(run);
                run = 0;
            }
            out.push_back(cell == MXQ_COLOR_RED ? kFirstMoverStone
                                                : kSecondMoverStone);
        }
        if (run > 0) {
            out += std::to_string(run);
        }
        if (rank > 1) {
            out.push_back('/');
        }
    }

    /* Every counter derives from the ply count, because these games begin from
     * one position and reach every other by play. */
    out += (ply_count % 2u == 0u) ? " w" : " b";
    out += " - - 0 ";
    out += std::to_string(ply_count / 2u + 1u);
    return out;
}

bool point_of_square(MxqGameKind game, const char *text, int32_t &out_file,
                     int32_t &out_rank) {
    if (!well_formed_square(game, text)) {
        return false;
    }
    out_file = text[0] - 'a';
    out_rank = 0;
    for (size_t i = 1; text[i] != '\0'; ++i) {
        out_rank = out_rank * 10 + (text[i] - '0');
    }
    --out_rank; /* the notation counts ranks from 1; these indices from 0 */
    return true;
}

std::string square_of_point(MxqGameKind game, int32_t file, int32_t rank) {
    const Board board = board_of(game);
    assert(file >= 0 && file < board.last_file - 'a' + 1 && rank >= 0 &&
           rank < board.last_rank && "a point off this game's board");
    (void)board;
    std::string out;
    out.push_back(static_cast<char>('a' + file));
    out += std::to_string(rank + 1);
    return out;
}

} /* namespace notation */
} /* namespace mxq */
