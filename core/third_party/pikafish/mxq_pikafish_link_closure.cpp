/*
 * The three definitions the vendored rules slice references and does not carry.
 *
 * This file is ours, not the fork's. Everything under upstream/ is a verbatim
 * copy of the pinned revision; this is the one translation unit in the target
 * that is not, and it exists because the slice is three of the fork's source
 * files rather than all of them. Each declaration below lives in a header the
 * slice includes, and each definition lives in a .cpp file the slice does not
 * take: prefetch in misc.cpp, UCIEngine::square in uci.cpp, and
 * TranspositionTable::first_entry in tt.cpp. Taking those three files instead
 * would pull in the engine's option table, its network loading and its
 * transposition table, which is the whole search and evaluation half this
 * vendoring exists to leave behind.
 *
 * They are defined HERE rather than left for a consumer to supply, and that is
 * a decision rather than a convenience. This target's archive ships inside
 * MiniXiangqiCore.xcframework, and an archive with undefined symbols links
 * correctly only for as long as nothing pulls its members in wholesale — which
 * -all_load, -force_load and a future whole-archive link would each do. A
 * complete archive cannot be broken that way.
 *
 * None of the three is a placeholder. The bodies are correct for a slice that
 * has no search:
 *
 *   prefetch                     is a hint and nothing else, and this is the
 *                                fork's own NO_PREFETCH body verbatim
 *                                (upstream/src/misc.h:47 declares it;
 *                                misc.cpp:438 is this body). The target defines
 *                                NO_PREFETCH so the profile and the body agree.
 *   TranspositionTable::         is reached only through Position::do_move's
 *   first_entry                  prefetch of the entry a search would probe.
 *                                With no table allocated there is no entry, and
 *                                with prefetch a no-op the result is discarded
 *                                unread. Nothing in the slice dereferences it.
 *   UCIEngine::square            is the file-and-rank spelling of a square, and
 *                                this is that function, not a stub. The slice
 *                                reaches it from operator<<(ostream&, const
 *                                Position&) for the Checkers line, which is
 *                                live code — a wrong body here would print
 *                                wrong squares rather than fail to link.
 *
 * The engine's coordinates are a0-i9 with rank 0 as Red's back rank, so the
 * spelling below is 'a' + file and '0' + rank. It is the fork's own, at
 * upstream/src/uci.cpp's definition of the same function at the pinned
 * revision.
 *
 * The namespace written here is Stockfish because that is what the vendored
 * headers declare. The target renames it wholesale — see CMakeLists.txt — so
 * what this file actually defines is PikafishJieqi::. Spelling it Stockfish
 * keeps this file readable beside the sources it completes.
 */

#include "misc.h"
#include "tt.h"
#include "types.h"
#include "uci.h"

#include <string>

namespace Stockfish {

void prefetch(const void*) {}

std::string UCIEngine::square(Square s) {
    return std::string{char('a' + file_of(s)), char('0' + rank_of(s))};
}

TTEntry* TranspositionTable::first_entry(const Key) const { return nullptr; }

}  // namespace Stockfish
