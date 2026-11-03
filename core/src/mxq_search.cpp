/*
 * The search facade: mxq_engine_prepare/teardown/query, mxq_search_start and
 * mxq_search_cancel, and mxq_core_cancel_all.
 *
 * The core has one internal thread, the engine thread, which is the sole
 * caller of every engine entry point. It runs a queue of preparations,
 * teardowns and searches, and it is the thread every callback is delivered on.
 *
 * mxq_search_start copies the line it is given and returns a ticket. The
 * engine thread later searches the copy and delivers through this ladder:
 *
 *   1. cancelled — also honoured at pickup, so a cancelled search never burns
 *      its movetime;
 *   2. the engine's own failure — no move, an engine no longer prepared, or a
 *      line that stopped replaying — as MXQ_SEARCH_FAILED with its status;
 *   3. malformed — text that is not a move of this game's notation;
 *   4. illegal — the move replayed after the line through the rules facade.
 *
 * Only a survivor arrives as MXQ_SEARCH_MOVE. Whether the line is still the
 * game's is the caller's question: the core keeps no game.
 *
 * The facade's state is process-global, like the engines it fronts. One mutex
 * guards it, and it is never held while calling into a bridge or a callback.
 */

#include "mxq_search.hpp"

#include "mxq_build_config.h"
#include "mxq_core_state.hpp"
#include "mxq_engine_bridge.hpp"
#include "mxq_internal.hpp"
#include "mxq_notation.hpp"
#include "mxq_rules.hpp"

#include "mxq_rapfi_bridge.hpp"

#include <atomic>
#include <cassert>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace mxq {
namespace search {
namespace {

/* ---------------------------------------------------------------------- */
/* Tasks                                                                   */
/* ---------------------------------------------------------------------- */

struct Task {
    enum class Kind { Search, Prepare, Teardown };
    Kind kind = Kind::Search;

    /* Search */
    uint64_t                 ticket = 0;
    MxqGameKind              game = MXQ_GAME_KIND_MINI_XIANGQI;
    std::string              start_fen;
    std::vector<std::string> moves;
    uint32_t                 movetime_ms = 0;
    MxqSearchCallback        callback = nullptr;
    void                    *user_data = nullptr;
    std::atomic<bool>        cancelled{false};

    /* Prepare */
    uint32_t    threads = 0;
    uint32_t    hash_mib = 0;
    std::string assets_dir;

