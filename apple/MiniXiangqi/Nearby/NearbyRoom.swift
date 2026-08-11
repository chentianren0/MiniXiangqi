// Who is in the room, and which connection a game would travel.
//
// docs/interaction-design.md, "Nearby play": the room is everybody there is to
// play with — a device this one is paired with, and a device on the same local
// network running the application — each one row, one device, in one list; a
// device that is both is one row and not two; and no row says which of the two
// it is.
//
// Two jobs, and they are one file because they are one sentence. The first is
// the merge: three sources know about devices, and one device is one row
// whichever of them saw it. The second is the choice: where more than one
// connection stands to a device, exactly one of them is what the list hands
// over, and which one is decided here rather than anywhere above.
//
// **Nothing above this file learns what carried a connection.** A `NearbyPeer`
// names a device and a connection and has nowhere to put a kind; `NearbyLink`
// gives the driver a name, a send and a close.
//
// **The preference between the two paths is spent at the moment a connection is
// named**, and nowhere else. The transport mints a connection's identifier with
// its own order in front of it, so the candidate it would rather use sorts first
// by construction — and everything that chooses among connections, here and in
// the driver, does it by sorting those opaque identifiers blindly. That is what
// lets one preference serve two choosers with no seam carrying a link kind and
// no chooser above the transport reading one.
//
// Platform-free on purpose: the merge and the order are decidable without a
// radio, a network, or a device, so they are testable without one.

import Foundation

/// What a row calls a device.
///
/// **Every device has words, and none of them is an identifier.** A raw
/// identity on screen would be a diagnostic shown to a reader, and the one this
/// transport's radio path mints spells out a carrier besides, which no word the
/// application writes may do. So there are two cases and no third: what the
/// device is called, or the one neutral label.
nonisolated enum NearbyLabel: Equatable, Sendable {
    /// The device's own name, as the system knows it.
    case named(String)
    /// The one neutral label, with the four characters that tell two otherwise
    /// wordless rows apart where the identity offers any.
    case unnamed(tail: String?)

    /// The label a device carries, from what is known about it.
    init(name: String?, peer: PeerDeviceID) {
        if let named = NearbyDeviceName.present(name) {
            self = .named(named)
        } else {
            self = .unnamed(tail: NearbyIdentity.tail(ofPeer: peer))
        }
    }

    /// The words themselves, in the reader's own language. The neutral label is
    /// copy and is translated; a device's own name is data and is not.
    var text: String {
        switch self {
        case .named(let name):
            name
        case .unnamed(let tail):
            tail.map { "\(String(localized: "nearby.unnamedDevice")) \($0)" }
                ?? String(localized: "nearby.unnamedDevice")
        }
    }
}

