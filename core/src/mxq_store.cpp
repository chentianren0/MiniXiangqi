/* Opening, creating, migrating and closing the library store.
 *
 * The schema created here is the one docs/game-data.md accepts as version 1,
 * transcribed constraint for constraint; the connection regime — write-ahead
 * logging, full synchronous durability, foreign keys on — is the same
 * contract's, applied and then read back rather than assumed. Everything that
 * SQL can express about the accepted invariants is expressed in the DDL; what
 * it cannot (legality of the move line, derived-column agreement) is core
 * logic gated by tests, per the contract.
 */

#include "mxq_store.hpp"

#include "mxq_internal.hpp"

#include "sqlite3.h"

#include <cstdint>
#include <filesystem>
#include <string>

namespace mxq {
namespace store {

namespace {

/*
 * Schema version 1, exactly as accepted in docs/game-data.md ("Library store
 * schema"). Three STRICT tables; the single library row with the single
 * nullable active-game reference; result well-formedness, the
 * mode-to-configuration relationship and time ordering as check constraints;
 * History content immutability and the archive-and-clear ordering as
 * triggers; the accepted History ordering served by one partial index that
 * excludes the active game structurally.
 *
 * Text columns carry the serialized identifier vocabulary of game-data.md
 * verbatim, so the database is self-describing and the closed sets are
 * legible as constraints.
 */
const char *const kSchemaV1 = R"SQL(
CREATE TABLE meta (
  key   TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;

CREATE TABLE game (
  -- AUTOINCREMENT so a record_id is never reused: History ordering breaks its
  -- ties on this column, and a stale id held across a deletion must dangle
  -- rather than resolve to some later game.
  record_id          INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id            TEXT    NOT NULL UNIQUE CHECK (length(game_id) = 36),
  archive            BLOB    NOT NULL,
  content_sha256     TEXT    NOT NULL CHECK (length(content_sha256) = 64),
  mode               TEXT    NOT NULL CHECK (mode IN ('human-vs-ai', 'free-play')),
  human_side         TEXT    CHECK (human_side IN ('red', 'black')),
  ai_level           TEXT    CHECK (ai_level IN ('fast', 'standard', 'deep')),
  ai_movetime_ms     INTEGER CHECK (ai_movetime_ms > 0),
  first_mover_choice TEXT    CHECK (first_mover_choice IN ('human-first', 'ai-first', 'random')),
  move_count         INTEGER NOT NULL CHECK (move_count >= 0),
  outcome            TEXT    CHECK (outcome IN ('red-wins', 'black-wins', 'draw', 'none')),
  end_reason         TEXT    CHECK (end_reason IN ('checkmate', 'stalemate',
                                                   'threefold-repetition',
                                                   'perpetual-check', 'perpetual-chase',
                                                   'mutual-perpetual-check',
                                                   'mutual-perpetual-chase',
                                                   'resignation', 'ended-early')),
  provenance         TEXT    NOT NULL CHECK (provenance IN ('locally-played', 'imported')),
  pinned             INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
  started_at_ms      INTEGER NOT NULL CHECK (started_at_ms >= 0),
  ended_at_ms        INTEGER,
  added_at_ms        INTEGER,
  -- A row is the active game exactly when its committed outcome is null; the
  -- terminal columns commit together, and the History-added time exists
  -- exactly for History records.
  CHECK ((outcome IS NULL) = (end_reason IS NULL)),
  CHECK ((outcome IS NULL) = (ended_at_ms IS NULL)),
  CHECK ((outcome IS NULL) = (added_at_ms IS NULL)),
  -- Pinning is History library metadata; the active game is never pinned.
  CHECK (outcome IS NOT NULL OR pinned = 0),
  -- Time ordering.
  CHECK (ended_at_ms IS NULL OR ended_at_ms >= started_at_ms),
  CHECK (added_at_ms IS NULL OR added_at_ms >= 0),
  -- Result well-formedness: the cross-field vocabulary rules of game-data.md.
  CHECK (outcome IS NULL OR ((outcome = 'none') = (end_reason = 'ended-early'))),
  CHECK (outcome IS NULL OR ((outcome = 'draw') =
         (end_reason IN ('threefold-repetition',
                         'mutual-perpetual-check', 'mutual-perpetual-chase')))),
  CHECK (end_reason IS NULL OR end_reason <> 'resignation' OR
         (mode = 'human-vs-ai' AND
          ((human_side = 'red' AND outcome = 'black-wins') OR
           (human_side = 'black' AND outcome = 'red-wins')))),
  -- The mode-to-configuration relationship: the four configuration fields
  -- exist exactly for human-versus-AI games, matching the archive, which
  -- simply omits them in Free Play.
  CHECK ((mode = 'human-vs-ai') = (human_side IS NOT NULL)),
  CHECK ((mode = 'human-vs-ai') = (ai_level IS NOT NULL)),
  CHECK ((mode = 'human-vs-ai') = (ai_movetime_ms IS NOT NULL)),
  CHECK ((mode = 'human-vs-ai') = (first_mover_choice IS NOT NULL)),
  -- A record can only enter this library as imported once it is complete.
  CHECK (provenance <> 'imported' OR outcome IS NOT NULL)
) STRICT;

CREATE TABLE library (
  id               INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  active_record_id INTEGER REFERENCES game (record_id)
) STRICT;

-- The accepted History ordering — pinned first, then newest History-added
-- time within each group, tie-break record_id descending — served by one
-- partial index that excludes the active game structurally.
CREATE INDEX history_order
  ON game (pinned DESC, added_at_ms DESC, record_id DESC)
  WHERE outcome IS NOT NULL;

-- The library row is permanent: created with the schema, never deleted.
CREATE TRIGGER library_row_is_permanent
BEFORE DELETE ON library
BEGIN
  SELECT RAISE(ABORT, 'the library row is permanent');
END;

-- History content immutability: once an outcome is committed, everything
-- except pin state is immutable.
CREATE TRIGGER history_content_is_immutable
BEFORE UPDATE ON game
WHEN OLD.outcome IS NOT NULL
 AND (NEW.record_id          IS NOT OLD.record_id
   OR NEW.game_id            IS NOT OLD.game_id
   OR NEW.archive            IS NOT OLD.archive
   OR NEW.content_sha256     IS NOT OLD.content_sha256
   OR NEW.mode               IS NOT OLD.mode
   OR NEW.human_side         IS NOT OLD.human_side
   OR NEW.ai_level           IS NOT OLD.ai_level
   OR NEW.ai_movetime_ms     IS NOT OLD.ai_movetime_ms
   OR NEW.first_mover_choice IS NOT OLD.first_mover_choice
   OR NEW.move_count         IS NOT OLD.move_count
   OR NEW.outcome            IS NOT OLD.outcome
   OR NEW.end_reason         IS NOT OLD.end_reason
   OR NEW.provenance         IS NOT OLD.provenance
   OR NEW.started_at_ms      IS NOT OLD.started_at_ms
   OR NEW.ended_at_ms        IS NOT OLD.ended_at_ms
   OR NEW.added_at_ms        IS NOT OLD.added_at_ms)
BEGIN
  SELECT RAISE(ABORT, 'history content is immutable');
END;

-- The archive-and-clear ordering: within the one committing transaction the
-- library's active-game reference is cleared before the outcome is committed,
-- so no statement ever observes a committed game still referenced as active.
CREATE TRIGGER commit_clears_active_reference_first
BEFORE UPDATE OF outcome ON game
WHEN OLD.outcome IS NULL AND NEW.outcome IS NOT NULL
 AND (SELECT active_record_id FROM library WHERE id = 1) IS OLD.record_id
BEGIN
  SELECT RAISE(ABORT,
               'clear the active-game reference before committing an outcome');
END;

-- And the reference may only ever be set to an uncommitted game.
CREATE TRIGGER active_reference_is_an_uncommitted_game
BEFORE UPDATE OF active_record_id ON library
WHEN NEW.active_record_id IS NOT NULL
 AND (SELECT outcome FROM game
       WHERE record_id = NEW.active_record_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT,
               'the active-game reference must name an uncommitted game');
END;

-- The one library row, with no active game.
INSERT INTO library (id, active_record_id) VALUES (1, NULL);

-- Non-authoritative bookkeeping; migration never reads this table.
INSERT INTO meta (key, value) VALUES ('created_schema_version', '1');

-- The library revision: the monotonic counter every committed store mutation
-- bumps, which is the accepted answer to library-change observation. A fresh
-- library has seen no mutation.
INSERT INTO meta (key, value) VALUES ('library_revision', '0');
)SQL";

/* Map a SQLite result to the taxonomy. The raw (extended) result rides along
 * in MxqError.subsystem_code for diagnostics; it is never branched on. */
MxqStatus map_sqlite(int rc) {
    switch (rc & 0xff) {
    case SQLITE_BUSY:
    case SQLITE_LOCKED:
        return MXQ_ERR_STORE_BUSY;
    case SQLITE_FULL:
        return MXQ_ERR_STORE_FULL;
    case SQLITE_CORRUPT:
    case SQLITE_NOTADB:
    case SQLITE_FORMAT:
        return MXQ_ERR_STORE_CORRUPT;
    case SQLITE_NOMEM:
        return MXQ_ERR_RESOURCE_ALLOCATION_FAILED;
    default:
        return MXQ_ERR_STORE_IO;
    }
}

MxqStatus fail(MxqError *err, MxqStatus status, int sqlite_rc,
               const std::string &detail) {
    fill_error_subsystem(err, status, detail.c_str(), sqlite_rc);
    return status;
}

MxqStatus fail_sqlite(MxqError *err, int sqlite_rc, const std::string &detail) {
    return fail(err, map_sqlite(sqlite_rc), sqlite_rc, detail);
}

/* Run statements that return no result rows. */
bool exec(sqlite3 *db, const char *sql, int &rc, std::string &detail) {
    char *msg = nullptr;
    rc = sqlite3_exec(db, sql, nullptr, nullptr, &msg);
    if (rc != SQLITE_OK) {
        detail = msg != nullptr ? msg : sqlite3_errmsg(db);
        sqlite3_free(msg);
        return false;
    }
    sqlite3_free(msg);
    return true;
}

/* Run a query expected to yield at least one row and read its first column.
 * TEXT and INTEGER results both come back as text via sqlite3_column_text,
 * which is what pragma verification compares. */
bool query_first_column(sqlite3 *db, const char *sql, std::string &value,
                        int &rc, std::string &detail) {
    sqlite3_stmt *stmt = nullptr;
    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        detail = sqlite3_errmsg(db);
        return false;
    }
    rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        detail = rc == SQLITE_DONE ? std::string("query returned no rows")
                                   : std::string(sqlite3_errmsg(db));
        if (rc == SQLITE_DONE) {
            rc = SQLITE_INTERNAL;
        }
        sqlite3_finalize(stmt);
        return false;
    }
    const unsigned char *text = sqlite3_column_text(stmt, 0);
    value = text != nullptr ? reinterpret_cast<const char *>(text) : "";
    rc = sqlite3_finalize(stmt);
    if (rc != SQLITE_OK) {
        detail = sqlite3_errmsg(db);
        return false;
    }
    return true;
}

/* Apply one pragma and verify the value it reads back, because the contract's
 * regime is a property of the open connection, not a request. */
MxqStatus apply_pragma(sqlite3 *db, const char *set_sql, const char *get_sql,
                       const char *expected, const char *name, MxqError *err) {
    int rc = SQLITE_OK;
    std::string detail;
    if (!exec(db, set_sql, rc, detail)) {
        return fail_sqlite(err, rc,
                           std::string("cannot apply ") + name + ": " + detail);
    }
    std::string value;
    if (!query_first_column(db, get_sql, value, rc, detail)) {
        return fail_sqlite(err, rc,
                           std::string("cannot read back ") + name + ": " + detail);
    }
    if (value != expected) {
        return fail(err, MXQ_ERR_STORE_IO, 0,
                    std::string(name) + " did not take effect: expected " +
                        expected + ", read " + value);
    }
    return MXQ_OK;
}

/* The structural verification run on every successful open: the three tables
 * of schema version 1 exist and are STRICT, and the single library row is
 * present. Deeper agreement — constraints, triggers, index — is the schema's
 * own text, which this build only ever creates whole. */
MxqStatus verify_schema(sqlite3 *db, MxqError *err) {
    int rc = SQLITE_OK;
    std::string detail;
    std::string value;

    if (!query_first_column(db,
                            "SELECT count(*) FROM sqlite_schema "
                            "WHERE type = 'table' "
                            "AND name IN ('meta', 'game', 'library') "
                            "AND sql LIKE '%STRICT%';",
                            value, rc, detail)) {
        return fail_sqlite(err, rc, "cannot inspect the schema: " + detail);
    }
    if (value != "3") {
        return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                    "the store does not hold the three STRICT tables of schema "
                    "version 1 (found " + value + ")");
    }

