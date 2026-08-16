/*
 * Store-foundation tests: the SQLite-backed library store opened by
 * mxq_core_init, and the deterministic-identity seam.
 *
 * Everything here runs against a scratch directory under the system temporary
 * path; nothing touches a real store. Two kinds of access are used
 * deliberately:
 *
 *   - the public C surface, for what the contract promises callers
 *     (initialisation opens or refuses the store, shutdown closes it);
 *   - direct SQLite connections and the core's internal headers, for what the
 *     schema and the identity provider must actually contain. Schema shape is
 *     asserted by querying the closed database, never by trusting that the DDL
 *     ran, and identity is read from the same provider sessions will consume.
 *     The white-box access is legitimate here because this runner links the
 *     core statically and is part of the same repository; nothing of it leaks
 *     through mxq.h.
 *
 * The direct-connection cases also exercise the schema's own enforcement —
 * the permanence trigger, History immutability, the archive-and-clear
 * ordering triggers, and a representative check constraint — by attempting
 * exactly the writes they must refuse.
 */

#include "mxq.h"

#include "mxq_core_state.hpp" /* internal, deliberately: see the header comment */

#include "sqlite3.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <random>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

int g_failures = 0;
std::string g_case;

void check(bool ok, const std::string &what) {
    if (!ok) {
        ++g_failures;
        std::cout << "  FAIL  [" << g_case << "] " << what << "\n";
    }
}

void check_eq(const std::string &got, const std::string &want,
              const std::string &what) {
    if (got != want) {
        ++g_failures;
        std::cout << "  FAIL  [" << g_case << "] " << what << ": expected \""
                  << want << "\", got \"" << got << "\"\n";
    }
}

std::string assets_dir() {
    if (const char *env = std::getenv("MXQ_ASSETS_DIR")) {
        return env;
    }
#if defined(MXQ_ASSETS_DIR_DEFAULT)
    return MXQ_ASSETS_DIR_DEFAULT;
#else
    return std::string();
#endif
}

MxqError make_error() {
    MxqError err;
    std::memset(&err, 0, sizeof(err));
    err.struct_size = static_cast<uint32_t>(sizeof(err));
    return err;
}

MxqStatus init_core(const std::string &store_dir, uint32_t flags,
                    MxqCore **out_core, MxqError *err) {
    const std::string assets = assets_dir();
    MxqCoreConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.api_major = MXQ_API_VERSION_MAJOR;
    config.api_minor = MXQ_API_VERSION_MINOR;
    config.api_patch = MXQ_API_VERSION_PATCH;
    config.flags = flags;
    config.store_directory = store_dir.c_str();
    config.asset_directory = assets.c_str();
    return mxq_core_init(&config, out_core, err);
}

/* A fresh scratch directory per case, so no case can lean on another. The
 * run-unique token keeps two simultaneous runs of this binary apart. */
fs::path scratch_dir(const char *name) {
    static const std::string run_token = [] {
        std::random_device rd;
        char buffer[17];
        std::snprintf(buffer, sizeof(buffer), "%08x%08x", rd(), rd());
        return std::string(buffer);
    }();
    const fs::path dir = fs::temp_directory_path() /
                         ("minixiangqi-store-tests-" + run_token) / name;
    std::error_code ec;
    fs::remove_all(dir, ec);
    fs::create_directories(dir, ec);
    return dir;
}

fs::path db_path(const fs::path &dir) {
    return dir / mxq::store::kDatabaseFileName;
}

/* -------- direct SQLite access, for asserting rather than trusting -------- */

sqlite3 *open_direct(const fs::path &path) {
    sqlite3 *db = nullptr;
    const int rc = sqlite3_open_v2(path.string().c_str(), &db,
                                   SQLITE_OPEN_READWRITE, nullptr);
    check(rc == SQLITE_OK, "cannot open the database directly: " +
                               std::string(sqlite3_errstr(rc)));
    if (rc != SQLITE_OK) {
        sqlite3_close(db);
        return nullptr;
    }
    return db;
}

