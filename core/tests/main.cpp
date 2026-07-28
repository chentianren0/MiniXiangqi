/*
 * The Mini Xiangqi core test runner.
 *
 * One shared C++ runner, per docs/architecture.md: the approved fixtures are the
 * project's independent authority, so they must be executed by one harness
 * producing identical results on every development platform, without a
 * frontend. Two harnesses would make a discrepancy between them possible.
 *
 * It reports four verdicts per fixture:
 *
 *   PASS      every expectation held.
 *   FAIL      an expectation did not hold. The message names it.
 *   NOT IMPL  the fixture loaded, but its expectations cannot yet be evaluated
 *             because the core's rules facade is not in this binary. Never
 *             counted as a pass.
 *   ERROR     the fixture itself could not be read or does not satisfy the
 *             schema in fixtures/rules/README.md.
 *
 * Exit status is 0 when nothing failed and nothing errored, 1 when something
 * did, and 2 when the run could not be set up at all. NOT IMPLEMENTED does not
 * fail the run — it would be red by construction until the facade lands — but it
 * is stated on its own summary line and is emitted as a skipped test case in the
 * JUnit report.
 */

#include "mxq.h"

#include "mxq_fixture.hpp"
#include "mxq_rules_facade.hpp"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

/* Where the bundled variant configuration lives. The store directory is a
 * scratch path per run; the assets are part of the source tree, so the two are
 * never the same place. $MXQ_ASSETS_DIR overrides, which is how a packaged
 * build points at its own bundle. */
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


enum class Verdict { Pass, Fail, NotImplemented, Error };

struct FixtureResult {
    std::string id;      /* the fixture's own id, or the file stem on error */
    std::string area;
    std::string title;
    std::string file;
    Verdict verdict = Verdict::Error;
    int checks = 0;
    std::vector<std::string> messages;
};

struct Options {
    fs::path fixtures_dir;
    fs::path junit_path;
    bool help = false;
};

const char *kUsage =
    "Usage: mxq_core_tests [--fixtures <dir>] [--junit <file>]\n"
    "\n"
    "  --fixtures <dir>  the approved rules fixtures. Defaults to\n"
    "                    $MXQ_FIXTURES_DIR, then to the fixtures/rules\n"
    "                    directory this build was configured against.\n"
    "  --junit <file>    also write a JUnit XML report there, for CI.\n"
    "  --help            show this message.\n";

/* ---------------------------------------------------------------------- */
/* Small helpers                                                          */
/* ---------------------------------------------------------------------- */

MxqError make_error() {
    MxqError err;
    std::memset(&err, 0, sizeof(err));
    err.struct_size = static_cast<uint32_t>(sizeof(err));
    return err;
}

std::string error_text(const MxqError &err, MxqStatus rc) {
    std::string s = mxq_status_name(rc);
    if (err.detail[0] != '\0') {
        s += ": ";
        s += err.detail;
    }
    return s;
}

const char *verdict_label(Verdict v) {
    switch (v) {
    case Verdict::Pass: return "PASS    ";
    case Verdict::Fail: return "FAIL    ";
    case Verdict::NotImplemented: return "NOT IMPL";
    case Verdict::Error: return "ERROR   ";
    }
    return "????????";
}

std::string join(const std::vector<std::string> &items, const char *sep) {
    std::string s;
    for (size_t i = 0; i < items.size(); ++i) {
        if (i != 0) {
            s += sep;
        }
        s += items[i];
    }
    return s;
}

std::string xml_escape(const std::string &in) {
    std::string out;
    out.reserve(in.size());
    for (const char c : in) {
        switch (c) {
        case '&': out += "&amp;"; break;
        case '<': out += "&lt;"; break;
        case '>': out += "&gt;"; break;
        case '"': out += "&quot;"; break;
        case '\'': out += "&apos;"; break;
        default:
            /* Strip the control characters XML 1.0 cannot carry. */
            if (static_cast<unsigned char>(c) < 0x20 && c != '\n' && c != '\t') {
                out += ' ';
            } else {
                out += c;
            }
        }
    }
    return out;
}

/* ---------------------------------------------------------------------- */
/* Fixture evaluation                                                     */
/* ---------------------------------------------------------------------- */

void check_position(const mxqtest::Fixture &fx, const MxqPosition &position,
                    const std::string &where, std::vector<std::string> &msgs) {
    if (fx.result_fen != position.fen) {
        msgs.push_back(where + ": result_fen expected \"" + fx.result_fen +
                       "\", core produced \"" + position.fen + "\"");
    }
    const bool in_check = position.in_check != 0;
    if (fx.in_check != in_check) {
        msgs.push_back(where + ": in_check expected " +
                       (fx.in_check ? "true" : "false") + ", core reported " +
                       (in_check ? "true" : "false"));
    }
}

