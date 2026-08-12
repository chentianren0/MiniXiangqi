/*
 * The second engine's bridge runner: preparation with its three preflights,
 * search under each of the two games, cancellation, the rules switch, and
 * teardown.
 *
 * It drives the bridge directly rather than a public C entry point, and that is
 * not a shortcut — at this stage there is no public entry point to drive. The
 * game vocabulary the C surface speaks names two games and neither of them is
 * played on this engine; widening it is a coordinated change of its own, with an
 * ABI decision, a placement move grammar and a store constraint inside it. So
 * the bridge is where this engine is offered, and a capability offered nowhere
 * else is asserted where it is offered or nowhere at all. The precedent is the
 * first engine's own runner, which reaches past the C surface for exactly the
 * same reason on the variant axis.
 *
 * It links the vendored engine directly, and deliberately: "the effective
 * evaluator is the pinned network, not classical", "the transposition table was
 * released whole", and "the thread count is the one the plan asked for" are
 * claims about the engine's own globals, and a runner that asked the bridge to
 * report on itself would test the report rather than the state.
 *
 * The third preflight is the one this engine needs a preflight for at all, and
 * it is stated here rather than tested, because **it cannot be provoked while
 * every pinned file covers its own rule.** A weight set that does not cover the
 * rule or the board size raises an exception the engine's own evaluator maker
 * catches and discards, leaving an engine on classical evaluation with the
 * configuration looking exactly as it was asked for. But reaching that gate
 * means getting a wrong-rule file past the byte gate first, and the byte gate
 * checks each file against the pins of the name it was staged under — so a renju
 * file under the freestyle name is refused on its length, several gates early.
 * There is no way to build the input the third gate is for without either
 * re-pinning a file or reaching around the bridge's own selection.
 *
 * So the case below asserts what is actually true and useful — a wrong-rule file
 * cannot get past the pins by any route — and the gate itself stands as defence
 * against a future re-pin, when a file that is genuinely pinned but genuinely
 * wrong for its rule becomes constructible. That is the day it earns its keep,
 * and the day it would be too late to add it.
 *
 * With the engine in the build, a missing or mismatched staged weight file FAILS
 * this suite with the staging message rather than skipping: a suite that
 * silently skipped its engine would report green on exactly the regression it
 * exists to catch. Without MXQ_ENABLE_GOMOKU_FACADE the bridge is not in the
 * library at all and every case reports NOT IMPLEMENTED.
 *
 * Movetimes are chosen for the suite's wall clock: completing searches think for
 * a couple of hundred milliseconds, and the multi-second movetime appears only
 * in the case that never lets it finish.
 */

#include "mxq.h"

#if MXQ_TEST_GOMOKU_FACADE
/* The engine's own globals, deliberately: see the header comment. */
#include "search/hashtable.h"
#include "search/searchengine.h"
#include "search/searchthread.h"

