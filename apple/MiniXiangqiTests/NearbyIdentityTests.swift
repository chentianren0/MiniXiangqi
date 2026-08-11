// Who a device is to another device.
//
// The protocol asks its transport for one identity per peer — the same across a
// relaunch, the same behind every connection whatever carries it, unchanged
// while a session stands. Everything here is that promise: an identifier minted
// once and kept, an identity a connection is named by rather than guessed at,
// and the mapping that lets a paired device be one row before anything has
// dialled it.
//
// The resolution is asserted over a fake exchange rather than a connection,
// because it is the step that stands between a connection becoming usable and
// the driver being told of it, and nothing about it needs a radio or a network
// to be true.
//
// Nothing here writes the standard database: a hosted unit run would otherwise
// be writing the identity of the application on this machine.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The nearby identity")
@MainActor
struct NearbyIdentityTests {

    // MARK: - This device

    @Test("An identifier is minted once and is the same answer ever after")
    func oneInstallHasOneIdentifier() throws {
        try withDefaults { defaults in
            let minted = NearbyIdentity.own(in: defaults)
            #expect(!minted.isEmpty)
            #expect(NearbyIdentity.own(in: defaults) == minted, "and it is kept, not re-minted")
            #expect(defaults.string(forKey: NearbyIdentity.identifierKey) == minted,
                    "under the key it is stored by")
        }
    }

    @Test("Two installations are two identities")
    func eachInstallIsItsOwn() throws {
        try withDefaults { first in
            try withDefaults { second in
                #expect(NearbyIdentity.own(in: first) != NearbyIdentity.own(in: second))
            }
        }
    }

    @Test("A canonical identity cannot be spelled the way a pairing record is")
    func theTwoKindsOfIdentityCannotCollide() {
        #expect(NearbyIdentity.peer("9F3C") == PeerDeviceID("device-9F3C"))
        #expect(NearbyIdentity.peer("9F3C").rawValue.hasPrefix("device-"))
        #expect(!NearbyIdentity.peer("9F3C").rawValue.hasPrefix("wifi-aware-device-"))
    }

    // MARK: - What a device is called where it has no name

    @Test("The label is a kind and four characters, and never a device's name")
    func theLabelSaysNothingPersonal() {
        let identifier = "9F3C1D2E-4B5A-6789-ABCD-EF0123456A1B"
        #expect(NearbyIdentity.tail(of: identifier) == "6A1B")
        #expect(NearbyIdentity.label(for: identifier, kind: "iPhone") == "iPhone 6A1B")
        // A kind on its own, where an identifier has nothing to take a tail
        // from, rather than a label made of something else.
        #expect(NearbyIdentity.label(for: "", kind: "iPad") == "iPad")
    }

    // MARK: - The pairing mapping

    @Test("What stands behind a pairing is remembered, and a changed identifier replaces it")
    func theMappingIsLearnedAndReplaced() throws {
        try withDefaults { defaults in
            let pairing = PeerDeviceID("wifi-aware-device-7")
            #expect(NearbyIdentity.linked(to: pairing, in: defaults) == nil,
                    "nothing is known about a pairing nothing has connected over")

            NearbyIdentity.link(pairing, to: "9F3C", in: defaults)
            #expect(NearbyIdentity.linked(to: pairing, in: defaults)
                    == NearbyIdentity.peer("9F3C"))

            // Saying the same thing again says nothing new.
            NearbyIdentity.link(pairing, to: "9F3C", in: defaults)
            #expect(NearbyIdentity.linked(to: pairing, in: defaults)
                    == NearbyIdentity.peer("9F3C"))

            // A reinstall is a new identity behind the same pairing, and the
            // newer answer is the true one.
            NearbyIdentity.link(pairing, to: "A17B", in: defaults)
            #expect(NearbyIdentity.linked(to: pairing, in: defaults)
                    == NearbyIdentity.peer("A17B"))
        }
    }

    @Test("One pairing's mapping is not another's")
    func mappingsAreHeldPerPairing() throws {
        try withDefaults { defaults in
            NearbyIdentity.link(PeerDeviceID("wifi-aware-device-1"), to: "AAA", in: defaults)
            NearbyIdentity.link(PeerDeviceID("wifi-aware-device-2"), to: "BBB", in: defaults)

            #expect(NearbyIdentity.linked(to: PeerDeviceID("wifi-aware-device-1"), in: defaults)
                    == NearbyIdentity.peer("AAA"))
            #expect(NearbyIdentity.linked(to: PeerDeviceID("wifi-aware-device-2"), in: defaults)
                    == NearbyIdentity.peer("BBB"))
        }
    }

    // MARK: - Settling one connection

    @Test("This device says who it is, and the peer's answer is what the connection is named by")
    func theExchangeNamesTheConnection() async throws {
        try await withDefaults { defaults in
            let exchange = FakeExchange(answering: "9F3C")
            let pairing = PeerDeviceID("wifi-aware-device-7")

            let peer = await NearbyIdentity.resolve(over: exchange, pairing: pairing,
                                                    within: .seconds(8), in: defaults)

            #expect(peer == NearbyIdentity.peer("9F3C"),
                    "the identity that arrived, never the pairing record")
            #expect(exchange.said == [NearbyIdentity.own(in: defaults)],
                    "and this device said its own, once")
            #expect(exchange.asked == 1,
                    "asked once: a peer cannot re-identify itself mid-connection")
            #expect(NearbyIdentity.linked(to: pairing, in: defaults)
                    == NearbyIdentity.peer("9F3C"),
                    "learned over the pairing it arrived on, for the next time")
        }
    }

    @Test("A connection that never says who it is names nobody")
    func silenceIsNoIdentity() async throws {
        try await withDefaults { defaults in
            let exchange = FakeExchange(answering: nil)
            let pairing = PeerDeviceID("wifi-aware-device-7")

            let peer = await NearbyIdentity.resolve(over: exchange, pairing: pairing,
                                                    within: .seconds(8), in: defaults)

            // Nothing is handed over and nothing is remembered: the transport
            // drops such a connection rather than opening it under some other
            // name, because a peer named two ways destroys games.
            #expect(peer == nil)
            #expect(NearbyIdentity.linked(to: pairing, in: defaults) == nil)
        }
    }

    @Test("A link that cannot even be spoken on names nobody")
    func aDyingLinkNamesNobody() async throws {
        try await withDefaults { defaults in
            let exchange = FakeExchange(answering: "9F3C")
            exchange.fails = true

            #expect(await NearbyIdentity.resolve(over: exchange, pairing: nil,
                                                 within: .seconds(8), in: defaults) == nil)
            #expect(exchange.waited == nil, "nothing is waited for on a link already gone")
        }
    }

    @Test("A connection with no pairing behind it is named all the same")
    func anUnpairedConnectionIsNamedToo() async throws {
        try await withDefaults { defaults in
            let exchange = FakeExchange(answering: "A17B")

            let peer = await NearbyIdentity.resolve(over: exchange, pairing: nil,
                                                    within: .seconds(8), in: defaults)

            #expect(peer == NearbyIdentity.peer("A17B"),
                    "one mechanism names a peer, whichever path carried it")
        }
    }

    @Test("The exchange is idempotent: running it again settles on the same identity")
    func aSecondExchangeChangesNothing() async throws {
        try await withDefaults { defaults in
            let pairing = PeerDeviceID("wifi-aware-device-7")
            let first = await NearbyIdentity.resolve(over: FakeExchange(answering: "9F3C"),
                                                     pairing: pairing, within: .seconds(8),
                                                     in: defaults)
            let again = await NearbyIdentity.resolve(over: FakeExchange(answering: "9F3C"),
                                                     pairing: pairing, within: .seconds(8),
                                                     in: defaults)

            #expect(first == again)
            #expect(NearbyIdentity.linked(to: pairing, in: defaults) == first)
        }
    }

    // MARK: - The suite's own parts

    /// A scratch preferences domain of this test's own, so that a run writes
    /// neither the application's identity nor another test's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "com.chentianren.MiniXiangqi.tests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let name = "com.chentianren.MiniXiangqi.tests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }
}

/// The two things the transport does with a connection before it decides what
/// is behind it, without a connection.
@MainActor
private final class FakeExchange: NearbyLinkageExchange {
    /// What the other device says for itself, or nothing at all.
    private let answer: String?
    /// Whether this device can speak on the link at all.
    var fails = false

    private(set) var said: [String] = []
    private(set) var waited: Duration?
    /// How many times the peer's identity was asked for. Once per connection is
    /// the rule: a peer says who it is, and what it says after that is not a
    /// second answer.
    private(set) var asked = 0

    init(answering answer: String?) { self.answer = answer }

    func sendLinkage(_ identifier: String) async throws {
        if fails { throw CancellationError() }
        said.append(identifier)
    }

    func linkageArrived(within window: Duration) async -> String? {
        waited = window
        asked += 1
        return answer
    }
}
