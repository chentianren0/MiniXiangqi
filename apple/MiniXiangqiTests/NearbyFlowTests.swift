// The nearby flow, without a radio in the room.
//
// What is pinned here is the part of the feature that is neither the protocol
// nor a picture: whether the entry is offered at all, what an invitation carries,
// what the two answers do, how a refusal reaches the reader, when the board takes
// a tap, and when anything is said about the link. The protocol itself is the
// engine's suite, and the driver's plumbing is the driver's; nothing here re-tests
// either — the driver is a fake precisely so that a refusal can be produced on
// request, which a working engine will not do.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The nearby flow")
@MainActor
struct NearbyFlowTests {

    // MARK: - Whether nearby is offered at all

    @Test("A device without the radio offers nothing and starts nothing")
    func theEntryIsGatedOnTheHardware() {
        let radio = FakeRadio(isSupported: false)
        let flow = flow(radio: radio, isAvailable: false)

        #expect(!flow.isAvailable)
        // Even asked, there is nothing to wake: the rows are not drawn, and the
        // radio is not started behind them.
        flow.open(.miniXiangqi)
        #expect(!radio.isRunning)
    }

    @Test("A device with the radio offers it, and the surface wakes it")
    func theEntryIsOfferedWhereTheRadioIs() {
        let radio = FakeRadio(isSupported: true)
        let flow = flow(radio: radio, isAvailable: true)

        #expect(flow.isAvailable)
        flow.open(.miniXiangqi)
        #expect(flow.proposing == .miniXiangqi)
        #expect(radio.isRunning, "the sheet is a nearby surface, so the radio comes up")
    }

    @Test("Availability is the hardware's answer, and the Mac's is no")
    func availabilityReadsTheRadioWhereThereIsOne() {
        #if os(iOS)
        #expect(NearbyFlow.isAvailableHere(FakeRadio(isSupported: true)))
        #expect(!NearbyFlow.isAvailableHere(FakeRadio(isSupported: false)))
        #else
        // A Mac has neither the entitlement nor the system's pairing UI, so the
        // answer is no whatever a radio would have said.
        #expect(!NearbyFlow.isAvailableHere(FakeRadio(isSupported: true)))
        #endif
    }

    // MARK: - Proposing