std::string query_text(sqlite3 *db, const std::string &sql) {
    sqlite3_stmt *stmt = nullptr;
    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        check(false, "prepare failed: " + sql + ": " + sqlite3_errmsg(db));
        return "<prepare failed>";
    }
    std::string value = "<no rows>";
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *text = sqlite3_column_text(stmt, 0);
        value = text != nullptr ? reinterpret_cast<const char *>(text) : "<null>";
    }
    sqlite3_finalize(stmt);
    return value;
}

void exec_ok(sqlite3 *db, const std::string &sql) {
    char *msg = nullptr;
    const int rc = sqlite3_exec(db, sql.c_str(), nullptr, nullptr, &msg);
    check(rc == SQLITE_OK, "statement failed: " + sql + ": " +
                               (msg != nullptr ? msg : "?"));
    sqlite3_free(msg);
}

/* The write the schema must refuse. The interesting assertion is that it
 * fails; the message is reported when it wrongly succeeds. */
void exec_refused(sqlite3 *db, const std::string &sql, const std::string &why) {
    char *msg = nullptr;
    const int rc = sqlite3_exec(db, sql.c_str(), nullptr, nullptr, &msg);
    check(rc != SQLITE_OK, "the schema must refuse this (" + why + "): " + sql);
    sqlite3_free(msg);
}

/* -------------------------------- cases ---------------------------------- */

const char *const kHex64 =
    "0000000000000000000000000000000000000000000000000000000000000000";

void case_fresh_open_creates_schema() {
    g_case = "fresh open creates the schema";
    const fs::path dir = scratch_dir("fresh");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    MxqStatus rc = init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
    check(rc == MXQ_OK, std::string("mxq_core_init failed: ") +
                            mxq_status_name(rc) + ": " + err.detail);
    if (rc != MXQ_OK) {
        return;
    }
    check(fs::exists(db_path(dir)), "the database file exists after init");
    rc = mxq_core_shutdown(core, nullptr);
    check(rc == MXQ_OK, "mxq_core_shutdown failed");

    sqlite3 *db = open_direct(db_path(dir));
    if (db == nullptr) {
        return;
    }
    /* The recorded schema version and the persistent half of the regime. */
    check_eq(query_text(db, "PRAGMA user_version;"), "5", "user_version");
    check_eq(query_text(db, "PRAGMA journal_mode;"), "wal",
             "journal_mode persisted in the file");
    /* The compiled defaults from the hardened option set reach even a fresh
     * direct connection that set nothing. */
    check_eq(query_text(db, "PRAGMA foreign_keys;"), "1",
             "SQLITE_DEFAULT_FOREIGN_KEYS=1 took effect");

    /* The four tables, all STRICT. */
    check_eq(query_text(db, "SELECT count(*) FROM sqlite_schema WHERE "
                            "type='table' AND name IN "
                            "('meta','game','library','nearby_session');"),
             "4", "the four tables exist");
    check_eq(query_text(db, "SELECT count(*) FROM sqlite_schema WHERE "
                            "type='table' AND name IN "
                            "('meta','game','library','nearby_session') AND "
                            "sql LIKE '%STRICT%';"),
             "4", "all four tables are STRICT");
    check_eq(query_text(db, "SELECT count(*) FROM sqlite_schema WHERE "
                            "type='table' AND name NOT LIKE 'sqlite_%';"),
             "4", "no tables beyond the four");

    /* record_id is never reused: the History tie-break is this column, so a
     * reused rowid would let a stale id resolve to some later game. */
    check_eq(query_text(db, "SELECT count(*) FROM sqlite_schema WHERE "
                            "name='game' AND sql LIKE '%AUTOINCREMENT%';"),
             "1", "game.record_id is AUTOINCREMENT");

    /* The triggers and the one partial History index. */
    for (const char *trigger : {"library_row_is_permanent",
                                "history_content_is_immutable",
                                "commit_clears_active_reference_first",
                                "active_reference_is_an_uncommitted_game"}) {
        check_eq(query_text(db, std::string("SELECT count(*) FROM "
                                            "sqlite_schema WHERE "
                                            "type='trigger' AND name='") +
                                    trigger + "';"),
                 "1", std::string("trigger ") + trigger + " exists");
    }
    check_eq(query_text(db, "SELECT count(*) FROM sqlite_schema WHERE "
                            "type='index' AND name='history_order' AND sql "
                            "LIKE '%WHERE outcome IS NOT NULL%';"),
             "1", "the partial History index exists and excludes the active game");

    /* The single library row, with no active game, and the bookkeeping row. */
    check_eq(query_text(db, "SELECT count(*) FROM library;"), "1",
             "exactly one library row");
    check_eq(query_text(db, "SELECT active_record_id IS NULL FROM library;"),
             "1", "no active game on a fresh store");
    check_eq(query_text(db, "SELECT value FROM meta WHERE "
                            "key='created_schema_version';"),
             "5", "the meta bookkeeping row");
    /* A library that has recorded no mutation is at revision 0, which is what
     * a caller comparing revisions starts from. */
    check_eq(query_text(db, "SELECT value FROM meta WHERE "
                            "key='library_revision';"),
             "0", "a fresh library is at revision 0");
    sqlite3_close(db);
}

