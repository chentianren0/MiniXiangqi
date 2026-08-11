// The BoardGame Protocol's Wi-Fi Aware binding, as the transport it names.
//
// docs/boardgame-protocol.md, "A transport binding: Wi-Fi Aware", is what this
// file implements and nothing more: the one declared `_boardgame._tcp` service,
// both devices running the publisher and the subscriber together, TCP in `.bulk`
// on both sides, the Network framework's JSON message coder so the protocol
// layer sees whole messages, and two crossed connections both left standing.
//
// The connection layer names the connection and the paired device behind it,
// and hands both to the driver. It reads no message and decides nothing about
// a session: what arrives goes to the driver as it is, and what the engine
// answers with comes back as a send or a close.
//
// iPhone and iPad only. The entitlement is signed for those two alone, and the
// system pairing UI does not exist on the Mac at all, so the whole feature is
// compiled out there.

#if os(iOS)

import Foundation
import Network
import Observation
import UIKit
import WiFiAware

/// The one service, declared `Publishable` and `Subscribable` in the
/// Info.plist's `WiFiAwareServices`. `nil` — never a crash — if the declaration
/// and this name ever disagree.
///
/// `nonisolated`: the network stack reads these off the main actor.
nonisolated enum NearbyService {
    static let name = "_boardgame._tcp"

    static var publishable: WAPublishableService? { WAPublishableService.allServices[name] }
    static var subscribable: WASubscribableService? { WASubscribableService.allServices[name] }
}

/// A connection carrying the protocol's messages: TCP, framed by the JSON
/// coder, decoding straight into the message type. The `Codable` conformance in
/// `BoardGameMessage` is the wire format — nothing composes those bytes twice.
typealias NearbyChannel =
    NetworkConnection<Coder<BoardGameMessage, BoardGameMessage, NetworkJSONCoder>>

/// The identity sessions and resume rely on, minted in one place. It is the
/// *paired device*, never the endpoint: `WAPairedDevice.id` names the system's
/// pairing record, which is made once per pair of devices and outlives the
/// application, so it is the same number on the next connection and after a
/// relaunch. An endpoint object is not — a new one is minted per discovery.
nonisolated func nearbyPeerID(of device: WAPairedDevice) -> PeerDeviceID {
    PeerDeviceID("wifi-aware-device-\(device.id)")
}

/// The protocol stack both sides build, listener and browser alike.
private func nearbyParameters() -> NWParametersBuilder<
    Coder<BoardGameMessage, BoardGameMessage, NetworkJSONCoder>
> {
    .parameters {
        Coder(receiving: BoardGameMessage.self, sending: BoardGameMessage.self,
              using: NetworkJSONCoder()) {
            TCP()
        }
    }
    // Realtime, for its committed availability rather than its throughput: the
    // radio's windows span the infrastructure channels instead of the social
    // channel alone, which is what shortens a dial and steadies a marginal
    // link — the two places this feature actually waits. The battery this
    // spends is spent only while the radio runs, and the radio runs only while
    // nearby play is in use or a game is owed settling. It moves no bands and
    // adds no range: the 5 GHz choice is the platform's own.
    .wifiAware { $0.performanceMode = .realtime }
}

/// One Wi-Fi Aware connection, and the whole of what the driver may do with it.
@MainActor
@Observable
final class NearbyConnection: NearbyLink, Identifiable {
    /// Which side opened it. Both may stand at once between one pair of
    /// devices, and the contract allows exactly that.
    enum Direction: String, Sendable {
        case incoming, outgoing
    }

    let id: ConnectionID
    let direction: Direction

    private(set) var isReady = false
    /// The paired device the transport resolved behind this connection.
    private(set) var peer: PeerDeviceID?
    /// That device's name, for the screen alone. Nothing keys on it.
    private(set) var peerName: String?
    private(set) var signalStrength: Double?

    /// The connection itself, released when its life ends. The Network
    /// framework gives `NetworkConnection` no cancel of its own: a connection
    /// lives as long as something holds it, so letting go of it is how one is
    /// torn down, and this reference is the last hold on it.
    @ObservationIgnored private var channel: NearbyChannel?
    @ObservationIgnored private var life: Task<Void, Never>?
    /// Whether the driver has been told of this connection. Until it has, the
    /// engine holds nothing for it and an arrival has nowhere to go.
    @ObservationIgnored private var isOpen = false
    @ObservationIgnored private var waiting: [BoardGameMessage] = []
    /// Readiness, said once. The state handler watches the connection for its
    /// whole life, so the answer travels rather than being read out of a stream
    /// somebody stopped consuming.
    @ObservationIgnored private let readiness: AsyncStream<Bool>
    @ObservationIgnored private let readinessFeed: AsyncStream<Bool>.Continuation

