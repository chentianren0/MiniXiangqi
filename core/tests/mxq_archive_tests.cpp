/*
 * The archive-codec runner: the golden corpus and the rejection corpus in
 * fixtures/archive/, walked file by file.
 *
 * It is the archive's counterpart to the rules-fixture runner. Both corpora are
 * data — a file plus an expectation sidecar — so a new case is a new pair of
 * files and never a new function here, and both are executed through the public
 * C surface only: what the codec must promise is what mxq.h says, not what its
 * internals happen to do.
 *
 * Three things are asserted of every golden:
 *
 *   - mxq_archive_probe accepts it and fills MxqArchiveInfo exactly as the
 *     sidecar states;
 *   - mxq_archive_validate accepts it and fills a byte-identical
 *     MxqArchiveInfo, because validate is documented as everything probe does
 *     and then some;
 *   - its bytes are already in canonical form, checked here rather than
 *     assumed, so that the golden files are usable as byte-exact inputs by the
 *     encoder that will have to reproduce them.
 *
 * Of every rejection fixture, the sidecar states the status probe must return
 * and the status validate must return; they differ exactly for the rules-tier
 * classes, where a structural probe is documented to accept a file that a full
 * validation refuses.
 *
 * Without MXQ_ENABLE_RULES_FACADE, mxq_archive_validate is not in the library
 * at all — the same stance the session-free rules facade takes — so every
 * validate expectation reports NOT IMPLEMENTED, which is never counted as a
 * pass, while every probe expectation still runs. That is the whole difference
 * between the two configurations.
 */

#include "mxq.h"

#include "mxq_json.hpp"

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

int g_failed = 0;      /* fixtures with at least one unmet expectation */
int g_errored = 0;     /* fixtures that could not be read at all */
int g_passed = 0;
int g_skipped = 0;     /* expectations that need a facade this build lacks */
int g_checks = 0;      /* expectations actually evaluated */

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

MxqArchiveInfo make_info() {
    MxqArchiveInfo info;
    std::memset(&info, 0, sizeof(info));
    info.struct_size = static_cast<uint32_t>(sizeof(info));
    return info;
}

/* ---------------------------------------------------------------------- */
/* One fixture's accumulated verdict                                       */
/* ---------------------------------------------------------------------- */

struct Case {
    std::string name;
    std::vector<std::string> messages;
    bool skipped_something = false;

    void check(bool ok, const std::string &what) {
        ++g_checks;
        if (!ok) {
            messages.push_back(what);
        }
    }

    void check_eq(const std::string &got, const std::string &want,
                  const std::string &what) {
        check(got == want, what + ": expected \"" + want + "\", got \"" + got +
                               "\"");
    }

    void check_eq(int64_t got, int64_t want, const std::string &what) {
        check(got == want, what + ": expected " + std::to_string(want) +
                               ", got " + std::to_string(got));
    }
};

void report(const Case &c) {
    if (!c.messages.empty()) {
        ++g_failed;
        std::cout << "  FAIL      " << c.name << "\n";
        for (const std::string &m : c.messages) {
            std::cout << "            " << m << "\n";
        }
        return;
    }
    if (c.skipped_something) {
        ++g_skipped;
        std::cout << "  PART SKIP " << c.name
                  << "  (validate needs the rules facade)\n";
        return;
    }
    ++g_passed;
    std::cout << "  PASS      " << c.name << "\n";
}

/* ---------------------------------------------------------------------- */
/* The serialised vocabularies, for reading the sidecars                   */
/* ---------------------------------------------------------------------- */

std::string mode_text(MxqPlayMode mode) {
    switch (mode) {
    case MXQ_PLAY_MODE_HUMAN_VS_AI: return "human-vs-ai";
    case MXQ_PLAY_MODE_FREE_PLAY: return "free-play";
    default: break;
    }
    return "unknown(" + std::to_string(mode) + ")";
}

/* The NONE constants have no serialised counterpart: the archive omits the
 * member, so a sidecar spells them null. */
std::string color_text(MxqColor color) {
    switch (color) {
    case MXQ_COLOR_NONE: return "null";
    case MXQ_COLOR_RED: return "red";
    case MXQ_COLOR_BLACK: return "black";
    default: break;
    }
    return "unknown(" + std::to_string(color) + ")";
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

std::string end_reason_text(MxqEndReason reason) {
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
    default: break;
    }
    return "unknown(" + std::to_string(reason) + ")";
}

