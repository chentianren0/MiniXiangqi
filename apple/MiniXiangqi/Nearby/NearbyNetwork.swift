// The local network as a way to reach the other player: a Bonjour registration
// this device answers on, a browse for everybody else's, and plain TCP between
// them.
//
// **Why there is a second path at all.** The paired-device radio picks its own
// channel and the application has no say in it; through a wall, in the next
// room of a home, it is often not enough. A home network is. So the two run
// together — the radio for where there is no infrastructure at all, the network
// for reach — and above this file nothing knows which one a game is on.
//
// **It is plain.** No TLS of ours, no keys, no certificates, no cryptography of
// ours anywhere: the protocol excludes it, and what stands in its place is
// stated rather than invented. The home network's own boundary is the boundary,
// the advertised identity is honest-only and proves nothing, and the gate every
// game passes is the proposal's consent prompt — which the protocol requires of
// every game and which is the same prompt whatever reached this device.
//
// **Nothing personal is broadcast.** The registration's instance name is set
// explicitly, to what kind of device this is and four characters of its own
// identifier. Left alone it would be the system's device name, which is its
// owner's own name as often as not, and a Bonjour registration is a broadcast
// to a whole network. The TXT record carries the identifier and nothing else:
// no name, no version — `hello` states the protocol's — and no state, the
// protocol having words of its own for busy.
//
// The registration and the browse run on exactly the transport's own bracket,
// which is only ever entered from a user action or a return to the foreground.
// That is what puts the system's local-network prompt in front of somebody who
// has just asked for nearby play, and what keeps an undetermined permission
// from being met in the background, where it would be denied in silence.

#if os(iOS)

import Foundation
import Network
import UIKit

/// What the advertisement carries.
nonisolated enum NearbyAdvertisement {
    /// The one TXT key: the sender's own identifier.
    static let identifierKey = "id"
}

extension NearbyTransport {

    /// The stack the network path builds: the same frame coder over the same
    /// TCP the radio uses, and nothing over it.
    private func networkParameters() -> NWParametersBuilder<
        Coder<NearbyFrame, NearbyFrame, NetworkJSONCoder>
    > {
        nearbyStack()
    }

    // MARK: - Start and stop

    /// Both halves at once, exactly as the radio runs its publisher and its
    /// subscriber together: a device is reachable and looking at the same time,
    /// because either side may be the one who invites.
    func startNetwork() {
        let identifier = NearbyIdentity.own()
        let label = NearbyIdentity.label(for: identifier, kind: UIDevice.current.model)
        // The label is safe to log where a device name is not: it is a kind and
        // four characters of an identifier, which is what it is for.
        log.note("On the local network as “\(label)”.")
        networkListenerTask = Task { [self] in
            await runNetworkListener(as: label, saying: identifier)
        }
        networkBrowserTask = Task { [self] in
            await runNetworkBrowser(own: identifier)
        }
    }

    func stopNetwork() {
        networkListenerTask?.cancel()
        networkBrowserTask?.cancel()
        networkListenerTask = nil
        networkBrowserTask = nil
        // The room's network half is a live fact and it stops being true here.
        advertised = []
        dialling = []
        networkListenerState = "stopped"
        networkBrowserState = "stopped"
    }

    // MARK: - Being reachable

    private func runNetworkListener(as label: String, saying identifier: String) async {
        while !Task.isCancelled {
            do {
                try await NetworkListener(
                    for: .bonjour(name: label, type: NearbyService.name, domain: nil,
                                  txtRecord: NWTXTRecord(
                                      [NearbyAdvertisement.identifierKey: identifier])),
                    using: networkParameters()
                )
                .onStateUpdate { [self] _, state in
                    Task { @MainActor in
                        let described = Self.describe(state)
                        guard networkListenerState != described else { return }
                        networkListenerState = described
                        log.note("Network listener: \(described)")
                    }
                }
                // Awaited *inside* the closure, as the radio's is: an early
                // return tears the incoming connection down before adoption can
                // run.
                .run { [self] channel in
                    await adopt(channel, direction: .incoming, kind: .network)
                }
            } catch {
                networkListenerState = "failed"
                log.note("Network listener ended: \(Self.describe(error)).")
            }
            guard !Task.isCancelled else { break }
            try? await Task.sleep(for: .seconds(2))
            log.note("Restarting the network listener.")
        }
    }

