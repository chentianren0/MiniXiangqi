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
MxqStatus require_impl(const MxqGame *game, MxqError *err) {
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
    out->position_revision = game.position_revision;
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

} /* namespace */

MxqStatus require(const MxqGame *game, MxqError *err) {
    return require_impl(game, err);
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

archive::Record record_of(const MxqGame &game) {
    archive::Record record;
    record.game_id = game.game_id;
    record.config = game.config;
    record.moves = game.moves;
    record.started_at_ms = game.started_at_ms;
    record.written_at_ms = game.written_at_ms;
    /* An active game's stored content records no end. The terminal trio is
     * written by the commits that end a game, which are not this PR's. */
    record.completed = false;
    return record;
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
    const MxqStatus load =
        mxq::store::load_active(*core->store, exists, record_id, archive, err);
    if (load != MXQ_OK) {
        return load;
    }
    if (!exists) {
        /* Absence is success. A frontend asking whether there is a game to
         * resume is asking a question, not making a claim. */
        return MXQ_OK;
    }

    /*
     * The stored bytes go back through the codec — structurally, and then
     * through the same replay the archive validator uses — rather than being
     * trusted because this core wrote them. What is deliberately not applied
     * are the import size bounds: a long local game must always resume.
     *
     * A row that fails either half is store corruption. It is not an archive
     * rejection: nothing imported it, and the user's answer is about their
     * library rather than about a file they chose.
     */
    mxq::archive::Stored stored;
    MxqError decode_error;
    std::memset(&decode_error, 0, sizeof(decode_error));
    decode_error.struct_size = static_cast<uint32_t>(sizeof(decode_error));
    const MxqStatus decoded = mxq::archive::read_stored(
        reinterpret_cast<const uint8_t *>(archive.data()), archive.size(),
        stored, &decode_error);
    if (decoded != MXQ_OK) {
        mxq::fill_error_subsystem(
            err, MXQ_ERR_STORE_CORRUPT,
            (std::string("the stored active game does not decode: ") +
             decode_error.detail)
                .c_str(),
            decoded);
        return MXQ_ERR_STORE_CORRUPT;
    }
    if (stored.completed) {
        mxq::fill_error(err, MXQ_ERR_STORE_CORRUPT,
                        "the active game's archive records an end, which only "
                        "a History record may");
        return MXQ_ERR_STORE_CORRUPT;
    }
    if (stored.start_fen != MXQ_START_FEN) {
        mxq::fill_error(err, MXQ_ERR_STORE_CORRUPT,
                        "the active game does not start from the frozen "
                        "starting position");
        return MXQ_ERR_STORE_CORRUPT;
    }

    auto game = std::unique_ptr<MxqGame>(new MxqGame());
    game->game_id = stored.game_id;
    game->config = stored.config;
    game->config.struct_size = static_cast<uint32_t>(sizeof(MxqGameConfig));
    game->started_at_ms = stored.started_at_ms;
    game->written_at_ms = stored.written_at_ms;
    game->moves = stored.moves;
    game->record_id = record_id;
    game->core = core;

    /* The rules tier, on the line as stored. */
    mxq::session::Replayed replayed;
    MxqError replay_error;
    std::memset(&replay_error, 0, sizeof(replay_error));
    replay_error.struct_size = static_cast<uint32_t>(sizeof(replay_error));
    if (mxq::session::replay_prefix(*game, game->moves.size(), false, replayed,
                                    &replay_error) != MXQ_OK) {
        mxq::fill_error(
            err, MXQ_ERR_STORE_CORRUPT,
            (std::string("the stored active game does not replay: ") +
             replay_error.detail)
                .c_str());
        return MXQ_ERR_STORE_CORRUPT;
    }

    MxqGame *raw = game.release();
    mxq::session::register_session(raw);
    *out_game = raw;
    *out_exists = 1;
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
    const MxqStatus rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    mxq::session::Owner owner(game);
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
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

} /* extern "C" */
