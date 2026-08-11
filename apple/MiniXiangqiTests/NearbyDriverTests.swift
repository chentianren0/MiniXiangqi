// The driver's plumbing: what it hands the engine, and what it does with the
// answers.
//
// The contract itself is pinned by the engine's own suite against the real
// core, so nothing here re-tests the protocol. What is left is exactly the
// glue: sends leaving in the order the engine made them and on the connection
// it named, an unreadable arrival becoming the violation that closes a
// connection, a connection's death reaching the engine, the resume a returning
// peer is owed being initiated without the driver deciding which sessions owe
// one, and the settling exchange an unsettled end opens on a connection that
// was standing all along.
//
// The rules are a stub rather than the core, because none of this is a question
// about a game — and because a driver test has to wait for a send task, which a
// test holding the singleton core must never do while another suite is running.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The nearby driver")
@MainActor
struct NearbyDriverTests {

    // MARK: - Order

    @Test("Sends leave in the order the engine made them, on the connection it named")
    func sendsKeepTheirOrder() async throws {
        let link = FakeLink(.first)
        let other = FakeLink(.second)
        let driver = driver(minting: "S-mine")

        driver.connectionReady(link, with: .peer)
        driver.connectionReady(other, with: .otherPeer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        try driver.play("b1b2", in: "S-mine")

        await settle { link.sent.count == 3 }
        #expect(link.sent == [.hello(.init(protocolVersion: 1)),
                              .propose(.init(session: "S-mine", rulesID: Stub.game,
                                             rulesVersion: Stub.version, proposerMoves: .first)),
                              .move(.init(session: "S-mine", index: 0, move: "b1b2"))])
        // The crossed connection to the other device carries its own hello and
        // nothing of this session.
        #expect(other.sent == [.hello(.init(protocolVersion: 1))])
    }

    @Test("A connection that is gone is not sent to")
    func nothingIsSentToADeadConnection() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        await settle { link.sent.count == 1 }

        driver.connectionDied(.first)
        // A proposal has nowhere to go, and the engine refuses it for a
        // connection it no longer holds.
        #expect(throws: BoardGameRefusal.unknownConnection) {
            try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        }
        await settle()
        #expect(link.sent == [.hello(.init(protocolVersion: 1))])
    }

    // MARK: - Unreadable

    @Test("An unreadable arrival is malformed, and the engine's close is performed")
    func unreadableClosesTheConnection() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        #expect(driver.sessions.count == 1)

        driver.receivedUnreadable(on: .first)

        #expect(link.isClosed)
        // The session the connection carried is void with it.
        #expect(driver.sessions.isEmpty)
        #expect(driver.peers[.first] == nil)
    }

    @Test("A message decoded from bytes no version knows is unreadable")
    func theCodecIsWhatCallsAMessageUnreadable() throws {
        // The transport sees whole messages, never bytes, so what "unreadable"
        // means at that seam is exactly what the codec refuses. This pins the
        // refusal that the transport turns into the driver's input.
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(BoardGameMessage.self,
                                     from: Data(#"{"greet":{"protocol":1}}"#.utf8))
        }
    }

    // MARK: - Death

    @Test("A connection's death reaches the engine, and the session it carried is interrupted")
    func deathReachesTheEngine() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)

        driver.connectionDied(.first)

        let session = try #require(driver.sessions.first)
        #expect(session.state == .active)
        // Interrupted rather than lost: bound to nothing until a resume
        // exchange re-binds it.
        #expect(session.connection == nil)
        #expect(driver.peers[.first] == nil)
    }

    @Test("An unanswered proposal dies with its connection, and owes no resume afterwards")
    func aProposalDiesWithItsConnection() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)

        driver.connectionDied(.first)
        #expect(driver.sessions.isEmpty)

        let fresh = FakeLink(.second)
        driver.connectionReady(fresh, with: .peer)
        await settle { fresh.sent.count == 1 }
        #expect(fresh.sent == [.hello(.init(protocolVersion: 1))])
    }

    // MARK: - Resume

    @Test("A fresh connection to a known peer initiates the interrupted session's resume")
    func aReturningPeerIsResumed() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        try driver.play("b1b2", in: "S-mine")
        driver.connectionDied(.first)

        let fresh = FakeLink(.second)
        driver.connectionReady(fresh, with: .peer)

        await settle { fresh.sent.count == 2 }
        // hello first, then the resume the contract says follows it.
        #expect(fresh.sent == [.hello(.init(protocolVersion: 1)),
                               .resume(.init(session: "S-mine", undos: 0, count: 1,
                                             keep: 1, end: nil))])
    }

    @Test("A session whose connection dies is resumed on the crossed one already standing")
    func theCrossedConnectionCarriesTheResume() async throws {
        let bound = FakeLink(.first)
        let crossed = FakeLink(.second)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(bound, with: .peer)
        driver.connectionReady(crossed, with: .peer)
        driver.received(.hello(.init()), on: .first)
        driver.received(.hello(.init()), on: .second)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        try driver.play("b1b2", in: "S-mine")

        // The connection the session was bound to goes; the other still stands,
        // and the interrupted session is owed its resume there rather than
        // waiting for a reconnection that has already happened.
        driver.connectionDied(.first)

        await settle { crossed.sent.count == 2 }
        #expect(crossed.sent == [.hello(.init(protocolVersion: 1)),
                                 .resume(.init(session: "S-mine", undos: 0, count: 1,
                                               keep: 1, end: nil))])
    }

    @Test("Where two crossed connections stand, the resume takes the one named first")
    func theResumeTakesTheTransportsOwnOrder() async throws {
        // **The ordering seam, from the side that has to be blind to it.** Three
        // connections to one device, and all this layer knows of any of them is
        // its name. The transport mints those names with its own preference in
        // front — so choosing the first name is choosing the path it would
        // rather use, and nothing here reads a link, asks what carries one, or
        // could be told.
        //
        // It is a real choice and not a tidy one: this device is the proposer,
        // so the connection its resume travels is the connection the exchange
        // *completes* on, and the other crossed one is refused for the rest of
        // the exchange. Which one it is decides what carries the rest of the
        // game.
        let overNetwork = FakeLink(ConnectionID("z", over: .network))
        let crossedRadio = FakeLink(ConnectionID("a", over: .radio))
        let bound = FakeLink(ConnectionID("m", over: .radio))
        let driver = driver(minting: "S-mine")
        for link in [overNetwork, crossedRadio, bound] {
            driver.connectionReady(link, with: .peer)
            driver.received(.hello(.init()), on: link.id)
        }
        // The game is proposed on neither of the two that will be left, so
        // nothing has resumed on either when the choice comes to be made.
        try driver.propose(to: .peer, on: bound.id, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: bound.id)
        try driver.play("b1b2", in: "S-mine")

        driver.connectionDied(bound.id)

        await settle { overNetwork.sent.count == 2 }
        #expect(overNetwork.sent == [.hello(.init(protocolVersion: 1)),
                                     .resume(.init(session: "S-mine", undos: 0, count: 1,
                                                   keep: 1, end: nil))],
                "the first name the transport minted is where the exchange goes")
        await settle()
        #expect(crossedRadio.sent == [.hello(.init(protocolVersion: 1))],
                "and the other crossed connection carries nothing of the exchange")
    }

    @Test("A healthy session is resumed on a new connection too — the accepted width, pinned")
    func aHealthySessionIsResumedOnANewConnection() async throws {
        // **This pins accepted behavior, not a defect.** Nothing has died here:
        // an active session, in play on a live connection, meets a second
        // connection to the same device — and the driver offers resume for it,
        // because the driver offers resume for every session it holds with a
        // peer and lets the engine refuse the ones that need none. The owner
        // ruled the width stands (2026-08-04, in #133's decided list):
        // connections idle out between moves, so reconnection-and-resume is the
        // protocol's everyday motion, and a crossed connection re-binding a
        // healthy session is that same motion. Narrowing it later is a real
        // change of behavior; this test is here so that change has to be a
        // visible, deliberate edit rather than a silent one.
        let bound = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(bound, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        try driver.play("b1b2", in: "S-mine")
        driver.received(.move(.init(session: "S-mine", index: 1, move: "b7b6")), on: .first)
        let healthy = try #require(driver.sessions.first)
        #expect(healthy.isInPlay)

        let fresh = FakeLink(.second)
        driver.connectionReady(fresh, with: .peer)

        await settle { fresh.sent.count == 2 }
        #expect(fresh.sent == [.hello(.init(protocolVersion: 1)),
                               .resume(.init(session: "S-mine", undos: 0, count: 2,
                                             keep: 2, end: nil))])
        // Until the exchange completes the session is gated — the contract's
        // "Neither peer sends a `move` for the session until it holds the
        // other's `resume`" — and it is this peer's turn, so the refusal is the
        // gate and nothing else.
        let gated = try #require(driver.sessions.first)
        #expect(gated.state == .active)
        #expect(gated.isLocalTurn)
        #expect(!gated.isInPlay)
        #expect(throws: BoardGameRefusal.notInPlay) { try driver.play("b1b3", in: "S-mine") }

        // The peer answers on the new connection, and the ordinary exchange
        // re-binds the session there, with its plies untouched.
        driver.received(.hello(.init()), on: .second)
        driver.received(.resume(.init(session: "S-mine", undos: 0, count: 2, keep: 2, end: nil)),
                        on: .second)
        let rebound = try #require(driver.sessions.first)
        #expect(rebound.connection == .second)
        #expect(rebound.isInPlay)
        #expect(rebound.plies == ["b1b2", "b7b6"])

        // Play goes on, on the connection the exchange chose. The proposer sent
        // its resume on exactly one connection, so the old one carried none.
        try driver.play("b1b3", in: "S-mine")
        await settle { fresh.sent.count == 3 }
        #expect(fresh.sent == [.hello(.init(protocolVersion: 1)),
                               .resume(.init(session: "S-mine", undos: 0, count: 2,
                                             keep: 2, end: nil)),
                               .move(.init(session: "S-mine", index: 2, move: "b1b3"))])
        #expect(bound.sent == [.hello(.init(protocolVersion: 1)),
                               .propose(.init(session: "S-mine", rulesID: Stub.game,
                                              rulesVersion: Stub.version, proposerMoves: .first)),
                               .move(.init(session: "S-mine", index: 0, move: "b1b2"))])
    }

    @Test("An ended session this peer has not settled is resumed too, stating its end")
    func anUnsettledEndIsResumed() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        try driver.resign(in: "S-mine")
        driver.connectionDied(.first)

        let fresh = FakeLink(.second)
        driver.connectionReady(fresh, with: .peer)

        await settle { fresh.sent.count == 2 }
        #expect(fresh.sent == [.hello(.init(protocolVersion: 1)),
                               .resume(.init(session: "S-mine", undos: 0, count: 0,
                                             keep: 0, end: .resign))])
    }

    // MARK: - Settling an end that happened on a live connection

    @Test("An end this device's own ply decided opens the settling exchange at once")
    func ourDecidingPlyIsSettledOnTheLiveConnection() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine", rules: Stub(decidingAfter: 1))
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        try driver.play("b1b2", in: "S-mine")

        let ended = try #require(driver.sessions.first)
        #expect(ended.state == .ended)
        #expect(!ended.settled, "this peer's own ply decided the end")

        // The ending ply, and behind it the exchange that settles it —
        // unprompted, on the connection the game was being played on.
        await settle { link.sent.count == 4 }
        #expect(link.sent == [.hello(.init(protocolVersion: 1)),
                              .propose(.init(session: "S-mine", rulesID: Stub.game,
                                             rulesVersion: Stub.version, proposerMoves: .first)),
                              .move(.init(session: "S-mine", index: 0, move: "b1b2")),
                              .resume(.init(session: "S-mine", undos: 0, count: 1,
                                            keep: 1, end: nil))])

        // The peer answers on that same connection and the exchange completes,
        // which is the whole of what settlement is — and what a finished game
        // waits for before the library files it.
        driver.received(.resume(.init(session: "S-mine", undos: 0, count: 1, keep: 1, end: nil)),
                        on: .first)
        #expect(driver.sessions.first?.settled == true)
        await settle()
        #expect(link.sent.count == 4, "a completed exchange asks for nothing more")
    }

    @Test("This device's resignation opens the settling exchange at once")
    func ourResignationIsSettledOnTheLiveConnection() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)

        try driver.resign(in: "S-mine")

        await settle { link.sent.count == 4 }
        #expect(link.sent == [.hello(.init(protocolVersion: 1)),
                              .propose(.init(session: "S-mine", rulesID: Stub.game,
                                             rulesVersion: Stub.version, proposerMoves: .first)),
                              .resign(.init(session: "S-mine")),
                              .resume(.init(session: "S-mine", undos: 0, count: 0,
                                            keep: 0, end: .resign))])
        #expect(driver.sessions.first?.settled == false)

        driver.received(.resume(.init(session: "S-mine", undos: 0, count: 0, keep: 0, end: nil)),
                        on: .first)
        #expect(driver.sessions.first?.settled == true)
    }

    @Test("This device's accepted draw opens the settling exchange at once")
    func ourAcceptedDrawIsSettledOnTheLiveConnection() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        driver.received(.offerDraw(.init(session: "S-mine", at: 0)), on: .first)

        try driver.acceptDraw(in: "S-mine")

        await settle { link.sent.count == 4 }
        #expect(link.sent == [.hello(.init(protocolVersion: 1)),
                              .propose(.init(session: "S-mine", rulesID: Stub.game,
                                             rulesVersion: Stub.version, proposerMoves: .first)),
                              .acceptDraw(.init(session: "S-mine")),
                              .resume(.init(session: "S-mine", undos: 0, count: 0,
                                            keep: 0, end: .acceptDraw))])
        #expect(driver.sessions.first?.settled == false)

        driver.received(.resume(.init(session: "S-mine", undos: 0, count: 0, keep: 0, end: nil)),
                        on: .first)
        #expect(driver.sessions.first?.settled == true)
    }

    @Test("An end with no connection to settle on opens nothing, and waits")
    func anEndWithNowhereToSettleWaits() async throws {
        let link = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(link, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        await settle { link.sent.count == 2 }
        driver.connectionDied(.first)

        // The terminal has nowhere to go and rides the next resume's `end`;
        // there is no connection to open that exchange on either, so this peer
        // waits for one exactly as an interrupted session does.
        try driver.resign(in: "S-mine")

        await settle()
        #expect(link.sent == [.hello(.init(protocolVersion: 1)),
                              .propose(.init(session: "S-mine", rulesID: Stub.game,
                                             rulesVersion: Stub.version, proposerMoves: .first))])
        let waiting = try #require(driver.sessions.first)
        #expect(waiting.state == .ended)
        #expect(!waiting.settled)
        #expect(waiting.exchange == nil)
    }

    @Test("A terminal taken mid-exchange is settled by the exchange that follows it")
    func aTerminalTakenMidExchangeIsSettledByTheNextOne() async throws {
        let bound = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(bound, with: .peer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .peer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)

        // A second connection to the same device puts an exchange in flight.
        let fresh = FakeLink(.second)
        driver.connectionReady(fresh, with: .peer)
        driver.received(.hello(.init()), on: .second)
        #expect(driver.sessions.first?.exchange != nil)

        // The player resigns while it is in flight. The terminal has no outlet
        // — the session is not in play — and the exchange already standing is
        // not one to open again, so nothing goes out for it here.
        try driver.resign(in: "S-mine")
        await settle { fresh.sent.count == 2 }
        #expect(fresh.sent == [.hello(.init(protocolVersion: 1)),
                               .resume(.init(session: "S-mine", undos: 0, count: 0,
                                             keep: 0, end: nil))])

        // The peer's answer completes that exchange, which sends the terminal
        // the resume could not state — and leaves the session ended, unsettled
        // and exchange-less, so the second exchange is opened for it at once.
        driver.received(.resume(.init(session: "S-mine", undos: 0, count: 0, keep: 0, end: nil)),
                        on: .second)
        await settle { fresh.sent.count == 4 }
        #expect(Array(fresh.sent.dropFirst(2))
                == [.resign(.init(session: "S-mine")),
                    .resume(.init(session: "S-mine", undos: 0, count: 0,
                                  keep: 0, end: .resign))])
        #expect(driver.sessions.first?.settled == false)

        // This peer's own resume stated the terminal this time, so completing
        // the exchange settles the session: two exchanges, and no third.
        driver.received(.resume(.init(session: "S-mine", undos: 0, count: 0, keep: 0, end: nil)),
                        on: .second)
        #expect(driver.sessions.first?.settled == true)
        await settle()
        #expect(fresh.sent.count == 4)
    }

    @Test("A session with another device is left alone by this one's return")
    func onlyThatDevicesSessionsAreResumed() async throws {
        let theirs = FakeLink(.first)
        let driver = driver(minting: "S-mine")
        driver.connectionReady(theirs, with: .otherPeer)
        driver.received(.hello(.init()), on: .first)
        try driver.propose(to: .otherPeer, on: .first, rulesID: Stub.game, proposerMoves: .first)
        driver.received(.accept(.init(session: "S-mine")), on: .first)
        driver.connectionDied(.first)

        let fresh = FakeLink(.second)
        driver.connectionReady(fresh, with: .peer)

        await settle { fresh.sent.count == 1 }
        #expect(fresh.sent == [.hello(.init(protocolVersion: 1))])
    }

    // MARK: - The launch arguments

    #if DEBUG
    @Test("The harness reads its launch arguments, and opens for nothing else")
    func theLaunchArgumentsAreRead() {
        #expect(NearbyLaunch(arguments: []) == NearbyLaunch(arguments: ["MiniXiangqi"]))
        #expect(!NearbyLaunch(arguments: ["MiniXiangqi"]).opensHarness)

        let launch = NearbyLaunch(arguments: ["MiniXiangqi", "-mxq-open-nearby",
                                              "-mxq-nearby-autostart",
                                              "-mxq-nearby-script", "b1b2, b7b6,"])
        #expect(launch.opensHarness)
        #expect(launch.autostarts)
        #expect(launch.script == ["b1b2", "b7b6"])
        #expect(launch.move(at: 0) == "b1b2")
        #expect(launch.move(at: 1) == "b7b6")
        #expect(launch.move(at: 2) == nil)
    }

    @Test("A script flag with nothing after it is no script")
    func anEmptyScriptIsNoScript() {
        #expect(NearbyLaunch(arguments: ["MiniXiangqi", "-mxq-nearby-script"]).script.isEmpty)
        #expect(NearbyLaunch(arguments: ["MiniXiangqi", "-mxq-nearby-script", ",, "]).script
                .isEmpty)
    }
    #endif

    // MARK: - The suite's own parts

    private func driver(minting session: String, rules: Stub = Stub()) -> NearbyDriver {
        NearbyDriver(rules: rules, log: NearbyLog(), sessionIDs: { session })
    }

    /// Lets the driver's per-connection send tasks run. They are main-actor
    /// tasks with nothing to wait on, so this is a handful of turns rather than
    /// a wait; the bound is there so a broken driver fails a test rather than
    /// hanging a run.
    private func settle(until reached: @MainActor () -> Bool = { false }) async {
        for _ in 0..<200 {
            if reached() { return }
            await Task.yield()
        }
    }
}

