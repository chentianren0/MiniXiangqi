/* Sessions: the mxq_game_ surface. See mxq_session.hpp for the design. */

#include "mxq_session.hpp"

#include "mxq_archive_read.hpp"
#include "mxq_archive_write.hpp"
#include "mxq_core_state.hpp"
#include "mxq_engine_bridge.hpp"
#include "mxq_internal.hpp"
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
        assert(false && "a mutation on a detached read-only session");
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
    engine::Adjudication     adj{};
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
    const engine::ReplayError rc = engine::replay(
        MXQ_START_FEN, moves.empty() ? nullptr : moves.data(), moves.size(),
        out.fen, out.in_check, out.ply, out.adj,
        want_legal ? &out.legal : nullptr, first_illegal, detail);
    if (rc != engine::ReplayError::None) {
        fill_error(err, MXQ_ERR_INTERNAL_INVARIANT,
                   ("the retained line no longer replays: " + detail).c_str());
        return MXQ_ERR_INTERNAL_INVARIANT;
    }
    return MXQ_OK;
}

MxqColor side_to_move(const std::string &fen) {
    return fen.find(" w ") != std::string::npos ? MXQ_COLOR_RED
                                                : MXQ_COLOR_BLACK;
}

/* Red moves first from the frozen starting position, so the side that made
 * ply i is decided by i's parity and never has to be tracked. */
MxqColor mover_of(size_t ply_index) {
    return (ply_index % 2 == 0) ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
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
    if (game.config.mode != MXQ_PLAY_MODE_HUMAN_VS_AI) {
        return 1;
    }
    if (mover_of(n - 1) == game.config.human_side) {
        return 1;
    }
    return n >= 2 ? 2u : 0u;
}

