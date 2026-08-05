// The store's memory of a nearby game.
//
// Over the real core and a scratch library, because what these cases are about
// is the library: which core call a change in the protocol session turns into,
// and what the store holds afterwards. A stand-in library would be a second
// opinion about that, which is exactly the thing worth not having.

import Foundation
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
        NearbyRecord(library: core, log: NearbyLog())
    }

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