/// A connection that records instead of transmitting.
@MainActor
private final class FakeLink: NearbyLink {
    let id: ConnectionID
    private(set) var sent: [BoardGameMessage] = []
    private(set) var isClosed = false

    init(_ id: ConnectionID) { self.id = id }

    func send(_ message: BoardGameMessage) async throws { sent.append(message) }

    func close() { isClosed = true }
}

/// Rules enough to plumb against: one game, every move text lawful, and one
/// knob — the ply count at which the game is over. What a game's rules actually
/// say is asked of the core in the oracle's own suite, and what the engine does
/// with the answer is pinned in the engine's; the knob is here because a
/// rules-decided end is one of the two ways a peer is left holding a session
/// unsettled, and this suite deliberately has no core to reach one through.
private nonisolated struct Stub: BoardGameRules {
    static let game = "minixiangqi"
    static let version = "1"

    /// The count at which this game is decided, where it ever is. The mover of
    /// the last ply wins, so an end reached here is one that ply decided.
    var decidingAfter: Int?

    func version(of rulesID: String) -> String? {
        rulesID == Self.game ? Self.version : nil
    }

    func standing(after plies: [String], of rulesID: String) -> RulesStanding {
        guard let decidingAfter, !plies.isEmpty, plies.count >= decidingAfter else {
            return .ongoing
        }
        return .decided(.moverWins(Mover.atPly(plies.count - 1)), .checkmate)
    }

    func verdict(for text: String, after plies: [String], of rulesID: String) -> PlyVerdict {
        // A ply after the game is decided is unlawful, as the core's oracle
        // answers it, so no test can lean on play the engine would never see.
        guard case .ongoing = standing(after: plies, of: rulesID) else {
            return .unlawful
        }
        return .lawful(standing(after: plies + [text], of: rulesID))
    }
}

// MARK: - The transport's names, pinned for the suite

extension ConnectionID {
    fileprivate static let first = ConnectionID("connection-1")
    fileprivate static let second = ConnectionID("connection-2")
}

extension PeerDeviceID {
    fileprivate static let peer = PeerDeviceID("peer-device")
    fileprivate static let otherPeer = PeerDeviceID("other-peer-device")
}