    if (!query_first_column(db, "SELECT count(*) FROM library;", value, rc,
                            detail)) {
        return fail_sqlite(err, rc, "cannot read the library row: " + detail);
    }
    if (value != "1") {
        return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                    "the library must hold exactly one row (found " + value +
                        ")");
    }
    return MXQ_OK;
}

MxqStatus create_schema_v1(sqlite3 *db, MxqError *err) {
    int rc = SQLITE_OK;
    std::string detail;
    if (!exec(db, "BEGIN IMMEDIATE;", rc, detail)) {
        return fail_sqlite(err, rc, "cannot begin the schema transaction: " + detail);
    }
    if (!exec(db, kSchemaV1, rc, detail) ||
        !exec(db, "PRAGMA user_version = 1;", rc, detail)) {
        const std::string cause = detail;
        std::string ignored;
        int rollback_rc = SQLITE_OK;
        exec(db, "ROLLBACK;", rollback_rc, ignored);
        return fail_sqlite(err, rc, "cannot create schema version 1: " + cause);
    }
    if (!exec(db, "COMMIT;", rc, detail)) {
        return fail_sqlite(err, rc, "cannot commit schema version 1: " + detail);
    }
    return MXQ_OK;
}

/* ---------------------------------------------------------------------- */
/* Statements                                                              */
/* ---------------------------------------------------------------------- */

