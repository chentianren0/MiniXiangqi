/*
 * The Jieqi deal, derived from a seed and a nonce.
 *
 * A dealt game's two devices never send the deal: each computes it from the
 * seed and the nonce the handshake exchanged, and the two must compute one
 * identical deal or they are playing different games. So every step here is
 * normative rather than an implementation's choice — the counter stream's width
 * and byte order, the rejection sampling that keeps a drawn value uniform, the
 * direction Fisher–Yates runs in, the order the pieces are held in and the
 * order the squares are laid out in.
 */

#ifndef MXQ_DEAL_HPP
#define MXQ_DEAL_HPP

#include "mxq.h"

#include <cstdint>
#include <string>

namespace mxq {
namespace deal {

/* Fifteen non-general pieces a side, dealt onto fifteen squares. */
constexpr int32_t kDealtPieces = 15;

/*
 * One derived deal: the piece each side's fifteen non-general start squares
 * holds, and the digest of the deal itself.
 *
 * red[i] and black[i] are piece letters in that side's own case, standing on
 * the i-th square of that side's list. The generals are not dealt.
 *
 * digest is sixty-four lowercase hexadecimal digits. It is what a resume
 * compares, because it covers everything a deal comes from where the
 * commitment covers the seed alone.
 */
struct Deal {
    char        red[kDealtPieces];
    char        black[kDealtPieces];
    std::string digest;
};

/*
 * Derive the deal from a seed and a nonce, each given as exactly sixty-four
 * lowercase hexadecimal digits.
 *
 * Returns false, with `detail` filled, for a value that is not that; the
 * derivation itself is total.
 */
bool derive(const std::string &seed_hex, const std::string &nonce_hex,
            Deal &out, std::string &detail);

/* The SHA-256 of the thirty-two bytes `hex32` spells, as sixty-four lowercase
 * hexadecimal digits: the commitment. False for a value that is not sixty-four
 * lowercase hexadecimal digits. */
bool commitment_of(const std::string &hex32, std::string &out);


/*
 * The position record this deal spells: the thirty dealt pieces face down on
 * their squares, the two generals face up on their own, Red to move, halfmove
 * 0 and fullmove 1. Written by the jieqi bridge's own writer.
 */
std::string start_of(const Deal &deal);

} /* namespace deal */
} /* namespace mxq */

#endif /* MXQ_DEAL_HPP */
