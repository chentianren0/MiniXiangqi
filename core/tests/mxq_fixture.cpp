#include "mxq_fixture.hpp"

#include "mxq_json.hpp"

#include <cmath>
#include <cstring>
#include <fstream>
#include <set>
#include <sstream>

namespace mxqtest {

namespace {

/* A fixture is one of two shapes, and `setup` is what tells them apart: a play
 * fixture states a history and what holds at its end, and a setup fixture states
 * a position and whether its game may begin there. Each is checked against its
 * own member set, so a file that mixes them is a load error rather than a
 * fixture half of whose members were quietly ignored. */
const std::set<std::string> kPlayMembers = {
    "id", "title", "area", "variant", "start_fen",
    "moves", "assertions", "boundary", "rationale"};

const std::set<std::string> kSetupMembers = {"id",        "title", "area",
                                             "variant",   "start_fen",
                                             "setup",     "rationale"};

const std::set<std::string> kSetupMembersInner = {"violation", "side", "square"};

/* The violation classes a setup fixture may name, one for each the core
 * reports. */
const std::set<std::string> kViolations = {
    "piece-count",     "palace",            "elephant-side",
    "soldier-rank",    "facing-generals",   "opponent-in-check",
    "not-frozen-start"};

const std::set<std::string> kSides = {"red", "black"};

const std::set<std::string> kAssertionMembers = {
    "in_check", "result_fen", "legal_moves",
    "rejected_moves", "applied", "game_state"};

const std::set<std::string> kGameStateMembers = {"state", "reason",
                                                 "at_occurrence"};

const std::set<std::string> kAppliedMembers = {"move", "result_fen", "in_check"};

const std::set<std::string> kBoundaryMembers = {"prefix_len", "expect"};

const std::set<std::string> kStates = {"ongoing", "claimable-draw", "red-wins",
                                       "black-wins", "draw"};

/* The reason identifiers fixtures may carry. The two mutual reasons are
 * reserved for the deferred mutual-violation tranche and are accepted here so
 * that adding one of those fixtures is not also a runner change. */
const std::set<std::string> kReasons = {
    "checkmate",             "stalemate",
    "threefold-repetition",  "perpetual-check",
    "perpetual-chase",       "mutual-perpetual-check",
    "mutual-perpetual-chase", "fifty-move-rule"};

/* The ruleset identifiers a fixture may declare, and the game each names. The
 * identifier prefix a fixture's id must carry goes with it: the two are one
 * decision, and a file named for one game while declaring the other is a
 * mistake worth catching at load rather than at a diverging expectation. */
struct VariantRow {
    const char *identifier;
    MxqGameKind game;
    const char *id_prefix;
};

const VariantRow kVariants[] = {
    {"minixiangqi", MXQ_GAME_KIND_MINI_XIANGQI, "mx-"},
    {"xiangqi", MXQ_GAME_KIND_XIANGQI, "xq-"},
};

class Loader {
public:
    explicit Loader(std::string &error) : error_(error) {}

    bool fail(const std::string &what) {
        if (error_.empty()) {
            error_ = what;
        }
        return false;
    }

    bool require_members(const JsonValue &v, const std::set<std::string> &allowed,
                         const std::string &where) {
        for (const auto &entry : v.object()) {
            if (allowed.find(entry.first) == allowed.end()) {
                return fail(where + ": unknown member \"" + entry.first + "\"");
            }
        }
        for (const auto &name : allowed) {
            if (v.member(name) == nullptr) {
                return fail(where + ": missing member \"" + name + "\"");
            }
        }
        return true;
    }

    const JsonValue *typed(const JsonValue &v, const std::string &name,
                           JsonValue::Type want, const std::string &where,
                           bool nullable) {
        const JsonValue *m = v.member(name);
        if (m == nullptr) {
            fail(where + ": missing member \"" + name + "\"");
            return nullptr;
        }
        if (nullable && m->is_null()) {
            return m;
        }
        if (m->type() != want) {
            fail(where + "." + name + ": expected " +
                 JsonValue::type_name(want) + ", found " +
                 JsonValue::type_name(m->type()));
            return nullptr;
        }
        return m;
    }

