// Two engines in one process over a fake link that drops, delays and reorders
// messages: the evidence that both devices record the same game.

import Foundation
import Testing
@testable import MiniXiangqi

/// One end of a fake connection: what its engine sent, not yet delivered.
@MainActor
final class FakeLink: PeerLink {
    var inFlight: [PeerMessage] = []

    func send(_ message: PeerMessage) { inFlight.append(message) }
    func close() {}
}

/// Two devices and the link between them. A proposes and plays Red.
@MainActor
final class TwoDevices {
    enum Device { case a, b }

    let a: PeerEngine
    let b: PeerEngine
    private(set) var game: UUID?

    /// The delivery at which the connection drops, losing what is in flight.
    var dropAt: Int?
    /// Whether a dropped connection's messages still arrive afterwards, on the
    /// dead link, behind the new connection's.
    var arriveLate = false
    /// Whether deliveries alternate between the two directions, or drain A's
    /// first.
    var alternate = false
    /// Whether everything in flight is delivered after each step, rather than
    /// only what the next step needs, which is what lets endings cross.
    var eager = false

    private var ends: (a: FakeLink, b: FakeLink)?
    private var late: [(to: PeerEngine, on: FakeLink, PeerMessage)] = []
    private(set) var deliveries = 0
    private var counting = false
    private var fromA = true

    init(core: Core, mode: PlayMode = .nearby) {
        a = PeerEngine(mode: mode, library: TestLibraries.another(over: core))
        b = PeerEngine(mode: mode, library: TestLibraries.another(over: core))
    }

    func engine(_ device: Device) -> PeerEngine { device == .a ? a : b }

    var isConnected: Bool { ends != nil }

    func connect() {
        let ends = (a: FakeLink(), b: FakeLink())
        self.ends = ends
        a.opened(ends.a, peer: "B", name: "B")
        b.opened(ends.b, peer: "A", name: "A")
        for (engine, link, message) in late { engine.received(message, from: link) }
        late = []
    }

    func drop() {
        guard let ends else { return }
        self.ends = nil
        if arriveLate {
            late += ends.a.inFlight.map { (b, ends.b, $0) } + ends.b.inFlight.map { (a, ends.a, $0) }
        }
        a.closed(ends.a)
        b.closed(ends.b)
    }

    /// One message delivered, or the planned drop. False when nothing is in
    /// flight.
    @discardableResult
    func deliverOne() -> Bool {
        guard let ends, !(ends.a.inFlight.isEmpty && ends.b.inFlight.isEmpty) else { return false }
        let sendingA = ends.b.inFlight.isEmpty || (!ends.a.inFlight.isEmpty && fromA)
        if alternate { fromA.toggle() }
        if counting {
            deliveries += 1
            if deliveries == dropAt {
                drop()
                return true
            }
        }
        if sendingA {
            b.received(ends.a.inFlight.removeFirst(), from: ends.b)
        } else {
            a.received(ends.b.inFlight.removeFirst(), from: ends.a)
        }
        return true
    }

    func deliverAll() {
        while deliverOne() {}
    }

    /// Everything delivered, over a new connection where the last one dropped.
    func settle() {
        while true {
            deliverAll()
            if isConnected { return }
            connect()
        }
    }

    /// A proposes, B accepts, and the count of deliveries starts from here.
    func start(_ kind: GameKind) {
        connect()
        a.propose(kind, side: .red, to: "B")
        deliverAll()
        b.accept()
        deliverAll()
        game = a.game?.id
        counting = true
    }

    /// Tries `act` until it holds, delivering one message at a time between
    /// tries and connecting again when nothing is left in flight.
    func until(_ act: () -> Bool) {
        for _ in 0..<500 {
            if act() { return }
            if deliverOne() { continue }
            if isConnected { break }
            connect()
        }
        Issue.record("a step never became possible")
    }

    func record(_ device: Device) throws -> GameRecord {
        let game = try #require(self.game)
        return try #require(try engine(device).library.record(game))
    }
}

