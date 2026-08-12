/* The Rapfi bridge. See mxq_rapfi_bridge.hpp for why it is one file. */

#include "mxq_rapfi_bridge.hpp"

#include "mxq_build_config.h"
#include "mxq_sha256.hpp"

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

/* Everything pinned to one game, in one row per game. The weight fields are that
 * game's own pins, and reading a file against the wrong row is exactly the
 * mistake the byte preflight below would otherwise stop catching. All of it
 * comes from pinned-inputs.json through the generated build configuration
 * rather than being spelled here.
 *
 * `white_*` is null exactly when one file serves both sides. That is not a
 * special case bolted on: mix9svq declares separate black and white weights, and
 * a configuration naming a single file resolves it as both paths, which is how
 * the freestyle network is published and how it is configured upstream. */
struct WeightPin {
    const char *filename;
    uint64_t    byte_length;
    const char *sha256;
};

struct RulesPin {
    const char      *id;
    ::Rule           engine_rule;
    WeightPin        black;
    const WeightPin *white; /* null when `black` serves both sides */
};

constexpr WeightPin kRenjuWhite = {MXQ_BUILD_RENJU_WHITE_NNUE_FILENAME,
                                   MXQ_BUILD_RENJU_WHITE_NNUE_BYTE_LENGTH,
                                   MXQ_BUILD_RENJU_WHITE_NNUE_SHA256};

constexpr RulesPin kRulesPins[] = {
    {"gomoku-15",
     ::Rule::FREESTYLE,
     {MXQ_BUILD_GOMOKU_NNUE_FILENAME, MXQ_BUILD_GOMOKU_NNUE_BYTE_LENGTH,
      MXQ_BUILD_GOMOKU_NNUE_SHA256},
     nullptr},
    {"renju",
     ::Rule::RENJU,
     {MXQ_BUILD_RENJU_BLACK_NNUE_FILENAME, MXQ_BUILD_RENJU_BLACK_NNUE_BYTE_LENGTH,
      MXQ_BUILD_RENJU_BLACK_NNUE_SHA256},
     &kRenjuWhite},
};

/* A switch rather than a comparison, and a count rather than a comment: adding
 * a game to the enum without a row here is a warning at the switch, and adding
 * a case without a row is caught by the assertion. Both would otherwise be an
 * out-of-bounds read of a table that looks obviously right. */
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

/* The rules a configuration that has never happened would report. Nothing
 * searches in it — is_configured() is false until configure() succeeds — so it
 * is a starting value rather than a posture the way the first engine's default
 * variant is one. That difference is the difference between the engines: the
 * first bridge answers rules queries with no engine prepared and so must always
 * have a variant loaded, and this one answers nothing until it is prepared. */
constexpr Rules kInitialRules = Rules::Gomoku15;

/* The rules the process-global tables and the loaded weights are currently for,
 * and whether anything is loaded at all. Written only by configure() and
 * deconfigure(), both under g_mutex; read by search_run(), which holds no lock
 * and reads them exactly as it reads those tables. Atomic because a plain read
 * racing a write is a data race whatever the values are, and these cost
 * nothing. */
std::atomic<Rules> g_active_rules{kInitialRules};
std::atomic<bool>  g_configured{false};

/* The engine's global state is process-wide and not re-entrant, and the core is
 * singleton-enforced for exactly that reason (core-interface.md). */
std::mutex g_mutex;

/* Whether the engine's classical tables have been loaded from its own embedded
 * configuration. Once per process: they are rule-independent and nothing later
 * invalidates them. */
bool g_config_loaded = false;

/*
 * The engine writes every message and every error to std::cout, and
 * Config::GeneralCfg.messageMode silences the ones that ask it first — but not
 * the config loader's own, which run while the mode is still being parsed. A
 * library must not write to a host application's standard output at all, so the
 * stream is redirected for the length of any call that can produce one, and the
 * message mode is set to NONE besides. Belt and braces, and the braces are the
 * ones that hold: messageMode is data the engine reads, and a path that forgets
 * to read it is a path this catches anyway.
 *
 * std::cout only. The engine writes nothing to std::cerr — every message and
 * every error goes through iohelper.h's sync_cout(), including ERRORL — so
 * swapping cerr would redirect a stream this engine never uses and take the
 * host's own diagnostics with it. That is the first bridge's posture too.
 *
 * One write is out of reach of this and is stated rather than implied:
 * core/platform.cpp's Windows large-page free path uses std::printf, which is C
 * stdio and not std::cout. It is unreachable here — that path is inside
 * #ifdef _WIN32 and this engine is not built for Windows — and it is recorded
 * as pending fork work in pinned-inputs.json for the same reason.
 */
