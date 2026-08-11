// What carries the BoardGame Protocol between two devices.
//
// The protocol contract names no transport and asks four things of whatever
// carries it: whole messages rather than bytes a peer must frame for itself; a
// stable peer identity behind every connection, exactly one per peer whatever
// carries it; room for more than one connection between one pair of peers; and
// an authenticity and privacy that belong to the carrier rather than to the
// protocol. This layer answers all four, over two paths at once.
//
// **Both paths are here, and nothing above can tell them apart.** The
// paired-device radio needs no network at all and is what a companion is
// reachable over anywhere; the local network reaches through the walls of a
// home, which the radio cannot. Both run whenever the transport runs, both
// dial and both listen, both carry the same frames over TCP, and the room
// merges them into one row per device. Which one a game is on is not a fact any
// caller can read: `NearbyPeer` has nowhere to put it and `NearbyLink` gives
// the driver a name, a send and a close.
//
// **The identity is exchanged, not assumed.** Between a connection becoming
// usable and the driver being told of it, this device says who it is and hears
// who the other is, and that answer is the peer identity the driver is handed —
// see `NearbyIdentity`. A connection that never says dies unnamed. That is what
// makes "exactly one identity per peer, whatever carries it" structural: there
// is one moment where a peer is named, and one thing it can be named by.
//
// The connection layer reads no message and decides nothing about a session:
// what arrives goes to the driver as it is, and what the engine answers with
// comes back as a send or a close.
//
// iPhone and iPad only. The Wi-Fi Aware entitlement is signed for those two
// alone, and the system pairing UI does not exist on the Mac at all, so the
// whole feature is compiled out there.

#if os(iOS)

import Foundation
import Network
import Observation
import UIKit
import WiFiAware

/// The one service name, in both of the places a service is named: the
/// Info.plist's `WiFiAwareServices`, where it is declared `Publishable` and
/// `Subscribable`, and the Bonjour registration on the local network, where it
/// is the service type. One name, because it names the same thing — two devices
/// playing one board game — and DNS-SD service types and Wi-Fi Aware service
/// names are drawn from the same registry.
///
/// The two Wi-Fi Aware lookups answer `nil` — never a crash — if the
/// declaration and this name ever disagree.
///
/// `nonisolated`: the network stack reads these off the main actor.
nonisolated enum NearbyService {
    static let name = "_boardgame._tcp"

    static var publishable: WAPublishableService? { WAPublishableService.allServices[name] }
    static var subscribable: WASubscribableService? { WASubscribableService.allServices[name] }
}

/// A connection carrying the transport's frames: TCP, framed by the JSON coder,
/// decoding straight into the frame type. The `Codable` conformance in
/// `NearbyFrame` is the wire format — and a game's own message inside one is
/// exactly the bytes `BoardGameMessage` composes, because that is the type that
/// composes them.
typealias NearbyChannel =
    NetworkConnection<Coder<NearbyFrame, NearbyFrame, NetworkJSONCoder>>

/// What a paired device is called where nothing better is known: the system's
/// pairing record, which is made once per pair of devices and outlives the
/// application, so it is the same number on the next connection and after a
/// relaunch. An endpoint object is not — a new one is minted per discovery.
///
/// **It is the room's fallback, never a connection's identity.** A device is
/// listed under this while it is paired and nothing has yet learned what
/// application identity stands behind the pairing; the moment a connection
/// resolves that, the mapping is stored and the row is the canonical identity's.
nonisolated func nearbyPairingID(of device: WAPairedDevice) -> PeerDeviceID {
    PeerDeviceID("wifi-aware-device-\(device.id)")
}

extension WAPairedDevice {
    /// What this device is called, out of the two names the system may hold
    /// for it — and nothing at all where it holds neither, which is a state
    /// the rows have their own answer for.
    var displayName: String? {
        NearbyDeviceName.resolved(name: name, pairingName: pairingInfo?.pairingName)
    }
}

/// The protocol stack every connection is built on, whichever path carries it:
/// the frame coder over TCP, and nothing else. There is no TLS here and no
/// cryptography of ours anywhere — on the radio the platform authenticates the
/// pairing, and on the network the home's own boundary is the boundary, with
/// the proposal's consent prompt as the gate every game passes.
func nearbyStack() -> NWParametersBuilder<
    Coder<NearbyFrame, NearbyFrame, NetworkJSONCoder>
> {
    .parameters {
        Coder(receiving: NearbyFrame.self, sending: NearbyFrame.self,
              using: NetworkJSONCoder()) {
            TCP()
        }
    }
}

