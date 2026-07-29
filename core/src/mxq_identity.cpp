#include "mxq_identity.hpp"

#include <chrono>
#include <random>

namespace mxq {
namespace identity {

namespace {

/* Format 16 UUID bytes as canonical lowercase text. */
std::string format_uuid(const uint8_t bytes[16]) {
    static const char *hex = "0123456789abcdef";
    std::string out;
    out.reserve(36);
    for (int i = 0; i < 16; ++i) {
        if (i == 4 || i == 6 || i == 8 || i == 10) {
            out.push_back('-');
        }
        out.push_back(hex[bytes[i] >> 4]);
        out.push_back(hex[bytes[i] & 0x0f]);
    }
    return out;
}

/* Assemble a version 7 UUID from its three fields: the 48-bit UTC millisecond
 * timestamp, 12 bits of rand_a, and 62 bits of rand_b, per RFC 9562. The
 * version nibble and the '10' variant bits are applied here so no caller can
 * produce a differently shaped identifier. */
std::string make_uuid_v7(uint64_t unix_ts_ms, uint16_t rand_a, uint64_t rand_b) {
    uint8_t b[16];
    b[0] = static_cast<uint8_t>(unix_ts_ms >> 40);
    b[1] = static_cast<uint8_t>(unix_ts_ms >> 32);
    b[2] = static_cast<uint8_t>(unix_ts_ms >> 24);
    b[3] = static_cast<uint8_t>(unix_ts_ms >> 16);
    b[4] = static_cast<uint8_t>(unix_ts_ms >> 8);
    b[5] = static_cast<uint8_t>(unix_ts_ms);
    b[6] = static_cast<uint8_t>(0x70 | ((rand_a >> 8) & 0x0f)); /* version 7 */
    b[7] = static_cast<uint8_t>(rand_a);
    b[8] = static_cast<uint8_t>(0x80 | ((rand_b >> 56) & 0x3f)); /* variant 10 */
    b[9]  = static_cast<uint8_t>(rand_b >> 48);
    b[10] = static_cast<uint8_t>(rand_b >> 40);
    b[11] = static_cast<uint8_t>(rand_b >> 32);
    b[12] = static_cast<uint8_t>(rand_b >> 24);
    b[13] = static_cast<uint8_t>(rand_b >> 16);
    b[14] = static_cast<uint8_t>(rand_b >> 8);
    b[15] = static_cast<uint8_t>(rand_b);
    return format_uuid(b);
}

int64_t real_now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch())
        .count();
}

/* std::random_device is the platform's own entropy source on every supported
 * toolchain — /dev/urandom-class on Apple platforms, the OS CSPRNG on Windows —
 * which is what "cryptographically seeded" means here. Identifier generation
 * is once per created game, so drawing directly is not a hot path. */
uint64_t random_u64() {
    std::random_device rd;
    return (static_cast<uint64_t>(rd()) << 32) ^ static_cast<uint64_t>(rd());
}

} /* namespace */

void Provider::reset(bool deterministic) {
    std::lock_guard<std::mutex> lock(mutex_);
    deterministic_ = deterministic;
    next_time_ms_  = kDeterministicEpochMs;
    uuid_counter_  = 0;
}

int64_t Provider::now_ms() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!deterministic_) {
        return real_now_ms();
    }
    const int64_t value = next_time_ms_;
    next_time_ms_ += 1000;
    return value;
}

std::string Provider::next_game_id() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!deterministic_) {
        const uint64_t ts = static_cast<uint64_t>(real_now_ms()) & 0xffffffffffffull;
        const uint16_t rand_a = static_cast<uint16_t>(random_u64() & 0x0fff);
        const uint64_t rand_b = random_u64() & 0x3fffffffffffffffull;
        return make_uuid_v7(ts, rand_a, rand_b);
    }
    /* The counter-derived sequence MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY
     * documents: the nth identifier carries the fixed epoch + n in its time
     * field, zero rand_a, and n in its final 62 bits. */
    const uint64_t n = uuid_counter_++;
    const uint64_t ts =
        (static_cast<uint64_t>(kDeterministicEpochMs) + n) & 0xffffffffffffull;
    return make_uuid_v7(ts, 0, n & 0x3fffffffffffffffull);
}

} /* namespace identity */
} /* namespace mxq */