/* A prepared statement that finalises itself. No statement outlives its
 * operation in this design — the store's close relies on it — so ownership is
 * scoped rather than cached. */
class Stmt {
public:
    Stmt(sqlite3 *db, const char *sql) {
        rc_ = sqlite3_prepare_v2(db, sql, -1, &stmt_, nullptr);
    }
    ~Stmt() { sqlite3_finalize(stmt_); }

    Stmt(const Stmt &) = delete;
    Stmt &operator=(const Stmt &) = delete;

    bool ok() const { return rc_ == SQLITE_OK && stmt_ != nullptr; }
    int rc() const { return rc_; }
    sqlite3_stmt *get() { return stmt_; }

    /* One-based, as SQLite counts parameters. */
    void bind_text(int at, const char *value) {
        if (value == nullptr) {
            sqlite3_bind_null(stmt_, at);
        } else {
            sqlite3_bind_text(stmt_, at, value, -1, SQLITE_TRANSIENT);
        }
    }
    void bind_text(int at, const std::string &value) {
        sqlite3_bind_text(stmt_, at, value.data(),
                          static_cast<int>(value.size()), SQLITE_TRANSIENT);
    }
    void bind_blob(int at, const std::string &value) {
        sqlite3_bind_blob(stmt_, at, value.data(),
                          static_cast<int>(value.size()), SQLITE_TRANSIENT);
    }
    void bind_int64(int at, int64_t value) {
        sqlite3_bind_int64(stmt_, at, value);
    }
    /* Zero is the archive's own way of saying "this member is absent", so a
     * column that mirrors an omitted member holds NULL rather than 0. */
    void bind_int64_or_null(int at, int64_t value) {
        if (value == 0) {
            sqlite3_bind_null(stmt_, at);
        } else {
            sqlite3_bind_int64(stmt_, at, value);
        }
    }

    int step() { return sqlite3_step(stmt_); }

    std::string error(sqlite3 *db) const { return sqlite3_errmsg(db); }

private:
    sqlite3_stmt *stmt_ = nullptr;
    int           rc_ = SQLITE_OK;
};

/* One transaction, rolled back whole unless it is committed. Every store
 * operation is one transaction (docs/game-data.md), and a rollback that
 * depends on remembering to call it is a rollback that is one early return
 * from not happening. */
class Transaction {
public:
    explicit Transaction(sqlite3 *db) : db_(db) {}
    ~Transaction() {
        if (open_) {
            std::string ignored;
            int rc = SQLITE_OK;
            exec(db_, "ROLLBACK;", rc, ignored);
        }
    }

    Transaction(const Transaction &) = delete;
    Transaction &operator=(const Transaction &) = delete;

    bool begin(int &rc, std::string &detail) {
        /* IMMEDIATE: the write lock is taken up front, so a busy store is
         * reported here rather than at the commit, where half the statements
         * would already have run. */
        if (!exec(db_, "BEGIN IMMEDIATE;", rc, detail)) {
            return false;
        }
        open_ = true;
        return true;
    }

    bool commit(int &rc, std::string &detail) {
        if (!exec(db_, "COMMIT;", rc, detail)) {
            return false;
        }
        open_ = false;
        return true;
    }

private:
    sqlite3 *db_ = nullptr;
    bool     open_ = false;
};

/* ---------------------------------------------------------------------- */
/* The library revision                                                    */
/* ---------------------------------------------------------------------- */

constexpr const char *kRevisionKey = "library_revision";

/*
 * Bump the counter inside the caller's transaction, so that it commits with
 * the change it reports or not at all.
 *
 * The upsert is one statement rather than a read and a write: it is also what
 * makes the counter arrive for a library created by a build that predates it,
 * where the row is simply absent and the first mutation writes 1. It is an
 * ON CONFLICT DO UPDATE and not OR REPLACE — there is no implicit delete here,
 * and the prohibition at the top of mxq_store.hpp is kept.
 */
