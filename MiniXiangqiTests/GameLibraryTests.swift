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
}