void check_game_state(const mxqtest::Fixture &fx, const MxqGameStatus &status,
                      std::vector<std::string> &msgs) {
    const std::string state = mxqtest::state_identifier(status.state);
    if (fx.game_state.state != state) {
        msgs.push_back("game_state.state expected \"" + fx.game_state.state +
                       "\", core reported \"" + state + "\"");
    }
    const std::string reason = mxqtest::reason_identifier(status.reason);
    const std::string want_reason =
        fx.game_state.reason.has_value() ? *fx.game_state.reason : std::string();
    if (want_reason != reason) {
        msgs.push_back("game_state.reason expected \"" + want_reason +
                       "\", core reported \"" + reason + "\"");
    }
    if (fx.game_state.at_occurrence.has_value()) {
        const int64_t got = static_cast<int64_t>(status.at_occurrence);
        if (*fx.game_state.at_occurrence != got) {
            msgs.push_back("game_state.at_occurrence expected " +
                           std::to_string(*fx.game_state.at_occurrence) +
                           ", core reported " + std::to_string(got));
        }
    }
}

void evaluate_fixture(mxqtest::RulesFacade &facade, const mxqtest::Fixture &fx,
                      FixtureResult &result) {
    std::vector<std::string> &msgs = result.messages;

    MxqPosition position;
    std::memset(&position, 0, sizeof(position));
    position.struct_size = static_cast<uint32_t>(sizeof(position));
    MxqGameStatus status;
    std::memset(&status, 0, sizeof(status));
    status.struct_size = static_cast<uint32_t>(sizeof(status));

    MxqError err = make_error();
    size_t first_illegal = 0;
    MxqStatus rc =
        facade.evaluate(fx.start_fen, fx.moves, position, status, first_illegal, err);
    if (rc != MXQ_OK) {
        if (rc == MXQ_ERR_RULES_INVALID_HISTORY) {
            msgs.push_back("the history is not legal: move index " +
                           std::to_string(first_illegal) + " (\"" +
                           (first_illegal < fx.moves.size()
                                ? fx.moves[first_illegal]
                                : std::string("?")) +
                           "\") was rejected. Every move in an approved fixture "
                           "must be legal at its turn.");
        } else {
            msgs.push_back("mxq_rules_evaluate failed: " + error_text(err, rc));
        }
        result.verdict = Verdict::Fail;
        return;
    }

    check_position(fx, position, "after the history", msgs);
    check_game_state(fx, status, msgs);

    /* The exact complete legal-move set, and the moves that must be illegal.
     * Both read the same set, so it is fetched once. */
    std::vector<std::string> legal;
    bool have_legal = false;
    if (fx.legal_moves.has_value() || fx.rejected_moves.has_value()) {
        err = make_error();
        rc = facade.legal_moves(fx.start_fen, fx.moves, legal, err);
        if (rc != MXQ_OK) {
            msgs.push_back("mxq_rules_legal_moves failed: " + error_text(err, rc));
        } else {
            have_legal = true;
            std::sort(legal.begin(), legal.end());
        }
    }

    if (have_legal && fx.legal_moves.has_value()) {
        std::vector<std::string> want = *fx.legal_moves;
        std::sort(want.begin(), want.end());
        if (want != legal) {
            std::vector<std::string> missing;
            std::set_difference(want.begin(), want.end(), legal.begin(),
                                legal.end(), std::back_inserter(missing));
            std::vector<std::string> extra;
            std::set_difference(legal.begin(), legal.end(), want.begin(),
                                want.end(), std::back_inserter(extra));
            std::string m = "legal_moves differs: " +
                            std::to_string(want.size()) + " expected, " +
                            std::to_string(legal.size()) + " produced";
            if (!missing.empty()) {
                m += "; missing [" + join(missing, " ") + "]";
            }
            if (!extra.empty()) {
                m += "; unexpected [" + join(extra, " ") + "]";
            }
            msgs.push_back(m);
        }
    }

    if (have_legal && fx.rejected_moves.has_value()) {
        for (const std::string &move : *fx.rejected_moves) {
            if (std::binary_search(legal.begin(), legal.end(), move)) {
                msgs.push_back("rejected_moves: \"" + move +
                               "\" must be illegal here but the core reports it "
                               "legal");
            }
        }
    }

    /* Single-move probes: applying the move must produce exactly that FEN and
     * check state. */
    if (fx.applied.has_value()) {
        for (const mxqtest::AppliedProbe &probe : *fx.applied) {
            std::vector<std::string> moves = fx.moves;
            moves.push_back(probe.move);

            MxqPosition after;
            std::memset(&after, 0, sizeof(after));
            after.struct_size = static_cast<uint32_t>(sizeof(after));
            MxqGameStatus after_status;
            std::memset(&after_status, 0, sizeof(after_status));
            after_status.struct_size =
                static_cast<uint32_t>(sizeof(after_status));

            err = make_error();
            size_t bad = 0;
            rc = facade.evaluate(fx.start_fen, moves, after, after_status, bad, err);
            if (rc != MXQ_OK) {
                msgs.push_back("applied \"" + probe.move +
                               "\": the core rejected it: " + error_text(err, rc));
                continue;
            }
            if (probe.result_fen != after.fen) {
                msgs.push_back("applied \"" + probe.move +
                               "\": result_fen expected \"" + probe.result_fen +
                               "\", core produced \"" + after.fen + "\"");
            }
            const bool in_check = after.in_check != 0;
            if (probe.in_check != in_check) {
                msgs.push_back("applied \"" + probe.move +
                               "\": in_check expected " +
                               (probe.in_check ? "true" : "false") +
                               ", core reported " + (in_check ? "true" : "false"));
            }
        }
    }

    /* The boundary prefix: one repetition cycle earlier the outcome must not yet
     * exist. The fixture states what does hold there in prose; what is
     * mechanically checkable is that the asserted outcome has not attached. */
    if (fx.boundary.has_value()) {
        const std::vector<std::string> prefix(
            fx.moves.begin(),
            fx.moves.begin() + static_cast<std::ptrdiff_t>(fx.boundary->prefix_len));

        MxqPosition at;
        std::memset(&at, 0, sizeof(at));
        at.struct_size = static_cast<uint32_t>(sizeof(at));
        MxqGameStatus at_status;
        std::memset(&at_status, 0, sizeof(at_status));
        at_status.struct_size = static_cast<uint32_t>(sizeof(at_status));

        err = make_error();
        size_t bad = 0;
        rc = facade.evaluate(fx.start_fen, prefix, at, at_status, bad, err);
        if (rc != MXQ_OK) {
            msgs.push_back("boundary prefix of " +
                           std::to_string(fx.boundary->prefix_len) +
                           " plies: mxq_rules_evaluate failed: " +
                           error_text(err, rc));
        } else {
            const std::string state = mxqtest::state_identifier(at_status.state);
            if (state == fx.game_state.state) {
                msgs.push_back("boundary prefix of " +
                               std::to_string(fx.boundary->prefix_len) +
                               " plies: expected \"" + fx.boundary->expect +
                               "\", but the core already reports \"" + state +
                               "\"; the outcome must attach only at the asserted "
                               "occurrence");
            }
        }
    }

    result.verdict = msgs.empty() ? Verdict::Pass : Verdict::Fail;
}