/* A sidecar member that is either a string or null, rendered the way the
 * *_text helpers above render the corresponding NONE constant. */
std::string text_or_null(const mxqtest::JsonValue *value) {
    if (value == nullptr || value->is_null()) {
        return "null";
    }
    if (value->is_string()) {
        return value->string();
    }
    return "<not a string>";
}

/* ---------------------------------------------------------------------- */
/* Canonical form, checked rather than assumed                             */
/* ---------------------------------------------------------------------- */

/*
 * The canonical form of docs/game-data.md: UTF-8, one line, members in
 * codepoint order, no insignificant whitespace, integers only.
 *
 * The reader in the core deliberately does not require this of an incoming
 * file — canonicalisation happens after validation and before hashing, so a
 * differently spelled but equivalent document is accepted. The golden files
 * are held to it anyway, because they are what the encoder must be able to
 * reproduce byte for byte.
 *
 * This scanner assumes the document already parsed; the codec has said so by
 * the time it runs.
 */
class CanonicalScan {
public:
    CanonicalScan(const std::string &text, std::vector<std::string> &problems)
        : text_(text), problems_(problems) {}

    void run() {
        if (text_.empty()) {
            problems_.push_back("the file is empty");
            return;
        }
        value();
        if (pos_ != text_.size()) {
            problems_.push_back(
                "trailing bytes after the document (a canonical archive is "
                "exactly one line with no terminator)");
        }
    }

private:
    char peek() const { return pos_ < text_.size() ? text_[pos_] : '\0'; }

    void value() {
        const char c = peek();
        if (c == '{') {
            object();
        } else if (c == '[') {
            array();
        } else if (c == '"') {
            std::string ignored;
            string(ignored);
        } else if (c == 't' || c == 'f' || c == 'n') {
            while (pos_ < text_.size() && text_[pos_] >= 'a' &&
                   text_[pos_] <= 'z') {
                ++pos_;
            }
        } else {
            number();
        }
    }

    void object() {
        ++pos_; /* '{' */
        if (peek() == '}') {
            ++pos_;
            return;
        }
        std::string previous;
        for (;;) {
            std::string name;
            if (peek() != '"') {
                problems_.push_back("a member name was expected at byte " +
                                    std::to_string(pos_));
                return;
            }
            string(name);
            if (!previous.empty() && !(previous < name)) {
                problems_.push_back("members are not in codepoint order: \"" +
                                    previous + "\" precedes \"" + name + "\"");
            }
            previous = name;
            if (peek() != ':') {
                problems_.push_back("\":\" was expected at byte " +
                                    std::to_string(pos_));
                return;
            }
            ++pos_;
            value();
            if (peek() == ',') {
                ++pos_;
                continue;
            }
            if (peek() == '}') {
                ++pos_;
                return;
            }
            problems_.push_back("insignificant whitespace or a stray byte at " +
                                std::to_string(pos_));
            return;
        }
    }

    void array() {
        ++pos_; /* '[' */
        if (peek() == ']') {
            ++pos_;
            return;
        }
        for (;;) {
            value();
            if (peek() == ',') {
                ++pos_;
                continue;
            }
            if (peek() == ']') {
                ++pos_;
                return;
            }
            problems_.push_back("insignificant whitespace or a stray byte at " +
                                std::to_string(pos_));
            return;
        }
    }

    void string(std::string &out) {
        out.clear();
        ++pos_; /* the opening quote */
        while (pos_ < text_.size() && text_[pos_] != '"') {
            if (text_[pos_] == '\\') {
                out.push_back(text_[pos_]);
                ++pos_;
                if (pos_ < text_.size()) {
                    out.push_back(text_[pos_]);
                    ++pos_;
                }
                continue;
            }
            out.push_back(text_[pos_]);
            ++pos_;
        }
        ++pos_; /* the closing quote */
    }

