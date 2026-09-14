// The library, as the History screen reads it.
//
// docs/interaction-design.md, "History library": pinned records first, newest
// within each group. That order is a core guarantee — `mxq_store_history_page`
// returns it and frontends never re-sort — so this type holds the records in
// exactly the order they arrived and splits them into the two accepted groups
// by taking the pinned prefix. There is no comparator here, deliberately.
//
// The store calls run synchronously, on the main actor, under the same
// documented exception in docs/core-interface.md's threading contract that the
// active game's commits run under: a History read commits nothing and does not
// fsync, so it is strictly cheaper than the ~2 ms per-move commit the owner's
// proportionality ruling already accepted there. `HistoryStore` stays a
// `Sendable` value over the core handle alone, so the off-main restructure
// remains available in reserve rather than having to be invented later. Import
// is the one call here that the exception does not cover and that therefore
// already runs off it.

import Foundation
import MiniXiangqiCore
import Observation

@Observable
final class HistoryLibrary {
    /// The surface this library reads through, and the one 共享 exports
    /// through: the file a row hands out and the list that row is in are the
    /// same library's, and there is no second handle for either to drift from.
    let store: HistoryStore

    /// The records, in the core's order. Never sorted here.
    private(set) var records: [RecordSummary] = []

    /// Whether the first read has come back. The empty state is a claim about
    /// the library, and it may not be made before the library has answered.
    private(set) var loaded = false

    /// The library revision the records were read at — the monotonic counter
    /// every committed store mutation bumps. Coming back to the screen compares
    /// it rather than re-reading blind; the interface offers no notification
    /// and this cheap check is what it offers instead.
    private var revision: UInt64 = 0

    /// The last read the store refused. A library that cannot be read is worth
    /// saying so about, rather than showing an empty list that lies.
    private(set) var failure: CoreError?

    /// The last deletion the store refused, held while its alert is up. Pinning
    /// has no counterpart: a pin that failed is a row that did not move between
    /// the two sections, which is the accepted non-blocking treatment for a
    /// reversible action.
    private(set) var deletionFailure: CoreError?

    /// What the last import had to say, other than the row appearing — and,
    /// when the row *is* what it had to say, which row.
    ///
    /// Both live here rather than on the screen because an import outlives the
    /// screen that started it: the destination is torn down and rebuilt as the
    /// player moves between destinations, and an answer held in a view would be
    /// delivered to a view that is no longer the one being looked at. An import
    /// is a fact about the library, and this is the library.
    private(set) var importAnswer: ImportAnswer?
    private(set) var importedRecord: UInt64?

    init(store: HistoryStore) {
        self.store = store
    }

    /// The two accepted groups. `pinnedRecords` is a prefix of `records`
    /// because the core already put it there.
    var pinnedRecords: ArraySlice<RecordSummary> {
        records.prefix { $0.pinned }
    }

    var unpinnedRecords: ArraySlice<RecordSummary> {
        records.drop { $0.pinned }
    }

    var isEmpty: Bool { loaded && records.isEmpty }

    // MARK: - Reading

    /// Reads the library. Called when the screen appears and after every
    /// mutation, because the answer to "what does the list look like now" is
    /// the store's rather than this type's to work out.
    func load() {
        do {
            let page = try store.all()
            records = page.records
            revision = page.revision
            failure = nil
        } catch {
            failure = CoreError(wrapping: error)
        }
        loaded = true
    }

    /// Reads again only if the library has changed since it was read. Coming
    /// back from the board after filing a game is exactly this case.
    func loadIfChanged() {
        guard loaded else { return load() }
        // A failed staleness check is not worth a screen of its own: the full
        // read below reports for both.
        if let current = try? store.count(), current.revision == revision { return }
        load()
    }

    // MARK: - Mutating

    /// Pin or unpin, then read back. A refusal is silent by design: the row not
    /// moving between the sections is the report.
    func setPinned(_ pinned: Bool, on record: RecordSummary) {
        try? store.setPinned(pinned, on: record.id)
        load()
    }

    /// Deletes permanently, then reads back. A refusal is held for the alert:
    /// this is the one irreversible action in the surface, and a delete that
    /// silently did nothing would leave the player unable to tell which.
    func delete(_ record: RecordSummary) {
        do {
            try store.delete(record.id)
        } catch {
            deletionFailure = CoreError(wrapping: error)
        }
        load()
    }

    func dismissDeletionFailure() {
        deletionFailure = nil
    }

    // MARK: - Import

    /// Files one game file, then reads back.
    ///
    /// Unlike everything else here, the call itself runs off the main actor:
    /// docs/core-interface.md keeps import outside the exception the rest of
    /// this surface runs under, because validating an untrusted file replays
    /// every ply of it against a two-second budget before anything is written.
    /// That is a change of call site and not of design — the store surface is
    /// already a `Sendable` value over the core handle.
    ///
    /// The answer is recorded here rather than returned, so that whichever
    /// screen is on show when it arrives is the one that presents it.
    func importGame(_ bytes: Data) async {
        let store = self.store
        importAnswer = nil
        do {
            let imported = try await Task.detached { try store.importGame(bytes) }.value
            load()
            switch imported.outcome {
            case .created:
                // Nothing to say: the row is the answer, and the list has it.
                importedRecord = imported.record.id
            case .existing:
                importAnswer = .duplicate(imported.record)
            }
        } catch {
            // Nothing was written on any refusal, so there is nothing to read
            // back — only something to say.
            importAnswer = ImportAnswer(refusing: CoreError(wrapping: error),
                                        retrying: bytes)
        }
    }

