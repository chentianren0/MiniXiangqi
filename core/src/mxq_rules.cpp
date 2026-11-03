/* The rules facade. mxq_rules_start_fen needs no engine; mxq_rules_deal derives
 * a dealt start; the rest replay a history through an engine. */

#include "mxq_internal.hpp"
#include "mxq_notation.hpp"

#include <cassert>

#include "mxq_core_state.hpp"
#include "mxq_deal.hpp"
#include "mxq_engine_bridge.hpp"
#include "mxq_jieqi_bridge.hpp"
#include "mxq_rules.hpp"
#include "mxq_setup.hpp"

#include "mxq_rapfi_bridge.hpp"

#include <string>
#include <vector>

/* ------------------------------------------------------------------------- */
/* The dispatch: which engine answers for which game                         */
/* ------------------------------------------------------------------------- */

namespace mxq {
namespace rules {

namespace {

/* Rapfi's replay refusals, in the shared vocabulary. */
ReplayError from_placement(mxq::rapfi::ReplayError rc) {
    switch (rc) {
    case mxq::rapfi::ReplayError::None:
        return ReplayError::None;
    case mxq::rapfi::ReplayError::StartFenInvalid:
        return ReplayError::StartFenInvalid;
    case mxq::rapfi::ReplayError::IllegalMove:
        return ReplayError::IllegalMove;
    case mxq::rapfi::ReplayError::Faulted:
        return ReplayError::Faulted;
    }
    return ReplayError::Faulted;
}

/* The Jieqi bridge's. It has no NotInitialised: its bootstrap cannot fail and
 * the bridge runs it itself. */
ReplayError from_jieqi(mxq::jieqi::ReplayError rc) {
    switch (rc) {
    case mxq::jieqi::ReplayError::None:
        return ReplayError::None;
    case mxq::jieqi::ReplayError::StartFenInvalid:
        return ReplayError::StartFenInvalid;
    case mxq::jieqi::ReplayError::IllegalMove:
        return ReplayError::IllegalMove;
    case mxq::jieqi::ReplayError::Faulted:
        return ReplayError::Faulted;
    }
    return ReplayError::Faulted;
}

} /* namespace */

ReplayError replay(MxqGameKind game, const char *start_fen,
                   const char *const *moves, size_t move_count,
                   std::string &out_fen, bool &out_in_check, uint32_t &out_ply,
                   Adjudication &out_adj,
                   std::vector<std::string> *out_legal_moves,
                   size_t &first_illegal, std::string &detail) {
    assert(notation::known_game(game) && "a game outside the closed vocabulary");
    if (game == MXQ_GAME_KIND_JIEQI) {
        /* Asked by name, because a Jieqi position with nothing face down is
         * spelled exactly as a Xiangqi one. */
        mxq::jieqi::Adjudication hidden{MXQ_GAME_ONGOING, MXQ_END_REASON_NONE,
                                        0};
        const ReplayError rc = from_jieqi(mxq::jieqi::replay(
            start_fen, moves, move_count, out_fen, out_in_check, out_ply, hidden,
            out_legal_moves, first_illegal, detail));
        out_adj.state = hidden.state;
        out_adj.reason = hidden.reason;
        out_adj.at_occurrence = hidden.at_occurrence;
        return rc;
    }
    if (notation::move_class_of(game) == notation::MoveClass::Placement) {
        /* No check exists in these games. */
        out_in_check = false;
        mxq::rapfi::Adjudication placement{MXQ_GAME_ONGOING,
                                           MXQ_END_REASON_NONE};
        const ReplayError rc = from_placement(mxq::rapfi::replay(
            game, start_fen, moves, move_count, out_fen, out_ply, placement,
            out_legal_moves, first_illegal, detail));
        out_adj.state = placement.state;
        out_adj.reason = placement.reason;
        out_adj.at_occurrence = 0;
        return rc;
    }
    switch (engine::replay(engine::variant_of(game), start_fen, moves,
                           move_count, out_fen, out_in_check, out_ply, out_adj,
                           out_legal_moves, first_illegal, detail)) {
    case engine::ReplayError::None:
        return ReplayError::None;
    case engine::ReplayError::NotInitialised:
        return ReplayError::NotInitialised;
    case engine::ReplayError::StartFenInvalid:
        return ReplayError::StartFenInvalid;
    case engine::ReplayError::IllegalMove:
        return ReplayError::IllegalMove;
    }
    return ReplayError::NotInitialised;
}

bool validate_fen(MxqGameKind game, const char *fen, std::string &detail) {
    assert(notation::known_game(game) && "a game outside the closed vocabulary");
    if (game == MXQ_GAME_KIND_JIEQI) {
        /* No engine is asked: Pikafish validates nothing — a malformed record
         * is silently mangled, and a face-down piece off its own start square
         * is an out-of-bounds write — so the structural reading is the core's
         * own and runs before anything reaches it. */
        mxq::jieqi::Record record{};
        return mxq::jieqi::read_record(fen, record, detail);
    }
    if (notation::move_class_of(game) == notation::MoveClass::Placement) {
        /* No engine is asked: Rapfi has no notation for a board, so the
         * placement encoding is the core's own. */
        return notation::well_formed_placement(game, fen, detail);
    }
    return engine::validate_fen(engine::variant_of(game), fen, detail);
}

} /* namespace rules */
} /* namespace mxq */


