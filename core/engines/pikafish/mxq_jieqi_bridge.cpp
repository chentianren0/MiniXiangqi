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

/* The slice's namespace is renamed; the alias is spelled at every call site so
 * each line shows which of the two Stockfish derivatives it reaches. */
namespace pf = PikafishJieqi;

namespace mxq {
namespace jieqi {
namespace {

/*
 * The record's letters in the engine's piece order. The two vocabularies spell
 * the seven pieces with the same letters, so only the face-down mark needs
 * translating.
 */
constexpr const char *kLettersLower = "racpnbk";

constexpr size_t kLetterCount = 7;

/*
 * The dialect's ceiling on face-down pieces per identity, not the game's: the
 * pool field spells one digit each. The setup predicate answers what a deal
 * gives. A general is never face down: the engine's pool has no king entry, so
 * revealing one would drive a count below zero and stand a second general.
 */
constexpr int32_t kFaceDownMost[kLetterCount] = {9, 9, 9, 9, 9, 9, 0};

/*
 * The standard array, rank 1 first. The engine reads a face-down piece's
 * colour and role off its own copy of this table, not the FEN, so a face-down
 * piece anywhere else is an out-of-bounds write there and a refusal here.
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

/* kLetterCount for a character that is no piece of this game. */
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

/* Arithmetic rather than a second table, so the orders cannot drift; the
 * static_assert below pins kLettersLower to the engine's enumerators. */
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

/* Our ranks run 1-10, the engine's 0-9, both from Red's back rank. Every square
 * crossing the bridge goes through here or square_text. */
pf::Square engine_square(int32_t file, int32_t rank) {
    assert(file >= 0 && file < kFiles && rank >= 0 && rank < kRanks &&
           "a point off this game's board");
    return static_cast<pf::Square>(rank * kFiles + file);
}

std::string square_text(pf::Square square) {
    const int32_t index = static_cast<int32_t>(square);
    std::string   out;
    out.push_back(static_cast<char>('a' + index % kFiles));
    out += std::to_string(index / kFiles + 1);
    return out;
}

/* False unless there are exactly six non-empty fields, which also refuses a
 * doubled or trailing space. */
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
 * No leading zero unless exactly "0". Nine digits at most so an untrusted run
 * cannot overflow the engine's int; the forty-move rule ends a game at eighty.
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

bool read_board(const std::string &field, Record &out, std::string &detail) {
    for (int32_t rank = 0; rank < kRanks; ++rank) {
        for (int32_t file = 0; file < kFiles; ++file) {
            out.letter[rank][file] = kEmpty;
            out.down[rank][file] = false;
        }
    }

    int32_t rank = kRanks - 1;
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
            /* Nine files cannot spell a two-digit run and a zero run means nothing;
             * either would be a second spelling of one position. */
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
 * The one walk both placement fields are written by: the record's, which spells
 * identities, and the engine dialect's, which spells face-down pieces `X`/`x`
 * and pools the identities. Sharing it guarantees both lay the same pieces on
 * the same squares.
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

std::string write_board(const Record &record) {
    return write_placement(
        record, [&record](std::string &out, int32_t rank, int32_t file) {
            out.push_back(record.letter[rank][file]);
            if (record.down[rank][file]) {
                out.push_back('~');
            }
        });
}

/* Position identity is placement, face-down marks and side to move; the
 * counters are ignored. Hidden identities never change within a game. */
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

/*
 * The engine's five-field position: face-down pieces as `X`/`x`, side to move,
 * the remaining pool as twelve letter-count pairs with zeros written out, and
 * the counters. The engine reads a face-down piece's role off its square, so
 * the pool, tallied from the `~` marks, is how the deal enters it.
 * read_record has bounded every count to one digit.
 */
std::string dialect_of(const Record &record) {
    int32_t pool[kLetterCount][2] = {{0, 0}};

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
        /* The engine's piece order less the king, White then Black. */
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

/*
 * Attack tables and Zobrist keys, once, before the first position is set. They
 * are read-only afterwards, so distinct positions are independent; a single
 * Position is not thread-safe (rule_judge mutates it), and each is a local.
 */
std::once_flag g_bootstrap;

void bootstrap() {
    pf::Bitboards::init();
    pf::Position::init();
}

/*
 * The engine reports a side-to-move-relative value and the rule that fired.
 *
 *  - Checkmate and stalemate are asked first; the engine reports neither.
 *  - The repetition class comes from the reported rule: one draw value covers
 *    threefold repetition, mutual perpetual check and mutual perpetual chase.
 *  - The loser of a decisive repetition comes from the value (the violator
 *    loses), never from who is to move at detection.
 *
 * rule_judge acts on a repetition when `++cnt == 2 || ply > i`; the second
 * clause is a search economy, and ply 0 excludes it, leaving the third
 * occurrence, where the outcome attaches.
 *
 * rule_judge writes value and rule on a false return too, so neither is read
 * unless it returned true.
 */
Adjudication adjudicate(pf::Position &pos,
                        const std::vector<std::string> &identities) {
    Adjudication a{};
    a.state = MXQ_GAME_ONGOING;
    a.reason = MXQ_END_REASON_NONE;
    a.at_occurrence = 0;

    const bool side_to_move_is_red = (pos.side_to_move() == pf::WHITE);

    if (pf::MoveList<pf::LEGAL>(pos).size() == 0) {
        /* Stalemate is a loss too, not a draw. */
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
        /* Only a capture resets the count, not a reveal. Automatic, so a committed
         * draw rather than a claimable one, and no position had to recur. */
        a.state = MXQ_GAME_DRAW;
        a.reason = MXQ_END_REASON_FORTY_MOVE_RULE;
        return a;
    }

    /* The engine says that an outcome attached, not where: an interrupted and
     * resumed violation attaches at the fourth occurrence, so count it. */
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
            /* Unreachable. An unknown rule is not evidence of a claimable repetition,
             * so answer ONGOING with no occurrence. */
            a.at_occurrence = 0;
            break;
        }
        return a;
    }

    /* A decisive repetition is automatic, not claim-gated. */
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
        /* A plain repetition is always drawn (a decisive value comes only with a
         * chase), so name no rule rather than guess: a wrong reason is stored with
         * the game forever, a missing one is caught by a fixture. */
        break;
    }
    return a;
}

bool read_move(const std::string &text, int32_t &from_file, int32_t &from_rank,
               int32_t &to_file, int32_t &to_rank) {
    size_t at = 0;
    const auto square = [&text, &at](int32_t &file, int32_t &rank) {
        if (at >= text.size() || text[at] < 'a' || text[at] > 'i') {
            return false;
        }
        file = text[at] - 'a';
        ++at;
        /* The whole digit run, so "a10" is not read as "a1" plus a stray "0". A
         * file letter is never a digit, so the run ends where the next square
         * begins. */
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

    /* The engine sets each general's square when it reads a position, so a
     * board without one leaves it at a1; and the pool is one digit per
     * identity with no general entry. Refuse both here rather than leave an
     * out-of-bounds write. */
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
        /* A Position points into its state list and adjudication walks it back,
         * so a deque: reallocation would invalidate the pointers. The Position is
         * on the heap because it carries a 16 KiB repetition filter and rule_judge
         * puts a second one on the stack during chase detection. */
        auto states = std::make_unique<std::deque<pf::StateInfo>>(1);
        auto pos = std::make_unique<pf::Position>();
        pos->set(dialect_of(record), &states->back());

        /* Every position stood in, start included, for occurrence counts. */
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

            /* An illegal move stops the replay rather than being skipped: a shortened
             * line answers about the wrong position and looks like an answer. */
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

            /* Revealed identities come only from the tracked record. */
            const char mover = record.letter[from_rank][from_file];
            const bool mover_down = record.down[from_rank][from_file];
            const char taken = record.letter[to_rank][to_file];
            const bool taken_down = record.down[to_rank][to_file];

            /*
             * do_move never touches the pool: a moving face-down piece flips through
             * do_flip, which decrements the pool and rebuilds the check state do_move
             * leaves empty for it; a captured face-down piece never flips, so its
             * identity leaves the pool through the accessor. This is the engine's own
             * sequence, without a transposition table.
             */
            states->emplace_back();
            pos->do_move(move, states->back());
            if (mover_down) {
                pos->do_flip(to, piece_of_letter(mover));
            }
            if (taken_down) {
                pos->rest_piece(piece_of_letter(taken))--;
            }

            /* The flip is mandatory, so the piece always arrives face up. */
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
            /* Read back from the engine, the counter rule_judge uses for the forty-move
             * rule, so the record and the outcome cannot disagree. */
            record.halfmove = static_cast<uint32_t>(pos->rule40_count());

            identities.push_back(identity_of(record));
        }

        out_fen = write_record(record);
        /* Bitboard is a 128-bit integer; its truth is the question. */
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
        /* No exception crosses the core. The slice allocates nothing; only this
         * bridge's state chain can run out of memory. */
        detail = "the jieqi rules authority could not allocate the state a "
                 "replay of this line needs";
        return ReplayError::Faulted;
    }
}

} /* namespace jieqi */
} /* namespace mxq */
