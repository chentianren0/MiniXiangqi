/*
 * The search facade: mxq_engine_prepare/teardown/query, the mxq_search_
 * group, and mxq_core_cancel_all.
 *
 * The design, from docs/core-interface.md's threading contract:
 *
 * The core creates exactly one internal thread — the engine thread, the sole
 * caller of every engine entry point. It is a dispatcher over a task queue:
 * preparation, teardown and searches all execute on it, which is what makes
 * "engine reconfiguration serialises behind search" structural rather than
 * policed, and it is the thread every completion callback is delivered on.
 * The engine's own pool threads (Threads.set) are the engine's internals
 * behind the bridge, not callers of anything here.
 *
 * mxq_search_start never retains the session: it snapshots the initial FEN,
 * the complete move list, the game_id, the session's instance_id, the
 * position_revision and the frozen movetime under the session's single-owner
 * guard, and returns a ticket. mxq_search_start_hint makes the same snapshot
 * for a different question — the move to show the player, rather than the move
 * the AI is about to play — and what reaches the engine thread is one kind of
 * job either way, so a hint's ticket, cancellation, staleness, ladder,
 * retention and callback are the reply's. The two differ only in what they
 * validate before enqueuing: see Purpose below.
 *
 * The engine thread later drives the engine over the snapshot and applies the
 * rejection ladder at delivery, in the contract's order:
 *
 *   1. cancelled — asked first, and also honoured at pickup, so a cancelled
 *      job never burns its movetime. A cancellation that follows no mutation
 *      (the platform-suspension path) leaves the revision matching, so this
 *      rung is the only one that rejects that late result.
 *   2. stale — position_revision against the origin session resolved by its
 *      instance_id, by value, through mxq::session::current_revision_of. The
 *      instance identity is what makes the revision comparable at all: a
 *      game_id is shared by every session of one stored game across a
 *      release-and-resume while each session's counter restarts at zero, so
 *      only the counter of the very session the search was started on can
 *      say whether the position moved. A released or absent origin rejects
 *      here: a result that cannot be shown fresh against the session it came
 *      from is not delivered as a move. This is one of two comparisons by
 *      design; the frontend compares again before applying, because neither
 *      alone covers both race directions.
 *   3. the engine's own typed failure — no move, a snapshot that stopped
 *      replaying, an engine no longer prepared — as MXQ_SEARCH_FAILED with
 *      the typed engine-domain status. Slotted after stale because a failure
 *      against a position nobody is at any more is the stale fact, not the
 *      failure. A *fault* is recorded in the engine state ahead of the
 *      ladder, whatever rung then classifies the result: an engine that can
 *      no longer be trusted is a fact about the engine, not about this
 *      result's delivery.
 *   4. malformed — the engine returned text that is not a move of this
 *      notation at all.
 *   5. illegal — the well-formed move is replayed against the snapshot
 *      through the same rules facade every legality answer comes from.
 *
 * Only a survivor arrives as MXQ_SEARCH_MOVE. The callback runs on the engine
 * thread inside the reentrancy guard; the result is then retained under its
 * ticket for mxq_search_poll/mxq_search_wait — equivalent consumers — until
 * the next search or shutdown.
 *
 * The facade's state is process-global like the bridge's, because the engine
 * it fronts is process-global; MxqCore is singleton-enforced for exactly this
 * reason. All facade state is guarded by one mutex, which is never held while
 * calling into the bridge, the session registry, or a callback.
 */

#include "mxq_search.hpp"

#include "mxq_build_config.h"
#include "mxq_core_state.hpp"
#include "mxq_engine_bridge.hpp"
#include "mxq_internal.hpp"
#include "mxq_notation.hpp"
#include "mxq_rules.hpp"
#include "mxq_session.hpp"

