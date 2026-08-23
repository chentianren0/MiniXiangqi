// The matches this device is playing over, and the room the surfaces read.
//
// The nearby transport is built around discovery, because *finding* the other
// device is the whole problem there. **Here there is nothing to find.** Game
// Center delivers a match — from an invitation the player accepted or a party
// code they entered, both of them the system's own surfaces — and this adopts
// it. There is no publisher, no browser, no discovery, and by design no
// rediscovery: online play stands no reconnection vigil, and coming back to an
// interrupted game is a fresh invitation on which the protocol's resume
// reconciliation picks it up unchanged.
//
// That is why this object is small, and why it is not smaller: what it owns is
// the one thing a connection cannot own for itself — a name no other connection
// of this process has had — plus the hold that keeps a match's delegate alive
// and the room the surfaces read off it.
//
// **Nothing here reaches for a match.** `adopt(_:)` is the door, and what walks
// through it — an accepted invitation, a party code, the matchmaker's own view
// controller — is chosen in `OnlineParty`. What this owns about an arrival is
// the rule that no two live connections ever reach one player, which is kept at
// the instant a connection names the person behind it.

import Foundation
import GameKit
import Observation

@MainActor
@Observable
final class OnlineTransport: NearbyReach {
    let driver: NearbyDriver
    let log: NearbyLog

    private(set) var isRunning = false
    private(set) var connections: [OnlineConnection] = []

    init(driver: NearbyDriver, log: NearbyLog) {
        self.driver = driver
        self.log = log
    }

    // MARK: - Adopting a match

    /// Take up a match Game Center has handed over.
    @discardableResult
    func adopt(_ match: GKMatch) -> OnlineConnection {
        let connection = open(over: match)
        // The delegate first, so that nothing GameKit has to say between here
        // and the readiness read below is missed. It cannot arrive early
        // either: every callback goes through the connection's hop, which runs
        // no sooner than the main queue's next turn, and this whole method is
        // one turn.
        match.delegate = connection
        if let opponent = OnlineConnection.opponent(of: match) {
            connection.becameUsable(reaching: OnlineIdentity.peer(opponent.gamePlayerID),
                                    named: opponent.displayName)
        }
        return connection
    }

    /// The half of an adoption with no GameKit in it: a name no connection has
    /// had before, a connection over the channel, and this transport's hold on
    /// it until its life is over.
    @discardableResult
    func open(over channel: any OnlineMatchChannel) -> OnlineConnection {
        let connection = OnlineConnection(id: Self.mintName(), over: channel,
                                          driver: driver, log: log)
        connection.whenFinished = { [weak self, weak connection] in
            self?.connections.removeAll { $0 === connection }
        }
        connection.whenNaming = { [weak self, weak connection] peer in
            guard let self, let connection else { return }
            letGoOfEverythingReaching(peer, except: connection)
        }
        connections.append(connection)
        log.note("Adopting the online connection \(NearbyDriver.short(connection.id)).")
        return connection
    }

    /// **The single-adoption rule**, kept at the one instant it can be: a
    /// connection has just named the player behind it, and anything else
    /// reaching that same player is let go of before the driver is told of this
    /// one.
    ///
    /// The rule is `OnlineIdentity`'s, and the reason is that an online peer is
    /// a **person**: the driver routes by peer, so a game standing on one
    /// connection would have its resume offered on the other, which is not
    /// holding it and answers `unknown_session` — an answer that voids the
    /// session on both sides. What must never stand is therefore not a second
    /// game but a second *concurrent* connection; one connection after another
    /// is the ordinary way back into an interrupted game.
    ///
    /// **The one standing gives way rather than the fresh one being turned
    /// down.** The fresh match is what the player has just consented to and the
    /// standing one is what their friend walked away from to make it; refusing
    /// would leave them holding a match with nobody at the other end.
    ///
    /// **It is here rather than at the door a match arrives through**, which is
    /// where stage 2 expected it, because a door cannot always answer: GameKit
    /// hands a match over before every player it is waiting for has connected,
    /// and such a match names nobody to compare. A peer becoming known is the
    /// first moment the question has an answer, and it is the same moment
    /// whichever way the match arrived.
    private func letGoOfEverythingReaching(_ peer: PeerDeviceID,
                                           except keeping: OnlineConnection) {
        for connection in connections where connection !== keeping
            && connection.peer == peer {
            connection.replaced()
        }
    }

