/*
 * The search-facade runner: mxq_engine_prepare/teardown/query, the
 * mxq_search_ group, and mxq_core_cancel_all, held to the deterministic,
 * Mac-testable subset of docs/testing.md's engine-integration section.
 *
 * Everything observable through the public C surface is asserted through it.
 * Two things are reached past it on purpose, and nothing else is:
 *
 *   - the engine's own globals — Options, the thread pool, the transposition
 *     table, and the effective NNUE state — because "the applied Threads
 *     value", "the transposition table is released whole", and "the engine's
 *     effective NNUE state is on after configuration, not merely that the
 *     network file exists" are claims about the engine, and trusting the
 *     facade to report on itself would test the report rather than the state;
 *   - staged asset directories under the system temporary path, because the
 *     missing, wrong-basename, and corrupt network refusals are properties of
 *     bytes on disk and are provoked with exactly the bytes they describe.
 *
 * The wrong-basename case is the one the NNUE policy exists for: the network
 * bytes are the pinned ones — every byte-level preflight passes — but the
 * basename names the PARENT variant rather than the custom one, the engine
 * clears its internal NNUE flag silently while the Use NNUE option still reads
 * true, and only the effective-state preflight stands between that and an
 * opponent silently playing on classical evaluation. The mistake is a live one
 * even now that the network is committed under its bundled name: minixiangqi
 * and minixiangqiaxf differ by three characters, and only one of them is the
 * variant this app plays. It is asserted for both variants, because a preflight
 * wired to the app's variant alone would pass everything here and still let a
 * search of the other one run on classical evaluation.
 *
 * The variant axis is the third thing reached past the public surface, and the
 * reason is the same shape as the other two: the bridge is configured for one
 * of two variants, the C surface above it creates games of one of them, and a
 * capability nothing above can request is asserted where it is offered or
 * nowhere at all. Those cases call the bridge on the test thread with no search
 * outstanding, which is the exclusion configure() documents; they never mix
 * that with the facade's own engine calls, whose state they would not update.
 *
 * With the engine in the build, a missing or mismatched staged network FAILS
 * this suite with the configure-time message rather than skipping: a suite
 * that silently skipped its engine would report green on exactly the
 * regression it exists to catch. Without MXQ_ENABLE_RULES_FACADE the search
 * facade is not in the library at all and every case reports NOT IMPLEMENTED,
 * exactly as the session runner degrades.
 *
 * Movetimes are chosen for the suite's wall clock: completing searches think
 * for tenths of a second — any positive movetime is a valid frozen value —
 * and the multi-second movetimes appear only in cases that never let them
 * finish: cancellation, staleness, reconfiguration refusal, shutdown.
 */

#include "mxq.h"

#if MXQ_TEST_RULES_FACADE
/* The engine's own globals, deliberately: see the header comment. */
#include "evaluate.h"
#include "thread.h"
#include "tt.h"
#include "uci.h"
#include "variant.h"

/* The bridge itself, deliberately: see the header comment. */
#include "mxq_engine_bridge.hpp"
/* And the core's one notation authority, so that "this move is in that game's
 * notation" is asked where the grammar is decided rather than spelled again
 * here as a character range. */
#include "mxq_notation.hpp"
/* And the core's own SHA-256, so that "this game's profile names this game's
 * network" is checked against the staged bytes rather than against a second
 * copy of the hash written here. */
#include "mxq_sha256.hpp"
#endif

#if MXQ_TEST_GOMOKU_FACADE
/* The second engine's bridge, for the one case that asserts each engine is
 * released when the other is prepared: see the header comment. */
#include "mxq_rapfi_bridge.hpp"
#endif

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <thread>
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
            std::cout << "  SKIP      " << name << "  (" << skip_reason
                      << ")\n";
            return;
        }
        ++g_passed;
        std::cout << "  ok        " << name << "\n";
    }
};

#if MXQ_TEST_RULES_FACADE

/* The staged asset directory: the variant configuration plus the network
 * under its bundled name, placed by the build after verifying the bytes. This
 * is the shipped shape — one network, for the variant the app plays. */
std::string staged_assets() {
    if (const char *env = std::getenv("MXQ_TEST_ASSETS_DIR")) {
        return env;
    }
    return MXQ_TEST_ASSETS_DIR;
}

/* The same, plus the built-in variant's network: the shape a two-variant
 * configuration is handed, kept apart so that exercising the second variant
 * cannot change what the cases above see. */
std::string staged_xiangqi_assets() {
    if (const char *env = std::getenv("MXQ_TEST_XIANGQI_ASSETS_DIR")) {
        return env;
    }
    return MXQ_TEST_XIANGQI_ASSETS_DIR;
}

/* All of it from pinned-inputs.json through the build, rather than spelled
 * again here: replacing a network is then the bytes and the manifest and
 * nothing else. */
constexpr const char *kBundledNetworkName = MXQ_TEST_NNUE_FILENAME;
constexpr const char *kVariantId = MXQ_TEST_VARIANT_ID;
constexpr const char *kBaseVariantId = MXQ_TEST_BASE_VARIANT_ID;
constexpr const char *kXiangqiNetworkName = MXQ_TEST_XIANGQI_NNUE_FILENAME;
constexpr const char *kXiangqiVariantId = MXQ_TEST_XIANGQI_VARIANT_ID;
constexpr int64_t kBundledNetworkBytes = MXQ_TEST_NNUE_BYTE_LENGTH;
constexpr int64_t kXiangqiNetworkBytes = MXQ_TEST_XIANGQI_NNUE_BYTE_LENGTH;
constexpr const char *kVariantIniName = "minixiangqi-variants.ini";

/* The same bytes under a basename naming the variant this one derives FROM:
 * the bundled name with `minixiangqiaxf` replaced by `minixiangqi`. It is the
 * plausible mistake — the two identifiers differ by three characters and only
 * one of them is the variant the engine is configured for — and the engine
 * refuses it in silence. */
std::string wrong_prefix_network_name() {
    return std::string(kBaseVariantId) +
           std::string(kBundledNetworkName).substr(std::strlen(kVariantId));
}

/* A fresh scratch directory per case, so no case can lean on another. */
fs::path scratch_root() {
    static const fs::path root = [] {
        std::random_device rd;
        char buffer[17];
        std::snprintf(buffer, sizeof(buffer), "%08x%08x", rd(), rd());
        return fs::temp_directory_path() /
               ("minixiangqi-search-tests-" + std::string(buffer));
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
 * One scratch directory holding what more than one engine needs at once, which
 * is the shape a distribution actually ships: the core takes one asset
 * directory, and a build that carries two engines stages both into it.
 *
 * The movement staging is the parameter because the two cases below want
 * different ones of it — the shipped one-network shape, or that plus the
 * built-in variant's network — and which a case takes is part of what that case
 * is about. An empty source is skipped rather than failing, so a build without
 * the second engine stages exactly what it has.
 */
fs::path stage_every_engines_assets(const char *name,
                                    const std::string &movement) {
    const fs::path assets = scratch_dir(name);
    std::error_code ec;
    for (const std::string &source :
         {movement, std::string(MXQ_TEST_GOMOKU_ASSETS_DIR)}) {
        if (source.empty()) {
            continue;
        }
        for (const fs::directory_entry &entry :
             fs::directory_iterator(fs::path(source), ec)) {
            fs::copy_file(entry.path(), assets / entry.path().filename(),
                          fs::copy_options::overwrite_existing, ec);
        }
    }
    return assets;
}

MxqError make_error() {
    MxqError err;
    std::memset(&err, 0, sizeof(err));
    err.struct_size = static_cast<uint32_t>(sizeof(err));
    return err;
}

MxqStatus init_core(const std::string &store_dir, const std::string &assets,
                    MxqCore **out_core, MxqError *err) {
    MxqCoreConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.api_major = MXQ_API_VERSION_MAJOR;
    config.api_minor = MXQ_API_VERSION_MINOR;
    config.api_patch = MXQ_API_VERSION_PATCH;
    config.flags = 0;
    config.store_directory = store_dir.c_str();
    config.asset_directory = assets.c_str();
    return mxq_core_init(&config, out_core, err);
}

/* A budget whose plan lands exactly at the 256 MiB minimum with two threads:
 * a reserve of max(20% of 384 MiB, 128 MiB) = 128 MiB leaves 256 MiB usable,
 * under half of a 16 GiB device, rounded to 256. The smallest sufficient
 * preparation is also the fastest one this suite can make. */
MxqEngineBudget sufficient_budget() {
    MxqEngineBudget budget;
    std::memset(&budget, 0, sizeof(budget));
    budget.struct_size = static_cast<uint32_t>(sizeof(budget));
    budget.active_processor_count = 2;
    budget.available_bytes = 384ull * 1024ull * 1024ull;
    budget.physical_bytes = 16ull * 1024ull * 1024ull * 1024ull;
    return budget;
}

/* 300 MiB available: 128 reserved, 172 usable, rounded to 128 — below the
 * accepted minimum. */
MxqEngineBudget insufficient_budget() {
    MxqEngineBudget budget = sufficient_budget();
    budget.available_bytes = 300ull * 1024ull * 1024ull;
    return budget;
}

MxqGameConfig hvai_config(uint32_t movetime_ms,
                          MxqGameKind game = MXQ_GAME_KIND_MINI_XIANGQI) {
    MxqGameConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.mode = MXQ_PLAY_MODE_HUMAN_VS_AI;
    config.human_side = MXQ_COLOR_RED;
    config.ai_level = MXQ_AI_LEVEL_FAST;
    config.first_mover_choice = MXQ_FIRST_MOVER_HUMAN_FIRST;
    config.ai_movetime_ms = movetime_ms;
    config.local_side = MXQ_COLOR_NONE;
    config.game = game;
    return config;
}

/* The mode that freezes no level and no movetime at all, and so has nothing
 * for a search request to equal — the session the hint entry exists for. */
MxqGameConfig free_play_config(MxqGameKind game = MXQ_GAME_KIND_MINI_XIANGQI) {
    MxqGameConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.mode = MXQ_PLAY_MODE_FREE_PLAY;
    config.human_side = MXQ_COLOR_NONE;
    config.ai_level = MXQ_AI_LEVEL_NONE;
    config.first_mover_choice = MXQ_FIRST_MOVER_NONE;
    config.ai_movetime_ms = 0;
    config.local_side = MXQ_COLOR_NONE;
    config.game = game;
    return config;
}

MxqSearchRequest request_of(uint32_t movetime_ms) {
    MxqSearchRequest request;
    std::memset(&request, 0, sizeof(request));
    request.struct_size = static_cast<uint32_t>(sizeof(request));
    request.movetime_ms = movetime_ms;
    return request;
}

MxqEnginePlan make_plan() {
    MxqEnginePlan plan;
    std::memset(&plan, 0, sizeof(plan));
    plan.struct_size = static_cast<uint32_t>(sizeof(plan));
    return plan;
}

MxqSearchResult make_result() {
    MxqSearchResult result;
    std::memset(&result, 0, sizeof(result));
    result.struct_size = static_cast<uint32_t>(sizeof(result));
    return result;
}

/* The first legal move in the session's current position. 128 is the size
 * docs/core-interface.md's capacity constants make provably sufficient for this
 * variant; 64 is not. */
bool first_legal_move(const MxqGame *game, std::string &out) {
    MxqMove moves[128];
    for (auto &m : moves) {
        m.struct_size = static_cast<uint32_t>(sizeof(MxqMove));
    }
    size_t count = 0;
    if (mxq_game_legal_moves(game, moves, 128, &count, nullptr) != MXQ_OK ||
        count == 0) {
        return false;
    }
    out = moves[0].text;
    return true;
}

/* Whether the session accepts this move in the position it is in now, asked of
 * its own legal set rather than by applying it: the legal set of the current
 * position is the side to move's, and a proposal that commits nothing has to be
 * checked in a way that commits nothing either. */
bool legal_here(const MxqGame *game, const std::string &move) {
    MxqMove moves[128];
    for (auto &m : moves) {
        m.struct_size = static_cast<uint32_t>(sizeof(MxqMove));
    }
    size_t count = 0;
    if (mxq_game_legal_moves(game, moves, 128, &count, nullptr) != MXQ_OK) {
        return false;
    }
    for (size_t i = 0; i < count; ++i) {
        if (move == moves[i].text) {
            return true;
        }
    }
    return false;
}

/* The session's committed move count, read back out of the store rather than
 * off the session: "the hint commits nothing" is a claim about what was
 * written. */
uint32_t stored_move_count(MxqCore *core) {
    MxqRecordSummary summary;
    std::memset(&summary, 0, sizeof(summary));
    summary.struct_size = static_cast<uint32_t>(sizeof(summary));
    uint8_t exists = 0;
    if (mxq_store_active_summary(core, &summary, nullptr, &exists, nullptr) !=
            MXQ_OK ||
        exists != 1) {
        return UINT32_MAX;
    }
    return summary.move_count;
}

/* What one callback observed, written on the engine thread and read by the
 * test thread after completion. */
struct Delivered {
    std::atomic<bool> called{false};
    MxqSearchResult   result{};
    std::thread::id   thread_id{};
};

void record_callback(const MxqSearchResult *result, void *user_data) {
    Delivered *delivered = static_cast<Delivered *>(user_data);
    delivered->result = *result; /* copy and return */
    delivered->thread_id = std::this_thread::get_id();
    delivered->called.store(true, std::memory_order_release);
}

/* ---------------------------------------------------------------------- */
/* Preparation                                                             */
/* ---------------------------------------------------------------------- */

void case_query_before_prepare() {
    Case c("the engine reports uninitialised, with its profile, before any "
           "preparation");
    const fs::path store = scratch_dir("query-before-prepare");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        MxqEngineState state = MXQ_ENGINE_STATE_READY;
        char profile[MXQ_PROFILE_ID_CAP];
        size_t len = 0;
        c.check_status(mxq_engine_query(core, &state, profile, sizeof(profile),
                                        &len, &err),
                       MXQ_OK, "engine query");
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_UNINITIALIZED,
                   "state before preparation");
        c.check(len > 0 && profile[0] != '\0',
                "the profile identifier names the configuration even before "
                "preparation");
        /* The profile carries the pinned variant identifier. */
        c.check(std::string(profile).find("minixiangqiaxf") != std::string::npos,
                "the profile identifier names the pinned variant");
        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

void case_prepare_applies_the_plan() {
    Case c("preparation applies the plan and the effective NNUE state is on");
    const fs::path store = scratch_dir("prepare-applies");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        const MxqEngineBudget budget = sufficient_budget();

        /* The pure plan, computed beside the preparation: the applied plan
         * must be the same plan, not a variation on it. */
        MxqEnginePlan pure = make_plan();
        c.check_status(mxq_engine_plan(&budget, &pure, &err), MXQ_OK,
                       "the pure plan");

        MxqEnginePlan applied = make_plan();
        err = make_error();
        c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err),
                       MXQ_OK, "prepare");
        c.check_eq(applied.threads, pure.threads, "applied threads");
        c.check_eq(applied.hash_mib, pure.hash_mib, "applied hash");
        c.check_eq(applied.sufficient, 1, "applied plan is sufficient");
        c.check_eq(applied.hash_mib, 256, "the smallest sufficient plan");

        MxqEngineState state = MXQ_ENGINE_STATE_UNINITIALIZED;
        char profile[MXQ_PROFILE_ID_CAP];
        size_t len = 0;
        c.check_status(mxq_engine_query(core, &state, profile, sizeof(profile),
                                        &len, &err),
                       MXQ_OK, "engine query");
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_READY,
                   "state after preparation");

        /* The engine's own state, not the facade's report of it. */
        c.check_eq(static_cast<int64_t>(size_t(Stockfish::Options["Threads"])),
                   static_cast<int64_t>(pure.threads),
                   "the engine's Threads option");
        c.check_eq(static_cast<int64_t>(size_t(Stockfish::Options["Hash"])),
                   static_cast<int64_t>(pure.hash_mib),
                   "the engine's Hash option");
        c.check_eq(static_cast<int64_t>(Stockfish::Threads.size()),
                   static_cast<int64_t>(pure.threads),
                   "the engine's actual pool size");
        c.check(Stockfish::TT.allocated(),
                "the transposition table is allocated");
        c.check_eq(std::string(Stockfish::Options["UCI_Variant"]),
                   "minixiangqiaxf", "the engine's variant option");
        c.check(Stockfish::Eval::useNNUE,
                "the engine's effective NNUE state is on — the internal flag, "
                "not the option");
        const std::string expected_path =
            (fs::path(staged_assets()) / kBundledNetworkName).string();
        c.check_eq(Stockfish::Eval::eval_file_loaded, expected_path,
                   "the loaded network is the staged bundled one");

        /* The accepted shared profile. */
        c.check_eq(static_cast<int64_t>(int(Stockfish::Options["Skill Level"])),
                   20, "Skill Level");
        /* Read through each option's own type, not through its string form:
         * the engine's string conversion asserts on a spin or a check, so
         * reading one as a string passes only where the assertion is compiled
         * out and traps in a debug build. */
        c.check_eq(static_cast<int64_t>(int(Stockfish::Options["MultiPV"])), 1,
                   "MultiPV");
        c.check_eq(static_cast<int64_t>(
                       bool(Stockfish::Options["UCI_LimitStrength"])),
                   0, "UCI_LimitStrength is off");
        c.check_eq(static_cast<int64_t>(bool(Stockfish::Options["Ponder"])), 0,
                   "Ponder is off");

        /* Teardown releases whole and the rules bridge keeps answering. */
        err = make_error();
        c.check_status(mxq_engine_teardown(core, &err), MXQ_OK, "teardown");
        c.check_status(mxq_engine_query(core, &state, profile, sizeof(profile),
                                        &len, &err),
                       MXQ_OK, "engine query after teardown");
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_UNINITIALIZED,
                   "state after teardown");
        c.check(!Stockfish::TT.allocated(),
                "the transposition table is released whole");
        c.check_eq(static_cast<int64_t>(Stockfish::Threads.size()), 1,
                   "the pool returns to the rules posture");

        char fen[MXQ_FEN_CAP];
        size_t fen_len = 0;
        c.check_status(mxq_rules_start_fen(MXQ_GAME_KIND_MINI_XIANGQI, fen, sizeof(fen), &fen_len, &err),
                       MXQ_OK, "start fen");
        MxqPosition position;
        std::memset(&position, 0, sizeof(position));
        position.struct_size = static_cast<uint32_t>(sizeof(position));
        MxqGameStatus status;
        std::memset(&status, 0, sizeof(status));
        status.struct_size = static_cast<uint32_t>(sizeof(status));
        c.check_status(mxq_rules_evaluate(core, MXQ_GAME_KIND_MINI_XIANGQI, fen, nullptr, 0, &position,
                                          &status, nullptr, &err),
                       MXQ_OK, "rules still answer after teardown");
        c.check_eq(static_cast<int64_t>(status.state), MXQ_GAME_ONGOING,
                   "the start position is ongoing");

        /* Teardown of an unprepared engine asks for a state that already
         * holds. */
        c.check_status(mxq_engine_teardown(core, &err), MXQ_OK,
                       "teardown is idempotent");

        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

