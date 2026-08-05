// The nearby feature as the person in front of the screen meets it: whether the
// entry is offered at all, which nearby page is showing, the proposal being
// composed, and the answer a proposal is owed.
//
// docs/interaction-design.md, "Nearby play": the entry is a third row inside
// each game's section on the Play home, shown only where the hardware has the
// radio; the row raises that game's propose sheet, where a device is chosen and
// a side with it, or opens the game already going with somebody; the peer
// answers a consent prompt; and a refusal is presented by its reason rather than
// by its code.
//
// **It holds no protocol logic.** Which proposals may be made, which are
// refused, whose turn it is and when a session is void are the engine's
// answers — reached through the driver, and surfaced here as they come back.
// Where this file reads a session it is asking what to draw, never what the
// contract allows.
//
// **A session belongs to the peer, not to this page.** The driver and the engine
// live for as long as the app does, so leaving the nearby board is the
// interruption the protocol already models rather than the end of anything, and
// coming back finds the session where the two devices left it.
//
// The seams are the driver and the radio. Both are protocols so that this
// object's own behaviour can be tested without a radio in the room — and the
// availability the entry rows are gated on is injected for the same reason,
// since a Simulator has no Wi-Fi Aware and a test has to be able to show both
// states.

import Foundation
import Observation

extension GameKind {
    /// The `rules_id` the BoardGame Protocol names this game by. The rules
    /// oracle holds the same mapping on its own side of the engine, where it
    /// answers what a `rules_id` means; this is the half the surfaces need,
    /// which is what to put in a proposal.
    var rulesID: String {
        switch self {
        case .miniXiangqi: "minixiangqi"
        case .xiangqi: "xiangqi"
        }
    }

    init?(rulesID: String) {
        guard let match = Self.allCases.first(where: { $0.rulesID == rulesID }) else {
            return nil
        }
        self = match
    }
}

/// One device this peer can propose to right now: a ready connection and the
/// paired device behind it.
nonisolated struct NearbyPeer: Identifiable, Equatable, Sendable {
    var connection: ConnectionID
    var peer: PeerDeviceID
    /// The device's own name, for the row alone. Nothing keys on it, and it
    /// never travels: it is the peer's owner's name as often as not.
    var name: String?

    /// The *device*, because two crossed connections to one device are one
    /// device to the person looking at the list.
    var id: PeerDeviceID { peer }
}

/// The radio, as the surfaces need it.
@MainActor
protocol NearbyRadio: AnyObject {
    /// Whether this hardware has Wi-Fi Aware at all.
    var isSupported: Bool { get }
    var isRunning: Bool { get }
    /// Every device with a ready connection, one entry per device.
    var peers: [NearbyPeer] { get }
    func start()
    func stop()
}

/// The driver, as the surfaces need it: this device's own player's intents, and
/// the sessions and refusals the engine answers with.
@MainActor
protocol NearbyDriving: AnyObject {
    var sessions: [BoardGameSession] { get }
    var declines: [NearbyDecline] { get }

    func propose(to peer: PeerDeviceID, on connection: ConnectionID, rulesID: String,
                 proposerMoves: Mover) throws(BoardGameRefusal)
    func answer(_ session: String, accepting: Bool) throws(BoardGameRefusal)
    func play(_ text: String, in session: String) throws(BoardGameRefusal)
    func resign(in session: String) throws(BoardGameRefusal)
}

extension NearbyDriver: NearbyDriving { }