bool bump_revision(sqlite3 *db, int &rc, std::string &detail) {
    return exec(db,
                "INSERT INTO meta (key, value) VALUES ('library_revision', '1')"
                " ON CONFLICT (key) DO UPDATE"
                " SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT);",
                rc, detail);
}

/* Read the counter. An absent row is revision 0: a library that has recorded
 * no mutation and one that predates the counter answer the same thing, which
 * is the truth in both cases. */
MxqStatus read_revision(sqlite3 *db, uint64_t &out, MxqError *err) {
    out = 0;
    Stmt select(db, "SELECT CAST(value AS INTEGER) FROM meta WHERE key = ?;");
    if (!select.ok()) {
        return fail_sqlite(err, select.rc(),
                           "cannot prepare the revision query: " +
                               select.error(db));
    }
    select.bind_text(1, kRevisionKey);
    const int step = select.step();
    if (step == SQLITE_DONE) {
        return MXQ_OK;
    }
    if (step != SQLITE_ROW) {
        return fail_sqlite(err, step, "cannot read the library revision: " +
                                          select.error(db));
    }
    const int64_t value = sqlite3_column_int64(select.get(), 0);
    out = value < 0 ? 0u : static_cast<uint64_t>(value);
    return MXQ_OK;
}

/* ---------------------------------------------------------------------- */
/* Reading rows                                                            */
/* ---------------------------------------------------------------------- */

/* The summary columns, in one order, named once. Every statement that reads a
 * row selects exactly this list, so read_summary below can decode any of
 * them. */
const char *const kSummaryColumns =
    "record_id, game_id, content_sha256, mode, human_side, ai_level,"
    " ai_movetime_ms, move_count, outcome, end_reason, provenance, pinned,"
    " started_at_ms, ended_at_ms, added_at_ms";

/* Where the archive column lands when a statement selects kSummaryColumns and
 * then the blob. */
constexpr int kArchiveColumn = 15;

std::string text_at(sqlite3_stmt *stmt, int column) {
    if (sqlite3_column_type(stmt, column) == SQLITE_NULL) {
        return std::string();
    }
    const unsigned char *text = sqlite3_column_text(stmt, column);
    return text != nullptr ? reinterpret_cast<const char *>(text)
                           : std::string();
}

void read_summary(sqlite3_stmt *stmt, Summary &out) {
    out.record_id = static_cast<uint64_t>(sqlite3_column_int64(stmt, 0));
    out.game_id = text_at(stmt, 1);
    out.content_sha256 = text_at(stmt, 2);
    out.mode = text_at(stmt, 3);
    out.human_side = text_at(stmt, 4);
    out.ai_level = text_at(stmt, 5);
    out.ai_movetime_ms = sqlite3_column_int64(stmt, 6);
    out.move_count = sqlite3_column_int64(stmt, 7);
    out.outcome = text_at(stmt, 8);
    out.end_reason = text_at(stmt, 9);
    out.provenance = text_at(stmt, 10);
    out.pinned = sqlite3_column_int64(stmt, 11) != 0;
    out.started_at_ms = sqlite3_column_int64(stmt, 12);
    out.ended_at_ms = sqlite3_column_int64(stmt, 13);
    out.added_at_ms = sqlite3_column_int64(stmt, 14);
}

/* The archive column of a row already stepped to, as bytes. A column this
 * build cannot read is corruption rather than an empty archive. */
bool read_archive(sqlite3_stmt *stmt, int column, std::string &out) {
    const void *blob = sqlite3_column_blob(stmt, column);
    const int bytes = sqlite3_column_bytes(stmt, column);
    if (bytes < 0 || (blob == nullptr && bytes > 0)) {
        return false;
    }
    out.assign(static_cast<const char *>(blob), static_cast<size_t>(bytes));
    return true;
}

/*
 * The library's active-game reference, and whether the row it names is there.
 *
 * Two statements rather than one join, because the join cannot tell absence
 * from a dangling reference and those are different answers: no active game is
 * an ordinary state, and a reference to a row that is not there is corruption.
 */
MxqStatus active_reference(sqlite3 *db, bool &out_exists,
                           uint64_t &out_record_id, MxqError *err) {
    out_exists = false;
    out_record_id = 0;

    Stmt reference(db, "SELECT active_record_id FROM library WHERE id = 1;");
    if (!reference.ok()) {
        return fail_sqlite(err, reference.rc(),
                           "cannot prepare the library query: " +
                               reference.error(db));
    }
    const int step = reference.step();
    if (step != SQLITE_ROW) {
        return fail(err, MXQ_ERR_STORE_CORRUPT, step,
                    "the library row is missing");
    }
    if (sqlite3_column_type(reference.get(), 0) == SQLITE_NULL) {
        return MXQ_OK;
    }
    out_record_id =
        static_cast<uint64_t>(sqlite3_column_int64(reference.get(), 0));
    out_exists = true;
    return MXQ_OK;
}

} /* namespace */

