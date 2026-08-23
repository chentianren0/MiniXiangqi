/*
 * The History runner: the four ways a game ends, and the library they leave
 * behind.
 *
 * Two kinds of case, as the session runner has:
 *
 *   - the scenarios in fixtures/store/terminal/, which are data — a
 *     configuration, a move line, the ending that closes it, and the golden it
 *     must reproduce — so a fifth ending is a new file and never a new
 *     function here;
 *   - named cases for what is a property of the library rather than of a game:
 *     the ordering, the pagination boundaries, the revision counter, the
 *     single-active invariant across an archiving, and the three hardening
 *     paths the sessions verify asked for.
 *
 * Most of it runs through the public C surface only. Two things are reached
 * through the core's internal headers on purpose, both already established by
 * the session runner: the clock and identity provider, to place a game at the
 * identity a golden was minted with and to give two games the same
 * History-added instant; and a second SQLite connection, used to take the
 * database's write lock so that an archiving transaction fails for the reason
 * a real one would, and to tamper with a row so that the corruption paths are
 * driven by damage rather than by a seam.
 *
 * Without MXQ_ENABLE_RULES_FACADE a game cannot be played, so no History
 * record can be made and every case that needs one reports NOT IMPLEMENTED,
 * which is never counted as a pass. What still runs there is the empty
 * library: mxq_store_history_count, mxq_store_history_page and the revision
 * are pure store queries and answer in both configurations.
 */

#include "mxq.h"

#include "mxq_json.hpp"

#if MXQ_TEST_RULES_FACADE
#include "mxq_core_state.hpp" /* internal, deliberately: the identity provider */
#include "sqlite3.h"
#endif

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <vector>

namespace fs = std::filesystem;

#ifndef MXQ_TEST_RULES_FACADE
#define MXQ_TEST_RULES_FACADE 0
#endif

namespace {

int g_passed = 0;
int g_failed = 0;
int g_skipped = 0;
int g_checks = 0;

/* The one skip the closing banner speaks for, matched by value. Two things skip
 * here and they are two different absences: this one, and a scenario of a game
 * only a build with the second engine carries. A banner that fired on the total
 * announced that endings were missing from a build that had them, which is a
 * report about the build that is not true of it. */
const char *const kNoFacade = "ending a game needs the rules facade";
int g_skipped_no_facade = 0;

/* ---------------------------------------------------------------------- */
/* One case's verdict                                                      */
/* ---------------------------------------------------------------------- */

struct Case {
    std::string              name;
    std::vector<std::string> messages;
    std::string              skip_reason;

    explicit Case(std::string n) : name(std::move(n)) {}

    void skip(const std::string &why) { skip_reason = why; }

    void check(bool ok, const std::string &what) {
        ++g_checks;
        if (!ok) {
            messages.push_back(what);
        }
    }

    void check_eq(const std::string &got, const std::string &want,
                  const std::string &what) {
        check(got == want,
              what + ": expected \"" + want + "\", got \"" + got + "\"");
    }

    void check_eq(int64_t got, int64_t want, const std::string &what) {
        check(got == want, what + ": expected " + std::to_string(want) +
                               ", got " + std::to_string(got));
    }

    void check_status(MxqStatus got, MxqStatus want, const std::string &what) {
        check(got == want, what + ": expected " +
                               std::string(mxq_status_name(want)) + ", got " +
                               std::string(mxq_status_name(got)));
    }

    void report() {
        if (!messages.empty()) {
            ++g_failed;
            std::cout << "  FAIL      " << name << "\n";
            for (const std::string &m : messages) {
                std::cout << "            " << m << "\n";
            }
            return;
        }
        if (!skip_reason.empty()) {
            ++g_skipped;
            if (skip_reason == kNoFacade) {
                ++g_skipped_no_facade;
            }
            std::cout << "  SKIP      " << name << "  (" << skip_reason << ")\n";
            return;
        }
        ++g_passed;
        std::cout << "  PASS      " << name << "\n";
    }
};

/* ---------------------------------------------------------------------- */
/* Scaffolding                                                             */
/* ---------------------------------------------------------------------- */

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

MxqRecordSummary make_summary() {
    MxqRecordSummary s;
    std::memset(&s, 0, sizeof(s));
    s.struct_size = static_cast<uint32_t>(sizeof(s));
    return s;
}

#if MXQ_TEST_RULES_FACADE
/* Only a build that can play a game needs these: without the facade the one
 * case that runs never reaches a position, a status or a configuration. */
MxqGameStatus make_status() {
    MxqGameStatus s;
    std::memset(&s, 0, sizeof(s));
    s.struct_size = static_cast<uint32_t>(sizeof(s));
    return s;
}

MxqPosition make_position() {
    MxqPosition p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = static_cast<uint32_t>(sizeof(p));
    return p;
}

MxqGameConfig make_config() {
    MxqGameConfig c;
    std::memset(&c, 0, sizeof(c));
    c.struct_size = static_cast<uint32_t>(sizeof(c));
    c.mode = MXQ_PLAY_MODE_FREE_PLAY;
    c.human_side = MXQ_COLOR_NONE;
    c.ai_level = MXQ_AI_LEVEL_NONE;
    c.first_mover_choice = MXQ_FIRST_MOVER_NONE;
    c.ai_movetime_ms = 0;
    c.local_side = MXQ_COLOR_NONE;
    return c;
}
#endif /* MXQ_TEST_RULES_FACADE */

fs::path scratch_root() {
    static const fs::path root = [] {
        std::random_device rd;
        char token[17];
        std::snprintf(token, sizeof(token), "%08x%08x", rd(), rd());
        return fs::temp_directory_path() /
               ("minixiangqi-history-tests-" + std::string(token));
    }();
    return root;
}

fs::path scratch_dir(const std::string &name) {
    const fs::path dir = scratch_root() / name;
    std::error_code ec;
    fs::remove_all(dir, ec);
    fs::create_directories(dir, ec);
    return dir;
}

MxqStatus init_core(const fs::path &store_dir, uint32_t flags, MxqCore **out,
                    MxqError *err) {
    const std::string assets = assets_dir();
    const std::string store = store_dir.string();
    MxqCoreConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.api_major = MXQ_API_VERSION_MAJOR;
    config.api_minor = MXQ_API_VERSION_MINOR;
    config.api_patch = MXQ_API_VERSION_PATCH;
    config.flags = flags;
    config.store_directory = store.c_str();
    config.asset_directory = assets.c_str();
    return mxq_core_init(&config, out, err);
}

/* ---------------------------------------------------------------------- */
/* The empty library, which needs no engine                                */
/* ---------------------------------------------------------------------- */

void case_empty_library() {
    Case c("an empty library counts, pages and reports its revision");
    const fs::path store = scratch_dir("empty");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }

    uint8_t exists = 1;
    err = make_error();
    c.check_status(mxq_store_active_exists(core, &exists, &err), MXQ_OK,
                   "mxq_store_active_exists");
    c.check_eq(exists, 0, "a fresh library holds no active game");

    uint32_t count = 99;
    uint64_t revision = 99;
    err = make_error();
    c.check_status(mxq_store_history_count(core, &count, &revision, &err),
                   MXQ_OK, "mxq_store_history_count");
    c.check_eq(count, 0, "a fresh library has no History records");
    c.check_eq(static_cast<int64_t>(revision), 0,
               "a fresh library is at revision 0");

    /* A page of an empty library writes nothing and is not an error, whether
     * it is asked for from the start or from past the end. */
    std::vector<MxqRecordSummary> page(4, make_summary());
    size_t written = 99;
    err = make_error();
    c.check_status(mxq_store_history_page(core, 0, 4, page.data(), page.size(),
                                          &written, &revision, &err),
                   MXQ_OK, "a page of an empty library");
    c.check_eq(static_cast<int64_t>(written), 0, "nothing was written");
    err = make_error();
    c.check_status(mxq_store_history_page(core, 10, 4, page.data(), page.size(),
                                          &written, &revision, &err),
                   MXQ_OK, "a page past the end of an empty library");
    c.check_eq(static_cast<int64_t>(written), 0, "nothing was written");

    /* And an identifier no record ever had is not found rather than empty. */
    MxqRecordSummary summary = make_summary();
    err = make_error();
    c.check_status(mxq_store_history_get(core, 1, &summary, &err),
                   MXQ_ERR_STORE_NOT_FOUND, "mxq_store_history_get on nothing");
    err = make_error();
    c.check_status(mxq_store_history_set_pinned(core, 1, 1, &err),
                   MXQ_ERR_STORE_NOT_FOUND, "pinning nothing");
    err = make_error();
    c.check_status(mxq_store_history_delete(core, 1, &err),
                   MXQ_ERR_STORE_NOT_FOUND, "deleting nothing");

    err = make_error();
    c.check_status(mxq_store_history_count(core, &count, &revision, &err),
                   MXQ_OK, "mxq_store_history_count again");
    c.check_eq(static_cast<int64_t>(revision), 0,
               "a refused mutation is not a mutation");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

#if MXQ_TEST_RULES_FACADE

/* ---------------------------------------------------------------------- */
/* Small readers                                                           */
/* ---------------------------------------------------------------------- */

bool read_file(const fs::path &path, std::string &out) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return false;
    }
    out.assign(std::istreambuf_iterator<char>(in),
               std::istreambuf_iterator<char>());
    return true;
}

std::string encode_of(MxqCore *core, const MxqGame *game, Case &c,
                      const std::string &where) {
    MxqBlob *blob = nullptr;
    MxqError err = make_error();
    const MxqStatus rc = mxq_archive_encode(core, game, &blob, &err);
    c.check(rc == MXQ_OK, where + ": mxq_archive_encode failed: " +
                              std::string(mxq_status_name(rc)) + ": " +
                              err.detail);
    if (rc != MXQ_OK) {
        return std::string();
    }
    const std::string bytes(
        reinterpret_cast<const char *>(mxq_blob_bytes(blob)),
        mxq_blob_len(blob));
    mxq_blob_release(blob);
    return bytes;
}

uint64_t revision_of(MxqCore *core, Case &c, const std::string &where) {
    uint32_t count = 0;
    uint64_t revision = 0;
    MxqError err = make_error();
    const MxqStatus rc =
        mxq_store_history_count(core, &count, &revision, &err);
    c.check(rc == MXQ_OK, where + ": mxq_store_history_count failed: " +
                              std::string(mxq_status_name(rc)));
    return revision;
}

uint32_t count_of(MxqCore *core, Case &c, const std::string &where) {
    uint32_t count = 0;
    uint64_t revision = 0;
    MxqError err = make_error();
    const MxqStatus rc =
        mxq_store_history_count(core, &count, &revision, &err);
    c.check(rc == MXQ_OK, where + ": mxq_store_history_count failed: " +
                              std::string(mxq_status_name(rc)));
    return count;
}

std::vector<MxqRecordSummary> page_of(MxqCore *core, uint32_t offset,
                                      uint32_t limit, Case &c,
                                      const std::string &where) {
    std::vector<MxqRecordSummary> page(limit == 0 ? 1 : limit, make_summary());
    size_t written = 0;
    uint64_t revision = 0;
    MxqError err = make_error();
    const MxqStatus rc = mxq_store_history_page(core, offset, limit,
                                                page.data(), limit, &written,
                                                &revision, &err);
    c.check(rc == MXQ_OK, where + ": mxq_store_history_page failed: " +
                              std::string(mxq_status_name(rc)) + ": " +
                              err.detail);
    page.resize(rc == MXQ_OK ? written : 0);
    return page;
}

std::string state_text(MxqGameState state) {
    switch (state) {
    case MXQ_GAME_ONGOING: return "ongoing";
    case MXQ_GAME_CLAIMABLE_DRAW: return "claimable-draw";
    case MXQ_GAME_RED_WINS: return "red-wins";
    case MXQ_GAME_BLACK_WINS: return "black-wins";
    case MXQ_GAME_DRAW: return "draw";
    default: break;
    }
    return "unknown(" + std::to_string(state) + ")";
}

std::string outcome_text(MxqOutcome outcome) {
    switch (outcome) {
    case MXQ_OUTCOME_NONE: return "none";
    case MXQ_OUTCOME_RED_WINS: return "red-wins";
    case MXQ_OUTCOME_BLACK_WINS: return "black-wins";
    case MXQ_OUTCOME_DRAW: return "draw";
    default: break;
    }
    return "unknown(" + std::to_string(outcome) + ")";
}

std::string reason_text(MxqEndReason reason) {
    switch (reason) {
    case MXQ_END_REASON_NONE: return "null";
    case MXQ_END_REASON_CHECKMATE: return "checkmate";
    case MXQ_END_REASON_STALEMATE: return "stalemate";
    case MXQ_END_REASON_THREEFOLD_REPETITION: return "threefold-repetition";
    case MXQ_END_REASON_PERPETUAL_CHECK: return "perpetual-check";
    case MXQ_END_REASON_PERPETUAL_CHASE: return "perpetual-chase";
    case MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK: return "mutual-perpetual-check";
    case MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE: return "mutual-perpetual-chase";
    case MXQ_END_REASON_RESIGNATION: return "resignation";
    case MXQ_END_REASON_ENDED_EARLY: return "ended-early";
    case MXQ_END_REASON_FIFTY_MOVE_RULE: return "fifty-move-rule";
    case MXQ_END_REASON_AGREED_DRAW: return "agreed-draw";
    case MXQ_END_REASON_MUTUAL_RESIGNATION: return "mutual-resignation";
    case MXQ_END_REASON_FIVE_IN_A_ROW: return "five-in-a-row";
    case MXQ_END_REASON_BOARD_FULL: return "board-full";
    default: break;
    }
    return "unknown(" + std::to_string(reason) + ")";
}

/*
 * The index a deterministic identifier carries: the counter is spelled in the
 * final 62 bits, so the last group of the UUID is it. Advancing the provider
 * to that index is how a golden minted as the corpus's fourth game can be
 * reproduced by a run that would otherwise mint its first.
 */
bool advance_identity_to(MxqCore *core, const std::string &game_id,
                         std::string &error) {
    const size_t dash = game_id.rfind('-');
    if (dash == std::string::npos) {
        error = "the golden's game_id is not a UUID";
        return false;
    }
    const unsigned long long index =
        std::strtoull(game_id.substr(dash + 1).c_str(), nullptr, 16);
    if (index > 1024) {
        error = "the golden's identity index is implausibly far along";
        return false;
    }
    for (unsigned long long i = 0; i < index; ++i) {
        core->identity.next_game_id();
    }
    return true;
}

/* ---------------------------------------------------------------------- */
/* Locking and tampering, through a second connection                      */
/* ---------------------------------------------------------------------- */

