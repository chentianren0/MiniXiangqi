// Nearby's carrier on iPhone, iPad and Mac alike: a Bonjour registration this
// device answers on, a browse for everybody else's, and TCP between them, with
// peer-to-peer Wi-Fi included so two devices find each other without a shared
// network. Network.framework's Coder frames each message on the connection and
// encodes it as JSON.
//
// Each install has its own id, carried in the TXT record and in the hello that
// opens every connection. The device with the smaller id dials, so a pair has
// one connection. The advertised name is the kind of device and four characters
// of the id, never the system's device name, which is often its owner's.
//
// It runs while the flow keeps it up: from a user action or a return to the
// foreground, so the local-network prompt appears in front of somebody who has
// just asked for Nearby Play.

import Foundation
import Network
import Observation
#if canImport(UIKit)
import UIKit
#endif

private typealias Channel = NetworkConnection<Coder<PeerMessage, PeerMessage, NetworkJSONCoder>>

@MainActor
@Observable
final class NearbyNetwork: PeerCarrier {
    static let service = "_boardgame._tcp"

    private let engine: PeerEngine
    @ObservationIgnored private let id: String
    @ObservationIgnored private let name: String

    private(set) var isRunning = false
    private(set) var discovered: [NearbyPeer] = []

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var connections: [NearbyConnection] = []
    @ObservationIgnored private var endpoints: [String: Bonjour.Endpoint] = [:]
    @ObservationIgnored private var dialing: Set<String> = []

    var pairsOnArrival: Bool { false }
    var interruption: LinkInterruption { .passing }

    init(engine: PeerEngine, defaults: UserDefaults = .standard) {
        self.engine = engine
        if let stored = defaults.string(forKey: "nearby.identifier") {
            id = stored
        } else {
            id = UUID().uuidString
            defaults.set(id, forKey: "nearby.identifier")
        }
        #if canImport(UIKit)
        let kind = UIDevice.current.model
        #else
        let kind = "Mac"
        #endif
        name = "\(kind) \(id.filter(\.isHexDigit).suffix(4).uppercased())"
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        NearbyLogger.note("Nearby is on as \(name).")
        tasks = [Task { await listen() }, Task { await browse() }]
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        tasks.forEach { $0.cancel() }
        tasks = []
        connections.forEach { $0.close() }
        endpoints = [:]
        discovered = []
    }

    private static func parameters()
        -> NWParametersBuilder<Coder<PeerMessage, PeerMessage, NetworkJSONCoder>> {
        .parameters {
            Coder(receiving: PeerMessage.self, sending: PeerMessage.self,
                  using: NetworkJSONCoder()) {
                // A device that walks away or is suspended sends no FIN. The
                // keepalive and the retransmission limit end such a link within
                // seconds, so the device with the smaller id dials again.
                TCP()
                    .keepalive(idleTimeInSeconds: 5, count: 3, intervalInSeconds: 2)
                    .retransmitConnectionDropTime(15)
            }
        }
        .peerToPeerIncluded(true)
    }

    private func listen() async {
        while !Task.isCancelled {
            do {
                try await NetworkListener(
                    for: .bonjour(name: name, type: Self.service, domain: nil,
                                  txtRecord: NWTXTRecord(["id": id])),
                    using: Self.parameters()
                )
                // Awaited inside: returning early tears the connection down.
                .run { [self] channel in await run(NearbyConnection(channel)) }
            } catch {
                NearbyLogger.note("The listener ended: \(error)")
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func browse() async {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        while !Task.isCancelled {
            do {
                try await NetworkBrowser(
                    for: .bonjour(Self.service, domain: nil, includeTxtRecord: true),
                    using: parameters
                )
                .run { [self] found in saw(found) }
            } catch {
                NearbyLogger.note("The browser ended: \(error)")
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func saw(_ found: [Bonjour.Endpoint]) {
        var latest: [String: Bonjour.Endpoint] = [:]
        var peers: [NearbyPeer] = []
        for endpoint in found {
            guard let peer = endpoint.txtRecord["id"], !peer.isEmpty, peer != id,
                  latest[peer] == nil else { continue }
            latest[peer] = endpoint
            peers.append(NearbyPeer(id: peer, name: endpoint.name))
        }
        endpoints = latest
        discovered = peers.sorted { $0.name < $1.name }
        dialAll()
    }

    /// The smaller id dials every device it sees and is not talking to.
    private func dialAll() {
        guard isRunning else { return }
        for (peer, endpoint) in endpoints
        where id < peer && !dialing.contains(peer) && engine.connected[peer] == nil {
            dialing.insert(peer)
            Task {
                await run(NearbyConnection(Channel(to: endpoint, using: Self.parameters())))
                dialing.remove(peer)
                try? await Task.sleep(for: .seconds(2))
                dialAll()
            }
        }
    }

    private func run(_ connection: NearbyConnection) async {
        connections.append(connection)
        await connection.run(engine: engine, hello: .hello(peer: id, name: name))
        connections.removeAll { $0 === connection }
    }
}

/// One TCP connection, from its hello to its end.
@MainActor
private final class NearbyConnection: PeerLink {
    private var channel: Channel?
    private var life: Task<Void, Never>?
    private let outbox: AsyncStream<PeerMessage>.Continuation
    private let queued: AsyncStream<PeerMessage>

    init(_ channel: Channel) {
        self.channel = channel
        (queued, outbox) = AsyncStream.makeStream()
    }

    func send(_ message: PeerMessage) {
        outbox.yield(message)
    }

    /// Letting go of the connection is what cancels it.
    func close() {
        life?.cancel()
    }

    func run(engine: PeerEngine, hello: PeerMessage) async {
        guard let channel else { return }
        let task = Task { await live(channel, engine: engine, hello: hello) }
        life = task
        await task.value
        self.channel = nil
    }

    private func live(_ channel: Channel, engine: PeerEngine, hello: PeerMessage) async {
        // A failed connection does not always end the receive loop on its own,
        // so its state ends it.
        channel.onStateUpdate { [weak self] _, state in
            switch state {
            case .failed, .cancelled, .waiting:
                Task { @MainActor in self?.close() }
            default:
                break
            }
        }
        let sending = Task { [queued] in
            for await message in queued { try? await channel.send(message) }
        }
        // A connection that has not said who it is within a few seconds is
        // dropped, so the dialler can try again.
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { self?.close() }
        }
        send(hello)
        var peer: String?
        do {
            for try await (message, _) in channel.messages {
                if case .hello(let id, let name) = message {
                    guard peer == nil else { continue }
                    peer = id
                    watchdog.cancel()
                    engine.opened(self, peer: id, name: name)
                } else if peer != nil {
                    engine.received(message, from: self)
                }
            }
        } catch {
            NearbyLogger.note("A connection ended: \(error)")
        }
        watchdog.cancel()
        sending.cancel()
        outbox.finish()
        if peer != nil { engine.closed(self) }
    }
}
