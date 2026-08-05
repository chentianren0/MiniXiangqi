/*
 * The interchange runner: one game out as a file, one game in from one.
 *
 * The archive runner already holds the codec to every rejection class the
 * accepted validation order defines. This runner does not re-prove any of that;
 * it drives the same corpus through the real import pipeline and asserts two
 * things the codec runner structurally cannot: that every class refuses through
 * mxq_store_import with the status the sidecar already fixed, and that the
 * library is not touched when it does. A validation that is right and a
 * transaction that runs anyway would pass the codec runner completely.
 *
 * The transactional half is driven rather than reasoned about. A second
 * connection takes the database's write lock, so an import fails where a real
 * contended one would — inside BEGIN IMMEDIATE, with every validation stage
 * already passed — and what must hold afterwards is the whole of
 * docs/game-data.md's promise: no record, no revision bump, and the same call
 * succeeding once the store is free.
 *
 * The corpus is the archive corpus, unchanged. The five completed goldens are
 * what an export produces and what an import accepts; the four active shapes
 * are what the store holds while a game is being played, and importing one is
 * refused — "refusing to import an incomplete one is the importer's rule rather
 * than the codec's", which fixtures/archive/README.md wrote down before this
 * runner existed.
 *
 * Without MXQ_ENABLE_RULES_FACADE an import cannot replay a move line and so
 * does not exist in the library, and no History record can be made for an
 * export to find. One case runs there — export from a library that has none —
 * and the rest report NOT IMPLEMENTED, which is never counted as a pass.
 */

#include "mxq.h"

#include "mxq_json.hpp"

#if MXQ_TEST_RULES_FACADE
#include "sqlite3.h"
#endif

#include <algorithm>
#include <chrono>
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

fs::path scratch_root() {
    static const fs::path root = [] {
        std::random_device rd;
        char token[17];
        std::snprintf(token, sizeof(token), "%08x%08x", rd(), rd());
        return fs::temp_directory_path() /
               ("minixiangqi-interchange-tests-" + std::string(token));
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

MxqStatus init_core(const fs::path &store_dir, MxqCore **out, MxqError *err) {
    const std::string assets = assets_dir();
    const std::string store = store_dir.string();
    MxqCoreConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.api_major = MXQ_API_VERSION_MAJOR;
    config.api_minor = MXQ_API_VERSION_MINOR;
    config.api_patch = MXQ_API_VERSION_PATCH;
    config.flags = MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY;
    config.store_directory = store.c_str();
    config.asset_directory = assets.c_str();
    return mxq_core_init(&config, out, err);
}

#if MXQ_TEST_RULES_FACADE
/* Everything below reads a fixture, and only a build that can import one has
 * anything to read it for: without the facade the one case that runs never
 * opens a file, never names a status against a sidecar, and never inspects a
 * document. */

MxqRecordSummary make_summary() {
    MxqRecordSummary s;
    std::memset(&s, 0, sizeof(s));
    s.struct_size = static_cast<uint32_t>(sizeof(s));
    return s;
}

bool read_file(const fs::path &path, std::string &out) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return false;
    }
    out.assign(std::istreambuf_iterator<char>(in),
               std::istreambuf_iterator<char>());
    return true;
}

bool read_sidecar(const fs::path &path, mxqtest::JsonValue &out,
                  std::string &error) {
    std::string text;
    if (!read_file(path, text)) {
        error = "cannot read " + path.filename().string();
        return false;
    }
    if (!mxqtest::json_parse(text, out, error)) {
        error = path.filename().string() + ": " + error;
        return false;
    }
    if (!out.is_object()) {
        error = path.filename().string() + ": the expectation is not an object";
        return false;
    }
    return true;
}

std::vector<fs::path> archives_in(const fs::path &dir, std::string &error) {
    std::vector<fs::path> files;
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) {
        error = "not a directory: " + dir.string();
        return files;
    }
    for (const fs::directory_entry &entry : fs::directory_iterator(dir, ec)) {
        if (entry.path().extension() == ".mxq") {
            files.push_back(entry.path());
        }
    }
    if (ec) {
        error = "cannot read " + dir.string() + ": " + ec.message();
    }
    std::sort(files.begin(), files.end());
    return files;
}

const uint8_t *bytes_of(const std::string &s) {
    return reinterpret_cast<const uint8_t *>(s.data());
}

/*
 * The `content` object's bytes inside a canonical document.
 *
 * The canonical form puts the five envelope members in codepoint order —
 * archive_format, archive_version, content, game_id, origin — so the content
 * object is exactly what lies between `"content":` and `,"game_id":`. That is
 * what the content hash is taken over and what an export must not touch, and
 * extracting it here lets a test say "these two documents carry the same game"
 * without reimplementing the codec to do it.
 */
std::string content_of(const std::string &document) {
    const std::string open = "\"content\":";
    const std::string close = ",\"game_id\":";
    const size_t at = document.find(open);
    const size_t end = document.find(close, at == std::string::npos ? 0 : at);
    if (at == std::string::npos || end == std::string::npos) {
        return std::string();
    }
    return document.substr(at + open.size(), end - at - open.size());
}

/* The `origin` object's bytes, which is the rest of the document after it: it
 * is the last member in codepoint order, and the closing brace goes with it. */