    void number() {
        const size_t start = pos_;
        if (peek() == '-') {
            ++pos_;
        }
        while (pos_ < text_.size() && text_[pos_] >= '0' && text_[pos_] <= '9') {
            ++pos_;
        }
        if (pos_ == start) {
            problems_.push_back("a value was expected at byte " +
                                std::to_string(start));
            ++pos_;
            return;
        }
        if (pos_ < text_.size() &&
            (text_[pos_] == '.' || text_[pos_] == 'e' || text_[pos_] == 'E')) {
            problems_.push_back("a number that is not an integer at byte " +
                                std::to_string(start));
        }
    }

    const std::string        &text_;
    std::vector<std::string> &problems_;
    size_t                    pos_ = 0;
};

/* ---------------------------------------------------------------------- */
/* Reading a fixture pair                                                  */
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

/* ---------------------------------------------------------------------- */
/* The two corpora                                                         */
/* ---------------------------------------------------------------------- */

MxqStatus probe(MxqCore *core, const std::string &bytes, MxqArchiveInfo &info,
                MxqError &err) {
    info = make_info();
    err = make_error();
    return mxq_archive_probe(core, reinterpret_cast<const uint8_t *>(
                                       bytes.data()),
                             bytes.size(), &info, &err);
}

#if MXQ_TEST_RULES_FACADE
MxqStatus validate(MxqCore *core, const std::string &bytes,
                   MxqArchiveInfo &info, MxqError &err) {
    info = make_info();
    err = make_error();
    return mxq_archive_validate(core, reinterpret_cast<const uint8_t *>(
                                          bytes.data()),
                                bytes.size(), &info, &err);
}
#endif

void check_info(Case &c, const MxqArchiveInfo &info,
                const mxqtest::JsonValue &want, const std::string &where) {
    const mxqtest::JsonValue *version = want.member("archive_version");
    c.check_eq(static_cast<int64_t>(info.archive_version),
               version != nullptr ? static_cast<int64_t>(version->number()) : -1,
               where + ".archive_version");

    const mxqtest::JsonValue *moves = want.member("move_count");
    c.check_eq(static_cast<int64_t>(info.move_count),
               moves != nullptr ? static_cast<int64_t>(moves->number()) : -1,
               where + ".move_count");

    c.check_eq(mode_text(info.mode), text_or_null(want.member("mode")),
               where + ".mode");
    c.check_eq(color_text(info.human_side),
               text_or_null(want.member("human_side")), where + ".human_side");
    c.check_eq(outcome_text(info.outcome), text_or_null(want.member("outcome")),
               where + ".outcome");
    c.check_eq(end_reason_text(info.end_reason),
               text_or_null(want.member("end_reason")), where + ".end_reason");

    const mxqtest::JsonValue *started = want.member("started_at_ms");
    c.check_eq(info.started_at_ms,
               started != nullptr ? static_cast<int64_t>(started->number()) : -1,
               where + ".started_at_ms");
    const mxqtest::JsonValue *ended = want.member("ended_at_ms");
    c.check_eq(info.ended_at_ms,
               ended != nullptr ? static_cast<int64_t>(ended->number()) : -1,
               where + ".ended_at_ms");
    c.check_eq(std::string(info.game_id), text_or_null(want.member("game_id")),
               where + ".game_id");
}

void run_golden(MxqCore *core, const fs::path &file, const fs::path &sidecar) {
    Case c;
    c.name = "valid/" + file.filename().string();

    std::string bytes;
    mxqtest::JsonValue expected;
    std::string error;
    if (!read_file(file, bytes) || !read_sidecar(sidecar, expected, error)) {
        ++g_errored;
        std::cout << "  ERROR     " << c.name << "\n            "
                  << (error.empty() ? "cannot read the archive" : error) << "\n";
        return;
    }
    const mxqtest::JsonValue *want_info = expected.member("info");
    if (want_info == nullptr || !want_info->is_object()) {
        ++g_errored;
        std::cout << "  ERROR     " << c.name
                  << "\n            the sidecar has no \"info\" object\n";
        return;
    }

    /* The golden bytes are canonical. */
    std::vector<std::string> canonical_problems;
    CanonicalScan(bytes, canonical_problems).run();
    c.check(canonical_problems.empty(),
            "the golden file is not in canonical form: " +
                (canonical_problems.empty() ? std::string()
                                            : canonical_problems.front()));

    MxqArchiveInfo probed;
    MxqError err;
    MxqStatus rc = probe(core, bytes, probed, err);
    c.check(rc == MXQ_OK, std::string("mxq_archive_probe rejected it: ") +
                              mxq_status_name(rc) + ": " + err.detail);
    if (rc == MXQ_OK) {
        check_info(c, probed, *want_info, "probe");
    }

#if MXQ_TEST_RULES_FACADE
    MxqArchiveInfo validated;
    rc = validate(core, bytes, validated, err);
    c.check(rc == MXQ_OK, std::string("mxq_archive_validate rejected it: ") +
                              mxq_status_name(rc) + ": " + err.detail);
    if (rc == MXQ_OK) {
        check_info(c, validated, *want_info, "validate");
        c.check(std::memcmp(&probed, &validated, sizeof(probed)) == 0,
                "probe and validate produced different MxqArchiveInfo values; "
                "validate is documented as everything probe does");
    }
#else
    c.skipped_something = true;
#endif

    report(c);
}

