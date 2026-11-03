// Pinned first, newest within each group, is the library query's order. This
// type never sorts; it takes the pinned prefix.

import Foundation
import Observation

@Observable
final class HistoryLibrary {
    let library: GameLibrary

    private(set) var records: [GameRecord] = []

    /// The empty state may not be claimed before the library has answered.
    private(set) var loaded = false

    /// Shown rather than an empty list that would lie.
    private(set) var failure: CoreError?

    /// Held while its alert is up. A failed pin needs no alert: the row not
    /// moving is the report.
    private(set) var deletionFailure: CoreError?

    /// Held here, not on the screen, because an import outlives the screen
    /// that started it: destinations are torn down and rebuilt as the player
    /// moves between them.
    private(set) var importAnswer: ImportAnswer?
    private(set) var importedRecord: UUID?

    init(library: GameLibrary) {
        self.library = library
    }

    /// A prefix of `records` because the query already put it there.
    var pinnedRecords: ArraySlice<GameRecord> {
        records.prefix { $0.pinned }
    }

    var unpinnedRecords: ArraySlice<GameRecord> {
        records.drop { $0.pinned }
    }

    var isEmpty: Bool { loaded && records.isEmpty }

    // MARK: - Reading

    /// Called after every change too, because a game filed on Play is a row here.
    func load() {
        do {
            records = try library.history()
            failure = nil
        } catch {
            failure = CoreError(wrapping: error)
        }
        loaded = true
    }

    // MARK: - Changing

    func setPinned(_ pinned: Bool, on record: GameRecord) {
        try? library.setPinned(pinned, on: record)
        load()
    }

    /// A refusal is held for the alert: this is the one irreversible action
    /// here, and a silent no-op would leave the player unable to tell.
    func delete(_ record: GameRecord) {
        do {
            try library.delete(record)
        } catch {
            deletionFailure = CoreError(wrapping: error)
        }
        load()
    }

    func dismissDeletionFailure() {
        deletionFailure = nil
    }

    // MARK: - Import

    /// The answer is recorded rather than returned, so whichever screen is on
    /// show when it arrives presents it.
    func importGame(_ bytes: Data) {
        importAnswer = nil
        do {
            let imported = try library.importGame(bytes)
            load()
            switch imported.outcome {
            case .created:
                importedRecord = imported.record.id
            case .existing:
                importAnswer = .duplicate(imported.record)
            }
        } catch let refusal as ImportRefusal {
            importAnswer = ImportAnswer(refusal)
        } catch {
            importAnswer = .saveFailed(bytes)
        }
    }

    /// The picker could not hand a file over, which from here is the same as
    /// an unreadable file.
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

    /// The screen hands in its Reduce Motion policy; a test hands in seams
    /// that let it fire a landing when it chooses.
    func replay(of record: GameRecord,
                policy: MotionPolicy = MotionPolicy(reduceMotion: false),
                animator: MotionAnimator = .live,
                feedback: Feedback = .live) -> Result<Replay, CoreError> {
        do {
            return .success(try Replay(record: record, core: library.core,
                                       policy: policy, animator: animator,
                                       feedback: feedback))
        } catch {
            return .failure(CoreError(wrapping: error))
        }
    }
}

/// Everything an import can answer other than a row appearing. A file another
/// version wrote is never presented as a damaged file.
enum ImportAnswer: Equatable {
    case duplicate(GameRecord)
    case newerVersion
    case earlierVersion
    case unreadable
    /// Readable, but not a game these rules play. No bytes held: a retry
    /// would not change the answer.
    case illegalGame
    /// The bytes are held so that 重试 retries the same import.
    case saveFailed(Data)

    init(_ refusal: ImportRefusal) {
        switch refusal {
        case .unreadable: self = .unreadable
        case .newerVersion: self = .newerVersion
        case .earlierVersion: self = .earlierVersion
        case .illegal: self = .illegalGame
        }
    }

    var title: String {
        switch self {
        case .duplicate: "alert.importDuplicate.title"
        case .newerVersion: "alert.importNewerVersion.title"
        case .earlierVersion: "alert.importEarlierVersion.title"
        case .unreadable: "alert.importUnreadable.title"
        case .illegalGame: "alert.importIllegalGame.title"
        case .saveFailed: "alert.importSaveFailed.title"
        }
    }

    var message: String {
        switch self {
        case .duplicate: "alert.importDuplicate.message"
        case .newerVersion: "alert.importNewerVersion.message"
        case .earlierVersion: "alert.importEarlierVersion.message"
        case .unreadable: "alert.importUnreadable.message"
        case .illegalGame: "alert.importIllegalGame.message"
        case .saveFailed: "alert.importSaveFailed.message"
        }
    }
}
