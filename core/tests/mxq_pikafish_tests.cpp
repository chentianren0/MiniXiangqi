/*
 * The jieqi engine's smoke runner: two Stockfish-family engines in one process,
 * each answering for its own game.
 *
 * This is the isolation proof for the vendored Pikafish rules slice, and it is
 * the only thing that references that slice at this stage — no bridge exists
 * yet and no game reaches it through the C surface. What it exists to catch is
 * a failure that is silent everywhere else: Fairy-Stockfish and Pikafish are
 * both Stockfish derivatives, both declare the namespace `Stockfish`, and both
 * define Position::init, Bitboards::init and their neighbours as strong symbols
 * with identical signatures. Two static archives holding the same strong symbol
 * link without complaint, and the linker's choice of body is decided by link
 * order. The vendored slice is therefore compiled with the whole namespace
 * renamed to PikafishJieqi, and this runner is what says the rename holds:
 * both engines' tables are initialised here, in this order, in one process, and
 * each is then asked a question only it can answer correctly.
 *
 * Fairy-Stockfish is asked through the public C surface rather than through its
 * headers, and not only for tidiness. The two engines' headers have the same
 * file names — position.h, movegen.h, bitboard.h, types.h — so a translation
 * unit with both engines' include directories on its path would resolve those
 * spellings by search order. Driving the first engine through mxq.h removes the
 * question: what this file includes from an engine, it includes from exactly
 * one.
 *
 * Every use of the vendored slice below is spelled PikafishJieqi:: rather than
 * Stockfish::. Both compile — the rename is a preprocessor define and the
 * headers themselves say Stockfish — and the renamed spelling is the one that
 * makes each call site say out loud which engine it reaches, which is this
 * file's subject.
 *
 * The expectations are the ones the feasibility probe established and no more.
 * This is not a jieqi rules corpus: the vendored engine is the rules authority
 * for that game and it is unmodified and revision-pinned, so there is no second
 * reading to hold it against. Every case below is one wiring claim.
 *
 * Without MXQ_ENABLE_RULES_FACADE neither engine is in the build and every case
 * reports NOT IMPLEMENTED.
 */

#include "mxq.h"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <random>
#include <string>
#include <vector>

#if MXQ_TEST_RULES_FACADE
    #include <deque>
    #include <memory>

    #include "bitboard.h"
    #include "movegen.h"
    #include "position.h"
#endif

namespace fs = std::filesystem;

