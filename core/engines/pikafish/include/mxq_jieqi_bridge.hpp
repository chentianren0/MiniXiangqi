/*
 * The one place the core touches the vendored Pikafish jieqi slice. Nothing of
 * the engine appears in this header, so the facade can call the bridge without
 * seeing the renamed namespace the slice is compiled under; the bridge itself
 * is compiled in the slice's target for that reason.
 *
 *   - The engine validates nothing: a malformed record is silently mangled, and
 *     a face-down piece anywhere but its own start square is an out-of-bounds
 *     write. Every position the engine is handed is composed here from a
 *     record that passed read_record.
 *   - Reveal letters always come from the deal the record holds and the move,
 *     never from a caller: the engine would accept and plant a letter naming an
 *     enemy piece or an exhausted identity.
 */

#ifndef MXQ_JIEQI_BRIDGE_HPP
#define MXQ_JIEQI_BRIDGE_HPP

#include "mxq.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace mxq {
namespace jieqi {

constexpr int32_t kFiles = 9;
constexpr int32_t kRanks = 10;

/* No piece letter is 0, so the grid needs no occupancy array. */
constexpr char kEmpty = '\0';

/*
 * A position record, read. A face-down piece is written as its identity letter
 * followed by `~`: the letter says what it is, the mark that the players do not
 * know it.
 *
 * Indexed [rank from Red's back rank][file from a], both zero-based, so
 * letter[0][4] is e1. The FEN lists the highest rank first; read_record turns it.
 */
struct Record {
    char     letter[kRanks][kFiles]; /* the identity; its case is its side */
    bool     down[kRanks][kFiles];   /* face down: the `~` mark */
    MxqColor side_to_move;
    uint32_t halfmove; /* plies since the last capture; the forty-move count */
    uint32_t fullmove;
};

/*
 * Read one position record, refusing everything the engine would not survive:
 * the six fields in their exact spelling; a face-down piece only on a dark home
 * square of its own side; one general a side (without one the engine leaves its
 * king square unset); and at most the face-down complement the game gives a
 * side (the engine's dialect cannot spell a larger pool).
 *
 * `detail` receives the reason on a refusal.
 */
bool read_record(const char *fen, Record &out, std::string &detail);


std::string write_record(const Record &record);

/*
 * The piece that starts on a point of the standard array, kEmpty if none. A
 * hidden piece has never moved, so it plays the role of the square it stands on.
 */
char home_letter(int32_t file, int32_t rank);

/* One of the thirty start squares that is not a general's: the only points a
 * face-down piece can ever stand on. */
bool is_dark_home(int32_t file, int32_t rank);

/* Adjudicated by the bridge, independent of how the engine reports it. */
struct Adjudication {
    MxqGameState state;
    MxqEndReason reason;
    uint32_t     at_occurrence; /* 0 unless the outcome is repetition-based */
};

enum class ReplayError {
    None,
    StartFenInvalid, /* not a position record of this game */
    IllegalMove,     /* first_illegal is the offending index */
    Faulted,         /* an allocation failed; no exception crosses the core */
};

/*
 * Replay `moves` from `start_fen` under Jieqi's rules and report the position
 * reached, check, ply count, adjudication and, if asked, the legal moves in
 * `a1`-`i10` coordinates.
 *
 * Always replay from the line's own start; never adjudicate from a mid-game
 * record. The engine keeps its key across a reveal, but a captured face-down
 * piece's pool decrement updates nothing and setting a position folds the whole
 * remaining pool in, so a position reached by play and the same position set
 * from its record have different keys. Within one replay every compared key
 * lies in one capture-free window and carries the same offset.
 *
 * On anything but ReplayError::None the outputs are unspecified.
 */
ReplayError replay(const char *start_fen, const char *const *moves,
                   size_t move_count, std::string &out_fen, bool &out_in_check,
                   uint32_t &out_ply, Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal, std::string &detail);

} /* namespace jieqi */
} /* namespace mxq */

#endif /* MXQ_JIEQI_BRIDGE_HPP */
