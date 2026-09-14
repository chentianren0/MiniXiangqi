// The store's memory of a nearby game.
//
// Over the real core and a scratch library, because what these cases are about
// is the library: which core call a change in the protocol session turns into,
// and what the store holds afterwards. A stand-in library would be a second
// opinion about that, which is exactly the thing worth not having.

import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@MainActor
@Suite("A nearby game in the library", .retiringItsCores)
struct NearbyRecordTests {
    private static let peer = PeerDeviceID("wifi-aware-device-77E1B0C2")
    private static let identifier = "6f1d9c22-2f5a-7c31-9a04-0c1f2e3d4b5a"

    /// A session this device proposed and the peer accepted: local is the first
    /// mover, which is Red.
    private func session(plies: [String] = []) -> BoardGameSession {
        var session = BoardGameSession(id: Self.identifier, peer: Self.peer,
                                       rulesID: GameKind.miniXiangqi.rulesID,
                                       rulesVersion: "1", proposerMoves: .first,
                                       proposer: .local)
        session.accepted = true
        session.plies = plies
        return session
    }

    private func memory(over core: Core) -> NearbyRecord {
        NearbyRecord(library: core, rules: core.boardGameRules, log: NearbyLog(),
                     mode: .nearby)
    }

    /// The same, over a library whose archive-and-clear this suite answers. It
    /// is the one call that cannot answer inside itself — the threading
    /// contract keeps it off this actor — so the result-less filing path is
    /// reached by parking it, exactly as the Play home's suite parks the same
    /// seam.
    private func memory(over parked: ParkedNearbyArchive) -> NearbyRecord {
        NearbyRecord(library: parked, rules: parked.core.boardGameRules,
                     log: NearbyLog(), mode: .nearby)
    }

    /// A session this device's *peer* proposed: local takes the second mover,
    /// which is Black, so a line's even-indexed plies are the peer's.
    private func peerProposed(_ game: GameKind = .miniXiangqi,
                              plies: [String] = []) -> BoardGameSession {
        var session = BoardGameSession(id: Self.identifier, peer: Self.peer,
                                       rulesID: game.rulesID,
                                       rulesVersion: "1", proposerMoves: .first,
                                       proposer: .peer)
        session.accepted = true
        session.plies = plies
        return session
    }

    /// A dealt session this device proposed, over the corpus's own deal — the
    /// one vector the store fixtures and the protocol suites all read.
    private func dealtSession(plies: [String] = []) -> BoardGameSession {
        var session = BoardGameSession(id: Self.identifier, peer: Self.peer,
                                       rulesID: GameKind.jieqi.rulesID,
                                       rulesVersion: "1", proposerMoves: .first,
                                       proposer: .local)
        session.accepted = true
        session.handshake = .dealt(
            BoardGameDeal(commit: BoardGameRulesTests.commit,
                          nonce: BoardGameRulesTests.nonce,
                          seed: BoardGameRulesTests.seed,
                          digest: BoardGameRulesTests.digest,
                          start: BoardGameRulesTests.dealtStart))
        session.plies = plies
        return session
    }

    /// The mating line: three plies, and the third — index 2, an even index —
    /// is the first mover's.
    private static let mate = ["b1b3", "a6a5", "b3d3"]

    /// The first mover's five along the eighth rank, the other player answering
    /// down the a-file. Nine plies, and the ninth — index 8, an even index — is
    /// the first mover's.
    private static let fiveInARow = ["d8", "a1", "e8", "a2", "f8", "a3",
                                     "g8", "a4", "h8"]

    // MARK: - Becoming the library's active game

    @Test("A session that becomes active is the library's active game")
    func anActiveSessionIsTheActiveGame() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([session()])

        let summary = try #require(try core.activeGameSummary())
        #expect(summary.mode == .nearby)
        #expect(summary.game == .miniXiangqi)
        #expect(summary.localSide == .red, "the mover the protocol resolved")
        #expect(summary.moveCount == 0)

