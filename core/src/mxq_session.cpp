/* Sessions: the mxq_game_ surface. See mxq_session.hpp for the design. */

#include "mxq_session.hpp"

#include "mxq_archive_read.hpp"
#include "mxq_archive_write.hpp"
#include "mxq_core_state.hpp"
#include "mxq_deal.hpp"
#include "mxq_engine_bridge.hpp"
#include "mxq_internal.hpp"
#include "mxq_notation.hpp"
#include "mxq_rules.hpp"
#include "mxq_setup.hpp"
#include "mxq_sha256.hpp"
#include "mxq_store.hpp"

#include <algorithm>
#include <cassert>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace mxq {
namespace session {
namespace {

/* ---------------------------------------------------------------------- */
/* The handle registry                                                     */
/* ---------------------------------------------------------------------- */

/*
 * Every handle issued and not yet released. Membership is what makes a stale
 * pointer answerable: a session function is handed a pointer it may not
 * dereference until this registry says the pointer is one of ours, and a
 * tombstoned entry — a session whose core has shut down — is still an entry,
 * still valid memory, and still released by its owner.
 *
 * The registry is a flat vector because a frontend holds one or two sessions;
 * an index would cost more than the scan.
 */
std::mutex &registry_mutex() {
    static std::mutex mutex;
    return mutex;
}

std::vector<MxqGame *> &registry() {
    static std::vector<MxqGame *> live;
    return live;
}

void register_session(MxqGame *game) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    /* Process-unique and never reused, unlike the object's address, which the
     * allocator may hand to a later session; 1-based so that an unregistered
     * session's zero can never name anything. */
    static uint64_t next_instance = 1;
    game->instance_id = next_instance++;
    registry().push_back(game);
}

bool known(const MxqGame *game) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    return std::find(registry().begin(), registry().end(), game) !=
           registry().end();
}

void forget(MxqGame *game) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    std::vector<MxqGame *> &live = registry();
    live.erase(std::remove(live.begin(), live.end(), game), live.end());
}

/* ---------------------------------------------------------------------- */
/* Entry                                                                   */
/* ---------------------------------------------------------------------- */

/*
 * The two checks every session function makes, in this order: the handle is
 * one this core issued and has not been tombstoned, and no other thread is
 * inside the session.
 *
 * A pointer the registry does not know is a programming error and asserts in a
 * debug build, as the argument domain does. A tombstoned handle does not
 * assert: mxq.h documents MXQ_ERR_ARG_INVALID_HANDLE as what every outstanding
 * handle answers after mxq_core_shutdown, so returning it there is the
 * contract being kept rather than a caller being caught.
 */
/*
 * The third check, made by every mutation and by nothing else.
 *
 * The order matters: a detached session was never attached to a row, so
 * read-only is asked before archived. Read-only asserts because mxq.h lists it
 * among the programming errors; archived does not, because a frontend can
 * legitimately still hold the handle of a game that has just ended.
 */
MxqStatus require_mutable_impl(const MxqGame *game, MxqError *err) {
    if (game->read_only) {
        assert(false && "a call needing a mutable session on a detached "
                        "read-only one");
        fill_error(err, MXQ_ERR_STATE_SESSION_READ_ONLY,
                   "this session is a detached read-only replay");
        return MXQ_ERR_STATE_SESSION_READ_ONLY;
    }
    if (game->archived) {
        fill_error(err, MXQ_ERR_STATE_SESSION_ARCHIVED,
                   "this game has been archived and is now an immutable "
                   "History record");
        return MXQ_ERR_STATE_SESSION_ARCHIVED;
    }
    return MXQ_OK;
}

MxqStatus require_impl(const MxqGame *game, MxqError *err) {
    /* Before anything else, even the null check: inside a search callback no
     * session function is legal, and the refusal must arrive before the
     * handle is judged. */
    if (in_search_callback()) {
        return refuse_reentrant(err);
    }
    if (game == nullptr) {
        assert(false && "required session handle was null");
        fill_error(err, MXQ_ERR_ARG_NULL, "required session handle was null");
        return MXQ_ERR_ARG_NULL;
    }
    if (!known(game)) {
        assert(false && "session handle was never issued, or was released");
        fill_error(err, MXQ_ERR_ARG_INVALID_HANDLE,
                   "the session handle is not live");
        return MXQ_ERR_ARG_INVALID_HANDLE;
    }
    if (game->core == nullptr) {
        fill_error(err, MXQ_ERR_ARG_INVALID_HANDLE,
                   "the session's core has shut down");
        return MXQ_ERR_ARG_INVALID_HANDLE;
    }
    return MXQ_OK;
}

/* ---------------------------------------------------------------------- */
/* Rules, through the one facade                                           */
/* ---------------------------------------------------------------------- */

/* What replaying a prefix of the retained line reports. */
struct Replayed {
    std::string              fen;
    bool                     in_check = false;
    uint32_t                 ply = 0;
    rules::Adjudication      adj{};
    std::vector<std::string> legal;
};

/*
 * Replay the first ply_count plies. A failure here is not an ordinary outcome:
 * the retained line was legal when it was accepted and was validated again
 * when it was resumed, so a line that stops replaying means this build no
 * longer agrees with a game it committed. It is reported as an internal
 * invariant violation rather than dressed up as a rules answer.
 */
MxqStatus replay_prefix(const MxqGame &game, size_t ply_count, bool want_legal,
                        Replayed &out, MxqError *err) {
    std::vector<const char *> moves;
    moves.reserve(ply_count);
    for (size_t i = 0; i < ply_count; ++i) {
        moves.push_back(game.moves[i].c_str());
    }

    std::string detail;
    size_t first_illegal = 0;
    /* The session's own configuration decides everything: which starting
     * position the line runs from and which ruleset it is replayed under.
     * Neither is derived from the other, and neither is a default — the start is
     * the game's frozen one only where the configuration named no other. */
    const MxqGameKind kind = game.config.game;
    const rules::ReplayError rc = rules::replay(
        kind, notation::start_fen(game.config),
        moves.empty() ? nullptr : moves.data(), moves.size(), out.fen,
        out.in_check, out.ply, out.adj, want_legal ? &out.legal : nullptr,
        first_illegal, detail);
    if (rc != rules::ReplayError::None) {
        /* "this game" rather than "the retained line": the shortest prefix this
         * replays is no prefix at all, which is the start position by itself,
         * and a game with no plies yet has no line to say has stopped
         * replaying. */
        fill_error(err, MXQ_ERR_INTERNAL_INVARIANT,
                   ("this game no longer replays: " + detail).c_str());
        return MXQ_ERR_INTERNAL_INVARIANT;
    }
    return MXQ_OK;
}

MxqColor side_to_move(const std::string &fen) {
    return fen.find(" w ") != std::string::npos ? MXQ_COLOR_RED
                                                : MXQ_COLOR_BLACK;
}

/*
 * Which side made ply i.
 *
 * Ply 0 is the first move played from the session's start position, by
 * whichever side that position has to move — Red from a frozen start, and
 * whichever side a composed one names. So the parity alone decides nothing:
 * it selects between the start's side and the other, and the start is what
 * says which those are.
 */
MxqColor mover_of(const MxqGameConfig &config, size_t ply_index) {
    const MxqColor first = side_to_move(notation::start_fen(config));
    const MxqColor second =
        first == MXQ_COLOR_RED ? MXQ_COLOR_BLACK : MXQ_COLOR_RED;
    return (ply_index % 2 == 0) ? first : second;
}

/*
 * The start a caller's configuration names, or the empty string where it names
 * the game's own — which an empty member and the frozen FEN spelled out both
 * do. Every entry that judges a start reads it through here, so "this
 * configuration composes a position" is one answer rather than three.
 *
 * The read is bounded by the member's declared size rather than by a
 * terminator, because the array is the caller's: a member left unterminated is
 * a caller's defect, and reading past it would make that defect this core's
 * crash. What comes back is a std::string, so nothing downstream is reading the
 * caller's storage any more.
 */
std::string named_start(const MxqGameConfig &config) {
    const void *nul =
        std::memchr(config.start_fen, '\0', sizeof(config.start_fen));
    const size_t length =
        nul != nullptr
            ? static_cast<size_t>(static_cast<const char *>(nul) -
                                  config.start_fen)
            : sizeof(config.start_fen);
    std::string named(config.start_fen, length);
    /* The canonicalisation is against a frozen start, so a game that has none
     * keeps whatever it named: a Jieqi session's start always reads back spelled
     * out, there being no constant for the empty member to have meant. */
    if (notation::has_frozen_start(config.game) &&
        named == notation::start_fen(config.game)) {
        named.clear();
    }
    return named;
}

bool terminal(MxqGameState state) {
    return state == MXQ_GAME_RED_WINS || state == MXQ_GAME_BLACK_WINS ||
           state == MXQ_GAME_DRAW;
}

/*
 * How many plies one Undo removes, and whether Undo is available at all.
 *
 * Free Play removes one ply and supports repeated Undo to the initial
 * position. Human-versus-AI proceeds by human decision cycles: with the human's
 * own move last, that move is what an Undo cancels; with the AI's reply last,
 * the reply and the human move that triggered it come off together. The one
 * position with no cycle to return to is an AI-first game after the AI's
 * opening move and before the human has answered — undoing it would return to
 * a position the AI must move in again, which is not a decision the human
 * made, so there is nothing to undo yet.
 *
 * An unconfirmed natural terminal state remains the active game and can be
 * undone (docs/game-data.md), so a terminal state does not withdraw Undo.
 */
uint32_t undo_plies_for(const MxqGame &game) {
    const size_t n = game.moves.size();
    if (n == 0) {
        return 0;
    }
    /* A nearby game has no unilateral undo (docs/game-data.md): a retraction
     * there is the two players' agreement, and what it retracts is what they
     * agreed to keep, which is not this call's one-or-two plies. */
    if (game.config.mode == MXQ_PLAY_MODE_NEARBY) {
        return 0;
    }
    if (game.config.mode != MXQ_PLAY_MODE_HUMAN_VS_AI) {
        return 1;
    }
    if (mover_of(game.config, n - 1) == game.config.human_side) {
        return 1;
    }
    return n >= 2 ? 2u : 0u;
}

