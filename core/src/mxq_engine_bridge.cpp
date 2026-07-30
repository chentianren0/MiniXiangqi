/* The Fairy-Stockfish bridge. See mxq_engine_bridge.hpp for why it is one file. */

#include "mxq_engine_bridge.hpp"

#include "mxq_build_config.h"
#include "mxq_sha256.hpp"

#include "apiutil.h"
#include "piece.h"
#include "bitboard.h"
#include "endgame.h"
#include "evaluate.h"
#include "misc.h"
#include "movegen.h"
#include "position.h"
#include "search.h"
#include "thread.h"
#include "tt.h"
#include "uci.h"
#include "variant.h"

#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <atomic>
#include <mutex>
#include <sstream>

using namespace Stockfish;

namespace mxq {
namespace engine {
namespace {

/* The identifier and configuration filename are fixed by
 * docs/engine-integration.md, "Accepted variant packaging". */
constexpr const char *kVariantId = "minixiangqiaxf";
constexpr const char *kVariantFile = "minixiangqi-variants.ini";

/* The engine's process-global tables, which are built once and never rebuilt.
 * Loading the variant configuration is separate and may be retried, because a
 * missing or wrong asset directory is a caller's mistake to correct rather than
 * a permanent property of the process. */
std::once_flag g_bootstrap;
std::mutex g_init_mutex;
std::atomic<bool> g_ready{false};
std::string g_init_detail;
InitError g_init_error = InitError::None;

/* The engine's global state is process-wide and not re-entrant, and the core is
 * singleton-enforced for exactly that reason (core-interface.md). Rules queries
 * are serialised here rather than assumed to be called one at a time. */
std::mutex g_mutex;

void bootstrap() {
    pieceMap.init();
    variants.init();
    UCI::init(Options);
}

void initialise_once(const std::string &assets_dir) {
    std::call_once(g_bootstrap, bootstrap);

    const std::string path = assets_dir.empty()
                                 ? std::string(kVariantFile)
                                 : assets_dir + "/" + kVariantFile;
    std::ifstream in(path);
    if (!in) {
        g_init_detail = "cannot open the bundled variant configuration at " + path;
        g_init_error = InitError::AssetMissing;
        return;
    }
    std::stringstream ss;
    ss << in.rdbuf();
    variants.parse_istream<false>(ss);
    Options["UCI_Variant"].set_combo(variants.get_keys());

    if (variants.find(std::string(kVariantId)) == variants.end()) {
        g_init_detail = std::string("the bundled configuration does not define ") + kVariantId;
        g_init_error = InitError::VariantLoadFailed;
        return;
    }

    PSQT::init(variants.find(std::string(kVariantId))->second);
    Bitboards::init();
    Position::init();
    Bitbases::init();
    Endgames::init();
    Search::init();
    /* One thread: this bridge answers rules queries and never searches. The
     * search facade sizes its own pool through configure(), and deconfigure()
     * restores this posture. */
    Threads.set(1);
    Search::clear();
    /* The piece and bitboard tables for the one pinned variant, built here
     * once and rebuilt only under configure()'s exclusion. replay() used to
     * re-run this per call, which rewrote process-global tables under any
     * concurrent reader once a search could be that reader; see the
     * serialisation design in mxq_engine_bridge.hpp. */
    UCI::init_variant(variants.find(std::string(kVariantId))->second);
    g_ready = true;
}

const Variant *target_variant() {
    return variants.find(std::string(kVariantId))->second;
}

/* The engine reports one side-to-move-relative Value and a flag. The contract
 * wants a state and a reason. Everything this function knows, it derives:
 *
 *  - checkmate and stalemate from there being no legal move, and from whether
 *    the side to move is in check;
 *  - a neutral repetition from an optional end valued as a draw;
 *  - a decisive repetition from an optional end valued as a mate, attributed by
 *    the accepted rule that the violating side loses — never by which side
 *    happens to be to move at detection;
 *  - perpetual check against perpetual chase from whether the side that loses
 *    delivered check at every occurrence of the repeated position. The engine
 *    collapses both onto the same Value, so this is the only way to tell them
 *    apart until the fork exposes which branch fired. Where the evidence does
 *    not decide it, the reason is left unset rather than guessed: a wrong
 *    reason is recorded in the archive forever.
 */
/* placement + side to move, which is what docs/xiangqi-rules.md makes position
 * identity: "the two counters are ignored". */
std::string identity(const std::string &fen) {
    size_t sp = fen.find(' ');
    if (sp == std::string::npos) {
        return fen;
    }
    size_t sp2 = fen.find(' ', sp + 1);
    return fen.substr(0, sp2 == std::string::npos ? fen.size() : sp2);
}

/* Every ply after which the position now on the board stood there. */
std::vector<size_t> occurrences_of(const std::vector<std::string> &identities,
                                   const std::string &here) {
    std::vector<size_t> at;
    for (size_t i = 0; i < identities.size(); ++i) {
        if (identities[i] == here) {
            at.push_back(i);
        }
    }
    return at;
}

/* The first ply of the repetition adjudication actually rests on: the three
 * occurrences ending at the present one.
 *
 * Anything earlier is lead-in or an interrupted attempt, and neither says who
 * is violating now. Judging over the whole history instead gets both ends
 * wrong: every real perpetual check has a quiet lead-in, and counting those
 * quiet plies makes it read as a chase; while an interrupted violation that
 * later resumes would have its interruption held against it.
 *
 * This is the same window the rules contract adjudicates on. mx-chs-022 is the
 * case that pins it: a violation interrupted and resumed attaches at the fourth
 * occurrence, and it is the second, third and fourth — not the first — that
 * decide what it was. */
size_t window_start(const std::vector<size_t> &occurrences) {
    if (occurrences.empty()) {
        return 0;
    }
    return occurrences.size() >= 3 ? occurrences[occurrences.size() - 3]
                                   : occurrences.front();
}

Adjudication adjudicate(Position &pos, const std::vector<Ply> &plies,
                        const std::vector<std::string> &identities) {
    Adjudication a{};
    a.state = MXQ_GAME_ONGOING;
    a.reason = MXQ_END_REASON_NONE;
    a.at_occurrence = 0;

    const bool side_to_move_is_red = (pos.side_to_move() == WHITE);
    const bool no_legal_move = (MoveList<LEGAL>(pos).size() == 0);

    if (no_legal_move) {
        /* Both are a loss for the player who cannot move, per
         * docs/xiangqi-rules.md: "A position with no legal move is a loss for
         * the player who cannot move." Stalemate is not a draw in Xiangqi. */
        a.state = side_to_move_is_red ? MXQ_GAME_BLACK_WINS : MXQ_GAME_RED_WINS;
        a.reason = pos.checkers() ? MXQ_END_REASON_CHECKMATE : MXQ_END_REASON_STALEMATE;
        return a;
    }

    Value value = VALUE_DRAW;
    OptionalGameEndRule rule = OPTIONAL_END_NONE;
    if (pos.is_optional_game_end(value, 0, 0, &rule)) {
        /* How many times the position on the board has now stood there. The
         * engine reports that an outcome attached, not where: a violation that
         * was interrupted and resumed attaches at the fourth occurrence, not
         * the third, so this is counted rather than assumed. */
        const std::string here = identity(pos.fen());
        const std::vector<size_t> occurrences = occurrences_of(identities, here);
        a.at_occurrence = static_cast<uint32_t>(occurrences.size());

        /* Judge the violation over the repetition, never over the whole game. */
        const size_t first = window_start(occurrences);

        if (value == VALUE_DRAW) {
            /* A neutral threefold and a mutual same-class violation both come
             * back as a draw value. They are different outcomes: the first is
             * claimable and the second is automatic, so the game does not end
             * on its own if this is read wrongly.
             *
             * The fork reports which rule produced the end, which is what
             * separates them: a draw the perpetual-chase branch produced is
             * both sides chasing, because a unilateral chase is decisive. The
             * check case is derived from the plies instead — the engine folds
             * mutual perpetual check onto the same rule, and both sides having
             * checked at every one of their own moves inside the repetition is
             * the trace it leaves. */
            if (rule == OPTIONAL_END_PERPETUAL_CHASE) {
                a.state = MXQ_GAME_DRAW;
                a.reason = MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE;
                return a;
            }
            size_t red_moves = 0, black_moves = 0;
            bool red_always_checked = true, black_always_checked = true;
            for (size_t i = first; i < plies.size(); ++i) {
                const Ply &p = plies[i];
                if (p.by_red) {
                    ++red_moves;
                    if (!p.gives_check) red_always_checked = false;
                } else {
                    ++black_moves;
                    if (!p.gives_check) black_always_checked = false;
                }
            }
            if (red_moves > 0 && black_moves > 0 && red_always_checked &&
                black_always_checked) {
                a.state = MXQ_GAME_DRAW;
                a.reason = MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK;
                return a;
            }
            a.state = MXQ_GAME_CLAIMABLE_DRAW;
            a.reason = MXQ_END_REASON_THREEFOLD_REPETITION;
            return a;
        }
        /* A decisive repetition is automatic, not claim-gated. */
        const bool side_to_move_wins = (value > VALUE_DRAW);
        const bool red_wins = (side_to_move_is_red == side_to_move_wins);
        a.state = red_wins ? MXQ_GAME_RED_WINS : MXQ_GAME_BLACK_WINS;

        /* The loser is the violator, by the accepted rule that a violation is
         * named by outcome and never by who is to move at detection. Perpetual
         * check is then distinguishable from perpetual chase because the
         * violator must have given check at every one of ITS OWN moves — the
         * victim's replies give none, so counting every ply would make every
         * perpetual check look like a chase. */
        const bool loser_is_red = !red_wins;
        size_t loser_moves = 0;
        bool loser_checked_every_move = true;
        for (size_t i = first; i < plies.size(); ++i) {
            const Ply &p = plies[i];
            if (p.by_red != loser_is_red) {
                continue;
            }
            ++loser_moves;
            if (!p.gives_check) {
                loser_checked_every_move = false;
            }
        }
        a.reason = (loser_moves > 0 && loser_checked_every_move)
                       ? MXQ_END_REASON_PERPETUAL_CHECK
                       : MXQ_END_REASON_PERPETUAL_CHASE;
        return a;
    }

    return a;
}

} /* namespace */

InitError ensure_initialised(const char *assets_dir, std::string &detail) {
    std::lock_guard<std::mutex> lock(g_init_mutex);
    if (g_ready) {
        return InitError::None;
    }
    /* Retried rather than latched: a failed init leaves the process able to
     * succeed on a later attempt with a correct asset directory, and reports
     * the attempt that actually failed rather than quoting a stale path. */
    g_init_detail.clear();
    g_init_error = InitError::None;
    initialise_once(assets_dir ? assets_dir : "");
    if (!g_ready) {
        detail = g_init_detail;
        return g_init_error;
    }
    return InitError::None;
}

bool validate_fen(const char *fen, std::string &detail) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_ready) {
        detail = "the engine is not initialised";
        return false;
    }
    if (fen == nullptr) {
        detail = "fen was null";
        return false;
    }
    const FEN::FenValidation v = FEN::validate_fen(std::string(fen), target_variant(), false);
    if (v != FEN::FEN_OK) {
        detail = "the FEN does not satisfy the frozen structural encoding";
        return false;
    }
    return true;
}