MxqStatus create_active(Store &store, const ActiveGame &row,
                        uint64_t &out_record_id, MxqError *err) {
    out_record_id = 0;
    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    int rc = SQLITE_OK;
    std::string detail;
    Transaction tx(db);
    if (!tx.begin(rc, detail)) {
        return fail_sqlite(err, rc, "cannot begin the creation transaction: " +
                                        detail);
    }

    /* The single active game, checked inside the transaction that would break
     * it: the reference column is the invariant, so the reference is what is
     * asked. */
    {
        bool active = false;
        uint64_t active_id = 0;
        const MxqStatus st = active_reference(db, active, active_id, err);
        if (st != MXQ_OK) {
            return st;
        }
        if (active) {
            fill_error(err, MXQ_ERR_STATE_ACTIVE_GAME_EXISTS,
                       "the library already holds an active game");
            return MXQ_ERR_STATE_ACTIVE_GAME_EXISTS;
        }
    }

    {
        Stmt insert(db,
                    "INSERT INTO game (game_id, archive, content_sha256, mode,"
                    " human_side, ai_level, ai_movetime_ms, first_mover_choice,"
                    " move_count, provenance, started_at_ms)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'locally-played', ?);");
        if (!insert.ok()) {
            return fail_sqlite(err, insert.rc(),
                               "cannot prepare the insert: " + insert.error(db));
        }
        insert.bind_text(1, row.game_id);
        insert.bind_blob(2, row.archive);
        insert.bind_text(3, row.content_sha256);
        insert.bind_text(4, row.mode);
        insert.bind_text(5, row.human_side);
        insert.bind_text(6, row.ai_level);
        insert.bind_int64_or_null(7, row.ai_movetime_ms);
        insert.bind_text(8, row.first_mover_choice);
        insert.bind_int64(9, row.move_count);
        insert.bind_int64(10, row.started_at_ms);
        const int step = insert.step();
        if (step != SQLITE_DONE) {
            return fail_sqlite(err, step,
                               "cannot insert the active game: " +
                                   insert.error(db));
        }
    }

    const int64_t record_id = sqlite3_last_insert_rowid(db);

    {
        /* The reference is set after the row exists and while its outcome is
         * still null, which is the order the active_reference_is_an_
         * uncommitted_game trigger requires. */
        Stmt reference(db,
                       "UPDATE library SET active_record_id = ? WHERE id = 1;");
        if (!reference.ok()) {
            return fail_sqlite(err, reference.rc(),
                               "cannot prepare the reference update: " +
                                   reference.error(db));
        }
        reference.bind_int64(1, record_id);
        const int step = reference.step();
        if (step != SQLITE_DONE) {
            return fail_sqlite(err, step,
                               "cannot point the library at the new game: " +
                                   reference.error(db));
        }
    }

    if (!bump_revision(db, rc, detail)) {
        return fail_sqlite(err, rc,
                           "cannot bump the library revision: " + detail);
    }

    if (!tx.commit(rc, detail)) {
        return fail_sqlite(err, rc, "cannot commit the new game: " + detail);
    }
    out_record_id = static_cast<uint64_t>(record_id);
    return MXQ_OK;
}

MxqStatus load_active(Store &store, bool &out_exists, uint64_t &out_record_id,
                      std::string &out_archive, std::string &out_content_sha256,
                      MxqError *err) {
    out_exists = false;
    out_record_id = 0;
    out_archive.clear();
    out_content_sha256.clear();

    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    bool referenced = false;
    uint64_t record_id = 0;
    const MxqStatus st = active_reference(db, referenced, record_id, err);
    if (st != MXQ_OK) {
        return st;
    }
    if (!referenced) {
        /* No active game. Absence is an ordinary state and not an error. */
        return MXQ_OK;
    }

    Stmt select(db, "SELECT archive, content_sha256 FROM game"
                    " WHERE record_id = ?;");
    if (!select.ok()) {
        return fail_sqlite(err, select.rc(),
                           "cannot prepare the active-game query: " +
                               select.error(db));
    }
    select.bind_int64(1, static_cast<int64_t>(record_id));
    const int step = select.step();
    if (step == SQLITE_DONE) {
        /* The library names a row that is not there. Foreign keys are on, so
         * nothing this core does can produce it; answering "no active game"
         * would quietly discard a game the library still claims to hold. */
        return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                    "the library's active-game reference names a row that is "
                    "not there");
    }
    if (step != SQLITE_ROW) {
        return fail_sqlite(err, step, "cannot read the active game: " +
                                          select.error(db));
    }
    if (!read_archive(select.get(), 0, out_archive)) {
        return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                    "the active game's archive column is unreadable");
    }
    out_content_sha256 = text_at(select.get(), 1);
    out_record_id = record_id;
    out_exists = true;
    return MXQ_OK;
}

MxqStatus rewrite_active(Store &store, uint64_t record_id,
                         const std::string &archive,
                         const std::string &content_sha256, int64_t move_count,
                         MxqError *err) {
    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    int rc = SQLITE_OK;
    std::string detail;
    Transaction tx(db);
    if (!tx.begin(rc, detail)) {
        return fail_sqlite(err, rc,
                           "cannot begin the mutation transaction: " + detail);
    }

    {
        /* The outcome condition is not decoration: it is what makes this
         * statement incapable of rewriting a History record, whatever record
         * id it is handed. The trigger would refuse it too; refusing it here
         * as well means the answer is a status rather than a raised error. */
        Stmt update(db, "UPDATE game SET archive = ?, content_sha256 = ?,"
                        " move_count = ? WHERE record_id = ?"
                        " AND outcome IS NULL;");
        if (!update.ok()) {
            return fail_sqlite(err, update.rc(),
                               "cannot prepare the update: " + update.error(db));
        }
        update.bind_blob(1, archive);
        update.bind_text(2, content_sha256);
        update.bind_int64(3, move_count);
        update.bind_int64(4, static_cast<int64_t>(record_id));
        const int step = update.step();
        if (step != SQLITE_DONE) {
            return fail_sqlite(err, step, "cannot rewrite the active game: " +
                                              update.error(db));
        }
        if (sqlite3_changes(db) != 1) {
            fill_error(err, MXQ_ERR_STORE_NOT_FOUND,
                       "the active game's row is no longer there to rewrite");
            return MXQ_ERR_STORE_NOT_FOUND;
        }
    }

    if (!bump_revision(db, rc, detail)) {
        return fail_sqlite(err, rc,
                           "cannot bump the library revision: " + detail);
    }

    if (!tx.commit(rc, detail)) {
        return fail_sqlite(err, rc, "cannot commit the move: " + detail);
    }
    return MXQ_OK;
}

