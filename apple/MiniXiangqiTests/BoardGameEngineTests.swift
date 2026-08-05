// The session engine against docs/boardgame-protocol.md, clause by clause.
//
// The engine is driven the way the transport will drive it: a connection comes
// up, messages arrive on it, this peer's own player asks for things, and every
// answer is the sends, the close verdicts, and the sessions it leaves behind.
// The rules come from the real core throughout, so a game that ends here ends
// for the reason the app's own games end for.
//
// Session identifiers are pinned rather than minted, because the crossing rule
// is decided by a byte-wise sort and a test of it must own both sides of the
// comparison.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The BoardGame Protocol engine", .retiringItsCores)
@MainActor
struct BoardGameEngineTests {

    /// The lines the oracle suite verifies against the core.
    static let mateLine = BoardGameRulesTests.mateLine
    static let shuffleLine = BoardGameRulesTests.shuffleLine

    // MARK: - hello

    @Test("A connection opens with hello, before anything else")
    func openingSendsHello() throws {
        let engine = try engine()
        #expect(sent(engine.connectionOpened(.first, with: .peer))
                == [.hello(.init(protocolVersion: 1))])
    }

    @Test("A message before the other peer's hello closes the connection")
    func nothingArrivesBeforeHello() throws {
        let engine = try engine()
        _ = engine.connectionOpened(.first, with: .peer)
        let effects = engine.receive(.propose(.init(session: "S", rulesID: "minixiangqi",
                                                    rulesVersion: "1", proposerMoves: .first)),
                                     on: .first)
        #expect(violations(effects) == [.noLawfulMeaning])
        #expect(closed(effects) == [.first])
        #expect(engine.session("S") == nil)
    }

    @Test("A version this peer will not speak closes the connection")
    func anotherVersionClosesTheConnection() throws {
        let engine = try engine()
        _ = engine.connectionOpened(.first, with: .peer)
        let effects = engine.receive(.hello(.init(protocolVersion: 2)), on: .first)
        #expect(effects == [.close(.first, .unsupportedVersion(2))])
    }

    @Test("A negative protocol version reads as the integer it is, and the engine refuses it")
    func aNegativeVersionIsReadAndRefused() throws {
        // The contract types `protocol` as an integer, not a non-negative one,
        // so the codec has nothing to refuse in these bytes: a version this
        // peer will not speak is answered by closing the connection.
        let hello = try JSONDecoder().decode(BoardGameMessage.self,
                                             from: Data(#"{"hello":{"protocol":-1}}"#.utf8))
        #expect(hello == .hello(.init(protocolVersion: -1)))

        let engine = try engine()
        _ = engine.connectionOpened(.first, with: .peer)
        #expect(engine.receive(hello, on: .first) == [.close(.first, .unsupportedVersion(-1))])
    }

    @Test("A second hello on one connection has no lawful meaning")
    func helloOpensOnce() throws {
        let engine = try connected()
        #expect(violations(engine.receive(.hello(.init()), on: .first)) == [.noLawfulMeaning])
    }

    // MARK: - Proposing

    @Test("Proposing offers the game at this peer's own interpretation version")
    func proposingOffersTheGame() throws {
        let engine = try connected(minting: ["S-mine"])
        let effects = try engine.propose(to: .peer, on: .first, rulesID: "minixiangqi",
                                         proposerMoves: .first)

        #expect(sent(effects) == [.propose(.init(session: "S-mine", rulesID: "minixiangqi",
                                                 rulesVersion: "1", proposerMoves: .first))])
        let session = try #require(engine.session("S-mine"))
        #expect(session.state == .proposed)
        #expect(session.proposer == .local)
        #expect(session.connection == .first)
        #expect(session.localMover == .first)
        #expect(session.count == 0)
    }

    @Test("This peer proposes only a game it plays")
    func proposingAGameThisPeerDoesNotPlay() throws {
        let engine = try connected()
        #expect(throws: BoardGameRefusal.unknownGame) {
            try engine.propose(to: .peer, on: .first, rulesID: "go-19", proposerMoves: .first)
        }
    }

    @Test("A proposal of a game this peer does not implement is declined with unknown_game")
    func unknownGameIsDeclined() throws {
        let engine = try connected()
        let effects = peerProposes(engine, "S", game: "go-19")
        #expect(sent(effects) == [.decline(.init(session: "S", reason: .unknownGame))])
        #expect(engine.session("S") == nil)
    }

    @Test("The rules version is compared byte-wise, and any difference is rules_mismatch")
    func versionMismatchIsDeclined() throws {
        let engine = try connected()
        for version in ["2", "1.0", "01", " 1", "1 "] {
            let effects = peerProposes(engine, "S-\(version)", version: version)
            #expect(sent(effects) == [.decline(.init(session: "S-\(version)",
                                                     reason: .rulesMismatch))])
            #expect(engine.session("S-\(version)") == nil)
        }
    }

    @Test("A proposal past the rules gate stands unanswered until the player answers")
    func consentIsThePlayers() throws {
        let engine = try connected()
        #expect(peerProposes(engine, "S").isEmpty, "the gate passed; nothing is owed yet")
        let session = try #require(engine.session("S"))
        #expect(session.state == .proposed)
        #expect(session.proposer == .peer)
        #expect(session.localMover == .second, "the proposer took the first mover")

        #expect(sent(try engine.answer("S", accepting: true)) == [.accept(.init(session: "S"))])
        #expect(engine.session("S")?.state == .active)
    }

    @Test("A refused proposal is declined and forgotten")
    func refusingAProposal() throws {
        let engine = try connected()
        _ = peerProposes(engine, "S")
        #expect(sent(try engine.answer("S", accepting: false))
                == [.decline(.init(session: "S", reason: .declined))])
        #expect(engine.session("S") == nil)
    }

    @Test("busy answers a proposal that arrives while an active session stands")
    func busyAnswersASecondGame() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine)
        let effects = peerProposes(engine, "S-second")
        #expect(sent(effects) == [.decline(.init(session: "S-second", reason: .busy))])
        #expect(engine.session(id)?.state == .active)
        #expect(engine.session("S-second") == nil)
    }

    @Test("Crossed proposals: the lower session identifier survives")
    func crossingKeepsTheLowerIdentifier() throws {
        let engine = try connected(minting: ["A-mine"])
        _ = try engine.propose(to: .peer, on: .first, rulesID: "minixiangqi", proposerMoves: .first)

        let effects = peerProposes(engine, "B-theirs")
        #expect(effects.isEmpty, "the losing proposal is void without an answer")
        #expect(engine.session("A-mine")?.state == .proposed)
        #expect(engine.session("B-theirs") == nil)
    }

    @Test("Crossed proposals: this peer's own is void when theirs sorts lower")
    func crossingDropsTheHigherIdentifier() throws {
        let engine = try connected(minting: ["B-mine"])
        _ = try engine.propose(to: .peer, on: .first, rulesID: "minixiangqi", proposerMoves: .first)

        let effects = peerProposes(engine, "A-theirs")
        #expect(effects.isEmpty, "the surviving proposal waits for the player, not for an answer")
        #expect(engine.session("B-mine") == nil)
        #expect(engine.session("A-theirs")?.state == .proposed)
    }

    @Test("Crossed proposals carrying one identifier leave neither standing, and answer nothing")
    func crossedProposalsWithTheSameIdentifier() throws {
        let engine = try connected(minting: ["S-same"])
        _ = try engine.propose(to: .peer, on: .first, rulesID: "minixiangqi", proposerMoves: .first)

        let effects = peerProposes(engine, "S-same")
        #expect(effects.isEmpty, "neither sorts lower, so neither survives and neither is answered")
        #expect(engine.session("S-same") == nil)
        #expect(engine.sessions.isEmpty)
    }

    @Test("Identifiers are compared by their bytes, not by Unicode equivalence")
    func identifiersAreComparedByTheirBytes() throws {
        // One character, composed and decomposed: equal as Swift strings,
        // different as bytes, and the decomposed one sorts lower.
        let composed = "S-\u{00E9}"
        let decomposed = "S-e\u{0301}"
        #expect(composed == decomposed, "Swift's own comparison is what this defends against")

        let engine = try connected(minting: [composed])
        _ = try engine.propose(to: .peer, on: .first, rulesID: "minixiangqi", proposerMoves: .first)
        let effects = peerProposes(engine, decomposed)

        #expect(effects.isEmpty)
        #expect(engine.session(composed) == nil, "the higher identifier is void without an answer")
        #expect(engine.session(decomposed)?.state == .proposed,
                "and the two are two sessions, not one entry")
    }

    @Test("A refused proposal is reported with its reason and forgotten")
    func ourProposalIsRefused() throws {
        let engine = try connected(minting: ["S-mine"])
        _ = try engine.propose(to: .peer, on: .first, rulesID: "minixiangqi", proposerMoves: .first)

        let effects = engine.receive(.decline(.init(session: "S-mine", reason: .busy)), on: .first)
        #expect(effects == [.declined(session: "S-mine", peer: .peer, reason: .busy)])
        #expect(engine.session("S-mine") == nil)
    }

    @Test("An arriving proposal retires the lingering ended session, settled or not")
    func aProposalRetiresTheLingeringSession() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine)
        _ = try engine.resign(in: id)
        #expect(engine.session(id)?.settled == false)

        _ = peerProposes(engine, "S-next")
        #expect(engine.session(id) == nil)
        #expect(engine.session("S-next")?.state == .proposed)
    }

    @Test("This peer proposes only when its own lingering copy is settled")
    func proposingWaitsForSettlement() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromPeer(engine)
        _ = try engine.resign(in: id)

        #expect(throws: BoardGameRefusal.lingeringSessionUnsettled) {
            try engine.propose(to: .peer, on: .first, rulesID: "minixiangqi", proposerMoves: .first)
        }

        // The exchange that settles it: this peer opens it on the live
        // connection, and the proposer's resume completes it.
        _ = try engine.resume(id, on: .first)
        _ = engine.receive(.resume(.init(session: id, undos: 0, count: 0, keep: 0, end: nil)),
                           on: .first)
        #expect(engine.session(id)?.settled == true)

        _ = try engine.propose(to: .peer, on: .first, rulesID: "minixiangqi", proposerMoves: .first)
        #expect(engine.session(id) == nil, "a new proposal retires it")
        #expect(engine.session("S-mine")?.state == .proposed)
    }

    @Test("A proposal is scoped to the connection it travelled on")
    func acceptOnAnotherConnection() throws {
        let engine = try connected(minting: ["S-mine"])
        _ = connect(engine, .second)
        _ = try engine.propose(to: .peer, on: .first, rulesID: "minixiangqi", proposerMoves: .first)

        let effects = engine.receive(.accept(.init(session: "S-mine")), on: .second)
        #expect(violations(effects) == [.noLawfulMeaning])
        #expect(closed(effects) == [.second])
        #expect(engine.session("S-mine") == nil, "the session is void")
    }

    @Test("An unanswered proposal dies with its connection, and is unknown afterwards")
    func aProposalDiesWithItsConnection() throws {
        let engine = try connected()
        _ = peerProposes(engine, "S")
        engine.connectionDied(.first)
        #expect(engine.session("S") == nil)

        _ = connect(engine, .second)
        let effects = engine.receive(.resume(.init(session: "S", undos: 0, count: 0,
                                                   keep: 0, end: nil)), on: .second)
        #expect(sent(effects) == [.decline(.init(session: "S", reason: .unknownSession))])
    }

    // MARK: - Playing

    @Test("proposer_moves and index parity decide every turn")
    func turnsFollowParity() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)

        #expect(engine.session(id)?.isLocalTurn == false)
        #expect(throws: BoardGameRefusal.notYourTurn) { try engine.play("b1b2", in: id) }

        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        #expect(engine.session(id)?.isLocalTurn == true)

        #expect(sent(try engine.play("b7b6", in: id))
                == [.move(.init(session: id, index: 1, move: "b7b6"))])
        #expect(engine.session(id)?.plies == ["b1b2", "b7b6"])
    }

    @Test("A move whose index is not the receiver's count has no lawful meaning")
    func indexDiscipline() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        let effects = engine.receive(.move(.init(session: id, index: 1, move: "b1b2")), on: .first)
        #expect(violations(effects) == [.noLawfulMeaning])
        #expect(engine.session(id) == nil)
    }

    @Test("A move on the other peer's turn has no lawful meaning")
    func turnDiscipline() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)

        let effects = engine.receive(.move(.init(session: id, index: 1, move: "b7b6")), on: .first)
        #expect(violations(effects) == [.noLawfulMeaning], "index 1 is this peer's ply")
        #expect(engine.session(id) == nil)
    }

    @Test("An illegal move is a violation of its own class")
    func illegalMovesAreViolations() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)

        let effects = engine.receive(.move(.init(session: id, index: 0, move: "b1b7")), on: .first)
        #expect(violations(effects) == [.illegalMove])
        #expect(closed(effects) == [.first])
        #expect(engine.session(id) == nil, "the session is void")
    }

    @Test("This peer's own unlawful move is refused rather than sent")
    func ourOwnUnlawfulMove() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        #expect(throws: BoardGameRefusal.unlawfulMove) { try engine.play("b7b1", in: id) }
        #expect(engine.session(id)?.count == 1, "nothing landed")
    }

    @Test("A game played to mate ends by the rules, with no message for the end")
    func aGamePlayedToMate() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        let effects = try play(Self.mateLine, into: engine, id)

        #expect(sent(effects) == [.move(.init(session: id, index: 1, move: "b7b6"))],
                "the only message this peer owed was its own ply")
        let session = try #require(engine.session(id))
        #expect(session.state == .ended)
        #expect(session.end == BoardGameEnd(result: .moverWins(.first),
                                            ending: .rulesDecided(.checkmate)))
        #expect(session.settled, "the other peer's ply decided it")
        #expect(throws: BoardGameRefusal.notActive) { try engine.play("a6a5", in: id) }
    }

    @Test("A peer whose own ply decided the end holds the session unsettled")
    func ourDecidingPlyLeavesUsUnsettled() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromHere(engine, "S-mine", moves: .first)
        try play(Self.mateLine, into: engine, id)

        let session = try #require(engine.session(id))
        #expect(session.end?.ending == .rulesDecided(.checkmate))
        #expect(!session.settled)
    }

    // MARK: - The claim

    @Test("The claim is a ply: it travels as a move and ends the game as the draw it claims")
    func claiming() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromHere(engine, "S-mine", moves: .first)
        try play(Self.shuffleLine, into: engine, id)
        #expect(engine.session(id)?.isLocalTurn == true)

        let effects = try engine.claim(in: id)
        #expect(sent(effects) == [.move(.init(session: id, index: 8, move: "claim"))])
        let session = try #require(engine.session(id))
        #expect(session.plies.last == "claim")
        #expect(session.count == 9, "a claim carries an index and increments the count")
        #expect(session.end == BoardGameEnd(result: .draw,
                                            ending: .rulesDecided(.threefoldRepetition)))
        #expect(!session.settled)
    }

    @Test("An arriving claim ends the game where the repetition stands")
    func anArrivingClaim() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(Self.shuffleLine, into: engine, id)

        let effects = engine.receive(.move(.init(session: id, index: 8, move: "claim")), on: .first)
        #expect(effects.isEmpty)
        let session = try #require(engine.session(id))
        #expect(session.end == BoardGameEnd(result: .draw,
                                            ending: .rulesDecided(.threefoldRepetition)))
        #expect(session.settled, "the other peer claimed it")
    }

    @Test("A claim with nothing to claim is an illegal move")
    func claimingNothing() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)

        let effects = engine.receive(.move(.init(session: id, index: 0, move: "claim")), on: .first)
        #expect(violations(effects) == [.illegalMove])
        #expect(engine.session(id) == nil)
    }

    @Test("This peer's own claim is refused where the repetition does not stand")
    func ourOwnClaimWithNothingToClaim() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromHere(engine, "S-mine", moves: .first)
        #expect(throws: BoardGameRefusal.unlawfulMove) { try engine.claim(in: id) }
    }

    @Test("Nothing is in sequence after a claim")
    func nothingFollowsAClaim() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromHere(engine, "S-mine", moves: .first)
        try play(Self.shuffleLine, into: engine, id)
        _ = try engine.claim(in: id)

        // Their ply by parity, at the count the session holds, and a move that
        // would be legal on the board the shuffle left. The game is over.
        let effects = engine.receive(.move(.init(session: id, index: 9, move: "b7b6")), on: .first)
        #expect(effects.isEmpty, "discarded by the ended session, never a violation")
        #expect(engine.session(id)?.count == 9)
        #expect(engine.session(id)?.end?.ending == .rulesDecided(.threefoldRepetition))
    }

    // MARK: - Offers and requests

    @Test("An offer from the off-turn peer stands, and accepting it ends the game as agreed")
    func aDrawOfferAndItsAcceptance() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        _ = engine.receive(.offerDraw(.init(session: id, at: 1)), on: .first)

        #expect(engine.session(id)?.item
                == NegotiationItem(opener: .peer, kind: .drawOffer, at: 1))
        #expect(sent(try engine.acceptDraw(in: id)) == [.acceptDraw(.init(session: id))])
        let session = try #require(engine.session(id))
        #expect(session.end == BoardGameEnd(result: .draw, ending: .agreedDraw))
        #expect(!session.settled, "this peer sent the terminal")
        #expect(session.item == nil)
    }

    @Test("An arrival whose at differs from the receiver's count is stale and silently void")
    func staleItemsAreSilentlyVoid() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        _ = try engine.play("b7b6", in: id)

        // Their offer was sent at their count of 1 and crossed this peer's ply.
        let effects = engine.receive(.offerDraw(.init(session: id, at: 1)), on: .first)
        #expect(effects.isEmpty)
        #expect(engine.session(id)?.item == nil)
        #expect(engine.session(id)?.state == .active, "stale is not a violation")
    }

    @Test("Only the off-turn peer opens a negotiation")
    func onlyTheOffTurnPeerOpens() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)

        let effects = engine.receive(.offerDraw(.init(session: id, at: 0)), on: .first)
        #expect(violations(effects) == [.noLawfulMeaning], "at index 0 the proposer is on turn")
        #expect(engine.session(id) == nil)
    }

    @Test("While its item stands the off-turn peer sends nothing further")
    func aSecondItemWhileOneStands() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        _ = engine.receive(.offerDraw(.init(session: id, at: 1)), on: .first)

        let effects = engine.receive(.requestUndo(.init(session: id, at: 1, keep: 0)), on: .first)
        #expect(violations(effects) == [.noLawfulMeaning])
        #expect(engine.session(id) == nil)
    }

    @Test("keep runs from 0 to one less than the sender's count; anything else is malformed")
    func keepIsBounded() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)

        let effects = engine.receive(.requestUndo(.init(session: id, at: 1, keep: 1)), on: .first)
        #expect(violations(effects) == [.malformed])
        #expect(engine.session(id) == nil)
    }

    @Test("An accepted retraction removes the plies beyond keep and counts itself")
    func acceptingARetraction() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        _ = engine.receive(.requestUndo(.init(session: id, at: 1, keep: 0)), on: .first)

        #expect(sent(try engine.acceptUndo(in: id)) == [.acceptUndo(.init(session: id))])
        let session = try #require(engine.session(id))
        #expect(session.plies.isEmpty)
        #expect(session.undos == 1)
        #expect(session.reportedKeep == 0)
        #expect(session.item == nil)
        #expect(!session.isLocalTurn, "the position is the first mover's again")
    }

    @Test("An accepted draw that matches no standing item has no lawful meaning")
    func acceptingADrawNobodyOffered() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        #expect(violations(engine.receive(.acceptDraw(.init(session: id)), on: .first))
                == [.noLawfulMeaning])
        #expect(engine.session(id) == nil)
    }

    @Test("An accepted retraction that matches no standing item has no lawful meaning")
    func acceptingARetractionNobodyRequested() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        #expect(violations(engine.receive(.acceptUndo(.init(session: id)), on: .first))
                == [.noLawfulMeaning])
        #expect(engine.session(id) == nil)
    }

    @Test("A landing move voids the standing item on both sides")
    func aLandingMoveVoidsTheItem() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)

        // Their offer, answered with a move instead of an acceptance.
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        _ = engine.receive(.offerDraw(.init(session: id, at: 1)), on: .first)
        _ = try engine.play("b7b6", in: id)
        #expect(engine.session(id)?.item == nil)

        // This peer's own offer, answered by their move.
        _ = try engine.offerDraw(in: id)
        #expect(engine.session(id)?.item?.opener == .local)
        _ = engine.receive(.move(.init(session: id, index: 2, move: "b2b1")), on: .first)
        #expect(engine.session(id)?.item == nil)
    }

    @Test("This peer's own negotiations are off-turn only, one at a time, and bounded")
    func ourOwnNegotiations() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)

        #expect(throws: BoardGameRefusal.offTurnOnly) { try engine.offerDraw(in: id) }
        _ = try engine.play("b7b6", in: id)

        #expect(throws: BoardGameRefusal.keepOutOfRange) { try engine.requestUndo(keeping: 2, in: id) }
        #expect(sent(try engine.requestUndo(keeping: 1, in: id))
                == [.requestUndo(.init(session: id, at: 2, keep: 1))])
        #expect(throws: BoardGameRefusal.itemStanding) { try engine.offerDraw(in: id) }

        // The one thing an off-turn peer may still send while its item stands.
        #expect(sent(try engine.resign(in: id)) == [.resign(.init(session: id))])
    }

    @Test("Pending offers and requests do not survive the connection that carried them")
    func itemsDieWithTheirConnection() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        _ = engine.receive(.offerDraw(.init(session: id, at: 1)), on: .first)

        engine.connectionDied(.first)
        let session = try #require(engine.session(id))
        #expect(session.item == nil)
        #expect(session.state == .active)
        #expect(session.connection == nil)
    }

    // MARK: - Ending, and the one precedence rule

    @Test("A resignation ends the session for the peer that did not send it")
    func theirResignation() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)

        #expect(engine.receive(.resign(.init(session: id)), on: .first).isEmpty)
        let session = try #require(engine.session(id))
        #expect(session.end == BoardGameEnd(result: .moverWins(.second),
                                            ending: .resignation(.peer)))
        #expect(session.settled)
    }

    @Test("This peer's resignation is sent, ends the session, and leaves it unsettled")
    func ourResignation() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)

        #expect(sent(try engine.resign(in: id)) == [.resign(.init(session: id))])
        let session = try #require(engine.session(id))
        #expect(session.end == BoardGameEnd(result: .moverWins(.first),
                                            ending: .resignation(.local)))
        #expect(!session.settled)
    }

    @Test("A resignation with no connection to carry it rides the next resume")
    func resigningWithNoConnection() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        engine.connectionDied(.first)

        #expect(try engine.resign(in: id).isEmpty)
        let session = try #require(engine.session(id))
        #expect(session.state == .ended)
        #expect(!session.settled)
        #expect(session.resumeMessage.end == .resign)
    }

    @Test("Both peers resigned: the game is a draw")
    func crossedResignations() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = try engine.resign(in: id)

        #expect(engine.receive(.resign(.init(session: id)), on: .first).isEmpty)
        #expect(engine.session(id)?.end == BoardGameEnd(result: .draw, ending: .bothResigned))
    }

    @Test("A draw by agreement outranks a resignation")
    func agreementOutranksResignation() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        _ = try engine.play("b7b6", in: id)
        _ = try engine.offerDraw(in: id)
        _ = try engine.resign(in: id)
        #expect(engine.session(id)?.end?.ending == .resignation(.local))

        // Their acceptance crossed the resignation and arrives for an ended
        // session, which merges terminals by the precedence rule.
        _ = engine.receive(.acceptDraw(.init(session: id)), on: .first)
        #expect(engine.session(id)?.end == BoardGameEnd(result: .draw, ending: .agreedDraw))
    }

    @Test("A rules-decided end outranks every ending a message carries")
    func rulesDecidedOutranksEverything() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b3", "b7b6"], into: engine, id)
        _ = try engine.resign(in: id)
        #expect(engine.session(id)?.end?.ending == .resignation(.local))

        _ = engine.receive(.move(.init(session: id, index: 2, move: "b3d3")), on: .first)
        let session = try #require(engine.session(id))
        #expect(session.count == 3, "an ended session applies a valid in-sequence move")
        #expect(session.end == BoardGameEnd(result: .moverWins(.first),
                                            ending: .rulesDecided(.checkmate)))
    }

    @Test("A rules-decided end outranks a draw agreed before it")
    func rulesDecidedOutranksAnAgreedDraw() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b3", "b7b6"], into: engine, id)
        _ = try engine.offerDraw(in: id)
        _ = engine.receive(.acceptDraw(.init(session: id)), on: .first)
        #expect(engine.session(id)?.end?.ending == .agreedDraw)

        _ = engine.receive(.move(.init(session: id, index: 2, move: "b3d3")), on: .first)
        #expect(engine.session(id)?.end == BoardGameEnd(result: .moverWins(.first),
                                                        ending: .rulesDecided(.checkmate)))
    }

    @Test("A draw agreed after the mate does not lower it")
    func anAgreedDrawArrivingAfterTheMate() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b3", "b7b6"], into: engine, id)
        _ = try engine.offerDraw(in: id)

        _ = engine.receive(.move(.init(session: id, index: 2, move: "b3d3")), on: .first)
        #expect(engine.session(id)?.end?.ending == .rulesDecided(.checkmate))

        _ = engine.receive(.acceptDraw(.init(session: id)), on: .first)
        #expect(engine.session(id)?.end == BoardGameEnd(result: .moverWins(.first),
                                                        ending: .rulesDecided(.checkmate)))
    }

    @Test("A resignation arriving after the draw the peer agreed to does not lower it")
    func aResignationArrivingAfterTheAgreedDraw() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = try engine.offerDraw(in: id)
        _ = engine.receive(.acceptDraw(.init(session: id)), on: .first)
        #expect(engine.session(id)?.end?.ending == .agreedDraw)

        // Their resignation crossed their own acceptance: the merge keeps the
        // terminal that outranks rather than taking whichever arrived last.
        _ = engine.receive(.resign(.init(session: id)), on: .first)
        let session = try #require(engine.session(id))
        #expect(session.peerTerminal == .acceptDraw)
        #expect(session.end == BoardGameEnd(result: .draw, ending: .agreedDraw))
    }

    @Test("An ended session discards everything but a move, a terminal, and a resume")
    func theEndedSessionDiscardsTheRest() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.resign(.init(session: id)), on: .first)

        for message: BoardGameMessage in [.offerDraw(.init(session: id, at: 0)),
                                          .requestUndo(.init(session: id, at: 4, keep: 0)),
                                          .acceptDraw(.init(session: id)),
                                          .acceptUndo(.init(session: id)),
                                          .accept(.init(session: id))] {
            let effects = engine.receive(message, on: .first)
            #expect(effects.isEmpty, "discarded, never a violation")
            #expect(engine.session(id) != nil)
        }
        // accept_draw is a terminal, so it merged rather than being discarded.
        #expect(engine.session(id)?.end?.ending == .agreedDraw)
    }

    // MARK: - Interruption and resume

    @Test("An interruption keeps the line and loses the binding")
    func anInterruption() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b2"], into: engine, id)
        engine.connectionDied(.first)

        let session = try #require(engine.session(id))
        #expect(session.state == .active)
        #expect(session.connection == nil)
        #expect(session.plies == ["b1b2"])
        #expect(throws: BoardGameRefusal.notInPlay) { try engine.play("b7b6", in: id) }
    }

    @Test("The exchange completes on the connection the proposer's resume travelled")
    func theProposersResumeCompletesTheExchange() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b2"], into: engine, id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        let effects = engine.receive(.resume(.init(session: id, undos: 0, count: 1,
                                                   keep: 1, end: nil)), on: .second)
        #expect(sent(effects) == [.resume(.init(session: id, undos: 0, count: 1,
                                                keep: 1, end: nil))])
        let session = try #require(engine.session(id))
        #expect(session.connection == .second, "the session re-binds there")
        #expect(session.exchange == nil)
        #expect(session.isInPlay)
        #expect(session.settled)
    }

    @Test("A resume that travelled another connection is re-sent on the completing one")
    func resumeIsReSentOnTheCompletingConnection() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        engine.connectionDied(.first)
        _ = connect(engine, .second)
        _ = connect(engine, .third)

        // This peer is not the proposer, so its choice of connection decides
        // nothing.
        #expect(sent(try engine.resume(id, on: .second))
                == [.resume(.init(session: id, undos: 0, count: 0, keep: 0, end: nil))])
        let effects = engine.receive(.resume(.init(session: id, undos: 0, count: 0,
                                                   keep: 0, end: nil)), on: .third)
        #expect(sent(effects) == [.resume(.init(session: id, undos: 0, count: 0,
                                                keep: 0, end: nil))])
        #expect(engine.session(id)?.connection == .third)
        #expect(engine.session(id)?.exchange == nil)
    }

    @Test("The proposer sends its resume on one connection, and a stray elsewhere is void")
    func theProposerChoosesOneConnection() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromHere(engine, "S-mine", moves: .first)
        try play(["b1b2"], into: engine, id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)
        _ = connect(engine, .third)

        #expect(sent(try engine.resume(id, on: .second))
                == [.resume(.init(session: id, undos: 0, count: 1, keep: 1, end: nil))])
        #expect(throws: BoardGameRefusal.resumeConnectionChosen) {
            try engine.resume(id, on: .third)
        }

        let stray = engine.receive(.resume(.init(session: id, undos: 0, count: 1,
                                                  keep: 1, end: nil)), on: .third)
        #expect(stray.isEmpty, "void")
        #expect(engine.session(id)?.exchange != nil, "the exchange is not complete")

        let completing = engine.receive(.resume(.init(session: id, undos: 0, count: 1,
                                                       keep: 1, end: nil)), on: .second)
        #expect(completing.isEmpty, "this peer's resume already travelled the completing connection")
        #expect(engine.session(id)?.connection == .second)
        #expect(engine.session(id)?.settled == true)
    }

    @Test("The peer holding more plies resends the missing ones as ordinary moves")
    func theLongerLineIsResent() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b2", "b7b6"], into: engine, id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        let effects = engine.receive(.resume(.init(session: id, undos: 0, count: 1,
                                                   keep: 1, end: nil)), on: .second)
        #expect(sent(effects) == [
            .resume(.init(session: id, undos: 0, count: 2, keep: 2, end: nil)),
            .move(.init(session: id, index: 1, move: "b7b6")),
        ])
        #expect(engine.session(id)?.isInPlay == true, "nothing is owed the other way")
    }

    @Test("A resent claim travels as the ordinary move it is")
    func aResentClaim() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromHere(engine, "S-mine", moves: .first)
        try play(Self.shuffleLine, into: engine, id)
        _ = try engine.claim(in: id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        _ = try engine.resume(id, on: .second)
        let effects = engine.receive(.resume(.init(session: id, undos: 0, count: 8,
                                                    keep: 8, end: nil)), on: .second)
        #expect(sent(effects) == [.move(.init(session: id, index: 8, move: "claim"))])
        let session = try #require(engine.session(id))
        #expect(session.settled, "the exchange completed")
        #expect(session.end?.ending == .rulesDecided(.threefoldRepetition))
    }

    @Test("A peer owed plies completes only when the last of them has arrived")
    func theCompletionCondition() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b2", "b7b6"], into: engine, id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        let effects = engine.receive(.resume(.init(session: id, undos: 0, count: 3,
                                                    keep: 3, end: nil)), on: .second)
        #expect(sent(effects) == [.resume(.init(session: id, undos: 0, count: 2,
                                                 keep: 2, end: nil))])
        #expect(engine.session(id)?.exchange?.owed == 1)
        #expect(engine.session(id)?.isInPlay == false)
        #expect(throws: BoardGameRefusal.notInPlay) { try engine.play("b7b6", in: id) }

        #expect(engine.receive(.move(.init(session: id, index: 2, move: "b2b1")),
                               on: .second).isEmpty)
        let session = try #require(engine.session(id))
        #expect(session.plies == ["b1b2", "b7b6", "b2b1"])
        #expect(session.isInPlay)
        #expect(session.settled)
    }

    @Test("Neither peer sends a move before it holds the other's resume")
    func noMoveBeforeTheOthersResume() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromHere(engine, "S-mine", moves: .first)
        try play(["b1b2"], into: engine, id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)
        _ = try engine.resume(id, on: .second)

        let effects = engine.receive(.move(.init(session: id, index: 1, move: "b7b6")),
                                     on: .second)
        #expect(violations(effects) == [.noLawfulMeaning])
        #expect(engine.session(id) == nil)
    }

    @Test("The peer with more retractions decides the truncation")
    func undosDecideTheTruncation() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b2", "b7b6", "b2b1"], into: engine, id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        // They accepted a retraction this peer never learned of.
        let effects = engine.receive(.resume(.init(session: id, undos: 1, count: 1,
                                                    keep: 1, end: nil)), on: .second)
        #expect(sent(effects) == [.resume(.init(session: id, undos: 0, count: 3,
                                                 keep: 3, end: nil))],
                "a resume states the session as its sender held it")
        let session = try #require(engine.session(id))
        #expect(session.plies == ["b1b2"])
        #expect(session.undos == 1)
        #expect(session.reportedKeep == 1)
        #expect(session.isInPlay)
        #expect(session.isLocalTurn, "the truncated position is this peer's to move")
    }

    @Test("A resume's end merges by the precedence rule as the terminal itself would")
    func theEndMerges() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        _ = engine.receive(.resume(.init(session: id, undos: 0, count: 0, keep: 0,
                                          end: .resign)), on: .second)
        let session = try #require(engine.session(id))
        #expect(session.end == BoardGameEnd(result: .moverWins(.second),
                                            ending: .resignation(.peer)))
        #expect(session.settled)
    }

    @Test("An ended session this peer proposed answers a resume, settled or not")
    func aSettledProposerAnswersAResume() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromHere(engine, "S-mine", moves: .first)
        _ = engine.receive(.resign(.init(session: id)), on: .first)
        #expect(engine.session(id)?.settled == true, "the other peer sent the terminal")
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        let effects = engine.receive(.resume(.init(session: id, undos: 0, count: 0,
                                                    keep: 0, end: .resign)), on: .second)
        #expect(sent(effects) == [.resume(.init(session: id, undos: 0, count: 0,
                                                 keep: 0, end: nil))],
                "the proposer answers on the connection the resume arrived on")
        let session = try #require(engine.session(id))
        #expect(session.connection == .second)
        #expect(session.exchange == nil, "and the exchange runs to completion")
    }

    @Test("An active session this peer proposed answers a resume without an intent of its own")
    func aProposerAnswersAResumeForAnActiveSession() throws {
        let engine = try connected(minting: ["S-mine"])
        let id = try activeSessionFromHere(engine, "S-mine", moves: .first)
        try play(["b1b2"], into: engine, id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        let effects = engine.receive(.resume(.init(session: id, undos: 0, count: 1,
                                                    keep: 1, end: nil)), on: .second)
        #expect(sent(effects) == [.resume(.init(session: id, undos: 0, count: 1,
                                                 keep: 1, end: nil))])
        #expect(engine.session(id)?.connection == .second)
        #expect(engine.session(id)?.isInPlay == true)
    }

    @Test("A terminal taken mid-exchange travels on the re-bind, and settles no sooner than any sent one")
    func aTerminalTakenMidExchangeTravelsOnTheReBind() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b2", "b7b6"], into: engine, id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        // They hold a ply this peer has not seen, so the exchange stays in
        // flight — and this peer's own resume has already travelled.
        _ = engine.receive(.resume(.init(session: id, undos: 0, count: 3,
                                          keep: 3, end: nil)), on: .second)
        #expect(engine.session(id)?.exchange?.owed == 1)

        #expect(try engine.resign(in: id).isEmpty, "there is nowhere to send it yet")
        #expect(engine.session(id)?.settled == false)

        let effects = engine.receive(.move(.init(session: id, index: 2, move: "b2b1")),
                                     on: .second)
        #expect(sent(effects) == [.resign(.init(session: id))],
                "the held terminal goes as the re-bind completes the exchange")
        let session = try #require(engine.session(id))
        #expect(session.connection == .second)
        #expect(session.exchange == nil)
        #expect(!session.settled, "a sent terminal settles when a later exchange completes for it")
        #expect(session.end == BoardGameEnd(result: .moverWins(.first),
                                            ending: .resignation(.local)))
    }

    @Test("A terminal taken between two resumes is judged by the one that travelled the completing connection")
    func aTerminalTakenBetweenTwoResumes() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        try play(["b1b2"], into: engine, id)
        engine.connectionDied(.first)
        // Both connections of a crossed bring-up are up, and this peer did not
        // propose, so it does not decide which one the exchange completes on.
        _ = connect(engine, .second)
        _ = connect(engine, .third)

        #expect(sent(try engine.resume(id, on: .second))
                == [.resume(.init(session: id, undos: 0, count: 1, keep: 1, end: nil))])

        #expect(try engine.resign(in: id).isEmpty, "mid-exchange there is nowhere to send it")

        #expect(sent(try engine.resume(id, on: .third))
                == [.resume(.init(session: id, undos: 0, count: 1, keep: 1, end: .resign))],
                "the later resume states the terminal; the earlier one could not have")

        // The proposer took the first of the two — the one this peer's resume
        // crossed with no end on it — and every resume on the other is void.
        let effects = engine.receive(.resume(.init(session: id, undos: 0, count: 1,
                                                    keep: 1, end: nil)), on: .second)
        #expect(sent(effects) == [.resign(.init(session: id))],
                "nothing the other peer read carried the terminal, so it goes as itself")
        let session = try #require(engine.session(id))
        #expect(session.connection == .second)
        #expect(!session.settled)
        #expect(session.end == BoardGameEnd(result: .moverWins(.first),
                                            ending: .resignation(.local)))
    }

    @Test("A standing offer does not survive the exchange that re-binds the session")
    func theExchangeVoidsAStandingItem() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 0, move: "b1b2")), on: .first)
        _ = engine.receive(.offerDraw(.init(session: id, at: 1)), on: .first)
        #expect(engine.session(id)?.item != nil)

        // Their side saw the connection die; this one did not, so only their
        // copy of the offer went with it.
        _ = connect(engine, .second)
        _ = engine.receive(.resume(.init(session: id, undos: 0, count: 1,
                                          keep: 1, end: nil)), on: .second)

        let session = try #require(engine.session(id))
        #expect(session.item == nil)
        #expect(session.connection == .second)
        #expect(throws: BoardGameRefusal.noStandingItem) { try engine.acceptDraw(in: id) }
    }

    @Test("A second resume on the connection this peer's own already travelled is refused")
    func aRepeatedResumeIsRefused() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        _ = try engine.resume(id, on: .second)
        #expect(throws: BoardGameRefusal.resumeOutstanding) { try engine.resume(id, on: .second) }
    }

    @Test("An unknown_session answer to this peer's own resume voids the session")
    func unknownSessionAnswersAResumeMidExchange() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        engine.connectionDied(.first)
        _ = connect(engine, .second)

        // This peer did not propose, so no completing connection is known —
        // and the one that would name it is never coming.
        _ = try engine.resume(id, on: .second)
        #expect(engine.session(id)?.exchange?.completing == nil)

        let effects = engine.receive(.decline(.init(session: id, reason: .unknownSession)),
                                     on: .second)
        #expect(effects == [.declined(session: id, peer: .peer, reason: .unknownSession)])
        #expect(engine.session(id) == nil, "the session is void on both sides")
    }

    @Test("An unprompted unknown_session decline answers nothing and has no lawful meaning")
    func anUnpromptedUnknownSessionDecline() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)

        let effects = engine.receive(.decline(.init(session: id, reason: .unknownSession)),
                                     on: .first)
        #expect(violations(effects) == [.noLawfulMeaning])
        #expect(engine.session(id) == nil)
    }

    @Test("An ended session discards a decline it did not ask for")
    func anEndedSessionDiscardsAnUnpromptedDecline() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.resign(.init(session: id)), on: .first)

        let effects = engine.receive(.decline(.init(session: id, reason: .unknownSession)),
                                     on: .first)
        #expect(effects.isEmpty)
        #expect(engine.session(id) != nil, "discarded, never a violation")
    }

    @Test("A resume for a session this peer does not hold is answered with unknown_session")
    func unknownSessionIsAnswered() throws {
        let engine = try connected()
        let effects = engine.receive(.resume(.init(session: "S-nobody", undos: 0, count: 0,
                                                    keep: 0, end: nil)), on: .first)
        #expect(sent(effects) == [.decline(.init(session: "S-nobody", reason: .unknownSession))])
    }

    @Test("A resume for a session this peer retired is answered with unknown_session")
    func aRetiredSessionIsUnknown() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.resign(.init(session: id)), on: .first)
        _ = peerProposes(engine, "S-next")
        #expect(engine.session(id) == nil, "the arriving proposal retired the ended copy")

        // Their resume for the old session crossed the proposal that retired
        // it, and this peer genuinely does not know it any more: the answer is
        // the one that voids it on both sides.
        let effects = engine.receive(.resume(.init(session: id, undos: 0, count: 0,
                                                    keep: 0, end: .resign)), on: .first)
        #expect(sent(effects) == [.decline(.init(session: id, reason: .unknownSession))])
        #expect(engine.session("S-next")?.state == .proposed, "and the new proposal stands")
    }

    @Test("An unknown_session answer voids the session on this side too")
    func unknownSessionVoidsIt() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = try engine.resign(in: id)
        engine.connectionDied(.first)
        _ = connect(engine, .second)
        _ = try engine.resume(id, on: .second)

        let effects = engine.receive(.decline(.init(session: id, reason: .unknownSession)),
                                     on: .second)
        #expect(effects == [.declined(session: id, peer: .peer, reason: .unknownSession)])
        #expect(engine.session(id) == nil)
    }

    @Test("A settled session has nothing to resume")
    func nothingToResume() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.resign(.init(session: id)), on: .first)
        #expect(engine.session(id)?.settled == true)
        #expect(throws: BoardGameRefusal.nothingToResume) { try engine.resume(id, on: .first) }
    }

    @Test("A resume for a proposal has no lawful meaning")
    func resumingAProposal() throws {
        let engine = try connected()
        _ = peerProposes(engine, "S")
        let effects = engine.receive(.resume(.init(session: "S", undos: 0, count: 0,
                                                    keep: 0, end: nil)), on: .first)
        #expect(violations(effects) == [.noLawfulMeaning])
        #expect(engine.session("S") == nil)
    }

    // MARK: - Violations

    @Test("A violation closes the connection, and the engine forgets it")
    func aViolationForgetsTheConnection() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = engine.receive(.move(.init(session: id, index: 5, move: "b1b2")), on: .first)

        #expect(engine.session(id) == nil)
        // The transport will not hand the engine that identifier again, and the
        // engine is ready for a fresh connection under it.
        #expect(sent(engine.connectionOpened(.first, with: .peer)) == [.hello(.init())])
    }

    @Test("A message delivered after this peer's own close verdict is discarded")
    func aMessageAfterTheCloseVerdict() throws {
        let engine = try connected()
        let id = try activeSessionFromPeer(engine, peerMoves: .first)
        _ = connect(engine, .second)

        // A second connection, carrying no session, closed by a message for a
        // session this peer does not hold.
        #expect(closed(engine.receive(.resign(.init(session: "S-nobody")), on: .second))
                == [.second])
        let held = try #require(engine.session(id))

        // The transport's receive loop had already taken this one when the
        // verdict went out.
        #expect(engine.receive(.move(.init(session: id, index: 0, move: "b1b2")),
                               on: .second).isEmpty)
        #expect(engine.session(id) == held, "nothing it says has anywhere to apply")
        #expect(engine.sessions.count == 1)
    }

    @Test("A message the transport could not read is malformed")
    func aMessageThatDidNotDecode() throws {
        let engine = try connected()
        let effects = engine.receivedMalformedMessage(on: .first)
        #expect(violations(effects) == [.malformed])
        #expect(closed(effects) == [.first])
    }

    // MARK: - Driving the engine

    private func engine(minting identifiers: [String] = []) throws -> BoardGameEngine {
        let core = try TestCores.fresh()
        let pending = Identifiers(identifiers)
        return BoardGameEngine(rules: core.boardGameRules, sessionIDs: { pending.next() })
    }

    /// An engine with one connection up and the other peer's hello in hand.
    private func connected(minting identifiers: [String] = []) throws -> BoardGameEngine {
        let engine = try engine(minting: identifiers)
        _ = connect(engine, .first)
        return engine
    }

    @discardableResult
    private func connect(_ engine: BoardGameEngine,
                         _ connection: ConnectionID) -> [BoardGameEffect] {
        let effects = engine.connectionOpened(connection, with: .peer)
        _ = engine.receive(.hello(.init()), on: connection)
        return effects
    }

    @discardableResult
    private func peerProposes(_ engine: BoardGameEngine, _ id: String,
                              moves: Mover = .first, game: String = "minixiangqi",
                              version: String = "1",
                              on connection: ConnectionID = .first) -> [BoardGameEffect] {
        engine.receive(.propose(.init(session: id, rulesID: game, rulesVersion: version,
                                      proposerMoves: moves)),
                       on: connection)
    }

    /// An active session the other peer proposed and this one accepted.
    private func activeSessionFromPeer(_ engine: BoardGameEngine, _ id: String = "S-peer",
                                       peerMoves: Mover = .first,
                                       on connection: ConnectionID = .first) throws -> String {
        peerProposes(engine, id, moves: peerMoves, on: connection)
        _ = try engine.answer(id, accepting: true)
        return id
    }

    /// An active session this peer proposed and the other accepted.
    private func activeSessionFromHere(_ engine: BoardGameEngine, _ id: String,
                                       moves: Mover = .first,
                                       on connection: ConnectionID = .first) throws -> String {
        _ = try engine.propose(to: .peer, on: connection, rulesID: "minixiangqi",
                               proposerMoves: moves)
        _ = engine.receive(.accept(.init(session: id)), on: connection)
        return id
    }

    /// Plays a line into a session, each ply from whichever peer owes it.
    @discardableResult
    private func play(_ line: [String], into engine: BoardGameEngine, _ id: String,
                      on connection: ConnectionID = .first) throws -> [BoardGameEffect] {
        var effects: [BoardGameEffect] = []
        for text in line {
            let session = try #require(engine.session(id))
            if session.isLocalTurn {
                effects += try engine.play(text, in: id)
            } else {
                effects += engine.receive(.move(.init(session: id, index: session.count,
                                                      move: text)),
                                          on: connection)
            }
        }
        return effects
    }

    // MARK: - Reading the answers

    private func sent(_ effects: [BoardGameEffect]) -> [BoardGameMessage] {
        effects.compactMap { effect in
            guard case .send(let message, _) = effect else { return nil }
            return message
        }
    }

    private func closed(_ effects: [BoardGameEffect]) -> [ConnectionID] {
        effects.compactMap { effect in
            guard case .close(let connection, _) = effect else { return nil }
            return connection
        }
    }

    private func violations(_ effects: [BoardGameEffect]) -> [Violation.Kind] {
        effects.compactMap { effect in
            guard case .close(_, .violation(let violation)) = effect else { return nil }
            return violation.kind
        }
    }
}

// MARK: - The transport's names, pinned for the suite

extension ConnectionID {
    fileprivate static let first = ConnectionID("connection-1")
    fileprivate static let second = ConnectionID("connection-2")
    fileprivate static let third = ConnectionID("connection-3")
}

extension PeerDeviceID {
    fileprivate static let peer = PeerDeviceID("peer-device")
}

/// The session identifiers a test pins. `@unchecked Sendable` because the suite
/// is main-actor and every test body synchronous: nothing else can be inside
/// this while a test is.
private final class Identifiers: @unchecked Sendable {
    private var pending: [String]

    init(_ pending: [String]) { self.pending = pending }

    func next() -> String {
        pending.isEmpty ? "unpinned-\(UUID().uuidString)" : pending.removeFirst()
    }
}
