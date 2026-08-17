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
 * The five archiving paths — mxq_game_claim_draw, mxq_game_resign,
 * mxq_game_confirm_result, mxq_game_commit_nearby_end and
 * mxq_store_archive_and_clear — end that game. They differ only in how they
 * classify the ending. Four derive the classification from the committed state
 * alone; the fifth is nearby play's, where the ending is one the two players
 * declared and no position decided, so the caller states which of the three
 * explicit ends the reconciled session reached and the core still derives the
 * outcome from it — no caller ever asserts a result.
 * What they then do is one transaction in the store, through one function, so
 * that "the outcome, the immutable History record, and the cleared
 * active-game reference, atomically" cannot be five subtly different things.
 * Afterwards the session is archived: its queries keep answering, its
 * mutations refuse, and the document it encodes to is the finished one the
 * History record holds.
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

    /* This session object's own identity: process-unique, assigned at
     * registration, never reused. Not the game's identity — that is game_id,
     * which a released-then-resumed game carries into a second session whose
     * revision counter restarts. Delivery-time staleness resolves the session
     * through this, so a search can only ever be compared against the counter
     * it was started under. */
    uint64_t instance_id = 0;

    /* The instant of the committed change the stored document records, which
     * is what its origin.exported_at spells. Carried so that re-encoding a
     * session reproduces the bytes the store holds. */
    int64_t written_at_ms = 0;

    /* The retained main line, index 0 first. */
    std::vector<std::string> moves;

    /*
     * The evidence a dealt game's start was dealt rather than chosen: the
     * commitment, the nonce and the seed the protocol's handshake left behind,
     * frozen at creation and recovered unchanged by resume. Present exactly for
     * a nearby jieqi game and empty for everything else.
     *
     * They are on the session rather than only on the wire session beside it
     * because they are archive content: a filed game keeps them and its wire
     * session is deleted with it, so a replay of a History record must be able
     * to encode them back without one. The fourth value the handshake left —
     * the digest — is not here, because it is not archive content: it is
     * derivable from the deal, and it stays where the re-verification needs it.
     */
    std::string deal_commit;
    std::string deal_nonce;
    std::string deal_seed;

    /* Bumped by every accepted mutation; the staleness authority a search
     * result is compared against. Per session, restarting at zero — which is
     * exactly why delivery resolves the session by instance_id above: two
     * sessions of one game_id across a release-and-resume carry independent
     * counters whose values can collide, so the counter is meaningful only
     * beside the instance it belongs to. Atomic because the engine thread
     * reads it at delivery, through current_revision_of, while the owner
     * thread may be mid-mutation: the mutation that wins that race bumps the
     * value the delivery compares, and either order is correct — a bump the
     * delivery misses is caught by the frontend's second comparison, which
     * the contract requires for exactly this reason. */
    std::atomic<uint64_t> position_revision{0};

    /* The committed ending, written by the five archiving paths and recovered
     * by opening a History record. Meaningful exactly when completed is true,
     * which is also when the document this session encodes to carries the
     * terminal trio. */
    bool         completed = false;
    MxqOutcome   outcome = MXQ_OUTCOME_NONE;
    MxqEndReason end_reason = MXQ_END_REASON_NONE;
    int64_t      ended_at_ms = 0;

    /* The store row this session is attached to. */
    uint64_t record_id = 0;

    /*
     * The wire session a nearby active game is being played over, where the
     * store holds one. It is carried on the session so that every committed
     * mutation writes it in its own transaction: a move line and a retraction
     * count committed a transaction apart could disagree, and the resume
     * exchange would then reconcile to a line neither player played.
     *
     * Absent for every local game, for an imported nearby record, for a replay,
     * and for a nearby game the protocol has parted with.
     */
    bool             has_nearby = false;
    MxqNearbySession nearby{};

    /*
     * The two ways a session stops accepting mutations, which are different
     * facts and carry different statuses.
     *
     * read_only is what a detached session is born: a replay or an import
     * preview was never attached to a row, and asking one for anything that
     * needs a mutable session — a mutation, or the hint search, which proposes
     * a move only a mutable session could take — is a category error the caller
     * made. MXQ_ERR_STATE_SESSION_READ_ONLY, which mxq.h lists among the
     * programming errors.
     *
     * archived is what an attached session becomes when one of the five
     * archiving paths succeeds: the game it owned is now an immutable History
     * record. That is ordinary control flow — MXQ_ERR_STATE_SESSION_ARCHIVED —
     * because a frontend can hold a handle across the moment the game ends.
     * Queries keep answering in both states, and the caller still releases the
     * handle.
     */
    bool read_only = false;
    bool archived = false;

    /* The core that issued this handle, and null once tombstoned. */
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

