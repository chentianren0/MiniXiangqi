/* The library store behind mxq_store_ and the attached-session commits.
 *
 * One embedded SQLite database, opened at mxq_core_init and closed at
 * mxq_core_shutdown, holding the schema docs/game-data.md accepts as version 6.
 * This header is internal: nothing SQLite-shaped is visible through mxq.h, per
 * docs/architecture.md, and core/CMakeLists.txt links the vendored library
 * PRIVATE for the same reason.
 *
 * The store is one process, one connection, one serialized writer. The
 * connection lives here together with the one mutex that will serialize every
 * store operation (core-interface.md's threading contract); in this PR the
 * only operations are open and close, but the lock discipline is established
 * with the handle so later operations inherit it rather than invent it.
 *
 * Write paths must never use OR REPLACE or the REPLACE conflict resolution on
 * game or library: SQLite's implicit delete fires no trigger with recursion
 * off, so the defensive triggers above the schema would be silently bypassed.
 * Conflicts are handled by the explicit statements a transaction states.
 *
 * The library revision — core-interface.md's monotonic counter, the accepted
 * answer to library-change observation — lives in the meta table and is bumped
 * inside the same transaction as the mutation it reports, so a caller can
 * never read a revision that a committed change has not yet reached. It is
 * bookkeeping rather than game data: losing it would lose no game, which is
 * why meta is where it belongs.
 */

#ifndef MXQ_STORE_HPP
#define MXQ_STORE_HPP

#include "mxq.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

struct sqlite3;

namespace mxq {
namespace store {

/* The store's one database file, under the frontend-supplied store directory.
 * The name is part of the accepted contract: docs/game-data.md, "Library store
 * schema, version 6". Write-ahead logging keeps its journal beside it as
 * library.sqlite3-wal and library.sqlite3-shm. */
constexpr const char *kDatabaseFileName = "library.sqlite3";

class Store {
public:
    ~Store();

    Store(const Store &) = delete;
    Store &operator=(const Store &) = delete;

    /* The serialized-writer lock. Every store operation in later PRs takes it
     * for its whole transaction. */
    std::mutex &mutex() { return mutex_; }

    sqlite3 *db() { return db_; }

private:
    friend MxqStatus open(const std::string &directory,
                          std::unique_ptr<Store> &out, MxqError *err);
    Store() = default;

