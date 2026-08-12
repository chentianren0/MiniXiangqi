/*
 * The placement games' adapter runner: the notation the core owns for them, the
 * legality and adjudication the vendored engine answers, and the engine dispatch
 * that reaches that engine from the public surface.
 *
 * Everything here is driven through the public C surface. That is a difference
 * from the bridge runner beside it and not an accident: the bridge runner exists
 * because at its stage no public entry point reached the second engine, and this
 * one exists because now they all do.
 *
 * What it deliberately is not is a rules corpus. The vendored engine is the
 * rules authority for these games and it is unmodified and revision-pinned, so
 * there is no second reading for a corpus to hold it against and nothing that
 * could drift without a git-visible act. Every case below is one wiring claim
 * with a future change it would catch, and the cases are the check a deliberate
 * upstream rebase reruns. The recorded boundary: a fork change that ever touches
 * rules behaviour lands together with the test that pins it.
 *
 * The positions are built by hand from move lines rather than from stored
 * fixtures, which is the engine_search precedent: what is asserted is which
 * answer the adapter gets from the engine, and a file in between would only add
 * a place for the two to disagree.
 *
 * Without MXQ_ENABLE_GOMOKU_FACADE the core does not carry these games at all,
 * and every case reports NOT IMPLEMENTED.
 */

#include "mxq.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <random>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

int g_passed = 0;
int g_failed = 0;
int g_skipped = 0;
int g_checks = 0;

struct Case {
    std::string              name;
    std::vector<std::string> messages;
    std::string              skip_reason;

    explicit Case(std::string n) : name(std::move(n)) {}

    void skip(const std::string &why) { skip_reason = why; }

    void check(bool ok, const std::string &what) {
        ++g_checks;
        if (!ok) {
            messages.push_back(what);
        }
    }

    void check_eq(const std::string &got, const std::string &want,
                  const std::string &what) {
        check(got == want,
              what + ": expected \"" + want + "\", got \"" + got + "\"");
    }

    void check_eq(int64_t got, int64_t want, const std::string &what) {
        check(got == want, what + ": expected " + std::to_string(want) +
                               ", got " + std::to_string(got));
    }

    void check_status(MxqStatus got, MxqStatus want, const std::string &what) {
        check(got == want, what + ": expected " + mxq_status_name(want) +
                               ", got " + mxq_status_name(got));
    }

    void report() {
        if (!messages.empty()) {
            ++g_failed;
            std::cout << "  FAIL      " << name << "\n";
            for (const std::string &m : messages) {
                std::cout << "            " << m << "\n";
            }
            return;
        }
        if (!skip_reason.empty()) {
            ++g_skipped;
            std::cout << "  SKIP      " << name << "  (" << skip_reason << ")\n";
            return;
        }
        ++g_passed;
        std::cout << "  ok        " << name << "\n";
    }
};

#if MXQ_TEST_GOMOKU_FACADE

/* A fresh scratch directory per case, so no case can lean on another. */
fs::path scratch_root() {
    static const fs::path root = [] {
        std::random_device rd;
        char buffer[17];
        std::snprintf(buffer, sizeof(buffer), "%08x%08x", rd(), rd());
        return fs::temp_directory_path() /
               ("minixiangqi-gomoku-tests-" + std::string(buffer));
    }();
    return root;
}

fs::path scratch_dir(const char *name) {
    const fs::path dir = scratch_root() / name;
    std::error_code ec;
    fs::remove_all(dir, ec);
    fs::create_directories(dir, ec);
    return dir;
}

/*
 * One asset directory holding what both engines need: the first engine's variant
 * configuration and network, which mxq_core_init loads before anything else, and
 * the second engine's weights, which a preparation for a placement game reads.
 * The core takes one asset directory, and a distribution ships one, so the suite
 * builds the shape a distribution has rather than pointing each engine at its
 * own staged directory.
 */
fs::path combined_assets() {
    static const fs::path dir = [] {
        const fs::path out = scratch_root() / "assets";
        std::error_code ec;
        fs::create_directories(out, ec);
        for (const char *source : {MXQ_TEST_ASSETS_DIR, MXQ_TEST_GOMOKU_ASSETS_DIR}) {
            if (source == nullptr || *source == '\0') {
                continue;
            }
            for (const fs::directory_entry &entry :
                 fs::directory_iterator(fs::path(source), ec)) {
                fs::copy_file(entry.path(), out / entry.path().filename(),
                              fs::copy_options::overwrite_existing, ec);
            }
        }
        return out;
    }();
    return dir;
}

MxqError make_error() {
    MxqError err;
    std::memset(&err, 0, sizeof(err));
    err.struct_size = static_cast<uint32_t>(sizeof(err));
    return err;
}