sqlite3 *open_second_connection(const fs::path &store) {
    sqlite3 *db = nullptr;
    const std::string path = (store / "library.sqlite3").string();
    if (sqlite3_open_v2(path.c_str(), &db, SQLITE_OPEN_READWRITE, nullptr) !=
        SQLITE_OK) {
        sqlite3_close(db);
        return nullptr;
    }
    return db;
}

bool run_sql(sqlite3 *db, const char *sql) {
    return sqlite3_exec(db, sql, nullptr, nullptr, nullptr) == SQLITE_OK;
}

/* One query's first column, as text. Reading the database directly is how a
 * case asks what the store actually holds rather than what its own API says it
 * holds. */
std::string query_text(sqlite3 *db, const std::string &sql) {
    sqlite3_stmt *stmt = nullptr;
    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        return "<prepare failed>";
    }
    std::string value = "<no row>";
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *text = sqlite3_column_text(stmt, 0);
        value = text != nullptr ? reinterpret_cast<const char *>(text) : "";
    }
    sqlite3_finalize(stmt);
    return value;
}

/* ---------------------------------------------------------------------- */
/* Playing a scenario's move line                                          */
/* ---------------------------------------------------------------------- */

struct Ending {
    std::string action;
    std::string archive;
    std::string outcome;
    std::string end_reason;
    std::string state;
    /* The two members mxq_game_commit_nearby_end takes beyond the handle: which
     * of the protocol's explicit ends the two players reached, and — for the one
     * that names a side — which side resigned. */
    std::string reason;
    std::string resigning_side;
};

struct Scenario {
    std::string              title;
    MxqGameConfig            config = make_config();
    std::vector<std::string> moves;
    Ending                   end;
    /* The deal the scenario's game was dealt, where it has one. It belongs to a
     * game rather than to a mode — only the dealt game has one — and a scenario
     * that states it is created over the wire session those four values arrive
     * in; see the session runner, whose schema this shares. */
    std::string              deal_commit;
    std::string              deal_nonce;
    std::string              deal_seed;
    std::string              deal_digest;
    /* Whether the scenario's game is one only a build with the second engine
     * carries; see the session runner's own note. */
    bool                     needs_gomoku = false;
};

/* The wire session a dealt scenario is created over: a session at its birth,
 * carrying the deal and the two identifiers nothing compares. */
MxqNearbySession nearby_session_of(const Scenario &scenario) {
    MxqNearbySession wire;
    std::memset(&wire, 0, sizeof(wire));
    wire.struct_size = static_cast<uint32_t>(sizeof(wire));
    wire.proposer = MXQ_NEARBY_PROPOSER_LOCAL;
    wire.sent_end = MXQ_NEARBY_TERMINAL_NONE;
    const char *const session_id = "session-of-the-dealt-ending";
    const char *const peer_id = "peer-of-the-dealt-ending";
    std::memcpy(wire.session_id, session_id, std::strlen(session_id) + 1);
    std::memcpy(wire.peer_id, peer_id, std::strlen(peer_id) + 1);
    std::memcpy(wire.deal_commit, scenario.deal_commit.c_str(), 65);
    std::memcpy(wire.deal_nonce, scenario.deal_nonce.c_str(), 65);
    std::memcpy(wire.deal_seed, scenario.deal_seed.c_str(), 65);
    std::memcpy(wire.deal_digest, scenario.deal_digest.c_str(), 65);
    return wire;
}

/* Creation, through whichever door the scenario's game needs. */
MxqStatus create_scenario_game(MxqCore *core, const Scenario &scenario,
                               MxqGame **out_game, MxqError *err) {
    if (scenario.deal_commit.empty()) {
        return mxq_game_create(core, &scenario.config, out_game, err);
    }
    const MxqNearbySession wire = nearby_session_of(scenario);
    return mxq_game_create_nearby(core, &scenario.config, &wire, out_game, err);
}

bool read_scenario(const fs::path &path, Scenario &out, std::string &error) {
    std::string text;
    if (!read_file(path, text)) {
        error = "cannot read " + path.string();
        return false;
    }
    mxqtest::JsonValue root;
    if (!mxqtest::json_parse(text, root, error)) {
        return false;
    }
    if (!root.is_object()) {
        error = "the scenario is not a JSON object";
        return false;
    }

    const mxqtest::JsonValue *title = root.member("title");
    out.title = title != nullptr && title->is_string() ? title->string()
                                                       : path.stem().string();

    const mxqtest::JsonValue *config = root.member("config");
    if (config == nullptr || !config->is_object()) {
        error = "the scenario has no \"config\" object";
        return false;
    }
    const mxqtest::JsonValue *mode = config->member("mode");
    if (mode == nullptr || !mode->is_string()) {
        error = "\"config.mode\" is missing";
        return false;
    }
    if (mode->string() == "human-vs-ai") {
        out.config.mode = MXQ_PLAY_MODE_HUMAN_VS_AI;
        const mxqtest::JsonValue *side = config->member("human_side");
        const mxqtest::JsonValue *level = config->member("ai_level");
        const mxqtest::JsonValue *movetime = config->member("ai_movetime_ms");
        const mxqtest::JsonValue *first = config->member("first_mover_choice");
        if (side == nullptr || level == nullptr || movetime == nullptr ||
            first == nullptr) {
            error = "a human-versus-AI scenario states all four configuration "
                    "members";
            return false;
        }
        out.config.human_side =
            side->string() == "red" ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
        out.config.ai_level = level->string() == "fast" ? MXQ_AI_LEVEL_FAST
                              : level->string() == "standard"
                                  ? MXQ_AI_LEVEL_STANDARD
                                  : MXQ_AI_LEVEL_DEEP;
        out.config.ai_movetime_ms = static_cast<uint32_t>(movetime->number());
        out.config.first_mover_choice =
            first->string() == "human-first"  ? MXQ_FIRST_MOVER_HUMAN_FIRST
            : first->string() == "ai-first"   ? MXQ_FIRST_MOVER_AI_FIRST
                                              : MXQ_FIRST_MOVER_RANDOM;
    } else if (mode->string() == "nearby" || mode->string() == "online") {
        out.config.mode = mode->string() == "nearby" ? MXQ_PLAY_MODE_NEARBY
                                                     : MXQ_PLAY_MODE_ONLINE;
        /* Local perspective is store metadata rather than archive content, and
         * a networked game is played from one of the two sides of this device,
         * so a networked scenario states which. */
        const mxqtest::JsonValue *local = config->member("local_side");
        if (local == nullptr || !local->is_string() ||
            (local->string() != "red" && local->string() != "black")) {
            error = "a networked scenario states \"config.local_side\"";
            return false;
        }
        out.config.local_side =
            local->string() == "red" ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
    } else if (mode->string() != "free-play") {
        error = "\"config.mode\" is not one of the four accepted modes";
        return false;
    }

    /* The game the scenario is of. Required rather than defaulted: a scenario
     * that did not say would be played under whichever game the runner
     * happened to pick, which is the one thing a two-game corpus must not do. */
    /* The position the game begins from, where the scenario names one. Absent
     * is the game's frozen start, exactly as the empty member is on the other
     * side of the interface — and a game that has no frozen start always names
     * one, because there is a start of it for every deal. */
    if (const mxqtest::JsonValue *start = config->member("start_fen")) {
        if (!start->is_string() ||
            start->string().size() >= sizeof(out.config.start_fen)) {
            error = "\"config.start_fen\" is not a start this interface carries";
            return false;
        }
        std::memcpy(out.config.start_fen, start->string().c_str(),
                    start->string().size() + 1);
    }

    {
        const mxqtest::JsonValue *game = config->member("game");
        if (game == nullptr || !game->is_string()) {
            error = "\"config.game\" is missing";
            return false;
        }
        if (game->string() == "minixiangqi") {
            out.config.game = MXQ_GAME_KIND_MINI_XIANGQI;
        } else if (game->string() == "xiangqi") {
            out.config.game = MXQ_GAME_KIND_XIANGQI;
        } else if (game->string() == "gomoku-15") {
            out.config.game = MXQ_GAME_KIND_GOMOKU_15;
            out.needs_gomoku = true;
        } else if (game->string() == "renju") {
            out.config.game = MXQ_GAME_KIND_RENJU;
            out.needs_gomoku = true;
        } else if (game->string() == "jieqi") {
            out.config.game = MXQ_GAME_KIND_JIEQI;
        } else {
            error = "\"config.game\" is not one of the accepted games";
            return false;
        }
    }

    if (const mxqtest::JsonValue *deal = root.member("deal")) {
        const auto value = [&](const char *name) {
            const mxqtest::JsonValue *v = deal->member(name);
            return v != nullptr && v->is_string() ? v->string() : std::string();
        };
        out.deal_commit = value("commit");
        out.deal_nonce = value("nonce");
        out.deal_seed = value("seed");
        out.deal_digest = value("digest");
        if (out.deal_commit.size() != 64 || out.deal_nonce.size() != 64 ||
            out.deal_seed.size() != 64 || out.deal_digest.size() != 64) {
            error = "a scenario's \"deal\" states four 64-digit values";
            return false;
        }
    }

    if (const mxqtest::JsonValue *moves = root.member("moves")) {
        for (const mxqtest::JsonValue &move : moves->array()) {
            out.moves.push_back(move.string());
        }
    }

    const mxqtest::JsonValue *end = root.member("end");
    if (end == nullptr || !end->is_object()) {
        error = "the scenario has no \"end\" object";
        return false;
    }
    const auto member = [&](const char *name) {
        const mxqtest::JsonValue *v = end->member(name);
        return v != nullptr && v->is_string() ? v->string() : std::string();
    };
    out.end.action = member("action");
    out.end.archive = member("archive");
    out.end.outcome = member("outcome");
    out.end.end_reason = member("end_reason");
    out.end.state = member("state");
    out.end.reason = member("reason");
    out.end.resigning_side = member("resigning_side");
    if (out.end.action.empty()) {
        error = "the scenario's \"end\" states no action";
        return false;
    }
    if (out.end.action == "commit_nearby_end" && out.end.reason.empty()) {
        error = "a nearby ending states which end the two players reached";
        return false;
    }
    return true;
}

/* The one call a scenario's ending names. */
MxqStatus perform_ending(const Ending &end, MxqCore *core, MxqGame *game,
                         uint64_t *out_record_id, MxqError *err) {
    if (end.action == "claim_draw") {
        return mxq_game_claim_draw(game, out_record_id, err);
    }
    if (end.action == "resign") {
        return mxq_game_resign(game, out_record_id, err);
    }
    if (end.action == "confirm_result") {
        return mxq_game_confirm_result(game, out_record_id, err);
    }
    if (end.action == "commit_nearby_end") {
        const MxqEndReason reason =
            end.reason == "resignation"        ? MXQ_END_REASON_RESIGNATION
            : end.reason == "mutual-resignation"
                ? MXQ_END_REASON_MUTUAL_RESIGNATION
                : MXQ_END_REASON_AGREED_DRAW;
        const MxqColor side = end.resigning_side == "red"     ? MXQ_COLOR_RED
                              : end.resigning_side == "black" ? MXQ_COLOR_BLACK
                                                              : MXQ_COLOR_NONE;
        return mxq_game_commit_nearby_end(game, reason, side, out_record_id,
                                          err);
    }
    return mxq_store_archive_and_clear(core, game, out_record_id, err);
}

/* Every mutation an archived session must refuse, and the status it owes. */
void check_archived_refuses_everything(Case &c, MxqCore *core, MxqGame *game,
                                       const std::string &where) {
    struct Refusal {
        const char *name;
        MxqStatus   status;
    };
    uint64_t record_id = 0;
    uint32_t removed = 0;
    const Refusal refusals[] = {
        {"mxq_game_apply_move",
         mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr)},
        {"mxq_game_undo", mxq_game_undo(game, &removed, nullptr)},
        {"mxq_game_claim_draw",
         mxq_game_claim_draw(game, &record_id, nullptr)},
        {"mxq_game_resign", mxq_game_resign(game, &record_id, nullptr)},
        {"mxq_game_confirm_result",
         mxq_game_confirm_result(game, &record_id, nullptr)},
        {"mxq_game_commit_nearby_end",
         mxq_game_commit_nearby_end(game, MXQ_END_REASON_AGREED_DRAW,
                                    MXQ_COLOR_NONE, &record_id, nullptr)},
        {"mxq_store_archive_and_clear",
         mxq_store_archive_and_clear(core, game, &record_id, nullptr)},
    };
    for (const Refusal &refusal : refusals) {
        c.check(refusal.status == MXQ_ERR_STATE_SESSION_ARCHIVED,
                where + ": " + refusal.name +
                    " on an archived session is MXQ_ERR_STATE_SESSION_ARCHIVED,"
                    " got " +
                    std::string(mxq_status_name(refusal.status)));
    }
    c.check_eq(removed, 0, where + ": a refused undo removes nothing");
    c.check_eq(static_cast<int64_t>(record_id), 0,
               where + ": a refused ending yields no record id");
}

/* Every query an archived or detached session must still answer, with no
 * affordance left on the table. */
void check_queries_still_answer(Case &c, MxqGame *game, size_t move_count,
                                const std::string &state,
                                const std::string &where) {
    MxqPosition position = make_position();
    MxqError err = make_error();
    c.check_status(mxq_game_position(game, &position, &err), MXQ_OK,
                   where + ": mxq_game_position");
    c.check_eq(position.ply_count, static_cast<int64_t>(move_count),
               where + ": the ply count");

    MxqGameStatus status = make_status();
    err = make_error();
    c.check_status(mxq_game_status(game, &status, &err), MXQ_OK,
                   where + ": mxq_game_status");
    c.check_eq(state_text(status.state), state, where + ": the replayed state");
    c.check_eq(status.claim_available, 0, where + ": claim_available");
    c.check_eq(status.undo_available, 0, where + ": undo_available");
    c.check_eq(status.undo_plies, 0, where + ": undo_plies");
    c.check_eq(status.resign_available, 0, where + ": resign_available");
    c.check_eq(status.search_expected, 0, where + ": search_expected");

    MxqGameConfig config = make_config();
    err = make_error();
    c.check_status(mxq_game_config(game, &config, &err), MXQ_OK,
                   where + ": mxq_game_config");

    char id[MXQ_GAME_ID_CAP];
    size_t len = 0;
    err = make_error();
    c.check_status(mxq_game_id(game, id, sizeof(id), &len, &err), MXQ_OK,
                   where + ": mxq_game_id");
    c.check_eq(static_cast<int64_t>(len), 36, where + ": the identity's length");

    size_t count = 0;
    err = make_error();
    const MxqStatus history =
        mxq_game_move_history(game, nullptr, 0, &count, &err);
    c.check(move_count == 0 ? history == MXQ_OK
                            : history == MXQ_ERR_ARG_BUFFER_TOO_SMALL,
            where + ": mxq_game_move_history reports its count");
    c.check_eq(static_cast<int64_t>(count), static_cast<int64_t>(move_count),
               where + ": the retained line's length");

    MxqPosition initial = make_position();
    err = make_error();
    c.check_status(mxq_game_position_at(game, 0, &initial, &err), MXQ_OK,
                   where + ": mxq_game_position_at(0)");
}

