/*
 * The jieqi engine's smoke runner: two Stockfish-family engines in one process,
 * each answering for its own game, and the game axis the core carries over the
 * second one.
 *
 * This is the isolation proof for the vendored Pikafish rules slice. What it
 * exists to catch is a failure that is silent everywhere else: Fairy-Stockfish
 * and Pikafish are
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
 * This is not a jieqi rules corpus. That is the `jq-` fixtures' job, and they
 * are the authority the bridge is held to; what the cases below claim is
 * wiring — that each engine answers from its own tables, and that the game axis
 * over the second one answers what docs/core-interface.md says it does. The
 * axis half is here rather than beside the games it refuses because every one
 * of those refusals is about this engine: nothing searches it, and the archive
 * version that stores it is not this build's.
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
    #include "uci.h"
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

    /* The one link-closure stub that is live code rather than a no-op: a wrong
     * body would print wrong squares, so it is executed here rather than only
     * linked. */
    c.check_eq(PikafishJieqi::UCIEngine::square(PikafishJieqi::SQ_D0), "d0",
               "the live stub prints the square it is given");

    c.report();
}

/*
 * The dealt start jq-set-001 states, in the record form the contract freezes:
 * every face-down piece is its identity letter followed by `~`, and no
 * permutation is the identity one — a1 holds a soldier and d1 a chariot.
 */
const char *const kDealtStart =
    "p~c~p~n~kb~r~a~p~/9/1n~5r~1/a~1b~1c~1p~1p~/9/9/"
    "B~1A~1C~1P~1P~/1R~5N~1/9/P~N~P~R~KC~P~A~B~ w - - 0 1";

void case_the_core_answers_for_jieqi_through_the_c_surface() {
    Case c("the rules facade answers for jieqi through mxq.h");

    /*
     * The same question the first engine's case asks, asked of the other one:
     * the count is the bridge's answer rather than a constant of the surface,
     * and reaching it needs the vendored slice's own tables. It also proves the
     * link shape — mxq_core holds the bridge behind $<LINK_ONLY:>, so a caller
     * that reaches this answer through mxq.h alone has the archive without the
     * engine's headers or its renamed namespace anywhere near it.
     */
    std::vector<MxqMove> moves(64);
    for (MxqMove &move : moves) {
        move.struct_size = static_cast<uint32_t>(sizeof(MxqMove));
    }
    std::size_t count = 0;
    MxqError    err = make_error();
    c.check_status(mxq_rules_legal_moves(g_core, MXQ_GAME_KIND_JIEQI,
                                         kDealtStart, nullptr, 0, moves.data(),
                                         moves.size(), &count, &err),
                   MXQ_OK,
                   "the rules facade answers (" + std::string(err.detail) + ")");
    c.check_eq(static_cast<int64_t>(count), 44,
               "a dealt start has forty-four legal moves");

    MxqSetupViolation violation;
    std::memset(&violation, 0, sizeof(violation));
    violation.struct_size = static_cast<uint32_t>(sizeof(violation));
    err = make_error();
    c.check_status(mxq_rules_validate_setup(g_core, MXQ_GAME_KIND_JIEQI,
                                            kDealtStart, &violation, &err),
                   MXQ_OK, "a dealt start is a position to set up in");

    c.report();
}

/*
 * The regression pin for the engine's raised move capacity.
 *
 * MoveList holds ExtMove[MAX_MOVES], and MAX_MOVES was 128 — above Xiangqi's
 * derived maximum of 119 and below Jieqi's of 175. The gap is not a margin: a
 * position offering more legal moves than the bound wrote past the array's own
 * storage, inside a frame this core creates, on a call mxq.h invites, from a
 * record the core's own structural reading accepts. The fork raised the bound to
 * 256 at the pinned revision; this is what says so from the outside.
 *
 * The position below is ordinary play rather than a construction the game
 * cannot reach. Red was dealt soldiers onto its two chariot and its two cannon
 * home squares and has never moved them, so they stand face down and move as
 * the chariots and cannons whose squares they are; Red's real chariots and
 * cannons were dealt elsewhere, were revealed by their first moves, and now
 * stand in the open; Black is down to a bare general. That is exactly the trade
 * the derivation in docs/core-interface.md describes — a hidden piece is worth
 * its square, and four soldiers hidden on the two chariot and two cannon squares
 * is where the trade stops paying.
 *
 * Both bounds are the contract's rather than a measurement's. Strictly above 128
 * is what makes this a position the old capacity could not hold, and at most 175
 * is that document's derived maximum for this game, which no position may
 * exceed. The buffer is the shared figure of 512, for the same reason every
 * other caller that wants one array uses it.
 */
void case_a_position_past_the_old_move_capacity() {
    Case c("a legal position offers more moves than the old MAX_MOVES held");

    const char *const kHighMobility =
        "3k5/9/3C5/6R2/5C3/2R6/9/1P~5P~1/4K4/P~7P~ w - - 0 1";

    MxqError err = make_error();
    c.check_status(mxq_rules_validate_fen(g_core, MXQ_GAME_KIND_JIEQI,
                                          kHighMobility, &err),
                   MXQ_OK, "the position is one this core accepts");

    std::vector<MxqMove> moves(512);
    for (MxqMove &move : moves) {
        move.struct_size = static_cast<uint32_t>(sizeof(MxqMove));
    }
    std::size_t count = 0;
    err = make_error();
    c.check_status(mxq_rules_legal_moves(g_core, MXQ_GAME_KIND_JIEQI,
                                         kHighMobility, nullptr, 0, moves.data(),
                                         moves.size(), &count, &err),
                   MXQ_OK,
                   "the facade answers (" + std::string(err.detail) + ")");
    c.check(count > 128,
            "the position offers more than the old capacity of 128 moves (got " +
                std::to_string(count) + ")");
    c.check(count <= 175,
            "and no more than this game's derived maximum of 175 (got " +
                std::to_string(count) + ")");

    c.report();
}