void fill_status(const MxqGame &game, const Replayed &replayed,
                 MxqGameStatus *out) {
    out->state = replayed.adj.state;
    out->reason = replayed.adj.reason;
    out->at_occurrence = replayed.adj.at_occurrence;
    /* Whose turn it is, from the replayed position and never from a ply count.
     * Reported in every state, the finished ones included: what a finished game
     * is nobody's turn for is a presentation rule, and `state` is what says the
     * game is finished. */
    out->side_to_move = side_to_move(replayed.fen);

    /*
     * A session that can no longer mutate offers nothing. A replay and an
     * archived game are both finished: undo, the claim, resignation and an
     * owed search are all actions on a game still being played, and a frontend
     * that had to work that out for itself would be re-deriving exactly the
     * policy these flags exist to carry.
     *
     * The state above is still the replayed one, because that is what
     * MxqGameState is for: the committed outcome of a finished game — which
     * for a resignation or an ended-early record is not a position's verdict
     * at all — is MxqOutcome, and MxqRecordSummary is where it is read.
     */
    if (game.read_only || game.archived) {
        out->undo_available = 0;
        out->undo_plies = 0;
        out->claim_available = 0;
        out->resign_available = 0;
        out->search_expected = 0;
        return;
    }

    const uint32_t undo = undo_plies_for(game);
    out->undo_available = undo > 0 ? 1u : 0u;
    out->undo_plies = undo;

    out->claim_available =
        replayed.adj.state == MXQ_GAME_CLAIMABLE_DRAW ? 1u : 0u;

    /* Resignation is human-versus-AI only, and there is nothing to resign once
     * the game has a result of its own. A claimable repetition is not a
     * result: the game continues unless the claim is made. */
    out->resign_available =
        (game.config.mode == MXQ_PLAY_MODE_HUMAN_VS_AI &&
         !terminal(replayed.adj.state))
            ? 1u
            : 0u;

    /* A search is owed when the game is human-versus-AI, still running, and
     * the side to move is the AI's. Deriving it here is the point: no frontend
     * re-derives whose turn it is. */
    out->search_expected =
        (game.config.mode == MXQ_PLAY_MODE_HUMAN_VS_AI &&
         !terminal(replayed.adj.state) &&
         side_to_move(replayed.fen) != game.config.human_side)
            ? 1u
            : 0u;
}

void fill_position(const MxqGame &game, const Replayed &replayed,
                   MxqPosition *out) {
    out->ply_count = replayed.ply;
    out->position_revision =
        game.position_revision.load(std::memory_order_acquire);
    out->side_to_move = side_to_move(replayed.fen);
    out->in_check = replayed.in_check ? 1u : 0u;
    copy_bounded(out->fen, sizeof(out->fen), replayed.fen.c_str());
}

/* The buffer convention of mxq_game_legal_moves, shared by the three functions
 * that answer a move list: *out_count is always the number available, and a
 * capacity below it is the routine buffer-too-small answer with the required
 * size set. */
MxqStatus write_moves(const std::vector<std::string> &moves, MxqMove *out,
                      size_t cap, size_t *out_count, const char *what,
                      MxqError *err) {
    *out_count = moves.size();
    if (moves.empty()) {
        return MXQ_OK;
    }
    if (out == nullptr || cap < moves.size()) {
        fill_error_required(err, MXQ_ERR_ARG_BUFFER_TOO_SMALL, what,
                            moves.size());
        return MXQ_ERR_ARG_BUFFER_TOO_SMALL;
    }
    for (size_t i = 0; i < moves.size(); ++i) {
        out[i].struct_size = static_cast<uint32_t>(sizeof(MxqMove));
        copy_bounded(out[i].text, sizeof(out[i].text), moves[i].c_str());
    }
    return MXQ_OK;
}

/* ---------------------------------------------------------------------- */
/* Writing the one active row                                              */
/* ---------------------------------------------------------------------- */

/* The row a record encodes to: the canonical bytes, their hash, and the
 * summary columns, all derived from the same values in one place so that the
 * columns can never disagree with the blob. */
store::ActiveGame row_of(const archive::Record &record,
                         const std::string &document,
                         const std::string &content) {
    store::ActiveGame row;
    row.game_id = record.game_id;
    row.archive = document;
    row.content_sha256 = sha256_hex(content);
    row.rules_id = archive::rules_id_text(record.config.game);
    row.mode = archive::mode_text(record.config.mode);
    row.human_side = archive::color_text(record.config.human_side);
    row.ai_level = archive::ai_level_text(record.config.ai_level);
    row.first_mover_choice =
        archive::first_mover_text(record.config.first_mover_choice);
    /* The one column the document does not carry: local perspective is store
     * metadata, so it is written here from the frozen configuration and never
     * from the bytes. */
    row.local_side = archive::color_text(record.config.local_side);
    row.ai_movetime_ms = static_cast<int64_t>(record.config.ai_movetime_ms);
    row.move_count = static_cast<int64_t>(record.moves.size());
    row.started_at_ms = record.started_at_ms;
    return row;
}

/* ---------------------------------------------------------------------- */
/* The wire session a nearby game is played over                           */
/* ---------------------------------------------------------------------- */

const char *nearby_terminal_text(MxqNearbyTerminal terminal) {
    switch (terminal) {
    case MXQ_NEARBY_TERMINAL_RESIGN:      return "resign";
    case MXQ_NEARBY_TERMINAL_ACCEPT_DRAW: return "accept_draw";
    default: break;
    }
    return "";
}

/* The C struct as the store's row. The two identifiers travel verbatim; the two
 * closed vocabularies become the serialised spellings the schema's CHECK
 * constraints are written in, exactly as every other store vocabulary does; and
 * the four deal values travel verbatim too, the empty string spelling the SQL
 * NULL a session with no deal holds. */
store::NearbySession nearby_row_of(const MxqNearbySession &state) {
    store::NearbySession row;
    row.session_id = state.session_id;
    row.peer_id = state.peer_id;
    row.proposer =
        state.proposer == MXQ_NEARBY_PROPOSER_PEER ? "peer" : "local";
    row.sent_end = nearby_terminal_text(state.sent_end);
    row.undos = static_cast<int64_t>(state.undos);
    row.keep = static_cast<int64_t>(state.keep);
    row.claimed = state.claimed != 0;
    row.deal_commit = state.deal_commit;
    row.deal_nonce = state.deal_nonce;
    row.deal_seed = state.deal_seed;
    row.deal_digest = state.deal_digest;
    return row;
}

/* What a mutation of this session writes beside its move line: the wire session
 * where it has one, and nothing where it has none. */
const store::NearbySession *nearby_of(const MxqGame &game,
                                      store::NearbySession &scratch) {
    if (!game.has_nearby) {
        return nullptr;
    }
    scratch = nearby_row_of(game.nearby);
    return &scratch;
}

/* One identifier copied into its fixed capacity. Refuses rather than truncates:
 * a session identifier one byte short is a different session. */
bool copy_identifier(const char *value, char *out, size_t cap) {
    if (value == nullptr) {
        return false;
    }
    const size_t length = std::strlen(value);
    if (length == 0 || length >= cap) {
        return false;
    }
    std::memcpy(out, value, length + 1);
    return true;
}

/*
 * A stored row as the session carries it. The vocabularies are the schema's
 * own, so a value outside them is store corruption rather than a guess — the
 * same answer fill_summary gives a column outside its closed set. The two
 * identifiers are constrained non-empty by the schema and bounded by the
 * capacity this interface defines; a row that does not fit one is corrupt for
 * the same reason.
 */
MxqStatus adopt_nearby_row(MxqGame &game, const store::NearbySession &row,
                           MxqError *err) {
    MxqNearbySession state;
    std::memset(&state, 0, sizeof(state));
    state.struct_size = static_cast<uint32_t>(sizeof(state));
    if (row.proposer == "local") {
        state.proposer = MXQ_NEARBY_PROPOSER_LOCAL;
    } else if (row.proposer == "peer") {
        state.proposer = MXQ_NEARBY_PROPOSER_PEER;
    } else {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   "the wire session's proposer is not one of the two peers");
        return MXQ_ERR_STORE_CORRUPT;
    }
    if (row.sent_end.empty()) {
        state.sent_end = MXQ_NEARBY_TERMINAL_NONE;
    } else if (row.sent_end == "resign") {
        state.sent_end = MXQ_NEARBY_TERMINAL_RESIGN;
    } else if (row.sent_end == "accept_draw") {
        state.sent_end = MXQ_NEARBY_TERMINAL_ACCEPT_DRAW;
    } else {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   "the wire session's terminal is not one the protocol sends");
        return MXQ_ERR_STORE_CORRUPT;
    }
    if (row.undos < 0 || row.keep < 0 ||
        !copy_identifier(row.session_id.c_str(), state.session_id,
                         MXQ_NEARBY_SESSION_ID_CAP) ||
        !copy_identifier(row.peer_id.c_str(), state.peer_id,
                         MXQ_NEARBY_PEER_ID_CAP)) {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   "the wire session's identifiers or counts are not ones this "
                   "build can hold");
        return MXQ_ERR_STORE_CORRUPT;
    }
    state.undos = static_cast<uint32_t>(row.undos);
    state.keep = static_cast<uint32_t>(row.keep);
    state.claimed = row.claimed ? 1u : 0u;

    /* The four deal values, present exactly for a session of the one game whose
     * start is dealt. The schema says so too, in a trigger, so a row that
     * disagrees is corruption rather than a shape this build should carry
     * forward; and the values themselves are re-verified by the caller, against
     * everything the deal comes from, before the session is handed out. */
    {
        const bool dealt = game.config.game == MXQ_GAME_KIND_JIEQI;
        const std::string *const columns[] = {&row.deal_commit, &row.deal_nonce,
                                              &row.deal_seed, &row.deal_digest};
        char *const fields[] = {state.deal_commit, state.deal_nonce,
                                state.deal_seed, state.deal_digest};
        for (size_t i = 0; i < 4; ++i) {
            if (columns[i]->empty() == dealt ||
                (dealt && !deal::is_hex32(*columns[i]))) {
                fill_error(err, MXQ_ERR_STORE_CORRUPT,
                           "the wire session's deal is not the shape this "
                           "game's session has");
                return MXQ_ERR_STORE_CORRUPT;
            }
            if (dealt) {
                std::memcpy(fields[i], columns[i]->c_str(),
                            columns[i]->size() + 1);
            }
        }
    }

    game.has_nearby = true;
    game.nearby = state;
    return MXQ_OK;
}

/*
 * The shape of an arriving wire session: the two closed vocabularies, two
 * identifiers that are present and fit, and the deal — four values that are
 * each sixty-four lowercase hexadecimal digits for the one game whose start is
 * dealt and empty for every other. It is a programming error to get any of it
 * wrong; every value here is one the frontend itself owns, and which game it is
 * playing most of all.
 */
