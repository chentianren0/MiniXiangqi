/*
 * The store's C surface: the active game, and History as something to read.
 *
 * Everything here is a thin translation. The transactions live in
 * mxq_store.cpp, the sessions in mxq_session.cpp, and what this file does is
 * turn the database's own vocabulary — the serialised identifiers the schema's
 * CHECK constraints are written in — into the enums MxqRecordSummary carries,
 * and turn a caller's buffer into the buffer convention each function
 * documents.
 *
 * Three functions here need the rules facade and are absent without it, for
 * the same reason mxq_archive_validate is: a live state is derived by
 * replaying a move line, and a session is a move line plus that replay. The
 * other five are pure store queries and answer in either configuration,
 * because a function that can answer should.
 */

#include "mxq_archive_write.hpp"
#include "mxq_core_state.hpp"
#include "mxq_internal.hpp"
#include "mxq_store.hpp"

#if defined(MXQ_ENABLE_RULES_FACADE)
#include "mxq_archive_read.hpp"
#include "mxq_session.hpp"
#endif

#include <cassert>
#include <cstring>
#include <string>
#include <vector>

namespace mxq {
namespace store {
namespace {

/* ---------------------------------------------------------------------- */
/* The closed vocabularies, read backwards                                 */
/* ---------------------------------------------------------------------- */

/*
 * Each of these inverts the writer's own table rather than restating it. A
 * second list of spellings here would be a second authority for what
 * "black-wins" means, and the two would drift the first time one was edited;
 * inverting the forward function makes that impossible.
 *
 * An empty column is the archive's absence — SQL NULL, which is what the four
 * configuration members hold in Free Play and what the terminal pair holds
 * while a game is still active — and maps to the NONE constant. A non-empty
 * value outside the vocabulary cannot arise from anything this core writes:
 * the schema refuses it as a CHECK constraint, so meeting one is corruption.
 */
template <typename Value, size_t N>
bool value_of(const std::string &text, const Value (&domain)[N],
              const char *(*spelling)(Value), Value &out) {
    for (const Value candidate : domain) {
        const char *name = spelling(candidate);
        if (name != nullptr && text == name) {
            out = candidate;
            return true;
        }
    }
    return false;
}

bool game_of(const std::string &text, MxqGameKind &out) {
    /* Every game the vocabulary has, and the spelling is what says which of
     * them this format version stores: a game it does not carry has none, and
     * value_of's null test above is where that becomes a refusal rather than a
     * row read as some other game. */
    static const MxqGameKind domain[] = {MXQ_GAME_KIND_MINI_XIANGQI,
                                         MXQ_GAME_KIND_XIANGQI,
                                         MXQ_GAME_KIND_GOMOKU_15,
                                         MXQ_GAME_KIND_RENJU,
                                         MXQ_GAME_KIND_JIEQI};
    return value_of(text, domain, archive::rules_id_text, out);
}

bool mode_of(const std::string &text, MxqPlayMode &out) {
    static const MxqPlayMode domain[] = {MXQ_PLAY_MODE_HUMAN_VS_AI,
                                         MXQ_PLAY_MODE_FREE_PLAY,
                                         MXQ_PLAY_MODE_NEARBY,
                                         MXQ_PLAY_MODE_ONLINE};
    return value_of(text, domain, archive::mode_text, out);
}

bool color_of(const std::string &text, MxqColor &out) {
    static const MxqColor domain[] = {MXQ_COLOR_RED, MXQ_COLOR_BLACK};
    if (text.empty()) {
        out = MXQ_COLOR_NONE;
        return true;
    }
    return value_of(text, domain, archive::color_text, out);
}

bool ai_level_of(const std::string &text, MxqAiLevel &out) {
    static const MxqAiLevel domain[] = {MXQ_AI_LEVEL_FAST, MXQ_AI_LEVEL_STANDARD,
                                        MXQ_AI_LEVEL_DEEP};
    if (text.empty()) {
        out = MXQ_AI_LEVEL_NONE;
        return true;
    }
    return value_of(text, domain, archive::ai_level_text, out);
}

bool outcome_of(const std::string &text, MxqOutcome &out) {
    static const MxqOutcome domain[] = {MXQ_OUTCOME_NONE, MXQ_OUTCOME_RED_WINS,
                                        MXQ_OUTCOME_BLACK_WINS,
                                        MXQ_OUTCOME_DRAW};
    if (text.empty()) {
        /* MxqOutcome has no absent constant, and MXQ_OUTCOME_NONE is also the
         * committed outcome of a game ended early. end_reason is what
         * separates the two, exactly as it is in MxqArchiveInfo. */
        out = MXQ_OUTCOME_NONE;
        return true;
    }
    return value_of(text, domain, archive::outcome_text, out);
}

bool end_reason_of(const std::string &text, MxqEndReason &out) {
    static const MxqEndReason domain[] = {
        MXQ_END_REASON_CHECKMATE,              MXQ_END_REASON_STALEMATE,
        MXQ_END_REASON_THREEFOLD_REPETITION,   MXQ_END_REASON_PERPETUAL_CHECK,
        MXQ_END_REASON_PERPETUAL_CHASE,        MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK,
        MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE, MXQ_END_REASON_RESIGNATION,
        MXQ_END_REASON_ENDED_EARLY,            MXQ_END_REASON_FIFTY_MOVE_RULE,
        MXQ_END_REASON_FORTY_MOVE_RULE,
        MXQ_END_REASON_AGREED_DRAW,            MXQ_END_REASON_MUTUAL_RESIGNATION,
        MXQ_END_REASON_FIVE_IN_A_ROW,          MXQ_END_REASON_BOARD_FULL};
    if (text.empty()) {
        out = MXQ_END_REASON_NONE;
        return true;
    }
    return value_of(text, domain, archive::end_reason_text, out);
}

/* Provenance is local library metadata and never an archive field, so the
 * writer has no spelling of it to invert; docs/game-data.md's vocabulary is
 * transcribed here, where it is used. */
bool provenance_of(const std::string &text, MxqProvenance &out) {
    if (text == "locally-played") {
        out = MXQ_PROVENANCE_LOCALLY_PLAYED;
        return true;
    }
    if (text == "imported") {
        out = MXQ_PROVENANCE_IMPORTED;
        return true;
    }
    if (text == "derived") {
        out = MXQ_PROVENANCE_DERIVED;
        return true;
    }
    return false;
}

} /* namespace */

/*
 * One row's summary columns as MxqRecordSummary. Declared in mxq_store.hpp
 * because the interchange pair returns one too; see the comment there.
 *
 * Every field is a column; nothing is recomputed from the blob here, because
 * the columns are written from the same values the document is written from
 * and docs/game-data.md requires them to be exactly recomputable from it —
 * except the four that are local library metadata, which the blob does not
 * decide and which are read from their own columns like the rest. A value
 * outside a closed vocabulary is corruption rather than a summary with a
 * guessed field in it.
 */
MxqStatus fill_summary(const Summary &row, bool is_active,
                       MxqRecordSummary *out, MxqError *err) {
    MxqGameKind game = MXQ_GAME_KIND_MINI_XIANGQI;
    MxqPlayMode mode = MXQ_PLAY_MODE_FREE_PLAY;
    MxqColor human_side = MXQ_COLOR_NONE;
    MxqColor local_side = MXQ_COLOR_NONE;
    MxqAiLevel ai_level = MXQ_AI_LEVEL_NONE;
    MxqOutcome outcome = MXQ_OUTCOME_NONE;
    MxqEndReason end_reason = MXQ_END_REASON_NONE;
    MxqProvenance provenance = MXQ_PROVENANCE_LOCALLY_PLAYED;
    if (!game_of(row.rules_id, game) || !mode_of(row.mode, mode) ||
        !color_of(row.human_side, human_side) ||
        !color_of(row.local_side, local_side) ||
        !ai_level_of(row.ai_level, ai_level) ||
        !outcome_of(row.outcome, outcome) ||
        !end_reason_of(row.end_reason, end_reason) ||
        !provenance_of(row.provenance, provenance)) {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   "a stored row carries a value outside the closed "
                   "vocabularies");
        return MXQ_ERR_STORE_CORRUPT;
    }
    if (row.game_id.size() + 1 > sizeof(out->game_id)) {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   "a stored row's identity is not a canonical UUID");
        return MXQ_ERR_STORE_CORRUPT;
    }

