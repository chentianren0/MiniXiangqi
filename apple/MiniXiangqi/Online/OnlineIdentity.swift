// Who the other player is, where the carrier has already answered it.
//
// The protocol contract asks the transport for "a stable peer identity named
// behind every connection … exactly one such identity per peer — the same
// across a relaunch, the same behind every connection to that peer whatever
// carries it". On the local paths nothing the system offered answered that, so
// `NearbyIdentity` mints an identifier per install and the two devices tell
// each other theirs on every connection they open.
//
// **Here the carrier answers it, and that is the whole of the identity.** A
// `GKPlayer`'s `gamePlayerID` is Game Center's own identifier for a person
// within this game: stable across relaunches, the same behind every match with
// them, and issued by the service that authenticated them rather than claimed
// by whoever is on the other end. So this transport opens no exchange, sends
// nothing of its own on the wire, and writes nothing down — there is nothing to
// learn that has not already been said, and nothing to remember between
// connections. `NearbyIdentity`'s two preference stores are untouched: neither
// this install's minted identifier nor the pairing linkage means anything to a
// player Game Center named.
//
// **The namespace is its own, and must be.** A nearby identity is an install of
// this app; an online identity is a person's Game Center account, and the same
// person on two devices is one identity here and two there. Spelling them the
// same way would be two different things under one name, which the engine
// answers by destroying a game rather than by degrading one — so the prefixes
// are disjoint by construction, and no online peer can ever collide with a
// `device-` one.
//
// **The identifier never reaches a reader.** It is privacy-scoped by Apple —
// unique to this game, and not the player's account anywhere else — and what a
// row shows is `GKPlayer.displayName`, which is the system's own name for them
// and which the app neither invents nor stores. That is also why nothing here
// extends `NearbyIdentity`'s label and tail handling: `tail(ofPeer:)` answers
// nothing for an online peer, which is right, because the four-character tail
// exists for a device that has no name at all and Game Center always supplies
// one.

import Foundation

/// What Game Center calls the other player, in the protocol's own vocabulary.
nonisolated enum OnlineIdentity {

    /// What an online identity is spelled with, so that it and a nearby one can
    /// never be spelled the same way by accident. It is deliberately not
    /// `NearbyIdentity.peerPrefix`, and deliberately not a prefix of it.
    static let peerPrefix = "game-center-"

    /// The peer identity a Game Center player identifier names.
    ///
    /// `PeerDeviceID` is named for what the local paths could name — an install
    /// on a device — and what it holds here is a person. Nothing above cares:
    /// the engine only ever compares one to another, and the contract's demand
    /// is stability rather than what the identity is *of*.
    static func peer(_ gamePlayerID: String) -> PeerDeviceID {
        PeerDeviceID("\(peerPrefix)\(gamePlayerID)")
    }
}