/// What a device is called, out of everything the system may know it by.
nonisolated enum NearbyDeviceName {
    /// The name to show for a paired device.
    ///
    /// **The pairing ceremony is asymmetric**, so the two devices do not end up
    /// holding the same record: the side that went looking chose the other *by*
    /// its name and keeps it, while the side that made itself discoverable saw
    /// only a code to confirm — and its record's own `name` is routinely
    /// nothing at all. The name the ceremony itself left is the second place to
    /// look, and it is the one that saves that side's rows.
    static func resolved(name: String?, pairingName: String?) -> String? {
        present(name) ?? present(pairingName)
    }

    /// A name that is actually a name. Absent and blank are one case: a record
    /// carrying spaces is a record with nothing in it, and a row of spaces is
    /// worse than the neutral label, because it looks like a bug rather than
    /// like a device.
    static func present(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// What carries a connection. **Inside the transport only** — nothing outside
/// it is ever handed one of these, and no seam has anywhere to put one.
///
/// Its `rawValue` is the transport's own order between the two paths, and the
/// one use it is put to is naming a connection: a connection's identifier
/// carries this in front of it, which is how the preference reaches everything
/// that sorts identifiers without any of them being told what it means.
nonisolated enum NearbyLinkKind: Int, Sendable {
    /// The local network. Preferred where both stand: it is the path that
    /// reaches through the walls of a home, which is the whole reason there
    /// are two.
    case network = 0
    /// The paired-device radio, which needs no network at all.
    case radio = 1
}

nonisolated extension ConnectionID {
    /// The name the transport gives one of its connections, with its own
    /// preference in front of it.
    ///
    /// **This is where the choice between the two paths is made** — once, at the
    /// moment a connection comes into existence, by the one layer that knows
    /// there are two of them. Everything downstream chooses among connections by
    /// sorting these strings, so the preferred one is already first and no
    /// chooser has to be told why.
    ///
    /// It is lawful because the identifier is opaque above the transport: it is
    /// transport-minted, transport-local, never compared across devices, and
    /// never on the wire. It is invisible because what a log or a screen shows
    /// of a connection is its *tail*, which is the framework's own name for it
    /// and carries none of this.
    init(_ name: String, over kind: NearbyLinkKind) {
        self.init("\(kind.rawValue)-\(name)")
    }
}

/// One connection that stands to one device, as the room considers it.
nonisolated struct NearbyCandidate: Equatable, Sendable {
    var connection: ConnectionID
    var peer: PeerDeviceID
    /// What the connection can say the device is called, where it can say
    /// anything. Never travels, and nothing keys on it.
    var name: String?
}

nonisolated extension NearbyCandidate {
    /// Every candidate, in the transport's own order — which is the order its
    /// connections were named in, the preferred path first.
    ///
    /// **Deterministic, because a redraw must not move a row and a resend must
    /// not change connections.** Two crossed connections to one device are the
    /// ordinary bring-up on either path, and the answer to "which one" has to
    /// be the same answer every time it is asked. Nothing here reads a link:
    /// this sorts opaque names, and the transport put its preference into them.
    static func ordered(_ candidates: [NearbyCandidate]) -> [NearbyCandidate] {
        candidates.sorted { $0.connection.rawValue < $1.connection.rawValue }
    }

    /// The devices these candidates reach, one row each, each carrying the one
    /// connection the room hands over for it — and no trace of what carried it.
    static func room(_ candidates: [NearbyCandidate]) -> [NearbyPeer] {
        var seen: Set<PeerDeviceID> = []
        return ordered(candidates).compactMap { candidate in
            guard seen.insert(candidate.peer).inserted else { return nil }
            return NearbyPeer(connection: candidate.connection, peer: candidate.peer,
                              name: candidate.name)
        }
    }
}

nonisolated extension NearbyPeer {
    /// What this row calls the device. Every row has words, and a row that has
    /// no name to show is the neutral label rather than anything of the
    /// transport's own.
    var label: NearbyLabel { NearbyLabel(name: name, peer: peer) }

    /// The room, from the three sources that know about it.
    ///
    /// **The pairing registry is a standing fact.** A paired device is in the
    /// room whether or not anything has dialled it and whatever the other
    /// device is doing, because that is what a pairing is. A list made of
    /// connections is empty at exactly the moment somebody opens the sheet to
    /// make one.
    ///
    /// **Discovery is a live fact.** A device that is not paired is in the room
    /// while it is on the network with its own player in nearby play, which is
    /// as long as it is advertising.
    ///
    /// **The connections are what a proposal travels**, and a device the
    /// transport is talking to has a row even where neither of the others has
    /// caught up with it.
    ///
    /// One device is one row: the merge is by the canonical identity, which the
    /// pairing mapping and the advertised identifier both answer with. A paired
    /// device whose linkage is not yet known is the one case that can stand
    /// twice — under its pairing record and under its advertisement — and it
    /// converges the first time a connection to it resolves, because the
    /// mapping that resolution writes outlives it.
    ///
    /// Ordered by the identity itself, which is durable, so the row somebody is
    /// about to press does not move under them.
    static func room(paired: [NearbyPeer], discovered: [NearbyPeer],
                     connected: [NearbyPeer]) -> [NearbyPeer] {
        var room: [PeerDeviceID: NearbyPeer] = [:]
        // Each source contributes what it alone knows, and the first name wins:
        // the registry's is the system's own record of a device somebody paired
        // deliberately, and the advertisement's is a label rather than a name.
        for device in paired + discovered + connected {
            let standing = room[device.peer]
            room[device.peer] = NearbyPeer(connection: device.connection ?? standing?.connection,
                                           peer: device.peer,
                                           name: standing?.name ?? device.name)
        }
        return room.values.sorted { $0.peer.rawValue < $1.peer.rawValue }
    }
}
