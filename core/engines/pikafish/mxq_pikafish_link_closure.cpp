/*
 * The three definitions the vendored rules slice references but does not carry:
 * they live in misc.cpp, uci.cpp and tt.cpp, which would pull in the option
 * table, network loading and transposition table the slice leaves behind.
 * Defining them here keeps the target complete, so a whole-archive link
 * (-all_load, -force_load) cannot break it.
 *
 *   prefetch                       the fork's own NO_PREFETCH body; the target
 *                                  defines NO_PREFETCH to match.
 *   TranspositionTable::first_entry reached only through do_move's prefetch;
 *                                  with no table and prefetch a no-op, the
 *                                  result is never read.
 *   UCIEngine::square              the real spelling, not a stub: the slice
 *                                  prints squares through it for the Checkers
 *                                  line. Coordinates are a0-i9, rank 0 Red's.
 *
 * The namespace is spelled Stockfish as the vendored headers declare it; the
 * target renames it to PikafishJieqi.
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