ReplayError replay(const char *start_fen,
                   const char *const *moves, size_t move_count,
                   std::string &out_fen,
                   bool &out_in_check,
                   uint32_t &out_ply,
                   Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal,
                   std::string &detail) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_ready) {
        detail = "the engine is not initialised";
        return ReplayError::NotInitialised;
    }
    if (start_fen == nullptr) {
        detail = "start_fen was null";
        return ReplayError::StartFenInvalid;
    }

    const Variant *v = target_variant();
    if (FEN::validate_fen(std::string(start_fen), v, false) != FEN::FEN_OK) {
        detail = "start_fen does not satisfy the frozen structural encoding";
        return ReplayError::StartFenInvalid;
    }

    /* The state list must outlive every do_move: Position holds a pointer into
     * it. A deque rather than a vector because reallocation would invalidate
     * those pointers. The variant's piece and bitboard tables are NOT
     * re-initialised here: they were built at initialise_once for the one
     * pinned variant and never change, and rewriting them per replay would
     * race a concurrent search's reads. */
    auto states = std::make_unique<std::deque<StateInfo>>(1);
    Position pos;
    pos.set(v, std::string(start_fen), false, &states->back(), Threads.main());

    /* Recorded per ply so a perpetual check can be told from a perpetual chase,
     * which the engine's return value alone does not distinguish. */
    std::vector<Ply> plies;
    plies.reserve(move_count);
    /* Every position the game has stood in, the start included, so an
     * occurrence count can be derived rather than assumed. */
    std::vector<std::string> identities;
    identities.reserve(move_count + 1);
    identities.push_back(identity(pos.fen()));

    for (size_t i = 0; i < move_count; ++i) {
        if (moves == nullptr || moves[i] == nullptr) {
            first_illegal = i;
            detail = "a move in the history was null";
            return ReplayError::IllegalMove;
        }
        /* to_move takes a non-const reference, so the string must be a named
         * lvalue rather than a temporary. */
        std::string move_text(moves[i]);
        const Move m = UCI::to_move(pos, move_text);
        if (m == MOVE_NONE) {
            first_illegal = i;
            detail = "move " + move_text + " is not legal at its turn";
            return ReplayError::IllegalMove;
        }
        plies.push_back(Ply{pos.side_to_move() == WHITE, pos.gives_check(m)});
        states->emplace_back();
        pos.do_move(m, states->back());
        identities.push_back(identity(pos.fen()));
    }

    out_fen = pos.fen();
    out_in_check = (pos.checkers() != 0);
    out_ply = static_cast<uint32_t>(move_count);
    out_adj = adjudicate(pos, plies, identities);

    if (out_legal_moves != nullptr) {
        out_legal_moves->clear();
        for (const auto &m : MoveList<LEGAL>(pos)) {
            out_legal_moves->push_back(UCI::move(pos, m));
        }
    }
    return ReplayError::None;
}

