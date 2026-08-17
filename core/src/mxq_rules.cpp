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

/* Outside the guard, because mxq_rules_start_fen is: a game with no frozen
 * start is a programming error to ask, and that assertion is compiled in every
 * configuration this file has. */
#include <cassert>

#if defined(MXQ_ENABLE_RULES_FACADE)
#include "mxq_core_state.hpp"
#include "mxq_deal.hpp"
#include "mxq_engine_bridge.hpp"
#include "mxq_jieqi_bridge.hpp"
#include "mxq_rules.hpp"
#include "mxq_setup.hpp"

#if defined(MXQ_ENABLE_GOMOKU_FACADE)
#include "mxq_rapfi_bridge.hpp"
#endif

#include <string>
#include <vector>

/* ------------------------------------------------------------------------- */
/* The dispatch: which engine answers for which game                         */
/* ------------------------------------------------------------------------- */

namespace mxq {
namespace rules {

namespace {

#if defined(MXQ_ENABLE_GOMOKU_FACADE)
/* The second bridge's replay refusals, in the shared vocabulary. */
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
#endif

/* The third bridge's, in the same vocabulary. It has no NotInitialised: the
 * jieqi slice's whole bootstrap is two calls that cannot fail and that the
 * bridge makes for itself, so there is no configuration for a caller to have
 * skipped and no asset for one to be missing. */
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
        /* The one movement game the first engine does not play. It is asked by
         * name rather than by any property of the position, because a jieqi
         * position with nothing left face down is spelled exactly as the
         * xiangqi position it is not. */
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
#if defined(MXQ_ENABLE_GOMOKU_FACADE)
    if (notation::move_class_of(game) == notation::MoveClass::Placement) {
        /* No check exists in these games, so the caller is told so rather than
         * left with whatever it initialised the flag to. */
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
#endif
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
        /* No engine is asked, and here that is a rule rather than a
         * convenience: the engine this game is played on validates nothing at
         * all — a malformed record is accepted and silently mangled, and a
         * face-down piece spelled off its own start square is an out-of-bounds
         * write — so the structural reading is the core's own and runs before
         * anything reaches it. */
        mxq::jieqi::Record record{};
        return mxq::jieqi::read_record(fen, record, detail);
    }
#if defined(MXQ_ENABLE_GOMOKU_FACADE)
    if (notation::move_class_of(game) == notation::MoveClass::Placement) {
        /* No engine is asked. The placement games' encoding is the core's own —
         * their engine holds a board and has no notation for one — so the
         * structural question is answered where the structure is defined. */
        return notation::well_formed_placement(game, fen, detail);
    }
#endif
    return engine::validate_fen(engine::variant_of(game), fen, detail);
}

} /* namespace rules */
} /* namespace mxq */

#endif

extern "C" {

MxqStatus MXQ_CALL mxq_rules_start_fen(MxqGameKind game, char *out, size_t cap,
                                       size_t *out_len, MxqError *err) {
    const MxqStatus rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    /* A game with no frozen start has nothing to report, and asking is a
     * programming error by the same reachability rule a game outside the
     * vocabulary meets: the caller owns the game axis and mxq.h states the
     * absence. Jieqi is that game — it begins from a dealt start and from no
     * other position, and whatever dealt the game holds the position. */
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
    if (!mxq::rules::validate_fen(game, fen, detail)) {
        mxq::fill_error(err, MXQ_ERR_RULES_INVALID_FEN, detail.c_str());
        return MXQ_ERR_RULES_INVALID_FEN;
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_rules_validate_setup(MxqCore *core, MxqGameKind game,
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
        /* begin_out zeroes, and zero is MXQ_SETUP_RULE_NONE and an empty
         * square — but not MXQ_COLOR_NONE, which is -1. Every field the caller
         * can read is written before any return below, the structural refusal
         * included. */
        out_violation->side = MXQ_COLOR_NONE;
    }

    mxq::setup::Violation found;
    std::string detail;
    switch (mxq::setup::evaluate(game, fen, found, detail)) {
    case mxq::setup::Error::None:
        break;
    case mxq::setup::Error::FenInvalid:
    case mxq::setup::Error::NotInitialised:
        /* The same pairing replay_into makes of the same two conditions, and
         * for the same reason: an engine that never came up cannot say what
         * board a FEN is of, so the honest answer is the one about the FEN. It
         * is unreachable through this surface — mxq_core_init fails whole when
         * the engine does not initialise — so what the arm decides is not which
         * code a caller sees but whether two entries reporting one condition
         * report it alike. They do. */
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
        /* The engine could not be run at all, which is a resource this machine
         * did not have rather than an answer about the position. */
        mxq::fill_error(err, MXQ_ERR_RESOURCE_ALLOCATION_FAILED, detail.c_str());
        return MXQ_ERR_RESOURCE_ALLOCATION_FAILED;
    }

    /* One reading of the replayed position, for both output shapes. Read twice
     * it would be right twice until one of the two stopped being written, which
     * is a side to move that is Red because nothing set it. */
    const MxqColor side_to_move =
        (fen.find(" w ") != std::string::npos) ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;

    if (out_position != nullptr) {
        out_position->ply_count = ply;
        out_position->position_revision = 0; /* session-free: no revision exists */
        out_position->side_to_move = side_to_move;
        out_position->in_check = in_check ? 1u : 0u;
        mxq::copy_bounded(out_position->fen, sizeof(out_position->fen), fen.c_str());
    }

    if (out_status != nullptr) {
        out_status->state = adj.state;
        out_status->reason = adj.reason;
        out_status->at_occurrence = adj.at_occurrence;
        out_status->side_to_move = side_to_move;
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

MxqStatus MXQ_CALL mxq_rules_deal(MxqCore *core, MxqGameKind game,
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
    /* One game is dealt. Asking any other for a deal is a programming error by
     * the same reachability rule mxq_rules_start_fen's absent frozen start
     * meets: the caller owns the game axis and mxq.h states which game this
     * is. */
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

    /* The shape both values are written in is checked where it is defined,
     * which is inside the derivation: one spelling, one test, and the detail
     * naming which of the two was not it. */
    mxq::deal::Deal derived;
    std::string detail;
    if (!mxq::deal::derive(seed, nonce, derived, detail)) {
        assert(false && "a handshake value is sixty-four lowercase hexadecimal "
                        "digits");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE, detail.c_str());
        return MXQ_ERR_ARG_RANGE;
    }

    /* The commitment cannot refuse a seed the derivation just accepted: both
     * ask the one question about it. */
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

#endif /* MXQ_ENABLE_RULES_FACADE */

} /* extern "C" */