void case_schema_enforces_its_invariants() {
    g_case = "the schema enforces its invariants";
    const fs::path dir = scratch_dir("enforce");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    MxqStatus rc = init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
    check(rc == MXQ_OK, "mxq_core_init failed");
    if (rc != MXQ_OK) {
        return;
    }
    mxq_core_shutdown(core, nullptr);

    sqlite3 *db = open_direct(db_path(dir));
    if (db == nullptr) {
        return;
    }

    /* The library row is permanent and alone. */
    exec_refused(db, "DELETE FROM library;", "permanence trigger");
    exec_refused(db, "INSERT INTO library (id, active_record_id) VALUES (2, NULL);",
                 "single-row constraint");

    /* The game axis is a closed vocabulary in the schema, not a label the
     * writer is trusted with: a row naming a third ruleset is refused where a
     * mode outside its vocabulary is. */
    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "provenance, started_at_ms) VALUES "
                             "('00000000-0000-7000-8000-00000000000b', x'7b7d', '") +
                     kHex64 +
                     "', 'janggi', 'free-play', 0, 'locally-played', 1000);",
                 "rules_id vocabulary");

    /* And the one cross-field rule the game axis creates: the move-count rule
     * is Xiangqi's, so a Mini Xiangqi record cannot have ended by it. A core
     * that reported the reason for the wrong game would be caught here rather
     * than shipped into a History row nobody re-derives. */
    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "outcome, end_reason, provenance, started_at_ms, "
                             "ended_at_ms, added_at_ms) VALUES "
                             "('00000000-0000-7000-8000-00000000000c', x'7b7d', '") +
                     kHex64 +
                     "', 'minixiangqi', 'free-play', 4, 'draw', "
                     "'fifty-move-rule', 'locally-played', 1000, 2000, 3000);",
                 "the move-count rule belongs to Xiangqi");

    /* The same row is accepted for the game that has the rule, which is what
     * makes the refusal above about the game rather than about the reason. */
    exec_ok(db, std::string("INSERT INTO game (game_id, archive, "
                            "content_sha256, rules_id, mode, move_count, "
                            "outcome, end_reason, provenance, started_at_ms, "
                            "ended_at_ms, added_at_ms) VALUES "
                            "('00000000-0000-7000-8000-00000000000d', x'7b7d', '") +
                    kHex64 +
                    "', 'xiangqi', 'free-play', 4, 'draw', 'fifty-move-rule', "
                    "'locally-played', 1000, 2000, 3000);");

    /* The wider rule the same axis creates, which the move-count rule is a
     * narrowing of: a rule reason belongs to the kind of game whose rules
     * produce it, and both directions are constraints because a partition
     * checked on one side refuses half of what it knows. Each refusal is
     * followed by the row that differs only in the game, for the reason the
     * pair above exists: without the acceptance, a constraint that refused the
     * reason outright would pass. */
    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "outcome, end_reason, provenance, started_at_ms, "
                             "ended_at_ms, added_at_ms) VALUES "
                             "('00000000-0000-7000-8000-00000000001a', x'7b7d', '") +
                     kHex64 +
                     "', 'minixiangqi', 'free-play', 4, 'draw', 'board-full', "
                     "'locally-played', 1000, 2000, 3000);",
                 "a board to fill is a placement game's");
    exec_ok(db, std::string("INSERT INTO game (game_id, archive, "
                            "content_sha256, rules_id, mode, move_count, "
                            "outcome, end_reason, provenance, started_at_ms, "
                            "ended_at_ms, added_at_ms) VALUES "
                            "('00000000-0000-7000-8000-00000000001b', x'7b7d', '") +
                    kHex64 +
                    "', 'gomoku-15', 'free-play', 4, 'draw', 'board-full', "
                    "'locally-played', 1000, 2000, 3000);");

    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "outcome, end_reason, provenance, started_at_ms, "
                             "ended_at_ms, added_at_ms) VALUES "
                             "('00000000-0000-7000-8000-00000000001c', x'7b7d', '") +
                     kHex64 +
                     "', 'renju', 'free-play', 4, 'red-wins', 'checkmate', "
                     "'locally-played', 1000, 2000, 3000);",
                 "a king to mate is a movement game's");
    exec_ok(db, std::string("INSERT INTO game (game_id, archive, "
                            "content_sha256, rules_id, mode, move_count, "
                            "outcome, end_reason, provenance, started_at_ms, "
                            "ended_at_ms, added_at_ms) VALUES "
                            "('00000000-0000-7000-8000-00000000001d', x'7b7d', '") +
                    kHex64 +
                    "', 'minixiangqi', 'free-play', 4, 'red-wins', 'checkmate', "
                    "'locally-played', 1000, 2000, 3000);");

    /* A representative cross-field rule: a draw outcome must carry a draw
     * reason. */
    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "outcome, end_reason, provenance, started_at_ms, "
                             "ended_at_ms, added_at_ms) VALUES "
                             "('00000000-0000-7000-8000-00000000000a', x'7b7d', '") +
                     kHex64 +
                     "', 'minixiangqi', 'free-play', 4, 'draw', 'checkmate', "
                     "'locally-played', 1000, 2000, 3000);",
                 "outcome/end_reason well-formedness");

    /* The two ends two players declare to each other belong to the one mode
     * that has two players: a Free Play game has nobody to agree with. */
    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "outcome, end_reason, provenance, started_at_ms, "
                             "ended_at_ms, added_at_ms) VALUES "
                             "('00000000-0000-7000-8000-00000000000e', x'7b7d', '") +
                     kHex64 +
                     "', 'minixiangqi', 'free-play', 4, 'draw', 'agreed-draw', "
                     "'locally-played', 1000, 2000, 3000);",
                 "an agreed draw belongs to nearby");

    /* Local perspective, both ways round. A locally played nearby record has a
     * local side and nothing else does — an imported one had no local player,
     * and neither local mode has two. */
    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "provenance, started_at_ms, local_side) VALUES "
                             "('00000000-0000-7000-8000-00000000000f', x'7b7d', '") +
                     kHex64 +
                     "', 'minixiangqi', 'free-play', 0, 'locally-played', "
                     "1000, 'red');",
                 "a local side outside nearby play");
    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "provenance, started_at_ms) VALUES "
                             "('00000000-0000-7000-8000-000000000010', x'7b7d', '") +
                     kHex64 +
                     "', 'minixiangqi', 'nearby', 0, 'locally-played', 1000);",
                 "a locally played nearby game without a local side");
    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "outcome, end_reason, provenance, started_at_ms, "
                             "ended_at_ms, added_at_ms, local_side) VALUES "
                             "('00000000-0000-7000-8000-000000000011', x'7b7d', '") +
                     kHex64 +
                     "', 'minixiangqi', 'nearby', 4, 'draw', 'agreed-draw', "
                     "'imported', 1000, 2000, 3000, 'red');",
                 "an imported nearby record with a local side");

    /* And the shape that is right: a nearby record ended by an agreement, with
     * the local side its own device played. */
    exec_ok(db, std::string("INSERT INTO game (game_id, archive, "
                            "content_sha256, rules_id, mode, move_count, "
                            "outcome, end_reason, provenance, started_at_ms, "
                            "ended_at_ms, added_at_ms, local_side) VALUES "
                            "('00000000-0000-7000-8000-000000000012', x'7b7d', '") +
                    kHex64 +
                    "', 'minixiangqi', 'nearby', 4, 'draw', "
                    "'mutual-resignation', 'locally-played', 1000, 2000, 3000, "
                    "'black');");

    /* A resignation needs an opponent to resign to. Free Play is one person
     * moving both sides and has none; nearby play has one, and the outcome
     * names the winner without a human_side to check it against, which is the
     * whole difference from the human-versus-AI rule beside it. */
    exec_refused(db,
                 std::string("INSERT INTO game (game_id, archive, "
                             "content_sha256, rules_id, mode, move_count, "
                             "outcome, end_reason, provenance, started_at_ms, "
                             "ended_at_ms, added_at_ms) VALUES "
                             "('00000000-0000-7000-8000-000000000013', x'7b7d', '") +
                     kHex64 +
                     "', 'minixiangqi', 'free-play', 4, 'red-wins', "
                     "'resignation', 'locally-played', 1000, 2000, 3000);",
                 "a resignation with nobody to resign to");
    exec_ok(db, std::string("INSERT INTO game (game_id, archive, "
                            "content_sha256, rules_id, mode, move_count, "
                            "outcome, end_reason, provenance, started_at_ms, "
                            "ended_at_ms, added_at_ms, local_side) VALUES "
                            "('00000000-0000-7000-8000-000000000014', x'7b7d', '") +
                    kHex64 +
                    "', 'minixiangqi', 'nearby', 4, 'red-wins', 'resignation', "
                    "'locally-played', 1000, 2000, 3000, 'red');");

    /* A History record: insert, then verify everything but pin state is
     * immutable. */
    exec_ok(db, std::string("INSERT INTO game (game_id, archive, "
                            "content_sha256, rules_id, mode, move_count, "
                            "outcome, end_reason, provenance, started_at_ms, "
                            "ended_at_ms, added_at_ms) VALUES "
                            "('00000000-0000-7000-8000-000000000001', x'7b7d', '") +
                    kHex64 +
                    "', 'minixiangqi', 'free-play', 4, 'none', 'ended-early', "
                    "'locally-played', 1000, 2000, 3000);");
    exec_refused(db, "UPDATE game SET move_count = 5 WHERE game_id = "
                     "'00000000-0000-7000-8000-000000000001';",
                 "History content immutability");
    exec_ok(db, "UPDATE game SET pinned = 1 WHERE game_id = "
                "'00000000-0000-7000-8000-000000000001';");

    /* The archive-and-clear ordering. An active game, referenced by the
     * library: committing its outcome while still referenced must be refused;
     * after the reference clears it commits; and the cleared reference can
     * never be pointed at a committed game again. */
    exec_ok(db, std::string("INSERT INTO game (game_id, archive, "
                            "content_sha256, rules_id, mode, move_count, "
                            "provenance, started_at_ms) VALUES "
                            "('00000000-0000-7000-8000-000000000002', x'7b7d', '") +
                    kHex64 +
                    "', 'xiangqi', 'free-play', 0, 'locally-played', 1000);");
    exec_ok(db, "UPDATE library SET active_record_id = (SELECT record_id FROM "
                "game WHERE outcome IS NULL);");
    exec_refused(db,
                 "UPDATE game SET outcome = 'none', end_reason = "
                 "'ended-early', ended_at_ms = 2000, added_at_ms = 3000 "
                 "WHERE outcome IS NULL;",
                 "commit before the reference is cleared");
    exec_ok(db, "UPDATE library SET active_record_id = NULL;");
    exec_ok(db, "UPDATE game SET outcome = 'none', end_reason = "
                "'ended-early', ended_at_ms = 2000, added_at_ms = 3000 "
                "WHERE outcome IS NULL;");
    exec_refused(db,
                 "UPDATE library SET active_record_id = (SELECT record_id "
                 "FROM game WHERE game_id = "
                 "'00000000-0000-7000-8000-000000000002');",
                 "the reference must name an uncommitted game");
    sqlite3_close(db);

    /* The store, with records in it, still opens. */
    err = make_error();
    rc = init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
    check(rc == MXQ_OK, std::string("reopen after direct writes failed: ") +
                            mxq_status_name(rc) + ": " + err.detail);
    if (rc == MXQ_OK) {
        mxq_core_shutdown(core, nullptr);
    }
}

