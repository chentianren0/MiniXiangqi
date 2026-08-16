/* The Fairy-Stockfish bridge. See mxq_engine_bridge.hpp for why it is one file. */

#include "mxq_engine_bridge.hpp"

#include "mxq_build_config.h"
#include "mxq_notation.hpp"
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

/* Two things are called Variant in this file and nowhere else in the core:
 * mxq::engine::Variant, the closed two-value choice this bridge's callers
 * speak, and Stockfish::Variant, the engine's configuration record for one of
 * them. The unqualified name is the first — the engine's is always written
 * Stockfish::Variant below, which is also how it reads as what it is. */

namespace mxq {
namespace engine {
namespace {

/* The configuration filename is fixed by docs/engine-integration.md, "Variant
 * packaging". */
constexpr const char *kVariantFile = "minixiangqi-variants.ini";

/* Everything pinned to one variant, in one row per variant. The identifier is
 * what UCI_Variant takes and what the network's basename must begin with; the
 * three network fields are that variant's own pins, and reading a network
 * against the wrong row is exactly the mistake the byte preflight below would
 * otherwise stop catching. All of it comes from pinned-inputs.json through the
 * generated build configuration rather than being spelled here. */
struct VariantPin {
    const char *id;
    const char *nnue_filename;
    uint64_t    nnue_byte_length;
    const char *nnue_sha256;
};

constexpr VariantPin kVariantPins[] = {
    {MXQ_BUILD_VARIANT_ID, MXQ_BUILD_NNUE_FILENAME, MXQ_BUILD_NNUE_BYTE_LENGTH,
     MXQ_BUILD_NNUE_SHA256},
    {MXQ_BUILD_XIANGQI_VARIANT_ID, MXQ_BUILD_XIANGQI_NNUE_FILENAME,
     MXQ_BUILD_XIANGQI_NNUE_BYTE_LENGTH, MXQ_BUILD_XIANGQI_NNUE_SHA256},
};
/* The rules posture's variant: the app's own, which is what a core that has
 * never prepared an engine replays in. */
constexpr Variant kDefaultVariant = Variant::MiniXiangqi;

/* A switch rather than a comparison, and a count rather than a comment: adding
 * a variant to the enum without a row here is a warning at the switch, and
 * adding a case without a row is caught by the assertion. Both would otherwise
 * be an out-of-bounds read of a table that looks obviously right. */
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

/* The variant the process-global tables are currently built for. Written only
 * by configure() and deconfigure(), both under g_mutex; read by search_run(),
 * which holds no lock and reads it exactly as it reads those tables. Atomic
 * because a plain read racing a write is a data race whatever the values are,
 * and this one costs nothing. */
std::atomic<Variant> g_active_variant{kDefaultVariant};

/* The engine's process-global bootstrap, done once and never repeated — the
 * piece registry, the variant map and the option map, none of which is
 * per-variant. Loading the variant configuration is separate and may be
 * retried, because a missing or wrong asset directory is a caller's mistake to
 * correct rather than a permanent property of the process. */
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

