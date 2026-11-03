// The library, as the History screen reads it.
//
// docs/interaction-design.md, "History library": pinned records first, newest
// within each group. That order is the library's query, so this type holds the
// records in exactly the order they arrived and splits them into the two
// accepted groups by taking the pinned prefix. There is no comparator here.

import Foundation
import Observation

@Observable
final class HistoryLibrary {
    /// The library this reads through, and the one 共享 exports from.
    let library: GameLibrary

    /// The records, in the query's order. Never sorted here.
    private(set) var records: [GameRecord] = []

    /// Whether the first read has come back. The empty state is a claim about
    /// the library, and it may not be made before the library has answered.
    private(set) var loaded = false

    /// The last read the library refused. A library that cannot be read is
    /// worth saying so about, rather than showing an empty list that lies.
    private(set) var failure: CoreError?

    /// The last deletion the library refused, held while its alert is up.
    /// Pinning has no counterpart: a pin that failed is a row that did not move
    /// between the two sections, which is the accepted non-blocking treatment
    /// for a reversible action.
    private(set) var deletionFailure: CoreError?

    /// What the last import had to say, other than the row appearing — and,
    /// when the row *is* what it had to say, which row.
    ///
    /// Both live here rather than on the screen because an import outlives the
    /// screen that started it: the destination is torn down and rebuilt as the
    /// player moves between destinations, and an answer held in a view would be
    /// delivered to a view that is no longer the one being looked at.
    private(set) var importAnswer: ImportAnswer?
    private(set) var importedRecord: UUID?

    init(library: GameLibrary) {
        self.library = library
    }

    /// The two accepted groups. `pinnedRecords` is a prefix of `records`
    /// because the query already put it there.
    var pinnedRecords: ArraySlice<GameRecord> {
        records.prefix { $0.pinned }
    }

    var unpinnedRecords: ArraySlice<GameRecord> {
        records.drop { $0.pinned }
    }

    var isEmpty: Bool { loaded && records.isEmpty }

    // MARK: - Reading

    /// Reads the library. Called when the screen appears and after every
    /// change, because a game filed on the Play destination is a row here.
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

    /// Pin or unpin, then read back. A refusal is silent by design: the row not
    /// moving between the sections is the report.
    func setPinned(_ pinned: Bool, on record: GameRecord) {
        try? library.setPinned(pinned, on: record)
        load()
    }

    /// Deletes permanently, then reads back. A refusal is held for the alert:
    /// this is the one irreversible action in the surface, and a delete that
    /// silently did nothing would leave the player unable to tell which.
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

    /// Files one game file, then reads back. The answer is recorded here rather
    /// than returned, so that whichever screen is on show when it arrives is
    /// the one that presents it.
    func importGame(_ bytes: Data) {
        importAnswer = nil
        do {
            let imported = try library.importGame(bytes)
            load()
            switch imported.outcome {
            case .created:
                // Nothing to say: the row is the answer, and the list has it.
                importedRecord = imported.record.id
            case .existing:
                importAnswer = .duplicate(imported.record)
            }
        } catch let refusal as ImportRefusal {
            importAnswer = ImportAnswer(refusal)
        } catch {
            // The file was fine; the library would not take it.
            importAnswer = .saveFailed(bytes)
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

    /// The replay of one record. The motion the walk is shown with comes in
    /// from the caller: the screen hands in the Reduce Motion policy it reads
    /// from the environment, and a test hands in the seams that let it fire a
    /// landing when it chooses.
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

/// Everything an import can answer other than a row appearing.
///
/// The created-by-a-newer-version answer is distinct and never presented as a
/// damaged file. The picker is where the wrong-file case is actually
/// prevented, by filtering to the declared type.
enum ImportAnswer: Equatable {
    case duplicate(GameRecord)
    case newerVersion
    case unreadable
    /// The file is readable and the game it records is not one these rules
    /// play. No bytes are held, because nothing about a retry would change the
    /// answer.
    case illegalGame
    /// The file was fine; the library would not take it. The bytes are held so
    /// that 重试 is a retry of the same import.
    case saveFailed(Data)

    init(_ refusal: ImportRefusal) {
        switch refusal {
        case .unreadable: self = .unreadable
        case .newerVersion: self = .newerVersion
        case .illegal: self = .illegalGame
        }
    }

    var title: String {
        switch self {
        case .duplicate: "alert.importDuplicate.title"
        case .newerVersion: "alert.importNewerVersion.title"
        case .unreadable: "alert.importUnreadable.title"
        case .illegalGame: "alert.importIllegalGame.title"
        case .saveFailed: "alert.importSaveFailed.title"
        }
    }

    var message: String {
        switch self {
        case .duplicate: "alert.importDuplicate.message"
        case .newerVersion: "alert.importNewerVersion.message"
        case .unreadable: "alert.importUnreadable.message"
        case .illegalGame: "alert.importIllegalGame.message"
        case .saveFailed: "alert.importSaveFailed.message"
        }
    }
}
