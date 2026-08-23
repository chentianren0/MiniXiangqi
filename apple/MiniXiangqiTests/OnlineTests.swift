// The Game Center layer's own decisions, and none of GameKit's.
//
// What this transport actually decides is small and load-bearing: when a
// connection is handed to the driver, what happens to what arrives before that,
// whether a payload's refusal is a violation or a death, what a peer is called,
// and that a match never comes back under a name a connection has already had.
// Every one of those is reachable by calling the connection's own inputs, which
// is why they are written as inputs rather than as GameKit callbacks — the
// callbacks reduce GameKit's objects to exactly these values and do nothing
// else.
//
// **Nothing here simulates GameKit and nothing here tests it.** There is no
// stand-in for a `GKMatch`, a `GKPlayer` or a delegate queue: what a match does
// is Apple's, what two signed-in devices do is stage 5's driven runs, and a
// simulation of either would prove only that the simulation matches the belief
// that built it.
//
// The driver underneath is the real one, because the outcomes that tell the
// classification apart are its and the engine's: a violation leaves no session,
// and a death leaves the session standing and interrupted. A fake driver could
// only record which method was called, which is the thing under test restated.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("Online play over Game Center")
@MainActor
struct OnlineTests {

    // MARK: - Ingress: readiness, the buffer, and the order

    @Test("What arrives before the driver is told waits, and arrives in order")
    func arrivalsBeforeReadyWaitAndKeepTheirOrder() throws {
        let (transport, driver) = madeTransport()
        let match = FakeMatch()
        let connection = transport.open(over: match)

        // Both land in the instant between the match becoming usable and the
        // driver being told of it — which is a real instant here, because
        // GameKit may deliver the other player's opening messages before it
        // reports that the player connected.
        connection.payloadArrived(try payload(.hello(.init())))
        connection.payloadArrived(try payload(.propose(.init(session: "S-theirs",
                                                             rulesID: OnlineStub.game,
                                                             rulesVersion: OnlineStub.version,
                                                             proposerMoves: .first))))
        #expect(driver.sessions.isEmpty, "the driver has not been told of the connection yet")

        connection.becameUsable(reaching: .friend, named: "Wei")

        // One session, which is all three promises at once. Dropped, and there
        // would be none; delivered early, the engine would have had no
        // connection to hold them against and there would be none; delivered
        // out of order, a message before the peer's hello is a violation and
        // there would be none — and the match would have been disconnected.
        #expect(driver.peers[connection.id] == .friend)
        #expect(driver.sessions.count == 1)
        #expect(driver.sessions.first?.state == .proposed)
        #expect(!match.isDisconnected)
    }

    @Test("A match names its player once, and a second naming changes nothing")
    func aSecondNamingIsRefused() async throws {
        let (transport, driver) = madeTransport()
        let match = FakeMatch()
        let connection = transport.open(over: match)
        connection.becameUsable(reaching: .friend, named: "Wei")
        await settle { match.sent.count == 1 }

        // Every real match reaches this twice: adoption names the player where
        // GameKit has already delivered one, and GameKit reports that same
        // player connecting a moment later, through the hop.
        connection.becameUsable(reaching: .otherFriend, named: "Lan")

        // The driver refuses a second open of one connection whatever this
        // does, so it goes on holding the first peer — which is exactly why the
        // naming has to be refused *here* as well. Renamed, the room would show
        // one player while the driver routed to another, and what the driver
        // routes by peer is the resume a session is owed.
        #expect(connection.peer == .friend)
        #expect(connection.peerName == "Wei")
        #expect(driver.peers[connection.id] == .friend)
        #expect(transport.peers.first?.peer == .friend)
        #expect(transport.peers.first?.name == "Wei")
    }