/// That stack as the radio wants it.
private func radioParameters() -> NWParametersBuilder<
    Coder<NearbyFrame, NearbyFrame, NetworkJSONCoder>
> {
    nearbyStack()
    // Realtime, for its committed availability rather than its throughput: the
    // radio's windows span the infrastructure channels instead of the social
    // channel alone, which is what shortens a dial and steadies a marginal
    // link — the two places this feature actually waits. The battery this
    // spends is spent only while the radio runs, and the radio runs only while
    // nearby play is in use or a game is owed settling. It moves no bands and
    // adds no range: the 5 GHz choice is the platform's own.
    .wifiAware { $0.performanceMode = .realtime }
}

/// One connection, on either path, and the whole of what the driver may do
/// with it.
@MainActor
@Observable
final class NearbyConnection: NearbyLink, NearbyLinkageExchange, Identifiable {
    /// Which side opened it. Both may stand at once between one pair of
    /// devices, and the contract allows exactly that.
    enum Direction: String, Sendable {
        case incoming, outgoing
    }

    /// What this connection is called. **Minted with the transport's own
    /// preference in front of it**, so that the connection this layer would
    /// rather use sorts first wherever connections are chosen between — here,
    /// and in the driver, neither of which reads what carries one. See
    /// `ConnectionID.init(_:over:)`.
    let id: ConnectionID
    let direction: Direction
    /// What carries it. **The transport's own business**: it is spent naming
    /// the connection and asking the path what it can say for itself, and it
    /// reaches no seam.
    let kind: NearbyLinkKind

    private(set) var isReady = false
    /// The device the transport resolved behind this connection — the identity
    /// it sent for itself, which is the only thing a connection is ever named
    /// by. Nothing until the exchange has settled it, and the driver is not
    /// told of the connection before then.
    private(set) var peer: PeerDeviceID?
    /// What that device is called, for the screen alone. Nothing keys on it.
    private(set) var peerName: String?
    private(set) var signalStrength: Double?
    /// The pairing record behind a radio connection, where the platform names
    /// one. It is not the peer's identity: it is what the identity learned here
    /// is remembered against, so that the room can show one row for a device it
    /// is both paired with and browsing before anything has dialled it.
    @ObservationIgnored private var pairing: PeerDeviceID?

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
    /// The identifier the other device sent for itself. The receive loop is the
    /// only reader of the wire, so what it sees travels here rather than being
    /// waited for on a stream two things are consuming.
    @ObservationIgnored private let linkage: AsyncStream<String>
    @ObservationIgnored private let linkageFeed: AsyncStream<String>.Continuation

    /// How long a connection may sit short of `.ready` before it is dropped so
    /// the browser loop can try again. Measured on the two devices: a healthy
    /// connection is ready in well under a second, and one that is not ready
    /// after this is holding radio resources for nothing. Eight seconds rather
    /// than the spike's twenty, because a stuck attempt costs the whole window
    /// before the retry that does connect.
    ///
    /// It is also how long the identity exchange has: a connection that is
    /// usable but has not said who it is is as useless as one that never became
    /// usable, and it is dropped for the same reason and after the same wait.
    private static let readyWindow = Duration.seconds(8)

