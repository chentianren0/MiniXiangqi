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
import Observation

@Observable
final class HistoryLibrary {
    private let store: HistoryStore

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
    /// A refusal is returned rather than held: an import has five different
    /// things it can have to say and the screen is where they are said. Nothing
    /// is written on any of them, so there is nothing to read back either.
    func importGame(_ bytes: Data) async -> Result<ImportedGame, CoreError> {
        let store = self.store
        do {
            let imported = try await Task.detached { try store.importGame(bytes) }.value
            load()
            return .success(imported)
        } catch {
            return .failure(CoreError(wrapping: error))
        }
    }

    // MARK: - Replay

    /// Opens one record as a detached read-only session and builds the replay
    /// over it. This is the one call here whose cost rises with the game's own
    /// length — it decodes the archive and replays every ply — and it is the
    /// one to re-measure when the exception above is re-measured on device.
    func replay(of record: RecordSummary) -> Result<Replay, CoreError> {
        do {
            return .success(try Replay(record: record,
                                       session: ReplaySession(try store.open(record.id))))
        } catch {
            return .failure(CoreError(wrapping: error))
        }
    }
}