extern "C" {

MxqStatus mxq_rules_start_fen(MxqGameKind game, char *out, size_t cap,
                                       size_t *out_len, MxqError *err) {
    const MxqStatus rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    /* Jieqi has no frozen start; it begins from a deal. */
    if (!mxq::notation::has_frozen_start(game)) {
        assert(false && "this game has no frozen start to report");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "this game has no frozen starting position; it begins "
                        "from a dealt start and from no other");
        return MXQ_ERR_ARG_RANGE;
    }
    return mxq::write_string(mxq::notation::start_fen(game), out, cap, out_len,
                             err);
}


MxqStatus mxq_rules_validate_setup(MxqCore *core, MxqGameKind game,
                                            const char *fen,
                                            MxqSetupViolation *out_violation,
                                            MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (fen == nullptr) {
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "fen was null");
        return MXQ_ERR_ARG_NULL;
    }
    if (out_violation != nullptr) {
        const MxqStatus orc = mxq::begin_out(
            out_violation, out_violation->struct_size,
            static_cast<uint32_t>(sizeof(MxqSetupViolation)),
            static_cast<uint32_t>(sizeof(MxqSetupViolation)), err);
        if (orc != MXQ_OK) {
            return orc;
        }
        /* begin_out zeroes, but MXQ_COLOR_NONE is -1. Every field is written
         * before any return below. */
        out_violation->side = MXQ_COLOR_NONE;
    }

    mxq::setup::Violation found;
    std::string detail;
    switch (mxq::setup::evaluate(game, fen, found, detail)) {
    case mxq::setup::Error::None:
        break;
    case mxq::setup::Error::FenInvalid:
    case mxq::setup::Error::NotInitialised:
        /* Paired as replay_into pairs them: an engine that never came up
         * cannot say what board a FEN is of. */
        mxq::fill_error(err, MXQ_ERR_RULES_INVALID_FEN, detail.c_str());
        return MXQ_ERR_RULES_INVALID_FEN;
    }

    if (out_violation != nullptr) {
        out_violation->rule = found.rule;
        out_violation->side = found.side;
        mxq::copy_bounded(out_violation->square, sizeof(out_violation->square),
                          found.square.c_str());
    }
    if (found.rule == MXQ_SETUP_RULE_NONE) {
        return MXQ_OK;
    }
    mxq::fill_error(err, MXQ_ERR_RULES_ILLEGAL_POSITION, detail.c_str());
    return MXQ_ERR_RULES_ILLEGAL_POSITION;
}

namespace {

/* Replay once and fill whichever output shape the caller asked for, so that
 * evaluate and legal_moves never disagree about the same history. */
MxqStatus replay_into(MxqCore *core, MxqGameKind game, const char *start_fen,
                      const char *const *moves, size_t move_count,
                      MxqPosition *out_position, MxqGameStatus *out_status,
                      std::vector<std::string> *out_legal,
                      size_t *out_first_illegal_index, MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (start_fen == nullptr) {
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "start_fen was null");
        return MXQ_ERR_ARG_NULL;
    }

    if (out_position != nullptr) {
        const MxqStatus prc = mxq::begin_out(
            out_position, out_position->struct_size,
            static_cast<uint32_t>(sizeof(MxqPosition)),
            static_cast<uint32_t>(sizeof(MxqPosition)), err);
        if (prc != MXQ_OK) {
            return prc;
        }
    }
    if (out_status != nullptr) {
        const MxqStatus src = mxq::begin_out(
            out_status, out_status->struct_size,
            static_cast<uint32_t>(sizeof(MxqGameStatus)),
            static_cast<uint32_t>(sizeof(MxqGameStatus)), err);
        if (src != MXQ_OK) {
            return src;
        }
    }

    std::string fen;
    std::string detail;
    bool in_check = false;
    uint32_t ply = 0;
    mxq::rules::Adjudication adj{};
    size_t first_illegal = 0;