void run_rejection(MxqCore *core, const fs::path &file,
                   const fs::path &sidecar) {
    Case c;
    c.name = "rejected/" + file.filename().string();

    std::string bytes;
    mxqtest::JsonValue expected;
    std::string error;
    if (!read_file(file, bytes) || !read_sidecar(sidecar, expected, error)) {
        ++g_errored;
        std::cout << "  ERROR     " << c.name << "\n            "
                  << (error.empty() ? "cannot read the archive" : error) << "\n";
        return;
    }

    const mxqtest::JsonValue *want_probe = expected.member("probe");
    const mxqtest::JsonValue *want_validate = expected.member("validate");
    const mxqtest::JsonValue *detail_contains =
        expected.member("detail_contains");
    const mxqtest::JsonValue *detail_index = expected.member("detail_index");
    if (want_probe == nullptr || !want_probe->is_string() ||
        want_validate == nullptr || !want_validate->is_string()) {
        ++g_errored;
        std::cout << "  ERROR     " << c.name
                  << "\n            the sidecar needs \"probe\" and "
                     "\"validate\" status names\n";
        return;
    }

    MxqArchiveInfo info;
    MxqError err;
    MxqStatus rc = probe(core, bytes, info, err);
    c.check_eq(std::string(mxq_status_name(rc)), want_probe->string(),
               "mxq_archive_probe status");
    if (rc != MXQ_OK && detail_contains != nullptr &&
        detail_contains->is_string() &&
        want_probe->string() != "MXQ_OK") {
        const std::string detail = err.detail;
        c.check(detail.find(detail_contains->string()) != std::string::npos,
                "the probe detail does not name the rejection: expected to "
                "find \"" +
                    detail_contains->string() + "\" in \"" + detail + "\"");
    }

#if MXQ_TEST_RULES_FACADE
    rc = validate(core, bytes, info, err);
    c.check_eq(std::string(mxq_status_name(rc)), want_validate->string(),
               "mxq_archive_validate status");
    if (rc != MXQ_OK && detail_contains != nullptr &&
        detail_contains->is_string()) {
        const std::string detail = err.detail;
        c.check(detail.find(detail_contains->string()) != std::string::npos,
                "the validate detail does not name the rejection: expected to "
                "find \"" +
                    detail_contains->string() + "\" in \"" + detail + "\"");
    }
    if (detail_index != nullptr && detail_index->is_number()) {
        c.check_eq(static_cast<int64_t>(err.detail_index),
                   static_cast<int64_t>(detail_index->number()),
                   "MxqError.detail_index");
    }
#else
    /* detail_index belongs to a rules-tier rejection, which only validate
     * reaches. */
    (void)detail_index;
    (void)want_validate;
    c.skipped_something = true;
#endif

    report(c);
}

/* ---------------------------------------------------------------------- */
/* The limits no committed file should carry                               */
/* ---------------------------------------------------------------------- */

/*
 * Two accepted import limits are size limits, and a fixture file for either
 * would be a megabyte or seventy kilobytes of noise in the repository. They are
 * built here instead, each side of its boundary, which also pins that the
 * limits are boundaries rather than approximations.
 */
