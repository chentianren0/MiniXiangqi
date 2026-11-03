// The real core over scratch stores, one at a time: the core is a process-wide
// singleton, so opening the next one shuts down the last, and `.retiringItsCores`
// shuts each down as its test ends. A core still running at process exit
// aborts the host after the run has reported green.

import Foundation
import MiniXiangqiCore
import Observation
import Testing
@testable import MiniXiangqi

@MainActor
enum TestCores {
    private static var current: (core: Core, directory: URL)?

    static func fresh() throws -> Core {
        try open(at: scratchDirectory())
    }

    static func open(at directory: URL) throws -> Core {
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

    static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mxq-test-store-\(UUID().uuidString)",
                                    isDirectory: true)
    }

    static func retire(keeping directory: URL? = nil) {
        guard let current else { return }
        current.core.shutdown()
        if current.directory != directory {
            try? FileManager.default.removeItem(at: current.directory)
        }
        self.current = nil
    }

    static func retire(_ opened: OpenedCores) {
        guard let core = opened.core, current?.core === core else { return }
        retire()
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

@MainActor
func openGame(on core: Core) throws -> Game {
    if !core.hasSession, try !core.resumeActive() {
        try core.create(.freePlay(game: .miniXiangqi))
    }
    return try Game(core: core)
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

@MainActor
func searchResult(_ outcome: SearchOutcome, move: String, game: Game,
                  ticket: UInt64 = 1, revision: UInt64? = nil,
                  identity: String? = nil) -> SearchResult {
    var raw = MxqSearchResult()
    raw.struct_size = UInt32(MemoryLayout<MxqSearchResult>.size)
    raw.outcome = switch outcome {
    case .move: MxqSearchOutcome(MXQ_SEARCH_MOVE)
    case .cancelled: MxqSearchOutcome(MXQ_SEARCH_CANCELLED)
    case .stale: MxqSearchOutcome(MXQ_SEARCH_STALE)
    case .malformed: MxqSearchOutcome(MXQ_SEARCH_MALFORMED)
    case .illegal: MxqSearchOutcome(MXQ_SEARCH_ILLEGAL)
    case .failed: MxqSearchOutcome(MXQ_SEARCH_FAILED)
    }
    raw.ticket = ticket
    raw.position_revision = revision ?? game.evaluation.positionRevision
    withUnsafeMutableBytes(of: &raw.move.text) { buffer in
        for (index, byte) in move.utf8.enumerated() { buffer[index] = byte }
    }
    withUnsafeMutableBytes(of: &raw.game_id) { buffer in
        for (index, byte) in (identity ?? game.identity).utf8.enumerated() {
            buffer[index] = byte
        }
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

// MARK: - The nearby driver, faked

@MainActor
@Observable
final class FakeDriver: NearbyDriving {
    struct Proposal: Equatable {
        var peer: PeerDeviceID
        var connection: ConnectionID
        var rulesID: String
        var proposerMoves: Mover
    }

    struct Answer: Equatable {
        var session: String
        var accepting: Bool
    }

    enum Intent: Equatable {
        case claim
        case offerDraw
        case acceptDraw
        case requestUndo(keep: Int)
        case acceptUndo
    }

    var sessions: [BoardGameSession] = []
    var declines: [NearbyDecline] = []
    var ownMoveRefusals = 0
    var refuses: BoardGameRefusal?
    var mints = "S"
    var claimStandsAnswer = false

    private(set) var proposals: [Proposal] = []
    private(set) var answers: [Answer] = []
    private(set) var played: [String] = []
    private(set) var resigned: [String] = []
    private(set) var intents: [Intent] = []
    private(set) var claimsAsked: [String] = []

    func propose(to peer: PeerDeviceID, on connection: ConnectionID, rulesID: String,
                 proposerMoves: Mover) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        proposals.append(Proposal(peer: peer, connection: connection, rulesID: rulesID,
                                  proposerMoves: proposerMoves))
        var proposed = BoardGameSession(id: mints, peer: peer, rulesID: rulesID,
                                        rulesVersion: "1", proposerMoves: proposerMoves,
                                        proposer: .local)
        proposed.connection = connection
        sessions.append(proposed)
    }

    func answer(_ session: String, accepting: Bool) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        answers.append(Answer(session: session, accepting: accepting))
    }

    func play(_ text: String, in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        played.append(text)
    }

    func resign(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        resigned.append(session)
    }

    func claim(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.claim)
    }

    func offerDraw(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.offerDraw)
    }

    func acceptDraw(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.acceptDraw)
    }

    func requestUndo(keeping keep: Int, in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.requestUndo(keep: keep))
    }

    func acceptUndo(in session: String) throws(BoardGameRefusal) {
        if let refuses { throw refuses }
        intents.append(.acceptUndo)
    }

    func claimStands(in session: BoardGameSession) -> Bool {
        claimsAsked.append(session.id)
        return claimStandsAnswer
    }

    var stored: BoardGameSession?
    private(set) var resumedStored = 0
    private(set) var abandoned = 0

    func resumeStoredGame() -> String? {
        resumedStored += 1
        guard let stored else { return nil }
        sessions.append(stored)
        return stored.id
    }

    func abandonStoredGame() {
        abandoned += 1
        sessions.removeAll { $0.state != .proposed }
        stored = nil
    }
}

// MARK: - 保存并继续, held in flight

/// Holds PlayState's archive step open, so a test decides when it answers.
@MainActor
final class HeldArchive {
    private(set) var requests = 0
    private var parked: (@MainActor (Result<UInt64, CoreError>) -> Void)?

    init(holding state: PlayState) {
        state.archiveActiveGame = { [unowned self] completion in
            requests += 1
            parked = completion
        }
    }

    func answer(_ result: Result<UInt64, CoreError>) {
        let completion = parked
        parked = nil
        completion?(result)
    }
}