    @Test("An invitation carries the row's game, the chosen side, and the chosen device")
    func aProposalCarriesWhatWasComposed() throws {
        let driver = FakeDriver()
        let radio = FakeRadio(isSupported: true, peers: [.other])
        let flow = flow(driver: driver, radio: radio)

        flow.open(.xiangqi)
        flow.proposerMoves = .second
        // A room usually holds one device, so the first is chosen already.
        let device = try #require(flow.chosenDevice)
        flow.invite(device, to: .xiangqi)

        #expect(driver.proposals == [FakeDriver.Proposal(peer: NearbyPeer.other.peer,
                                                         connection: NearbyPeer.other.connection,
                                                         rulesID: "xiangqi",
                                                         proposerMoves: .second)])
        #expect(flow.refusal == nil)
    }

    @Test("The engine's refusal is presented by its reason rather than by its code")
    func anEngineRefusalIsPresentedByReason() {
        let driver = FakeDriver()
        driver.refuses = .peerIsBusy
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true, peers: [.other]))

        flow.open(.miniXiangqi)
        flow.invite(.other, to: .miniXiangqi)

        #expect(flow.refusal == .refused(.peerIsBusy))
        #expect(flow.refusal?.messageKey == "nearby.refusal.alreadyPlaying")
        flow.dismissRefusal()
        #expect(flow.refusal == nil)
    }

    @Test("Every refusal the wire has a word for reaches the reader as words")
    func everyDeclineReasonHasItsOwnSentence() {
        let keys = DeclineReason.allCases.map { NearbyRefusal.declined($0).messageKey }
        #expect(keys == ["nearby.refusal.declined",
                         "nearby.refusal.unknownGame",
                         "nearby.refusal.rulesMismatch",
                         "nearby.refusal.busy",
                         "nearby.refusal.unknownSession"])
        // Distinct, because a reason a reader cannot tell from another reason is
        // a code with extra steps.
        #expect(Set(keys).count == DeclineReason.allCases.count)
        // The engine's own refusals divide into the three situations a person can
        // do something about: wait for the pair's last game, wait for this one,
        // or try again.
        #expect(NearbyRefusal.refused(.proposalOutstanding).messageKey
                == "nearby.refusal.alreadyPlaying")
        #expect(NearbyRefusal.refused(.lingeringSessionUnsettled).messageKey
                == "nearby.refusal.settling")
        #expect(NearbyRefusal.refused(.unknownConnection).messageKey
                == "nearby.refusal.notNow")
    }

    @Test("A refusal the peer sent is presented once")
    func aPeerRefusalIsPresentedOnce() {
        let driver = FakeDriver()
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true, peers: [.other]))
        flow.open(.miniXiangqi)

        driver.declines = [NearbyDecline(session: "S", peer: NearbyPeer.other.peer,
                                         reason: .busy, at: Date())]
        flow.sessionsChanged()
        #expect(flow.refusal == .declined(.busy))
        #expect(flow.refusal?.messageKey == "nearby.refusal.busy")

        flow.dismissRefusal()
        // The list only grows, so the same refusal must not come back the next
        // time anything moves.
        flow.sessionsChanged()
        #expect(flow.refusal == nil)
    }

    @Test("A proposal the peer accepted opens the board by itself")
    func anAcceptedProposalOpensTheBoard() {
        let driver = FakeDriver()
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true, peers: [.other]))
        flow.open(.miniXiangqi)
        flow.invite(.other, to: .miniXiangqi)

        driver.sessions = [session(proposer: .local, accepted: true)]
        flow.sessionsChanged()

        #expect(flow.proposing == nil, "the sheet has done its errand")
        #expect(flow.boardSessionID == "S")
    }

    // MARK: - Consenting

    @Test("An arriving proposal is the invitation, and accepting it opens the board")
    func acceptingAnInvitationOpensTheBoard() throws {
        let driver = FakeDriver()
        driver.sessions = [session(proposer: .peer)]
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true))

        #expect(try #require(flow.invitation).id == "S")
        flow.accept("S")

        #expect(driver.answers == [FakeDriver.Answer(session: "S", accepting: true)])
        #expect(flow.boardSessionID == "S")
    }

    @Test("Declining answers the peer and opens nothing")
    func decliningOpensNothing() {
        let driver = FakeDriver()
        driver.sessions = [session(proposer: .peer)]
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true))

        flow.decline("S")

        #expect(driver.answers == [FakeDriver.Answer(session: "S", accepting: false)])
        #expect(flow.boardSessionID == nil)
        #expect(flow.proposing == nil)
    }

    // MARK: - The row into a game already going

    @Test("A game already going is what its own row opens")
    func theRowLeadsBackIntoTheGame() {
        let driver = FakeDriver()
        driver.sessions = [session(proposer: .local, accepted: true)]
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true))

        flow.open(.miniXiangqi)
        #expect(flow.boardSessionID == "S")
        #expect(flow.proposing == nil)

        // The other game's row names another game, so it offers a new one — and
        // the engine is what refuses the proposal if the peer is busy.
        flow.leaveBoard()
        flow.open(.xiangqi)
        #expect(flow.proposing == .xiangqi)
        #expect(flow.boardSessionID == nil)
    }

    // MARK: - The radio

    @Test("The radio rests when no surface is up and nothing is owed")
    func theRadioRestsWhenThereIsNothingToDo() {
        let driver = FakeDriver()
        let radio = FakeRadio(isSupported: true)
        let flow = flow(driver: driver, radio: radio)

        flow.open(.miniXiangqi)
        #expect(radio.isRunning)
        flow.dismissSheet()
        #expect(!radio.isRunning)
    }

    @Test("and stays up while a game is standing with somebody")
    func theRadioStaysUpForASession() {
        let driver = FakeDriver()
        let radio = FakeRadio(isSupported: true)
        let flow = flow(driver: driver, radio: radio)

        flow.open(.miniXiangqi)
        driver.sessions = [session(proposer: .local, accepted: true)]
        // The invitation was answered, so the sheet has done its errand and the
        // board is what is up.
        flow.sessionsChanged()
        #expect(flow.proposing == nil)
        flow.leaveBoard()
        #expect(radio.isRunning, "the session belongs to the peer, not to the page")

        // A finished game that is settled owes nothing, and the radio may rest.
        driver.sessions = [ended()]
        flow.leaveBoard()
        #expect(!radio.isRunning)
    }

    // MARK: - The turn lock

    @Test("The board takes a tap only on this device's turn, and only in play")
    func theTurnLockIsTheProtocolsAnswer() throws {
        let live = session(proposer: .local, accepted: true)
        let play = try #require(board(live))
        // The proposer takes the first mover here, and the ply index is zero.
        #expect(play.acceptsInput)
        #expect(play.controller == .you)

        play.sync(with: with(live) { $0.plies = ["b1b2"] })
        #expect(!play.acceptsInput, "the ply is the other device's now")
        #expect(play.controller == .peer)

        play.sync(with: with(live) { $0.connection = nil })
        #expect(!play.acceptsInput, "and an interrupted session sends nothing")

        play.sync(with: with(live) { $0.peerTerminal = .resign })
        #expect(!play.acceptsInput, "nor does a game that is over")
        #expect(play.end?.state == .redWins)
        #expect(play.end?.reason == .resignation)
    }

    // MARK: - What is said about the link

    @Test("Nothing is said about the link in ordinary play")
    func anIdleLinkIsInvisible() throws {
        let live = session(proposer: .local, accepted: true)
        let play = try #require(board(live))
        #expect(!play.isWaitingOnConnection)

        // The connection idles out between moves by the radio's own design, and
        // the driver brings it back underneath. On the *other* device's turn
        // that costs this player nothing, so it is not reported.
        play.sync(with: with(live) { $0.plies = ["b1b2"]; $0.connection = nil })
        #expect(!play.isWaitingOnConnection)
    }

    @Test("and something is said when what the player did has not reached the peer")
    func anUndeliveredActIsSaid() throws {
        let live = session(proposer: .local, accepted: true)
        let play = try #require(board(live))

        // A resignation made while the link was down is held by the engine and
        // rides the next resume. That is the player's own act waiting to be
        // delivered, which is exactly the case the one quiet line is for.
        play.sync(with: with(live) {
            $0.connection = nil
            $0.localTerminal = .resign
            $0.settled = false
        })
        #expect(play.isWaitingOnConnection)

        // And it goes when the link comes back and the exchange settles it.
        play.sync(with: with(live) { $0.localTerminal = .resign })
        #expect(!play.isWaitingOnConnection)
    }

    // MARK: - The suite's own parts

    private func flow(driver: any NearbyDriving = FakeDriver(),
                      radio: any NearbyRadio,
                      isAvailable: Bool = true) -> NearbyFlow {
        NearbyFlow(driver: driver, radio: radio, positions: FakePositions(),
                   isAvailable: isAvailable)
    }

    /// The board's model over one session, with the position faked: what a
    /// position *is* belongs to the core and to the oracle's own suite.
    ///
    /// The animator runs bodies at once and parks the completions, so a
    /// transition this suite never asks to finish still leaves the board where
    /// it was put; the feedback is a sink, because what a nearby landing sounds
    /// like is the shared rule the motion suites already pin.
    private func board(_ session: BoardGameSession) -> NearbyPlay? {
        NearbyPlay(session: session, driver: FakeDriver(), positions: FakePositions(),
                   animator: ManualAnimator().animator,
                   feedback: Feedback(perform: { _ in }, play: { _ in }))
    }

    private func session(proposer: Party, accepted: Bool = false) -> BoardGameSession {
        var session = BoardGameSession(id: "S", peer: NearbyPeer.other.peer,
                                       rulesID: "minixiangqi", rulesVersion: "1",
                                       proposerMoves: .first, proposer: proposer)
        session.connection = ConnectionID("c")
        session.accepted = accepted
        return session
    }

    /// A finished, settled session — the one the pair's dealings may linger with.
    private func ended() -> BoardGameSession {
        var finished = session(proposer: .local, accepted: true)
        finished.peerTerminal = .resign
        return finished
    }

    private func with(_ session: BoardGameSession,
                      _ change: (inout BoardGameSession) -> Void) -> BoardGameSession {
        var copy = session
        change(&copy)
        return copy
    }
}