    /* Prepare and teardown completion, read by the marshalling caller. */
    bool        done = false;
    MxqStatus   status = MXQ_OK;
    std::string detail;
};

/* ---------------------------------------------------------------------- */
/* Facade state                                                            */
/* ---------------------------------------------------------------------- */

std::mutex g_mutex;
std::condition_variable g_engine_cv; /* wakes the engine thread */
std::condition_variable g_done_cv;   /* wakes waiters: marshalled
                                      * prepare/teardown, quiesce */
std::deque<std::shared_ptr<Task>> g_queue;
std::shared_ptr<Task> g_running;
std::thread g_thread;
bool g_thread_live = false;
bool g_exiting = false;

uint64_t g_next_ticket = 1; /* 0 is never issued */

std::atomic<int32_t> g_engine_state{MXQ_ENGINE_STATE_UNINITIALIZED};

/*
 * The game an engine is prepared for, or -1 when none is. The facade holds it
 * because neither bridge knows whether the other is configured. Written on the
 * engine thread, read on any.
 */
std::atomic<int32_t> g_prepared_game{-1};

/* The profile identifier: the core revision, the revision of the engine the
 * game is played on, its variant and its network. Twelve characters of each
 * revision keep the whole under MXQ_PROFILE_ID_CAP. */
std::string compose_profile_id(MxqGameKind game) {
    const auto first12 = [](const char *value) {
        const std::string s(value);
        return s.size() > 12 ? s.substr(0, 12) : s;
    };
    if (notation::move_class_of(game) == notation::MoveClass::Placement) {
        const rapfi::Rules rules = rapfi::rules_of(game);
        return first12(MXQ_BUILD_CORE_REVISION) + "-" +
               first12(rapfi::fork_revision()) + "-" +
               rapfi::rules_variant_id(rules) + "-" +
               rapfi::rules_network_id(rules);
    }
    const engine::Variant variant = engine::variant_of(game);
    return first12(MXQ_BUILD_CORE_REVISION) + "-" +
           first12(MXQ_BUILD_FORK_REVISION) + "-" +
           engine::variant_id(variant) + "-" +
           engine::variant_network_id(variant);
}

/* The profile of one game, composed once each. */
const std::string &profile_id_of(MxqGameKind game) {
    static const std::string composed[] = {
        compose_profile_id(MXQ_GAME_KIND_MINI_XIANGQI),
        compose_profile_id(MXQ_GAME_KIND_XIANGQI),
        compose_profile_id(MXQ_GAME_KIND_GOMOKU_15),
        compose_profile_id(MXQ_GAME_KIND_RENJU),
    };
    const size_t count = sizeof(composed) / sizeof(composed[0]);
    /* One entry per searched game; the entries that would ask for another
     * refuse it first. */
    assert(notation::known_game(game) && notation::searched(game) &&
           static_cast<size_t>(game) < count &&
           "a game no engine searches has no profile identifier");
    return composed[static_cast<size_t>(game) < count
                        ? static_cast<size_t>(game)
                        : 0u];
}

/* The profile a move would be produced under right now. Before any preparation
 * it is the movement engine's active variant, whose tables are always built. */
const std::string &profile_id() {
    const int32_t prepared = g_prepared_game.load(std::memory_order_acquire);
    if (prepared >= 0) {
        return profile_id_of(static_cast<MxqGameKind>(prepared));
    }
    return profile_id_of(engine::active_variant() == engine::Variant::Xiangqi
                             ? MXQ_GAME_KIND_XIANGQI
                             : MXQ_GAME_KIND_MINI_XIANGQI);
}

/* Whether a search task is queued or running. Caller holds g_mutex. */
bool search_outstanding_locked() {
    if (g_running != nullptr && g_running->kind == Task::Kind::Search) {
        return true;
    }
    for (const auto &task : g_queue) {
        if (task->kind == Task::Kind::Search) {
            return true;
        }
    }
    return false;
}

/* ---------------------------------------------------------------------- */
/* The engine thread                                                       */
/* ---------------------------------------------------------------------- */

/* Asked of the notation table, so that this dispatch and the rules dispatch in
 * mxq_rules.cpp cannot answer differently. */
bool played_on_gomoku_engine(MxqGameKind game) {
    return notation::move_class_of(game) == notation::MoveClass::Placement;
}

/* Both bridges are idempotent and cheap when nothing is configured. */
void deconfigure_all() {
    engine::deconfigure();
    rapfi::deconfigure();
}

/* Each is a flag store on an engine that is not thinking. */
void abort_all() {
    engine::search_abort();
    rapfi::search_abort();
}

void run_prepare(Task &task) {
    std::string detail;
    MxqStatus   status = MXQ_OK;

    /* The other engine is released first: the memory plan is sized for one
     * transposition table, and a failed preparation leaves nothing prepared. */
    if (played_on_gomoku_engine(task.game)) {
        engine::deconfigure();
        switch (rapfi::configure(rapfi::rules_of(task.game), task.threads,
                                 task.hash_mib, task.assets_dir, detail)) {
        case rapfi::ConfigureError::None:
            status = MXQ_OK;
            break;
        case rapfi::ConfigureError::AssetMissing:
            status = MXQ_ERR_ENGINE_ASSET_MISSING;
            break;
        case rapfi::ConfigureError::AssetMismatch:
            status = MXQ_ERR_ENGINE_ASSET_MISMATCH;
            break;
        case rapfi::ConfigureError::RulesLoadFailed:
            status = MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED;
            break;
        case rapfi::ConfigureError::HashAllocationFailed:
            status = MXQ_ERR_ENGINE_HASH_ALLOCATION_FAILED;
            break;
        }
    } else
    {
        rapfi::deconfigure();
        switch (engine::configure(engine::variant_of(task.game), task.threads,
                                  task.hash_mib, task.assets_dir, detail)) {
        case engine::ConfigureError::None:
            status = MXQ_OK;
            break;
        case engine::ConfigureError::AssetMissing:
            status = MXQ_ERR_ENGINE_ASSET_MISSING;
            break;
        case engine::ConfigureError::AssetMismatch:
            status = MXQ_ERR_ENGINE_ASSET_MISMATCH;
            break;
        case engine::ConfigureError::VariantLoadFailed:
            status = MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED;
            break;
        case engine::ConfigureError::HashAllocationFailed:
            status = MXQ_ERR_ENGINE_HASH_ALLOCATION_FAILED;
            break;
        }
    }

    task.detail = detail;
    task.status = status;
    if (status == MXQ_OK) {
        g_prepared_game.store(task.game, std::memory_order_release);
        g_engine_state.store(MXQ_ENGINE_STATE_READY, std::memory_order_release);
        return;
    }
    /* configure() unwound whole. */
    g_prepared_game.store(-1, std::memory_order_release);
    g_engine_state.store(MXQ_ENGINE_STATE_UNINITIALIZED,
                         std::memory_order_release);
}

void run_teardown(Task &task) {
    deconfigure_all();
    g_prepared_game.store(-1, std::memory_order_release);
    g_engine_state.store(MXQ_ENGINE_STATE_UNINITIALIZED,
                         std::memory_order_release);
    task.status = MXQ_OK;
}

/* What one engine's run reported, in the terms the delivery ladder shares. */
struct EngineRun {
    bool        produced = false;
    bool        faulted = false;
    MxqStatus   status = MXQ_OK;
    std::string move;
    int32_t     score_cp = 0;
    uint32_t    depth = 0;
    uint64_t    nodes = 0;
};

/* Caller: the engine thread, with the engine prepared for the task's game. */
EngineRun run_engine(const Task &task, std::string &detail) {
    EngineRun out;

    if (played_on_gomoku_engine(task.game)) {
        /* The caller promises a legal line, so a ply that is not a point is a
         * fault rather than a rules answer. */
        std::vector<rapfi::Point> points;
        points.reserve(task.moves.size());
        for (const std::string &move : task.moves) {
            int32_t file = 0;
            int32_t rank = 0;
            if (!notation::point_of_square(task.game, move.c_str(), file,
                                           rank)) {
                detail = "the line carries a ply that is not a point of "
                         "this board";
                out.faulted = true;
                out.status = MXQ_ERR_ENGINE_FAULTED;
                return out;
            }
            rapfi::Point point;
            point.x = static_cast<uint8_t>(file);
            point.y = static_cast<uint8_t>(rank);
            points.push_back(point);
        }

        rapfi::SearchOutput produced;
        switch (rapfi::search_run(points, task.movetime_ms, task.cancelled,
                                  produced, detail)) {
        case rapfi::SearchError::None:
            out.produced = true;
            out.move = notation::square_of_point(task.game, produced.point.x,
                                                 produced.point.y);
            out.score_cp = produced.score_cp;
            out.depth = produced.depth;
            out.nodes = produced.nodes;
            break;
        case rapfi::SearchError::NoMove:
            /* Not a fault. */
            out.status = MXQ_ERR_ENGINE_NO_MOVE;
            break;
        case rapfi::SearchError::NotConfigured:
        case rapfi::SearchError::ReplayFailed:
        case rapfi::SearchError::Faulted:
            out.faulted = true;
            out.status = MXQ_ERR_ENGINE_FAULTED;
            break;
        }
        return out;
    }

    engine::SearchOutput produced;
    switch (engine::search_run(task.start_fen, task.moves, task.movetime_ms,
                               task.cancelled, produced, detail)) {
    case engine::SearchError::None:
        out.produced = true;
        out.move = produced.move;
        out.score_cp = produced.score_cp;
        out.depth = produced.depth;
        out.nodes = produced.nodes;
        break;
    case engine::SearchError::NoMove:
        out.status = MXQ_ERR_ENGINE_NO_MOVE;
        break;
    case engine::SearchError::ReplayFailed:
        out.faulted = true;
        out.status = MXQ_ERR_ENGINE_FAULTED;
        break;
    }
    return out;
}

/* One search, engine work through delivery. Runs with no facade lock held. */
void run_search(Task &task) {
    MxqSearchResult result;
    std::memset(&result, 0, sizeof(result));
    result.struct_size = static_cast<uint32_t>(sizeof(result));
    result.move.struct_size = static_cast<uint32_t>(sizeof(result.move));
    result.ticket = task.ticket;
    result.status = MXQ_OK;
    copy_bounded(result.profile_id, sizeof(result.profile_id),
                 profile_id_of(task.game).c_str());

    EngineRun ran;
    std::string engine_detail;
    bool engine_ran = false;
    const bool ready = g_engine_state.load(std::memory_order_acquire) ==
                       MXQ_ENGINE_STATE_READY;
    if (!task.cancelled.load(std::memory_order_acquire) && ready) {
        const auto begun = std::chrono::steady_clock::now();
        ran = run_engine(task, engine_detail);
        result.elapsed_ms = static_cast<uint32_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - begun)
                .count());
        engine_ran = true;
    }