    // MARK: - Looking

    /// One standing browse rather than a fresh one per answer. What the network
    /// half has to notice is somebody arriving and somebody leaving, and a
    /// browse that stays up reports both as they happen — which is what makes
    /// the room's "listed while its player is in nearby play" true rather than
    /// nearly true.
    private func runNetworkBrowser(own identifier: String) async {
        while !Task.isCancelled {
            do {
                try await NetworkBrowser(
                    for: .bonjour(NearbyService.name, domain: nil, includeTxtRecord: true)
                )
                .onStateUpdate { [self] _, state in
                    Task { @MainActor in
                        let described = Self.describe(state)
                        guard networkBrowserState != described else { return }
                        networkBrowserState = described
                        log.note("Network browser: \(described)")
                    }
                }
                .run { [self] endpoints in
                    await saw(endpoints, own: identifier)
                }
            } catch {
                networkBrowserState = "failed"
                log.note("Network browser ended: \(Self.describe(error)).")
            }
            guard !Task.isCancelled else { break }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Everything advertising itself right now, as the room and as somebody to
    /// dial.
    ///
    /// **The advertised identifier is a hint and the frame is the answer.** It
    /// is what names a row before anything has connected and what keeps this
    /// device from dialling somebody it is already talking to; the identity a
    /// connection is opened under is the one that arrived on the connection
    /// itself.
    private func saw(_ endpoints: [Bonjour.Endpoint], own identifier: String) async {
        var room: [NearbyPeer] = []
        var seen: Set<String> = []

        for endpoint in endpoints {
            guard let hint = endpoint.txtRecord[NearbyAdvertisement.identifierKey],
                  !hint.isEmpty
            else { continue }
            // This device's own registration comes back on its own browse.
            guard hint != identifier else { continue }
            // One device can be reachable on more than one interface, and so
            // stand at more than one endpoint; it is one device all the same.
            guard seen.insert(hint).inserted else { continue }

            // **A row's words are never the wire's.** The advertised instance
            // name is a string a stranger composed, and identity here is
            // honest-only, so nothing it says is put in front of a reader. The
            // row carries the one neutral label, and the four characters that
            // tell two of them apart come off the identity itself.
            let peer = NearbyIdentity.peer(hint)
            room.append(NearbyPeer(connection: nil, peer: peer, name: nil))

            // Dialling somebody this device is already connected to would
            // replace a healthy connection with a fresh one and cost a resume
            // exchange for nothing. The crossing the other device may be making
            // at this same instant is a different thing, and the contract
            // leaves both standing.
            guard !isConnected(to: peer), !dialling.contains(endpoint.id) else { continue }
            dial(endpoint)
        }

        guard advertised != room else { return }
        advertised = room
        log.note("On the network: \(room.count) device(s).")
    }

    /// One outgoing connection to one advertisement at a time.
    ///
    /// The endpoint's own label goes no further than this line, and it is
    /// written the way a name is written — a string somebody else composed is
    /// treated as one whether or not it looks like a device.
    private func dial(_ endpoint: Bonjour.Endpoint) {
        dialling.insert(endpoint.id)
        log.note("Dialling ", naming: endpoint.name, ".")
        let channel = NearbyChannel(to: endpoint, using: networkParameters())
        Task { [self] in
            await adopt(channel, direction: .outgoing, kind: .network)?.value
            dialling.remove(endpoint.id)
        }
    }
}

#endif
