/*
 * A game session: what lives behind MxqGame.
 *
 * A session is the game's stored history — its frozen configuration, its
 * identity, and its move line — plus mxq::engine::replay. There is no
 * incremental rules state and no rules code here at all: every query replays
 * the retained line through the same facade the conformance fixtures and the
 * archive validator go through, so a position cannot mean one thing in a
 * session and another in a fixture. Games are short and replay is cheap; a
 * second rules implementation would not be.
 *
 * Store-attached sessions (mxq_game_create, mxq_game_resume_active) own the
 * single active row. Their two ordinary mutations commit inside the call:
 * docs/game-data.md's autosave is not a feature above this interface, it is
 * apply_move's and undo's postcondition, and a commit that fails means the
 * mutation did not happen.
 *
 * Handles are registered rather than merely allocated. mxq_core_shutdown
 * tombstones every session it issued — the handle stays valid memory, every
 * function on it answers MXQ_ERR_ARG_INVALID_HANDLE as mxq.h promises, and the
 * caller still releases it — because the alternative is a handle that dangles
 * into freed memory the moment a frontend tears down out of order.
 *
 * Sessions are single-owner: one thread inside a session at a time, and a
 * detected second one is refused with MXQ_ERR_ARG_CONCURRENT_USE rather than
 * serialised, because with one main window and one active game a concurrent
 * session call is a frontend bug and picking an order would hide it. Owner is
 * that rule, and every entry point takes it first.
 *
 * Compiled only when MXQ_ENABLE_RULES_FACADE is ON: a session that cannot
 * replay cannot answer a single one of its queries, so without the engine the
 * mxq_game_ functions are absent from the library rather than stubbed, exactly
 * as the session-free rules facade is.
 */

#ifndef MXQ_SESSION_HPP
#define MXQ_SESSION_HPP

#include "mxq.h"

#include "mxq_archive_write.hpp"

#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

struct MxqCore;

/*
 * The session behind the opaque handle.
 *
 * Every field is either frozen at creation or advanced by a committed
 * mutation. Nothing here is derived rules state: state, affordances and the
 * position are computed on demand from moves.
 */
struct MxqGame {
    /* Frozen at create, and recovered unchanged by resume. */
    std::string   game_id;
    MxqGameConfig config{};
    int64_t       started_at_ms = 0;

    /* The instant of the committed change the stored document records, which
     * is what its origin.exported_at spells. Carried so that re-encoding a
     * session reproduces the bytes the store holds. */
    int64_t written_at_ms = 0;

    /* The retained main line, index 0 first. */
    std::vector<std::string> moves;

    /* Bumped by every accepted mutation; the staleness authority a search
     * result is compared against. Per session, so a resumed session starts
     * again at zero — a search cannot outlive the session it was started
     * from. */
    uint64_t position_revision = 0;

    /* The store row this session is attached to. */
    uint64_t record_id = 0;

    /* The core that issued this handle, and null once tombstoned. Every
     * session this PR can produce is store-attached; the detached read-only
     * sessions and the archived-after-a-terminal-commit state arrive with the
     * PRs that introduce them, and their guards belong with them. */
    MxqCore *core = nullptr;

    /* The single-owner flag. See Owner. */
    std::atomic<bool> busy{false};
};

namespace mxq {
namespace session {

/*
 * The single-owner guard. Constructing it claims the session for this thread;
 * a session already claimed is refused rather than waited for, which is what
 * makes MXQ_ERR_ARG_CONCURRENT_USE a detected race rather than a serialised
 * one.
 *
 * The guard is also what core/tests drives the concurrency case through: a
 * test holding it is exactly a thread inside the session, with no test-only
 * seam in the core to arrange it.
 */
class Owner {
public:
    explicit Owner(MxqGame *game) : game_(game) {
        if (game_ == nullptr) {
            return;
        }
        bool expected = false;
        held_ = game_->busy.compare_exchange_strong(expected, true,
                                                    std::memory_order_acq_rel);
    }
    ~Owner() {
        if (held_) {
            game_->busy.store(false, std::memory_order_release);
        }
    }

    Owner(const Owner &) = delete;
    Owner &operator=(const Owner &) = delete;

    bool held() const { return held_; }

private:
    MxqGame *game_ = nullptr;
    bool     held_ = false;
};

/*
 * The handle check every session function makes first: the pointer is one this
 * core issued and has not been tombstoned. Exposed because mxq_archive_encode
 * takes a session too and must ask exactly the same question.
 */
MxqStatus require(const MxqGame *game, MxqError *err);

/* The refusal an unheld Owner turns into. */
MxqStatus concurrent_use(MxqError *err);

/*
 * Tombstone every session this core issued: called by mxq_core_shutdown before
 * the store closes. The handles stay allocated — their owners still hold them
 * and still release them — and every function on one answers
 * MXQ_ERR_ARG_INVALID_HANDLE afterwards.
 */
void invalidate_all(const MxqCore *core);

/* The version 1 document this session's committed state encodes to. */
archive::Record record_of(const MxqGame &game);

} /* namespace session */
} /* namespace mxq */

#endif /* MXQ_SESSION_HPP */