    /* Recorded before the ladder: a cancelled result must not leave a faulted
     * engine trusted for the next search. */
    if (engine_ran && ran.faulted) {
        g_engine_state.store(MXQ_ENGINE_STATE_FAULTED,
                             std::memory_order_release);
    }

    /* The ladder at the top of this file. */
    for (;;) {
        if (task.cancelled.load(std::memory_order_acquire)) {
            result.outcome = MXQ_SEARCH_CANCELLED;
            break;
        }

        if (!ready) {
            /* Torn down or faulted between mxq_search_start and this run. */
            result.outcome = MXQ_SEARCH_FAILED;
            result.status = MXQ_ERR_ENGINE_NOT_PREPARED;
            break;
        }
        if (!engine_ran || !ran.produced) {
            result.outcome = MXQ_SEARCH_FAILED;
            result.status = engine_ran ? ran.status : MXQ_ERR_ENGINE_FAULTED;
            break;
        }

        result.score_cp = ran.score_cp;
        result.depth = ran.depth;
        result.nodes = ran.nodes;

        if (!notation::well_formed_move(task.game, ran.move)) {
            result.outcome = MXQ_SEARCH_MALFORMED;
            break;
        }

        {
            std::vector<const char *> line;
            line.reserve(task.moves.size() + 1);
            for (const std::string &move : task.moves) {
                line.push_back(move.c_str());
            }
            line.push_back(ran.move.c_str());

            std::string fen;
            std::string detail;
            bool in_check = false;
            uint32_t ply = 0;
            rules::Adjudication adj{};
            size_t first_illegal = 0;
            const rules::ReplayError replayed = rules::replay(
                task.game, task.start_fen.c_str(), line.data(), line.size(),
                fen, in_check, ply, adj, nullptr, first_illegal, detail);
            if (replayed != rules::ReplayError::None) {
                if (replayed == rules::ReplayError::IllegalMove &&
                    first_illegal + 1 == line.size()) {
                    result.outcome = MXQ_SEARCH_ILLEGAL;
                    break;
                }
                result.outcome = MXQ_SEARCH_FAILED;
                result.status = MXQ_ERR_ENGINE_FAULTED;
                g_engine_state.store(MXQ_ENGINE_STATE_FAULTED,
                                     std::memory_order_release);
                break;
            }
        }

        result.outcome = MXQ_SEARCH_MOVE;
        copy_bounded(result.move.text, sizeof(result.move.text),
                     ran.move.c_str());
        break;
    }