    @Test("A payload the codec refuses is a violation, not a death")
    func aRefusedPayloadVoidsTheSession() async throws {
        let (transport, driver) = madeTransport()
        let match = FakeMatch()
        let connection = try await inPlay(over: match, on: transport, driver: driver)

        connection.payloadArrived(Data(#"{"greet":{"protocol":1}}"#.utf8))

        // Malformed is a protocol violation, so the connection closes and the
        // session is **void**. Classifying it as a death instead would leave
        // both peers holding a game one of them had already broken, waiting to
        // resume it.
        #expect(driver.sessions.isEmpty)
        #expect(driver.peers[connection.id] == nil)
        #expect(match.isDisconnected)
    }

    @Test("A player who disconnects is a death, and the session survives it")
    func aPlayerLeavingInterruptsRatherThanVoids() async throws {
        let (transport, driver) = madeTransport()
        let match = FakeMatch()
        let connection = try await inPlay(over: match, on: transport, driver: driver)

        connection.playerLeft()

        // GameKit's receive path never throws, so this callback is the whole of
        // what says a connection ended: without it the driver would go on
        // holding a link to somebody who has gone. And a death is the *other*
        // side of the split — the game is interrupted and resumable, which is
        // what the disconnect notice promises the player.
        #expect(driver.sessions.count == 1)
        #expect(driver.sessions.first?.state == .active)
        #expect(driver.sessions.first?.connection == nil, "interrupted, not bound")
        #expect(driver.peers[connection.id] == nil)
        #expect(transport.connections.isEmpty)
    }

    @Test("A match that fails is a death too")
    func aFailedMatchInterruptsRatherThanVoids() async throws {
        let (transport, driver) = madeTransport()
        let match = FakeMatch()
        let connection = try await inPlay(over: match, on: transport, driver: driver)

        connection.matchFailed("the network went away")

        // The second of the two things GameKit says about the match itself.
        // Reading it as a refusal instead would void a game that nobody played
        // wrongly.
        #expect(driver.sessions.count == 1)
        #expect(driver.sessions.first?.state == .active)
        #expect(driver.peers[connection.id] == nil)
    }

    @Test("A match that never reached anybody tells the driver nothing")
    func aMatchThatFailedEarlyIsNoDeath() {
        let (transport, driver) = madeTransport()
        let connection = transport.open(over: FakeMatch())

        connection.matchFailed("nobody ever connected")

        // The driver was never handed this connection, so there is no death to
        // report for it — but the transport must still let go, or a match that
        // reaches nobody would sit in the room for the rest of the launch.
        #expect(driver.peers.isEmpty)
        #expect(driver.sessions.isEmpty)
        #expect(transport.connections.isEmpty)
    }

    // MARK: - Sending, and closing

    @Test("A message goes out as its own JSON and nothing else")
    func aMessageIsItsOwnBytes() async throws {
        let (transport, driver) = madeTransport()
        let match = FakeMatch()
        let connection = transport.open(over: match)
        connection.becameUsable(reaching: .friend, named: "Wei")

        // The hello the engine opens every connection with.
        await settle { match.sent.count == 1 }
        #expect(try match.messages == [.hello(.init())])
        // Byte for byte what `BoardGameMessage` composes: this transport wraps
        // nothing around it. A frame here would be a second wire format for one
        // protocol, defined in a second place.
        #expect(match.sent.first == (try payload(.hello(.init()))))
        #expect(driver.sessions.isEmpty)
    }

    @Test("Closing lets go of the match, and nothing is sent over it afterwards")
    func closingTearsTheMatchDown() async throws {
        let (transport, _) = madeTransport()
        let match = FakeMatch()
        let connection = transport.open(over: match)
        connection.becameUsable(reaching: .friend, named: "Wei")
        await settle { match.sent.count == 1 }

        connection.close()

        // A close verdict that left the match standing would leave the other
        // player in a match with somebody who has stopped answering, and with
        // nothing to tell them so.
        #expect(match.isDisconnected)
        #expect(transport.connections.isEmpty)
        await #expect(throws: (any Error).self) {
            try await connection.send(.hello(.init()))
        }
    }

    // MARK: - Names

    @Test("Every match is a name no connection of this process has had")
    func namesAreNeverReused() throws {
        let (transport, driver) = madeTransport()
        let first = transport.open(over: FakeMatch())
        first.becameUsable(reaching: .friend, named: "Wei")
        first.playerLeft()

        // The same friend, come back on a fresh invitation — which is the only
        // way back, online play having no rediscovery.
        let second = transport.open(over: FakeMatch())
        second.becameUsable(reaching: .friend, named: "Wei")

        // The engine holds a precondition on connection identifiers, and a
        // reattachment that came back under the old name would be a new
        // connection it believed it already had — with a session still bound to
        // the dead one.
        #expect(first.id != second.id)
        #expect(driver.peers[second.id] == .friend)
        #expect(driver.peers[first.id] == nil)
    }

    @Test("An online peer is a Game Center player, in a namespace of its own")
    func onlineIdentityCannotCollideWithANearbyOne() {
        let identifier = "A:_1a2b3c4d5e"
        let peer = OnlineIdentity.peer(identifier)

        #expect(peer.rawValue == "game-center-\(identifier)")
        #expect(!peer.rawValue.hasPrefix(NearbyIdentity.peerPrefix))
        // The same string under the two transports is two peers, which is what
        // keeps a Game Center account and an install of this app from ever
        // being spelled the same way. Spelled alike, one peer would be named
        // two things — which the engine answers by destroying a game.
        #expect(NearbyIdentity.peer(identifier) != peer)
        // And the four-character tail is not an online peer's: it exists for a
        // device with no name at all, and Game Center always supplies one.
        #expect(NearbyIdentity.tail(ofPeer: peer) == nil)
    }

    // MARK: - The room

    @Test("The room is the players a match has actually reached")
    func theRoomListsWhoAMatchReaches() {
        let (transport, _) = madeTransport()
        #expect(!transport.hasRadio, "there is no pairing radio behind Game Center")
        #expect(transport.peers.isEmpty)

        let connection = transport.open(over: FakeMatch())
        // A match with nobody behind it yet is not a row: a row is something a
        // proposal can travel, and this one has no peer to name.
        #expect(transport.peers.isEmpty)

        connection.becameUsable(reaching: .friend, named: "Wei")

        #expect(transport.peers.count == 1)
        #expect(transport.peers.first?.peer == .friend)
        #expect(transport.peers.first?.connection == connection.id)
        #expect(transport.peers.first?.name == "Wei",
                "the name is Game Center's own, shown as it comes")
    }

