// The library the History screen reads, and the walk the replay screen makes.
//
// Every test here plays real games into a real store through the same path a
// person's game takes, then reads them back through the same surface the screen
// reads them through. Nothing asserts a rule and nothing asserts an order this
// code computed: the order is the core's guarantee, and what is checked is that
// the library reports it and never rearranges it.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The History library")
@MainActor
struct HistoryTests {

    /// The mate line, reached after a four-ply shuffle that returns the
    /// position to the start — the same mate, in a longer game, so that two
    /// filed records differ by more than their instant.
    static let longMateLine = ["b1b2", "b7b6", "b2b1", "b6b7"] + GameTests.mateLine

    /// Plays each line into one store and files it, as the app does: a
    /// claimable repetition is claimed, a natural result is confirmed.
    @discardableResult
    private func file(_ lines: [[String]], into core: Core) throws -> Core {
        for line in lines {
            core.endSession()
            let game = try Game(rules: core)
            try game.replay(line)
            if game.evaluation.claimAvailable {
                game.claimDraw()
            } else {
                try game.file()
            }
        }
        core.endSession()
        return core
    }

    private func library(over core: Core) -> HistoryLibrary {
        let library = HistoryLibrary(store: core.history)
        library.load()
        return library
    }

    // MARK: - What the list shows

    @Test("An empty library is empty, and says so only once it has answered")
    func absenceIsTheEmptyState() throws {
        let core = try TestCores.fresh()
        let library = HistoryLibrary(store: core.history)
        #expect(!library.isEmpty, "nothing may be claimed before the store has answered")

        library.load()
        #expect(library.loaded)
        #expect(library.isEmpty)
        #expect(library.records.isEmpty)
        #expect(library.failure == nil)
    }

