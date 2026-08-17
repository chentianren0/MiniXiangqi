/* The deal derivation. See mxq_deal.hpp for what it owes and to whom. */

#include "mxq_deal.hpp"

#include "mxq_sha256.hpp"

#if defined(MXQ_ENABLE_RULES_FACADE)
#include "mxq_jieqi_bridge.hpp"
#include "mxq_notation.hpp"
#endif

#include <cassert>
#include <cstring>

namespace mxq {
namespace deal {
namespace {

/* Thirty-two bytes, which is the width of all four handshake values. */
constexpr size_t kValueBytes = 32;

int hex_digit(char c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    return -1;
}

bool read_hex32(const std::string &text, uint8_t out[kValueBytes]) {
    if (!is_hex32(text)) {
        return false;
    }
    for (size_t i = 0; i < kValueBytes; ++i) {
        out[i] = static_cast<uint8_t>(hex_digit(text[i * 2]) * 16 +
                                      hex_digit(text[i * 2 + 1]));
    }
    return true;
}

std::string hex_of(const uint8_t *bytes, size_t len) {
    static const char kHex[] = "0123456789abcdef";
    std::string out;
    out.reserve(len * 2);
    for (size_t i = 0; i < len; ++i) {
        out.push_back(kHex[bytes[i] >> 4]);
        out.push_back(kHex[bytes[i] & 0x0fu]);
    }
    return out;
}

/*
 * The counter stream, § Deriving the deal:
 *
 *   "The stream is the concatenation, for counter 0, 1, 2, … in turn, of
 *    SHA-256(key ‖ counter), each counter written as eight bytes most
 *    significant first. It is read from the front, byte by byte as values are
 *    drawn, and never rewound."
 *
 * Reading it byte by byte and never rewinding is what makes the derivation a
 * function of the two contributions alone: a reader that refilled per draw, or
 * that aligned draws to block boundaries, would produce a different deal from
 * the same seed and nonce, and the two devices would not be playing one game.
 */
class Stream {
public:
    explicit Stream(const uint8_t key[kValueBytes]) {
        std::memcpy(key_, key, kValueBytes);
    }

    uint8_t next_byte() {
        if (at_ == sizeof(block_)) {
            refill();
        }
        return block_[at_++];
    }

    /* The next four bytes as an unsigned 32-bit integer, most significant
     * first. */
    uint32_t next_u32() {
        uint32_t value = 0;
        for (int i = 0; i < 4; ++i) {
            value = (value << 8) | static_cast<uint32_t>(next_byte());
        }
        return value;
    }

private:
    void refill() {
        uint8_t input[kValueBytes + 8];
        std::memcpy(input, key_, kValueBytes);
        for (int i = 0; i < 8; ++i) {
            input[kValueBytes + i] =
                static_cast<uint8_t>((counter_ >> (8 * (7 - i))) & 0xffu);
        }
        sha256(input, sizeof(input), block_);
        ++counter_;
        at_ = 0;
    }

