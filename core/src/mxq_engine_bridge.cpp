/* The Fairy-Stockfish bridge. See mxq_engine_bridge.hpp for why it is one file. */

#include "mxq_engine_bridge.hpp"

#include "apiutil.h"
#include "piece.h"
#include "bitboard.h"
#include "endgame.h"
#include "movegen.h"
#include "position.h"
#include "search.h"
#include "thread.h"
#include "uci.h"
#include "variant.h"

#include <cstring>
#include <deque>
#include <fstream>
#include <memory>
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

std::once_flag g_once;
bool g_ready = false;
std::string g_init_detail;

/* The engine's global state is process-wide and not re-entrant, and the core is
 * singleton-enforced for exactly that reason (core-interface.md). Rules queries
 * are serialised here rather than assumed to be called one at a time. */
std::mutex g_mutex;

void initialise_once(const std::string &assets_dir) {
    pieceMap.init();
    variants.init();
    UCI::init(Options);

    const std::string path = assets_dir.empty()
                                 ? std::string(kVariantFile)
                                 : assets_dir + "/" + kVariantFile;
    std::ifstream in(path);
    if (!in) {
        g_init_detail = "cannot open the bundled variant configuration at " + path;
        return;
    }
    std::stringstream ss;
    ss << in.rdbuf();
    variants.parse_istream<false>(ss);
    Options["UCI_Variant"].set_combo(variants.get_keys());

    if (variants.find(std::string(kVariantId)) == variants.end()) {
        g_init_detail = std::string("the bundled configuration does not define ") + kVariantId;
        return;
    }

    PSQT::init(variants.find(std::string(kVariantId))->second);
    Bitboards::init();
    Position::init();
    Bitbases::init();
    Endgames::init();
    Search::init();
    /* One thread: this bridge answers rules queries and never searches. The
     * search facade sizes its own pool. */
    Threads.set(1);
    Search::clear();
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
    if (pos.is_optional_game_end(value)) {
        /* How many times the position on the board has now stood there. The
         * engine reports that an outcome attached, not where: a violation that
         * was interrupted and resumed attaches at the fourth occurrence, not
         * the third, so this is counted rather than assumed. */
        const std::string here = identity(pos.fen());
        uint32_t occurrences = 0;
        for (const std::string &id : identities) {
            if (id == here) {
                ++occurrences;
            }
        }
        a.at_occurrence = occurrences;

        if (value == VALUE_DRAW) {
            /* A neutral threefold and a mutual same-class violation both come
             * back as a draw value. They are different outcomes: the first is
             * claimable and the second is automatic. Mutual perpetual check is
             * separable here, because both sides must have checked at every one
             * of their own moves. Mutual perpetual chase leaves no such trace,
             * and the fork does not yet report which branch fired, so it is
             * reported as the neutral repetition it is indistinguishable from
             * rather than guessed at. */
            size_t red_moves = 0, black_moves = 0;
            bool red_always_checked = true, black_always_checked = true;
            for (const Ply &p : plies) {
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
        for (const Ply &p : plies) {
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

bool ensure_initialised(const char *assets_dir, std::string &detail) {
    const std::string dir = assets_dir ? assets_dir : "";
    std::call_once(g_once, [&] { initialise_once(dir); });
    if (!g_ready) {
        detail = g_init_detail;
        return false;
    }
    return true;
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

bool replay(const char *start_fen,
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
        return false;
    }
    if (start_fen == nullptr) {
        detail = "start_fen was null";
        return false;
    }

    const Variant *v = target_variant();
    if (FEN::validate_fen(std::string(start_fen), v, false) != FEN::FEN_OK) {
        detail = "start_fen does not satisfy the frozen structural encoding";
        return false;
    }

    /* The state list must outlive every do_move: Position holds a pointer into
     * it. A deque rather than a vector because reallocation would invalidate
     * those pointers. */
    auto states = std::make_unique<std::deque<StateInfo>>(1);
    Position pos;
    UCI::init_variant(v);
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
            return false;
        }
        /* to_move takes a non-const reference, so the string must be a named
         * lvalue rather than a temporary. */
        std::string move_text(moves[i]);
        const Move m = UCI::to_move(pos, move_text);
        if (m == MOVE_NONE) {
            first_illegal = i;
            detail = "move " + move_text + " is not legal at its turn";
            return false;
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
    return true;
}

} /* namespace engine */
} /* namespace mxq */
