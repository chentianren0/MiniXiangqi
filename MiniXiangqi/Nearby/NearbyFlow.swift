// Playing somebody on another device, as the person in front of the screen
// meets it: whether the row is offered, the propose sheet, the consent prompt,
// the refusal, and the board.
//
// One flow per way of reaching the other device: Nearby and Online are two
// instances over two carriers, and nothing above the carrier tells them apart.

import Foundation
import Observation

/// One device that could be invited.
nonisolated struct NearbyPeer: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var connected = false
}

/// What reaches the other device, as the flow needs it.
@MainActor
protocol PeerCarrier: AnyObject {
    var isRunning: Bool { get }
    /// Devices this carrier can see without a connection: Nearby's browse.
    var discovered: [NearbyPeer] { get }
    /// Whether whoever connects is the friend the player already chose, so the
    /// game goes to them without a press: Online. Nearby lists a room to pick
    /// from instead.
    var pairsOnArrival: Bool { get }
    var interruption: LinkInterruption { get }
    func start()
    func stop()
}

/// What a lost connection means on a carrier: Nearby finds the other device
/// again by itself; Online waits for the two players to invite each other.
nonisolated enum LinkInterruption: Equatable, Sendable {
    case passing, lasting

    var messageKey: String {
        switch self {
        case .passing: "nearby.connecting"
        case .lasting: "online.interrupted"
        }
    }
}

/// Why a proposal did not become a game.
nonisolated enum NearbyRefusal: Equatable, Sendable {
    case declined, busy, notNow

    var messageKey: String {
        switch self {
        case .declined: "nearby.refusal.declined"
        case .busy: "nearby.refusal.busy"
        case .notNow: "nearby.refusal.notNow"
        }
    }
}

@MainActor
@Observable
final class NearbyFlow {
    let engine: PeerEngine
    let carrier: any PeerCarrier
    let positions: any NearbyPositions
    var mode: PlayMode { engine.mode }

    private let availability: @MainActor () -> Bool
    var isAvailable: Bool { availability() }

    /// The library's one active game, to make room in and come back to.
    weak var room: (any NearbyRoom)?

    /// Whether this device proposes the moment the friend arrives, where the
    /// carrier pairs on arrival: the device that brought them.
    @ObservationIgnored var proposesOnArrival: @MainActor () -> Bool = { false }

    private(set) var proposing: GameKind?
    private(set) var boardGameID: UUID?
    var proposerSide: Side = .red
    var chosenPeer: String?
    private(set) var refusal: NearbyRefusal?
    private(set) var dismissedResultOf: UUID?

    /// The proposal whose acceptance is waiting for room in the library.
    private var answering: UUID?
    private var orientations: [UUID: Bool] = [:]
    /// Peers a proposal went to on arrival, while they stay connected.
    private var offeredTo: Set<String> = []

    init(engine: PeerEngine, carrier: any PeerCarrier, positions: any NearbyPositions,
         availability: @escaping @MainActor () -> Bool) {
        self.engine = engine
        self.carrier = carrier
        self.positions = positions
        self.availability = availability
        engine.started = { [weak self] id in self?.openBoard(id) }
        engine.declined = { [weak self] busy in self?.refusal = busy ? .busy : .declined }
        engine.arrived = { [weak self] peer in
            self?.offeredTo.remove(peer)
            self?.roomChanged(arrival: true)
        }
        engine.delivered = { [weak self] in self?.restIfIdle() }
    }

    // MARK: - What the surfaces read

    /// Every device that could be invited: the carrier's own sightings and every
    /// connected one, one row each.
    var peers: [NearbyPeer] {
        var rows = carrier.discovered
        for (id, name) in engine.connected {
            if let index = rows.firstIndex(where: { $0.id == id }) {
                rows[index].connected = true
            } else {
                rows.append(NearbyPeer(id: id, name: name, connected: true))
            }
        }
        return rows
    }

    /// The row pressed, or else the first connected device.
    var chosenDevice: NearbyPeer? {
        peers.first { $0.id == chosenPeer } ?? peers.first { $0.connected } ?? peers.first
    }

    var canInvite: Bool { chosenDevice?.connected == true }

    /// The proposal waiting for this player, unless they have answered it.
    var invitation: PeerProposal? {
        engine.incoming.flatMap { $0.game == answering ? nil : $0 }
    }

    var invited: PeerProposal? { engine.outgoing }

    var boardGame: PeerGame? {
        engine.game.flatMap { $0.id == boardGameID ? $0 : nil }
    }

    /// The name a peer gave, for the consent prompt.
    func name(of peer: String) -> String {
        peers.first { $0.id == peer }?.name ?? String(localized: "nearby.unnamedDevice")
    }