    uint8_t  key_[kValueBytes];
    uint8_t  block_[32] = {0};
    /* sizeof(block_) forces the first read to refill, so counter 0 is the first
     * block and no zeroed bytes are ever handed out. */
    size_t   at_ = sizeof(block_);
    uint64_t counter_ = 0;
};

/*
 * A value below n, § Deriving the deal:
 *
 *   "take the next four bytes of the stream, most significant first, as an
 *    unsigned 32-bit integer v; with limit the largest multiple of n that is at
 *    most 2^32, discard v and take another four bytes whenever v is limit or
 *    above; otherwise the value is v mod n."
 *
 * The discarding is part of the derivation rather than an implementation's
 * choice: v mod n alone favours the low values whenever n does not divide 2^32,
 * and two implementations that made different choices about it would deal
 * different games. limit is computed in 64-bit arithmetic because for n a power
 * of two it is 2^32 itself, which no uint32_t holds — and then no v is ever at
 * or above it, which is the case where the rejection costs nothing.
 */
uint32_t value_below(Stream &stream, uint32_t n) {
    assert(n >= 2 && "a value is drawn below at least two");
    const uint64_t two_32 = 1ull << 32;
    const uint64_t limit = (two_32 / n) * n;
    for (;;) {
        const uint32_t v = stream.next_u32();
        if (static_cast<uint64_t>(v) < limit) {
            return v % n;
        }
    }
}

/*
 * A permutation of m items, § Deriving the deal:
 *
 *   "for i from m − 1 down to 1, draw a value j below i + 1 and exchange the
 *    items at i and j."
 *
 * Downward, and with the draw below i + 1 so that an item may be exchanged with
 * itself. The upward variant and the draw below i are both Fisher–Yates and
 * both wrong here: they consume the stream in another order and produce another
 * permutation from the same bytes.
 */
void permutation(Stream &stream, uint8_t *items, int32_t m) {
    for (int32_t i = 0; i < m; ++i) {
        items[i] = static_cast<uint8_t>(i);
    }
    for (int32_t i = m - 1; i >= 1; --i) {
        const uint32_t j = value_below(stream, static_cast<uint32_t>(i + 1));
        const uint8_t swap = items[i];
        items[i] = items[j];
        items[j] = swap;
    }
}

/*
 * The fifteen non-general pieces a side holds, in the order the protocol fixes:
 * "chariot, chariot, horse, horse, elephant, elephant, advisor, advisor,
 * cannon, cannon, soldier, soldier, soldier, soldier, soldier". Item number k
 * of a permutation is this list's k-th piece, so the order is what the item
 * numbers mean and the digest is taken over the numbers rather than over the
 * letters.
 */
constexpr char kPieces[kDealtPieces] = {'R', 'R', 'N', 'N', 'B', 'B',
                                        'A', 'A', 'C', 'C', 'P', 'P',
                                        'P', 'P', 'P'};

/* Each side's fifteen non-general start squares, in the protocol's order. The
 * permuted list is laid onto them item by item, first item onto first square,
 * so this order is normative and not a convenience. */
constexpr const char *kRedSquares[kDealtPieces] = {
    "a1", "b1", "c1", "d1", "f1", "g1", "h1", "i1",
    "b3", "h3", "a4", "c4", "e4", "g4", "i4"};
constexpr const char *kBlackSquares[kDealtPieces] = {
    "a7", "c7", "e7", "g7", "i7", "b8", "h8", "a10",
    "b10", "c10", "d10", "f10", "g10", "h10", "i10"};

char lowercase(char c) { return static_cast<char>(c - 'A' + 'a'); }

} /* namespace */

bool is_hex32(const std::string &text) {
    if (text.size() != kValueBytes * 2) {
        return false;
    }
    for (const char c : text) {
        if (hex_digit(c) < 0) {
            return false;
        }
    }
    return true;
}

bool commitment_of(const std::string &hex32, std::string &out) {
    uint8_t bytes[kValueBytes];
    if (!read_hex32(hex32, bytes)) {
        return false;
    }
    out = sha256_hex(bytes, sizeof(bytes));
    return true;
}

const char *square_of(MxqColor side, int32_t index) {
    if (index < 0 || index >= kDealtPieces) {
        assert(false && "a dealt square index outside the fifteen");
        return "";
    }
    return side == MXQ_COLOR_RED ? kRedSquares[index] : kBlackSquares[index];
}

bool derive(const std::string &seed_hex, const std::string &nonce_hex,
            Deal &out, std::string &detail) {
    uint8_t seed[kValueBytes];
    uint8_t nonce[kValueBytes];
    if (!read_hex32(seed_hex, seed)) {
        detail = "the seed is not thirty-two bytes in lowercase hexadecimal";
        return false;
    }
    if (!read_hex32(nonce_hex, nonce)) {
        detail = "the nonce is not thirty-two bytes in lowercase hexadecimal";
        return false;
    }

    /* The key, § Deriving the deal: "SHA-256(seed ‖ nonce) over the two
     * thirty-two-byte values, seed first". Seed first is the whole of the
     * ordering, and reversing it derives another deal from the same
     * handshake. */
    uint8_t joined[kValueBytes * 2];
    std::memcpy(joined, seed, kValueBytes);
    std::memcpy(joined + kValueBytes, nonce, kValueBytes);
    uint8_t key[kValueBytes];
    sha256(joined, sizeof(joined), key);

    /* "jieqi's deal is two permutations of fifteen items, Red's drawn first and
     * Black's second" — drawn one after another from the one stream, which is
     * why they are drawn here in that order and from this one object. */
    Stream stream(key);
    uint8_t red_items[kDealtPieces];
    uint8_t black_items[kDealtPieces];
    permutation(stream, red_items, kDealtPieces);
    permutation(stream, black_items, kDealtPieces);

    for (int32_t i = 0; i < kDealtPieces; ++i) {
        out.red[i] = kPieces[red_items[i]];
        out.black[i] = lowercase(kPieces[black_items[i]]);
    }

    /*
     * The deal digest, § Deriving the deal: "SHA-256 over the deal itself: for
     * each permutation the game drew, in the order it drew them, the item
     * number standing at index 0, then the one at index 1, and so on, one byte
     * each. For jieqi that is thirty bytes, Red's fifteen then Black's
     * fifteen."
     *
     * The item numbers rather than the piece letters, which is what makes the
     * digest bind the derivation itself: two different permutations can lay the
     * same letters onto the same squares — the five soldiers are one item apiece
     * — and a digest over letters would call those one deal.
     */
    uint8_t material[kDealtPieces * 2];
    std::memcpy(material, red_items, kDealtPieces);
    std::memcpy(material + kDealtPieces, black_items, kDealtPieces);
    uint8_t digest[kValueBytes];
    sha256(material, sizeof(material), digest);
    out.digest = hex_of(digest, sizeof(digest));

    detail.clear();
    return true;
}

#if defined(MXQ_ENABLE_RULES_FACADE)

bool verify(const std::string &commit, const std::string &nonce,
            const std::string &seed, const char *start_fen,
            const std::string *expected_digest, std::string &detail) {
    /* The commitment first, because it is the check the commitment exists for:
     * within a completed handshake it is what binds the dealer's contribution
     * before the other one can be known. */
    std::string computed;
    if (!commitment_of(seed, computed)) {
        detail = "the seed is not thirty-two bytes in lowercase hexadecimal";
        return false;
    }
    if (computed != commit) {
        detail = "the seed does not hash to the commitment recorded beside it";
        return false;
    }

    Deal derived;
    if (!derive(seed, nonce, derived, detail)) {
        return false;
    }
    if (expected_digest != nullptr && derived.digest != *expected_digest) {
        detail = "the deal the seed and the nonce derive is not the one the "
                 "recorded digest names";
        return false;
    }

    /* And the deal against the start it is supposed to be. The record is read
     * through the bridge's own reading of it, so the identities compared here
     * are the identities the rules read — there is no second parser of this
     * form. */
    jieqi::Record record{};
    if (!jieqi::read_record(start_fen, record, detail)) {
        return false;
    }
    for (int32_t i = 0; i < kDealtPieces; ++i) {
        for (int32_t which = 0; which < 2; ++which) {
            const MxqColor side = which == 0 ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
            const char *square = square_of(side, i);
            int32_t file = 0;
            int32_t rank = 0;
            if (!notation::point_of_square(MXQ_GAME_KIND_JIEQI, square, file,
                                           rank)) {
                assert(false && "a dealt square is a square of this board");
                detail = "a dealt square is not a square of this board";
                return false;
            }
            const char dealt = which == 0 ? derived.red[i] : derived.black[i];
            if (!record.down[rank][file] ||
                record.letter[rank][file] != dealt) {
                detail = std::string("the derived deal puts a different piece "
                                     "on ") +
                         square + " than the start spells";
                return false;
            }
        }
    }

    detail.clear();
    return true;
}

#endif /* MXQ_ENABLE_RULES_FACADE */

} /* namespace deal */
} /* namespace mxq */