    out->move_count = static_cast<uint32_t>(row.move_count);
    out->record_id = row.record_id;
    out->started_at_ms = row.started_at_ms;
    out->ended_at_ms = row.ended_at_ms;
    out->added_at_ms = row.added_at_ms;
    out->mode = mode;
    out->human_side = human_side;
    out->ai_level = ai_level;
    out->ai_movetime_ms = static_cast<uint32_t>(row.ai_movetime_ms);
    out->outcome = outcome;
    out->end_reason = end_reason;
    out->provenance = provenance;
    out->pinned = row.pinned ? 1u : 0u;
    out->is_active = is_active ? 1u : 0u;
    out->game = game;
    out->local_side = local_side;
    copy_bounded(out->game_id, sizeof(out->game_id), row.game_id.c_str());
    return MXQ_OK;
}

MxqStatus begin_summary(MxqRecordSummary *out, MxqError *err) {
    return begin_out(out, out != nullptr ? out->struct_size : 0u,
                     static_cast<uint32_t>(sizeof(MxqRecordSummary)),
                     static_cast<uint32_t>(sizeof(MxqRecordSummary)), err);
}

} /* namespace store */
} /* namespace mxq */

/* ------------------------------------------------------------------------- */
/* The C surface                                                             */
/* ------------------------------------------------------------------------- */