    @Test("Leaving the surfaces does not end a match")
    func stoppingKeepsTheMatch() {
        let (transport, _) = madeTransport()
        let match = FakeMatch()
        let connection = transport.open(over: match)
        connection.becameUsable(reaching: .friend, named: "Wei")

        transport.start()
        transport.start()
        #expect(transport.isRunning)
        transport.stop()
        transport.stop()
        #expect(!transport.isRunning)

        // Nearby tears its connections down with its bracket because its
        // devices find each other again by themselves. Online has no
        // rediscovery at all, so a match dropped because a screen closed is a
        // game neither player could ever pick up again.
        #expect(!match.isDisconnected)
        #expect(transport.connections.count == 1)
        #expect(transport.peers.count == 1)
    }

    // MARK: - Whether the row stands at all

    @Test("Online play stands only where Game Center could carry a game")
    func availabilityHonoursBothHalvesOfTheRule() {
        #expect(GameCenterAvailability.stands(authenticated: true,
                                              multiplayerRestricted: false))
        #expect(!GameCenterAvailability.stands(authenticated: false,
                                               multiplayerRestricted: false))
        // The Screen Time clause, which is a parental control rather than a
        // preference of ours and one of the obligations this feature was
        // accepted with. Dropping it would offer the row on a device where
        // multiplayer gaming is restricted — the exact case the contract says
        // the row is absent for.
        #expect(!GameCenterAvailability.stands(authenticated: true,
                                               multiplayerRestricted: true))
        #expect(!GameCenterAvailability.stands(authenticated: false,
                                               multiplayerRestricted: true))
    }

    // MARK: - The suite's own parts

    private func madeTransport() -> (OnlineTransport, NearbyDriver) {
        let log = NearbyLog()
        let driver = NearbyDriver(rules: OnlineStub(), log: log,
                                  sessionIDs: { "S-mine" })
        return (OnlineTransport(driver: driver, log: log), driver)
    }

    /// A connection with a game being played over it, reached the way the two
    /// devices reach it: everything the other peer says arrives as bytes on the
    /// wire, so the decode this suite is about is on the path.
    private func inPlay(over match: FakeMatch, on transport: OnlineTransport,
                        driver: NearbyDriver) async throws -> OnlineConnection {
        let connection = transport.open(over: match)
        connection.becameUsable(reaching: .friend, named: "Wei")
        connection.payloadArrived(try payload(.hello(.init())))
        try driver.propose(to: .friend, on: connection.id, rulesID: OnlineStub.game,
                           proposerMoves: .first)
        connection.payloadArrived(try payload(.accept(.init(session: "S-mine"))))
        await settle { match.sent.count == 2 }
        #expect(driver.sessions.first?.state == .active)
        return connection
    }

    private func payload(_ message: BoardGameMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    /// Lets the driver's per-connection send tasks run. They are main-actor
    /// tasks with nothing to wait on, so this is a handful of turns rather than
    /// a wait; the bound is there so a broken transport fails a test rather
    /// than hanging a run.
    private func settle(until reached: @MainActor () -> Bool = { false }) async {
        for _ in 0..<200 {
            if reached() { return }
            await Task.yield()
        }
    }
}