MxqPosition make_position() {
    MxqPosition p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = static_cast<uint32_t>(sizeof(p));
    return p;
}

MxqGameStatus make_status() {
    MxqGameStatus s;
    std::memset(&s, 0, sizeof(s));
    s.struct_size = static_cast<uint32_t>(sizeof(s));
    return s;
}

MxqStatus init_core(const fs::path &store, MxqCore **out_core, MxqError *err) {
    MxqCoreConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.api_major = MXQ_API_VERSION_MAJOR;
    config.api_minor = MXQ_API_VERSION_MINOR;
    config.api_patch = MXQ_API_VERSION_PATCH;
    config.flags = MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY;
    const std::string store_text = store.string();
    const std::string assets_text = combined_assets().string();
    config.store_directory = store_text.c_str();
    config.asset_directory = assets_text.c_str();
    return mxq_core_init(&config, out_core, err);
}

const char *state_text(MxqGameState state) {
    switch (state) {
    case MXQ_GAME_ONGOING:        return "ongoing";
    case MXQ_GAME_CLAIMABLE_DRAW: return "claimable-draw";
    case MXQ_GAME_RED_WINS:       return "first-mover-wins";
    case MXQ_GAME_BLACK_WINS:     return "second-mover-wins";
    case MXQ_GAME_DRAW:           return "draw";
    default:                      return "?";
    }
}

const char *reason_text(MxqEndReason reason) {
    switch (reason) {
    case MXQ_END_REASON_NONE:          return "none";
    case MXQ_END_REASON_FIVE_IN_A_ROW: return "five-in-a-row";
    case MXQ_END_REASON_BOARD_FULL:    return "board-full";
    default:                           return "another game's reason";
    }
}

/* The frozen starting position of both games: an empty 15x15 board, the first
 * mover to play, and nothing in the fields these games do not use. */
const char *start_fen(MxqCore *core, MxqGameKind game, char *buffer,
                      size_t cap) {
    size_t length = 0;
    if (mxq_rules_start_fen(game, buffer, cap, &length, nullptr) != MXQ_OK) {
        buffer[0] = '\0';
    }
    (void)core;
    return buffer;
}

/* Replay a line through the session-free surface and report where it arrived. */
struct Arrived {
    MxqStatus     status = MXQ_OK;
    MxqPosition   position = make_position();
    MxqGameStatus state = make_status();
    size_t        first_illegal = 0;
    MxqError      err = make_error();
};

Arrived evaluate(MxqCore *core, MxqGameKind game,
                 const std::vector<std::string> &moves) {
    char fen[MXQ_FEN_CAP];
    start_fen(core, game, fen, sizeof(fen));

    std::vector<const char *> texts;
    texts.reserve(moves.size());
    for (const std::string &move : moves) {
        texts.push_back(move.c_str());
    }

    Arrived out;
    out.status = mxq_rules_evaluate(
        core, game, fen, texts.empty() ? nullptr : texts.data(), texts.size(),
        &out.position, &out.state, &out.first_illegal, &out.err);
    return out;
}

/* Every legal move at the end of a line, through the two-call buffer
 * protocol — which is also how the count is asked for. */
std::vector<std::string> legal_moves(MxqCore *core, MxqGameKind game,
                                     const std::vector<std::string> &moves,
                                     MxqStatus &out_status) {
    char fen[MXQ_FEN_CAP];
    start_fen(core, game, fen, sizeof(fen));

    std::vector<const char *> texts;
    texts.reserve(moves.size());
    for (const std::string &move : moves) {
        texts.push_back(move.c_str());
    }

    /* Asking for the count is a null buffer of no capacity, and the answer is
     * MXQ_ERR_ARG_BUFFER_TOO_SMALL with the count written — routine, and the
     * documented way to size the buffer. A position with no legal move at all
     * needs no buffer and answers MXQ_OK. */
    size_t count = 0;
    const MxqStatus probe = mxq_rules_legal_moves(
        core, game, fen, texts.empty() ? nullptr : texts.data(), texts.size(),
        nullptr, 0, &count, nullptr);
    std::vector<std::string> out;
    if (probe != MXQ_OK && probe != MXQ_ERR_ARG_BUFFER_TOO_SMALL) {
        out_status = probe;
        return out;
    }
    out_status = MXQ_OK;
    if (count == 0) {
        return out;
    }
    std::vector<MxqMove> buffer(count);
    for (MxqMove &move : buffer) {
        move.struct_size = static_cast<uint32_t>(sizeof(MxqMove));
    }
    size_t written = 0;
    out_status = mxq_rules_legal_moves(core, game, fen, texts.data(),
                                       texts.size(), buffer.data(),
                                       buffer.size(), &written, nullptr);
    if (out_status != MXQ_OK) {
        return out;
    }
    out.reserve(written);
    for (size_t i = 0; i < written; ++i) {
        out.push_back(buffer[i].text);
    }
    return out;
}

