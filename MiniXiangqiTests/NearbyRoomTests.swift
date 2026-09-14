// Who is in the room, and which connection a game would travel.
//
// docs/interaction-design.md, "Nearby play": the room is everybody there is to
// play with, each one row, one device; a device that is both paired and on the
// network is one row and not two; and no row says which of the two it is. Every
// claim here is one of those sentences, decided without a radio, a network or a
// device, because the merge and the order do not need one.
//
// The last of them is the one worth stating out loud: **a row cannot tell you
// what carried it**. The transport knows, and spends what it knows naming its
// connections; what comes out of the choosing is a device and a connection, and
// two candidates that differ only in their path produce the same row.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The nearby room")
struct NearbyRoomTests {

    // MARK: - The sources

    @Test("A paired device is in the room before anybody dials it")
    func theRegistryIsAStandingFact() {
        // The state the sheet is opened in: the two devices are paired, and the
        // transport has only just been woken, so nothing is dialled yet.
        let paired = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-2"),
                                name: "Their iPad")

        #expect(NearbyPeer.room(paired: [paired], discovered: [], connected: []) == [paired])
    }

    @Test("A device on the network nobody has paired with is a row of its own")
    func anUnpairedDeviceIsInTheRoom() {
        // Nameless, because names do not travel and the words a stranger
        // advertises are not put in front of a reader either.
        let advertised = NearbyPeer(connection: nil, peer: NearbyIdentity.peer("A17B"),
                                    name: nil)

        let room = NearbyPeer.room(paired: [], discovered: [advertised], connected: [])

        #expect(room == [advertised])
        #expect(room.first?.label == .unnamed(tail: "A17B"),
                "and it carries the one neutral label, told apart by its identity")
    }

    @Test("A device the registry and a connection both know is one row, carrying the connection")
    func theRoomJoinsItsSourcesPerDevice() {
        let peer = NearbyIdentity.peer("9F3C")
        let registry = NearbyPeer(connection: nil, peer: peer, name: "Their iPhone")
        let live = NearbyPeer(connection: ConnectionID("c-1"), peer: peer, name: "iPhone 9F3C")

        let room = NearbyPeer.room(paired: [registry], discovered: [], connected: [live])

        #expect(room.count == 1, "one device is one row, whatever knows about it")
        #expect(room.first?.connection == ConnectionID("c-1"),
                "and the row carries the connection a proposal would travel")
        #expect(room.first?.name == "Their iPhone",
                "under the name the system's own pairing record gives it")
    }

    @Test("A paired device that is also on the network is one row and not two")
    func theLinkageIsWhatMakesOneRow() {
        // The pairing record's row is under the identity the mapping learned
        // over an earlier connection, which is the same identity the
        // advertisement carries. That is the whole of why they merge.
        let peer = NearbyIdentity.peer("9F3C")
        let paired = NearbyPeer(connection: nil, peer: peer, name: "Their iPad")
        let advertised = NearbyPeer(connection: nil, peer: peer, name: nil)

        let room = NearbyPeer.room(paired: [paired], discovered: [advertised], connected: [])

        #expect(room.count == 1)
        #expect(room.first?.name == "Their iPad",
                "under the name the pairing record gives it, which is the better of the two")
    }

    @Test("A paired device whose linkage is not known yet stands under its pairing record")
    func thePairingRecordIsTheFallback() {
        // Nothing has connected over the pairing, so nothing knows the identity
        // behind it, and the row is the pairing's own. The advertisement beside
        // it is a second row until a connection resolves them — which is what
        // the stored mapping is for.
        let pairing = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-2"),
                                 name: "Their iPad")
        let advertised = NearbyPeer(connection: nil, peer: NearbyIdentity.peer("9F3C"),
                                    name: nil)

        let room = NearbyPeer.room(paired: [pairing], discovered: [advertised], connected: [])

        #expect(room.count == 2, "two rows, honestly, until one connection settles it")
    }

    @Test("The room holds a connected device neither of the other sources has")
    func aConnectedDeviceIsAlwaysInTheRoom() {
        let live = NearbyPeer(connection: ConnectionID("c-1"),
                              peer: NearbyIdentity.peer("A17B"), name: "iPhone A17B")

        #expect(NearbyPeer.room(paired: [], discovered: [], connected: [live]) == [live])
    }

    @Test("The room's order is the devices' own, so a row does not move under a press")
    func theRoomIsOrderedByTheDurableIdentity() {
        let second = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-2"),
                                name: "B")
        let first = NearbyPeer(connection: ConnectionID("c-9"),
                               peer: PeerDeviceID("wifi-aware-device-1"), name: "A")

        #expect(NearbyPeer.room(paired: [second], discovered: [], connected: [first])
                .map(\.peer) == [first.peer, second.peer])
        // The same room however the sources happen to be ordered.
        #expect(NearbyPeer.room(paired: [second, first], discovered: [], connected: [])
                .map(\.peer) == [first.peer, second.peer])
    }

    // MARK: - What a row calls a device

    @Test("A device's own name is what the system holds, and the ceremony's name saves the rest")
    func theNameIsResolvedFromBothPlacesTheSystemKeepsOne() {
        // The record's own name, where the pairing left one there — which is
        // the side that went looking for the other device.
        #expect(NearbyDeviceName.resolved(name: "Their iPad", pairingName: "Their iPad")
                == "Their iPad")
        // And the ceremony's, where it did not — which is the side that merely
        // made itself discoverable, and whose rows would otherwise all be
        // nameless.
        #expect(NearbyDeviceName.resolved(name: nil, pairingName: "Their iPad")
                == "Their iPad")
        // Blank is missing, in either place: a row of spaces reads as a fault
        // rather than as a device.
        #expect(NearbyDeviceName.resolved(name: "   ", pairingName: "Their iPad")
                == "Their iPad")
        #expect(NearbyDeviceName.resolved(name: "  Their iPad  ", pairingName: nil)
                == "Their iPad")
        #expect(NearbyDeviceName.resolved(name: "", pairingName: " ") == nil)
        #expect(NearbyDeviceName.resolved(name: nil, pairingName: nil) == nil)
    }

    @Test("A named device's row is its name")
    func aNamedDeviceIsCalledByItsName() {
        let device = NearbyPeer(connection: nil, peer: NearbyIdentity.peer("9F3C1D2E"),
                                name: "Their iPad")

        #expect(device.label == .named("Their iPad"))
        #expect(device.label.text == "Their iPad")
    }

    @Test("A device with no name is the one neutral label, and never an identifier")
    func anUnnamedDeviceIsCalledTheNeutralLabel() {
        for name in [nil, "", "   "] {
            let paired = NearbyPeer(connection: nil,
                                    peer: PeerDeviceID("wifi-aware-device-2"), name: name)

            #expect(paired.label == .unnamed(tail: nil),
                    "a pairing record's own number is the system's bookkeeping, not a row")
            // The two things a row must never be: the identity, and the words
            // inside it, which name a way of reaching a device.
            #expect(paired.label.text != paired.peer.rawValue)
            #expect(!paired.label.text.contains("wifi-aware"))
            #expect(!paired.label.text.isEmpty)
        }
    }

    @Test("A row's words do not change with the connection that stands")
    func aRowReadsTheSameOverEitherPath() {
        // The consequence of getting the sources' order or their contents
        // wrong, stated as the rule it breaks. The registry is where a name
        // comes from and it is the merge's first source; a connection carries a
        // name only where its own path has one to give — a radio connection has
        // the pairing record behind it, a network connection has nothing it
        // would be safe to show — so a row that took its words from whichever
        // connection was chosen would read one way over one path and another
        // over the other, for a reason the reader can neither see nor act on.
        let peer = NearbyIdentity.peer("9F3C1D2E")
        let registry = NearbyPeer(connection: nil, peer: peer, name: "Their iPhone")
        let overRadio = NearbyPeer(connection: ConnectionID("c-1"), peer: peer,
                                   name: "Their iPhone")
        let overNetwork = NearbyPeer(connection: ConnectionID("c-2"), peer: peer, name: nil)

        let radio = NearbyPeer.room(paired: [registry], discovered: [], connected: [overRadio])
        let network = NearbyPeer.room(paired: [registry], discovered: [],
                                      connected: [overNetwork])

        #expect(radio.first?.label == .named("Their iPhone"))
        #expect(network.first?.label == radio.first?.label)
        // And the connection each row carries is still its own path's.
        #expect(radio.first?.connection == ConnectionID("c-1"))
        #expect(network.first?.connection == ConnectionID("c-2"))
    }

    @Test("Where two devices have no name, four characters of the identity tell them apart")
    func unnamedDevicesAreStillDistinguishable() {
        let here = NearbyPeer(connection: nil, peer: NearbyIdentity.peer("1111-AAAA"),
                              name: nil)
        let there = NearbyPeer(connection: nil, peer: NearbyIdentity.peer("2222-BBBB"),
                               name: nil)

        #expect(here.label == .unnamed(tail: "AAAA"))
        #expect(there.label == .unnamed(tail: "BBBB"))
        #expect(here.label.text != there.label.text)
        // The same words in both, with only the four characters differing:
        // there is one neutral label, not a family of them.
        #expect(here.label.text.hasSuffix(" AAAA"))
        #expect(there.label.text.hasSuffix(" BBBB"))
        #expect(here.label.text.dropLast(5) == there.label.text.dropLast(5))
    }

    // MARK: - Which connection

    @Test("The transport's preference is in the name it mints, ahead of the name itself")
    func theOrderIsMintedIntoTheIdentifier() {
        // **The whole mechanism, in one line.** The transport is the only layer
        // that knows there are two paths, and the only thing it does with that
        // knowledge is name its connections: the preferred path's name sorts
        // first, whatever the framework called the connection underneath. Every
        // chooser downstream — the room here, the driver's settling pick — is a
        // blind sort of opaque strings, and there is no second place where the
        // two paths could fall out of step.
        #expect(ConnectionID("z", over: .network).rawValue
                < ConnectionID("a", over: .radio).rawValue,
                "the path decides before the framework's own name is even looked at")
        // Within one path the framework's name decides, so two crossed
        // connections order the same way every time they are asked.
        #expect(ConnectionID("a", over: .network).rawValue
                < ConnectionID("z", over: .network).rawValue)
        // And nothing a reader ever sees carries it. **The names the framework
        // actually hands out are one or two characters** — `1`, `2`, `3` in
        // order per process, as a driven run's own log lines show — so a reader
        // is protected by `name` stripping the rank and by nothing else. These
        // are those names, not a long fixture that would hide the question.
        #expect(ConnectionID("1", over: .network).name == "1")
        #expect(ConnectionID("1", over: .radio).name == "1")
        #expect(ConnectionID("12", over: .radio).name == "12")
        #expect(ConnectionID("1", over: .radio).name == ConnectionID("1", over: .network).name,
                "the two paths' connections read alike, which is the whole promise")
        // An identifier that never went through the mint is its own name.
        #expect(ConnectionID("staged-connection").name == "staged-connection")
        #expect(ConnectionID("c-1").name == "c-1")
    }

    @Test("Where a device is reachable both ways, the network is the one handed over")
    func theNetworkIsPreferred() {
        let peer = NearbyIdentity.peer("9F3C")
        // The radio's connection has the name that would sort first if the
        // framework's own names were all there was to sort.
        let overRadio = NearbyCandidate(connection: ConnectionID("a", over: .radio),
                                        peer: peer, name: "Their iPad")
        let overNetwork = NearbyCandidate(connection: ConnectionID("z", over: .network),
                                          peer: peer, name: "iPad 9F3C")

        // Whichever order they were found in.
        for candidates in [[overRadio, overNetwork], [overNetwork, overRadio]] {
            #expect(NearbyCandidate.ordered(candidates) == [overNetwork, overRadio])
            #expect(NearbyCandidate.room(candidates)
                    == [NearbyPeer(connection: ConnectionID("z", over: .network), peer: peer,
                                   name: "iPad 9F3C")],
                    "one row, and the connection on it is the network's")
        }
    }

    @Test("Two connections of one kind are ordered by the connection's own name")
    func crossedConnectionsAreOrderedDeterministically() {
        let peer = NearbyIdentity.peer("9F3C")
        let incoming = NearbyCandidate(connection: ConnectionID("c-1", over: .network),
                                       peer: peer, name: nil)
        let outgoing = NearbyCandidate(connection: ConnectionID("c-2", over: .network),
                                       peer: peer, name: nil)

        #expect(NearbyCandidate.ordered([outgoing, incoming]) == [incoming, outgoing])
        #expect(NearbyCandidate.room([outgoing, incoming]).first?.connection
                == ConnectionID("c-1", over: .network),
                "so the row does not change under a redraw")
    }

    @Test("Each device gets its own row, and each row its own device's connection")
    func everyDeviceIsChosenFor() {
        let here = NearbyIdentity.peer("AAA")
        let there = NearbyIdentity.peer("BBB")
        let candidates = [
            NearbyCandidate(connection: ConnectionID("c-1", over: .radio), peer: here,
                            name: "Their iPad"),
            NearbyCandidate(connection: ConnectionID("c-2", over: .network), peer: there,
                            name: "iPhone BBB"),
        ]

        // Two devices, two rows, each carrying its own device's connection. The
        // order they come out in is the candidates' — which row is drawn where
        // is the room's own question, and `NearbyPeer.room` answers it by the
        // durable identity.
        let rows = NearbyCandidate.room(candidates)
        #expect(rows.count == 2)
        #expect(rows.first { $0.peer == here }?.connection
                == ConnectionID("c-1", over: .radio))
        #expect(rows.first { $0.peer == there }?.connection
                == ConnectionID("c-2", over: .network))
    }

    @Test("A row cannot say what carried it")
    func theRowSaysNothingAboutThePath() {
        // The same device, reached the two ways. The two connections are named
        // differently — that is where the transport's own preference lives —
        // and what the room hands over is the same row all the same, because a
        // row has nowhere to put the difference and nothing above the transport
        // is given it.
        let peer = NearbyIdentity.peer("9F3C")
        let overRadio = NearbyCandidate(connection: ConnectionID("c-1", over: .radio),
                                        peer: peer, name: "Their iPad")
        let overNetwork = NearbyCandidate(connection: ConnectionID("c-1", over: .network),
                                          peer: peer, name: "Their iPad")

        let radioRow = NearbyCandidate.room([overRadio])
        let networkRow = NearbyCandidate.room([overNetwork])
        #expect(radioRow.map(\.peer) == networkRow.map(\.peer))
        #expect(radioRow.map(\.label) == networkRow.map(\.label))
        #expect(radioRow.map(\.name) == networkRow.map(\.name))
    }
}
