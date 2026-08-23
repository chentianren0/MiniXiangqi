// Playing somebody on another device, as the person in front of the screen
// meets it: whether the entry is offered at all, which page is showing, the
// proposal being composed, and the answer a proposal is owed.
//
// docs/interaction-design.md, "Nearby play" and "Online play": the entry is a
// row inside each game's section on the Play home; the row raises that game's
// propose surface, where a side is chosen, or opens the game already going with
// somebody; the peer answers a consent prompt; and a refusal is presented by its
// reason rather than by its code.
//
// **One object, and one of it per way of reaching another device.** "An online
// game is the nearby game in everything but how the two devices reach each
// other", so online play is a second instance of this over a second transport
// rather than a second class beside it: what differs is under the seams below —
// the reach, and the driver's own record of the mode a game is played in — and
// a surface that would tell the two apart is a surface designed wrong.
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
// The seams are the driver and the transport. Both are protocols so that this
// object's own behaviour can be tested with neither a radio in the room nor a
// network under it — and the availability the entry rows are gated on is
// injected for the same reason, since the answer belongs to the platform and a
// test has to be able to show a screen with the rows and a screen without them.

import Foundation
import Observation

/// One device in the room, and the connection a proposal would travel where one
/// is up. How the room is made of what knows about it is `NearbyPeer.room`.
nonisolated struct NearbyPeer: Identifiable, Equatable, Sendable {
    /// The connection to that device, where the transport has one ready.
    ///
    /// **A device is in the room whether or not a connection stands.** A
    /// pairing is the system's own record, made once per pair of devices and
    /// outliving the app; an advertisement on the network is a device whose
    /// player is in nearby play right now; a connection is a thing the
    /// transport dials seconds after it starts and lets go of between moves. So
    /// this is optional, and the row is drawn either way.
    var connection: ConnectionID?
    var peer: PeerDeviceID
    /// What the device is called, for the row alone. Nothing keys on it, and it
    /// never travels: it is the peer's owner's name as often as not.
    var name: String?

    /// The *device*, because two crossed connections to one device are one
    /// device to the person looking at the list.
    var id: PeerDeviceID { peer }
}

/// What this device reaches other devices with, as the surfaces need it.
@MainActor
protocol NearbyReach: AnyObject {
    /// Whether this hardware has the paired-device radio.
    ///
    /// **The pairing entry is the only thing that reads it**, because pairing is
    /// the system's own ceremony over that radio and a device without one has
    /// nothing to pair with. Nothing else gates on it: the feature itself, the
    /// room, and every game stand whether or not the answer is yes, since the
    /// other way of reaching a device asks the hardware for nothing.
    var hasRadio: Bool { get }
    var isRunning: Bool { get }
    /// Every device in the room, one entry per device — the system's pairing
    /// records and whatever is advertising itself on the network, carrying the
    /// connection to each where one is up.
    var peers: [NearbyPeer] { get }

    /// Whether choosing somebody to play is done from the room, or was already
    /// done before anybody was in it.
    ///
    /// The local paths list whoever happens to be reachable, so the room is a
    /// list to pick from and picking is what the propose surface is for. Where
    /// the player names their opponent to the system first — an invitation to
    /// one friend, a code said to one friend — the person who arrives is the
    /// person who was chosen, and a control asking which of them to play would
    /// be asking a question with one answer.
    var playerChoosesFromTheRoom: Bool { get }

    /// What a link that has gone means here, which is the one thing a board
    /// says about a connection.
    var interruption: LinkInterruption { get }

    /// Take up the system's pairing record, which is one of what the room is
    /// made of.
    ///
    /// Idempotent, and deliberately *not* bracketed by `start()` and `stop()`:
    /// pairing is a record the system holds whether or not anything is running.
    /// It is a call rather than something the transport does once, because the
    /// system's snapshots can end on their own and a watch that ended has to be
    /// taken again. Hardware with no radio has no records to watch, and this
    /// answers that for itself so that every caller is the same call.
    func watchPairedDevices()
    func start()
    func stop()
}