    if (task.callback != nullptr) {
        CallbackScope scope;
        task.callback(&result, task.user_data);
    }
}

void engine_thread_main() {
    for (;;) {
        std::shared_ptr<Task> task;
        {
            std::unique_lock<std::mutex> lock(g_mutex);
            g_engine_cv.wait(lock,
                             [] { return g_exiting || !g_queue.empty(); });
            if (g_queue.empty()) {
                break;
            }
            task = g_queue.front();
            g_queue.pop_front();
            g_running = task;
        }

        switch (task->kind) {
        case Task::Kind::Search:
            run_search(*task);
            break;
        case Task::Kind::Prepare:
            run_prepare(*task);
            break;
        case Task::Kind::Teardown:
            run_teardown(*task);
            break;
        }

        {
            std::lock_guard<std::mutex> lock(g_mutex);
            g_running.reset();
            task->done = true;
        }
        g_done_cv.notify_all();
    }
}

/* Caller holds g_mutex. Callbacks still fire, cancelled. */
void cancel_all_locked() {
    for (const auto &task : g_queue) {
        if (task->kind == Task::Kind::Search) {
            task->cancelled.store(true, std::memory_order_release);
        }
    }
    if (g_running != nullptr && g_running->kind == Task::Kind::Search) {
        g_running->cancelled.store(true, std::memory_order_release);
        abort_all();
    }
}

/*
 * Enqueue a prepare or teardown task and block until the engine thread has
 * run it. The outstanding-search refusal is checked under the enqueue's lock,
 * so no search can slip in and stall the reconfiguration for a full movetime.
 */
