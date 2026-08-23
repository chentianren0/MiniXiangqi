// What carries the BoardGame Protocol between two players over Game Center.
//
// The protocol contract names no transport and asks four things of whatever
// carries it: whole messages rather than bytes a peer must frame for itself; a
// stable peer identity behind every connection, exactly one per peer whatever
// carries it; room for more than one connection between one pair of peers; and
// an authenticity and privacy that belong to the carrier rather than to the
// protocol. A `GKMatch` answers all four, and answers three of them more
// directly than the local paths do: GameKit delivers whole payloads, so nothing
// frames anything; Game Center has already named the player, so no exchange
// settles who is there (`OnlineIdentity`); and the account it authenticated is
// the authenticity, with no cryptography of ours anywhere here either.
//
// **This is a second implementation of one seam, not a second seam.** The
// driver above is the same driver and the engine is the same engine, and
// neither can tell what a connection is made of: `NearbyLink` gives them a
// name, a send and a close. Nothing but `BoardGameMessage` goes on this wire —
// `hello`, the proposals, the deal handshake, `resume` and the close verdicts
// are all the engine's, and they arrive through this seam exactly as they do
// over Wi-Fi Aware. There is no frame around them here: `NearbyFrame` exists to
// carry the local paths' identity exchange, and this transport has none, so a
// payload *is* the message's own JSON and nothing composes the bytes twice.
//
// # The death and the refusal
//
// The contract forces one split and punishes getting it backwards. A connection
// that **died** leaves its session interrupted and resumable; an **unreadable**
// arrival is malformed, which is a protocol violation, which closes the
// connection and leaves the session **void**. They are different outcomes for
// the players, not different log lines.
//
// **The split is drawn by which callback spoke, and nothing has to classify an
// error at all.** That is the one way this path is easier than the local one,
// where a single throwing stream carried both and the breadth of "anything that
// is not the connection's own end" had to stand in for the coder's refusal.
//
// A **death** is either of the two things GameKit says about the match itself:
//
//   - `match(_:player:didChange:)` with `.disconnected` — the other player left,
//     lost the network, or was disconnected by this device's own `close()`.
//   - `match(_:didFailWithError:)` — GameKit could not keep the local player
//     connected to anybody in the match.
//
// A **refusal** is one thing and only one: a payload that `BoardGameMessage`'s
// own strict decoder will not read. There is no framing to fail here and no
// stream error to mistake for one, so "unreadable" means exactly what the
// protocol means by malformed, and nothing else can reach that branch.
//
// **The trap on this path is the mirror of the local one's.** There the danger
// was reading a coder's refusal as a death, because everything arrived as a
// thrown error. Here nothing throws at all: GameKit's receive callback has no
// failure to report and never will, so a death that `didChange` does not report
// is a death nobody learns of — the driver would go on holding a link to a
// player who has gone, the engine would keep a session it could never resume,
// and no radio timeout would ever come along to end it. A player transitioning
// to disconnected is therefore load-bearing rather than informational, and it
// is the whole of what says a connection ended.
//
// # What is decided here
//
// Readiness, the buffer that holds what arrives before it, the decode, and the
// death — every one of them reachable without a network, a match, or a second
// signed-in player. GameKit's callbacks reduce its objects to values and hand
// them to those decisions, which is why what this layer actually decides can be
// proved.

import Foundation
import GameKit
import Observation

/// The whole of what a connection does to the match beneath it: put one payload
/// on the wire, and leave.
///
/// A seam rather than calls on `GKMatch` directly, for the reason
/// `NearbyLinkageExchange` is one: what this layer decides is load-bearing, and
/// it has to be provable without two signed-in accounts and a network between
/// them.
@MainActor
protocol OnlineMatchChannel: AnyObject {
    /// One payload to the other player, whole and in order.
    ///
    /// Throwing is the connection dying, which is what `NearbyLink.send`
    /// promises the driver.
    func sendReliably(_ payload: Data) throws
    /// Leave the match. The other player sees the local player disconnect,
    /// which is their connection's death and their session's interruption.
    func disconnect()
}

extension GKMatch: OnlineMatchChannel {
    /// **`.reliable`, always.** The protocol's model is one reliable ordered
    /// stream per direction, and reliable is the mode that gives both: whole
    /// messages, delivered, in the order they were sent. Unreliable is the mode
    /// a game of positions per frame would want, and this is a game of moves —
    /// a move that arrives out of order or not at all is not a faster game, it
    /// is a violation and a void session.
    func sendReliably(_ payload: Data) throws {
        try send(payload, to: players, dataMode: .reliable)
    }
}

