#include "mxq_deal.hpp"

#include "mxq_jieqi_bridge.hpp"
#include "mxq_notation.hpp"

#include <CommonCrypto/CommonDigest.h>

#include <cassert>
#include <cstring>

namespace mxq {
namespace deal {
namespace {

/* The width of all four handshake values. */
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

/* Exactly sixty-four lowercase hexadecimal digits. */
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

void sha256(const uint8_t *bytes, size_t len, uint8_t out[CC_SHA256_DIGEST_LENGTH]) {
    CC_SHA256(bytes, static_cast<CC_LONG>(len), out);
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
 * The counter stream: the concatenation, for counter 0, 1, 2, … in turn, of
 * SHA-256(key ‖ counter), each counter written as eight bytes most significant
 * first. It is read from the front, byte by byte as values are drawn, and
 * never rewound; refilling per draw or aligning draws to block boundaries
 * would deal another game from the same seed and nonce.
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

    /* Most significant first. */
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
 * A value below n: take the next four bytes as v; with limit the largest
 * multiple of n that is at most 2^32, discard v and take another four whenever
 * v is limit or above; otherwise the value is v mod n. The discarding is part
 * of the derivation, since v mod n alone favours the low values. limit is
 * 64-bit because for n a power of two it is 2^32 itself.
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
 * A permutation of m items: for i from m − 1 down to 1, draw a value j below
 * i + 1 and exchange the items at i and j. The upward variant and the draw
 * below i are both Fisher–Yates and both deal another permutation from the
 * same bytes.
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
 * The fifteen non-general pieces a side holds, in the protocol's order. Item
 * number k of a permutation is this list's k-th piece.
 */
constexpr char kPieces[kDealtPieces] = {'R', 'R', 'N', 'N', 'B', 'B',
                                        'A', 'A', 'C', 'C', 'P', 'P',
                                        'P', 'P', 'P'};

/* Each side's fifteen non-general start squares, in the protocol's order. The
 * permuted list is laid onto them item by item, first item onto first
 * square. */
constexpr const char *kRedSquares[kDealtPieces] = {
    "a1", "b1", "c1", "d1", "f1", "g1", "h1", "i1",
    "b3", "h3", "a4", "c4", "e4", "g4", "i4"};
constexpr const char *kBlackSquares[kDealtPieces] = {
    "a7", "c7", "e7", "g7", "i7", "b8", "h8", "a10",
    "b10", "c10", "d10", "f10", "g10", "h10", "i10"};

char lowercase(char c) { return static_cast<char>(c - 'A' + 'a'); }

/* The i-th square of one side's list, as its text. i outside 0..14 asserts and
 * answers the empty string. */
const char *square_of(MxqColor side, int32_t index) {
    if (index < 0 || index >= kDealtPieces) {
        assert(false && "a dealt square index outside the fifteen");
        return "";
    }
    return side == MXQ_COLOR_RED ? kRedSquares[index] : kBlackSquares[index];
}

} /* namespace */

bool commitment_of(const std::string &hex32, std::string &out) {
    uint8_t bytes[kValueBytes];
    if (!read_hex32(hex32, bytes)) {
        return false;
    }
    uint8_t digest[kValueBytes];
    sha256(bytes, sizeof(bytes), digest);
    out = hex_of(digest, sizeof(digest));
    return true;
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

    /* The key: SHA-256(seed ‖ nonce), seed first. */
    uint8_t joined[kValueBytes * 2];
    std::memcpy(joined, seed, kValueBytes);
    std::memcpy(joined + kValueBytes, nonce, kValueBytes);
    uint8_t key[kValueBytes];
    sha256(joined, sizeof(joined), key);

    /* Two permutations of fifteen items from the one stream, Red's first. */
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
     * The deal digest: SHA-256 over the item number at each index, one byte
     * each, Red's fifteen then Black's. Item numbers rather than letters,
     * because two permutations can lay the same letters onto the same squares.
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


std::string start_of(const Deal &deal) {
    /* An empty board: zero is an empty, face-up point. */
    jieqi::Record record{};

    /* The generals, from the same home table the dealt-start predicate
     * reads. */
    for (int32_t rank = 0; rank < jieqi::kRanks; ++rank) {
        for (int32_t file = 0; file < jieqi::kFiles; ++file) {
            const char home = jieqi::home_letter(file, rank);
            if (home == 'K' || home == 'k') {
                record.letter[rank][file] = home;
            }
        }
    }

    for (int32_t i = 0; i < kDealtPieces; ++i) {
        for (int32_t which = 0; which < 2; ++which) {
            const MxqColor side = which == 0 ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
            int32_t file = 0;
            int32_t rank = 0;
            if (!notation::point_of_square(MXQ_GAME_KIND_JIEQI,
                                           square_of(side, i), file, rank)) {
                assert(false && "a dealt square is a square of this board");
                continue;
            }
            record.letter[rank][file] = which == 0 ? deal.red[i] : deal.black[i];
            record.down[rank][file] = true;
        }
    }

    record.side_to_move = MXQ_COLOR_RED;
    record.halfmove = 0;
    record.fullmove = 1;
    return jieqi::write_record(record);
}

} /* namespace deal */
} /* namespace mxq */