extern "C" {

MxqStatus MXQ_CALL mxq_store_active_exists(MxqCore *core, uint8_t *out_exists,
                                           MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_exists == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_exists = 0;

    bool exists = false;
    const MxqStatus st = mxq::store::active_exists(*core->store, exists, err);
    if (st != MXQ_OK) {
        return st;
    }
    *out_exists = exists ? 1u : 0u;
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_store_history_count(MxqCore *core, uint32_t *out_count,
                                           uint64_t *out_library_revision,
                                           MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_count == nullptr || out_library_revision == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_count = 0;
    *out_library_revision = 0;

    uint32_t count = 0;
    uint64_t revision = 0;
    const MxqStatus st =
        mxq::store::history_count(*core->store, count, revision, err);
    if (st != MXQ_OK) {
        return st;
    }
    *out_count = count;
    *out_library_revision = revision;
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_store_history_page(MxqCore *core, uint32_t offset,
                                          uint32_t limit,
                                          MxqRecordSummary *out, size_t cap,
                                          size_t *out_count,
                                          uint64_t *out_library_revision,
                                          MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_count == nullptr || out_library_revision == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_count = 0;
    *out_library_revision = 0;

    /*
     * The caller chose the page size, so a buffer that cannot hold it is a
     * caller bug rather than a routine way of asking how much room a page
     * needs: the answer is the number the caller just supplied. Nothing is
     * read, and required_size carries limit back for symmetry with every other
     * buffer-too-small.
     */
    if (cap < limit) {
        mxq::fill_error_required(err, MXQ_ERR_ARG_BUFFER_TOO_SMALL,
                                 "the History page buffer is smaller than the "
                                 "requested page",
                                 limit);
        return MXQ_ERR_ARG_BUFFER_TOO_SMALL;
    }
    if (limit > 0 && out == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL,
                        "a page of more than zero records needs somewhere to "
                        "write them");
        return MXQ_ERR_ARG_NULL;
    }

    std::vector<mxq::store::Summary> rows;
    uint64_t revision = 0;
    const MxqStatus st =
        mxq::store::history_page(*core->store, offset, limit, rows, revision,
                                 err);
    if (st != MXQ_OK) {
        return st;
    }
    for (size_t i = 0; i < rows.size(); ++i) {
        /* An array's elements are stamped rather than inspected, as
         * mxq_game_legal_moves' are: the core indexes the array by its own
         * sizeof, so a caller whose element size differed could not be indexed
         * at all, and there is nothing a per-element struct_size could tell it
         * that the array itself has not already assumed. */
        std::memset(&out[i], 0, sizeof(MxqRecordSummary));
        out[i].struct_size = static_cast<uint32_t>(sizeof(MxqRecordSummary));
        const MxqStatus filled =
            mxq::store::fill_summary(rows[i], false, &out[i], err);
        if (filled != MXQ_OK) {
            return filled;
        }
    }
    *out_count = rows.size();
    *out_library_revision = revision;
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_store_history_get(MxqCore *core, uint64_t record_id,
                                         MxqRecordSummary *out, MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    rc = mxq::store::begin_summary(out, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::store::Summary row;
    rc = mxq::store::history_record(*core->store, record_id, row, nullptr, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    return mxq::store::fill_summary(row, false, out, err);
}

MxqStatus MXQ_CALL mxq_store_history_set_pinned(MxqCore *core,
                                                uint64_t record_id,
                                                uint8_t pinned, MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (pinned > 1u) {
        assert(false && "pinned is 0 or 1");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE, "pinned is 0 or 1");
        return MXQ_ERR_ARG_RANGE;
    }
    return mxq::store::history_set_pinned(*core->store, record_id, pinned != 0,
                                          err);
}

MxqStatus MXQ_CALL mxq_store_history_delete(MxqCore *core, uint64_t record_id,
                                            MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    return mxq::store::history_delete(*core->store, record_id, err);
}

#if defined(MXQ_ENABLE_RULES_FACADE)

MxqStatus MXQ_CALL mxq_store_active_summary(MxqCore *core,
                                            MxqRecordSummary *out,
                                            MxqGameStatus *out_status,
                                            uint8_t *out_exists,
                                            MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_exists == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_exists = 0;
    /* Both optional outs are prepared before anything can fail, so that a
     * caller reading them after a refusal reads zeroes rather than whatever
     * they held. */
    if (out != nullptr) {
        rc = mxq::store::begin_summary(out, err);
        if (rc != MXQ_OK) {
            return rc;
        }
    }
    if (out_status != nullptr) {
        rc = mxq::begin_out(out_status, out_status->struct_size,
                            static_cast<uint32_t>(sizeof(MxqGameStatus)),
                            static_cast<uint32_t>(sizeof(MxqGameStatus)), err);
        if (rc != MXQ_OK) {
            return rc;
        }
    }

    bool exists = false;
    mxq::store::Summary row;
    std::string archive_bytes;
    rc = mxq::store::active_summary(*core->store, exists, row,
                                    out_status != nullptr ? &archive_bytes
                                                          : nullptr,
                                    err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (!exists) {
        /* Absence is success, exactly as it is for mxq_game_resume_active. */
        return MXQ_OK;
    }
    if (out != nullptr) {
        rc = mxq::store::fill_summary(row, true, out, err);
        if (rc != MXQ_OK) {
            return rc;
        }
    }

    if (out_status != nullptr) {
        /*
         * The live state is derived by replaying the stored line, because
         * there is nowhere else it could come from: no state flag is
         * persisted, and a second adjudicator would be a second answer. The
         * decode is the store's own path back into a row it wrote, so its
         * refusals are corruption rather than an archive rejection.
         */
        mxq::archive::Stored stored;
        MxqError decode_error;
        std::memset(&decode_error, 0, sizeof(decode_error));
        decode_error.struct_size = static_cast<uint32_t>(sizeof(decode_error));
        const MxqStatus decoded = mxq::archive::read_stored(
            reinterpret_cast<const uint8_t *>(archive_bytes.data()),
            archive_bytes.size(), stored, &decode_error);
        if (decoded != MXQ_OK) {
            mxq::fill_error_subsystem(
                err, MXQ_ERR_STORE_CORRUPT,
                (std::string("the stored active game does not decode: ") +
                 decode_error.detail)
                    .c_str(),
                decoded);
            return MXQ_ERR_STORE_CORRUPT;
        }
        rc = mxq::session::status_of_line(stored.config, stored.moves,
                                          out_status, err);
        if (rc != MXQ_OK) {
            return rc;
        }
    }

    *out_exists = 1;
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_store_archive_and_clear(MxqCore *core, MxqGame *active,
                                               uint64_t *out_record_id,
                                               MxqError *err) {
    return mxq::session::archive_and_clear(core, active, out_record_id, err);
}

MxqStatus MXQ_CALL mxq_store_history_open(MxqCore *core, uint64_t record_id,
                                          MxqGame **out_replay, MxqError *err) {
    return mxq::session::history_open(core, record_id, out_replay, err);
}

#endif /* MXQ_ENABLE_RULES_FACADE */

} /* extern "C" */