/* ---------------------------------------------------------------------- */
/* Reporting                                                              */
/* ---------------------------------------------------------------------- */

bool write_junit(const fs::path &path, const std::vector<FixtureResult> &results,
                 const std::string &not_implemented_reason) {
    int failures = 0;
    int errors = 0;
    int skipped = 0;
    for (const FixtureResult &r : results) {
        switch (r.verdict) {
        case Verdict::Fail: ++failures; break;
        case Verdict::Error: ++errors; break;
        case Verdict::NotImplemented: ++skipped; break;
        case Verdict::Pass: break;
        }
    }

    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
        return false;
    }
    out << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    out << "<testsuites name=\"minixiangqi-core\" tests=\"" << results.size()
        << "\" failures=\"" << failures << "\" errors=\"" << errors
        << "\" skipped=\"" << skipped << "\">\n";
    out << "  <testsuite name=\"rules-fixtures\" tests=\"" << results.size()
        << "\" failures=\"" << failures << "\" errors=\"" << errors
        << "\" skipped=\"" << skipped << "\">\n";
    for (const FixtureResult &r : results) {
        const std::string classname =
            "rules." + (r.area.empty() ? std::string("unknown") : r.area);
        out << "    <testcase classname=\"" << xml_escape(classname)
            << "\" name=\"" << xml_escape(r.id) << "\" file=\""
            << xml_escape(r.file) << "\">";
        const std::string detail = xml_escape(join(r.messages, "\n"));
        switch (r.verdict) {
        case Verdict::Pass:
            out << "</testcase>\n";
            break;
        case Verdict::Fail:
            out << "\n      <failure message=\"fixture expectation not met\">"
                << detail << "</failure>\n    </testcase>\n";
            break;
        case Verdict::Error:
            out << "\n      <error message=\"fixture could not be loaded\">"
                << detail << "</error>\n    </testcase>\n";
            break;
        case Verdict::NotImplemented:
            out << "\n      <skipped message=\"NOT IMPLEMENTED: "
                << xml_escape(not_implemented_reason) << "\"/>\n    </testcase>\n";
            break;
        }
    }
    out << "  </testsuite>\n";
    out << "</testsuites>\n";
    return out.good();
}

