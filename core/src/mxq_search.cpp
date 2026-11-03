/*
 * The search facade: mxq_engine_prepare/teardown/query, mxq_search_start and
 * mxq_search_cancel, and mxq_core_cancel_all.
 *
 * The core has one internal thread, the engine thread, which is the sole
 * caller of every engine entry point. It runs a queue of preparations,
 * teardowns and searches, which is what makes reconfiguration wait behind a
 * search structurally, and it is the thread every callback is delivered on.
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

    /* Search: the copied line. */
    uint64_t                 ticket = 0;
    MxqGameKind              game = MXQ_GAME_KIND_MINI_XIANGQI;
    std::string              start_fen;
    std::vector<std::string> moves;
    uint32_t                 movetime_ms = 0;
    MxqSearchCallback        callback = nullptr;
    void                    *user_data = nullptr;
    std::atomic<bool>        cancelled{false};

    /* Prepare: the game to prepare for, the applied plan values, and the asset
     * directory. */
    uint32_t    threads = 0;
    uint32_t    hash_mib = 0;
    std::string assets_dir;

    /* Prepare/Teardown completion, read by the marshalling caller. */
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
 * The game an engine is prepared for, or -1 when none is.
 *
 * The facade holds this rather than asking a bridge, and that is the change two
 * engines make: each bridge knows what it is configured for and neither knows
 * whether the other is, so "which game would a search run in" is a question only
 * the thing that dispatches between them can answer. Written on the engine
 * thread by preparation and teardown; read by mxq_search_start and
 * mxq_engine_query on any thread, which is why it is atomic.
 */
std::atomic<int32_t> g_prepared_game{-1};

/* The profile identifier: the core revision, the revision of the engine fork
 * this game is played on, and the two per-game facts MxqGameProfile reports,
 * composed once into the bounded string mxq_engine_query and every result report
 * carry. Twelve characters of each revision and of the network's SHA-256 name a
 * build as unambiguously as the axes themselves do at this scale, and keep the
 * whole under MXQ_PROFILE_ID_CAP.
 *
 * The fork revision is the one the game's own engine is vendored at. Naming the
 * first engine's for a game the second one plays would attribute a move to a
 * build that had nothing to do with it. */
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

/* The profile of one game, composed once each. Three of the four parts are that
 * game's own, so the identifier is: a move produced for one game must not be
 * attributed to another's network. */
const std::string &profile_id_of(MxqGameKind game) {
    static const std::string composed[] = {
        compose_profile_id(MXQ_GAME_KIND_MINI_XIANGQI),
        compose_profile_id(MXQ_GAME_KIND_XIANGQI),
        compose_profile_id(MXQ_GAME_KIND_GOMOKU_15),
        compose_profile_id(MXQ_GAME_KIND_RENJU),
    };
    const size_t count = sizeof(composed) / sizeof(composed[0]);
    /* One entry per searched game, so a game nothing searches has none: the
     * three entries that would ask for one refuse it first, and this is where
     * that is asserted rather than assumed. */
    assert(notation::known_game(game) && notation::searched(game) &&
           static_cast<size_t>(game) < count &&
           "a game no engine searches has no profile identifier");
    return composed[static_cast<size_t>(game) < count
                        ? static_cast<size_t>(game)
                        : 0u];
}

/* The profile of the configuration a move would be produced by right now: the
 * game an engine is prepared for. Before any preparation there is none, and what
 * is reported is the movement engine's own rules posture — its tables are built
 * for a variant whether or not anything asked for one, and that is what a search
 * would run in if one could start at all. */
const std::string &profile_id() {
    const int32_t prepared = g_prepared_game.load(std::memory_order_acquire);
    if (prepared >= 0) {
        return profile_id_of(static_cast<MxqGameKind>(prepared));
    }
    return profile_id_of(engine::active_variant() == engine::Variant::Xiangqi
                             ? MXQ_GAME_KIND_XIANGQI
                             : MXQ_GAME_KIND_MINI_XIANGQI);
}

/* Whether a search task is outstanding: queued or running. Caller holds
 * g_mutex. This is what MXQ_ERR_STATE_SEARCH_IN_PROGRESS reports. */
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

/* Whether this game is played on the second engine. One question, asked from the
 * notation table, so that the dispatch below and the rules dispatch in
 * mxq_rules.cpp cannot ever answer it differently. It exists only where that
 * engine does: without it this core carries no game it could answer yes for. */
bool played_on_gomoku_engine(MxqGameKind game) {
    return notation::move_class_of(game) == notation::MoveClass::Placement;
}

/* Release every engine. Both bridges are idempotent about it and neither is
 * expensive when nothing is configured, and calling both is what makes "one
 * engine is prepared at a time" true rather than merely intended. */