void case_reopen_is_idempotent() {
    g_case = "close and reopen is idempotent";
    const fs::path dir = scratch_dir("reopen");

    for (int round = 0; round < 3; ++round) {
        MxqCore *core = nullptr;
        MxqError err = make_error();
        const MxqStatus rc =
            init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
        check(rc == MXQ_OK, "round " + std::to_string(round) +
                                ": mxq_core_init failed: " + err.detail);
        if (rc != MXQ_OK) {
            return;
        }
        mxq_core_shutdown(core, nullptr);
    }

    sqlite3 *db = open_direct(db_path(dir));
    if (db == nullptr) {
        return;
    }
    check_eq(query_text(db, "PRAGMA user_version;"), "5",
             "user_version unchanged after reopens");
    check_eq(query_text(db, "SELECT count(*) FROM library;"), "1",
             "still exactly one library row");
    check_eq(query_text(db, "SELECT count(*) FROM meta;"), "2",
             "the two bookkeeping rows were not re-inserted");
    check_eq(query_text(db, "SELECT value FROM meta WHERE "
                            "key='library_revision';"),
             "0", "reopening a library is not a mutation of it");
    sqlite3_close(db);
}

void case_newer_schema_is_refused() {
    g_case = "a newer schema version is refused";
    const fs::path dir = scratch_dir("newer");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    MxqStatus rc = init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
    check(rc == MXQ_OK, "mxq_core_init failed");
    if (rc != MXQ_OK) {
        return;
    }
    mxq_core_shutdown(core, nullptr);

    sqlite3 *db = open_direct(db_path(dir));
    if (db == nullptr) {
        return;
    }
    exec_ok(db, "PRAGMA user_version = 6;");
    sqlite3_close(db);

    err = make_error();
    rc = init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
    check(rc == MXQ_ERR_STORE_SCHEMA_TOO_NEW,
          std::string("expected MXQ_ERR_STORE_SCHEMA_TOO_NEW, got ") +
              mxq_status_name(rc));
    check(mxq_status_domain(rc) == MXQ_DOMAIN_STORE,
          "the refusal is store-domain");
    check(core == nullptr || rc != MXQ_OK, "no core was created");

    /* The refusal is version-driven and nothing else: winding the version
     * back makes the same file open again. */
    db = open_direct(db_path(dir));
    if (db == nullptr) {
        return;
    }
    exec_ok(db, "PRAGMA user_version = 5;");
    sqlite3_close(db);

    err = make_error();
    rc = init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
    check(rc == MXQ_OK, "the store opens again once the version is current");
    if (rc == MXQ_OK) {
        mxq_core_shutdown(core, nullptr);
    }
}

