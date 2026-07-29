// The cores the unit suite plays on.
//
// The core is singleton-enforced — one live instance per process — and every
// session test needs a store of its own, so the suite runs its cores through
// one coordinator: asking for the next core shuts down the previous one, which
// the singleton demands anyway, and hands back the real core over a scratch
// directory nobody keeps. Nothing is mocked; a test core differs from the
// app's only in where its store lives. The host app cooperates by presenting
// nothing under a hosted unit run, so the one instance slot is always free and
// the player's own store is never opened, let alone written.
//
// Every suite here is @MainActor and every test body is synchronous, so no
// two tests ever hold cores at once and no coordination beyond the actor is
// needed.

import Foundation
@testable import MiniXiangqi

@MainActor
enum TestCores {
    private static var current: (core: Core, directory: URL)?

    /// The real core over a fresh scratch store: the state every test starts
    /// from unless it is about resuming one.
    static func fresh() throws -> Core {
        try open(at: scratchDirectory())
    }

    /// The real core over the given store — the same call `fresh()` makes,
    /// separated so a round-trip test can shut one core down and open the
    /// next over the same directory, which is exactly what quitting and
    /// relaunching the app does.
    static func open(at directory: URL) throws -> Core {
        retire(keeping: directory)
        let core = try Core(storeDirectory: directory.path)
        current = (core, directory)
        return core
    }

    /// A place for a store, not yet a store: `open(at:)` makes it one.
    static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mxq-test-store-\(UUID().uuidString)",
                                    isDirectory: true)
    }

    /// Shuts down the live test core, freeing the one instance slot. `open`
    /// calls it for the next test; the last core of a run is reclaimed by
    /// process exit, which the store's journal is designed to survive. The
    /// retired store is removed with its core — except the one a round trip
    /// is about to resume from, which is the whole point of the trip.
    static func retire(keeping directory: URL? = nil) {
        guard let current else { return }
        current.core.shutdown()
        if current.directory != directory {
            try? FileManager.default.removeItem(at: current.directory)
        }
        self.current = nil
    }
}