MxqStatus read_nearby_state(MxqGameKind game, const MxqNearbySession *state,
                            MxqNearbySession &out, MxqError *err) {
    MxqStatus rc = check_in(state, state != nullptr ? state->struct_size : 0u,
                            static_cast<uint32_t>(sizeof(MxqNearbySession)),
                            static_cast<uint32_t>(sizeof(MxqNearbySession)),
                            err);
    if (rc != MXQ_OK) {
        return rc;
    }
    const bool vocabulary_ok =
        (state->proposer == MXQ_NEARBY_PROPOSER_LOCAL ||
         state->proposer == MXQ_NEARBY_PROPOSER_PEER) &&
        (state->sent_end == MXQ_NEARBY_TERMINAL_NONE ||
         state->sent_end == MXQ_NEARBY_TERMINAL_RESIGN ||
         state->sent_end == MXQ_NEARBY_TERMINAL_ACCEPT_DRAW) &&
        state->claimed <= 1;
    std::memset(&out, 0, sizeof(out));
    out.struct_size = static_cast<uint32_t>(sizeof(MxqNearbySession));
    out.proposer = state->proposer;
    out.undos = state->undos;
    out.keep = state->keep;
    out.sent_end = state->sent_end;
    out.claimed = state->claimed;

    /* The deal, whose presence is the game's: a session of the one dealt game
     * carries all four values and a session of any other carries none. Read
     * bounded by the member's declared size, exactly as the two identifiers
     * are, because the array is the caller's. */
    bool deal_ok = true;
    {
        const bool dealt = game == MXQ_GAME_KIND_JIEQI;
        const char *const from[] = {state->deal_commit, state->deal_nonce,
                                    state->deal_seed, state->deal_digest};
        char *const into[] = {out.deal_commit, out.deal_nonce, out.deal_seed,
                              out.deal_digest};
        for (size_t i = 0; i < 4; ++i) {
            const void *nul = std::memchr(from[i], '\0', MXQ_DEAL_HEX_CAP);
            const size_t length =
                nul != nullptr
                    ? static_cast<size_t>(static_cast<const char *>(nul) -
                                          from[i])
                    : MXQ_DEAL_HEX_CAP;
            const std::string value(from[i], length);
            if (dealt != deal::is_hex32(value)) {
                deal_ok = false;
                break;
            }
            if (dealt) {
                std::memcpy(into[i], value.c_str(), value.size() + 1);
            }
        }
    }

    if (!vocabulary_ok || !deal_ok ||
        !copy_identifier(state->session_id, out.session_id,
                         MXQ_NEARBY_SESSION_ID_CAP) ||
        !copy_identifier(state->peer_id, out.peer_id, MXQ_NEARBY_PEER_ID_CAP)) {
        assert(false && "the wire session is not one the protocol carries");
        fill_error(err, MXQ_ERR_ARG_RANGE,
                   "the nearby wire session's identifiers, deal or vocabulary "
                   "are not ones this interface defines");
        return MXQ_ERR_ARG_RANGE;
    }
    return MXQ_OK;
}

/*
 * Commit one mutated move line and, only if that succeeded, adopt it.
 *
 * This ordering is the whole of docs/game-data.md's autosave rule: the store
 * decides whether the mutation happened. A failed commit returns with the
 * session — its moves, its revision, its written instant — exactly as it was,
 * so no accepted-but-unsaved change can exist even for the duration of a
 * return.
 *
 * A nearby game's wire session rides the same transaction, from whatever the
 * session carries at the moment of the commit: a ply carries the retraction
 * count it did not change, and a retraction carries the one it did.
 */
MxqStatus commit_line(MxqGame &game, std::vector<std::string> line,
                      MxqError *err) {
    const int64_t written_at = game.core->identity.now_ms();

    archive::Record record = record_of(game);
    record.moves = std::move(line);
    record.written_at_ms = written_at;

    const std::string content = archive::content_bytes(record);
    const std::string document = archive::document_bytes(record, content);

    store::NearbySession scratch;
    const MxqStatus rc = store::rewrite_active(
        *game.core->store, game.record_id, document, sha256_hex(content),
        static_cast<int64_t>(record.moves.size()), nearby_of(game, scratch),
        err);
    if (rc != MXQ_OK) {
        return rc;
    }

    game.moves = std::move(record.moves);
    game.written_at_ms = written_at;
    ++game.position_revision;
    return MXQ_OK;
}

/* ---------------------------------------------------------------------- */
/* Ending a game                                                           */
/* ---------------------------------------------------------------------- */

/* The committed outcome a live terminal state commits as. The two live states
 * that are not terminal have no committed outcome at all, which is what makes
 * this a question with a false answer rather than a mapping with a default. */
bool outcome_of(MxqGameState state, MxqOutcome &out) {
    switch (state) {
    case MXQ_GAME_RED_WINS:   out = MXQ_OUTCOME_RED_WINS;   return true;
    case MXQ_GAME_BLACK_WINS: out = MXQ_OUTCOME_BLACK_WINS; return true;
    case MXQ_GAME_DRAW:       out = MXQ_OUTCOME_DRAW;       return true;
    default: break;
    }
    return false;
}

/*
 * The one atomic ending, shared by all five archiving paths.
 *
 * The classification arrives already settled by the path that called in; what
 * happens here is the rest of the sentence mxq.h writes three times and
 * core-interface.md once — commit the outcome, insert the immutable History
 * record, clear the active-game reference, atomically — plus the adoption that
 * may only follow it.
 *
 * One reading of the clock serves the whole event: the game ended, it entered
 * History, and the document recording that change was written, all at the same
 * instant. Two readings would put three timestamps a second apart on one
 * commit and make the bytes depend on how many times the clock was asked.
 *
 * Adoption is strictly after the commit, exactly as an ordinary mutation's is:
 * a store-domain failure returns with the game still active, still unarchived,
 * and still holding the bytes it held, so the retry the accepted 无法保存对局
 * flow offers is a retry of the same call on the same game.
 */
MxqStatus end_game(MxqGame &game, MxqOutcome outcome, MxqEndReason reason,
                   uint64_t &out_record_id, MxqError *err) {
    out_record_id = 0;
    // Clamped to the creation instant: the schema refuses an ending before its
    // beginning, and a wall clock stepped backwards since creation would
    // otherwise make the ending fail identically on every retry until the
    // clock caught up — a retry the accepted flow offers must be able to work.
    const int64_t at = std::max(game.started_at_ms,
                                game.core->identity.now_ms());

    archive::Record record = record_of(game);
    record.completed = true;
    record.outcome = outcome;
    record.end_reason = reason;
    record.ended_at_ms = at;
    record.written_at_ms = at;

    const std::string content = archive::content_bytes(record);
    const std::string document = archive::document_bytes(record, content);

    store::Completion done;
    done.archive = document;
    done.content_sha256 = sha256_hex(content);
    done.move_count = static_cast<int64_t>(record.moves.size());
    done.outcome = archive::outcome_text(outcome);
    done.end_reason = archive::end_reason_text(reason);
    done.ended_at_ms = at;
    done.added_at_ms = at;

    const MxqStatus rc =
        store::commit_completion(*game.core->store, game.record_id, done, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    game.completed = true;
    game.outcome = outcome;
    game.end_reason = reason;
    game.ended_at_ms = at;
    game.written_at_ms = at;
    game.archived = true;
    /* The transaction deleted the wire session with the game it belonged to, so
     * the session stops carrying one too: a handle held across the moment a game
     * ends must not answer with a wire session the store no longer holds. */
    game.has_nearby = false;
    std::memset(&game.nearby, 0, sizeof(game.nearby));
    /* The revision is the staleness authority, and a game that has ended is
     * the strongest reason there is to reject a search that is still running
     * against it. */
    ++game.position_revision;
    out_record_id = game.record_id;
    return MXQ_OK;
}

/* ---------------------------------------------------------------------- */
/* Building a session from a stored row                                    */
/* ---------------------------------------------------------------------- */

/*
 * A decoded document as a session, without asking anything of it.
 *
 * Three callers build a session from bytes — resume, opening a History record,
 * and opening an archive file for preview — and they differ in what they check
 * first, not in what a session is. This is the part they share; the checks stay
 * with the caller that owns their meaning, because "the row this core wrote no
 * longer replays" and "the file you chose does not replay" are different
 * sentences with different statuses.
 */
std::unique_ptr<MxqGame> session_of(MxqCore *core,
                                    const archive::Stored &stored,
                                    uint64_t record_id, bool read_only) {
    auto game = std::unique_ptr<MxqGame>(new MxqGame());
    game->game_id = stored.game_id;
    game->config = stored.config;
    game->config.struct_size = static_cast<uint32_t>(sizeof(MxqGameConfig));
    game->started_at_ms = stored.started_at_ms;
    game->written_at_ms = stored.written_at_ms;
    game->moves = stored.moves;
    game->deal_commit = stored.deal_commit;
    game->deal_nonce = stored.deal_nonce;
    game->deal_seed = stored.deal_seed;
    game->completed = stored.completed;
    game->outcome = stored.outcome;
    game->end_reason = stored.end_reason;
    game->ended_at_ms = stored.ended_at_ms;
    game->record_id = record_id;
    game->read_only = read_only;
    game->core = core;
    return game;
}

/*
 * The path back from bytes to a session, shared by resume and by opening a
 * History record.
 *
 * Three things are asked of a row this core wrote, in order: that the bytes
 * still decode, that the content hash the row records is the hash of the
 * content they carry, and that the move line still replays. The first and the
 * third catch structural and rules damage; the middle one is a comparison
 * against a value written at the same instant as the blob, so a byte flipped
 * in either is caught by a hash rather than by whether some later stage
 * happens to notice. All three are store corruption where they fail: nothing
 * imported this row, and the answer is about the user's library rather than
 * about a file they chose. The import size bounds are deliberately not
 * applied — a long local game must always open.
 *
 * local_side arrives beside the bytes rather than out of them, because it is
 * the one part of a session's configuration the document does not carry: the
 * store's own column is its only source, and the schema's constraint is what
 * keeps it paired with the mode.
 */
MxqStatus session_from_row(MxqCore *core, uint64_t record_id,
                           const std::string &archive_bytes,
                           const std::string &content_sha256,
                           const std::string &local_side,
                           bool expect_completed, bool read_only,
                           std::unique_ptr<MxqGame> &out, MxqError *err) {
    out.reset();

    archive::Stored stored;
    MxqError decode_error;
    std::memset(&decode_error, 0, sizeof(decode_error));
    decode_error.struct_size = static_cast<uint32_t>(sizeof(decode_error));
    const MxqStatus decoded = archive::read_stored(
        reinterpret_cast<const uint8_t *>(archive_bytes.data()),
        archive_bytes.size(), stored, &decode_error);
    if (decoded != MXQ_OK) {
        fill_error_subsystem(err, MXQ_ERR_STORE_CORRUPT,
                             (std::string("the stored game does not decode: ") +
                              decode_error.detail)
                                 .c_str(),
                             decoded);
        return MXQ_ERR_STORE_CORRUPT;
    }
    if (stored.completed != expect_completed) {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   expect_completed
                       ? "a History record's archive records no end"
                       : "the active game's archive records an end, which only "
                         "a History record may");
        return MXQ_ERR_STORE_CORRUPT;
    }
    /* The start, against the same per-game policy an import applies. A row this
     * core wrote can only hold a start creation accepted, so a start that no
     * longer passes is damage to the library rather than an answer about a
     * position — which is why every rung of the policy lands on one status
     * here. */
    {
        setup::Violation violation;
        std::string why;
        if (setup::judge_start(stored.config.game,
                               notation::start_fen(stored.config), violation,
                               why) != setup::StartError::None) {
            fill_error(err, MXQ_ERR_STORE_CORRUPT,
                       ("the stored game does not start from a position its "
                        "game may begin from: " +
                        why)
                           .c_str());
            return MXQ_ERR_STORE_CORRUPT;
        }
    }
    /* And, where the row records the evidence of a deal, that the evidence is
     * this game's: the seed hashes to the commitment and the deal it derives is
     * the one the start spells. A row this core wrote can only hold a deal
     * creation accepted, so a deal that no longer verifies is damage to the
     * library — which is why this lands on the same status the start does
     * rather than on the archive's own. The fourth value is the wire session's
     * and is compared by the caller that has one. */
    if (!stored.deal_commit.empty()) {
        std::string why;
        if (!deal::verify(stored.deal_commit, stored.deal_nonce,
                          stored.deal_seed,
                          notation::start_fen(stored.config),
                          /*expected_digest=*/nullptr, why)) {
            fill_error(err, MXQ_ERR_STORE_CORRUPT,
                       ("the stored game's deal is not the one its start "
                        "spells: " +
                        why)
                           .c_str());
            return MXQ_ERR_STORE_CORRUPT;
        }
    }

    std::unique_ptr<MxqGame> game =
        session_of(core, stored, record_id, read_only);
    if (local_side == "red") {
        game->config.local_side = MXQ_COLOR_RED;
    } else if (local_side == "black") {
        game->config.local_side = MXQ_COLOR_BLACK;
    } else if (!local_side.empty()) {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   "the stored game's local side is not a side");
        return MXQ_ERR_STORE_CORRUPT;
    }

    /* The integrity compare. Re-encoding the decoded document reproduces the
     * canonical bytes this writer produced — that is the property the golden
     * corpus pins — so hashing them is hashing what the row should hold. */
    const std::string content = archive::content_bytes(record_of(*game));
    if (sha256_hex(content) != content_sha256) {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   "the stored game's content hash does not match its bytes");
        return MXQ_ERR_STORE_CORRUPT;
    }

    /* The rules tier, on the line as stored. */
    Replayed replayed;
    MxqError replay_error;
    std::memset(&replay_error, 0, sizeof(replay_error));
    replay_error.struct_size = static_cast<uint32_t>(sizeof(replay_error));
    if (replay_prefix(*game, game->moves.size(), false, replayed,
                      &replay_error) != MXQ_OK) {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   (std::string("the stored game does not replay: ") +
                    replay_error.detail)
                       .c_str());
        return MXQ_ERR_STORE_CORRUPT;
    }

    out = std::move(game);
    return MXQ_OK;
}