    /// How many connections this process has named. Never reset, never
    /// consulted for anything else.
    private static var minted = 0

    /// A name no connection of this process has carried before.
    ///
    /// **Identifiers are never reused for the life of the process.** The engine
    /// holds a precondition on that, and it is right to: a match that came back
    /// under an old name would be a new connection the engine believed it
    /// already had, with a session bound to the dead one. Every match — the
    /// first, and every one that replaces it — is therefore a fresh name, a
    /// fresh `connectionReady`, and the driver's own resume machinery does the
    /// rest unaided. Counting is the whole mechanism, because a `GKMatch` has
    /// nothing stable to derive a name from anyway.
    ///
    /// **A room-space of its own, with no rank digit in front of it.** The
    /// nearby transport writes a rank there so that two crossed connections to
    /// one *device* sort into its preference between two local paths. Online has
    /// one path and no such crossing to break: an online peer is a Game Center
    /// player under `OnlineIdentity`'s namespace, which no nearby connection can
    /// ever name, so nothing would ever consult the preference a rank encodes.
    /// A name that begins with a letter is also the name `ConnectionID.name`
    /// gives back whole, which is what a log line and a screen read.
    ///
    /// These sort as text, so past nine connections `online-10` comes before
    /// `online-2` — the trap `NearbyLinkKind` keeps its ranks to one digit to
    /// avoid, and harmless here for the reason above: `NearbyCandidate.ordered`
    /// asks only that the answer be the same every time it is asked, and
    /// between two online connections to one player there is no preference to
    /// get backwards.
    static func mintName() -> ConnectionID {
        minted += 1
        return ConnectionID("online-\(minted)")
    }

    // MARK: - The room

    /// **No.** `hasRadio` is the Wi-Fi Aware pairing section's own question and
    /// nothing else asks it; online play has no pairing ceremony, and no
    /// section that would draw one.
    var hasRadio: Bool { false }

    /// **Yes.** The player names their opponent before there is a room at all —
    /// one friend in the system's own invitation, or one friend they said a
    /// party code to — so whoever arrives is who they picked, and there is
    /// nothing left to choose between.
    var pairsOnArrival: Bool { true }

    /// **Nothing brings a match back.** There is no rediscovery here by design,
    /// so a link that has gone is gone until the two players meet again through
    /// a fresh invitation or code — on which the protocol's own resume picks
    /// the game up unchanged. What the board owes the player meanwhile is not a
    /// wait but the fact that the game is kept.
    var interruption: LinkInterruption { .lasting }

    /// The players in the room: whoever the matches this transport holds have
    /// reached, one row each, under the name Game Center gave them.
    ///
    /// **One source, where nearby has three.** A pairing registry and an
    /// advertisement are both answers to "who is out there", and online has
    /// nobody out there — a player is in this room because a match reaches
    /// them, and for no other reason. A match that has not reached anybody yet
    /// contributes nothing, because a row with no identity behind it is a row
    /// that cannot be proposed to.
    var peers: [NearbyPeer] {
        NearbyCandidate.room(connections.compactMap { connection in
            guard let peer = connection.peer else { return nil }
            return NearbyCandidate(connection: connection.id, peer: peer,
                                   name: connection.peerName)
        })
    }

    /// Nothing to watch. Pairing is the local radio's ceremony and its records
    /// are the system's; Game Center holds no such thing, and this answers that
    /// here so that every caller is the same call.
    func watchPairedDevices() { }

    /// The surfaces' bracket, which has nothing under it.
    ///
    /// It is kept because the seam is one seam and a caller must not have to
    /// know which transport it holds — not because there is anything to start.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        log.note("Online play is open.")
    }

    /// **No match is let go of here.** Nearby's bracket tears its connections
    /// down because its devices find each other again by themselves seconds
    /// later; online play has no rediscovery at all, so a match dropped because
    /// a screen closed is a game neither player could ever pick up — and a
    /// session belongs to the peer rather than to a page. What ends a match is a
    /// close verdict, the harness's Stop, or the other player leaving.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        log.note("Online play is closed.")
    }
}