/* The record a scenario's ending must have left in History. */
void check_record(Case &c, const MxqRecordSummary &record,
                  const Scenario &scenario, uint64_t record_id,
                  const std::string &game_id, const std::string &where) {
    c.check_eq(static_cast<int64_t>(record.record_id),
               static_cast<int64_t>(record_id), where + ": record_id");
    c.check_eq(std::string(record.game_id), game_id, where + ": game_id");
    c.check_eq(static_cast<int64_t>(record.move_count),
               static_cast<int64_t>(scenario.moves.size()),
               where + ": move_count");
    c.check_eq(outcome_text(record.outcome), scenario.end.outcome,
               where + ": outcome");
    c.check_eq(reason_text(record.end_reason), scenario.end.end_reason,
               where + ": end_reason");
    c.check_eq(record.game, scenario.config.game, where + ": game");
    c.check_eq(record.mode, scenario.config.mode, where + ": mode");
    c.check_eq(record.human_side, scenario.config.human_side,
               where + ": human_side");
    c.check_eq(record.ai_level, scenario.config.ai_level, where + ": ai_level");
    c.check_eq(record.ai_movetime_ms, scenario.config.ai_movetime_ms,
               where + ": ai_movetime_ms");
    c.check_eq(record.provenance, MXQ_PROVENANCE_LOCALLY_PLAYED,
               where + ": provenance");
    c.check_eq(record.pinned, 0, where + ": a new record is unpinned");
    c.check_eq(record.is_active, 0, where + ": a History record is not active");
    c.check(record.added_at_ms > 0,
            where + ": a History record has a History-added time");
    c.check(record.ended_at_ms == record.added_at_ms,
            where + ": the game ended and entered History at one instant");
    c.check(record.ended_at_ms >= record.started_at_ms,
            where + ": it did not end before it started");
}

/* ---------------------------------------------------------------------- */
/* The scenario: one ending, end to end                                    */
/* ---------------------------------------------------------------------- */

void run_scenario(const fs::path &path, const fs::path &archives) {
    Scenario scenario;
    std::string error;
    Case c(path.stem().string());
    if (!read_scenario(path, scenario, error)) {
        c.check(false, "cannot read the scenario: " + error);
        c.report();
        return;
    }
    c.name = path.stem().string() + " — " + scenario.title;

#if !MXQ_TEST_GOMOKU_FACADE
    if (scenario.needs_gomoku) {
        c.skip("the placement games need the second engine");
        c.report();
        return;
    }
#endif

    std::string golden;
    if (!scenario.end.archive.empty() &&
        !read_file(archives / "valid" / scenario.end.archive, golden)) {
        c.check(false, "cannot read the golden " + scenario.end.archive);
        c.report();
        return;
    }

    const fs::path store = scratch_dir(path.stem().string());

    MxqCore *core = nullptr;
    MxqError err = make_error();
    MxqStatus rc = init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core,
                             &err);
    c.check(rc == MXQ_OK, std::string("mxq_core_init failed: ") + err.detail);
    if (rc != MXQ_OK) {
        c.report();
        return;
    }

    if (!golden.empty()) {
        const size_t at = golden.find("\"game_id\":\"");
        if (at == std::string::npos ||
            !advance_identity_to(core, golden.substr(at + 11, 36), error)) {
            c.check(false, "cannot align the identity sequence: " + error);
            mxq_core_shutdown(core, nullptr);
            c.report();
            return;
        }
    }

    /* ---- play the line ---- */
    MxqGame *game = nullptr;
    err = make_error();
    rc = create_scenario_game(core, scenario, &game, &err);
    c.check(rc == MXQ_OK, std::string("mxq_game_create failed: ") +
                              mxq_status_name(rc) + ": " + err.detail);
    if (rc != MXQ_OK) {
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }
    for (size_t i = 0; i < scenario.moves.size(); ++i) {
        err = make_error();
        rc = mxq_game_apply_move(game, scenario.moves[i].c_str(), nullptr,
                                 nullptr, &err);
        c.check(rc == MXQ_OK, "move " + std::to_string(i) + " (" +
                                  scenario.moves[i] + ") was refused: " +
                                  std::string(mxq_status_name(rc)) + ": " +
                                  err.detail);
        if (rc != MXQ_OK) {
            mxq_game_release(game);
            mxq_core_shutdown(core, nullptr);
            c.report();
            return;
        }
    }

    char id_buffer[MXQ_GAME_ID_CAP];
    size_t id_len = 0;
    mxq_game_id(game, id_buffer, sizeof(id_buffer), &id_len, nullptr);
    const std::string game_id(id_buffer);
    const std::string active_bytes = encode_of(core, game, c, "before the end");
    const uint64_t revision_before = revision_of(core, c, "before the end");

    MxqGameStatus before = make_status();
    mxq_game_status(game, &before, nullptr);
    c.check_eq(state_text(before.state), scenario.end.state,
               "the state the ending is classified from");

    /* ---- the ending ---- */
    uint64_t record_id = 0;
    err = make_error();
    rc = perform_ending(scenario.end, core, game, &record_id, &err);
    c.check(rc == MXQ_OK, "the ending was refused: " +
                              std::string(mxq_status_name(rc)) + ": " +
                              err.detail);
    if (rc != MXQ_OK) {
        mxq_game_release(game);
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }
    c.check(record_id > 0, "the ending returns the new record's identifier");
    c.check(revision_of(core, c, "after the ending") > revision_before,
            "the ending bumped the library revision");

    /* ---- the session afterwards ---- */
    check_archived_refuses_everything(c, core, game, "archived");
    check_queries_still_answer(c, game, scenario.moves.size(),
                               scenario.end.state, "archived");

    const std::string finished = encode_of(core, game, c, "archived");
    c.check(finished != active_bytes,
            "the finished document is not the active one");
    if (!golden.empty()) {
        c.check_eq(finished, golden,
                   "the archived session is the golden " + scenario.end.archive);
    }

    /* ---- the library afterwards ---- */
    uint8_t exists = 1;
    err = make_error();
    c.check_status(mxq_store_active_exists(core, &exists, &err), MXQ_OK,
                   "mxq_store_active_exists");
    c.check_eq(exists, 0, "the library holds no active game");

    exists = 1;
    err = make_error();
    MxqRecordSummary active = make_summary();
    MxqGameStatus active_status = make_status();
    c.check_status(mxq_store_active_summary(core, &active, &active_status,
                                            &exists, &err),
                   MXQ_OK, "mxq_store_active_summary");
    c.check_eq(exists, 0, "there is no active summary to report");

    c.check_eq(count_of(core, c, "after the ending"), 1,
               "History holds exactly the archived game");

    MxqRecordSummary record = make_summary();
    err = make_error();
    c.check_status(mxq_store_history_get(core, record_id, &record, &err),
                   MXQ_OK, "mxq_store_history_get");
    check_record(c, record, scenario, record_id, game_id, "the record");

    const std::vector<MxqRecordSummary> page =
        page_of(core, 0, 8, c, "after the ending");
    c.check_eq(static_cast<int64_t>(page.size()), 1, "the page holds one row");
    if (page.size() == 1) {
        c.check_eq(static_cast<int64_t>(page[0].record_id),
                   static_cast<int64_t>(record_id),
                   "the page holds the archived game");
    }

    /* ---- and a new game may be created, because the old one is filed ---- */
    MxqGameConfig fresh = make_config();
    MxqGame *next = nullptr;
    uint64_t next_record = 0;
    err = make_error();
    c.check_status(mxq_game_create(core, &fresh, &next, &err), MXQ_OK,
                   "a new game may be created once the old one is filed");
    if (next != nullptr) {
        err = make_error();
        c.check_status(
            mxq_store_archive_and_clear(core, next, &next_record, &err), MXQ_OK,
            "and filed in its turn");
        c.check(next_record > record_id,
                "record identifiers are never reused");
        mxq_game_release(next);
        err = make_error();
        c.check_status(mxq_store_history_delete(core, next_record, &err),
                       MXQ_OK, "the second record is deleted again");
    }

    mxq_game_release(game);
    game = nullptr;
    mxq_core_shutdown(core, nullptr);
    core = nullptr;

    /* ---- across a relaunch ---- */
    err = make_error();
    rc = init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err);
    c.check(rc == MXQ_OK, std::string("reopening the store failed: ") +
                              err.detail);
    if (rc != MXQ_OK) {
        c.report();
        return;
    }

    uint8_t resumed_exists = 1;
    MxqGame *resumed = reinterpret_cast<MxqGame *>(0x1);
    err = make_error();
    c.check_status(mxq_game_resume_active(core, &resumed, &resumed_exists, &err),
                   MXQ_OK, "mxq_game_resume_active after the ending");
    c.check_eq(resumed_exists, 0, "there is nothing left to resume");
    c.check(resumed == nullptr, "and no session was produced");

    MxqRecordSummary after_reopen = make_summary();
    err = make_error();
    c.check_status(mxq_store_history_get(core, record_id, &after_reopen, &err),
                   MXQ_OK, "the record survives the relaunch");
    check_record(c, after_reopen, scenario, record_id, game_id,
                 "the record after the relaunch");

    /* ---- opened for replay ---- */
    MxqGame *replay = nullptr;
    err = make_error();
    rc = mxq_store_history_open(core, record_id, &replay, &err);
    c.check(rc == MXQ_OK, std::string("mxq_store_history_open failed: ") +
                              mxq_status_name(rc) + ": " + err.detail);
    if (rc == MXQ_OK) {
        check_queries_still_answer(c, replay, scenario.moves.size(),
                                   scenario.end.state, "replay");

        char replay_id[MXQ_GAME_ID_CAP];
        size_t replay_len = 0;
        mxq_game_id(replay, replay_id, sizeof(replay_id), &replay_len, nullptr);
        c.check_eq(std::string(replay_id), game_id,
                   "the replay is the same game");

        const std::string replayed_bytes =
            encode_of(core, replay, c, "replay");
        c.check_eq(replayed_bytes, finished,
                   "the replay encodes to the record's own bytes");

        MxqArchiveInfo info;
        std::memset(&info, 0, sizeof(info));
        info.struct_size = static_cast<uint32_t>(sizeof(info));
        err = make_error();
        c.check_status(
            mxq_archive_validate(
                core, reinterpret_cast<const uint8_t *>(replayed_bytes.data()),
                replayed_bytes.size(), &info, &err),
            MXQ_OK, "the archived bytes validate");
        c.check_eq(outcome_text(info.outcome), scenario.end.outcome,
                   "the validated outcome");
        c.check_eq(reason_text(info.end_reason), scenario.end.end_reason,
                   "the validated end reason");

#if defined(NDEBUG)
        /* A replay is read-only, and every mutation says so. A mutation on a
         * detached session is one of the programming errors the contract has
         * assert in a debug build, so the returned status is only a promise
         * where that assertion is compiled out; asking for it in a debug build
         * would be asking the core to break its own rule. */
        uint32_t removed = 0;
        uint64_t ignored = 0;
        const MxqStatus refusals[] = {
            mxq_game_apply_move(replay, "b1b3", nullptr, nullptr, nullptr),
            mxq_game_undo(replay, &removed, nullptr),
            mxq_game_claim_draw(replay, &ignored, nullptr),
            mxq_game_resign(replay, &ignored, nullptr),
            mxq_game_confirm_result(replay, &ignored, nullptr),
            mxq_store_archive_and_clear(core, replay, &ignored, nullptr),
        };
        for (const MxqStatus refusal : refusals) {
            c.check(refusal == MXQ_ERR_STATE_SESSION_READ_ONLY,
                    std::string("a mutation on a replay is "
                                "MXQ_ERR_STATE_SESSION_READ_ONLY, got ") +
                        mxq_status_name(refusal));
        }
#endif
        mxq_game_release(replay);
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/* ---------------------------------------------------------------------- */
/* Cases that are properties of the library                                */
/* ---------------------------------------------------------------------- */

/*
 * A failing ending, on every one of the four paths, driven through the store's
 * own transaction: a second connection holds the database's write lock, so
 * BEGIN IMMEDIATE inside the archiving is refused as SQLITE_BUSY exactly as a
 * real contended write would be. Nothing sleeps, and no seam in the core
 * arranges it.
 *
 * What must be true afterwards is the whole of docs/game-data.md's sentence
 * about it: the game remains active and unchanged, no History record exists,
 * and the same call succeeds once the store is free — which is what makes the
 * accepted 无法保存对局 retry a retry rather than a second chance at a
 * different outcome.
 */
void case_a_failed_ending_is_retryable(const std::vector<fs::path> &paths) {
    Case c("a failed ending leaves the game active, unchanged and retryable");

    for (const fs::path &path : paths) {
        Scenario scenario;
        std::string error;
        if (!read_scenario(path, scenario, error)) {
            c.check(false, "cannot read the scenario: " + error);
            continue;
        }
        const std::string what = path.stem().string();
#if !MXQ_TEST_GOMOKU_FACADE
        /* The same skip run_scenario makes, and for the same reason: a game
         * this build does not carry has no session to fail an ending on, so
         * driving one here would report the absent engine as a broken retry. */
        if (scenario.needs_gomoku) {
            continue;
        }
#endif
        const fs::path store = scratch_dir("retry-" + what);

        MxqCore *core = nullptr;
        MxqError err = make_error();
        if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core,
                      &err) != MXQ_OK) {
            c.check(false, what + ": mxq_core_init failed");
            continue;
        }
        MxqGame *game = nullptr;
        err = make_error();
        if (create_scenario_game(core, scenario, &game, &err) != MXQ_OK) {
            c.check(false, what + ": mxq_game_create failed");
            mxq_core_shutdown(core, nullptr);
            continue;
        }
        for (const std::string &move : scenario.moves) {
            mxq_game_apply_move(game, move.c_str(), nullptr, nullptr, nullptr);
        }
        const std::string before_bytes = encode_of(core, game, c, what);
        const uint64_t before_revision = revision_of(core, c, what);
        MxqGameStatus before = make_status();
        mxq_game_status(game, &before, nullptr);

        sqlite3 *blocker = open_second_connection(store);
        c.check(blocker != nullptr, what + ": the second connection opens");
        if (blocker == nullptr) {
            mxq_game_release(game);
            mxq_core_shutdown(core, nullptr);
            continue;
        }
        c.check(run_sql(blocker, "BEGIN EXCLUSIVE;"),
                what + ": the second connection takes the write lock");

        uint64_t refused_id = 99;
        err = make_error();
        const MxqStatus refused =
            perform_ending(scenario.end, core, game, &refused_id, &err);
        c.check(mxq_status_domain(refused) == MXQ_DOMAIN_STORE,
                what + ": an ending that cannot commit fails in the store "
                       "domain, got " +
                    std::string(mxq_status_name(refused)));
        c.check_eq(static_cast<int64_t>(refused_id), 0,
                   what + ": a failed ending yields no record id");
        c.check_eq(encode_of(core, game, c, what + " after the failure"),
                   before_bytes,
                   what + ": the game is exactly at its pre-ending committed "
                          "state");

        MxqGameStatus after = make_status();
        err = make_error();
        c.check_status(mxq_game_status(game, &after, &err), MXQ_OK,
                       what + ": the session still answers");
        c.check(after.undo_available == before.undo_available &&
                    after.claim_available == before.claim_available &&
                    after.resign_available == before.resign_available,
                what + ": a failed ending withdraws no affordance");

        c.check(run_sql(blocker, "ROLLBACK;"), what + ": the lock is released");
        sqlite3_close(blocker);

        c.check_eq(count_of(core, c, what), 0,
                   what + ": no History record exists");
        c.check_eq(static_cast<int64_t>(revision_of(core, c, what)),
                   static_cast<int64_t>(before_revision),
                   what + ": a failed ending is not a mutation");

        /* The same call, on the same game, now succeeds: what failed was the
         * commit and not the ending. */
        uint64_t record_id = 0;
        err = make_error();
        const MxqStatus retried =
            perform_ending(scenario.end, core, game, &record_id, &err);
        c.check(retried == MXQ_OK,
                what + ": the same ending commits once the store is free, got " +
                    std::string(mxq_status_name(retried)) + ": " + err.detail);
        c.check(record_id > 0, what + ": and it returns a record id");
        c.check_eq(count_of(core, c, what + " after the retry"), 1,
                   what + ": History holds exactly one record");

        MxqRecordSummary record = make_summary();
        err = make_error();
        if (mxq_store_history_get(core, record_id, &record, &err) == MXQ_OK) {
            c.check_eq(outcome_text(record.outcome), scenario.end.outcome,
                       what + ": the retried ending recorded the same outcome");
            c.check_eq(reason_text(record.end_reason), scenario.end.end_reason,
                       what + ": and the same reason");
        }

        mxq_game_release(game);
        mxq_core_shutdown(core, nullptr);
    }

    c.report();
}