    init(_ channel: NearbyChannel, direction: Direction, kind: NearbyLinkKind) {
        self.channel = channel
        self.direction = direction
        self.kind = kind
        self.id = ConnectionID(channel.id, over: kind)
        (readiness, readinessFeed) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (linkage, linkageFeed) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    // MARK: - NearbyLink

    /// One protocol message, wrapped on its way out. The driver hands over a
    /// message and nothing else, and what the wire carries is this layer's.
    func send(_ message: BoardGameMessage) async throws {
        guard let channel else { throw CancellationError() }
        try await channel.send(.message(message))
    }

    // MARK: - NearbyLinkageExchange

    /// Who this device is, said once, before the driver is told anything.
    func sendLinkage(_ identifier: String) async throws {
        guard let channel else { throw CancellationError() }
        try await channel.send(.linkage(.init(id: identifier)))
    }

    /// Who the other device says it is, for as long as the window allows.
    ///
    /// **It is asked once, and answered once for the connection's whole life.**
    /// The stream is closed on the first arrival, so a second linkage frame is
    /// discarded by the receive loop's own `yield` rather than acted on: a peer
    /// cannot re-identify itself half way through a connection. That is
    /// load-bearing rather than tidy — the contract's identity is the same
    /// "behind every connection to that peer … and unchanged for as long as a
    /// session with that peer stands", and a peer that could rename itself
    /// under a standing session would be answered by the engine with an
    /// unknown-session void or a violation close, which is a game destroyed.
    /// Whatever a peer sends after it has said who it is, it has said who it is.
    func linkageArrived(within window: Duration) async -> String? {
        let watchdog = Task { [self] in
            try? await Task.sleep(for: window)
            linkageFeed.finish()
        }
        defer { watchdog.cancel() }

        for await identifier in linkage {
            linkageFeed.finish()
            return identifier
        }
        return nil
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
            for try await (frame, _) in channel.messages {
                switch frame {
                case .linkage(let linkage):
                    // The transport's own, and it stops here: the driver is
                    // handed protocol messages and nothing else, so neither it
                    // nor the engine can tell a frame exists.
                    linkageFeed.yield(linkage.id)
                case .message(let message):
                    if isOpen {
                        driver.received(message, on: id)
                    } else {
                        // The other peer's hello can land in the instant between
                        // this connection being usable and the driver being told
                        // of it. It waits rather than arriving for a connection
                        // the engine does not hold yet.
                        waiting.append(message)
                    }
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

    /// Readiness, who is behind it, and the handover to the driver — in that
    /// order, and the driver hears nothing until the last of them.
    ///
    /// **The identity is settled here or the connection does not open.** This
    /// is the one place a peer is named, which is what makes one identity per
    /// peer a fact of the code: there is no later moment at which a connection
    /// could acquire a second one, and no connection the driver holds that was
    /// named by anything else.
    private func open(_ channel: NearbyChannel, driver: NearbyDriver, log: NearbyLog) async {
        guard await becomesReady(channel, log: log) else {
            log.note("Connection \(NearbyDriver.short(id)) never became ready — dropping it "
                     + "so the loop can try again.")
            close()
            return
        }
        isReady = true
        guard await resolvePairing(of: channel, log: log) else { return }

        guard let peer = await NearbyIdentity.resolve(over: self, pairing: pairing,
                                                      within: Self.readyWindow)
        else {
            // Either this device could not say who it is, which means the link
            // is already dying, or the other device never said — and a
            // connection with nobody behind it is a connection with nothing to
            // do. The loop dials again.
            log.note("Connection \(NearbyDriver.short(id)) named nobody — dropping it.")
            close()
            return
        }
        self.peer = peer
        log.note("Connection \(NearbyDriver.short(id)) reaches ",
                 naming: peerName ?? "an unnamed device",
                 " (\(peer.rawValue)).")

        driver.connectionReady(self, with: peer)
        isOpen = true
        let held = waiting
        waiting = []
        for message in held { driver.received(message, on: id) }
    }

    /// The pairing record behind a radio connection, where there is one to
    /// find: the name a row can carry, the signal, and the pairing the identity
    /// exchange will be remembered against. A radio connection with no path
    /// behind it has nothing to say for itself and is dropped, as it always
    /// was; a network connection has no pairing at all, which is not a fault.
    private func resolvePairing(of channel: NearbyChannel, log: NearbyLog) async -> Bool {
        guard kind == .radio else { return true }
        guard let path = await wifiAwarePath(of: channel) else {
            log.note("Connection \(NearbyDriver.short(id)) reported no Wi-Fi Aware path, so "
                     + "there is no device behind it — dropping it.")
            close()
            return false
        }
        pairing = nearbyPairingID(of: path.endpoint.device)
        peerName = path.endpoint.device.displayName
        signalStrength = path.performance.signalStrength
        return true
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

/// Both paths — the publisher and the subscriber on the radio, the listener and
/// the browser on the network — and the connections all four bring up.
@MainActor
@Observable
final class NearbyTransport {
    let driver: NearbyDriver
    let log: NearbyLog

    private(set) var isRunning = false
    private(set) var listenerState = "stopped"
    private(set) var browserState = "stopped"
    /// The network half's own state, written by it — the two loops live in
    /// `NearbyNetwork.swift`, which is a file boundary rather than an ownership
    /// one.
    var networkListenerState = "stopped"
    var networkBrowserState = "stopped"
    private(set) var pairedDevices: [WAPairedDevice] = []
    /// What is advertising itself on the network right now, under the identity
    /// each advertises and the label it carries. It is a live fact and it
    /// empties when the transport stops, which is what makes a device's row
    /// there mean "its player is in nearby play" rather than "it has the app".
    var advertised: [NearbyPeer] = []
    private(set) var connections: [NearbyConnection] = []

    @ObservationIgnored private var listenerTask: Task<Void, Never>?
    @ObservationIgnored private var browserTask: Task<Void, Never>?
    @ObservationIgnored var networkListenerTask: Task<Void, Never>?
    @ObservationIgnored var networkBrowserTask: Task<Void, Never>?
    @ObservationIgnored private var pairedDevicesTask: Task<Void, Never>?
    /// Whether the browser loop is holding off because a connection stands. It
    /// says so once rather than every time it looks.
    @ObservationIgnored private var isHolding = false
    /// The advertisements this device is dialling right now, by the endpoint's
    /// own name. Two dials to one endpoint would be two connections nothing
    /// asked for; the crossing the other device may be making at the same
    /// instant is a different thing, and the contract leaves both standing.
    @ObservationIgnored var dialling: Set<String> = []

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
                    #if DEBUG
                    // Which of the two names a record actually carries is the
                    // one thing about this that only a pair of real devices can
                    // answer, and the ceremony is asymmetric enough that the
                    // answer differs by side. Both names stay private in the
                    // system log and are whole in this device's own console.
                    for device in pairedDevices {
                        log.note("Record \(device.id) name: ", naming: device.name ?? "—")
                        log.note("Record \(device.id) pairing name: ",
                                 naming: device.pairingInfo?.pairingName ?? "—")
                    }
                    #endif
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

    /// **One bracket for both paths.** Everything that listens or dials starts
    /// here and stops in `stop()`, so the two are up together, down together,
    /// and unobservably alike from anywhere above. It is the surfaces' own
    /// bracket — a nearby page opening, and anything still owed to somebody —
    /// and it is entered from a user action or a return to the foreground,
    /// which is what puts the system's local-network prompt where it belongs:
    /// in front of somebody who has just asked for this.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        log.note("Starting \(NearbyService.name).")
        startRadio()
        startNetwork()
    }

    private func startRadio() {
        #if DEBUG
        // A driven run proving what happens when one path goes away holds the
        // other down from the start. Debug builds only, and no release build
        // compiles it.
        guard NearbyLaunch.current.runsRadio else {
            log.note("The radio is held down by this run's arguments.")
            return
        }
        #endif
        // Hardware with no radio starts nothing here and everything on the
        // other path: the feature is not the radio's, and a publisher looping
        // against a radio that does not exist would burn a retry every two
        // seconds for a device that is playing perfectly well.
        guard Self.isSupported else {
            log.note("No radio on this device — the local network is the whole reach.")
            return
        }
        guard NearbyService.publishable != nil, NearbyService.subscribable != nil else {
            log.note("The service \(NearbyService.name) is missing from WiFiAwareServices.")
            return
        }
        log.note("Publishing and subscribing together.")
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
        stopNetwork()
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
                    using: radioParameters()
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
                    await adopt(channel, direction: .incoming, kind: .radio)
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
                guard !isConnected(to: identity(of: device)) else {
                    if !isHolding {
                        isHolding = true
                        log.note("Already connected to ",
                                 naming: device.displayName ?? "that device",
                                 " — waiting rather than dialling again.")
                    }
                    try? await Task.sleep(for: .seconds(4))
                    continue
                }
                isHolding = false
                log.note("Discovered ", naming: device.displayName ?? "an unnamed device",
                         " — dialling.")

                let channel = NearbyChannel(to: endpoint, using: radioParameters())
                // One outgoing connection at a time: the next browse waits for
                // this one to be over, whether it was ready or the first cold
                // attempt the radio refused.
                await adopt(channel, direction: .outgoing, kind: .radio)?.value
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
    func isConnected(to peer: PeerDeviceID) -> Bool {
        connections.contains { $0.isReady && $0.peer == peer }
    }

    /// What a paired device is known as: the identity behind the pairing where
    /// this device has learned one, and the pairing record until it has.
    private func identity(of device: WAPairedDevice) -> PeerDeviceID {
        let pairing = nearbyPairingID(of: device)
        return NearbyIdentity.linked(to: pairing) ?? pairing
    }

    /// Every connection that stands, as the room considers them. A device
    /// reachable both ways is dealt with over the network, because that is the
    /// path that reaches through a wall and the one whose loss is a room away
    /// rather than a house away — and that preference is already spent by the
    /// time a candidate exists, in the name the connection was minted with.
    var candidates: [NearbyCandidate] {
        connections.filter(\.isReady).compactMap { connection in
            guard let peer = connection.peer else { return nil }
            return NearbyCandidate(connection: connection.id, peer: peer,
                                   name: connection.peerName)
        }
    }

    @discardableResult
    func adopt(_ channel: NearbyChannel, direction: NearbyConnection.Direction,
               kind: NearbyLinkKind) async -> Task<Void, Never>? {
        let connection = NearbyConnection(channel, direction: direction, kind: kind)
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