#if MXQ_TEST_GOMOKU_FACADE
/*
 * Preparing one game's engine releases the other engine first.
 *
 * That is load-bearing rather than tidy: one memory plan is computed from one
 * probe and sized for one transposition table, so an engine left prepared beside
 * the one being prepared would put two tables on a device the plan sized for
 * one. Nothing observable through the C surface distinguishes it — the profile
 * identifier and MxqEngineState both derive from the facade's own record of
 * which game is prepared, and would read identically if neither release ran.
 *
 * So this reaches past the surface, at the two named places and for the reason
 * this file's header already gives for the other three: the claim is about the
 * engines' own state, and asking the facade to report on itself would test the
 * report. Each bridge's released posture is read where that bridge keeps it —
 * the first engine's transposition table and pool size, the second engine's own
 * configured flag.
 */
void case_preparing_one_engine_releases_the_other() {
    Case c("preparing for a game releases the engine the other game is played on");

    /* The shipped shape of the movement staging — one network, for the variant
     * the app plays — beside the second engine's own. */
    const fs::path assets =
        stage_every_engines_assets("both-engines-assets", staged_assets());

    const fs::path store = scratch_dir("both-engines-store");
    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store.string(), assets.string(), &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    const MxqEngineBudget budget = sufficient_budget();
    const auto prepare = [&](MxqGameKind game, const std::string &who) {
        MxqEnginePlan plan;
        std::memset(&plan, 0, sizeof(plan));
        plan.struct_size = static_cast<uint32_t>(sizeof(plan));
        MxqError local = make_error();
        c.check_status(mxq_engine_prepare(core, game, &budget, &plan, &local),
                       MXQ_OK, who + " prepares (" + local.detail + ")");
    };

    /* A movement game: its own engine holds a table, and the placement engine
     * holds nothing. */
    prepare(MXQ_GAME_KIND_MINI_XIANGQI, "Mini Xiangqi");
    c.check(Stockfish::TT.allocated(),
            "the movement engine holds its transposition table");
    c.check(!mxq::rapfi::is_configured(),
            "and the placement engine is not configured beside it");

    /* A placement game: the movement engine goes back to the rules posture it
     * holds when nothing is prepared, table released whole. */
    prepare(MXQ_GAME_KIND_GOMOKU_15, "Gomoku");
    c.check(mxq::rapfi::is_configured(),
            "the placement engine is configured");
    c.check(!Stockfish::TT.allocated(),
            "and the movement engine's table was released first");
    c.check_eq(static_cast<int64_t>(Stockfish::Threads.size()), 1,
               "its pool with it");

    /* And back, which is the direction a player switching games takes. The app's
     * own game again rather than the other movement one: the staged directory is
     * the shipped shape, which holds one movement network, and which movement
     * game this is does not matter to the direction being asserted. */
    prepare(MXQ_GAME_KIND_MINI_XIANGQI, "Mini Xiangqi");
    c.check(Stockfish::TT.allocated(),
            "the movement engine holds a table again");
    c.check(!mxq::rapfi::is_configured(),
            "and the placement engine was released first");

    err = make_error();
    c.check_status(mxq_engine_teardown(core, &err), MXQ_OK, "teardown");
    c.check(!Stockfish::TT.allocated() && !mxq::rapfi::is_configured(),
            "teardown releases both");

    mxq_core_shutdown(core, nullptr);
    c.report();
}
#endif /* MXQ_TEST_GOMOKU_FACADE */

void case_insufficient_memory_initialises_nothing() {
    Case c("a budget below the minimum refuses without initialising anything");
    const fs::path store = scratch_dir("insufficient");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        const MxqEngineBudget budget = insufficient_budget();
        MxqEnginePlan applied = make_plan();
        err = make_error();
        c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err),
                       MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY,
                       "prepare below the minimum");
        MxqEngineState state = MXQ_ENGINE_STATE_READY;
        char profile[MXQ_PROFILE_ID_CAP];
        size_t len = 0;
        c.check_status(mxq_engine_query(core, &state, profile, sizeof(profile),
                                        &len, nullptr),
                       MXQ_OK, "engine query");
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_UNINITIALIZED,
                   "nothing was initialised");
        c.check(!Stockfish::TT.allocated(),
                "no transposition table was allocated, and no smaller Hash "
                "was substituted");
        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

/* Stage a temp asset directory holding the real variant configuration plus
 * whatever network bytes the case needs. */
fs::path stage_assets(const char *name, const char *network_name,
                      const std::string *network_bytes) {
    const fs::path dir = scratch_dir(name);
    std::error_code ec;
    fs::copy_file(fs::path(staged_assets()) / kVariantIniName,
                  dir / kVariantIniName, ec);
    if (network_name != nullptr && network_bytes != nullptr) {
        std::ofstream out(dir / network_name, std::ios::binary);
        out.write(network_bytes->data(),
                  static_cast<std::streamsize>(network_bytes->size()));
    }
    return dir;
}

std::string read_file(const fs::path &path) {
    std::ifstream in(path, std::ios::binary);
    return std::string((std::istreambuf_iterator<char>(in)),
                       std::istreambuf_iterator<char>());
}

/*
 * mxq_core_game_profile, whole: the four things its contract claims.
 *
 * It is the one query with no core parameter and no lock at all — a lookup in
 * a constexpr table — so "callable before initialisation" is not a convenience
 * but the shape of the function. The value half is what makes the claim worth
 * asserting rather than reading: the profile pairs a variant with the network
 * that variant is verified against, and a report that paired them by position
 * would be right for one game and silently wrong for the other.
 */
void case_game_profile() {
    Case c("mxq_core_game_profile answers for each game before any core "
           "exists, and pairs each variant with its own network");

    /* Before initialisation, and deliberately first in the suite's order: no
     * core has been created yet when this runs. */
    MxqError err = make_error();
    MxqGameProfile mini;
    std::memset(&mini, 0, sizeof(mini));
    mini.struct_size = static_cast<uint32_t>(sizeof(mini));
    c.check_status(
        mxq_core_game_profile(MXQ_GAME_KIND_MINI_XIANGQI, &mini, &err), MXQ_OK,
        "the app's game, before mxq_core_init");

    MxqGameProfile xiangqi;
    std::memset(&xiangqi, 0, sizeof(xiangqi));
    xiangqi.struct_size = static_cast<uint32_t>(sizeof(xiangqi));
    err = make_error();
    c.check_status(mxq_core_game_profile(MXQ_GAME_KIND_XIANGQI, &xiangqi, &err),
                   MXQ_OK, "the other game, before mxq_core_init");

    c.check_eq(static_cast<int64_t>(mini.game), MXQ_GAME_KIND_MINI_XIANGQI,
               "the profile names the game it was asked about");
    c.check_eq(static_cast<int64_t>(xiangqi.game), MXQ_GAME_KIND_XIANGQI,
               "and so does the other");

    /* The variant identifiers come from the manifest through the build
     * configuration, which is where the bridge reads its own from. */
    c.check_eq(std::string(mini.variant_id), std::string(kVariantId),
               "the app's game binds the pinned variant");
    c.check_eq(std::string(xiangqi.variant_id), std::string(kXiangqiVariantId),
               "the other game binds the built-in variant");

    /* And the network each names is that variant's own bytes, not the other's.
     * Hashing the staged file is what makes this a statement about the pairing
     * rather than about two strings being different from each other. */
    const std::string mini_bytes =
        read_file(fs::path(staged_xiangqi_assets()) / kBundledNetworkName);
    const std::string xiangqi_bytes =
        read_file(fs::path(staged_xiangqi_assets()) / kXiangqiNetworkName);
    if (mini_bytes.empty() || xiangqi_bytes.empty()) {
        c.check(false, "both networks are staged for this case");
    } else {
        c.check_eq(std::string(mini.nnue_sha256), mxq::sha256_hex(mini_bytes),
                   "the app's game names the SHA-256 of the network staged "
                   "for it");
        c.check_eq(std::string(xiangqi.nnue_sha256),
                   mxq::sha256_hex(xiangqi_bytes),
                   "the other game names the SHA-256 of its own network");
    }

#if defined(NDEBUG)
    /* A game outside the closed vocabulary is a programming error, so this
     * expectation is only observable where the assertion is compiled out. The
     * value is one past the last game any build carries rather than a literal
     * that a widened vocabulary would quietly turn into a game this core does
     * play — which is exactly what it did the first time the vocabulary grew. */
    MxqGameProfile refused;
    std::memset(&refused, 0, sizeof(refused));
    refused.struct_size = static_cast<uint32_t>(sizeof(refused));
    err = make_error();
    c.check_status(mxq_core_game_profile(
                       static_cast<MxqGameKind>(MXQ_GAME_KIND_RENJU + 1),
                       &refused, &err),
                   MXQ_ERR_ARG_RANGE, "a game this core does not play");
#endif
    c.report();
}

/* Every game this build carries, in the vocabulary's own order. Two cases below
 * ask the same question of each of them, and a list written twice would be a
 * list that stopped covering a game the day one copy was extended. */
const std::vector<MxqGameKind> &carried_games() {
    static const std::vector<MxqGameKind> games = {
        MXQ_GAME_KIND_MINI_XIANGQI,
        MXQ_GAME_KIND_XIANGQI,
#if MXQ_TEST_GOMOKU_FACADE
        MXQ_GAME_KIND_GOMOKU_15,
        MXQ_GAME_KIND_RENJU,
#endif
    };
    return games;
}

/* One game's profile identifier, or an empty string where the entry refused. */
std::string expected_profile_id(Case &c, MxqGameKind game,
                                const std::string &what) {
    char buffer[MXQ_PROFILE_ID_CAP];
    std::memset(buffer, 0, sizeof(buffer));
    size_t len = 0;
    MxqError err = make_error();
    const MxqStatus status =
        mxq_engine_profile_id(game, buffer, sizeof(buffer), &len, &err);
    c.check_status(status, MXQ_OK, what);
    if (status != MXQ_OK) {
        return std::string();
    }
    c.check(len > 0 && buffer[0] != '\0', what + ": a non-empty identifier");
    return std::string(buffer);
}

/*
 * mxq_engine_profile_id, whole: the identifier a game would be prepared under.
 *
 * It runs where mxq_core_game_profile above runs — before any core exists —
 * because that is its shape rather than a convenience. What it asserts is the
 * one fact no other entry states: a profile names the revision of the engine
 * *its own game* is played on, and this core has two of those. MxqVersion
 * reports the first engine's, so a caller composing an identifier out of that
 * and mxq_core_game_profile is right for the two games that engine plays and
 * silently wrong for the two it does not.
 *
 * That is not a hypothetical shape of mistake. It is the defect that kept
 * human-versus-AI off the placement games until this entry existed, and what
 * this case would catch is its return: a composition "simplified" to one
 * revision, or a segment dropped from it, either of which would make two games
 * answer with one identifier and attribute a move to a build that never played
 * it.
 */