class CoutSilencer {
public:
    CoutSilencer() : saved_(std::cout.rdbuf(&sink_)) {}
    ~CoutSilencer() { std::cout.rdbuf(saved_); }
    CoutSilencer(const CoutSilencer &) = delete;
    CoutSilencer &operator=(const CoutSilencer &) = delete;

private:
    /* Discarding rather than accumulating. A buffer would be a memory leak
     * shaped like a guard: this one spans a whole search, and a search at the
     * engine's ordinary message level writes a line per iteration. */
    struct Sink : std::streambuf {
        int overflow(int c) override { return c; }
        std::streamsize xsputn(const char *, std::streamsize n) override {
            return n;
        }
    };
    Sink            sink_;
    std::streambuf *saved_;
};

/* One selected weight file: where it is, and the pins it must satisfy. */
struct WeightChoice {
    std::string      path;
    const WeightPin *pin;
};

/*
 * Gate 1, selection. Which files this rule needs, by the names the manifest
 * pins, in the asset directory the frontend supplied.
 *
 * There is no search for an unrecognised file the way the first engine's
 * selection has one, and the difference is what a name means to each engine.
 * Fairy-Stockfish binds a network to a variant by its basename, so a candidate
 * file whose name does not match is a real and silent hazard worth looking for.
 * Rapfi reads the rule and the board size out of the file's own header and takes
 * the name as nothing at all, so a file under an unexpected name is a file this
 * build cannot verify against any pin — and an unverifiable file is refused,
 * not guessed at.
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

/* Gate 2, bytes. Every selected file's length and SHA-256 against its own pins,
 * before the engine is given a path. */
bool verify_weights(const std::vector<WeightChoice> &weights, bool &out_missing,
                    std::string &detail) {
    out_missing = false;
    for (const WeightChoice &weight : weights) {
        std::ifstream in(weight.path, std::ios::binary);
        if (!in) {
            detail = "cannot open the weight file at " + weight.path;
            out_missing = true;
            return false;
        }
        /* Ten megabytes into a std::string, which can throw. Treated as a file
         * this build cannot read rather than as an engine failure: whether the
         * bytes did not arrive or could not be held, the file is not usable and
         * the caller's answer is the same. */
        std::string bytes;
        try {
            bytes.assign(std::istreambuf_iterator<char>(in),
                         std::istreambuf_iterator<char>());
        } catch (const std::exception &e) {
            detail = std::string("cannot read the weight file at ") +
                     weight.path + ": " + e.what();
            out_missing = true;
            return false;
        }
        if (in.bad()) {
            detail = "cannot read the weight file at " + weight.path;
            out_missing = true;
            return false;
        }
        /* The diagnosis leads and the path follows: MxqError.detail is bounded,
         * and when a long path forces truncation it is the path that must lose,
         * never the fact the caller can act on. */
        if (bytes.size() != static_cast<size_t>(weight.pin->byte_length)) {
            detail = "the weight file is " + std::to_string(bytes.size()) +
                     " bytes where the one pinned as " +
                     std::string(weight.pin->filename) + " is " +
                     std::to_string(weight.pin->byte_length) + ", at " +
                     weight.path;
            return false;
        }
        if (sha256_hex(bytes) != weight.pin->sha256) {
            detail = "the weight file does not match the SHA-256 pinned for " +
                     std::string(weight.pin->filename) + ", at " + weight.path;
            return false;
        }
    }
    return true;
}

/* The deconfigured posture, shared by deconfigure() and configure()'s unwind.
 * Caller holds g_mutex.
 *
 * The order is the one the engine's own ownership demands. The threads go first,
 * because a thread holds a board and an evaluator and the evaluator holds a
 * reference to the registry-owned weights; dropping the threads is what releases
 * them. The evaluator maker goes next so that a later preparation installs its
 * own rather than inheriting one for the wrong rule. The table goes last and
 * goes whole — resize(0) rather than a smaller size — because a partially
 * reduced transposition table is not a state anything here defines. */
void deconfigure_locked() {
    CoutSilencer silence;
    Search::Engine.stopThinking();
    Search::Engine.setNumThreads(0);
    Search::Engine.setupEvaluator(nullptr);
    Search::TT.resize(0);
    g_configured.store(false, std::memory_order_release);
}