        let wire = try #require(try core.nearbyWireSession())
        #expect(wire.sessionID == Self.identifier)
        #expect(wire.peerID == Self.peer.rawValue)
        #expect(wire.proposedLocally)
        #expect(wire.undos == 0)
        #expect(wire.sentEnd == nil)
        #expect(!wire.claimed)
    }

    /// The mode is the record's own, and it is the only thing the two ways of
    /// reaching another device differ by in the library.
    ///
    /// What this would catch is every game two devices play being filed as a
    /// nearby one: History and the Current Game card would name the mode
    /// untruthfully, and the record a player exported would say a game played
    /// at any distance had been played in the same room.
    @Test("A game played over Game Center is recorded as an online one")
    func anOnlineGameIsRecordedAsOnline() throws {
        let core = try TestCores.fresh()
        let record = NearbyRecord(library: core, rules: core.boardGameRules,
                                  log: NearbyLog(), mode: .online)

        record.follow([session()])

        let summary = try #require(try core.activeGameSummary())
        #expect(summary.mode == .online)
        #expect(summary.game == .miniXiangqi)
        #expect(summary.localSide == .red, "and everything else is nearby play's")
        #expect(try core.nearbyWireSession()?.sessionID == Self.identifier)
    }

    /// One record per way of reaching another device, and each takes up only
    /// its own mode's interrupted game.
    ///
    /// What this would catch is a record reading any networked active game
    /// back: both records would claim one game at launch, and the session one
    /// of them handed the engine would be offered to peers that never held it.
    @Test("A record takes up the interrupted game of its own mode alone")
    func aRecordResumesOnlyItsOwnMode() throws {
        let core = try TestCores.fresh()
        NearbyRecord(library: core, rules: core.boardGameRules,
                     log: NearbyLog(), mode: .online).follow([session()])
        core.endSession()

        #expect(try memory(over: core).standing() == nil,
                "the online game standing is not the nearby record's to rebuild")
        #expect(try NearbyRecord(library: core, rules: core.boardGameRules,
                                 log: NearbyLog(), mode: .online).standing() != nil)
    }

    @Test("A dealt game reaches the library as its deal, with the evidence it was dealt")
    func aDealtGameCarriesItsDeal() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([dealtSession()])
        record.follow([dealtSession(plies: ["b1c3"])])

        let summary = try #require(try core.activeGameSummary())
        #expect(summary.game == .jieqi)
        #expect(summary.mode == .nearby)
        #expect(try core.moveHistory() == ["b1c3"])

        let wire = try #require(try core.nearbyWireSession())
        let deal = try #require(wire.deal)
        #expect(deal.commit == BoardGameRulesTests.commit)
        #expect(deal.nonce == BoardGameRulesTests.nonce)
        #expect(deal.seed == BoardGameRulesTests.seed)
        #expect(deal.digest == BoardGameRulesTests.digest,
                "the fourth is the session's own, and never reaches the archive")
    }

    @Test("A dealt game is created over its deal, and files the evidence it was dealt")
    func aDealtGameIsFiledWithItsProvenance() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([dealtSession()])

        // **The deal rides in the game's own start.** A dealt game has no frozen
        // position to begin from: what the handshake derived is the position it
        // was created over, and every reveal and disclosed capture replays from
        // it.
        #expect(try core.configuration().startFEN == BoardGameRulesTests.dealtStart)

        var over = dealtSession(plies: ["b1c3"])
        over.peerTerminal = .resign
        record.follow([over])

        let library = HistoryLibrary(store: core.history)
        library.load()
        let filed = try #require(library.records.first)
        #expect(filed.game == .jieqi)
        #expect(filed.mode == .nearby)

        // And what stands beside the start in the filed document is the evidence
        // the deal was not chosen: with the three, anybody holding the file can
        // hash the seed against the commitment, derive the deal, and check that
        // what comes out is the start in front of them.
        let text = try #require(String(data: try core.history.export(filed.id),
                                       encoding: .utf8))
        #expect(text.contains("\"start_fen\":\"\(BoardGameRulesTests.dealtStart)\""))
        #expect(text.contains("\"deal_commit\":\"\(BoardGameRulesTests.commit)\""))
        #expect(text.contains("\"deal_nonce\":\"\(BoardGameRulesTests.nonce)\""))
        #expect(text.contains("\"deal_seed\":\"\(BoardGameRulesTests.seed)\""))
        #expect(!text.contains(BoardGameRulesTests.digest),
                "the fourth is derivable from the deal it names, and is no part of it")
    }

    @Test("A dealt game comes back over the deal it was played on, re-verified")
    func aDealtGameComesBack() throws {
        let directory = TestCores.scratchDirectory()
        do {
            let core = try TestCores.open(at: directory)
            let record = memory(over: core)
            record.follow([dealtSession()])
            record.follow([dealtSession(plies: ["b1c3", "b8e8"])])
            record.release()
        }

        let relaunched = try TestCores.open(at: directory)
        let record = memory(over: relaunched)
        let restored = try #require(try record.standing())

        #expect(restored.plies == ["b1c3", "b8e8"])
        #expect(restored.state == .active, "a completed handshake comes back active")
        #expect(restored.deal?.digest == BoardGameRulesTests.digest)
        #expect(restored.deal?.seed == BoardGameRulesTests.seed)
        #expect(restored.dealtStart == BoardGameRulesTests.dealtStart,
                "the deal is derived from the seed and the nonce again, not stored")
    }

    @Test("Plies from either side reach the store as they land")
    func pliesReachTheStore() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([session()])
        record.follow([session(plies: ["b1b3"])])
        record.follow([session(plies: ["b1b3", "b7b5"])])

        #expect(try core.moveHistory() == ["b1b3", "b7b5"])
        #expect(try core.activeGameSummary()?.moveCount == 2)
        #expect(try core.nearbyWireSession()?.undos == 0,
                "a ply carries the retraction count it did not change")
    }

    @Test("The negotiated retraction moves the line and the count together")
    func theRetractionMovesBoth() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([session()])
        record.follow([session(plies: ["b1b3", "b7b5", "b3b1"])])

        var retracted = session(plies: ["b1b3"])
        retracted.undos = 1
        retracted.retractedTo = 1
        record.follow([retracted])

        #expect(try core.moveHistory() == ["b1b3"], "what the two players kept")
        let wire = try #require(try core.nearbyWireSession())
        #expect(wire.undos == 1)
        #expect(wire.keep == 1)
    }

    @Test("A resume that reconciles to another line is followed too")
    func reconciliationIsFollowed() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([session()])
        record.follow([session(plies: ["b1b3", "b7b5", "b3b1"])])

        // The other peer's resume reported a higher undos, so this device
        // truncated to its keep and the line then grew a different way.
        var reconciled = session(plies: ["b1b3", "a6a5"])
        reconciled.undos = 2
        reconciled.retractedTo = 1
        record.follow([reconciled])

        #expect(try core.moveHistory() == ["b1b3", "a6a5"])
        #expect(try core.nearbyWireSession()?.undos == 2)
    }

    // MARK: - Ending

    @Test("A terminal this device sent is recorded and files nothing")
    func anUnsettledTerminalWaits() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([session()])
        var resigned = session(plies: ["b1b3"])
        resigned.localTerminal = .resign
        resigned.settled = false
        record.follow([resigned])

        #expect(try core.activeGameSummary() != nil,
                "the game is still the library's, because the peers have not settled")
        #expect(try core.nearbyWireSession()?.sentEnd == .resign)
        #expect(try core.historyCount() == 0)
    }

    @Test("A settled ending files the game into History")
    func aSettledEndingFiles() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([session()])
        var over = session(plies: ["b1b3"])
        over.peerTerminal = .resign
        record.follow([over])

        #expect(try core.activeGameSummary() == nil,
                "the terminal commit cleared the active-game reference")
        let library = HistoryLibrary(store: core.history)
        library.load()
        let filed = try #require(library.records.first)
        #expect(filed.mode == .nearby)
        #expect(filed.reason == .resignation)
        #expect(filed.outcome == .redWins, "the peer took Black and resigned")
        #expect(filed.moveCount == 1)
    }

    @Test("An agreed draw files as the end the two players declared")
    func anAgreedDrawFiles() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([session()])
        var agreed = session(plies: ["b1b3", "b7b5"])
        agreed.peerTerminal = .acceptDraw
        record.follow([agreed])

        let library = HistoryLibrary(store: core.history)
        library.load()
        let filed = try #require(library.records.first)
        #expect(filed.reason == .agreedDraw)
        #expect(filed.outcome == .draw)
    }

    @Test("A session the engine parted with is filed as it stood")
    func aVoidedSessionIsFiled() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([session()])
        var resigned = session(plies: ["b1b3"])
        resigned.localTerminal = .resign
        resigned.settled = false
        record.follow([resigned])

        // The peer's fresh proposal retired it, or its resume was answered with
        // `unknown_session`: either way the engine no longer holds it, and there
        // is no way back into the game.
        record.follow([])

        #expect(try core.activeGameSummary() == nil)
        let library = HistoryLibrary(store: core.history)
        library.load()
        let filed = try #require(library.records.first)
        #expect(filed.reason == .resignation)
        #expect(filed.outcome == .blackWins, "this device resigned, playing Red")
    }

    // MARK: - Across a relaunch

    @Test("An interrupted game comes back with the session it was played over")
    func aRelaunchReadsTheGameBack() throws {
        let directory = TestCores.scratchDirectory()
        do {
            let core = try TestCores.open(at: directory)
            let record = memory(over: core)
            record.follow([session()])
            var standing = session(plies: ["b1b3", "b7b5", "b3b1"])
            standing.undos = 1
            standing.retractedTo = 2
            standing.localTerminal = .acceptDraw
            standing.settled = false
            record.follow([standing])
            record.release()
        }

        // A second core over the same store is exactly what a relaunch is.
        let relaunched = try TestCores.open(at: directory)
        let record = memory(over: relaunched)
        let restored = try #require(try record.standing())

        #expect(restored.id == Self.identifier)
        #expect(restored.peer == Self.peer)
        #expect(restored.plies == ["b1b3", "b7b5", "b3b1"])
        #expect(restored.undos == 1)
        #expect(restored.reportedKeep == 2)
        #expect(restored.localTerminal == .acceptDraw)
        #expect(!restored.settled, "a terminal this device sent is owed an exchange")
        #expect(restored.state == .ended, "and the game has the result it declared")
        #expect(restored.localMover == .first, "the mover came back from local_side")
        #expect(restored.proposer == .local)
        #expect(restored.connection == nil, "a connection does not survive a launch")
        #expect(restored.item == nil, "and neither does a standing offer")
    }

    @Test("A claimed draw comes back with the claim the archive does not record")
    func aClaimSurvivesTheRelaunch() throws {
        let directory = TestCores.scratchDirectory()
        let claimed = ["b1b3", "b7b5", "b3b1", "b5b7",
                       "b1b3", "b7b5", "b3b1", "b5b7"]
        do {
            let core = try TestCores.open(at: directory)
            let record = memory(over: core)
            record.follow([session()])
            var standing = session(plies: claimed + [TurnAction.claim])
            standing.rulesEnd = RulesDecision(result: .draw,
                                              reason: .threefoldRepetition)
            standing.settled = false
            record.follow([standing])
            #expect(try core.moveHistory() == claimed,
                    "the claim is not a move, and the archive records none")
            #expect(try core.nearbyWireSession()?.claimed == true)
            record.release()
        }

        let relaunched = try TestCores.open(at: directory)
        let record = memory(over: relaunched)
        let restored = try #require(try record.standing())
        #expect(restored.plies == claimed + [TurnAction.claim])
        #expect(restored.count == claimed.count + 1,
                "so the resumed count matches the peer's")
        #expect(!restored.settled)
    }

    @Test("A game this device's own ply ended comes back owing a resume")
    func ourOwnDecisivePlyRestoresUnsettled() throws {
        let directory = TestCores.scratchDirectory()
        do {
            let core = try TestCores.open(at: directory)
            let record = memory(over: core)
            record.follow([session()])
            // The mate is committed and the filing has not happened: this
            // device's own ply decided the end, so the session is unsettled and
            // the record leaves it standing.
            var mated = session(plies: Self.mate)
            mated.rulesEnd = RulesDecision(result: .moverWins(.first),
                                           reason: .checkmate)
            mated.settled = false
            record.follow([mated])
            #expect(try core.activeGameSummary() != nil,
                    "an unsettled ending is not filed")
            #expect(try core.nearbyWireSession()?.sentEnd == nil,
                    "and no terminal was sent — the plies decided it")
            record.release()
        }

        let relaunched = try TestCores.open(at: directory)
        let restored = try #require(try memory(over: relaunched).standing())
        #expect(restored.plies == Self.mate)
        #expect(restored.rulesEnd?.reason == .checkmate,
                "the end is read off the line, not out of the row")
        #expect(restored.ownPlyDecidedTheEnd)
        #expect(!restored.settled,
                "a peer whose own ply decided the end owes a resume exchange")
        #expect(try relaunched.activeGameSummary() != nil,
                "so nothing was filed on the way back in")
    }

    @Test("A game the other player's ply ended comes back settled, and files")
    func theirDecisivePlyRestoresSettledAndFiles() throws {
        let directory = TestCores.scratchDirectory()
        do {
            let core = try TestCores.open(at: directory)
            let record = memory(over: core)
            record.follow([peerProposed()])
            // Settled here the moment it arrived, so it would have been filed —
            // a row still standing over it is a filing that did not commit,
            // which is the only way this state is reached.
            var mated = peerProposed(plies: Self.mate)
            mated.rulesEnd = RulesDecision(result: .moverWins(.first),
                                           reason: .checkmate)
            mated.settled = false
            record.follow([mated])
            #expect(try core.activeGameSummary() != nil)
            record.release()
        }

        let relaunched = try TestCores.open(at: directory)
        let record = memory(over: relaunched)
        let restored = try #require(try record.standing())
        #expect(!restored.ownPlyDecidedTheEnd, "the mating ply was the peer's")
        #expect(restored.settled)

        record.follow([restored])
        #expect(try relaunched.activeGameSummary() == nil,
                "a settled ending files on the publication after the restore")
        let library = HistoryLibrary(store: relaunched.history)
        library.load()
        #expect(library.records.first?.reason == .checkmate)
    }

    @Test("A claim the other player made comes back settled")
    func theirClaimRestoresSettled() throws {
        let directory = TestCores.scratchDirectory()
        let repeated = ["b1b3", "b7b5", "b3b1", "b5b7",
                        "b1b3", "b7b5", "b3b1", "b5b7"]
        do {
            let core = try TestCores.open(at: directory)
            let record = memory(over: core)
            record.follow([peerProposed()])
            var claimed = peerProposed(plies: repeated + [TurnAction.claim])
            claimed.rulesEnd = RulesDecision(result: .draw,
                                             reason: .threefoldRepetition)
            claimed.settled = false
            record.follow([claimed])
            #expect(try core.nearbyWireSession()?.claimed == true)
            record.release()
        }

        let relaunched = try TestCores.open(at: directory)
        let restored = try #require(try memory(over: relaunched).standing())
        #expect(restored.plies.last == TurnAction.claim)
        #expect(!restored.ownPlyDecidedTheEnd,
                "the claim is a ply, and this one is at an even index")
        #expect(restored.settled, "so this device owes no exchange for it")
    }

    // MARK: - A game stones were placed in

    /// The whole record path for a game whose plies are single points: created
    /// as the library's active nearby game, followed ply by ply as they land,
    /// filed by the end the line itself decided, and read back out of History as
    /// the game that was played.
    ///
    /// It would catch the store path refusing a single-square ply — which is
    /// the one thing between a nearby placement game and the library, every call
    /// on the way being the call the movement games already make — and a filing
    /// that lost which game it was of.
    @Test("A nearby placement game is followed, filed, and replays from History")
    func aPlacementGameIsRecordedAndFiled() throws {
        let core = try TestCores.fresh()
        let record = memory(over: core)

        record.follow([peerProposed(.gomoku15)])
        let summary = try #require(try core.activeGameSummary())
        #expect(summary.game == .gomoku15)
        #expect(summary.mode == .nearby)
        #expect(summary.localSide == .black,
                "the peer proposed and took the first mover, which is the black stone")

        // The line as the driver publishes it: one ply per publication, the last
        // of them carrying the end its own plies decided.
        for count in 1...Self.fiveInARow.count {
            var live = peerProposed(.gomoku15,
                                    plies: Array(Self.fiveInARow.prefix(count)))
            if count == Self.fiveInARow.count {
                live.rulesEnd = RulesDecision(result: .moverWins(.first),
                                              reason: .fiveInARow)
            }
            record.follow([live])
        }

        #expect(try core.activeGameSummary() == nil,
                "the peer's own decisive ply is settled here, so it filed")
        let library = HistoryLibrary(store: core.history)
        library.load()
        let filed = try #require(library.records.first)
        #expect(filed.game == .gomoku15)
        #expect(filed.mode == .nearby)
        #expect(filed.outcome == .redWins, "the first mover's five, which is Black's")
        #expect(filed.reason == .fiveInARow)
        #expect(filed.moveCount == Self.fiveInARow.count)

        switch library.replay(of: filed, policy: MotionPolicy(reduceMotion: true),
                              animator: ManualAnimator().animator,
                              feedback: Feedback(perform: { _ in }, play: { _ in })) {
        case .success(let replay):
            defer { replay.close() }
            #expect(replay.moves == Self.fiveInARow)
        case .failure(let error):
            throw error
        }
    }

    // MARK: - A session the protocol parted with, and no result at all

    @Test("A parted session with no result asks the library to file it, once")
    func aPartedSessionWithNoResultIsFiled() throws {
        let core = try TestCores.fresh()
        let parked = ParkedNearbyArchive(core)
        let record = memory(over: parked)

        record.follow([session()])
        record.follow([session(plies: ["b1b3", "b7b5"])])
        #expect(try core.activeGameSummary() != nil)
        #expect(try core.moveHistory() == ["b1b3", "b7b5"])

        // `unknown_session`, a violation, or the peer's fresh proposal: the
        // engine no longer holds it, and there is no result to file it by, so
        // what a game that stopped is worth is the store's own to decide.
        record.follow([])
        #expect(parked.requests == 1, "the store's own classification is asked for")
        #expect(parked.endSessions == 0,
                "the archive takes the session with it, so nothing releases it here")

        parked.answer(.success(1))
        #expect(parked.endSessions == 0, "and a commit still releases nothing here")
        // The record is holding nothing now, which is what lets a later session
        // begin: one that still thought it held a game would follow the game
        // that has gone instead.
        record.release()
        #expect(parked.endSessions == 0,
                "a record that let go has nothing left to let go of")
        #expect(parked.requests == 1, "and it does not ask again by itself")
    }

    @Test("A refused archive of a parted session lets the session go")
    func aRefusedArchiveOfAPartedSessionLetsGo() throws {
        let core = try TestCores.fresh()
        let parked = ParkedNearbyArchive(core)
        let record = memory(over: parked)

        record.follow([session()])
        record.follow([])
        #expect(parked.requests == 1)

        parked.answerWithRefusal()
        #expect(parked.endSessions == 1,
                "a refusal puts the session back, and this record lets it go")
        #expect(try core.activeGameSummary() != nil,
                "and the game is still the library's, exactly as it stood")

        record.release()
        #expect(parked.endSessions == 1, "with nothing left to release twice")
        #expect(parked.requests == 1, "and it does not ask again by itself")
    }

    @Test("A library with no nearby game gives nothing back")
    func nothingToComeBackTo() throws {
        let core = try TestCores.fresh()
        #expect(try memory(over: core).standing() == nil)

        try core.create(.freePlay(game: .miniXiangqi))
        core.endSession()
        #expect(try memory(over: core).standing() == nil,
                "a local active game is not a nearby one")
    }
}