/* The check every mutation makes after that one, and the hint search with them:
 * this session still accepts mutations at all. See read_only and archived above
 * for why they are two facts and not one. */
MxqStatus require_mutable(const MxqGame *game, MxqError *err);

/*
 * The check every path that puts a move on this position makes: the committed
 * line has no result of its own, and MXQ_ERR_STATE_GAME_OVER where it has. A
 * claimable neutral repetition is not such a result — play continues there
 * unless the claim is made — so it passes.
 *
 * mxq_game_apply_move asks it before accepting a move and the hint search asks
 * it before proposing one, because a game that would take no move has none to
 * suggest either. Exposed for the second of those: the search facade is another
 * translation unit, and one rule answering in two places is what keeps the two
 * answers the same.
 */
MxqStatus require_no_result(const MxqGame *game, MxqError *err);

/* The refusal an unheld Owner turns into. */
MxqStatus concurrent_use(MxqError *err);

/*
 * Tombstone every session this core issued: called by mxq_core_shutdown before
 * the store closes. The handles stay allocated — their owners still hold them
 * and still release them — and every function on one answers
 * MXQ_ERR_ARG_INVALID_HANDLE afterwards.
 */
void invalidate_all(const MxqCore *core);

/*
 * The delivery-time half of the staleness comparison: the current
 * position_revision of the registered session whose instance_id is instance,
 * or false when no such session exists.
 *
 * The session is found by its instance identity and by nothing else. A
 * game_id is not unique among sessions across time — releasing a session and
 * resuming the same stored game registers a second session under the same
 * game_id, whose per-session revision restarts at zero — so a lookup that
 * answered with *any* session carrying the id could compare a search against
 * a counter it was never started under, and equal numbers would then mean
 * different positions: the defeat of both documented staleness checks at
 * once, since the frontend's second comparison reads the same live counter.
 * The instance identity is process-unique and never reused, so the only
 * session this can answer from is the one the search was started on: released
 * or absent finds nothing and the result is rejected as stale, because a
 * result that cannot be shown fresh against the session it came from must not
 * be delivered as a move; an archived session is still found, and rejects by
 * value anyway, because ending a game bumped its revision. game_id rides
 * along as a cross-check on the registry's own consistency. Only frozen
 * fields and the atomic revision are read here, because every other session
 * field belongs to the owner thread.
 */
bool current_revision_of(const MxqCore *core, uint64_t instance,
                         const char *game_id, uint64_t &out_revision);

/* The document this session's committed state encodes to, in the one archive
 * version this build defines. */
archive::Record record_of(const MxqGame &game);

/*
 * mxq_store_archive_and_clear's whole body, and mxq_store_history_open's.
 *
 * Both are declared in mxq.h under the store's prefix because that is the
 * surface they belong to, and both are sessions work: one is the fourth
 * archiving path and performs exactly the ending the four terminal commits
 * do, the other issues a detached read-only session. They live here with the
 * code that already knows how to end a game and how to build a session from a
 * stored row, rather than being reassembled from exported pieces on the other
 * side of a translation unit.
 */
MxqStatus archive_and_clear(MxqCore *core, MxqGame *active,
                            uint64_t *out_record_id, MxqError *err);
MxqStatus history_open(MxqCore *core, uint64_t record_id, MxqGame **out_replay,
                       MxqError *err);

/*
 * The live state of a stored move line, without a session.
 *
 * mxq_store_active_summary answers the Play destination and the
 * save-and-continue confirmation "without materialising a session", and the
 * state and affordances it reports are still derived by replaying the line —
 * there is no second adjudicator and no persisted state flag. This is that
 * derivation, reachable without issuing a handle.
 */
MxqStatus status_of_line(const MxqGameConfig &config,
                         const std::vector<std::string> &moves,
                         MxqGameStatus *out, MxqError *err);

} /* namespace session */
} /* namespace mxq */

#endif /* MXQ_SESSION_HPP */