/*
 * Whether a live session is already attached to this row.
 *
 * Resuming the active game twice would produce two sessions over one row, each
 * committing over the other's work with no diagnosis at all. mxq.h already
 * answers "two owners of one thing" with MXQ_ERR_ARG_CONCURRENT_USE, and this
 * is that question asked of the row rather than of the session: it is a
 * frontend bug, it is detected rather than serialised, and nothing is changed
 * by the refusal.
 *
 * An archived session no longer owns its row — the row is a History record and
 * the library holds no active game — so it does not stand in the way of
 * anything; but neither does it make resume succeed, because there is nothing
 * active to resume.
 */
bool attached_to(const MxqCore *core, uint64_t record_id) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    for (const MxqGame *game : registry()) {
        if (game->core == core && !game->read_only && !game->archived &&
            game->record_id == record_id) {
            return true;
        }
    }
    return false;
}

} /* namespace */

MxqStatus require(const MxqGame *game, MxqError *err) {
    return require_impl(game, err);
}

MxqStatus require_mutable(const MxqGame *game, MxqError *err) {
    return require_mutable_impl(game, err);
}

MxqStatus require_no_result(const MxqGame *game, MxqError *err) {
    /* The result is the replayed line's own verdict, asked of the same facade
     * every other legality answer comes from; nothing about it is stored. */
    Replayed committed;
    const MxqStatus rc =
        replay_prefix(*game, game->moves.size(), false, committed, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (terminal(committed.adj.state)) {
        fill_error(err, MXQ_ERR_STATE_GAME_OVER,
                   "the game already has a result");
        return MXQ_ERR_STATE_GAME_OVER;
    }
    return MXQ_OK;
}

MxqStatus concurrent_use(MxqError *err) {
    fill_error(err, MXQ_ERR_ARG_CONCURRENT_USE,
               "another thread is inside this session");
    return MXQ_ERR_ARG_CONCURRENT_USE;
}

void invalidate_all(const MxqCore *core) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    for (MxqGame *game : registry()) {
        if (game->core == core) {
            /* Tombstoned, not freed: the owner still holds this pointer and
             * still calls mxq_game_release on it. */
            game->core = nullptr;
            game->moves.clear();
            game->moves.shrink_to_fit();
        }
    }
}

bool current_revision_of(const MxqCore *core, uint64_t instance,
                         const char *game_id, uint64_t &out_revision) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    /* Exactly the session the search was started on, or nothing. A lookup
     * that fell back to any session carrying the game_id was the defect
     * behind a committed wrong move: a release-and-resume registers a second
     * session under the same id whose per-session revision restarts, so the
     * fallback compared a search against a counter it was never started
     * under, and equal values meant different positions. instance_id is never
     * reused, so absence here is the fact the stale rung wants: the origin
     * session is gone, and the result cannot be shown fresh against it. */
    for (const MxqGame *game : registry()) {
        if (game->instance_id == instance && game->core == core &&
            game->game_id == game_id) {
            out_revision =
                game->position_revision.load(std::memory_order_acquire);
            return true;
        }
    }
    return false;
}

archive::Record record_of(const MxqGame &game) {
    archive::Record record;
    record.game_id = game.game_id;
    record.config = game.config;
    record.moves = game.moves;
    record.deal_commit = game.deal_commit;
    record.deal_nonce = game.deal_nonce;
    record.deal_seed = game.deal_seed;
    record.started_at_ms = game.started_at_ms;
    record.written_at_ms = game.written_at_ms;
    /* An active game's stored content records no end; a game one of the four
     * archiving paths has ended carries the trio that path committed, so
     * encoding an archived session reproduces the History record's own
     * bytes. */
    record.completed = game.completed;
    record.outcome = game.outcome;
    record.end_reason = game.end_reason;
    record.ended_at_ms = game.ended_at_ms;
    return record;
}

MxqStatus status_of_line(const MxqGameConfig &config,
                         const std::vector<std::string> &moves,
                         MxqGameStatus *out, MxqError *err) {
    /*
     * The start, before the line is replayed from it.
     *
     * This is the one function that replays a line from a configuration it did
     * not create — the summary surface reads a row and asks it — so it is where
     * the policy is applied for those callers. It is not the same check as
     * creation's, and it cannot be: what reaches here has already been stored,
     * so a start that no longer passes is a damaged library rather than an
     * answer about a position, and every rung lands on MXQ_ERR_STORE_CORRUPT.
     *
     * It is asked at all because the engine is not a validator: a damaged start
     * offering the capture of a general trips an assertion inside the replay,
     * and the Play home reads this at launch, so the refusal has to arrive
     * before the position reaches the engine rather than instead of an answer.
     */
    {
        setup::Violation violation;
        std::string why;
        if (setup::judge_start(config.game, notation::start_fen(config),
                               violation, why) != setup::StartError::None) {
            fill_error(err, MXQ_ERR_STORE_CORRUPT,
                       ("the stored game does not start from a position its "
                        "game may begin from: " +
                        why)
                           .c_str());
            return MXQ_ERR_STORE_CORRUPT;
        }
    }

    /* A session is its configuration plus its move line plus replay, and this
     * borrows exactly that much of one. It is never registered and never
     * handed out, so it is not a session in the sense mxq.h uses the word: no
     * handle exists, nothing owns it, and it cannot be mutated. */
    MxqGame line;
    line.config = config;
    line.moves = moves;

    Replayed replayed;
    const MxqStatus rc = replay_prefix(line, line.moves.size(), false, replayed,
                                       err);
    if (rc != MXQ_OK) {
        return rc;
    }
    fill_status(line, replayed, out);
    return MXQ_OK;
}

