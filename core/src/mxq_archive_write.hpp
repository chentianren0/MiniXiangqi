/*
 * The archive codec's write side: the only place canonical bytes are produced.
 *
 * docs/game-data.md fixes the canonical form in seven clauses — UTF-8, one
 * line, members in codepoint order, no insignificant whitespace, integers only,
 * `null` forbidden, minimal string escaping. Reading enforces the three that
 * decide what a document means and re-establishes the rest by canonicalising;
 * this writer produces all seven, because the writer's output *is* the
 * canonical spelling and the content hash is taken over exactly these bytes.
 *
 * Nothing here knows what a session is. It takes a Record — the complete
 * version 4 document as values — and returns bytes, so that the same writer
 * serves an attached session's every commit, mxq_archive_encode, and the
 * export path when it lands, and none of them can spell a document its own
 * way.
 */

#ifndef MXQ_ARCHIVE_WRITE_HPP
#define MXQ_ARCHIVE_WRITE_HPP

#include "mxq.h"

#include <cstdint>
#include <string>
#include <vector>

namespace mxq {
namespace archive {

/*
 * One version 4 document, as values.
 *
 * config.game is what the document's rules_id spells and what its start_fen is
 * taken from: one field decides both, so a document cannot record one game's
 * identity beside the other's opening position.
 *
 * The terminal trio is present exactly when completed is true; an active
 * game's stored content omits outcome, end_reason and ended_at, which is the
 * whole difference between the two shapes a stored archive can have.
 *
 * written_at_ms is what origin.exported_at spells. It is the instant of the
 * committed change this document records rather than a fresh reading of the
 * clock, so that a game's archive bytes are a pure function of its committed
 * state: the same committed game encodes identically twice, and identically
 * again after a resume, which is what makes the stored blob comparable with
 * what mxq_archive_encode returns. origin is never hashed, never compared and
 * never trusted (docs/game-data.md), so nothing downstream depends on the
 * choice; the export path regenerates the member for the export event.
 */
struct Record {
    std::string              game_id;
    MxqGameConfig            config{};
    std::vector<std::string> moves;
    int64_t                  started_at_ms = 0;
    int64_t                  written_at_ms = 0;
    bool                     completed = false;
    MxqOutcome               outcome = MXQ_OUTCOME_NONE;
    MxqEndReason             end_reason = MXQ_END_REASON_NONE;
    int64_t                  ended_at_ms = 0;
};

/* The canonical bytes of the `content` object alone — what docs/game-data.md
 * hashes for content identity, and exactly the substring document_bytes
 * embeds. */
std::string content_bytes(const Record &record);

/* The complete canonical document: envelope, the content object as already
 * written, and origin. Taking the content rather than rebuilding it is what
 * guarantees the hashed bytes and the stored bytes are the same bytes. */
std::string document_bytes(const Record &record, const std::string &content);

/* The exact fixed-width RFC 3339 UTC spelling docs/game-data.md fixes:
 * YYYY-MM-DDTHH:MM:SS.sssZ, the one spelling of an instant this format has. */
std::string timestamp_text(int64_t epoch_ms);

/* The closed serialised vocabularies, for the store's summary columns as much
 * as for the document. Absence is a null pointer, matching the archive, which
 * omits the member, and the store, which holds SQL NULL. */
const char *rules_id_text(MxqGameKind game);
const char *mode_text(MxqPlayMode mode);
const char *color_text(MxqColor color);
const char *ai_level_text(MxqAiLevel level);
const char *first_mover_text(MxqFirstMoverChoice choice);
const char *outcome_text(MxqOutcome outcome);
const char *end_reason_text(MxqEndReason reason);

} /* namespace archive */
} /* namespace mxq */

#endif /* MXQ_ARCHIVE_WRITE_HPP */