    /// The sheet is up to reach the other player of a game already going, so
    /// there is no side to choose.
    var isMeetingAgain: Bool {
        guard let proposing else { return false }
        return room?.standingGame(in: mode) == proposing
    }

    // MARK: - Navigation

    /// A row on the Play home: back into this game going in this mode, or the
    /// sheet that proposes one, once the library has room.
    func open(_ game: GameKind) {
        wake()
        if room?.standingGame(in: mode) == game {
            reenter(game)
        } else {
            makingRoom(for: game) { [weak self] in self?.raiseSheet(for: game) }
        }
    }

    /// The sheet comes up afresh: a friend still connected from before gets
    /// the proposal at once.
    private func raiseSheet(for game: GameKind) {
        proposing = game
        offeredTo = []
        roomChanged(arrival: false)
    }

    /// Back into the game in play. Its board opens where the other device comes
    /// back by itself or is still here; otherwise the sheet that brings them.
    func reenter(_ game: GameKind) {
        wake()
        guard let id = engine.takeUpStoredGame() else { return }
        if carrier.interruption == .passing || engine.game?.linked == true {
            openBoard(id)
        } else {
            raiseSheet(for: game)
        }
    }

    func openBoard(_ id: UUID) {
        proposing = nil
        offeredTo = []
        boardGameID = id
        wake()
    }

    func dismissSheet() {
        proposing = nil
        engine.withdraw()
        restIfIdle()
    }

    func leaveBoard() {
        boardGameID = nil
        engine.letGo()
        restIfIdle()
    }

    // MARK: - Proposing and answering

    func invite(_ device: NearbyPeer, to game: GameKind) {
        if !engine.propose(game, side: proposerSide, to: device.id) { refusal = .notNow }
    }

    /// The sheet is up and somebody arrived, or the sheet just came up. The game
    /// the two were already playing opens; otherwise, where the carrier pairs
    /// on arrival, the proposal goes out: on arrival from the device that
    /// brought the friend, and from whichever device raised the sheet.
    private func roomChanged(arrival: Bool) {
        guard let game = proposing else { return }
        if room?.standingGame(in: mode) == game {
            if engine.game?.linked == true, let id = engine.game?.id { openBoard(id) }
            return
        }
        guard carrier.pairsOnArrival, !arrival || proposesOnArrival(), invited == nil,
              let device = chosenDevice, device.connected, !offeredTo.contains(device.id)
        else { return }
        offeredTo.insert(device.id)
        invite(device, to: game)
    }

    /// Accepting makes room first: an accepted proposal is a game that needs
    /// somewhere to be recorded.
    func accept() {
        guard let proposal = engine.incoming else { return }
        answering = proposal.game
        makingRoom(for: proposal.kind) { [weak self] in
            guard let self else { return }
            answering = nil
            if engine.accept(proposal.game) { openBoard(proposal.game) } else { refusal = .notNow }
        } otherwise: { [weak self] in
            self?.answering = nil
            self?.engine.decline()
        }
    }

    func decline() {
        engine.decline()
    }

    func dismissRefusal() {
        refusal = nil
    }

    func dismissResult(of game: UUID) {
        dismissedResultOf = game
    }

    func orientation(of game: UUID) -> Bool? {
        orientations[game]
    }

    func setOrientation(_ flipped: Bool, of game: UUID) {
        orientations[game] = flipped
    }

    private func makingRoom(for game: GameKind, _ opening: @escaping @MainActor () -> Void,
                            otherwise: @escaping @MainActor () -> Void = {}) {
        guard let room else { return opening() }
        room.makeRoom(for: game, in: mode, then: opening, otherwise: otherwise)
    }

    // MARK: - The carrier

    /// The carrier runs while a surface is up, a game is going in this mode, or
    /// an ending is still owed to the other device.
    private var needsCarrier: Bool {
        proposing != nil || boardGameID != nil || room?.standingGame(in: mode) != nil
            || engine.owesEndings
    }

    private func wake() {
        guard isAvailable, !carrier.isRunning else { return }
        carrier.start()
    }

    private func restIfIdle() {
        guard carrier.isRunning, !needsCarrier else { return }
        carrier.stop()
    }

    /// At launch the carrier comes up only to deliver an ending still owed:
    /// continuing a game waits for the player to come back to it.
    func launched() {
        if engine.owesEndings { wake() }
    }

    /// Back in front: the carrier comes up again where something needs it. A
    /// listener or browser the background ended restarts by itself.
    func returnedToForeground() {
        if needsCarrier { wake() }
    }

    /// The library is about to file the game in play as ended early.
    func giveUpActiveGame() {
        engine.giveUp()
        if boardGameID != nil { leaveBoard() }
    }
}
