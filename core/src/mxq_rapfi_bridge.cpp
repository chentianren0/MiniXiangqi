/* The Rapfi bridge; see mxq_rapfi_bridge.hpp. */

#include "mxq_rapfi_bridge.hpp"

#include "mxq_build_config.h"
#include "mxq_notation.hpp"

/* The engine's headers are upstream's, and leave parameters unused. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-parameter"
#include "config.h"
#include "core/iohelper.h"
#include "core/pos.h"
#include "core/types.h"
#include "eval/evalconfig.h"
#include "eval/evaluator.h"
#include "game/board.h"
#include "search/ab/searcher.h"
#include "search/hashtable.h"
#include "search/searchcommon.h"
#include "search/searchengine.h"
#include "search/searcher.h"
#include "search/searchthread.h"
#pragma clang diagnostic pop

#include <cassert>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

namespace mxq {
namespace rapfi {
namespace {

/* Everything pinned to one game, one row per game. mix9svq resolves a single
 * weight file as both sides' path, which is how the freestyle network is
 * published. */
struct WeightPin {
    const char *filename;
};

struct RulesPin {
    const char      *id;
    const char      *variant_id; /* the engine's own name for the rule, at the
                                  * one board size these games are played on */
    ::Rule           engine_rule;
    const char      *network_id; /* the one Black plays with names the pair */
    WeightPin        black;
    const WeightPin *white; /* null when `black` serves both sides */
};

constexpr WeightPin kRenjuWhite = {MXQ_BUILD_RENJU_WHITE_NNUE_FILENAME};

constexpr RulesPin kRulesPins[] = {
    {"gomoku-15",
     "freestyle15",
     ::Rule::FREESTYLE,
     MXQ_BUILD_GOMOKU_NNUE_ID,
     {MXQ_BUILD_GOMOKU_NNUE_FILENAME},
     nullptr},
    {"renju",
     "renju15",
     ::Rule::RENJU,
     MXQ_BUILD_RENJU_BLACK_NNUE_ID,
     {MXQ_BUILD_RENJU_BLACK_NNUE_FILENAME},
     &kRenjuWhite},
};

/* A new enumerator without a case warns at the switch; a case without a row
 * trips the assertion. Either would otherwise read past the table. */
static_assert(sizeof(kRulesPins) / sizeof(kRulesPins[0]) == 2,
              "one pinned row per Rules enumerator");

constexpr size_t pin_index(Rules rules) {
    switch (rules) {
    case Rules::Gomoku15:
        return 0u;
    case Rules::Renju:
        return 1u;
    }
    return 0u; /* unreachable: the switch is exhaustive */
}

const RulesPin &pin_of(Rules rules) {
    return kRulesPins[pin_index(rules)];
}

/* Only a starting value: nothing searches until configure() succeeds. */
constexpr Rules kInitialRules = Rules::Gomoku15;

/* Written only by configure() and deconfigure(), under g_mutex; read by
 * search_run() without the lock, hence atomic. */
std::atomic<Rules> g_active_rules{kInitialRules};
std::atomic<bool>  g_configured{false};

/* The engine's global state is process-wide and not re-entrant. */
std::mutex g_mutex;

/* The classical tables are rule-independent, so they load once per process. */
bool g_config_loaded = false;

/*
 * The engine writes every message and error to std::cout. messageMode silences
 * most, but not the config loader's, which run while the mode is being parsed,
 * and a library must not write to the host's standard output. So std::cout is
 * redirected around any call that can write, and messageMode is NONE as well.
 *
 * std::cout only: everything goes through iohelper.h's sync_cout(), including
 * ERRORL, so swapping std::cerr would only swallow the host's own diagnostics.
 */
class CoutSilencer {
public:
    CoutSilencer() : saved_(std::cout.rdbuf(&sink_)) {}
    ~CoutSilencer() { std::cout.rdbuf(saved_); }
    CoutSilencer(const CoutSilencer &) = delete;
    CoutSilencer &operator=(const CoutSilencer &) = delete;

private:
    /* Discards rather than buffers: it spans a whole search, which writes a
     * line per iteration. */
    struct Sink : std::streambuf {
        int overflow(int c) override { return c; }
        std::streamsize xsputn(const char *, std::streamsize n) override {
            return n;
        }
    };
    Sink            sink_;
    std::streambuf *saved_;
};