void case_expected_profile_id() {
    Case c("mxq_engine_profile_id names each game's own engine, before any "
           "core exists");

    MxqVersion version;
    std::memset(&version, 0, sizeof(version));
    version.struct_size = static_cast<uint32_t>(sizeof(version));
    MxqError err = make_error();
    c.check_status(mxq_core_version(&version, &err), MXQ_OK,
                   "the version axes, before mxq_core_init");
    /* Twelve characters is what the identifier carries of a revision. Asked as
     * a substring rather than by taking the identifier apart, so that this
     * asserts which engine is named and not how the parts are joined. */
    const std::string reported_fork =
        std::string(version.fork_revision).substr(0, 12);

    std::vector<std::string> identifiers;
    for (const MxqGameKind game : carried_games()) {
        identifiers.push_back(expected_profile_id(
            c, game, "game " + std::to_string(static_cast<int>(game)) +
                         ", before mxq_core_init"));
    }

    /* Each game's own. Three of the four parts a profile is composed of are
     * that game's, so two games sharing an identifier would attribute one
     * game's moves to the other's network. */
    for (size_t i = 0; i < identifiers.size(); ++i) {
        for (size_t j = i + 1; j < identifiers.size(); ++j) {
            c.check(identifiers[i] != identifiers[j],
                    "each game's identifier is its own (" + identifiers[i] +
                        " / " + identifiers[j] + ")");
        }
    }

    /* The movement games are played on the fork MxqVersion names, and the
     * placement games are not. The second half is the gap this entry closes:
     * the revision a placement game's profile carries is one no other entry
     * reports, so there is nothing above this interface to compose it from. */
    c.check(identifiers[0].find(reported_fork) != std::string::npos &&
                identifiers[1].find(reported_fork) != std::string::npos,
            "the movement games name the fork revision MxqVersion reports");
#if MXQ_TEST_GOMOKU_FACADE
    c.check(identifiers[2].find(reported_fork) == std::string::npos &&
                identifiers[3].find(reported_fork) == std::string::npos,
            "and the placement games name a revision it does not report");
#endif

#if defined(NDEBUG)
    /* A game outside the closed vocabulary is a programming error, so this
     * expectation is only observable where the assertion is compiled out. One
     * past the last game any build carries, for the reason the case above gives
     * for the same value. */
    char refused[MXQ_PROFILE_ID_CAP];
    size_t refused_len = 0;
    err = make_error();
    c.check_status(mxq_engine_profile_id(
                       static_cast<MxqGameKind>(MXQ_GAME_KIND_RENJU + 1),
                       refused, sizeof(refused), &refused_len, &err),
                   MXQ_ERR_ARG_RANGE, "a game this core does not play");
#endif
    c.report();
}

/*
 * The identifier a game *would* be prepared under is the one it *is* prepared
 * under, for every game this build carries.
 *
 * These two answers are what readiness is decided by: a frontend compares what
 * mxq_engine_query reports against what this game needs, and acts on whether
 * they are the same string. So a divergence between them is not a diagnostic
 * inaccuracy. It is either an engine that never reads as ready — which stalls a
 * human-versus-AI game in a preparation loop that can never end — or one that
 * always does, which searches a position on whatever board the engine happens
 * to hold. Nothing else in this suite would notice either: every other case
 * reads one of the two answers and never both.
 */
void case_expected_profile_matches_the_prepared_one() {
    Case c("the profile a game would be prepared under is the one it is "
           "prepared under");

    /* Both movement networks rather than the shipped one, because this case
     * prepares every game the build carries and one of them is the built-in
     * variant. */
    const fs::path assets = stage_every_engines_assets(
        "every-engine-assets", staged_xiangqi_assets());

    const fs::path store = scratch_dir("every-engine-store");
    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store.string(), assets.string(), &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    const MxqEngineBudget budget = sufficient_budget();
    for (const MxqGameKind game : carried_games()) {
        const std::string who = "game " + std::to_string(static_cast<int>(game));
        MxqEnginePlan plan;
        std::memset(&plan, 0, sizeof(plan));
        plan.struct_size = static_cast<uint32_t>(sizeof(plan));
        err = make_error();
        const MxqStatus prepared_status =
            mxq_engine_prepare(core, game, &budget, &plan, &err);
        c.check_status(prepared_status, MXQ_OK,
                       who + " prepares (" + err.detail + ")");
        if (prepared_status != MXQ_OK) {
            continue;
        }

        MxqEngineState state = MXQ_ENGINE_STATE_UNINITIALIZED;
        char prepared[MXQ_PROFILE_ID_CAP];
        std::memset(prepared, 0, sizeof(prepared));
        size_t len = 0;
        err = make_error();
        c.check_status(mxq_engine_query(core, &state, prepared,
                                        sizeof(prepared), &len, &err),
                       MXQ_OK, who + " queries");
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_READY,
                   who + " is ready");
        c.check_eq(std::string(prepared),
                   expected_profile_id(c, game, who + " expects"),
                   who + " is prepared under the profile it expects");
    }

    err = make_error();
    c.check_status(mxq_engine_teardown(core, &err), MXQ_OK, "teardown");
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_missing_network() {
    Case c("a missing network refuses as asset-missing and the AI does not "
           "start");
    const fs::path assets = stage_assets("missing-nnue", nullptr, nullptr);
    const fs::path store = scratch_dir("missing-nnue-store");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), assets.string(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        const MxqEngineBudget budget = sufficient_budget();
        MxqEnginePlan applied = make_plan();
        err = make_error();
        c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err),
                       MXQ_ERR_ENGINE_ASSET_MISSING, "prepare");
        MxqEngineState state = MXQ_ENGINE_STATE_READY;
        char profile[MXQ_PROFILE_ID_CAP];
        size_t len = 0;
        mxq_engine_query(core, &state, profile, sizeof(profile), &len, nullptr);
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_UNINITIALIZED,
                   "the engine did not start");
        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

void case_wrong_basename_network() {
    Case c("the pinned bytes under the parent variant's basename fail the "
           "effective-NNUE preflight, not the byte preflight");
    /* The realistic packaging failure: the bytes are exactly the pinned
     * network — length and hash both pass — but the basename names the parent
     * variant, so it does not begin with the variant identifier. */
    const std::string bytes =
        read_file(fs::path(staged_assets()) / kBundledNetworkName);
    const std::string wrong_name = wrong_prefix_network_name();

    /* What is staged has to be the mistake this case is about, and it is
     * composed from two build definitions rather than written out — so a
     * definition that arrived empty or wrong would compose something like
     * "-ad52b8658c9e.nnue", which fails the prefix rule for a reason nobody
     * intended and would let this case pass while testing nothing it claims to.
     * These three make that loud instead. */
    c.check(std::strlen(kBaseVariantId) > 0,
            "MXQ_TEST_BASE_VARIANT_ID reached this build: the staged name is "
            "composed from it and means nothing when it is empty");
    c.check(wrong_name.starts_with(kBaseVariantId) &&
                wrong_name.size() > std::strlen(kBaseVariantId),
            "the staged name is the parent variant's identifier followed by the "
            "rest of the bundled name, got: " + wrong_name);
    c.check(!wrong_name.starts_with(kVariantId),
            std::string("the staged name does NOT begin with the configured "
                        "variant identifier, which is the whole provocation, "
                        "got: ") +
                wrong_name);

    const fs::path assets =
        stage_assets("wrong-basename", wrong_name.c_str(), &bytes);
    const fs::path store = scratch_dir("wrong-basename-store");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), assets.string(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        const MxqEngineBudget budget = sufficient_budget();
        MxqEnginePlan applied = make_plan();
        err = make_error();
        c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err),
                       MXQ_ERR_ENGINE_ASSET_MISMATCH, "prepare");
        c.check(std::string(err.detail).find("effective NNUE state") !=
                    std::string::npos,
                std::string("the detail names the effective state, got: ") +
                    err.detail);
        c.check(!Stockfish::Eval::useNNUE,
                "the engine's internal NNUE flag really was cleared — the "
                "trap this preflight exists for");
        MxqEngineState state = MXQ_ENGINE_STATE_READY;
        char profile[MXQ_PROFILE_ID_CAP];
        size_t len = 0;
        mxq_engine_query(core, &state, profile, sizeof(profile), &len, nullptr);
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_UNINITIALIZED,
                   "the engine unwound whole rather than keeping a partial "
                   "configuration");
        c.check(!Stockfish::TT.allocated(), "the unwind released the table");
        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

void case_corrupt_network() {
    Case c("corrupt network bytes refuse as asset-mismatch before the engine "
           "sees them");
    /* Right name, wrong bytes, at the pinned length: only the hash preflight
     * can catch this one. */
    std::string bytes =
        read_file(fs::path(staged_assets()) / kBundledNetworkName);
    if (bytes.size() > 100) {
        bytes[100] = static_cast<char>(~bytes[100]);
    }
    const fs::path assets =
        stage_assets("corrupt-nnue", kBundledNetworkName, &bytes);
    const fs::path store = scratch_dir("corrupt-nnue-store");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), assets.string(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        const MxqEngineBudget budget = sufficient_budget();
        MxqEnginePlan applied = make_plan();
        err = make_error();
        c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err),
                       MXQ_ERR_ENGINE_ASSET_MISMATCH, "prepare, flipped byte");
        c.check(std::string(err.detail).find("SHA-256") != std::string::npos,
                std::string("the detail names the hash, got: ") + err.detail);

        /* A truncated file fails the cheaper byte-length preflight. */
        const std::string truncated = bytes.substr(0, 1024);
        const fs::path assets2 =
            stage_assets("truncated-nnue", kBundledNetworkName, &truncated);
        mxq_core_shutdown(core, nullptr);
        core = nullptr;
        err = make_error();
        c.check_status(
            init_core(scratch_dir("truncated-nnue-store").string(),
                      assets2.string(), &core, &err),
            MXQ_OK, "core init against the truncated staging");
        if (core != nullptr) {
            err = make_error();
            c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err),
                           MXQ_ERR_ENGINE_ASSET_MISMATCH,
                           "prepare, truncated");
            c.check(std::string(err.detail).find("bytes") != std::string::npos,
                    std::string("the detail names the byte length, got: ") +
                        err.detail);
            mxq_core_shutdown(core, nullptr);
        }
    }
    c.report();
}

void case_variant_load_failure() {
    Case c("a configuration that parses but defines no pinned variant is a "
           "variant load failure, not a missing asset");
    /* The engine's process-global variant table survives a shutdown, so this
     * case is honest only while nothing has loaded the real configuration
     * yet — which is why main() runs it first. */
    const fs::path assets = scratch_dir("no-variant");
    {
        std::ofstream out(assets / kVariantIniName);
        out << "# a configuration that parses and defines nothing\n";
    }
    const fs::path store = scratch_dir("no-variant-store");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    const MxqStatus rc = init_core(store.string(), assets.string(), &core, &err);
    c.check_status(rc, MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED, "core init");
    c.check(core == nullptr, "no core was created");

    /* And a directory with no configuration at all is the missing asset. */
    const fs::path empty = scratch_dir("no-ini");
    err = make_error();
    c.check_status(init_core(scratch_dir("no-ini-store").string(),
                             empty.string(), &core, &err),
                   MXQ_ERR_ENGINE_ASSET_MISSING, "core init without the file");
    c.check(core == nullptr, "no core was created without the file");
    c.report();
}

/* ---------------------------------------------------------------------- */
/* Search                                                                  */
/* ---------------------------------------------------------------------- */

/* What the reentrancy probe observed from inside one callback. */
struct ReentrantProbe {
    Delivered delivered;
    const MxqGame *game = nullptr;
    MxqCore *core = nullptr;
    MxqStatus session_status = MXQ_OK;
    MxqStatus poll_status = MXQ_OK;
    MxqStatus cancel_status = MXQ_OK;
    MxqStatus plan_status = MXQ_ERR_ARG_REENTRANT;
    MxqStatus version_status = MXQ_ERR_ARG_REENTRANT;
    MxqStatus profile_status = MXQ_ERR_ARG_REENTRANT;
    MxqStatus profile_id_status = MXQ_ERR_ARG_REENTRANT;
    MxqStatus start_fen_status = MXQ_ERR_ARG_REENTRANT;
    MxqStatus versions_status = MXQ_ERR_ARG_REENTRANT;
};

void reentrant_callback(const MxqSearchResult *result, void *user_data) {
    ReentrantProbe *probe = static_cast<ReentrantProbe *>(user_data);

    /* Everything but the documented pure helpers refuses. */
    MxqGameStatus status;
    std::memset(&status, 0, sizeof(status));
    status.struct_size = static_cast<uint32_t>(sizeof(status));
    probe->session_status = mxq_game_status(probe->game, &status, nullptr);

    MxqSearchResult polled = make_result();
    uint8_t ready = 0;
    probe->poll_status =
        mxq_search_poll(probe->core, result->ticket, &polled, &ready, nullptr);
    probe->cancel_status =
        mxq_search_cancel(probe->core, result->ticket, nullptr);

    /* The documented pure helpers answer. */
    MxqEngineBudget budget;
    std::memset(&budget, 0, sizeof(budget));
    budget.struct_size = static_cast<uint32_t>(sizeof(budget));
    budget.active_processor_count = 1;
    budget.available_bytes = 1ull << 30;
    budget.physical_bytes = 1ull << 33;
    MxqEnginePlan plan = make_plan();
    probe->plan_status = mxq_engine_plan(&budget, &plan, nullptr);

    MxqVersion version;
    std::memset(&version, 0, sizeof(version));
    version.struct_size = static_cast<uint32_t>(sizeof(version));
    probe->version_status = mxq_core_version(&version, nullptr);

    MxqGameProfile profile;
    std::memset(&profile, 0, sizeof(profile));
    profile.struct_size = static_cast<uint32_t>(sizeof(profile));
    probe->profile_status =
        mxq_core_game_profile(MXQ_GAME_KIND_MINI_XIANGQI, &profile, nullptr);

    char profile_id[MXQ_PROFILE_ID_CAP];
    size_t profile_id_len = 0;
    probe->profile_id_status =
        mxq_engine_profile_id(MXQ_GAME_KIND_MINI_XIANGQI, profile_id,
                              sizeof(profile_id), &profile_id_len, nullptr);

    char fen[MXQ_FEN_CAP];
    size_t len = 0;
    probe->start_fen_status =
        mxq_rules_start_fen(MXQ_GAME_KIND_MINI_XIANGQI, fen, sizeof(fen), &len, nullptr);

    uint32_t min_readable = 0;
    uint32_t current = 0;
    probe->versions_status =
        mxq_archive_supported_versions(&min_readable, &current, nullptr);

    record_callback(result, &probe->delivered);
}