/* Create a game, play it, and file it. Returns the new record's identifier. */
uint64_t play_and_file(MxqCore *core, const MxqGameConfig &config,
                       const std::vector<std::string> &moves, Case &c,
                       const std::string &where) {
    MxqGameConfig local = config;
    MxqGame *game = nullptr;
    MxqError err = make_error();
    MxqStatus rc = mxq_game_create(core, &local, &game, &err);
    c.check(rc == MXQ_OK, where + ": mxq_game_create failed: " +
                              std::string(mxq_status_name(rc)) + ": " +
                              err.detail);
    if (rc != MXQ_OK) {
        return 0;
    }
    for (const std::string &move : moves) {
        err = make_error();
        rc = mxq_game_apply_move(game, move.c_str(), nullptr, nullptr, &err);
        c.check(rc == MXQ_OK, where + ": " + move + " was refused: " +
                                  std::string(mxq_status_name(rc)));
    }
    uint64_t record_id = 0;
    err = make_error();
    rc = mxq_store_archive_and_clear(core, game, &record_id, &err);
    c.check(rc == MXQ_OK, where + ": mxq_store_archive_and_clear failed: " +
                              std::string(mxq_status_name(rc)) + ": " +
                              err.detail);
    mxq_game_release(game);
    return record_id;
}

void case_archive_and_clear_without_a_game() {
    Case c("archive-and-clear with nothing to archive");
    const fs::path store = scratch_dir("nothing-to-archive");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    /* No session at all: the one required pointer is the active game, so its
     * absence is a state rather than a programming error. */
    uint64_t record_id = 99;
    err = make_error();
    c.check_status(mxq_store_archive_and_clear(core, nullptr, &record_id, &err),
                   MXQ_ERR_STATE_ACTIVE_GAME_MISSING,
                   "archiving no game at all");
    c.check_eq(static_cast<int64_t>(record_id), 0, "no record id was produced");
    c.check_eq(count_of(core, c, "after the refusal"), 0,
               "nothing entered History");

    /* And a session that has already been archived is archived, not missing:
     * the two are different facts and the caller can tell them apart. */
    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    err = make_error();
    mxq_game_create(core, &config, &game, &err);
    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);
    err = make_error();
    c.check_status(mxq_store_archive_and_clear(core, game, &record_id, &err),
                   MXQ_OK, "the first archiving");
    err = make_error();
    c.check_status(mxq_store_archive_and_clear(core, game, &record_id, &err),
                   MXQ_ERR_STATE_SESSION_ARCHIVED, "the second archiving");
    c.check_eq(count_of(core, c, "after the second"), 1,
               "History holds one record, not two");

    mxq_game_release(game);
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_endings_refuse_where_they_do_not_apply() {
    Case c("each ending refuses where its own rule does not hold");
    const fs::path store = scratch_dir("refusals");

    /* The status this PR appends is in the state domain and names itself, so a
     * frontend routing by domain and a log naming the code both work before
     * anything returns it. */
    c.check_eq(std::string(mxq_status_name(MXQ_ERR_STATE_CONFIRM_UNAVAILABLE)),
               "MXQ_ERR_STATE_CONFIRM_UNAVAILABLE",
               "the appended status names itself");
    c.check_eq(mxq_status_domain(MXQ_ERR_STATE_CONFIRM_UNAVAILABLE),
               MXQ_DOMAIN_STATE, "and reports the state domain");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    /* Free Play, one move: ongoing. */
    MxqGameConfig free_play = make_config();
    MxqGame *game = nullptr;
    err = make_error();
    mxq_game_create(core, &free_play, &game, &err);
    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);
    const std::string bytes = encode_of(core, game, c, "before the refusals");
    const uint64_t revision = revision_of(core, c, "before the refusals");

    uint64_t record_id = 99;
    err = make_error();
    c.check_status(mxq_game_claim_draw(game, &record_id, &err),
                   MXQ_ERR_STATE_CLAIM_UNAVAILABLE,
                   "claiming a draw with no repetition to claim");
    err = make_error();
    c.check_status(mxq_game_resign(game, &record_id, &err),
                   MXQ_ERR_STATE_RESIGN_UNAVAILABLE,
                   "resigning in Free Play");
    err = make_error();
    c.check_status(mxq_game_confirm_result(game, &record_id, &err),
                   MXQ_ERR_STATE_CONFIRM_UNAVAILABLE,
                   "confirming a result an ongoing game does not have");
    c.check_eq(static_cast<int64_t>(record_id), 0,
               "no refusal produced a record id");
    c.check_eq(encode_of(core, game, c, "after the refusals"), bytes,
               "the game is untouched by every refusal");
    c.check_eq(static_cast<int64_t>(revision_of(core, c, "after the refusals")),
               static_cast<int64_t>(revision),
               "a refused ending is not a mutation");
    c.check_eq(count_of(core, c, "after the refusals"), 0,
               "and nothing entered History");

    /* The claimable repetition is not a result to confirm: the game continues
     * there unless the claim is made, and confirming is the other decision. */
    for (const char *move : {"b7b5", "b3b1", "b5b7", "b1b3", "b7b5", "b3b1",
                             "b5b7"}) {
        mxq_game_apply_move(game, move, nullptr, nullptr, nullptr);
    }
    MxqGameStatus claimable = make_status();
    mxq_game_status(game, &claimable, nullptr);
    c.check_eq(state_text(claimable.state), "claimable-draw",
               "the line reaches a claimable repetition");
    err = make_error();
    c.check_status(mxq_game_confirm_result(game, &record_id, &err),
                   MXQ_ERR_STATE_CONFIRM_UNAVAILABLE,
                   "confirming a claimable repetition");

    /* File it, so the next game may be created. An unclaimed claimable
     * repetition is still an ongoing game, so it is recorded as ended early
     * rather than as the draw nobody claimed. */
    uint64_t filed = 0;
    err = make_error();
    c.check_status(mxq_store_archive_and_clear(core, game, &filed, &err),
                   MXQ_OK, "the unclaimed repetition is filed");
    MxqRecordSummary unclaimed = make_summary();
    err = make_error();
    mxq_store_history_get(core, filed, &unclaimed, &err);
    c.check_eq(outcome_text(unclaimed.outcome), "none",
               "an unclaimed repetition records no competitive result");
    c.check_eq(reason_text(unclaimed.end_reason), "ended-early",
               "it is recorded as ended early rather than as a draw");
    mxq_game_release(game);

    /* Human versus AI, mated: resignation would overwrite a result the game
     * really has, and the claim has nothing to claim. */
    MxqGameConfig human = make_config();
    human.mode = MXQ_PLAY_MODE_HUMAN_VS_AI;
    human.human_side = MXQ_COLOR_RED;
    human.ai_level = MXQ_AI_LEVEL_STANDARD;
    human.first_mover_choice = MXQ_FIRST_MOVER_HUMAN_FIRST;
    human.ai_movetime_ms = MXQ_MOVETIME_STANDARD_MS;
    MxqGame *mated = nullptr;
    err = make_error();
    c.check_status(mxq_game_create(core, &human, &mated, &err), MXQ_OK,
                   "the human-versus-AI game is created");
    for (const char *move : {"b1b3", "a6a5", "b3d3"}) {
        mxq_game_apply_move(mated, move, nullptr, nullptr, nullptr);
    }
    MxqGameStatus over = make_status();
    mxq_game_status(mated, &over, nullptr);
    c.check_eq(state_text(over.state), "red-wins", "the line is a checkmate");
    c.check_eq(over.resign_available, 0,
               "resignation is withdrawn once the game has a result");

    err = make_error();
    c.check_status(mxq_game_resign(mated, &record_id, &err),
                   MXQ_ERR_STATE_RESIGN_UNAVAILABLE,
                   "resigning a game that already has a result");
    err = make_error();
    c.check_status(mxq_game_claim_draw(mated, &record_id, &err),
                   MXQ_ERR_STATE_CLAIM_UNAVAILABLE,
                   "claiming a draw in a mated position");
    /* An agreed ending is a nearby action, and a mode check precedes the
     * position: this game has both a result of its own and nobody to agree
     * with, and the answer names the one that decides it. */
    err = make_error();
    c.check_status(mxq_game_commit_nearby_end(mated, MXQ_END_REASON_AGREED_DRAW,
                                              MXQ_COLOR_NONE, &record_id, &err),
                   MXQ_ERR_STATE_RESIGN_UNAVAILABLE,
                   "an agreed ending in a game with one player");

    /* File it, so the next game may be created: one active game spans every
     * mode as well as both games. */
    err = make_error();
    c.check_status(mxq_game_confirm_result(mated, &filed, &err), MXQ_OK,
                   "the mated game is confirmed and filed");
    mxq_game_release(mated);

    /* Nearby, mated: the protocol's precedence rule says an end the rules
     * decided outranks one the players declared, so every explicit ending is
     * refused over a position that already has a result. */
    MxqGameConfig nearby = make_config();
    nearby.mode = MXQ_PLAY_MODE_NEARBY;
    nearby.local_side = MXQ_COLOR_BLACK;
    MxqGame *decided = nullptr;
    err = make_error();
    c.check_status(mxq_game_create(core, &nearby, &decided, &err), MXQ_OK,
                   "the nearby game is created");
    for (const char *move : {"b1b3", "a6a5", "b3d3"}) {
        mxq_game_apply_move(decided, move, nullptr, nullptr, nullptr);
    }
    MxqGameStatus nearby_over = make_status();
    mxq_game_status(decided, &nearby_over, nullptr);
    c.check_eq(state_text(nearby_over.state), "red-wins",
               "the nearby line is a checkmate too");
    c.check_eq(nearby_over.undo_available, 0,
               "a nearby game offers no unilateral undo");
    c.check_eq(nearby_over.resign_available, 0,
               "and mxq_game_resign's affordance stays human-versus-AI's");

    const struct {
        const char  *what;
        MxqEndReason reason;
        MxqColor     side;
    } declared[] = {
        {"a resignation", MXQ_END_REASON_RESIGNATION, MXQ_COLOR_BLACK},
        {"a mutual resignation", MXQ_END_REASON_MUTUAL_RESIGNATION,
         MXQ_COLOR_NONE},
        {"an agreed draw", MXQ_END_REASON_AGREED_DRAW, MXQ_COLOR_NONE},
    };
    for (const auto &declaration : declared) {
        err = make_error();
        c.check_status(mxq_game_commit_nearby_end(decided, declaration.reason,
                                                  declaration.side, &record_id,
                                                  &err),
                       MXQ_ERR_STATE_GAME_OVER,
                       std::string(declaration.what) +
                           " over a decided position");
    }
    c.check_eq(static_cast<int64_t>(record_id), 0,
               "no refused ending produced a record id");

    /* mxq_game_undo is not the nearby retraction, and refuses rather than
     * removing a ply the two players did not agree to drop. */
    uint32_t removed = 7;
    err = make_error();
    c.check_status(mxq_game_undo(decided, &removed, &err),
                   MXQ_ERR_STATE_UNDO_UNAVAILABLE,
                   "undoing a nearby game unilaterally");
    c.check_eq(removed, 0, "and it removes nothing");

    /* File it, so the boundary case below may create its own game. */
    err = make_error();
    c.check_status(mxq_game_confirm_result(decided, &filed, &err), MXQ_OK,
                   "the decided nearby game is confirmed and filed");
    mxq_game_release(decided);

    /*
     * The other side of that boundary: a claimable neutral repetition is not a
     * result — the game continues there unless the claim is made — so an end
     * the two players declared is lawful over it and commits the draw they
     * declared rather than the one nobody claimed.
     */
    MxqGame *claimable_nearby = nullptr;
    err = make_error();
    c.check_status(mxq_game_create(core, &nearby, &claimable_nearby, &err),
                   MXQ_OK, "the second nearby game is created");
    for (const char *move : {"b1b3", "b7b5", "b3b1", "b5b7", "b1b3", "b7b5",
                             "b3b1", "b5b7"}) {
        mxq_game_apply_move(claimable_nearby, move, nullptr, nullptr, nullptr);
    }
    MxqGameStatus repeated = make_status();
    mxq_game_status(claimable_nearby, &repeated, nullptr);
    c.check_eq(state_text(repeated.state), "claimable-draw",
               "the nearby line reaches a claimable repetition");

    uint64_t agreed = 0;
    err = make_error();
    c.check_status(mxq_game_commit_nearby_end(claimable_nearby,
                                              MXQ_END_REASON_AGREED_DRAW,
                                              MXQ_COLOR_NONE, &agreed, &err),
                   MXQ_OK, "an agreed draw over a claimable repetition");
    MxqRecordSummary agreed_record = make_summary();
    err = make_error();
    mxq_store_history_get(core, agreed, &agreed_record, &err);
    c.check_eq(outcome_text(agreed_record.outcome), "draw",
               "which records a draw");
    c.check_eq(reason_text(agreed_record.end_reason), "agreed-draw",
               "and records that the players agreed it, not that one claimed "
               "the repetition");
    mxq_game_release(claimable_nearby);

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * The wire session a nearby game is played over, from its birth to its death.
 *
 * It is one row, keyed on the active game, and everything about it is a
 * question of *when* it is written and when it is gone: created with the game
 * in one transaction, carried unchanged by an ordinary ply, moved with the move
 * line by the negotiated retraction, rewritten on its own by the one change the
 * game does not share, read back by a resume, and deleted — explicitly, because
 * archiving updates the game row in place and no cascade fires there — when the
 * game files.
 */
