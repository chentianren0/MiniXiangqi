// A file representation rather than a data one: data is enough for a
// pasteboard but not for AirDrop, Mail or Messages. The export runs only when
// a service asks for the file.
//
// The Mac's share picker asks for the file while it holds the main thread, and
// waits up to two seconds for it, twice. So the file is made without the main
// actor: the record is read in a context of its own over the container.

import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// The Info.plist declaration must agree with this identifier and
    /// conformance exactly.
    static let miniXiangqiGame = UTType(exportedAs: "com.chentianren.minixiangqi.game",
                                        conformingTo: .json)
}

/// Holds the record's identity rather than its bytes, so presenting a share
/// control costs nothing.
nonisolated struct GameFile: Transferable, Sendable {
    var id: UUID
    var endedAt: Date
    var container: ModelContainer

    @MainActor
    init(record: GameRecord, in library: GameLibrary) {
        id = record.id
        endedAt = record.endedAt ?? record.startedAt
        container = library.container
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .miniXiangqiGame) { game in
            SentTransferredFile(try await game.write())
        }
        .suggestedFileName { $0.name }
    }

    /// Built from the game's end, not the export, so one game keeps one name.
    /// The one fixed date pattern in the app: a filename should sort
    /// chronologically and read the same on every device, hence `en_US_POSIX`.
    var name: String {
        Self.stamp.string(from: endedAt) + ".mxq"
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'minixiangqi'-yyyy-MM-dd-HHmm"
        return formatter
    }()

    /// The game file of the record `id`, read in a context of its own.
    static func data(of id: UUID, in container: ModelContainer) throws -> Data {
        var descriptor = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try ModelContext(container).fetch(descriptor).first else {
            throw LibraryRefusal.unavailable
        }
        return try record.fileData()
    }

    @concurrent private func write() async throws -> URL {
        let contents = try Self.data(of: id, in: container)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: false)
        try contents.write(to: url, options: .atomic)
        return url
    }
}
