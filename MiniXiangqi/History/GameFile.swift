// The game file, as the rest of the system sees it: a type, a name, and a
// representation the share sheet can hand to another application.
//
// docs/game-data.md fixes all three of the type's parts — the `.mxq` extension,
// the `com.chentianren.minixiangqi.game` identifier, and that it conforms to
// `public.json`, because the archive is one canonical-JSON document and a file
// that says so stays inspectable. The declaration itself lives in the app's
// Info.plist, which is what registers it with the system; this is the Swift
// spelling of the same identifier.
//
// The transfer representation is a **file** representation deliberately. A data
// representation alone is enough for a pasteboard and not enough for AirDrop,
// Mail or Messages — the services an offline test team actually moves a game
// with — so the export writes a real file into the app's own temporary
// directory and hands that over.
//
// The export runs inside that representation's own asynchronous closure rather
// than in the button that presented the sheet. That is where it belongs twice
// over: docs/core-interface.md keeps export off the main actor, and a share
// sheet that has not been asked for a file yet has no reason to have done the
// work.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// The archive's own type. `exportedAs` because this application defines
    /// it; the identifier and its conformance are the accepted ones and the
    /// Info.plist declaration must agree with them exactly.
    static let miniXiangqiGame = UTType(exportedAs: "com.chentianren.minixiangqi.game",
                                        conformingTo: .json)
}

/// One History record on its way out of the app.
///
/// It holds the record and the store rather than the bytes, so that presenting
/// a share control costs nothing: the export happens when a service asks for
/// the file, and only then.
nonisolated struct GameFile: Transferable, Sendable {
    var record: RecordSummary
    var store: HistoryStore

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .miniXiangqiGame) { game in
            SentTransferredFile(try game.write())
        }
        .suggestedFileName { $0.name }
    }

    /// The filename, built from the game's own end rather than from the export.
    ///
    /// `origin.exported_at` is regenerated on every export, so a name built
    /// from it would give one game a different name every time it was shared.
    /// The game's end does not move.
    ///
    /// **The one place in this app that writes a date pattern, and the one
    /// place that is right to.** A displayed date belongs to the reader's
    /// locale and to their own clock setting; a filename belongs to the file,
    /// and a file that sorts chronologically in a folder and reads the same on
    /// every device is worth more than a localized one. `en_US_POSIX` is what
    /// makes that a promise rather than a coincidence.
    var name: String {
        Self.stamp.string(from: record.endedAt) + ".mxq"
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'minixiangqi'-yyyy-MM-dd-HHmm"
        return formatter
    }()

    /// Exports the record and writes it where a transfer can pick it up. The
    /// temporary directory is the app's own, so nothing here needs access to a
    /// location the user chose.
    private func write() throws -> URL {
        let bytes = try store.export(record.id)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: false)
        try bytes.write(to: url, options: .atomic)
        return url
    }
}