/* ------------------------------------------------------------------------- */
/* The search side                                                           */
/* ------------------------------------------------------------------------- */

namespace {

/*
 * The engine prints: iterative-deepening info lines, the NNUE verification
 * notice, the variant notice on_variant_change emits, and the final bestmove,
 * all through sync_cout, which is std::cout under a mutex. An embedded engine
 * has no business writing to the host process's stdout, and there is no
 * upstream switch to turn it off, so the printing windows are contained by
 * swapping std::cout's buffer for a sink for exactly their duration. The
 * windows are on the facade's engine thread (configure and the search run),
 * and every engine print happens strictly inside them. A host thread writing
 * to std::cout during such a window would be swallowed with it; the product
 * frontends never write to std::cout, and the trade is documented rather than
 * silent. std::cerr is deliberately left alone: the engine reports a failed
 * TT allocation there, and a real fault is worth a stderr line.
 */
class CoutSilencer {
public:
    CoutSilencer() : saved_(std::cout.rdbuf(&sink_)) {}
    ~CoutSilencer() { std::cout.rdbuf(saved_); }
    CoutSilencer(const CoutSilencer &) = delete;
    CoutSilencer &operator=(const CoutSilencer &) = delete;

private:
    struct Sink : std::streambuf {
        int overflow(int c) override { return c; }
        std::streamsize xsputn(const char *, std::streamsize n) override {
            return n;
        }
    };
    Sink sink_;
    std::streambuf *saved_;
};

/*
 * Find the network file to preflight. The pinned basename is what packaging
 * bundles and is preferred; failing that, a directory holding exactly one
 * .nnue file names its candidate unambiguously. The fallback is what makes
 * the wrong-basename packaging failure — the network staged under its source
 * name instead of the bundled one — reach the effective-state preflight as a
 * typed refusal instead of hiding behind "no such file": the bytes are right,
 * the byte and hash preflights pass, and the engine then clears its internal
 * NNUE flag over the basename, which is exactly what the preflight exists to
 * catch.
 */
bool find_network(const std::string &assets_dir, std::string &out_path,
                  std::string &detail) {
    namespace fs = std::filesystem;
    const fs::path dir = assets_dir.empty() ? fs::path(".") : fs::path(assets_dir);
    const fs::path pinned = dir / MXQ_BUILD_NNUE_FILENAME;
    std::error_code ec;
    if (fs::is_regular_file(pinned, ec)) {
        out_path = pinned.string();
        return true;
    }
    std::string only;
    size_t count = 0;
    for (const auto &entry : fs::directory_iterator(dir, ec)) {
        if (entry.is_regular_file() && entry.path().extension() == ".nnue") {
            only = entry.path().string();
            ++count;
        }
    }
    if (ec) {
        detail = "cannot read the asset directory at " + dir.string();
        return false;
    }
    if (count == 1) {
        out_path = only;
        return true;
    }
    detail = count == 0
                 ? "no NNUE network found in " + dir.string() + " (expected " +
                       MXQ_BUILD_NNUE_FILENAME + ")"
                 : "several .nnue files in " + dir.string() +
                       " and none is the bundled " + MXQ_BUILD_NNUE_FILENAME;
    return false;
}

/* The deconfigured posture, shared by deconfigure() and configure()'s unwind.
 * Caller holds g_mutex. The option floor goes first so the pool resize that
 * follows re-allocates a megabyte rather than the gigabytes being released;
 * the final direct resize(0) is the release itself, which the Hash option
 * cannot express because its minimum is 1. */
void deconfigure_locked() {
    CoutSilencer silence;
    Options["Hash"] = std::string("1");
    Options["Threads"] = std::string("1");
    TT.resize(0);
}

} /* namespace */

