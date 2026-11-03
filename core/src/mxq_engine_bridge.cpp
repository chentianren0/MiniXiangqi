/* The Fairy-Stockfish bridge. */

#include "mxq_engine_bridge.hpp"

#include "mxq_build_config.h"
#include "mxq_notation.hpp"

/* The engine's headers are upstream's; their 64-to-32 conversions would
 * otherwise warn against this file. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
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
#pragma clang diagnostic pop

#include <cassert>
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

/* Unqualified Variant is mxq::engine::Variant; the engine's configuration
 * record is always written Stockfish::Variant. */

namespace mxq {
namespace engine {
namespace {

constexpr const char *kVariantFile = "minixiangqi-variants.ini";

/* One row per variant: the identifier UCI_Variant takes, which the network's
 * basename must begin with, and that variant's network. */
struct VariantPin {
    const char *id;
    const char *nnue_filename;
    const char *nnue_id;
};

constexpr VariantPin kVariantPins[] = {
    {MXQ_BUILD_VARIANT_ID, MXQ_BUILD_NNUE_FILENAME, MXQ_BUILD_NNUE_ID},
    {MXQ_BUILD_XIANGQI_VARIANT_ID, MXQ_BUILD_XIANGQI_NNUE_FILENAME,
     MXQ_BUILD_XIANGQI_NNUE_ID},
};
/* The variant a core that has never prepared an engine replays in. */
constexpr Variant kDefaultVariant = Variant::MiniXiangqi;

/* A variant added to the enum without a row here warns at the switch below;
 * a case added without a row fails this assertion. Either would otherwise be an
 * out-of-bounds read. */
static_assert(sizeof(kVariantPins) / sizeof(kVariantPins[0]) == 2,
              "one pinned row per Variant enumerator");

constexpr size_t pin_index(Variant variant) {
    switch (variant) {
    case Variant::MiniXiangqi:
        return 0u;
    case Variant::Xiangqi:
        return 1u;
    }
    return 0u; /* unreachable: the switch is exhaustive */
}

const VariantPin &pin_of(Variant variant) {
    return kVariantPins[pin_index(variant)];
}

/* The variant the process-global tables are built for. Written only by
 * configure() and deconfigure(), under g_mutex; read lock-free by
 * search_run(), hence atomic. */
std::atomic<Variant> g_active_variant{kDefaultVariant};

/* The piece registry, variant map and option map are bootstrapped once.
 * Loading the variant configuration may be retried, because a wrong asset
 * directory is a caller's mistake to correct, not a property of the process. */
std::once_flag g_bootstrap;
std::mutex g_init_mutex;
std::atomic<bool> g_ready{false};
std::string g_init_detail;
InitError g_init_error = InitError::None;

/* The engine's global state is process-wide and not re-entrant; rules queries
 * are serialised here. */
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

    /* The built-in variant is registered behind the engine's LARGEBOARDS
     * guard, so its absence means a build that lost a define rather than a
     * configuration that lost a section; the detail says which. */
    for (size_t i = 0; i < sizeof(kVariantPins) / sizeof(kVariantPins[0]);
         ++i) {
        const VariantPin &pin = kVariantPins[i];
        if (variants.find(std::string(pin.id)) == variants.end()) {
            g_init_detail =
                i == pin_index(Variant::Xiangqi)
                    ? std::string("the engine does not define the variant ") +
                          pin.id
                    : std::string("the bundled variant configuration does not "
                                  "define the variant ") +
                          pin.id;
            g_init_error = InitError::VariantLoadFailed;
            return;
        }
    }