// MARK: - The seams

/// A driver that records instead of speaking, and refuses when the test says so.
@MainActor
private final class FakeDriver: NearbyDriving {
    struct Proposal: Equatable {
        var peer: PeerDeviceID
        var connection: ConnectionID
        var rulesID: String
        var proposerMoves: Mover
    }

    struct Answer: Equatable {
        var session: String
        var accepting: Bool
    }

    var sessions: [BoardGameSession] = []
    var declines: [NearbyDecline] = []
    /// What every intent answers with, where the test wants a refusal.
    var refuses: BoardGameRefusal?

    private(set) var proposals: [Proposal] = []
    private(set) var answers: [Answer] = []
    private(set) var played: [String] = []
    private(set) var resigned: [String] = []

    func propose(to peer: PeerDeviceID, on connection: ConnectionID, rulesID: String,
                 proposerMoves: Mover) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        proposals.append(Proposal(peer: peer, connection: connection, rulesID: rulesID,
                                  proposerMoves: proposerMoves))
    }

    func answer(_ session: String, accepting: Bool) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        answers.append(Answer(session: session, accepting: accepting))
    }

    func play(_ text: String, in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        played.append(text)
    }

    func resign(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        resigned.append(session)
    }
}

@MainActor
private final class FakeRadio: NearbyRadio {
    let isSupported: Bool
    private(set) var isRunning = false
    var peers: [NearbyPeer]

    init(isSupported: Bool, peers: [NearbyPeer] = []) {
        self.isSupported = isSupported
        self.peers = peers
    }

    func start() { isRunning = true }
    func stop() { isRunning = false }
}

/// Positions enough to hold a board up. What a position actually is comes from
/// the core, and the oracle's own suite is where that is asked.
private nonisolated struct FakePositions: NearbyPositions {
    func standing(of game: GameKind, after plies: [String]) -> NearbyStanding? {
        NearbyStanding(
            evaluation: Evaluation(fen: Core.startFEN(for: game),
                                   sideToMove: Mover.atPly(plies.count) == .first
                                       ? .red : .black,
                                   inCheck: false,
                                   plyCount: plies.count,
                                   positionRevision: UInt64(plies.count),
                                   state: .ongoing,
                                   reason: .none,
                                   atOccurrence: 0,
                                   claimAvailable: false,
                                   undoAvailable: false,
                                   undoPlies: 0,
                                   resignAvailable: false,
                                   searchExpected: false),
            legalMoves: [])
    }
}

extension NearbyPeer {
    fileprivate static let other = NearbyPeer(connection: ConnectionID("connection-1"),
                                              peer: PeerDeviceID("peer-device"),
                                              name: "Their iPhone")
}