void case_the_game_axis_refuses_what_this_game_has_none_of() {
    Case c("jieqi is prepared for nothing and searched never, session or not");

    /*
     * Four refusals, and they are one rule read four ways: this game's rules
     * authority performs no search and carries no network, so there is nothing
     * to prepare, nothing to name it by, and no variant and network for a
     * profile to report; and it has no frozen start to report, beginning from a
     * dealt start and from no other position. Three of the four are programming
     * errors and assert, so they are stated where the assertion is compiled out.
     *
     * The fourth is not, and it is the one this stage made reachable: a session
     * of this game exists now, so the search facade's refusal can be asked of a
     * real one rather than inferred from the absence of one. It is ordinary
     * control flow — the engine is not ready for this game and never will be —
     * so it is the one evaluated in both configurations.
     */
    MxqGameConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.game = MXQ_GAME_KIND_JIEQI;
    config.mode = MXQ_PLAY_MODE_FREE_PLAY;
    config.human_side = MXQ_COLOR_NONE;
    config.ai_level = MXQ_AI_LEVEL_NONE;
    config.first_mover_choice = MXQ_FIRST_MOVER_NONE;
    config.local_side = MXQ_COLOR_NONE;
    std::memcpy(config.start_fen, kDealtStart, std::strlen(kDealtStart) + 1);

    MxqGame  *game = nullptr;
    MxqError  err = make_error();
    c.check_status(mxq_game_create(g_core, &config, &game, &err), MXQ_OK,
                   "a session of this game is created from its dealt start");
    if (game != nullptr) {
        MxqGameStatus status;
        std::memset(&status, 0, sizeof(status));
        status.struct_size = static_cast<uint32_t>(sizeof(status));
        err = make_error();
        c.check_status(mxq_game_status(game, &status, &err), MXQ_OK,
                       "and answers for its status");
        c.check(status.search_expected == 0, "which never owes a search");

        /* A hint is the one search entry a Free Play session may ask for, and
         * this game's answer to it is the engine axis's permanent one rather
         * than a state some preparation would clear. */
        uint64_t ticket = 0;
        err = make_error();
        c.check_status(mxq_search_start_hint(g_core, game, MXQ_MOVETIME_FAST_MS,
                                             nullptr, nullptr, &ticket, &err),
                       MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "and no engine is ready to hint at it");

        /* Filed rather than released: the library holds one active game, and
         * leaving one behind would be a state no later case asked for. */
        mxq_store_archive_and_clear(g_core, game, nullptr, nullptr);
        mxq_game_release(game);
    }

#if defined(NDEBUG)
    /* The three programming errors, observable only where the assertion that
     * stands guard over them is compiled out. */
    char        fen[MXQ_FEN_CAP];
    std::size_t fen_len = 0;
    err = make_error();
    c.check_status(mxq_rules_start_fen(MXQ_GAME_KIND_JIEQI, fen, sizeof(fen),
                                       &fen_len, &err),
                   MXQ_ERR_ARG_RANGE, "there is no frozen start to report");

    MxqGameProfile profile;
    std::memset(&profile, 0, sizeof(profile));
    profile.struct_size = static_cast<uint32_t>(sizeof(profile));
    err = make_error();
    c.check_status(mxq_core_game_profile(MXQ_GAME_KIND_JIEQI, &profile, &err),
                   MXQ_ERR_ARG_RANGE, "it binds no variant and no network");

    char        profile_id[MXQ_PROFILE_ID_CAP];
    std::size_t profile_len = 0;
    err = make_error();
    c.check_status(mxq_engine_profile_id(MXQ_GAME_KIND_JIEQI, profile_id,
                                         sizeof(profile_id), &profile_len, &err),
                   MXQ_ERR_ARG_RANGE, "and no profile identifier names it");

    MxqEngineBudget budget;
    std::memset(&budget, 0, sizeof(budget));
    budget.struct_size = static_cast<uint32_t>(sizeof(budget));
    budget.physical_bytes = 8ull * 1024ull * 1024ull * 1024ull;
    budget.available_bytes = 4ull * 1024ull * 1024ull * 1024ull;
    budget.active_processor_count = 4;
    MxqEnginePlan applied;
    std::memset(&applied, 0, sizeof(applied));
    applied.struct_size = static_cast<uint32_t>(sizeof(applied));
    err = make_error();
    c.check_status(mxq_engine_prepare(g_core, MXQ_GAME_KIND_JIEQI, &budget,
                                      &applied, &err),
                   MXQ_ERR_ARG_RANGE, "and there is nothing to prepare");
#endif

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
    case_the_core_answers_for_jieqi_through_the_c_surface();
    case_a_position_past_the_old_move_capacity();
    case_the_game_axis_refuses_what_this_game_has_none_of();

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