void deconfigure_all() {
    engine::deconfigure();
    rapfi::deconfigure();
}

/* Ask whichever engine is running to stop. Both are asked, for the same reason
 * both are released: the facade knows a search is outstanding and the cheapest
 * correct thing is to tell both, each of which is a flag store on an engine that
 * is not thinking. */
void abort_all() {
    engine::search_abort();
    rapfi::search_abort();
}

void run_prepare(Task &task) {
    std::string detail;
    MxqStatus   status = MXQ_OK;

    /*
     * The other engine is released first, and that is the shape of "one engine
     * is prepared at a time" with two of them. The memory plan is computed once
     * from one probe and sized for one transposition table; leaving the previous
     * engine holding its own would put two tables on a device the plan sized for
     * one. Releasing before configuring rather than after also means a failed
     * preparation leaves nothing prepared, which is what the observable state
     * below already promises.
     */
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
    /* configure() unwound whole; the observable state says so. */
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

/*
 * What one engine's run reported, in the terms the delivery ladder shares.
 *
 * The two engines have their own typed failures and their own move vocabulary —
 * one returns canonical text, the other a point — and what the ladder needs of
 * either is the same three facts: a move in this game's notation or none,
 * whether the engine can still be trusted afterwards, and the engine-domain
 * status a failure is delivered as. Translating each engine's answer into these
 * once, here, is what keeps the ladder one ladder.
 */
struct EngineRun {
    bool        produced = false;
    bool        faulted = false;
    MxqStatus   status = MXQ_OK;
    std::string move;
    int32_t     score_cp = 0;
    uint32_t    depth = 0;
    uint64_t    nodes = 0;
};

/* Drive the engine this task's game is played on. Caller: the engine thread,
 * with the engine prepared for that game. */
EngineRun run_engine(const Task &task, std::string &detail) {
    EngineRun out;

    if (played_on_gomoku_engine(task.game)) {
        /* The second engine speaks points, and the line is text. The line is
         * legal by the caller's contract, so a ply that does not parse is a
         * breach of it rather than a rules answer. */
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
            /* The engine answering a position it found no move in, which is not
             * a fault. */
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

/*
 * One search, engine work through delivery. Runs with no facade lock held:
 * everything it needs is owned by the task, and the legality answer comes from
 * the rules bridge under the bridge's own lock.
 */
void run_search(Task &task) {
    MxqSearchResult result;
    std::memset(&result, 0, sizeof(result));
    result.struct_size = static_cast<uint32_t>(sizeof(result));
    result.move.struct_size = static_cast<uint32_t>(sizeof(result.move));
    result.ticket = task.ticket;
    result.status = MXQ_OK;
    /* The profile of the game this search is for, not of whatever the engine
     * happens to be configured for now: mxq_search_start already refused a
     * game the engine is not prepared for. */
    copy_bounded(result.profile_id, sizeof(result.profile_id),
                 profile_id_of(task.game).c_str());

    /* The engine runs only for a job nobody has cancelled on an engine that
     * is still prepared; the ladder below decides what is delivered either
     * way. */
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

    /* A fault is recorded before the ladder runs, because it is a fact about
     * the engine rather than about this result's delivery: a cancelled result
     * must not leave a faulted engine trusted for the next search. A position
     * with no move is the engine answering, not a fault. */
    if (engine_ran && ran.faulted) {
        g_engine_state.store(MXQ_ENGINE_STATE_FAULTED,
                             std::memory_order_release);
    }

    /* The rejection ladder, in the contract's order. */
    for (;;) {
        /* 1. Cancelled. */
        if (task.cancelled.load(std::memory_order_acquire)) {
            result.outcome = MXQ_SEARCH_CANCELLED;
            break;
        }

        /* 2. The engine's own failure. */
        if (!ready) {
            /* Torn down or faulted between this search's acceptance and its
             * run; the synchronous MXQ_ERR_STATE_ENGINE_NOT_READY belongs to
             * mxq_search_start, not to a delivered result. */
            result.outcome = MXQ_SEARCH_FAILED;
            result.status = MXQ_ERR_ENGINE_NOT_PREPARED;
            break;
        }
        if (!engine_ran || !ran.produced) {
            result.outcome = MXQ_SEARCH_FAILED;
            /* Either the engine answered with no move — its own answer, not a
             * fault — or the line stopped replaying under it, which means the
             * engine can no longer be trusted until it is prepared again. That
             * state transition already happened above. */
            result.status = engine_ran ? ran.status : MXQ_ERR_ENGINE_FAULTED;
            break;
        }

        result.score_cp = ran.score_cp;
        result.depth = ran.depth;
        result.nodes = ran.nodes;

        /* 3. Malformed, against this game's board and move class. */
        if (!notation::well_formed_move(task.game, ran.move)) {
            result.outcome = MXQ_SEARCH_MALFORMED;
            break;
        }

        /* 4. Illegal: the line plus the proposed move, replayed through the
         * rules facade. */
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
                /* An earlier ply stopped replaying: not the engine's move
                 * being refused but the line itself. */
                result.outcome = MXQ_SEARCH_FAILED;
                result.status = MXQ_ERR_ENGINE_FAULTED;
                g_engine_state.store(MXQ_ENGINE_STATE_FAULTED,
                                     std::memory_order_release);
                break;
            }
        }

        /* The survivor. */
        result.outcome = MXQ_SEARCH_MOVE;
        copy_bounded(result.move.text, sizeof(result.move.text),
                     ran.move.c_str());
        break;
    }

    /* Delivery: the callback on this thread, inside the reentrancy guard,
     * with the result borrowed for the duration of the call. */
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
                /* Exiting with a drained queue: every outstanding callback
                 * has fired. */
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

/* Flag every outstanding search cancelled and stop the engine if one is
 * running. Caller holds g_mutex. Callbacks still fire, with the cancelled
 * outcome, when the engine thread delivers each flagged task. */
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
 * run it. The serialisation refusal is applied under the same lock as the
 * enqueue — checked separately it would be a check-then-act, and a search
 * slipping into the gap would put the reconfiguration behind a full movetime,
 * which is exactly the stall the contract refuses instead.
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

/*
 * Copy the line and enqueue it. The copy is values only, so the caller's line
 * may change the moment this returns.
 */
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
        /* Checked under the enqueue's lock, and again when the search runs: a
         * teardown already queued ahead of it turns the run-time check into
         * the answer. */
        if (g_engine_state.load(std::memory_order_acquire) !=
            MXQ_ENGINE_STATE_READY) {
            fill_error(err, MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "the engine is not prepared");
            return MXQ_ERR_STATE_ENGINE_NOT_READY;
        }
        /* The tables a search reads are the prepared game's, so a line of
         * another game would fail to replay under them. */
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
        /* Cancel all work. The engine thread drains the queue before it
         * exits, so every flagged task still delivers its callback with the
         * cancelled outcome. */
        cancel_all_locked();
        g_exiting = true;
    }
    g_engine_cv.notify_one();
    g_thread.join();
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_thread_live = false;
    }
    /* The engine thread is joined, so no search is running; release every
     * engine whole. Concurrent rules queries are safe against this — each
     * serialises on its own bridge's mutex. */
    deconfigure_all();
    g_prepared_game.store(-1, std::memory_order_release);
    g_engine_state.store(MXQ_ENGINE_STATE_UNINITIALIZED,
                         std::memory_order_release);
}

