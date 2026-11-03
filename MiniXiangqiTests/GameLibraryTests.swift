import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The library", .retiringItsCores)
@MainActor
struct GameLibraryTests {
    /// Plays the three-ply mate on a new Mini Xiangqi game and files it.
    private func fileAMate(in library: GameLibrary,
                           _ configuration: GameConfiguration = .freePlay(game: .miniXiangqi)) throws -> UUID {
        try library.create(configuration)
        for move in GameTests.mateLine { try library.apply(move) }
        return try library.confirmResult()
    }

    @Test("A record round-trips through export and import")
    func aRecordRoundTrips() throws {
        let library = try TestLibraries.fresh()
        let id = try fileAMate(in: library, .humanVersusAI(game: .miniXiangqi, humanSide: .red,
                                                           level: .deep))
        let original = try #require(try library.record(id))
        let file = try library.fileData(of: id)

        let other = TestLibraries.another(over: library.core)
        let imported = try other.importGame(file)
        #expect(imported.outcome == .created)
        let record = imported.record
        #expect(record.id == original.id)
        #expect(record.kind == .miniXiangqi)
        #expect(record.mode == .humanVersusAI)
        #expect(record.humanSide == .red)
        #expect(record.aiLevel == .deep)
        #expect(record.setup == nil)
        #expect(record.moves == GameTests.mateLine)
        #expect(record.result == .redWins)
        #expect(record.reason == .checkmate)
        #expect(abs(record.startedAt.timeIntervalSince(original.startedAt)) < 1)
        #expect(abs(try #require(record.endedAt).timeIntervalSince(try #require(original.endedAt))) < 1)
        #expect(record.imported, "the library notes where it came from")
        #expect(try other.history().map(\.id) == [id])

        #expect(try other.importGame(file).outcome == .existing,
                "the same game a second time is the record already there")
        #expect(try other.historyCount() == 1)
    }

    @Test("History is pinned first, then newest")
    func historyOrdersPinnedFirstThenNewest() throws {
        let library = try TestLibraries.fresh()
        let oldest = try fileAMate(in: library)
        let middle = try fileAMate(in: library)
        let newest = try fileAMate(in: library)
        #expect(try library.history().map(\.id) == [newest, middle, oldest])

        try library.setPinned(true, on: try #require(try library.record(oldest)))
        #expect(try library.history().map(\.id) == [oldest, newest, middle])
    }

    @Test("Import refuses a file whose moves are illegal, and files nothing")
    func importRefusesIllegalMoves() throws {
        let library = try TestLibraries.fresh()
        let id = try fileAMate(in: library)
        var document = try #require(try JSONSerialization.jsonObject(
            with: try library.fileData(of: id)) as? [String: Any])
        document["id"] = UUID().uuidString
        document["moves"] = ["b1b3", "a6a5", "b3b8"]
        let tampered = try JSONSerialization.data(withJSONObject: document)

        #expect(throws: ImportRefusal.illegal) { try library.importGame(tampered) }
        #expect(try library.historyCount() == 1, "the library is as it was")
    }

    @Test("A dealt game round-trips through export and import, its deal as its start")
    func aDealtGameRoundTrips() throws {
        let library = try TestLibraries.fresh()
        let deal = try library.core.deal(.jieqi)
        try library.create(.freePlay(game: .jieqi, startFEN: deal.startFEN))
        let game = try Game(library: library)
        try game.replay(JieqiTests.claimableLine)
        game.claimDraw()
        let id = try #require(game.filedRecordID)

        let other = TestLibraries.another(over: library.core)
        let imported = try other.importGame(try library.fileData(of: id))
        #expect(imported.outcome == .created)
        #expect(imported.record.kind == .jieqi)
        #expect(imported.record.setup == deal.startFEN, "the deal is where the game began")
        #expect(imported.record.moves == JieqiTests.claimableLine)
        #expect(imported.record.result == .draw)
        #expect(imported.record.reason == .threefoldRepetition)
    }

    @Test("A 3.x file and a file from a newer version are refused, each with its own answer")
    func filesFromOtherVersionsAreRefused() throws {
        let library = try TestLibraries.fresh()
        let history = HistoryLibrary(library: library)

        history.importGame(Data(Self.earlierFile.utf8))
        #expect(history.importAnswer == .earlierVersion)

        let id = try fileAMate(in: library)
        var document = try #require(try JSONSerialization.jsonObject(
            with: try library.fileData(of: id)) as? [String: Any])
        document["id"] = UUID().uuidString
        document["version"] = GameRecord.fileVersion + 1
        history.importGame(try JSONSerialization.data(withJSONObject: document))
        #expect(history.importAnswer == .newerVersion)
        #expect(try library.historyCount() == 1, "neither was filed")
    }

    /// A game file as the 3.x app wrote it.
    private static let earlierFile = """
        {"archive_format":"minixiangqi-game","archive_version":7,"content":{"ai_level":"standard",\
        "ai_movetime_ms":3000,"end_reason":"checkmate","ended_at":"2026-01-01T00:00:04.000Z",\
        "first_mover_choice":"human-first","human_side":"red","mode":"human-vs-ai",\
        "moves":["b1b3","a6a5","b3d3"],"outcome":"red-wins","rules_id":"minixiangqi",\
        "rules_version":1,"start_fen":"rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1",\
        "started_at":"2026-01-01T00:00:00.000Z"},"game_id":"019b76da-a803-7000-8000-000000000003",\
        "origin":{"app_version":"1.0.0","exported_at":"2026-01-01T00:00:04.000Z"}}
        """
}