std::string origin_of(const std::string &document) {
    const std::string open = ",\"origin\":";
    const size_t at = document.find(open);
    if (at == std::string::npos) {
        return std::string();
    }
    return document.substr(at + open.size());
}

/* The envelope's game_id, for a test that has to rewrite one. */
std::string game_id_of(const std::string &document) {
    const std::string open = ",\"game_id\":\"";
    const size_t at = document.find(open);
    if (at == std::string::npos) {
        return std::string();
    }
    return document.substr(at + open.size(), 36);
}
#endif /* MXQ_TEST_RULES_FACADE */

/* ---------------------------------------------------------------------- */
/* Export from a library with nothing in it, which needs no engine         */
/* ---------------------------------------------------------------------- */

void case_export_wants_a_history_record() {
    Case c("exporting what the library does not hold is not found");
    const fs::path store = scratch_dir("export-empty");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }

    MxqBlob *blob = reinterpret_cast<MxqBlob *>(1);
    err = make_error();
    c.check_status(mxq_store_export(core, 1, &blob, &err),
                   MXQ_ERR_STORE_NOT_FOUND, "exporting record 1 of nothing");
    c.check(blob == nullptr,
            "a refused export writes NULL rather than leaving the caller's "
            "pointer as it was");

    /* And an identifier no record ever had answers the same way as one that
     * was issued and deleted: the store never reissues a record_id. */
    err = make_error();
    c.check_status(mxq_store_export(core, 987654321, &blob, &err),
                   MXQ_ERR_STORE_NOT_FOUND, "exporting an implausible id");

#if defined(NDEBUG)
    /* The argument assertions are compiled out, so their statuses are
     * observable; a debug build traps instead, which is the same contract
     * stated more loudly. */
    err = make_error();
    c.check_status(mxq_store_export(core, 1, nullptr, &err), MXQ_ERR_ARG_NULL,
                   "export with nowhere to put the blob");
#endif

    mxq_core_shutdown(core, nullptr);
    c.report();
}

#if MXQ_TEST_RULES_FACADE

/* ---------------------------------------------------------------------- */
/* Small readers over the library                                          */
/* ---------------------------------------------------------------------- */

struct Library {
    uint32_t count = 0;
    uint64_t revision = 0;
    uint8_t  active = 0;
};

Library library_of(MxqCore *core, Case &c, const std::string &what) {
    Library out;
    MxqError err = make_error();
    c.check_status(mxq_store_history_count(core, &out.count, &out.revision,
                                           &err),
                   MXQ_OK, what + ": mxq_store_history_count");
    err = make_error();
    c.check_status(mxq_store_active_exists(core, &out.active, &err), MXQ_OK,
                   what + ": mxq_store_active_exists");
    return out;
}

void check_library_unchanged(Case &c, const Library &before,
                             const Library &after, const std::string &what) {
    c.check_eq(after.count, before.count, what + ": the History count");
    c.check_eq(static_cast<int64_t>(after.revision),
               static_cast<int64_t>(before.revision),
               what + ": the library revision");
    c.check_eq(after.active, before.active, what + ": the active game");
}

std::string blob_text(MxqBlob *blob) {
    if (blob == nullptr) {
        return std::string();
    }
    const uint8_t *data = mxq_blob_bytes(blob);
    return std::string(reinterpret_cast<const char *>(data),
                       mxq_blob_len(blob));
}

/* One export, as bytes, with the blob released before the caller sees them. */
std::string export_of(MxqCore *core, uint64_t record_id, Case &c,
                      const std::string &what) {
    MxqBlob *blob = nullptr;
    MxqError err = make_error();
    const MxqStatus rc = mxq_store_export(core, record_id, &blob, &err);
    c.check_status(rc, MXQ_OK, what + ": mxq_store_export");
    if (rc != MXQ_OK) {
        return std::string();
    }
    const std::string bytes = blob_text(blob);
    mxq_blob_release(blob);
    return bytes;
}

/* What a stored record's row holds, byte for byte: opening it and encoding it
 * reproduces the row's own document, which is the property the golden corpus
 * pins and the only route to those bytes through the public surface. */
std::string stored_bytes(MxqCore *core, uint64_t record_id, Case &c,
                         const std::string &what) {
    MxqGame *replay = nullptr;
    MxqError err = make_error();
    if (mxq_store_history_open(core, record_id, &replay, &err) != MXQ_OK) {
        c.check(false, what + ": mxq_store_history_open failed: " + err.detail);
        return std::string();
    }
    MxqBlob *blob = nullptr;
    err = make_error();
    const MxqStatus rc = mxq_archive_encode(core, replay, &blob, &err);
    c.check_status(rc, MXQ_OK, what + ": mxq_archive_encode");
    std::string bytes;
    if (rc == MXQ_OK) {
        bytes = blob_text(blob);
        mxq_blob_release(blob);
    }
    mxq_game_release(replay);
    return bytes;
}

