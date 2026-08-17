/*
 * The two paths back from bytes to a whole document: the store's own, and the
 * importer's.
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
 * The rules tier is deliberately not in read_stored. Resuming replays the move
 * line anyway to reach a position, so the caller performs that step and reports
 * its own failure; that function answers only what the bytes structurally say.
 *
 * read_imported is the other one: every bound applied, every stage run
 * including the rules tier, and the same whole document returned. It is what
 * mxq_store_import validates with and what mxq_game_open_archive previews with,
 * so a preview and an import accept exactly the same set of files.
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

/* One version 6 document, decoded whole — a row's or a file's. The terminal
 * trio is meaningful exactly when completed is true. written_at_ms is
 * origin.exported_at, which a resumed session carries forward so that
 * re-encoding it reproduces the bytes the store holds, and which an imported
 * record keeps as the export event the file describes. archive_version is
 * carried because duplicate detection compares it (docs/game-data.md). The
 * document's start_fen is in config, where a session's start lives, rather than
 * beside it: one fact, one home. */
struct Stored {
    uint32_t                 archive_version = 0;
    std::string              game_id;
    MxqGameConfig            config{};
    std::vector<std::string> moves;
    /* The deal's provenance, present exactly for a nearby jieqi document. A
     * session carries it so that re-encoding reproduces the bytes it came from,
     * and so that a resumed game can re-verify its own deal without the
     * document it is not yet. */
    std::string              deal_commit;
    std::string              deal_nonce;
    std::string              deal_seed;
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

#if defined(MXQ_ENABLE_RULES_FACADE)

/*
 * Decode and fully validate untrusted file bytes: docs/game-data.md's accepted
 * validation order entire, stages one to five, with every import bound applied.
 * Returns MXQ_OK, or the archive-domain status of the first stage that refused,
 * with err filled. Touches no persistent state — the caller's write transaction
 * is stage six and runs only after this returns MXQ_OK.
 *
 * One refusal is import's rather than the format's, and it is asked after those
 * five stages rather than among them: a document recording no end is the shape
 * a stored *active* game has, and an import creates an immutable History record
 * or nothing at all, so a file carrying no terminal trio is refused as
 * malformed here rather than at the store's constraints. Every exported file is
 * a completed game (docs/game-data.md). Asking it last is what keeps a file's
 * rejection class the same whichever entry point asked.
 *
 * The rules tier is why this needs the facade, exactly as mxq_archive_validate
 * does.
 */
MxqStatus read_imported(const uint8_t *bytes, size_t len, Stored &out,
                        MxqError *err);

#endif /* MXQ_ENABLE_RULES_FACADE */

} /* namespace archive */
} /* namespace mxq */

#endif /* MXQ_ARCHIVE_READ_HPP */
