/*
 * The store's own path back into a game this core wrote.
 *
 * mxq_archive_probe and mxq_archive_validate are import-facing: they apply the
 * accepted import bounds of docs/game-data.md — 1 MiB per file, 10 000 plies —
 * because that is what those bounds are for. Those bounds must not reach a row
 * the store itself wrote: live local play is not length-limited, and a locally
 * produced game that exceeds them stays fully playable and replayable, so a
 * long game must always resume. Only re-importing its export is refused.
 *
 * read_stored is therefore the same decoder with those two bounds lifted, and
 * with the decoded configuration and identity returned in full rather than
 * reduced to the summary MxqArchiveInfo carries — resuming a session needs the
 * move line and the frozen configuration, not a summary. The structural limits
 * that describe the *format* rather than the size of a game (nesting depth,
 * members per object, string length) still apply: a corrupted row must not be
 * able to steer the reader, and no document this writer produces comes close
 * to them.
 *
 * The rules tier is deliberately not here. Resuming replays the move line
 * anyway to reach a position, so the caller performs that step and reports its
 * own failure; this function answers only what the bytes structurally say.
 */

#ifndef MXQ_ARCHIVE_READ_HPP
#define MXQ_ARCHIVE_READ_HPP

#include "mxq.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace mxq {
namespace archive {

/* A stored document, decoded whole. The terminal trio is meaningful exactly
 * when completed is true. written_at_ms is origin.exported_at, which a
 * resumed session carries forward so that re-encoding it reproduces the bytes
 * the store holds. */
struct Stored {
    std::string              game_id;
    MxqGameConfig            config{};
    std::vector<std::string> moves;
    std::string              start_fen;
    int64_t                  started_at_ms = 0;
    int64_t                  written_at_ms = 0;
    bool                     completed = false;
    MxqOutcome               outcome = MXQ_OUTCOME_NONE;
    MxqEndReason             end_reason = MXQ_END_REASON_NONE;
    int64_t                  ended_at_ms = 0;
};

/*
 * Decode bytes the store holds. Returns MXQ_OK, or the archive-domain status
 * the same stages would return for an imported file, with err filled. The
 * caller decides what a refusal means where it stands: a row this core wrote
 * that no longer decodes is store corruption rather than a bad import.
 */
MxqStatus read_stored(const uint8_t *bytes, size_t len, Stored &out,
                      MxqError *err);

} /* namespace archive */
} /* namespace mxq */

#endif /* MXQ_ARCHIVE_READ_HPP */
