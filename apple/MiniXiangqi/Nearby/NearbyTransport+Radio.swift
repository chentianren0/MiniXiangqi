// The Wi-Fi Aware transport, as the nearby surfaces need it.
//
// The connection layer is the protocol's binding and knows nothing about a
// screen; what a screen needs is narrower and differently shaped — is the radio
// here at all, is it running, and who is in the room. This is that view of it,
// written beside the transport rather than into it so the binding stays what the
// protocol contract describes and nothing more.

#if os(iOS)

import Foundation

extension NearbyTransport: NearbyRadio {
    /// Whether this hardware has Wi-Fi Aware. The type's own answer, as an
    /// instance question, because the surfaces hold a radio rather than a type.
    var isSupported: Bool { Self.isSupported }

    /// The devices in the room, one entry per *device*.
    ///
    /// Two crossed connections to one device are the binding's ordinary
    /// bring-up and both stay up, but they are one device to the person looking
    /// at the list — and a proposal travels one of them, so the list hands over
    /// exactly one. Ordered by the connection's own name so the row a person is
    /// about to press does not move under them.
    var peers: [NearbyPeer] {
        var seen: Set<PeerDeviceID> = []
        return connections
            .filter(\.isReady)
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .compactMap { connection in
                guard let peer = connection.peer, seen.insert(peer).inserted else {
                    return nil
                }
                return NearbyPeer(connection: connection.id, peer: peer,
                                  name: connection.peerName)
            }
    }
}

#endif
