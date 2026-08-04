// The nearby-play connectivity spike: Wi-Fi Aware transport, no game.
//
// Branch-only experiment code (issue #114). This is not product behaviour and
// no docs/ contract governs it; it exists to answer the transport questions the
// protocol draft depends on, on real devices, before that draft is written:
//
// - Can both devices run publisher and subscriber at once, so that starting a
//   game needs no host/guest choice? What happens when the two connections
//   cross — do we get one link or two?
// - What does the link do when a screen locks, the app backgrounds, or the
//   players walk apart — and does a dropped link come back by itself?
// - What round-trip time and signal do moves actually see in `.bulk` mode?
//
// Everything here is deliberately symmetric: the one Start button runs a
// `NetworkListener` (publish) and a `NetworkBrowser` (subscribe) together on
// the same `_boardgame._tcp` service, exactly what Adopting Wi-Fi Aware says an
// app may do. Peers exchange a hello and then ping/pong every two seconds; the
// screen shows every connection, its round-trip time, its signal, and a log.
//
// The service name `_boardgame._tcp` is the owner's chosen name (2026-08-04),
// final only when the feature ships.

#if os(iOS)

import Foundation
import Network
import Observation
import OSLog
import UIKit
import WiFiAware

let nearbySpikeLogger = Logger(subsystem: "com.ppppvz.minixiangqi", category: "nearby-spike")

/// The declared service, named once. `nil` — never a crash — if the Info.plist
/// declaration and this constant ever disagree, and the screen says so.
/// `nonisolated`: the network stack reads these off the main actor.
nonisolated enum NearbySpikeService {
    static let name = "_boardgame._tcp"
    static var publishable: WAPublishableService? { WAPublishableService.allServices[name] }
    static var subscribable: WASubscribableService? { WASubscribableService.allServices[name] }
}

/// What the spike sends: a greeting, then heartbeats. `sentAt` comes back in
/// the pong, so round-trip time needs no clock agreement between the devices.
/// `nonisolated`: the connection's coder encodes and decodes these on its own
/// executor, so the Codable conformance must not be actor-isolated.
nonisolated enum SpikeMessage: Codable, Sendable {
    case hello(deviceName: String)
    case ping(seq: Int, sentAt: Date)
    case pong(seq: Int, sentAt: Date)
}

typealias SpikeConnection = NetworkConnection<Coder<SpikeMessage, SpikeMessage, NetworkJSONCoder>>

/// One live connection as the screen sees it.
struct SpikePeer: Identifiable {
    enum Direction: String { case incoming, outgoing }

    let id: String
    let direction: Direction
    var peerName: String?
    var deviceName: String?
    var isReady = false
    var lastHeard: Date?
    var lastRoundTrip: Duration?
    var signalStrength: Double?
    var pingsSent = 0
    var pongsReceived = 0
}

/// The whole experiment, observable by the screen. Networking callbacks arrive
/// off the main actor and hop back through `Task { @MainActor in … }`; the
/// stored state is only ever touched here.
@MainActor
@Observable
final class NearbySpikeSession {
    struct LogLine: Identifiable {
        let id = UUID()
        let at: Date
        let text: String
    }

    private(set) var isRunning = false
    private(set) var listenerState = "stopped"
    private(set) var browserState = "stopped"
    private(set) var pairedDevices: [WAPairedDevice] = []
    private(set) var peers: [SpikePeer] = []
    private(set) var lines: [LogLine] = []

    /// Restart publish/subscribe after a failure instead of stopping — the
    /// reconnection half of the experiment.
    var autoRestart = true

    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pairedDevicesTask: Task<Void, Never>?
    private var connections: [String: SpikeConnection] = [:]
    private var receiveTasks: [String: Task<Void, Never>] = [:]
    private var nextPingSeq = 0

    private static let localDeviceName = UIDevice.current.name

    // MARK: - Log

    func log(_ text: String) {
        nearbySpikeLogger.info("\(text, privacy: .public)")
        lines.append(LogLine(at: Date(), text: text))
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
    }

