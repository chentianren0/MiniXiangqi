// The nearby-play connectivity spike: Wi-Fi Aware transport, no game.
//
// Branch-only experiment code (issue #114). This is not product behaviour and
// no docs/ contract governs it; it exists to answer the transport questions the
// protocol draft depends on, on real devices, before that draft is written.
//
// First device run (2026-08-04, internal TestFlight): pairing, discovery, and
// the crossed both-direction connections all worked; every data path then
// failed or stalled with POSIX 50 "Network is down", and the log carried only
// that generic code. This revision turns the spike into an experiment matrix:
//
// - **Roles** — Both / Publish only / Subscribe only. Isolates whether four
//   simultaneous radio operations between the same two devices (listener,
//   browser, and a crossing connection on each side) exhaust the radio —
//   `WAError.noRadioResources` documents exactly that remedy.
// - **Stack** — TCP + `.bulk` (the game's natural shape) versus UDP +
//   `.realtime` + `interactiveVideo`, the exact shape of Apple's known-working
//   sample. One variable at a time.
// - Every failure now also logs `NWError.wifiAware`, the Wi-Fi Aware-specific
//   error beneath the POSIX code.
// - A 20-second watchdog drops a connection stuck before `.ready`, so the
//   browser loop retries instead of waiting forever on a dead attempt.
//
// The service names `_boardgame._tcp` / `_boardgame._udp` are declared in the
// Info.plist; "boardgame" is the owner's chosen name (2026-08-04), final only
// when the feature ships.

#if os(iOS)

import Foundation
import Network
import Observation
import OSLog
import UIKit
import WiFiAware

let nearbySpikeLogger = Logger(subsystem: "com.ppppvz.minixiangqi", category: "nearby-spike")

/// Which of the two Wi-Fi Aware roles this device runs. `both` is the
/// symmetric shape the feature wants; the single roles exist to isolate
/// failures.
nonisolated enum SpikeRoles: String, CaseIterable, Identifiable {
    case both, publish, subscribe
    var id: String { rawValue }
}

/// The protocol stack under test. `tcpBulk` is the shape a board game wants;
/// `udpRealtime` is the exact shape of Apple's known-working sample app.
nonisolated enum SpikeTransport: String, CaseIterable, Identifiable {
    case tcpBulk, udpRealtime
    var id: String { rawValue }

    var serviceName: String {
        switch self {
        case .tcpBulk: "_boardgame._tcp"
        case .udpRealtime: "_boardgame._udp"
        }
    }

    var label: String {
        switch self {
        case .tcpBulk: "TCP + bulk"
        case .udpRealtime: "UDP + realtime"
        }
    }
}