/// The driver, as the surfaces need it: this device's own player's intents, and
/// the sessions and refusals the engine answers with.
@MainActor
protocol NearbyDriving: AnyObject {
    var sessions: [BoardGameSession] { get }
    var declines: [NearbyDecline] { get }
    /// How many of this device's own plies the library has refused to record.
    /// It only grows; the board watches it, because a move of the player's own
    /// that the library would not keep is the one thing about a nearby ply they
    /// are owed a word about.
    var ownMoveRefusals: Int { get }

    func propose(to peer: PeerDeviceID, on connection: ConnectionID, rulesID: String,
                 proposerMoves: Mover) throws(BoardGameRefusal)
    func answer(_ session: String, accepting: Bool) throws(BoardGameRefusal)
    func play(_ text: String, in session: String) throws(BoardGameRefusal)
    func resign(in session: String) throws(BoardGameRefusal)

    /// The claimed draw, which travels as an ordinary ply.
    func claim(in session: String) throws(BoardGameRefusal)
    func offerDraw(in session: String) throws(BoardGameRefusal)
    func acceptDraw(in session: String) throws(BoardGameRefusal)
    func requestUndo(keeping keep: Int, in session: String) throws(BoardGameRefusal)
    func acceptUndo(in session: String) throws(BoardGameRefusal)

    /// Whether the claimed draw stands for this device's player. The engine's
    /// own oracle answers it — the same question the engine asks when the claim
    /// is played — so the affordance and the legality are one answer.
    func claimStands(in session: BoardGameSession) -> Bool

    /// Take up the interrupted nearby game the library holds, and answer its
    /// identifier where there was one. Called when the player comes back to it,
    /// never at launch: continuing needs the other person, so it is theirs to
    /// start.
    func resumeStoredGame() -> String?

    /// Give up whatever game is being played, because the library is about to
    /// hold another one. Nothing is sent: the contract has no vocabulary for
    /// abandoning a game, and the other peer learns of it from the
    /// `unknown_session` its next resume is answered with.
    func abandonStoredGame()
}

extension NearbyDriver: NearbyDriving { }

/// What a link that has gone means on the transport that was carrying it.
///
/// The board says one thing about a connection, and this is which thing. It is
/// the transport's answer because the fact is the transport's — "an online game
/// is the nearby game in everything but how the two devices reach each other",
/// and how a lost reach is regained is exactly that.
nonisolated enum LinkInterruption: Equatable, Sendable {
    /// It comes back without anybody doing anything. The local paths dial again
    /// by themselves seconds later, so the wait ends on its own and the line
    /// says so — and off the player's own turn it is not worth saying at all.
    case passing
    /// Nothing will bring it back. There is no rediscovery here, so what the
    /// player is owed is not a wait but what became of the game: it is kept,
    /// and leaving costs them nothing.
    case lasting

    /// The sentence the player reads, as its key rather than its string — the
    /// reason `NearbyRefusal.messageKey` is a key: this mapping is the whole of
    /// the promise that an interruption reaches the reader as words, and it is
    /// pinned without a language being chosen for it.
    var messageKey: String {
        switch self {
        case .passing: "nearby.connecting"
        case .lasting: "online.interrupted"
        }
    }
}

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
        // The two devices held one identifier and two deals. It is a resume's
        // answer like the one above, and the game is over on both devices.
        case .declined(.dealMismatch): "nearby.refusal.dealMismatch"
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

    /// The title over that sentence.
    ///
    /// Every refusal but one answers a game that never began. `unknown_session`
    /// is the protocol's answer to a **resume**, so what it refuses is a game
    /// that was already under way — and a game in progress that ends is not a
    /// game that did not start.
    var titleKey: String {
        switch self {
        case .declined(.unknownSession), .declined(.dealMismatch): "nearby.ended.title"
        default: "alert.nearbyDeclined.title"
        }
    }
}