/// One live match, and the whole of what the driver may do with it.
@MainActor
@Observable
final class OnlineConnection: NSObject, NearbyLink, GKMatchDelegate {

    /// What this connection is called. Minted fresh for every match — see
    /// `OnlineTransport.mintName()`, which owns why.
    let id: ConnectionID

    /// The player Game Center named behind this match. Nothing until the match
    /// is usable, and the driver is not told of the connection before then.
    private(set) var peer: PeerDeviceID?
    /// What Game Center calls that player, for the screen alone. Nothing keys
    /// on it, and it never travels.
    private(set) var peerName: String?

    /// Told once, when this connection's life is over, so the transport can let
    /// go of it. The transport sets it; nothing else reads it.
    @ObservationIgnored var whenFinished: (@MainActor () -> Void)?

    @ObservationIgnored private let driver: NearbyDriver
    @ObservationIgnored private let log: NearbyLog
    /// The match, released when this connection's life ends.
    @ObservationIgnored private var match: (any OnlineMatchChannel)?
    /// Whether the driver has been told of this connection. Until it has, the
    /// engine holds nothing for it and an arrival has nowhere to go.
    @ObservationIgnored private var isOpen = false
    /// Whether its life is over. It latches: a connection dies once, however
    /// many ways GameKit finds to say so.
    @ObservationIgnored private var isFinished = false
    /// What arrived before the driver was told, still as bytes.
    @ObservationIgnored private var waiting: [Data] = []

    init(id: ConnectionID, over match: any OnlineMatchChannel,
         driver: NearbyDriver, log: NearbyLog) {
        self.id = id
        self.match = match
        self.driver = driver
        self.log = log
        super.init()
    }

    // MARK: - NearbyLink

    /// One protocol message, as its own JSON and nothing else.
    ///
    /// **It throws only when the link is already dying**, which is what the
    /// driver reads a throw as. A match this connection has let go of is one
    /// such link; a send GameKit refuses is the other. The encode is inside the
    /// same promise deliberately: a message this device could not compose is
    /// not a connection it can go on speaking over, and the driver's answer to
    /// a throw — close it, and let the session stay resumable — is the right
    /// one for that too.
    func send(_ message: BoardGameMessage) async throws {
        guard let match else { throw CancellationError() }
        try match.sendReliably(JSONEncoder().encode(message))
    }

    /// Close the connection: a close verdict of the engine's, or the harness's
    /// Stop.
    ///
    /// **It tears down where it stands.** Nothing is awaited and nothing is
    /// scheduled — when this returns the match is disconnected, the buffer is
    /// gone, and no further arrival can reach the driver.
    ///
    /// **It reports no death**, and that is deliberate rather than an omission.
    /// Both of the driver's callers have already accounted for the connection
    /// by the time they call this: a close verdict forgets the connection
    /// before closing it, and `closeEverything()` reports the death itself. A
    /// call back into the driver from here would re-enter it in the middle of
    /// the effect loop that asked for the close, to tell it something it just
    /// said.
    func close() {
        guard !isFinished else { return }
        log.note("Closing the online connection \(NearbyDriver.short(id)).")
        finish()
    }

    // MARK: - What the match reports

    /// The match is usable and Game Center has named the player behind it.
    ///
    /// **This is the one place a connection is opened**, which is what makes
    /// one identity per peer a fact of the code rather than a rule somebody has
    /// to keep: there is no later moment at which this connection could acquire
    /// a second identity, and a second arrival here is ignored rather than
    /// renaming a peer under a standing session.
    func becameUsable(reaching peer: PeerDeviceID, named name: String) {
        guard !isFinished, !isOpen else { return }
        self.peer = peer
        self.peerName = name
        log.note("The online connection \(NearbyDriver.short(id)) reaches ",
                 naming: name, " (\(peer.rawValue)).")
        driver.connectionReady(self, with: peer)
        isOpen = true
        let held = waiting
        waiting = []
        for payload in held { deliver(payload) }
    }

    /// One payload arrived from the other player.
    func payloadArrived(_ payload: Data) {
        guard !isFinished else { return }
        guard isOpen else {
            // The other player's `hello` can land in the instant between the
            // match becoming usable and the driver being told of it. It waits
            // rather than arriving for a connection the engine does not hold
            // yet — and it waits **as bytes**, so that a payload the codec will
            // refuse keeps its place in the arrival order too. Reading it early
            // would give the refusal to a connection the driver has never heard
            // of, which is a violation announced against nothing.
            waiting.append(payload)
            return
        }
        deliver(payload)
    }