/* ---------------------------------------------------------------------- */

bool parse_options(int argc, char **argv, Options &opt, std::string &error) {
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--help" || arg == "-h") {
            opt.help = true;
            return true;
        }
        if (arg == "--fixtures" || arg == "--junit") {
            if (i + 1 >= argc) {
                error = arg + " needs a value";
                return false;
            }
            const std::string value = argv[++i];
            if (arg == "--fixtures") {
                opt.fixtures_dir = value;
            } else {
                opt.junit_path = value;
            }
            continue;
        }
        error = "unknown argument \"" + arg + "\"";
        return false;
    }
    return true;
}

void print_banner(const fs::path &fixtures_dir, size_t fixture_count) {
    MxqVersion version;
    std::memset(&version, 0, sizeof(version));
    version.struct_size = static_cast<uint32_t>(sizeof(version));
    MxqError err = make_error();
    const MxqStatus rc = mxq_core_version(&version, &err);

    std::cout << "Mini Xiangqi core test runner\n";
    if (rc == MXQ_OK) {
        std::cout << "  C API           " << version.api_major << "."
                  << version.api_minor << "." << version.api_patch << "\n"
                  << "  archive         v" << version.archive_version_current
                  << " (minimum readable v"
                  << version.archive_version_min_readable << ")\n"
                  << "  store schema    v" << version.store_schema_version << "\n"
                  << "  core revision   " << version.core_revision << "\n"
                  << "  fork revision   " << version.fork_revision << "\n"
                  << "  variant         " << version.variant_id << "\n"
                  << "  network         " << version.nnue_sha256 << "\n";
    } else {
        std::cout << "  mxq_core_version failed: " << error_text(err, rc) << "\n";
    }

    char start_fen[MXQ_FEN_CAP];
    size_t len = 0;
    err = make_error();
    if (mxq_rules_start_fen(start_fen, sizeof(start_fen), &len, &err) == MXQ_OK) {
        std::cout << "  start FEN       " << start_fen << "\n";
    }

    std::cout << "  fixtures        " << fixtures_dir.string() << " ("
              << fixture_count << " files)\n";
}

} /* namespace */

