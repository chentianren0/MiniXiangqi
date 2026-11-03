// A file representation rather than a data one: data is enough for a
// pasteboard but not for AirDrop, Mail or Messages. The export runs only when
// a service asks for the file.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// docs/game-data.md and the Info.plist declaration must agree with this
    /// identifier and conformance exactly.
    static let miniXiangqiGame = UTType(exportedAs: "com.chentianren.minixiangqi.game",
                                        conformingTo: .json)
}

/// Holds the record's identity rather than its bytes, so presenting a share
/// control costs nothing.
nonisolated struct GameFile: Transferable, Sendable {
    var id: UUID
    var endedAt: Date
    var library: GameLibrary

    @MainActor
    init(record: GameRecord, in library: GameLibrary) {
        id = record.id
        endedAt = record.endedAt ?? record.startedAt
        self.library = library
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

    private func write() async throws -> URL {
        let contents = try await library.fileData(of: id)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: false)
        try contents.write(to: url, options: .atomic)
        return url
    }
}