    switch (mxq::rules::replay(game, start_fen, moves, move_count, fen, in_check,
                               ply, adj, out_legal, first_illegal, detail)) {
    case mxq::rules::ReplayError::None:
        break;
    case mxq::rules::ReplayError::IllegalMove:
        if (out_first_illegal_index != nullptr) {
            *out_first_illegal_index = first_illegal;
        }
        mxq::fill_error_index(err, MXQ_ERR_RULES_INVALID_HISTORY,
                              detail.c_str(), first_illegal);
        return MXQ_ERR_RULES_INVALID_HISTORY;
    case mxq::rules::ReplayError::StartFenInvalid:
    case mxq::rules::ReplayError::NotInitialised:
        mxq::fill_error(err, MXQ_ERR_RULES_INVALID_FEN, detail.c_str());
        return MXQ_ERR_RULES_INVALID_FEN;
    case mxq::rules::ReplayError::Faulted:
        /* A resource this machine did not have, not an answer about the
         * position. */
        mxq::fill_error(err, MXQ_ERR_RESOURCE_ALLOCATION_FAILED, detail.c_str());
        return MXQ_ERR_RESOURCE_ALLOCATION_FAILED;
    }

    /* One reading of the replayed position, for both output shapes. */
    const MxqColor side_to_move =
        (fen.find(" w ") != std::string::npos) ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;

    if (out_position != nullptr) {
        out_position->ply_count = ply;
        out_position->side_to_move = side_to_move;
        out_position->in_check = in_check ? 1u : 0u;
        mxq::copy_bounded(out_position->fen, sizeof(out_position->fen), fen.c_str());
    }

    if (out_status != nullptr) {
        out_status->state = adj.state;
        out_status->reason = adj.reason;
        out_status->at_occurrence = adj.at_occurrence;
        out_status->side_to_move = side_to_move;
    }

    return MXQ_OK;
}

} /* namespace */

MxqStatus mxq_rules_evaluate(MxqCore *core, MxqGameKind game,
                                      const char *start_fen,
                                      const char *const *moves, size_t move_count,
                                      MxqPosition *out_position,
                                      MxqGameStatus *out_status,
                                      size_t *out_first_illegal_index,
                                      MxqError *err) {
    return replay_into(core, game, start_fen, moves, move_count, out_position,
                       out_status, nullptr, out_first_illegal_index, err);
}

MxqStatus mxq_rules_legal_moves(MxqCore *core, MxqGameKind game,
                                         const char *start_fen,
                                         const char *const *moves,
                                         size_t move_count, MxqMove *out,
                                         size_t cap, size_t *out_count,
                                         MxqError *err) {
    if (out_count == nullptr) {
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "out_count was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_count = 0;

    std::vector<std::string> legal;
    const MxqStatus rc = replay_into(core, game, start_fen, moves, move_count,
                                     nullptr, nullptr, &legal, nullptr, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    *out_count = legal.size();
    /* Zero legal moves needs no buffer; only an actual overflow is an
     * error. */
    if (legal.empty()) {
        return MXQ_OK;
    }
    if (out == nullptr || cap < legal.size()) {
        mxq::fill_error_required(err, MXQ_ERR_ARG_BUFFER_TOO_SMALL,
                                 "the legal-move buffer is too small",
                                 legal.size());
        return MXQ_ERR_ARG_BUFFER_TOO_SMALL;
    }
    for (size_t i = 0; i < legal.size(); ++i) {
        out[i].struct_size = static_cast<uint32_t>(sizeof(MxqMove));
        mxq::copy_bounded(out[i].text, sizeof(out[i].text), legal[i].c_str());
    }
    return MXQ_OK;
}

MxqStatus mxq_rules_deal(MxqCore *core, MxqGameKind game,
                                  const char *seed, const char *nonce,
                                  MxqDeal *out, MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (game != MXQ_GAME_KIND_JIEQI) {
        assert(false && "this game has no deal");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "this game is not dealt; it begins from a position no "
                        "seed and nonce derive");
        return MXQ_ERR_ARG_RANGE;
    }
    if (seed == nullptr) {
        assert(false && "required seed pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "seed was null");
        return MXQ_ERR_ARG_NULL;
    }
    if (nonce == nullptr) {
        assert(false && "required nonce pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "nonce was null");
        return MXQ_ERR_ARG_NULL;
    }

    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqDeal)),
                        static_cast<uint32_t>(sizeof(MxqDeal)), err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /* The derivation checks the shape of both values. */
    mxq::deal::Deal derived;
    std::string detail;
    if (!mxq::deal::derive(seed, nonce, derived, detail)) {
        assert(false && "a handshake value is sixty-four lowercase hexadecimal "
                        "digits");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE, detail.c_str());
        return MXQ_ERR_ARG_RANGE;
    }

    /* Cannot refuse a seed the derivation just accepted. */
    std::string commit;
    const bool bound = mxq::deal::commitment_of(seed, commit);
    assert(bound && "the seed the derivation read is the seed this binds");
    (void)bound;

    mxq::copy_bounded(out->start_fen, sizeof(out->start_fen),
                      mxq::deal::start_of(derived).c_str());
    mxq::copy_bounded(out->commit, sizeof(out->commit), commit.c_str());
    mxq::copy_bounded(out->digest, sizeof(out->digest), derived.digest.c_str());
    return MXQ_OK;
}


} /* extern "C" */