    const VariantPin &initial = pin_of(kDefaultVariant);
    PSQT::init(variants.find(std::string(initial.id))->second);
    Bitboards::init();
    Position::init();
    Bitbases::init();
    Endgames::init();
    Search::init();
    /* One thread for rules queries; configure() sizes the search pool and
     * deconfigure() restores this. */
    Threads.set(1);
    Search::clear();
    /* Built once here and rebuilt only under configure()'s exclusion, never
     * per replay: a concurrent search reads these tables. */
    UCI::init_variant(variants.find(std::string(initial.id))->second);
    g_active_variant.store(kDefaultVariant, std::memory_order_release);
    g_ready = true;
}

const Stockfish::Variant *variant_object(Variant variant) {
    return variants.find(std::string(pin_of(variant).id))->second;
}

const Stockfish::Variant *target_variant() {
    return variant_object(g_active_variant.load(std::memory_order_acquire));
}

/* Position identity is placement and side to move; the counters are
 * ignored. */
std::string identity(const std::string &fen) {
    size_t sp = fen.find(' ');
    if (sp == std::string::npos) {
        return fen;
    }
    size_t sp2 = fen.find(' ', sp + 1);
    return fen.substr(0, sp2 == std::string::npos ? fen.size() : sp2);
}

/* How many times the position now on the board has stood there. */
size_t occurrences_of(const std::vector<std::string> &identities,
                      const std::string &here) {
    size_t n = 0;
    for (const std::string &past : identities) {
        if (past == here) {
            ++n;
        }
    }
    return n;
}

/* The engine reports one side-to-move-relative Value, a flag, and which rule
 * produced the end (the fork's accessor). From those:
 *
 *  - checkmate and stalemate from there being no legal move, and from whether
 *    the side to move is in check;
 *  - the repetition class from the reported rule, never inferred: the value
 *    alone cannot tell a neutral threefold from a mutual perpetual chase;
 *  - who lost a decisive repetition from the value: the violating side loses,
 *    whoever is to move at detection.
 *
 * The rule and the value together are exhaustive, because the engine derives
 * both from the same two predicates in one expression: a violation only one
 * side commits is a mate value for the other, and one both commit is a draw.
 * So PERPETUAL_CHECK with a draw value IS mutual perpetual check, likewise
 * PERPETUAL_CHASE, and N_FOLD is the neutral claimable repetition. N_MOVE_RULE
 * is none of them: the capture-free move count running out, which Xiangqi has
 * and Mini Xiangqi does not.
 *
 * That exhaustiveness holds only without material counting: position.cpp
 * applies materialCounting AFTER *rule is set, so the engine would report
 * PERPETUAL_CHECK with a decisive value for a MUTUAL violation. Neither pinned
 * variant counts material, and neither switch below guesses past what it was
 * told: a wrong reason is stored with the game, an absent one is caught by a
 * fixture. */
Adjudication adjudicate(Position &pos,
                        const std::vector<std::string> &identities) {
    Adjudication a{};
    a.state = MXQ_GAME_ONGOING;
    a.reason = MXQ_END_REASON_NONE;
    a.at_occurrence = 0;

    const bool side_to_move_is_red = (pos.side_to_move() == WHITE);
    const bool no_legal_move = (MoveList<LEGAL>(pos).size() == 0);

    if (no_legal_move) {
        /* No legal move loses, in check or not: stalemate is not a draw in
         * Xiangqi. */
        a.state = side_to_move_is_red ? MXQ_GAME_BLACK_WINS : MXQ_GAME_RED_WINS;
        a.reason = pos.checkers() ? MXQ_END_REASON_CHECKMATE : MXQ_END_REASON_STALEMATE;
        return a;
    }

    Value value = VALUE_DRAW;
    OptionalGameEndRule rule = OPTIONAL_END_NONE;
    if (pos.is_optional_game_end(value, 0, 0, &rule)) {
        /* Not a repetition, so at_occurrence stays 0. Xiangqi only (Mini
         * Xiangqi sets nMoveRule = 0), and automatic rather than claimable. */
        if (rule == OPTIONAL_END_N_MOVE_RULE) {
            a.state = MXQ_GAME_DRAW;
            a.reason = MXQ_END_REASON_FIFTY_MOVE_RULE;
            return a;
        }

        /* The engine reports that an outcome attached, not where: a violation
         * that was interrupted and resumed attaches at the fourth occurrence,
         * not the third, so this is counted rather than assumed. */
        a.at_occurrence = static_cast<uint32_t>(
            occurrences_of(identities, identity(pos.fen())));

        if (value == VALUE_DRAW) {
            /* A neutral threefold (claimable) and a mutual same-class violation
             * (automatic) both come back as a draw value; the reported rule
             * separates them. */
            switch (rule) {
            case OPTIONAL_END_PERPETUAL_CHECK:
                a.state = MXQ_GAME_DRAW;
                a.reason = MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK;
                break;
            case OPTIONAL_END_PERPETUAL_CHASE:
                a.state = MXQ_GAME_DRAW;
                a.reason = MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE;
                break;
            case OPTIONAL_END_N_FOLD:
                a.state = MXQ_GAME_CLAIMABLE_DRAW;
                a.reason = MXQ_END_REASON_THREEFOLD_REPETITION;
                break;
            default:
                /* Unreachable under either pinned configuration: the other
                 * drawn branches are Janggi repetition, the counting rules and
                 * Sittuyin stalemate. An unknown rule is not evidence that a
                 * repetition is claimable, so the game stays ONGOING and
                 * at_occurrence goes back to 0. */
                a.at_occurrence = 0;
                break;
            }
            return a;
        }

        /* A decisive repetition is automatic, not claim-gated. */
        const bool side_to_move_wins = (value > VALUE_DRAW);
        const bool red_wins = (side_to_move_is_red == side_to_move_wins);
        a.state = red_wins ? MXQ_GAME_RED_WINS : MXQ_GAME_BLACK_WINS;

        switch (rule) {
        case OPTIONAL_END_PERPETUAL_CHECK:
            a.reason = MXQ_END_REASON_PERPETUAL_CHECK;
            break;
        case OPTIONAL_END_PERPETUAL_CHASE:
            a.reason = MXQ_END_REASON_PERPETUAL_CHASE;
            break;
        default:
            /* Unreachable under either pinned configuration: the other
             * decisive branches need material counting or Janggi repetition.
             * The reason is left unset rather than guessed. */
            break;
        }
        return a;
    }

    return a;
}

} /* namespace */

Variant variant_of(MxqGameKind game) {
    /* Asserted because the default arm answers with a real variant: a
     * placement game reaching it would silently be played as Mini Xiangqi. */
    assert(notation::move_class_of(game) == notation::MoveClass::Movement &&
           "a game this engine does not play reached the bridge");
    switch (game) {
    case MXQ_GAME_KIND_XIANGQI:
        return Variant::Xiangqi;
    case MXQ_GAME_KIND_MINI_XIANGQI:
    default:
        /* Unreachable: the C surface rejects an out-of-range game with
         * MXQ_ERR_ARG_RANGE first. */
        return Variant::MiniXiangqi;
    }
}

Variant active_variant() {
    return g_active_variant.load(std::memory_order_acquire);
}

const char *variant_id(Variant variant) { return pin_of(variant).id; }

const char *variant_network_id(Variant variant) {
    return pin_of(variant).nnue_id;
}

InitError ensure_initialised(const char *assets_dir, std::string &detail) {
    std::lock_guard<std::mutex> lock(g_init_mutex);
    if (g_ready) {
        return InitError::None;
    }
    /* Retried rather than latched, reporting the attempt that failed. */
    g_init_detail.clear();
    g_init_error = InitError::None;
    initialise_once(assets_dir ? assets_dir : "");
    if (!g_ready) {
        detail = g_init_detail;
        return g_init_error;
    }
    return InitError::None;
}

bool validate_fen(Variant variant, const char *fen, std::string &detail) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_ready) {
        detail = "the engine is not initialised";
        return false;
    }
    if (fen == nullptr) {
        detail = "fen was null";
        return false;
    }
    const FEN::FenValidation v =
        FEN::validate_fen(std::string(fen), variant_object(variant), false);
    if (v != FEN::FEN_OK) {
        detail = "the FEN does not satisfy the frozen structural encoding";
        return false;
    }
    return true;
}

