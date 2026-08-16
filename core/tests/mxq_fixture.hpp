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

#include "mxq.h"

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

/*
 * What the setup-legality predicate must answer for `start_fen`.
 *
 * A setup fixture asks a different question from every other one here — not
 * what may be played over a position but whether its game may begin there — so
 * it carries this instead of `moves`, `assertions` and `boundary` rather than
 * alongside them. A history has no meaning for it, and asserting a legal-move
 * set over a position no game could reach would be pinning an answer nothing
 * asks for.
 *
 * `violation` is null exactly when the position is a legal setup, and `side`
 * and `square` are then null too. Which of the two a violated class carries is
 * the class's own, and the fixtures are where that is pinned.
 */
struct SetupExpect {
    std::optional<std::string> violation;
    std::optional<std::string> side;   /* "red" or "black" */
    std::optional<std::string> square;
};

struct Fixture {
    std::string id;
    std::string title;
    std::string area;
    /* The ruleset the fixture is defined against, as written and as decoded.
     * The decoded value is what the fixture is replayed under: a fixture set
     * covering two games that dispatched on anything else — the board implied
     * by the FEN, the file it sits in — would be replaying its own guess. */
    std::string variant;
    MxqGameKind game = MXQ_GAME_KIND_MINI_XIANGQI;
    std::string start_fen;
    std::vector<std::string> moves;

    bool in_check = false;
    std::string result_fen;
    std::optional<std::vector<std::string>> legal_moves;
    std::optional<std::vector<std::string>> rejected_moves;
    std::optional<std::vector<AppliedProbe>> applied;
    GameStateExpect game_state;

    std::optional<Boundary> boundary;

    /* Present exactly for a setup fixture, and then every member above from
     * `moves` down is absent from the file and unread here. */
    std::optional<SetupExpect> setup;

    std::string rationale;

    /* How many normative expectations this fixture carries, for the report. */
    int check_count() const;
};

/* Load one fixture file. On failure returns false and sets `error`. */
bool fixture_load(const std::string &path, Fixture &out, std::string &error);

} /* namespace mxqtest */

#endif /* MXQ_TESTS_FIXTURE_HPP */