/* The engine's own embedded configuration, loaded once. It carries the classical
 * evaluation and score tables — which search reads for move ordering whatever
 * the evaluator is — and no [model.evaluator] section at all, which is what
 * makes it safe to load: it installs no weights of its own for the gate below to
 * be fooled by.
 *
 * Command::loadConfig() is deliberately not what does this. Its resolution order
 * is the working directory and then a directory derived from argv[0], and inside
 * an app bundle the first is whatever the host process happens to be sitting in
 * and the second is meaningless. A config.toml left in either would silently
 * replace the engine's configuration, weights included. Config::loadConfig takes
 * a stream, so the embedded text can be handed to it directly and no filesystem
 * lookup happens at all. */
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

Rules active_rules() {
    return g_active_rules.load(std::memory_order_acquire);
}

bool is_configured() {
    return g_configured.load(std::memory_order_acquire);
}

ConfigureError prepare(Rules rules, const MxqEngineBudget &budget,
                       const std::string &assets_dir, MxqEnginePlan &out_applied,
                       std::string &detail) {
    /* Nothing here throws — the plan is arithmetic over values, and configure()
     * below is guarded in its own right. */
    std::memset(&out_applied, 0, sizeof(out_applied));
    out_applied.struct_size = static_cast<uint32_t>(sizeof(out_applied));

    MxqEngineBudget probe = budget;
    probe.struct_size = static_cast<uint32_t>(sizeof(probe));
    const MxqStatus rc = mxq_engine_plan(&probe, &out_applied, nullptr);
    if (rc != MXQ_OK) {
        detail = "the memory plan could not be computed";
        return ConfigureError::RulesLoadFailed;
    }
    if (out_applied.sufficient == 0) {
        detail = "the calculated transposition-table budget is below the "
                 "accepted minimum; nothing was initialised";
        return ConfigureError::InsufficientMemory;
    }
    return configure(rules, out_applied.threads, out_applied.hash_mib,
                     assets_dir, detail);
}