    /// How long a connection may sit short of `.ready` before it is dropped so
    /// the browser loop can try again. Measured on the two devices: a healthy
    /// connection is ready in well under a second, and one that is not ready
    /// after this is holding radio resources for nothing. Eight seconds rather
    /// than the spike's twenty, because a stuck attempt costs the whole window
    /// before the retry that does connect.
    private static let readyWindow = Duration.seconds(8)

    init(_ channel: NearbyChannel, direction: Direction) {
        self.channel = channel
        self.direction = direction
        self.id = ConnectionID(channel.id)
        (readiness, readinessFeed) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    // MARK: - NearbyLink

    func send(_ message: BoardGameMessage) async throws {
        guard let channel else { throw CancellationError() }
        try await channel.send(message)
    }

    /// Ends the connection's life, which releases it, which cancels it.
    func close() {
        life?.cancel()
    }

    // MARK: - Its life

    /// Starts the connection's life and hands back the task it runs on, so a
    /// caller that owns one connection at a time — the browser loop — can wait
    /// for it to be over.
    @discardableResult
    func start(driver: NearbyDriver, log: NearbyLog,
               whenDone: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let task = Task { [self] in
            await live(driver: driver, log: log)
            channel = nil
            whenDone()
        }
        life = task
        return task
    }

    /// **Reading the connection is what sets it going.** A `NetworkConnection`
    /// of a one-to-one protocol has no `start()`; it is established because
    /// something is waiting on it, so the receive loop comes first and
    /// readiness is resolved beside it. Waiting for `.ready` before reading
    /// leaves the connection in setup for ever — measured on the two devices,
    /// where every attempt hit the ready window and the state handler never
    /// fired once.
    private func live(driver: NearbyDriver, log: NearbyLog) async {
        guard let channel else { return }
        log.note("Adopting the \(direction.rawValue) connection \(NearbyDriver.short(id)).")

        watch(channel, log: log)
        let opening = Task { [self] in await open(channel, driver: driver, log: log) }
        defer { opening.cancel() }

        do {
            for try await (message, _) in channel.messages {
                if isOpen {
                    driver.received(message, on: id)
                } else {
                    // The other peer's hello can land in the instant between
                    // this connection being usable and the driver being told of
                    // it. It waits rather than arriving for a connection the
                    // engine does not hold yet.
                    waiting.append(message)
                }
            }
            log.note("Connection \(NearbyDriver.short(id)): the stream ended.")
        } catch {
            // The split the contract forces, and the reason it is drawn on the
            // *death* side rather than on the refusal side.
            //
            // This layer never sees bytes, so the coder's refusal is the whole
            // of what "unreadable" can mean here — and unreadable is malformed,
            // which is a violation: the connection closes and the session is
            // **void**. A connection that merely died leaves its session
            // interrupted and resumable, which is a different outcome
            // altogether. Getting the two the wrong way round is not a
            // cosmetic difference.
            //
            // `NetworkConnection.messages` is an `AsyncThrowingStream` of
            // `any Error`, and nothing promises that a coder's `DecodingError`
            // arrives here bare rather than wrapped by the framework. Matching
            // `DecodingError` alone would therefore let a wrapped refusal be
            // read as a death and quietly downgrade a violation. So only the
            // connection's own end is read as a death — an `NWError` from the
            // network stack, or the cancellation `close()` raises — and
            // everything else is the coder refusing what arrived. The breadth
            // is the contract's requirement, not sloppiness.
            if NearbyTransport.isConnectionEnd(error) {
                log.note("Connection \(NearbyDriver.short(id)): receiving ended — "
                         + "\(NearbyTransport.describe(error)).")
            } else {
                log.note("Connection \(NearbyDriver.short(id)): unreadable — \(error).")
                if isOpen { driver.receivedUnreadable(on: id) }
            }
        }
        isReady = false
        if isOpen {
            isOpen = false
            driver.connectionDied(id)
        }
    }

    /// Readiness, the paired device behind it, and the handover to the driver.
    private func open(_ channel: NearbyChannel, driver: NearbyDriver, log: NearbyLog) async {
        guard await becomesReady(channel, log: log) else {
            log.note("Connection \(NearbyDriver.short(id)) never became ready — dropping it "
                     + "so the loop can try again.")
            close()
            return
        }
        isReady = true
        guard let path = await wifiAwarePath(of: channel) else {
            log.note("Connection \(NearbyDriver.short(id)) reported no Wi-Fi Aware path, so "
                     + "there is no device to name behind it — dropping it.")
            close()
            return
        }
        let peer = nearbyPeerID(of: path.endpoint.device)
        self.peer = peer
        peerName = path.endpoint.device.name
        signalStrength = path.performance.signalStrength
        log.note("Connection \(NearbyDriver.short(id)) reaches ",
                 naming: path.endpoint.device.name ?? "an unnamed device",
                 " (\(peer.rawValue)).")

        driver.connectionReady(self, with: peer)
        isOpen = true
        let held = waiting
        waiting = []
        for message in held { driver.received(message, on: id) }
    }

    /// Watches the connection for its whole life. A connection that fails after
    /// it was ready must end here: the message stream does *not* throw when the
    /// radio drops one — measured on the two devices, where a connection failed
    /// with the idle timeout and its receive loop simply went on waiting, so
    /// nobody learned it was gone and the browser never dialled again.
    private func watch(_ channel: NearbyChannel, log: NearbyLog) {
        channel.onStateUpdate { [weak self] _, state in
            Task { @MainActor in
                guard let self else { return }
                let name = NearbyDriver.short(self.id)
                log.note("Connection \(name): \(NearbyTransport.describe(state))")
                switch state {
                case .ready:
                    self.readinessFeed.yield(true)
                case .waiting(let error):
                    log.note("Connection \(name) is waiting: "
                             + "\(NearbyTransport.describe(error))")
                    // `.waiting` is transient by contract, but the cold radio's
                    // first attempt reports `connectionFailed` there and never
                    // leaves it. Waiting out the whole window for a connection
                    // that has already failed only delays the retry that fixes
                    // it.
                    if case .connectionFailed = error.wifiAware {
                        self.readinessFeed.yield(false)
                        self.close()
                    }
                case .failed(let error):
                    log.note("Connection \(name) failed: \(NearbyTransport.describe(error))")
                    self.readinessFeed.yield(false)
                    self.close()
                case .cancelled:
                    self.readinessFeed.yield(false)
                    self.close()
                default:
                    break
                }
            }
        }
    }

    /// Waits for `.ready`, for as long as the ready window allows. A connection
    /// stuck short of ready would otherwise hold the loop and the radio for
    /// ever; the first attempts after a cold radio do fail, and retrying is
    /// what carries them.
    private func becomesReady(_ channel: NearbyChannel, log: NearbyLog) async -> Bool {
        if channel.state == .ready { return true }

        let watchdog = Task { [self] in
            try? await Task.sleep(for: Self.readyWindow)
            readinessFeed.yield(false)
        }
        defer { watchdog.cancel() }

        for await ready in readiness { return ready }
        return false
    }

    /// The Wi-Fi Aware path behind the connection, which is where the paired
    /// device's identity comes from. It is not always there the instant a
    /// connection is ready, so this asks a few times before giving up.
    private func wifiAwarePath(of channel: NearbyChannel) async -> WAPath? {
        for attempt in 0..<5 {
            if let path = try? await channel.currentPath?.wifiAware { return path }
            if attempt < 4 { try? await Task.sleep(for: .milliseconds(200)) }
        }
        return nil
    }
}

/// The publisher, the subscriber, and the connections they bring up.
@MainActor
@Observable
final class NearbyTransport {
    private let driver: NearbyDriver
    private let log: NearbyLog

