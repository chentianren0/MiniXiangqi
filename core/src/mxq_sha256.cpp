/*
 * SHA-256, from FIPS 180-4 § 6.2 directly.
 *
 * One pass, no streaming interface and no incremental state: everything the
 * core hashes is a canonical archive already held whole in memory, and a
 * hasher with one entry point is a hasher with one way to be wrong.
 *
 * The constants below are the specification's own: the eight initial hash
 * values H(0) are the fractional parts of the square roots of the first eight
 * primes, and the sixty-four round constants K are the fractional parts of the
 * cube roots of the first sixty-four primes. They are transcribed rather than
 * computed, exactly as the specification tabulates them.
 */

#include "mxq_sha256.hpp"

#include <cstring>
#include <vector>

namespace mxq {
namespace {

constexpr uint32_t kInitial[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u,
                                  0xa54ff53au, 0x510e527fu, 0x9b05688cu,
                                  0x1f83d9abu, 0x5be0cd19u};

constexpr uint32_t kRound[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu,
    0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u, 0xd807aa98u, 0x12835b01u,
    0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u,
    0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u,
    0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u,
    0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
    0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u,
    0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u, 0x1e376c08u,
    0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu,
    0x682e6ff3u, 0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};

uint32_t rotr(uint32_t x, unsigned n) {
    return (x >> n) | (x << (32u - n));
}

/* The specification's six logical functions, § 4.1.2. */
uint32_t ch(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (~x & z); }
uint32_t maj(uint32_t x, uint32_t y, uint32_t z) {
    return (x & y) ^ (x & z) ^ (y & z);
}
uint32_t big_sigma0(uint32_t x) {
    return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
}
uint32_t big_sigma1(uint32_t x) {
    return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
}
uint32_t small_sigma0(uint32_t x) {
    return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
}
uint32_t small_sigma1(uint32_t x) {
    return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
}

/* One 512-bit block into the eight working words, § 6.2.2. */
void compress(uint32_t h[8], const uint8_t block[64]) {
    uint32_t w[64];
    for (unsigned t = 0; t < 16; ++t) {
        w[t] = (static_cast<uint32_t>(block[t * 4]) << 24) |
               (static_cast<uint32_t>(block[t * 4 + 1]) << 16) |
               (static_cast<uint32_t>(block[t * 4 + 2]) << 8) |
               static_cast<uint32_t>(block[t * 4 + 3]);
    }
    for (unsigned t = 16; t < 64; ++t) {
        w[t] = small_sigma1(w[t - 2]) + w[t - 7] + small_sigma0(w[t - 15]) +
               w[t - 16];
    }

    uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];

    for (unsigned t = 0; t < 64; ++t) {
        const uint32_t t1 = hh + big_sigma1(e) + ch(e, f, g) + kRound[t] + w[t];
        const uint32_t t2 = big_sigma0(a) + maj(a, b, c);
        hh = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    h[0] += a;
    h[1] += b;
    h[2] += c;
    h[3] += d;
    h[4] += e;
    h[5] += f;
    h[6] += g;
    h[7] += hh;
}

} /* namespace */

void sha256(const uint8_t *bytes, size_t len, uint8_t out[32]) {
    uint32_t h[8];
    std::memcpy(h, kInitial, sizeof(h));

    /* Whole blocks straight from the input. */
    size_t offset = 0;
    while (len - offset >= 64) {
        compress(h, bytes + offset);
        offset += 64;
    }

    /* The padded tail, § 5.1.1: the remainder, then 0x80, then zeroes, then
     * the message length in bits as a 64-bit big-endian integer. That length
     * needs nine bytes of room, so the tail is one block when the remainder is
     * under 56 bytes and two when it is not. */
    uint8_t tail[128] = {0};
    const size_t rest = len - offset;
    if (rest > 0) {
        std::memcpy(tail, bytes + offset, rest);
    }
    tail[rest] = 0x80u;
    const size_t tail_len = rest < 56 ? 64u : 128u;
    const uint64_t bits = static_cast<uint64_t>(len) * 8u;
    for (unsigned i = 0; i < 8; ++i) {
        tail[tail_len - 1 - i] = static_cast<uint8_t>((bits >> (8u * i)) & 0xffu);
    }
    compress(h, tail);
    if (tail_len == 128) {
        compress(h, tail + 64);
    }

    for (unsigned i = 0; i < 8; ++i) {
        out[i * 4 + 0] = static_cast<uint8_t>((h[i] >> 24) & 0xffu);
        out[i * 4 + 1] = static_cast<uint8_t>((h[i] >> 16) & 0xffu);
        out[i * 4 + 2] = static_cast<uint8_t>((h[i] >> 8) & 0xffu);
        out[i * 4 + 3] = static_cast<uint8_t>(h[i] & 0xffu);
    }
}

std::string sha256_hex(const uint8_t *bytes, size_t len) {
    uint8_t digest[32];
    sha256(bytes, len, digest);
    static const char kHex[] = "0123456789abcdef";
    std::string out;
    out.reserve(64);
    for (unsigned i = 0; i < 32; ++i) {
        out.push_back(kHex[digest[i] >> 4]);
        out.push_back(kHex[digest[i] & 0x0fu]);
    }
    return out;
}

std::string sha256_hex(const std::string &bytes) {
    return sha256_hex(reinterpret_cast<const uint8_t *>(bytes.data()),
                      bytes.size());
}

} /* namespace mxq */