/// Why a game the board was showing went away without a result.
///
/// These are the ways the engine parts with a session the board was on:
/// everything else it does to a session leaves the session there. Which of them
/// happened is read off the session as it last stood and off what the driver
/// holds afterwards, rather than decided here.
nonisolated enum NearbyVoid: Equatable, Sendable {
    /// The other device answered this device's resume by saying it holds no
    /// such game — it was relaunched, or lost the session some other way.
    case lostByPeer
    /// The two devices' resumes named one game and two deals, so neither is
    /// playing the game the other is. It voids the session on both sides
    /// exactly as the answer above does, and it is a different fact.
    case dealMismatch
    /// A connection closed on a violation, and the session it carried is void.
    case disagreement
    /// The other player's fresh proposal retired it.
    case retired
    /// The deal never finished. A dealing session is bound to the connection its
    /// proposal travelled on and dies with it: it holds nothing worth
    /// reconciling, it is never resumed, and the pair simply proposes again and
    /// deals again. The protocol calls that routine, and it is the one of these
    /// where no game had begun.
    case dealDied

    /// The one sentence the board says about it. `unknown_session` already has
    /// its own words, and they are the same words for the same fact.
    ///
    /// The key rather than the string, for the reason a refusal's is: this
    /// mapping is the whole of the promise that a void reaches the reader as
    /// words, and it is pinned without a language being chosen for it.
    var messageKey: String {
        switch self {
        case .lostByPeer: "nearby.refusal.unknownSession"
        case .dealMismatch: "nearby.refusal.dealMismatch"
        case .disagreement: "nearby.ended.disagreement"
        case .retired: "nearby.ended.newGame"
        // A game that never began, which is the sentence this app already has
        // for a game that could not start and may be proposed again. A board
        // over a dealing session has no position to stand a notice in front of
        // and leaves for the room instead, so these are the words the case is
        // read in rather than words a reader has met.
        case .dealDied: "nearby.refusal.notNow"
        }
    }

    /// That sentence, in the reader's language.
    var message: String {
        String(localized: String.LocalizationValue(stringLiteral: messageKey))
    }
}

@MainActor
@Observable
final class NearbyFlow {
    let driver: any NearbyDriving
    let reach: any NearbyReach
    /// The positions a nearby board draws, which the board's own model asks.
    /// Held here because this object is the nearby feature's one dependency set
    /// and the board is opened from it.
    let positions: any NearbyPositions

    /// Which way of playing somebody this instance is. It is what a game
    /// created here is recorded under and what the library is asked about, so
    /// the two instances never mistake each other's active game for their own.
    let mode: PlayMode

    /// Whether the Play home offers this way of playing at all.
    ///
    /// **Asked rather than stored**, because one of the two answers moves under
    /// the app: the local paths' answer is the platform's and is the same for
    /// the whole launch, while Game Center's is the player's own account —
    /// a sign-in that completes after the window is up, a sign-out in Settings,
    /// a restriction applied while the app was in the background. A value read
    /// once at assembly would be a row standing for an account that is gone.
    private let availability: @MainActor () -> Bool

    var isAvailable: Bool { availability() }

    /// The library's one active game, as something to ask for and to come back
    /// into. A nearby game *is* an active game now, so the way in depends on
    /// what the library is already holding, and making room for a new one is
    /// the accepted flow's rather than this object's.
    weak var room: (any NearbyRoom)?

    /// Told after the library's active game has changed under it, so the Play
    /// home's card is drawn from what the store says rather than from what this
    /// object last saw.
    var libraryChanged: (@MainActor () -> Void)?

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

    /// Why the board's session went away, where it went away with the game
    /// still on. A session the engine parted with is not in the driver's list
    /// to be read any more, so the answer is worked out at the moment it goes
    /// and kept for the board to say.
    private(set) var boardVoid: NearbyVoid?

    /// The board's session as the driver last published it, held against its
    /// going away: what device it was with, and — the part a void cannot carry —
    /// how it ended, where it ended at all.
    private(set) var boardHeld: BoardGameSession?

    /// How many of the driver's refusals have been presented. The driver's list
    /// only grows, so the count is the whole of what "already seen" means.
    private var declinesSeen = 0

    /// The proposal this device sent and is waiting on, by identifier. It is
    /// what the board opens for, and it is deliberately *this session* rather
    /// than "a game is going": the driver publishes on its own — a connection
    /// idling out is a publication — and a game standing with somebody must not
    /// take away a sheet the player raised for another one.
    private var awaitedSession: String?

    /// Which boards the player has turned round. It is presentation, and it
    /// belongs to the *game* rather than to the page: the board's own model is
    /// rebuilt on every entry, and a board come back to is the board that was
    /// left.
    private var orientations: [String: Bool] = [:]