void case_search_end_to_end() {
    Case c("a real search yields a legal move the session accepts, delivered "
           "on the engine thread, retained under its ticket");
    const fs::path store = scratch_dir("end-to-end");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err), MXQ_OK,
                   "prepare");

    const uint32_t movetime = 120;
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        /* The human moves; the status then owes a search. */
        std::string human_move;
        c.check(first_legal_move(game, human_move), "a legal human move");
        MxqGameStatus status;
        std::memset(&status, 0, sizeof(status));
        status.struct_size = static_cast<uint32_t>(sizeof(status));
        c.check_status(mxq_game_apply_move(game, human_move.c_str(), nullptr,
                                           &status, &err),
                       MXQ_OK, "human move applies");
        c.check_eq(status.search_expected, 1, "a search is expected");

        char game_id[MXQ_GAME_ID_CAP];
        size_t id_len = 0;
        c.check_status(mxq_game_id(game, game_id, sizeof(game_id), &id_len,
                                   &err),
                       MXQ_OK, "game id");
        MxqPosition before;
        std::memset(&before, 0, sizeof(before));
        before.struct_size = static_cast<uint32_t>(sizeof(before));
        c.check_status(mxq_game_position(game, &before, &err), MXQ_OK,
                       "position before search");

        /* The wrong movetime is refused before anything starts; so is a
         * Free Play shape, which has no frozen movetime at all. */
        MxqSearchRequest wrong = request_of(movetime + 1);
        uint64_t ticket = 0;
        c.check_status(mxq_search_start(core, game, &wrong, nullptr, nullptr,
                                        &ticket, &err),
                       MXQ_ERR_ARG_RANGE,
                       "a request not equal to the frozen movetime");

        ReentrantProbe probe;
        probe.game = game;
        probe.core = core;
        MxqSearchRequest request = request_of(movetime);
        err = make_error();
        c.check_status(mxq_search_start(core, game, &request,
                                        reentrant_callback, &probe, &ticket,
                                        &err),
                       MXQ_OK, "search start");
        c.check(ticket != 0, "a ticket was issued");

        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the result arrived");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_MOVE,
                   "the outcome is a move");
        c.check_eq(result.ticket, static_cast<int64_t>(ticket),
                   "the result carries its ticket");
        c.check_eq(std::string(result.game_id), game_id,
                   "the result carries the game identity");
        c.check_eq(static_cast<int64_t>(result.position_revision),
                   static_cast<int64_t>(before.position_revision),
                   "the result carries the revision it searched from");
        c.check(result.profile_id[0] != '\0',
                "the result names the profile that produced it");
        c.check(result.nodes > 0, "nodes were searched");
        c.check(result.depth > 0, "a depth was reached");
        c.check(result.elapsed_ms >= movetime / 2,
                "the search thought for about its movetime");

        /* The callback observed the same result, on the engine thread, and
         * the reentrancy guard held. */
        c.check(probe.delivered.called.load(std::memory_order_acquire),
                "the callback fired");
        c.check(probe.delivered.thread_id != std::this_thread::get_id(),
                "the callback was delivered on the core's engine thread, not "
                "the calling thread");
        c.check_eq(static_cast<int64_t>(probe.delivered.result.outcome),
                   MXQ_SEARCH_MOVE, "the callback saw the move");
        c.check_eq(std::string(probe.delivered.result.move.text),
                   std::string(result.move.text),
                   "callback and wait are equivalent consumers");
        c.check_status(probe.session_status, MXQ_ERR_ARG_REENTRANT,
                       "a session call inside the callback");
        c.check_status(probe.poll_status, MXQ_ERR_ARG_REENTRANT,
                       "a poll inside the callback");
        c.check_status(probe.cancel_status, MXQ_ERR_ARG_REENTRANT,
                       "a cancel inside the callback");
        c.check_status(probe.plan_status, MXQ_OK,
                       "mxq_engine_plan is legal inside the callback");
        c.check_status(probe.version_status, MXQ_OK,
                       "mxq_core_version is legal inside the callback");
        c.check_status(probe.profile_status, MXQ_OK,
                       "mxq_core_game_profile is legal inside the callback");
        c.check_status(probe.profile_id_status, MXQ_OK,
                       "mxq_engine_profile_id is legal inside the callback");
        c.check_status(probe.start_fen_status, MXQ_OK,
                       "mxq_rules_start_fen is legal inside the callback");
        c.check_status(probe.versions_status, MXQ_OK,
                       "mxq_archive_supported_versions is legal inside the "
                       "callback");

        /* The move survives the whole ladder, so the session accepts it. */
        MxqPosition after;
        std::memset(&after, 0, sizeof(after));
        after.struct_size = static_cast<uint32_t>(sizeof(after));
        c.check_status(mxq_game_apply_move(game, result.move.text, &after,
                                           &status, &err),
                       MXQ_OK, "the proposed move is legal and applies");
        c.check(after.position_revision > before.position_revision,
                "the applied move bumped the revision");

        /* Retention: available again and again, until the next search. */
        MxqSearchResult again = make_result();
        ready = 0;
        c.check_status(mxq_search_poll(core, ticket, &again, &ready, &err),
                       MXQ_OK, "poll after wait");
        c.check_eq(ready, 1, "the result is retained under its ticket");
        c.check_eq(std::string(again.move.text), std::string(result.move.text),
                   "the retained result is the same result");

        /* The next search replaces it. */
        std::string second_human;
        c.check(first_legal_move(game, second_human), "a second human move");
        c.check_status(mxq_game_apply_move(game, second_human.c_str(), nullptr,
                                           nullptr, &err),
                       MXQ_OK, "second human move applies");
        uint64_t second_ticket = 0;
        err = make_error();
        c.check_status(mxq_search_start(core, game, &request, nullptr, nullptr,
                                        &second_ticket, &err),
                       MXQ_OK, "second search start");
        ready = 1;
        c.check_status(mxq_search_poll(core, ticket, &again, &ready, &err),
                       MXQ_OK, "poll the first ticket after the next search");
        c.check_eq(ready, 0, "the first result is gone: retained until the "
                             "next search, and this was the next search");
        MxqSearchResult second = make_result();
        c.check_status(mxq_search_wait(core, second_ticket, 20000, &second,
                                       &ready, &err),
                       MXQ_OK, "wait for the second search");
        c.check_eq(ready, 1, "the second result arrived");
        c.check_eq(static_cast<int64_t>(second.outcome), MXQ_SEARCH_MOVE,
                   "the second outcome is a move");

        /* Gone after shutdown: the handle no longer answers at all. A core
         * handle that is not the live instance is one of the programming
         * errors the contract has assert in a debug build, so the returned
         * status is observable only where that assertion is compiled out. */
        mxq_core_shutdown(core, nullptr);
#if defined(NDEBUG)
        ready = 1;
        MxqSearchResult gone = make_result();
        const MxqStatus dead =
            mxq_search_poll(core, second_ticket, &gone, &ready, nullptr);
        c.check(dead != MXQ_OK,
                "after shutdown the ticket answers an error, not a result");
#endif
        mxq_game_release(game);
    } else {
        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

void case_free_play_owes_no_search() {
    Case c("a Free Play session has no frozen movetime and no search");
    const fs::path store = scratch_dir("free-play");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        const MxqEngineBudget budget = sufficient_budget();
        MxqEnginePlan applied = make_plan();
        c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err),
                       MXQ_OK, "prepare");
        const MxqGameConfig config = free_play_config();
        MxqGame *game = nullptr;
        c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                       "free play create");
        if (game != nullptr) {
            MxqSearchRequest request = request_of(0);
            uint64_t ticket = 0;
            err = make_error();
            c.check_status(mxq_search_start(core, game, &request, nullptr,
                                            nullptr, &ticket, &err),
                           MXQ_ERR_ARG_RANGE,
                           "a zero movetime never equals a frozen one");
            mxq_game_release(game);
        }
        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

