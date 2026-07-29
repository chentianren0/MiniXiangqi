// One game out as a file, one game in from one — as this app asks for them.
//
// The core's own runner already holds the pipeline to every rejection class,
// the round trip and the transaction; none of that is re-proved here. What this
// suite is for is the seam above it: that a blob becomes `Data` and is released,
// that an import lands where the list will read it, that both answers a
// successful import can give arrive as the two cases the screen switches on,
// and that a refusal arrives as the status the screen routes by. Those are this
// app's to get wrong.
//
// Every file these tests import was exported by this app a moment earlier, from
// a game it played itself. That makes the round trip the subject rather than a
// fixture's byte layout — and it is the round trip a person actually performs.
//
// Every test here is synchronous, deliberately. The core is singleton-enforced
// and `TestCores` retires the live one to build the next, so a test that
// suspends hands the main actor to a sibling that will shut its core down
// underneath it. `HistoryLibrary.importGame` is the one thing that therefore
// cannot be driven from here — it exists to move the call off the main actor —
// and it is driven end to end by the UI suite instead, against the running app.

import Foundation
import MiniXiangqiCore
import Testing
import UniformTypeIdentifiers
@testable import MiniXiangqi

@Suite("Import and export")
@MainActor
struct InterchangeTests {

    /// Plays one line into the store and files it, exactly as the app does.
    @discardableResult
    private func file(_ line: [String], into core: Core) throws -> UInt64 {
        core.endSession()
        let game = try Game(rules: core)
        try game.replay(line)
        if game.evaluation.claimAvailable {
            game.claimDraw()
        } else {
            try game.file()
        }
        core.endSession()
        return try #require(game.filedRecordID)
    }

    private func library(over core: Core) -> HistoryLibrary {
        let library = HistoryLibrary(store: core.history)
        library.load()
        return library
    }

    // MARK: - Export

