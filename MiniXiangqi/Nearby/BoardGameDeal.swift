// The deal a hidden-information session is played over, and the spelling its
// four values travel in.
//
// docs/boardgame-protocol-v2.md, "The deal handshake": a hidden-information
// game's start is dealt, and from the session's first ply both devices hold the
// entire deal. The deal is never sent — it is derived on both ends from the
// handshake's two contributions — so what this file holds is the handshake's
// own progress, the four values a completed one produces, and the one spelling
// the protocol writes them in.
//
// **The derivation itself is not here.** Two implementations of it disagreeing
// by a byte would leave two devices playing different games under one
// identifier, so it lives in the core, behind `BoardGameRules.deal`. What is
// here is the commitment — SHA-256 of the seed's own thirty-two bytes, which
// the dealer needs before any nonce exists and so before there is a deal to
// derive — and the entropy the two contributions are drawn from.

import CryptoKit
import Foundation
import Security

/// The thirty-two-byte values the handshake exchanges, in the one spelling the
/// protocol writes them in.
///
/// `commit`, `nonce`, `seed` and `deal_digest` are "strings of exactly
/// sixty-four lowercase hexadecimal digits — thirty-two bytes in order, two
/// digits a byte, high nibble first — and any other string is malformed". An
/// uppercase digit is one of those other strings.
nonisolated enum DealHex {
    /// What every one of the four values is, in bytes.
    static let byteCount = 32
    /// And in digits, which is what the wire carries.
    static var digitCount: Int { byteCount * 2 }

    /// Whether a string is one of the four values as the protocol spells them.
    /// The codec asks this, because a value of any other shape is malformed and
    /// malformed is a violation rather than something to read past.
    static func isWellFormed(_ text: String) -> Bool {
        let digits = text.utf8
        guard digits.count == digitCount else { return false }
        return digits.allSatisfy { digit in
            (0x30...0x39).contains(digit) || (0x61...0x66).contains(digit)
        }
    }

    /// The bytes a well-formed value spells, or nil where it is not one.
    static func bytes(of text: String) -> [UInt8]? {
        guard isWellFormed(text) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)
        var high: UInt8?
        for digit in text.utf8 {
            let value = digit <= 0x39 ? digit - 0x30 : digit - 0x61 + 10
            if let leading = high {
                bytes.append(leading << 4 | value)
                high = nil
            } else {
                high = value
            }
        }
        return bytes
    }

    /// Bytes as the sixty-four digits, high nibble first.
    static func text(of bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// One contribution: thirty-two bytes from the platform's cryptographic
    /// source.
    ///
    /// `SecRandomCopyBytes` and not `SystemRandomNumberGenerator`, for the
    /// reason a locally dealt game draws its own the same way: what the deal
    /// asks for is the platform's *cryptographic* source, and the value the
    /// other device is entitled to assume nobody chose is exactly this one.
    ///
    /// **Drawn per handshake and never kept.** "A contribution serves exactly
    /// one handshake: a pair that deals again — after an abandoned handshake, a
    /// voided session, any re-proposal — draws afresh on both ends, because a
    /// reused contribution is one the other side can already know."
    ///
    /// Nil where the source refused, which is a device that cannot deal at all:
    /// the deal is the one thing this protocol will not make from something
    /// weaker, so the handshake stops where it stands rather than continuing on
    /// a value nobody can vouch for.
    static func contribution() -> String? {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
        else { return nil }
        return text(of: bytes)
    }

    /// The commitment a seed binds to: the SHA-256 of its thirty-two bytes.
    ///
    /// Computed here rather than asked of the deriving entry because of when it
    /// is needed — the dealer commits "without having seen the nonce", so at
    /// that moment there is no deal to derive and nothing but the seed to hash.
    /// "A thirty-two-byte seed carries enough entropy that the hash discloses
    /// nothing about it and binds it completely, which is why the commitment
    /// needs no separate blinding value."
    static func commitment(for seed: String) -> String? {
        guard let bytes = bytes(of: seed) else { return nil }
        return text(of: SHA256.hash(data: Data(bytes)))
    }
}

/// A completed deal, as a hidden-information session holds it.
nonisolated struct BoardGameDeal: Sendable, Equatable {
    /// The commitment the dealer bound its seed with, before it could know the
    /// other contribution.
    var commit: String
    /// The other peer's half.
    var nonce: String
    /// The seed itself, which opened the commitment.
    var seed: String
    /// The digest of the deal those two derived. It is the one of the four a
    /// `resume` carries, "because it binds everything a deal comes from — the
    /// seed, the nonce, and the derivation itself — where the commitment binds
    /// the seed alone".
    var digest: String
    /// The position the deal produced.
    ///
    /// **It holds every hidden identity, so it never travels** — not on the
    /// wire, not into a log line, and not into a diagnostic string. Each end
    /// derives it, shows its own player only what the game's rules allow that
    /// player to know, and sends the game's own move text and nothing else.
    var start: String

    /// A persisted handshake re-derived and re-verified, "against everything
    /// the deal comes from": the seed hashed against the commitment, and the
    /// deal re-derived and its digest compared with the persisted one.
    ///
    /// Nil where either check fails — "a failure of either check means what it
    /// holds is no longer the session". A persisted nonce that has rotted
    /// passes the commitment check and fails the digest, which is why both are
    /// asked and why the digest is the one that travels.
    static func verified(commit: String, nonce: String, seed: String, digest: String,
                         of rulesID: String,
                         by rules: any BoardGameRules) -> BoardGameDeal? {
        guard let derived = rules.deal(seed: seed, nonce: nonce, of: rulesID),
              derived.commit == commit, derived.digest == digest
        else { return nil }
        return derived
    }
}

/// The deal handshake as one end of it stands. A session carries one exactly
/// when its game is a hidden-information game, and none for every other game —
/// which is the pairing the protocol draws between such a game and the
/// handshake its session opens with.
nonisolated enum DealHandshake: Sendable, Equatable {
    /// The dealer, bound to a seed it has committed, waiting for the nonce.
    case awaitingNonce(commit: String, seed: String)
    /// The other peer, waiting for the dealer's commitment.
    case awaitingCommit
    /// The other peer, its nonce sent, waiting for the seed that opens the
    /// commitment.
    case awaitingSeed(commit: String, nonce: String)
    /// Both contributions are in and the deal is derived. The session is
    /// **active** from here: the dealer's on sending `deal_seed`, the other
    /// end's on verifying it.
    case dealt(BoardGameDeal)

    var deal: BoardGameDeal? {
        guard case .dealt(let deal) = self else { return nil }
        return deal
    }
}