/// A library whose archive-and-clear this suite answers, over a real core.
///
/// It is the one call in `NearbyLibrary` that cannot answer inside itself — the
/// threading contract keeps it off this actor — so a case that wants to see what
/// follows it parks it, exactly as the Play home's suite parks the same seam.
@MainActor
final class ParkedNearbyArchive: NearbyLibrary {
    let core: Core

    private(set) var requests = 0
    /// How many times the record let go of the store's session on its own. It
    /// is the whole of the bookkeeping the two archive arms differ in: the
    /// archive takes the session with it when it commits, and hands it back
    /// when it refuses.
    private(set) var endSessions = 0
    private var parked: (@MainActor (Result<UInt64, CoreError>) -> Void)?

    init(_ core: Core) { self.core = core }

    func archiveActiveAndClear(
        completion: @escaping @MainActor (Result<UInt64, CoreError>) -> Void
    ) {
        requests += 1
        parked = completion
    }

    /// Answers the archive in flight, as the queue would. The real
    /// archive-and-clear is deliberately not performed: what it records and
    /// what it deletes are the core suite's to pin, and it cannot answer inside
    /// its own call, so a case that waited for it would suspend while holding
    /// this suite's one core.
    func answer(_ result: Result<UInt64, CoreError>) {
        let completion = parked
        parked = nil
        completion?(result)
    }