void case_cancel_before_completion() {
    Case c("cancellation is prompt, and the late result is rejected by the "
           "cancelled rung with the revision unchanged");
    const fs::path store = scratch_dir("cancel");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err), MXQ_OK,
                   "prepare");
    const uint32_t movetime = 5000; /* never allowed to finish */
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        std::string human_move;
        c.check(first_legal_move(game, human_move), "a legal human move");
        c.check_status(mxq_game_apply_move(game, human_move.c_str(), nullptr,
                                           nullptr, &err),
                       MXQ_OK, "human move applies");
        MxqPosition before;
        std::memset(&before, 0, sizeof(before));
        before.struct_size = static_cast<uint32_t>(sizeof(before));
        c.check_status(mxq_game_position(game, &before, &err), MXQ_OK,
                       "position before search");

        Delivered delivered;
        MxqSearchRequest request = request_of(movetime);
        uint64_t ticket = 0;
        const auto begun = std::chrono::steady_clock::now();
        c.check_status(mxq_search_start(core, game, &request, record_callback,
                                        &delivered, &ticket, &err),
                       MXQ_OK, "search start");
        c.check_status(mxq_search_cancel(core, ticket, &err), MXQ_OK,
                       "cancel");
        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        const auto elapsed =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - begun)
                .count();
        c.check_eq(ready, 1, "the cancelled result was delivered");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_CANCELLED,
                   "the outcome is cancelled");
        c.check(elapsed < 2500,
                "cancellation was prompt (" + std::to_string(elapsed) +
                    " ms against a movetime of 5000)");
        c.check(delivered.called.load(std::memory_order_acquire),
                "the cancelled callback still fired");
        c.check_eq(static_cast<int64_t>(delivered.result.outcome),
                   MXQ_SEARCH_CANCELLED, "the callback saw the cancellation");

        /* The suspension property: no mutation happened, so the revision
         * still matches — the cancelled rung, not the stale rung, is what
         * rejected the late result. */
        MxqPosition after;
        std::memset(&after, 0, sizeof(after));
        after.struct_size = static_cast<uint32_t>(sizeof(after));
        c.check_status(mxq_game_position(game, &after, &err), MXQ_OK,
                       "position after cancellation");
        c.check_eq(static_cast<int64_t>(after.position_revision),
                   static_cast<int64_t>(before.position_revision),
                   "the revision is unchanged");
        c.check_eq(static_cast<int64_t>(result.position_revision),
                   static_cast<int64_t>(after.position_revision),
                   "the rejected result even matches the live revision — "
                   "only cancellation rejects this one");

        /* Cancelling a finished ticket asks for a state that already
         * holds. */
        c.check_status(mxq_search_cancel(core, ticket, &err), MXQ_OK,
                       "cancel after completion");
        c.check_status(mxq_search_cancel(core, 987654321u, &err), MXQ_OK,
                       "cancel of an unknown ticket");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_undo_while_thinking_is_stale() {
    Case c("a mutation after the search started makes the result stale");
    const fs::path store = scratch_dir("stale");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err), MXQ_OK,
                   "prepare");
    const uint32_t movetime = 600;
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        std::string human_move;
        c.check(first_legal_move(game, human_move), "a legal human move");
        c.check_status(mxq_game_apply_move(game, human_move.c_str(), nullptr,
                                           nullptr, &err),
                       MXQ_OK, "human move applies");

        Delivered delivered;
        MxqSearchRequest request = request_of(movetime);
        uint64_t ticket = 0;
        c.check_status(mxq_search_start(core, game, &request, record_callback,
                                        &delivered, &ticket, &err),
                       MXQ_OK, "search start");

        /* Undo while the engine is thinking — the accepted product flow that
         * makes this rung real. The session mutates and commits on this
         * thread while the engine searches on its own; the revision bump is
         * what neutralises the un-cancelled search. */
        std::this_thread::sleep_for(std::chrono::milliseconds(120));
        uint32_t removed = 0;
        c.check_status(mxq_game_undo(game, &removed, &err), MXQ_OK,
                       "undo while thinking");
        c.check_eq(removed, 1, "the human move came off");

        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the result was delivered");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_STALE,
                   "the outcome is stale");
        c.check_eq(static_cast<int64_t>(delivered.result.outcome),
                   MXQ_SEARCH_STALE, "the callback saw the staleness");
        MxqPosition now;
        std::memset(&now, 0, sizeof(now));
        now.struct_size = static_cast<uint32_t>(sizeof(now));
        c.check_status(mxq_game_position(game, &now, &err), MXQ_OK,
                       "position after undo");
        c.check(now.position_revision != result.position_revision,
                "the live revision differs from the searched one");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_released_origin_is_stale_even_when_identity_recurs() {
    Case c("a search from a released session is stale even when a resumed "
           "session reuses its game_id at a colliding revision");
    const fs::path store = scratch_dir("stale-recur");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err), MXQ_OK,
                   "prepare");

    /* The wrong-move shape this regression pins: search at revision 2 of one
     * session, then release it without cancelling and resume the same stored
     * game — a second session whose counter restarts — and walk it to
     * revision 2 of a different position. Both documented staleness
     * comparisons then read equal values, so only the origin session's own
     * identity can reject the result; delivering it as a move commits the
     * old position's move onto the new position. */
    const uint32_t movetime = 1200;
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        for (int ply = 0; ply < 2; ++ply) {
            std::string move;
            c.check(first_legal_move(game, move), "a legal move to apply");
            c.check_status(mxq_game_apply_move(game, move.c_str(), nullptr,
                                               nullptr, &err),
                           MXQ_OK, "the move applies");
        }

        Delivered delivered;
        MxqSearchRequest request = request_of(movetime);
        uint64_t ticket = 0;
        c.check_status(mxq_search_start(core, game, &request, record_callback,
                                        &delivered, &ticket, &err),
                       MXQ_OK, "search start at revision 2");
        mxq_game_release(game);

        MxqGame *resumed = nullptr;
        uint8_t exists = 0;
        c.check_status(mxq_game_resume_active(core, &resumed, &exists, &err),
                       MXQ_OK, "resume the same stored game");
        c.check_eq(exists, 1, "the active game is there to resume");
        if (resumed != nullptr) {
            for (int ply = 0; ply < 2; ++ply) {
                std::string move;
                c.check(first_legal_move(resumed, move),
                        "a legal move on the resumed session");
                c.check_status(mxq_game_apply_move(resumed, move.c_str(),
                                                   nullptr, nullptr, &err),
                               MXQ_OK, "the resumed session's move applies");
            }
            MxqPosition now;
            std::memset(&now, 0, sizeof(now));
            now.struct_size = static_cast<uint32_t>(sizeof(now));
            c.check_status(mxq_game_position(resumed, &now, &err), MXQ_OK,
                           "the resumed position");
            c.check_eq(now.position_revision, 2,
                       "the resumed counter really collides with the "
                       "searched one — the case bites only if the values "
                       "agree");

            MxqSearchResult result = make_result();
            uint8_t ready = 0;
            c.check_status(mxq_search_wait(core, ticket, 20000, &result,
                                           &ready, &err),
                           MXQ_OK, "wait");
            c.check_eq(ready, 1, "the result was delivered");
            c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_STALE,
                       "the released origin makes the result stale, colliding "
                       "counter or not");
            c.check_eq(static_cast<int64_t>(delivered.result.outcome),
                       MXQ_SEARCH_STALE, "the callback saw the staleness");

            MxqMove history[16];
            size_t count = 0;
            c.check_status(mxq_game_move_history(resumed, history, 16, &count,
                                                 &err),
                           MXQ_OK, "the resumed history");
            c.check_eq(count, 4,
                       "nothing from the dead search reached the live game");
            mxq_game_release(resumed);
        }
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_released_origin_without_replacement_is_stale() {
    Case c("a search whose origin session was released rejects as stale");
    const fs::path store = scratch_dir("stale-released");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err), MXQ_OK,
                   "prepare");
    const uint32_t movetime = 600;
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        std::string move;
        c.check(first_legal_move(game, move), "a legal move");
        c.check_status(mxq_game_apply_move(game, move.c_str(), nullptr,
                                           nullptr, &err),
                       MXQ_OK, "the move applies");
        Delivered delivered;
        MxqSearchRequest request = request_of(movetime);
        uint64_t ticket = 0;
        c.check_status(mxq_search_start(core, game, &request, record_callback,
                                        &delivered, &ticket, &err),
                       MXQ_OK, "search start");
        /* Released without a cancel, and nothing resumes it: the origin is
         * simply gone at delivery. */
        mxq_game_release(game);
        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the result was delivered");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_STALE,
                   "an absent origin is the stale fact");
        c.check_eq(static_cast<int64_t>(delivered.result.outcome),
                   MXQ_SEARCH_STALE, "the callback saw the staleness");
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_no_move_on_a_terminal_position_is_failed() {
    Case c("a search on a position with no legal moves delivers the typed "
           "no-move failure and faults nothing");
    const fs::path store = scratch_dir("no-move");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err), MXQ_OK,
                   "prepare");
    const uint32_t movetime = 200;
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        /* The three-ply checkmate the session suite plays: the side to move
         * has no legal reply, so the engine has no move to return. The
         * facade refuses nothing here — search_expected is the frontend's
         * affordance, not a gate — and the delivery must say what the engine
         * found, in the engine's own domain. */
        for (const char *move : {"b1b3", "a6a5", "b3d3"}) {
            c.check_status(mxq_game_apply_move(game, move, nullptr, nullptr,
                                               &err),
                           MXQ_OK, "the mating line applies");
        }
        MxqGameStatus over;
        std::memset(&over, 0, sizeof(over));
        over.struct_size = static_cast<uint32_t>(sizeof(over));
        c.check_status(mxq_game_status(game, &over, &err), MXQ_OK,
                       "the terminal status");
        c.check_eq(static_cast<int64_t>(over.state), MXQ_GAME_RED_WINS,
                   "the line really mates");

        Delivered delivered;
        MxqSearchRequest request = request_of(movetime);
        uint64_t ticket = 0;
        c.check_status(mxq_search_start(core, game, &request, record_callback,
                                        &delivered, &ticket, &err),
                       MXQ_OK, "search start on the mated position");
        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the result was delivered");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_FAILED,
                   "no move is the typed failure outcome");
        c.check_eq(static_cast<int64_t>(result.status), MXQ_ERR_ENGINE_NO_MOVE,
                   "and its status is the engine-domain no-move code");
        c.check_eq(static_cast<int64_t>(delivered.result.status),
                   MXQ_ERR_ENGINE_NO_MOVE, "the callback saw the same code");

        /* NoMove is the engine answering an empty position, not a fault: the
         * next game's search must find the engine still prepared. */
        MxqEngineState state = MXQ_ENGINE_STATE_UNINITIALIZED;
        char profile[128];
        size_t profile_len = 0;
        c.check_status(mxq_engine_query(core, &state, profile,
                                        sizeof(profile), &profile_len, &err),
                       MXQ_OK, "query after the no-move delivery");
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_READY,
                   "the engine is still ready");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_reconfiguration_refused_mid_search() {
    Case c("prepare and teardown refuse while a search is outstanding, and "
           "search after teardown refuses as not ready");
    const fs::path store = scratch_dir("in-progress");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err), MXQ_OK,
                   "prepare");
    const uint32_t movetime = 4000;
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        std::string human_move;
        c.check(first_legal_move(game, human_move), "a legal human move");
        c.check_status(mxq_game_apply_move(game, human_move.c_str(), nullptr,
                                           nullptr, &err),
                       MXQ_OK, "human move applies");
        MxqSearchRequest request = request_of(movetime);
        uint64_t ticket = 0;
        c.check_status(mxq_search_start(core, game, &request, nullptr, nullptr,
                                        &ticket, &err),
                       MXQ_OK, "search start");

        err = make_error();
        c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err),
                       MXQ_ERR_STATE_SEARCH_IN_PROGRESS,
                       "prepare mid-search refuses rather than stalling");
        err = make_error();
        c.check_status(mxq_engine_teardown(core, &err),
                       MXQ_ERR_STATE_SEARCH_IN_PROGRESS,
                       "teardown mid-search cancels nothing and refuses");

        c.check_status(mxq_search_cancel(core, ticket, &err), MXQ_OK,
                       "cancel");
        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait out the cancellation");
        c.check_eq(ready, 1, "the cancelled result was delivered");

        c.check_status(mxq_engine_teardown(core, &err), MXQ_OK,
                       "teardown after the search drained");
        err = make_error();
        c.check_status(mxq_search_start(core, game, &request, nullptr, nullptr,
                                        &ticket, &err),
                       MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "search after teardown refuses: the engine is not "
                       "prepared");

        /* The rules bridge is untouched by the whole episode: the session
         * keeps answering. */
        MxqMove moves[128];
        size_t count = 0;
        c.check_status(mxq_game_legal_moves(game, moves, 128, &count, &err),
                       MXQ_OK, "legal moves after teardown");
        c.check(count > 0, "the position still has its legal moves");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_core_cancel_all_quiesces() {
    Case c("mxq_core_cancel_all blocks until the engine quiesces and the "
           "game plays on");
    const fs::path store = scratch_dir("cancel-all");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err), MXQ_OK,
                   "prepare");
    const uint32_t movetime = 4000;
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        std::string human_move;
        c.check(first_legal_move(game, human_move), "a legal human move");
        c.check_status(mxq_game_apply_move(game, human_move.c_str(), nullptr,
                                           nullptr, &err),
                       MXQ_OK, "human move applies");
        Delivered delivered;
        MxqSearchRequest request = request_of(movetime);
        uint64_t ticket = 0;
        c.check_status(mxq_search_start(core, game, &request, record_callback,
                                        &delivered, &ticket, &err),
                       MXQ_OK, "search start");

        c.check_status(mxq_core_cancel_all(core, &err), MXQ_OK, "cancel all");
        /* Blocking until quiescence means the callback has already fired by
         * the time it returns. */
        c.check(delivered.called.load(std::memory_order_acquire),
                "the callback fired before cancel_all returned");
        c.check_eq(static_cast<int64_t>(delivered.result.outcome),
                   MXQ_SEARCH_CANCELLED, "with the cancelled outcome");

        /* The committed game is never affected: the store is consistent and
         * the session mutable. */
        std::string next_move;
        c.check(first_legal_move(game, next_move),
                "the position still answers");
        c.check_status(mxq_game_apply_move(game, next_move.c_str(), nullptr,
                                           nullptr, &err),
                       MXQ_OK, "the game plays on after cancel_all");

        MxqEngineState state = MXQ_ENGINE_STATE_UNINITIALIZED;
        char profile[MXQ_PROFILE_ID_CAP];
        size_t len = 0;
        c.check_status(mxq_engine_query(core, &state, profile, sizeof(profile),
                                        &len, &err),
                       MXQ_OK, "engine query");
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_READY,
                   "cancel_all cancels work; releasing the engine is "
                   "teardown's job");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_shutdown_mid_search() {
    Case c("shutdown mid-search fires the cancelled callback, joins, and "
           "leaves the store consistent for the next core");
    const fs::path store = scratch_dir("shutdown-mid-search");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget, &applied, &err), MXQ_OK,
                   "prepare");
    const uint32_t movetime = 4000;
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game == nullptr) {
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }
    std::string human_move;
    c.check(first_legal_move(game, human_move), "a legal human move");
    c.check_status(mxq_game_apply_move(game, human_move.c_str(), nullptr,
                                       nullptr, &err),
                   MXQ_OK, "human move applies and commits");

    Delivered delivered;
    MxqSearchRequest request = request_of(movetime);
    uint64_t ticket = 0;
    c.check_status(mxq_search_start(core, game, &request, record_callback,
                                    &delivered, &ticket, &err),
                   MXQ_OK, "search start");

    /* No cancel first: shutdown itself cancels all work, and joining the
     * engine thread means the callback has fired by the time it returns. */
    c.check_status(mxq_core_shutdown(core, &err), MXQ_OK,
                   "shutdown mid-search");
    c.check(delivered.called.load(std::memory_order_acquire),
            "the callback fired before the join completed");
    c.check_eq(static_cast<int64_t>(delivered.result.outcome),
               MXQ_SEARCH_CANCELLED, "with the cancelled outcome");

    /* The handle is tombstoned, not freed. */
    MxqGameStatus status;
    std::memset(&status, 0, sizeof(status));
    status.struct_size = static_cast<uint32_t>(sizeof(status));
    c.check_status(mxq_game_status(game, &status, nullptr),
                   MXQ_ERR_ARG_INVALID_HANDLE,
                   "the outstanding handle answers invalid-handle");
    mxq_game_release(game);

    /* Termination mid-search loses nothing: the committed move is in the
     * store, and a fresh core resumes it. */
    MxqCore *next = nullptr;
    err = make_error();
    c.check_status(init_core(store.string(), staged_assets(), &next, &err),
                   MXQ_OK, "a fresh core over the same store");
    if (next != nullptr) {
        MxqGame *resumed = nullptr;
        uint8_t exists = 0;
        c.check_status(mxq_game_resume_active(next, &resumed, &exists, &err),
                       MXQ_OK, "resume");
        c.check_eq(exists, 1, "the active game survived");
        if (resumed != nullptr) {
            MxqMove line[8];
            size_t count = 0;
            c.check_status(mxq_game_move_history(resumed, line, 8, &count,
                                                 &err),
                           MXQ_OK, "the resumed line");
            c.check_eq(static_cast<int64_t>(count), 1,
                       "exactly the committed human move — the search "
                       "committed nothing");
            mxq_game_release(resumed);
        }
        mxq_core_shutdown(next, nullptr);
    }
    c.report();
}

/* ---------------------------------------------------------------------- */
/* Hints                                                                   */
/* ---------------------------------------------------------------------- */

/*
 * The hint entry is mxq_search_start with three differences, and these cases
 * are those three plus the promise that nothing else moved: the thinking time
 * is an input rather than a cross-check — one of the levels, or this game's own
 * frozen value — one search is outstanding at a time, and the states that would
 * take no move have no move to suggest. Everything the reply path already
 * proves about tickets, staleness, cancellation and delivery is asserted here
 * only where a hint could plausibly have taken its own path to it.
 *
 * Completing hints think for MXQ_MOVETIME_FAST_MS, the shortest of the levels,
 * or for the short frozen value a case created its own game with; the cases
 * that never let a search finish use the longer levels.
 */