void fill_status(const MxqGame &game, const Replayed &replayed,
                 MxqGameStatus *out) {
    out->state = replayed.adj.state;
    out->reason = replayed.adj.reason;
    out->at_occurrence = replayed.adj.at_occurrence;

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

/* The frozen canonical notation: <from><to> over the 7 by 7 board, no
 * suffix. */
bool well_formed_move(const char *move) {
    if (move == nullptr || std::strlen(move) != 4) {
        return false;
    }
    for (size_t i = 0; i < 4; i += 2) {
        if (move[i] < 'a' || move[i] > 'g') {
            return false;
        }
        if (move[i + 1] < '1' || move[i + 1] > '7') {
            return false;
        }
    }
    return true;
}

bool well_formed_square(const char *square) {
    return square != nullptr && std::strlen(square) == 2 && square[0] >= 'a' &&
           square[0] <= 'g' && square[1] >= '1' && square[1] <= '7';
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
    row.mode = archive::mode_text(record.config.mode);
    row.human_side = archive::color_text(record.config.human_side);
    row.ai_level = archive::ai_level_text(record.config.ai_level);
    row.first_mover_choice =
        archive::first_mover_text(record.config.first_mover_choice);
    row.ai_movetime_ms = static_cast<int64_t>(record.config.ai_movetime_ms);
    row.move_count = static_cast<int64_t>(record.moves.size());
    row.started_at_ms = record.started_at_ms;
    return row;
}

/*
 * Commit one mutated move line and, only if that succeeded, adopt it.
 *
 * This ordering is the whole of docs/game-data.md's autosave rule: the store
 * decides whether the mutation happened. A failed commit returns with the
 * session — its moves, its revision, its written instant — exactly as it was,
 * so no accepted-but-unsaved change can exist even for the duration of a
 * return.
 */
MxqStatus commit_line(MxqGame &game, std::vector<std::string> line,
                      MxqError *err) {
    const int64_t written_at = game.core->identity.now_ms();

    archive::Record record = record_of(game);
    record.moves = std::move(line);
    record.written_at_ms = written_at;

    const std::string content = archive::content_bytes(record);
    const std::string document = archive::document_bytes(record, content);

    const MxqStatus rc = store::rewrite_active(
        *game.core->store, game.record_id, document, sha256_hex(content),
        static_cast<int64_t>(record.moves.size()), err);
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
 * The one atomic ending, shared by all four archiving paths.
 *
 * The classification arrives already derived from the committed state; what
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
 */
MxqStatus session_from_row(MxqCore *core, uint64_t record_id,
                           const std::string &archive_bytes,
                           const std::string &content_sha256,
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
    if (stored.start_fen != MXQ_START_FEN) {
        fill_error(err, MXQ_ERR_STORE_CORRUPT,
                   "the stored game does not start from the frozen starting "
                   "position");
        return MXQ_ERR_STORE_CORRUPT;
    }

    std::unique_ptr<MxqGame> game =
        session_of(core, stored, record_id, read_only);

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
                          /*expect_completed=*/true, /*read_only=*/true, game,
                          err);
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

MxqStatus MXQ_CALL mxq_game_create(MxqCore *core, const MxqGameConfig *config,
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
    const bool human_vs_ai = config->mode == MXQ_PLAY_MODE_HUMAN_VS_AI;
    bool shape_ok = human_vs_ai || config->mode == MXQ_PLAY_MODE_FREE_PLAY;
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
        /* Free Play omits all four rather than writing the NONE constants into
         * the archive, so it must not carry values to omit. */
        shape_ok = shape_ok && config->human_side == MXQ_COLOR_NONE &&
                   config->ai_level == MXQ_AI_LEVEL_NONE &&
                   config->first_mover_choice == MXQ_FIRST_MOVER_NONE &&
                   config->ai_movetime_ms == 0;
    }
    if (!shape_ok) {
        assert(false && "the game configuration is not one this ruleset defines");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "the configuration's mode and its four human-versus-AI "
                        "members do not agree");
        return MXQ_ERR_ARG_RANGE;
    }

    auto game = std::unique_ptr<MxqGame>(new MxqGame());
    game->game_id = core->identity.next_game_id();
    /* One reading of the clock for one committed event: it is both the game's
     * start and the instant the document it writes records. */
    game->started_at_ms = core->identity.now_ms();
    game->written_at_ms = game->started_at_ms;
    game->config = *config;
    game->config.struct_size = static_cast<uint32_t>(sizeof(MxqGameConfig));
    game->core = core;

    const mxq::archive::Record record = mxq::session::record_of(*game);
    const std::string content = mxq::archive::content_bytes(record);
    const std::string document = mxq::archive::document_bytes(record, content);

    uint64_t record_id = 0;
    rc = mxq::store::create_active(
        *core->store, mxq::session::row_of(record, document, content),
        record_id, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    game->record_id = record_id;

    MxqGame *raw = game.release();
    mxq::session::register_session(raw);
    *out_game = raw;
    return MXQ_OK;
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
    const MxqStatus load = mxq::store::load_active(
        *core->store, exists, record_id, archive, content_sha256, err);
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
        core, record_id, archive, content_sha256, /*expect_completed=*/false,
        /*read_only=*/false, game, err);
    if (built != MXQ_OK) {
        return built;
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
    if (!mxq::session::well_formed_square(from_square)) {
        assert(false && "from_square is not a square of this board");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "from_square is not a two-character square of this "
                        "board");
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

    std::vector<std::string> from_here;
    for (const std::string &move : replayed.legal) {
        if (move.compare(0, 2, from_square, 2) == 0) {
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
    if (!mxq::session::well_formed_move(move)) {
        mxq::fill_error(err, MXQ_ERR_RULES_MALFORMED_MOVE,
                        "the move is not in the canonical <from><to> notation");
        return MXQ_ERR_RULES_MALFORMED_MOVE;
    }

    /* A game with a result of its own accepts no further move. A claimable
     * repetition is not such a result: play continues unless the claim is
     * made. */
    mxq::session::Replayed before;
    rc = mxq::session::replay_prefix(*game, game->moves.size(), false, before,
                                     err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (mxq::session::terminal(before.adj.state)) {
        mxq::fill_error(err, MXQ_ERR_STATE_GAME_OVER,
                        "the game already has a result");
        return MXQ_ERR_STATE_GAME_OVER;
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
    mxq::engine::Adjudication adj{};
    size_t first_illegal = 0;
    switch (mxq::engine::replay(MXQ_START_FEN, texts.data(), texts.size(), fen,
                                in_check, ply, adj, nullptr, first_illegal,
                                detail)) {
    case mxq::engine::ReplayError::None:
        break;
    case mxq::engine::ReplayError::IllegalMove:
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
    case mxq::engine::ReplayError::StartFenInvalid:
    case mxq::engine::ReplayError::NotInitialised:
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

/* ------------------------------------------------------------------------- */
/* The terminal commits                                                      */
/* ------------------------------------------------------------------------- */

/*
 * The three of them share a shape: the handle checks, the single-owner claim,
 * the mutability check, and the replay their classification is derived from.
 * Each then decides one thing — whether the ending it names is available here,
 * and what outcome and reason it commits — and hands that to end_game. None
 * takes a classification from the caller, because none may: docs/game-data.md
 * derives the saved classification from the committed game state, and a
 * caller-supplied result would be a second authority for what a game's outcome
 * is.
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

} /* extern "C" */