void case_the_wire_session_lives_with_its_game() {
    Case c("a nearby game's wire session is created, carried, and filed away");
    const fs::path store = scratch_dir("wire-session");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, 0, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqGameConfig config = make_config();
    config.mode = MXQ_PLAY_MODE_NEARBY;
    config.local_side = MXQ_COLOR_RED;

    MxqNearbySession birth;
    std::memset(&birth, 0, sizeof(birth));
    birth.struct_size = static_cast<uint32_t>(sizeof(birth));
    birth.proposer = MXQ_NEARBY_PROPOSER_LOCAL;
    std::snprintf(birth.session_id, sizeof(birth.session_id),
                  "6f1d9c22-2f5a-7c31-9a04-0c1f2e3d4b5a");
    std::snprintf(birth.peer_id, sizeof(birth.peer_id),
                  "wifi-aware-device-77E1B0C2");

    /* The Free Play configuration this case asks two questions with, declared
     * here rather than beside the first because the second is a build away. */
    MxqGameConfig local = make_config();

#if defined(NDEBUG)
    /* A session at birth has retracted, claimed and declared nothing, a wire
     * session belongs to a nearby game, and a session without an identifier is
     * not one the protocol carries. All three are programming errors the
     * contract has assert in a debug build, so the returned status is only a
     * promise where that assertion is compiled out. */
    MxqNearbySession used = birth;
    used.undos = 1;
    MxqGame *refused = nullptr;
    err = make_error();
    c.check_status(mxq_game_create_nearby(core, &config, &used, &refused, &err),
                   MXQ_ERR_ARG_RANGE,
                   "a nearby game created over a session that has retracted");
    used = birth;
    err = make_error();
    c.check_status(mxq_game_create_nearby(core, &local, &used, &refused, &err),
                   MXQ_ERR_ARG_RANGE, "a wire session over a Free Play game");
    used = birth;
    used.session_id[0] = '\0';
    err = make_error();
    c.check_status(mxq_game_create_nearby(core, &config, &used, &refused, &err),
                   MXQ_ERR_ARG_RANGE, "a wire session with no identifier");
#endif

    MxqGame *game = nullptr;
    err = make_error();
    c.check_status(mxq_game_create_nearby(core, &config, &birth, &game, &err),
                   MXQ_OK, "the nearby game and its wire session are created");
    c.check(game != nullptr, "the session handle exists");
    if (game == nullptr) {
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }

    sqlite3 *reader = open_second_connection(store);
    c.check(reader != nullptr, "a second connection reads the store");
    const auto row_count = [&](const char *what) {
        return reader == nullptr ? std::string("?")
                                 : query_text(reader, std::string("SELECT ") +
                                                          what +
                                                          " FROM nearby_session;");
    };
    c.check_eq(row_count("count(*)"), "1", "one wire session stands");
    c.check_eq(row_count("session_id"), std::string(birth.session_id),
               "keyed on the identifier the proposer minted");
    c.check_eq(row_count("proposer"), "local", "and on which peer proposed");
    c.check_eq(row_count("undos"), "0", "with nothing retracted");

    /* A ply carries the wire session it did not change. */
    err = make_error();
    c.check_status(
        mxq_game_apply_move(game, "b1b3", nullptr, nullptr, &err), MXQ_OK,
        "a ply lands");
    for (const char *move : {"b7b5", "b3b1"}) {
        mxq_game_apply_move(game, move, nullptr, nullptr, nullptr);
    }
    c.check_eq(row_count("undos"), "0", "which retracted nothing");
    c.check_eq(row_count("count(*)"), "1", "and left the one row standing");

    /* The negotiated retraction: the surviving line and the counts that
     * produced it, in one transaction. */
    MxqNearbySession retracted = birth;
    retracted.undos = 1;
    retracted.keep = 1;
    err = make_error();
    c.check_status(mxq_game_retract_nearby(game, 3, &retracted, &err),
                   MXQ_ERR_ARG_RANGE, "a retraction that keeps every ply");
    err = make_error();
    c.check_status(mxq_game_retract_nearby(game, 1, &retracted, &err), MXQ_OK,
                   "the two players' retraction");
    size_t count = 0;
    mxq_game_move_history(game, nullptr, 0, &count, nullptr);
    c.check_eq(static_cast<int64_t>(count), 1, "one ply survives");
    c.check_eq(row_count("undos"), "1", "and the retraction was counted");
    c.check_eq(row_count("keep"), "1", "beside the count it survived to");

    /* The one change the game does not share: a terminal this device sent,
     * which ends nothing until the resume exchange settles it. */
    MxqNearbySession sent = retracted;
    sent.sent_end = MXQ_NEARBY_TERMINAL_RESIGN;
#if defined(NDEBUG)
    /* A wire session's identity is frozen, and writing another's over it is a
     * programming error that asserts in a debug build, as above. */
    MxqNearbySession stranger = sent;
    std::snprintf(stranger.session_id, sizeof(stranger.session_id),
                  "00000000-0000-7000-8000-000000000000");
    err = make_error();
    c.check_status(mxq_game_set_nearby_session(game, &stranger, &err),
                   MXQ_ERR_ARG_RANGE,
                   "another session's bookkeeping written over this one's");
#endif
    err = make_error();
    c.check_status(mxq_game_set_nearby_session(game, &sent, &err), MXQ_OK,
                   "the terminal this device sent is recorded");
    c.check_eq(row_count("sent_end"), "resign", "and the store holds it");
    c.check_eq(row_count("count(*)"), "1", "still one row");

    /* What a relaunched application reads back. */
    mxq_game_release(game);
    game = nullptr;
    MxqGame *resumed = nullptr;
    uint8_t exists = 0;
    err = make_error();
    c.check_status(mxq_game_resume_active(core, &resumed, &exists, &err),
                   MXQ_OK, "the interrupted game resumes");
    c.check_eq(exists, 1, "and the library held one");
    MxqNearbySession read;
    std::memset(&read, 0, sizeof(read));
    read.struct_size = static_cast<uint32_t>(sizeof(read));
    uint8_t has_wire = 0;
    err = make_error();
    c.check_status(mxq_game_nearby_session(resumed, &read, &has_wire, &err),
                   MXQ_OK, "its wire session is read back");
    c.check_eq(has_wire, 1, "and there is one");
    c.check_eq(std::string(read.session_id), std::string(birth.session_id),
               "the session identifier survives a relaunch");
    c.check_eq(std::string(read.peer_id), std::string(birth.peer_id),
               "and the peer's device identity with it");
    c.check_eq(read.undos, 1, "the retraction count survives");
    c.check_eq(read.keep, 1, "and the count it survived to");
    c.check_eq(read.sent_end, MXQ_NEARBY_TERMINAL_RESIGN,
               "and the terminal this device had sent");
    c.check_eq(read.proposer, MXQ_NEARBY_PROPOSER_LOCAL,
               "and which peer proposed");
    MxqGameConfig resumed_config = make_config();
    mxq_game_config(resumed, &resumed_config, nullptr);
    c.check_eq(resumed_config.local_side, MXQ_COLOR_RED,
               "the mover comes back from local_side, not from a second copy");

    /* And it dies with the game. The commit updates the game row in place, so
     * nothing cascades: the deletion is the transaction's own statement. */
    uint64_t filed = 0;
    err = make_error();
    c.check_status(mxq_game_commit_nearby_end(resumed,
                                              MXQ_END_REASON_RESIGNATION,
                                              MXQ_COLOR_RED, &filed, &err),
                   MXQ_OK, "the reconciled resignation files the game");
    c.check_eq(row_count("count(*)"), "0",
               "and the filed game leaves no wire session behind");
    has_wire = 1;
    err = make_error();
    c.check_status(mxq_game_nearby_session(resumed, &read, &has_wire, &err),
                   MXQ_OK, "an archived session still answers");
    c.check_eq(has_wire, 0, "and carries no wire session either");
    err = make_error();
    c.check_status(mxq_game_set_nearby_session(resumed, &sent, &err),
                   MXQ_ERR_STATE_SESSION_ARCHIVED,
                   "writing a wire session over a filed game");
    mxq_game_release(resumed);

    /* A local game has none of this. */
    MxqGame *free_play = nullptr;
    err = make_error();
    c.check_status(mxq_game_create(core, &local, &free_play, &err), MXQ_OK,
                   "a Free Play game is created");
    has_wire = 1;
    err = make_error();
    c.check_status(mxq_game_nearby_session(free_play, &read, &has_wire, &err),
                   MXQ_OK, "and answers about a wire session");
    c.check_eq(has_wire, 0, "with none");
    err = make_error();
    c.check_status(mxq_game_retract_nearby(free_play, 0, &birth, &err),
                   MXQ_ERR_STATE_UNDO_UNAVAILABLE,
                   "a negotiated retraction of a game with one player");
    err = make_error();
    c.check_status(mxq_game_set_nearby_session(free_play, &birth, &err),
                   MXQ_ERR_STATE_RESIGN_UNAVAILABLE,
                   "and a wire session over one");
    err = make_error();
    c.check_status(mxq_store_archive_and_clear(core, free_play, &filed, &err),
                   MXQ_OK, "the Free Play game is archived to make room");
    mxq_game_release(free_play);

    /* The fifth archiving path takes the wire session too. An interrupted
     * nearby game the player files before starting something else is a game
     * that stopped: ended early, no competitive result, and nothing of the
     * session it was played over left behind. */
    MxqGame *interrupted = nullptr;
    err = make_error();
    c.check_status(mxq_game_create_nearby(core, &config, &birth, &interrupted,
                                          &err),
                   MXQ_OK, "an interrupted nearby game is created");
    mxq_game_apply_move(interrupted, "b1b3", nullptr, nullptr, nullptr);
    mxq_game_apply_move(interrupted, "b7b5", nullptr, nullptr, nullptr);
    c.check_eq(row_count("count(*)"), "1",
               "which is being played over a wire session");
    uint64_t stopped = 0;
    err = make_error();
    c.check_status(mxq_store_archive_and_clear(core, interrupted, &stopped,
                                               &err),
                   MXQ_OK, "and archive-and-clear files it");
    c.check_eq(row_count("count(*)"), "0",
               "in the transaction that took its wire session with it");
    MxqRecordSummary stopped_record = make_summary();
    err = make_error();
    mxq_store_history_get(core, stopped, &stopped_record, &err);
    c.check_eq(reason_text(stopped_record.end_reason), "ended-early",
               "recorded as the game that stopped");
    c.check_eq(outcome_text(stopped_record.outcome), "none",
               "with no competitive result");
    c.check_eq(stopped_record.local_side, MXQ_COLOR_RED,
               "and the local perspective it was played from");
    mxq_game_release(interrupted);

    /* The cascade, which is the second line of defence rather than the one
     * that fires at a filing: a game row that goes takes its wire session with
     * it, whatever removed it. */
    MxqGame *doomed = nullptr;
    err = make_error();
    c.check_status(mxq_game_create_nearby(core, &config, &birth, &doomed, &err),
                   MXQ_OK, "a third nearby game is created");
    mxq_game_release(doomed);
    if (reader != nullptr) {
        c.check_eq(query_text(reader, "SELECT count(*) FROM nearby_session;"),
                   "1", "with a wire session of its own");
        const std::string active =
            query_text(reader, "SELECT active_record_id FROM library;");
        c.check(run_sql(reader, "UPDATE library SET active_record_id = NULL;"),
                "the library reference is cleared");
        c.check(run_sql(reader, ("DELETE FROM game WHERE record_id = " + active +
                                 ";")
                                    .c_str()),
                "the game row is deleted directly");
        c.check_eq(query_text(reader, "SELECT count(*) FROM nearby_session;"),
                   "0", "and no wire session outlives its game");
        sqlite3_close(reader);
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * Online play is nearby play's twin everywhere the mode gates behaviour.
 *
 * The two networked modes differ in how the two devices reached each other and
 * in nothing this core is asked about, so the interesting claim is that every
 * rule keyed to a second player on the other end reads the same for both: the
 * creation door takes it, the store's constraints accept the row and its local
 * side, the unilateral undo stays withheld, the negotiated retraction and the
 * wire-session rewrite are legal, the agreed ending commits, the document that
 * comes out spells the mode it was played in, and a dealt game of it records
 * the deal its handshake produced.
 *
 * It is one case rather than a second copy of the nearby suite because what is
 * under test is the twinning and not the wire session, which
 * case_the_wire_session_lives_with_its_game already follows from birth to death.
 */
void case_online_is_nearbys_twin() {
    Case c("an online game is a nearby game in everything the mode decides");
    const fs::path store = scratch_dir("online-twin");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, 0, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqGameConfig config = make_config();
    config.mode = MXQ_PLAY_MODE_ONLINE;
    config.local_side = MXQ_COLOR_BLACK;

    MxqNearbySession birth;
    std::memset(&birth, 0, sizeof(birth));
    birth.struct_size = static_cast<uint32_t>(sizeof(birth));
    birth.proposer = MXQ_NEARBY_PROPOSER_PEER;
    std::snprintf(birth.session_id, sizeof(birth.session_id),
                  "0f2e4d6c-8a91-7b23-9c05-1d2e3f405162");
    std::snprintf(birth.peer_id, sizeof(birth.peer_id), "game-center-A4C19E70");

    /* The creation door: one entry for both networked modes, and the
     * configuration is what says which of them this game is. */
    MxqGame *game = nullptr;
    err = make_error();
    c.check_status(mxq_game_create_nearby(core, &config, &birth, &game, &err),
                   MXQ_OK, "an online game is created over its wire session");
    c.check(game != nullptr, "and the session handle exists");
    if (game == nullptr) {
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }

    sqlite3 *reader = open_second_connection(store);
    c.check(reader != nullptr, "a second connection reads the store");
    if (reader != nullptr) {
        c.check_eq(query_text(reader, "SELECT mode FROM game;"), "online",
                   "the row records the mode it was played in");
        c.check_eq(query_text(reader, "SELECT local_side FROM game;"), "black",
                   "and carries the local side networked play requires");
        c.check_eq(query_text(reader, "SELECT count(*) FROM nearby_session;"),
                   "1", "and the schema takes its wire session");
    }

    /* The withheld unilateral undo, which is the mode's rule and not the
     * transport's: what two players agreed to keep is the only retraction
     * either networked mode has. */
    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);
    mxq_game_apply_move(game, "b7b5", nullptr, nullptr, nullptr);
    MxqGameStatus status = make_status();
    err = make_error();
    mxq_game_status(game, &status, &err);
    c.check_eq(status.undo_available, 0, "an online game offers no undo");
    c.check_eq(status.undo_plies, 0, "and has no plies to take back");
    err = make_error();
    c.check_status(mxq_game_undo(game, nullptr, &err),
                   MXQ_ERR_STATE_UNDO_UNAVAILABLE,
                   "and refuses one asked for");

    /* And the three entries a wire session's game answers. */
    MxqNearbySession retracted = birth;
    retracted.undos = 1;
    retracted.keep = 1;
    err = make_error();
    c.check_status(mxq_game_retract_nearby(game, 1, &retracted, &err), MXQ_OK,
                   "the two players' retraction is legal on it");
    MxqNearbySession sent = retracted;
    sent.sent_end = MXQ_NEARBY_TERMINAL_ACCEPT_DRAW;
    err = make_error();
    c.check_status(mxq_game_set_nearby_session(game, &sent, &err), MXQ_OK,
                   "and so is recording the terminal this device sent");

    /* The agreed ending, which belongs to the modes with a player on the other
     * end and to no other. */
    uint64_t filed = 0;
    err = make_error();
    c.check_status(mxq_game_commit_nearby_end(game, MXQ_END_REASON_AGREED_DRAW,
                                              MXQ_COLOR_NONE, &filed, &err),
                   MXQ_OK, "the draw the two players agreed files the game");
    MxqRecordSummary record = make_summary();
    err = make_error();
    mxq_store_history_get(core, filed, &record, &err);
    c.check_eq(record.mode, MXQ_PLAY_MODE_ONLINE,
               "the History record names the mode truthfully");
    c.check_eq(outcome_text(record.outcome), "draw", "and records a draw");
    c.check_eq(reason_text(record.end_reason), "agreed-draw",
               "that the two players agreed");
    c.check_eq(record.local_side, MXQ_COLOR_BLACK,
               "with the local perspective it was played from");
    if (reader != nullptr) {
        c.check_eq(query_text(reader, "SELECT count(*) FROM nearby_session;"),
                   "0", "and the filed game leaves no wire session behind");
        sqlite3_close(reader);
    }
    mxq_game_release(game);

    /* The document, which is where the mode crosses to another device: the
     * archive spells it, and a reader gets back the mode that was written. */
    MxqGame *replay = nullptr;
    err = make_error();
    c.check_status(mxq_store_history_open(core, filed, &replay, &err), MXQ_OK,
                   "the record opens for replay");
    if (replay != nullptr) {
        const std::string document = encode_of(core, replay, c, "the record");
        c.check(document.find("\"mode\":\"online\"") != std::string::npos,
                "whose document spells the mode in the archive's vocabulary");
        MxqArchiveInfo info;
        std::memset(&info, 0, sizeof(info));
        info.struct_size = static_cast<uint32_t>(sizeof(info));
        err = make_error();
        c.check_status(
            mxq_archive_validate(
                core, reinterpret_cast<const uint8_t *>(document.data()),
                document.size(), &info, &err),
            MXQ_OK, "and validates");
        c.check_eq(info.mode, MXQ_PLAY_MODE_ONLINE,
                   "reading back the mode it was written in");
        mxq_game_release(replay);
    }

    /*
     * And the deal, which is the one thing the mode decides that a game of Mini
     * Xiangqi has nothing to say about. The writer and the reader each ask
     * whether this document is a dealt game's played over the wire, and each
     * asks it of the game *and* the mode; either of them narrowed back to nearby
     * alone would break this pair in opposite directions and both silently. A
     * writer that narrowed would omit the three members and produce a document
     * its own reader refuses; a reader that narrowed would refuse the three
     * members as evidence of a handshake this game supposedly never had.
     *
     * The deal is the corpus's own — the vector fixtures/store/jieqi-nearby-dealt
     * is built on, and the one case_a_retraction_may_not_rewrite_the_wire_session
     * uses — so the start here and the start there are one position rather than
     * two transcriptions.
     */
    const char *const kDealt =
        "r~r~c~b~kp~n~n~b~/9/1p~5a~1/c~1p~1p~1p~1a~/9/9/"
        "P~1P~1C~1B~1R~/1P~5B~1/9/C~A~P~N~KA~P~R~N~ w - - 0 1";

    MxqGameConfig dealt = make_config();
    dealt.game = MXQ_GAME_KIND_JIEQI;
    dealt.mode = MXQ_PLAY_MODE_ONLINE;
    dealt.local_side = MXQ_COLOR_RED;
    std::memcpy(dealt.start_fen, kDealt, std::strlen(kDealt) + 1);

    MxqNearbySession handshake;
    std::memset(&handshake, 0, sizeof(handshake));
    handshake.struct_size = static_cast<uint32_t>(sizeof(handshake));
    handshake.proposer = MXQ_NEARBY_PROPOSER_LOCAL;
    std::snprintf(handshake.session_id, sizeof(handshake.session_id),
                  "b7c3e1a4-9d20-7f68-8a15-2c3d4e5f6071");
    std::snprintf(handshake.peer_id, sizeof(handshake.peer_id),
                  "game-center-6D2F91B0");
    std::snprintf(handshake.deal_commit, sizeof(handshake.deal_commit), "%s",
                  "66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5"
                  "f2925");
    std::snprintf(handshake.deal_nonce, sizeof(handshake.deal_nonce), "%s",
                  "a14441000000000000000000000000000000000000000000000000000000"
                  "0000");
    std::snprintf(handshake.deal_seed, sizeof(handshake.deal_seed), "%s",
                  "00000000000000000000000000000000000000000000000000000000000"
                  "00000");
    std::snprintf(handshake.deal_digest, sizeof(handshake.deal_digest), "%s",
                  "98ec20c5cd254471f1b321de793bdb85683135b940e2a00558228637ea00"
                  "1baa");

    MxqGame *dealt_game = nullptr;
    err = make_error();
    c.check_status(
        mxq_game_create_nearby(core, &dealt, &handshake, &dealt_game, &err),
        MXQ_OK, "a dealt online game is created over its handshake's session");
    /* Checked rather than merely guarded against: everything this section is
     * for hangs off the handle, and a silent skip would leave the pair of
     * presence rules below as untested as they were before it existed. */
    c.check(dealt_game != nullptr, "and the session handle exists");
    if (dealt_game != nullptr) {
        /* Read back before the filing: the session re-verifies its own deal
         * against all four values, and all four survive the mode. */
        MxqNearbySession wire;
        std::memset(&wire, 0, sizeof(wire));
        wire.struct_size = static_cast<uint32_t>(sizeof(wire));
        uint8_t wire_exists = 0;
        err = make_error();
        c.check_status(
            mxq_game_nearby_session(dealt_game, &wire, &wire_exists, &err),
            MXQ_OK, "its wire session reads back");
        c.check_eq(wire_exists, 1, "and there is one");
        c.check_eq(std::string(wire.deal_commit),
                   std::string(handshake.deal_commit),
                   "carrying the commitment the dealer bound its seed with");
        c.check_eq(std::string(wire.deal_digest),
                   std::string(handshake.deal_digest),
                   "and the digest a resume compares with the other device");

        for (const char *move : {"b1c3", "b8e8"}) {
            mxq_game_apply_move(dealt_game, move, nullptr, nullptr, nullptr);
        }
        uint64_t dealt_record = 0;
        err = make_error();
        c.check_status(mxq_game_commit_nearby_end(dealt_game,
                                                  MXQ_END_REASON_AGREED_DRAW,
                                                  MXQ_COLOR_NONE, &dealt_record,
                                                  &err),
                       MXQ_OK, "and the two players agree a draw over it");
        mxq_game_release(dealt_game);

        MxqGame *dealt_replay = nullptr;
        err = make_error();
        c.check_status(
            mxq_store_history_open(core, dealt_record, &dealt_replay, &err),
            MXQ_OK, "the dealt record opens for replay");
        c.check(dealt_replay != nullptr, "and the replay handle exists");
        if (dealt_replay != nullptr) {
            const std::string document =
                encode_of(core, dealt_replay, c, "the dealt record");
            c.check(document.find("\"mode\":\"online\"") != std::string::npos,
                    "whose document is an online game's");
            /* The three the archive records, written because the game is dealt
             * and the mode is a networked one. */
            for (const char *member : {"deal_commit", "deal_nonce",
                                       "deal_seed"}) {
                c.check(document.find(std::string("\"") + member + "\":") !=
                            std::string::npos,
                        std::string("and carries \"") + member +
                            "\", the deal's provenance");
            }
            /* And the fourth, which no document carries: it is derivable from
             * the deal the other three produce. */
            c.check(document.find("\"deal_digest\"") == std::string::npos,
                    "and not the digest, which is derivable from them");

            /* The round trip, which is the reader's own half of the same
             * question: a document whose deal members the reader did not expect
             * is refused as malformed rather than read. */
            MxqArchiveInfo dealt_info;
            std::memset(&dealt_info, 0, sizeof(dealt_info));
            dealt_info.struct_size = static_cast<uint32_t>(sizeof(dealt_info));
            err = make_error();
            c.check_status(
                mxq_archive_validate(
                    core, reinterpret_cast<const uint8_t *>(document.data()),
                    document.size(), &dealt_info, &err),
                MXQ_OK, "and the document validates as it stands");
            c.check_eq(dealt_info.mode, MXQ_PLAY_MODE_ONLINE,
                       "in the mode it was played in");
            c.check_eq(dealt_info.game, MXQ_GAME_KIND_JIEQI,
                       "and the game whose start is dealt");
            mxq_game_release(dealt_replay);
        }
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * The deal a wire session carries, refused where its game has none.
 *
 * The presence rule is two questions rather than one: a value is empty exactly
 * where the game has no deal, and sixty-four lowercase hexadecimal digits
 * exactly where it has one. Asked as a single comparison against the hex test
 * the two collapse for the game with no deal — junk is not hexadecimal and
 * neither is the empty string that game owes — so malformed text reads as
 * absence, is dropped in silence, and tells the caller nothing about what it
 * passed. That is the half pinned here, because it is the half that had no
 * diagnostic at all.
 */
void case_a_deal_is_refused_where_its_game_has_none() {
    Case c("a wire session's deal is refused where its game has none");
    const fs::path store = scratch_dir("deal-presence");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, 0, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqGameConfig config = make_config();
    config.mode = MXQ_PLAY_MODE_NEARBY;
    config.local_side = MXQ_COLOR_RED;

    MxqNearbySession birth;
    std::memset(&birth, 0, sizeof(birth));
    birth.struct_size = static_cast<uint32_t>(sizeof(birth));
    birth.proposer = MXQ_NEARBY_PROPOSER_PEER;
    std::snprintf(birth.session_id, sizeof(birth.session_id),
                  "0a3c7e51-8b26-7d40-9f11-2c4d6e8a0b13");
    std::snprintf(birth.peer_id, sizeof(birth.peer_id),
                  "wifi-aware-device-3C90A17F");

#if defined(NDEBUG)
    /* A game whose start nobody deals, over a session claiming a deal. It is a
     * programming error the contract has assert in a debug build, so the
     * returned status is a promise only where that assertion is compiled
     * out. */
    {
        MxqNearbySession junk = birth;
        std::snprintf(junk.deal_commit, sizeof(junk.deal_commit),
                      "not a commitment");
        MxqGame *refused = nullptr;
        err = make_error();
        c.check_status(
            mxq_game_create_nearby(core, &config, &junk, &refused, &err),
            MXQ_ERR_ARG_RANGE,
            "junk deal text on a game that is dealt no start");
        uint8_t exists = 1;
        err = make_error();
        c.check_status(mxq_store_active_exists(core, &exists, &err), MXQ_OK,
                       "the library answers afterwards");
        c.check_eq(exists, 0,
                   "and the refusal left no game behind it: a value read as "
                   "absence would have been dropped and the game created");
    }
#endif

    /* The accepting half, which every build runs: the same game over the same
     * session with its four deal values empty, which is the shape a game with
     * no deal has. */
    MxqGame *game = nullptr;
    err = make_error();
    c.check_status(mxq_game_create_nearby(core, &config, &birth, &game, &err),
                   MXQ_OK, "a nearby game of a game with no deal is created");
    mxq_game_release(game);

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * What a negotiated retraction may not rewrite.
 *
 * mxq_game_retract_nearby writes the whole of the wire session beside the
 * shortened line — the four columns the deal stands in among them — so the
 * freeze mxq_game_set_nearby_session applies is this entry's too, and for the
 * same reasons. A session's identity is not something a later call revises; and
 * three of the four deal values are already in the document the row stands
 * beside, so a retraction carrying a different well-formed deal would leave the
 * store holding a session whose evidence contradicts its own game. The next
 * resume answers that MXQ_ERR_STORE_CORRUPT, which is an active game nothing
 * can open until the row is repaired by hand.
 *
 * The deal is the corpus's own — the vector fixtures/store/jieqi-nearby-dealt
 * is built on — so the start here and the start there are one position rather
 * than two transcriptions.
 */
void case_a_retraction_may_not_rewrite_the_wire_session() {
    Case c("a retraction carrying another deal or another identity is refused");
    const fs::path store = scratch_dir("retraction-freeze");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    const char *const kDealt =
        "r~r~c~b~kp~n~n~b~/9/1p~5a~1/c~1p~1p~1p~1a~/9/9/"
        "P~1P~1C~1B~1R~/1P~5B~1/9/C~A~P~N~KA~P~R~N~ w - - 0 1";

    MxqGameConfig config = make_config();
    config.game = MXQ_GAME_KIND_JIEQI;
    config.mode = MXQ_PLAY_MODE_NEARBY;
    config.local_side = MXQ_COLOR_RED;
    std::memcpy(config.start_fen, kDealt, std::strlen(kDealt) + 1);

    MxqNearbySession birth;
    std::memset(&birth, 0, sizeof(birth));
    birth.struct_size = static_cast<uint32_t>(sizeof(birth));
    birth.proposer = MXQ_NEARBY_PROPOSER_LOCAL;
    std::snprintf(birth.session_id, sizeof(birth.session_id),
                  "d41f6b08-5e73-7a92-bc10-4f5e6a7b8c9d");
    std::snprintf(birth.peer_id, sizeof(birth.peer_id),
                  "wifi-aware-device-91B4D07E");
    std::snprintf(birth.deal_commit, sizeof(birth.deal_commit), "%s",
                  "66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5"
                  "f2925");
    std::snprintf(birth.deal_nonce, sizeof(birth.deal_nonce), "%s",
                  "a14441000000000000000000000000000000000000000000000000000000"
                  "0000");
    std::snprintf(birth.deal_seed, sizeof(birth.deal_seed), "%s",
                  "00000000000000000000000000000000000000000000000000000000000"
                  "00000");
    std::snprintf(birth.deal_digest, sizeof(birth.deal_digest), "%s",
                  "98ec20c5cd254471f1b321de793bdb85683135b940e2a00558228637ea00"
                  "1baa");

    MxqGame *game = nullptr;
    err = make_error();
    c.check_status(mxq_game_create_nearby(core, &config, &birth, &game, &err),
                   MXQ_OK, "the dealt nearby game and its wire session exist");
    if (game == nullptr) {
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }
    for (const char *move : {"b1c3", "b8e8"}) {
        err = make_error();
        c.check_status(mxq_game_apply_move(game, move, nullptr, nullptr, &err),
                       MXQ_OK, std::string("the ply ") + move + " lands");
    }

    sqlite3 *reader = open_second_connection(store);
    c.check(reader != nullptr, "a second connection reads the store");
    const auto row_count = [&](const char *what) {
        return reader == nullptr
                   ? std::string("?")
                   : query_text(reader, std::string("SELECT ") + what +
                                            " FROM nearby_session;");
    };
    const auto line_length = [&] {
        size_t count = 0;
        mxq_game_move_history(game, nullptr, 0, &count, nullptr);
        return static_cast<int64_t>(count);
    };

    /* A retraction the two players could have negotiated in every respect but
     * the one it revises. Both shapes are programming errors that assert in a
     * debug build, so the status is a promise only where that is compiled
     * out. */
    MxqNearbySession retracted = birth;
    retracted.undos = 1;
    retracted.keep = 1;
#if defined(NDEBUG)
    {
        MxqNearbySession other_deal = retracted;
        std::snprintf(other_deal.deal_digest, sizeof(other_deal.deal_digest),
                      "%s",
                      "0000000000000000000000000000000000000000000000000000000"
                      "000000000");
        err = make_error();
        c.check_status(mxq_game_retract_nearby(game, 1, &other_deal, &err),
                       MXQ_ERR_ARG_RANGE,
                       "a retraction carrying a deal this game was not dealt");
        c.check_eq(row_count("undos"), "0", "which retracted nothing");
        c.check_eq(row_count("deal_digest"), std::string(birth.deal_digest),
                   "and left the deal the game was dealt");
        c.check_eq(line_length(), 2, "and left the line where it was");

        MxqNearbySession stranger = retracted;
        std::snprintf(stranger.session_id, sizeof(stranger.session_id),
                      "00000000-0000-7000-8000-000000000000");
        err = make_error();
        c.check_status(mxq_game_retract_nearby(game, 1, &stranger, &err),
                       MXQ_ERR_ARG_RANGE,
                       "a retraction carrying another session's identifier");
        c.check_eq(row_count("undos"), "0", "which retracted nothing either");
        c.check_eq(row_count("session_id"), std::string(birth.session_id),
                   "and left the identity the session was created with");
        c.check_eq(line_length(), 2, "and left the line where it was");
    }
#endif

    /* And the honest retraction, which every build runs: the same call with the
     * session this game is actually being played over. */
    err = make_error();
    c.check_status(mxq_game_retract_nearby(game, 1, &retracted, &err), MXQ_OK,
                   "the two players' retraction");
    c.check_eq(line_length(), 1, "one ply survives");
    c.check_eq(row_count("undos"), "1", "and the retraction was counted");
    c.check_eq(row_count("deal_digest"), std::string(birth.deal_digest),
               "over the deal the game was dealt, unchanged");
    if (reader != nullptr) {
        sqlite3_close(reader);
    }
    mxq_game_release(game);

    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_history_ordering() {
    Case c("History is ordered pinned first, newest first, by record id");
    const fs::path store = scratch_dir("ordering");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqGameConfig config = make_config();
    const uint64_t first = play_and_file(core, config, {"b1b3"}, c, "first");
    const uint64_t second = play_and_file(core, config, {"b1b3", "b7b5"}, c,
                                          "second");
    const uint64_t third = play_and_file(core, config, {"b1b2"}, c, "third");
    c.check(first < second && second < third,
            "record identifiers increase with each new record");

    const auto ids = [&](const std::string &where) {
        std::vector<uint64_t> out;
        for (const MxqRecordSummary &row : page_of(core, 0, 8, c, where)) {
            out.push_back(row.record_id);
        }
        return out;
    };

    c.check(ids("unpinned") == std::vector<uint64_t>({third, second, first}),
            "newest History-added time first");

    err = make_error();
    c.check_status(mxq_store_history_set_pinned(core, first, 1, &err), MXQ_OK,
                   "the oldest record is pinned");
    c.check(ids("pinned") == std::vector<uint64_t>({first, third, second}),
            "a pinned record leads, whatever its time");

    err = make_error();
    c.check_status(mxq_store_history_set_pinned(core, second, 1, &err), MXQ_OK,
                   "a second record is pinned");
    c.check(ids("two pinned") == std::vector<uint64_t>({second, first, third}),
            "the pinned group is ordered by time within itself");

    err = make_error();
    c.check_status(mxq_store_history_set_pinned(core, first, 0, &err), MXQ_OK,
                   "the first record is unpinned");
    c.check_status(mxq_store_history_set_pinned(core, second, 0, &err), MXQ_OK,
                   "and so is the second");
    c.check(ids("unpinned again") ==
                std::vector<uint64_t>({third, second, first}),
            "unpinning restores the plain order");

    MxqRecordSummary summary = make_summary();
    err = make_error();
    mxq_store_history_get(core, first, &summary, &err);
    c.check_eq(summary.pinned, 0, "the pin state round-trips to 0");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_ordering_tie_is_broken_by_record_id() {
    Case c("two records added in the same millisecond are ordered by record id");
    const fs::path store = scratch_dir("tie");

    /*
     * The deterministic clock restarts at every mxq_core_init, so two games
     * played in two lifetimes of the same store, with the same number of
     * committed changes, reach History at exactly the same instant. That is
     * the tie the accepted ordering breaks on record_id, arranged out of the
     * contract's own guarantees rather than by writing a timestamp by hand.
     *
     * The identity sequence restarts too, and game_id is unique, so the
     * second lifetime is advanced past the first game's identifier before it
     * creates its own.
     */
    std::vector<uint64_t> made;
    for (int lifetime = 0; lifetime < 2; ++lifetime) {
        MxqCore *core = nullptr;
        MxqError err = make_error();
        if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core,
                      &err) != MXQ_OK) {
            c.check(false, "mxq_core_init failed");
            c.report();
            return;
        }
        for (int skip = 0; skip < lifetime; ++skip) {
            core->identity.next_game_id();
        }
        MxqGameConfig config = make_config();
        made.push_back(play_and_file(core, config, {"b1b3"}, c,
                                     "lifetime " + std::to_string(lifetime)));
        mxq_core_shutdown(core, nullptr);
    }

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "reopening failed");
        c.report();
        return;
    }
    const std::vector<MxqRecordSummary> page = page_of(core, 0, 8, c, "tie");
    c.check_eq(static_cast<int64_t>(page.size()), 2, "both records are there");
    if (page.size() == 2) {
        c.check_eq(page[0].added_at_ms, page[1].added_at_ms,
                   "the two records share a History-added time");
        c.check_eq(static_cast<int64_t>(page[0].record_id),
                   static_cast<int64_t>(made[1]),
                   "the later record_id leads the tie");
        c.check_eq(static_cast<int64_t>(page[1].record_id),
                   static_cast<int64_t>(made[0]),
                   "and the earlier one follows");
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_pagination_boundaries() {
    Case c("pagination at its boundaries");
    const fs::path store = scratch_dir("pagination");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqGameConfig config = make_config();
    std::vector<uint64_t> made;
    for (int i = 0; i < 3; ++i) {
        made.push_back(play_and_file(core, config, {"b1b3"}, c,
                                     "record " + std::to_string(i)));
    }
    std::reverse(made.begin(), made.end()); /* newest first, as History reads */

    uint32_t count = 0;
    uint64_t revision = 0;
    err = make_error();
    c.check_status(mxq_store_history_count(core, &count, &revision, &err),
                   MXQ_OK, "mxq_store_history_count");
    c.check_eq(count, 3, "three records");

    /* A page exactly the size of the list. */
    std::vector<MxqRecordSummary> exact(3, make_summary());
    size_t written = 0;
    uint64_t page_revision = 0;
    err = make_error();
    c.check_status(mxq_store_history_page(core, 0, 3, exact.data(), 3, &written,
                                          &page_revision, &err),
                   MXQ_OK, "an exact page");
    c.check_eq(static_cast<int64_t>(written), 3, "all three were written");
    c.check_eq(static_cast<int64_t>(page_revision),
               static_cast<int64_t>(revision),
               "the page reports the same revision the count did");

    /* A page larger than the list writes only what there is. */
    std::vector<MxqRecordSummary> roomy(8, make_summary());
    err = make_error();
    c.check_status(mxq_store_history_page(core, 0, 8, roomy.data(), 8, &written,
                                          &page_revision, &err),
                   MXQ_OK, "a page larger than the list");
    c.check_eq(static_cast<int64_t>(written), 3, "only three were written");

    /* A page that starts inside the list and runs past its end. */
    err = make_error();
    c.check_status(mxq_store_history_page(core, 2, 8, roomy.data(), 8, &written,
                                          &page_revision, &err),
                   MXQ_OK, "a page overlapping the end");
    c.check_eq(static_cast<int64_t>(written), 1, "one record was left");
    if (written == 1) {
        c.check_eq(static_cast<int64_t>(roomy[0].record_id),
                   static_cast<int64_t>(made[2]), "and it is the last one");
    }

    /* A page entirely past the end. */
    err = make_error();
    c.check_status(mxq_store_history_page(core, 3, 8, roomy.data(), 8, &written,
                                          &page_revision, &err),
                   MXQ_OK, "a page past the end");
    c.check_eq(static_cast<int64_t>(written), 0, "nothing was written");

    /* A buffer smaller than the page the caller asked for is the caller's bug,
     * and the required size is the page size it named. */
    written = 99;
    err = make_error();
    c.check_status(mxq_store_history_page(core, 0, 4, roomy.data(), 3, &written,
                                          &page_revision, &err),
                   MXQ_ERR_ARG_BUFFER_TOO_SMALL, "a buffer below the limit");
    c.check_eq(static_cast<int64_t>(err.required_size), 4,
               "required_size names the requested page size");
    c.check_eq(static_cast<int64_t>(written), 0, "nothing was written");

    /* Asking for no records at all is not an error. */
    written = 99;
    err = make_error();
    c.check_status(mxq_store_history_page(core, 0, 0, nullptr, 0, &written,
                                          &page_revision, &err),
                   MXQ_OK, "a page of zero records");
    c.check_eq(static_cast<int64_t>(written), 0, "nothing was written");

    /* Offsets walk the list in the accepted order, one at a time. */
    for (uint32_t i = 0; i < 3; ++i) {
        const std::vector<MxqRecordSummary> one =
            page_of(core, i, 1, c, "offset " + std::to_string(i));
        c.check_eq(static_cast<int64_t>(one.size()), 1, "one row at a time");
        if (one.size() == 1) {
            c.check_eq(static_cast<int64_t>(one[0].record_id),
                       static_cast<int64_t>(made[i]),
                       "offset " + std::to_string(i) + " is the right record");
        }
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_pin_and_delete_bump_the_revision() {
    Case c("every committed mutation bumps the library revision");
    const fs::path store = scratch_dir("revisions");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    std::vector<uint64_t> revisions;
    revisions.push_back(revision_of(core, c, "fresh"));

    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    err = make_error();
    mxq_game_create(core, &config, &game, &err);
    revisions.push_back(revision_of(core, c, "after the creation"));
    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);
    revisions.push_back(revision_of(core, c, "after the move"));
    uint32_t removed = 0;
    mxq_game_undo(game, &removed, nullptr);
    revisions.push_back(revision_of(core, c, "after the undo"));
    uint64_t record_id = 0;
    err = make_error();
    mxq_store_archive_and_clear(core, game, &record_id, &err);
    revisions.push_back(revision_of(core, c, "after the archiving"));
    mxq_game_release(game);

    err = make_error();
    c.check_status(mxq_store_history_set_pinned(core, record_id, 1, &err),
                   MXQ_OK, "pinning");
    revisions.push_back(revision_of(core, c, "after the pin"));
    err = make_error();
    c.check_status(mxq_store_history_set_pinned(core, record_id, 0, &err),
                   MXQ_OK, "unpinning");
    revisions.push_back(revision_of(core, c, "after the unpin"));
    err = make_error();
    c.check_status(mxq_store_history_delete(core, record_id, &err), MXQ_OK,
                   "deleting");
    revisions.push_back(revision_of(core, c, "after the deletion"));

    for (size_t i = 1; i < revisions.size(); ++i) {
        c.check(revisions[i] > revisions[i - 1],
                "revision " + std::to_string(i) + " (" +
                    std::to_string(revisions[i]) +
                    ") is greater than the one before it (" +
                    std::to_string(revisions[i - 1]) + ")");
    }

    /* A refused mutation commits nothing, so it moves nothing. */
    const uint64_t settled = revisions.back();
    err = make_error();
    c.check_status(mxq_store_history_delete(core, record_id, &err),
                   MXQ_ERR_STORE_NOT_FOUND, "deleting it twice");
    c.check_eq(static_cast<int64_t>(revision_of(core, c, "after the refusal")),
               static_cast<int64_t>(settled),
               "a refused deletion is not a mutation");
    c.check_eq(count_of(core, c, "after the deletion"), 0,
               "the deletion was permanent");

    /* And the identifier never comes back: AUTOINCREMENT is what makes the
     * ordering tie-break strict and a stale identifier dangle. */
    const uint64_t next = play_and_file(core, config, {"b1b3"}, c, "the next");
    c.check(next > record_id,
            "a deleted record's identifier is never issued again");
    MxqRecordSummary gone = make_summary();
    err = make_error();
    c.check_status(mxq_store_history_get(core, record_id, &gone, &err),
                   MXQ_ERR_STORE_NOT_FOUND,
                   "the deleted identifier still resolves to nothing");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_active_summary_and_the_single_active_game() {
    Case c("the active summary, and one active game across an archiving");
    const fs::path store = scratch_dir("active-summary");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqGameConfig config = make_config();
    config.mode = MXQ_PLAY_MODE_HUMAN_VS_AI;
    config.human_side = MXQ_COLOR_BLACK;
    config.ai_level = MXQ_AI_LEVEL_DEEP;
    config.first_mover_choice = MXQ_FIRST_MOVER_RANDOM;
    config.ai_movetime_ms = MXQ_MOVETIME_DEEP_MS;

    MxqGame *game = nullptr;
    err = make_error();
    c.check_status(mxq_game_create(core, &config, &game, &err), MXQ_OK,
                   "mxq_game_create");

    /* Before any move: the human is Black, so it is the AI's turn, and the
     * summary derives that from the frozen configuration and the empty line
     * rather than from anything persisted. */
    MxqGameStatus owed = make_status();
    uint8_t present = 0;
    err = make_error();
    c.check_status(
        mxq_store_active_summary(core, nullptr, &owed, &present, &err), MXQ_OK,
        "mxq_store_active_summary before the first move");
    c.check_eq(present, 1, "the created game is the active one");
    c.check_eq(owed.search_expected, 1, "a search is owed at the start");

    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);

    char id[MXQ_GAME_ID_CAP];
    size_t len = 0;
    mxq_game_id(game, id, sizeof(id), &len, nullptr);

    MxqRecordSummary summary = make_summary();
    MxqGameStatus status = make_status();
    uint8_t exists = 0;
    err = make_error();
    c.check_status(
        mxq_store_active_summary(core, &summary, &status, &exists, &err),
        MXQ_OK, "mxq_store_active_summary");
    c.check_eq(exists, 1, "there is an active game");
    c.check_eq(std::string(summary.game_id), std::string(id),
               "the summary names the active game");
    c.check_eq(summary.is_active, 1, "is_active");
    c.check_eq(summary.move_count, 1, "move_count");
    c.check_eq(summary.mode, MXQ_PLAY_MODE_HUMAN_VS_AI, "mode");
    c.check_eq(summary.human_side, MXQ_COLOR_BLACK, "human_side");
    c.check_eq(summary.ai_level, MXQ_AI_LEVEL_DEEP, "ai_level");
    c.check_eq(summary.ai_movetime_ms, MXQ_MOVETIME_DEEP_MS, "ai_movetime_ms");
    c.check_eq(summary.outcome, MXQ_OUTCOME_NONE, "an active game has no outcome");
    c.check_eq(summary.end_reason, MXQ_END_REASON_NONE, "and no end reason");
    c.check_eq(summary.added_at_ms, 0, "and no History-added time");
    c.check_eq(summary.ended_at_ms, 0, "and no end instant");
    c.check_eq(summary.pinned, 0, "the active game is never pinned");
    c.check(summary.started_at_ms > 0, "it does have a start instant");

    /* The live state comes from the stored line, not from a flag. */
    c.check_eq(state_text(status.state), "ongoing", "the reported state");
    c.check_eq(status.resign_available, 1,
               "a human-versus-AI game in progress may be resigned");
    c.check_eq(status.search_expected, 0,
               "and after the AI's move it is the human's turn");

    /* It is not a History record, and History does not claim it. */
    MxqRecordSummary as_history = make_summary();
    err = make_error();
    c.check_status(
        mxq_store_history_get(core, summary.record_id, &as_history, &err),
        MXQ_ERR_STORE_NOT_FOUND, "the active game is not a History record");
    MxqGame *as_replay = reinterpret_cast<MxqGame *>(0x1);
    err = make_error();
    c.check_status(
        mxq_store_history_open(core, summary.record_id, &as_replay, &err),
        MXQ_ERR_STORE_NOT_FOUND, "nor can it be opened as one");
    c.check(as_replay == nullptr, "and no replay session was produced");
    err = make_error();
    c.check_status(mxq_store_history_set_pinned(core, summary.record_id, 1,
                                                &err),
                   MXQ_ERR_STORE_NOT_FOUND, "nor pinned");
    err = make_error();
    c.check_status(mxq_store_history_delete(core, summary.record_id, &err),
                   MXQ_ERR_STORE_NOT_FOUND, "nor deleted");

    /* A second creation is refused while it is active; after the archiving it
     * is not. */
    MxqGameConfig free_play = make_config();
    MxqGame *second = nullptr;
    err = make_error();
    c.check_status(mxq_game_create(core, &free_play, &second, &err),
                   MXQ_ERR_STATE_ACTIVE_GAME_EXISTS,
                   "a second active game is refused");

    uint64_t record_id = 0;
    err = make_error();
    c.check_status(mxq_store_archive_and_clear(core, game, &record_id, &err),
                   MXQ_OK, "the active game is filed");
    mxq_game_release(game);

    err = make_error();
    c.check_status(mxq_game_create(core, &free_play, &second, &err), MXQ_OK,
                   "and then another may be created");
    if (second != nullptr) {
        MxqRecordSummary now = make_summary();
        exists = 0;
        err = make_error();
        c.check_status(
            mxq_store_active_summary(core, &now, nullptr, &exists, &err),
            MXQ_OK, "the new game is the active one");
        c.check_eq(exists, 1, "there is an active game again");
        c.check(now.record_id != record_id,
                "and it is not the record that was filed");
        mxq_game_release(second);
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_corrupt_content_hash_is_refused() {
    Case c("a row whose content hash disagrees with its bytes is corruption");
    const fs::path store = scratch_dir("bad-hash");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }
    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    err = make_error();
    mxq_game_create(core, &config, &game, &err);
    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);
    mxq_game_release(game);
    mxq_core_shutdown(core, nullptr);

    /* The blob is tampered into a document that still decodes, still
     * canonicalises, and still replays — the recorded move swapped for a
     * different legal move of the same length — so nothing but the hash
     * comparison can tell it from the record it replaced. The review drove
     * exactly this shape; the weaker hash-column rewrite proved only that a
     * comparison exists. */
    sqlite3 *tamper = open_second_connection(store);
    c.check(tamper != nullptr, "the tampering connection opens");
    if (tamper != nullptr) {
        c.check(run_sql(tamper,
                        "UPDATE game SET archive = CAST(REPLACE(CAST(archive "
                        "AS TEXT), '\"b1b3\"', '\"b1b2\"') AS BLOB) "
                        "WHERE outcome IS NULL;"),
                "the blob is rewritten valid-but-different");
        sqlite3_close(tamper);
    }

    err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "reopening failed");
        c.report();
        return;
    }
    MxqGame *resumed = reinterpret_cast<MxqGame *>(0x1);
    uint8_t exists = 1;
    err = make_error();
    c.check_status(mxq_game_resume_active(core, &resumed, &exists, &err),
                   MXQ_ERR_STORE_CORRUPT, "resuming a row with a wrong hash");
    c.check(resumed == nullptr, "no session was produced");
    c.check(std::string(err.detail).find("hash") != std::string::npos,
            std::string("the diagnostic names the hash: ") + err.detail);

    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_second_resume_is_refused() {
    Case c("a second resume while a session is attached is refused");
    const fs::path store = scratch_dir("second-resume");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }
    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    err = make_error();
    mxq_game_create(core, &config, &game, &err);
    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);

    /* The created session is attached to the row, so resuming it would alias
     * it: two sessions committing over one another, last writer wins. */
    MxqGame *second = reinterpret_cast<MxqGame *>(0x1);
    uint8_t exists = 1;
    err = make_error();
    c.check_status(mxq_game_resume_active(core, &second, &exists, &err),
                   MXQ_ERR_ARG_CONCURRENT_USE,
                   "resuming a game a session already holds");
    c.check(second == nullptr, "no second session was produced");
    c.check_eq(exists, 0, "and nothing was claimed to exist");

    /* Releasing the first makes the row resumable again, which is what says
     * the refusal was about the attachment and not about the row. */
    mxq_game_release(game);
    err = make_error();
    c.check_status(mxq_game_resume_active(core, &second, &exists, &err), MXQ_OK,
                   "resuming once the first session is released");
    c.check_eq(exists, 1, "the game is there");

    /* An archived session no longer holds its row — but there is nothing
     * active left to resume either. */
    uint64_t record_id = 0;
    err = make_error();
    c.check_status(mxq_store_archive_and_clear(core, second, &record_id, &err),
                   MXQ_OK, "the game is filed");
    MxqGame *third = reinterpret_cast<MxqGame *>(0x1);
    err = make_error();
    c.check_status(mxq_game_resume_active(core, &third, &exists, &err), MXQ_OK,
                   "resuming after the archiving");
    c.check_eq(exists, 0, "there is nothing active to resume");
    c.check(third == nullptr, "and no session was produced");

    mxq_game_release(second);
    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_dangling_active_reference_is_corruption() {
    Case c("a library reference to a row that is not there is corruption");
    const fs::path store = scratch_dir("dangling");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }
    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    err = make_error();
    mxq_game_create(core, &config, &game, &err);
    mxq_game_release(game);
    mxq_core_shutdown(core, nullptr);

    /* Foreign keys are off on this connection, which is the only way to write
     * a reference the core's own connection would refuse: this is external
     * damage, not a state the core can reach. */
    sqlite3 *tamper = open_second_connection(store);
    c.check(tamper != nullptr, "the tampering connection opens");
    if (tamper != nullptr) {
        c.check(run_sql(tamper, "PRAGMA foreign_keys = OFF;"),
                "foreign keys are off for the tamper");
        c.check(run_sql(tamper,
                        "UPDATE library SET active_record_id = 424242"
                        " WHERE id = 1;"),
                "the library is pointed at a row that is not there");
        sqlite3_close(tamper);
    }

    err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "reopening failed");
        c.report();
        return;
    }

    uint8_t exists = 1;
    err = make_error();
    c.check_status(mxq_store_active_exists(core, &exists, &err),
                   MXQ_ERR_STORE_CORRUPT,
                   "mxq_store_active_exists on a dangling reference");
    c.check_eq(exists, 0, "and it claims no active game");

    MxqGame *resumed = reinterpret_cast<MxqGame *>(0x1);
    exists = 1;
    err = make_error();
    c.check_status(mxq_game_resume_active(core, &resumed, &exists, &err),
                   MXQ_ERR_STORE_CORRUPT,
                   "mxq_game_resume_active on a dangling reference");
    c.check(resumed == nullptr, "no session was produced");
    c.check_eq(exists, 0, "and absence was not reported as success");

    MxqRecordSummary summary = make_summary();
    exists = 1;
    err = make_error();
    c.check_status(
        mxq_store_active_summary(core, &summary, nullptr, &exists, &err),
        MXQ_ERR_STORE_CORRUPT, "mxq_store_active_summary likewise");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

#endif /* MXQ_TEST_RULES_FACADE */

} /* namespace */