void check_summaries_agree(Case &c, const MxqRecordSummary &a,
                           const MxqRecordSummary &b,
                           const std::string &what) {
    c.check_eq(std::string(b.game_id), std::string(a.game_id),
               what + ": game_id");
    c.check_eq(b.mode, a.mode, what + ": mode");
    c.check_eq(b.human_side, a.human_side, what + ": human_side");
    c.check_eq(b.ai_level, a.ai_level, what + ": ai_level");
    c.check_eq(b.ai_movetime_ms, a.ai_movetime_ms, what + ": ai_movetime_ms");
    c.check_eq(b.move_count, a.move_count, what + ": move_count");
    c.check_eq(b.outcome, a.outcome, what + ": outcome");
    c.check_eq(b.end_reason, a.end_reason, what + ": end_reason");
    c.check_eq(b.started_at_ms, a.started_at_ms, what + ": started_at_ms");
    c.check_eq(b.ended_at_ms, a.ended_at_ms, what + ": ended_at_ms");
    c.check_eq(b.provenance, a.provenance, what + ": provenance");
}

/* ---------------------------------------------------------------------- */
/* The rejection corpus, through the pipeline that persists                */
/* ---------------------------------------------------------------------- */

/*
 * Every class the codec refuses, refused identically by the import path, with
 * the library untouched each time.
 *
 * The expectation is the archive corpus's own sidecar — its `validate` member,
 * because import runs the whole ladder including the rules tier — so this
 * runner states no expectation of its own and cannot drift from the one the
 * data contract already fixed. `detail_contains` rides along where the sidecar
 * carries it, which is how the distinct created-by-a-newer-version message is
 * pinned through the surface a frontend actually calls.
 *
 * mxq_game_open_archive is asked the same question in the same loop: the
 * preview and the import must accept exactly the same set of files, and a
 * preview that showed a board the import then refused would be the worst of
 * both answers.
 */