#if defined(MXQ_ENABLE_GOMOKU_FACADE)
#include "mxq_rapfi_bridge.hpp"
#endif

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

    /* Search: the snapshot, and nothing of the session but values.
     * origin_instance names the session the search was started on — the
     * registry's process-unique, never-reused identity, so a later session
     * of the same game (or an allocator's reuse of the same address) can
     * never stand in for it at delivery. */
    uint64_t                 ticket = 0;
    MxqGameKind              game = MXQ_GAME_KIND_MINI_XIANGQI;
    std::string              start_fen;
    std::vector<std::string> moves;
    std::string              game_id;
    uint64_t                 origin_instance = 0;
    uint64_t                 position_revision = 0;
    uint32_t                 movetime_ms = 0;
    MxqCore                 *core = nullptr;
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
std::condition_variable g_done_cv;   /* wakes waiters: poll/wait, marshalled
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

/* The one retained result: under its ticket until the next search or
 * shutdown. */
bool g_retained_valid = false;
MxqSearchResult g_retained{};

/* The profile identifier: the core revision, the revision of the engine fork
 * this game is played on, and the two per-game facts MxqGameProfile reports,
 * composed once into the bounded string mxq_engine_query and every result report
 * carry. Twelve characters of each revision and of the network hash name a build
 * as unambiguously as the axes themselves do at this scale, and keep the whole
 * under MXQ_PROFILE_ID_CAP.
 *
 * The fork revision is the one the game's own engine is vendored at. Naming the
 * first engine's for a game the second one plays would attribute a move to a
 * build that had nothing to do with it. */
std::string compose_profile_id(MxqGameKind game) {
    const auto first12 = [](const char *value) {
        const std::string s(value);
        return s.size() > 12 ? s.substr(0, 12) : s;
    };
#if defined(MXQ_ENABLE_GOMOKU_FACADE)
    if (notation::move_class_of(game) == notation::MoveClass::Placement) {
        const rapfi::Rules rules = rapfi::rules_of(game);
        return first12(MXQ_BUILD_CORE_REVISION) + "-" +
               first12(rapfi::fork_revision()) + "-" +
               rapfi::rules_variant_id(rules) + "-" +
               first12(rapfi::rules_nnue_sha256(rules));
    }
#endif
    const engine::Variant variant = engine::variant_of(game);
    return first12(MXQ_BUILD_CORE_REVISION) + "-" +
           first12(MXQ_BUILD_FORK_REVISION) + "-" +
           engine::variant_id(variant) + "-" +
           first12(engine::variant_nnue_sha256(variant));
}

/* The profile of one game, composed once each. Three of the four parts are that
 * game's own, so the identifier is: a move produced for one game must not be
 * attributed to another's network. */
