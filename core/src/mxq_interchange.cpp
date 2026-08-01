/*
 * The store's interchange pair: one game out as a file, one game in from one.
 *
 * These are the two ends of docs/game-data.md's transfer contract, and they are
 * deliberately asymmetric.
 *
 * Export is a read and a rewrite. The record's own content — the moves, the
 * frozen configuration, the identity, the ending — is not touched, because it
 * is what makes the game that game; what is regenerated is `origin`, which
 * describes the export event and nothing else, and which the contract says is
 * "regenerated on every export, never hashed, never compared, never trusted".
 * Exporting the same record twice therefore produces two documents that differ
 * in exactly one member and agree in their content bytes and their content
 * hash, which is what makes an exported file comparable with the row it came
 * from.
 *
 * Import is the whole validation order, and its last stage is the only one that
 * touches the database. Stages one to five live in the codec — the same ladder
 * mxq_archive_validate runs, reused rather than restated — and this file adds
 * canonicalisation, hashing, and the single write transaction that compares the
 * identity and, only for a game the library does not have, inserts once. A file
 * is never partially imported: everything before the transaction is pure, and
 * the transaction is one.
 *
 * Export needs no rules facade: it decodes a row this core wrote and writes it
 * out again, and a document is not a position. Import does, because its fifth
 * stage replays the move line, so it is compiled out with the facade exactly as
 * mxq_archive_validate is — absent rather than stubbed, because the accepted
 * error taxonomy has no not-implemented code.
 */

#include "mxq_archive_read.hpp"
#include "mxq_archive_write.hpp"
#include "mxq_core_state.hpp"
#include "mxq_internal.hpp"
#include "mxq_sha256.hpp"
#include "mxq_store.hpp"

#include <cassert>
#include <cstring>
#include <string>

namespace mxq {
namespace interchange {
namespace {

/*
 * A decoded document as the writer's value shape.
 *
 * The read side and the write side name the same document differently — Stored
 * is what bytes decode to, Record is what bytes are written from — and this is
 * the one adapter between them. Both functions here go through it, so a
 * re-encoded document is re-encoded one way.
 */
archive::Record record_of(const archive::Stored &stored) {
    archive::Record record;
    record.game_id = stored.game_id;
    record.config = stored.config;
    record.moves = stored.moves;
    record.started_at_ms = stored.started_at_ms;
    record.written_at_ms = stored.written_at_ms;
    record.completed = stored.completed;
    record.outcome = stored.outcome;
    record.end_reason = stored.end_reason;
    record.ended_at_ms = stored.ended_at_ms;
    return record;
}

/* Decode a row the store holds, reporting a refusal as what it is where it
 * stands: nothing imported this row, so bytes that no longer read are the
 * user's library being damaged rather than a file they chose being bad. */
MxqStatus decode_row(const std::string &bytes, archive::Stored &out,
                     const char *what, MxqError *err) {
    MxqError decode_error;
    std::memset(&decode_error, 0, sizeof(decode_error));
    decode_error.struct_size = static_cast<uint32_t>(sizeof(decode_error));
    const MxqStatus decoded = archive::read_stored(
        reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size(), out,
        &decode_error);
    if (decoded != MXQ_OK) {
        fill_error_subsystem(err, MXQ_ERR_STORE_CORRUPT,
                             (std::string(what) + " does not decode: " +
                              decode_error.detail)
                                 .c_str(),
                             decoded);
        return MXQ_ERR_STORE_CORRUPT;
    }
    return MXQ_OK;
}

MxqBlob *blob_of(const std::string &document) {
    auto *blob = new MxqBlob();
    blob->data = new uint8_t[document.size()];
    blob->len = document.size();
    std::memcpy(blob->data, document.data(), document.size());
    return blob;
}

} /* namespace */
} /* namespace interchange */
} /* namespace mxq */

/* ------------------------------------------------------------------------- */
/* The C surface                                                             */
/* ------------------------------------------------------------------------- */