void case_the_rejection_corpus_refuses_identically(
    const std::vector<fs::path> &rejected) {
    Case c("every rejection class refuses through import, and touches nothing");
    const fs::path store = scratch_dir("rejections");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }
    const Library before = library_of(core, c, "before");

    for (const fs::path &file : rejected) {
        const std::string what = file.stem().string();
        std::string bytes;
        mxqtest::JsonValue expected;
        std::string error;
        if (!read_file(file, bytes) ||
            !read_sidecar(file.parent_path() / (what + ".expected.json"),
                          expected, error)) {
            c.check(false, what + ": cannot read the fixture pair: " + error);
            continue;
        }
        const mxqtest::JsonValue *want = expected.member("validate");
        if (want == nullptr || !want->is_string()) {
            c.check(false, what + ": the sidecar states no validate status");
            continue;
        }
        const mxqtest::JsonValue *detail_contains =
            expected.member("detail_contains");

        MxqImportOutcome outcome = MXQ_IMPORT_EXISTING;
        uint64_t record_id = 99;
        MxqRecordSummary summary = make_summary();
        err = make_error();
        const MxqStatus rc =
            mxq_store_import(core, bytes_of(bytes), bytes.size(), &outcome,
                             &record_id, &summary, &err);
        c.check_eq(std::string(mxq_status_name(rc)), want->string(),
                   what + ": mxq_store_import");
        c.check_eq(static_cast<int64_t>(record_id), 0,
                   what + ": a refused import yields no record id");
        if (detail_contains != nullptr && detail_contains->is_string()) {
            const std::string detail(err.detail);
            c.check(detail.find(detail_contains->string()) !=
                        std::string::npos,
                    what + ": the import diagnostic must contain \"" +
                        detail_contains->string() + "\", got \"" + detail +
                        "\"");
        }

        MxqGame *preview = reinterpret_cast<MxqGame *>(1);
        err = make_error();
        c.check_eq(std::string(mxq_status_name(mxq_game_open_archive(
                       core, bytes_of(bytes), bytes.size(), &preview, &err))),
                   want->string(), what + ": mxq_game_open_archive");
        c.check(preview == nullptr,
                what + ": a refused preview issues no session");

        check_library_unchanged(c, before, library_of(core, c, what),
                                what + ": a refused import changes nothing");
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * The four active shapes. They are complete documents of the version this
 * build defines, and the codec reads them; what they are not is an exported
 * game, because an export is one immutable History record and a History record
 * has an ending. Import refuses them before the store is consulted, so the
 * schema's own "a record can only enter this library as imported once it is
 * complete" never has to be the thing that says so — a database constraint is
 * the wrong voice for a file problem.
 */
void case_an_unfinished_game_is_not_an_import(
    const std::vector<fs::path> &active_shapes) {
    Case c("a document that records no end is refused, and not by the schema");
    const fs::path store = scratch_dir("unfinished");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }
    const Library before = library_of(core, c, "before");

    for (const fs::path &file : active_shapes) {
        const std::string what = file.stem().string();
        std::string bytes;
        if (!read_file(file, bytes)) {
            c.check(false, what + ": cannot read the golden");
            continue;
        }

        err = make_error();
        c.check_status(mxq_store_import(core, bytes_of(bytes), bytes.size(),
                                        nullptr, nullptr, nullptr, &err),
                       MXQ_ERR_ARCHIVE_MALFORMED, what + ": mxq_store_import");
        const std::string detail(err.detail);
        c.check(detail.find("records no end") != std::string::npos,
                what + ": the refusal says what is missing, got \"" + detail +
                    "\"");

        MxqGame *preview = nullptr;
        err = make_error();
        c.check_status(mxq_game_open_archive(core, bytes_of(bytes),
                                             bytes.size(), &preview, &err),
                       MXQ_ERR_ARCHIVE_MALFORMED,
                       what + ": mxq_game_open_archive refuses it too");

        check_library_unchanged(c, before, library_of(core, c, what),
                                what + ": nothing was written");
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/* ---------------------------------------------------------------------- */
/* The round trip                                                          */
/* ---------------------------------------------------------------------- */

/*
 * A golden imported, exported, and imported again into a second library.
 *
 * Four properties, in the order they depend on one another:
 *
 *   - what the first library stores is the file, byte for byte. The golden is
 *     already canonical, so canonicalisation is the identity on it, and origin
 *     survives because an import preserves the export event the file describes
 *     rather than restamping it;
 *   - an export changes exactly one member. Its content bytes are the golden's
 *     content bytes, and two exports of one record differ only in origin, which
 *     is the whole of "regenerated on every export, never hashed, never
 *     compared";
 *   - the exported file imports into a fresh library and lands the same game:
 *     every field of the record agrees except the two the library owns — the
 *     record id it issued and the instant it was added;
 *   - and the second library's stored content is still the golden's content,
 *     so the game survived two encodes, two decodes and a restamp unaltered.
 */
void case_a_golden_round_trips(const std::vector<fs::path> &completed) {
    Case c("export and import round-trip a game without altering it");

    for (const fs::path &file : completed) {
        const std::string what = file.stem().string();
        std::string golden;
        if (!read_file(file, golden)) {
            c.check(false, what + ": cannot read the golden");
            continue;
        }

        MxqCore *first = nullptr;
        MxqError err = make_error();
        if (init_core(scratch_dir("trip-a-" + what), &first, &err) != MXQ_OK) {
            c.check(false, what + ": mxq_core_init failed");
            continue;
        }

        MxqImportOutcome outcome = MXQ_IMPORT_EXISTING;
        uint64_t record_id = 0;
        MxqRecordSummary imported = make_summary();
        err = make_error();
        const MxqStatus rc =
            mxq_store_import(first, bytes_of(golden), golden.size(), &outcome,
                             &record_id, &imported, &err);
        c.check_status(rc, MXQ_OK, what + ": importing the golden");
        if (rc != MXQ_OK) {
            c.check(false, what + ": " + err.detail);
            mxq_core_shutdown(first, nullptr);
            continue;
        }
        c.check_eq(outcome, MXQ_IMPORT_CREATED, what + ": a new record");
        c.check(record_id != 0, what + ": the record has an identifier");
        c.check_eq(static_cast<int64_t>(imported.record_id),
                   static_cast<int64_t>(record_id),
                   what + ": the summary is the record's own");
        c.check_eq(imported.provenance, MXQ_PROVENANCE_IMPORTED,
                   what + ": provenance is the library's word, not the file's");
        c.check_eq(imported.pinned, 0, what + ": an import is not pinned");
        c.check_eq(imported.is_active, 0,
                   what + ": an import is never the active game");
        c.check(imported.added_at_ms > 0,
                what + ": the record carries a History-added time");
        c.check_eq(library_of(first, c, what).count, 1,
                   what + ": the library holds exactly the imported game");

        c.check_eq(stored_bytes(first, record_id, c, what), golden,
                   what + ": the row holds the file, byte for byte");

        const std::string exported = export_of(first, record_id, c, what);
        c.check_eq(content_of(exported), content_of(golden),
                   what + ": an export carries the record's own content");
        c.check(!content_of(exported).empty(),
                what + ": the content was found at all");
        c.check_eq(game_id_of(exported), game_id_of(golden),
                   what + ": identity is frozen forever");

        const std::string again = export_of(first, record_id, c, what);
        c.check_eq(content_of(again), content_of(exported),
                   what + ": two exports carry the same game");
        c.check(origin_of(again) != origin_of(exported),
                what + ": and each names its own export event");

        /* The second library, which has never seen this game. */
        MxqCore *second = nullptr;
        mxq_core_shutdown(first, nullptr);
        err = make_error();
        if (init_core(scratch_dir("trip-b-" + what), &second, &err) != MXQ_OK) {
            c.check(false, what + ": the second mxq_core_init failed");
            continue;
        }

        MxqRecordSummary reimported = make_summary();
        uint64_t second_id = 0;
        outcome = MXQ_IMPORT_EXISTING;
        err = make_error();
        c.check_status(mxq_store_import(second, bytes_of(exported),
                                        exported.size(), &outcome, &second_id,
                                        &reimported, &err),
                       MXQ_OK, what + ": importing the export");
        c.check_eq(outcome, MXQ_IMPORT_CREATED,
                   what + ": a library that has never seen it creates it");
        check_summaries_agree(c, imported, reimported,
                              what + ": the record survives the round trip");
        c.check_eq(content_of(stored_bytes(second, second_id, c, what)),
                   content_of(golden),
                   what + ": and so does its content, exactly");

        mxq_core_shutdown(second, nullptr);
    }

    c.report();
}

/* ---------------------------------------------------------------------- */
/* Duplicate and conflict                                                  */
/* ---------------------------------------------------------------------- */

/*
 * The same game twice, and the same game after a round trip through a file.
 *
 * The second is the sharper of the two: an export restamps origin, so the
 * bytes differ from what the library holds while the game does not. A duplicate
 * test that compared documents rather than content would report a new game
 * here, and the user would collect a second copy of every file they exported
 * and re-imported.
 */
void case_a_duplicate_returns_the_existing_record(const fs::path &file) {
    Case c("importing a game the library already has returns that record");
    const fs::path store = scratch_dir("duplicate");
    std::string golden;
    if (!read_file(file, golden)) {
        c.check(false, "cannot read the golden");
        c.report();
        return;
    }

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }

    MxqImportOutcome outcome = MXQ_IMPORT_EXISTING;
    uint64_t first_id = 0;
    MxqRecordSummary first = make_summary();
    err = make_error();
    if (mxq_store_import(core, bytes_of(golden), golden.size(), &outcome,
                         &first_id, &first, &err) != MXQ_OK) {
        c.check(false, std::string("the first import failed: ") + err.detail);
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }
    const Library after_first = library_of(core, c, "after the first import");

    MxqRecordSummary second = make_summary();
    uint64_t second_id = 0;
    outcome = MXQ_IMPORT_CREATED;
    err = make_error();
    c.check_status(mxq_store_import(core, bytes_of(golden), golden.size(),
                                    &outcome, &second_id, &second, &err),
                   MXQ_OK, "importing the same file again is success");
    c.check_eq(outcome, MXQ_IMPORT_EXISTING, "and says the record existed");
    c.check_eq(static_cast<int64_t>(second_id),
               static_cast<int64_t>(first_id),
               "the existing record is the one returned");
    check_summaries_agree(c, first, second, "the record it returns");
    c.check_eq(second.added_at_ms, first.added_at_ms,
               "a duplicate does not re-date the record it found");
    check_library_unchanged(c, after_first, library_of(core, c, "duplicate"),
                            "a duplicate writes nothing at all");

    /* And the same game after an export, whose origin names a different
     * event: origin is never hashed and never compared, so this is the same
     * game arriving in different bytes. */
    const std::string exported = export_of(core, first_id, c, "the export");
    c.check(exported != golden,
            "the export really does differ from what the library holds");
    MxqRecordSummary third = make_summary();
    uint64_t third_id = 0;
    outcome = MXQ_IMPORT_CREATED;
    err = make_error();
    c.check_status(mxq_store_import(core, bytes_of(exported), exported.size(),
                                    &outcome, &third_id, &third, &err),
                   MXQ_OK, "importing this library's own export");
    c.check_eq(outcome, MXQ_IMPORT_EXISTING,
               "a restamped origin is not a different game");
    c.check_eq(static_cast<int64_t>(third_id), static_cast<int64_t>(first_id),
               "and it is the same record");
    check_library_unchanged(c, after_first,
                            library_of(core, c, "the re-import"),
                            "the library still holds one game");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * One identity, two games. The file is refused and the library is not changed,
 * which is the whole of the accepted answer: an identity conflict has no
 * resolution the core may pick, because both documents claim to be the same
 * game and only the person holding them knows which one they meant.
 */
void case_an_identity_conflict_changes_nothing(const fs::path &mine,
                                               const fs::path &theirs) {
    Case c("a second game under one identity is refused, and nothing changes");
    const fs::path store = scratch_dir("conflict");

    std::string held;
    std::string other;
    if (!read_file(mine, held) || !read_file(theirs, other)) {
        c.check(false, "cannot read the two goldens");
        c.report();
        return;
    }

    /* The same game_id, a different game. game_id is 36 characters wherever it
     * appears, so the substitution leaves a canonical document — which matters,
     * because a file refused for its spelling would prove nothing about
     * identity. */
    const std::string held_id = game_id_of(held);
    const std::string other_id = game_id_of(other);
    c.check(held_id.size() == 36 && other_id.size() == 36 &&
                held_id != other_id,
            "the two goldens carry two different identities to begin with");
    std::string collided = other;
    const size_t at = collided.find(other_id);
    if (at == std::string::npos) {
        c.check(false, "cannot find the identity to rewrite");
        c.report();
        return;
    }
    collided.replace(at, 36, held_id);

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }

    uint64_t record_id = 0;
    err = make_error();
    if (mxq_store_import(core, bytes_of(held), held.size(), nullptr, &record_id,
                         nullptr, &err) != MXQ_OK) {
        c.check(false, std::string("the first import failed: ") + err.detail);
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }
    const Library before = library_of(core, c, "before the conflict");
    const std::string before_bytes =
        stored_bytes(core, record_id, c, "before the conflict");

    /* The colliding file is valid on its own: it is refused for the identity
     * it claims and for nothing else, which is what makes this a conflict test
     * rather than a validation test. */
    MxqGame *preview = nullptr;
    err = make_error();
    c.check_status(mxq_game_open_archive(core, bytes_of(collided),
                                         collided.size(), &preview, &err),
                   MXQ_OK, "the colliding file is a valid game");
    mxq_game_release(preview);

    MxqImportOutcome outcome = MXQ_IMPORT_EXISTING;
    uint64_t refused_id = 99;
    err = make_error();
    c.check_status(mxq_store_import(core, bytes_of(collided), collided.size(),
                                    &outcome, &refused_id, nullptr, &err),
                   MXQ_ERR_STORE_IDENTITY_CONFLICT, "importing it anyway");
    c.check_eq(static_cast<int64_t>(refused_id), 0,
               "a refused import yields no record id");

    check_library_unchanged(c, before, library_of(core, c, "after"),
                            "a conflict is not a mutation");
    c.check_eq(stored_bytes(core, record_id, c, "after"), before_bytes,
               "and the record it collided with is exactly as it was");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/* ---------------------------------------------------------------------- */
/* What an import must not disturb                                         */
/* ---------------------------------------------------------------------- */

/*
 * An import while a game is being played. The active game is the one thing the
 * accepted contract names twice — "never creates or replaces the active game" —
 * and here it is a played line with a committed move in it, so a disturbance
 * would show as bytes rather than as a flag.
 *
 * The active game's record id is also asked of the export, because the active
 * game is not a History record and exporting it would be exporting an unfinished
 * game.
 */
void case_an_import_leaves_the_active_game_alone(const fs::path &file) {
    Case c("an import never creates, replaces or disturbs the active game");
    const fs::path store = scratch_dir("active");
    std::string golden;
    if (!read_file(file, golden)) {
        c.check(false, "cannot read the golden");
        c.report();
        return;
    }

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }

    MxqGameConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.mode = MXQ_PLAY_MODE_FREE_PLAY;
    config.human_side = MXQ_COLOR_NONE;
    config.ai_level = MXQ_AI_LEVEL_NONE;
    config.first_mover_choice = MXQ_FIRST_MOVER_NONE;
    config.local_side = MXQ_COLOR_NONE;

    MxqGame *game = nullptr;
    err = make_error();
    if (mxq_game_create(core, &config, &game, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_game_create failed: ") + err.detail);
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }
    err = make_error();
    c.check_status(mxq_game_apply_move(game, "b1b3", nullptr, nullptr, &err),
                   MXQ_OK, "the active game takes a move");

    MxqBlob *blob = nullptr;
    err = make_error();
    c.check_status(mxq_archive_encode(core, game, &blob, &err), MXQ_OK,
                   "the active game encodes");
    const std::string before = blob_text(blob);
    mxq_blob_release(blob);

    MxqRecordSummary active = make_summary();
    uint8_t exists = 0;
    err = make_error();
    c.check_status(mxq_store_active_summary(core, &active, nullptr, &exists,
                                            &err),
                   MXQ_OK, "the active summary before");
    c.check_eq(exists, 1, "there is an active game to disturb");

    /* Exporting it is not found: an export is one immutable History record. */
    MxqBlob *refused = reinterpret_cast<MxqBlob *>(1);
    err = make_error();
    c.check_status(mxq_store_export(core, active.record_id, &refused, &err),
                   MXQ_ERR_STORE_NOT_FOUND, "exporting the active game");
    c.check(refused == nullptr, "and it hands back no blob");

    uint64_t record_id = 0;
    MxqRecordSummary imported = make_summary();
    err = make_error();
    c.check_status(mxq_store_import(core, bytes_of(golden), golden.size(),
                                    nullptr, &record_id, &imported, &err),
                   MXQ_OK, "importing while a game is being played");
    c.check(record_id != active.record_id,
            "the imported record is not the active game's row");
    c.check_eq(imported.is_active, 0, "and it is not active");

    MxqRecordSummary after = make_summary();
    err = make_error();
    c.check_status(mxq_store_active_summary(core, &after, nullptr, &exists,
                                            &err),
                   MXQ_OK, "the active summary after");
    c.check_eq(exists, 1, "the game is still active");
    c.check_eq(after.record_id, active.record_id, "and still the same row");
    c.check_eq(after.move_count, active.move_count, "with its line intact");

    err = make_error();
    blob = nullptr;
    c.check_status(mxq_archive_encode(core, game, &blob, &err), MXQ_OK,
                   "the active game still encodes");
    c.check_eq(blob_text(blob), before,
               "byte for byte what it was before the import");
    mxq_blob_release(blob);

    /* The played game can still be moved on, which is the point of leaving it
     * alone at all. */
    err = make_error();
    c.check_status(mxq_game_apply_move(game, "b7b5", nullptr, nullptr, &err),
                   MXQ_OK, "and it still accepts moves");

    mxq_game_release(game);
    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * A failed import, driven through the store's own transaction: a second
 * connection holds the database's write lock, so BEGIN IMMEDIATE is refused as
 * SQLITE_BUSY exactly as a real contended write would be. Nothing sleeps, and
 * no seam in the core arranges it.
 *
 * What must hold afterwards is docs/game-data.md's whole sentence about it: the
 * file is never partially imported, the library is exactly as it was, and the
 * same call succeeds once the store is free — which is what makes the retry the
 * accepted import-failure flow offers a retry rather than a second chance at a
 * different outcome.
 */
void case_a_failed_import_is_retryable(const fs::path &file) {
    Case c("an import that cannot commit writes nothing and retries clean");
    const fs::path store = scratch_dir("contended");
    std::string golden;
    if (!read_file(file, golden)) {
        c.check(false, "cannot read the golden");
        c.report();
        return;
    }

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }
    const Library before = library_of(core, c, "before");

    sqlite3 *blocker = nullptr;
    const std::string path = (store / "library.sqlite3").string();
    if (sqlite3_open_v2(path.c_str(), &blocker, SQLITE_OPEN_READWRITE,
                        nullptr) != SQLITE_OK ||
        sqlite3_exec(blocker, "BEGIN EXCLUSIVE;", nullptr, nullptr, nullptr) !=
            SQLITE_OK) {
        c.check(false, "the second connection cannot take the write lock");
        sqlite3_close(blocker);
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }

    MxqImportOutcome outcome = MXQ_IMPORT_EXISTING;
    uint64_t record_id = 99;
    MxqRecordSummary summary = make_summary();
    err = make_error();
    const MxqStatus refused =
        mxq_store_import(core, bytes_of(golden), golden.size(), &outcome,
                         &record_id, &summary, &err);
    c.check(mxq_status_domain(refused) == MXQ_DOMAIN_STORE,
            std::string("an import that cannot commit fails in the store "
                        "domain, got ") +
                mxq_status_name(refused));
    c.check_eq(static_cast<int64_t>(record_id), 0,
               "a failed import yields no record id");
    c.check_eq(summary.record_id, 0,
               "and no summary of a record that was not written");

    c.check(sqlite3_exec(blocker, "ROLLBACK;", nullptr, nullptr, nullptr) ==
                SQLITE_OK,
            "the lock is released");
    sqlite3_close(blocker);

    check_library_unchanged(c, before, library_of(core, c, "after the refusal"),
                            "a failed import is not a mutation");

    /* The same call, on the same bytes, now succeeds: what failed was the
     * commit and not the file. */
    err = make_error();
    record_id = 0;
    outcome = MXQ_IMPORT_EXISTING;
    c.check_status(mxq_store_import(core, bytes_of(golden), golden.size(),
                                    &outcome, &record_id, &summary, &err),
                   MXQ_OK, "the retry");
    c.check_eq(outcome, MXQ_IMPORT_CREATED, "which creates the record");
    c.check(record_id != 0, "with an identifier of its own");
    c.check_eq(library_of(core, c, "after the retry").count, 1,
               "and the library holds exactly one game");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/* ---------------------------------------------------------------------- */
/* The preview                                                             */
/* ---------------------------------------------------------------------- */

/*
 * A file opened as a session without being imported, which is what the app
 * shows someone before they decide.
 *
 * A detached session is a whole game — its identity, its line, its ending — and
 * re-encoding it reproduces the file it came from, which is the same property
 * that makes a stored row comparable with its own bytes. What it is not is a
 * record: nothing was written, and releasing it leaves the library exactly as
 * it found it.
 */
void case_a_preview_is_a_game_and_not_a_record(const fs::path &file) {
    Case c("an archive opens as a read-only session without becoming a record");
    const fs::path store = scratch_dir("preview");
    std::string golden;
    if (!read_file(file, golden)) {
        c.check(false, "cannot read the golden");
        c.report();
        return;
    }

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }
    const Library before = library_of(core, c, "before");

    MxqGame *preview = nullptr;
    err = make_error();
    if (mxq_game_open_archive(core, bytes_of(golden), golden.size(), &preview,
                              &err) != MXQ_OK) {
        c.check(false, std::string("mxq_game_open_archive failed: ") +
                           err.detail);
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }

    char id[MXQ_GAME_ID_CAP];
    size_t id_len = 0;
    err = make_error();
    c.check_status(mxq_game_id(preview, id, sizeof(id), &id_len, &err), MXQ_OK,
                   "the preview states its identity");
    c.check_eq(std::string(id), game_id_of(golden),
               "which is the file's, unchanged");

    MxqGameStatus status;
    std::memset(&status, 0, sizeof(status));
    status.struct_size = static_cast<uint32_t>(sizeof(status));
    err = make_error();
    c.check_status(mxq_game_status(preview, &status, &err), MXQ_OK,
                   "the preview reports its state");
    c.check(status.undo_available == 0 && status.claim_available == 0 &&
                status.resign_available == 0 && status.search_expected == 0,
            "a finished game offers no action");

    size_t plies = 0;
    err = make_error();
    const MxqStatus probe =
        mxq_game_move_history(preview, nullptr, 0, &plies, &err);
    c.check(probe == MXQ_OK || probe == MXQ_ERR_ARG_BUFFER_TOO_SMALL,
            "the preview reports its move count");

    MxqPosition position;
    std::memset(&position, 0, sizeof(position));
    position.struct_size = static_cast<uint32_t>(sizeof(position));
    err = make_error();
    c.check_status(mxq_game_position_at(preview, 0, &position, &err), MXQ_OK,
                   "and can be walked from its initial position");

#if defined(NDEBUG)
    /* Mutations are a category error on a session that was never attached —
     * one of the programming errors the contract has assert in a debug build,
     * so the returned status is observable only where the assertion is
     * compiled out. */
    err = make_error();
    c.check_status(mxq_game_apply_move(preview, "b1b3", nullptr, nullptr, &err),
                   MXQ_ERR_STATE_SESSION_READ_ONLY, "a move on a preview");
    err = make_error();
    c.check_status(mxq_game_undo(preview, nullptr, &err),
                   MXQ_ERR_STATE_SESSION_READ_ONLY, "an undo on a preview");
#endif

    MxqBlob *blob = nullptr;
    err = make_error();
    c.check_status(mxq_archive_encode(core, preview, &blob, &err), MXQ_OK,
                   "the preview encodes");
    c.check_eq(blob_text(blob), golden,
               "back to the file it was opened from, byte for byte");
    mxq_blob_release(blob);

    mxq_game_release(preview);
    check_library_unchanged(c, before, library_of(core, c, "after"),
                            "a preview is not a record");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/* ---------------------------------------------------------------------- */
/* The budget                                                              */
/* ---------------------------------------------------------------------- */

/*
 * The accepted validation time budget: two seconds on the slowest supported
 * device, for the largest file the accepted bounds admit.
 *
 * One assertion on the largest golden, with the whole budget as its margin.
 * This is not a benchmark and does not try to be: the number it defends is a
 * ceiling nobody should approach, and a runner that measured a distribution
 * would fail on a loaded machine for reasons that say nothing about the code.
 * The bound that actually keeps import cheap is the size bound the corpus
 * already pins on both sides.
 */
void case_the_largest_golden_imports_inside_the_budget(const fs::path &file) {
    Case c("the largest golden imports well inside the two-second budget");
    const fs::path store = scratch_dir("budget");
    std::string golden;
    if (!read_file(file, golden)) {
        c.check(false, "cannot read the golden");
        c.report();
        return;
    }

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, &core, &err) != MXQ_OK) {
        c.check(false, std::string("mxq_core_init failed: ") + err.detail);
        c.report();
        return;
    }

    const auto started = std::chrono::steady_clock::now();
    err = make_error();
    const MxqStatus rc = mxq_store_import(core, bytes_of(golden), golden.size(),
                                          nullptr, nullptr, nullptr, &err);
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::steady_clock::now() - started)
                             .count();
    c.check_status(rc, MXQ_OK, "importing " + file.stem().string());
    c.check(elapsed < 2000,
            "the import took " + std::to_string(elapsed) +
                " ms, and the accepted budget is 2000");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

#endif /* MXQ_TEST_RULES_FACADE */

} /* namespace */