namespace {

/* The body of configure(), with g_mutex already held and with exceptions still
 * able to escape it. configure() below is the guard around both. */
ConfigureError configure_locked(Rules rules, uint32_t threads, uint32_t hash_mib,
                                const std::string &assets_dir,
                                std::string &detail) {
    const RulesPin &wanted = pin_of(rules);

    /* Gate 1: which files. */
    std::vector<WeightChoice> weights;
    if (!select_weights(assets_dir, rules, weights, detail)) {
        return ConfigureError::AssetMissing;
    }

    /* Gate 2: their bytes, before the engine sees a path. A length or hash
     * mismatch is a damaged installation and refuses here; the engine's own
     * header check never has to be the thing that catches it. */
    bool missing = false;
    if (!verify_weights(weights, missing, detail)) {
        return missing ? ConfigureError::AssetMissing
                       : ConfigureError::AssetMismatch;
    }

    {
        CoutSilencer silence;

        /* Every configuration starts from the released posture and creates its
         * thread set exactly once inside it. That is not tidiness — it is half
         * of the answer to a deadlock in the engine's own thread teardown.
         *
         * SearchThread::init() starts the worker and then queues the thread's
         * first task, which leaves `running` true until the worker picks it up.
         * SearchThread's destructor sets `exit` and then waits for `running` to
         * fall. If the destructor runs before that first task has been picked
         * up, the worker's next look at its loop sees `exit` and returns without
         * ever clearing `running` — and the destructor waits for a flag nothing
         * will ever clear again. Destroying a thread set soon after creating it
         * is what makes that window reachable, and setupSearcher() re-creates
         * the whole set on its own (it calls setNumThreads with the current
         * count), so calling it while threads exist and then resizing is exactly
         * the sequence that provokes it.
         *
         * Releasing first means setupSearcher and setupEvaluator both run
         * against an empty thread set, where they only record what they are
         * given. The other half is below: after the threads are created, this
         * function waits for them to pick their init task up, which closes the
         * window rather than merely making it narrow. */
        Search::Engine.stopThinking();
        Search::Engine.setNumThreads(0);

        if (!load_internal_config(detail)) {
            deconfigure_locked();
            return ConfigureError::RulesLoadFailed;
        }
        /* After the load, because the load commits the parsed [general] table
         * over whatever was set before it. */
        Config::GeneralCfg.messageMode = MsgMode::NONE;

        /* The evaluator, by absolute path and through an identity resolver.
         * The engine's production resolver walks the working directory and the
         * argv[0]-derived binary directory; the paths here are already absolute
         * and already verified, so resolving them again could only find
         * something else. */
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

        /* The accepted shared search profile: one strongest configuration, with
         * the levels differing only in thinking time. strengthLevel stays at its
         * maximum, multiPV at one, and no node or depth limit is imposed — all
         * of which are SearchOptions defaults and are set per search rather than
         * here, in search_run.
         *
         * Alpha-beta rather than MCTS: it is the engine's default searcher, it
         * is what its own benchmark positions and its CI are run against, and
         * it is the one whose memory limit is the transposition table alone —
         * which is what the core's memory plan is a size for.
         *
         * With no threads live this only records the searcher; the thread set
         * below is created against it. */
        Search::Engine.setupSearcher(Search::createSearcher("alphabeta"));

        /* The threads, then the table. setNumThreads must not be called from a
         * worker thread; the facade's engine thread is not one. clear(true)
         * begins a new game — a fresh board state and a flushed transposition
         * table — which is what a rules switch needs and what a first
         * preparation needs equally. */
        Search::Engine.setNumThreads(threads);

        /* The other half of the deadlock answer, and it has to be here rather
         * than left to the calls after it.
         *
         * Nothing further down this function is a synchronisation point on
         * every path. clear(true) reaches HashTable::clear, which spawns
         * threads of its own rather than driving these. setMemoryLimit reaches
         * HashTable::resize, which returns early when the size has not changed —
         * before its waitForIdle — so a re-preparation at the same table size
         * passes straight through. Gate 3 then calls setBoardAndEvaluator
         * directly, which startThinking would have reached only after waiting.
         * So on the rules-switch path the workers could still be holding an
         * unpicked init task when a refusal below unwinds to setNumThreads(0),
         * which is exactly the destroy-before-pickup ordering the race needs.
         *
         * Waiting here also closes a data race that has nothing to do with the
         * deadlock: the init task writes each thread's numaId, and
         * setBoardAndEvaluator reads it. The write only happens for a thread
         * count above Numa::BindGroupThreshold, so it is a race the accepted
         * memory plan reaches on any machine that reports more than eight
         * processors. */
        Search::Engine.waitForIdle();

        Search::Engine.clear(true);
    }

    /* The transposition table, sized in KiB. The engine reports total failure
     * through the fork's recoverable-allocation change rather than by leaving
     * the process. */
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
    /* And the size it actually took. The engine's own degradation halves the
     * request until an allocation succeeds and reports that as success, which is
     * reasonable for a program that owns its machine and wrong for this one: the
     * accepted memory policy computes a budget from a fresh probe and refuses
     * below its minimum rather than quietly playing with less. A short table is
     * therefore the same answer as no table. */
    if (Search::Engine.searcher()->getMemoryLimit() < hash_kib) {
        detail = "the transposition table degraded to " +
                 std::to_string(Search::Engine.searcher()->getMemoryLimit() /
                                1024u) +
                 " MiB of the " + std::to_string(hash_mib) + " MiB planned";
        deconfigure_locked();
        return ConfigureError::HashAllocationFailed;
    }

    /* Gate 3: the effective evaluator, after the whole configuration.
     *
     * This is the gate the engine's own silence makes necessary. A weight set
     * that does not cover the rule or the board size raises UnsupportedRuleError
     * or UnsupportedBoardSizeError inside the maker, and the maker catches both
     * and moves to the next weight entry — with none left, it returns nullptr,
     * logs at a message level that is off, and the engine plays the whole game
     * on classical evaluation with nothing anywhere reporting it.
     *
     * So the question is put to the engine in the only form that cannot be
     * answered by a configuration value: build the thread state a search would
     * build, for this rule at this size, and ask whether an evaluator came out
     * of it. setBoardAndEvaluator is what start_thinking itself calls, and the
     * evaluator it leaves is the one a search would use — the same object, since
     * it is kept whenever the rule and the size still match. */
    {
        CoutSilencer silence;
        Search::Engine.ctx.options.rule = {wanted.engine_rule,
                                           GameRule::FREEOPEN};
        Board probe(kBoardSize);
        probe.newGame(wanted.engine_rule);
        Search::Engine.main()->setBoardAndEvaluator(probe);
    }
    if (Search::Engine.main()->evaluator == nullptr) {
        /* What a null evaluator means is deliberately not narrowed to one
         * cause. The maker returns nothing when the weights do not cover the
         * rule or the size, and equally when a load failed — a short read, a
         * decompression error, an allocation that could not be met. It writes a
         * message about which, and that message goes to a stream this bridge is
         * silencing, so naming one cause here would be a guess printed as a
         * fact. What the caller can act on is the same either way: the engine
         * has no network for this game and must not play. */
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
        /* docs/architecture.md: no exception, and nothing that terminates the
         * process, may cross the core's boundary. This engine throws to report
         * — a bad allocation building a board, a thread the system would not
         * create, a weight stream that ended early — and every one of those
         * arrives here as one answer: the engine did not come up. Unwound whole
         * afterwards, because a half-configured engine is not a state anything
         * defines. */
        detail = std::string("the engine failed to prepare: ") + e.what();
        try {
            deconfigure_locked();
        } catch (...) {
            /* Teardown has nothing left to report with and nowhere better to
             * go: the caller is already being told the preparation failed. */
        }
        return ConfigureError::RulesLoadFailed;
    }
}

void deconfigure() {
    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        deconfigure_locked();
    } catch (...) {
        /* Release returns void by design — a caller tearing an engine down has
         * no decision left to make — so a throw here has nothing to be reported
         * as. Swallowed rather than allowed to cross the boundary. */
    }
}