int main(int argc, char **argv) {
    Options opt;
    std::string arg_error;
    if (!parse_options(argc, argv, opt, arg_error)) {
        std::cerr << "mxq_core_tests: " << arg_error << "\n\n" << kUsage;
        return 2;
    }
    if (opt.help) {
        std::cout << kUsage;
        return 0;
    }

    if (opt.fixtures_dir.empty()) {
        if (const char *env = std::getenv("MXQ_FIXTURES_DIR")) {
            opt.fixtures_dir = env;
        } else {
            opt.fixtures_dir = MXQ_FIXTURES_DIR_DEFAULT;
        }
    }

    std::error_code ec;
    if (!fs::is_directory(opt.fixtures_dir, ec)) {
        std::cerr << "mxq_core_tests: not a directory: "
                  << opt.fixtures_dir.string() << "\n";
        return 2;
    }

    std::vector<fs::path> files;
    {
        std::error_code iter_ec;
        fs::directory_iterator it(opt.fixtures_dir, iter_ec);
        if (iter_ec) {
            std::cerr << "mxq_core_tests: cannot read "
                      << opt.fixtures_dir.string() << ": " << iter_ec.message()
                      << "\n";
            return 2;
        }
        for (const fs::directory_entry &entry : it) {
            if (entry.path().extension() != ".json") {
                continue;
            }
            /* A separate code per entry: sharing one with the iterator let a
             * broken entry be dropped in silence and a stale value abort the
             * run later. An entry that cannot be stat'd is a setup failure,
             * because a fixture we cannot read is not a fixture we may skip —
             * but an entry that stats cleanly and simply is not a regular file,
             * such as a directory named *.json, is not a fixture at all and is
             * passed over rather than taking the suite down. */
            std::error_code entry_ec;
            const bool regular = entry.is_regular_file(entry_ec);
            if (entry_ec) {
                std::cerr << "mxq_core_tests: cannot read "
                          << entry.path().string() << ": " << entry_ec.message()
                          << "\n";
                return 2;
            }
            if (!regular) {
                continue;
            }
            files.push_back(entry.path());
        }
    }
    std::sort(files.begin(), files.end());
    if (files.empty()) {
        std::cerr << "mxq_core_tests: no fixtures in "
                  << opt.fixtures_dir.string() << "\n";
        return 2;
    }

    print_banner(opt.fixtures_dir, files.size());

    /* Bring the rules facade up once. Its store lives in a temporary directory:
     * the fixtures are session-free and touch no library, but mxq_core_init
     * still needs a frontend-supplied location, since the core never derives a
     * platform path of its own. */
    mxqtest::RulesFacade facade;
    std::string unavailable;
    const fs::path scratch =
        fs::temp_directory_path(ec) / "minixiangqi-core-tests";
    const bool available =
        facade.open(scratch.string(), assets_dir(), unavailable);
    if (available) {
        std::cout << "  rules facade    available\n";
    } else {
        std::cout << "  rules facade    UNAVAILABLE\n"
                  << "                  " << unavailable << "\n";
    }
    std::cout << "\n";

    std::vector<FixtureResult> results;
    results.reserve(files.size());

    for (const fs::path &file : files) {
        FixtureResult result;
        result.file = fs::relative(file, opt.fixtures_dir, ec).string();
        if (result.file.empty()) {
            result.file = file.filename().string();
        }
        result.id = file.stem().string();

        mxqtest::Fixture fixture;
        std::string load_error;
        if (!mxqtest::fixture_load(file.string(), fixture, load_error)) {
            result.verdict = Verdict::Error;
            result.messages.push_back(load_error);
            results.push_back(std::move(result));
            continue;
        }

        result.id = fixture.id;
        result.area = fixture.area;
        result.title = fixture.title;
        result.checks = fixture.check_count();

        /* The file name and the fixture's own identifier must agree: the
         * identifiers are stable and are how the rules contract refers to
         * them. */
        if (fixture.id != file.stem().string()) {
            result.verdict = Verdict::Error;
            result.messages.push_back("id \"" + fixture.id +
                                      "\" does not match the file name \"" +
                                      file.stem().string() + "\"");
            results.push_back(std::move(result));
            continue;
        }

        if (!available) {
            result.verdict = Verdict::NotImplemented;
            results.push_back(std::move(result));
            continue;
        }

        evaluate_fixture(facade, fixture, result);
        results.push_back(std::move(result));
    }

    int passed = 0;
    int failed = 0;
    int not_implemented = 0;
    int errored = 0;
    int checks_total = 0;
    int checks_evaluated = 0;

    for (const FixtureResult &r : results) {
        std::cout << "  " << verdict_label(r.verdict) << "  " << r.id << "  ["
                  << (r.area.empty() ? "?" : r.area) << "]  " << r.checks
                  << " checks  " << r.title << "\n";
        for (const std::string &m : r.messages) {
            std::cout << "              " << m << "\n";
        }
        checks_total += r.checks;
        switch (r.verdict) {
        case Verdict::Pass:
            ++passed;
            checks_evaluated += r.checks;
            break;
        case Verdict::Fail:
            ++failed;
            checks_evaluated += r.checks;
            break;
        case Verdict::NotImplemented: ++not_implemented; break;
        case Verdict::Error: ++errored; break;
        }
    }

    std::cout << "\n"
              << results.size() << " fixtures: " << passed << " passed, "
              << failed << " failed, " << not_implemented
              << " not implemented, " << errored << " errored\n"
              << checks_evaluated << " of " << checks_total
              << " normative expectations evaluated\n";

    if (not_implemented > 0) {
        std::cout << "\nNOT IMPLEMENTED: " << not_implemented << " fixture"
                  << (not_implemented == 1 ? "" : "s")
                  << " could not be evaluated. " << unavailable << "\n";
    }

    if (!opt.junit_path.empty()) {
        if (!write_junit(opt.junit_path, results, unavailable)) {
            std::cerr << "mxq_core_tests: cannot write "
                      << opt.junit_path.string() << "\n";
            return 2;
        }
        std::cout << "JUnit report: " << opt.junit_path.string() << "\n";
    }

    return (failed > 0 || errored > 0) ? 1 : 0;
}
