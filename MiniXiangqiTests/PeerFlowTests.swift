import Foundation
import Testing
@testable import MiniXiangqi

@MainActor
final class FakeCarrier: PeerCarrier {
    var isRunning = false
    var discovered: [NearbyPeer] = []
    let pairsOnArrival: Bool
    var interruption: LinkInterruption { pairsOnArrival ? .lasting : .passing }

    /// What stopping drops, as stopping Nearby closes its connections.
    var stopping: () -> Void = {}

    init(pairsOnArrival: Bool) { self.pairsOnArrival = pairsOnArrival }

    func start() { isRunning = true }
    func stop() {
        isRunning = false
        stopping()
    }
}

@Suite("Proposing and answering", .retiringItsCores, .serialized)
@MainActor
struct PeerFlowTests {
    private func online(over library: GameLibrary) -> (NearbyFlow, PeerEngine) {
        let engine = PeerEngine(mode: .online, library: library)
        let flow = NearbyFlow(engine: engine, carrier: FakeCarrier(pairsOnArrival: true),
                              positions: library.core.nearbyPositions, availability: { true })
        flow.proposesOnArrival = { true }
        return (flow, engine)
    }

    /// A Nearby sheet up, and a proposal from the device in the room.
    private func invited(over library: GameLibrary)
        -> (NearbyFlow, FakeCarrier, FakeLink, UUID) {
        let engine = PeerEngine(mode: .nearby, library: library)
        let carrier = FakeCarrier(pairsOnArrival: false)
        let flow = NearbyFlow(engine: engine, carrier: carrier,
                              positions: library.core.nearbyPositions, availability: { true })
        let link = FakeLink()
        carrier.stopping = { engine.closed(link) }
        flow.open(.xiangqi)
        engine.opened(link, peer: "B", name: "iPhone 5871")
        let game = UUID()
        engine.received(.propose(game: game, kind: .xiangqi, proposerSide: .red, seed: nil),
                        from: link)
        return (flow, carrier, link, game)
    }

    private func proposals(on link: FakeLink) -> Int {
        link.inFlight.filter { if case .propose = $0 { true } else { false } }.count
    }

    @Test("A friend still connected is proposed to again, and a fresh match re-arms the proposal")
    func aConnectedFriendIsProposedToAgain() throws {
        let (flow, engine) = online(over: try TestLibraries.fresh())
        let link = FakeLink()
        engine.opened(link, peer: "B", name: "B")

        flow.open(.xiangqi)
        #expect(proposals(on: link) == 1, "the sheet coming up proposes to the friend still here")
        let game = try #require(engine.outgoing?.game)
        engine.received(.decline(game: game, busy: false), from: link)
        #expect(flow.refusal == .declined)

        flow.dismissSheet()
        flow.open(.xiangqi)
        #expect(proposals(on: link) == 2, "raising the sheet again is a second try")

        engine.received(.decline(game: try #require(engine.outgoing?.game), busy: false),
                        from: link)
        let fresh = FakeLink()
        engine.opened(fresh, peer: "B", name: "B")
        #expect(proposals(on: fresh) == 1, "a new match with the same friend proposes again")
    }

    @Test("Cancelling the Save and Continue an acceptance needed declines the proposal")
    func cancellingTheRoomDeclines() throws {
        let library = try TestLibraries.fresh()
        try library.create(.freePlay(game: .miniXiangqi))
        library.endSession()
        let state = PlayState(library: library)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        let (flow, engine) = online(over: library)
        flow.room = state
        let link = FakeLink()
        engine.opened(link, peer: "B", name: "B")
        let game = UUID()
        engine.received(.propose(game: game, kind: .xiangqi, proposerSide: .red, seed: nil),
                        from: link)

        flow.accept()
        #expect(flow.invitation == nil, "the prompt does not come back while the room is asked for")
        state.dismissConfirmation()
        #expect(engine.incoming == nil)
        #expect(link.inFlight.last == .decline(game: game, busy: false))
    }

    // The sheet going away under the prompt is what iOS did when the prompt was
    // raised beneath it.
    @Test("An invitation outlives the sheet until it is answered", arguments: [true, false])
    func theInvitationOutlivesTheSheet(accepting: Bool) throws {
        let (flow, carrier, link, game) = invited(over: try TestLibraries.fresh())

        flow.dismissSheet()
        #expect(flow.invitation?.game == game, "the prompt keeps its proposal and its connection")

        if accepting {
            flow.accept()
            #expect(link.inFlight.last == .accept(game: game))
            #expect(flow.boardGame?.id == game)
        } else {
            flow.decline()
            #expect(link.inFlight.last == .decline(game: game, busy: false))
            #expect(!carrier.isRunning, "answered, nothing keeps Nearby up")
        }
    }

    @Test("The consent prompt names the device, the game and the side, with every format filled")
    func theInvitationReadsWhole() throws {
        let (flow, _, _, _) = invited(over: try TestLibraries.fresh())
        let message = try #require(flow.invitationMessage)
        #expect(message.hasPrefix("iPhone 5871 · \(GameKind.xiangqi.localizedName) · "))
        #expect(!message.contains("%"))
    }
}