    /// The store-domain refusal, which puts the session back.
    func answerWithRefusal() {
        answer(.failure(CoreError(status: MxqStatus(MXQ_ERR_STORE_IO),
                                  detail: "refused by this suite")))
    }

    var hasSession: Bool { core.hasSession }
    func endSession() {
        endSessions += 1
        core.endSession()
    }
    func resumeActive() throws -> Bool { try core.resumeActive() }
    func create(_ configuration: GameConfiguration) throws { try core.create(configuration) }
    func configuration() throws -> GameConfiguration { try core.configuration() }
    func gameID() throws -> String { try core.gameID() }
    func resign() throws -> UInt64 { try core.resign() }
    func apply(_ move: String) throws { try core.apply(move) }
    func undo() throws -> Int { try core.undo() }
    func claimDraw() throws -> UInt64 { try core.claimDraw() }
    func confirmResult() throws -> UInt64 { try core.confirmResult() }
    func evaluation() throws -> Evaluation { try core.evaluation() }
    func moveHistory() throws -> [String] { try core.moveHistory() }
    func legalMoves() throws -> [String] { try core.legalMoves() }
    func fen(atPly ply: Int) throws -> String { try core.fen(atPly: ply) }
    func firstMover() throws -> Side { try core.firstMover() }
    func activeGameSummary() throws -> ActiveGameSummary? { try core.activeGameSummary() }
    func createNearby(_ configuration: GameConfiguration,
                      wire: NearbyWireSession) throws {
        try core.createNearby(configuration, wire: wire)
    }
    func nearbyWireSession() throws -> NearbyWireSession? { try core.nearbyWireSession() }
    func setNearbyWireSession(_ wire: NearbyWireSession) throws {
        try core.setNearbyWireSession(wire)
    }
    func retractNearby(to keep: Int, wire: NearbyWireSession) throws {
        try core.retractNearby(to: keep, wire: wire)
    }
    func commitNearbyEnd(_ ending: NearbyEnding) throws -> UInt64 {
        try core.commitNearbyEnd(ending)
    }
}
