/* The library store behind mxq_store_ and the attached-session commits.
 *
 * One embedded SQLite database, opened at mxq_core_init and closed at
 * mxq_core_shutdown, holding the schema docs/game-data.md accepts as version 1.
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
#include <memory>
#include <mutex>
#include <string>
#include <vector>

struct sqlite3;

namespace mxq {
namespace store {

/* The store's one database file, under the frontend-supplied store directory.
 * The name is part of the accepted contract: docs/game-data.md, "Library store
 * schema". Write-ahead logging keeps its journal beside it as
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
    const char *mode = nullptr;
    const char *human_side = nullptr;
    const char *ai_level = nullptr;
    const char *first_mover_choice = nullptr;
    int64_t     ai_movetime_ms = 0; /* 0 means the archive omits it */
    int64_t     move_count = 0;
    int64_t     started_at_ms = 0;
};

/*
 * Insert the new active game and point the library at it, in one transaction.
 * Returns MXQ_ERR_STATE_ACTIVE_GAME_EXISTS, changing nothing, when the library
 * already holds one: the single-active-game invariant is structural in the
 * schema and checked inside the transaction that would break it.
 *
 * The insert names its columns explicitly and never uses OR REPLACE, per the
 * prohibition at the top of this header.
 */
MxqStatus create_active(Store &store, const ActiveGame &row,
                        uint64_t &out_record_id, MxqError *err);

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
                      MxqError *err);

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
                         MxqError *err);

/*
 * What ending a game writes over its active row.
 *
 * The four archiving paths — the three terminal commits and archive-and-clear —
 * differ only in how they classify the ending; what they write is this, and
 * they write it through one function so that "one atomic transaction: the
 * outcome, the immutable History record, and the cleared active-game
 * reference" is one place rather than four.
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
    std::string mode;
    std::string human_side;
    std::string ai_level;
    int64_t     ai_movetime_ms = 0;
    int64_t     move_count = 0;
    std::string outcome;
    std::string end_reason;
    std::string provenance;
    bool        pinned = false;
    int64_t     started_at_ms = 0;
    int64_t     ended_at_ms = 0;
    int64_t     added_at_ms = 0;
};

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

/* The library revision alone, for the callers that report it beside something
 * other than a count. */
MxqStatus library_revision(Store &store, uint64_t &out_revision, MxqError *err);

/*
 * Open — creating if absent — the store under directory, whose leading
 * directories are created as needed:
 *
 *   - the required pragmas are applied and then read back and verified:
 *     journal_mode=WAL, synchronous=FULL, foreign_keys=ON;
 *   - a fresh database receives the complete schema version 1 in one
 *     transaction, and its user_version pragma is set to 1;
 *   - an existing database is verified: the three tables must exist and be
 *     STRICT, and the single library row must be present;
 *   - a database whose recorded schema version is newer than this build is
 *     refused with MXQ_ERR_STORE_SCHEMA_TOO_NEW; an older recorded version
 *     dispatches forward-only migrations (none exist yet: version 1 is the
 *     first schema ever shipped).
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