/* The bridge itself, which is the surface under test. */
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

    void check_eq(int64_t got, int64_t want, const std::string &what) {
        check(got == want, what + ": expected " + std::to_string(want) +
                               ", got " + std::to_string(got));
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

#if MXQ_TEST_GOMOKU_FACADE

using mxq::rapfi::ConfigureError;
using mxq::rapfi::Point;
using mxq::rapfi::Rules;
using mxq::rapfi::SearchError;

/* The staged asset directory: the three pinned weight files, placed by the build
 * after verifying every byte of each against pinned-inputs.json. */
std::string staged_assets() {
    if (const char *env = std::getenv("MXQ_TEST_GOMOKU_ASSETS_DIR")) {
        return env;
    }
    return MXQ_TEST_GOMOKU_ASSETS_DIR;
}

/* All of it from pinned-inputs.json through the build rather than spelled again
 * here: replacing a weight file is then the bytes and the manifest and nothing
 * else. */
constexpr const char *kGomokuWeight = MXQ_TEST_GOMOKU_NNUE_FILENAME;
constexpr const char *kRenjuBlackWeight = MXQ_TEST_RENJU_BLACK_NNUE_FILENAME;
constexpr const char *kRenjuWhiteWeight = MXQ_TEST_RENJU_WHITE_NNUE_FILENAME;
constexpr int64_t kGomokuWeightBytes = MXQ_TEST_GOMOKU_NNUE_BYTE_LENGTH;

/* A fresh scratch directory per case, so no case can lean on another. */
fs::path scratch_root() {
    static const fs::path root = [] {
        std::random_device rd;
        char buffer[17];
        std::snprintf(buffer, sizeof(buffer), "%08x%08x", rd(), rd());
        return fs::temp_directory_path() /
               ("minixiangqi-rapfi-tests-" + std::string(buffer));
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

/* A probe generous enough that the accepted arithmetic yields a usable table
 * without asking the machine running the suite for gigabytes: 4 GiB available
 * against 16 GiB physical reserves a fifth and caps at half the physical, so the
 * plan lands well above the 256 MiB minimum and far below the 4 GiB ceiling. */
MxqEngineBudget ample_budget(uint32_t threads = 2) {
    MxqEngineBudget budget;
    std::memset(&budget, 0, sizeof(budget));
    budget.struct_size = static_cast<uint32_t>(sizeof(budget));
    budget.active_processor_count = threads;
    budget.available_bytes = 4ull * 1024 * 1024 * 1024;
    budget.physical_bytes = 16ull * 1024 * 1024 * 1024;
    return budget;
}

MxqEnginePlan empty_plan() {
    MxqEnginePlan plan;
    std::memset(&plan, 0, sizeof(plan));
    plan.struct_size = static_cast<uint32_t>(sizeof(plan));
    return plan;
}

/* The staging gate. Every case runs against bytes the build verified, so a
 * suite run without them is a failure with the reason rather than a pass. */
bool staging_ok(Case &c) {
    if (MXQ_TEST_GOMOKU_NNUE_STAGED) {
        return true;
    }
    c.check(false, std::string("the pinned weights were not staged: ") +
                       MXQ_TEST_GOMOKU_NNUE_PROBLEM);
    return false;
}

const char *configure_error_name(ConfigureError e) {
    switch (e) {
    case ConfigureError::None:
        return "None";
    case ConfigureError::InsufficientMemory:
        return "InsufficientMemory";
    case ConfigureError::AssetMissing:
        return "AssetMissing";
    case ConfigureError::AssetMismatch:
        return "AssetMismatch";
    case ConfigureError::RulesLoadFailed:
        return "RulesLoadFailed";
    case ConfigureError::HashAllocationFailed:
        return "HashAllocationFailed";
    }
    return "?";
}

void check_configure(Case &c, ConfigureError got, ConfigureError want,
                     const std::string &what) {
    c.check(got == want, what + ": expected " + configure_error_name(want) +
                             ", got " + configure_error_name(got));
}

/* Whether the engine currently holds a real NNUE evaluator for the rule it is
 * prepared for. This is the fact the third preflight is about, read from the
 * engine rather than from anything the bridge says. */
bool effective_evaluator_is_nnue() {
    return !Search::Engine.empty() &&
           Search::Engine.main()->evaluator != nullptr;
}

/* -------------------------------------------------------------------- */
/* Preparation                                                          */
/* -------------------------------------------------------------------- */

void case_prepare_each_game() {
    Case c("preparation loads the pinned network for each game");
    if (!staging_ok(c)) {
        c.report();
        return;
    }

    const Rules games[] = {Rules::Gomoku15, Rules::Renju};
    for (Rules rules : games) {
        MxqEnginePlan plan = empty_plan();
        std::string detail;
        const ConfigureError rc =
            mxq::rapfi::prepare(rules, ample_budget(), staged_assets(), plan,
                                detail);
        check_configure(c, rc, ConfigureError::None,
                        std::string("prepare ") + mxq::rapfi::rules_id(rules) +
                            " (" + detail + ")");
        if (rc != ConfigureError::None) {
            continue;
        }
        c.check(mxq::rapfi::is_configured(),
                std::string("the bridge reports prepared for ") +
                    mxq::rapfi::rules_id(rules));
        c.check(mxq::rapfi::active_rules() == rules,
                std::string("the active rules are ") +
                    mxq::rapfi::rules_id(rules));
        /* The third preflight's own subject, read from the engine: an evaluator
         * exists for this rule at this size, so the search that follows is the
         * network's and not the classical fallback's. */
        c.check(effective_evaluator_is_nnue(),
                std::string("the effective evaluator is the network for ") +
                    mxq::rapfi::rules_id(rules));
        /* The plan reached the engine rather than being computed and dropped. */
        c.check_eq(static_cast<int64_t>(Search::Engine.size()),
                   static_cast<int64_t>(plan.threads),
                   "the engine holds the planned thread count");
        c.check_eq(static_cast<int64_t>(
                       Search::Engine.searcher()->getMemoryLimit()),
                   static_cast<int64_t>(plan.hash_mib) * 1024,
                   "the transposition table is the planned size in KiB");
    }
    mxq::rapfi::deconfigure();
    c.report();
}

void case_insufficient_memory_refuses() {
    Case c("a below-minimum budget refuses and configures nothing");
    if (!staging_ok(c)) {
        c.report();
        return;
    }
    mxq::rapfi::deconfigure();

    /* The boundary, from the injected probe alone. 256 MiB is the accepted
     * minimum and the reserve is the greater of a fifth of the probe or
     * 128 MiB, so a probe of 384 MiB reserves 128 and leaves 256 usable —
     * exactly the minimum, and accepted — while one of 383 MiB leaves less and
     * rounds below it. */
    struct Probe {
        uint64_t available;
        bool     sufficient;
        const char *what;
    };
    const Probe probes[] = {
        {0, false, "a probe of nothing"},
        {64ull * 1024 * 1024, false, "a probe below the reserve"},
        {383ull * 1024 * 1024, false, "a probe one MiB below the boundary"},
        {384ull * 1024 * 1024, true, "a probe exactly at the boundary"},
    };

    for (const Probe &probe : probes) {
        MxqEngineBudget budget = ample_budget();
        budget.available_bytes = probe.available;
        MxqEnginePlan plan = empty_plan();
        std::string detail;
        const ConfigureError rc = mxq::rapfi::prepare(
            Rules::Gomoku15, budget, staged_assets(), plan, detail);
        if (probe.sufficient) {
            check_configure(c, rc, ConfigureError::None,
                            std::string(probe.what) + " prepares (" + detail +
                                ")");
            c.check_eq(plan.hash_mib, 256, "the boundary budget is 256 MiB");
            mxq::rapfi::deconfigure();
        } else {
            check_configure(c, rc, ConfigureError::InsufficientMemory,
                            std::string(probe.what) + " refuses");
            c.check(!mxq::rapfi::is_configured(),
                    std::string(probe.what) + " configures nothing");
            /* Nothing was initialised, so the engine holds no threads either:
             * the refusal is before any engine call, not a rollback after one. */
            c.check(Search::Engine.empty(),
                    std::string(probe.what) + " creates no engine threads");
        }
    }
    c.report();
}

void case_missing_weight_refuses() {
    Case c("a missing weight file refuses before the engine sees a path");
    if (!staging_ok(c)) {
        c.report();
        return;
    }
    mxq::rapfi::deconfigure();

    const fs::path dir = scratch_dir("no-weights");
    MxqEnginePlan plan = empty_plan();
    std::string detail;
    const ConfigureError rc = mxq::rapfi::prepare(
        Rules::Renju, ample_budget(), dir.string(), plan, detail);
    check_configure(c, rc, ConfigureError::AssetMissing,
                    "an empty asset directory refuses");
    c.check(!mxq::rapfi::is_configured(), "nothing is configured");
    c.check(detail.find(kRenjuBlackWeight) != std::string::npos,
            "the diagnostic names the file it wanted: " + detail);
    c.report();
}

void case_damaged_weight_refuses() {
    Case c("a weight file that is not its pinned bytes refuses");
    if (!staging_ok(c)) {
        c.report();
        return;
    }
    mxq::rapfi::deconfigure();

    /* Two directories: one whose file is the wrong length, one whose file is the
     * right length and the wrong bytes. The second is the case a length check
     * alone would pass, and it is why the pin is a hash. */
    const fs::path truncated = scratch_dir("truncated");
    {
        std::ifstream in(fs::path(staged_assets()) / kGomokuWeight,
                         std::ios::binary);
        std::string bytes((std::istreambuf_iterator<char>(in)),
                          std::istreambuf_iterator<char>());
        bytes.resize(bytes.size() / 2);
        std::ofstream out(truncated / kGomokuWeight, std::ios::binary);
        out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    }
    const fs::path corrupt = scratch_dir("corrupt");
    {
        std::ifstream in(fs::path(staged_assets()) / kGomokuWeight,
                         std::ios::binary);
        std::string bytes((std::istreambuf_iterator<char>(in)),
                          std::istreambuf_iterator<char>());
        c.check_eq(static_cast<int64_t>(bytes.size()), kGomokuWeightBytes,
                   "the staged weight file is its pinned length");
        /* One byte, well past the header, so nothing structural changes. */
        bytes[bytes.size() / 2] = static_cast<char>(bytes[bytes.size() / 2] ^ 0xff);
        std::ofstream out(corrupt / kGomokuWeight, std::ios::binary);
        out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    }

    for (const auto &entry : {std::make_pair(truncated, "a truncated file"),
                              std::make_pair(corrupt, "one flipped byte")}) {
        MxqEnginePlan plan = empty_plan();
        std::string detail;
        const ConfigureError rc = mxq::rapfi::prepare(
            Rules::Gomoku15, ample_budget(), entry.first.string(), plan, detail);
        check_configure(c, rc, ConfigureError::AssetMismatch,
                        std::string(entry.second) + " refuses");
        c.check(!mxq::rapfi::is_configured(),
                std::string(entry.second) + " configures nothing");
    }
    c.report();
}

void case_wrong_rule_weights_cannot_pass_the_pins() {
    Case c("a weight file for another rule cannot get past the pins");
    if (!staging_ok(c)) {
        c.report();
        return;
    }
    mxq::rapfi::deconfigure();

    /* Real renju weights, staged under the freestyle file's name — the shape of
     * a genuine mistake rather than of damage, since every byte is a byte the
     * project ships.
     *
     * What refuses it is the byte gate, on length, because that gate checks each
     * file against the pins of the name it was staged under and these two files
     * are not the same size. This case asserts that, and not more: the refusal
     * arrives well before the effective-evaluator gate, and the two share a
     * status, so an assertion here cannot tell which one spoke.
     *
     * That is the honest state of things, and the header at the top of this file
     * says why it is not a gap: while every pinned file covers its own rule,
     * there is no input that reaches the third gate. What this case does prove
     * is the property that actually protects the player today — a file for the
     * wrong rule cannot be configured by any route the bridge offers. */
    const fs::path dir = scratch_dir("renju-weights-as-freestyle");
    fs::copy_file(fs::path(staged_assets()) / kRenjuBlackWeight,
                  dir / kGomokuWeight);

    MxqEnginePlan plan = empty_plan();
    std::string detail;
    const ConfigureError rc = mxq::rapfi::prepare(
        Rules::Gomoku15, ample_budget(), dir.string(), plan, detail);
    check_configure(c, rc, ConfigureError::AssetMismatch,
                    "renju weights under the freestyle name refuse");
    c.check(!mxq::rapfi::is_configured(), "nothing is configured");
    c.check(!effective_evaluator_is_nnue(),
            "no evaluator survives the refusal");
    c.report();
}

/* -------------------------------------------------------------------- */
/* Search                                                               */
/* -------------------------------------------------------------------- */

void case_search_each_game() {
    Case c("a search returns an empty point on the board, within its movetime");
    if (!staging_ok(c)) {
        c.report();
        return;
    }

    const Rules games[] = {Rules::Gomoku15, Rules::Renju};
    for (Rules rules : games) {
        mxq::rapfi::deconfigure();
        MxqEnginePlan plan = empty_plan();
        std::string detail;
        if (mxq::rapfi::prepare(rules, ample_budget(), staged_assets(), plan,
                                detail) != ConfigureError::None) {
            c.check(false, std::string("prepare ") +
                               mxq::rapfi::rules_id(rules) + ": " + detail);
            continue;
        }

        /* A short opening line rather than an empty board, so the answer is a
         * search rather than the engine's trivial centre-point reply. */
        const std::vector<Point> moves = {{7, 7}, {7, 8}, {8, 7}};
        const uint32_t movetime_ms = 200;
        std::atomic<bool> cancelled{false};
        mxq::rapfi::SearchOutput out;
        const auto begun = std::chrono::steady_clock::now();
        const SearchError rc = mxq::rapfi::search_run(moves, movetime_ms,
                                                      cancelled, out, detail);
        const auto elapsed_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - begun)
                .count();

        const std::string who = mxq::rapfi::rules_id(rules);
        c.check(rc == SearchError::None,
                who + ": the search completed (" + detail + ")");
        if (rc != SearchError::None) {
            continue;
        }
        c.check(out.point.x < mxq::rapfi::kBoardSize &&
                    out.point.y < mxq::rapfi::kBoardSize,
                who + ": the proposed point is on the board");
        bool occupied = false;
        for (const Point &played : moves) {
            if (played.x == out.point.x && played.y == out.point.y) {
                occupied = true;
            }
        }
        c.check(!occupied, who + ": the proposed point is empty");
        /* The engine keeps a reserve inside the turn time and returns before it
         * elapses. The upper bound is generous — this asserts that the movetime
         * bounds the search at all, not how precisely it does. */
        c.check(elapsed_ms < movetime_ms * 5,
                who + ": the search returned within its movetime (" +
                    std::to_string(elapsed_ms) + " ms for " +
                    std::to_string(movetime_ms) + " ms)");
        c.check(out.nodes > 0, who + ": the search reports nodes");
    }
    mxq::rapfi::deconfigure();
    c.report();
}

void case_search_refuses_an_occupied_point() {
    Case c("a snapshot that plays an occupied point is refused, not searched");
    if (!staging_ok(c)) {
        c.report();
        return;
    }
    mxq::rapfi::deconfigure();
    MxqEnginePlan plan = empty_plan();
    std::string detail;
    if (mxq::rapfi::prepare(Rules::Gomoku15, ample_budget(), staged_assets(),
                            plan, detail) != ConfigureError::None) {
        c.check(false, "prepare: " + detail);
        c.report();
        return;
    }

    std::atomic<bool> cancelled{false};
    mxq::rapfi::SearchOutput out;
    const std::vector<Point> repeated = {{7, 7}, {7, 7}};
    c.check(mxq::rapfi::search_run(repeated, 100, cancelled, out, detail) ==
                SearchError::ReplayFailed,
            "a repeated point fails to replay");

    const std::vector<Point> off_board = {{15, 0}};
    c.check(mxq::rapfi::search_run(off_board, 100, cancelled, out, detail) ==
                SearchError::ReplayFailed,
            "an off-board point fails to replay");

    mxq::rapfi::deconfigure();
    c.report();
}

void case_search_without_an_engine_is_refused() {
    Case c("a search with no engine prepared is refused");
    mxq::rapfi::deconfigure();
    std::atomic<bool> cancelled{false};
    mxq::rapfi::SearchOutput out;
    std::string detail;
    c.check(mxq::rapfi::search_run({}, 100, cancelled, out, detail) ==
                SearchError::NotConfigured,
            "search_run reports that nothing is prepared");
    c.report();
}

void case_cancellation_returns_early() {
    Case c("a cancelled search stops well before its movetime");
    if (!staging_ok(c)) {
        c.report();
        return;
    }
    mxq::rapfi::deconfigure();
    MxqEnginePlan plan = empty_plan();
    std::string detail;
    if (mxq::rapfi::prepare(Rules::Gomoku15, ample_budget(), staged_assets(),
                            plan, detail) != ConfigureError::None) {
        c.check(false, "prepare: " + detail);
        c.report();
        return;
    }

    /* Long enough that finishing it would be unmistakable. */
    const uint32_t movetime_ms = 10000;
    const std::vector<Point> moves = {{7, 7}, {7, 8}, {8, 7}};
    std::atomic<bool> cancelled{false};
    mxq::rapfi::SearchOutput out;

    std::thread canceller([&] {
        std::this_thread::sleep_for(std::chrono::milliseconds(150));
        /* The flag first, then the engine: the flag is what search_run
         * re-checks after the engine re-arms its own stop flag, so setting it
         * first is what closes the window a cancellation racing the start
         * would otherwise fall into. */
        cancelled.store(true, std::memory_order_release);
        mxq::rapfi::search_abort();
    });

    const auto begun = std::chrono::steady_clock::now();
    mxq::rapfi::search_run(moves, movetime_ms, cancelled, out, detail);
    const auto elapsed_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - begun)
            .count();
    canceller.join();

    c.check(elapsed_ms < movetime_ms / 2,
            "the cancelled search returned early (" +
                std::to_string(elapsed_ms) + " ms of " +
                std::to_string(movetime_ms) + " ms)");

    /* And the engine is usable afterwards: a cancellation is not a fault. */
    std::atomic<bool> not_cancelled{false};
    mxq::rapfi::SearchOutput after;
    c.check(mxq::rapfi::search_run(moves, 200, not_cancelled, after, detail) ==
                SearchError::None,
            "the engine searches again after a cancellation");

    mxq::rapfi::deconfigure();
    c.report();
}

/* -------------------------------------------------------------------- */
/* The rules switch, and teardown                                       */
/* -------------------------------------------------------------------- */

void case_rules_switch_serialises_through_one_engine() {
    Case c("the two games serialise through one engine, table flushed between");
    if (!staging_ok(c)) {
        c.report();
        return;
    }
    mxq::rapfi::deconfigure();

    MxqEnginePlan plan = empty_plan();
    std::string detail;
    const std::vector<Point> moves = {{7, 7}, {7, 8}, {8, 7}};
    std::atomic<bool> cancelled{false};

    /* Freestyle, then renju, then freestyle again, each through configure()
     * without a teardown between: a rules switch IS a reconfiguration, and it
     * has to work as one. */
    const Rules order[] = {Rules::Gomoku15, Rules::Renju, Rules::Gomoku15};
    for (Rules rules : order) {
        const ConfigureError rc = mxq::rapfi::prepare(
            rules, ample_budget(), staged_assets(), plan, detail);
        const std::string who = mxq::rapfi::rules_id(rules);
        check_configure(c, rc, ConfigureError::None,
                        "switch to " + who + " (" + detail + ")");
        if (rc != ConfigureError::None) {
            continue;
        }
        c.check(mxq::rapfi::active_rules() == rules,
                "the active rules are now " + who);
        c.check(effective_evaluator_is_nnue(),
                "the effective evaluator is " + who + "'s network");
        /* A fresh table each time. Entries keyed under one rule's pattern and
         * zobrist tables mean something else under the other's, so a switch
         * that kept them would be reading another game's answers. */
        c.check_eq(Search::TT.hashUsage(), 0,
                   "the transposition table is empty after the switch to " +
                       who);
        mxq::rapfi::SearchOutput out;
        c.check(mxq::rapfi::search_run(moves, 200, cancelled, out, detail) ==
                    SearchError::None,
                who + " searches after the switch (" + detail + ")");
    }

    mxq::rapfi::deconfigure();
    c.report();
}

void case_teardown_releases_everything() {
    Case c("teardown releases the table and the threads whole");
    if (!staging_ok(c)) {
        c.report();
        return;
    }
    mxq::rapfi::deconfigure();

    MxqEnginePlan plan = empty_plan();
    std::string detail;
    if (mxq::rapfi::prepare(Rules::Renju, ample_budget(), staged_assets(), plan,
                            detail) != ConfigureError::None) {
        c.check(false, "prepare: " + detail);
        c.report();
        return;
    }
    c.check(Search::Engine.size() > 0, "the engine holds threads when prepared");
    c.check(Search::TT.hashSizeKB() > 0,
            "the transposition table is allocated when prepared");

    mxq::rapfi::deconfigure();

    c.check(!mxq::rapfi::is_configured(), "the bridge reports not prepared");
    c.check(Search::Engine.empty(), "no engine threads survive the teardown");
    /* "Released whole" means down to the floor the table's own class invariant
     * keeps, not down to nothing: resize(0) clamps to one bucket, because
     * probe(), store() and prefetch() are unguarded and rest on there being at
     * least one. hashSizeKB() reports buckets divided by sixteen, so one bucket
     * reads as zero KiB — the assertion below would pass on a table of up to
     * fifteen buckets as well, so what it really pins is that no real table
     * survived, which is the claim worth making. It fails loudly if a
     * preparation's table is still there. */
    c.check_eq(static_cast<int64_t>(Search::TT.hashSizeKB()), 0,
               "no allocated transposition table survives the teardown "
               "(the one-bucket floor reads as zero KiB)");
    /* And a second teardown is harmless, which is what a deterministic one
     * means: the shutdown path runs it after the facade already has. */
    mxq::rapfi::deconfigure();
    c.check(!mxq::rapfi::is_configured(), "a second teardown changes nothing");

    /* And preparation works again afterwards. */
    c.check(mxq::rapfi::prepare(Rules::Gomoku15, ample_budget(),
                                staged_assets(), plan, detail) ==
                ConfigureError::None,
            "the engine prepares again after a teardown (" + detail + ")");
    mxq::rapfi::deconfigure();
    c.report();
}

void case_the_engine_is_silent() {
    Case c("preparing and searching write nothing to standard output");
    if (!staging_ok(c)) {
        c.report();
        return;
    }
    mxq::rapfi::deconfigure();

    /* The outcome, not the switch. Asserting that messageMode is NONE would
     * assert that the line of the bridge which sets it ran — true, and no
     * evidence at all about whether anything reaches the host's stdout, which is
     * the thing a library must not touch. So this captures the stream around a
     * real preparation and a real search and requires the capture to be empty.
     *
     * The one write it cannot see is stated rather than implied: platform.cpp's
     * Windows large-page path uses C stdio, which no rdbuf swap intercepts. It
     * is unreachable in this build. */
    std::ostringstream captured;
    std::streambuf *saved = std::cout.rdbuf(captured.rdbuf());

    MxqEnginePlan plan = empty_plan();
    std::string detail;
    const ConfigureError rc = mxq::rapfi::prepare(
        Rules::Gomoku15, ample_budget(), staged_assets(), plan, detail);
    if (rc == ConfigureError::None) {
        std::atomic<bool> cancelled{false};
        mxq::rapfi::SearchOutput out;
        mxq::rapfi::search_run({{7, 7}, {7, 8}, {8, 7}}, 200, cancelled, out,
                               detail);
    }
    mxq::rapfi::deconfigure();

    std::cout.rdbuf(saved);

    check_configure(c, rc, ConfigureError::None, "prepare (" + detail + ")");
    const std::string leaked = captured.str();
    c.check(leaked.empty(),
            "nothing reached standard output; captured " +
                std::to_string(leaked.size()) + " bytes: \"" +
                leaked.substr(0, 120) + "\"");
    c.report();
}

#endif /* MXQ_TEST_GOMOKU_FACADE */

} /* namespace */