/// One scripted game, as the two players play it.
struct Script: Sendable, CustomTestStringConvertible {
    enum Step: Sendable {
        /// The next move, by whichever device is to move.
        case move(String)
        case resign(TwoDevices.Device)
        /// Resigns too, where that device's game is still going.
        case alsoResign(TwoDevices.Device)
        /// The device to move claims the draw.
        case claim
        case agreeDraw(offeredBy: TwoDevices.Device)
        case takeBack(askedBy: TwoDevices.Device)
        /// Both resign before either hears of the other's.
        case bothResign
    }

    var name: String
    var kind: GameKind = .miniXiangqi
    var steps: [Step]
    /// The endings this game may end with, or nil where only agreement counts.
    var expected: [EndReason]?

    var testDescription: String { name }

    static let all: [Script] = [
        Script(name: "checkmate",
               steps: ["b1b3", "b7b6", "b3d3"].map(Step.move), expected: [.checkmate]),
        Script(name: "a checkmate crossing the loser's resignation",
               steps: ["b1b3", "b7b6", "b3d3"].map(Step.move) + [.alsoResign(.b)],
               expected: [.checkmate]),
        Script(name: "resign on turn",
               steps: [.move("b1b3"), .move("b7b6"), .resign(.a)], expected: [.resignation]),
        Script(name: "resign off turn",
               steps: [.move("b1b3"), .resign(.a)], expected: [.resignation]),
        Script(name: "the second player resigns",
               steps: [.move("b1b3"), .resign(.b)], expected: [.resignation]),
        Script(name: "agreed draw",
               steps: [.move("b1b3"), .move("b7b6"), .agreeDraw(offeredBy: .b)],
               expected: [.agreedDraw]),
        Script(name: "claimed draw",
               steps: ["b1b2", "b7b6", "b2b1", "b6b7", "b1b2", "b7b6", "b2b1", "b6b7"]
                   .map(Step.move) + [.claim],
               expected: [.threefoldRepetition]),
        Script(name: "takeback, then resign",
               steps: [.move("b1b3"), .move("b7b6"), .takeBack(askedBy: .b), .move("d6d5"),
                       .resign(.b)],
               expected: [.resignation]),
        Script(name: "a takeback accepted as its asker resigns",
               steps: [.move("b1b3"), .move("b7b6"), .takeBack(askedBy: .b), .resign(.b)],
               expected: [.resignation]),
        Script(name: "a draw accepted as its offerer resigns",
               steps: [.move("b1b3"), .move("b7b6"), .agreeDraw(offeredBy: .b), .alsoResign(.b)],
               expected: [.agreedDraw]),
        Script(name: "resignations that cross",
               steps: [.move("b1b3"), .move("b7b6"), .bothResign],
               expected: [.mutualResignation, .resignation]),
        Script(name: "a Gomoku five",
               kind: .gomoku15,
               steps: ["h8", "a1", "i8", "a3", "j8", "a5", "k8", "a7", "l8"].map(Step.move),
               expected: [.fiveInARow]),
    ]

    /// Plays the script, returning the number of deliveries it took.
    @MainActor
    @discardableResult
    func play(on devices: TwoDevices) -> Int {
        devices.start(kind)
        var ply = 0
        for step in steps {
            switch step {
            case .move(let move):
                let mover = devices.engine(ply.isMultiple(of: 2) ? .a : .b)
                devices.until { mover.play(move) }
                ply += 1
            case .resign(let device):
                devices.until { devices.engine(device).resign() }
            case .alsoResign(let device):
                devices.engine(device).resign()
            case .claim:
                let mover = devices.engine(ply.isMultiple(of: 2) ? .a : .b)
                devices.until { mover.claimDraw() }
            case .agreeDraw(let offerer):
                devices.until { answer(.draw, offeredBy: offerer, on: devices) }
            case .takeBack(let asker):
                devices.until { answer(.takeback, offeredBy: asker, on: devices) }
                ply -= 1
            case .bothResign:
                devices.until { devices.a.resign() && devices.b.resign() }
            }
            if devices.eager { devices.deliverAll() }
        }
        devices.settle()
        return devices.deliveries
    }

