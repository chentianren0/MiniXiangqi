/*
 * The one place the core touches the vendored Pikafish jieqi slice.
 *
 * Everything above this header speaks in mxq_ types and in the position record
 * docs/jieqi-rules.md freezes; everything below it speaks the engine's own
 * dialect and the engine's own types. Nothing of the engine appears here, which
 * is what lets mxq_core call this bridge without ever seeing the renamed
 * namespace the slice is compiled under — see the target's wiring in
 * core/CMakeLists.txt, where the reason that separation is load-bearing rather
 * than tidy is written out.
 *
 * The bridge is its own static library for that reason: it links mxq::pikafish
 * the ordinary way, and mxq_core holds it behind $<LINK_ONLY:>, so the rename
 * definition reaches this translation unit and no other. A core source that
 * spoke Stockfish:: to the OTHER engine must never be compiled under it.
 *
 * Two obligations of docs/jieqi-engine-integration.md live here and are the
 * reason several things below look like duplication of the engine's own work:
 *
 *   - **The engine validates nothing.** Setting a position has no error path, a
 *     malformed record is silently mangled, and a face-down piece spelled
 *     anywhere but its own start square is an out-of-bounds write rather than a
 *     refusal. So read_record below is the structural reading of the record
 *     form, it runs before anything reaches the engine, and every position the
 *     engine is handed is composed by this bridge from a record that passed it.
 *   - **Reveal letters are always the core's own.** What a move revealed is
 *     derived from the deal the record already holds and from the move, never
 *     from a file, a caller, or another device — the engine's dialect would
 *     accept a letter naming an enemy piece or an identity the pool has
 *     exhausted, and plant it.
 *
 * Compiled only when MXQ_ENABLE_RULES_FACADE is ON, which is the switch the
 * slice itself shares.
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

/* Xiangqi's board exactly, which is Jieqi's: nine files, ten ranks. */
constexpr int32_t kFiles = 9;
constexpr int32_t kRanks = 10;

/* An empty point. No piece letter is 0, so the grid needs no second array to
 * say which of its points are occupied. */
constexpr char kEmpty = '\0';

/*
 * A position in the record form docs/jieqi-rules.md freezes, read.
 *
 * The record is the objective position and holds every hidden identity: a
 * face-down piece is written as its identity letter followed by `~`, so the
 * letter says what the piece is and the mark says the players do not know it.
 * That is the whole of the difference from a Xiangqi position record, and it is
 * why this struct carries the two arrays rather than one.
 *
 * Indexed [rank from Red's back rank][file from a], both zero-based, so
 * letter[0][4] is e1 and letter[9][4] is e10. The FEN's own order is the other
 * way round — highest rank first — and read_record is where that is turned.
 */
struct Record {
    char     letter[kRanks][kFiles]; /* the identity; its case is its side */
    bool     down[kRanks][kFiles];   /* face down: the `~` mark */
    MxqColor side_to_move;
    uint32_t halfmove; /* plies since the last capture; the forty-move count */
    uint32_t fullmove;
};

/*
 * Read one position record, and refuse everything the engine would not survive.
 *
 * This is mxq_rules_validate_fen's answer for this game, and it takes less than
 * the record's alphabet allows, exactly as docs/core-interface.md states: the
 * six fields and the frozen spelling of each; a face-down piece only on one of
 * the thirty dark home squares and only in the colour of the side whose square
 * that is; one general a side; and a face-down complement inside what the game
 * gives a side. The last two are what a board this entry accepts owes the
 * engine — a board without a general leaves its king square unset, and a
 * face-down count above nine is a pool this dialect cannot spell.
 *
 * `detail` receives the reason on a refusal, as the short English diagnostic
 * MxqError carries.
 */
bool read_record(const char *fen, Record &out, std::string &detail);

/* The record written back out, in the same frozen form. */
std::string write_record(const Record &record);

/*
 * The piece that starts on one point of the standard array, in Red's own
 * letters for Red's half and Black's for Black's, and kEmpty for a point no
 * piece starts on.
 *
 * It is the whole of what makes a hidden piece move: a hidden piece has never
 * moved, so the square it stands on is its own start square, and the role it
 * plays is the role that square gives it. The dealt-start predicate reads the
 * same table for the same reason, which is why it is here and not private.
 */
char home_letter(int32_t file, int32_t rank);

/* Whether a face-down piece may stand on this point: one of the thirty start
 * squares that is not a general's. The two generals are the only pieces that
 * ever start face up, and a piece flips the moment it moves, so no other point
 * of the board ever holds one. */
bool is_dark_home(int32_t file, int32_t rank);

/* Adjudication as docs/jieqi-rules.md describes it, independent of how the
 * engine happens to report it. Its shape is the other bridges': a state, a
 * reason, and the occurrence a repetition-based outcome attached at. */
struct Adjudication {
    MxqGameState state;
    MxqEndReason reason;
    uint32_t     at_occurrence; /* 0 unless the outcome is repetition-based */
};

/* Why a replay did not complete. Returned rather than inferred from the detail
 * string, exactly as the other two bridges return theirs. */
enum class ReplayError {
    None,
    StartFenInvalid, /* not a position record of this game */
    IllegalMove,     /* first_illegal is the offending index */
    Faulted,         /* the bridge could not run: an allocation it could not
                      * meet. docs/architecture.md forbids an exception crossing
                      * the core's boundary, so it is contained here */
};

/*
 * Replay `moves` from `start_fen` under Jieqi's rules, and report where the line
 * arrived: the position in the record form, whether the side to move is in
 * check, the ply count, the adjudication, and — when asked for — every legal
 * move there, in the contract's own `a1`-`i10` coordinates.
 *
 * The whole line is replayed from its own start every time, and no adjudication
 * ever resumes from a mid-game record: a position reached by playing a line and
 * the same position set from its own record do not carry the same key, because
 * the engine's flip bookkeeping maintains the key across a reveal while the pool
 * decrement for a captured face-down piece maintains nothing and setting a
 * position folds the whole remaining pool in. Within one replay that divergence
 * cannot mislead — every key the engine compares lies inside one capture-free
 * window and carries the same offset — which is the argument
 * docs/jieqi-engine-integration.md makes in full.
 *
 * On anything but ReplayError::None the outputs are unspecified, exactly as
 * mxq_rules_evaluate documents.
 */
ReplayError replay(const char *start_fen, const char *const *moves,
                   size_t move_count, std::string &out_fen, bool &out_in_check,
                   uint32_t &out_ply, Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal, std::string &detail);

} /* namespace jieqi */
} /* namespace mxq */

#endif /* MXQ_JIEQI_BRIDGE_HPP */
