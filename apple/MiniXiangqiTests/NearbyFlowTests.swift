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
        #expect(radio.watches == 0, "and where there is no radio there are no pairings to watch")
    }

    @Test("The registry watch is taken every time a surface wakes, radio running or not")
    func everyWakeTakesTheRegistryWatch() {
        let radio = FakeRadio(isSupported: true)
        let flow = flow(radio: radio)

        flow.open(.miniXiangqi)
        #expect(radio.isRunning)
        #expect(radio.watches == 1)

        // The radio is already up, so nothing starts it again — and the watch is
        // taken all the same. This is the only place a watch the system ended is
        // ever retaken, and a radio held up by a standing session would
        // otherwise leave the room empty for the rest of the launch.
        flow.open(.xiangqi)
        #expect(radio.isRunning)
        #expect(radio.watches == 2, "the registry is not on the radio's bracket")
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

        let connection = try #require(NearbyPeer.other.connection)
        #expect(driver.proposals == [FakeDriver.Proposal(peer: NearbyPeer.other.peer,
                                                         connection: connection,
                                                         rulesID: "xiangqi",
                                                         proposerMoves: .second)])
        #expect(flow.refusal == nil)
    }

    // MARK: - The room

    @Test("The room is the pairing registry, and a device with no connection is in it")
    func theRoomIsThePairingRegistry() {
        // The state the sheet is opened in: the two devices are paired, and the
        // radio has only just been woken, so nothing is dialled yet.
        let paired = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-2"),
                                name: "Their iPad")
        let room = NearbyPeer.room(paired: [paired], connected: [])

        #expect(room == [paired], "a paired device is in the room before anybody dials it")
    }

    @Test("A device both paired and connected is one row, carrying the connection")
    func theRoomJoinsTheTwoSourcesPerDevice() {
        let peer = PeerDeviceID("wifi-aware-device-1")
        let registry = NearbyPeer(connection: nil, peer: peer, name: "Their iPhone")
        let live = NearbyPeer(connection: ConnectionID("c-1"), peer: peer, name: "Their iPhone")

        let room = NearbyPeer.room(paired: [registry], connected: [live])

        #expect(room.count == 1, "one device is one row, whatever knows about it")
        #expect(room.first?.connection == ConnectionID("c-1"),
                "and the row carries the connection a proposal would travel")
    }

    @Test("The room holds a connected device the registry has not caught up with")
    func theRoomKeepsAConnectedDeviceTheRegistryMisses() {
        let live = NearbyPeer(connection: ConnectionID("c-1"),
                              peer: PeerDeviceID("wifi-aware-device-9"), name: "Their iPad")

        #expect(NearbyPeer.room(paired: [], connected: [live]) == [live])
    }

    @Test("The room's order is the devices' own, so a row does not move under a press")
    func theRoomIsOrderedByTheDurableIdentifier() {
        let second = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-2"),
                                name: "B")
        let first = NearbyPeer(connection: ConnectionID("c-9"),
                               peer: PeerDeviceID("wifi-aware-device-1"), name: "A")

        #expect(NearbyPeer.room(paired: [second], connected: [first]).map(\.peer)
                == [first.peer, second.peer])
        // The same room however the two sources happen to be ordered.
        #expect(NearbyPeer.room(paired: [second, first], connected: []).map(\.peer)
                == [first.peer, second.peer])
    }

    @Test("A device paired while the sheet is open appears on it")
    func aDevicePairedWhileTheSheetIsOpenAppears() {
        let radio = FakeRadio(isSupported: true)
        let flow = flow(radio: radio)

        flow.open(.miniXiangqi)
        #expect(flow.proposing == .miniXiangqi)
        #expect(flow.peers.isEmpty, "nobody is in the room yet, and the sheet says so")
        #expect(flow.chosenDevice == nil, "so there is nobody to invite")

        // The system's pairing hands back to the sheet, and the registry watch
        // publishes the pair without anything being pressed again.
        radio.peers = [.other]

        #expect(flow.peers == [NearbyPeer.other], "the row is there the moment the pairing is")
        #expect(flow.chosenDevice?.peer == NearbyPeer.other.peer,
                "and a room holding one device has that device chosen already")
    }

    @Test("The default choice is a device the invitation can leave for")
    func theDefaultChoicePrefersAConnectedDevice() {
        // The room's own order puts the device nothing has dialled first.
        let waiting = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-1"),
                                 name: "Their iPad")
        let ready = NearbyPeer(connection: ConnectionID("c-1"),
                               peer: PeerDeviceID("wifi-aware-device-2"), name: "Their iPhone")
        let flow = flow(radio: FakeRadio(isSupported: true, peers: [waiting, ready]))

        #expect(flow.chosenDevice?.peer == ready.peer,
                "the standing default is the device an invitation can leave for")
        #expect(flow.canInvite)

        // A pressed row is the choice whatever its state: presence is the
        // list's business, and readiness the button's.
        flow.chosenPeer = waiting.peer
        #expect(flow.chosenDevice?.peer == waiting.peer)
        #expect(!flow.canInvite, "and there is nothing for an invitation to travel")
    }

    @Test("Among devices alike in readiness the room's own order stands")
    func theDefaultChoiceKeepsTheRoomsOrderAmongEquals() {
        let first = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-1"),
                               name: "A")
        let second = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-2"),
                                name: "B")
        let flow = flow(radio: FakeRadio(isSupported: true, peers: [first, second]))

        #expect(flow.chosenDevice?.peer == first.peer)
        #expect(!flow.canInvite, "with nothing dialled anywhere, the invitation is not offered")
    }

    @Test("The invitation is offered only where there is a connection to carry it")
    func theInvitationIsOfferedOnlyWithAConnection() {
        let radio = FakeRadio(isSupported: true)
        let flow = flow(radio: radio)

        flow.open(.miniXiangqi)
        #expect(!flow.canInvite, "an empty room has nobody to invite")

        // A paired device the transport has not dialled is a row, and not yet
        // an invitation: a control is offered exactly where the act behind it
        // would be allowed.
        let waiting = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-2"),
                                 name: "Their iPad")
        radio.peers = [waiting]
        #expect(flow.chosenDevice?.peer == waiting.peer, "the row is there all the same")
        #expect(!flow.canInvite)

        // The browser's own dial lands, and the same row is one to press.
        radio.peers = [NearbyPeer(connection: ConnectionID("c-1"), peer: waiting.peer,
                                  name: waiting.name)]
        #expect(flow.canInvite)
    }

    @Test("An invitation to a device with no connection yet is refused, not lost")
    func invitingADeviceWithNoConnectionIsRefused() {
        let driver = FakeDriver()
        let waiting = NearbyPeer(connection: nil, peer: PeerDeviceID("wifi-aware-device-2"),
                                 name: "Their iPad")
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true, peers: [waiting]))

        flow.open(.miniXiangqi)
        flow.invite(waiting, to: .miniXiangqi)

        #expect(driver.proposals.isEmpty, "there is nowhere for it to travel")
        #expect(flow.refusal == .refused(.unknownConnection))
        #expect(flow.refusal?.messageKey == "nearby.refusal.notNow",
                "which reaches the reader as the sentence for a connection that is not there")
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

    @Test("A game standing with somebody does not take away a sheet raised for another")
    func anUnrelatedSessionDoesNotOpenABoard() {
        let driver = FakeDriver()
        // A Mini Xiangqi game is already going with this peer.
        driver.sessions = [session(proposer: .local, accepted: true)]
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true, peers: [.other]))

        flow.open(.xiangqi)
        #expect(flow.proposing == .xiangqi, "the other game's row offers a new game")

        // The driver publishes for its own reasons — a connection idling out is
        // a publication, and Stage 1 measured those every twenty or thirty
        // seconds. Nothing this device asked for has happened, so nothing moves.
        flow.sessionsChanged()

        #expect(flow.proposing == .xiangqi)
        #expect(flow.boardSessionID == nil,
                "only the answer to this device's own invitation opens a board")
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
        let radio = FakeRadio(isSupported: true, peers: [.other])
        let flow = flow(driver: driver, radio: radio)

        flow.open(.miniXiangqi)
        flow.invite(.other, to: .miniXiangqi)
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

    @Test("and when the player reaches for a board the link has locked")
    func reachingForALockedBoardIsSaid() throws {
        let live = session(proposer: .local, accepted: true)
        let play = try #require(board(live))

        // The link goes on this device's own turn. Nothing is said yet: a
        // reconnection takes seconds, and the player has asked for nothing.
        play.sync(with: with(live) { $0.connection = nil })
        #expect(!play.isWaitingOnConnection)

        // Reaching for the board and finding it locked is the moment the link
        // starts costing them something, so the line does not wait out the
        // stretch.
        play.tap(Square(file: 1, rank: 0))
        #expect(play.isWaitingOnConnection)

        // And it goes when the link comes back, with the reaching forgotten.
        play.sync(with: live)
        #expect(!play.isWaitingOnConnection)
    }

    // MARK: - Which way round the board is

    @Test("A board turned round stays turned round across leaving it")
    func aFlipSurvivesLeavingTheBoard() throws {
        let flow = flow(radio: FakeRadio(isSupported: true))
        let live = session(proposer: .local, accepted: true)
        #expect(flow.orientation(of: live.id) == nil,
                "a board nobody has turned has none of its own")

        let play = try #require(board(live))
        #expect(!play.flipped,
                "this device moves first, so its own side is already at the bottom")
        play.flip()
        flow.setOrientation(play.flipped, of: live.id)
        #expect(play.flipped)

        // The board's model is rebuilt on every entry, and what it is handed is
        // what the player last had.
        let returned = try #require(board(live, flipped: flow.orientation(of: live.id)))
        #expect(returned.flipped)
    }

    // MARK: - The negotiations

    @Test("提和 and 悔棋 are on offer exactly where the engine's own law allows them")
    func offeringMirrorsTheEngine() throws {
        let live = session(proposer: .local, accepted: true)
        let play = try #require(board(live))

        // This device's own turn at ply zero: a negotiation is the off-turn
        // peer's to open, so neither is available.
        #expect(!play.canOfferDraw)
        #expect(!play.canRequestUndo)

        // Off turn, with a ply of this device's own behind it.
        play.sync(with: with(live) { $0.plies = ["b1b2"] })
        #expect(play.canOfferDraw)
        #expect(play.canRequestUndo)

        // Off turn with nothing played — this device takes the second mover, so
        // the game opens on the other player's turn. The engine's `keep` has no
        // value in range, so there is nothing to ask back.
        let waiting = try #require(board(session(proposer: .peer, accepted: true)))
        #expect(waiting.controller == .peer)
        #expect(waiting.canOfferDraw)
        #expect(!waiting.canRequestUndo, "a game with no plies has none to take back")

        // An item standing is the engine's one-at-a-time rule, whoever opened
        // it, and an interrupted session can send nothing at all.
        play.sync(with: with(live) {
            $0.plies = ["b1b2"]
            $0.item = NegotiationItem(opener: .local, kind: .drawOffer, at: 1)
        })
        #expect(!play.canOfferDraw)
        #expect(!play.canRequestUndo)

        play.sync(with: with(live) { $0.plies = ["b1b2"]; $0.connection = nil })
        #expect(!play.canOfferDraw)
        #expect(!play.canRequestUndo)
    }

    @Test("and each sends what it says: an offer, and this device's own last ply back")
    func openingSendsTheEnginesOwnAsk() throws {
        let driver = FakeDriver()
        let live = with(session(proposer: .local, accepted: true)) {
            $0.plies = ["b1b2", "b7b6", "b2b1"]
        }
        let play = try #require(board(live, driver: driver))

        play.offerDraw()
        play.requestUndo()
        // `keep` is the engine's count less one, read at the moment of the ask.
        #expect(driver.intents == [.offerDraw, .requestUndo(keep: 2)])

        // Neither is sent where the engine would refuse it: the surface does not
        // ask a question it has already been told the answer to.
        play.sync(with: with(live) { $0.connection = nil })
        play.offerDraw()
        play.requestUndo()
        #expect(driver.intents == [.offerDraw, .requestUndo(keep: 2)])
    }

    @Test("What the other player is asking is the engine's item, and nothing else")
    func theArrivingItemIsPresented() throws {
        let live = with(session(proposer: .local, accepted: true)) { $0.plies = ["b1b2"] }
        let play = try #require(board(live))
        #expect(play.standingItem == nil)

        // This device's own offer is not something to answer.
        play.sync(with: with(live) {
            $0.item = NegotiationItem(opener: .local, kind: .drawOffer, at: 1)
        })
        #expect(play.standingItem == nil)

        // The other player's is.
        let offered = with(live) {
            $0.plies = ["b1b2", "b7b6"]
            $0.item = NegotiationItem(opener: .peer, kind: .drawOffer, at: 2)
        }
        play.sync(with: offered)
        #expect(play.standingItem == .drawOffer)

        play.sync(with: with(offered) {
            $0.item = NegotiationItem(opener: .peer, kind: .undoRequest(keep: 1), at: 2)
        })
        #expect(play.standingItem == .undoRequest(keep: 1))

        // A ply landing voids it in the engine, so it un-presents at the same
        // instant and with as little ceremony: nothing here held it.
        play.sync(with: with(offered) { $0.plies = ["b1b2", "b7b6", "b2b1"]; $0.item = nil })
        #expect(play.standingItem == nil)

        // And an interrupted session has nothing to answer with.
        play.sync(with: with(offered) { $0.connection = nil })
        #expect(play.standingItem == nil)
    }

    @Test("接受 answers whichever of the two stands, and nothing where none does")
    func acceptingAnswersTheStandingItem() throws {
        let driver = FakeDriver()
        let live = with(session(proposer: .local, accepted: true)) {
            $0.plies = ["b1b2", "b7b6"]
        }
        let play = try #require(board(live, driver: driver))

        play.accept()
        #expect(driver.intents.isEmpty, "there is nothing standing to accept")

        play.sync(with: with(live) {
            $0.item = NegotiationItem(opener: .peer, kind: .drawOffer, at: 2)
        })
        play.accept()
        #expect(driver.intents == [.acceptDraw])

        play.sync(with: with(live) {
            $0.item = NegotiationItem(opener: .peer, kind: .undoRequest(keep: 1), at: 2)
        })
        play.accept()
        #expect(driver.intents == [.acceptDraw, .acceptUndo])
    }

    @Test("An applied retraction is the shorter line, shown going back")
    func anAcceptedRetractionIsDrawn() throws {
        let live = with(session(proposer: .local, accepted: true)) { $0.plies = ["b1b2"] }
        let play = try #require(board(live, positions: AdvancedPositions()))
        #expect(play.shown == ["b1b2"])

        // The engine applies the retraction and publishes; the board follows it
        // back through the board's own Undo rather than cutting to it.
        play.sync(with: with(live) { $0.plies = []; $0.undos = 1; $0.retractedTo = 0 })
        #expect(play.shown == [])
        #expect(play.transit?.kind == .undo)

        let ply = try #require(Move(text: "b1b2", on: GameKind.miniXiangqi.board))
        #expect(play.transit?.move == Move(from: ply.to, to: ply.from),
                "the mover travels home, which is the ply read backwards")

        // A longer truncation is not a move being taken back, so it cuts.
        let long = with(live) { $0.plies = ["b1b2", "b7b6", "b2b1"] }
        let other = try #require(board(long, positions: AdvancedPositions()))
        other.sync(with: with(long) { $0.plies = [] })
        #expect(other.shown == [])
        #expect(other.transit == nil, "nobody wants to watch three moves go past")
    }

    // MARK: - The claim

    @Test("The claim stands exactly where the engine says it stands")
    func theClaimIsTheEnginesAnswer() throws {
        let driver = FakeDriver()
        let live = session(proposer: .local, accepted: true)
        let play = try #require(board(live, driver: driver))

        #expect(!play.claimStands)
        #expect(driver.claimsAsked == ["S"], "the affordance is asked of the session")
        #expect(play.statusState == .ongoing)
        play.claimDraw()
        #expect(driver.intents.isEmpty, "nothing is claimed that the engine would refuse")

        driver.claimStandsAnswer = true
        #expect(play.claimStands)
        play.claimDraw()
        #expect(driver.intents == [.claim])
    }

    @Test("and the 可判和 line stands with it rather than with the position alone")
    func theClaimLineFollowsTheEngine() throws {
        let driver = FakeDriver()
        let live = session(proposer: .local, accepted: true)
        let play = try #require(board(live, driver: driver, positions: ClaimablePositions()))

        // The position is claimable and the engine is not offering the claim —
        // the other device's turn, an interrupted session, anything. The line
        // follows the engine.
        #expect(play.statusState == .ongoing)

        driver.claimStandsAnswer = true
        #expect(play.statusState == .claimableDraw)

        // A finished game says its result instead, whatever the position is.
        play.sync(with: with(live) { $0.peerTerminal = .resign })
        #expect(play.statusState == .redWins)
    }

    // MARK: - The agreed draw

    @Test("A draw the two players agreed says so, in the word the core has not got")
    func anAgreedDrawIsNamed() throws {
        let live = session(proposer: .local, accepted: true)
        let play = try #require(board(live))

        play.sync(with: with(live) { $0.localTerminal = .acceptDraw })
        #expect(play.end?.state == .draw)
        #expect(play.end?.byAgreement == true)
        #expect(play.end?.reason == EndReason.none, "no position decided this")
        #expect(play.reasonText == String(localized: "reason.agreedDraw"))
    }

    // MARK: - A game that goes away

    @Test("A session the peer no longer holds is why the board says the game ended")
    func aSessionLostByThePeerIsSaid() {
        let driver = FakeDriver()
        driver.sessions = [session(proposer: .local, accepted: true)]
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true))
        flow.open(.miniXiangqi)
        #expect(flow.boardVoid == nil)

        // The peer answered this device's resume by saying it has no such game.
        driver.sessions = []
        driver.declines = [NearbyDecline(session: "S", peer: NearbyPeer.other.peer,
                                         reason: .unknownSession, at: Date())]
        flow.sessionsChanged()

        #expect(flow.boardVoid == .lostByPeer)
        #expect(flow.boardVoid?.messageKey == "nearby.refusal.unknownSession")
        #expect(flow.refusal == nil, "one event gets one sentence, and the board has it")
        #expect(flow.boardSessionID == "S", "the board stays where it is")
    }

    @Test("A fresh proposal from the same device is the other reason it can go")
    func aRetiredSessionIsSaid() {
        let driver = FakeDriver()
        driver.sessions = [session(proposer: .local, accepted: true)]
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true))
        flow.open(.miniXiangqi)

        // The other player proposed again, which retires what stood with them.
        // What is left with that device is their fresh, unanswered proposal.
        driver.sessions = [session(id: "S2", proposer: .peer)]
        flow.sessionsChanged()

        #expect(flow.boardVoid == .retired)
        #expect(flow.boardVoid?.messageKey == "nearby.ended.newGame")
    }

    @Test("and everything else is the two devices ceasing to agree")
    func aVoidedSessionIsSaid() {
        let driver = FakeDriver()
        driver.sessions = [session(proposer: .local, accepted: true)]
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true))
        flow.open(.miniXiangqi)

        // A connection closed on a violation takes the session with it, and
        // nothing else is left behind for it.
        driver.sessions = []
        flow.sessionsChanged()

        #expect(flow.boardVoid == .disagreement)
        #expect(flow.boardVoid?.messageKey == "nearby.ended.disagreement")
        // Distinct sentences, because a reason a reader cannot tell from another
        // reason is a code with extra steps.
        #expect(Set([NearbyVoid.lostByPeer, .disagreement, .retired].map(\.messageKey)).count == 3)
    }

    @Test("A game that ended and was retired in one update is still the result")
    func aResultAndItsRemovalInOneUpdateIsStillTheResult() throws {
        let driver = FakeDriver()
        let live = session(proposer: .local, accepted: true)
        driver.sessions = [live]
        let flow = flow(driver: driver, radio: FakeRadio(isSupported: true))
        flow.open(.miniXiangqi)
        let play = try #require(board(live))

        // Two publications between two redraws, which is what a reconnection
        // does: the other peer's resume carried its resignation, and the propose
        // that followed it on the same connection retired the game that
        // resignation had ended. A view watching redraws sees only the second.
        driver.sessions = [with(live) { $0.peerTerminal = .resign }]
        driver.sessions = [session(id: "S2", proposer: .peer)]
        flow.sessionsChanged()

        #expect(flow.boardVoid == .retired)
        // The publication the redraw skipped is the one the flow held, and it
        // is the one carrying the end.
        let held = try #require(flow.boardHeld)
        #expect(held.end?.ending == .resignation(.peer))

        // Applied before the board is told the game went away, which is what
        // makes the result win: this game was won, and the board says so rather
        // than saying the other player started a new one.
        play.sync(with: held)
        play.wentAway(try #require(flow.boardVoid))
        #expect(play.end?.state == .redWins)
        #expect(play.reasonText == EndReason.resignation.text)
        #expect(play.isOver)
    }

    @Test("A board told its game went away stops offering the game")
    func aVoidedBoardIsQuiet() throws {
        let live = with(session(proposer: .local, accepted: true)) { $0.plies = ["b1b2"] }
        let play = try #require(board(live))
        #expect(play.canOfferDraw)
        #expect(!play.isOver)

        play.wentAway(.disagreement)
        #expect(play.isOver)
        #expect(play.voided == .disagreement)
        #expect(!play.canOfferDraw)
        #expect(!play.canRequestUndo)
        #expect(!play.canResign)
        #expect(!play.acceptsInput)
        #expect(!play.claimStands)
        #expect(!play.isWaitingOnConnection,
                "the notice has said what became of it; the link is beside the point")
    }

    @Test("A refusal answering a resume is not titled as a game that did not start")
    func aResumeRefusalIsTitledForAGameThatWasUnderWay() {
        #expect(NearbyRefusal.declined(.unknownSession).titleKey == "nearby.ended.title")
        for reason in DeclineReason.allCases where reason != .unknownSession {
            #expect(NearbyRefusal.declined(reason).titleKey == "alert.nearbyDeclined.title")
        }
        #expect(NearbyRefusal.refused(.peerIsBusy).titleKey == "alert.nearbyDeclined.title")
    }

    // MARK: - The library's one active game

    @Test("A proposal is not made until there is room in the library for the game")
    func aProposalWaitsForTheRoomItsGameWillNeed() {
        let radio = FakeRadio(isSupported: true)
        let flow = flow(radio: radio)
        let room = FakeRoom()
        flow.room = room

        flow.open(.miniXiangqi)
        #expect(room.asked == [.miniXiangqi])
        #expect(flow.proposing == nil, "nothing is composed while the room is being made")

        room.grant()
        #expect(flow.proposing == .miniXiangqi)
    }

    @Test("An invitation is answered only once its game has somewhere to live")
    func acceptingWaitsForTheRoomToo() {
        let radio = FakeRadio(isSupported: true)
        let driver = FakeDriver()
        driver.sessions = [session(id: "S", proposer: .peer)]
        let flow = flow(driver: driver, radio: radio)
        let room = FakeRoom()
        flow.room = room

        flow.accept("S")
        #expect(driver.answers.isEmpty,
                "an accepted proposal is a game in progress, and it needs a home first")

        room.grant()
        #expect(driver.answers == [FakeDriver.Answer(session: "S", accepting: true)])
        #expect(flow.boardSessionID == "S")
    }

    @Test("A nearby row leads back into the interrupted game the library holds")
    func theRowLeadsBackIntoTheStoredGame() {
        let radio = FakeRadio(isSupported: true)
        let driver = FakeDriver()
        driver.stored = with(session(id: "S", proposer: .local, accepted: true)) {
            $0.plies = ["b1b3"]
        }
        let flow = flow(driver: driver, radio: radio)
        let room = FakeRoom()
        room.standingNearbyGame = .miniXiangqi
        flow.room = room

        flow.open(.miniXiangqi)
        #expect(room.asked.isEmpty, "the room is already this game's")
        #expect(driver.resumedStored == 1)
        #expect(flow.boardSessionID == "S")
        #expect(radio.isRunning, "and the radio is up for the resume that follows")
    }

    @Test("A game the library cannot give back opens nothing")
    func nothingToComeBackTo() {
        let radio = FakeRadio(isSupported: true)
        let driver = FakeDriver()
        let flow = flow(driver: driver, radio: radio)

        flow.reenter(.miniXiangqi)
        #expect(driver.resumedStored == 1)
        #expect(flow.boardSessionID == nil)
    }

    @Test("Giving up the active game lets the session go and takes the board down")
    func givingUpTheActiveGame() {
        let radio = FakeRadio(isSupported: true)
        let driver = FakeDriver()
        driver.sessions = [session(id: "S", proposer: .local, accepted: true)]
        let flow = flow(driver: driver, radio: radio)
        flow.openBoard("S")

        flow.giveUpActiveGame()
        #expect(driver.abandoned == 1)
        #expect(flow.boardSessionID == nil)
    }

    @Test("Coming back from a suspension takes the radio up again, and only then")
    func comingBackFromASuspension() {
        let radio = FakeRadio(isSupported: true)
        let driver = FakeDriver()
        let flow = flow(driver: driver, radio: radio)

        flow.returnedToForeground()
        #expect(!radio.isRunning, "nothing is owed and no surface is up")

        driver.sessions = [session(id: "S", proposer: .local, accepted: true)]
        flow.returnedToForeground()
        #expect(radio.isRunning)
        #expect(radio.watches > 0, "and the pairing watch is taken again")
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
    private func board(_ session: BoardGameSession, flipped: Bool? = nil,
                       driver: FakeDriver = FakeDriver(),
                       positions: any NearbyPositions = FakePositions()) -> NearbyPlay? {
        NearbyPlay(session: session, driver: driver, positions: positions,
                   flipped: flipped,
                   animator: ManualAnimator().animator,
                   feedback: Feedback(perform: { _ in }, play: { _ in }))
    }

    private func session(id: String = "S", proposer: Party,
                         accepted: Bool = false) -> BoardGameSession {
        var session = BoardGameSession(id: id, peer: NearbyPeer.other.peer,
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
///
/// Observable like the real one, because *when* it publishes is part of what is
/// under test: the flow holds the board's session at every publication rather
/// than at every redraw, and a fake that published silently could not tell the
/// two apart.
@MainActor
@Observable
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

    /// One negotiation intent, as the driver received it.
    enum Intent: Equatable {
        case claim
        case offerDraw
        case acceptDraw
        case requestUndo(keep: Int)
        case acceptUndo
    }

    var sessions: [BoardGameSession] = []
    var declines: [NearbyDecline] = []
    var ownMoveRefusals = 0
    /// What every intent answers with, where the test wants a refusal.
    var refuses: BoardGameRefusal?
    /// The identifier the engine would mint for the next proposal.
    var mints = "S"
    /// What the engine's own oracle would say about the claim.
    var claimStandsAnswer = false

    private(set) var proposals: [Proposal] = []
    private(set) var answers: [Answer] = []
    private(set) var played: [String] = []
    private(set) var resigned: [String] = []
    private(set) var intents: [Intent] = []
    /// The sessions `claimStands` was asked about, which is what proves the
    /// affordance is the engine's answer rather than the position's.
    private(set) var claimsAsked: [String] = []

    func propose(to peer: PeerDeviceID, on connection: ConnectionID, rulesID: String,
                 proposerMoves: Mover) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        proposals.append(Proposal(peer: peer, connection: connection, rulesID: rulesID,
                                  proposerMoves: proposerMoves))
        // The engine mints the identifier and holds the proposal it made, which
        // is what the flow reads back to learn which session it is waiting on.
        var proposed = BoardGameSession(id: mints, peer: peer, rulesID: rulesID,
                                        rulesVersion: "1", proposerMoves: proposerMoves,
                                        proposer: .local)
        proposed.connection = connection
        sessions.append(proposed)
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

    func claim(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.claim)
    }

    func offerDraw(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.offerDraw)
    }

    func acceptDraw(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.acceptDraw)
    }

    func requestUndo(keeping keep: Int, in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.requestUndo(keep: keep))
    }

    func acceptUndo(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.acceptUndo)
    }

    func claimStands(in session: BoardGameSession) -> Bool {
        claimsAsked.append(session.id)
        return claimStandsAnswer
    }

    /// The interrupted game the library would give back, where a case has set
    /// one up, and what it was asked.
    var stored: BoardGameSession?
    private(set) var resumedStored = 0
    private(set) var abandoned = 0

    func resumeStoredGame() -> String? {
        resumedStored += 1
        guard let stored else { return nil }
        sessions.append(stored)
        return stored.id
    }

    func abandonStoredGame() {
        abandoned += 1
        sessions.removeAll { $0.state != .proposed }
        stored = nil
    }
}