    /// The other device accepts once the offer stands with it; an offer a drop
    /// voided is made again.
    @MainActor
    private func answer(_ kind: PeerOffer.Kind, offeredBy offerer: TwoDevices.Device,
                        on devices: TwoDevices) -> Bool {
        let other = devices.engine(offerer == .a ? .b : .a)
        if other.game?.offer?.kind == kind, other.acceptOffer() { return true }
        devices.engine(offerer).offer(kind)
        return false
    }
}

@Suite("Two devices, one game", .retiringItsCores, .serialized)
@MainActor
struct PeerEngineTests {

    private func expectAgreement(_ devices: TwoDevices, _ script: Script,
                                 _ context: String) throws {
        let a = try devices.record(.a)
        let b = try devices.record(.b)
        #expect(a.endedAt != nil && b.endedAt != nil, "\(context): the game ended on both")
        #expect(a.moves == b.moves, "\(context): the same moves")
        #expect(a.takebacks == b.takebacks, "\(context): the same takebacks")
        #expect(a.result == b.result && a.reason == b.reason,
                "\(context): the same ending, \(String(describing: a.reason)) and \(String(describing: b.reason))")
        if let expected = script.expected, let reason = a.reason {
            #expect(expected.contains(reason), "\(context): ended by \(reason)")
        }
    }

    @Test("Both records end identically, wherever the connection drops", arguments: Script.all)
    func everyEndingAtEveryDropPoint(_ script: Script) throws {
        let core = try TestCores.fresh()
        for (alternate, eager) in [(false, false), (true, false), (false, true)] {
            let schedule = (alternate ? ", alternating" : "") + (eager ? ", eager" : "")
            let clean = TwoDevices(core: core)
            clean.alternate = alternate
            clean.eager = eager
            let deliveries = script.play(on: clean)
            try expectAgreement(clean, script, "no drop" + schedule)
            for dropAt in 1...max(deliveries, 1) {
                for arriveLate in [false, true] {
                    let devices = TwoDevices(core: core)
                    devices.alternate = alternate
                    devices.eager = eager
                    devices.dropAt = dropAt
                    devices.arriveLate = arriveLate
                    script.play(on: devices)
                    try expectAgreement(devices, script,
                                        "drop at \(dropAt)" + (arriveLate ? ", late" : "")
                                            + schedule)
                }
            }
        }
    }

    @Test("A resignation made with no connection reaches the other device on the next one")
    func anOfflineEndingIsDeliveredByResume() throws {
        let devices = TwoDevices(core: try TestCores.fresh())
        devices.start(.miniXiangqi)
        devices.a.play("b1b3")
        devices.deliverAll()
        devices.drop()

        #expect(devices.b.resign(), "resigning needs no connection")
        let b = try devices.record(.b)
        #expect(b.reason == .resignation && b.endingUndelivered,
                "written before it is sent, and marked undelivered")
        #expect(try devices.record(.a).endedAt == nil)

        devices.connect()
        devices.deliverAll()
        let a = try devices.record(.a)
        #expect(a.result == .redWins && a.reason == .resignation)
        #expect(!b.endingUndelivered, "the other device's resume showed it arrived")
    }

    @Test("A move lost in a drop arrives with the resume, and play goes on")
    func aLostMoveArrivesWithTheResume() throws {
        let devices = TwoDevices(core: try TestCores.fresh())
        devices.start(.miniXiangqi)
        devices.a.play("b1b3")
        devices.drop()
        #expect(devices.b.game?.inPlay == false)
        #expect(!devices.b.play("b7b6"), "nobody plays while the devices are apart")

        devices.connect()
        #expect(devices.a.game?.inPlay == false, "not until the other device's resume arrives")
        devices.deliverAll()
        #expect(try devices.record(.b).moves == ["b1b3"])
        #expect(devices.a.game?.inPlay == true && devices.b.game?.inPlay == true)
        #expect(devices.b.play("b7b6"))
    }

    @Test("An accepted takeback lost in a drop is applied by the resume")
    func aLostTakebackIsAppliedByTheResume() throws {
        let devices = TwoDevices(core: try TestCores.fresh())
        devices.start(.miniXiangqi)
        devices.a.play("b1b3")
        devices.deliverAll()
        #expect(devices.a.offer(.takeback))
        devices.deliverAll()
        #expect(devices.b.acceptOffer())
        devices.drop()
        #expect(try devices.record(.a).moves == ["b1b3"])

        devices.connect()
        devices.deliverAll()
        #expect(try devices.record(.a).moves == [])
        #expect(try devices.record(.a).takebacks == [0])
        #expect(devices.a.play("b1b2"), "and it is A's move again")
    }

    @Test("A game the other device gave up ends early here, saying so")
    func aGameGivenUpEndsEarly() throws {
        let devices = TwoDevices(core: try TestCores.fresh())
        devices.start(.miniXiangqi)
        devices.drop()
        devices.a.giveUp()
        try devices.a.library.change(try devices.record(.a)) { $0.end(.none, .endedEarly) }

        devices.connect()
        devices.deliverAll()
        let b = try devices.record(.b)
        #expect(b.reason == .endedEarly)
        #expect(devices.b.game?.voided == .lostByPeer)
    }

    @Test("A relaunched device resumes the game it holds")
    func aRelaunchResumes() throws {
        let devices = TwoDevices(core: try TestCores.fresh())
        devices.start(.miniXiangqi)
        devices.a.play("b1b3")
        devices.deliverAll()
        devices.drop()

        let relaunched = PeerEngine(mode: .nearby, library: devices.b.library)
        let link = (a: FakeLink(), b: FakeLink())
        devices.a.opened(link.a, peer: "B", name: "B")
        relaunched.opened(link.b, peer: "A", name: "A")
        for message in link.a.inFlight { relaunched.received(message, from: link.b) }
        for message in link.b.inFlight { devices.a.received(message, from: link.a) }
        #expect(relaunched.game?.inPlay == true)
        #expect(relaunched.play("b7b6"))
    }

    @Test("A move the rules refuse ends the game early on both devices")
    func anIllegalMoveEndsTheGame() throws {
        let devices = TwoDevices(core: try TestCores.fresh())
        devices.start(.miniXiangqi)
        let link = FakeLink()
        devices.b.opened(link, peer: "A", name: "A")
        devices.b.received(.move(game: try #require(devices.game), ply: 0, move: "a1a9"),
                           from: link)
        #expect(try devices.record(.b).reason == .endedEarly)
        #expect(devices.b.game?.voided == .disagreement)
        #expect(link.inFlight.last == .gone(game: try #require(devices.game)))
    }

    @Test("A Jieqi proposal carries the seed, and both devices deal the same game")
    func jieqiIsDealtFromTheSeed() throws {
        let devices = TwoDevices(core: try TestCores.fresh())
        devices.start(.jieqi)
        let a = try devices.record(.a)
        let b = try devices.record(.b)
        #expect(a.setup != nil)
        #expect(a.setup == b.setup)
        #expect(a.localSide == .red && b.localSide == .black)
    }

    @Test("A second proposal while one stands is answered busy")
    func theFirstProposalWins() throws {
        let core = try TestCores.fresh()
        let devices = TwoDevices(core: core)
        devices.connect()
        let third = FakeLink()
        devices.b.opened(third, peer: "C", name: "C")
        devices.a.propose(.xiangqi, side: .red, to: "B")
        devices.deliverAll()
        let game = UUID()
        devices.b.received(.propose(game: game, kind: .renju, proposerSide: .red, seed: nil),
                           from: third)
        #expect(third.inFlight == [.decline(game: game, busy: true)])
        #expect(devices.b.incoming?.peer == "A")
    }
}
