// Online's carrier: the Game Center match. GameKit delivers each payload whole,
// so a message is its own JSON and nothing frames it, and the other player's
// Game Center id is who they are. Matches arrive from `OnlineParty`, never by
// discovery, so a match that ends stays ended until the two invite each other
// again.

import Foundation
import GameKit
import Observation

@MainActor
@Observable
final class OnlineTransport: PeerCarrier {
    private let engine: PeerEngine
    @ObservationIgnored private var matches: [OnlineMatch] = []

    private(set) var isRunning = false
    var discovered: [NearbyPeer] { [] }
    var interruption: LinkInterruption { .lasting }

    init(engine: PeerEngine) {
        self.engine = engine
    }

    func adopt(_ match: GKMatch) {
        let link = OnlineMatch(match, engine: engine)
        link.ended = { [weak self, weak link] in self?.matches.removeAll { $0 === link } }
        matches.append(link)
        match.delegate = link
        link.connectIfReady()
    }

    func start() { isRunning = true }
    func stop() { isRunning = false }
}

/// One match, as the engine's link to the player in it.
@MainActor
private final class OnlineMatch: NSObject, PeerLink, GKMatchDelegate {
    private var match: GKMatch?
    private let engine: PeerEngine
    private var isOpen = false
    var ended: (() -> Void)?

    init(_ match: GKMatch, engine: PeerEngine) {
        self.match = match
        self.engine = engine
    }

    func send(_ message: PeerMessage) {
        guard let match, let data = try? JSONEncoder().encode(message) else { return }
        try? match.send(data, to: match.players, dataMode: .reliable)
    }

    func close() {
        finish()
    }

    /// The match is usable once nobody else is expected in it.
    func connectIfReady() {
        guard !isOpen, let match, match.expectedPlayerCount == 0,
              let player = match.players.first else { return }
        isOpen = true
        engine.opened(self, peer: player.gamePlayerID, name: player.displayName)
    }

    private func finish() {
        guard let match else { return }
        self.match = nil
        match.delegate = nil
        match.disconnect()
        if isOpen { engine.closed(self) }
        ended?()
    }

    nonisolated func match(_ match: GKMatch, didReceive data: Data,
                           fromRemotePlayer player: GKPlayer) {
        guard let message = try? JSONDecoder().decode(PeerMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.engine.received(message, from: self) }
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer,
                           didChange state: GKPlayerConnectionState) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                switch state {
                case .connected: self.connectIfReady()
                case .disconnected: self.finish()
                default: break
                }
            }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.finish() }
        }
    }

    nonisolated func match(_ match: GKMatch,
                           shouldReinviteDisconnectedPlayer player: GKPlayer) -> Bool {
        false
    }
}