MxqStatus commit_completion(Store &store, uint64_t record_id,
                            const Completion &done, MxqError *err) {
    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    int rc = SQLITE_OK;
    std::string detail;
    Transaction tx(db);
    if (!tx.begin(rc, detail)) {
        return fail_sqlite(err, rc,
                           "cannot begin the archiving transaction: " + detail);
    }

    /* The row must still be the library's active game. Asking inside the
     * transaction that would end it is the same discipline creation uses: the
     * reference column is the invariant, so the reference is what is asked. */
    {
        bool referenced = false;
        uint64_t active_id = 0;
        const MxqStatus st = active_reference(db, referenced, active_id, err);
        if (st != MXQ_OK) {
            return st;
        }
        if (!referenced || active_id != record_id) {
            fill_error(err, MXQ_ERR_STORE_NOT_FOUND,
                       "the game is no longer the library's active game");
            return MXQ_ERR_STORE_NOT_FOUND;
        }
    }

    {
        /* First: the reference goes. The commit_clears_active_reference_first
         * trigger refuses the outcome update while the library still names the
         * row, so this ordering is the schema's requirement and not a
         * preference. */
        Stmt clear(db, "UPDATE library SET active_record_id = NULL"
                       " WHERE id = 1;");
        if (!clear.ok()) {
            return fail_sqlite(err, clear.rc(),
                               "cannot prepare the reference clear: " +
                                   clear.error(db));
        }
        const int step = clear.step();
        if (step != SQLITE_DONE) {
            return fail_sqlite(err, step,
                               "cannot clear the active-game reference: " +
                                   clear.error(db));
        }
    }

    {
        /* Then the outcome, with the finished document and its hash. The
         * outcome IS NULL condition is what makes this statement incapable of
         * rewriting a History record, whatever record id it is handed. */
        Stmt commit(db, "UPDATE game SET archive = ?, content_sha256 = ?,"
                        " move_count = ?, outcome = ?, end_reason = ?,"
                        " ended_at_ms = ?, added_at_ms = ?"
                        " WHERE record_id = ? AND outcome IS NULL;");
        if (!commit.ok()) {
            return fail_sqlite(err, commit.rc(),
                               "cannot prepare the archiving update: " +
                                   commit.error(db));
        }
        commit.bind_blob(1, done.archive);
        commit.bind_text(2, done.content_sha256);
        commit.bind_int64(3, done.move_count);
        commit.bind_text(4, done.outcome);
        commit.bind_text(5, done.end_reason);
        commit.bind_int64(6, done.ended_at_ms);
        commit.bind_int64(7, done.added_at_ms);
        commit.bind_int64(8, static_cast<int64_t>(record_id));
        const int step = commit.step();
        if (step != SQLITE_DONE) {
            return fail_sqlite(err, step, "cannot commit the outcome: " +
                                              commit.error(db));
        }
        if (sqlite3_changes(db) != 1) {
            fill_error(err, MXQ_ERR_STORE_NOT_FOUND,
                       "the active game's row is no longer there to archive");
            return MXQ_ERR_STORE_NOT_FOUND;
        }
    }

    if (!bump_revision(db, rc, detail)) {
        return fail_sqlite(err, rc,
                           "cannot bump the library revision: " + detail);
    }

    if (!tx.commit(rc, detail)) {
        return fail_sqlite(err, rc, "cannot commit the archived game: " +
                                        detail);
    }
    return MXQ_OK;
}

MxqStatus active_exists(Store &store, bool &out_exists, MxqError *err) {
    out_exists = false;
    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    bool referenced = false;
    uint64_t record_id = 0;
    const MxqStatus st = active_reference(db, referenced, record_id, err);
    if (st != MXQ_OK) {
        return st;
    }
    if (!referenced) {
        return MXQ_OK;
    }

    /* The reference must name a row. A dangling one is corruption here for the
     * same reason it is in load_active: the answer "there is no active game"
     * would be a lie the library itself contradicts. */
    Stmt present(db, "SELECT 1 FROM game WHERE record_id = ?;");
    if (!present.ok()) {
        return fail_sqlite(err, present.rc(),
                           "cannot prepare the active-game query: " +
                               present.error(db));
    }
    present.bind_int64(1, static_cast<int64_t>(record_id));
    const int step = present.step();
    if (step == SQLITE_DONE) {
        return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                    "the library's active-game reference names a row that is "
                    "not there");
    }
    if (step != SQLITE_ROW) {
        return fail_sqlite(err, step, "cannot read the active game: " +
                                          present.error(db));
    }
    out_exists = true;
    return MXQ_OK;
}

MxqStatus active_summary(Store &store, bool &out_exists, Summary &out,
                         std::string *out_archive, MxqError *err) {
    out_exists = false;
    out = Summary();
    if (out_archive != nullptr) {
        out_archive->clear();
    }

    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    bool referenced = false;
    uint64_t record_id = 0;
    const MxqStatus st = active_reference(db, referenced, record_id, err);
    if (st != MXQ_OK) {
        return st;
    }
    if (!referenced) {
        return MXQ_OK;
    }

    const std::string sql = std::string("SELECT ") + kSummaryColumns +
                            ", archive FROM game WHERE record_id = ?;";
    Stmt select(db, sql.c_str());
    if (!select.ok()) {
        return fail_sqlite(err, select.rc(),
                           "cannot prepare the active-summary query: " +
                               select.error(db));
    }
    select.bind_int64(1, static_cast<int64_t>(record_id));
    const int step = select.step();
    if (step == SQLITE_DONE) {
        return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                    "the library's active-game reference names a row that is "
                    "not there");
    }
    if (step != SQLITE_ROW) {
        return fail_sqlite(err, step, "cannot read the active game: " +
                                          select.error(db));
    }
    read_summary(select.get(), out);
    if (out_archive != nullptr && !read_archive(select.get(), kArchiveColumn, *out_archive)) {
        return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                    "the active game's archive column is unreadable");
    }
    out_exists = true;
    return MXQ_OK;
}