int main(int argc, char **argv) {
    fs::path fixtures;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--fixtures" && i + 1 < argc) {
            fixtures = argv[++i];
        } else {
            std::cerr << "usage: mxq_interchange_tests [--fixtures <dir>]\n";
            return 2;
        }
    }
    if (fixtures.empty()) {
        if (const char *env = std::getenv("MXQ_ARCHIVE_FIXTURES_DIR")) {
            fixtures = env;
        } else {
#if defined(MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT)
            fixtures = MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT;
#endif
        }
    }
    if (fixtures.empty()) {
        std::cerr << "no archive fixtures directory\n";
        return 2;
    }

    std::cout << "Mini Xiangqi interchange tests\n";
    std::cout << "  fixtures: " << fixtures << "\n";

    case_export_wants_a_history_record();

#if MXQ_TEST_RULES_FACADE
    std::string error;
    const std::vector<fs::path> goldens =
        archives_in(fixtures / "valid", error);
    const std::vector<fs::path> rejected =
        archives_in(fixtures / "rejected", error);
    if (!error.empty() || goldens.empty() || rejected.empty()) {
        std::cerr << "  ERROR the archive corpus is missing: "
                  << (error.empty() ? "one of its directories is empty" : error)
                  << "\n";
        return 2;
    }

    /*
     * The corpus splits itself: a completed golden carries the terminal trio
     * and is what an export produces, an active shape does not and is what the
     * store holds mid-game. Which is which is read from the file rather than
     * listed here, so a new golden joins the right half by being what it is.
     */
    std::vector<fs::path> completed;
    std::vector<fs::path> active_shapes;
    fs::path largest;
    uintmax_t largest_size = 0;
    for (const fs::path &file : goldens) {
        std::string bytes;
        if (!read_file(file, bytes)) {
            std::cerr << "  ERROR cannot read " << file << "\n";
            return 2;
        }
        if (bytes.find("\"ended_at\":") != std::string::npos) {
            completed.push_back(file);
            if (bytes.size() > largest_size) {
                largest_size = bytes.size();
                largest = file;
            }
        } else {
            active_shapes.push_back(file);
        }
    }
    if (completed.size() < 2 || active_shapes.empty()) {
        std::cerr << "  ERROR the corpus no longer has both shapes\n";
        return 2;
    }

    case_the_rejection_corpus_refuses_identically(rejected);
    case_an_unfinished_game_is_not_an_import(active_shapes);
    case_a_golden_round_trips(completed);
    case_a_duplicate_returns_the_existing_record(completed.front());
    case_an_identity_conflict_changes_nothing(completed.front(),
                                              completed.back());
    case_an_import_leaves_the_active_game_alone(completed.front());
    case_a_failed_import_is_retryable(completed.front());
    case_a_preview_is_a_game_and_not_a_record(completed.front());
    case_the_largest_golden_imports_inside_the_budget(largest);
#else
    Case skipped("import, the round trip, and the preview");
    skipped.skip("importing a game needs the rules facade");
    skipped.report();
#endif

    std::cout << "  " << g_passed << " passed, " << g_failed << " failed, "
              << g_skipped << " skipped, " << g_checks << " checks\n";

    std::error_code cleanup;
    fs::remove_all(scratch_root(), cleanup);
    return g_failed == 0 ? 0 : 1;
}