ProbeError side_to_move_in_check(Variant variant, const char *fen,
                                 bool &out_in_check, std::string &detail) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_ready) {
        detail = "the engine is not initialised";
        return ProbeError::NotInitialised;
    }
    if (fen == nullptr) {
        detail = "fen was null";
        return ProbeError::FenInvalid;
    }

    const Stockfish::Variant *v = variant_object(variant);
    if (FEN::validate_fen(std::string(fen), v, false) != FEN::FEN_OK) {
        detail = "the FEN does not satisfy the frozen structural encoding";
        return ProbeError::FenInvalid;
    }

    /* No move is made, so one state record suffices; set() computes the
     * checkers. On the heap like every StateInfo here: it carries an NNUE
     * accumulator whose alignment the allocator honours. */
    auto state = std::make_unique<StateInfo>();
    Position pos;
    pos.set(v, std::string(fen), false, state.get(), Threads.main());
    out_in_check = static_cast<bool>(pos.checkers());
    return ProbeError::None;
}

ReplayError replay(Variant variant, const char *start_fen,
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

    const Stockfish::Variant *v = variant_object(variant);
    if (FEN::validate_fen(std::string(start_fen), v, false) != FEN::FEN_OK) {
        detail = "start_fen does not satisfy the frozen structural encoding";
        return ReplayError::StartFenInvalid;
    }

    /* The state list must outlive every do_move: Position holds pointers into
     * it, which a vector's reallocation would invalidate. The piece and
     * bitboard tables are deliberately not re-initialised for `variant`; see
     * replay() in the header. */
    auto states = std::make_unique<std::deque<StateInfo>>(1);
    Position pos;
    pos.set(v, std::string(start_fen), false, &states->back(), Threads.main());

    /* Every position the game has stood in, the start included. */
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
        states->emplace_back();
        pos.do_move(m, states->back());
        identities.push_back(identity(pos.fen()));
    }

    out_fen = pos.fen();
    /* Not compared against 0: where Bitboard is a class rather than
     * `unsigned __int128`, that comparison is ambiguous. */
    out_in_check = static_cast<bool>(pos.checkers());
    out_ply = static_cast<uint32_t>(move_count);
    out_adj = adjudicate(pos, identities);

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
 * The engine prints info lines, NNUE and variant notices and bestmove through
 * sync_cout, with no switch to turn it off. std::cout's buffer is swapped for a
 * sink for the duration of configure and the search run, where every engine
 * print happens; any other thread's std::cout output in that window is lost
 * too. std::cerr is left alone: a failed TT allocation is reported there.
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

