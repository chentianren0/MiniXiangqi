/* The Pikafish jieqi bridge. See mxq_jieqi_bridge.hpp for why it is its own
 * library and what the engine below it does not do for itself. */

#include "mxq_jieqi_bridge.hpp"

#include "bitboard.h"
#include "movegen.h"
#include "position.h"
#include "types.h"

#include <cassert>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <new>

/* The vendored slice is compiled with its whole namespace renamed, so the
 * engine's own name for itself is PikafishJieqi here and Stockfish nowhere. The
 * alias is spelled out at every call site below rather than pulled in with a
 * using-directive, so that a reader of any one line can see which of the two
 * embedded Stockfish derivatives it reaches. */
namespace pf = PikafishJieqi;

namespace mxq {
namespace jieqi {
namespace {

/* ------------------------------------------------------------------------- */
/* The board, the letters, and the standard array                            */
/* ------------------------------------------------------------------------- */

/*
 * The piece letters of the record form, lowercase, in the order the engine's own
 * piece vocabulary numbers them: rook, advisor, cannon, pawn, knight, bishop,
 * king. The two vocabularies spell the seven pieces with the same seven letters
 * — a chariot is a rook, a horse a knight, an elephant a bishop, a soldier a
 * pawn — so a letter needs no translation in either direction and only the
 * face-down mark does.
 */
constexpr const char *kLettersLower = "racpnbk";

constexpr size_t kLetterCount = 7;

/*
 * How many of one identity a side may hold face down, and it is the dialect's
 * ceiling rather than the game's: the pool field spells one digit per identity,
 * so nine is what a record can hand the engine. What a deal actually gives a
 * side — two of each piece and five soldiers — is the dealt-start question and
 * is answered by the setup predicate, which is where a shape that is no deal
 * gets the answer that says so.
 *
 * The general is the one exception, and it is not a ceiling but an absence. A
 * face-down general is a piece the pool field cannot carry at all: the engine's
 * pool has no king entry, so such a record would hand it fifteen dark squares
 * against fourteen pooled identities, and revealing that piece would drive its
 * count below zero and stand a second general on the board.
 */
constexpr int32_t kFaceDownMost[kLetterCount] = {9, 9, 9, 9, 9, 9, 0};

/*
 * The standard array, in the record's own letters, rank 1 first — the same
 * order this file indexes a Record by, and the same array the engine keeps its
 * own copy of. The engine reads a face-down piece's colour and role off this
 * table rather than out of its FEN, which is why a face-down piece anywhere but
 * one of these squares is an out-of-bounds write there and a refusal here.
 */
constexpr const char *kHomeRanks[kRanks] = {
    "RNBAKABNR", /* rank 1 */
    ".........", /* rank 2 */
    ".C.....C.", /* rank 3 */
    "P.P.P.P.P", /* rank 4 */
    ".........", /* rank 5 */
    ".........", /* rank 6 */
    "p.p.p.p.p", /* rank 7 */
    ".c.....c.", /* rank 8 */
    ".........", /* rank 9 */
    "rnbakabnr", /* rank 10 */
};

bool is_digit(char c) { return c >= '0' && c <= '9'; }

bool is_red_letter(char c) { return c >= 'A' && c <= 'Z'; }

char to_lower(char c) { return is_red_letter(c) ? static_cast<char>(c - 'A' + 'a') : c; }

/* The index of a letter in kLettersLower, or kLetterCount for a character that
 * is no piece of this game. */
size_t letter_index(char c) {
    const char lower = to_lower(c);
    for (size_t i = 0; i < kLetterCount; ++i) {
        if (kLettersLower[i] == lower) {
            return i;
        }
    }
    return kLetterCount;
}

MxqColor side_of_letter(char c) {
    return is_red_letter(c) ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
}

/*
 * The engine's Piece for one of our letters.
 *
 * The engine numbers its pieces ROOK=1 through KING=7 for White and the same
 * plus eight for Black, which is exactly kLettersLower's order offset by one.
 * It is arithmetic rather than a second table so that the two orders cannot
 * drift: kLettersLower is asserted against the engine's own enumerators below.
 */
pf::Piece piece_of_letter(char c) {
    const size_t index = letter_index(c);
    assert(index < kLetterCount && "a letter that is no piece of this game");
    const int value = static_cast<int>(index) + 1 +
                      (side_of_letter(c) == MXQ_COLOR_RED ? 0 : 8);
    return static_cast<pf::Piece>(value);
}

static_assert(pf::W_ROOK == 1 && pf::W_ADVISOR == 2 && pf::W_CANNON == 3 &&
                  pf::W_PAWN == 4 && pf::W_KNIGHT == 5 && pf::W_BISHOP == 6 &&
                  pf::W_KING == 7 && pf::B_ROOK == 9,
              "the letter order is the engine's piece order, offset by one");

/*
 * The engine's square for one of ours, and the only place the two coordinate
 * systems meet.
 *
 * This contract's ranks run 1 to 10 from Red's back rank and the engine's run 0
 * to 9 from the same rank, so a square translates by arithmetic in both
 * directions and never by copying. Every square this bridge hands the engine
 * and every square it reads back passes through here or through square_text
 * below; a rank that looks right is the failure this note exists to prevent.
 */
pf::Square engine_square(int32_t file, int32_t rank) {
    assert(file >= 0 && file < kFiles && rank >= 0 && rank < kRanks &&
           "a point off this game's board");
    return static_cast<pf::Square>(rank * kFiles + file);
}

/* The same translation, the other way: the record's own text for an engine
 * square. */
std::string square_text(pf::Square square) {
    const int32_t index = static_cast<int32_t>(square);
    std::string   out;
    out.push_back(static_cast<char>('a' + index % kFiles));
    out += std::to_string(index / kFiles + 1);
    return out;
}

/* ------------------------------------------------------------------------- */
/* Reading and writing the record form                                       */
/* ------------------------------------------------------------------------- */

/* The six fields, split on single spaces. False unless there are exactly six and
 * none is empty — which is also what refuses a doubled or a trailing space. */
bool split_fields(const std::string &text, std::string out[6]) {
    size_t begin = 0;
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

/*
 * A counter field: decimal digits with no leading zero unless the value is
 * exactly "0". The length is bounded because the value is handed to an engine
 * that reads it into an int: a record is untrusted input, and a digit run long
 * enough to overflow one is refused here rather than wrapped there. Nine digits
 * is far past anything either counter can reach — the forty-move rule ends a
 * game at eighty — and is comfortably inside an int.
 */
bool read_counter(const std::string &field, uint32_t &out) {
    if (field.empty() || field.size() > 9) {
        return false;
    }
    for (const char c : field) {
        if (!is_digit(c)) {
            return false;
        }
    }
    if (field.size() > 1 && field[0] == '0') {
        return false;
    }
    out = 0;
    for (const char c : field) {
        out = out * 10u + static_cast<uint32_t>(c - '0');
    }
    return true;
}

/*
 * The board field into the grid: ten ranks highest first, nine points each, an
 * empty run written as a single digit, and a face-down piece written as its
 * identity letter followed by `~`.
 */
bool read_board(const std::string &field, Record &out, std::string &detail) {
    for (int32_t rank = 0; rank < kRanks; ++rank) {
        for (int32_t file = 0; file < kFiles; ++file) {
            out.letter[rank][file] = kEmpty;
            out.down[rank][file] = false;
        }
    }

    int32_t rank = kRanks - 1; /* the field's first rank is the highest */
    int32_t file = 0;
    for (size_t at = 0; at < field.size(); ++at) {
        const char c = field[at];
        if (c == '/') {
            if (file != kFiles || rank == 0) {
                detail = "the board is not ten ranks of nine points";
                return false;
            }
            --rank;
            file = 0;
            continue;
        }
        if (is_digit(c)) {
            /* One digit is the whole of a run: nine files cannot spell a
             * two-digit one, and a run of zero has no meaning. Both would be a
             * second spelling of a position that has exactly one. */
            if (c == '0' || file + (c - '0') > kFiles) {
                detail = "an empty run runs past the rank it is in";
                return false;
            }
            file += c - '0';
            continue;
        }
        const size_t index = letter_index(c);
        if (index == kLetterCount || file >= kFiles) {
            detail = "the board field holds a character that is no piece of "
                     "this game";
            return false;
        }
        const bool down = (at + 1 < field.size() && field[at + 1] == '~');
        if (down) {
            ++at;
            if (!is_dark_home(file, rank)) {
                detail = "a face-down piece stands off its own start square, "
                         "which is a position this game cannot reach";
                return false;
            }
            if (side_of_letter(c) != side_of_letter(kHomeRanks[rank][file])) {
                detail = "a face-down piece stands on the other side's start "
                         "square";
                return false;
            }
        }
        out.letter[rank][file] = c;
        out.down[rank][file] = down;
        ++file;
    }
    if (rank != 0 || file != kFiles) {
        detail = "the board is not ten ranks of nine points";
        return false;
    }
    return true;
}

/*
 * The walk both placement fields are written by: ten ranks highest first, nine
 * points each, empty points counted into a run and every occupied one handed to
 * `emit`.
 *
 * There are two placement fields — the record's, which spells identities, and
 * the engine dialect's, which spells face-down pieces `X` and `x` and keeps
 * the identities in a pool beside the board — and they must lay the same pieces
 * on the same squares in the same order or the position the engine is handed is
 * not the position the caller was answered about. One walk is what makes that
 * true by construction rather than by two loops agreeing.
 */
template <typename Emit>
std::string write_placement(const Record &record, Emit emit) {
    std::string out;
    for (int32_t rank = kRanks - 1; rank >= 0; --rank) {
        int32_t run = 0;
        for (int32_t file = 0; file < kFiles; ++file) {
            if (record.letter[rank][file] == kEmpty) {
                ++run;
                continue;
            }
            if (run > 0) {
                out += std::to_string(run);
                run = 0;
            }
            emit(out, rank, file);
        }
        if (run > 0) {
            out += std::to_string(run);
        }
        if (rank > 0) {
            out.push_back('/');
        }
    }
    return out;
}

/* The board field of the record, without its five suffix fields: a face-down
 * piece is its identity letter followed by the mark that says the players do
 * not know it. */
std::string write_board(const Record &record) {
    return write_placement(
        record, [&record](std::string &out, int32_t rank, int32_t file) {
            out.push_back(record.letter[rank][file]);
            if (record.down[rank][file]) {
                out.push_back('~');
            }
        });
}

/* Placement — including which pieces are face down — and side to move, which is
 * what docs/jieqi-rules.md makes position identity: "the two counters are
 * ignored". The hidden identities never change inside one game, so two
 * positions of one line with equal visible boards have equal records, and this
 * is that comparison either way. */
std::string identity_of(const Record &record) {
    return write_board(record) +
           (record.side_to_move == MXQ_COLOR_RED ? " w" : " b");
}

size_t occurrences_of(const std::vector<std::string> &identities,
                      const std::string &here) {
    size_t n = 0;
    for (const std::string &past : identities) {
        if (past == here) {
            ++n;
        }
    }
    return n;
}

/* ------------------------------------------------------------------------- */
/* The engine's dialect                                                      */
/* ------------------------------------------------------------------------- */

/*
 * The record composed into the engine's own five-field position: the placement
 * with a face-down piece written `X` for Red and `x` for Black, the side to
 * move, the remaining pool as twelve letter-and-count pairs in a fixed order
 * with the zero counts written out, and the two counters.
 *
 * The pool is the deal entering the engine. A face-down piece's identity is not
 * in the engine's placement at all — it reads the role off the square, which is
 * jieqi's own rule about how such a piece moves — so the pool is what says which
 * identities are still concealed, and it is derived here from the `~` marks the
 * record holds. Counts are single digits in this dialect and read_record has
 * already bounded each at what a side can hold, so every count is spellable.
 */
std::string dialect_of(const Record &record) {
    int32_t pool[kLetterCount][2] = {{0, 0}};

    /* The same walk write_board takes, emitting the dialect's own two marks and
     * tallying the pool as it goes: what the placement stops saying is exactly
     * what the pool has to say instead. */
    std::string out = write_placement(
        record, [&record, &pool](std::string &out_field, int32_t rank,
                                 int32_t file) {
            const char c = record.letter[rank][file];
            if (!record.down[rank][file]) {
                out_field.push_back(c);
                return;
            }
            out_field.push_back(is_red_letter(c) ? 'X' : 'x');
            pool[letter_index(c)][is_red_letter(c) ? 0 : 1] += 1;
        });

    out += (record.side_to_move == MXQ_COLOR_RED ? " w " : " b ");
    for (int32_t side = 0; side < 2; ++side) {
        /* The engine writes and reads this field as rook, advisor, cannon,
         * pawn, knight, bishop — its own piece order, less the king — for White
         * and then for Black. kLettersLower is that order. */
        for (size_t i = 0; i + 1 < kLetterCount; ++i) {
            const char letter = kLettersLower[i];
            out.push_back(side == 0 ? static_cast<char>(letter - 'a' + 'A')
                                    : letter);
            assert(pool[i][side] <= 9 && "a pool count this dialect cannot spell");
            out += std::to_string(pool[i][side]);
        }
    }
    out += " " + std::to_string(record.halfmove) + " " +
           std::to_string(record.fullmove);
    return out;
}

/* ------------------------------------------------------------------------- */
/* Bootstrap                                                                 */
/* ------------------------------------------------------------------------- */

/*
 * The slice's whole bootstrap: the attack tables and the Zobrist keys, once.
 * Neither depends on the other and both must have run before the first position
 * is set, because setting one already reads the magic tables and the keys.
 *
 * There is no lock beyond this one, and that is the slice's own property rather
 * than an optimism: what these two fill is written once and read forever after,
 * so distinct positions are independent of each other once the bootstrap has
 * run. One position is not — adjudication is a non-const call on it and the move
 * machinery keeps a repetition filter inside it — and every position here is a
 * local of the call that made it.
 */
std::once_flag g_bootstrap;

void bootstrap() {
    pf::Bitboards::init();
    pf::Position::init();
}

/* ------------------------------------------------------------------------- */
/* Adjudication                                                              */
/* ------------------------------------------------------------------------- */

/*
 * The engine reports one side-to-move-relative Value, whether an ending fired,
 * and — since the fork's `report-the-rule` change — which rule produced it. The
 * contract wants a state and a reason:
 *
 *  - checkmate and stalemate are the caller's questions and are asked first,
 *    from there being no legal move and from whether the side to move is in
 *    check. The engine's own adjudication reports neither.
 *  - the repetition class comes from the reported rule and is never inferred:
 *    one draw value stands for a threefold repetition, a mutual perpetual check
 *    and a mutual perpetual chase alike, and the reported rule is the whole of
 *    what separates them.
 *  - who lost a decisive repetition comes from the value, by the accepted rule
 *    that the violating side loses — never from which side happens to be to move
 *    at detection.
 *
 * The third occurrence is where an outcome attaches, and the `ply` argument is
 * what makes that so. rule_judge acts on a repetition when `++cnt == 2 ||
 * ply > i`: the second half of that is a search reading two folds as enough,
 * which is a search's own economy and not this game's rule, and a ply of zero is
 * what excludes it. What is left is the third occurrence — two earlier ones
 * inside the capture-free window — which is exactly where the rules contract
 * attaches an outcome, so no count is compared here to hold the report back.
 *
 * rule_judge writes its value and its rule on a false return too — the two-fold
 * bound its own search reads — so nothing below is read unless it returned true.
 */
Adjudication adjudicate(pf::Position &pos,
                        const std::vector<std::string> &identities) {
    Adjudication a{};
    a.state = MXQ_GAME_ONGOING;
    a.reason = MXQ_END_REASON_NONE;
    a.at_occurrence = 0;

    const bool side_to_move_is_red = (pos.side_to_move() == pf::WHITE);

    if (pf::MoveList<pf::LEGAL>(pos).size() == 0) {
        /* Both are a loss for the player who cannot move, per
         * docs/jieqi-rules.md: "A position with no legal move is a loss for the
         * player who cannot move. Stalemate is not a draw." */
        a.state = side_to_move_is_red ? MXQ_GAME_BLACK_WINS : MXQ_GAME_RED_WINS;
        a.reason = pos.checkers() ? MXQ_END_REASON_CHECKMATE
                                  : MXQ_END_REASON_STALEMATE;
        return a;
    }

    pf::Value         value = pf::VALUE_DRAW;
    pf::RuleJudgeRule rule = pf::RULE_JUDGE_NONE;
    if (!pos.rule_judge(value, 0, &rule)) {
        return a;
    }

    if (rule == pf::RULE_JUDGE_RULE40) {
        /* Forty moves — eighty plies — without a capture, and only a capture
         * resets the count: no piece's own move resets it, and a reveal does not
         * either, irreversible though a reveal is. Automatic rather than
         * claimable, so it is a committed draw and not MXQ_GAME_CLAIMABLE_DRAW,
         * and its at_occurrence stays 0 because no position had to stand twice
         * for it. */
        a.state = MXQ_GAME_DRAW;
        a.reason = MXQ_END_REASON_FORTY_MOVE_RULE;
        return a;
    }

    /* The engine reports that an outcome attached, not where: a violation that
     * was interrupted and resumed attaches at the fourth occurrence, not the
     * third, so this is counted rather than assumed. */
    a.at_occurrence =
        static_cast<uint32_t>(occurrences_of(identities, identities.back()));

    if (value == pf::VALUE_DRAW) {
        switch (rule) {
        case pf::RULE_JUDGE_PERPETUAL_CHECK:
            a.state = MXQ_GAME_DRAW;
            a.reason = MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK;
            break;
        case pf::RULE_JUDGE_PERPETUAL_CHASE:
            a.state = MXQ_GAME_DRAW;
            a.reason = MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE;
            break;
        case pf::RULE_JUDGE_REPETITION:
            a.state = MXQ_GAME_CLAIMABLE_DRAW;
            a.reason = MXQ_END_REASON_THREEFOLD_REPETITION;
            break;
        default:
            /* Unreachable: the rules above are the whole of what a drawn
             * judgement can be, and RULE_JUDGE_NONE never accompanies a true
             * return. It is left unnamed rather than folded into the neutral
             * repetition — a rule this build does not know is not evidence that
             * a repetition is claimable, and answering ONGOING is the honest end
             * of that. The occurrence count goes with it, this being no outcome
             * at all. */
            a.at_occurrence = 0;
            break;
        }
        return a;
    }

    /* A decisive repetition is automatic, not claim-gated. The loser is the
     * violator, by the accepted rule that a violation is named by outcome and
     * never by who is to move at detection. */
    const bool side_to_move_wins = (value > pf::VALUE_DRAW);
    a.state = (side_to_move_is_red == side_to_move_wins) ? MXQ_GAME_RED_WINS
                                                         : MXQ_GAME_BLACK_WINS;
    switch (rule) {
    case pf::RULE_JUDGE_PERPETUAL_CHECK:
        a.reason = MXQ_END_REASON_PERPETUAL_CHECK;
        break;
    case pf::RULE_JUDGE_PERPETUAL_CHASE:
        a.reason = MXQ_END_REASON_PERPETUAL_CHASE;
        break;
    default:
        /* A plain repetition is drawn by construction — the chase detector
         * returns a decisive value only where exactly one side chased, and then
         * it reports a chase — so this arm names no rule rather than guessing
         * one. A wrong reason is recorded in the archive forever, while an
         * absent one is caught by a fixture. */
        break;
    }
    return a;
}

/* ------------------------------------------------------------------------- */
/* One ply                                                                   */
/* ------------------------------------------------------------------------- */

/* One move of the record's own coordinates, read. False for anything that is
 * not two squares of this board and nothing else. */
bool read_move(const std::string &text, int32_t &from_file, int32_t &from_rank,
               int32_t &to_file, int32_t &to_rank) {
    size_t at = 0;
    const auto square = [&text, &at](int32_t &file, int32_t &rank) {
        if (at >= text.size() || text[at] < 'a' || text[at] > 'i') {
            return false;
        }
        file = text[at] - 'a';
        ++at;
        /* The whole digit run, never a prefix of it: stopping early would read
         * "a1" out of "a10" and call the rest a second square. A file letter is
         * never a digit, so the run ends exactly where the next square begins
         * and no lookahead is needed. */
        if (at >= text.size() || !is_digit(text[at]) || text[at] == '0') {
            return false;
        }
        int32_t value = 0;
        while (at < text.size() && is_digit(text[at])) {
            value = value * 10 + (text[at] - '0');
            ++at;
            if (value > kRanks) {
                return false;
            }
        }
        rank = value - 1;
        return true;
    };
    return square(from_file, from_rank) && square(to_file, to_rank) &&
           at == text.size();
}

} /* namespace */

/* ------------------------------------------------------------------------- */
/* The interface                                                             */
/* ------------------------------------------------------------------------- */

char home_letter(int32_t file, int32_t rank) {
    assert(file >= 0 && file < kFiles && rank >= 0 && rank < kRanks &&
           "a point off this game's board");
    const char c = kHomeRanks[rank][file];
    return c == '.' ? kEmpty : c;
}

bool is_dark_home(int32_t file, int32_t rank) {
    const char c = home_letter(file, rank);
    return c != kEmpty && to_lower(c) != 'k';
}

bool read_record(const char *fen, Record &out, std::string &detail) {
    if (fen == nullptr) {
        detail = "the position was null";
        return false;
    }

    std::string fields[6];
    if (!split_fields(std::string(fen), fields)) {
        detail = "a position record is six fields separated by single spaces";
        return false;
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
    if (!read_counter(fields[4], out.halfmove)) {
        detail = "the halfmove clock is a decimal integer without a leading "
                 "zero";
        return false;
    }
    if (!read_counter(fields[5], out.fullmove) || out.fullmove == 0) {
        detail = "the fullmove number is a positive decimal integer without a "
                 "leading zero";
        return false;
    }
    if (!read_board(fields[0], out, detail)) {
        return false;
    }
    out.side_to_move = fields[1] == "w" ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;

    /*
     * Two counts, and both are what this entry owes the engine rather than
     * anything about how the position is spelled.
     *
     * A game cannot be played on a board a side has no general on, and the
     * engine keeps each general's square as state it sets when it reads the
     * position: a board without one leaves that square pointing at a1 and every
     * question about check reading a piece that is not there.
     *
     * And the pool the dialect carries is one digit per identity, with no entry
     * at all for a general, so a face-down count past those is a record this
     * bridge could not spell for the engine. Both are refusals of a position
     * the game never reaches, and both are made here rather than left to be
     * discovered as an out-of-bounds write.
     */
    int32_t generals[2] = {0, 0};
    int32_t face_down[kLetterCount][2] = {{0, 0}};
    for (int32_t rank = 0; rank < kRanks; ++rank) {
        for (int32_t file = 0; file < kFiles; ++file) {
            const char c = out.letter[rank][file];
            if (c == kEmpty) {
                continue;
            }
            const size_t index = letter_index(c);
            const int32_t side = side_of_letter(c) == MXQ_COLOR_RED ? 0 : 1;
            if (to_lower(c) == 'k') {
                ++generals[side];
            }
            if (out.down[rank][file]) {
                ++face_down[index][side];
            }
        }
    }
    if (generals[0] != 1 || generals[1] != 1) {
        detail = "a position of this game has exactly one general a side";
        return false;
    }
    for (size_t i = 0; i < kLetterCount; ++i) {
        for (int32_t side = 0; side < 2; ++side) {
            if (face_down[i][side] > kFaceDownMost[i]) {
                detail = kFaceDownMost[i] == 0
                             ? "a general is never face down"
                             : "a side holds more of one identity face down "
                               "than a position record can hand the engine";
                return false;
            }
        }
    }
    return true;
}

std::string write_record(const Record &record) {
    return write_board(record) +
           (record.side_to_move == MXQ_COLOR_RED ? " w" : " b") + " - - " +
           std::to_string(record.halfmove) + " " +
           std::to_string(record.fullmove);
}

ReplayError replay(const char *start_fen, const char *const *moves,
                   size_t move_count, std::string &out_fen, bool &out_in_check,
                   uint32_t &out_ply, Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal, std::string &detail) {
    std::call_once(g_bootstrap, bootstrap);

    Record record{};
    if (!read_record(start_fen, record, detail)) {
        return ReplayError::StartFenInvalid;
    }

    try {
        /* The state list must outlive every do_move: a Position holds a pointer
         * into it, and the adjudication walks the chain back. A deque rather
         * than a vector because reallocation would invalidate those pointers.
         *
         * Both it and the Position are on the heap, and the Position is there
         * for a reason of its own: it carries a sixteen-kibibyte repetition
         * filter, and rule_judge stands a second one of those on the stack for
         * the length of a chase detection. One of the two on the stack is a
         * cost the caller cannot see coming; two would be a deep replay's. */
        auto states = std::make_unique<std::deque<pf::StateInfo>>(1);
        auto pos = std::make_unique<pf::Position>();
        pos->set(dialect_of(record), &states->back());

        /* Every position the game has stood in, the start included, so an
         * occurrence count can be derived rather than assumed. */
        std::vector<std::string> identities;
        identities.reserve(move_count + 1);
        identities.push_back(identity_of(record));

        for (size_t i = 0; i < move_count; ++i) {
            if (moves == nullptr || moves[i] == nullptr) {
                first_illegal = i;
                detail = "a move in the history was null";
                return ReplayError::IllegalMove;
            }
            const std::string text(moves[i]);
            int32_t from_file = 0;
            int32_t from_rank = 0;
            int32_t to_file = 0;
            int32_t to_rank = 0;
            if (!read_move(text, from_file, from_rank, to_file, to_rank)) {
                first_illegal = i;
                detail = "move " + text + " is not two squares of this board";
                return ReplayError::IllegalMove;
            }

            /* The engine's own legal list is what a move is checked against,
             * and a move that is not in it stops the replay rather than being
             * skipped: a silently shortened line answers about a position
             * several plies from the one asked about, and looks exactly like an
             * answer. */
            const pf::Square from = engine_square(from_file, from_rank);
            const pf::Square to = engine_square(to_file, to_rank);
            pf::Move         move = pf::Move::none();
            for (const auto &candidate : pf::MoveList<pf::LEGAL>(*pos)) {
                if (candidate.from_sq() == from && candidate.to_sq() == to) {
                    move = candidate;
                    break;
                }
            }
            if (move == pf::Move::none()) {
                first_illegal = i;
                detail = "move " + text + " is not legal at its turn";
                return ReplayError::IllegalMove;
            }

            /*
             * The two identities this ply discloses, read from the record this
             * bridge has been tracking and from nothing else. The engine would
             * take a letter naming an enemy piece or an identity its pool has
             * run out of, and plant it; nothing outside this core ever supplies
             * one.
             */
            const char mover = record.letter[from_rank][from_file];
            const bool mover_down = record.down[from_rank][from_file];
            const char taken = record.letter[to_rank][to_file];
            const bool taken_down = record.down[to_rank][to_file];

            /*
             * The ply, in the engine's two halves. do_move never touches the
             * pool: a moving face-down piece flips through do_flip, which is
             * what decrements the pool and rebuilds the check state do_move
             * deliberately left empty for it, and a captured face-down piece
             * leaves the board face down, so its identity leaves the pool
             * through the accessor and never flips. It is the same pair of
             * steps the engine's own unvendored entry takes, and the
             * transposition table both entries take is left at its default of
             * none, this bridge holding no table for the engine to prefetch
             * into.
             */
            states->emplace_back();
            pos->do_move(move, states->back());
            if (mover_down) {
                pos->do_flip(to, piece_of_letter(mover));
            }
            if (taken_down) {
                pos->rest_piece(piece_of_letter(taken))--;
            }

            /* The record follows the same ply. A piece that was face down
             * arrives face up: the flip is mandatory, capture or no capture, and
             * there is no non-flipping alternative for the record to spell. */
            record.letter[to_rank][to_file] = mover;
            record.down[to_rank][to_file] = false;
            record.letter[from_rank][from_file] = kEmpty;
            record.down[from_rank][from_file] = false;
            if (record.side_to_move == MXQ_COLOR_BLACK) {
                ++record.fullmove;
            }
            record.side_to_move = record.side_to_move == MXQ_COLOR_RED
                                      ? MXQ_COLOR_BLACK
                                      : MXQ_COLOR_RED;
            /* The halfmove clock is read back from the engine rather than
             * counted a second time here. It is the same counter rule_judge
             * reads for the forty-move rule, so a record's fifth field and the
             * outcome that field drives cannot disagree about the same line. */
            record.halfmove = static_cast<uint32_t>(pos->rule40_count());

            identities.push_back(identity_of(record));
        }

        out_fen = write_record(record);
        /* Asked as a boolean rather than compared against 0: Bitboard is a
         * 128-bit integer here, and its truth is the question — whether the side
         * to move stands in check. */
        out_in_check = static_cast<bool>(pos->checkers());
        out_ply = static_cast<uint32_t>(move_count);
        out_adj = adjudicate(*pos, identities);

        if (out_legal_moves != nullptr) {
            out_legal_moves->clear();
            for (const auto &candidate : pf::MoveList<pf::LEGAL>(*pos)) {
                out_legal_moves->push_back(square_text(candidate.from_sq()) +
                                           square_text(candidate.to_sq()));
            }
        }
        return ReplayError::None;
    } catch (const std::bad_alloc &) {
        /* docs/architecture.md forbids an exception crossing the core's
         * boundary, and the slice itself allocates nothing: what can fail here
         * is this bridge's own state chain on a machine with no memory for it,
         * which is a resource the caller reports rather than an answer about the
         * position. */
        detail = "the jieqi rules authority could not allocate the state a "
                 "replay of this line needs";
        return ReplayError::Faulted;
    }
}

} /* namespace jieqi */
} /* namespace mxq */
