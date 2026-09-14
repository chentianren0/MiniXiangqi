// Who this device is to another device, and who another device is to this one.
//
// The protocol contract asks the transport for "a stable peer identity named
// behind every connection … exactly one such identity per peer — the same
// across a relaunch, the same behind every connection to that peer whatever
// carries it". Nothing the system offers answers that across two ways of
// reaching a device: a pairing record names a device only where the two are
// paired, and a network endpoint names an address rather than a device. So the
// application mints its own identifier, one per install, and the two devices
// tell each other theirs on every connection they open.
//
// **It is honest-only, and that is the whole posture.** The identifier is
// self-reported and proved by nothing. It buys no access: a device claiming
// another's identifier still reaches the proposal's consent prompt, which is
// the gate every game passes through. Collisions are a non-event at UUID width.
// There are no keys here, and there is no cryptography of ours anywhere in this
// feature.
//
// **A reinstall mints a new one**, which is the same event as the empty library
// beside it: a session the other device still holds is answered by the
// protocol's own unknown-session law, and nothing here is special-cased for it.
//
// The store is the app's own preferences database — the same one the Settings
// preferences live in, because it is where per-install app state belongs. None
// of this is a preference: nothing sets it, nothing shows it, and no screen
// reads it.

import Foundation

/// This install's identity, and what it has learned of other devices'.
nonisolated enum NearbyIdentity {

    /// The identifier this install answers to.
    static let identifierKey = "nearby.identifier"
    /// What this device has learned stands behind each pairing record.
    static let linkageKey = "nearby.linkage"

    // MARK: - This device

    /// This install's own identifier, minted the first time anything needs one.
    ///
    /// Main-actor because minting is a read and a write of one value and every
    /// caller is already there — the transport that advertises it and the
    /// connection that sends it are both main-actor. A second mint would be a
    /// second identity for one install, which is exactly what this type exists
    /// to make impossible.
    @MainActor
    static func own(in defaults: UserDefaults = Preferences.defaults) -> String {
        if let stored = defaults.string(forKey: identifierKey), !stored.isEmpty {
            return stored
        }
        let minted = UUID().uuidString
        defaults.set(minted, forKey: identifierKey)
        return minted
    }

    // MARK: - Another device

    /// What a canonical identity is spelled with, so that it and the
    /// pairing-record fallback can never be spelled the same way by accident.
    static let peerPrefix = "device-"

    /// The canonical peer identity an application identifier names.
    static func peer(_ identifier: String) -> PeerDeviceID {
        PeerDeviceID("\(peerPrefix)\(identifier)")
    }

    /// What this device has learned stands behind a pairing record, if it has
    /// learned it. The mapping is stored so that the room can show one row for
    /// a device it is both paired with and browsing before any connection to it
    /// stands.
    @MainActor
    static func linked(to pairing: PeerDeviceID,
                       in defaults: UserDefaults = Preferences.defaults) -> PeerDeviceID? {
        guard let identifier = mapping(in: defaults)[pairing.rawValue] else { return nil }
        return peer(identifier)
    }

    /// Remember what stands behind a pairing record. Idempotent, and a changed
    /// identifier replaces the mapping: an install that was reinstalled is a
    /// new identity behind the same pairing, and the newer answer is the true
    /// one.
    @MainActor
    static func link(_ pairing: PeerDeviceID, to identifier: String,
                     in defaults: UserDefaults = Preferences.defaults) {
        var mapped = mapping(in: defaults)
        guard mapped[pairing.rawValue] != identifier else { return }
        mapped[pairing.rawValue] = identifier
        defaults.set(mapped, forKey: linkageKey)
    }

    /// The stored mapping, and an empty one for anything unreadable — a
    /// preferences file is editable by hand, and the room still has to open.
    @MainActor
    private static func mapping(in defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: linkageKey) as? [String: String] ?? [:]
    }

    // MARK: - What a device is called where it has no name

    /// The label a device is advertised and listed under: what kind of device
    /// it is, and enough of its identifier to tell two of a kind apart.
    ///
    /// **Never the system's device name.** That name is its owner's own name as
    /// often as not, and it would otherwise be broadcast to a whole network by
    /// the mere fact of a Bonjour registration, which is the leak the privacy
    /// rule exists to prevent. Nothing keys on this: it is a row's words, and
    /// two devices that end up with the same words are two rows all the same,
    /// because a row is one identity rather than one label.
    static func label(for identifier: String, kind: String) -> String {
        let tail = tail(of: identifier)
        return tail.isEmpty ? kind : "\(kind) \(tail)"
    }

    /// The last four characters of an identifier, which is enough to tell two
    /// devices of one kind apart and not enough to be anybody's name.
    static func tail(of identifier: String) -> String {
        String(identifier.filter(\.isHexDigit).suffix(4)).uppercased()
    }

    /// The four characters a peer's row may carry where it has no name at all.
    ///
    /// **Only a canonical identity has one.** That identifier is a UUID this
    /// application minted, so four of its characters are four characters and
    /// nothing else; a pairing record's number is the system's own bookkeeping,
    /// which is not a thing to show a reader and not a thing to tell two
    /// devices apart by.
    static func tail(ofPeer peer: PeerDeviceID) -> String? {
        guard peer.rawValue.hasPrefix(peerPrefix) else { return nil }
        let tail = tail(of: String(peer.rawValue.dropFirst(peerPrefix.count)))
        return tail.isEmpty ? nil : tail
    }

    // MARK: - Settling one connection

    /// The exchange, once per connection, between a connection becoming usable
    /// and the driver being told of it.
    ///
    /// Answers the identity the driver is handed, or nothing at all — and
    /// nothing means the connection is dropped rather than opened under some
    /// other name. **A connection this device cannot name is a connection it
    /// must not hold**: the engine answers a message whose session peer does
    /// not match its connection's peer with an unknown-session void or a
    /// violation close, so a peer named two ways would not degrade a game, it
    /// would destroy one.
    ///
    /// Where the connection has a pairing behind it, what the peer said is
    /// remembered against that pairing. That is the whole of what pairing buys
    /// the identity: an anchor, learned over a connection the platform itself
    /// authenticated, that outlives the connection and lets the room show one
    /// row before the next one stands.
    @MainActor
    static func resolve(over exchange: any NearbyLinkageExchange,
                        pairing: PeerDeviceID?,
                        within window: Duration,
                        in defaults: UserDefaults = Preferences.defaults) async -> PeerDeviceID? {
        do {
            try await exchange.sendLinkage(own(in: defaults))
        } catch {
            // A send that throws is a link already dying, which the driver's
            // own contract says of every send on this seam.
            return nil
        }
        guard let identifier = await exchange.linkageArrived(within: window),
              !identifier.isEmpty
        else { return nil }

        if let pairing { link(pairing, to: identifier, in: defaults) }
        return peer(identifier)
    }
}

/// What the transport can do with a connection while it is still deciding what
/// stands behind it: say who this device is, and hear who the other one is.
///
/// A seam rather than a method, because the resolution it feeds is the load-
/// bearing step of the whole transport and has to be provable without a radio
/// in the room or a network under it.
@MainActor
protocol NearbyLinkageExchange: AnyObject {
    /// Say who this device is. Throws only when the link is already dying.
    func sendLinkage(_ identifier: String) async throws
    /// Who the other device says it is, or nothing where it never said within
    /// the window it had.
    func linkageArrived(within window: Duration) async -> String?
}