/// Why a game did not start, as the player is told: the other peer's own
/// refusal, or this device's engine declining to make the proposal.
nonisolated enum NearbyRefusal: Equatable, Sendable {
    /// The other peer refused a proposal or a resume, with its reason.
    case declined(DeclineReason)
    /// This device's own engine would not make the proposal.
    case refused(BoardGameRefusal)

    /// The sentence the player reads. Every refusal the protocol has a word for
    /// gets one of its own, because the reasons are things a person can act on —
    /// wait, update, or try another device — and a code is not.
    ///
    /// The key rather than the string, so that this mapping — which is the whole
    /// of the promise that a wire reason reaches the reader as words — can be
    /// pinned without a language being chosen for it.
    var messageKey: String {
        switch self {
        case .declined(.declined): "nearby.refusal.declined"
        case .declined(.busy): "nearby.refusal.busy"
        case .declined(.unknownGame): "nearby.refusal.unknownGame"
        case .declined(.rulesMismatch): "nearby.refusal.rulesMismatch"
        case .declined(.unknownSession): "nearby.refusal.unknownSession"
        // One nearby game at a time per peer is the engine's law, and these two
        // are the two ways it says so: a live session, and a proposal already
        // outstanding.
        case .refused(.peerIsBusy), .refused(.proposalOutstanding):
            "nearby.refusal.alreadyPlaying"
        // The pair's last game is still settling between the two devices, which
        // is the one refusal that passes on its own.
        case .refused(.lingeringSessionUnsettled): "nearby.refusal.settling"
        // Everything else is a connection that went away between the tap and
        // the send, or a state the surfaces should not have offered the act in.
        // There is nothing to explain and something to try again.
        case .refused: "nearby.refusal.notNow"
        }
    }
}

@MainActor
@Observable
final class NearbyFlow {
    let driver: any NearbyDriving
    let radio: any NearbyRadio
    /// The positions a nearby board draws, which the board's own model asks.
    /// Held here because this object is the nearby feature's one dependency set
    /// and the board is opened from it.
    let positions: any NearbyPositions

    /// Whether the Play home offers nearby at all. Injected rather than read
    /// here: the answer belongs to the hardware, and a test has to be able to
    /// show a screen with the rows and a screen without them.
    let isAvailable: Bool

    /// The propose sheet, up for the game whose row raised it: pairing, the
    /// devices in the room, the side this device would take, and the invitation.
    private(set) var proposing: GameKind?

    /// The session the board is showing, if the board is up. It is a page over
    /// the Play destination rather than a sheet, because it is a game.
    private(set) var boardSessionID: String?

    /// Which mover this device takes in the proposal it is composing. The
    /// proposer chooses; the peer takes the other side.
    var proposerMoves: Mover = .first

    /// Which device the invitation would go to. The first one in the room by
    /// default, since a room usually has exactly one.
    var chosenPeer: PeerDeviceID?

    /// The refusal waiting to be read, if one is.
    private(set) var refusal: NearbyRefusal?

    /// The session whose result the player has put away. It is held here rather
    /// than on the board because it is a fact about the *game*: the notice does
    /// not present itself again for the same result, and walking off the board
    /// and back is not seeing a new one.
    private(set) var dismissedResultOf: String?

    /// How many of the driver's refusals have been presented. The driver's list
    /// only grows, so the count is the whole of what "already seen" means.
    private var declinesSeen = 0

    init(driver: any NearbyDriving, radio: any NearbyRadio,
         positions: any NearbyPositions, isAvailable: Bool) {
        self.driver = driver
        self.radio = radio
        self.positions = positions
        self.isAvailable = isAvailable
    }

    /// Whether nearby is offered on this device. iPhone and iPad only — the
    /// entitlement is signed for those two and the system pairing UI does not
    /// exist on the Mac — and, there, only where the hardware has the radio.
    static func isAvailableHere(_ radio: any NearbyRadio) -> Bool {
        #if os(iOS)
        #if DEBUG
        // A Simulator has no Wi-Fi Aware, so the state a UI test cannot reach is
        // the one where the rows are *there*. Both states are named explicitly,
        // because a test that asserts the rows are hidden proves nothing unless
        // some other launch shows them.
        if let forced = DebugLaunch.argument(after: "-mxq-nearby-capable") {
            return forced == "1"
        }
        #endif
        return radio.isSupported
        #else
        return false
        #endif
    }

    // MARK: - What stands with the peers

    /// The proposal this device is being asked to answer, if one stands. At most
    /// one does: the contract allows one proposed or active session per pair,
    /// and this device is one of the pair.
    var invitation: BoardGameSession? {
        driver.sessions.first { $0.state == .proposed && $0.proposer == .peer }
    }

    /// The proposal this device made and is waiting on, if it is waiting.
    var invited: BoardGameSession? {
        driver.sessions.first { $0.state == .proposed && $0.proposer == .local }
    }