    bool string_list(const JsonValue &v, std::vector<std::string> &out,
                     const std::string &where) {
        for (size_t i = 0; i < v.array().size(); ++i) {
            const JsonValue &item = v.array()[i];
            if (!item.is_string()) {
                return fail(where + "[" + std::to_string(i) +
                            "]: expected string, found " +
                            JsonValue::type_name(item.type()));
            }
            out.push_back(item.string());
        }
        return true;
    }

    bool integer(const JsonValue &v, int64_t &out, const std::string &where) {
        const double d = v.number();
        if (!std::isfinite(d)) {
            return fail(where + ": expected an integer, got a non-finite number");
        }
        if (d != std::floor(d)) {
            return fail(where + ": expected an integer");
        }
        /* Converting a double outside int64_t's range is undefined, so the
         * range check must precede the cast rather than validate its result. */
        if (d < -9223372036854775808.0 || d >= 9223372036854775808.0) {
            return fail(where + ": integer is outside the representable range");
        }
        out = static_cast<int64_t>(d);
        return true;
    }

private:
    std::string &error_;
};

} /* namespace */

int Fixture::check_count() const {
    /* A setup fixture asserts the verdict and the three members of the report
     * the core fills, whichever way the verdict went. */
    if (setup.has_value()) {
        return 4;
    }
    /* in_check, result_fen and game_state are always asserted. */
    int n = 3;
    if (legal_moves.has_value()) {
        ++n;
    }
    if (rejected_moves.has_value()) {
        n += static_cast<int>(rejected_moves->size());
    }
    if (applied.has_value()) {
        n += 2 * static_cast<int>(applied->size());
    }
    if (boundary.has_value()) {
        ++n;
    }
    return n;
}

bool fixture_load(const std::string &path, Fixture &out, std::string &error) {
    error.clear();
    Loader load(error);

    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return load.fail("cannot open the file");
    }
    std::ostringstream buffer;
    buffer << in.rdbuf();
    if (!in.good() && !in.eof()) {
        return load.fail("cannot read the file");
    }
    const std::string text = buffer.str();

    JsonValue root;
    std::string parse_error;
    if (!json_parse(text, root, parse_error)) {
        return load.fail("invalid JSON: " + parse_error);
    }
    if (!root.is_object()) {
        return load.fail("the document is not an object");
    }
    const bool is_setup = root.member("setup") != nullptr;
    if (!load.require_members(root, is_setup ? kSetupMembers : kPlayMembers,
                              "fixture")) {
        return false;
    }

    const JsonValue *v = nullptr;

#define MXQ_TAKE_STRING(dest, name)                                          \
    v = load.typed(root, name, JsonValue::Type::String, "fixture", false);   \
    if (v == nullptr) {                                                      \
        return false;                                                        \
    }                                                                        \
    (dest) = v->string()

    MXQ_TAKE_STRING(out.id, "id");
    MXQ_TAKE_STRING(out.title, "title");
    MXQ_TAKE_STRING(out.area, "area");
    MXQ_TAKE_STRING(out.variant, "variant");
    MXQ_TAKE_STRING(out.start_fen, "start_fen");
    MXQ_TAKE_STRING(out.rationale, "rationale");
#undef MXQ_TAKE_STRING

    /* The declared ruleset, decoded into the game the fixture is replayed
     * under. An identifier this runner does not know is a load error rather
     * than a fixture quietly replayed under some default. */
    {
        const VariantRow *row = nullptr;
        for (const VariantRow &candidate : kVariants) {
            if (out.variant == candidate.identifier) {
                row = &candidate;
                break;
            }
        }
        if (row == nullptr) {
            return load.fail("fixture.variant: \"" + out.variant +
                             "\" is not a ruleset this runner knows");
        }
        out.game = row->game;
        if (out.id.compare(0, std::strlen(row->id_prefix), row->id_prefix) !=
            0) {
            return load.fail("fixture.id: a " + out.variant +
                             " fixture's id begins with \"" +
                             row->id_prefix + "\"");
        }
    }