/*
 * The other side of the version comparison. One version is defined, nothing
 * migrates into it, and a store recording a schema this build has no path to is
 * refused — which is the whole of what happens to it. The file is left exactly
 * as it is: the core does not destroy data it cannot read, and a user who wants
 * the app to start again removes the store themselves.
 *
 * The version written below is deliberately not the one any release used: what
 * is under test is the comparison, and a test naming a particular older shape
 * would be the only thing in the repository that did.
 */
void case_older_schema_is_refused() {
    g_case = "a schema below this build's is refused, and the file is left";
    const fs::path dir = scratch_dir("older");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    MxqStatus rc = init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
    check(rc == MXQ_OK, "mxq_core_init failed");
    if (rc != MXQ_OK) {
        return;
    }
    mxq_core_shutdown(core, nullptr);

    /* A record in the file, so that "left as it is" is observable rather than
     * asserted, and a version this build has no path to. */
    sqlite3 *db = open_direct(db_path(dir));
    if (db == nullptr) {
        return;
    }
    exec_ok(db, std::string("INSERT INTO game (game_id, archive, "
                            "content_sha256, rules_id, mode, move_count, "
                            "outcome, end_reason, provenance, started_at_ms, "
                            "ended_at_ms, added_at_ms) VALUES "
                            "('00000000-0000-7000-8000-000000000021', x'7b7d', '") +
                    kHex64 +
                    "', 'minixiangqi', 'free-play', 4, 'none', 'ended-early', "
                    "'locally-played', 1000, 2000, 3000);");
    exec_ok(db, "PRAGMA user_version = 1;");
    sqlite3_close(db);

    err = make_error();
    rc = init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
    check(rc == MXQ_ERR_STORE_MIGRATION_FAILED,
          std::string("expected MXQ_ERR_STORE_MIGRATION_FAILED, got ") +
              mxq_status_name(rc));
    check(mxq_status_domain(rc) == MXQ_DOMAIN_STORE,
          "the refusal is store-domain");
    check(rc != MXQ_ERR_STORE_SCHEMA_TOO_NEW,
          "and is not the newer-build answer, which is a different fact");
    check(core == nullptr || rc != MXQ_OK, "no core was created");

    /* Nothing about the file changed: the version it records, the record it
     * holds, and the file itself are all still there. */
    check(fs::exists(db_path(dir)), "the store file is still there");
    db = open_direct(db_path(dir));
    if (db == nullptr) {
        return;
    }
    check_eq(query_text(db, "PRAGMA user_version;"), "1",
             "the refusal did not rewrite the recorded version");
    check_eq(query_text(db, "SELECT count(*) FROM game;"), "1",
             "and the record the store held is still in it");
    sqlite3_close(db);
}