    @Test("The list is the store's, newest first, and the active game is not in it")
    func theListReflectsTheStore() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine, Self.longMateLine], into: core)

        // A game still being played is the active game, which is not a History
        // record and must not appear.
        let playing = try Game(rules: core)
        try playing.replay(["b1b4"])

        let library = library(over: core)
        #expect(library.records.count == 2, "two filed games, and only those two")
        #expect(library.records.map(\.moveCount) == [7, 3],
                "the most recently filed comes first")
        #expect(library.records.allSatisfy { $0.outcome == .redWins })
        #expect(library.records.allSatisfy { $0.reason == .checkmate })
        #expect(library.records.allSatisfy { $0.mode == .freePlay })
        #expect(library.records.allSatisfy { !$0.pinned })
        #expect(library.pinnedRecords.isEmpty)
        #expect(library.unpinnedRecords.count == 2)
    }

    @Test("A claimed draw and a confirmed mate keep their own outcomes")
    func eachRecordKeepsItsOwnResult() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine, GameTests.shuffleLine], into: core)

        let library = library(over: core)
        let draw = try #require(library.records.first)
        #expect(draw.outcome == .draw)
        #expect(draw.reason == .threefoldRepetition)
        #expect(draw.moveCount == 8)

        let mate = try #require(library.records.last)
        #expect(mate.outcome == .redWins)
        #expect(mate.reason == .checkmate)
        #expect(mate.moveCount == 3)
    }

    // MARK: - Pin

    @Test("Pinning moves a record to the front, and unpinning puts it back")
    func pinningReorders() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine, Self.longMateLine], into: core)
        let library = library(over: core)

        // The older game — last in the list, because the newest is first.
        let older = try #require(library.records.last)
        library.setPinned(true, on: older)

        #expect(library.records.first?.id == older.id,
                "a pinned record comes before every unpinned one")
        #expect(library.records.first?.pinned == true)
        #expect(library.pinnedRecords.map(\.id) == [older.id],
                "and the pinned group is exactly it")
        #expect(library.unpinnedRecords.count == 1)

        library.setPinned(false, on: try #require(library.records.first))
        #expect(library.records.last?.id == older.id, "unpinned, it is the older game again")
        #expect(library.pinnedRecords.isEmpty)
    }

    // MARK: - Delete

    @Test("Deletion removes the record permanently and leaves the rest alone")
    func deletionIsPermanent() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine, Self.longMateLine], into: core)
        let library = library(over: core)
        let survivor = try #require(library.records.first).id
        let doomed = try #require(library.records.last)

        library.delete(doomed)

        #expect(library.deletionFailure == nil)
        #expect(library.records.map(\.id) == [survivor], "the other game is untouched")
        #expect(try core.historyCount() == 1, "and the store agrees")
    }

    @Test("A deletion the store refuses is recorded for the retry, and changes nothing")
    func aRefusedDeletionChangesNothing() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine], into: core)
        let library = library(over: core)
        let record = try #require(library.records.first)

        library.delete(record)
        #expect(library.records.isEmpty)

        // The same record again: a record_id is never reissued, so the second
        // deletion is a real refusal from a real store rather than a stand-in's.
        library.delete(record)
        #expect(library.deletionFailure != nil, "the refusal is held for the alert")
        #expect(try core.historyCount() == 0, "and nothing else changed")

        library.dismissDeletionFailure()
        #expect(library.deletionFailure == nil)
    }

    @Test("Deleting the active game's record is refused: it is not a History record")
    func theActiveGameCannotBeDeleted() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine], into: core)
        let library = library(over: core)
        let filed = try #require(library.records.first)

        let playing = try Game(rules: core)
        try playing.replay(["b1b4"])
        #expect(try core.activeGameExists())

        // Every id the list can offer belongs to a filed game, so the active
        // game is out of reach by construction. What is checked here is the
        // store's own half of that: it names no active game to the list, and
        // the record ids the list does hold are not the active game's.
        library.load()
        #expect(library.records.map(\.id) == [filed.id],
                "the active game is not a row anything can act on")
        #expect(try core.activeGameExists(), "and reading History did not disturb it")
    }

    // MARK: - The metadata line

    @Test("The line names the mode, the result, the reason, and the move count")
    func theMetadataLineComposes() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine], into: core)
        let record = try #require(library(over: core).records.first)

        let line = record.metadataLine
        #expect(line.contains(record.modeText))
        #expect(line.contains(record.resultText))
        #expect(line.contains(try #require(record.reasonText)),
                "a checkmate says so: the result word alone does not")
        #expect(line.contains(record.moveCountText))
        // Free Play has no controller label, exactly as the turn status has
        // none, because one person controls both sides.
        #expect(record.humanSide == nil)
        #expect(line.split(separator: "·").count == 4,
                "mode · result · reason · moves, and nothing else")
    }

    @Test("An ended-early record says why instead of saying it twice")
    func anEndedEarlyRecordDropsTheReason() {
        // `outcome = none` is true exactly when `end_reason = ended-early`, so
        // the two are one fact and the row states it once.
        let record = RecordSummary(id: 1, mode: .freePlay, humanSide: nil,
                                   outcome: .none, reason: .endedEarly,
                                   moveCount: 12, pinned: false, imported: false,
                                   endedAt: .now)
        #expect(record.reasonText == nil)
        #expect(record.resultText == EndReason.endedEarly.text)
        #expect(record.metadataLine.split(separator: "·").count == 3,
                "mode · ended early · moves")
    }

    @Test("A human-versus-AI record names the human's side")
    func aHumanVersusAIRecordNamesTheSide() {
        let record = RecordSummary(id: 1, mode: .humanVersusAI, humanSide: .black,
                                   outcome: .redWins, reason: .resignation,
                                   moveCount: 42, pinned: false, imported: false,
                                   endedAt: .now)
        #expect(record.metadataLine.contains(String(localized: "metadata.youBlack")))
        #expect(record.reasonText != nil,
                "a resignation keeps its reason: 红方获胜 alone does not say whether the player was mated")
        #expect(record.metadataLine.split(separator: "·").count == 5,
                "mode · side · result · reason · moves")
    }
}

@Suite("Replaying a History record")
@MainActor
struct ReplayTests {

    private func replay(of line: [String]) throws -> (Replay, [String], [String]) {
        let core = try TestCores.fresh()
        let played = try Game(rules: core)
        try played.replay(line)
        let notation = played.notation
        // The positions the game itself stood in, ply by ply, captured while it
        // was being played — which is what the walk has to reproduce.
        var fens = [String]()
        for ply in 0...line.count { fens.append(try core.fen(atPly: ply)) }
        // Only a finished or claimable game can be filed today: an ordinary
        // ongoing one is archived by the save-and-continue flow, which is not
        // built yet. A line that is neither is a mistake in the test.
        try #require(played.evaluation.claimAvailable || played.isFinished,
                     "a replay test's line has to be one the app can file")
        if played.evaluation.claimAvailable { played.claimDraw() } else { try played.file() }
        core.endSession()