struct NetworkChoice {
    std::string       path;
    const VariantPin *pin;
};

/*
 * Every network to hand the engine for `variant`, that variant's own first.
 *
 * The first must be there, preferably under its pinned basename; failing that,
 * a lone .nnue file that is no other variant's pinned network is taken. That
 * fallback makes a network staged under the wrong basename reach the
 * effective-state preflight in configure() as AssetMismatch rather than hide
 * behind "no such file".
 *
 * Every other pinned network present is appended; a directory carrying one
 * variant's network prepares that variant and refuses the other.
 */
bool find_networks(const std::string &assets_dir, Variant variant,
                   std::vector<NetworkChoice> &out, std::string &detail) {
    namespace fs = std::filesystem;
    const fs::path dir = assets_dir.empty() ? fs::path(".") : fs::path(assets_dir);
    const VariantPin &wanted = pin_of(variant);

    const auto is_pinned_name = [](const std::string &basename) {
        for (const VariantPin &pin : kVariantPins) {
            if (basename == pin.nnue_filename) {
                return true;
            }
        }
        return false;
    };

    std::error_code ec;
    const fs::path pinned = dir / wanted.nnue_filename;
    if (fs::is_regular_file(pinned, ec)) {
        out.push_back({pinned.string(), &wanted});
    } else {
        std::string only;
        size_t count = 0;
        for (const auto &entry : fs::directory_iterator(dir, ec)) {
            if (entry.is_regular_file() &&
                entry.path().extension() == ".nnue" &&
                !is_pinned_name(entry.path().filename().string())) {
                only = entry.path().string();
                ++count;
            }
        }
        if (ec) {
            detail = "cannot read the asset directory at " + dir.string();
            return false;
        }
        if (count != 1) {
            detail = count == 0
                         ? "no NNUE network for " + std::string(wanted.id) +
                               " found in " + dir.string() + " (expected " +
                               wanted.nnue_filename + ")"
                         : "several unrecognised .nnue files in " +
                               dir.string() + " and none is " +
                               wanted.nnue_filename;
            return false;
        }
        out.push_back({only, &wanted});
    }

    for (const VariantPin &pin : kVariantPins) {
        if (&pin == &wanted) {
            continue;
        }
        const fs::path other = dir / pin.nnue_filename;
        if (fs::is_regular_file(other, ec)) {
            out.push_back({other.string(), &pin});
        }
    }
    return true;
}

/* The deconfigured posture, shared by deconfigure() and configure()'s unwind.
 * Caller holds g_mutex. The Hash floor goes first so the pool resize that
 * follows re-allocates a megabyte rather than the gigabytes being released;
 * resize(0) is the release itself, which the Hash option (minimum 1) cannot
 * express.
 *
 * The variant is restored only when it differs: assigning UCI_Variant rebuilds
 * the tables and re-runs the NNUE load whatever value it is given. */