std::string document_with_plies(size_t count) {
    std::string doc =
        "{\"archive_format\":\"minixiangqi-game\",\"archive_version\":1,"
        "\"content\":{\"mode\":\"free-play\",\"moves\":[";
    for (size_t i = 0; i < count; ++i) {
        if (i != 0) {
            doc += ',';
        }
        doc += "\"b1b3\"";
    }
    doc +=
        "],\"rules_id\":\"minixiangqi\",\"rules_version\":1,"
        "\"start_fen\":\"rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1\","
        "\"started_at\":\"2026-01-01T00:00:00.000Z\"},"
        "\"game_id\":\"019b76da-a800-7000-8000-000000000000\","
        "\"origin\":{\"app_version\":\"1.0.0\","
        "\"exported_at\":\"2026-01-01T00:01:00.000Z\"}}";
    return doc;
}

void run_synthesised(MxqCore *core, const std::string &golden) {
    {
        Case c;
        c.name = "synthesised/exactly-1-MiB";
        std::string bytes = golden;
        /* Padding with trailing whitespace, which the read path accepts: the
         * canonical form is what the core writes, not an extra acceptance
         * rule on what it reads. */
        bytes.append(1024u * 1024u - bytes.size(), ' ');
        MxqArchiveInfo info;
        MxqError err;
        const MxqStatus rc = probe(core, bytes, info, err);
        c.check(rc == MXQ_OK, std::string("a document of exactly 1 MiB must be "
                                          "accepted, got ") +
                                  mxq_status_name(rc) + ": " + err.detail);
        report(c);
    }
    {
        Case c;
        c.name = "synthesised/over-1-MiB";
        std::string bytes = golden;
        bytes.append(1024u * 1024u + 1u - bytes.size(), ' ');
        MxqArchiveInfo info;
        MxqError err;
        const MxqStatus rc = probe(core, bytes, info, err);
        c.check_eq(std::string(mxq_status_name(rc)),
                   std::string("MXQ_ERR_ARCHIVE_TOO_LARGE"),
                   "one byte past the 1 MiB import limit");
        report(c);
    }
    {
        Case c;
        c.name = "synthesised/exactly-10000-plies";
        const std::string bytes = document_with_plies(10000);
        MxqArchiveInfo info;
        MxqError err;
        const MxqStatus rc = probe(core, bytes, info, err);
        c.check(rc == MXQ_OK,
                std::string("10 000 plies is within the import limit, got ") +
                    mxq_status_name(rc) + ": " + err.detail);
        if (rc == MXQ_OK) {
            c.check_eq(static_cast<int64_t>(info.move_count), 10000,
                       "move_count");
        }
        report(c);
    }
    {
        Case c;
        c.name = "synthesised/over-10000-plies";
        const std::string bytes = document_with_plies(10001);
        MxqArchiveInfo info;
        MxqError err;
        const MxqStatus rc = probe(core, bytes, info, err);
        c.check_eq(std::string(mxq_status_name(rc)),
                   std::string("MXQ_ERR_ARCHIVE_TOO_LARGE"),
                   "one ply past the 10 000-ply import limit");
        report(c);
    }
}

/* ---------------------------------------------------------------------- */

void run_argument_contract(MxqCore *core, const std::string &golden) {
    Case c;
    c.name = "contract/arguments";

    MxqArchiveInfo info = make_info();
    MxqError err = make_error();
    MxqStatus rc = mxq_archive_probe(core, nullptr, 12, &info, &err);
    c.check_eq(std::string(mxq_status_name(rc)), std::string("MXQ_ERR_ARG_NULL"),
               "null bytes");

    /* A struct_size this build cannot interpret is a programming error, not a
     * rejection of the file. */
    info = make_info();
    info.struct_size = 4;
    err = make_error();
    rc = mxq_archive_probe(core,
                           reinterpret_cast<const uint8_t *>(golden.data()),
                           golden.size(), &info, &err);
    c.check_eq(std::string(mxq_status_name(rc)),
               std::string("MXQ_ERR_ARG_STRUCT_SIZE"), "short struct_size");

    /* The version report the codec dispatches on. */
    uint32_t min_readable = 0;
    uint32_t current = 0;
    err = make_error();
    rc = mxq_archive_supported_versions(&min_readable, &current, &err);
    c.check(rc == MXQ_OK, "mxq_archive_supported_versions failed");
    c.check_eq(static_cast<int64_t>(min_readable), 1, "minimum readable");
    c.check_eq(static_cast<int64_t>(current), 1, "current");

    report(c);
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

} /* namespace */