MxqStatus marshal(std::shared_ptr<Task> task, MxqError *err) {
    {
        std::unique_lock<std::mutex> lock(g_mutex);
        if (g_exiting || !g_thread_live) {
            fill_error(err, MXQ_ERR_STATE_SHUTTING_DOWN,
                       "the core is shutting down");
            return MXQ_ERR_STATE_SHUTTING_DOWN;
        }
        if (search_outstanding_locked()) {
            fill_error(err, MXQ_ERR_STATE_SEARCH_IN_PROGRESS,
                       task->kind == Task::Kind::Prepare
                           ? "a search is outstanding; prepare after it "
                             "completes or is cancelled"
                           : "a search is outstanding; cancel it before "
                             "tearing the engine down");
            return MXQ_ERR_STATE_SEARCH_IN_PROGRESS;
        }
        g_queue.push_back(task);
        g_engine_cv.notify_one();
        g_done_cv.wait(lock, [&] { return task->done; });
    }
    if (task->status != MXQ_OK) {
        fill_error(err, task->status, task->detail.c_str());
    }
    return task->status;
}

MxqStatus start(MxqGameKind game, const char *start_fen,
                const char *const *moves, size_t move_count,
                uint32_t movetime_ms, MxqSearchCallback callback,
                void *user_data, uint64_t *out_ticket, MxqError *err) {
    if (start_fen == nullptr || (move_count > 0 && moves == nullptr)) {
        assert(false && "required line pointer was null");
        fill_error(err, MXQ_ERR_ARG_NULL, "the line to search was null");
        return MXQ_ERR_ARG_NULL;
    }
    if (movetime_ms == 0) {
        assert(false && "a search needs a thinking time");
        fill_error(err, MXQ_ERR_ARG_RANGE, "movetime_ms was zero");
        return MXQ_ERR_ARG_RANGE;
    }

    auto task = std::make_shared<Task>();
    task->kind = Task::Kind::Search;
    task->game = game;
    task->start_fen = start_fen;
    task->moves.reserve(move_count);
    for (size_t i = 0; i < move_count; ++i) {
        if (moves[i] == nullptr) {
            assert(false && "a move in the line was null");
            fill_error(err, MXQ_ERR_ARG_NULL, "a move in the line was null");
            return MXQ_ERR_ARG_NULL;
        }
        task->moves.emplace_back(moves[i]);
    }
    task->movetime_ms = movetime_ms;
    task->callback = callback;
    task->user_data = user_data;

    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (g_exiting || !g_thread_live) {
            fill_error(err, MXQ_ERR_STATE_SHUTTING_DOWN,
                       "the core is shutting down");
            return MXQ_ERR_STATE_SHUTTING_DOWN;
        }
        /* Checked again when the search runs, for a teardown queued ahead. */
        if (g_engine_state.load(std::memory_order_acquire) !=
            MXQ_ENGINE_STATE_READY) {
            fill_error(err, MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "the engine is not prepared");
            return MXQ_ERR_STATE_ENGINE_NOT_READY;
        }
        if (g_prepared_game.load(std::memory_order_acquire) != game) {
            fill_error(err, MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "the engine is prepared for another game");
            return MXQ_ERR_STATE_ENGINE_NOT_READY;
        }
        task->ticket = g_next_ticket++;
        g_queue.push_back(task);
        g_engine_cv.notify_one();
    }
    *out_ticket = task->ticket;
    return MXQ_OK;
}

} /* namespace */

/* ---------------------------------------------------------------------- */
/* Lifecycle, called from mxq_core.cpp                                     */
/* ---------------------------------------------------------------------- */

void startup() {
    std::lock_guard<std::mutex> lock(g_mutex);
    assert(!g_thread_live && "the engine thread is already running");
    g_exiting = false;
    g_queue.clear();
    g_running.reset();
    g_next_ticket = 1;
    g_prepared_game.store(-1, std::memory_order_release);
    g_engine_state.store(MXQ_ENGINE_STATE_UNINITIALIZED,
                         std::memory_order_release);
    g_thread = std::thread(engine_thread_main);
    g_thread_live = true;
}

void shutdown() {
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (!g_thread_live) {
            return;
        }
        /* The engine thread drains the queue before it exits, so every task
         * still delivers its callback, cancelled. */
        cancel_all_locked();
        g_exiting = true;
    }
    g_engine_cv.notify_one();
    g_thread.join();
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_thread_live = false;
    }
    /* Concurrent rules queries are safe: each serialises on its bridge's
     * mutex. */
    deconfigure_all();
    g_prepared_game.store(-1, std::memory_order_release);
    g_engine_state.store(MXQ_ENGINE_STATE_UNINITIALIZED,
                         std::memory_order_release);
}