    // MARK: - Paired devices

    func watchPairedDevices() {
        guard pairedDevicesTask == nil else { return }
        pairedDevicesTask = Task {
            do {
                for try await snapshot in WAPairedDevice.allDevices {
                    self.pairedDevices = Array(snapshot.values)
                }
            } catch {
                self.log("Paired-device watch failed: \(error)")
            }
        }
    }

    // MARK: - Start and stop

    /// The symmetric start: publish and subscribe together. Neither device is
    /// a host; whichever browser finds the other's listener first connects,
    /// and if both do, the screen shows the crossed pair.
    func start() {
        guard !isRunning else { return }
        guard NearbySpikeService.publishable != nil, NearbySpikeService.subscribable != nil else {
            log("Service \(NearbySpikeService.name) is missing from WiFiAwareServices — check Info.plist.")
            return
        }
        isRunning = true
        log("Starting publisher and subscriber for \(NearbySpikeService.name).")
        listenerTask = Task { await self.runListenerLoop() }
        browserTask = Task { await self.runBrowserLoop() }
        heartbeatTask = Task { await self.runHeartbeatLoop() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        listenerTask?.cancel()
        browserTask?.cancel()
        heartbeatTask?.cancel()
        listenerTask = nil
        browserTask = nil
        heartbeatTask = nil
        for (id, _) in connections { drop(id, reason: "stopped") }
        listenerState = "stopped"
        browserState = "stopped"
        log("Stopped.")
    }

    // MARK: - Publisher

    private func runListenerLoop() async {
        while !Task.isCancelled {
            do {
                try await NetworkListener(
                    for: .wifiAware(.connecting(to: .spikeService, from: .allPairedDevices)),
                    using: .parameters {
                        Coder(receiving: SpikeMessage.self, sending: SpikeMessage.self,
                              using: NetworkJSONCoder()) {
                            TCP()
                        }
                    }
                    .wifiAware { $0.performanceMode = .bulk }
                )
                .onStateUpdate { _, state in
                    Task { @MainActor in
                        self.listenerState = Self.describe(state)
                        self.log("Listener: \(Self.describe(state))")
                    }
                }
                .run { connection in
                    Task { @MainActor in
                        self.adopt(connection, direction: .incoming)
                    }
                }
            } catch {
                await MainActor.run {
                    self.listenerState = "failed"
                    self.log("Listener ended: \(error)")
                }
            }
            guard autoRestart, !Task.isCancelled else { break }
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { self.log("Restarting listener.") }
        }
    }

    // MARK: - Subscriber

    private func runBrowserLoop() async {
        while !Task.isCancelled {
            let hasOutgoing = peers.contains { $0.direction == .outgoing }
            if hasOutgoing {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            do {
                let browser = NetworkBrowser(
                    for: .wifiAware(.connecting(to: .allPairedDevices, from: .spikeService))
                )
                .onStateUpdate { _, state in
                    Task { @MainActor in
                        self.browserState = Self.describe(state)
                        self.log("Browser: \(Self.describe(state))")
                    }
                }
                let endpoint = try await browser.run { endpoints in
                    if let first = endpoints.first {
                        return .finish(first)
                    }
                    return .continue
                }
                await MainActor.run { self.log("Discovered endpoint: \(endpoint)") }
                let connection = SpikeConnection(
                    to: endpoint,
                    using: .parameters {
                        Coder(receiving: SpikeMessage.self, sending: SpikeMessage.self,
                              using: NetworkJSONCoder()) {
                            TCP()
                        }
                    }
                    .wifiAware { $0.performanceMode = .bulk }
                )
                await MainActor.run { self.adopt(connection, direction: .outgoing) }
                // Wait until this outgoing connection leaves the peer list
                // before browsing again; the loop's head re-checks.
                while !Task.isCancelled, self.connections[connection.id] != nil {
                    try await Task.sleep(for: .seconds(1))
                }
            } catch {
                await MainActor.run {
                    self.browserState = "failed"
                    self.log("Browser ended: \(error)")
                }
                guard autoRestart, !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Connections

    private func adopt(_ connection: SpikeConnection, direction: SpikePeer.Direction) {
        let id = connection.id
        log("Adopting \(direction.rawValue) connection \(id.suffix(8)).")
        connections[id] = connection
        peers.append(SpikePeer(id: id, direction: direction))

        connection.onStateUpdate { connection, state in
            Task { @MainActor in
                self.log("Connection \(connection.id.suffix(8)): \(Self.describe(state))")
                switch state {
                case .ready:
                    self.update(connection.id) { $0.isReady = true }
                    await self.send(.hello(deviceName: Self.localDeviceName), on: connection)
                    await self.refreshPath(of: connection)
                case .failed, .cancelled:
                    self.drop(connection.id, reason: "connection \(Self.describe(state))")
                default:
                    break
                }
            }
        }

        receiveTasks[id] = Task {
            do {
                for try await (message, _) in connection.messages {
                    await self.received(message, on: connection)
                }
            } catch {
                await MainActor.run { self.log("Receive loop \(id.suffix(8)) ended: \(error)") }
            }
            await MainActor.run { self.drop(id, reason: "receive loop ended") }
        }
    }

    private func drop(_ id: String, reason: String) {
        guard connections[id] != nil else { return }
        log("Dropping connection \(id.suffix(8)) (\(reason)).")
        receiveTasks[id]?.cancel()
        receiveTasks[id] = nil
        connections[id] = nil
        peers.removeAll { $0.id == id }
    }

    private func update(_ id: String, _ change: (inout SpikePeer) -> Void) {
        guard let index = peers.firstIndex(where: { $0.id == id }) else { return }
        change(&peers[index])
    }

    // MARK: - Messages

    private func received(_ message: SpikeMessage, on connection: SpikeConnection) async {
        update(connection.id) { $0.lastHeard = Date() }
        switch message {
        case .hello(let deviceName):
            log("Peer on \(connection.id.suffix(8)) is “\(deviceName)”.")
            update(connection.id) { $0.peerName = deviceName }
        case .ping(let seq, let sentAt):
            await send(.pong(seq: seq, sentAt: sentAt), on: connection)
        case .pong(let seq, let sentAt):
            let roundTrip = Duration.seconds(Date().timeIntervalSince(sentAt))
            update(connection.id) {
                $0.pongsReceived += 1
                $0.lastRoundTrip = roundTrip
            }
            if seq % 5 == 0 {
                log("Pong \(seq) on \(connection.id.suffix(8)): \(Self.milliseconds(roundTrip)).")
            }
        }
    }

    private func send(_ message: SpikeMessage, on connection: SpikeConnection) async {
        do {
            try await connection.send(message)
        } catch {
            log("Send failed on \(connection.id.suffix(8)): \(error)")
        }
    }

    // MARK: - Heartbeat

    private func runHeartbeatLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            for (id, connection) in connections where connection.state == .ready {
                nextPingSeq += 1
                update(id) { $0.pingsSent += 1 }
                await send(.ping(seq: nextPingSeq, sentAt: Date()), on: connection)
                await refreshPath(of: connection)
            }
        }
    }

    private func refreshPath(of connection: SpikeConnection) async {
        guard let wifiAware = try? await connection.currentPath?.wifiAware else { return }
        update(connection.id) {
            $0.deviceName = wifiAware.endpoint.device.name
            $0.signalStrength = wifiAware.performance.signalStrength
        }
    }

    // MARK: - Descriptions

    private static func describe(_ state: Any) -> String {
        String(describing: state)
    }

    static func milliseconds(_ duration: Duration) -> String {
        let millis = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        return String(format: "%.0f ms", millis)
    }
}

extension WAPublishableService {
    static var spikeService: WAPublishableService { NearbySpikeService.publishable! }
}

extension WASubscribableService {
    static var spikeService: WASubscribableService { NearbySpikeService.subscribable! }
}

#endif