/// The library's one active game, as the flow asks about it: what it is holding,
/// and the making of room that is somebody else's flow.
@MainActor
private final class FakeRoom: NearbyRoom {
    var standingNearbyGame: GameKind?
    private(set) var asked: [GameKind] = []
    private var pending: (@MainActor () -> Void)?

    func makeRoom(for game: GameKind, then opening: @escaping @MainActor () -> Void) {
        asked.append(game)
        pending = opening
    }

    /// The room was made — the archive committed, or there was nothing to file.
    func grant() {
        let opening = pending
        pending = nil
        opening?()
    }
}

@MainActor
private final class FakeRadio: NearbyRadio {
    let isSupported: Bool
    private(set) var isRunning = false
    /// How many times the registry watch was asked for. It is counted rather
    /// than flagged because the whole of the promise is that it is asked for
    /// again, off the radio's own bracket.
    private(set) var watches = 0
    var peers: [NearbyPeer]

    init(isSupported: Bool, peers: [NearbyPeer] = []) {
        self.isSupported = isSupported
        self.peers = peers
    }

    func watchPairedDevices() { watches += 1 }
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

/// The same, with the position claimable. Whether a position *is* claimable is
/// the core's answer; what this shows is a board where it is, so that what the
/// status line does with the engine's separate answer can be asked.
private nonisolated struct ClaimablePositions: NearbyPositions {
    func standing(of game: GameKind, after plies: [String]) -> NearbyStanding? {
        guard var standing = FakePositions().standing(of: game, after: plies) else { return nil }
        standing.evaluation.state = .claimableDraw
        standing.evaluation.claimAvailable = true
        return standing
    }
}

/// The same, with Red's cannon standing a point up the board — the position
/// `b1b2` produces. A reversal draws the piece that made the ply travelling
/// home, and it reads that piece off the ply's destination, which in the start
/// position is an empty point.
private nonisolated struct AdvancedPositions: NearbyPositions {
    func standing(of game: GameKind, after plies: [String]) -> NearbyStanding? {
        guard var standing = FakePositions().standing(of: game, after: plies) else { return nil }
        standing.evaluation.fen = "rcnkncr/p1ppp1p/7/7/7/PCPPP1P/R1NKNCR w - - 0 1"
        return standing
    }
}

extension NearbyPeer {
    fileprivate static let other = NearbyPeer(connection: ConnectionID("connection-1"),
                                              peer: PeerDeviceID("peer-device"),
                                              name: "Their iPhone")
}