namespace {

int g_passed  = 0;
int g_failed  = 0;
int g_skipped = 0;
int g_checks  = 0;

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

#if MXQ_TEST_RULES_FACADE

/*
 * Jieqi's starting position, in the vendored engine's own FEN dialect. `x` and
 * `X` are face-down pieces, and the field after the side to move is the pool of
 * pieces still to be revealed. The engine's coordinates are a0-i9 with rank 0
 * as Red's back rank, which is why the advisor below stands on d0 and steps to
 * e1.
 */
const char *const kJieqiStartFen =
    "xxxxkxxxx/9/1x5x1/x1x1x1x1x/9/9/X1X1X1X1X/1X5X1/9/XXXXKXXXX w "
    "R2A2C2P5N2B2r2a2c2p5n2b2 0 1";

std::string square_name(PikafishJieqi::Square s) {
    return std::string{char('a' + PikafishJieqi::file_of(s)),
                       char('0' + PikafishJieqi::rank_of(s))};
}

std::string move_name(PikafishJieqi::Move m) {
    return square_name(m.from_sq()) + square_name(m.to_sq());
}

/* A fresh scratch directory, so this runner leans on no other's state. */
fs::path scratch_root() {
    static const fs::path root = [] {
        std::random_device rd;
        char               buffer[17];
        std::snprintf(buffer, sizeof(buffer), "%08x%08x", rd(), rd());
        return fs::temp_directory_path() /
               ("minixiangqi-pikafish-tests-" + std::string(buffer));
    }();
    return root;
}

MxqError make_error() {
    MxqError err;
    std::memset(&err, 0, sizeof(err));
    err.struct_size = static_cast<uint32_t>(sizeof(err));
    return err;
}

MxqStatus init_core(MxqCore **out_core, MxqError *err) {
    const fs::path store = scratch_root() / "store";
    std::error_code ec;
    fs::create_directories(store, ec);

    MxqCoreConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.api_major   = MXQ_API_VERSION_MAJOR;
    config.api_minor   = MXQ_API_VERSION_MINOR;
    config.api_patch   = MXQ_API_VERSION_PATCH;
    config.flags       = MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY;
    const std::string store_text  = store.string();
    const std::string assets_text = MXQ_ASSETS_DIR_DEFAULT;
    config.store_directory        = store_text.c_str();
    config.asset_directory        = assets_text.c_str();
    return mxq_core_init(&config, out_core, err);
}

/*
 * Both engines are brought up here, before any case runs, and the order is the
 * order the failure this file exists to catch would need: Fairy-Stockfish first,
 * through mxq_core_init, then the jieqi slice's own two-call bootstrap. If the
 * rename ever stopped holding, the second Bitboards::init would be the first's
 * body and would overwrite — or fail to fill — the tables the other engine is
 * already using, and both halves of the suite would be answering from one set
 * of tables.
 */
MxqCore *g_core = nullptr;

bool bring_up_both_engines() {
    MxqError err = make_error();
    if (init_core(&g_core, &err) != MXQ_OK) {
        std::cout << "  the Fairy-Stockfish-backed core did not initialise: "
                  << err.detail << "\n";
        return false;
    }
    PikafishJieqi::Bitboards::init();
    PikafishJieqi::Position::init();
    return true;
}

void case_the_first_engine_still_answers_for_its_own_game() {
    Case c("the Fairy-Stockfish-backed core answers for Mini Xiangqi");

    char        fen[MXQ_FEN_CAP];
    std::size_t fen_len = 0;
    MxqError    err     = make_error();
    c.check_status(mxq_rules_start_fen(MXQ_GAME_KIND_MINI_XIANGQI, fen,
                                       sizeof(fen), &fen_len, &err),
                   MXQ_OK, "Mini Xiangqi's frozen start is available");
    c.check_eq(std::string(fen), "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1",
               "the frozen start is the one docs/xiangqi-rules.md fixes");

    /*
     * The count is the engine's answer rather than a constant of the surface:
     * the fixture mx-move-001 pins this position's complete legal set at
     * nineteen moves, and reaching that number requires Fairy-Stockfish's own
     * attack tables to be the ones consulted.
     */
    std::vector<MxqMove> moves(64);
    for (MxqMove &move : moves) {
        move.struct_size = static_cast<uint32_t>(sizeof(MxqMove));
    }
    std::size_t count = 0;
    err               = make_error();
    c.check_status(mxq_rules_legal_moves(g_core, MXQ_GAME_KIND_MINI_XIANGQI, fen,
                                         nullptr, 0, moves.data(), moves.size(),
                                         &count, &err),
                   MXQ_OK, "the rules facade answers (" + std::string(err.detail) + ")");
    c.check_eq(static_cast<int64_t>(count), 19,
               "Mini Xiangqi's starting position has nineteen legal moves");

    c.report();
}

void case_the_jieqi_slice_reads_its_own_start_position() {
    Case c("the vendored jieqi slice round-trips its starting FEN");

    auto                 states = std::make_unique<std::deque<PikafishJieqi::StateInfo>>(1);
    PikafishJieqi::Position pos;
    pos.set(kJieqiStartFen, &states->back());

    c.check_eq(pos.fen(), std::string(kJieqiStartFen),
               "the starting FEN survives a parse and a re-emit byte for byte");

    c.report();
}

void case_the_jieqi_slice_generates_the_starting_move_set() {
    Case c("the vendored jieqi slice generates forty-four legal moves");

    auto                 states = std::make_unique<std::deque<PikafishJieqi::StateInfo>>(1);
    PikafishJieqi::Position pos;
    pos.set(kJieqiStartFen, &states->back());

    int count = 0;
    for (const auto &m : PikafishJieqi::MoveList<PikafishJieqi::LEGAL>(pos)) {
        (void) m;
        ++count;
    }
    c.check_eq(static_cast<int64_t>(count), 44,
               "the starting position has forty-four legal moves");

    c.report();
}

void case_a_face_down_piece_moves_as_the_piece_that_starts_there() {
    Case c("a face-down advisor on d0 has exactly one move, d0e1");

    /*
     * The rule this pins is the one that makes jieqi a different game rather
     * than xiangqi with a fog: a face-down piece moves as the piece that STARTS
     * on its square, whatever it will turn out to be. d0 is an advisor's square,
     * and an advisor in the starting array reaches the palace centre and
     * nowhere else. Nothing about this answer is available from a generic
     * xiangqi engine reading this position, which is what makes it the sharp
     * end of the isolation proof.
     */
    auto                 states = std::make_unique<std::deque<PikafishJieqi::StateInfo>>(1);
    PikafishJieqi::Position pos;
    pos.set(kJieqiStartFen, &states->back());

    std::vector<std::string> from_d0;
    for (const auto &m : PikafishJieqi::MoveList<PikafishJieqi::LEGAL>(pos)) {
        if (m.from_sq() == PikafishJieqi::SQ_D0) {
            from_d0.push_back(move_name(m));
        }
    }

    c.check_eq(static_cast<int64_t>(from_d0.size()), 1,
               "d0 offers one move");
    if (from_d0.size() == 1) {
        c.check_eq(from_d0.front(), "d0e1", "and it is the step to the palace centre");
    }

    c.report();
}

#endif /* MXQ_TEST_RULES_FACADE */

} /* namespace */

int main() {
    std::cout << "Jieqi engine: two Stockfish-family engines in one process\n";

#if MXQ_TEST_RULES_FACADE
    std::cout << "  assets          " << MXQ_ASSETS_DIR_DEFAULT << "\n\n";

    if (!bring_up_both_engines()) {
        std::cout << "\nFAILED to bring both engines up; nothing below can be "
                     "asked.\n";
        return 1;
    }

    case_the_first_engine_still_answers_for_its_own_game();
    case_the_jieqi_slice_reads_its_own_start_position();
    case_the_jieqi_slice_generates_the_starting_move_set();
    case_a_face_down_piece_moves_as_the_piece_that_starts_there();

    mxq_core_shutdown(g_core, nullptr);
    g_core = nullptr;

    std::error_code cleanup;
    fs::remove_all(scratch_root(), cleanup);
#else
    std::cout << "\n";
    Case skipped("the jieqi engine");
    skipped.skip("this build carries neither engine");
    skipped.report();
#endif

    const int total = g_passed + g_failed + g_skipped;
    std::cout << "\n"
              << total << " cases: " << g_passed << " passed, " << g_failed
              << " failed, " << g_skipped << " skipped\n"
              << g_checks << " expectations evaluated\n";
    if (g_skipped > 0) {
        std::cout << "\nNOT IMPLEMENTED: the jieqi slice is compiled with the "
                     "first engine. Build with -DMXQ_ENABLE_RULES_FACADE=ON to "
                     "evaluate these.\n";
    }
    return g_failed > 0 ? 1 : 0;
}