        let library = HistoryLibrary(store: core.history)
        library.load()
        let record = try #require(library.records.first)
        switch library.replay(of: record) {
        case .success(let replay): return (replay, notation, fens)
        case .failure(let error): throw error
        }
    }

    @Test("Replay opens at the initial position with no move behind it")
    func replayOpensAtTheStart() throws {
        let (replay, notation, fens) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        #expect(replay.ply == 0)
        #expect(replay.isAtStart)
        #expect(!replay.isAtEnd)
        #expect(replay.lastMove == nil, "no brackets at an initial position")
        #expect(replay.position.fen == fens[0])
        #expect(replay.moves == GameTests.mateLine)
        #expect(replay.notation == notation,
                "the record reads back in the words the sitting itself wrote")
        #expect(!replay.flipped, "Free Play opens Red at the bottom")
    }

    @Test("The walk is the core's: every ply is the position the game stood in")
    func theWalkMatchesThePositionsPlayed() throws {
        let (replay, _, fens) = try replay(of: GameTests.shuffleLine)
        defer { replay.close() }

        #expect(replay.position.fen == fens[0])
        while !replay.isAtEnd {
            replay.stepForward()
            #expect(replay.position.fen == fens[replay.ply],
                    "ply \(replay.ply) is the position the game stood in")
            #expect(replay.lastMove?.text == GameTests.shuffleLine[replay.ply - 1],
                    "the brackets mark the move that produced what is on screen")
        }
        #expect(replay.ply == GameTests.shuffleLine.count, "the whole line, and no more")
    }

    @Test("The transport reaches both ends and stops at them")
    func theTransportIsBounded() throws {
        let (replay, _, _) = try replay(of: GameTests.shuffleLine)
        defer { replay.close() }
        let plies = GameTests.shuffleLine.count

        replay.stepBack()
        #expect(replay.ply == 0, "there is nothing before the initial position")

        replay.goToEnd()
        #expect(replay.ply == plies)
        #expect(replay.isAtEnd)
        replay.stepForward()
        #expect(replay.ply == plies, "and nothing after the last")

        replay.stepBack()
        #expect(replay.ply == plies - 1)
        replay.goToStart()
        #expect(replay.ply == 0)

        replay.show(move: 2)
        #expect(replay.ply == 2, "the move list jumps to a selected move")
    }

    @Test("A checked general is ringed at the ply that checks it, and not before")
    func checkFollowsTheWalk() throws {
        // The mate line ends in check, which is what makes it a mate; the
        // check line itself leaves the game running, and an ongoing game is
        // not a History record yet.
        let (replay, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        #expect(replay.checkedGeneral == nil)
        replay.goToEnd()
        #expect(replay.position.inCheck, "the core reports the check")
        #expect(replay.checkedGeneral == Square("d7"),
                "and the rings go round the general it is about")
        replay.stepBack()
        #expect(replay.checkedGeneral == nil, "walking back walks the check back too")
    }

    @Test("Autoplay walks to the end and stops there")
    func autoplayStopsAtTheEnd() throws {
        let (replay, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        replay.toggleAutoplay()
        #expect(replay.autoplaying, "playback starts only after a user action, and this was one")

        // Manual navigation pauses playback, which is the accepted behaviour
        // and is also what keeps this test off the clock.
        replay.stepForward()
        #expect(!replay.autoplaying)
        #expect(replay.ply == 1)

        replay.goToEnd()
        replay.toggleAutoplay()
        #expect(!replay.autoplaying, "there is nothing left to play at the final position")
    }

    @Test("Flipping the board changes presentation only, and pauses playback")
    func flippingIsPresentationOnly() throws {
        let (replay, _, fens) = try replay(of: GameTests.shuffleLine)
        defer { replay.close() }
        replay.toggleAutoplay()

        replay.flipped = true

        #expect(!replay.autoplaying, "a flip pauses playback")
        #expect(replay.ply == 0)
        #expect(replay.position.fen == fens[0], "and changes nothing about the position")
    }

    @Test("A closed replay releases its session and answers nothing further")
    func closingReleasesTheSession() throws {
        let (replay, _, _) = try replay(of: GameTests.mateLine)
        replay.close()

        // The walk stops rather than crashing: an invalid handle is the answer
        // the interface promises after a release, and the walk clamps to what
        // it already had.
        replay.stepForward()
        #expect(replay.ply == 0)
    }
}
