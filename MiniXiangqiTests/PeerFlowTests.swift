import Foundation
import Testing
@testable import MiniXiangqi

@MainActor
final class FakeCarrier: PeerCarrier {
    var isRunning = false
    var discovered: [NearbyPeer] = []
    let pairsOnArrival: Bool
    var interruption: LinkInterruption { pairsOnArrival ? .lasting : .passing }

    init(pairsOnArrival: Bool) { self.pairsOnArrival = pairsOnArrival }

    func start() { isRunning = true }
    func stop() { isRunning = false }
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
}