/* One selected weight file. */
struct WeightChoice {
    std::string      path;
    const WeightPin *pin;
};

/*
 * Gate 1, selection: the files this rule needs, by their pinned names. Unlike
 * Fairy-Stockfish, Rapfi reads the rule and board size from the file's header
 * and ignores its name, so there is no scan for misnamed candidates.
 */
bool select_weights(const std::string &assets_dir, Rules rules,
                    std::vector<WeightChoice> &out, std::string &detail) {
    namespace fs = std::filesystem;
    const fs::path  dir = assets_dir.empty() ? fs::path(".") : fs::path(assets_dir);
    const RulesPin &wanted = pin_of(rules);

    const WeightPin *pins[2] = {&wanted.black, wanted.white};
    for (const WeightPin *pin : pins) {
        if (pin == nullptr) {
            continue; /* one file serves both sides */
        }
        const fs::path path = dir / pin->filename;
        std::error_code ec;
        if (!fs::is_regular_file(path, ec)) {
            detail = "the weight file " + std::string(pin->filename) +
                     " pinned for " + wanted.id + " is not in " + dir.string();
            return false;
        }
        out.push_back({path.string(), pin});
    }
    return true;
}

/* Shared by deconfigure() and configure()'s unwind. Caller holds g_mutex.
 *
 * Threads first: each holds a board and an evaluator, which references the
 * weights, so dropping them releases the weights. The evaluator maker next, so
 * a later preparation cannot inherit one for the wrong rule. The table last,
 * released whole. */
void deconfigure_locked() {
    CoutSilencer silence;
    Search::Engine.stopThinking();
    Search::Engine.setNumThreads(0);
    Search::Engine.setupEvaluator(nullptr);
    Search::TT.resize(0);
    g_configured.store(false, std::memory_order_release);
}

/* The engine's embedded configuration: the classical evaluation and score
 * tables, which search uses for move ordering, and no [model.evaluator]
 * section, so it installs no weights that could fool gate 2.
 *
 * Not Command::loadConfig(): it looks in the working directory and next to
 * argv[0], where a stray config.toml would silently replace the configuration,
 * weights included. Config::loadConfig takes a stream and touches no files. */
bool load_internal_config(std::string &detail) {
    if (g_config_loaded) {
        return true;
    }
    if (Config::InternalConfig.empty()) {
        detail = "the engine was built without its internal configuration";
        return false;
    }
    std::istringstream stream(Config::InternalConfig);
    if (!Config::loadConfig(stream)) {
        detail = "the engine's internal configuration did not load";
        return false;
    }
    g_config_loaded = true;
    return true;
}

} /* namespace */

const char *rules_id(Rules rules) {
    return pin_of(rules).id;
}

Rules rules_of(MxqGameKind game) {
    switch (game) {
    case MXQ_GAME_KIND_GOMOKU_15:
        return Rules::Gomoku15;
    case MXQ_GAME_KIND_RENJU:
        return Rules::Renju;
    default:
        break;
    }
    /* notation::move_class_of routes only this engine's games here. */
    assert(false && "a game this engine does not play reached the bridge");
    return Rules::Gomoku15;
}

const char *rules_variant_id(Rules rules) {
    return pin_of(rules).variant_id;
}

const char *rules_network_id(Rules rules) {
    return pin_of(rules).network_id;
}

const char *fork_revision() {
    return MXQ_BUILD_GOMOKU_FORK_REVISION;
}

Rules active_rules() {
    return g_active_rules.load(std::memory_order_acquire);
}

bool is_configured() {
    return g_configured.load(std::memory_order_acquire);
}

/* ------------------------------------------------------------------------- */
/* The rules side                                                            */
/* ------------------------------------------------------------------------- */

