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
  record_id          INTEGER PRIMARY KEY,
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

} /* namespace */

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
    sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, 1, nullptr);

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
