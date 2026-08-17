/*
 * The deal, derived exactly as docs/boardgame-protocol-v2.md derives it.
 *
 * A dealt game's two devices never send the deal: each computes it from the
 * seed and the nonce the handshake exchanged, and the two must compute one
 * identical deal or they are playing different games under one identifier. That
 * makes every step of the derivation normative rather than an implementation's
 * choice — the counter stream's width and byte order, the rejection sampling
 * that keeps a drawn value uniform, the direction Fisher–Yates runs in, the
 * fixed order the pieces are held in, and the fixed order the squares are laid
 * out in. Each is cited against the section that fixes it at the point it is
 * implemented below.
 *
 * This core is the first implementation of it, and it is not the last: the
 * Apple frontend will derive the same deal from the same two values when it
 * plays a nearby game, and a later reader of a finished record derives it again
 * to check the record against its own evidence. So the unit test beside it —
 * core/tests/mxq_session_tests.cpp, the derivation case — states a known seed
 * and nonce, the intermediate values a hand-execution of this algorithm
 * produces, and the deal that comes out, and it is the anchor those later
 * implementations are verified against rather than a test of this one.
 *
 * Nothing here is a rule of the game. What a deal means for play is
 * docs/jieqi-rules.md's, and the position record the deal spells is the game's
 * own start_fen; deriving one is protocol because both ends must compute the
 * same one from what crossed the wire.
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
 * red[i] and black[i] are piece letters in that side's own case — 'R', 'N',
 * 'B', 'A', 'C', 'P' for Red and their lowercase for Black — standing on the
 * i-th square of that side's list, which the protocol fixes and square_of names
 * below. The generals are not dealt and are not here.
 *
 * digest is the deal's own digest in the same sixty-four lowercase hexadecimal
 * digits the handshake's other three values are written in. It is what a resume
 * compares, because it binds everything a deal comes from where the commitment
 * binds the seed alone.
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
 * Returns false, with `detail` filled, for a value that is not that — the one
 * thing this can refuse, the derivation itself being total over every pair of
 * thirty-two-byte values.
 */
bool derive(const std::string &seed_hex, const std::string &nonce_hex,
            Deal &out, std::string &detail);

/*
 * The i-th square of one side's list, as its text — `a1` for Red's first and
 * `a7` for Black's. Both lists are the protocol's own and are in its order; i
 * outside 0..14 is a programming error and answers the empty string.
 *
 * Exposed because the archive's validation compares a derived deal against the
 * identities a start_fen spells, and it must walk the same squares in the same
 * order this module laid them out in.
 */
const char *square_of(MxqColor side, int32_t index);

/*
 * Whether `text` is one of the four handshake values as they are written
 * everywhere they are written: exactly sixty-four lowercase hexadecimal digits.
 * One spelling, checked in one place, so the archive's field validity, the wire
 * session's argument check and the store's constraint cannot drift apart.
 */
bool is_hex32(const std::string &text);

/* The SHA-256 of the thirty-two bytes `hex32` spells, as the same sixty-four
 * lowercase hexadecimal digits — the commitment check, which is the one thing
 * the commitment exists to catch. False for a value is_hex32 refuses. */
bool commitment_of(const std::string &hex32, std::string &out);

#if defined(MXQ_ENABLE_RULES_FACADE)

/*
 * The position record this deal spells: the thirty dealt pieces face down on
 * the squares square_of lays them out on, the two generals face up on their
 * own, Red to move, halfmove 0 and fullmove 1.
 *
 * It is the inverse of what verify below compares, and it is deliberately one
 * function away from it: the deal a start spells and the start a deal spells
 * must be the same relation read in two directions, and two hand-kept copies of
 * it would agree until one of them was changed. The record is written by the
 * bridge's own writer for the same reason verify reads it through the bridge's
 * own reader — there is no second speller of this form.
 */
std::string start_of(const Deal &deal);

/*
 * The whole of what a dealt game's evidence is checked against, in the order
 * docs/game-data.md's validation clause states it: the seed must hash to the
 * commitment, and the deal the seed and the nonce derive must be the one
 * `start_fen` spells.
 *
 * `expected_digest` is the fourth value where the caller holds one — the store
 * does, because a resumed session re-verifies against all four, and an archive
 * does not, the digest being derivable and therefore not recorded. Null skips
 * that comparison and nothing else.
 *
 * Returns false with `detail` filled on the first check that fails. It needs
 * the rules facade because reading the identities a position record spells is
 * the jieqi bridge's reading of that record and not a second one.
 */
bool verify(const std::string &commit, const std::string &nonce,
            const std::string &seed, const char *start_fen,
            const std::string *expected_digest, std::string &detail);

#endif /* MXQ_ENABLE_RULES_FACADE */

} /* namespace deal */
} /* namespace mxq */

#endif /* MXQ_DEAL_HPP */