namespace {

/* The body of search_run(), with exceptions still able to escape it. */
SearchError search_run_unguarded(const std::vector<Point> &moves,
                                 uint32_t movetime_ms,
                                 const std::atomic<bool> &cancelled,
                                 SearchOutput &out, std::string &detail) {
    /* No g_mutex here, deliberately: see the serialisation design in
     * mxq_rapfi_bridge.hpp. */
    if (!g_configured.load(std::memory_order_acquire)) {
        detail = "no engine is prepared";
        return SearchError::NotConfigured;
    }
    const RulesPin &active = pin_of(g_active_rules.load(std::memory_order_acquire));

    /* The board, replayed from empty. These games have no other starting
     * position, so the whole snapshot is the move list. */
    Board board(kBoardSize);
    board.newGame(active.engine_rule);
    for (size_t i = 0; i < moves.size(); ++i) {
        const Point &point = moves[i];
        if (point.x >= kBoardSize || point.y >= kBoardSize) {
            detail = "the snapshot has an off-board point at ply " +
                     std::to_string(i);
            return SearchError::ReplayFailed;
        }
        const Pos pos(point.x, point.y);
        if (!board.isEmpty(pos)) {
            detail = "the snapshot plays an occupied point at ply " +
                     std::to_string(i);
            return SearchError::ReplayFailed;
        }
        board.move(active.engine_rule, pos);
    }

    Search::SearchOptions options;
    options.rule = {active.engine_rule, GameRule::FREEOPEN};
    /* Turn time only, which is the shape the product's levels have: a maximum
     * thinking time per move and no match clock at all. The engine keeps a small
     * reserve inside it and returns before it elapses. */
    options.setTimeControl(static_cast<int64_t>(movetime_ms), 0);
    options.timeLimit = true;
    options.multiPV = 1;
    options.strengthLevel = 100;
    options.pondering = false;
    options.infoMode = Search::SearchOptions::INFO_NONE;
    /* The trivial-opening probe stays ON, which is a decision rather than a
     * default left alone. On an empty freestyle board the engine answers the
     * centre point without searching. That is the move a search would return
     * anyway and the one every opening theory opens with, so disabling the probe
     * would buy a few seconds of thinking to reach the same point — and it would
     * cost the player those seconds every single game, at the one moment there
     * is nothing on the board to look at. */
    options.disableOpeningQuery = false;

    {
        CoutSilencer silence;
        Search::Engine.startThinking(board, options, false);
        /* startThinking re-arms the engine's terminate flag, so a cancellation
         * that raced it would otherwise be lost and the search would run its
         * whole movetime. The cancel path sets the flag before it stops the
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
        /* Diagnostic only; nothing adjudicates from it. The engine's value scale
         * is already centipawn-shaped, and the mate range is clamped to a
         * sentinel rather than reported as a number nothing reads as one. */
        const Value value = main->rootMoves[0].value;
        if (value >= VALUE_MATE_IN_MAX_PLY) {
            out.score_cp = 32000;
        } else if (value <= VALUE_MATED_IN_MAX_PLY) {
            out.score_cp = -32000;
        } else {
            out.score_cp = static_cast<int32_t>(value);
        }
    }
    /* The completed iteration depth lives on the searcher's per-thread data
     * rather than on the root move. The cast is to the type this bridge itself
     * installed a page above — the engine has no run-time type information, and
     * nothing else here ever changes the searcher. */
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