    /* Every variant this build claims to run, not only the one it starts in:
     * the built-in one is registered by the engine behind its LARGEBOARDS
     * guard, so its absence is a build that lost a define rather than a
     * configuration that lost a section, and the two failures are worth
     * separating in the detail rather than in the code. */
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
    /* One thread: this bridge answers rules queries and never searches. The
     * search facade sizes its own pool through configure(), and deconfigure()
     * restores this posture. */
    Threads.set(1);
    Search::clear();
    /* The piece and bitboard tables for the variant the rules posture uses,
     * built here once and rebuilt only under configure()'s exclusion. replay()
     * used to re-run this per call, which rewrote process-global tables under
     * any concurrent reader once a search could be that reader; see the
     * serialisation design in mxq_engine_bridge.hpp. */
    UCI::init_variant(variants.find(std::string(initial.id))->second);
    g_active_variant.store(kDefaultVariant, std::memory_order_release);
    g_ready = true;
}

const Stockfish::Variant *variant_object(Variant variant) {
    return variants.find(std::string(pin_of(variant).id))->second;
}

/* The variant every rules query and every search reads: the one whose tables
 * are built. */
const Stockfish::Variant *target_variant() {
    return variant_object(g_active_variant.load(std::memory_order_acquire));
}

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

/* The engine reports one side-to-move-relative Value, a flag, and — since the
 * fork's accessor (chentianren0/Fairy-Stockfish#2) — which rule produced the end. The
 * contract wants a state and a reason:
 *
 *  - checkmate and stalemate from there being no legal move, and from whether
 *    the side to move is in check;
 *  - the repetition class from the reported rule, never inferred: the value
 *    alone cannot tell a neutral threefold from a mutual perpetual chase, and
 *    the ply history it used to be inferred from is an inference where a direct
 *    report is available;
 *  - who lost a decisive repetition from the value, by the accepted rule that
 *    the violating side loses — never by which side happens to be to move at
 *    detection.
 *
 * The rule and the value together are exhaustive, because the engine derives
 * both from the same two predicates in one expression: a perpetual violation
 * that only one side commits is a mate value for the other, and one both
 * commit is a draw. So `PERPETUAL_CHECK` with a draw value IS mutual perpetual
 * check, `PERPETUAL_CHASE` with a draw value IS mutual perpetual chase, and
 * `N_FOLD` is the neutral claimable repetition. Nothing here re-derives what
 * that expression already decided. `N_MOVE_RULE` is none of them and is taken
 * first: it is the capture-free move count running out, which Xiangqi has and
 * the app's variant does not.
 *
 * That exhaustiveness is a property of the pinned configuration and not of the
 * engine, and exactly one thing keeps it: position.cpp applies materialCounting
 * AFTER *rule has been set, overwriting a drawn result with a counted one. In a
 * variant with material counting the engine would therefore report
 * PERPETUAL_CHECK with a decisive value for a MUTUAL violation, and reading the
 * value as "one side did it" would name the wrong loser. Neither pinned variant
 * has material counting, so that path is closed here — but neither switch below
 * guesses past what it was told, for the same reason: a wrong reason is
 * recorded in the archive forever, while an absent one is caught by a
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
        /* The move-count rule first, because it is not a repetition and the
         * engine checks it before them: it reports the game that has run its
         * capture-free allowance, and its at_occurrence stays 0 because no
         * position had to stand twice for it. Xiangqi's alone — the app's
         * variant sets nMoveRule = 0, so this arm is unreachable there — and
         * automatic rather than claimable, which is why it is a committed draw
         * and not MXQ_GAME_CLAIMABLE_DRAW. */
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
            /* A neutral threefold and a mutual same-class violation both come
             * back as a draw value. They are different outcomes — the first is
             * claimable and the second is automatic, so the game does not end
             * on its own if this is read wrongly — and the reported rule is
             * exactly what separates them. */
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
                /* Unreachable under either pinned configuration, and left
                 * unnamed rather than folded into the neutral repetition: the
                 * remaining drawn branches are the Janggi position-repetition
                 * rule, the counting rules and the Sittuyin stalemate, none of
                 * which either variant enables. A rule this build does not know
                 * is not evidence that a repetition is claimable, and answering
                 * ONGOING is the honest end of that: the game continues, and a
                 * fixture catches the silence. The occurrence count goes with
                 * it — MxqGameStatus.at_occurrence is 0 unless the outcome is
                 * repetition-based, and this one is not an outcome at all. */
                a.at_occurrence = 0;
                break;
            }
            return a;
        }

        /* A decisive repetition is automatic, not claim-gated. The loser is the
         * violator, by the accepted rule that a violation is named by outcome
         * and never by who is to move at detection. */
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
            /* Unreachable under either pinned configuration: the other decisive
             * branches need material counting or the Janggi repetition rule,
             * and neither variant enables either. Material counting is the one
             * worth naming, because position.cpp applies it AFTER *rule is set
             * and would hand a decisive value to the move-count rule and to a
             * mutual violation alike; with it off, the arm above and this one
             * mean what they say. If one ever fires, the reason is left unset
             * rather than guessed — a wrong reason is recorded in the archive
             * forever, and a fixture catches an absent one. */
            break;
        }
        return a;
    }

    return a;
}

} /* namespace */