extern "C" {

MxqStatus MXQ_CALL mxq_store_export(MxqCore *core, uint64_t record_id,
                                    MxqBlob **out_blob, MxqError *err) {
    if (out_blob == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    /* Written before anything can fail, so a caller reading *out_blob after a
     * refusal reads NULL rather than whatever it held. */
    *out_blob = nullptr;

    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /* One immutable History record: the active game is not one, and asking for
     * it by its record id is MXQ_ERR_STORE_NOT_FOUND exactly as asking for an
     * identifier that was never issued is. */
    mxq::store::Summary summary;
    std::string archive_bytes;
    rc = mxq::store::history_record(*core->store, record_id, summary,
                                    &archive_bytes, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::archive::Stored stored;
    rc = mxq::interchange::decode_row(archive_bytes, stored,
                                      "the History record", err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /*
     * The content, re-encoded from what the row decoded to. It is the same
     * document the row holds — that identity is what the golden corpus pins —
     * so hashing it and comparing against the hash the row recorded is the
     * store's own integrity check, and it is also what makes "export changes
     * nothing but origin" a property of the code rather than of a test.
     */
    mxq::archive::Record record = mxq::interchange::record_of(stored);
    const std::string content = mxq::archive::content_bytes(record);
    if (mxq::sha256_hex(content) != summary.content_sha256) {
        mxq::fill_error(err, MXQ_ERR_STORE_CORRUPT,
                        "the History record's content hash does not match its "
                        "bytes");
        return MXQ_ERR_STORE_CORRUPT;
    }

    /* And the one member an export does regenerate. The instant comes from the
     * core's one clock, so a deterministic build exports deterministically. */
    record.written_at_ms = core->identity.now_ms();

    *out_blob =
        mxq::interchange::blob_of(mxq::archive::document_bytes(record, content));
    return MXQ_OK;
}

#if defined(MXQ_ENABLE_RULES_FACADE)

MxqStatus MXQ_CALL mxq_store_import(MxqCore *core, const uint8_t *bytes,
                                    size_t len, MxqImportOutcome *out_outcome,
                                    uint64_t *out_record_id,
                                    MxqRecordSummary *out_summary,
                                    MxqError *err) {
    /*
     * Every optional out is prepared before anything can fail. MXQ_IMPORT_
     * CREATED is zero and is therefore also what a refused call leaves behind;
     * the value is meaningful only on MXQ_OK, which is what mxq.h says of it.
     */
    if (out_outcome != nullptr) {
        *out_outcome = MXQ_IMPORT_CREATED;
    }
    if (out_record_id != nullptr) {
        *out_record_id = 0;
    }

    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_summary != nullptr) {
        rc = mxq::store::begin_summary(out_summary, err);
        if (rc != MXQ_OK) {
            return rc;
        }
    }
    if (bytes == nullptr) {
        assert(false && "required bytes pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "bytes was null");
        return MXQ_ERR_ARG_NULL;
    }

    /* Stages one to five, entire, and nothing persistent has been consulted:
     * transport and size, syntax under the structural limits, the envelope and
     * version dispatch, field validity and the cross-field rules, then the
     * rules tier. */
    mxq::archive::Stored stored;
    rc = mxq::archive::read_imported(bytes, len, stored, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /*
     * Canonicalisation and hashing, which is the stage between validation and
     * the write. The file may spell an equivalent document differently — one
     * line, member order and insignificant whitespace describe this writer's
     * output rather than what an incoming file must be — so what the library
     * stores is the canonical spelling of what the file said, and the content
     * hash is over exactly those bytes.
     *
     * origin travels unchanged. It describes the export event that produced the
     * file, which is a real event that really happened; it is never hashed,
     * never compared, and never what marks the record imported — the store's
     * own provenance column is that, written by the insert below.
     */
    const mxq::archive::Record record = mxq::interchange::record_of(stored);
    const std::string content = mxq::archive::content_bytes(record);
    const std::string document = mxq::archive::document_bytes(record, content);
    const std::string content_hash = mxq::sha256_hex(content);

    mxq::store::ImportedGame row;
    row.game_id = record.game_id;
    row.archive = document;
    row.content_sha256 = content_hash;
    row.rules_id = mxq::archive::rules_id_text(record.config.game);
    row.mode = mxq::archive::mode_text(record.config.mode);
    row.human_side = mxq::archive::color_text(record.config.human_side);
    row.ai_level = mxq::archive::ai_level_text(record.config.ai_level);
    row.first_mover_choice =
        mxq::archive::first_mover_text(record.config.first_mover_choice);
    row.ai_movetime_ms = static_cast<int64_t>(record.config.ai_movetime_ms);
    row.move_count = static_cast<int64_t>(record.moves.size());
    row.started_at_ms = record.started_at_ms;
    row.outcome = mxq::archive::outcome_text(record.outcome);
    row.end_reason = mxq::archive::end_reason_text(record.end_reason);
    row.ended_at_ms = record.ended_at_ms;
    /* The History-added time is the import, not the game: the list orders by
     * when a record entered this library. */
    row.added_at_ms = core->identity.now_ms();

    /*
     * The duplicate test, as docs/game-data.md states it: same game_id — which
     * is how the row was found at all — same archive version, same content hash
     * and bytes. The row is checked against its own recorded hash first, so
     * that a damaged row is reported as damage rather than compared and called
     * a conflict; after that, equal bytes and equal hashes are one question.
     *
     * The archive-version comparison cannot fail today, because version 1 is
     * the only version this build reads and a file of any other was refused at
     * stage three. It is written because the contract's answer for a differing
     * stored version is to reject conservatively, and that answer should exist
     * before there is a version 2 to need it.
     */
    const mxq::store::SameGame same_game =
        [&content, &content_hash, &stored](const std::string &existing_archive,
                                           const std::string &existing_hash,
                                           bool &out_same,
                                           MxqError *judge_err) -> MxqStatus {
        out_same = false;
        mxq::archive::Stored existing;
        const MxqStatus decoded = mxq::interchange::decode_row(
            existing_archive, existing, "the record already under this "
                                        "identity",
            judge_err);
        if (decoded != MXQ_OK) {
            return decoded;
        }
        const mxq::archive::Record existing_record =
            mxq::interchange::record_of(existing);
        const std::string existing_content =
            mxq::archive::content_bytes(existing_record);
        if (mxq::sha256_hex(existing_content) != existing_hash) {
            mxq::fill_error(judge_err, MXQ_ERR_STORE_CORRUPT,
                            "the record already under this identity has a "
                            "content hash that does not match its bytes");
            return MXQ_ERR_STORE_CORRUPT;
        }
        out_same = existing.archive_version == stored.archive_version &&
                   existing_content == content && existing_hash == content_hash;
        return MXQ_OK;
    };

    bool existing = false;
    uint64_t record_id = 0;
    mxq::store::Summary written;
    rc = mxq::store::import_game(*core->store, row, same_game, existing,
                                 record_id, written, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    if (out_outcome != nullptr) {
        *out_outcome = existing ? MXQ_IMPORT_EXISTING : MXQ_IMPORT_CREATED;
    }
    if (out_record_id != nullptr) {
        *out_record_id = record_id;
    }
    if (out_summary != nullptr) {
        return mxq::store::fill_summary(written, false, out_summary, err);
    }
    return MXQ_OK;
}

#endif /* MXQ_ENABLE_RULES_FACADE */

} /* extern "C" */