    /// The other player is no longer connected to the match. **A death**: the
    /// session is interrupted and resumable, and a later game with them is a
    /// fresh invitation the protocol's resume reconciles.
    func playerLeft() {
        died("the other player disconnected")
    }

    /// GameKit could not keep this device connected to the match. **A death**,
    /// for the same reason and with the same outcome.
    func matchFailed(_ reason: String) {
        died("the match failed — \(reason)")
    }

    /// One payload, decoded or refused. The driver logs both, so nothing here
    /// says it twice.
    private func deliver(_ payload: Data) {
        guard let message = try? JSONDecoder().decode(BoardGameMessage.self,
                                                      from: payload)
        else {
            driver.receivedUnreadable(on: id)
            return
        }
        driver.received(message, on: id)
    }

    /// The connection's end, said once.
    ///
    /// **The transport lets go before the driver is told.** The room is drawn
    /// from the connections the transport holds and the driver's own answer
    /// republishes the surfaces, so telling the driver first would redraw a room
    /// that still contained the player who has just gone.
    ///
    /// **Only a connection the driver knows about has a death to report.** A
    /// match that failed before it reached anybody was never handed over, so
    /// there is nothing for the driver to forget and nothing for the engine to
    /// interrupt.
    private func died(_ why: String) {
        guard !isFinished else { return }
        log.note("The online connection \(NearbyDriver.short(id)) ended: \(why).")
        let wasOpen = isOpen
        finish()
        if wasOpen { driver.connectionDied(id) }
    }

    private func finish() {
        isFinished = true
        isOpen = false
        waiting = []
        match?.disconnect()
        match = nil
        whenFinished?()
    }

    // MARK: - GameKit's side of it

    /// The player a match reaches, once it reaches one.
    ///
    /// `GKMatch.players` holds the remote players alone, and
    /// `expectedPlayerCount` is what says everybody the match is waiting for has
    /// arrived. Both are the readiness: a match still waiting is a match with
    /// nobody to play, and a connection is handed to the driver only when there
    /// is somebody behind it and something to say to them.
    nonisolated static func opponent(of match: GKMatch) -> GKPlayer? {
        guard match.expectedPlayerCount == 0 else { return nil }
        return match.players.first
    }

    nonisolated func match(_ match: GKMatch, didReceive data: Data,
                           fromRemotePlayer player: GKPlayer) {
        onMain { $0.payloadArrived(data) }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer,
                           didChange state: GKPlayerConnectionState) {
        switch state {
        case .connected:
            guard let opponent = Self.opponent(of: match) else { return }
            let peer = OnlineIdentity.peer(opponent.gamePlayerID)
            let name = opponent.displayName
            onMain { $0.becameUsable(reaching: peer, named: name) }
        case .disconnected:
            onMain { $0.playerLeft() }
        // `.unknown` is GameKit's *initial* state for a player rather than
        // something that happened to one, and it says nothing about whether the
        // connection stands. Reading it as a death would end games nobody left.
        default:
            break
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        let reason = error.map { String(describing: $0) } ?? "no reason given"
        onMain { $0.matchFailed(reason) }
    }

    /// **No.** A reinvited player would come back on this same match under this
    /// same connection, and the driver would never learn that anything had
    /// happened: no death, no fresh `connectionReady`, and therefore no resume —
    /// the protocol's own way of picking a game up would never run, and the two
    /// devices would go on from wherever each of them thought the game was.
    /// Online play has no ambient rediscovery by design; coming back is a fresh
    /// invitation or a party code, on which resume reconciles the game unchanged.
    nonisolated func match(_ match: GKMatch,
                           shouldReinviteDisconnectedPlayer player: GKPlayer) -> Bool {
        false
    }

    /// The hop from wherever GameKit spoke to where the decisions live.
    ///
    /// GameKit does not document which queue it calls a match delegate on, and
    /// the order arrivals reach the driver in *is* the protocol's model —
    /// "within each direction the stream preserves order". So this goes through
    /// the main queue, whose FIFO order is exactly the guarantee a detached
    /// `Task` does not give, and then states the isolation the hop bought. A
    /// `@MainActor` class is `Sendable`, so the connection itself crosses;
    /// nothing of GameKit's does, because each callback reduces its objects to
    /// values before handing them over.
    private nonisolated func onMain(
        _ body: @escaping @Sendable @MainActor (OnlineConnection) -> Void
    ) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body(self) } }
    }
}
