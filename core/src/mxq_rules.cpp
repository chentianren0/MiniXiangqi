/* The session-free rules facade.
 *
 * mxq_rules_start_fen is a constant of the ruleset and needs no engine. The
 * other three replay a history through the pinned fork and are compiled only
 * when MXQ_ENABLE_RULES_FACADE is ON; without it they are absent from the
 * library rather than stubbed, because the error taxonomy has no
 * not-implemented code and inventing one would be inventing contract
 * vocabulary. */

#include "mxq_internal.hpp"
#include "mxq_notation.hpp"

#if defined(MXQ_ENABLE_RULES_FACADE)
#include "mxq_core_state.hpp"
#include "mxq_engine_bridge.hpp"

#include <string>
#include <vector>
#endif

extern "C" {

MxqStatus MXQ_CALL mxq_rules_start_fen(MxqGameKind game, char *out, size_t cap,
                                       size_t *out_len, MxqError *err) {
    const MxqStatus rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    return mxq::write_string(mxq::notation::start_fen(game), out, cap, out_len,
                             err);
}

#if defined(MXQ_ENABLE_RULES_FACADE)

MxqStatus MXQ_CALL mxq_rules_validate_fen(MxqCore *core, MxqGameKind game,
                                          const char *fen, MxqError *err) {
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
    std::string detail;
    if (!mxq::engine::validate_fen(mxq::engine::variant_of(game), fen, detail)) {
        mxq::fill_error(err, MXQ_ERR_RULES_INVALID_FEN, detail.c_str());
        return MXQ_ERR_RULES_INVALID_FEN;
    }
    return MXQ_OK;
}

namespace {

/* Replay once and fill whichever output shape the caller asked for. evaluate
 * and legal_moves differ only in what they report, and sharing the replay is
 * what keeps them from ever disagreeing about the same history. */
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
    mxq::engine::Adjudication adj{};
    size_t first_illegal = 0;

    switch (mxq::engine::replay(mxq::engine::variant_of(game), start_fen, moves,
                                move_count, fen, in_check, ply, adj, out_legal,
                                first_illegal, detail)) {
    case mxq::engine::ReplayError::None:
        break;
    case mxq::engine::ReplayError::IllegalMove:
        if (out_first_illegal_index != nullptr) {
            *out_first_illegal_index = first_illegal;
        }
        mxq::fill_error_index(err, MXQ_ERR_RULES_INVALID_HISTORY,
                              detail.c_str(), first_illegal);
        return MXQ_ERR_RULES_INVALID_HISTORY;
    case mxq::engine::ReplayError::StartFenInvalid:
    case mxq::engine::ReplayError::NotInitialised:
        mxq::fill_error(err, MXQ_ERR_RULES_INVALID_FEN, detail.c_str());
        return MXQ_ERR_RULES_INVALID_FEN;
    }

    if (out_position != nullptr) {
        out_position->ply_count = ply;
        out_position->position_revision = 0; /* session-free: no revision exists */
        out_position->side_to_move =
            (fen.find(" w ") != std::string::npos) ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
        out_position->in_check = in_check ? 1u : 0u;
        mxq::copy_bounded(out_position->fen, sizeof(out_position->fen), fen.c_str());
    }

    if (out_status != nullptr) {
        out_status->state = adj.state;
        out_status->reason = adj.reason;
        out_status->at_occurrence = adj.at_occurrence;
        /* Session-free: undo, claim, resign and search are properties of a game
         * session, not of a position and a history. They read as unavailable
         * rather than as guesses. */
        out_status->undo_plies = 0;
        out_status->claim_available =
            (adj.state == MXQ_GAME_CLAIMABLE_DRAW) ? 1u : 0u;
        out_status->undo_available = 0;
        out_status->resign_available = 0;
        out_status->search_expected = 0;
    }

    return MXQ_OK;
}

} /* namespace */

MxqStatus MXQ_CALL mxq_rules_evaluate(MxqCore *core, MxqGameKind game,
                                      const char *start_fen,
                                      const char *const *moves, size_t move_count,
                                      MxqPosition *out_position,
                                      MxqGameStatus *out_status,
                                      size_t *out_first_illegal_index,
                                      MxqError *err) {
    return replay_into(core, game, start_fen, moves, move_count, out_position,
                       out_status, nullptr, out_first_illegal_index, err);
}

MxqStatus MXQ_CALL mxq_rules_legal_moves(MxqCore *core, MxqGameKind game,
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
    /* Zero legal moves is checkmate or stalemate, and reporting it needs no
     * buffer at all: a count of nothing fits in any capacity, including none.
     * Only an actual overflow is an error. */
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

#endif /* MXQ_ENABLE_RULES_FACADE */

} /* extern "C" */