Variant variant_of(MxqGameKind game) {
    /* This engine plays the movement games and only those. It is asked here
     * rather than trusted, because the default arm below answers with a real
     * variant: a placement game that reached it would be searched and
     * adjudicated as Mini Xiangqi rather than refused, which is the one way a
     * dispatch that missed a site could fail silently instead of loudly. */
    assert(notation::move_class_of(game) == notation::MoveClass::Movement &&
           "a game this engine does not play reached the bridge");
    switch (game) {
    case MXQ_GAME_KIND_XIANGQI:
        return Variant::Xiangqi;
    case MXQ_GAME_KIND_MINI_XIANGQI:
    default:
        /* The caller has already rejected a game outside the vocabulary — the C
         * surface answers MXQ_ERR_ARG_RANGE for one — so the default arm is
         * unreachable rather than a policy. It names the app's own game because
         * that is the rules posture, and because a switch over an int32_t
         * vocabulary needs a total answer. */
        return Variant::MiniXiangqi;
    }
}

Variant active_variant() {
    return g_active_variant.load(std::memory_order_acquire);
}

const char *variant_id(Variant variant) { return pin_of(variant).id; }

const char *variant_nnue_sha256(Variant variant) {
    return pin_of(variant).nnue_sha256;
}

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

    /* One state record and no move list: nothing here is ever advanced, so the
     * deque a replay needs to keep do_move's back-pointers alive has no
     * counterpart. set() computes the checkers as part of the position's state,
     * which is the whole of what this reads. It is on the heap rather than the
     * stack for the reason every StateInfo in this file is: the record carries
     * an NNUE accumulator and a per-square array, and the allocator is what
     * honours its alignment without this file having to know the number. */
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

    /* The state list must outlive every do_move: Position holds a pointer into
     * it. A deque rather than a vector because reallocation would invalidate
     * those pointers. The piece and bitboard tables are NOT re-initialised
     * here, whichever variant is being replayed: they are the same tables for
     * both (see replay() in mxq_engine_bridge.hpp), and rewriting them per
     * replay would race a concurrent search's reads. */
    auto states = std::make_unique<std::deque<StateInfo>>(1);
    Position pos;
    pos.set(v, std::string(start_fen), false, &states->back(), Threads.main());

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
        states->emplace_back();
        pos.do_move(m, states->back());
        identities.push_back(identity(pos.fen()));
    }

    out_fen = pos.fen();
    /* Asked as a boolean rather than compared against 0: Bitboard is
     * `unsigned __int128` where the compiler has it and a class with
     * conversion operators to bool, unsigned and unsigned long long where it
     * does not — MSVC — and against a literal 0 the class form makes the
     * comparison ambiguous. Its `operator bool` is an exact match, so this
     * reads the same on both, and it is the same question line 181 asks. */
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

/* One network the engine is to be handed, and the row its bytes must satisfy.
 * The pin travels with the path because the two must never be paired by
 * position or by hope: a network verified against the other variant's byte
 * length and hash is verified against nothing. */
struct NetworkChoice {
    std::string       path;
    const VariantPin *pin;
};

