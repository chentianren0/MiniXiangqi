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
 */

#ifndef MXQ_STORE_HPP
#define MXQ_STORE_HPP

#include "mxq.h"

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>

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
 * Read the active game's row. Absence is success with out_exists false: there
 * being no active game is an ordinary state, not a failure.
 */
MxqStatus load_active(Store &store, bool &out_exists, uint64_t &out_record_id,
                      std::string &out_archive, MxqError *err);

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