bool contains(const std::vector<std::string> &moves, const std::string &move) {
    for (const std::string &candidate : moves) {
        if (candidate == move) {
            return true;
        }
    }
    return false;
}

/* Interleave two sides' stones into one alternating line, the first mover
 * first. The two lists must differ in length by nothing or by one. */
std::vector<std::string> alternating(const std::vector<std::string> &first,
                                     const std::vector<std::string> &second) {
    std::vector<std::string> line;
    line.reserve(first.size() + second.size());
    for (size_t i = 0; i < first.size() || i < second.size(); ++i) {
        if (i < first.size()) {
            line.push_back(first[i]);
        }
        if (i < second.size()) {
            line.push_back(second[i]);
        }
    }
    return line;
}

/* -------------------------------------------------------------------- */
/* Notation                                                             */
/* -------------------------------------------------------------------- */

/*
 * Catches: a move grammar that decides how many squares a move is from the
 * text's length rather than from the game. Both halves of "h8h9" are squares of
 * this board, so a length test accepts it here while rejecting it on the narrow
 * boards where it was written — which is the day a placement game silently plays
 * a movement move.
 */
void case_a_move_is_one_square() {
    Case c("a placement move is one square of this board, and two is not one");
    const fs::path store = scratch_dir("notation");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    char fen[MXQ_FEN_CAP];
    size_t length = 0;
    err = make_error();
    c.check_status(mxq_rules_start_fen(MXQ_GAME_KIND_GOMOKU_15, fen,
                                       sizeof(fen), &length, &err),
                   MXQ_OK, "the starting position is reported");
    c.check_eq(std::string(fen),
               "15/15/15/15/15/15/15/15/15/15/15/15/15/15/15 w - - 0 1",
               "the empty board, the first mover to play");
    err = make_error();
    char renju_fen[MXQ_FEN_CAP];
    mxq_rules_start_fen(MXQ_GAME_KIND_RENJU, renju_fen, sizeof(renju_fen),
                        &length, &err);
    c.check_eq(std::string(renju_fen), std::string(fen),
               "and the same board for the stricter game");

    for (MxqGameKind game :
         {MXQ_GAME_KIND_GOMOKU_15, MXQ_GAME_KIND_RENJU}) {
        const std::string who =
            game == MXQ_GAME_KIND_RENJU ? "renju: " : "gomoku: ";
        const Arrived corner = evaluate(core, game, {"a1"});
        c.check_status(corner.status, MXQ_OK, who + "a1 is a square");
        const Arrived far = evaluate(core, game, {"o15"});
        c.check_status(far.status, MXQ_OK, who + "o15 is the far corner");

        for (const char *malformed : {"h8h9", "p1", "o16", "h0", "h08", "h",
                                      "8h", ""}) {
            const Arrived rejected = evaluate(core, game, {malformed});
            c.check(rejected.status == MXQ_ERR_RULES_INVALID_HISTORY,
                    who + "\"" + malformed + "\" is not a move of this board: " +
                        mxq_status_name(rejected.status));
        }
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * Catches: an encoding that gains a second spelling of one position, or that
 * stops being the game's own. A position with two spellings is two documents
 * disagreeing while meaning the same thing, and the archive compares bytes.
 */
void case_a_position_has_one_spelling() {
    Case c("a position of this board validates, and only in its one spelling");
    const fs::path store = scratch_dir("positions");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    const char *valid =
        "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0 1";
    err = make_error();
    c.check_status(
        mxq_rules_validate_fen(core, MXQ_GAME_KIND_GOMOKU_15, valid, &err),
        MXQ_OK, "a board with one stone on it");

    struct Rejected {
        const char *fen;
        const char *why;
    };
    /* Two empty runs in a row are not among these, and cannot be: digit
     * consumption is greedy, so "1" then "14" is read as one run of 114 and
     * refused for running past the board rather than for being two runs. There
     * is no text that reaches the parser as adjacent runs, so there is no case
     * to write for it. */
    const Rejected rejected[] = {
        {"15/15/15/15/15/15/15/7S7/15/15/15/15/15/15 b - - 0 1",
         "fourteen ranks"},
        {"15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15/15 b - - 0 1",
         "sixteen ranks"},
        {"15/15/15/15/15/15/15/7S8/15/15/15/15/15/15/15 b - - 0 1",
         "a rank of sixteen points"},
        {"15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0 1 1",
         "seven fields"},
        {"15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/015 b - - 0 1",
         "an empty run with a leading zero"},
        {"15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 x - - 0 1",
         "a side to move that is neither"},
        {"15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b K - 0 1",
         "something in a field this game does not use"},
        {"15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 1 1",
         "a halfmove clock in a game with no move-count rule"},
        {"15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0 0",
         "a fullmove number of zero"},
        {"15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0",
         "five fields"},
        {"rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1",
         "another game's board"},
    };
    for (const Rejected &bad : rejected) {
        err = make_error();
        c.check_status(
            mxq_rules_validate_fen(core, MXQ_GAME_KIND_GOMOKU_15, bad.fen, &err),
            MXQ_ERR_RULES_INVALID_FEN, bad.why);
    }

    /* And the other direction, which is what makes the game a question rather
     * than a hint: a placement position is not a position of a movement game. */
    err = make_error();
    c.check_status(
        mxq_rules_validate_fen(core, MXQ_GAME_KIND_XIANGQI, valid, &err),
        MXQ_ERR_RULES_INVALID_FEN, "a placement board is not Xiangqi's");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/* -------------------------------------------------------------------- */
/* Legality and adjudication                                            */
/* -------------------------------------------------------------------- */

/*
 * Catches: a legal-move enumeration bounded by something smaller than the board
 * — 128 was the number every buffer in this project was sized at before these
 * games — and a position writer that loses a stone or miscounts the plies.
 */
void case_placement_legality() {
    Case c("every empty point is a placement, and an occupied one is not");
    const fs::path store = scratch_dir("legality");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqStatus rc = MXQ_OK;
    const std::vector<std::string> opening =
        legal_moves(core, MXQ_GAME_KIND_GOMOKU_15, {}, rc);
    c.check_status(rc, MXQ_OK, "the empty board's legal moves");
    c.check_eq(static_cast<int64_t>(opening.size()), 225,
               "an empty 15x15 board has one placement per point");
    c.check(contains(opening, "a1") && contains(opening, "o15") &&
                contains(opening, "h8"),
            "including both corners and the centre");

    /* One ply, and the position it reaches. */
    const Arrived after = evaluate(core, MXQ_GAME_KIND_GOMOKU_15, {"h8"});
    c.check_status(after.status, MXQ_OK, "the first stone lands");
    c.check_eq(std::string(after.position.fen),
               "15/15/15/15/15/15/15/7S7/15/15/15/15/15/15/15 b - - 0 1",
               "the position writes the stone where it was played");
    c.check_eq(after.position.ply_count, 1, "one ply");
    c.check_eq(after.position.side_to_move, MXQ_COLOR_BLACK,
               "and it is the second mover's turn");
    c.check_eq(after.position.in_check, 0,
               "there is no check in a game with no king");
    c.check_eq(state_text(after.state.state), "ongoing", "the game continues");

    const std::vector<std::string> narrowed =
        legal_moves(core, MXQ_GAME_KIND_GOMOKU_15, {"h8"}, rc);
    c.check_status(rc, MXQ_OK, "and the legal moves after it");
    c.check_eq(static_cast<int64_t>(narrowed.size()), 224,
               "one fewer, the taken point");
    c.check(!contains(narrowed, "h8"), "and the taken point is not among them");

    const Arrived occupied =
        evaluate(core, MXQ_GAME_KIND_GOMOKU_15, {"h8", "h8"});
    c.check_status(occupied.status, MXQ_ERR_RULES_INVALID_HISTORY,
                   "a stone on an occupied point");
    c.check_eq(static_cast<int64_t>(occupied.first_illegal), 1,
               "reported at the ply that played it");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * Catches: the win condition being read from the wrong side's or the wrong
 * rule's table. Five is the whole game, and the reason it ended is what the
 * History record shows.
 */
void case_five_in_a_row_wins() {
    Case c("five in a row ends the game for the side that made it");
    const fs::path store = scratch_dir("five");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    /* The first mover completes d8-e8-f8-g8-h8 while the second plays a rank
     * far away with a gap between every stone, so nothing the second mover has
     * is a threat of its own. */
    const std::vector<std::string> line =
        alternating({"d8", "e8", "f8", "g8", "h8"}, {"a1", "c1", "e1", "g1"});

    for (MxqGameKind game : {MXQ_GAME_KIND_GOMOKU_15, MXQ_GAME_KIND_RENJU}) {
        const std::string who =
            game == MXQ_GAME_KIND_RENJU ? "renju: " : "gomoku: ";
        const Arrived arrived = evaluate(core, game, line);
        c.check_status(arrived.status, MXQ_OK, who + "the line replays");
        c.check_eq(state_text(arrived.state.state), "first-mover-wins",
                   who + "five in a row wins");
        c.check_eq(reason_text(arrived.state.reason), "five-in-a-row",
                   who + "and says so");

        MxqStatus rc = MXQ_OK;
        const std::vector<std::string> after = legal_moves(core, game, line, rc);
        c.check_status(rc, MXQ_OK, who + "the finished position answers");
        c.check_eq(static_cast<int64_t>(after.size()), 0,
                   who + "a finished game offers no move");

        /* And the line cannot be played past its own end. */
        std::vector<std::string> beyond = line;
        beyond.push_back("a15");
        const Arrived refused = evaluate(core, game, beyond);
        c.check_status(refused.status, MXQ_ERR_RULES_INVALID_HISTORY,
                       who + "a ply after the end");
        c.check_eq(static_cast<int64_t>(refused.first_illegal),
                   static_cast<int64_t>(line.size()),
                   who + "reported at the ply that followed it");
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * Catches: the forbidden-point query being asked of the wrong rule, the wrong
 * side, or not at all — and the three preconditions the engine's own query
 * documents (a renju board, an empty cell, Black to move) being met by accident
 * rather than by the adapter. The same shape is asked four ways and only one of
 * them refuses.
 */
void case_a_double_three_is_forbidden_for_black_alone() {
    Case c("a double three is forbidden for Black under Renju, and nowhere else");
    const fs::path store = scratch_dir("double-three");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    /* Playing h8 makes two open threes at once: f8-g8-h8 along the rank and
     * h6-h7-h8 up the file, both with room to become open fours. */
    const std::vector<std::string> first_movers = {"f8", "g8", "h6", "h7"};
    const std::vector<std::string> quiet = {"a1", "c1", "e1", "g1"};

    const std::vector<std::string> black_to_play =
        alternating(first_movers, quiet);
    /* The same shape in the second mover's hands, with one extra quiet stone so
     * that it is that side's turn. */
    const std::vector<std::string> white_to_play =
        alternating({"a1", "c1", "e1", "g1", "i1"}, first_movers);

    std::vector<std::string> black_plays = black_to_play;
    black_plays.push_back("h8");
    std::vector<std::string> white_plays = white_to_play;
    white_plays.push_back("h8");

    /* The one refusal. */
    const Arrived refused = evaluate(core, MXQ_GAME_KIND_RENJU, black_plays);
    c.check_status(refused.status, MXQ_ERR_RULES_INVALID_HISTORY,
                   "Renju: Black's double three");
    c.check_eq(static_cast<int64_t>(refused.first_illegal),
               static_cast<int64_t>(black_to_play.size()),
               "reported at the ply that played it");

    MxqStatus rc = MXQ_OK;
    const std::vector<std::string> offered =
        legal_moves(core, MXQ_GAME_KIND_RENJU, black_to_play, rc);
    c.check_status(rc, MXQ_OK, "Renju: the position offers its moves");
    c.check(!contains(offered, "h8"),
            "Renju: and a forbidden point is not among them");
    c.check(contains(offered, "a15"),
            "Renju: while the rest of the board still is");

    /* The three that do not refuse. */
    const Arrived freestyle =
        evaluate(core, MXQ_GAME_KIND_GOMOKU_15, black_plays);
    c.check_status(freestyle.status, MXQ_OK,
                   "Gomoku: nothing is forbidden to anyone");
    c.check_eq(state_text(freestyle.state.state), "ongoing",
               "Gomoku: and the game continues");

    const Arrived white_under_renju =
        evaluate(core, MXQ_GAME_KIND_RENJU, white_plays);
    c.check_status(white_under_renju.status, MXQ_OK,
                   "Renju: White's double three is White's business");

    const std::vector<std::string> white_offered =
        legal_moves(core, MXQ_GAME_KIND_RENJU, white_to_play, rc);
    c.check_status(rc, MXQ_OK, "Renju: White's position offers its moves");
    c.check(contains(white_offered, "h8"),
            "Renju: including the point Black could not have");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * Catches: a forbidden-point rule widened past what it forbids. Renju forbids
 * the double three and the double four; a four and a three together is the
 * ordinary strongest move in the game, and a rule that refused it would refuse
 * winning play.
 */
void case_a_four_and_a_three_is_legal_for_black() {
    Case c("a four and a three together is legal for Black under Renju");
    const fs::path store = scratch_dir("four-three");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    /* Playing h8 makes e8-f8-g8-h8, a four, and h6-h7-h8, an open three. */
    std::vector<std::string> line = alternating(
        {"e8", "f8", "g8", "h6", "h7"}, {"a1", "c1", "e1", "g1", "i1"});
    line.push_back("h8");

    const Arrived arrived = evaluate(core, MXQ_GAME_KIND_RENJU, line);
    c.check_status(arrived.status, MXQ_OK, "the four-three lands");
    c.check_eq(state_text(arrived.state.state), "ongoing",
               "and does not end the game by itself");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * Catches: the overline rule read from one table for both sides, or for both
 * games. It is the one rule where the same six stones mean three different
 * things, and all three come out of the engine's own per-rule, per-side tables
 * rather than from anything written here.
 */
void case_an_overline_is_black_s_alone_to_fear() {
    Case c("six in a row: forbidden for Renju's Black, and a win for anyone else");
    const fs::path store = scratch_dir("overline");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    /* c8-d8-e8 and g8-h8 with f8 empty: no five stands, and filling f8 makes
     * six. Neither side has five before that, so the game is still running. */
    const std::vector<std::string> shape = {"c8", "d8", "e8", "g8", "h8"};
    const std::vector<std::string> quiet = {"a1", "c1", "e1", "g1", "i1"};

    std::vector<std::string> first_mover_line = alternating(shape, quiet);
    const size_t first_mover_plies = first_mover_line.size();
    first_mover_line.push_back("f8");

    /* Renju: Black's overline is not a five and is forbidden. */
    const Arrived renju_black =
        evaluate(core, MXQ_GAME_KIND_RENJU, first_mover_line);
    c.check_status(renju_black.status, MXQ_ERR_RULES_INVALID_HISTORY,
                   "Renju: Black's overline");
    c.check_eq(static_cast<int64_t>(renju_black.first_illegal),
               static_cast<int64_t>(first_mover_plies),
               "reported at the ply that made it");

    /* Gomoku: six contains five, and five wins. */
    const Arrived freestyle =
        evaluate(core, MXQ_GAME_KIND_GOMOKU_15, first_mover_line);
    c.check_status(freestyle.status, MXQ_OK, "Gomoku: the overline lands");
    c.check_eq(state_text(freestyle.state.state), "first-mover-wins",
               "Gomoku: and wins");
    c.check_eq(reason_text(freestyle.state.reason), "five-in-a-row",
               "Gomoku: as a line of five or more");

    /* Renju: White's overline wins. The same shape one side over, with an extra
     * quiet stone so that it is White's turn. */
    std::vector<std::string> second_mover_line =
        alternating({"a1", "c1", "e1", "g1", "i1", "k1"}, shape);
    second_mover_line.push_back("f8");
    const Arrived renju_white =
        evaluate(core, MXQ_GAME_KIND_RENJU, second_mover_line);
    c.check_status(renju_white.status, MXQ_OK, "Renju: White's overline lands");
    c.check_eq(state_text(renju_white.state.state), "second-mover-wins",
               "Renju: and wins for White");
    c.check_eq(reason_text(renju_white.state.reason), "five-in-a-row",
               "Renju: as a line of five or more");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * Catches: the draw going unnoticed, or being reported as something else. It is
 * the only automatic end these games have besides the win, it is what the
 * campaign replaces Claim Draw with, and it is reachable in no other way — the
 * position has to be the whole board.
 */
void case_a_full_board_with_no_five_is_a_draw() {
    Case c("a full board with no line of five is a draw");
    const fs::path store = scratch_dir("draw");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    /*
     * A colouring of every point with no five of either colour in any direction:
     * the first mover takes the points where (file + 2 * rank) mod 8 is 4 or
     * more. Stepping one file changes the value by 1 and one anti-diagonal step
     * by 7, so those two directions run four at most; stepping one rank changes
     * it by 2 and one diagonal step by 3, so those run two at most. It leaves
     * 113 points to the first mover and 112 to the second, which is exactly how
     * 225 alternating plies divide.
     *
     * Freestyle, and deliberately: under Renju a hand-ordered line of 225 plies
     * would have to avoid every forbidden point on the way, which makes the
     * order carry the rule. The full-board draw is one answer for both games and
     * is reached through the same replay either way.
     */
    std::vector<std::string> first_mover;
    std::vector<std::string> second_mover;
    for (int32_t rank = 0; rank < 15; ++rank) {
        for (int32_t file = 0; file < 15; ++file) {
            const std::string point =
                std::string(1, static_cast<char>('a' + file)) +
                std::to_string(rank + 1);
            if ((file + 2 * rank) % 8 >= 4) {
                first_mover.push_back(point);
            } else {
                second_mover.push_back(point);
            }
        }
    }
    c.check_eq(static_cast<int64_t>(first_mover.size()), 113,
               "the first mover's share of the board");
    c.check_eq(static_cast<int64_t>(second_mover.size()), 112,
               "and the second mover's");

    const std::vector<std::string> line =
        alternating(first_mover, second_mover);
    c.check_eq(static_cast<int64_t>(line.size()), 225, "every point is played");

    /* One ply short, the game is still running. */
    std::vector<std::string> penultimate = line;
    penultimate.pop_back();
    const Arrived nearly =
        evaluate(core, MXQ_GAME_KIND_GOMOKU_15, penultimate);
    c.check_status(nearly.status, MXQ_OK, "224 plies replay");
    c.check_eq(state_text(nearly.state.state), "ongoing",
               "and one empty point is still a game");

    const Arrived full = evaluate(core, MXQ_GAME_KIND_GOMOKU_15, line);
    c.check_status(full.status, MXQ_OK, "the last point is played");
    c.check_eq(state_text(full.state.state), "draw", "a full board is a draw");
    c.check_eq(reason_text(full.state.reason), "board-full",
               "and says which draw");
    c.check_eq(full.position.ply_count, 225, "at the last ply");
    c.check_eq(full.state.claim_available, 0,
               "with nothing to claim: it is automatic");

    /* And the position it wrote, which is the widest string this interface
     * carries and the one every recorded figure about MXQ_FEN_CAP's headroom is
     * measured against. The number is asserted exactly rather than bounded,
     * because a loose bound is what let it be recorded wrong: 239 characters of
     * board field and 12 of suffix — " b - - 0 113", the fullmove number of a
     * 225-ply game running to three digits. mxq.h and core-interface.md both
     * quote it, and this is the position that produces it. */
    const std::string fen(full.position.fen);
    c.check_eq(static_cast<int64_t>(fen.size()), 251,
               "the widest position this interface carries");
    c.check_eq(fen.substr(fen.size() - 12), " b - - 0 113",
               "and the suffix the count includes");
    c.check(fen.size() < MXQ_FEN_CAP,
            "which fits the capacity with room to spare");
    err = make_error();
    c.check_status(
        mxq_rules_validate_fen(core, MXQ_GAME_KIND_GOMOKU_15, fen.c_str(), &err),
        MXQ_OK, "and is a position this game's own encoding accepts");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/* -------------------------------------------------------------------- */
/* Engine dispatch                                                      */
/* -------------------------------------------------------------------- */

/*
 * Catches: preparation reaching the wrong engine, or one engine being left
 * prepared beside the other. The profile identifier is how a saved diagnostic
 * attributes a move to the configuration that produced it, so it naming the
 * wrong engine's fork revision or the wrong rule's network would misattribute
 * every move of these games.
 */
void case_preparation_reaches_the_engine_the_game_is_played_on() {
    Case c("each game prepares its own engine, through the public surface");
    const fs::path store = scratch_dir("dispatch");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqEngineBudget budget;
    std::memset(&budget, 0, sizeof(budget));
    budget.struct_size = static_cast<uint32_t>(sizeof(budget));
    budget.active_processor_count = 2;
    budget.available_bytes = 4ull * 1024 * 1024 * 1024;
    budget.physical_bytes = 16ull * 1024 * 1024 * 1024;

    const auto prepared_profile = [&](MxqGameKind game,
                                      const std::string &who) {
        MxqEnginePlan plan;
        std::memset(&plan, 0, sizeof(plan));
        plan.struct_size = static_cast<uint32_t>(sizeof(plan));
        MxqError local = make_error();
        c.check_status(mxq_engine_prepare(core, game, &budget, &plan, &local),
                       MXQ_OK, who + " prepares (" + local.detail + ")");

        MxqEngineState state = MXQ_ENGINE_STATE_UNINITIALIZED;
        char profile[MXQ_PROFILE_ID_CAP];
        size_t length = 0;
        local = make_error();
        c.check_status(mxq_engine_query(core, &state, profile, sizeof(profile),
                                        &length, &local),
                       MXQ_OK, who + " reports its engine");
        c.check_eq(state, MXQ_ENGINE_STATE_READY, who + " is ready");
        return std::string(profile);
    };

    const std::string gomoku =
        prepared_profile(MXQ_GAME_KIND_GOMOKU_15, "Gomoku");
    c.check(gomoku.find("freestyle15") != std::string::npos,
            "Gomoku's profile names the rule its engine was configured for: " +
                gomoku);

    const std::string renju = prepared_profile(MXQ_GAME_KIND_RENJU, "Renju");
    c.check(renju.find("renju15") != std::string::npos,
            "Renju's profile names its own rule: " + renju);
    c.check(gomoku != renju,
            "and the two games are not attributed to one configuration");

    /* The profile also carries the game's own engine revision, so the two
     * placement games agree on it and the movement games do not. */
    const std::string movement =
        prepared_profile(MXQ_GAME_KIND_MINI_XIANGQI, "Mini Xiangqi");
    c.check(movement.find("freestyle15") == std::string::npos &&
                movement.find("renju15") == std::string::npos,
            "a movement game is not attributed to the placement engine: " +
                movement);

    /* And back again, which is the switch that must release one engine before
     * it configures the other. */
    const std::string again = prepared_profile(MXQ_GAME_KIND_RENJU, "Renju");
    c.check_eq(again, renju, "preparing back reports the same configuration");

    err = make_error();
    c.check_status(mxq_engine_teardown(core, &err), MXQ_OK,
                   "every engine is released together");
    MxqEngineState state = MXQ_ENGINE_STATE_READY;
    char profile[MXQ_PROFILE_ID_CAP];
    size_t length = 0;
    err = make_error();
    mxq_engine_query(core, &state, profile, sizeof(profile), &length, &err);
    c.check_eq(state, MXQ_ENGINE_STATE_UNINITIALIZED,
               "and the engine reports uninitialised");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * Catches: the persistence fence being crossed by accident. The archive format
 * has no rules_id for these games yet, and the writer asserts on one it cannot
 * name — so a session created for one would reach that assertion with a null
 * string behind it. This pins the refusal until the format widens, and it is the
 * case the stage that widens the format has to change.
 */
void case_persistence_still_refuses_these_games() {
    Case c("no session exists for a game this build's format cannot record");
    const fs::path store = scratch_dir("fence");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqGameConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.mode = MXQ_PLAY_MODE_FREE_PLAY;
    config.human_side = MXQ_COLOR_NONE;
    config.ai_level = MXQ_AI_LEVEL_NONE;
    config.first_mover_choice = MXQ_FIRST_MOVER_NONE;
    config.local_side = MXQ_COLOR_NONE;

    /* The second door into creation, which shares the guard. It is asked with a
     * configuration and a wire session it would otherwise accept — nearby mode,
     * a local side, and a session that has retracted, claimed and declared
     * nothing — so that what refuses is the fence and not one of the checks
     * mxq_game_create_nearby makes before it reaches the shared body. */
    MxqGameConfig nearby_config = config;
    nearby_config.mode = MXQ_PLAY_MODE_NEARBY;
    nearby_config.local_side = MXQ_COLOR_RED;

    MxqNearbySession birth;
    std::memset(&birth, 0, sizeof(birth));
    birth.struct_size = static_cast<uint32_t>(sizeof(birth));
    birth.proposer = MXQ_NEARBY_PROPOSER_LOCAL;
    std::snprintf(birth.session_id, sizeof(birth.session_id),
                  "019b76da-a800-7000-8000-000000000000");
    std::snprintf(birth.peer_id, sizeof(birth.peer_id),
                  "wifi-aware-device-77E1B0C2");

    for (MxqGameKind game : {MXQ_GAME_KIND_GOMOKU_15, MXQ_GAME_KIND_RENJU}) {
        config.game = game;
        nearby_config.game = game;

        MxqGame *refused = nullptr;
        err = make_error();
        c.check_status(mxq_game_create(core, &config, &refused, &err),
                       MXQ_ERR_ARG_RANGE,
                       "a session for a game the format has no rules_id for");
        c.check(refused == nullptr, "and no handle is issued");

        MxqGame *refused_nearby = nullptr;
        err = make_error();
        c.check_status(
            mxq_game_create_nearby(core, &nearby_config, &birth,
                                   &refused_nearby, &err),
            MXQ_ERR_ARG_RANGE,
            "a nearby session for one, through the other door");
        c.check(refused_nearby == nullptr, "and no handle there either");
    }

    uint8_t exists = 1;
    err = make_error();
    c.check_status(mxq_store_active_exists(core, &exists, &err), MXQ_OK,
                   "the library still answers");
    c.check_eq(exists, 0, "and holds nothing");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

#endif /* MXQ_TEST_GOMOKU_FACADE */

} /* namespace */

int main() {
    std::cout << "Placement games: notation, rules and dispatch\n";

#if MXQ_TEST_GOMOKU_FACADE
    std::cout << "  assets          " << combined_assets().string() << "\n\n";

    case_a_move_is_one_square();
    case_a_position_has_one_spelling();
    case_placement_legality();
    case_five_in_a_row_wins();
    case_a_double_three_is_forbidden_for_black_alone();
    case_a_four_and_a_three_is_legal_for_black();
    case_an_overline_is_black_s_alone_to_fear();
    case_a_full_board_with_no_five_is_a_draw();
    case_preparation_reaches_the_engine_the_game_is_played_on();
    case_persistence_still_refuses_these_games();

    std::error_code cleanup;
    fs::remove_all(scratch_root(), cleanup);
#else
    std::cout << "\n";
    Case skipped("the placement games");
    skipped.skip("this build does not carry them: they need the second engine");
    skipped.report();
#endif

    const int total = g_passed + g_failed + g_skipped;
    std::cout << "\n"
              << total << " cases: " << g_passed << " passed, " << g_failed
              << " failed, " << g_skipped << " skipped\n"
              << g_checks << " expectations evaluated\n";
    if (g_skipped > 0) {
        std::cout << "\nNOT IMPLEMENTED: the placement games need the second "
                     "engine. Build with -DMXQ_ENABLE_GOMOKU_FACADE=ON to "
                     "evaluate them.\n";
    }
    return g_failed > 0 ? 1 : 0;
}