MxqStatus archive_and_clear(MxqCore *core, MxqGame *active,
                            uint64_t *out_record_id, MxqError *err) {
    if (out_record_id != nullptr) {
        *out_record_id = 0;
    }
    MxqStatus rc = require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (active == nullptr) {
        /*
         * The one required pointer this function takes is the active game
         * itself, so its absence is a state rather than a programming error:
         * a frontend reaching the save-before-mode path with no game to save
         * is asking a question the library can answer.
         */
        fill_error(err, MXQ_ERR_STATE_ACTIVE_GAME_MISSING,
                   "there is no active game to archive");
        return MXQ_ERR_STATE_ACTIVE_GAME_MISSING;
    }
    rc = require(active, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (active->core != core) {
        assert(false && "the session belongs to another core");
        fill_error(err, MXQ_ERR_ARG_INVALID_HANDLE,
                   "the session was not issued by this core");
        return MXQ_ERR_ARG_INVALID_HANDLE;
    }
    Owner owner(active);
    if (!owner.held()) {
        return concurrent_use(err);
    }
    rc = require_mutable(active, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    Replayed replayed;
    rc = replay_prefix(*active, active->moves.size(), false, replayed, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /*
     * The classification docs/game-data.md accepts for save-before-mode, and
     * the only place ended-early may be written.
     *
     * An unconfirmed natural terminal state keeps its actual result and its
     * exact termination reason — recording a checkmate as "ended early" would
     * lose a result the game really has. Everything else is ended early with
     * no competitive result, the unclaimed claimable repetition included: it
     * is still an ongoing game, and a draw it records would be a draw nobody
     * claimed.
     */
    MxqOutcome outcome = MXQ_OUTCOME_NONE;
    MxqEndReason reason = MXQ_END_REASON_ENDED_EARLY;
    if (outcome_of(replayed.adj.state, outcome)) {
        reason = replayed.adj.reason;
    }

    uint64_t record_id = 0;
    rc = end_game(*active, outcome, reason, record_id, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_record_id != nullptr) {
        *out_record_id = record_id;
    }
    return MXQ_OK;
}

MxqStatus history_open(MxqCore *core, uint64_t record_id, MxqGame **out_replay,
                       MxqError *err) {
    MxqStatus rc = require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_replay == nullptr) {
        assert(false && "required out pointer was null");
        fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_replay = nullptr;

    store::Summary summary;
    std::string archive_bytes;
    rc = store::history_record(*core->store, record_id, summary, &archive_bytes,
                               err);
    if (rc != MXQ_OK) {
        return rc;
    }

    std::unique_ptr<MxqGame> game;
    rc = session_from_row(core, record_id, archive_bytes, summary.content_sha256,
                          summary.local_side, /*expect_completed=*/true,
                          /*read_only=*/true, game, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    MxqGame *raw = game.release();
    register_session(raw);
    *out_replay = raw;
    return MXQ_OK;
}

} /* namespace session */
} /* namespace mxq */

/* ------------------------------------------------------------------------- */
/* The C surface                                                             */
/* ------------------------------------------------------------------------- */

extern "C" {

/*
 * Creation, shared by the two doors into it.
 *
 * nearby is the wire session a nearby game is created over, and null for a game
 * created without one — every local game, and a nearby game a test or a fixture
 * builds with no protocol behind it. Where it is present it is written in the
 * same transaction as the game row.
 */
static MxqStatus create_game(MxqCore *core, const MxqGameConfig *config,
                             const MxqNearbySession *nearby,
                             MxqGame **out_game, MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    rc = mxq::check_in(config, config != nullptr ? config->struct_size : 0u,
                       static_cast<uint32_t>(sizeof(MxqGameConfig)),
                       static_cast<uint32_t>(sizeof(MxqGameConfig)), err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_game == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_game = nullptr;

    /*
     * The configuration arrives resolved: a Random first-mover choice is
     * resolved into human_side before creation, because only successful
     * creation commits a resolved side (docs/game-data.md) and the core never
     * reads a preference or invents a value the frontend owns. What is checked
     * here is the shape the archive and the store both require — the four
     * configuration members exist exactly for human-versus-AI games — and a
     * caller that gets it wrong is a programming error, not a user outcome.
     */
    /* The game axis is a closed vocabulary of its own and is checked as one:
     * every game has a game, in both modes, so this is not part of the
     * mode-to-configuration shape below. */
    rc = mxq::require_game(config->game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    /*
     * A session is store-attached and every stored row carries the document its
     * game encodes to, so a game the archive format does not spell cannot have
     * one. It is MXQ_ERR_ARG_RANGE and it does not assert, which is mxq.h's own
     * rule for it: it reports two parts of this core at different stages of one
     * widening rather than a caller outside a vocabulary it owns. The rules
     * facade answers for such a game in full; only persistence refuses it.
     */
    if (mxq::archive::rules_id_text(config->game) == nullptr) {
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "the archive format this build writes has no spelling "
                        "for this game, so no session can be stored for it");
        return MXQ_ERR_ARG_RANGE;
    }
    /*
     * The one game that plays fewer than three modes. Jieqi has no AI at all —
     * no search, no network, nothing to prepare — so a game of it against a
     * machine is a configuration of neither accepted shape, refused here beside
     * the shape checks below and for the same reason they are.
     */
    if (config->game == MXQ_GAME_KIND_JIEQI &&
        config->mode == MXQ_PLAY_MODE_HUMAN_VS_AI) {
        assert(false && "this game has no AI to play against");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "this game has no AI, so it is not played against one");
        return MXQ_ERR_ARG_RANGE;
    }
    const bool human_vs_ai = config->mode == MXQ_PLAY_MODE_HUMAN_VS_AI;
    const bool two_devices = config->mode == MXQ_PLAY_MODE_NEARBY;
    bool shape_ok =
        human_vs_ai || two_devices || config->mode == MXQ_PLAY_MODE_FREE_PLAY;
    if (human_vs_ai) {
        shape_ok = shape_ok &&
                   (config->human_side == MXQ_COLOR_RED ||
                    config->human_side == MXQ_COLOR_BLACK) &&
                   (config->ai_level == MXQ_AI_LEVEL_FAST ||
                    config->ai_level == MXQ_AI_LEVEL_STANDARD ||
                    config->ai_level == MXQ_AI_LEVEL_DEEP) &&
                   (config->first_mover_choice == MXQ_FIRST_MOVER_HUMAN_FIRST ||
                    config->first_mover_choice == MXQ_FIRST_MOVER_AI_FIRST ||
                    config->first_mover_choice == MXQ_FIRST_MOVER_RANDOM) &&
                   config->ai_movetime_ms > 0;
    } else {
        /* Free Play and nearby play omit all four rather than writing the NONE
         * constants into the archive, so they must not carry values to omit. */
        shape_ok = shape_ok && config->human_side == MXQ_COLOR_NONE &&
                   config->ai_level == MXQ_AI_LEVEL_NONE &&
                   config->first_mover_choice == MXQ_FIRST_MOVER_NONE &&
                   config->ai_movetime_ms == 0;
    }
    /* The mirror rule, and the only member that is store metadata rather than
     * archive content: a nearby game is played from one of the two sides of
     * this device, and a local game is played from neither. */
    shape_ok = shape_ok &&
               (two_devices ? (config->local_side == MXQ_COLOR_RED ||
                               config->local_side == MXQ_COLOR_BLACK)
                            : config->local_side == MXQ_COLOR_NONE);
    if (!shape_ok) {
        assert(false && "the game configuration is not one this ruleset defines");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "the configuration's mode and its human-versus-AI and "
                        "local-side members do not agree");
        return MXQ_ERR_ARG_RANGE;
    }

    /* The start this configuration names, or nothing where it names the game's
     * own. A frozen start spelled out is the game's own, so everything below
     * treats it exactly as an absent member. */
    const std::string named = mxq::session::named_start(*config);

    /*
     * A dealt game has no frozen start, so its configuration always names one:
     * there is a start for every deal and no one position for an empty member
     * to have meant. An empty member is therefore a configuration of a shape
     * this game does not have — a programming error, exactly as the mode
     * refusal above is, and not a position the frontend can show a person.
     */
    const bool dealt_game = config->game == MXQ_GAME_KIND_JIEQI;
    if (dealt_game && named.empty()) {
        assert(false && "a dealt game's configuration names its deal");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "this game begins from a dealt start, so its "
                        "configuration names one");
        return MXQ_ERR_ARG_RANGE;
    }

    /*
     * A composed start is Free Play's, and only Free Play's.
     *
     * The other two modes each have a fact a composed position would make
     * meaningless. Nearby play's is the wire protocol, which carries no start.
     * Human-versus-AI's is first_mover_choice, which the archive records and
     * cannot reconstruct: "human first" is a statement about a game whose first
     * mover is the frozen start's, and a position naming its own side to move
     * leaves it saying nothing. A vs-AI-from-a-scene feature is a contract
     * change rather than something to inherit muddled here.
     *
     * A dealt start is not a composed one and the rule does not reach it:
     * nobody put it together and neither player chose it. Free Play deals its
     * own and a nearby session's two ends derive one identical deal from the
     * handshake, so the two modes this game plays both name a start and neither
     * is composing a position.
     */
    if (!named.empty() && !dealt_game &&
        config->mode != MXQ_PLAY_MODE_FREE_PLAY) {
        assert(false && "a composed start belongs to a Free Play game");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "a game begun from a composed position is a Free Play "
                        "game; the other modes begin from the frozen start");
        return MXQ_ERR_ARG_RANGE;
    }

    /*
     * And a dealt game played over the wire carries the evidence its deal was
     * dealt: the commitment, the nonce and the seed are content of the document
     * this creation writes, so a nearby game of it is created through
     * mxq_game_create_nearby — the entry that takes the wire session those
     * values arrive in — and not through the plain one, which has nowhere to
     * take them from.
     */
    if (dealt_game && config->mode == MXQ_PLAY_MODE_NEARBY &&
        nearby == nullptr) {
        assert(false && "a nearby dealt game is created over its wire session");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "a nearby game of this game records the deal its "
                        "handshake produced, so it is created over the wire "
                        "session that carries it");
        return MXQ_ERR_ARG_RANGE;
    }

    /*
     * The start, and the three questions mxq.h asks of one.
     *
     * They are three because they are three different things to be wrong about,
     * and a caller composing a position asks them in this order too: how the
     * position is spelled, whether the game may be set up in it, and whether it
     * is a game to play at all. None of them is a programming error — a
     * composed position arrives from a person, so every refusal here is an
     * answer the frontend shows rather than a caller it catches.
     *
     * A start the game's own skips the first two: the frozen start passes each
     * of them by construction, and the session that begins from it is the
     * session every mode has always had.
     */
    if (!named.empty()) {
        mxq::setup::Violation violation;
        std::string why;
        switch (mxq::setup::judge_start(config->game, named.c_str(), violation,
                                        why)) {
        case mxq::setup::StartError::None:
            break;
        case mxq::setup::StartError::Structural:
        case mxq::setup::StartError::NotInitialised:
            /* The pairing mxq_rules_validate_setup makes of the same two
             * conditions, for the same reason: an engine that never came up
             * cannot say what board a FEN is of, so the honest answer is the
             * one about the FEN. */
            mxq::fill_error(err, MXQ_ERR_RULES_INVALID_FEN, why.c_str());
            return MXQ_ERR_RULES_INVALID_FEN;
        case mxq::setup::StartError::Illegal:
            mxq::fill_error(err, MXQ_ERR_RULES_ILLEGAL_POSITION, why.c_str());
            return MXQ_ERR_RULES_ILLEGAL_POSITION;
        }
    }

    auto game = std::unique_ptr<MxqGame>(new MxqGame());
    game->game_id = core->identity.next_game_id();
    /* One reading of the clock for one committed event: it is both the game's
     * start and the instant the document it writes records. */
    game->started_at_ms = core->identity.now_ms();
    game->written_at_ms = game->started_at_ms;
    game->config = *config;
    game->config.struct_size = static_cast<uint32_t>(sizeof(MxqGameConfig));
    /* The member is kept canonical, and written rather than echoed: a start
     * that is the frozen one is the empty string, so a game answers one way
     * about where it began whether it was just created or resumed from a row
     * whose document spells every start out — and nothing the caller left past
     * its terminator comes back out of mxq_game_config. */
    std::memset(game->config.start_fen, 0, sizeof(game->config.start_fen));
    if (!named.empty()) {
        mxq::copy_bounded(game->config.start_fen,
                          sizeof(game->config.start_fen), named.c_str());
    }
    game->core = core;
    if (nearby != nullptr) {
        game->has_nearby = true;
        game->nearby = *nearby;
        /* Three of the wire session's four deal values are this game's own
         * evidence rather than this device's, so they are copied onto the
         * session, where the document is written from. The digest is not among
         * them: it is derivable from the deal, and a record carries what cannot
         * be recomputed from what it already holds. */
        if (dealt_game) {
            game->deal_commit = nearby->deal_commit;
            game->deal_nonce = nearby->deal_nonce;
            game->deal_seed = nearby->deal_seed;
        }
    }

    /*
     * The third question: startability, which is creation's and not the
     * predicate's. A position that already has a result of its own is no game
     * to play, and it is asked by evaluating the start with no moves — which is
     * what mxq_rules_evaluate does for a caller composing one.
     *
     * Every start reaches it, the frozen ones included, because the answer for
     * those is free: a game's own opening position is ongoing, so the rung
     * costs one replay of a position with no plies and refuses nothing that was
     * ever created before.
     */
    {
        mxq::session::Replayed at_start;
        rc = mxq::session::replay_prefix(*game, 0, false, at_start, err);
        if (rc != MXQ_OK) {
            return rc;
        }
        if (mxq::session::terminal(at_start.adj.state)) {
            mxq::fill_error(err, MXQ_ERR_STATE_GAME_OVER,
                            "the position already has a result of its own, so "
                            "it is not a game to begin");
            return MXQ_ERR_STATE_GAME_OVER;
        }
    }

    const mxq::archive::Record record = mxq::session::record_of(*game);
    const std::string content = mxq::archive::content_bytes(record);
    const std::string document = mxq::archive::document_bytes(record, content);

    uint64_t record_id = 0;
    mxq::store::NearbySession scratch;
    rc = mxq::store::create_active(
        *core->store, mxq::session::row_of(record, document, content),
        mxq::session::nearby_of(*game, scratch), record_id, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    game->record_id = record_id;

    MxqGame *raw = game.release();
    mxq::session::register_session(raw);
    *out_game = raw;
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_create(MxqCore *core, const MxqGameConfig *config,
                                   MxqGame **out_game, MxqError *err) {
    return create_game(core, config, nullptr, out_game, err);
}

MxqStatus MXQ_CALL mxq_game_create_nearby(MxqCore *core,
                                          const MxqGameConfig *config,
                                          const MxqNearbySession *session,
                                          MxqGame **out_game, MxqError *err) {
    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    /*
     * Three things about the configuration this entry judges before create_game
     * reads it, and all of them guard on the same condition: a struct at least
     * the size this build declares, which is what check_in inside create_game
     * will ask of it anyway. Equality would let a caller that passed a larger
     * struct skip them and meet the store's trigger instead of this diagnostic.
     * The game axis is part of the same condition because both reading a start
     * and reading a deal need one: a game outside the vocabulary is refused by
     * create_game, which owns that refusal, rather than judged here.
     */
    const bool config_readable =
        config != nullptr && config->struct_size >= sizeof(MxqGameConfig) &&
        mxq::notation::known_game(config->game);
    if (!config_readable) {
        /* Nothing here can be judged without one, so the configuration's own
         * refusal is the whole answer and create_game is where it lives. */
        return create_game(core, config, nullptr, out_game, err);
    }

    /* The wire session, read under the game it belongs to — which is what says
     * whether it carries a deal. */
    MxqNearbySession state;
    rc = mxq::session::read_nearby_state(config->game, session, state, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    /* The shape of a session at birth. A game with no plies has retracted
     * nothing, claimed nothing and declared nothing, so any other value here is
     * a caller describing a session it cannot have. */
    if (state.undos != 0 || state.keep != 0 || state.claimed != 0 ||
        state.sent_end != MXQ_NEARBY_TERMINAL_NONE) {
        assert(false && "a nearby game is created over a session at its birth");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "a nearby game is created over a wire session that has "
                        "retracted, claimed and declared nothing");
        return MXQ_ERR_ARG_RANGE;
    }

    /* The mode is not a preference here: this call writes a nearby_session row,
     * and the schema's own trigger refuses one over any other kind of game.
     * Saying so before the transaction makes it a programming error rather than
     * a store failure. */
    if (config->mode != MXQ_PLAY_MODE_NEARBY) {
        assert(false && "a wire session belongs to a nearby game");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "a wire session belongs to a nearby game");
        return MXQ_ERR_ARG_RANGE;
    }
    /* And the start, refused in the same voice and on the same rung as the
     * mode. The protocol two devices play over carries no start position, so a
     * composed one is not a game they could both be in; a frontend that offered
     * one here would have built a game only this device knows the shape of.
     *
     * What is refused is a composed start and not a spelled-out one: the frozen
     * start written in full is the game's own start everywhere else in this
     * interface, and a caller that spells it is describing the game nearby play
     * already plays.
     *
     * The dealt game is the exception, and it is not composure that makes it
     * one: it has no frozen start for a spelled-out one to fold into, and the
     * start it names is the deal both devices derived from the handshake rather
     * than a position either of them chose. Its start is judged by the three
     * questions in create_game like every other named one. */
    if (config->game != MXQ_GAME_KIND_JIEQI &&
        !mxq::session::named_start(*config).empty()) {
        assert(false && "a nearby game begins from its game's frozen start");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "a nearby game begins from its game's frozen start: "
                        "the wire protocol carries no other");
        return MXQ_ERR_ARG_RANGE;
    }
    return create_game(core, config, &state, out_game, err);
}