    if (is_setup) {
        const JsonValue *s = load.typed(root, "setup", JsonValue::Type::Object,
                                        "fixture", false);
        if (s == nullptr ||
            !load.require_members(*s, kSetupMembersInner, "fixture.setup")) {
            return false;
        }
        SetupExpect expect;

        v = load.typed(*s, "violation", JsonValue::Type::String, "fixture.setup",
                       true);
        if (v == nullptr) {
            return false;
        }
        if (!v->is_null()) {
            expect.violation = v->string();
            if (kViolations.find(*expect.violation) == kViolations.end()) {
                return load.fail("fixture.setup.violation: \"" +
                                 *expect.violation +
                                 "\" is not an accepted violation class");
            }
        }

        v = load.typed(*s, "side", JsonValue::Type::String, "fixture.setup",
                       true);
        if (v == nullptr) {
            return false;
        }
        if (!v->is_null()) {
            expect.side = v->string();
            if (kSides.find(*expect.side) == kSides.end()) {
                return load.fail("fixture.setup.side: \"" + *expect.side +
                                 "\" is not a side");
            }
        }

        v = load.typed(*s, "square", JsonValue::Type::String, "fixture.setup",
                       true);
        if (v == nullptr) {
            return false;
        }
        if (!v->is_null()) {
            expect.square = v->string();
        }

        /* A legal setup has nothing to name. Which of the two an illegal one
         * names is the violation class's own and is pinned by the fixtures
         * themselves, not restated here. */
        if (!expect.violation.has_value() &&
            (expect.side.has_value() || expect.square.has_value())) {
            return load.fail(
                "fixture.setup: side and square must be null when the position "
                "is a legal setup");
        }

        out.setup = std::move(expect);
        return true;
    }

    v = load.typed(root, "moves", JsonValue::Type::Array, "fixture", false);
    if (v == nullptr || !load.string_list(*v, out.moves, "fixture.moves")) {
        return false;
    }

    /* assertions */
    const JsonValue *a =
        load.typed(root, "assertions", JsonValue::Type::Object, "fixture", false);
    if (a == nullptr ||
        !load.require_members(*a, kAssertionMembers, "fixture.assertions")) {
        return false;
    }

    v = load.typed(*a, "in_check", JsonValue::Type::Bool, "fixture.assertions",
                   false);
    if (v == nullptr) {
        return false;
    }
    out.in_check = v->boolean();

    v = load.typed(*a, "result_fen", JsonValue::Type::String,
                   "fixture.assertions", false);
    if (v == nullptr) {
        return false;
    }
    out.result_fen = v->string();

    v = load.typed(*a, "legal_moves", JsonValue::Type::Array,
                   "fixture.assertions", true);
    if (v == nullptr) {
        return false;
    }
    if (!v->is_null()) {
        std::vector<std::string> moves;
        if (!load.string_list(*v, moves, "fixture.assertions.legal_moves")) {
            return false;
        }
        out.legal_moves = std::move(moves);
    }

    v = load.typed(*a, "rejected_moves", JsonValue::Type::Array,
                   "fixture.assertions", true);
    if (v == nullptr) {
        return false;
    }
    if (!v->is_null()) {
        std::vector<std::string> moves;
        if (!load.string_list(*v, moves, "fixture.assertions.rejected_moves")) {
            return false;
        }
        out.rejected_moves = std::move(moves);
    }