    /// The picker could not hand a file over at all, which from here is
    /// indistinguishable from a file that cannot be read.
    func reportUnreadableFile() {
        importAnswer = .unreadable
    }

    func dismissImportAnswer() {
        importAnswer = nil
    }

    func clearImportedRecord() {
        importedRecord = nil
    }

    // MARK: - Replay

    /// Opens one record as a detached read-only session and builds the replay
    /// over it. This is the one call here whose cost rises with the game's own
    /// length — it decodes the archive and replays every ply — and it is the
    /// one to re-measure when the exception above is re-measured on device.
    ///
    /// The motion the walk is shown with comes in from the caller: the screen
    /// hands in the Reduce Motion policy it reads from the environment, and a
    /// test hands in the seams that let it fire a landing when it chooses.
    func replay(of record: RecordSummary,
                policy: MotionPolicy = MotionPolicy(reduceMotion: false),
                animator: MotionAnimator = .live,
                feedback: Feedback = .live) -> Result<Replay, CoreError> {
        do {
            return .success(try Replay(record: record,
                                       session: ReplaySession(try store.open(record.id)),
                                       policy: policy,
                                       animator: animator,
                                       feedback: feedback))
        } catch {
            return .failure(CoreError(wrapping: error))
        }
    }
}

/// Everything an import can answer other than a row appearing.
///
/// The classes are the ones the core's own taxonomy distinguishes, and no
/// others: a file that is not ours and a file that is damaged are both
/// `MXQ_ERR_ARCHIVE_MALFORMED`, and telling them apart above the interface
/// would mean reading a diagnostic string the contract reserves for logs. The
/// picker is where the wrong-file case is actually prevented, by filtering to
/// the declared type.
///
/// The created-by-a-newer-version answer is the one the data contract requires
/// to be distinct and never to be presented as corruption, and it is. The one
/// answer that *is* about corruption is about the library's own record rather
/// than about the file, and says so.
enum ImportAnswer: Equatable {
    case duplicate(RecordSummary)
    case conflict
    case newerVersion
    case unreadable
    /// The file is fine and so is the library; the record already under this
    /// file's identity is not. Its own bytes no longer decode, or no longer
    /// hash to what the row recorded for them, so the comparison an import has
    /// to make cannot be made at all.
    case damagedRecord
    /// The file is readable and the game it records is not one these rules
    /// play: its start is a position the setup-legality predicate refuses. No
    /// bytes are held, because nothing about a retry would change the answer —
    /// the file would have to be a different game.
    case illegalStart
    /// The file was fine; the library would not take it. The bytes are held so
    /// that 重试 is a retry of the same import.
    case saveFailed(Data)

    init(refusing error: CoreError, retrying bytes: Data) {
        switch error.status {
        case MxqStatus(MXQ_ERR_STORE_IDENTITY_CONFLICT):
            self = .conflict
        case MxqStatus(MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION):
            self = .newerVersion
        case MxqStatus(MXQ_ERR_STORE_CORRUPT):
            // Not a save that failed. Nothing was being saved yet: the import
            // reached the record already holding this identity and found it
            // damaged. A retry would find it damaged again, so offering one
            // would be offering an action that cannot work — and calling this
            // a failure to save would understate what is wrong and point at
            // the wrong thing.
            self = .damagedRecord
        default:
            // Which side refused decides which sentence is true: the archive
            // domain means the file, the rules domain means the game recorded
            // in it, and anything else that reaches here means the write that
            // would have filed it.
            switch mxq_status_domain(error.status) {
            case MxqStatus(MXQ_DOMAIN_ARCHIVE): self = .unreadable
            case MxqStatus(MXQ_DOMAIN_RULES): self = .illegalStart
            default: self = .saveFailed(bytes)
            }
        }
    }

    var title: String {
        switch self {
        case .duplicate: "alert.importDuplicate.title"
        case .conflict: "alert.importConflict.title"
        case .newerVersion: "alert.importNewerVersion.title"
        case .unreadable: "alert.importUnreadable.title"
        case .damagedRecord: "alert.importDamagedRecord.title"
        case .illegalStart: "alert.importIllegalStart.title"
        case .saveFailed: "alert.importSaveFailed.title"
        }
    }

    var message: String {
        switch self {
        case .duplicate: "alert.importDuplicate.message"
        case .conflict: "alert.importConflict.message"
        case .newerVersion: "alert.importNewerVersion.message"
        case .unreadable: "alert.importUnreadable.message"
        case .damagedRecord: "alert.importDamagedRecord.message"
        case .illegalStart: "alert.importIllegalStart.message"
        case .saveFailed: "alert.importSaveFailed.message"
        }
    }
}