ConfigureError configure(uint32_t threads, uint32_t hash_mib,
                         const std::string &assets_dir, std::string &detail) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_ready) {
        /* Unreachable through the facade: mxq_core_init fails whole when the
         * variant configuration does not load. Kept typed rather than assumed
         * away. */
        detail = "the engine is not initialised";
        return ConfigureError::VariantLoadFailed;
    }
    if (variants.find(std::string(kVariantId)) == variants.end()) {
        detail = std::string("the pinned variant ") + kVariantId +
                 " is not loaded";
        return ConfigureError::VariantLoadFailed;
    }

    /* The byte preflight: presence, pinned byte length, pinned SHA-256. The
     * engine never sees a path whose bytes were not verified first — a hash
     * mismatch is a damaged installation and refuses here, so the engine's
     * own fatal verification path stays unreachable. */
    std::string network_path;
    if (!find_network(assets_dir, network_path, detail)) {
        return ConfigureError::AssetMissing;
    }
    std::ifstream in(network_path, std::ios::binary);
    if (!in) {
        detail = "cannot open the NNUE network at " + network_path;
        return ConfigureError::AssetMissing;
    }
    std::string bytes((std::istreambuf_iterator<char>(in)),
                      std::istreambuf_iterator<char>());
    if (in.bad()) {
        detail = "cannot read the NNUE network at " + network_path;
        return ConfigureError::AssetMissing;
    }
    /* The diagnosis leads and the path follows: MxqError.detail is bounded,
     * and when a long path forces truncation it is the path that must lose,
     * never the fact the caller can act on. */
    if (bytes.size() != static_cast<size_t>(MXQ_BUILD_NNUE_BYTE_LENGTH)) {
        detail = "the NNUE network is " + std::to_string(bytes.size()) +
                 " bytes where the pinned network is " +
                 std::to_string(MXQ_BUILD_NNUE_BYTE_LENGTH) + ", at " +
                 network_path;
        return ConfigureError::AssetMismatch;
    }
    if (sha256_hex(bytes) != MXQ_BUILD_NNUE_SHA256) {
        detail = "the NNUE network does not match the pinned SHA-256, at " +
                 network_path;
        return ConfigureError::AssetMismatch;
    }

    {
        CoutSilencer silence;

        /* The pinned variant and the accepted shared search profile: Skill
         * Level 20, UCI_LimitStrength false, MultiPV 1, Ponder false, NNUE
         * evaluation. The profile values are the engine's own defaults, set
         * explicitly so the configuration is what this function says rather
         * than what a default happened to be. */
        Options["UCI_Variant"] = std::string(kVariantId);
        Options["Skill Level"] = std::string("20");
        Options["UCI_LimitStrength"] = std::string("false");
        Options["MultiPV"] = std::string("1");
        Options["Ponder"] = std::string("false");
        Options["Use NNUE"] = std::string("true");
        Options["EvalFile"] = network_path;

        /* The pool and the table. The Hash floor goes first so the pool
         * resize between them re-allocates a megabyte, not whatever the
         * previous preparation had applied; the target Hash then allocates
         * once, at the plan's value. */
        Options["Hash"] = std::string("1");
        Options["Threads"] = std::to_string(threads);
        Options["Hash"] = std::to_string(hash_mib);
    }

    if (!TT.allocated()) {
        /* The fork's recoverable Hash change: a failed resize leaves the
         * table empty and observable rather than terminating the process. */
        detail = "the transposition table of " + std::to_string(hash_mib) +
                 " MiB could not be allocated";
        deconfigure_locked();
        return ConfigureError::HashAllocationFailed;
    }

    /* The effective-state preflight, after the whole configuration and never
     * instead of it. A basename that does not begin with the variant
     * identifier clears the engine's internal NNUE flag silently while the
     * Use NNUE option still reads true, so the option is exactly what must
     * not be trusted here. */
    if (!Eval::useNNUE) {
        detail = "the engine's effective NNUE state is off after "
                 "configuration: the network basename must begin with " +
                 std::string(kVariantId) + " (got " + network_path + ")";
        deconfigure_locked();
        return ConfigureError::AssetMismatch;
    }
    if (Eval::eval_file_loaded != network_path) {
        detail = "the engine did not load the NNUE network at " + network_path;
        deconfigure_locked();
        return ConfigureError::AssetMismatch;
    }
    return ConfigureError::None;
}