int main() {
    std::cout << "Rapfi bridge\n";

#if MXQ_TEST_GOMOKU_FACADE
    case_prepare_each_game();
    case_insufficient_memory_refuses();
    case_missing_weight_refuses();
    case_damaged_weight_refuses();
    case_wrong_rule_weights_cannot_pass_the_pins();

    case_search_each_game();
    case_search_refuses_an_occupied_point();
    case_search_without_an_engine_is_refused();
    case_cancellation_returns_early();

    case_rules_switch_serialises_through_one_engine();
    case_teardown_releases_everything();
    case_the_engine_is_silent();

    std::error_code cleanup;
    fs::remove_all(scratch_root(), cleanup);
#else
    std::cout << "\n";
    Case skipped("the Rapfi bridge");
    skipped.skip("the bridge needs the second engine in the build");
    skipped.report();
#endif

    const int total = g_passed + g_failed + g_skipped;
    std::cout << "\n"
              << total << " cases: " << g_passed << " passed, " << g_failed
              << " failed, " << g_skipped << " skipped\n"
              << g_checks << " expectations evaluated\n";
    if (g_skipped > 0) {
        std::cout << "\nNOT IMPLEMENTED: the second engine is not in this "
                     "build. Build with -DMXQ_ENABLE_GOMOKU_FACADE=ON to "
                     "evaluate it.\n";
    }
    return g_failed > 0 ? 1 : 0;
}
