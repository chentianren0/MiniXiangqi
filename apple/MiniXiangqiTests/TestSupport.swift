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
// No core outlives the test that opened it: `.retiringItsCores` shuts one down
// as its test ends, so a run reaches process exit with the slot empty. Exit is
// not a teardown — a core whose engine thread is still running when the C++
// statics under it are destroyed aborts a host that has already reported green
// — and a suite that left its last core to the exit was asking exit to do a
// job it does not have.
//
// Every suite here is @MainActor and every test body is synchronous, so no two
// tests ever hold cores at once while they run. Retirement is the one thing
// that happens outside a body, and so the one thing that has to check: a test
// retires the core it opened only while that core is still the live one, and
// does nothing at all once a later test has taken the slot.

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
        // A test that has made no promise to end its cores would leave its last
        // one standing at process exit, and the host would abort after the run
        // reported green. Said here, that is a failure with a name and a fix in
        // it; left unsaid, it is a crash dialog nobody can trace back.
        if OpenedCores.running == nil {
            Issue.record("""
                This test opened a core without `.retiringItsCores`. Add the \
                trait to its @Suite, so the core it opens is shut down as the \
                test ends rather than left to process exit.
                """)
        }
        retire(keeping: directory)
        let core = try Core(storeDirectory: directory.path)
        current = (core, directory)
        OpenedCores.running?.core = core
        return core
    }

    /// A place for a store, not yet a store: `open(at:)` makes it one.
    static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mxq-test-store-\(UUID().uuidString)",
                                    isDirectory: true)
    }

    /// Shuts down the live test core, freeing the one instance slot. `open`
    /// calls it for the next test and `.retiringItsCores` calls it for the test
    /// that opened one, so nothing is ever left for process exit to reclaim.
    /// The retired store is removed with its core — except the one a round trip
    /// is about to resume from, which is the whole point of the trip.
    static func retire(keeping directory: URL? = nil) {
        guard let current else { return }
        current.core.shutdown()
        if current.directory != directory {
            try? FileManager.default.removeItem(at: current.directory)
        }
        self.current = nil
    }

    /// The end of one test's cores. It frees the slot only if what stands in it
    /// is still what that test opened, so it is the backstop and never the
    /// authority: a test that retired its own core — as the archive tests do,
    /// because their answers arrive across a suspension they will not hold a
    /// core through — finds nothing left to do here, and a test whose core a
    /// later `open` already retired must not reach for a slot that by then
    /// belongs to whatever test is running now.
    static func retire(_ opened: OpenedCores) {
        guard let core = opened.core, current?.core === core else { return }
        retire()
    }
}

/// The core the running test has open, which is how the test that opened one
/// finds it again at the end. A box rather than a field on `TestCores` because
/// it is per-test state, and `.retiringItsCores` — which makes one per test and
/// carries it into the body as a task value — is the only thing here that knows
/// where a test begins and ends.
@MainActor
final class OpenedCores {
    nonisolated init() {}

    fileprivate var core: Core?

    /// The box belonging to the test the caller is running inside.
    static var running: OpenedCores? { RunningTest.opened }
}

/// The value `.retiringItsCores` carries into the body it wraps. A task value
/// because that is what a test body inherits from the scope around it.
private enum RunningTest {
    @TaskLocal static var opened: OpenedCores?
}

/// Ends a test's cores with the test.
///
/// The suite used to let the last core of a run stand, on the reading that
/// process exit would reclaim it. It does not: the core's engine thread is
/// still running when the C++ statics under it are destroyed, so the host
/// aborts — `std::terminate` — after every test has reported and the run has
/// printed green, and the owner is shown a crash dialog for a run that
/// succeeded. So the test that opens a core is the one that shuts it down.
struct RetiringCores: TestTrait, SuiteTrait, TestScoping {
    /// Written on a suite, it holds for every test in it. What it promises is
    /// about what a test does with a core, and every test in a suite that opens
    /// them makes the same promise.
    var isRecursive: Bool { true }

    /// Around each test and never around the suite: a suite-wide scope would
    /// end cores between suites rather than between tests, which leaves exactly
    /// the core this exists to shut down — the last one — standing longest.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    // `@concurrent` on the body is the protocol's own signature, which this
    // target's approachable-concurrency default would otherwise read as
    // nonisolated-nonsending and fail to witness.
    func provideScope(for test: Test, testCase: Test.Case?,
                      performing body: @concurrent @Sendable () async throws -> Void) async throws {
        let opened = OpenedCores()
        do {
            try await RunningTest.$opened.withValue(opened) { try await body() }
        } catch {
            await TestCores.retire(opened)
            throw error
        }
        await TestCores.retire(opened)
    }
}

extension Trait where Self == RetiringCores {
    /// Every core this suite's tests open is shut down as the test that opened
    /// it ends. Required of any suite that asks `TestCores` for one: without
    /// it, the suite's last core reaches process exit alive and aborts the
    /// host, and `TestCores.open` says so rather than let it happen quietly.
    static var retiringItsCores: Self { Self() }
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

// MARK: - Rendering a view to a PNG

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// The platform image `ImageRenderer` produces here. The two snapshot suites
/// render the same views on both platforms and write the same PNGs; only the
/// framework holding the pixels differs, and it differs in exactly two calls.
#if canImport(AppKit)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

/// One rendered view, as a platform image and as PNG bytes.
@MainActor
func renderPNG(_ view: some View, scale: CGFloat) -> (image: PlatformImage, png: Data)? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    #if canImport(AppKit)
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { return nil }
    #else
    guard let image = renderer.uiImage, let png = image.pngData() else { return nil }
    #endif
    return (image, png)
}