    @Test("An exported record is the archive's own document")
    func exportProducesTheArchive() throws {
        let core = try TestCores.fresh()
        let record = try file(GameTests.mateLine, into: core)

        let bytes = try core.history.export(record)
        let text = try #require(String(data: bytes, encoding: .utf8))

        // Not a re-derivation of the format — the core owns every byte of it —
        // but the four claims the app depends on being true of what it hands
        // to another application.
        #expect(text.hasPrefix("{\"archive_format\":\"minixiangqi-game\""),
                "the in-band type check is the first thing a reader meets")
        #expect(text.contains("\"archive_version\":1"))
        #expect(text.contains("\"outcome\":\"red-wins\""),
                "an exported file is a completed game")
        #expect(!text.contains("\n"), "one line, which is what canonical means here")
    }

    @Test("Exporting twice changes the export event and nothing about the game")
    func exportRestampsOnlyTheOrigin() throws {
        let core = try TestCores.fresh()
        let record = try file(GameTests.mateLine, into: core)

        let first = try #require(String(data: try core.history.export(record), encoding: .utf8))
        let second = try #require(String(data: try core.history.export(record), encoding: .utf8))

        // `content` runs to `,"game_id":` in the canonical order, which is what
        // the content hash is taken over and what must never move.
        let content = { (document: String) in
            document.components(separatedBy: ",\"game_id\":").first
        }
        #expect(content(first) == content(second),
                "the game is the same game in both files")
    }

    @Test("The active game is not a History record, and is not exportable")
    func theActiveGameCannotBeExported() throws {
        let core = try TestCores.fresh()
        let game = try Game(rules: core)
        try game.replay(["b1b3"])

        #expect(throws: CoreError.self) {
            // Record ids start at 1, and the only row this store has is the
            // active game's.
            _ = try core.history.export(1)
        }
        core.endSession()
    }

    // MARK: - Import

    @Test("An exported game imports into another library as a new record")
    func exportImportsElsewhere() throws {
        let source = try TestCores.fresh()
        let record = try file(GameTests.mateLine, into: source)
        let file = try source.history.export(record)

        let destination = try TestCores.fresh()
        let imported = try destination.history.importGame(file)

        #expect(imported.outcome == .created)
        #expect(imported.record.outcome == .redWins)
        #expect(imported.record.reason == .checkmate)
        #expect(imported.record.moveCount == GameTests.mateLine.count)
        #expect(imported.record.imported, "provenance is the library's word for it")
        #expect(!imported.record.pinned)

        // And it is where the list reads from, not merely where the call said.
        let library = library(over: destination)
        #expect(library.records.map(\.id) == [imported.record.id])
        #expect(library.records[0].imported)
    }

    @Test("The same file twice returns the record the library already has")
    func aDuplicateReturnsTheExistingRecord() throws {
        let core = try TestCores.fresh()
        let record = try file(GameTests.mateLine, into: core)
        let exported = try core.history.export(record)

        // Importing this library's own export: the same game, in different
        // bytes, because an export stamps the event that produced the file.
        let first = try core.history.importGame(exported)
        #expect(first.outcome == .existing, "the game was already here")
        #expect(first.record.id == record)

        let again = try core.history.importGame(exported)
        #expect(again.outcome == .existing)
        #expect(again.record.id == record)
        #expect(library(over: core).records.count == 1,
                "and no second copy of it appeared")
    }

    @Test("A refused file is refused with the status the screen routes by")
    func aRefusalCarriesItsStatus() throws {
        let core = try TestCores.fresh()

        // Not a game file at all. Every structural refusal is this status, and
        // it is the one the screen turns into 无法读取这个对局文件.
        let nonsense = try #require("this is not an archive".data(using: .utf8))
        #expect(status(of: { try core.history.importGame(nonsense) })
                == MxqStatus(MXQ_ERR_ARCHIVE_MALFORMED))

        // A file from a version this build does not read — the one refusal the
        // data contract requires to be distinguishable, and never to be
        // presented as corruption.
        let record = try file(GameTests.mateLine, into: core)
        let exported = try #require(String(data: try core.history.export(record),
                                           encoding: .utf8))
        let newer = exported.replacingOccurrences(of: "\"archive_version\":1",
                                                  with: "\"archive_version\":2")
        let bytes = try #require(newer.data(using: .utf8))
        #expect(status(of: { try core.history.importGame(bytes) })
                == MxqStatus(MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION))

        #expect(library(over: core).records.count == 1,
                "and neither refusal changed the library")
    }

    /// The status a refusal carried, or `MXQ_OK` if there was no refusal —
    /// which is itself a failing expectation wherever this is used.
    private func status(of work: () throws -> ImportedGame) -> MxqStatus {
        do {
            _ = try work()
            return MxqStatus(MXQ_OK)
        } catch let error as CoreError {
            return error.status
        } catch {
            return MxqStatus(MXQ_ERR_INTERNAL_INVARIANT)
        }
    }

    @Test("An import creates a History record and never the active game")
    func importLeavesTheActiveGameAlone() throws {
        let source = try TestCores.fresh()
        let record = try file(GameTests.mateLine, into: source)
        let exported = try source.history.export(record)

        let core = try TestCores.fresh()
        let playing = try Game(rules: core)
        try playing.replay(["b1b3", "b7b5"])
        #expect(try core.activeGameExists())

        let imported = try core.history.importGame(exported)

        #expect(imported.outcome == .created)
        #expect(try core.activeGameExists(), "the game being played is still active")
        #expect(playing.moves.count == 2, "and still holds its own line")
        #expect(library(over: core).records.count == 1,
                "the import is a History record, and the active game is not one")
        core.endSession()
    }

    // MARK: - The file the share sheet hands on

    @Test("The exported file is named for the game rather than for the export")
    func theFilenameComesFromTheGame() throws {
        let core = try TestCores.fresh()
        try file(GameTests.mateLine, into: core)
        let summary = try #require(library(over: core).records.first)

        let name = GameFile(record: summary, store: core.history).name

        #expect(name.hasSuffix(".mxq"))
        #expect(name.hasPrefix("minixiangqi-"))
        // The same record names the same file every time — which is the whole
        // reason the name is built from the game's end and not from the export
        // event, since that one is regenerated on every export.
        #expect(name == GameFile(record: summary, store: core.history).name)

        // Fixed-width, machine-ordered, and independent of the reader's locale.
        let stamp = name.dropFirst("minixiangqi-".count).dropLast(".mxq".count)
        #expect(stamp.count == 15, "yyyy-MM-dd-HHmm")
        #expect(stamp.allSatisfy { $0.isNumber || $0 == "-" })
    }

    @Test("The game type is the accepted one, declared and conforming to JSON")
    func theTypeIsTheAcceptedOne() throws {
        let type = UTType.miniXiangqiGame
        #expect(type.identifier == "com.ppppvz.minixiangqi.game")
        #expect(type.conforms(to: .json), "the archive is one canonical-JSON document")
        #expect(type.preferredFilenameExtension == "mxq")
        #expect(type.isDeclared, "the app's Info.plist is what registers it")
    }
}