void deconfigure() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_ready) {
        return;
    }
    deconfigure_locked();
}

SearchError search_run(const std::string &start_fen,
                       const std::vector<std::string> &moves,
                       uint32_t movetime_ms,
                       const std::atomic<bool> &cancelled,
                       SearchOutput &out, std::string &detail) {
    /* No g_mutex here, deliberately: see the serialisation design in
     * mxq_engine_bridge.hpp. This reads the same stable tables a rules replay
     * reads, and holding the lock for the length of a search would stall
     * every board query behind it. */
    const Variant *v = target_variant();

    auto states = StateListPtr(new std::deque<StateInfo>(1));
    Position pos;
    pos.set(v, start_fen, false, &states->back(), Threads.main());
    for (size_t i = 0; i < moves.size(); ++i) {
        std::string move_text(moves[i]);
        const Move m = UCI::to_move(pos, move_text);
        if (m == MOVE_NONE) {
            detail = "the snapshot no longer replays at ply " +
                     std::to_string(i) + " (" + move_text + ")";
            return SearchError::ReplayFailed;
        }
        states->emplace_back();
        pos.do_move(m, states->back());
    }

    Search::LimitsType limits;
    limits.movetime = static_cast<TimePoint>(movetime_ms);
    limits.startTime = now();

    {
        CoutSilencer silence;
        Threads.start_thinking(pos, states, limits, false);
        /* start_thinking re-arms the engine's stop flag, so a cancellation
         * that raced it would otherwise be lost and the search would run its
         * whole movetime. The cancel path sets the flag before it stops the
         * engine, so this re-check closes the window. */
        if (cancelled.load(std::memory_order_acquire)) {
            Threads.stop = true;
        }
        Threads.main()->wait_for_search_finished();
    }

    const Thread *best = Threads.main()->bestThread;
    const Search::RootMove &root = best->rootMoves[0];
    const Move m = root.pv[0];
    if (m == MOVE_NONE) {
        detail = "the engine reported no move";
        return SearchError::NoMove;
    }
    out.move = UCI::move(best->rootPos, m);
    /* The same centipawn conversion UCI::value applies, clamped to a sentinel
     * for mate-range values. Diagnostic only; nothing adjudicates from it. */
    const Value value = root.score;
    if (value >= VALUE_MATE_IN_MAX_PLY) {
        out.score_cp = 32000;
    } else if (value <= VALUE_MATED_IN_MAX_PLY) {
        out.score_cp = -32000;
    } else {
        out.score_cp = static_cast<int32_t>(value * 100 / PawnValueEg);
    }
    out.depth = static_cast<uint32_t>(best->completedDepth);
    out.nodes = Threads.nodes_searched();
    return SearchError::None;
}

void search_abort() {
    Threads.stop = true;
}

} /* namespace engine */
} /* namespace mxq */