    v = load.typed(*a, "applied", JsonValue::Type::Array, "fixture.assertions",
                   true);
    if (v == nullptr) {
        return false;
    }
    if (!v->is_null()) {
        std::vector<AppliedProbe> probes;
        for (size_t i = 0; i < v->array().size(); ++i) {
            const JsonValue &item = v->array()[i];
            const std::string where =
                "fixture.assertions.applied[" + std::to_string(i) + "]";
            if (!item.is_object()) {
                return load.fail(where + ": expected an object");
            }
            if (!load.require_members(item, kAppliedMembers, where)) {
                return false;
            }
            AppliedProbe probe;
            const JsonValue *m =
                load.typed(item, "move", JsonValue::Type::String, where, false);
            if (m == nullptr) {
                return false;
            }
            probe.move = m->string();
            m = load.typed(item, "result_fen", JsonValue::Type::String, where,
                           false);
            if (m == nullptr) {
                return false;
            }
            probe.result_fen = m->string();
            m = load.typed(item, "in_check", JsonValue::Type::Bool, where, false);
            if (m == nullptr) {
                return false;
            }
            probe.in_check = m->boolean();
            probes.push_back(std::move(probe));
        }
        out.applied = std::move(probes);
    }

    /* game_state */
    const JsonValue *g = load.typed(*a, "game_state", JsonValue::Type::Object,
                                    "fixture.assertions", false);
    if (g == nullptr) {
        return false;
    }
    for (const auto &entry : g->object()) {
        if (kGameStateMembers.find(entry.first) == kGameStateMembers.end()) {
            return load.fail("fixture.assertions.game_state: unknown member \"" +
                             entry.first + "\"");
        }
    }
    v = load.typed(*g, "state", JsonValue::Type::String,
                   "fixture.assertions.game_state", false);
    if (v == nullptr) {
        return false;
    }
    out.game_state.state = v->string();
    if (kStates.find(out.game_state.state) == kStates.end()) {
        return load.fail("fixture.assertions.game_state.state: \"" +
                         out.game_state.state + "\" is not an accepted state");
    }

    v = load.typed(*g, "reason", JsonValue::Type::String,
                   "fixture.assertions.game_state", true);
    if (v == nullptr) {
        return false;
    }
    if (!v->is_null()) {
        out.game_state.reason = v->string();
        if (kReasons.find(*out.game_state.reason) == kReasons.end()) {
            return load.fail("fixture.assertions.game_state.reason: \"" +
                             *out.game_state.reason +
                             "\" is not an accepted reason");
        }
    }

    /* Results are named by rule outcome, and an ongoing game has no reason. */
    if ((out.game_state.state == "ongoing") == out.game_state.reason.has_value()) {
        return load.fail(
            "fixture.assertions.game_state: reason must be null exactly when "
            "the state is ongoing");
    }

    if (const JsonValue *occ = g->member("at_occurrence")) {
        if (!occ->is_number()) {
            return load.fail(
                "fixture.assertions.game_state.at_occurrence: expected a number");
        }
        int64_t n = 0;
        if (!load.integer(*occ, n,
                          "fixture.assertions.game_state.at_occurrence")) {
            return false;
        }
        out.game_state.at_occurrence = n;
    }

    /* boundary */
    v = load.typed(root, "boundary", JsonValue::Type::Object, "fixture", true);
    if (v == nullptr) {
        return false;
    }
    if (!v->is_null()) {
        if (!load.require_members(*v, kBoundaryMembers, "fixture.boundary")) {
            return false;
        }
        Boundary boundary;
        const JsonValue *m = load.typed(*v, "prefix_len", JsonValue::Type::Number,
                                        "fixture.boundary", false);
        if (m == nullptr ||
            !load.integer(*m, boundary.prefix_len, "fixture.boundary.prefix_len")) {
            return false;
        }
        if (boundary.prefix_len < 0 ||
            static_cast<size_t>(boundary.prefix_len) > out.moves.size()) {
            return load.fail(
                "fixture.boundary.prefix_len: outside the move history");
        }
        m = load.typed(*v, "expect", JsonValue::Type::String, "fixture.boundary",
                       false);
        if (m == nullptr) {
            return false;
        }
        boundary.expect = m->string();
        out.boundary = std::move(boundary);
    }

    return true;
}

} /* namespace mxqtest */