void deconfigure_locked() {
    CoutSilencer silence;
    if (g_active_variant.load(std::memory_order_relaxed) != kDefaultVariant) {
        Options["UCI_Variant"] = std::string(pin_of(kDefaultVariant).id);
        g_active_variant.store(kDefaultVariant, std::memory_order_release);
    }
    Options["Hash"] = std::string("1");
    Options["Threads"] = std::string("1");
    TT.resize(0);
}

} /* namespace */

ConfigureError configure(Variant variant, uint32_t threads, uint32_t hash_mib,
                         const std::string &assets_dir, std::string &detail) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_ready) {
        /* Unreachable through the facade: mxq_core_init fails when the
         * variant configuration does not load. */
        detail = "the engine is not initialised";
        return ConfigureError::VariantLoadFailed;
    }
    const VariantPin &wanted = pin_of(variant);
    if (variants.find(std::string(wanted.id)) == variants.end()) {
        detail = std::string("the variant ") + wanted.id + " is not loaded";
        return ConfigureError::VariantLoadFailed;
    }

    std::vector<NetworkChoice> networks;
    if (!find_networks(assets_dir, variant, networks, detail)) {
        return ConfigureError::AssetMissing;
    }

    /* The engine takes the first EvalFile token whose basename begins with the
     * variant's identifier; the requested network is first, so it is the one
     * selected. */
    const std::string &selected = networks.front().path;
    std::string eval_file;
    for (const NetworkChoice &network : networks) {
        if (!eval_file.empty()) {
            eval_file += UCI::SepChar;
        }
        eval_file += network.path;
    }

    {
        CoutSilencer silence;

        /* The profile values are the engine's defaults, set explicitly.
         * Assigning UCI_Variant rebuilds the piece, bitboard and PSQT tables
         * through the engine's on-change handler. */
        Options["UCI_Variant"] = std::string(wanted.id);
        g_active_variant.store(variant, std::memory_order_release);
        Options["Skill Level"] = std::string("20");
        Options["UCI_LimitStrength"] = std::string("false");
        Options["MultiPV"] = std::string("1");
        Options["Ponder"] = std::string("false");
        Options["Use NNUE"] = std::string("true");
        Options["EvalFile"] = eval_file;

        /* The Hash floor first, so the pool resize re-allocates a megabyte
         * rather than the previous table; the target Hash then allocates
         * once. */
        Options["Hash"] = std::string("1");
        Options["Threads"] = std::to_string(threads);
        Options["Hash"] = std::to_string(hash_mib);
    }

    if (!TT.allocated()) {
        /* In the fork a failed resize leaves the table empty rather than
         * terminating the process. */
        detail = "the transposition table of " + std::to_string(hash_mib) +
                 " MiB could not be allocated";
        deconfigure_locked();
        return ConfigureError::HashAllocationFailed;
    }

    /* A basename that does not begin with the variant identifier clears the
     * engine's internal NNUE flag silently while the Use NNUE option still
     * reads true. */
    if (!Eval::useNNUE) {
        detail = "the engine's effective NNUE state is off after "
                 "configuration: the network basename must begin with " +
                 std::string(wanted.id) + " (got " + selected + ")";
        deconfigure_locked();
        return ConfigureError::AssetMismatch;
    }
    /* Against the SELECTED token, never the option value: a failed load leaves
     * eval_file_loaded naming whatever loaded last, which may still appear
     * elsewhere in the list. */
    if (Eval::eval_file_loaded != selected) {
        detail = "the engine did not load the NNUE network at " + selected;
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
    /* No g_mutex, deliberately; see the serialisation notes in the header. */
    const Stockfish::Variant *v = target_variant();

    auto states = StateListPtr(new std::deque<StateInfo>(1));
    Position pos;
    pos.set(v, start_fen, false, &states->back(), Threads.main());
    for (size_t i = 0; i < moves.size(); ++i) {
        std::string move_text(moves[i]);
        const Move m = UCI::to_move(pos, move_text);
        if (m == MOVE_NONE) {
            detail = "the line does not replay at ply " +
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
         * that raced it would be lost. The cancel path sets `cancelled` before
         * stopping the engine, so this re-check closes the window. */
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
    /* UCI::value's centipawn conversion, with a sentinel for mate values.
     * Diagnostic only. */
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