MxqStatus MXQ_CALL mxq_game_resume_active(MxqCore *core, MxqGame **out_game,
                                          uint8_t *out_exists, MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_game == nullptr || out_exists == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_game = nullptr;
    *out_exists = 0;

    bool exists = false;
    uint64_t record_id = 0;
    std::string archive;
    std::string content_sha256;
    std::string local_side;
    const MxqStatus load = mxq::store::load_active(
        *core->store, exists, record_id, archive, content_sha256, local_side,
        err);
    if (load != MXQ_OK) {
        return load;
    }
    if (!exists) {
        /* Absence is success. A frontend asking whether there is a game to
         * resume is asking a question, not making a claim. */
        return MXQ_OK;
    }

    /*
     * One session per active row. A second resume while the first is still
     * live would leave two sessions committing over one another with no
     * diagnosis at all, so it is detected and refused rather than served.
     */
    if (mxq::session::attached_to(core, record_id)) {
        mxq::fill_error(err, MXQ_ERR_ARG_CONCURRENT_USE,
                        "a session is already attached to the active game");
        return MXQ_ERR_ARG_CONCURRENT_USE;
    }

    /*
     * The stored bytes go back through the codec — structurally, then against
     * the hash the row records, then through the same replay the archive
     * validator uses — rather than being trusted because this core wrote them.
     * See session_from_row; what is deliberately not applied are the import
     * size bounds, because a long local game must always resume.
     */
    std::unique_ptr<MxqGame> game;
    const MxqStatus built = mxq::session::session_from_row(
        core, record_id, archive, content_sha256, local_side,
        /*expect_completed=*/false, /*read_only=*/false, game, err);
    if (built != MXQ_OK) {
        return built;
    }

    /* The wire session, where the row has one. It is what a relaunched
     * application rebuilds its protocol session from, and it arrives beside the
     * bytes rather than out of them for the reason local_side does: the archive
     * carries nothing device-local. */
    {
        bool has_nearby = false;
        mxq::store::NearbySession row;
        const MxqStatus loaded = mxq::store::load_nearby_session(
            *core->store, record_id, has_nearby, row, err);
        if (loaded != MXQ_OK) {
            return loaded;
        }
        if (has_nearby) {
            const MxqStatus adopted =
                mxq::session::adopt_nearby_row(*game, row, err);
            if (adopted != MXQ_OK) {
                return adopted;
            }
            /*
             * The re-verification the protocol requires of a dealt session
             * before it uses its deal, and it is against everything the deal
             * comes from rather than against one value: the persisted seed
             * hashes to the persisted commitment, and the deal that seed and
             * nonce derive carries the persisted digest — a nonce that has
             * rotted passes the first check and fails the second, which is why
             * the digest is the one the wire compares. The deal against the
             * start it spells has already been asked of the document.
             *
             * Beside them, the row and the document must agree on the three
             * values they both hold: they were written in one transaction, so a
             * disagreement is damage rather than a state this build produced.
             */
            if (!game->deal_commit.empty()) {
                const std::string digest = game->nearby.deal_digest;
                std::string why;
                if (game->deal_commit != game->nearby.deal_commit ||
                    game->deal_nonce != game->nearby.deal_nonce ||
                    game->deal_seed != game->nearby.deal_seed) {
                    mxq::fill_error(err, MXQ_ERR_STORE_CORRUPT,
                                    "the wire session's deal is not the deal "
                                    "the stored game records");
                    return MXQ_ERR_STORE_CORRUPT;
                }
                if (!mxq::deal::verify(game->deal_commit, game->deal_nonce,
                                       game->deal_seed,
                                       mxq::notation::start_fen(game->config),
                                       &digest, why)) {
                    mxq::fill_error(
                        err, MXQ_ERR_STORE_CORRUPT,
                        ("the stored wire session's deal no longer verifies: " +
                         why)
                            .c_str());
                    return MXQ_ERR_STORE_CORRUPT;
                }
            }
        }
    }

    MxqGame *raw = game.release();
    mxq::session::register_session(raw);
    *out_game = raw;
    *out_exists = 1;
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_open_archive(MxqCore *core, const uint8_t *bytes,
                                         size_t len, MxqGame **out_game,
                                         MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_game == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_game = nullptr;
    if (bytes == nullptr) {
        assert(false && "required bytes pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "bytes was null");
        return MXQ_ERR_ARG_NULL;
    }

    /*
     * The importer's own validation, whole: a preview that shows a replayable
     * board must replay, and it must accept exactly the files an import would.
     * A preview that displayed a game import then refused would be the worst
     * of both answers.
     *
     * The rejections are therefore the archive-domain ones a file gets, not
     * the store-domain ones a row gets: nothing about the user's library is
     * being reported here.
     */
    mxq::archive::Stored stored;
    const MxqStatus read = mxq::archive::read_imported(bytes, len, stored, err);
    if (read != MXQ_OK) {
        return read;
    }

    /* Detached: no store row, so no record id, and read-only for good. The
     * move line was replayed by the validation above, so there is nothing left
     * to ask before the handle exists. */
    std::unique_ptr<MxqGame> game =
        mxq::session::session_of(core, stored, /*record_id=*/0,
                                 /*read_only=*/true);
    MxqGame *raw = game.release();
    mxq::session::register_session(raw);
    *out_game = raw;
    return MXQ_OK;
}

void MXQ_CALL mxq_game_release(MxqGame *game) {
    if (game == nullptr) {
        return;
    }
    /* Releasing a handle the registry does not know would be a double release
     * or a foreign pointer, and there is nothing safe to do with it: the
     * function returns void, so the assertion is the only report there is. */
    if (!mxq::session::known(game)) {
        assert(false && "released a session handle that is not live");
        return;
    }
    mxq::session::forget(game);
    delete game;
}

MxqStatus MXQ_CALL mxq_game_id(const MxqGame *game, char *out, size_t cap,
                               size_t *out_len, MxqError *err) {
    const MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    return mxq::write_string(game->game_id.c_str(), out, cap, out_len, err);
}

MxqStatus MXQ_CALL mxq_game_position(const MxqGame *game, MxqPosition *out,
                                     MxqError *err) {
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqPosition)),
                        static_cast<uint32_t>(sizeof(MxqPosition)), err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::session::Replayed replayed;
    rc = mxq::session::replay_prefix(*game, game->moves.size(), false, replayed,
                                     err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::fill_position(*game, replayed, out);
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_status(const MxqGame *game, MxqGameStatus *out,
                                   MxqError *err) {
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqGameStatus)),
                        static_cast<uint32_t>(sizeof(MxqGameStatus)), err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::session::Replayed replayed;
    rc = mxq::session::replay_prefix(*game, game->moves.size(), false, replayed,
                                     err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::fill_status(*game, replayed, out);
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_config(const MxqGame *game, MxqGameConfig *out,
                                   MxqError *err) {
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqGameConfig)),
                        static_cast<uint32_t>(sizeof(MxqGameConfig)), err);
    if (rc != MXQ_OK) {
        return rc;
    }
    const uint32_t writable = out->struct_size;
    MxqGameConfig config = game->config;
    config.struct_size = writable;
    std::memcpy(out, &config, writable);
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_legal_moves(const MxqGame *game, MxqMove *out,
                                        size_t cap, size_t *out_count,
                                        MxqError *err) {
    if (out_count == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "out_count was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_count = 0;

    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }

    mxq::session::Replayed replayed;
    rc = mxq::session::replay_prefix(*game, game->moves.size(), true, replayed,
                                     err);
    if (rc != MXQ_OK) {
        return rc;
    }
    return mxq::session::write_moves(replayed.legal, out, cap, out_count,
                                     "the legal-move buffer is too small", err);
}