    private(set) var isRunning = false
    private(set) var listenerState = "stopped"
    private(set) var browserState = "stopped"
    private(set) var pairedDevices: [WAPairedDevice] = []
    private(set) var connections: [NearbyConnection] = []

    @ObservationIgnored private var listenerTask: Task<Void, Never>?
    @ObservationIgnored private var browserTask: Task<Void, Never>?
    @ObservationIgnored private var pairedDevicesTask: Task<Void, Never>?
    /// Whether the browser loop is holding off because a connection stands. It
    /// says so once rather than every time it looks.
    @ObservationIgnored private var isHolding = false

    init(driver: NearbyDriver, log: NearbyLog) {
        self.driver = driver
        self.log = log
        // **The pairing registry is not radio work**, so it is not waited for
        // and it is not started and stopped with the publisher and the
        // subscriber. It is a system record this device already holds, it is
        // what the propose sheet's list of devices *is*, and it has to be right
        // at the instant that sheet opens rather than seconds later. Where
        // there is no radio there are no pairings either, and a Simulator is
        // the case that proves it — which the watch answers for itself, so that
        // every caller is the same call.
        watchPairedDevices()
    }

    /// Whether this device has the radio at all. Where it does not, there is
    /// nothing to start.
    static var isSupported: Bool {
        WACapabilities.supportedFeatures.contains(.wifiAware)
    }