MxqStatus history_count(Store &store, uint32_t &out_count,
                        uint64_t &out_revision, MxqError *err) {
    out_count = 0;
    out_revision = 0;
    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    {
        Stmt count(db,
                   "SELECT count(*) FROM game WHERE outcome IS NOT NULL;");
        if (!count.ok()) {
            return fail_sqlite(err, count.rc(),
                               "cannot prepare the History count: " +
                                   count.error(db));
        }
        const int step = count.step();
        if (step != SQLITE_ROW) {
            return fail_sqlite(err, step, "cannot count History: " +
                                              count.error(db));
        }
        out_count = static_cast<uint32_t>(sqlite3_column_int64(count.get(), 0));
    }
    return read_revision(db, out_revision, err);
}

MxqStatus history_page(Store &store, uint32_t offset, uint32_t limit,
                       std::vector<Summary> &out, uint64_t &out_revision,
                       MxqError *err) {
    out.clear();
    out_revision = 0;
    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    if (limit > 0) {
        /* The ORDER BY is the partial index's own key list, so the ordering
         * this page promises is the index rather than a second spelling of
         * it. */
        const std::string sql =
            std::string("SELECT ") + kSummaryColumns +
            " FROM game WHERE outcome IS NOT NULL"
            " ORDER BY pinned DESC, added_at_ms DESC, record_id DESC"
            " LIMIT ? OFFSET ?;";
        Stmt page(db, sql.c_str());
        if (!page.ok()) {
            return fail_sqlite(err, page.rc(),
                               "cannot prepare the History page: " +
                                   page.error(db));
        }
        page.bind_int64(1, static_cast<int64_t>(limit));
        page.bind_int64(2, static_cast<int64_t>(offset));
        for (;;) {
            const int step = page.step();
            if (step == SQLITE_DONE) {
                break;
            }
            if (step != SQLITE_ROW) {
                return fail_sqlite(err, step, "cannot read a History page: " +
                                                  page.error(db));
            }
            Summary row;
            read_summary(page.get(), row);
            out.push_back(std::move(row));
        }
    }
    return read_revision(db, out_revision, err);
}

MxqStatus history_record(Store &store, uint64_t record_id, Summary &out,
                         std::string *out_archive, MxqError *err) {
    out = Summary();
    if (out_archive != nullptr) {
        out_archive->clear();
    }
    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    /* outcome IS NOT NULL is what makes this a History query: the active game
     * is not a History record, and asking for it by its record id is the same
     * answer as asking for an identifier that was never issued. */
    const std::string sql = std::string("SELECT ") + kSummaryColumns +
                            ", archive FROM game"
                            " WHERE record_id = ? AND outcome IS NOT NULL;";
    Stmt select(db, sql.c_str());
    if (!select.ok()) {
        return fail_sqlite(err, select.rc(),
                           "cannot prepare the History query: " +
                               select.error(db));
    }
    select.bind_int64(1, static_cast<int64_t>(record_id));
    const int step = select.step();
    if (step == SQLITE_DONE) {
        fill_error(err, MXQ_ERR_STORE_NOT_FOUND,
                   "there is no History record with that identifier");
        return MXQ_ERR_STORE_NOT_FOUND;
    }
    if (step != SQLITE_ROW) {
        return fail_sqlite(err, step, "cannot read the History record: " +
                                          select.error(db));
    }
    read_summary(select.get(), out);
    if (out_archive != nullptr && !read_archive(select.get(), kArchiveColumn, *out_archive)) {
        return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                    "the History record's archive column is unreadable");
    }
    return MXQ_OK;
}

MxqStatus history_set_pinned(Store &store, uint64_t record_id, bool pinned,
                             MxqError *err) {
    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    int rc = SQLITE_OK;
    std::string detail;
    Transaction tx(db);
    if (!tx.begin(rc, detail)) {
        return fail_sqlite(err, rc, "cannot begin the pin transaction: " +
                                        detail);
    }

    {
        /* Pin state is the one mutable field of a History record, and the
         * history_content_is_immutable trigger is what says so: it names every
         * other column and fires when one of them moves. Restricting the
         * statement to committed rows keeps the active game — which the schema
         * forbids pinning — an ordinary not-found rather than a raised
         * constraint. */
        Stmt update(db, "UPDATE game SET pinned = ?"
                        " WHERE record_id = ? AND outcome IS NOT NULL;");
        if (!update.ok()) {
            return fail_sqlite(err, update.rc(),
                               "cannot prepare the pin update: " +
                                   update.error(db));
        }
        update.bind_int64(1, pinned ? 1 : 0);
        update.bind_int64(2, static_cast<int64_t>(record_id));
        const int step = update.step();
        if (step != SQLITE_DONE) {
            return fail_sqlite(err, step, "cannot set the pin state: " +
                                              update.error(db));
        }
        if (sqlite3_changes(db) != 1) {
            fill_error(err, MXQ_ERR_STORE_NOT_FOUND,
                       "there is no History record with that identifier");
            return MXQ_ERR_STORE_NOT_FOUND;
        }
    }

    if (!bump_revision(db, rc, detail)) {
        return fail_sqlite(err, rc,
                           "cannot bump the library revision: " + detail);
    }
    if (!tx.commit(rc, detail)) {
        return fail_sqlite(err, rc, "cannot commit the pin state: " + detail);
    }
    return MXQ_OK;
}

MxqStatus history_delete(Store &store, uint64_t record_id, MxqError *err) {
    std::lock_guard<std::mutex> lock(store.mutex());
    sqlite3 *db = store.db();

    int rc = SQLITE_OK;
    std::string detail;
    Transaction tx(db);
    if (!tx.begin(rc, detail)) {
        return fail_sqlite(err, rc, "cannot begin the deletion transaction: " +
                                        detail);
    }

    {
        /* Whole and permanent: there is no soft delete and no undo. The
         * committed-row condition keeps the active game out of reach — it is
         * also the referenced row, which foreign keys would refuse — so
         * deleting it is a not-found rather than a constraint failure, and a
         * failed deletion leaves the record intact because the transaction
         * rolls back whole. */
        Stmt remove(db, "DELETE FROM game"
                        " WHERE record_id = ? AND outcome IS NOT NULL;");
        if (!remove.ok()) {
            return fail_sqlite(err, remove.rc(),
                               "cannot prepare the deletion: " +
                                   remove.error(db));
        }
        remove.bind_int64(1, static_cast<int64_t>(record_id));
        const int step = remove.step();
        if (step != SQLITE_DONE) {
            return fail_sqlite(err, step, "cannot delete the History record: " +
                                              remove.error(db));
        }
        if (sqlite3_changes(db) != 1) {
            fill_error(err, MXQ_ERR_STORE_NOT_FOUND,
                       "there is no History record with that identifier");
            return MXQ_ERR_STORE_NOT_FOUND;
        }
    }

    if (!bump_revision(db, rc, detail)) {
        return fail_sqlite(err, rc,
                           "cannot bump the library revision: " + detail);
    }
    if (!tx.commit(rc, detail)) {
        return fail_sqlite(err, rc, "cannot commit the deletion: " + detail);
    }
    return MXQ_OK;
}