namespace {

/*
 * The engine's BLACK moves first; the core's MXQ_COLOR_RED is always the side
 * that moves first. So the core's "red" is drawn as a black stone here.
 */
MxqColor color_of(::Color side) {
    return side == BLACK ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
}

/* Which state a completed five gives, for the side that completed it. */
MxqGameState win_for(::Color side) {
    return side == BLACK ? MXQ_GAME_RED_WINS : MXQ_GAME_BLACK_WINS;
}

/*
 * The body of replay(), with g_mutex held; replay() catches what it throws.
 *
 * A point is forbidden exactly when Board::checkForbiddenPoint says so, which
 * resolves the recursive double-three cases the table's first pass does not. A
 * placement completes a five exactly when the point's Pattern4 for the mover is
 * A_FIVE, read before the stone lands. The tables are built per rule and side,
 * so that one read carries the rule differences:
 *
 *   - Freestyle checks no overline, so six in a row wins for either side.
 *   - Renju checks the overline for Black alone, so Black's six is FORBID and
 *     White's six still wins.
 *   - A five that is also a double-four or double-three is a five: A_FIVE is
 *     classified before anything is forbidden.
 */
ReplayError replay_locked(MxqGameKind game, const char *const *moves,
                          size_t move_count, std::string &out_fen,
                          uint32_t &out_ply, Adjudication &out_adj,
                          std::vector<std::string> *out_legal_moves,
                          size_t &first_illegal, std::string &detail) {
    const RulesPin &pin = pin_of(rules_of(game));
    const bool      renju = pin.engine_rule == ::Rule::RENJU;

    Board board(kBoardSize);
    board.newGame(pin.engine_rule);

    out_adj.state = MXQ_GAME_ONGOING;
    out_adj.reason = MXQ_END_REASON_NONE;

    for (size_t i = 0; i < move_count; ++i) {
        const char *text = (moves == nullptr) ? nullptr : moves[i];
        int32_t     file = 0;
        int32_t     rank = 0;
        if (text == nullptr ||
            !mxq::notation::point_of_square(game, text, file, rank)) {
            first_illegal = i;
            detail = "ply " + std::to_string(i) + " is not a point of this board";
            return ReplayError::IllegalMove;
        }
        /* A move after the game ended is refused at its own ply, which is the
         * index MXQ_ERR_RULES_INVALID_HISTORY reports. */
        if (out_adj.state != MXQ_GAME_ONGOING) {
            first_illegal = i;
            detail = "ply " + std::to_string(i) + " follows the end of the game";
            return ReplayError::IllegalMove;
        }
        const Pos pos(file, rank);
        if (!board.isEmpty(pos)) {
            first_illegal = i;
            detail = "ply " + std::to_string(i) + " places a stone on an "
                     "occupied point";
            return ReplayError::IllegalMove;
        }
        const ::Color mover = board.sideToMove();
        if (renju && mover == BLACK && board.checkForbiddenPoint(pos)) {
            first_illegal = i;
            detail = "ply " + std::to_string(i) + " is a forbidden point for "
                     "Black under these rules";
            return ReplayError::IllegalMove;
        }

        const Pattern4 completed = board.pattern4(pos, mover);
        board.move(pin.engine_rule, pos);

        if (completed == A_FIVE) {
            out_adj.state = win_for(mover);
            out_adj.reason = MXQ_END_REASON_FIVE_IN_A_ROW;
        } else if (board.movesLeft() == 0) {
            out_adj.state = MXQ_GAME_DRAW;
            out_adj.reason = MXQ_END_REASON_BOARD_FULL;
        }
    }

    out_ply = static_cast<uint32_t>(move_count);

    std::vector<MxqColor> cells(static_cast<size_t>(kBoardSize) *
                                    static_cast<size_t>(kBoardSize),
                                MXQ_COLOR_NONE);
    for (int32_t rank = 0; rank < kBoardSize; ++rank) {
        for (int32_t file = 0; file < kBoardSize; ++file) {
            const ::Color cell = board.get(Pos(file, rank));
            if (cell == BLACK || cell == WHITE) {
                cells[static_cast<size_t>(rank) *
                          static_cast<size_t>(kBoardSize) +
                      static_cast<size_t>(file)] = color_of(cell);
            }
        }
    }
    assert(color_of(board.sideToMove()) ==
               ((move_count % 2u == 0u) ? MXQ_COLOR_RED : MXQ_COLOR_BLACK) &&
           "the engine's side to move and plain alternation disagree");
    out_fen = mxq::notation::write_placement(game, cells.data(), cells.size(),
                                             out_ply);

    if (out_legal_moves != nullptr) {
        out_legal_moves->clear();
        /* A finished game offers no moves. */
        if (out_adj.state == MXQ_GAME_ONGOING) {
            const ::Color mover = board.sideToMove();
            const bool    forbidden_applies = renju && mover == BLACK;
            out_legal_moves->reserve(
                static_cast<size_t>(board.movesLeft()));
            for (int32_t rank = 0; rank < kBoardSize; ++rank) {
                for (int32_t file = 0; file < kBoardSize; ++file) {
                    const Pos pos(file, rank);
                    if (!board.isEmpty(pos)) {
                        continue;
                    }
                    if (forbidden_applies && board.checkForbiddenPoint(pos)) {
                        continue;
                    }
                    out_legal_moves->push_back(
                        mxq::notation::square_of_point(game, file, rank));
                }
            }
        }
    }
    return ReplayError::None;
}

} /* namespace */

