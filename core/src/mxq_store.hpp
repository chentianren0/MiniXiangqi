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
 */

#ifndef MXQ_STORE_HPP
#define MXQ_STORE_HPP

#include "mxq.h"

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