    std::mutex mutex_;
    sqlite3   *db_ = nullptr;
};

/*
 * The active game's row, as the store writes it.
 *
 * The canonical archive bytes are the record; every other member is a derived
 * summary column that exists only to answer the History list without decoding
 * a blob, and must be exactly recomputable from it (docs/game-data.md). They
 * are written from the same values the document was written from, in one
 * place, so the two cannot drift.
 *
 * The vocabulary members are the serialised spellings, or null where the
 * archive omits the member and the column holds SQL NULL: the four
 * configuration members exist exactly for human-versus-AI games. The pointers
 * are borrowed for the duration of the call.
 */
struct ActiveGame {
    std::string game_id;
    std::string archive;        /* the canonical bytes, verbatim */
    std::string content_sha256; /* 64 lowercase hexadecimal characters */
    const char *rules_id = nullptr; /* which game; never null */
    const char *mode = nullptr;
    const char *human_side = nullptr;
    const char *ai_level = nullptr;
    const char *first_mover_choice = nullptr;
    /* The side this device's player took: library metadata rather than a
     * derived column, present exactly for a nearby game and null otherwise. */
    const char *local_side = nullptr;
    int64_t     ai_movetime_ms = 0; /* 0 means the archive omits it */
    int64_t     move_count = 0;
    int64_t     started_at_ms = 0;
};

/*
 * The wire session an unfinished nearby game is played over, as the store holds
 * it: the serialised spellings of the two closed vocabularies, and the two
 * identifiers verbatim. An empty sent_end spells SQL NULL, for the reason
 * Summary's empty strings do — the vocabulary contains no empty value.
 *
 * It travels beside an ActiveGame or a rewritten line rather than on its own,
 * because the two move together and a store that held them a transaction apart
 * would reconcile a later resume to a line neither player played.
 */
struct NearbySession {
    std::string session_id;
    std::string peer_id;
    std::string proposer; /* "local" or "peer" */
    std::string sent_end; /* "resign", "accept_draw", or empty for NULL */
    int64_t     undos = 0;
    int64_t     keep = 0;
    bool        claimed = false;
    /* The four values a dealt game's handshake left behind, each sixty-four
     * lowercase hexadecimal digits and present exactly for a session of the one
     * game whose start is dealt. Empty spells SQL NULL, as sent_end's does. */
    std::string deal_commit;
    std::string deal_nonce;
    std::string deal_seed;
    std::string deal_digest;
};

/*
 * Insert the new active game and point the library at it, in one transaction.
 * Returns MXQ_ERR_STATE_ACTIVE_GAME_EXISTS, changing nothing, when the library
 * already holds one: the single-active-game invariant is structural in the
 * schema and checked inside the transaction that would break it.
 *
 * A nearby game arrives with the wire session it is being played over, and the
 * one transaction writes both rows: an active nearby game whose session the
 * store does not hold cannot be resumed, so the two are one event. Null
 * everywhere else.
 *
 * The insert names its columns explicitly and never uses OR REPLACE, per the
 * prohibition at the top of this header.
 */
MxqStatus create_active(Store &store, const ActiveGame &row,
                        const NearbySession *nearby, uint64_t &out_record_id,
                        MxqError *err);

/*
 * Read the active game's row: its record id, its canonical bytes, and the
 * content hash the row records for them, which the caller compares against the
 * bytes it decodes. Absence is success with out_exists false: there being no
 * active game is an ordinary state, not a failure.
 *
 * A library reference naming a row that is not there is not absence. Foreign
 * keys are on, so this cannot arise from anything the core does; it can arise
 * from a tampered or truncated file, and answering "no active game" there would
 * silently discard a game the library still claims to hold. It is
 * MXQ_ERR_STORE_CORRUPT.
 */
MxqStatus load_active(Store &store, bool &out_exists, uint64_t &out_record_id,
                      std::string &out_archive, std::string &out_content_sha256,
                      std::string &out_local_side, MxqError *err);

/*
 * The wire session a row is being played over, where it has one. Absence is
 * success with out_exists false: a local game has none, and so does a nearby
 * game whose session the protocol has parted with.
 */
MxqStatus load_nearby_session(Store &store, uint64_t record_id, bool &out_exists,
                              NearbySession &out, MxqError *err);

/*
 * Write the wire session over the row it belongs to, in one transaction, and
 * commit before returning. The row must still be the library's active game —
 * anything else is MXQ_ERR_STORE_NOT_FOUND — which is what keeps this from
 * attaching a session to a History record whatever record id it is handed.
 *
 * Written as an insert with an explicit conflict clause rather than OR REPLACE,
 * per the prohibition at the top of this header: OR REPLACE would delete the
 * existing row without firing a trigger.
 */
MxqStatus set_nearby_session(Store &store, uint64_t record_id,
                             const NearbySession &nearby, MxqError *err);

/*
 * Rewrite the one active row — the new canonical bytes, their hash, and the
 * move count derived from them — in one transaction, and commit before
 * returning. This is what an accepted move or undo is: there is no per-move
 * table and no deferred write, so every mutation is this one statement inside
 * its own transaction, and a failure leaves the previously committed row
 * exactly as it was.
 */
MxqStatus rewrite_active(Store &store, uint64_t record_id,
                         const std::string &archive,
                         const std::string &content_sha256, int64_t move_count,
                         const NearbySession *nearby, MxqError *err);

/*
 * What ending a game writes over its active row.
 *
 * The five archiving paths — the four terminal commits and archive-and-clear —
 * differ only in how they classify the ending; what they write is this, and
 * they write it through one function so that "one atomic transaction: the
 * outcome, the immutable History record, and the cleared active-game
 * reference" is one place rather than five.
 *
 * The archive is the finished shape: the same document the active row held,
 * rewritten with the terminal trio the classification decided. The vocabulary
 * members are the serialised spellings and are never null here — a committed
 * row always has both.
 */
struct Completion {
    std::string archive;
    std::string content_sha256;
    int64_t     move_count = 0;
    const char *outcome = nullptr;
    const char *end_reason = nullptr;
    int64_t     ended_at_ms = 0;
    int64_t     added_at_ms = 0; /* the History-added time that orders the list */
};

/*
 * Commit the ending, in one transaction: clear the library's active-game
 * reference, then write the outcome over the row it named, which is the order
 * the commit_clears_active_reference_first trigger requires — the reference is
 * gone before any statement can observe a committed game still referenced as
 * active.
 *
 * The update names outcome IS NULL in its condition, so this statement cannot
 * rewrite a History record whatever record id it is handed, and it never uses
 * OR REPLACE. A row that is no longer the library's active game is
 * MXQ_ERR_STORE_NOT_FOUND and nothing is written; the transaction rolls back
 * whole, so a failure anywhere leaves the game active, unchanged, and
 * retryable.
 *
 * The same transaction deletes the game's wire session, if it had one, and the
 * deletion is explicit rather than a cascade: this statement *updates* the game
 * row in place, so no foreign key ever fires here. A filed nearby game must
 * leave no session row behind — the row holds a peer's device identity, which
 * is device-local data that has no purpose past the game it belonged to.
 */
MxqStatus commit_completion(Store &store, uint64_t record_id,
                            const Completion &done, MxqError *err);

/*
 * One row's summary columns, in the serialised vocabulary the store holds them
 * in. The empty string spells SQL NULL — the four configuration members in
 * Free Play, and the terminal pair of the active game — because the closed
 * vocabularies contain no empty value and a separate presence flag per column
 * would be four more things to keep in step.
 *
 * Mapping these to the enums MxqRecordSummary carries is the C surface's job:
 * the store speaks the database's vocabulary, exactly as the schema's CHECK
 * constraints do.
 */
struct Summary {
    uint64_t    record_id = 0;
    std::string game_id;
    std::string content_sha256;
    std::string rules_id;
    std::string mode;
    std::string human_side;
    std::string ai_level;
    int64_t     ai_movetime_ms = 0;
    int64_t     move_count = 0;
    std::string outcome;
    std::string end_reason;
    std::string provenance;
    std::string local_side;
    bool        pinned = false;
    int64_t     started_at_ms = 0;
    int64_t     ended_at_ms = 0;
    int64_t     added_at_ms = 0;
};

/*
 * An imported game's row, whole.
 *
 * It is not an ActiveGame plus a Completion: an active game has no ending to
 * write and a History record is never the library's active game, so an import
 * writes one row that is complete from the moment it exists. The vocabulary
 * members are the serialised spellings, null exactly where the archive omits
 * the member, and the terminal pair is never null — an imported record is
 * always a completed game.
 *
 * added_at_ms is the History-added time, which for an import is the import
 * instant: docs/game-data.md orders each group by "the most recently completed
 * or imported first", so the file's own dates order nothing.
 */
struct ImportedGame {
    std::string game_id;
    std::string archive;        /* the canonical bytes, verbatim */
    std::string content_sha256; /* 64 lowercase hexadecimal characters */
    const char *rules_id = nullptr; /* which game; never null */
    const char *mode = nullptr;
    const char *human_side = nullptr;
    const char *ai_level = nullptr;
    const char *first_mover_choice = nullptr;
    int64_t     ai_movetime_ms = 0; /* 0 means the archive omits it */
    int64_t     move_count = 0;
    int64_t     started_at_ms = 0;
    const char *outcome = nullptr;
    const char *end_reason = nullptr;
    int64_t     ended_at_ms = 0;
    int64_t     added_at_ms = 0;
};

/*
 * The import's one write transaction — the last stage of docs/game-data.md's
 * validation order, and the only stage that touches the database at all.
 *
 * Inside one transaction: look for a row already holding this stable identity,
 * and then either
 *
 *   - there is none, and one insert creates the immutable History record. The
 *     library's active-game reference is not named by any statement here, which
 *     is how "an import never creates or replaces the active game" is
 *     structural rather than checked;
 *   - there is one and it is the same game, which is success: out_existing is
 *     true, the existing record is returned, and nothing is written — not even
 *     the library revision, because nothing changed;
 *   - there is one and it is a different game, which is
 *     MXQ_ERR_STORE_IDENTITY_CONFLICT with no persistent change.
 *
 * same_game is asked that question inside the transaction, because the codec
 * lives above the store: it is handed the bytes and the hash the row holds and
 * answers whether they are this file's game. A status other than MXQ_OK from it
 * aborts the import with that status — a row that no longer decodes is store
 * corruption rather than a conflict.
 */
using SameGame = std::function<MxqStatus(const std::string &archive,
                                         const std::string &content_sha256,
                                         bool &out_same, MxqError *err)>;

MxqStatus import_game(Store &store, const ImportedGame &row,
                      const SameGame &same_game, bool &out_existing,
                      uint64_t &out_record_id, Summary &out_summary,
                      MxqError *err);

/*
 * A row's summary columns as the MxqRecordSummary the C surface hands out, and
 * the out-struct preparation that precedes it.
 *
 * The store speaks the database's vocabulary — the serialised spellings the
 * schema's CHECK constraints are written in — and turning that into the enums
 * mxq.h carries is the C surface's job. It is declared here because the store
 * has two C surfaces now: the active game and History as something to read, and
 * the interchange pair. One translation, so a record cannot mean one thing when
 * a page reports it and another when an import returns it.
 *
 * A value outside a closed vocabulary is MXQ_ERR_STORE_CORRUPT rather than a
 * summary with a guessed field in it; nothing is recomputed from the blob,
 * because the columns were written from the same values the document was.
 */
MxqStatus fill_summary(const Summary &row, bool is_active, MxqRecordSummary *out,
                       MxqError *err);
MxqStatus begin_summary(MxqRecordSummary *out, MxqError *err);

/* Whether the library holds an active game. A dangling reference is corruption
 * here for the same reason it is in load_active. */
MxqStatus active_exists(Store &store, bool &out_exists, MxqError *err);

/* The active game's summary columns and its canonical bytes. Absence is
 * success with out_exists false. out_archive may be null when the caller wants
 * the columns alone. */
MxqStatus active_summary(Store &store, bool &out_exists, Summary &out,
                         std::string *out_archive, MxqError *err);

/*
 * The number of History records, and the library revision: the monotonic
 * counter every committed store mutation bumps. The pair is read under one
 * hold of the store's lock, so a caller comparing revisions is comparing
 * against the count it was told.
 */
MxqStatus history_count(Store &store, uint32_t &out_count,
                        uint64_t &out_revision, MxqError *err);

/*
 * One page of History in the accepted order — pinned first, newest
 * History-added time within each group, record_id descending as the tie-break
 * — which is the order the partial index is built in, so the ordering is the
 * index rather than a second spelling of it. At most limit rows are written;
 * an offset past the end writes none, which is not an error.
 */
MxqStatus history_page(Store &store, uint32_t offset, uint32_t limit,
                       std::vector<Summary> &out, uint64_t &out_revision,
                       MxqError *err);

/*
 * One History record's summary, and optionally its canonical bytes. The active
 * game is not a History record: asking for it by its record id is
 * MXQ_ERR_STORE_NOT_FOUND, exactly as asking for an id that was never issued
 * is.
 */
MxqStatus history_record(Store &store, uint64_t record_id, Summary &out,
                         std::string *out_archive, MxqError *err);

/* Set or clear a History record's pin state, the one mutable field. */
MxqStatus history_set_pinned(Store &store, uint64_t record_id, bool pinned,
                             MxqError *err);

/* Delete a History record whole and permanently. record_id is AUTOINCREMENT,
 * so the identifier is never issued again. */
MxqStatus history_delete(Store &store, uint64_t record_id, MxqError *err);

/*
 * Open — creating if absent — the store under directory, whose leading
 * directories are created as needed:
 *
 *   - the required pragmas are applied and then read back and verified:
 *     journal_mode=WAL, synchronous=FULL, foreign_keys=ON;
 *   - a fresh database receives the complete schema version 6 in one
 *     transaction, and its user_version pragma is set to 6;
 *   - an existing database is verified: the four tables must exist and be
 *     STRICT, and the single library row must be present;
 *   - a database recording any other schema version is refused, and never
 *     migrated: version 6 is the only schema this build defines. A newer one
 *     is MXQ_ERR_STORE_SCHEMA_TOO_NEW, which the contract requires to be said
 *     distinctly; anything else is MXQ_ERR_STORE_MIGRATION_FAILED.
 *
 * On failure returns the store-domain status, fills err (with the raw SQLite
 * result as subsystem_code where there is one), and leaves out empty; there is
 * no partially open store.
 */
MxqStatus open(const std::string &directory, std::unique_ptr<Store> &out,
               MxqError *err);

} /* namespace store */
} /* namespace mxq */

#endif /* MXQ_STORE_HPP */