/*
 * Find every network to hand the engine for a configuration of `variant`, with
 * that variant's own first.
 *
 * The first is the one that must be there. Its pinned basename is what
 * packaging stages and is preferred; failing that, a directory holding exactly
 * one .nnue file that is no OTHER variant's pinned network names its candidate
 * unambiguously. That fallback is what makes the wrong-basename packaging
 * failure — the network staged under its source name instead of the bundled one
 * — reach the effective-state preflight as a typed refusal instead of hiding
 * behind "no such file": the bytes are right, the byte and hash preflights
 * pass, and the engine then clears its internal NNUE flag over the basename,
 * which is exactly what the preflight exists to catch. A file that IS another
 * variant's pinned network is never that candidate: it is a network this build
 * knows the name of, and treating it as a mystery file would verify it against
 * the wrong pins.
 *
 * Every other pinned network present is appended, so that EvalFile carries the
 * whole set the asset directory holds. Absent ones are simply not in the list:
 * a directory that carries one variant's network prepares that variant and
 * refuses the other, which is what a distribution bundling one network is.
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
 * Caller holds g_mutex. The option floor goes first so the pool resize that
 * follows re-allocates a megabyte rather than the gigabytes being released;
 * the final direct resize(0) is the release itself, which the Hash option
 * cannot express because its minimum is 1.
 *
 * The variant goes back to the rules posture's, and only when it is not there
 * already: assigning UCI_Variant rebuilds the piece, bitboard and PSQT tables
 * and re-runs the NNUE load whatever value it is given, so an unconditional
 * assignment would make every teardown of the app's own variant do work it did
 * not do before this axis existed. Restoring it after the other variant is not
 * optional — the tables a rules query reads are whatever the last configuration
 * left, and a teardown must leave the bridge answering exactly as it did before
 * any preparation. */
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
        /* Unreachable through the facade: mxq_core_init fails whole when the
         * variant configuration does not load. Kept typed rather than assumed
         * away. */
        detail = "the engine is not initialised";
        return ConfigureError::VariantLoadFailed;
    }
    const VariantPin &wanted = pin_of(variant);
    if (variants.find(std::string(wanted.id)) == variants.end()) {
        detail = std::string("the variant ") + wanted.id + " is not loaded";
        return ConfigureError::VariantLoadFailed;
    }

    /* The byte preflight, over every network this configuration will hand the
     * engine: presence, pinned byte length, pinned SHA-256, each against the
     * pins of the variant that network is for. The engine never sees a path
     * whose bytes were not verified first — a hash mismatch is a damaged
     * installation and refuses here, so the engine's own fatal verification
     * path stays unreachable. */
    std::vector<NetworkChoice> networks;
    if (!find_networks(assets_dir, variant, networks, detail)) {
        return ConfigureError::AssetMissing;
    }
    for (const NetworkChoice &network : networks) {
        std::ifstream in(network.path, std::ios::binary);
        if (!in) {
            detail = "cannot open the NNUE network at " + network.path;
            return ConfigureError::AssetMissing;
        }
        std::string bytes((std::istreambuf_iterator<char>(in)),
                          std::istreambuf_iterator<char>());
        if (in.bad()) {
            detail = "cannot read the NNUE network at " + network.path;
            return ConfigureError::AssetMissing;
        }
        /* The diagnosis leads and the path follows: MxqError.detail is
         * bounded, and when a long path forces truncation it is the path that
         * must lose, never the fact the caller can act on. */
        if (bytes.size() !=
            static_cast<size_t>(network.pin->nnue_byte_length)) {
            detail = "the NNUE network is " + std::to_string(bytes.size()) +
                     " bytes where the network pinned for " +
                     std::string(network.pin->id) + " is " +
                     std::to_string(network.pin->nnue_byte_length) + ", at " +
                     network.path;
            return ConfigureError::AssetMismatch;
        }
        if (sha256_hex(bytes) != network.pin->nnue_sha256) {
            detail = "the NNUE network does not match the SHA-256 pinned for " +
                     std::string(network.pin->id) + ", at " + network.path;
            return ConfigureError::AssetMismatch;
        }
    }

    /* EvalFile is a list, and the engine takes the first token whose basename
     * begins with the current variant's identifier. The requested variant's
     * network is first in `networks`, so it is also the token the engine
     * selects — which is what makes `selected` below a fact rather than a
     * second guess at the engine's rule. */
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

        /* The requested variant and the accepted shared search profile: Skill
         * Level 20, UCI_LimitStrength false, MultiPV 1, Ponder false, NNUE
         * evaluation. The profile values are the engine's own defaults, set
         * explicitly so the configuration is what this function says rather
         * than what a default happened to be.
         *
         * Assigning UCI_Variant is what rebuilds the piece, bitboard and PSQT
         * tables for it: the engine's own on-change handler does that work, so
         * a switch needs nothing here beyond being inside this function's
         * exclusion. */
        Options["UCI_Variant"] = std::string(wanted.id);
        g_active_variant.store(variant, std::memory_order_release);
        Options["Skill Level"] = std::string("20");
        Options["UCI_LimitStrength"] = std::string("false");
        Options["MultiPV"] = std::string("1");
        Options["Ponder"] = std::string("false");
        Options["Use NNUE"] = std::string("true");
        Options["EvalFile"] = eval_file;

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
                 std::string(wanted.id) + " (got " + selected + ")";
        deconfigure_locked();
        return ConfigureError::AssetMismatch;
    }
    /* Against the SELECTED token, never against the option value. A failed
     * load leaves the engine's network zeroed and eval_file_loaded naming
     * whatever loaded last, and the engine's own verification asks only
     * whether that stale name appears anywhere in EvalFile — which, with more
     * than one network in the list, it does. */
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
    /* No g_mutex here, deliberately: see the serialisation design in
     * mxq_engine_bridge.hpp. This reads the same stable tables a rules replay
     * reads, and holding the lock for the length of a search would stall
     * every board query behind it. */
    const Stockfish::Variant *v = target_variant();

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
