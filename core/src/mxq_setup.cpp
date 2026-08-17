/* The setup-legality predicate. See mxq_setup.hpp for what it is and why it
 * never plays a move to find out. */

#include "mxq_setup.hpp"

#if defined(MXQ_ENABLE_RULES_FACADE)

#include "mxq_engine_bridge.hpp"
#include "mxq_jieqi_bridge.hpp"
#include "mxq_notation.hpp"
#include "mxq_rules.hpp"

#include <cstddef>
#include <string>
#include <vector>

namespace mxq {
namespace setup {
namespace {

/* ------------------------------------------------------------------------- */
/* The board this predicate has more than one answer for                      */
/* ------------------------------------------------------------------------- */

constexpr int32_t kFiles = 9;
constexpr int32_t kRanks = 10;

/* A position record is a 6-field FEN, and every game's is. */
constexpr size_t kFenFields = 6;

/* An empty point. No piece letter is 0, so the grid needs no second array to
 * say which of its cells are occupied. */
constexpr char kEmpty = '\0';

/* Indexed [rank from Red's back rank][file from a], both zero-based, so that
 * cell[0][3] is d1 and cell[9][3] is d10. The FEN's own order is the other way
 * round and the parser is where that is turned. */
struct Grid {
    char cell[kRanks][kFiles];
};

/* The pieces of the game, as the predicate reasons about them rather than as
 * the engine types them. */
enum class Kind {
    General,
    Advisor,
    Elephant,
    Horse,
    Chariot,
    Cannon,
    Soldier,
};

struct LetterRow {
    char letter; /* lowercase; the uppercase spelling is Red's */
    Kind kind;
};

/*
 * The frozen letters of docs/xiangqi-rules.md, and two more.
 *
 * The engine's own xiangqi variant registers 'h' for the horse and 'e' for the
 * elephant as synonyms, so a FEN spelling either is one mxq_rules_validate_fen
 * accepts and the engine will play. A predicate that could not read the board
 * would refuse a position that entry had just accepted, and for a reason no
 * caller could act on. Two rows are cheaper than that.
 */
constexpr LetterRow kLetters[] = {
    {'k', Kind::General},  {'a', Kind::Advisor}, {'b', Kind::Elephant},
    {'n', Kind::Horse},    {'r', Kind::Chariot}, {'c', Kind::Cannon},
    {'p', Kind::Soldier},  {'e', Kind::Elephant}, {'h', Kind::Horse},
};

/* How many of each a side may have. The general is the one row with a floor as
 * well as a ceiling, and it is a row rather than a special case so that the
 * count rule is one table read in one loop. */
struct CountRow {
    Kind        kind;
    int32_t     least;
    int32_t     most;
    const char *name; /* for MxqError.detail, which is English and never copy */
};

constexpr CountRow kCounts[] = {
    {Kind::General, 1, 1, "general"},   {Kind::Advisor, 0, 2, "advisor"},
    {Kind::Elephant, 0, 2, "elephant"}, {Kind::Horse, 0, 2, "horse"},
    {Kind::Chariot, 0, 2, "chariot"},   {Kind::Cannon, 0, 2, "cannon"},
    {Kind::Soldier, 0, 5, "soldier"},
};

constexpr size_t kKindCount = sizeof(kCounts) / sizeof(kCounts[0]);

/*
 * Where a piece may stand is where it can ever be, and for three of the seven
 * that is a list of points rather than a region. Each list is written once in
 * Red's own frame; Black's are these mirrored, which is what own_rank below
 * does for every zone rule at once.
 */
struct Point {
    int32_t file;
    int32_t rank;
};

/*
 * The seven points an elephant may stand on: c1 and g1, a3 and e3 and i3, c5
 * and g5. They are the whole of where an elephant can ever be — it steps
 * exactly two diagonally from one of two starting points and never crosses the
 * river — so "on its own side" and "on one of seven points" are the same rule,
 * and this is the stricter and truer spelling of it.
 */
constexpr Point kElephantPoints[] = {
    {2, 0}, {6, 0},         /* c1, g1 */
    {0, 2}, {4, 2}, {8, 2}, /* a3, e3, i3 */
    {2, 4}, {6, 4},         /* c5, g5 */
};

/*
 * The five points an advisor may stand on: d1 and f1, e2, d3 and f3 — the
 * palace's four corners and its centre. An advisor steps one diagonally from
 * d1 or f1 and never leaves the palace, and those five are the whole of where
 * that leaves it: the palace's four edge midpoints are inside the palace and
 * an advisor reaches none of them, so "inside its own palace" is the laxer
 * rule and this is the one the game has.
 */
constexpr Point kAdvisorPoints[] = {
    {3, 0}, {5, 0}, /* d1, f1 */
    {4, 1},         /* e2 */
    {3, 2}, {5, 2}, /* d3, f3 */
};

/* The palace, in the same frame: files d to f, the first three ranks. It is
 * the general's zone, and its own: the general walks the nine points
 * orthogonally, so every one of them is a point it can stand on. */
constexpr int32_t kPalaceFirstFile = 3;
constexpr int32_t kPalaceLastFile = 5;
constexpr int32_t kPalaceLastRank = 2;

/* Where a soldier starts, in the same frame: rank 4, zero-based 3. A soldier
 * never moves backward, so no soldier is ever behind it. */
constexpr int32_t kSoldierStartRank = 3;

/* The first rank across the river, zero-based 5. What a soldier gains there is
 * the sideways step, and with it every file. */
constexpr int32_t kSoldierCrossedRank = 5;

/*
 * A rank counted from a side's own back rank rather than from Red's.
 *
 * Every zone rule below is written once, in Red's frame, and read through this.
 * The alternative is each rule stated twice with the mirror worked out by hand
 * in the second copy, which is where the two copies stop agreeing.
 */
int32_t own_rank(MxqColor side, int32_t rank) {
    return side == MXQ_COLOR_RED ? rank : (kRanks - 1 - rank);
}

bool decode(char c, Kind &out_kind, MxqColor &out_side) {
    const bool red = (c >= 'A' && c <= 'Z');
    const char lower = red ? static_cast<char>(c - 'A' + 'a') : c;
    for (const LetterRow &row : kLetters) {
        if (row.letter == lower) {
            out_kind = row.kind;
            out_side = red ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
            return true;
        }
    }
    return false;
}

const char *side_name(MxqColor side) {
    return side == MXQ_COLOR_RED ? "red" : "black";
}

std::string square_of(int32_t file, int32_t rank) {
    return notation::square_of_point(MXQ_GAME_KIND_XIANGQI, file, rank);
}

/* ------------------------------------------------------------------------- */
/* Reading the position                                                       */
/* ------------------------------------------------------------------------- */

std::vector<std::string> fields_of(const std::string &fen) {
    std::vector<std::string> out;
    size_t at = 0;
    while (at <= fen.size()) {
        const size_t space = fen.find(' ', at);
        if (space == std::string::npos) {
            out.push_back(fen.substr(at));
            break;
        }
        out.push_back(fen.substr(at, space - at));
        at = space + 1;
    }
    return out;
}

/* A counter field, as the frozen encoding spells one: decimal digits, and no
 * leading zero on anything but zero itself. Its value is not this predicate's
 * question — neither counter is a rule about where pieces may stand — but its
 * spelling is, because a position of no board is what a record that cannot be
 * read back is. */
bool is_counter(const std::string &field) {
    for (const char c : field) {
        if (c < '0' || c > '9') {
            return false;
        }
    }
    return !field.empty() && (field.size() == 1 || field[0] != '0');
}

/* The board field, into the grid: the frozen encoding of
 * docs/xiangqi-rules.md read exactly — ten ranks highest first, nine files
 * each, an empty run written as its count. */
bool parse_board(const std::string &field, Grid &out) {
    for (int32_t r = 0; r < kRanks; ++r) {
        for (int32_t f = 0; f < kFiles; ++f) {
            out.cell[r][f] = kEmpty;
        }
    }

    int32_t rank = kRanks - 1; /* the field's first rank is the highest */
    int32_t file = 0;
    for (const char c : field) {
        if (c == '/') {
            if (file != kFiles || rank == 0) {
                return false;
            }
            --rank;
            file = 0;
            continue;
        }
        if (c >= '1' && c <= '9') {
            /* One digit is the whole of a run: nine files cannot spell a
             * two-digit one, and a run of zero has no meaning. */
            const int32_t run = c - '0';
            if (file + run > kFiles) {
                return false;
            }
            file += run;
            continue;
        }
        Kind kind = Kind::General;
        MxqColor side = MXQ_COLOR_NONE;
        if (file >= kFiles || !decode(c, kind, side)) {
            return false;
        }
        out.cell[rank][file] = c;
        ++file;
    }
    return rank == 0 && file == kFiles;
}

/* ------------------------------------------------------------------------- */
/* The rules                                                                  */
/* ------------------------------------------------------------------------- */

/* The four zones, each read in its own side's frame. */

template <size_t N>
bool on_one_of(const Point (&points)[N], int32_t file, int32_t own) {
    for (const Point &point : points) {
        if (point.file == file && point.rank == own) {
            return true;
        }
    }
    return false;
}

bool in_palace(int32_t file, int32_t own) {
    return file >= kPalaceFirstFile && file <= kPalaceLastFile &&
           own <= kPalaceLastRank;
}

bool on_advisor_point(int32_t file, int32_t own) {
    return on_one_of(kAdvisorPoints, file, own);
}

bool on_elephant_point(int32_t file, int32_t own) {
    return on_one_of(kElephantPoints, file, own);
}

bool on_soldier_point(int32_t file, int32_t own) {
    /* Two clauses, and the second ends at the river. Before it crosses, a
     * soldier moves only forward, so it still stands on the file it started
     * on, and the five starting files are a, c, e, g and i — the even indices.
     * Across the river it steps sideways as well, and from there every file is
     * reachable. */
    return own >= kSoldierStartRank &&
           (own >= kSoldierCrossedRank || file % 2 == 0);
}

/*
 * One row per kind: where it may stand, which rule that is, and how to say so.
 *
 * The three used to be three switches over the same enum — where, which rule,
 * which words — and a kind with no zone answered each of them separately. Three
 * answers to one question disagree the day one of them is edited, and the one
 * that disagrees silently is the middle one: a kind whose zone test says "legal
 * everywhere" while its rule says PALACE is a piece refused for standing where
 * it may. A row cannot come apart that way, and `inside == nullptr` is the whole
 * of what "this kind has no zone" means — a chariot, a horse and a cannon reach
 * every point of the board.
 */
struct ZoneRow {
    Kind         kind;
    bool       (*inside)(int32_t file, int32_t own_rank);
    MxqSetupRule rule;
    const char  *detail;
};

/* The general and the advisor share MXQ_SETUP_RULE_PALACE and not a zone: the
 * class is one per palace piece's own reach, and the two reaches differ — the
 * general walks all nine points, the advisor the five it can step to. */
constexpr ZoneRow kZones[] = {
    {Kind::General, in_palace, MXQ_SETUP_RULE_PALACE,
     "stands outside its own palace"},
    {Kind::Advisor, on_advisor_point, MXQ_SETUP_RULE_PALACE,
     "stands off the five palace points an advisor reaches"},
    {Kind::Elephant, on_elephant_point, MXQ_SETUP_RULE_ELEPHANT_SIDE,
     "stands off its own side's seven points"},
    {Kind::Horse, nullptr, MXQ_SETUP_RULE_NONE, nullptr},
    {Kind::Chariot, nullptr, MXQ_SETUP_RULE_NONE, nullptr},
    {Kind::Cannon, nullptr, MXQ_SETUP_RULE_NONE, nullptr},
    {Kind::Soldier, on_soldier_point, MXQ_SETUP_RULE_SOLDIER_RANK,
     "stands behind its own starting rank or, before the river, off its own "
     "starting files"},
};

/* Both per-kind tables are indexed by the enumerator, so a lookup is total by
 * construction and no arm can be missing to fall through. A row out of order —
 * or a kind added without one — is a compile error rather than a read past the
 * end or a silently wrong row, which is the same guarantee mxq_notation.cpp
 * gives its per-game table. */
template <typename Row, size_t N>
constexpr bool indexed_by_kind(const Row (&rows)[N]) {
    for (size_t i = 0; i < N; ++i) {
        if (static_cast<size_t>(rows[i].kind) != i) {
            return false;
        }
    }
    return true;
}

static_assert(sizeof(kZones) / sizeof(kZones[0]) == kKindCount,
              "one zone row per kind, the zoneless kinds included");
static_assert(indexed_by_kind(kZones), "the kind vocabulary indexes kZones");
static_assert(indexed_by_kind(kCounts), "the kind vocabulary indexes kCounts");

const ZoneRow &zone_of(Kind kind) {
    return kZones[static_cast<size_t>(kind)];
}

const CountRow &count_of(Kind kind) {
    return kCounts[static_cast<size_t>(kind)];
}

const char *kind_name(Kind kind) { return count_of(kind).name; }

/* Where a side's general stands, or false where it has none — which the count
 * rule has already refused by the time anything below asks. */
bool general_square(const Grid &grid, MxqColor side, int32_t &out_file,
                    int32_t &out_rank) {
    for (int32_t rank = 0; rank < kRanks; ++rank) {
        for (int32_t file = 0; file < kFiles; ++file) {
            const char c = grid.cell[rank][file];
            if (c == kEmpty) {
                continue;
            }
            Kind kind = Kind::General;
            MxqColor at = MXQ_COLOR_NONE;
            if (decode(c, kind, at) && kind == Kind::General && at == side) {
                out_file = file;
                out_rank = rank;
                return true;
            }
        }
    }
    return false;
}

/* The flying-general relation: one file, and nothing standing between. The
 * engine keeps this in its legality test rather than in the checkers it
 * computes for a position, so it is asked here — where it is arithmetic over
 * one file and needs no engine at all. */
bool generals_face(const Grid &grid) {
    int32_t red_file = 0;
    int32_t red_rank = 0;
    int32_t black_file = 0;
    int32_t black_rank = 0;
    if (!general_square(grid, MXQ_COLOR_RED, red_file, red_rank) ||
        !general_square(grid, MXQ_COLOR_BLACK, black_file, black_rank)) {
        return false;
    }
    if (red_file != black_file) {
        return false;
    }
    const int32_t low = red_rank < black_rank ? red_rank : black_rank;
    const int32_t high = red_rank < black_rank ? black_rank : red_rank;
    for (int32_t rank = low + 1; rank < high; ++rank) {
        if (grid.cell[rank][red_file] != kEmpty) {
            return false;
        }
    }
    return true;
}

/* The same position with the side to move flipped, which is how the question
 * "is the side NOT to move in check" is asked without ever making a move. */
std::string with_side_flipped(const std::vector<std::string> &fields,
                              MxqColor side_to_move) {
    std::string out;
    for (size_t i = 0; i < fields.size(); ++i) {
        if (i != 0) {
            out += ' ';
        }
        out += (i == 1) ? (side_to_move == MXQ_COLOR_RED ? "b" : "w") : fields[i];
    }
    return out;
}

/* ------------------------------------------------------------------------- */
/* The xiangqi predicate                                                      */
/* ------------------------------------------------------------------------- */

Error evaluate_xiangqi(const std::string &fen, Violation &out,
                       std::string &detail) {
    /*
     * The structure first, and read here rather than taken from the engine's
     * validator, which is laxer in three places: it checks a rank's width only
     * where a '/' follows, so never the last one; it accepts an empty run
     * written with a leading zero; and it accepts a FEN whose later fields are
     * simply absent, needing only one. The stricter reading is this entry's,
     * because what it is judging is a position that will be stored and
     * replayed, and none of those spellings is one the frozen encoding has. All
     * three answer MXQ_ERR_RULES_INVALID_FEN, which is what a position of no
     * board is, and xq-set-009 pins that they do — a parse loosened toward the
     * validator would otherwise start judging a board the engine is not
     * playing.
     *
     * Nothing stands in front of this. The engine's validator also wants one
     * general a side, and that is a question about the pieces rather than about
     * the spelling: this predicate answers it as the count clause below, at a
     * point, for a side, to a composer who has not placed a general yet. A
     * board still missing one is a board this entry reads.
     */
    const std::vector<std::string> fields = fields_of(fen);
    Grid grid{};
    if (fields.size() != kFenFields ||
        (fields[1] != "w" && fields[1] != "b") || fields[2] != "-" ||
        fields[3] != "-" || !is_counter(fields[4]) || !is_counter(fields[5]) ||
        !parse_board(fields[0], grid)) {
        detail = "the position is not the frozen encoding of this game's board";
        return Error::FenInvalid;
    }
    const MxqColor side_to_move =
        fields[1] == "w" ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;

    /* 1. Where each piece stands, walked once from a1 upward, so a position
     *    with two misplaced pieces always names the same one.
     *
     *    It is the first question because the report is read by someone
     *    composing a position and tells them what to fix next, and a point is
     *    what they can point at. It is also what makes the report useful before
     *    the position is finished: a piece off the points its kind can reach is
     *    wrong whatever else is still missing from the board. */
    for (int32_t rank = 0; rank < kRanks; ++rank) {
        for (int32_t file = 0; file < kFiles; ++file) {
            const char c = grid.cell[rank][file];
            Kind kind = Kind::General;
            MxqColor side = MXQ_COLOR_NONE;
            if (c == kEmpty || !decode(c, kind, side)) {
                continue;
            }
            const ZoneRow &zone = zone_of(kind);
            if (zone.inside == nullptr ||
                zone.inside(file, own_rank(side, rank))) {
                continue;
            }
            out.rule = zone.rule;
            out.side = side;
            out.square = square_of(file, rank);
            detail = "the " + std::string(side_name(side)) + " " +
                     kind_name(kind) + " at " + out.square + " " + zone.detail;
            return Error::None;
        }
    }

    /* 2. The complement, per side. A count is a property of a side rather than
     *    of any one point, so it names no square — and it is asked of pieces
     *    that all stand where they may, which is what the walk above has just
     *    settled. The general's floor is one of these rows: a side with no
     *    general has a complement the game does not give, and saying so is this
     *    clause's answer rather than a refusal to answer. */
    for (const MxqColor side : {MXQ_COLOR_RED, MXQ_COLOR_BLACK}) {
        int32_t counted[kKindCount] = {0};
        for (int32_t rank = 0; rank < kRanks; ++rank) {
            for (int32_t file = 0; file < kFiles; ++file) {
                const char c = grid.cell[rank][file];
                Kind kind = Kind::General;
                MxqColor at = MXQ_COLOR_NONE;
                if (c == kEmpty || !decode(c, kind, at) || at != side) {
                    continue;
                }
                ++counted[static_cast<size_t>(kind)];
            }
        }
        for (size_t i = 0; i < kKindCount; ++i) {
            if (counted[i] >= kCounts[i].least && counted[i] <= kCounts[i].most) {
                continue;
            }
            out.rule = MXQ_SETUP_RULE_PIECE_COUNT;
            out.side = side;
            out.square.clear();
            detail = std::string(side_name(side)) + " has " +
                     std::to_string(counted[i]) + " " + kCounts[i].name +
                     (counted[i] < kCounts[i].least
                          ? "s; the game gives a side no fewer than " +
                                std::to_string(kCounts[i].least)
                          : "s; the game gives a side no more than " +
                                std::to_string(kCounts[i].most));
            return Error::None;
        }
    }

    /* 3. The two generals. Its own class rather than a case of the check below,
     *    because the relation is symmetric: whoever is to move, the position
     *    offers a general the capture of a general. */
    if (generals_face(grid)) {
        out.rule = MXQ_SETUP_RULE_FACING_GENERALS;
        out.side = MXQ_COLOR_NONE;
        out.square.clear();
        detail = "the two generals face each other on an otherwise empty file";
        return Error::None;
    }

    /* 4. The side that is not to move, which no position a game could be played
     *    from leaves in check. The side that IS to move may be: it answers as
     *    its first move, and the whole point of a scene is often exactly that.
     *
     *    The question is put to the engine by setting the position with the side
     *    to move flipped and reading its checkers. Nothing is played: this is a
     *    position that may offer the capture of a general, and the engine's
     *    do_move asserts that no capture is one.
     *
     *    It is the last clause, so it is reached only with one general a side
     *    standing where a general may — a board the engine's own validator
     *    accepts. Every board it would refuse has been answered above, in this
     *    predicate's own vocabulary, without the engine being asked. */
    const MxqColor waiting = side_to_move == MXQ_COLOR_RED ? MXQ_COLOR_BLACK
                                                           : MXQ_COLOR_RED;
    const std::string flipped = with_side_flipped(fields, side_to_move);
    bool in_check = false;
    switch (engine::side_to_move_in_check(
        engine::variant_of(MXQ_GAME_KIND_XIANGQI), flipped.c_str(), in_check,
        detail)) {
    case engine::ProbeError::None:
        break;
    case engine::ProbeError::FenInvalid:
        return Error::FenInvalid;
    case engine::ProbeError::NotInitialised:
        return Error::NotInitialised;
    }
    if (in_check) {
        int32_t file = 0;
        int32_t rank = 0;
        out.rule = MXQ_SETUP_RULE_OPPONENT_IN_CHECK;
        out.side = waiting;
        out.square = general_square(grid, waiting, file, rank)
                         ? square_of(file, rank)
                         : std::string();
        detail = std::string(side_name(waiting)) +
                 " is not to move and stands in check";
        return Error::None;
    }

    out.rule = MXQ_SETUP_RULE_NONE;
    out.side = MXQ_COLOR_NONE;
    out.square.clear();
    detail.clear();
    return Error::None;
}

/* ------------------------------------------------------------------------- */
/* The jieqi membership question: is this a dealt start?                      */
/* ------------------------------------------------------------------------- */

/*
 * Jieqi defines no setup-legality predicate, because there is no composed
 * position for one to judge: the only shape a game of it begins in is the one
 * the deal produces. What it has instead is a membership question, and this is
 * it — the same shape as the frozen-start comparison every other game but
 * Xiangqi answers, asked of a family of positions rather than of one, because
 * there is a start for every deal.
 *
 * It is board arithmetic and asks no engine. The record has already been read
 * structurally by the caller, so what is left is the deal's own shape: the
 * thirty-two start squares occupied and no other point, the two generals face
 * up on their own, the other thirty face down, and each side's fifteen hidden
 * identities a permutation of that side's fifteen non-general pieces. Red
 * moves first.
 *
 * The whole answer is one rule, MXQ_SETUP_RULE_NOT_DEALT_START, and it names
 * neither a side nor a point. That is not a shortcut: a deal is dealt whole, so
 * a position that is not one is not one at a square — there is no composer here
 * to be told what to fix next, the way Xiangqi's clauses tell one.
 */
Error evaluate_jieqi(const jieqi::Record &record, Violation &out,
                     std::string &detail) {
    const auto refuse = [&out, &detail](const char *why) {
        out.rule = MXQ_SETUP_RULE_NOT_DEALT_START;
        out.side = MXQ_COLOR_NONE;
        out.square.clear();
        detail = std::string("this game begins from a dealt start and from no "
                             "other position; ") +
                 why;
        return Error::None;
    };

    if (record.side_to_move != MXQ_COLOR_RED) {
        return refuse("a deal is dealt with Red to move");
    }

    /* The complement each side is dealt, indexed as the letters below are. */
    constexpr char kDealtLetters[] = {'r', 'n', 'b', 'a', 'c', 'p'};
    constexpr int32_t kDealtEach[] = {2, 2, 2, 2, 2, 5};
    constexpr size_t kDealtKinds = sizeof(kDealtLetters) / sizeof(kDealtLetters[0]);
    static_assert(sizeof(kDealtEach) / sizeof(kDealtEach[0]) == kDealtKinds,
                  "one count per dealt piece letter");

    int32_t dealt[kDealtKinds][2] = {{0, 0}};
    for (int32_t rank = 0; rank < jieqi::kRanks; ++rank) {
        for (int32_t file = 0; file < jieqi::kFiles; ++file) {
            const char here = record.letter[rank][file];
            const char home = jieqi::home_letter(file, rank);
            if (home == jieqi::kEmpty) {
                if (here != jieqi::kEmpty) {
                    return refuse("a piece stands off the thirty-two squares a "
                                  "deal fills");
                }
                continue;
            }
            if (here == jieqi::kEmpty) {
                return refuse("a square a deal fills is empty");
            }

            const bool general = (here == 'K' || here == 'k');
            const bool general_square = (home == 'K' || home == 'k');
            if (general_square) {
                /* The two generals are the only pieces that ever start face up,
                 * and each stands on its own point. */
                if (!general || here != home || record.down[rank][file]) {
                    return refuse("a general's point does not hold that "
                                  "general, face up");
                }
                continue;
            }
            if (!record.down[rank][file]) {
                return refuse("a piece a deal deals face down stands face up");
            }
            /* read_record has already refused a face-down piece of the other
             * side's colour and a face-down general, so what is left to count is
             * which piece each side was dealt. */
            for (size_t i = 0; i < kDealtKinds; ++i) {
                const bool red = (here >= 'A' && here <= 'Z');
                const char lower = red ? static_cast<char>(here - 'A' + 'a')
                                       : here;
                if (lower == kDealtLetters[i]) {
                    ++dealt[i][red ? 0 : 1];
                    break;
                }
            }
        }
    }

    for (size_t i = 0; i < kDealtKinds; ++i) {
        for (int32_t side = 0; side < 2; ++side) {
            if (dealt[i][side] != kDealtEach[i]) {
                return refuse("a side's fifteen hidden identities are not its "
                              "own fifteen non-general pieces");
            }
        }
    }

    out.rule = MXQ_SETUP_RULE_NONE;
    out.side = MXQ_COLOR_NONE;
    out.square.clear();
    detail.clear();
    return Error::None;
}

} /* namespace */

Error evaluate(MxqGameKind game, const char *fen, Violation &out_violation,
               std::string &detail) {
    out_violation = Violation{};
    detail.clear();

    if (fen == nullptr) {
        detail = "fen was null";
        return Error::FenInvalid;
    }

    /* Xiangqi reads its own structure. Its predicate is the one that has more
     * than a single answer, so it is the one asked about boards a game is not
     * yet playable on, and mxq_rules_validate_fen refuses two of those for the
     * engine's reasons rather than for the rules' — a board short of a general
     * is the one a composer meets on the first tap. What that entry checks
     * about the spelling, evaluate_xiangqi checks, and more strictly. */
    if (game == MXQ_GAME_KIND_XIANGQI) {
        return evaluate_xiangqi(std::string(fen), out_violation, detail);
    }

    /*
     * Jieqi reads its own record, and that one reading is both halves of what
     * every other game needs two for: it is the precondition
     * mxq_rules_validate_fen applies — the same function that entry calls for
     * this game — and it is the form the membership arithmetic below reads the
     * position in. Its membership question is the dealt start, that being the
     * only shape a game of it begins in.
     */
    if (game == MXQ_GAME_KIND_JIEQI) {
        jieqi::Record record{};
        if (!jieqi::read_record(fen, record, detail)) {
            return Error::FenInvalid;
        }
        return evaluate_jieqi(record, out_violation, detail);
    }

    /* For every other game the precondition stands, and it is the same one
     * mxq_rules_validate_fen applies: a FEN that is not a position of this
     * game's board is not a position this predicate has an opinion about. */
    if (!rules::validate_fen(game, fen, detail)) {
        return Error::FenInvalid;
    }

    /*
     * Every other game begins from its frozen starting position and no other.
     *
     * It is the same entry rather than a refusal at some other layer because
     * the question is the same question — may this game be set up here — and a
     * caller that had to know which games have a predicate would be re-deriving
     * the per-game policy this entry exists to state. The comparison is against
     * the whole frozen FEN, so it is against its side to move as well: a game
     * whose first mover is frozen has no second setup that differs only there.
     */
    if (notation::has_frozen_start(game) &&
        std::string(fen) == notation::start_fen(game)) {
        return Error::None;
    }
    out_violation.rule = MXQ_SETUP_RULE_NOT_FROZEN_START;
    detail = "this game may be set up only in its frozen starting position";
    return Error::None;
}

StartError judge_start(MxqGameKind game, const char *fen,
                       Violation &out_violation, std::string &detail) {
    out_violation = Violation{};
    detail.clear();

    if (fen == nullptr) {
        detail = "fen was null";
        return StartError::Structural;
    }

    /* The frozen start is a start of every game that has one and is asked
     * nothing: it is already spelled with the counters below and already
     * accepted by the predicate, and short-circuiting it keeps a build without
     * the engine a game is played on from being asked about that game's own
     * opening. A game with no frozen start has no such position to recognise,
     * and every start it is given goes down the rungs. */
    if (notation::has_frozen_start(game) &&
        std::string(fen) == notation::start_fen(game)) {
        return StartError::None;
    }

    /* Rung 1, the spelling of a start. Only the two counters are read here: the
     * rest of the structure is the predicate's own to read, and reading it
     * twice would be two answers to one question. A record of six fields is
     * what having a fifth and a sixth to read means, so that much is asked
     * first. */
    const std::vector<std::string> fields = fields_of(fen);
    if (fields.size() != kFenFields) {
        detail = "a position record is six fields, and this is not the frozen "
                 "encoding of this game's board";
        return StartError::Structural;
    }

    /* Rung 1 still: the counters. They are not the composer's to choose, and a
     * position carrying any others is not a start whatever its pieces say, so
     * this is asked before the predicate rather than among its clauses. */
    if (fields[4] != "0" || fields[5] != "1") {
        detail = "a start position carries halfmove 0 and fullmove 1; this one "
                 "carries counters a game with plies behind it would";
        return StartError::Structural;
    }

    /* Rung 2, the game's own predicate, which is where the rest of the
     * structure is read: a FEN it cannot read at all is Structural here, the
     * same class the counters answer in. */
    switch (evaluate(game, fen, out_violation, detail)) {
    case Error::None:
        break;
    case Error::FenInvalid:
        return StartError::Structural;
    case Error::NotInitialised:
        return StartError::NotInitialised;
    }
    return out_violation.rule == MXQ_SETUP_RULE_NONE ? StartError::None
                                                     : StartError::Illegal;
}

} /* namespace setup */
} /* namespace mxq */

#endif /* MXQ_ENABLE_RULES_FACADE */