/// A match that records instead of transmitting.
@MainActor
private final class FakeMatch: OnlineMatchChannel {
    private(set) var sent: [Data] = []
    private(set) var isDisconnected = false

    func sendReliably(_ payload: Data) throws { sent.append(payload) }
    func disconnect() { isDisconnected = true }

    /// What was sent, as the messages they are — which is also the assertion
    /// that they are readable at all by the codec that composed them.
    var messages: [BoardGameMessage] {
        get throws {
            try sent.map { try JSONDecoder().decode(BoardGameMessage.self, from: $0) }
        }
    }
}

/// Rules enough to let the engine hold a proposal, and nothing more.
///
/// Deliberately not the driver suite's own stub: that one carries a knob for
/// the ply at which a game is decided, because a rules-decided end is one of
/// the two ways a peer is left unsettled, and this suite never reaches an end
/// at all. What a game's rules actually say is asked of the core in the
/// oracle's suite; nothing here is a question about a game.
private nonisolated struct OnlineStub: BoardGameRules {
    static let game = "minixiangqi"
    static let version = "1"

    func version(of rulesID: String) -> String? {
        rulesID == Self.game ? Self.version : nil
    }

    /// The one game this stub carries freezes its start, so no session over it
    /// opens with the deal handshake.
    func dealsItsStart(_ rulesID: String) -> Bool { false }

    func deal(seed: String, nonce: String, of rulesID: String) -> BoardGameDeal? { nil }

    func standing(after plies: [String], from start: String?,
                  of rulesID: String) -> RulesStanding { .ongoing }

    func verdict(for text: String, after plies: [String], from start: String?,
                 of rulesID: String) -> PlyVerdict { .lawful(.ongoing) }
}

extension PeerDeviceID {
    /// The other player, named the way Game Center names one.
    fileprivate static let friend = OnlineIdentity.peer("A:_1a2b3c4d5e")
    /// Somebody else, for the case that must not be able to rename a player a
    /// connection has already been opened under.
    fileprivate static let otherFriend = OnlineIdentity.peer("A:_9f8e7d6c5b")
}