int main(int argc, char **argv) {
    fs::path fixtures;
    fs::path archives;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--fixtures" && i + 1 < argc) {
            fixtures = argv[++i];
        } else if (arg == "--archives" && i + 1 < argc) {
            archives = argv[++i];
        } else {
            std::cerr << "usage: mxq_history_tests [--fixtures <dir>] "
                         "[--archives <dir>]\n";
            return 2;
        }
    }
    if (fixtures.empty()) {
        if (const char *env = std::getenv("MXQ_STORE_FIXTURES_DIR")) {
            fixtures = env;
        } else {
            fixtures = MXQ_STORE_FIXTURES_DIR_DEFAULT;
        }
    }
    fixtures /= "terminal";
    if (archives.empty()) {
        if (const char *env = std::getenv("MXQ_ARCHIVE_FIXTURES_DIR")) {
            archives = env;
        } else {
            archives = MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT;
        }
    }

    std::cout << "Mini Xiangqi terminal-commit and History tests\n"
              << "  fixtures        " << fixtures.string() << "\n"
              << "  archives        " << archives.string() << "\n"
              << "  rules facade    "
              << (MXQ_TEST_RULES_FACADE
                      ? "available; a game can be played and ended"
                      : "ABSENT; no game can be played, so none can be ended")
              << "\n\n";

    case_empty_library();