void case_hint_in_human_versus_ai() {
    Case c("a hint proposes a legal move for the side to move, commits "
           "nothing, and never asks what the game froze");
    const fs::path store = scratch_dir("hint-hvai");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget,
                                      &applied, &err),
                   MXQ_OK, "prepare");

    /* The frozen movetime is deliberately not one of the three accepted
     * levels, so that a hint answered at one of them cannot have been compared
     * with it. */
    const uint32_t frozen = 120;
    const MxqGameConfig config = hvai_config(frozen);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        /* The human's own turn: human_side is Red and Red moves first. */
        char game_id[MXQ_GAME_ID_CAP];
        size_t id_len = 0;
        c.check_status(mxq_game_id(game, game_id, sizeof(game_id), &id_len,
                                   &err),
                       MXQ_OK, "game id");
        MxqPosition before;
        std::memset(&before, 0, sizeof(before));
        before.struct_size = static_cast<uint32_t>(sizeof(before));
        c.check_status(mxq_game_position(game, &before, &err), MXQ_OK,
                       "position before the hint");
        c.check_eq(static_cast<int64_t>(before.side_to_move), MXQ_COLOR_RED,
                   "the side to move is the human's");

        Delivered delivered;
        uint64_t ticket = 0;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_FAST_MS,
                                             record_callback, &delivered,
                                             &ticket, &err),
                       MXQ_OK, "hint start");
        c.check(ticket != 0, "a ticket was issued");

        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the hint arrived");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_MOVE,
                   "the outcome is a move");
        c.check_eq(result.ticket, static_cast<int64_t>(ticket),
                   "the result carries its ticket");
        c.check_eq(std::string(result.game_id), game_id,
                   "the result carries the game identity");
        c.check_eq(static_cast<int64_t>(result.position_revision),
                   static_cast<int64_t>(before.position_revision),
                   "and the revision it searched from");
        c.check(result.profile_id[0] != '\0',
                "and the profile that produced it");
        c.check(delivered.called.load(std::memory_order_acquire),
                "the callback fired");
        c.check(delivered.thread_id != std::this_thread::get_id(),
                "on the core's engine thread, not the calling thread");
        c.check_eq(std::string(delivered.result.move.text),
                   std::string(result.move.text),
                   "callback and wait are equivalent consumers here too");

        /* A move of this board, and one the side to move may actually make. */
        c.check(mxq::notation::well_formed_move(MXQ_GAME_KIND_MINI_XIANGQI,
                                                std::string(result.move.text)),
                std::string("the move is in this game's notation, got: ") +
                    result.move.text);
        c.check(legal_here(game, result.move.text),
                std::string("the proposed move is in the side to move's legal "
                            "set, got: ") +
                    result.move.text);

        /* And nothing happened: the hint is advisory, so the position, the
         * revision and the stored line are exactly what they were. */
        MxqPosition after;
        std::memset(&after, 0, sizeof(after));
        after.struct_size = static_cast<uint32_t>(sizeof(after));
        c.check_status(mxq_game_position(game, &after, &err), MXQ_OK,
                       "position after the hint");
        c.check_eq(static_cast<int64_t>(after.position_revision),
                   static_cast<int64_t>(before.position_revision),
                   "the revision did not move");
        c.check_eq(std::string(after.fen), std::string(before.fen),
                   "the position did not move");
        c.check_eq(static_cast<int64_t>(stored_move_count(core)), 0,
                   "and the store holds no move: the hint committed nothing");

        /* The reply entry still cross-checks the frozen movetime, so the value
         * this hint was answered at would not have passed it. That is the
         * whole reason this entry exists. */
        MxqSearchRequest request = request_of(MXQ_MOVETIME_FAST_MS);
        uint64_t refused = 0;
        err = make_error();
        c.check_status(mxq_search_start(core, game, &request, nullptr, nullptr,
                                        &refused, &err),
                       MXQ_ERR_ARG_RANGE,
                       "the reply entry refuses the movetime the hint was "
                       "answered at");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_hint_in_free_play() {
    Case c("a Free Play session freezes no movetime, owes no search, and "
           "answers a hint all the same");
    const fs::path store = scratch_dir("hint-free-play");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget,
                                      &applied, &err),
                   MXQ_OK, "prepare");
    const MxqGameConfig config = free_play_config();
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "free play create");
    if (game != nullptr) {
        MxqGameConfig frozen;
        std::memset(&frozen, 0, sizeof(frozen));
        frozen.struct_size = static_cast<uint32_t>(sizeof(frozen));
        c.check_status(mxq_game_config(game, &frozen, &err), MXQ_OK,
                       "the frozen configuration");
        c.check_eq(frozen.ai_movetime_ms, 0, "which freezes no movetime");

        /* The reply entry has nothing to equal and refuses at every value,
         * this one included. */
        MxqSearchRequest request = request_of(MXQ_MOVETIME_FAST_MS);
        uint64_t refused = 0;
        err = make_error();
        c.check_status(mxq_search_start(core, game, &request, nullptr, nullptr,
                                        &refused, &err),
                       MXQ_ERR_ARG_RANGE,
                       "the reply entry refuses a session with no frozen "
                       "movetime");

        /* And the hint entry takes a session's frozen value only where it is
         * positive: this one's is zero, which is no thinking time at all, so
         * here the levels are the whole accepted set. */
        uint64_t at_zero = 1;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, 0, nullptr, nullptr,
                                             &at_zero, &err),
                       MXQ_ERR_ARG_RANGE,
                       "a hint at zero, which is this session's frozen value");
        c.check_eq(static_cast<int64_t>(at_zero), 0, "and no ticket for it");

        uint64_t ticket = 0;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_FAST_MS,
                                             nullptr, nullptr, &ticket, &err),
                       MXQ_OK, "hint start on the Free Play session");
        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the hint arrived");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_MOVE,
                   "the outcome is a move");
        c.check(legal_here(game, result.move.text),
                std::string("the proposed move is in the side to move's legal "
                            "set, got: ") +
                    result.move.text);
        c.check_eq(static_cast<int64_t>(stored_move_count(core)), 0,
                   "the hint committed nothing here either");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_hint_movetime_is_a_level_or_this_game_s_own() {
    Case c("the hint's thinking time is one of the levels or the value this "
           "game froze, and any other value is refused without a ticket");
    const fs::path store = scratch_dir("hint-movetime");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    /* Prepared, deliberately: an accepted thinking time has to be seen to be
     * ACCEPTED — a ticket for a real search — rather than merely to reach the
     * next refusal, which every value would do on an engine that is not ready.
     */
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget,
                                      &applied, &err),
                   MXQ_OK, "prepare");
    /* A positive frozen value that is none of the levels: the shape a game
     * created under a level pairing that has since been retuned has, and the
     * one the second accepted form exists for. */
    const uint32_t frozen = 120;
    const MxqGameConfig config = hvai_config(frozen);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        /* Each accepted value starts a search of its own, and each is drained
         * before the next: a hint refuses while one is outstanding, and a
         * cancelled search never burns its thinking time. */
        for (const uint32_t accepted : {MXQ_MOVETIME_FAST_MS,
                                        MXQ_MOVETIME_STANDARD_MS,
                                        MXQ_MOVETIME_DEEP_MS, frozen}) {
            uint64_t ticket = 0;
            err = make_error();
            c.check_status(mxq_search_start_hint(core, game, accepted, nullptr,
                                                 nullptr, &ticket, &err),
                           MXQ_OK,
                           std::to_string(accepted) +
                               " ms is accepted and searched for");
            c.check(ticket != 0, std::to_string(accepted) +
                                     " ms was issued a ticket");
            c.check_status(mxq_search_cancel(core, ticket, &err), MXQ_OK,
                           "cancel");
            MxqSearchResult result = make_result();
            uint8_t ready = 0;
            c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                           &err),
                           MXQ_OK, "wait out the cancellation");
            c.check_eq(ready, 1, "the cancelled hint drained");
        }

        /* Everything else is refused, on the same prepared engine with nothing
         * outstanding, so the thinking time is the only thing wrong with the
         * call. 121 is a near miss on this game's frozen value and 4000 one on
         * the levels; zero is what Free Play freezes, and a session's frozen
         * value counts only where it is positive. The refusal reports and does
         * not assert, so both configurations evaluate this. */
        for (const uint32_t refused :
             {0u, 1u, 119u, 121u, 999u, 4000u, 5001u, UINT32_MAX}) {
            uint64_t ticket = 1;
            err = make_error();
            c.check_status(mxq_search_start_hint(core, game, refused, nullptr,
                                                 nullptr, &ticket, &err),
                           MXQ_ERR_ARG_RANGE,
                           std::to_string(refused) +
                               " ms is neither a level nor this game's frozen "
                               "value");
            c.check_eq(static_cast<int64_t>(ticket), 0,
                       "and no ticket was issued for it");
        }
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_hint_refused_while_a_search_is_outstanding() {
    Case c("a hint refuses while any search is outstanding, is a search for "
           "the serialisation rule itself, and cancels like one");
    const fs::path store = scratch_dir("hint-in-progress");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget,
                                      &applied, &err),
                   MXQ_OK, "prepare");
    const uint32_t movetime = 4000; /* never allowed to finish */
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        std::string human_move;
        c.check(first_legal_move(game, human_move), "a legal human move");
        c.check_status(mxq_game_apply_move(game, human_move.c_str(), nullptr,
                                           nullptr, &err),
                       MXQ_OK, "human move applies");

        /* The AI's reply is outstanding: the hint would be answered against a
         * position that has moved on, so it is refused rather than queued. */
        MxqSearchRequest request = request_of(movetime);
        uint64_t reply = 0;
        c.check_status(mxq_search_start(core, game, &request, nullptr, nullptr,
                                        &reply, &err),
                       MXQ_OK, "the reply search starts");
        uint64_t hint = 1;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_DEEP_MS,
                                             nullptr, nullptr, &hint, &err),
                       MXQ_ERR_STATE_SEARCH_IN_PROGRESS,
                       "a hint while the reply is outstanding");
        c.check_eq(static_cast<int64_t>(hint), 0, "and no ticket was issued");

        c.check_status(mxq_search_cancel(core, reply, &err), MXQ_OK, "cancel");
        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, reply, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait out the cancellation");
        c.check_eq(ready, 1, "the cancelled reply was delivered");

        /* Now the hint is the outstanding search, and everything the facade
         * says about one holds for it. */
        Delivered delivered;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_DEEP_MS,
                                             record_callback, &delivered,
                                             &hint, &err),
                       MXQ_OK, "the hint starts once the reply has drained");
        uint64_t second = 1;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_DEEP_MS,
                                             nullptr, nullptr, &second, &err),
                       MXQ_ERR_STATE_SEARCH_IN_PROGRESS,
                       "a second hint while the first is outstanding");
        c.check_eq(static_cast<int64_t>(second), 0,
                   "and no ticket was issued for it either");
        err = make_error();
        c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI,
                                          &budget, &applied, &err),
                       MXQ_ERR_STATE_SEARCH_IN_PROGRESS,
                       "reconfiguration serialises behind a hint exactly as it "
                       "does behind a reply");

        MxqPosition before;
        std::memset(&before, 0, sizeof(before));
        before.struct_size = static_cast<uint32_t>(sizeof(before));
        c.check_status(mxq_game_position(game, &before, &err), MXQ_OK,
                       "position before the cancellation");
        c.check_status(mxq_search_cancel(core, hint, &err), MXQ_OK,
                       "cancel the hint");
        result = make_result();
        ready = 0;
        c.check_status(mxq_search_wait(core, hint, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the cancelled hint was delivered");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_CANCELLED,
                   "with the cancelled outcome");
        c.check(delivered.called.load(std::memory_order_acquire),
                "the cancelled callback still fired");
        c.check_eq(static_cast<int64_t>(delivered.result.outcome),
                   MXQ_SEARCH_CANCELLED, "the callback saw the cancellation");
        MxqPosition after;
        std::memset(&after, 0, sizeof(after));
        after.struct_size = static_cast<uint32_t>(sizeof(after));
        c.check_status(mxq_game_position(game, &after, &err), MXQ_OK,
                       "position after the cancellation");
        c.check_eq(static_cast<int64_t>(after.position_revision),
                   static_cast<int64_t>(before.position_revision),
                   "the cancelled hint left the game where it was");

        /* Teardown behaves: it is refused nowhere now, and the hint that
         * follows it is refused for the engine. */
        c.check_status(mxq_engine_teardown(core, &err), MXQ_OK,
                       "teardown once the hint has drained");
        uint64_t after_teardown = 1;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_FAST_MS,
                                             nullptr, nullptr, &after_teardown,
                                             &err),
                       MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "a hint after teardown refuses: the engine is not "
                       "prepared");
        c.check_eq(static_cast<int64_t>(after_teardown), 0,
                   "and issues no ticket");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_hint_refused_on_a_finished_game() {
    Case c("a game with a result of its own has no move to suggest, an "
           "archived one has none either, and a detached replay is refused for "
           "being one");
    const fs::path store = scratch_dir("hint-game-over");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget,
                                      &applied, &err),
                   MXQ_OK, "prepare");
    const MxqGameConfig config = hvai_config(120);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        /* The three-ply checkmate the session suite plays. */
        for (const char *move : {"b1b3", "a6a5", "b3d3"}) {
            c.check_status(mxq_game_apply_move(game, move, nullptr, nullptr,
                                               &err),
                           MXQ_OK, "the mating line applies");
        }
        MxqGameStatus over;
        std::memset(&over, 0, sizeof(over));
        over.struct_size = static_cast<uint32_t>(sizeof(over));
        c.check_status(mxq_game_status(game, &over, &err), MXQ_OK,
                       "the terminal status");
        c.check_eq(static_cast<int64_t>(over.state), MXQ_GAME_RED_WINS,
                   "the line really mates");

        uint64_t ticket = 1;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_FAST_MS,
                                             nullptr, nullptr, &ticket, &err),
                       MXQ_ERR_STATE_GAME_OVER,
                       "a hint on a finished game");
        c.check_eq(static_cast<int64_t>(ticket), 0, "and no ticket");

        /* And after the result is committed, the session is an immutable
         * History record: the same refusal every other post-ending call on the
         * handle makes. */
        uint64_t record_id = 0;
        err = make_error();
        c.check_status(mxq_game_confirm_result(game, &record_id, &err), MXQ_OK,
                       "confirm the result");
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_FAST_MS,
                                             nullptr, nullptr, &ticket, &err),
                       MXQ_ERR_STATE_SESSION_ARCHIVED,
                       "a hint on an archived session");

#if defined(NDEBUG)
        /* And the record opened for replay is refused for being a replay,
         * ahead of the result it also has: a hint needs a session that could
         * take the move it proposes, and a call needing a mutable session made
         * on a detached read-only one is one of the programming errors the
         * contract has assert in a debug build. The status is therefore
         * observable only where that assertion is compiled out — and nothing
         * offers a hint on a replay, which is what makes it one. */
        MxqGame *replay = nullptr;
        err = make_error();
        c.check_status(mxq_store_history_open(core, record_id, &replay, &err),
                       MXQ_OK, "the record opens as a replay");
        if (replay != nullptr) {
            uint64_t on_replay = 1;
            err = make_error();
            c.check_status(mxq_search_start_hint(core, replay,
                                                 MXQ_MOVETIME_FAST_MS, nullptr,
                                                 nullptr, &on_replay, &err),
                           MXQ_ERR_STATE_SESSION_READ_ONLY,
                           "a hint on a detached replay");
            c.check_eq(static_cast<int64_t>(on_replay), 0,
                       "and no ticket for it");
            mxq_game_release(replay);
        }
#endif
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_hint_on_a_claimable_repetition() {
    Case c("a claimable neutral repetition is not a result of its own, and the "
           "hint is answered there like in any other ongoing position");
    const fs::path store = scratch_dir("hint-claimable");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget,
                                      &applied, &err),
                   MXQ_OK, "prepare");
    const MxqGameConfig config = hvai_config(120);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        /* The shuffle the store suites reach claimability with: both chariots
         * out and back twice, so the starting position is on the board for the
         * third time. */
        for (const char *move : {"b1b3", "b7b5", "b3b1", "b5b7", "b1b3", "b7b5",
                                 "b3b1", "b5b7"}) {
            c.check_status(mxq_game_apply_move(game, move, nullptr, nullptr,
                                               &err),
                           MXQ_OK, "the shuffle applies");
        }
        MxqGameStatus claimable;
        std::memset(&claimable, 0, sizeof(claimable));
        claimable.struct_size = static_cast<uint32_t>(sizeof(claimable));
        c.check_status(mxq_game_status(game, &claimable, &err), MXQ_OK,
                       "the status of the repeated position");
        c.check_eq(static_cast<int64_t>(claimable.state),
                   MXQ_GAME_CLAIMABLE_DRAW,
                   "the line really does reach a claimable repetition");
        c.check_eq(claimable.claim_available, 1, "with the claim available");

        uint64_t ticket = 0;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_FAST_MS,
                                             nullptr, nullptr, &ticket, &err),
                       MXQ_OK,
                       "the hint is accepted: this game is ongoing, and the "
                       "claim is the player's to make or not");
        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the hint arrived");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_MOVE,
                   "the outcome is a move, not a refusal for a game that is "
                   "over");
        c.check(legal_here(game, result.move.text),
                std::string("the proposed move is in the side to move's legal "
                            "set, got: ") +
                    result.move.text);

        /* And the repetition is where it was: a hint decides nothing about the
         * claim, which is the player's. */
        MxqGameStatus after;
        std::memset(&after, 0, sizeof(after));
        after.struct_size = static_cast<uint32_t>(sizeof(after));
        c.check_status(mxq_game_status(game, &after, &err), MXQ_OK,
                       "the status after the hint");
        c.check_eq(static_cast<int64_t>(after.state), MXQ_GAME_CLAIMABLE_DRAW,
                   "the game is still the claimable repetition");
        c.check_eq(after.claim_available, 1, "and the claim is still there");
        c.check_eq(static_cast<int64_t>(stored_move_count(core)), 8,
                   "the store holds the shuffle and nothing the hint produced");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_hint_stale_after_a_move() {
    Case c("a hint answered for a position the game has left is rejected as "
           "stale, exactly as a reply is");
    const fs::path store = scratch_dir("hint-stale");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), staged_assets(), &core, &err),
                   MXQ_OK, "core init");
    if (core == nullptr) {
        c.report();
        return;
    }
    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_MINI_XIANGQI, &budget,
                                      &applied, &err),
                   MXQ_OK, "prepare");
    const MxqGameConfig config = hvai_config(120);
    MxqGame *game = nullptr;
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "game create");
    if (game != nullptr) {
        Delivered delivered;
        uint64_t ticket = 0;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_FAST_MS,
                                             record_callback, &delivered,
                                             &ticket, &err),
                       MXQ_OK, "hint start");

        /* The player takes the move rather than the hint — the accepted
         * dismissal — so the position the hint was asked about is gone. */
        std::this_thread::sleep_for(std::chrono::milliseconds(120));
        std::string played;
        c.check(first_legal_move(game, played), "a legal move to play");
        c.check_status(mxq_game_apply_move(game, played.c_str(), nullptr,
                                           nullptr, &err),
                       MXQ_OK, "the move applies while the hint is thinking");

        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the result was delivered");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_STALE,
                   "the outcome is stale");
        c.check_eq(static_cast<int64_t>(delivered.result.outcome),
                   MXQ_SEARCH_STALE, "the callback saw the staleness");
        c.check_eq(std::string(result.move.text), std::string(),
                   "and no move rode along with it");
        c.check_eq(static_cast<int64_t>(stored_move_count(core)), 1,
                   "the store holds the played move and nothing the hint "
                   "produced");
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

/* ---------------------------------------------------------------------- */
/* The variant axis                                                        */
/* ---------------------------------------------------------------------- */

/* The engine's own record for a variant: where its board dimensions and its
 * start position are decided, and the only honest source for either. */
const Stockfish::Variant *engine_variant(const char *id) {
    const auto found = Stockfish::variants.find(std::string(id));
    return found == Stockfish::variants.end() ? nullptr : found->second;
}

/* The smallest sufficient preparation, matching sufficient_budget()'s plan, so
 * that a bridge configuration here is the same configuration the facade makes.
 */
constexpr uint32_t kAxisThreads = 2;
constexpr uint32_t kAxisHashMib = 256;

mxq::engine::ConfigureError configure_for(mxq::engine::Variant variant,
                                          const std::string &assets,
                                          std::string &detail) {
    detail.clear();
    return mxq::engine::configure(variant, kAxisThreads, kAxisHashMib, assets,
                                  detail);
}

/*
 * The start axis through the whole path, once: create a Xiangqi Free Play
 * session from a composed position with Black to move, prepare, ask for a hint,
 * apply it, and encode.
 *
 * The hint is the assertion that matters and it needs no transcribed move to
 * make it. A search snapshots the session's start and its move line, so a build
 * that snapshotted the frozen array instead would search the opening array,
 * propose a move of it, and have that move refused by the delivery ladder's
 * legality rung — the outcome would be MXQ_SEARCH_REJECTED rather than a move
 * this position can take. Everything after it is the same session continuing:
 * Black made ply 0, so Red is to move, and the document the session encodes
 * carries the composed start back through the validator that judges one.
 */