void case_unopenable_store_fails_init() {
    g_case = "an unopenable store fails init";
    const fs::path dir = scratch_dir("unopenable");

    /* A regular file where a directory component must go. */
    const fs::path blocker = dir / "blocker";
    {
        FILE *f = std::fopen(blocker.string().c_str(), "w");
        check(f != nullptr, "cannot arrange the blocking file");
        if (f != nullptr) {
            std::fclose(f);
        }
    }
    const std::string bad_dir = (blocker / "store").string();

    MxqCore *core = nullptr;
    MxqError err = make_error();
    const MxqStatus rc = init_core(bad_dir, MXQ_CORE_FLAG_NONE, &core, &err);
    check(rc != MXQ_OK, "init must fail");
    check(mxq_status_domain(rc) == MXQ_DOMAIN_STORE,
          std::string("the failure is store-domain, got ") +
              mxq_status_name(rc));
    check(core == nullptr, "no core handle was produced");
}

void case_deterministic_identity_repeats() {
    g_case = "deterministic identity repeats across lifetimes";
    const fs::path dir = scratch_dir("deterministic");

    /* The exact sequences MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY documents in
     * mxq.h. Asserting the literal values pins the documentation, not merely
     * self-consistency. */
    const std::vector<std::string> want_ids = {
        "019b76da-a800-7000-8000-000000000000",
        "019b76da-a801-7000-8000-000000000001",
        "019b76da-a802-7000-8000-000000000002",
    };
    const std::vector<int64_t> want_times = {
        1767225600000, 1767225601000, 1767225602000};

    std::vector<std::string> first_ids;
    for (int lifetime = 0; lifetime < 2; ++lifetime) {
        MxqCore *core = nullptr;
        MxqError err = make_error();
        const MxqStatus rc = init_core(
            dir.string(), MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err);
        check(rc == MXQ_OK, "mxq_core_init failed: " + std::string(err.detail));
        if (rc != MXQ_OK) {
            return;
        }

        /* Interleaved on purpose: the identifier counter and the clock are
         * documented as independent sequences. */
        std::vector<std::string> ids;
        std::vector<int64_t> times;
        for (int i = 0; i < 3; ++i) {
            times.push_back(core->identity.now_ms());
            ids.push_back(core->identity.next_game_id());
        }
        const std::string label = "lifetime " + std::to_string(lifetime);
        for (int i = 0; i < 3; ++i) {
            check_eq(ids[static_cast<size_t>(i)],
                     want_ids[static_cast<size_t>(i)],
                     label + ": id " + std::to_string(i));
            check(times[static_cast<size_t>(i)] ==
                      want_times[static_cast<size_t>(i)],
                  label + ": time " + std::to_string(i) + " is " +
                      std::to_string(times[static_cast<size_t>(i)]));
        }
        if (lifetime == 0) {
            first_ids = ids;
        } else {
            check(ids == first_ids,
                  "the two lifetimes produced identical id sequences");
        }
        mxq_core_shutdown(core, nullptr);
    }
}

