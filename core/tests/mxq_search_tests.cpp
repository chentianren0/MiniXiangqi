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
 * basename is the SOURCE name rather than the bundled one, the engine clears
 * its internal NNUE flag silently while the Use NNUE option still reads true,
 * and only the effective-state preflight stands between that and an opponent
 * silently playing on classical evaluation.
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
 * under its bundled name, placed by the build after verifying the bytes. */
std::string staged_assets() {
    if (const char *env = std::getenv("MXQ_TEST_ASSETS_DIR")) {
        return env;
    }
    return MXQ_TEST_ASSETS_DIR;
}

constexpr const char *kBundledNetworkName = "minixiangqiaxf-12c45d5da817.nnue";
constexpr const char *kSourceNetworkName = "minixiangqi-12c45d5da817.nnue";
constexpr const char *kVariantIniName = "minixiangqi-variants.ini";

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

MxqGameConfig hvai_config(uint32_t movetime_ms) {
    MxqGameConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.mode = MXQ_PLAY_MODE_HUMAN_VS_AI;
    config.human_side = MXQ_COLOR_RED;
    config.ai_level = MXQ_AI_LEVEL_FAST;
    config.first_mover_choice = MXQ_FIRST_MOVER_HUMAN_FIRST;
    config.ai_movetime_ms = movetime_ms;
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

/* The first legal move in the session's current position. */
bool first_legal_move(const MxqGame *game, std::string &out) {
    MxqMove moves[64];
    for (auto &m : moves) {
        m.struct_size = static_cast<uint32_t>(sizeof(MxqMove));
    }
    size_t count = 0;
    if (mxq_game_legal_moves(game, moves, 64, &count, nullptr) != MXQ_OK ||
        count == 0) {
        return false;
    }
    out = moves[0].text;
    return true;
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
        c.check_status(mxq_engine_prepare(core, &budget, &applied, &err),
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
        c.check_eq(std::string(Stockfish::Options["MultiPV"]), "1", "MultiPV");
        c.check_eq(std::string(Stockfish::Options["UCI_LimitStrength"]),
                   "false", "UCI_LimitStrength");
        c.check_eq(std::string(Stockfish::Options["Ponder"]), "false",
                   "Ponder");

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
        c.check_status(mxq_rules_start_fen(fen, sizeof(fen), &fen_len, &err),
                       MXQ_OK, "start fen");
        MxqPosition position;
        std::memset(&position, 0, sizeof(position));
        position.struct_size = static_cast<uint32_t>(sizeof(position));
        MxqGameStatus status;
        std::memset(&status, 0, sizeof(status));
        status.struct_size = static_cast<uint32_t>(sizeof(status));
        c.check_status(mxq_rules_evaluate(core, fen, nullptr, 0, &position,
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
        c.check_status(mxq_engine_prepare(core, &budget, &applied, &err),
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
        c.check_status(mxq_engine_prepare(core, &budget, &applied, &err),
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
    Case c("the pinned bytes under the source basename fail the "
           "effective-NNUE preflight, not the byte preflight");
    /* The realistic packaging failure: the bytes are exactly the pinned
     * network — length and hash both pass — but the file kept its source
     * name, which does not begin with the variant identifier. */
    const std::string bytes =
        read_file(fs::path(staged_assets()) / kBundledNetworkName);
    const fs::path assets =
        stage_assets("wrong-basename", kSourceNetworkName, &bytes);
    const fs::path store = scratch_dir("wrong-basename-store");
    MxqError err = make_error();
    MxqCore *core = nullptr;
    c.check_status(init_core(store.string(), assets.string(), &core, &err),
                   MXQ_OK, "core init");
    if (core != nullptr) {
        const MxqEngineBudget budget = sufficient_budget();
        MxqEnginePlan applied = make_plan();
        err = make_error();
        c.check_status(mxq_engine_prepare(core, &budget, &applied, &err),
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
        c.check_status(mxq_engine_prepare(core, &budget, &applied, &err),
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
            c.check_status(mxq_engine_prepare(core, &budget, &applied, &err),
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

    char fen[MXQ_FEN_CAP];
    size_t len = 0;
    probe->start_fen_status =
        mxq_rules_start_fen(fen, sizeof(fen), &len, nullptr);

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
    c.check_status(mxq_engine_prepare(core, &budget, &applied, &err), MXQ_OK,
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

        /* Gone after shutdown: the handle no longer answers at all. */
        mxq_core_shutdown(core, nullptr);
        ready = 1;
        MxqSearchResult gone = make_result();
        const MxqStatus dead =
            mxq_search_poll(core, second_ticket, &gone, &ready, nullptr);
        c.check(dead != MXQ_OK,
                "after shutdown the ticket answers an error, not a result");
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
        c.check_status(mxq_engine_prepare(core, &budget, &applied, &err),
                       MXQ_OK, "prepare");
        MxqGameConfig config;
        std::memset(&config, 0, sizeof(config));
        config.struct_size = static_cast<uint32_t>(sizeof(config));
        config.mode = MXQ_PLAY_MODE_FREE_PLAY;
        config.human_side = MXQ_COLOR_NONE;
        config.ai_level = MXQ_AI_LEVEL_NONE;
        config.first_mover_choice = MXQ_FIRST_MOVER_NONE;
        config.ai_movetime_ms = 0;
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
    c.check_status(mxq_engine_prepare(core, &budget, &applied, &err), MXQ_OK,
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
    c.check_status(mxq_engine_prepare(core, &budget, &applied, &err), MXQ_OK,
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
    c.check_status(mxq_engine_prepare(core, &budget, &applied, &err), MXQ_OK,
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
        c.check_status(mxq_engine_prepare(core, &budget, &applied, &err),
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
        MxqMove moves[64];
        size_t count = 0;
        c.check_status(mxq_game_legal_moves(game, moves, 64, &count, &err),
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
    c.check_status(mxq_engine_prepare(core, &budget, &applied, &err), MXQ_OK,
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
    c.check_status(mxq_engine_prepare(core, &budget, &applied, &err), MXQ_OK,
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

    case_query_before_prepare();
    case_prepare_applies_the_plan();
    case_insufficient_memory_initialises_nothing();
    case_missing_network();
    case_wrong_basename_network();
    case_corrupt_network();

    case_search_end_to_end();
    case_free_play_owes_no_search();
    case_cancel_before_completion();
    case_undo_while_thinking_is_stale();
    case_reconfiguration_refused_mid_search();
    case_core_cancel_all_quiesces();
    case_shutdown_mid_search();
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
