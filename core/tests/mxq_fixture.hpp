/*
 * The approved rules-conformance fixture schema, as fixtures/rules/README.md
 * defines it.
 *
 * The fixtures are the independent authority the core is validated against, so
 * this loader is strict: an unknown member, a missing member, or a member of the
 * wrong type is a load error rather than something quietly ignored. A fixture
 * that fails to load is reported as an ERROR, which is distinct from a fixture
 * that loads but cannot yet be evaluated.
 */

#ifndef MXQ_TESTS_FIXTURE_HPP
#define MXQ_TESTS_FIXTURE_HPP

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace mxqtest {

/* One single-move probe: applying `move` must produce exactly `result_fen` and
 * `in_check`. */
struct AppliedProbe {
    std::string move;
    std::string result_fen;
    bool in_check = false;
};

/* The normative game state at the position reached after `moves`. */
struct GameStateExpect {
    std::string state;                     /* ongoing, claimable-draw,
                                            * red-wins, black-wins, draw */
    std::optional<std::string> reason;     /* null exactly when ongoing */
    std::optional<int64_t> at_occurrence;  /* repetition-based outcomes only */
};

/* A prefix one repetition cycle earlier at which the outcome must not yet
 * exist, pinning that the outcome attaches exactly at the asserted
 * occurrence. */
struct Boundary {
    int64_t prefix_len = 0;
    std::string expect;
};

struct Fixture {
    std::string id;
    std::string title;
    std::string area;
    std::string variant;
    std::string start_fen;
    std::vector<std::string> moves;

    bool in_check = false;
    std::string result_fen;
    std::optional<std::vector<std::string>> legal_moves;
    std::optional<std::vector<std::string>> rejected_moves;
    std::optional<std::vector<AppliedProbe>> applied;
    GameStateExpect game_state;

    std::optional<Boundary> boundary;
    std::string rationale;

    /* How many normative expectations this fixture carries, for the report. */
    int check_count() const;
};

/* Load one fixture file. On failure returns false and sets `error`. */
bool fixture_load(const std::string &path, Fixture &out, std::string &error);

} /* namespace mxqtest */

#endif /* MXQ_TESTS_FIXTURE_HPP */