bool looks_like_uuid_v7(const std::string &id) {
    if (id.size() != 36) {
        return false;
    }
    for (size_t i = 0; i < id.size(); ++i) {
        const char c = id[i];
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (c != '-') {
                return false;
            }
        } else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
            return false;
        }
    }
    return id[14] == '7' &&
           (id[19] == '8' || id[19] == '9' || id[19] == 'a' || id[19] == 'b');
}

void case_production_identity_is_real() {
    g_case = "without the flag, identity is real";
    const fs::path dir = scratch_dir("production");

    std::vector<std::string> ids;
    for (int lifetime = 0; lifetime < 2; ++lifetime) {
        MxqCore *core = nullptr;
        MxqError err = make_error();
        const MxqStatus rc =
            init_core(dir.string(), MXQ_CORE_FLAG_NONE, &core, &err);
        check(rc == MXQ_OK, "mxq_core_init failed");
        if (rc != MXQ_OK) {
            return;
        }
        ids.push_back(core->identity.next_game_id());
        ids.push_back(core->identity.next_game_id());

        const int64_t now = core->identity.now_ms();
        check(now > 1767225600000 && now < 4102444800000,
              "now_ms reads a real clock (got " + std::to_string(now) + ")");
        mxq_core_shutdown(core, nullptr);
    }

    for (const std::string &id : ids) {
        check(looks_like_uuid_v7(id), "well-formed lowercase v7 UUID: " + id);
        check(id != "019b76da-a800-7000-8000-000000000000",
              "a production id is not the deterministic sequence");
    }
    for (size_t i = 0; i < ids.size(); ++i) {
        for (size_t j = i + 1; j < ids.size(); ++j) {
            check(ids[i] != ids[j], "production ids differ (" + ids[i] + ")");
        }
    }
}

} /* namespace */

int main() {
    std::cout << "Mini Xiangqi store-foundation tests\n";

    case_fresh_open_creates_schema();
    case_schema_enforces_its_invariants();
    case_reopen_is_idempotent();
    case_newer_schema_is_refused();
    case_older_schema_is_refused();
    case_unopenable_store_fails_init();
    case_deterministic_identity_repeats();
    case_production_identity_is_real();

    if (g_failures == 0) {
        std::cout << "  all store-foundation checks passed\n";
        return 0;
    }
    std::cout << "  " << g_failures << " check(s) failed\n";
    return 1;
}
