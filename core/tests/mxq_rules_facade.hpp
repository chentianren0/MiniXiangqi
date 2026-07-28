/*
 * The runner's view of the core's session-free rules facade.
 *
 * docs/core-interface.md makes mxq_rules_evaluate and mxq_rules_legal_moves
 * exactly the surface the approved fixtures replay through: every assertion in
 * a fixture maps onto their outputs. This wrapper is the one place that knows
 * whether those functions are in the binary, so that the comparison logic in
 * main.cpp compiles and is reviewed whether or not the facade exists yet.
 *
 * While the facade is absent, open() fails with a reason and every fixture is
 * reported NOT IMPLEMENTED. It is never reported as passing.
 */

#ifndef MXQ_TESTS_RULES_FACADE_HPP
#define MXQ_TESTS_RULES_FACADE_HPP

#include "mxq.h"

#include <string>
#include <vector>

namespace mxqtest {

class RulesFacade {
public:
    RulesFacade() = default;
    ~RulesFacade();

    RulesFacade(const RulesFacade &) = delete;
    RulesFacade &operator=(const RulesFacade &) = delete;

    /* Bring the facade up. Returns false and sets `reason` when it cannot be
     * used, including when it is not built into this runner. */
    bool open(const std::string &store_directory,
              const std::string &asset_directory, std::string &reason);
    void close();
    bool is_open() const { return core_ != nullptr; }

    /* Replay `moves` from `start_fen`. On MXQ_ERR_RULES_INVALID_HISTORY,
     * first_illegal_index names the offending move. */
    MxqStatus evaluate(const std::string &start_fen,
                       const std::vector<std::string> &moves,
                       MxqPosition &position, MxqGameStatus &status,
                       size_t &first_illegal_index, MxqError &err);

    /* The complete legal-move set in the position reached by that replay. */
    MxqStatus legal_moves(const std::string &start_fen,
                          const std::vector<std::string> &moves,
                          std::vector<std::string> &out, MxqError &err);

private:
    MxqCore *core_ = nullptr;
};

/* The fixture identifiers for the core's live game state and end reason, so a
 * mismatch is reported in the fixture's own vocabulary rather than as a
 * number. Returns "unknown(<n>)" for a value this build does not know, which
 * the contract requires callers to tolerate. */
std::string state_identifier(MxqGameState state);
std::string reason_identifier(MxqEndReason reason);

} /* namespace mxqtest */

#endif /* MXQ_TESTS_RULES_FACADE_HPP */