ReplayError replay(MxqGameKind game, const char *start_fen,
                   const char *const *moves, size_t move_count,
                   std::string &out_fen, uint32_t &out_ply,
                   Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal, std::string &detail) {
    first_illegal = 0;

    if (start_fen == nullptr) {
        detail = "the starting position was null";
        return ReplayError::StartFenInvalid;
    }
    if (std::strcmp(start_fen, mxq::notation::start_fen(game)) != 0) {
        std::string why;
        if (!mxq::notation::well_formed_placement(game, start_fen, why)) {
            detail = why;
        } else {
            detail = "this game begins from the empty board and from no other "
                     "position";
        }
        return ReplayError::StartFenInvalid;
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        return replay_locked(game, moves, move_count, out_fen, out_ply, out_adj,
                             out_legal_moves, first_illegal, detail);
    } catch (const std::exception &e) {
        /* Only allocations can throw here, so this is a fault, not a rules
         * answer. */
        detail = std::string("the engine faulted replaying the line: ") + e.what();
        return ReplayError::Faulted;
    }
}

namespace {

/* The body of configure(), with g_mutex held; configure() catches what it
 * throws. */
ConfigureError configure_locked(Rules rules, uint32_t threads, uint32_t hash_mib,
                                const std::string &assets_dir,
                                std::string &detail) {
    const RulesPin &wanted = pin_of(rules);

    std::vector<WeightChoice> weights;
    if (!select_weights(assets_dir, rules, weights, detail)) {
        return ConfigureError::AssetMissing;
    }

    {
        CoutSilencer silence;

        /* Release the threads first, so the thread set is created exactly once
         * below. This avoids a deadlock in the engine's thread teardown:
         *
         * SearchThread::init() queues a first task, leaving `running` true
         * until the worker picks it up. The destructor sets `exit` and waits
         * for `running` to fall. If it runs before the pickup, the worker sees
         * `exit` and returns without clearing `running`, and the destructor
         * waits forever. setupSearcher() re-creates the whole set itself, so
         * calling it with threads live and then resizing provokes this.
         *
         * With no threads, setupSearcher and setupEvaluator only record what
         * they are given. The waitForIdle() below closes the rest. */
        Search::Engine.stopThinking();
        Search::Engine.setNumThreads(0);

        if (!load_internal_config(detail)) {
            deconfigure_locked();
            return ConfigureError::RulesLoadFailed;
        }
        /* After the load, which overwrites the [general] table. */
        Config::GeneralCfg.messageMode = MsgMode::NONE;

        /* An identity resolver: the engine's own searches the working directory
         * and next to argv[0], and these paths are already absolute. */
        Evaluation::EvaluatorWeightsConfig cfg;
        cfg.type = "mix9svq";
        Evaluation::EvaluatorWeightsConfig::WeightFiles files;
        if (wanted.white == nullptr) {
            files.file = weights[0].path;
        } else {
            files.fileBlack = weights[0].path;
            files.fileWhite = weights[1].path;
        }
        cfg.weights.push_back(files);

        try {
            Search::Engine.setupEvaluator(Evaluation::makeEvaluatorMaker(
                std::move(cfg),
                [](const std::filesystem::path &p) { return p; }));
        } catch (const std::exception &e) {
            detail = std::string("the evaluator could not be built: ") + e.what();
            deconfigure_locked();
            return ConfigureError::RulesLoadFailed;
        }

        /* Levels differ only in thinking time; the rest of the profile is set
         * per search in search_run.
         *
         * Alpha-beta rather than MCTS: it is the engine's default and its
         * memory is the transposition table alone, which the memory plan
         * sizes. */
        Search::Engine.setupSearcher(Search::createSearcher("alphabeta"));

        /* setNumThreads must not be called from a worker thread; the facade's
         * engine thread is not one. */
        Search::Engine.setNumThreads(threads);

        /* The other half of the deadlock fix: nothing below synchronises on
         * every path. HashTable::clear spawns its own threads,
         * HashTable::resize returns before its waitForIdle when the size is
         * unchanged, and gate 2 calls setBoardAndEvaluator directly. So a
         * refusal below could unwind to setNumThreads(0) before the workers
         * picked up their init task.
         *
         * It also closes a data race: above Numa::BindGroupThreshold threads
         * the init task writes each thread's numaId, which
         * setBoardAndEvaluator reads. */
        Search::Engine.waitForIdle();

        /* Begins a new game and flushes the transposition table. */
        Search::Engine.clear(true);
    }

    /* Sized in KiB. The fork reports a failed allocation instead of exiting. */
    const size_t hash_kib = static_cast<size_t>(hash_mib) * 1024u;
    bool allocated = false;
    {
        CoutSilencer silence;
        allocated = Search::Engine.searcher()->setMemoryLimit(hash_kib);
    }
    if (!allocated) {
        detail = "the transposition table of " + std::to_string(hash_mib) +
                 " MiB could not be allocated";
        deconfigure_locked();
        return ConfigureError::HashAllocationFailed;
    }
    /* The engine halves the request until an allocation succeeds and reports
     * success. The memory plan refuses rather than playing with less, so a
     * short table counts as no table. */
    if (Search::Engine.searcher()->getMemoryLimit() < hash_kib) {
        detail = "the transposition table degraded to " +
                 std::to_string(Search::Engine.searcher()->getMemoryLimit() /
                                1024u) +
                 " MiB of the " + std::to_string(hash_mib) + " MiB planned";
        deconfigure_locked();
        return ConfigureError::HashAllocationFailed;
    }

    /* Gate 2: the effective evaluator. The maker swallows UnsupportedRuleError
     * and UnsupportedBoardSizeError and returns nullptr, and the engine then
     * plays on classical evaluation silently.
     *
     * So build the thread state a search would, via setBoardAndEvaluator (what
     * start_thinking calls), and check that an evaluator came out. A search
     * keeps the same evaluator while the rule and size match. */
    {
        CoutSilencer silence;
        Search::Engine.ctx.options.rule = {wanted.engine_rule,
                                           GameRule::FREEOPEN};
        Board probe(kBoardSize);
        probe.newGame(wanted.engine_rule);
        Search::Engine.main()->setBoardAndEvaluator(probe);
    }
    if (Search::Engine.main()->evaluator == nullptr) {
        /* Not narrowed to one cause: a failed load also yields null, and the
         * engine's message saying which is silenced. */
        detail = "the engine has no NNUE evaluator for " + std::string(wanted.id) +
                 " at " + std::to_string(kBoardSize) + "x" +
                 std::to_string(kBoardSize) +
                 "; the pinned weights either do not cover it or did not load, "
                 "and a search would silently use classical evaluation";
        deconfigure_locked();
        return ConfigureError::AssetMismatch;
    }

    g_active_rules.store(rules, std::memory_order_release);
    g_configured.store(true, std::memory_order_release);
    return ConfigureError::None;
}

} /* namespace */