const std::string &profile_id_of(MxqGameKind game) {
    static const std::string composed[] = {
        compose_profile_id(MXQ_GAME_KIND_MINI_XIANGQI),
        compose_profile_id(MXQ_GAME_KIND_XIANGQI),
#if defined(MXQ_ENABLE_GOMOKU_FACADE)
        compose_profile_id(MXQ_GAME_KIND_GOMOKU_15),
        compose_profile_id(MXQ_GAME_KIND_RENJU),
#endif
    };
    const size_t count = sizeof(composed) / sizeof(composed[0]);
    assert(notation::known_game(game) && static_cast<size_t>(game) < count &&
           "a game outside the closed vocabulary");
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

/* The frozen canonical notation, checked over the engine's own output: the
 * malformed rung judges the engine exactly as the session surface judges a
 * caller. */
/* ---------------------------------------------------------------------- */
/* The engine thread                                                       */
/* ---------------------------------------------------------------------- */

#if defined(MXQ_ENABLE_GOMOKU_FACADE)
/* Whether this game is played on the second engine. One question, asked from the
 * notation table, so that the dispatch below and the rules dispatch in
 * mxq_rules.cpp cannot ever answer it differently. It exists only where that
 * engine does: without it this core carries no game it could answer yes for. */
bool played_on_gomoku_engine(MxqGameKind game) {
    return notation::move_class_of(game) == notation::MoveClass::Placement;
}
#endif

/* Release every engine. Both bridges are idempotent about it and neither is
 * expensive when nothing is configured, and calling both is what makes "one
 * engine is prepared at a time" true rather than merely intended. */
void deconfigure_all() {
    engine::deconfigure();
#if defined(MXQ_ENABLE_GOMOKU_FACADE)
    rapfi::deconfigure();
#endif
}

/* Ask whichever engine is running to stop. Both are asked, for the same reason
 * both are released: the facade knows a search is outstanding and the cheapest
 * correct thing is to tell both, each of which is a flag store on an engine that
 * is not thinking. */
void abort_all() {
    engine::search_abort();
#if defined(MXQ_ENABLE_GOMOKU_FACADE)
    rapfi::search_abort();
#endif
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
#if defined(MXQ_ENABLE_GOMOKU_FACADE)
    if (played_on_gomoku_engine(task.game)) {
        engine::deconfigure();
        switch (rapfi::configure(rapfi::rules_of(task.game), task.threads,
                                 task.hash_mib, task.assets_dir, detail)) {
        case rapfi::ConfigureError::None:
            status = MXQ_OK;
            break;
        case rapfi::ConfigureError::InsufficientMemory:
            /* Only rapfi::prepare returns it, and the facade computes the plan
             * itself and refuses below the minimum before it ever gets here. */
            status = MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY;
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
#endif
    {
#if defined(MXQ_ENABLE_GOMOKU_FACADE)
        rapfi::deconfigure();
#endif
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

#if defined(MXQ_ENABLE_GOMOKU_FACADE)
    if (played_on_gomoku_engine(task.game)) {
        /* The second engine speaks points, and the snapshot is text. Every one
         * of these was a legal move when the session accepted it, so a ply that
         * does not parse is an invariant breach rather than a rules answer. */
        std::vector<rapfi::Point> points;
        points.reserve(task.moves.size());
        for (const std::string &move : task.moves) {
            int32_t file = 0;
            int32_t rank = 0;
            if (!notation::point_of_square(task.game, move.c_str(), file,
                                           rank)) {
                detail = "the snapshot carries a ply that is not a point of "
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
#endif

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
 * everything it needs from the task is owned by the task, the staleness
 * answer comes from the session registry under that registry's own lock, and
 * the legality answer from the rules bridge under the bridge's.
 */
void run_search(Task &task) {
    MxqSearchResult result;
    std::memset(&result, 0, sizeof(result));
    result.struct_size = static_cast<uint32_t>(sizeof(result));
    result.move.struct_size = static_cast<uint32_t>(sizeof(result.move));
    result.ticket = task.ticket;
    result.position_revision = task.position_revision;
    result.status = MXQ_OK;
    copy_bounded(result.game_id, sizeof(result.game_id), task.game_id.c_str());
    /* The profile of the game this search is for, not of whatever the engine
     * happens to be configured for now: a delivered result names the
     * configuration it was produced by, and mxq_search_start already refused a
     * session whose game the engine is not prepared for. */
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
     * the engine rather than about this result's delivery: a cancelled or
     * stale classification below must not leave a faulted engine trusted for
     * the next search. A position with no move is the engine answering, not a
     * fault. */
    if (engine_ran && ran.faulted) {
        g_engine_state.store(MXQ_ENGINE_STATE_FAULTED,
                             std::memory_order_release);
    }

    /* The rejection ladder, in the contract's order. */
    for (;;) {
        /* 1. Cancelled. The suspension path: no mutation, matching revision,
         * and this rung is the only one that rejects the late result. */
        if (task.cancelled.load(std::memory_order_acquire)) {
            result.outcome = MXQ_SEARCH_CANCELLED;
            break;
        }

        /* 2. Stale, by value against the origin session, resolved by its
         * never-reused instance identity — the only counter this search's
         * revision is comparable with. */
        uint64_t current = 0;
        if (!session::current_revision_of(task.core, task.origin_instance,
                                          task.game_id.c_str(), current) ||
            current != task.position_revision) {
            result.outcome = MXQ_SEARCH_STALE;
            break;
        }

        /* 3. The engine's own typed failure, engine-domain by contract. */
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
             * fault — or the snapshot stopped replaying under it, which was
             * legal when the session accepted it and means the engine side can
             * no longer be trusted until it is torn down and prepared again.
             * That state transition already happened above, ahead of the
             * ladder. */
            result.status = engine_ran ? ran.status : MXQ_ERR_ENGINE_FAULTED;
            break;
        }

        result.score_cp = ran.score_cp;
        result.depth = ran.depth;
        result.nodes = ran.nodes;

        /* 4. Malformed. */
        /* Judged against the board and the move class of the game this search
         * is for, through the same authority the session surface judges a
         * caller with. */
        if (!notation::well_formed_move(task.game, ran.move)) {
            result.outcome = MXQ_SEARCH_MALFORMED;
            break;
        }

        /* 5. Illegal under the rules facade: the snapshot plus the proposed
         * move, replayed through the same facade every other legality answer
         * comes from. */
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
                 * being refused but the snapshot no longer agreeing with
                 * itself. */
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
     * with the result borrowed for the duration of the call — then retention
     * under the ticket for the poll/wait consumers. */
    if (task.callback != nullptr) {
        CallbackScope scope;
        task.callback(&result, task.user_data);
    }
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_retained = result;
        g_retained_valid = true;
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

/* Which entry a search came in through. The job is the same job either way —
 * one Task, one ladder, one delivery — and this decides only what is demanded
 * of the session before it is enqueued. */
enum class Purpose { Reply, Hint };

/*
 * The half both search entries share: the session's handle checks, the
 * single-owner guard, the state each purpose demands under it, the snapshot,
 * and the enqueue.
 *
 * The snapshot is made under the guard and is values only, so it can never
 * interleave with a mutation, and the session is not retained. What makes a
 * thinking time legal is the one thing the two entries do not agree about, so
 * each judges movetime_ms itself, here, where the session it is judged against
 * is held.
 */
MxqStatus start(MxqCore *core, const MxqGame *game, Purpose purpose,
                uint32_t movetime_ms, MxqSearchCallback callback,
                void *user_data, uint64_t *out_ticket, MxqError *err) {
    MxqStatus rc = session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (game->core != core) {
        assert(false && "the session was not issued by this core");
        fill_error(err, MXQ_ERR_ARG_INVALID_HANDLE,
                   "the session was not issued by this core");
        return MXQ_ERR_ARG_INVALID_HANDLE;
    }

    /* Taking an MxqGame * counts as being inside the session: the snapshot is
     * made under the single-owner guard, so it can never interleave with a
     * mutation. */
    session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return session::concurrent_use(err);
    }

    if (purpose == Purpose::Reply) {
        /* The request's movetime must equal the session's frozen movetime. A
         * session with no frozen movetime — Free Play — owes no search and has
         * nothing for the request to equal, so a zero never passes. */
        if (game->config.ai_movetime_ms == 0 ||
            movetime_ms != game->config.ai_movetime_ms) {
            fill_error(err, MXQ_ERR_ARG_RANGE,
                       "request movetime_ms must equal the session's frozen "
                       "ai_movetime_ms");
            return MXQ_ERR_ARG_RANGE;
        }
    } else {
        /*
         * The thinking time is an input here rather than a cross-check, and
         * two kinds of value are legal: one of the levels the product offers,
         * and whatever this game itself froze. The second is not a convenience.
         * A game keeps the thinking time it was created with however the levels
         * are retuned afterwards, so a resumed game's own frozen value is the
         * honest thing to think for in it, and a hint asked at it is two
         * independently-built components agreeing about that game rather than a
         * caller stepping outside a vocabulary it owns. Zero is not such a
         * value: a Free Play session froze none, and there is nothing to think
         * for zero milliseconds about.
         *
         * Report-only, like the reply's cross-check and for the same reason:
         * what a mismatch here reports is a level pairing that has moved since
         * the game was created, not a caller that could not have got here
         * honestly.
         */
        if (movetime_ms != MXQ_MOVETIME_FAST_MS &&
            movetime_ms != MXQ_MOVETIME_STANDARD_MS &&
            movetime_ms != MXQ_MOVETIME_DEEP_MS &&
            !(game->config.ai_movetime_ms != 0 &&
              movetime_ms == game->config.ai_movetime_ms)) {
            fill_error(err, MXQ_ERR_ARG_RANGE,
                       "movetime_ms must be one of the accepted thinking times "
                       "or this session's own frozen ai_movetime_ms");
            return MXQ_ERR_ARG_RANGE;
        }
        /*
         * A hint proposes a move this session could take, so the states that
         * would take no move are the states that have none to suggest: this is
         * mxq_game_apply_move's own gate, asked before the search rather than
         * after it. A claimable neutral repetition passes both.
         */
        rc = session::require_mutable(game, err);
        if (rc != MXQ_OK) {
            return rc;
        }
        rc = session::require_no_result(game, err);
        if (rc != MXQ_OK) {
            return rc;
        }
    }

    auto task = std::make_shared<Task>();
    task->kind = Task::Kind::Search;
    task->game = game->config.game;
    task->start_fen = notation::start_fen(game->config);
    task->moves = game->moves;
    task->game_id = game->game_id;
    task->position_revision =
        game->position_revision.load(std::memory_order_acquire);
    task->movetime_ms = movetime_ms;
    task->origin_instance = game->instance_id;
    task->core = core;
    task->callback = callback;
    task->user_data = user_data;

    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (g_exiting || !g_thread_live) {
            fill_error(err, MXQ_ERR_STATE_SHUTTING_DOWN,
                       "the core is shutting down");
            return MXQ_ERR_STATE_SHUTTING_DOWN;
        }
        /* Checked under the enqueue's lock, and re-checked when the job runs:
         * a teardown already queued ahead of this search leaves the state
         * READY here and turns the run-time check into the answer. */
        if (g_engine_state.load(std::memory_order_acquire) !=
            MXQ_ENGINE_STATE_READY) {
            fill_error(err, MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "the engine is not prepared");
            return MXQ_ERR_STATE_ENGINE_NOT_READY;
        }
        /*
         * One game is prepared at a time, and it is this session's game that
         * must be the one: the tables a search reads are the prepared game's, so
         * a session of another would fail to replay under them and be delivered
         * as a fault — and where the two games are played on different engines,
         * the prepared engine has no notion of the other's board at all.
         * Refusing here says the true thing instead — the engine is not ready
         * for THIS game — and the caller prepares for it.
         *
         * It is asked after the state, not before, because a core that has
         * prepared nothing has no prepared game to compare against: asking first
         * would answer with "prepared for another game" on a core that prepared
         * none, and send the caller to correct the wrong thing.
         */
        if (g_prepared_game.load(std::memory_order_acquire) !=
            game->config.game) {
            fill_error(err, MXQ_ERR_STATE_ENGINE_NOT_READY,
                       "the engine is prepared for the other game; "
                       "prepare it for this session's game first");
            return MXQ_ERR_STATE_ENGINE_NOT_READY;
        }
        /*
         * A hint is asked for one position and is worth nothing against
         * another, so it is refused rather than queued behind whatever the
         * engine thread is already doing — the AI's reply or an earlier hint
         * alike. The reply keeps its own behaviour: a game owes it, and a
         * caller that asks for it twice is asking about the same position.
         * Checked under the enqueue's own lock, because separately it would be
         * a check-then-act.
         */
        if (purpose == Purpose::Hint && search_outstanding_locked()) {
            fill_error(err, MXQ_ERR_STATE_SEARCH_IN_PROGRESS,
                       "a search is outstanding; cancel it or wait for it "
                       "before asking for a hint");
            return MXQ_ERR_STATE_SEARCH_IN_PROGRESS;
        }
        task->ticket = g_next_ticket++;
        /* The previous result was retained until the next search; this is the
         * next search. */
        g_retained_valid = false;
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
    g_retained_valid = false;
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
        /* The retained result does not survive shutdown. */
        g_retained_valid = false;
        std::memset(&g_retained, 0, sizeof(g_retained));
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

MxqStatus MXQ_CALL mxq_engine_prepare(MxqCore *core, MxqGameKind game,
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
    /* The same plan mxq_engine_plan computes, recomputed from the caller's
     * fresh probe: a later game never silently reuses an earlier game's
     * memory decision. */
    MxqEnginePlan plan;
    std::memset(&plan, 0, sizeof(plan));
    plan.struct_size = static_cast<uint32_t>(sizeof(plan));
    rc = mxq_engine_plan(budget, &plan, err);
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

MxqStatus MXQ_CALL mxq_engine_teardown(MxqCore *core, MxqError *err) {
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

MxqStatus MXQ_CALL mxq_engine_query(MxqCore *core, MxqEngineState *out_state,
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
MxqStatus MXQ_CALL mxq_engine_profile_id(MxqGameKind game, char *out,
                                         size_t cap, size_t *out_len,
                                         MxqError *err) {
    const MxqStatus rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    return mxq::write_string(mxq::search::profile_id_of(game).c_str(), out, cap,
                             out_len, err);
}

MxqStatus MXQ_CALL mxq_search_start(MxqCore *core, const MxqGame *game,
                                    const MxqSearchRequest *request,
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
    rc = mxq::check_in(request, request != nullptr ? request->struct_size : 0u,
                       static_cast<uint32_t>(sizeof(MxqSearchRequest)),
                       static_cast<uint32_t>(sizeof(MxqSearchRequest)), err);
    if (rc != MXQ_OK) {
        return rc;
    }
    return mxq::search::start(core, game, mxq::search::Purpose::Reply,
                              request->movetime_ms, callback, user_data,
                              out_ticket, err);
}

MxqStatus MXQ_CALL mxq_search_start_hint(MxqCore *core, const MxqGame *game,
                                         uint32_t movetime_ms,
                                         MxqSearchCallback callback,
                                         void *user_data, uint64_t *out_ticket,
                                         MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_ticket == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "out_ticket was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_ticket = 0;
    /* The thinking time is judged against the session, inside start(): what is
     * accepted is a level or this game's own frozen value, and the second of
     * those is not a fact this entry holds before the session is held. */
    return mxq::search::start(core, game, mxq::search::Purpose::Hint,
                              movetime_ms, callback, user_data, out_ticket,
                              err);
}

MxqStatus MXQ_CALL mxq_search_cancel(MxqCore *core, uint64_t ticket,
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

MxqStatus MXQ_CALL mxq_search_cancel_all(MxqCore *core, MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    std::lock_guard<std::mutex> lock(mxq::search::g_mutex);
    mxq::search::cancel_all_locked();
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_search_poll(MxqCore *core, uint64_t ticket,
                                   MxqSearchResult *out, uint8_t *out_ready,
                                   MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_ready == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "out_ready was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_ready = 0;
    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqSearchResult)),
                        static_cast<uint32_t>(sizeof(MxqSearchResult)), err);
    if (rc != MXQ_OK) {
        return rc;
    }
    std::lock_guard<std::mutex> lock(mxq::search::g_mutex);
    if (mxq::search::g_retained_valid &&
        mxq::search::g_retained.ticket == ticket) {
        const uint32_t writable = out->struct_size;
        MxqSearchResult result = mxq::search::g_retained;
        result.struct_size = writable;
        std::memcpy(out, &result, writable);
        *out_ready = 1;
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_search_wait(MxqCore *core, uint64_t ticket,
                                   uint32_t timeout_ms, MxqSearchResult *out,
                                   uint8_t *out_ready, MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_ready == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "out_ready was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_ready = 0;
    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqSearchResult)),
                        static_cast<uint32_t>(sizeof(MxqSearchResult)), err);
    if (rc != MXQ_OK) {
        return rc;
    }

    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::milliseconds(timeout_ms);
    std::unique_lock<std::mutex> lock(mxq::search::g_mutex);
    for (;;) {
        if (mxq::search::g_retained_valid &&
            mxq::search::g_retained.ticket == ticket) {
            const uint32_t writable = out->struct_size;
            MxqSearchResult result = mxq::search::g_retained;
            result.struct_size = writable;
            std::memcpy(out, &result, writable);
            *out_ready = 1;
            return MXQ_OK;
        }
        /* A ticket that is neither pending nor retained can never become
         * ready — it was superseded or never issued — so waiting the timeout
         * out for it would be a stall with a known answer. Timing out and
         * that answer are the same answer: *out_ready 0, MXQ_OK. */
        bool pending = false;
        for (const auto &task : mxq::search::g_queue) {
            if (task->kind == mxq::search::Task::Kind::Search &&
                task->ticket == ticket) {
                pending = true;
                break;
            }
        }
        if (!pending && mxq::search::g_running != nullptr &&
            mxq::search::g_running->kind ==
                mxq::search::Task::Kind::Search &&
            mxq::search::g_running->ticket == ticket) {
            pending = true;
        }
        if (!pending) {
            return MXQ_OK;
        }
        if (mxq::search::g_done_cv.wait_until(lock, deadline) ==
            std::cv_status::timeout) {
            return MXQ_OK;
        }
    }
}

} /* extern "C" */
