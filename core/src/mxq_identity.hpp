/* The core's one clock and identity provider.
 *
 * Everything in the core that needs an instant or a fresh game identifier asks
 * this provider — sessions will consume it for game_id, started_at and
 * History-added times — so that MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY has one
 * seam to act on. Two sources of time or identity would make the flag a lie.
 *
 * Production behaviour (the flag absent): now_ms reads the real UTC clock and
 * next_game_id generates a real RFC 9562 version 7 UUID with random bits from
 * a cryptographically seeded source.
 *
 * Deterministic behaviour (the flag set) is documented exactly, and
 * normatively, on MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY in mxq.h; this
 * implementation follows that comment rather than the other way around.
 */

#ifndef MXQ_IDENTITY_HPP
#define MXQ_IDENTITY_HPP

#include <cstdint>
#include <mutex>
#include <string>

namespace mxq {
namespace identity {

/* The fixed deterministic epoch: 2026-01-01T00:00:00.000Z. */
constexpr int64_t kDeterministicEpochMs = 1767225600000;

class Provider {
public:
    /* Configure the provider at mxq_core_init. Resets both deterministic
     * sequences, so two core lifetimes with the flag set observe identical
     * values. */
    void reset(bool deterministic);

    /* The current instant as UTC epoch milliseconds. Deterministic mode:
     * kDeterministicEpochMs on the first read, then +1000 per read. */
    int64_t now_ms();

    /* A fresh game identifier: a version 7 UUID in canonical lowercase text,
     * 36 characters. Deterministic mode: the counter-derived sequence the
     * header documents, independent of now_ms. */
    std::string next_game_id();

private:
    std::mutex mutex_;
    bool       deterministic_ = false;
    int64_t    next_time_ms_  = kDeterministicEpochMs;
    uint64_t   uuid_counter_  = 0;
};

} /* namespace identity */
} /* namespace mxq */

#endif /* MXQ_IDENTITY_HPP */