ConfigureError configure(Rules rules, uint32_t threads, uint32_t hash_mib,
                         const std::string &assets_dir, std::string &detail) {
    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        return configure_locked(rules, threads, hash_mib, assets_dir, detail);
    } catch (const std::exception &e) {
        /* No exception may leave the core. Any throw here means the engine did
         * not come up; it is unwound whole. */
        detail = std::string("the engine failed to prepare: ") + e.what();
        try {
            deconfigure_locked();
        } catch (...) {
            /* The caller is already told the preparation failed. */
        }
        return ConfigureError::RulesLoadFailed;
    }
}

void deconfigure() {
    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        deconfigure_locked();
    } catch (...) {
        /* Nothing to report a failed teardown to; it must not leave the
         * core. */
    }
}

namespace {

/* The body of search_run(), with exceptions still able to escape it. */
SearchError search_run_unguarded(const std::vector<Point> &moves,
                                 uint32_t movetime_ms,
                                 const std::atomic<bool> &cancelled,
                                 SearchOutput &out, std::string &detail) {
    /* No g_mutex, so a search does not block other bridge calls. */
    if (!g_configured.load(std::memory_order_acquire)) {
        detail = "no engine is prepared";
        return SearchError::NotConfigured;
    }
    const RulesPin &active = pin_of(g_active_rules.load(std::memory_order_acquire));

    Board board(kBoardSize);
    board.newGame(active.engine_rule);
    for (size_t i = 0; i < moves.size(); ++i) {
        const Point &point = moves[i];
        if (point.x >= kBoardSize || point.y >= kBoardSize) {
            detail = "the line has an off-board point at ply " +
                     std::to_string(i);
            return SearchError::ReplayFailed;
        }
        const Pos pos(point.x, point.y);
        if (!board.isEmpty(pos)) {
            detail = "the line plays an occupied point at ply " +
                     std::to_string(i);
            return SearchError::ReplayFailed;
        }
        board.move(active.engine_rule, pos);
    }

    Search::SearchOptions options;
    options.rule = {active.engine_rule, GameRule::FREEOPEN};
    /* Turn time only: levels are a thinking time per move with no match
     * clock. The engine returns a little before it elapses. */
    options.setTimeControl(static_cast<int64_t>(movetime_ms), 0);
    options.timeLimit = true;
    options.multiPV = 1;
    options.strengthLevel = 100;
    options.pondering = false;
    options.infoMode = Search::SearchOptions::INFO_NONE;
    /* The opening probe stays on: on an empty board the engine answers the
     * centre point at once, which a search would return anyway after a wait. */
    options.disableOpeningQuery = false;

    {
        CoutSilencer silence;
        Search::Engine.startThinking(board, options, false);
        /* startThinking re-arms the terminate flag, losing a cancellation that
         * raced it. The cancel path sets `cancelled` before stopping the
         * engine, so this re-check closes the window. */
        if (cancelled.load(std::memory_order_acquire)) {
            Search::Engine.stopThinking();
        }
        Search::Engine.waitForIdle();
    }

    const Pos best = Search::Engine.ctx.bestMove;
    if (!best.isInBoard(kBoardSize, kBoardSize)) {
        detail = "the engine reported no move";
        return SearchError::NoMove;
    }
    out.point.x = static_cast<uint8_t>(best.x());
    out.point.y = static_cast<uint8_t>(best.y());

    const Search::SearchThread *main = Search::Engine.main();
    if (!main->rootMoves.empty()) {
        /* Diagnostic only. The value scale is centipawn-shaped; mate scores
         * clamp to a sentinel. */
        const Value value = main->rootMoves[0].value;
        if (value >= VALUE_MATE_IN_MAX_PLY) {
            out.score_cp = 32000;
        } else if (value <= VALUE_MATED_IN_MAX_PLY) {
            out.score_cp = -32000;
        } else {
            out.score_cp = static_cast<int32_t>(value);
        }
    }
    /* The completed depth lives on the searcher's per-thread data. The cast is
     * to the alpha-beta searcher installed in configure(); the engine has no
     * RTTI. */
    if (const auto *data =
            main->searchDataAs<Search::AB::ABSearchData>()) {
        out.depth = static_cast<uint32_t>(
            data->completedDepth.load(std::memory_order_relaxed));
    }
    out.nodes = Search::Engine.nodesSearched();
    return SearchError::None;
}

} /* namespace */

SearchError search_run(const std::vector<Point> &moves, uint32_t movetime_ms,
                       const std::atomic<bool> &cancelled, SearchOutput &out,
                       std::string &detail) {
    try {
        return search_run_unguarded(moves, movetime_ms, cancelled, out, detail);
    } catch (const std::exception &e) {
        detail = std::string("the engine faulted during the search: ") + e.what();
        return SearchError::Faulted;
    }
}

void search_abort() {
    Search::Engine.stopThinking();
}

} /* namespace rapfi */
} /* namespace mxq */
