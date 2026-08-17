/*
 * SHA-256, as docs/game-data.md's content identity needs it.
 *
 * Content identity is "SHA-256 over the canonical bytes of the content object
 * alone", and that hash is compared across platforms, so the core carries its
 * own implementation: CommonCrypto exists only on Apple platforms, the Windows
 * equivalent is a different API again, and a correctness-critical value that
 * two platforms compute through two libraries is a value that can differ for
 * reasons no test here would see.
 *
 * The implementation in mxq_sha256.cpp is written from the FIPS 180-4
 * specification rather than vendored, so there is no third-party provenance to
 * record; core/tests/mxq_session_tests.cpp holds it to the published NIST test
 * vectors, including the multi-block one, before anything else in this core
 * trusts it.
 */

#ifndef MXQ_SHA256_HPP
#define MXQ_SHA256_HPP

#include <cstddef>
#include <cstdint>
#include <string>

namespace mxq {

/* The SHA-256 digest of len bytes at bytes, as exactly 64 lowercase
 * hexadecimal characters — the spelling docs/game-data.md's content hash and
 * the store's content_sha256 column both carry. A null pointer is legal only
 * with len 0. */
std::string sha256_hex(const uint8_t *bytes, size_t len);

/* The same digest as its thirty-two bytes. The deal derivation in mxq_deal.cpp
 * is what needs them: docs/boardgame-protocol-v2.md's key and counter stream are
 * hashes fed back into hashes, so a hexadecimal spelling in the middle of that
 * would be a conversion round trip on every block. */
void sha256(const uint8_t *bytes, size_t len, uint8_t out[32]);

/* The same, over a byte string. */
std::string sha256_hex(const std::string &bytes);

} /* namespace mxq */

#endif /* MXQ_SHA256_HPP */