void case_a_composed_start_through_search_and_the_archive() {
    Case c("a Xiangqi session composed from a position with Black to move is "
           "searched, moved and encoded from that position");
    const fs::path store = scratch_dir("composed-start");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(
        init_core(store.string(), staged_xiangqi_assets(), &core, &err), MXQ_OK,
        "core init against the two-network directory");
    if (core == nullptr) {
        c.report();
        return;
    }

    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    err = make_error();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_XIANGQI, &budget,
                                      &applied, &err),
                   MXQ_OK, "prepare for xiangqi");

    /* Black's chariot, cannon and soldier against Red's chariot and soldier,
     * with the two generals on one file and Red's soldier between them. A legal
     * setup, undecided, and Black's to move. */
    const char *const kScene = "4k4/9/7c1/1r7/9/3pP4/6R2/9/9/4K4 b - - 0 1";
    MxqGameConfig config = free_play_config(MXQ_GAME_KIND_XIANGQI);
    std::memcpy(config.start_fen, kScene, std::strlen(kScene) + 1);

    MxqGame *game = nullptr;
    err = make_error();
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "the scene is created");
    if (game != nullptr) {
        MxqPosition before;
        std::memset(&before, 0, sizeof(before));
        before.struct_size = static_cast<uint32_t>(sizeof(before));
        c.check_status(mxq_game_position(game, &before, &err), MXQ_OK,
                       "the scene's position");
        c.check_eq(std::string(before.fen), std::string(kScene),
                   "the session begins from the composed position");
        c.check_eq(before.side_to_move, MXQ_COLOR_BLACK,
                   "whose move ply 0 is");
        c.check_eq(before.ply_count, 0, "no ply has been played");

        uint64_t ticket = 0;
        err = make_error();
        c.check_status(mxq_search_start_hint(core, game, MXQ_MOVETIME_FAST_MS,
                                             nullptr, nullptr, &ticket, &err),
                       MXQ_OK, "hint start on the scene");
        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the hint arrived");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_MOVE,
                   "the outcome is a move, which it is only if the search "
                   "snapshotted this session's own start");

        MxqPosition after;
        std::memset(&after, 0, sizeof(after));
        after.struct_size = static_cast<uint32_t>(sizeof(after));
        MxqGameStatus status;
        std::memset(&status, 0, sizeof(status));
        status.struct_size = static_cast<uint32_t>(sizeof(status));
        err = make_error();
        c.check_status(mxq_game_apply_move(game, result.move.text, &after,
                                           &status, &err),
                       MXQ_OK,
                       std::string("the proposed move applies, got: ") +
                           result.move.text);
        c.check_eq(after.side_to_move, MXQ_COLOR_RED,
                   "Black having made ply 0, Red answers it");
        c.check_eq(status.side_to_move, MXQ_COLOR_RED,
                   "and the status says so too");
        c.check_eq(status.undo_plies, 1,
                   "Free Play takes one ply back, counted from the start's own "
                   "side");

        /* And the document, through the validator that judges a start. */
        MxqBlob *blob = nullptr;
        err = make_error();
        c.check_status(mxq_archive_encode(core, game, &blob, &err), MXQ_OK,
                       "the session encodes");
        if (blob != nullptr) {
            MxqArchiveInfo info;
            std::memset(&info, 0, sizeof(info));
            info.struct_size = static_cast<uint32_t>(sizeof(info));
            err = make_error();
            c.check_status(mxq_archive_validate(core, mxq_blob_bytes(blob),
                                                mxq_blob_len(blob), &info,
                                                &err),
                           MXQ_OK,
                           "and validates, composed start and all");
            c.check_eq(static_cast<int64_t>(info.game), MXQ_GAME_KIND_XIANGQI,
                       "as the game it names");
            c.check_eq(static_cast<int64_t>(info.move_count), 1,
                       "carrying the one ply played");
            mxq_blob_release(blob);
        }
        mxq_game_release(game);
    }
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_xiangqi_searches_under_its_own_network() {
    Case c("built-in xiangqi prepares under the xiangqi network, from a "
           "directory holding both, and searches its 9x10 board");
    const fs::path store = scratch_dir("xiangqi-search");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(
        init_core(store.string(), staged_xiangqi_assets(), &core, &err), MXQ_OK,
        "core init against the two-network directory");
    if (core == nullptr) {
        c.report();
        return;
    }

    /* The board this case claims to search, from the engine rather than from
     * this file. Without LARGEBOARDS the engine does not register the variant
     * at all, and the axis would have one working end. */
    const Stockfish::Variant *xiangqi = engine_variant(kXiangqiVariantId);
    c.check(xiangqi != nullptr,
            std::string("the engine registers ") + kXiangqiVariantId);
    if (xiangqi != nullptr) {
        c.check_eq(static_cast<int64_t>(xiangqi->maxFile) + 1, 9,
                   "nine files");
        c.check_eq(static_cast<int64_t>(xiangqi->maxRank) + 1, 10,
                   "ten ranks");
    }

    std::string detail;
    const mxq::engine::ConfigureError rc = configure_for(
        mxq::engine::Variant::Xiangqi, staged_xiangqi_assets(), detail);
    c.check(rc == mxq::engine::ConfigureError::None,
            "configure for xiangqi: " + detail);

    if (rc == mxq::engine::ConfigureError::None && xiangqi != nullptr) {
        const std::string xiangqi_network =
            (fs::path(staged_xiangqi_assets()) / kXiangqiNetworkName).string();
        const std::string app_network =
            (fs::path(staged_xiangqi_assets()) / kBundledNetworkName).string();

        c.check_eq(std::string(Stockfish::Options["UCI_Variant"]),
                   kXiangqiVariantId, "the engine's variant option");
        c.check(mxq::engine::active_variant() ==
                    mxq::engine::Variant::Xiangqi,
                "the bridge's active variant is the one it was configured for");
        c.check(Stockfish::Eval::useNNUE,
                "the engine's effective NNUE state is on — the internal flag, "
                "not the option, and classical evaluation is what its absence "
                "would silently mean");
        c.check_eq(Stockfish::Eval::eval_file_loaded, xiangqi_network,
                   "the network the engine actually read is the xiangqi one");

        /* EvalFile is the joined list, and the active variant's network leads
         * it: the engine selects the first token whose basename matches, so
         * leading with it is what makes the preflight's SELECTED token and the
         * engine's own choice the same string by construction. */
        const std::string eval_file =
            std::string(Stockfish::Options["EvalFile"]);
        c.check(eval_file.find(Stockfish::UCI::SepChar) != std::string::npos,
                "EvalFile is a list rather than a path, got: " + eval_file);
        c.check(eval_file.find(app_network) != std::string::npos,
                "the app's network is in the list too, got: " + eval_file);
        c.check(eval_file.rfind(xiangqi_network, 0) == 0,
                "the active variant's network leads the list, got: " +
                    eval_file);

        /* Searching the whole option value would not have discriminated,
         * which is why the loaded name is compared above rather than looked
         * for: the list holds both networks, so the other variant's name is a
         * substring of it too — exactly what the engine's own verification
         * asks, and exactly why the preflight asks something else. */

        std::atomic<bool> cancelled{false};
        mxq::engine::SearchOutput out;
        detail.clear();
        const mxq::engine::SearchError ran = mxq::engine::search_run(
            xiangqi->startFen, {}, 250, cancelled, out, detail);
        c.check(ran == mxq::engine::SearchError::None,
                "a search from the xiangqi start position completes: " +
                    detail);
        c.check(out.nodes > 0, "nodes were searched");
        c.check(out.depth > 0, "a depth was reached");

        /* That the move belongs to the nine-by-ten board is asked the only way
         * that cannot restate the implementation, and the only way a character
         * bound does not answer — a move of the app's seven-file board is
         * inside any bound the wider board admits: replaying it. A move of the
         * wrong board does not parse, and search_run says so rather than
         * searching on. */
        mxq::engine::SearchOutput after;
        detail.clear();
        const mxq::engine::SearchError replayed = mxq::engine::search_run(
            xiangqi->startFen, {out.move}, 250, cancelled, after, detail);
        c.check(replayed == mxq::engine::SearchError::None,
                "the proposed move replays as legal in the position it was "
                "found in: " + detail);
    }

    mxq::engine::deconfigure();
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_teardown_returns_the_bridge_to_the_app_variant() {
    Case c("a teardown after the other variant restores the app's variant, and "
           "preparing it again is the shipped one-network shape");
    const fs::path store = scratch_dir("xiangqi-restore");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(
        init_core(store.string(), staged_xiangqi_assets(), &core, &err), MXQ_OK,
        "core init");
    if (core == nullptr) {
        c.report();
        return;
    }

    std::string detail;
    c.check(configure_for(mxq::engine::Variant::Xiangqi,
                          staged_xiangqi_assets(),
                          detail) == mxq::engine::ConfigureError::None,
            "configure for xiangqi: " + detail);

    /* The rules posture is not "whatever the last configuration left". A
     * teardown that kept the other variant's tables would leave every legality
     * answer this core gives being answered on a nine-by-ten board. */
    mxq::engine::deconfigure();
    c.check(mxq::engine::active_variant() ==
                mxq::engine::Variant::MiniXiangqi,
            "the bridge is back on the app's variant");
    c.check_eq(std::string(Stockfish::Options["UCI_Variant"]), kVariantId,
               "and so is the engine");
    c.check(!Stockfish::TT.allocated(),
            "the transposition table is released whole");

    char fen[MXQ_FEN_CAP];
    size_t fen_len = 0;
    c.check_status(mxq_rules_start_fen(MXQ_GAME_KIND_MINI_XIANGQI, fen, sizeof(fen), &fen_len, &err),
                   MXQ_OK, "start fen");
    MxqPosition position;
    std::memset(&position, 0, sizeof(position));
    position.struct_size = static_cast<uint32_t>(sizeof(position));
    MxqGameStatus status;
    std::memset(&status, 0, sizeof(status));
    status.struct_size = static_cast<uint32_t>(sizeof(status));
    c.check_status(mxq_rules_evaluate(core, MXQ_GAME_KIND_MINI_XIANGQI, fen, nullptr, 0, &position, &status,
                                      nullptr, &err),
                   MXQ_OK, "the app's rules answer after the other variant");
    c.check_eq(static_cast<int64_t>(status.state), MXQ_GAME_ONGOING,
               "the start position is ongoing");

    /* And the shipped directory still configures the shipped way: one network,
     * no list, the same loaded name it has always had. */
    detail.clear();
    c.check(configure_for(mxq::engine::Variant::MiniXiangqi, staged_assets(),
                          detail) == mxq::engine::ConfigureError::None,
            "configure for the app's variant from the one-network directory: " +
                detail);
    const std::string app_network =
        (fs::path(staged_assets()) / kBundledNetworkName).string();
    c.check_eq(std::string(Stockfish::Options["EvalFile"]), app_network,
               "one network in the directory is one path in EvalFile");
    c.check_eq(Stockfish::Eval::eval_file_loaded, app_network,
               "and it is what the engine loaded");
    c.check(Stockfish::Eval::useNNUE, "with NNUE effective");

    const Stockfish::Variant *app_variant = engine_variant(kVariantId);
    c.check(app_variant != nullptr,
            std::string("the configuration defines ") + kVariantId);
    if (app_variant != nullptr) {
        c.check_eq(static_cast<int64_t>(app_variant->maxFile) + 1, 7,
                   "the app's board is seven files wide again");
        std::atomic<bool> cancelled{false};
        mxq::engine::SearchOutput out;
        detail.clear();
        c.check(mxq::engine::search_run(app_variant->startFen, {}, 250,
                                        cancelled, out, detail) ==
                    mxq::engine::SearchError::None,
                "the app's variant still searches: " + detail);
        c.check(mxq::notation::well_formed_move(MXQ_GAME_KIND_MINI_XIANGQI,
                                                out.move),
                "and its move is in the app's own notation, got: " + out.move);
    }

    mxq::engine::deconfigure();
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_direct_variant_switch_without_a_teardown() {
    Case c("configuring one variant straight after the other, with no teardown "
           "between, selects the new variant's network from the list the "
           "previous configuration left");
    const fs::path store = scratch_dir("variant-switch");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(
        init_core(store.string(), staged_xiangqi_assets(), &core, &err), MXQ_OK,
        "core init against the two-network directory");
    if (core == nullptr) {
        c.report();
        return;
    }

    /*
     * The shape the other variant cases do not reach. Each of them ends with a
     * deconfigure(), whose variant restore is conditional and whose option
     * floor rewrites EvalFile's neighbours; this one goes straight from one
     * configuration to the other, so at the moment UCI_Variant changes the
     * engine is still holding the PREVIOUS variant's EvalFile list and the
     * previous variant's loaded network. What must happen is that assigning
     * UCI_Variant re-runs the engine's NNUE initialisation and selects, from
     * that stale list, the token whose basename begins with the new variant's
     * identifier — which is why configure() can preflight the effective state
     * afterwards and mean it.
     *
     * The failure this pins is silent by construction: the engine leaves
     * eval_file_loaded naming whatever loaded last, so a switch that did not
     * reselect would keep searching the new variant's board with the old
     * variant's network and report Use NNUE true throughout.
     */
    const std::string mini_network =
        (fs::path(staged_xiangqi_assets()) / kBundledNetworkName).string();
    const std::string xiangqi_network =
        (fs::path(staged_xiangqi_assets()) / kXiangqiNetworkName).string();

    std::string detail;
    c.check(configure_for(mxq::engine::Variant::MiniXiangqi,
                          staged_xiangqi_assets(),
                          detail) == mxq::engine::ConfigureError::None,
            "configure for the app's variant first: " + detail);
    c.check_eq(Stockfish::Eval::eval_file_loaded, mini_network,
               "the app's network is what is loaded");

    detail.clear();
    c.check(configure_for(mxq::engine::Variant::Xiangqi,
                          staged_xiangqi_assets(),
                          detail) == mxq::engine::ConfigureError::None,
            "and then for xiangqi, with no teardown between: " + detail);
    c.check(mxq::engine::active_variant() == mxq::engine::Variant::Xiangqi,
            "the bridge is on xiangqi");
    c.check_eq(std::string(Stockfish::Options["UCI_Variant"]),
               kXiangqiVariantId, "and so is the engine");
    c.check_eq(Stockfish::Eval::eval_file_loaded, xiangqi_network,
               "the xiangqi network is what is loaded now");
    c.check(Stockfish::Eval::useNNUE, "with NNUE effective");

    /* And back, the same way: the switch is not one-directional, and the
     * app's variant is the one a real session returns to. */
    detail.clear();
    c.check(configure_for(mxq::engine::Variant::MiniXiangqi,
                          staged_xiangqi_assets(),
                          detail) == mxq::engine::ConfigureError::None,
            "and back to the app's variant, still with no teardown: " + detail);
    c.check_eq(Stockfish::Eval::eval_file_loaded, mini_network,
               "the app's network is loaded again");

    /* The tables followed the variant, not only the option: a search here is
     * the app's board, in the app's notation. */
    const Stockfish::Variant *app_variant = engine_variant(kVariantId);
    c.check(app_variant != nullptr,
            std::string("the configuration defines ") + kVariantId);
    if (app_variant != nullptr) {
        std::atomic<bool> cancelled{false};
        mxq::engine::SearchOutput out;
        detail.clear();
        c.check(mxq::engine::search_run(app_variant->startFen, {}, 250,
                                        cancelled, out, detail) ==
                    mxq::engine::SearchError::None,
                "the app's variant searches after two switches: " + detail);
        c.check(mxq::notation::well_formed_move(MXQ_GAME_KIND_MINI_XIANGQI,
                                                out.move),
                "and its move is in the app's own notation, got: " + out.move);
    }

    mxq::engine::deconfigure();
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_cross_loaded_network_is_refused_by_its_own_pin() {
    Case c("a network staged under the other variant's name is refused by that "
           "variant's byte pin, before the engine sees it");
    /* The two networks are structurally different — different feature
     * dimensions, four megabytes against eleven — so one loaded for the other
     * variant is not a weaker opponent, it is a load that fails and leaves the
     * engine's network zeroed. It never gets that far: the pins are per
     * variant, and the file is checked against the pins of the variant whose
     * name it carries. Pinning both networks to one byte length and one hash
     * would pass everything else in this suite and fail here. */
    const std::string app_bytes =
        read_file(fs::path(staged_assets()) / kBundledNetworkName);
    c.check_eq(static_cast<int64_t>(app_bytes.size()), kBundledNetworkBytes,
               "the staged app network is the length its pin gives");

    const fs::path assets =
        stage_assets("cross-loaded", kXiangqiNetworkName, &app_bytes);
    const fs::path store = scratch_dir("cross-loaded-store");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), assets.string(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        std::string detail;
        c.check(configure_for(mxq::engine::Variant::Xiangqi, assets.string(),
                              detail) ==
                    mxq::engine::ConfigureError::AssetMismatch,
                "configure for xiangqi refuses: " + detail);
        c.check(detail.find(std::to_string(kXiangqiNetworkBytes)) !=
                    std::string::npos,
                std::string("the detail quotes the xiangqi pin rather than the "
                            "app's, got: ") +
                    detail);
        c.check(detail.find(kXiangqiVariantId) != std::string::npos,
                std::string("and names the variant whose pin refused, got: ") +
                    detail);
        c.check(!Stockfish::TT.allocated(),
                "nothing was configured: the refusal is before the engine");
        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

void case_xiangqi_wrong_basename_network() {
    Case c("the pinned xiangqi bytes under a basename that does not begin with "
           "the variant identifier fail the effective-NNUE preflight");
    /* The same trap as the app's variant, for the second one. This network is
     * not this project's own, so the plausible rename is to whoever trained
     * it — and the engine would answer that rename by playing xiangqi on
     * classical evaluation without a word. A preflight wired to the app's
     * variant alone passes every other case in this suite and fails here. */
    const std::string xiangqi_bytes =
        read_file(fs::path(staged_xiangqi_assets()) / kXiangqiNetworkName);
    c.check_eq(static_cast<int64_t>(xiangqi_bytes.size()),
               kXiangqiNetworkBytes,
               "the staged xiangqi network is the length its pin gives");

    const std::string wrong_name =
        "pikafish" + std::string(kXiangqiNetworkName)
                         .substr(std::strlen(kXiangqiVariantId));
    c.check(!wrong_name.starts_with(kXiangqiVariantId) &&
                wrong_name.size() > std::strlen(kXiangqiVariantId),
            std::string("the staged name does NOT begin with the configured "
                        "variant identifier, which is the whole provocation, "
                        "got: ") +
                wrong_name);

    const fs::path assets = stage_assets("xiangqi-wrong-basename",
                                         wrong_name.c_str(), &xiangqi_bytes);
    const fs::path store = scratch_dir("xiangqi-wrong-basename-store");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), assets.string(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        std::string detail;
        c.check(configure_for(mxq::engine::Variant::Xiangqi, assets.string(),
                              detail) ==
                    mxq::engine::ConfigureError::AssetMismatch,
                "configure for xiangqi refuses: " + detail);
        c.check(detail.find("effective NNUE state") != std::string::npos,
                std::string("the detail names the effective state — the bytes "
                            "and the hash were both right, got: ") +
                    detail);
        c.check(!Stockfish::Eval::useNNUE,
                "the engine's internal NNUE flag really was cleared — the trap "
                "this preflight exists for, on the second variant too");
        c.check(!Stockfish::TT.allocated(), "the unwind released the table");
        c.check(mxq::engine::active_variant() ==
                    mxq::engine::Variant::MiniXiangqi,
                "the unwind also put the bridge back on the app's variant");
        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

/*
 * The two cases below reach the second variant through the public surface
 * rather than through the bridge, which is what every other case in this
 * section does. Nothing else asserts that mxq_engine_prepare accepts the other
 * game at all, that a session of it searches, or what a caller is told when the
 * engine is prepared for the game they are not playing.
 */

void case_the_c_surface_prepares_the_other_game() {
    Case c("the C surface prepares the engine for the other game and a session "
           "of it searches; before any preparation the refusal reports that "
           "rather than naming a preparation that never happened");
    const fs::path store = scratch_dir("xiangqi-c-surface");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(
        init_core(store.string(), staged_xiangqi_assets(), &core, &err), MXQ_OK,
        "core init against the two-network directory");
    if (core == nullptr) {
        c.report();
        return;
    }

    const uint32_t movetime = 120;
    const MxqGameConfig config = hvai_config(movetime, MXQ_GAME_KIND_XIANGQI);
    MxqGame *game = nullptr;
    err = make_error();
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "a session of the other game");
    if (game != nullptr) {
        std::string human_move;
        c.check(first_legal_move(game, human_move),
                "a legal human move on the other game's board");
        MxqGameStatus status;
        std::memset(&status, 0, sizeof(status));
        status.struct_size = static_cast<uint32_t>(sizeof(status));
        err = make_error();
        c.check_status(mxq_game_apply_move(game, human_move.c_str(), nullptr,
                                           &status, &err),
                       MXQ_OK, "the human move applies");
        c.check_eq(status.search_expected, 1, "a search is expected");

        /* Nothing has been prepared. The engine's variant is the rules
         * posture's, which is the app's — so the cross-game comparison is
         * true here as well, and what the caller must be told is the one they
         * can act on. */
        MxqSearchRequest request = request_of(movetime);
        uint64_t ticket = 0;
        err = make_error();
        c.check_status(mxq_search_start(core, game, &request, nullptr, nullptr,
                                        &ticket, &err),
                       MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "a search before any preparation");
        const std::string unprepared(err.detail);
        c.check(unprepared.find("not prepared") != std::string::npos,
                "the detail reports that the engine is not prepared, got: " +
                    unprepared);
        c.check(unprepared.find("other game") == std::string::npos,
                "and does not report a preparation for the other game, got: " +
                    unprepared);

        const MxqEngineBudget budget = sufficient_budget();
        MxqEnginePlan applied = make_plan();
        err = make_error();
        c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_XIANGQI, &budget,
                                          &applied, &err),
                       MXQ_OK, "prepare for the other game");
        c.check_eq(applied.sufficient, 1, "the applied plan is sufficient");

        MxqEngineState state = MXQ_ENGINE_STATE_UNINITIALIZED;
        char profile[MXQ_PROFILE_ID_CAP];
        size_t profile_len = 0;
        err = make_error();
        c.check_status(mxq_engine_query(core, &state, profile, sizeof(profile),
                                        &profile_len, &err),
                       MXQ_OK, "engine query");
        c.check_eq(static_cast<int64_t>(state), MXQ_ENGINE_STATE_READY,
                   "state after preparing the other game");
        /* The app's variant identifier ends with the built-in one, so the
         * separators are what make this a field comparison rather than a
         * substring both would satisfy. */
        c.check(std::string(profile).find(std::string("-") +
                                          kXiangqiVariantId + "-") !=
                    std::string::npos,
                std::string("the profile names the prepared game's variant, "
                            "got: ") +
                    profile);

        err = make_error();
        c.check_status(mxq_search_start(core, game, &request, nullptr, nullptr,
                                        &ticket, &err),
                       MXQ_OK, "search start on the other game's session");
        MxqSearchResult result = make_result();
        uint8_t ready = 0;
        err = make_error();
        c.check_status(mxq_search_wait(core, ticket, 20000, &result, &ready,
                                       &err),
                       MXQ_OK, "wait");
        c.check_eq(ready, 1, "the result arrived");
        c.check_eq(static_cast<int64_t>(result.outcome), MXQ_SEARCH_MOVE,
                   "the outcome is a move");
        c.check_eq(std::string(result.profile_id), std::string(profile),
                   "the result is attributed to the configuration it ran in");
        c.check(mxq::notation::well_formed_move(MXQ_GAME_KIND_XIANGQI,
                                                std::string(result.move.text)),
                std::string("the move is in the other game's notation, got: ") +
                    result.move.text);

        /* And the session takes it, which is what makes it a move of this
         * board rather than a string that parses as one. */
        err = make_error();
        c.check_status(mxq_game_apply_move(game, result.move.text, nullptr,
                                           &status, &err),
                       MXQ_OK, "the session accepts the move it was given");
        mxq_game_release(game);
    }

    c.check_status(mxq_engine_teardown(core, nullptr), MXQ_OK, "teardown");
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_a_session_of_the_unprepared_game_is_refused() {
    Case c("a search on a session of the game the engine is not prepared for "
           "is refused, and the detail names the preparation that does exist");
    const fs::path store = scratch_dir("cross-game-refusal");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(
        init_core(store.string(), staged_xiangqi_assets(), &core, &err), MXQ_OK,
        "core init against the two-network directory");
    if (core == nullptr) {
        c.report();
        return;
    }

    const MxqEngineBudget budget = sufficient_budget();
    MxqEnginePlan applied = make_plan();
    err = make_error();
    c.check_status(mxq_engine_prepare(core, MXQ_GAME_KIND_XIANGQI, &budget,
                                      &applied, &err),
                   MXQ_OK, "prepare for the other game");

    const uint32_t movetime = 120;
    const MxqGameConfig config = hvai_config(movetime);
    MxqGame *game = nullptr;
    err = make_error();
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "a session of the app's game");
    if (game != nullptr) {
        std::string human_move;
        c.check(first_legal_move(game, human_move), "a legal human move");
        MxqGameStatus status;
        std::memset(&status, 0, sizeof(status));
        status.struct_size = static_cast<uint32_t>(sizeof(status));
        err = make_error();
        c.check_status(mxq_game_apply_move(game, human_move.c_str(), nullptr,
                                           &status, &err),
                       MXQ_OK, "the human move applies");
        c.check_eq(status.search_expected, 1, "a search is expected");

        MxqSearchRequest request = request_of(movetime);
        uint64_t ticket = 0;
        err = make_error();
        c.check_status(mxq_search_start(core, game, &request, nullptr, nullptr,
                                        &ticket, &err),
                       MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "a search for the game the engine is not prepared for");
        const std::string refusal(err.detail);
        c.check(refusal.find("other game") != std::string::npos,
                "the detail names the preparation that exists rather than "
                "reporting none, got: " + refusal);
        mxq_game_release(game);
    }

    c.check_status(mxq_engine_teardown(core, nullptr), MXQ_OK, "teardown");
    mxq_core_shutdown(core, nullptr);
    c.report();
}

#endif /* MXQ_TEST_RULES_FACADE */

} /* namespace */

int main() {
    std::cout << "Mini Xiangqi search-facade tests\n"
              << "  rules facade    "
              << (MXQ_TEST_RULES_FACADE
                      ? "available; the search facade is in this build"
                      : "ABSENT; the search facade is not in this build")
              << "\n";
#if MXQ_TEST_RULES_FACADE
    std::cout << "  staged assets   " << staged_assets() << "\n\n";
#if !MXQ_TEST_NNUE_STAGED
    /* Never a silent skip: an engine build without its verified network
     * cannot prove the one chain these tests exist to prove. */
    Case unstaged("the staged NNUE network");
    unstaged.check(false, MXQ_TEST_NNUE_PROBLEM);
    unstaged.report();
#else
    /* First, before anything loads the real configuration into the engine's
     * process-global variant table: see the case's comment. */
    case_variant_load_failure();

    /* Before any core exists, and it must be: that is its whole claim. The
     * position rather than the order is what looks wrong here — the case
     * above creates no core, and every case below creates one. */
    case_game_profile();
    /* And the identifier composed from it, which is the other thing no core
     * has to exist for. */
    case_expected_profile_id();

    case_query_before_prepare();
    case_prepare_applies_the_plan();
    case_expected_profile_matches_the_prepared_one();
#if MXQ_TEST_GOMOKU_FACADE
    case_preparing_one_engine_releases_the_other();
#endif
    case_insufficient_memory_initialises_nothing();
    case_missing_network();
    case_wrong_basename_network();
    case_corrupt_network();

    case_search_end_to_end();
    case_free_play_owes_no_search();
    case_cancel_before_completion();
    case_undo_while_thinking_is_stale();
    case_released_origin_is_stale_even_when_identity_recurs();
    case_released_origin_without_replacement_is_stale();
    case_no_move_on_a_terminal_position_is_failed();
    case_reconfiguration_refused_mid_search();
    case_core_cancel_all_quiesces();
    case_shutdown_mid_search();

    case_hint_in_human_versus_ai();
    case_hint_in_free_play();
    case_hint_movetime_is_a_level_or_this_game_s_own();
    case_hint_refused_while_a_search_is_outstanding();
    case_hint_refused_on_a_finished_game();
    case_hint_on_a_claimable_repetition();
    case_hint_stale_after_a_move();

    /* The variant axis last: these are the only cases that leave the engine's
     * process-global variant tables anywhere but the app's variant, and each
     * of them puts them back before it returns. Running them after everything
     * else means no case above can depend on that being true.
     *
     * The two that reach the axis through the C surface come first, so that
     * the facade's own view of the engine and the bridge's are still the same
     * one when they run: the cases after them configure the bridge directly,
     * which the facade does not see. */
    case_the_c_surface_prepares_the_other_game();
    case_a_session_of_the_unprepared_game_is_refused();
    case_a_composed_start_through_search_and_the_archive();

    case_xiangqi_searches_under_its_own_network();
    case_teardown_returns_the_bridge_to_the_app_variant();
    case_direct_variant_switch_without_a_teardown();
    case_cross_loaded_network_is_refused_by_its_own_pin();
    case_xiangqi_wrong_basename_network();
#endif

    std::error_code cleanup;
    fs::remove_all(scratch_root(), cleanup);
#else
    std::cout << "\n";
    Case skipped("the search facade");
    skipped.skip("the mxq_engine_ and mxq_search_ functions need the rules "
                 "facade");
    skipped.report();
#endif

    const int total = g_passed + g_failed + g_skipped;
    std::cout << "\n"
              << total << " cases: " << g_passed << " passed, " << g_failed
              << " failed, " << g_skipped << " skipped\n"
              << g_checks << " expectations evaluated\n";
    if (g_skipped > 0) {
        std::cout << "\nNOT IMPLEMENTED: the search facade is not in this "
                     "build. Build with -DMXQ_ENABLE_RULES_FACADE=ON to "
                     "evaluate it.\n";
    }
    return g_failed > 0 ? 1 : 0;
}