    /// The connections the surface now up has already offered its game on. It
    /// is the sheet's own rule — "while an invitation is unanswered the sheet
    /// says so and offers no second one" — kept where a proposal goes out by
    /// itself rather than by a press, so that a room republishing under a
    /// refusal the player is still reading cannot propose again behind it.
    ///
    /// **The connection is what it counts, not the person.** Where the
    /// proposal is the only way a game is offered, a person who may be offered
    /// one once may never be offered one again — and a first proposal comes to
    /// nothing often enough to design for: their app closes before they answer,
    /// or this engine refuses it while the pair's last game is still settling.
    /// What they come back on is a fresh match under a fresh connection, which
    /// this has never offered anything, so the game goes out again. The same
    /// connection publishing again is the same offer, and is still refused.
    private var offeredOn: Set<ConnectionID> = []

    init(driver: any NearbyDriving, reach: any NearbyReach,
         positions: any NearbyPositions, mode: PlayMode,
         availability: @escaping @MainActor () -> Bool) {
        self.driver = driver
        self.reach = reach
        self.positions = positions
        self.mode = mode
        self.availability = availability
        watchPublications()
    }

    /// Holds the board's session at every *publication*, rather than at every
    /// redraw that happens to notice one.
    ///
    /// The driver publishes once per input it performs, and two inputs land
    /// between two redraws often enough to design for: on a reconnection the
    /// other peer's `resume` carrying its resignation and the `propose` that
    /// retires the game that resignation ended arrive back to back on one
    /// connection, and the transport hands both to the driver in one pass. A
    /// view's `onChange` compares the value at one redraw with the value at the
    /// next and never sees the one in between, so a board that learned what
    /// became of its game from redraws alone would be told the game was retired
    /// and never told it was won.
    ///
    /// This watches the publications themselves, and the change callback runs
    /// *before* the value moves — which is exactly what makes it useful: what it
    /// reads is the state the coming redraw is about to skip over.
    private func watchPublications() {
        withObservationTracking {
            _ = driver.sessions
        } onChange: { [weak self] in
            // The driver is main-actor and publishes there, so the notification
            // arrives there too.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.holdBoardSession()
                self.watchPublications()
            }
        }
    }

    /// The board's session as it stands right now, kept.
    private func holdBoardSession() {
        guard let boardSessionID,
              let held = driver.sessions.first(where: { $0.id == boardSessionID })
        else { return }
        boardHeld = held
    }

    /// Whether nearby is offered on this device.
    ///
    /// **iPhone and iPad, always.** The row stands wherever either way of
    /// reaching another device could carry a game, and one of the two asks the
    /// hardware for nothing at all: a device with no radio still plays over the
    /// local network, and a network the player has declined or has not joined is
    /// a shorter reach rather than a feature that is not there. So the question
    /// this answers is the platform's alone, and no hardware answer is read.
    ///
    /// Never on the Mac. The surfaces are built on every platform, so this
    /// answer, rather than their absence, is what withholds nearby play there —
    /// and it can only be the platform's, because the transports and the flow
    /// assembled over them are written for iOS alone.
    static var isAvailableHere: Bool {
        #if os(iOS)
        true
        #else
        false
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

    /// The devices the invitation may go to, and the one it would go to. The
    /// transport's own answer: every device this one is paired with, as the
    /// system holds them, and everything advertising itself on the network —
    /// which is what makes the list right the instant the sheet opens rather
    /// than once a connection has come up.
    var peers: [NearbyPeer] { reach.peers }

    /// The device an invitation would go to: the row that was pressed, or —
    /// with nothing pressed — the readiest device in the room.
    ///
    /// A device the transport has dialled is preferred to one it has not, so
    /// that the sheet's standing default is a device an invitation can leave
    /// for; among devices alike in that, the room's own order stands, which is
    /// the devices' own and does not move under a redraw. A pressed row is the
    /// choice whatever its state: presence is the list's business.
    var chosenDevice: NearbyPeer? {
        peers.first { $0.peer == chosenPeer }
            ?? peers.first { $0.connection != nil }
            ?? peers.first
    }

    /// Whether the sheet's one action is available.
    ///
    /// **Readiness is the button's business.** A control is offered exactly
    /// where the act behind it would be allowed, and an invitation to a device
    /// nothing has dialled has nowhere to travel — so a paired device is a row
    /// a person can look at and press, and the invitation waits for the dial
    /// the browser loop makes by itself seconds later.
    var canInvite: Bool { chosenDevice?.connection != nil }

    /// Whether anything is still owed between this device and another: a game
    /// being played, a proposal outstanding, or a finished game this device has
    /// not settled. It is what keeps the transport up after the pages have been
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
            if reachable(live) { openBoard(live.id) } else { proposing = game }
            return
        }
        // The interrupted game the library is holding is the same destination
        // by another route: after a relaunch the engine holds nothing, and the
        // row still names the game that is waiting. It is asked of this
        // instance's own mode, because the library's one active game belongs to
        // exactly one way of reaching another device and the other row must not
        // lead into it.
        if room?.standingGame(in: mode) == game {
            reenter(game)
            return
        }
        // One active game, and a nearby game is one of the ways to have one. A
        // proposal is not made until there is somewhere for the game it starts
        // to live.
        makingRoom(for: game) { [weak self] in self?.proposing = game }
    }

    /// Back into the nearby game the library is holding: the session is rebuilt
    /// from what the store kept of it, and the board opens on it. The transport
    /// wakes with the board and dials, and the resume the contract owes an
    /// interrupted session goes out by itself.
    ///
    /// Where the library has nothing to give back — a game the protocol already
    /// parted with, or a store that would not answer — nothing opens, and the
    /// game stays on the home as a record the player can file.
    func reenter(_ game: GameKind) {
        wake()
        guard let id = driver.resumeStoredGame() else {
            libraryChanged?()
            return
        }
        libraryChanged?()
        guard let session = driver.sessions.first(where: { $0.id == id }),
              reachable(session)
        else {
            proposing = game
            return
        }
        openBoard(id)
    }

    /// Whether the two devices are in touch over that game, or will be without
    /// anybody doing anything.
    ///
    /// **It is what decides whether the way into a standing game is its board
    /// or the surface that reaches its player.** Where a link comes back by
    /// itself the board is the whole of coming back: the transport dials, the
    /// protocol's resume goes out beneath it, and the game carries on — so the
    /// board opens whether or not anything is connected at that instant. Where
    /// nothing will bring one back, a board would be a position nobody could
    /// move on, and what the game needs is for the two people to meet again.
    private func reachable(_ session: BoardGameSession) -> Bool {
        session.connection != nil || reach.interruption == .passing
    }

    /// Whether the surface now up is meeting again over a game that already
    /// exists, rather than composing a new one.
    ///
    /// There is no side to choose then: the game has one, the two devices
    /// agreed it when they started, and offering the choice again would be
    /// offering a control that changes nothing.
    var isMeetingAgain: Bool {
        guard let proposing else { return false }
        return liveSession?.rulesID == proposing.rulesID
    }

    /// The accepted 保存并继续, asked for on behalf of a nearby game about to
    /// exist. It runs the act at once where the library is already free.
    private func makingRoom(for game: GameKind,
                            _ opening: @escaping @MainActor () -> Void) {
        guard let room else {
            opening()
            return
        }
        room.makeRoom(for: game, in: mode, then: opening)
    }

    /// Into a session's board — from the sheet when a proposal is answered, and
    /// from the consent prompt when this device accepts one.
    func openBoard(_ session: String) {
        proposing = nil
        offeredOn = []
        boardSessionID = session
        boardVoid = nil
        boardHeld = nil
        holdBoardSession()
        wake()
    }

    /// The sheet was put away. The proposal it may have sent stands: nothing in
    /// the protocol withdraws one, and the board opens by itself when the answer
    /// comes.
    func dismissSheet() {
        proposing = nil
        offeredOn = []
        restIfIdle()
    }

    /// The back control over the nearby board. The session stays exactly as it
    /// is — leaving a board is the interruption the protocol already models —
    /// and the Play home's own row is the way back into it.
    func leaveBoard() {
        boardSessionID = nil
        boardVoid = nil
        boardHeld = nil
        restIfIdle()
    }

    // MARK: - Proposing, and answering

    /// Offer this game to that device, on the side being composed.
    ///
    /// The identifier is the engine's to mint, so it is read back rather than
    /// supplied: what this device holds unanswered with that peer, the instant
    /// after the proposal was allowed, is the proposal it just made.
    func invite(_ device: NearbyPeer, to game: GameKind) {
        // A paired device the transport has not dialled yet is a row a person
        // may well press, since the room lists the pair rather than the
        // connection. There is nowhere for the proposal to travel, and the
        // engine's own word for that is the one the reader gets — the same
        // sentence a connection lost between the press and the send produces,
        // because to the reader it is the same fact.
        guard let connection = device.connection else {
            refusal = .refused(.unknownConnection)
            return
        }
        do {
            try driver.propose(to: device.peer, on: connection,
                               rulesID: game.rulesID, proposerMoves: proposerMoves)
            awaitedSession = invited?.id
        } catch {
            refusal = .refused(error)
        }
    }

    /// The room moved under the surface being composed.
    ///
    /// **Where the player chose their opponent before anybody was in the room,
    /// the proposal goes out the moment that person arrives.** They named one
    /// friend to the system, or said one code to one friend; whoever comes back
    /// is who they picked, and a control asking which of them to play would be
    /// asking a question with one answer. Where the room *is* the choice — the
    /// local paths, which list whoever happens to be reachable — this does
    /// nothing, and the sheet's own invitation is what sends.
    func roomChanged() {
        guard !reach.playerChoosesFromTheRoom, let game = proposing else { return }
        // The game the two of them were already playing, back within reach.
        // Nothing is proposed, because there is nothing to propose: the game is
        // theirs, the protocol's own resume reconciles it over the connection
        // that has just come up, and the board is where it goes on.
        if let live = liveSession, live.rulesID == game.rulesID {
            openBoard(live.id)
            return
        }
        guard invited == nil, let device = chosenDevice,
              let connection = device.connection, !offeredOn.contains(connection)
        else { return }
        offeredOn.insert(connection)
        invite(device, to: game)
    }

    /// The consent prompt's two answers. Accepting opens the board at once: the
    /// game has begun, and the board is where it is played.
    func accept(_ session: String) {
        // The room is made before the proposal is answered, not after: an
        // accepted proposal is a game in progress, and a game in progress with
        // nowhere in the library to live is a game whose moves nothing records.
        //
        // Nothing is said when this finds nothing, and there is nothing to say:
        // the proposal went away between the prompt and the answer, which takes
        // the prompt with it. The second half cannot fail at all — the engine
        // stores a session only for a `rules_id` its own oracle answered a
        // version for, and that oracle's answer *is* this table.
        guard let game = driver.sessions.first(where: { $0.id == session })
            .flatMap({ GameKind(rulesID: $0.rulesID) })
        else { return }
        makingRoom(for: game) { [weak self] in
            guard let self else { return }
            do throws(BoardGameRefusal) {
                try driver.answer(session, accepting: true)
                openBoard(session)
            } catch {
                refusal = .refused(error)
            }
        }
    }

    func decline(_ session: String) {
        try? driver.answer(session, accepting: false)
    }

    /// The sessions moved. **The proposal this device sent** and the peer
    /// accepted is a game in progress, so the board opens on it — the same
    /// arrival the accepting device already had. Nothing else opens a board:
    /// the driver publishes for its own reasons all the time, and only the
    /// answer to this device's own invitation is an answer.
    func sessionsChanged() {
        noteBoardVoid()
        if let awaited = awaitedSession {
            switch driver.sessions.first(where: { $0.id == awaited }) {
            case let session? where session.state == .active:
                awaitedSession = nil
                openBoard(session.id)
            case nil:
                // Declined, or void with the connection it was made on. The
                // refusal below is what says so.
                awaitedSession = nil
            default:
                break
            }
        }
        // A refusal the other peer sent reaches the player here rather than in
        // the driver, which records them and judges none of them — except the
        // one the board is already saying: a refused resume that voided the
        // game on screen is one event, and one event gets one sentence.
        if driver.declines.count > declinesSeen {
            declinesSeen = driver.declines.count
            if let decline = driver.declines.last,
               decline.session != boardSessionID || boardVoid == nil {
                refusal = .declined(decline.reason)
            }
        }
        // A publication is also where the library's active game can have moved
        // under the home: a nearby game is created when a session becomes
        // active and filed when the two devices settle on an ending, and the
        // card is drawn from what the store says.
        libraryChanged?()
    }

    /// The board's session is either still held or it is not, and a session the
    /// engine has parted with is one the board is owed a sentence about.
    private func noteBoardVoid() {
        guard let boardSessionID else { return }
        guard boardSession == nil else {
            holdBoardSession()
            return
        }
        guard boardVoid == nil, let peer = boardHeld?.peer else { return }
        boardVoid = reasonItWent(boardSessionID, with: peer)
    }

    /// Which of them it was, read off the session as it last stood and off what
    /// the driver holds now.
    ///
    /// **A session still dealing answers for itself**, ahead of everything read
    /// off what is left behind: it died with the connection its proposal
    /// travelled on, which is what the protocol says a dealing session does, and
    /// the pair simply proposes again and deals again. A handshake that ended
    /// that way is not the two devices disagreeing about anything.
    ///
    /// A decline naming an active session is one of the two answers that void a
    /// session on both sides — the other device saying it has no such game, or
    /// saying the two devices no longer hold one deal — and nothing else the
    /// protocol declines can reach one. A proposal standing with the same
    /// device is that device having started afresh. What is left is a connection
    /// closed on a violation, which is the only other thing that takes a session
    /// away from the peer it belongs to.
    private func reasonItWent(_ session: String, with peer: PeerDeviceID) -> NearbyVoid {
        if boardHeld?.state == .dealing { return .dealDied }
        if let decline = driver.declines.first(where: { $0.session == session }) {
            return decline.reason == .dealMismatch ? .dealMismatch : .lostByPeer
        }
        if driver.sessions.contains(where: {
            $0.peer == peer && $0.state == .proposed && $0.proposer == .peer
        }) {
            return .retired
        }
        return .disagreement
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

    /// Which way round the player last had that board, or nil where they have
    /// never turned it and the orientation rule still answers.
    func orientation(of session: String) -> Bool? {
        orientations[session]
    }

    func setOrientation(_ flipped: Bool, of session: String) {
        orientations[session] = flipped
    }

    // MARK: - The transport

    /// The transport runs while nearby is being used and while anything is owed
    /// to a peer, and not otherwise: a device with no nearby surface up and no
    /// session standing has nobody to be discovered by.
    ///
    /// **Both ways of reaching a device are on this one bracket**, so they are
    /// up together and down together, and no surface can tell that there are
    /// two. Nothing here asks what the hardware has: a device with no radio has
    /// the other path, and the transport starts what it has.
    ///
    /// **The pairing registry is not on that bracket.** A surface being up is
    /// the whole reason to be watching it, so the watch is taken every time one
    /// wakes, transport already running or not — the system's snapshots can end
    /// on their own, and a watch that ended once would otherwise leave the room
    /// empty for the rest of the launch.
    private func wake() {
        guard isAvailable else { return }
        reach.watchPairedDevices()
        guard !reach.isRunning else { return }
        reach.start()
    }

    private func restIfIdle() {
        guard proposing == nil, boardSessionID == nil, !holdsSomething,
              reach.isRunning else { return }
        reach.stop()
    }

    // MARK: - The application's own lifecycle

    /// The app was suspended and has come back.
    ///
    /// **Nothing about the game is at stake here**: every ply was committed as
    /// it landed, and the wire session went with it, so what a suspension costs
    /// is the transport and nothing else. What is taken up again is exactly
    /// that — the pairing watch, whose snapshots the system can end on its own,
    /// and everything that listens or dials, which a suspension stops. The
    /// connection itself is not chased: it idles out between moves, and the
    /// browsers dial again by themselves, which is the ordinary motion this
    /// feature was built on rather than a recovery.
    ///
    /// It is also where the local network's own permission is met, for the
    /// reason the bracket exists: a browse begun here begins in front of
    /// somebody who has just come back to this, never in the background where
    /// an undetermined permission is refused in silence.
    func returnedToForeground() {
        guard proposing != nil || boardSessionID != nil || holdsSomething else {
            return
        }
        wake()
    }
}

extension NearbyFlow {
    /// The library is about to hold another game. The session this one was
    /// played over is given up — the store's memory of it with it — and the
    /// board comes down, because the game it was showing is not this device's
    /// any more.
    func giveUpActiveGame() {
        driver.abandonStoredGame()
        if boardSessionID != nil { leaveBoard() }
    }
}