MxqStatus MXQ_CALL mxq_game_legal_moves_from(const MxqGame *game,
                                             const char *from_square,
                                             MxqMove *out, size_t cap,
                                             size_t *out_count, MxqError *err) {
    if (out_count == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "out_count was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_count = 0;

    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (!mxq::notation::well_formed_square(game->config.game, from_square)) {
        assert(false && "from_square is not a square of this board");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "from_square is not a square of this game's board");
        return MXQ_ERR_ARG_RANGE;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }

    mxq::session::Replayed replayed;
    rc = mxq::session::replay_prefix(*game, game->moves.size(), true, replayed,
                                     err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /* Asked through the notation authority rather than by comparing a fixed
     * two characters: on a board with a tenth rank "a1" is a prefix of "a10",
     * and a prefix comparison would answer for the wrong square. */
    std::vector<std::string> from_here;
    for (const std::string &move : replayed.legal) {
        if (mxq::notation::move_begins_at(game->config.game, move,
                                          from_square)) {
            from_here.push_back(move);
        }
    }
    /* A well-formed square with no legal move is a count of zero and MXQ_OK:
     * an empty square is a question with an answer, not a mistake. */
    return mxq::session::write_moves(from_here, out, cap, out_count,
                                     "the legal-move buffer is too small", err);
}

MxqStatus MXQ_CALL mxq_game_move_history(const MxqGame *game, MxqMove *out,
                                         size_t cap, size_t *out_count,
                                         MxqError *err) {
    if (out_count == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "out_count was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_count = 0;

    const MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    return mxq::session::write_moves(game->moves, out, cap, out_count,
                                     "the move-history buffer is too small",
                                     err);
}

MxqStatus MXQ_CALL mxq_game_position_at(const MxqGame *game, uint32_t ply,
                                        MxqPosition *out, MxqError *err) {
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqPosition)),
                        static_cast<uint32_t>(sizeof(MxqPosition)), err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (ply > game->moves.size()) {
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "ply is beyond the retained line");
        return MXQ_ERR_ARG_RANGE;
    }

    mxq::session::Replayed replayed;
    rc = mxq::session::replay_prefix(*game, ply, false, replayed, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::fill_position(*game, replayed, out);
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_apply_move(MxqGame *game, const char *move,
                                       MxqPosition *out_after,
                                       MxqGameStatus *out_status,
                                       MxqError *err) {
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(game);
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::session::require_mutable(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_after != nullptr) {
        rc = mxq::begin_out(out_after, out_after->struct_size,
                            static_cast<uint32_t>(sizeof(MxqPosition)),
                            static_cast<uint32_t>(sizeof(MxqPosition)), err);
        if (rc != MXQ_OK) {
            return rc;
        }
    }
    if (out_status != nullptr) {
        rc = mxq::begin_out(out_status, out_status->struct_size,
                            static_cast<uint32_t>(sizeof(MxqGameStatus)),
                            static_cast<uint32_t>(sizeof(MxqGameStatus)), err);
        if (rc != MXQ_OK) {
            return rc;
        }
    }
    if (move == nullptr) {
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "move was null");
        return MXQ_ERR_ARG_NULL;
    }
    /* Malformed and illegal are always distinguished: one is a caller's
     * mistake and the other is an ordinary answer to a legal question. */
    if (!mxq::notation::well_formed_move(game->config.game, move)) {
        mxq::fill_error(err, MXQ_ERR_RULES_MALFORMED_MOVE,
                        "the move is not two squares of this game's board in "
                        "the canonical <from><to> notation");
        return MXQ_ERR_RULES_MALFORMED_MOVE;
    }

    /* A game with a result of its own accepts no further move. A claimable
     * repetition is not such a result: play continues unless the claim is
     * made. */
    rc = mxq::session::require_no_result(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    std::vector<std::string> line = game->moves;
    line.push_back(move);

    std::vector<const char *> texts;
    texts.reserve(line.size());
    for (const std::string &text : line) {
        texts.push_back(text.c_str());
    }

    std::string fen;
    std::string detail;
    bool in_check = false;
    uint32_t ply = 0;
    mxq::rules::Adjudication adj{};
    size_t first_illegal = 0;
    switch (mxq::rules::replay(game->config.game,
                               mxq::notation::start_fen(game->config),
                               texts.data(), texts.size(), fen, in_check, ply,
                               adj, nullptr, first_illegal, detail)) {
    case mxq::rules::ReplayError::None:
        break;
    case mxq::rules::ReplayError::IllegalMove:
        if (first_illegal + 1 != line.size()) {
            /* An earlier ply stopped replaying: the retained line was legal
             * when it was committed, so this is not the caller's move being
             * refused. */
            mxq::fill_error(err, MXQ_ERR_INTERNAL_INVARIANT,
                            ("the retained line no longer replays: " + detail)
                                .c_str());
            return MXQ_ERR_INTERNAL_INVARIANT;
        }
        mxq::fill_error(err, MXQ_ERR_RULES_ILLEGAL_MOVE,
                        "the move is not legal in this position");
        return MXQ_ERR_RULES_ILLEGAL_MOVE;
    case mxq::rules::ReplayError::StartFenInvalid:
    case mxq::rules::ReplayError::NotInitialised:
    case mxq::rules::ReplayError::Faulted:
        mxq::fill_error(err, MXQ_ERR_INTERNAL_INVARIANT, detail.c_str());
        return MXQ_ERR_INTERNAL_INVARIANT;
    }

    /* The commit is the mutation. Until it returns, nothing has happened. */
    rc = mxq::session::commit_line(*game, std::move(line), err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::session::Replayed after;
    after.fen = fen;
    after.in_check = in_check;
    after.ply = ply;
    after.adj = adj;
    if (out_after != nullptr) {
        mxq::session::fill_position(*game, after, out_after);
    }
    if (out_status != nullptr) {
        mxq::session::fill_status(*game, after, out_status);
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_undo(MxqGame *game, uint32_t *out_plies_removed,
                                 MxqError *err) {
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(game);
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::session::require_mutable(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_plies_removed != nullptr) {
        *out_plies_removed = 0;
    }

    const uint32_t plies = mxq::session::undo_plies_for(*game);
    if (plies == 0) {
        mxq::fill_error(err, MXQ_ERR_STATE_UNDO_UNAVAILABLE,
                        "there is nothing to undo");
        return MXQ_ERR_STATE_UNDO_UNAVAILABLE;
    }

    std::vector<std::string> line = game->moves;
    line.resize(line.size() - plies);

    const MxqStatus committed =
        mxq::session::commit_line(*game, std::move(line), err);
    if (committed != MXQ_OK) {
        return committed;
    }
    if (out_plies_removed != nullptr) {
        *out_plies_removed = plies;
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_retract_nearby(MxqGame *game, uint32_t keep,
                                           const MxqNearbySession *session,
                                           MxqError *err) {
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(game);
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::session::require_mutable(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    MxqNearbySession state;
    rc = mxq::session::read_nearby_state(game->config.game, session, state, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /* The mirror of mxq_game_undo refusing on a nearby session: what two
     * players agreed to keep is not one player taking a move back, and neither
     * call is the other with an argument. */
    if (game->config.mode != MXQ_PLAY_MODE_NEARBY) {
        mxq::fill_error(err, MXQ_ERR_STATE_UNDO_UNAVAILABLE,
                        "a negotiated retraction is a nearby action");
        return MXQ_ERR_STATE_UNDO_UNAVAILABLE;
    }
    /* The protocol's own range: keep runs from the initial position to one less
     * than the count, so retracting nothing is not a retraction. */
    if (keep >= game->moves.size()) {
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "a retraction keeps fewer plies than the game holds");
        return MXQ_ERR_ARG_RANGE;
    }

    std::vector<std::string> line = game->moves;
    line.resize(keep);

    /* The wire session is adopted before the commit so that the one transaction
     * writes the shortened line and the retraction count that produced it
     * together. A refused commit leaves neither: the session's own copy goes
     * back with it. */
    const bool had_nearby = game->has_nearby;
    const MxqNearbySession previous = game->nearby;
    game->has_nearby = true;
    game->nearby = state;
    const MxqStatus committed =
        mxq::session::commit_line(*game, std::move(line), err);
    if (committed != MXQ_OK) {
        game->has_nearby = had_nearby;
        game->nearby = previous;
        return committed;
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_set_nearby_session(MxqGame *game,
                                               const MxqNearbySession *session,
                                               MxqError *err) {
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(game);
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::session::require_mutable(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    MxqNearbySession state;
    rc = mxq::session::read_nearby_state(game->config.game, session, state, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    if (game->config.mode != MXQ_PLAY_MODE_NEARBY) {
        mxq::fill_error(err, MXQ_ERR_STATE_RESIGN_UNAVAILABLE,
                        "a wire session belongs to a nearby game");
        return MXQ_ERR_STATE_RESIGN_UNAVAILABLE;
    }
    /* A session's identity is not something a later call revises. Where this
     * game already carries one, the two identifiers must be the ones it was
     * created with — a differing value is a caller writing one session's
     * bookkeeping over another's. */
    if (game->has_nearby &&
        (std::strcmp(game->nearby.session_id, state.session_id) != 0 ||
         std::strcmp(game->nearby.peer_id, state.peer_id) != 0)) {
        assert(false && "a wire session's identity is frozen");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "the wire session's identifiers are not this game's");
        return MXQ_ERR_ARG_RANGE;
    }
    /* And so is its deal, for a stronger reason than the identifiers': the deal
     * is what the game is played over, three of its four values are already in
     * the document this row holds, and a call that revised them would leave the
     * store holding a session whose evidence contradicts its own game. */
    if (game->has_nearby &&
        (std::strcmp(game->nearby.deal_commit, state.deal_commit) != 0 ||
         std::strcmp(game->nearby.deal_nonce, state.deal_nonce) != 0 ||
         std::strcmp(game->nearby.deal_seed, state.deal_seed) != 0 ||
         std::strcmp(game->nearby.deal_digest, state.deal_digest) != 0)) {
        assert(false && "a wire session's deal is frozen");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "the wire session's deal is not the one this game was "
                        "dealt");
        return MXQ_ERR_ARG_RANGE;
    }

    const bool had_nearby = game->has_nearby;
    const MxqNearbySession previous = game->nearby;
    game->has_nearby = true;
    game->nearby = state;
    const mxq::store::NearbySession row = mxq::session::nearby_row_of(state);
    rc = mxq::store::set_nearby_session(*game->core->store, game->record_id, row,
                                        err);
    if (rc != MXQ_OK) {
        game->has_nearby = had_nearby;
        game->nearby = previous;
        return rc;
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_nearby_session(const MxqGame *game,
                                           MxqNearbySession *out,
                                           uint8_t *out_exists, MxqError *err) {
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    if (out_exists == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_exists = 0;
    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqNearbySession)),
                        static_cast<uint32_t>(sizeof(MxqNearbySession)), err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (!game->has_nearby) {
        return MXQ_OK;
    }
    const uint32_t writable = out->struct_size;
    MxqNearbySession state = game->nearby;
    state.struct_size = writable;
    std::memcpy(out, &state, writable);
    *out_exists = 1;
    return MXQ_OK;
}

/* ------------------------------------------------------------------------- */
/* The terminal commits                                                      */
/* ------------------------------------------------------------------------- */

/*
 * The four of them share a shape: the handle checks, the single-owner claim,
 * the mutability check, and the replay their classification is judged against.
 * Each then decides one thing — whether the ending it names is available here,
 * and what outcome and reason it commits — and hands that to end_game.
 *
 * Three take no classification from the caller at all, because none may:
 * docs/game-data.md derives the saved classification from the committed game
 * state, and a caller-supplied result would be a second authority for what a
 * game's outcome is. The fourth is nearby play's, where that authority is not
 * the board: no position decides a resignation or an agreement, and the
 * reconciled session is the only thing that knows which one the two players
 * reached. So it takes the ending — never the outcome, which it still derives —
 * and the replay is what refuses it over a position the rules already decided.
 *
 * The preamble is written out in each rather than factored into a helper,
 * because its order is load-bearing: the registry check comes before anything
 * dereferences the handle, and the owner guard must live for the whole call.
 */
MxqStatus MXQ_CALL mxq_game_claim_draw(MxqGame *game, uint64_t *out_record_id,
                                       MxqError *err) {
    if (out_record_id != nullptr) {
        *out_record_id = 0;
    }
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(game);
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::session::require_mutable(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::session::Replayed replayed;
    rc = mxq::session::replay_prefix(*game, game->moves.size(), false, replayed,
                                     err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /* The claim is legal exactly where the core reports it available, which is
     * the same fact MxqGameStatus.claim_available carries: a frontend offering
     * 判和 and the core accepting it read one adjudication. */
    if (replayed.adj.state != MXQ_GAME_CLAIMABLE_DRAW) {
        mxq::fill_error(err, MXQ_ERR_STATE_CLAIM_UNAVAILABLE,
                        "there is no claimable repetition in this position");
        return MXQ_ERR_STATE_CLAIM_UNAVAILABLE;
    }

    /* The reason is the core's own, not a constant written twice. In this
     * ruleset threefold repetition is the only claimable outcome there is,
     * which is why mxq.h can name it. */
    uint64_t record_id = 0;
    rc = mxq::session::end_game(*game, MXQ_OUTCOME_DRAW, replayed.adj.reason,
                                record_id, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_record_id != nullptr) {
        *out_record_id = record_id;
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_resign(MxqGame *game, uint64_t *out_record_id,
                                   MxqError *err) {
    if (out_record_id != nullptr) {
        *out_record_id = 0;
    }
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(game);
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::session::require_mutable(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::session::Replayed replayed;
    rc = mxq::session::replay_prefix(*game, game->moves.size(), false, replayed,
                                     err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /*
     * Resignation is human-versus-AI only, and there is nothing to resign once
     * the game has a result of its own — which is exactly when
     * MxqGameStatus.resign_available reads 0, so the affordance and the
     * refusal are one rule rather than two.
     *
     * It is also what the archive requires: a recorded resignation must have a
     * non-terminal final position, because an unconfirmed natural result is
     * always recorded as its actual result. Refusing here is what keeps the
     * store from being asked to hold a row its own constraints would refuse.
     */
    MxqGameStatus status;
    std::memset(&status, 0, sizeof(status));
    status.struct_size = static_cast<uint32_t>(sizeof(status));
    mxq::session::fill_status(*game, replayed, &status);
    if (status.resign_available == 0) {
        mxq::fill_error(err, MXQ_ERR_STATE_RESIGN_UNAVAILABLE,
                        game->config.mode == MXQ_PLAY_MODE_HUMAN_VS_AI
                            ? "the game already has a result to resign from"
                            : "resignation is a human-versus-AI action");
        return MXQ_ERR_STATE_RESIGN_UNAVAILABLE;
    }

    /* The loss is the human's, so the win is the other side's. */
    const MxqOutcome outcome = game->config.human_side == MXQ_COLOR_RED
                                   ? MXQ_OUTCOME_BLACK_WINS
                                   : MXQ_OUTCOME_RED_WINS;
    uint64_t record_id = 0;
    rc = mxq::session::end_game(*game, outcome, MXQ_END_REASON_RESIGNATION,
                                record_id, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_record_id != nullptr) {
        *out_record_id = record_id;
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_confirm_result(MxqGame *game,
                                           uint64_t *out_record_id,
                                           MxqError *err) {
    if (out_record_id != nullptr) {
        *out_record_id = 0;
    }
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(game);
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::session::require_mutable(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::session::Replayed replayed;
    rc = mxq::session::replay_prefix(*game, game->moves.size(), false, replayed,
                                     err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /* There must be a natural result to confirm. A claimable repetition is not
     * one: the game continues there unless the claim is made, and claiming is
     * mxq_game_claim_draw's decision rather than this one's. */
    MxqOutcome outcome = MXQ_OUTCOME_NONE;
    if (!mxq::session::outcome_of(replayed.adj.state, outcome)) {
        mxq::fill_error(err, MXQ_ERR_STATE_CONFIRM_UNAVAILABLE,
                        "this position has no natural result to confirm");
        return MXQ_ERR_STATE_CONFIRM_UNAVAILABLE;
    }

    uint64_t record_id = 0;
    rc = mxq::session::end_game(*game, outcome, replayed.adj.reason, record_id,
                                err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_record_id != nullptr) {
        *out_record_id = record_id;
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_game_commit_nearby_end(MxqGame *game, MxqEndReason reason,
                                              MxqColor resigning_side,
                                              uint64_t *out_record_id,
                                              MxqError *err) {
    if (out_record_id != nullptr) {
        *out_record_id = 0;
    }
    MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(game);
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }
    rc = mxq::session::require_mutable(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /*
     * The reason and its side are a closed vocabulary the caller owns, so a
     * pairing outside it is a programming error rather than a user outcome:
     * a resignation names the side that resigned and the two draws name none.
     */
    const bool single_resignation = reason == MXQ_END_REASON_RESIGNATION;
    const bool side_ok = single_resignation
                             ? (resigning_side == MXQ_COLOR_RED ||
                                resigning_side == MXQ_COLOR_BLACK)
                             : resigning_side == MXQ_COLOR_NONE;
    if ((!single_resignation && reason != MXQ_END_REASON_MUTUAL_RESIGNATION &&
         reason != MXQ_END_REASON_AGREED_DRAW) ||
        !side_ok) {
        assert(false && "the nearby ending is not one the protocol carries");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "the end reason and the resigning side do not agree");
        return MXQ_ERR_ARG_RANGE;
    }

    /* These are the ends two players declare to each other, so a game with one
     * player has none of them. */
    if (game->config.mode != MXQ_PLAY_MODE_NEARBY) {
        mxq::fill_error(err, MXQ_ERR_STATE_RESIGN_UNAVAILABLE,
                        "an agreed ending is a nearby action");
        return MXQ_ERR_STATE_RESIGN_UNAVAILABLE;
    }

    mxq::session::Replayed replayed;
    rc = mxq::session::replay_prefix(*game, game->moves.size(), false, replayed,
                                     err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /*
     * An end the rules decided from the plies outranks everything the two
     * players declared — the protocol's own precedence rule — and the archive
     * refuses such a record for the same reason: a checkmate recorded as an
     * agreed draw would be a lost result. Refusing here is what keeps the store
     * from being asked to hold a row its own constraints would refuse. A
     * claimable neutral repetition is not a result, so either end is lawful
     * over it.
     */
    MxqOutcome decided = MXQ_OUTCOME_NONE;
    if (mxq::session::outcome_of(replayed.adj.state, decided)) {
        mxq::fill_error(err, MXQ_ERR_STATE_GAME_OVER,
                        "the game already has a result of its own");
        return MXQ_ERR_STATE_GAME_OVER;
    }

    /* The caller states which end the two players reached; the outcome is still
     * derived from it here, so no caller ever asserts a result. */
    const MxqOutcome outcome =
        single_resignation ? (resigning_side == MXQ_COLOR_RED
                                  ? MXQ_OUTCOME_BLACK_WINS
                                  : MXQ_OUTCOME_RED_WINS)
                           : MXQ_OUTCOME_DRAW;

    uint64_t record_id = 0;
    rc = mxq::session::end_game(*game, outcome, reason, record_id, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_record_id != nullptr) {
        *out_record_id = record_id;
    }
    return MXQ_OK;
}

} /* extern "C" */