    // MARK: - Paired devices

    /// The system's pairing list, which is the system's and outlives the app.
    ///
    /// Idempotent, and it lets go of its own handle when the snapshots stop, so
    /// that a watch which failed once is taken up again the next time a surface
    /// wakes — `NearbyFlow` calls this there, off the radio's own bracket —
    /// rather than leaving the list empty for the rest of the launch. Hardware
    /// with no radio is answered here rather than at each caller, so that every
    /// caller is the same call.
    func watchPairedDevices() {
        guard Self.isSupported, pairedDevicesTask == nil else { return }
        // Weakly, and cancelled when this object ends: the snapshots do not stop
        // on their own, so a task holding the transport would hold it — and its
        // subscription to the system's registry — for the whole launch, however
        // long ago everything else let go of it.
        pairedDevicesTask = Task { [weak self] in
            defer { self?.pairedDevicesTask = nil }
            do {
                for try await snapshot in WAPairedDevice.allDevices {
                    guard let self else { return }
                    pairedDevices = Array(snapshot.values)
                    // The room, as the propose sheet will list it. No device is
                    // named: a device's name is routinely its owner's own.
                    log.note("Paired devices: \(pairedDevices.count) "
                             + "— \(peers.filter { $0.connection != nil }.count) connected.")
                }
            } catch {
                self?.log.note("Watching the paired devices failed: \(Self.describe(error)).")
            }
        }
    }

    /// The watch ends with this object, not with `stop()`: the registry is not
    /// radio work, and it is the transport's own life it belongs to.
    deinit { pairedDevicesTask?.cancel() }

    // MARK: - Start and stop

