/*
 * TEMPORARY. Delete this file, its target in core/CMakeLists.txt, and the
 * core/tools/ directory when the rules facade lands.
 *
 * It exists for exactly one reason: the commit that vendors the pinned
 * Fairy-Stockfish fork has to be able to show that the engine is really linked
 * and that minixiangqiaxf really loads, and at that commit the core's own rules
 * facade — mxq_core_init, mxq_rules_evaluate, mxq_rules_legal_moves — is not
 * written yet, so the fixture runner cannot show it. Once the facade exists,
 * the approved fixtures in fixtures/rules/ demonstrate all of this and more, and
 * this probe is strictly worse than they are.
 *
 * It is not a test: it asserts nothing and CTest does not run it. It prints what
 * the engine reports and exits non-zero only if something it needs is absent.
 *
 * Build and run from the repository root:
 *
 *   cmake -S core -B core/.build -G Ninja -DMXQ_ENABLE_RULES_FACADE=ON
 *   cmake --build core/.build --target mxq_engine_probe
 *   ./core/.build/mxq_engine_probe
 */

#include "mxq.h"

#include "bitboard.h"
#include "endgame.h"
#include "evaluate.h"
#include "misc.h"
#include "movegen.h"
#include "piece.h"
#include "position.h"
#include "psqt.h"
#include "search.h"
#include "thread.h"
#include "types.h"
#include "uci.h"
#include "variant.h"

#include <cstddef>
#include <deque>
#include <iostream>
#include <string>
#include <vector>

using namespace Stockfish;

namespace {

const char *chasing_rule_name(ChasingRule rule) {
    switch (rule) {
    case NO_CHASING: return "none";
    case AXF_CHASING: return "axf";
    }
    return "unrecognised";
}

const char *yes_no(bool value) { return value ? "true" : "false"; }

/* Everything main() in the fork's src/main.cpp does before UCI::loop, minus
 * CommandLine::init, which only supplies a search directory for an embedded
 * NNUE network this build does not have. */
void engine_init() {
    pieceMap.init();
    variants.init();
    UCI::init(Options);
    Tune::init();
    PSQT::init(variants.find(Options["UCI_Variant"])->second);
    Bitboards::init();
    Position::init();
    Bitbases::init();
    Endgames::init();
    Threads.set(static_cast<size_t>(Options["Threads"]));
    Search::clear();
    Eval::NNUE::init();
}

void describe(const std::string &name, const Variant *v) {
    std::cout << "  " << name << "\n"
              << "    board                     : " << (v->maxFile + 1) << " files x "
              << (v->maxRank + 1) << " ranks\n"
              << "    startFen                  : " << v->startFen << "\n"
              << "    chasingRule               : " << chasing_rule_name(v->chasingRule) << "\n"
              << "    promotedSoldiersChaseable : " << yes_no(v->promotedSoldiersChaseable) << "\n"
              << "    nMoveRule                 : " << v->nMoveRule << "\n"
              << "    nFoldRule                 : " << v->nFoldRule << "\n"
              << "    perpetualCheckIllegal     : " << yes_no(v->perpetualCheckIllegal) << "\n"
              << "    flyingGeneral             : " << yes_no(v->flyingGeneral) << "\n";
}

int legal_move_count(const Variant *v, const std::string &fen,
                     std::vector<std::string> &out) {
    StateListPtr states(new std::deque<StateInfo>(1));
    Position pos;
    UCI::init_variant(v);
    pos.set(v, fen, false, &states->back(), Threads.main());
    int n = 0;
    for (const ExtMove &m : MoveList<LEGAL>(pos)) {
        out.push_back(UCI::move(pos, m));
        ++n;
    }
    return n;
}

} /* namespace */

int main() {
    /* The frozen starting position comes from the core, not from this file and
     * not from the engine: mxq_rules_start_fen is what the contract defines, and
     * calling it also proves mxq_core itself is linked into this binary. */
    char fen_buffer[128];
    size_t fen_len = 0;
    if (mxq_rules_start_fen(fen_buffer, sizeof(fen_buffer), &fen_len, nullptr) != MXQ_OK) {
        std::cerr << "probe: mxq_rules_start_fen failed\n";
        return 2;
    }
    const std::string start_fen(fen_buffer, fen_len);

    engine_init();
    std::cout << "engine        : " << engine_info() << "\n";
    std::cout << "core start FEN: " << start_fen << "\n";

    const std::string ini_path = MXQ_VARIANT_INI_PATH;
    std::cout << "variant file  : " << ini_path << "\n";

    if (variants.find("minixiangqiaxf") != variants.end()) {
        std::cerr << "probe: minixiangqiaxf exists before the file is loaded; the "
                     "name is supposed to be ours alone\n";
        return 2;
    }
    std::cout << "minixiangqiaxf before load: absent\n";

    Options["VariantPath"] = ini_path;

    const auto target = variants.find("minixiangqiaxf");
    if (target == variants.end()) {
        std::cerr << "probe: minixiangqiaxf did not load from " << ini_path << "\n";
        return 1;
    }
    std::cout << "minixiangqiaxf after load : present\n\n";

    const auto control = variants.find("minixiangqi");
    if (control == variants.end()) {
        std::cerr << "probe: built-in minixiangqi is missing\n";
        return 2;
    }

    std::cout << "variant configuration, target and control:\n";
    describe("[" + target->first + "] (loaded from the bundled file)", target->second);
    describe("[" + control->first + "] (built in, the fixture harness control)",
             control->second);

    std::cout << "\nlegal moves from the frozen starting position:\n";
    for (const auto *entry : {&*target, &*control}) {
        std::vector<std::string> moves;
        const int n = legal_move_count(entry->second, start_fen, moves);
        std::cout << "  " << entry->first << ": " << n << "\n    ";
        for (size_t i = 0; i < moves.size(); ++i) {
            std::cout << moves[i] << (i + 1 == moves.size() ? "\n" : " ");
        }
    }

    Threads.set(0);
    variants.clear_all();
    pieceMap.clear_all();
    return 0;
}