#if MXQ_TEST_RULES_FACADE
    std::vector<fs::path> scenarios;
    std::error_code ec;
    for (const fs::directory_entry &entry :
         fs::directory_iterator(fixtures, ec)) {
        if (entry.path().extension() == ".json") {
            scenarios.push_back(entry.path());
        }
    }
    if (ec || scenarios.empty()) {
        std::cerr << "mxq_history_tests: no scenarios in " << fixtures.string()
                  << "\n";
        return 2;
    }
    std::sort(scenarios.begin(), scenarios.end());
    for (const fs::path &scenario : scenarios) {
        run_scenario(scenario, archives);
    }

    case_a_failed_ending_is_retryable(scenarios);
    case_archive_and_clear_without_a_game();
    case_endings_refuse_where_they_do_not_apply();
    case_the_wire_session_lives_with_its_game();
    case_online_is_nearbys_twin();
    case_a_deal_is_refused_where_its_game_has_none();
    case_a_retraction_may_not_rewrite_the_wire_session();
    case_history_ordering();
    case_ordering_tie_is_broken_by_record_id();
    case_pagination_boundaries();
    case_pin_and_delete_bump_the_revision();
    case_active_summary_and_the_single_active_game();
    case_corrupt_content_hash_is_refused();
    case_second_resume_is_refused();
    case_dangling_active_reference_is_corruption();

    std::error_code cleanup;
    fs::remove_all(scratch_root(), cleanup);
#else
    Case skipped("the terminal commits and the History surface");
    skipped.skip(kNoFacade);
    skipped.report();
#endif

    const int total = g_passed + g_failed + g_skipped;
    std::cout << "\n"
              << total << " cases: " << g_passed << " passed, " << g_failed
              << " failed, " << g_skipped << " skipped\n"
              << g_checks << " expectations evaluated\n";
    if (g_skipped_no_facade > 0) {
        std::cout << "\nNOT IMPLEMENTED: the endings and the sessions they "
                     "produce are not in this build. Build with "
                     "-DMXQ_ENABLE_RULES_FACADE=ON to evaluate them.\n";
    }
    return g_failed > 0 ? 1 : 0;
}