int main(int argc, char **argv) {
    fs::path fixtures;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--fixtures" && i + 1 < argc) {
            fixtures = argv[++i];
        } else {
            std::cerr << "usage: mxq_archive_tests [--fixtures <dir>]\n";
            return 2;
        }
    }
    if (fixtures.empty()) {
        if (const char *env = std::getenv("MXQ_ARCHIVE_FIXTURES_DIR")) {
            fixtures = env;
        } else {
            fixtures = MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT;
        }
    }

    std::cout << "Mini Xiangqi archive-codec tests\n"
              << "  fixtures        " << fixtures.string() << "\n"
              << "  rules facade    "
              << (MXQ_TEST_RULES_FACADE
                      ? "available; mxq_archive_validate is in this build"
                      : "ABSENT; mxq_archive_validate is not in this build")
              << "\n\n";

    std::string error;
    const std::vector<fs::path> goldens =
        archives_in(fixtures / "valid", error);
    if (!error.empty()) {
        std::cerr << "mxq_archive_tests: " << error << "\n";
        return 2;
    }
    const std::vector<fs::path> rejections =
        archives_in(fixtures / "rejected", error);
    if (!error.empty()) {
        std::cerr << "mxq_archive_tests: " << error << "\n";
        return 2;
    }
    if (goldens.empty() || rejections.empty()) {
        std::cerr << "mxq_archive_tests: both corpora must have fixtures\n";
        return 2;
    }

    /* One core for the run. Its store is a scratch directory: the codec reads
     * bytes and touches no persistent state, but mxq_core_init still opens a
     * store, because the core never runs without one. */
    std::random_device rd;
    char token[17];
    std::snprintf(token, sizeof(token), "%08x%08x", rd(), rd());
    const fs::path scratch =
        fs::temp_directory_path() / ("minixiangqi-archive-tests-" + std::string(token));

    const std::string assets = assets_dir();
    const std::string store = scratch.string();
    MxqCoreConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.api_major = MXQ_API_VERSION_MAJOR;
    config.api_minor = MXQ_API_VERSION_MINOR;
    config.api_patch = MXQ_API_VERSION_PATCH;
    config.flags = MXQ_CORE_FLAG_NONE;
    config.store_directory = store.c_str();
    config.asset_directory = assets.c_str();

    MxqCore *core = nullptr;
    MxqError err = make_error();
    const MxqStatus rc = mxq_core_init(&config, &core, &err);
    if (rc != MXQ_OK) {
        std::cerr << "mxq_archive_tests: mxq_core_init failed: "
                  << mxq_status_name(rc) << ": " << err.detail << "\n";
        return 2;
    }

    for (const fs::path &file : goldens) {
        run_golden(core, file, file.parent_path() /
                                   (file.stem().string() + ".expected.json"));
    }
    for (const fs::path &file : rejections) {
        run_rejection(core, file, file.parent_path() /
                                      (file.stem().string() + ".expected.json"));
    }

    std::string first_golden;
    read_file(goldens.front(), first_golden);
    run_synthesised(core, first_golden);
    run_argument_contract(core, first_golden);

    mxq_core_shutdown(core, nullptr);
    std::error_code ec;
    fs::remove_all(scratch, ec);

    const int total = g_passed + g_failed + g_errored + g_skipped;
    std::cout << "\n"
              << total << " archive fixtures: " << g_passed << " passed, "
              << g_failed << " failed, " << g_errored << " errored, "
              << g_skipped << " partly skipped\n"
              << g_checks << " expectations evaluated\n";
    if (g_skipped > 0) {
        std::cout << "\nNOT IMPLEMENTED: mxq_archive_validate is not in this "
                     "build, so every validate expectation was skipped. Build "
                     "with -DMXQ_ENABLE_RULES_FACADE=ON to evaluate them.\n";
    }
    return (g_failed > 0 || g_errored > 0) ? 1 : 0;
}
