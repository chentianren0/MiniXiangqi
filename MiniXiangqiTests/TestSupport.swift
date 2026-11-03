// The real core, one at a time: the core is a process-wide singleton, so
// opening the next one shuts down the last, and `.retiringItsCores` shuts each
// down as its test ends. A core still running at process exit aborts the host
// after the run has reported green. Each test's library is its own, in memory
// or in a scratch file.

import Foundation
import MiniXiangqiCore
import Observation
import SwiftData
import Testing
@testable import MiniXiangqi

@MainActor
enum TestCores {
    private static var current: Core?

    static func fresh() throws -> Core {
        if OpenedCores.running == nil {
            Issue.record("""
                This test opened a core without `.retiringItsCores`. Add the \
                trait to its @Suite, so the core it opens is shut down as the \
                test ends rather than left to process exit.
                """)
        }
        retire()
        let core = try Core()
        current = core
        OpenedCores.running?.core = core
        return core
    }

    static func retire() {
        current?.shutdown()
        current = nil
    }

    static func retire(_ opened: OpenedCores) {
        guard let core = opened.core, current === core else { return }
        retire()
    }
}

@MainActor
enum TestLibraries {
    /// A fresh core and an empty library in memory.
    static func fresh() throws -> GameLibrary {
        GameLibrary(core: try TestCores.fresh(), container: try GameLibrary.container(at: nil))
    }

    /// A second empty library in memory, over the core the test already has.
    static func another(over core: Core) -> GameLibrary {
        GameLibrary(core: core, container: try! GameLibrary.container(at: nil))
    }

    /// A library file nobody keeps.
    static func scratchURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mxq-test-library-\(UUID().uuidString).store")
    }

    /// The library in `url`, as a relaunch opens it: a new container over the
    /// same file, on the core the test already has or on a fresh one.
    static func open(at url: URL, core: Core? = nil) throws -> GameLibrary {
        GameLibrary(core: try core ?? TestCores.fresh(), container: try GameLibrary.container(at: url))
    }
}

@MainActor
final class OpenedCores {
    nonisolated init() {}

    fileprivate var core: Core?

    static var running: OpenedCores? { RunningTest.opened }
}

private enum RunningTest {
    @TaskLocal static var opened: OpenedCores?
}

struct RetiringCores: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    // `@concurrent` is the protocol's own signature, which this target's
    // approachable-concurrency default would otherwise fail to witness.
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
    static var retiringItsCores: Self { Self() }
}

extension GameLibrary {
    func activeGameExists() throws -> Bool { try activeRecord() != nil }
    func historyCount() throws -> Int { try history().count }
}

@MainActor
func openGame(on library: GameLibrary) throws -> Game {
    if !library.hasSession, try !library.resumeActive() {
        try library.create(.freePlay(game: .miniXiangqi))
    }
    return try Game(library: library)
}

private struct RefusedReplayMove: Error {
    var text: String
}

extension Game {
    func replay(_ line: [String]) throws {
        for text in line {
            guard let move = Move(text: text, on: kind.board), legalMoves.contains(move) else {
                throw CoreError(wrapping: RefusedReplayMove(text: text))
            }
            play(move)
            if let failure { throw failure }
        }
    }
}

// MARK: - What a search's answer looks like

func searchResult(_ outcome: SearchOutcome, move: String, ticket: UInt64 = 1) -> SearchResult {
    var raw = MxqSearchResult()
    raw.struct_size = UInt32(MemoryLayout<MxqSearchResult>.size)
    raw.outcome = switch outcome {
    case .move: MxqSearchOutcome(MXQ_SEARCH_MOVE)
    case .cancelled: MxqSearchOutcome(MXQ_SEARCH_CANCELLED)
    case .malformed: MxqSearchOutcome(MXQ_SEARCH_MALFORMED)
    case .illegal: MxqSearchOutcome(MXQ_SEARCH_ILLEGAL)
    case .failed: MxqSearchOutcome(MXQ_SEARCH_FAILED)
    }
    raw.ticket = ticket
    withUnsafeMutableBytes(of: &raw.move.text) { buffer in
        for (index, byte) in move.utf8.enumerated() { buffer[index] = byte }
    }
    return SearchResult(raw)
}

// MARK: - The motion seams

@MainActor
final class ManualAnimator {
    private(set) var pending: [() -> Void] = []

    var animator: MotionAnimator {
        MotionAnimator { [self] _, body, completion in
            body()
            pending.append(completion)
        }
    }

    func completeNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()()
    }

    func completeAll() {
        while !pending.isEmpty { completeNext() }
    }
}

@MainActor
final class FeedbackRecorder {
    private(set) var sounds: [Feedback.Sound] = []

    var feedback: Feedback {
        Feedback { [self] sound in sounds.append(sound) }
    }
}

nonisolated func frozenStart(_ game: GameKind) -> String {
    Core.frozenStartFEN(for: game)!
}

// MARK: - 保存并继续, held in flight

/// Holds PlayState's archive step open, so a test decides when it answers.
@MainActor
final class HeldArchive {
    private(set) var requests = 0
    private var parked: (@MainActor (Result<UUID, CoreError>) -> Void)?

    init(holding state: PlayState) {
        state.archiveActiveGame = { [unowned self] completion in
            requests += 1
            parked = completion
        }
    }

    func answer(_ result: Result<UUID, CoreError>) {
        let completion = parked
        parked = nil
        completion?(result)
    }
}