    func start() {
        guard !isRunning else { return }
        guard NearbyService.publishable != nil, NearbyService.subscribable != nil else {
            log.note("The service \(NearbyService.name) is missing from WiFiAwareServices.")
            return
        }
        isRunning = true
        log.note("Starting \(NearbyService.name): publishing and subscribing together.")
        log.note("Capabilities: features=\(WACapabilities.supportedFeatures) "
                 + "maxDevices=\(WACapabilities.maximumConnectableDevices) "
                 + "maxPublish=\(WACapabilities.maximumPublishableServices) "
                 + "maxSubscribe=\(WACapabilities.maximumSubscribableServices)")
        log.note("This device is “", naming: UIDevice.current.name, "”.")
        listenerTask = Task { [self] in await runListener() }
        browserTask = Task { [self] in await runBrowser() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        listenerTask?.cancel()
        browserTask?.cancel()
        listenerTask = nil
        browserTask = nil
        driver.closeEverything()
        for connection in connections { connection.close() }
        listenerState = "stopped"
        browserState = "stopped"
        log.note("Stopped.")
    }

    // MARK: - The publisher

    private func runListener() async {
        guard let service = NearbyService.publishable else { return }
        while !Task.isCancelled {
            do {
                try await NetworkListener(
                    for: .wifiAware(.connecting(to: service, from: .allPairedDevices)),
                    using: nearbyParameters()
                )
                .onStateUpdate { [self] _, state in
                    Task { @MainActor in
                        guard listenerState != Self.describe(state) else { return }
                        listenerState = Self.describe(state)
                        log.note("Listener: \(listenerState)")
                    }
                }
                // The adoption is awaited *inside* the closure. An early return
                // tore the incoming connection down before adoption could run —
                // an instant ENOTCONN — which the spike paid for once already.
                .run { [self] channel in
                    await adopt(channel, direction: .incoming)
                }
            } catch {
                listenerState = "failed"
                log.note("Listener ended: \(Self.describe(error)).")
            }
            guard !Task.isCancelled else { break }
            try? await Task.sleep(for: .seconds(2))
            log.note("Restarting the listener.")
        }
    }

    // MARK: - The subscriber

    private func runBrowser() async {
        guard let service = NearbyService.subscribable else { return }
        while !Task.isCancelled {
            do {
                let browser = NetworkBrowser(
                    for: .wifiAware(.connecting(to: .allPairedDevices, from: service))
                )
                .onStateUpdate { [self] _, state in
                    Task { @MainActor in
                        // A browse is one run of a fresh browser, so the same
                        // states come round every time it is asked again; only
                        // a change is worth a line, and none of it is worth one
                        // while the loop is only looking to see whether the
                        // connection it already has is still there.
                        let described = Self.describe(state)
                        defer { browserState = described }
                        guard !isHolding, browserState != described else { return }
                        log.note("Browser: \(described)")
                    }
                }
                let endpoint = try await browser.run { endpoints in
                    if let first = endpoints.first { return .finish(first) }
                    return .continue
                }
                let device = endpoint.device

                // Crossed connections come up when both devices dial at once,
                // and the binding leaves both standing. Dialling a device this
                // one is *already* connected to is a different thing: it would
                // replace a healthy connection with a fresh one every time an
                // idle crossing died, and each replacement costs a resume
                // exchange. So the loop waits instead.
                // Looking again is a fresh browse each time, which is real radio
                // work for an answer that rarely changes. A longer-lived browse
                // that only finishes when there is somebody new to dial would be
                // cheaper; it is not this stage's, because a browser parked on
                // an unchanged endpoint set is never re-asked, and the moment
                // this loop has to notice is the one where a connection it holds
                // has just died.
                guard !isConnected(to: nearbyPeerID(of: device)) else {
                    if !isHolding {
                        isHolding = true
                        log.note("Already connected to ",
                                 naming: device.name ?? "that device",
                                 " — waiting rather than dialling again.")
                    }
                    try? await Task.sleep(for: .seconds(4))
                    continue
                }
                isHolding = false
                log.note("Discovered ", naming: device.name ?? "an unnamed device",
                         " — dialling.")

                let channel = NearbyChannel(to: endpoint, using: nearbyParameters())
                // One outgoing connection at a time: the next browse waits for
                // this one to be over, whether it was ready or the first cold
                // attempt the radio refused.
                await adopt(channel, direction: .outgoing)?.value
            } catch {
                browserState = "failed"
                log.note("Browser ended: \(Self.describe(error)).")
            }
            guard !Task.isCancelled else { break }
            // Both devices publish and subscribe together, so both dial at the
            // same instant and both retry in step. The jitter breaks that
            // lockstep: two devices retrying together kept meeting in the same
            // contention, and neither attempt ever left `preparing`.
            try? await Task.sleep(for: .milliseconds(Int.random(in: 400...2600)))
        }
    }

    // MARK: - Connections

    /// Whether a connection to that device is up here already.
    private func isConnected(to peer: PeerDeviceID) -> Bool {
        connections.contains { $0.isReady && $0.peer == peer }
    }

    @discardableResult
    private func adopt(_ channel: NearbyChannel,
                       direction: NearbyConnection.Direction) async -> Task<Void, Never>? {
        let connection = NearbyConnection(channel, direction: direction)
        connections.append(connection)
        return connection.start(driver: driver, log: log) { [weak self] in
            self?.connections.removeAll { $0 === connection }
        }
    }

    // MARK: - Descriptions

    static func describe(_ state: Any) -> String { String(describing: state) }

    /// Whether an error the receive loop ended on is the connection itself
    /// going away, rather than the coder refusing what arrived.
    ///
    /// The network stack's own failures are `NWError`, and a cancellation is
    /// this side's `close()` — the state watcher raises one for every failed or
    /// cancelled connection, so a genuine death often reaches the loop that way
    /// rather than as the error itself. Both are deaths. Anything else is the
    /// refusal.
    static func isConnectionEnd(_ error: any Error) -> Bool {
        error is NWError || error is CancellationError
    }

    /// A failure, with the Wi-Fi Aware error beneath the generic POSIX code
    /// where there is one — the generic code alone says nothing.
    static func describe(_ error: any Error) -> String {
        guard let network = error as? NWError else { return String(describing: error) }
        guard let wifiAware = network.wifiAware else { return String(describing: network) }
        return "\(network) — wifiAware: \(wifiAware)"
    }
}

/// The pairing views are pinned to the one declared service: pairing grants
/// access to the *device*, and every declared service can reach a paired one.
extension WAPublishableService {
    static var boardGame: WAPublishableService? { NearbyService.publishable }
}

extension WASubscribableService {
    static var boardGame: WASubscribableService? { NearbyService.subscribable }
}

#endif