/// The declared services, named once. `nil` — never a crash — if the
/// Info.plist declaration and these constants ever disagree.
/// `nonisolated`: the network stack reads these off the main actor.
nonisolated enum NearbySpikeService {
    static func publishable(_ transport: SpikeTransport) -> WAPublishableService? {
        WAPublishableService.allServices[transport.serviceName]
    }
    static func subscribable(_ transport: SpikeTransport) -> WASubscribableService? {
        WASubscribableService.allServices[transport.serviceName]
    }
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

    /// The experiment variables, chosen on the screen before Start.
    var roles: SpikeRoles = .both
    var transport: SpikeTransport = .tcpBulk

    /// Restart publish/subscribe after a failure instead of stopping — the
    /// reconnection half of the experiment.
    var autoRestart = true

    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pairedDevicesTask: Task<Void, Never>?
    private var connections: [String: SpikeConnection] = [:]
    private var receiveTasks: [String: Task<Void, Never>] = [:]
    private var watchdogs: [String: Task<Void, Never>] = [:]
    private var nextPingSeq = 0

    private static let localDeviceName = UIDevice.current.name

    // MARK: - Log

    func log(_ text: String) {
        nearbySpikeLogger.info("\(text, privacy: .public)")
        #if DEBUG
        // `devicectl --console` bridges stdout only, not OSLog: a driven
        // device run reads the spike through this print.
        print("[nearby] \(text)")
        #endif
        lines.append(LogLine(at: Date(), text: text))
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
    }

    /// The failure line that matters: the Wi-Fi Aware error beneath the
    /// generic POSIX code, when there is one.
    private func logFailure(_ what: String, _ error: NWError) {
        log("\(what) failed: \(error) — wifiAware: \(String(describing: error.wifiAware))")
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

    func start() {
        guard !isRunning else { return }
        let transport = self.transport
        guard NearbySpikeService.publishable(transport) != nil,
              NearbySpikeService.subscribable(transport) != nil else {
            log("Service \(transport.serviceName) is missing from WiFiAwareServices — check Info.plist.")
            return
        }
        isRunning = true
        log("Starting: roles=\(roles.rawValue) stack=\(transport.label) service=\(transport.serviceName)")
        log("Capabilities: features=\(WACapabilities.supportedFeatures) maxDevices=\(WACapabilities.maximumConnectableDevices) maxPublish=\(WACapabilities.maximumPublishableServices) maxSubscribe=\(WACapabilities.maximumSubscribableServices)")
        if roles != .subscribe {
            listenerTask = Task { await self.runListenerLoop(transport) }
        }
        if roles != .publish {
            browserTask = Task { await self.runBrowserLoop(transport) }
        }
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

    private func runListenerLoop(_ transport: SpikeTransport) async {
        guard let service = NearbySpikeService.publishable(transport) else { return }
        while !Task.isCancelled {
            do {
                switch transport {
                case .tcpBulk:
                    try await NetworkListener(
                        for: .wifiAware(.connecting(to: service, from: .allPairedDevices)),
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
                            if case .failed(let error) = state { self.logFailure("Listener", error) }
                            if case .waiting(let error) = state { self.logFailure("Listener (waiting)", error) }
                        }
                    }
                    // Await the adoption inside the closure — the sample does,
                    // and an early return here proved to tear the incoming
                    // connection down (instant ENOTCONN) before adoption ran.
                    .run { connection in
                        await self.adopt(connection, direction: .incoming)
                    }
                case .udpRealtime:
                    try await NetworkListener(
                        for: .wifiAware(.connecting(to: service, from: .allPairedDevices)),
                        using: .parameters {
                            Coder(receiving: SpikeMessage.self, sending: SpikeMessage.self,
                                  using: NetworkJSONCoder()) {
                                UDP()
                            }
                        }
                        .wifiAware { $0.performanceMode = .realtime }
                        .serviceClass(.interactiveVideo)
                    )
                    .onStateUpdate { _, state in
                        Task { @MainActor in
                            self.listenerState = Self.describe(state)
                            self.log("Listener: \(Self.describe(state))")
                            if case .failed(let error) = state { self.logFailure("Listener", error) }
                            if case .waiting(let error) = state { self.logFailure("Listener (waiting)", error) }
                        }
                    }
                    // Await the adoption inside the closure — the sample does,
                    // and an early return here proved to tear the incoming
                    // connection down (instant ENOTCONN) before adoption ran.
                    .run { connection in
                        await self.adopt(connection, direction: .incoming)
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

    private func runBrowserLoop(_ transport: SpikeTransport) async {
        guard let service = NearbySpikeService.subscribable(transport) else { return }
        while !Task.isCancelled {
            let hasOutgoing = peers.contains { $0.direction == .outgoing }
            if hasOutgoing {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            do {
                let browser = NetworkBrowser(
                    for: .wifiAware(.connecting(to: .allPairedDevices, from: service))
                )
                .onStateUpdate { _, state in
                    Task { @MainActor in
                        self.browserState = Self.describe(state)
                        self.log("Browser: \(Self.describe(state))")
                        if case .failed(let error) = state { self.logFailure("Browser", error) }
                    }
                }
                let endpoint = try await browser.run { endpoints in
                    if let first = endpoints.first {
                        return .finish(first)
                    }
                    return .continue
                }
                await MainActor.run { self.log("Discovered endpoint: \(endpoint)") }

                let connection: SpikeConnection
                switch transport {
                case .tcpBulk:
                    connection = SpikeConnection(
                        to: endpoint,
                        using: .parameters {
                            Coder(receiving: SpikeMessage.self, sending: SpikeMessage.self,
                                  using: NetworkJSONCoder()) {
                                TCP()
                            }
                        }
                        .wifiAware { $0.performanceMode = .bulk }
                    )
                case .udpRealtime:
                    connection = SpikeConnection(
                        to: endpoint,
                        using: .parameters {
                            Coder(receiving: SpikeMessage.self, sending: SpikeMessage.self,
                                  using: NetworkJSONCoder()) {
                                UDP()
                            }
                        }
                        .wifiAware { $0.performanceMode = .realtime }
                        .serviceClass(.interactiveVideo)
                    )
                }
                await MainActor.run { self.adopt(connection, direction: .outgoing) }
                // Wait until this outgoing connection leaves the peer list
                // (ready-then-dead, watchdog, or stop) before browsing again.
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
                    self.watchdogs[connection.id]?.cancel()
                    self.watchdogs[connection.id] = nil
                    self.update(connection.id) { $0.isReady = true }
                    await self.send(.hello(deviceName: Self.localDeviceName), on: connection)
                    await self.refreshPath(of: connection)
                case .waiting(let error):
                    // Transient by contract, but on this path it is where the
                    // stall lives — surface the Wi-Fi Aware error beneath it.
                    self.logFailure("Connection \(connection.id.suffix(8)) (waiting)", error)
                case .failed(let error):
                    self.logFailure("Connection \(connection.id.suffix(8))", error)
                    self.drop(connection.id, reason: "connection failed")
                case .cancelled:
                    self.drop(connection.id, reason: "connection cancelled")
                default:
                    break
                }
            }
        }

        // A connection stuck before `.ready` blocks the browser loop forever
        // and holds radio resources; give it 20 seconds, then retry fresh.
        watchdogs[id] = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            if let peer = self.peers.first(where: { $0.id == id }), !peer.isReady {
                self.log("Connection \(id.suffix(8)) not ready after 20 s — dropping to retry.")
                self.drop(id, reason: "connect watchdog")
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
        watchdogs[id]?.cancel()
        watchdogs[id] = nil
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

/// The pairing views are pinned to the `_tcp` service: pairing grants access
/// to the *device*, and every declared service can reach a paired device.
extension WAPublishableService {
    static var spikeService: WAPublishableService { NearbySpikeService.publishable(.tcpBulk)! }
}

extension WASubscribableService {
    static var spikeService: WASubscribableService { NearbySpikeService.subscribable(.tcpBulk)! }
}

#endif