MxqStatus library_revision(Store &store, uint64_t &out_revision,
                           MxqError *err) {
    std::lock_guard<std::mutex> lock(store.mutex());
    return read_revision(store.db(), out_revision, err);
}

Store::~Store() {
    if (db_ != nullptr) {
        /* No statement outlives its operation in this design, so close cannot
         * report SQLITE_BUSY; if it ever did, the leak would be a core bug,
         * and there is no caller here to report it to. */
        sqlite3_close(db_);
        db_ = nullptr;
    }
}

MxqStatus open(const std::string &directory, std::unique_ptr<Store> &out,
               MxqError *err) {
    out.reset();

    /* The frontend supplies the location; the leading directories may not
     * exist on a first launch, and creating them is part of "create". */
    const std::filesystem::path dir(directory);
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    if (ec) {
        return fail(err, MXQ_ERR_STORE_IO, ec.value(),
                    "cannot create the store directory: " + ec.message());
    }

    const std::string path = (dir / kDatabaseFileName).string();
    sqlite3 *raw = nullptr;
    int rc = sqlite3_open_v2(path.c_str(), &raw,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
                             nullptr);
    if (rc != SQLITE_OK) {
        const std::string detail =
            raw != nullptr ? sqlite3_errmsg(raw) : sqlite3_errstr(rc);
        sqlite3_close(raw);
        return fail_sqlite(err, rc, "cannot open the store: " + detail);
    }

    auto store = std::unique_ptr<Store>(new Store());
    store->db_ = raw;
    sqlite3 *db = raw;

    /* Extended result codes reach MxqError.subsystem_code as diagnostics.
     * SQLITE_DBCONFIG_DEFENSIVE completes the compile-time hardening at the
     * connection: the schema and the file structure cannot be rewritten
     * through SQL even by a corrupted statement. */
    sqlite3_extended_result_codes(db, 1);
    /* Checked like the pragmas below: a connection that silently declined the
     * defensive regime would be exactly the kind of quiet weakening this
     * open sequence exists to refuse. */
    if (int rc = sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, 1, nullptr);
        rc != SQLITE_OK) {
        return fail_sqlite(err, rc, "cannot enable the defensive regime");
    }

    /* The accepted connection regime, applied and read back. */
    MxqStatus st = apply_pragma(db, "PRAGMA journal_mode = WAL;",
                                "PRAGMA journal_mode;", "wal",
                                "journal_mode=WAL", err);
    if (st != MXQ_OK) {
        return st;
    }
    st = apply_pragma(db, "PRAGMA synchronous = FULL;", "PRAGMA synchronous;",
                      "2", "synchronous=FULL", err);
    if (st != MXQ_OK) {
        return st;
    }
    st = apply_pragma(db, "PRAGMA foreign_keys = ON;", "PRAGMA foreign_keys;",
                      "1", "foreign_keys=ON", err);
    if (st != MXQ_OK) {
        return st;
    }

    /* Schema versioning, per docs/game-data.md: the version lives in the
     * database's own version pragma, migration is forward-only, and a store
     * written by a newer build is refused rather than opened. */
    std::string detail;
    std::string value;
    if (!query_first_column(db, "PRAGMA user_version;", value, rc, detail)) {
        return fail_sqlite(err, rc, "cannot read the schema version: " + detail);
    }
    int64_t version = 0;
    try {
        version = std::stoll(value);
    } catch (...) {
        return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                    "unreadable schema version: " + value);
    }

    if (version == 0) {
        if (!query_first_column(db,
                                "SELECT count(*) FROM sqlite_schema "
                                "WHERE name NOT LIKE 'sqlite_%';",
                                value, rc, detail)) {
            return fail_sqlite(err, rc, "cannot inspect the schema: " + detail);
        }
        if (value != "0") {
            /* Content without a recorded schema version was never written by
             * any build of this core; whatever it is, opening it would be
             * guessing. */
            return fail(err, MXQ_ERR_STORE_CORRUPT, 0,
                        "the store has content but no recorded schema version");
        }
        st = create_schema_v1(db, err);
        if (st != MXQ_OK) {
            return st;
        }
    } else if (version > static_cast<int64_t>(MXQ_STORE_SCHEMA_VERSION)) {
        return fail(err, MXQ_ERR_STORE_SCHEMA_TOO_NEW,
                    static_cast<int>(version),
                    "the store was written by a newer build (schema version " +
                        std::to_string(version) + "; this build reads up to " +
                        std::to_string(MXQ_STORE_SCHEMA_VERSION) + ")");
    } else {
        /* Forward-only migration dispatch. Version 1 is the first schema ever
         * shipped, so no step exists yet; each future step migrates N to N+1
         * inside one transaction and lands as a case below. */
        while (version < static_cast<int64_t>(MXQ_STORE_SCHEMA_VERSION)) {
            switch (version) {
            default:
                return fail(err, MXQ_ERR_STORE_MIGRATION_FAILED,
                            static_cast<int>(version),
                            "no migration path from schema version " +
                                std::to_string(version));
            }
        }
    }

    st = verify_schema(db, err);
    if (st != MXQ_OK) {
        return st;
    }

    out = std::move(store);
    return MXQ_OK;
}

} /* namespace store */
} /* namespace mxq */