MxqStatus cancel_all_and_quiesce(MxqError *err) {
    (void)err;
    std::unique_lock<std::mutex> lock(g_mutex);
    cancel_all_locked();
    /* Prepare and teardown tasks are not cancelled, but are waited for. */
    g_done_cv.wait(lock, [] {
        return g_queue.empty() && g_running == nullptr;
    });
    return MXQ_OK;
}

} /* namespace search */
} /* namespace mxq */

/* ------------------------------------------------------------------------- */
/* The C surface                                                             */
/* ------------------------------------------------------------------------- */

extern "C" {

MxqStatus mxq_engine_prepare(MxqCore *core, MxqGameKind game,
                                      const MxqEngineBudget *budget,
                                      MxqEnginePlan *out_applied,
                                      MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (!mxq::notation::searched(game)) {
        assert(false && "no engine searches this game");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "no engine searches this game, so there is nothing to "
                        "prepare for it");
        return MXQ_ERR_ARG_RANGE;
    }
    MxqEnginePlan plan;
    std::memset(&plan, 0, sizeof(plan));
    plan.struct_size = static_cast<uint32_t>(sizeof(plan));
    rc = mxq::engine_plan(budget, &plan, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    rc = mxq::begin_out(out_applied,
                        out_applied != nullptr ? out_applied->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqEnginePlan)),
                        static_cast<uint32_t>(sizeof(MxqEnginePlan)), err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /* Never substitute a smaller Hash. */
    if (plan.sufficient == 0) {
        mxq::fill_error(err, MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY,
                        "the calculated Hash budget is below the accepted "
                        "minimum; nothing was initialised");
        return MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY;
    }

    auto task = std::make_shared<mxq::search::Task>();
    task->kind = mxq::search::Task::Kind::Prepare;
    task->game = game;
    task->threads = plan.threads;
    task->hash_mib = plan.hash_mib;
    task->assets_dir = core->asset_directory;

    rc = mxq::search::marshal(task, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    const uint32_t writable = out_applied->struct_size;
    plan.struct_size = writable;
    std::memcpy(out_applied, &plan, writable);
    return MXQ_OK;
}

MxqStatus mxq_engine_teardown(MxqCore *core, MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    /* Cancels nothing: with a search outstanding marshal refuses. */
    auto task = std::make_shared<mxq::search::Task>();
    task->kind = mxq::search::Task::Kind::Teardown;
    return mxq::search::marshal(task, err);
}

MxqStatus mxq_engine_query(MxqCore *core, MxqEngineState *out_state,
                                    char *out_profile_id, size_t cap,
                                    size_t *out_len, MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_state == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "out_state was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_state =
        mxq::search::g_engine_state.load(std::memory_order_acquire);
    return mxq::write_string(mxq::search::profile_id().c_str(), out_profile_id,
                             cap, out_len, err);
}

/* Composed by the same function as the query's answer, because callers compare
 * the two. */
MxqStatus mxq_engine_profile_id(MxqGameKind game, char *out,
                                         size_t cap, size_t *out_len,
                                         MxqError *err) {
    const MxqStatus rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (!mxq::notation::searched(game)) {
        assert(false && "no engine searches this game");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "no engine searches this game, so there is no profile "
                        "identifier to name it by");
        return MXQ_ERR_ARG_RANGE;
    }
    return mxq::write_string(mxq::search::profile_id_of(game).c_str(), out, cap,
                             out_len, err);
}

MxqStatus mxq_search_start(MxqCore *core, MxqGameKind game,
                           const char *start_fen, const char *const *moves,
                           size_t move_count, uint32_t movetime_ms,
                           MxqSearchCallback callback, void *user_data,
                           uint64_t *out_ticket, MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_ticket == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "out_ticket was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_ticket = 0;
    rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    return mxq::search::start(game, start_fen, moves, move_count, movetime_ms,
                              callback, user_data, out_ticket, err);
}

MxqStatus mxq_search_cancel(MxqCore *core, uint64_t ticket,
                                     MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    std::lock_guard<std::mutex> lock(mxq::search::g_mutex);
    for (const auto &task : mxq::search::g_queue) {
        if (task->kind == mxq::search::Task::Kind::Search &&
            task->ticket == ticket) {
            task->cancelled.store(true, std::memory_order_release);
            return MXQ_OK;
        }
    }
    if (mxq::search::g_running != nullptr &&
        mxq::search::g_running->kind == mxq::search::Task::Kind::Search &&
        mxq::search::g_running->ticket == ticket) {
        mxq::search::g_running->cancelled.store(true,
                                                std::memory_order_release);
        mxq::search::abort_all();
    }
    return MXQ_OK;
}

} /* extern "C" */
