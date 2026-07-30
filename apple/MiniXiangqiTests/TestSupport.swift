// The cores the unit suite plays on, and the seams it watches motion through.
//
// The animator and the feedback recorder are shared because play and replay
// show a move the same way and are therefore tested the same way: a suite that
// kept its own copy of either would be free to drift from the other's.
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
import Testing
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

/// A Free Play game, opened the way the app opens one.
///
/// Creation stopped being the first move's job when a pre-start state arrived in
/// front of it: **开始对局** creates the game, and the first move is played onto
/// a board that already exists. So a test that wants a board to play on asks for
/// one here — created where the store holds nothing, resumed where it holds an
/// active game, which is exactly the two cases the app itself has.
@MainActor
func openGame(on rules: Rules) throws -> Game {
    if !rules.hasSession, try !rules.resumeActive() {
        try rules.create(.freePlay)
    }
    return try Game(rules: rules)
}

/// Waits for something the app does off this actor to have happened.
///
/// One call needs it: the accepted archive-and-clear, which the threading
/// contract keeps off the UI thread, so it answers on a queue rather than inside
/// the call. Everything else in the suite is synchronous by design — the seams
/// answer on the spot — and this exists for the one that cannot be.
@MainActor
func settle(_ what: String, until condition: () -> Bool) async {
    for _ in 0..<300 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting for \(what)")
}

// MARK: - The motion seams

/// Runs animation bodies at once and parks their completions for the test to
/// fire in order, exactly as the live animator fires them. It is what makes
/// "during a transition" a state a test can stand in for as long as it likes,
/// on either screen that shows one.
@MainActor
final class ManualAnimator {
    private(set) var pending: [() -> Void] = []

    var animator: MotionAnimator {
        MotionAnimator { [self] _, body, completion in
            body()
            pending.append(completion)
        }
    }

    /// Fires the oldest parked completion, as time passing would.
    func completeNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()()
    }

    func completeAll() {
        while !pending.isEmpty { completeNext() }
    }
}

/// Records the two halves apart, because they are two decisions: every landing
/// is felt the same way, and each one is heard according to what it was. A test
/// that could only see one number could not tell a silenced sound from a missing
/// landing.
@MainActor
final class FeedbackRecorder {
    private(set) var events: [Feedback.Event] = []
    private(set) var sounds: [Feedback.Sound] = []

    /// The defaults the two gates read. Never the standard ones: under a hosted
    /// test bundle those are the app's own domain — the very domain the Settings
    /// switches write — and a suite that read it would fall silent the day
    /// somebody switched sound off in the app.
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// Composed the way the live feedback composes it — the app's own gates in
    /// front of both halves — so that what these tests watch being silenced or
    /// stilled is what the app silences and stills.
    var feedback: Feedback {
        Feedback.gating(by: defaults) { [self] event in
            events.append(event)
        } play: { [self] sound in
            sounds.append(sound)
        }
    }
}

/// The preferences the Settings switches write, in a scratch domain of the
/// suite's own. Cleared each time it is made, so no test inherits the state
/// another left; a preference left unnamed is left absent, which is the state of
/// a first launch and the one most tests want, since most of them are about
/// something the board does rather than about a switch.
@MainActor
enum ScratchDefaults {
    static let suiteName = "com.chentianren.MiniXiangqi.tests.preferences"

    static func make(soundEnabled: Bool? = nil,
                     hapticsEnabled: Bool? = nil,
                     deleteConfirmation: Bool? = nil) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        clear()
        if let soundEnabled { Preferences.sound.set(soundEnabled, in: defaults) }
        if let hapticsEnabled { Preferences.haptics.set(hapticsEnabled, in: defaults) }
        if let deleteConfirmation {
            Preferences.deleteConfirmation.set(deleteConfirmation, in: defaults)
        }
        return defaults
    }

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}