MxqStatus cancel_all_and_quiesce(MxqError *err) {
    (void)err;
    std::unique_lock<std::mutex> lock(g_mutex);
    cancel_all_locked();
    /* Block until the engine quiesces: the queue drained and the engine
     * thread idle, which is after every callback has fired. Prepare and
     * teardown tasks are not cancelled — they are not searches — but they
     * are quiesced behind all the same. */
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
    /* A game nothing searches has nothing to prepare, and asking is a
     * programming error by the reachability rule: the caller owns the game axis
     * and mxq.h states the absence. It is refused before the budget is read, so
     * nothing is computed and nothing is initialised. */
    if (!mxq::notation::searched(game)) {
        assert(false && "no engine searches this game");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "no engine searches this game, so there is nothing to "
                        "prepare for it");
        return MXQ_ERR_ARG_RANGE;
    }
    /* The plan, from the caller's fresh probe: a later game never reuses an
     * earlier game's memory decision. */
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

    /* Below the minimum: refuse without initialising anything, and never
     * substitute a smaller Hash. */
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

    /* Reconfiguration serialises behind search: refused inside marshal, under
     * the enqueue's own lock, rather than stalled. */
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
    /* Teardown cancels nothing itself: with a search outstanding it refuses
     * inside marshal, exactly as prepare does, and the caller cancels
     * first. */
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

/* The same string the query above would report once this game is prepared, and
 * it is composed by the same function for that reason: two compositions would
 * agree until the day one of them was edited, and the whole use of this entry is
 * a comparison against the other's answer. */
MxqStatus mxq_engine_profile_id(MxqGameKind game, char *out,
                                         size_t cap, size_t *out_len,
                                         MxqError *err) {
    const MxqStatus rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    /* The identifier a named game would be prepared under, so a game that is
     * never prepared has none: there is no engine revision, no rule and no
     * network for it to name, and no move for it to attribute. Refused exactly
     * as the preparation it stands to is. */
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
    /* An unknown or already-finished ticket is MXQ_OK: the caller asked for a
     * state — this search no longer runs — that already holds. */
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
