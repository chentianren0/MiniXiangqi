#include "mxq_rules_facade.hpp"

#include <cassert>
#include <cstring>

#ifndef MXQ_TEST_RULES_FACADE
#define MXQ_TEST_RULES_FACADE 0
#endif

namespace mxqtest {

std::string state_identifier(MxqGameState state) {
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

std::string reason_identifier(MxqEndReason reason) {
    switch (reason) {
    case MXQ_END_REASON_NONE: return "";
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
    default: break;
    }
    return "unknown(" + std::to_string(reason) + ")";
}

std::string rule_identifier(MxqSetupRule rule) {
    switch (rule) {
    case MXQ_SETUP_RULE_NONE: return "";
    case MXQ_SETUP_RULE_PIECE_COUNT: return "piece-count";
    case MXQ_SETUP_RULE_PALACE: return "palace";
    case MXQ_SETUP_RULE_ELEPHANT_SIDE: return "elephant-side";
    case MXQ_SETUP_RULE_SOLDIER_RANK: return "soldier-rank";
    case MXQ_SETUP_RULE_FACING_GENERALS: return "facing-generals";
    case MXQ_SETUP_RULE_OPPONENT_IN_CHECK: return "opponent-in-check";
    case MXQ_SETUP_RULE_NOT_FROZEN_START: return "not-frozen-start";
    default: break;
    }
    return "unknown(" + std::to_string(rule) + ")";
}

std::string color_identifier(MxqColor color) {
    switch (color) {
    case MXQ_COLOR_NONE: return "";
    case MXQ_COLOR_RED: return "red";
    case MXQ_COLOR_BLACK: return "black";
    default: break;
    }
    return "unknown(" + std::to_string(color) + ")";
}

bool rules_facade_built() { return MXQ_TEST_RULES_FACADE != 0; }

RulesFacade::~RulesFacade() { close(); }

#if MXQ_TEST_RULES_FACADE

bool RulesFacade::open(const std::string &store_directory,
                       const std::string &asset_directory,
                       std::string &reason) {
    MxqCoreConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.api_major = MXQ_API_VERSION_MAJOR;
    config.api_minor = MXQ_API_VERSION_MINOR;
    config.api_patch = MXQ_API_VERSION_PATCH;
    config.flags = MXQ_CORE_FLAG_NONE;
    config.store_directory = store_directory.c_str();
    config.asset_directory = asset_directory.c_str();

    MxqError err;
    std::memset(&err, 0, sizeof(err));
    err.struct_size = static_cast<uint32_t>(sizeof(err));

    const MxqStatus rc = mxq_core_init(&config, &core_, &err);
    if (rc != MXQ_OK) {
        core_ = nullptr;
        reason = std::string(mxq_status_name(rc)) + ": " + err.detail;
        return false;
    }
    return true;
}

void RulesFacade::close() {
    if (core_ == nullptr) {
        return;
    }
    mxq_core_shutdown(core_, nullptr);
    core_ = nullptr;
}

MxqStatus RulesFacade::evaluate(MxqGameKind game, const std::string &start_fen,
                                const std::vector<std::string> &moves,
                                MxqPosition &position, MxqGameStatus &status,
                                size_t &first_illegal_index, MxqError &err) {
    assert(is_open());
    std::vector<const char *> argv;
    argv.reserve(moves.size());
    for (const std::string &m : moves) {
        argv.push_back(m.c_str());
    }
    first_illegal_index = 0;
    return mxq_rules_evaluate(core_, game, start_fen.c_str(),
                              argv.empty() ? nullptr : argv.data(), argv.size(),
                              &position, &status, &first_illegal_index, &err);
}

MxqStatus RulesFacade::legal_moves(MxqGameKind game,
                                   const std::string &start_fen,
                                   const std::vector<std::string> &moves,
                                   std::vector<std::string> &out,
                                   MxqError &err) {
    assert(is_open());
    std::vector<const char *> argv;
    argv.reserve(moves.size());
    for (const std::string &m : moves) {
        argv.push_back(m.c_str());
    }

    /* Ask for the count first, then the values: MXQ_ERR_ARG_BUFFER_TOO_SMALL is
     * routine rather than a programming error, and this is the shape every
     * caller of a counted output uses. */
    size_t count = 0;
    MxqStatus rc = mxq_rules_legal_moves(
        core_, game, start_fen.c_str(), argv.empty() ? nullptr : argv.data(),
        argv.size(), nullptr, 0, &count, &err);
    if (rc != MXQ_OK && rc != MXQ_ERR_ARG_BUFFER_TOO_SMALL) {
        return rc;
    }

    std::vector<MxqMove> buffer(count);
    for (MxqMove &m : buffer) {
        m.struct_size = static_cast<uint32_t>(sizeof(MxqMove));
    }
    size_t written = 0;
    rc = mxq_rules_legal_moves(core_, game, start_fen.c_str(),
                               argv.empty() ? nullptr : argv.data(), argv.size(),
                               buffer.empty() ? nullptr : buffer.data(),
                               buffer.size(), &written, &err);
    if (rc != MXQ_OK) {
        return rc;
    }
    out.clear();
    out.reserve(written);
    for (size_t i = 0; i < written; ++i) {
        out.emplace_back(buffer[i].text);
    }
    return MXQ_OK;
}

MxqStatus RulesFacade::validate_setup(MxqGameKind game, const std::string &fen,
                                      MxqSetupViolation &violation, MxqError &err) {
    assert(is_open());
    std::memset(&violation, 0, sizeof(violation));
    violation.struct_size = static_cast<uint32_t>(sizeof(violation));
    return mxq_rules_validate_setup(core_, game, fen.c_str(), &violation, &err);
}

#else /* MXQ_TEST_RULES_FACADE */

bool RulesFacade::open(const std::string &store_directory,
                       const std::string &asset_directory,
                       std::string &reason) {
    (void)store_directory;
    (void)asset_directory;
    reason =
        "the core's rules facade is not built into this runner. It is "
        "implemented, but every entry point that replays a move line — "
        "mxq_rules_evaluate, mxq_rules_legal_moves and their relatives — is "
        "compiled out unless MXQ_ENABLE_RULES_FACADE is ON, because the "
        "vendored engine is a multi-minute build and nothing else in the core "
        "needs it. Configure with -DMXQ_ENABLE_RULES_FACADE=ON to evaluate "
        "these expectations instead of reporting them NOT IMPLEMENTED.";
    return false;
}

void RulesFacade::close() {}

MxqStatus RulesFacade::evaluate(MxqGameKind game, const std::string &start_fen,
                                const std::vector<std::string> &moves,
                                MxqPosition &position, MxqGameStatus &status,
                                size_t &first_illegal_index, MxqError &err) {
    (void)game;
    (void)start_fen;
    (void)moves;
    (void)position;
    (void)status;
    (void)first_illegal_index;
    (void)err;
    assert(false && "the rules facade is not built; open() must gate this");
    return MXQ_ERR_INTERNAL_INVARIANT;
}

MxqStatus RulesFacade::legal_moves(MxqGameKind game,
                                   const std::string &start_fen,
                                   const std::vector<std::string> &moves,
                                   std::vector<std::string> &out,
                                   MxqError &err) {
    (void)game;
    (void)start_fen;
    (void)moves;
    (void)out;
    (void)err;
    assert(false && "the rules facade is not built; open() must gate this");
    return MXQ_ERR_INTERNAL_INVARIANT;
}

MxqStatus RulesFacade::validate_setup(MxqGameKind game, const std::string &fen,
                                      MxqSetupViolation &violation, MxqError &err) {
    (void)game;
    (void)fen;
    (void)violation;
    (void)err;
    assert(false && "the rules facade is not built; open() must gate this");
    return MXQ_ERR_INTERNAL_INVARIANT;
}

#endif /* MXQ_TEST_RULES_FACADE */

} /* namespace mxqtest */
