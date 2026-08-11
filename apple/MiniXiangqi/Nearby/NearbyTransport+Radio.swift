// The transport, as the nearby surfaces need it.
//
// The connection layer carries the protocol and knows nothing about a screen;
// what a screen needs is narrower and differently shaped — is this device
// capable of nearby play at all, is it running, and who is in the room. This is
// that view of it, written beside the transport rather than into it so the
// connection layer stays what the protocol contract describes and nothing more.

#if os(iOS)

import Foundation
import WiFiAware

extension NearbyTransport: NearbyRadio {
    /// Whether this hardware has Wi-Fi Aware. The type's own answer, as an
    /// instance question, because the surfaces hold a transport rather than a
    /// type.
    var isSupported: Bool { Self.isSupported }

    /// The devices in the room, one entry per *device*.
    ///
    /// **Three sources, one row each.** The system's pairing records are a
    /// standing fact about a pair of devices, true whether or not anything has
    /// dialled either of them — a list made of connections alone is empty at
    /// exactly the moment the propose sheet opens, which is the moment it is
    /// read. The advertisements are the devices whose players are in nearby
    /// play right now, which is what puts a device nobody has paired with in
    /// the room at all. The connections are what a proposal actually travels.
    ///
    /// A device that more than one of them knows about is one row, because they
    /// name it the same way: the identity a device sends for itself is what a
    /// connection is named by, what an advertisement carries, and what a
    /// pairing record maps to once any connection has resolved it.
    /// **The registry is where a device's name comes from**, out of both the
    /// places the system may hold one. It matters here and not only on a
    /// connection: the registry's row is the merge's first source, so a name
    /// resolved here is the name the row keeps whichever connection stands.
    /// Reading only the record's own `name` would leave the discoverable side
    /// of a pairing nameless in the registry, and its row would then take its
    /// words from whichever candidate was chosen — reading one way over the
    /// radio and another over the network, which is a row that changes under
    /// the reader for a reason no row may have.
    var peers: [NearbyPeer] {
        NearbyPeer.room(
            paired: pairedDevices.map {
                let pairing = nearbyPairingID(of: $0)
                return NearbyPeer(connection: nil,
                                  peer: NearbyIdentity.linked(to: pairing) ?? pairing,
                                  name: $0.displayName)
            },
            discovered: advertised,
            // Two crossed connections to one device are the ordinary bring-up
            // and both stay up, but they are one device to the person looking
            // at the list — and a proposal travels one of them, so exactly one
            // is handed over, chosen where choosing belongs.
            connected: NearbyCandidate.room(candidates))
    }
}

#endif