    /// The game this device is playing with somebody, if it is playing one.
    var liveSession: BoardGameSession? {
        driver.sessions.first { $0.state == .active }
    }

    /// The session the board is showing, if the board is showing one.
    var boardSession: BoardGameSession? {
        guard let boardSessionID else { return nil }
        return driver.sessions.first { $0.id == boardSessionID }
    }

    /// The devices the invitation may go to, and the one it would go to.
    var peers: [NearbyPeer] { radio.peers }

    var chosenDevice: NearbyPeer? {
        peers.first { $0.peer == chosenPeer } ?? peers.first
    }

    /// Whether anything is still owed between this device and another: a game
    /// being played, a proposal outstanding, or a finished game this device has
    /// not settled. It is what keeps the radio up after the pages have been
    /// left.
    var holdsSomething: Bool {
        driver.sessions.contains { $0.state != .ended || !$0.settled }
    }

    // MARK: - Navigation

    /// A nearby row on the Play home: the game already going with somebody, or
    /// the sheet that offers one.
    ///
    /// The row leads to the standing game the way the home's own card does,
    /// rather than through a second surface for finding it again — but only
    /// where that game is this row's game, since the row names one.
    func open(_ game: GameKind) {
        wake()
        if let live = liveSession, live.rulesID == game.rulesID {
            openBoard(live.id)
            return
        }
        proposing = game
    }

    /// Into a session's board — from the sheet when a proposal is answered, and
    /// from the consent prompt when this device accepts one.
    func openBoard(_ session: String) {
        proposing = nil
        boardSessionID = session
        wake()
    }

    /// The sheet was put away. The proposal it may have sent stands: nothing in
    /// the protocol withdraws one, and the board opens by itself when the answer
    /// comes.
    func dismissSheet() {
        proposing = nil
        restIfIdle()
    }

    /// The back control over the nearby board. The session stays exactly as it
    /// is — leaving a board is the interruption the protocol already models —
    /// and the Play home's own row is the way back into it.
    func leaveBoard() {
        boardSessionID = nil
        restIfIdle()
    }

    // MARK: - Proposing, and answering

    /// Offer this game to that device, on the side being composed.
    func invite(_ device: NearbyPeer, to game: GameKind) {
        do {
            try driver.propose(to: device.peer, on: device.connection,
                               rulesID: game.rulesID, proposerMoves: proposerMoves)
        } catch {
            refusal = .refused(error)
        }
    }

    /// The consent prompt's two answers. Accepting opens the board at once: the
    /// game has begun, and the board is where it is played.
    func accept(_ session: String) {
        do {
            try driver.answer(session, accepting: true)
            openBoard(session)
        } catch {
            refusal = .refused(error)
        }
    }

    func decline(_ session: String) {
        try? driver.answer(session, accepting: false)
    }

    /// The sessions moved. A proposal this device made and the peer accepted is
    /// a game in progress, so the board opens on it — the same arrival the
    /// accepting device already had.
    func sessionsChanged() {
        if proposing != nil, let live = liveSession {
            openBoard(live.id)
        }
        // A refusal the other peer sent reaches the player here rather than in
        // the driver, which records them and judges none of them.
        if driver.declines.count > declinesSeen {
            declinesSeen = driver.declines.count
            refusal = driver.declines.last.map { .declined($0.reason) }
        }
    }

    func dismissRefusal() {
        refusal = nil
    }

    /// The result notice was put away. Closing it decides nothing about the
    /// game: the turn status still carries the result, and the way out is still
    /// in the controls behind it.
    func dismissResult(of session: String) {
        dismissedResultOf = session
    }

    // MARK: - The radio

    /// The radio runs while nearby is being used and while anything is owed to
    /// a peer, and not otherwise: a device with no nearby surface up and no
    /// session standing has nobody to be discovered by.
    private func wake() {
        guard isAvailable, radio.isSupported, !radio.isRunning else { return }
        radio.start()
    }

    private func restIfIdle() {
        guard proposing == nil, boardSessionID == nil, !holdsSomething,
              radio.isRunning else { return }
        radio.stop()
    }
}
