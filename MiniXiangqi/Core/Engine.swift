// The Swift veneer over the core's search facade, and the platform memory
// probe the Hash budget is computed from. The core does the budget arithmetic;
// this file only decides what the available and physical figures are here.
//
// `mxq_engine_prepare` and `mxq_engine_teardown` block (a prepare allocates the
// transposition table and loads the network), so they run on a serial dispatch
// queue of this file's own rather than on the cooperative pool.

import Foundation
import MiniXiangqiCore

#if canImport(Darwin)
import Darwin
#endif

// MARK: - The probe

/// The figures the Hash budget is computed from. Probed fresh at every
/// calculation: the retry after an insufficient-memory notice has to see the
/// memory the user just freed.
nonisolated struct EngineBudget: Sendable, Equatable {
    var activeProcessorCount: Int
    var availableBytes: UInt64
    var physicalBytes: UInt64

    var raw: MxqEngineBudget {
        var budget = MxqEngineBudget()
        budget.struct_size = UInt32(MemoryLayout<MxqEngineBudget>.size)
        budget.active_processor_count = UInt32(activeProcessorCount)
        budget.available_bytes = availableBytes
        budget.physical_bytes = physicalBytes
        return budget
    }

    /// A fresh reading of this machine. Never cached.
    static func probe() -> EngineBudget {
        EngineBudget(activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
                     availableBytes: availableMemory(),
                     physicalBytes: physicalMemory())
    }

    private static func physicalMemory() -> UInt64 {
        var bytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &bytes, &size, nil, 0) == 0 else {
            // Foundation's answer, so a probe never reports zero physical
            // memory and fails every game for a reason the user cannot act on.
            return ProcessInfo.processInfo.physicalMemory
        }
        return bytes
    }

    #if os(macOS) || targetEnvironment(simulator)
    /// macOS has no per-process memory limit, and in a Simulator process
    /// `os_proc_available_memory` answers zero, so the probe takes the
    /// system's free, inactive and purgeable pages: what the kernel can hand
    /// to a process that asks for gigabytes.
    private static func availableMemory() -> UInt64 {
        // `mach_host_self` hands out a send right per call, and the probe sits
        // on a retry loop the user drives, so each one is deallocated.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        // A refused probe reports nothing available, which becomes the
        // insufficient-memory notice: the conservative direction, and one the
        // user can act on.
        guard result == KERN_SUCCESS else { return 0 }
        let pages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.purgeable_count)
        // Asked of the host rather than read from `vm_kernel_page_size`, a
        // global a nonisolated function may not touch.
        var pageSize = vm_size_t(0)
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return 0 }
        return pages * UInt64(pageSize)
    }
    #else
    /// The process's own remaining limit, which is what bounds an allocation
    /// on iOS.
    private static func availableMemory() -> UInt64 {
        UInt64(os_proc_available_memory())
    }
    #endif
}

/// The plan a preparation applied, for the log.
nonisolated struct EnginePlan: Sendable, Equatable {
    var threads: Int
    var hashMiB: Int
    var sufficient: Bool
    var reserveBytes: UInt64
    var usableBytes: UInt64
    var budgetBytes: UInt64

    init(threads: Int, hashMiB: Int, sufficient: Bool, reserveBytes: UInt64,
         usableBytes: UInt64, budgetBytes: UInt64) {
        self.threads = threads
        self.hashMiB = hashMiB
        self.sufficient = sufficient
        self.reserveBytes = reserveBytes
        self.usableBytes = usableBytes
        self.budgetBytes = budgetBytes
    }

    init(_ plan: MxqEnginePlan) {
        threads = Int(plan.threads)
        hashMiB = Int(plan.hash_mib)
        sufficient = plan.sufficient != 0
        reserveBytes = plan.reserve_bytes
        usableBytes = plan.usable_bytes
        budgetBytes = plan.budget_bytes
    }
}

nonisolated extension CoreError {
    /// Whether this is the failure the 无法启动 AI 对手 notice is about: a
    /// budget under the minimum, or an allocation that failed at one that was
    /// not. Closing other apps fixes both and none of the engine's other
    /// failures (a missing network, a variant that would not load, a fault).
    var isInsufficientMemory: Bool {
        status == MxqStatus(MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY)
            || status == MxqStatus(MXQ_ERR_ENGINE_HASH_ALLOCATION_FAILED)
    }
}

nonisolated enum EngineState: Sendable {
    case uninitialized, ready, faulted

    init(_ state: MxqEngineState) {
        switch state {
        case MxqEngineState(MXQ_ENGINE_STATE_READY): self = .ready
        case MxqEngineState(MXQ_ENGINE_STATE_FAULTED): self = .faulted
        default: self = .uninitialized
        }
    }
}

// MARK: - A search's answer

/// The rejection ladder's rungs, in the order the core applies them.
nonisolated enum SearchOutcome: Sendable {
    case move, cancelled, malformed, illegal, failed

    init(_ outcome: MxqSearchOutcome) {
        switch outcome {
        case MxqSearchOutcome(MXQ_SEARCH_MOVE): self = .move
        case MxqSearchOutcome(MXQ_SEARCH_CANCELLED): self = .cancelled
        case MxqSearchOutcome(MXQ_SEARCH_MALFORMED): self = .malformed
        case MxqSearchOutcome(MXQ_SEARCH_ILLEGAL): self = .illegal
        default: self = .failed
        }
    }
}

/// The line a search is asked about: a game, the position it began from, and
/// the moves since. The core keeps no game, so this is the whole question.
nonisolated struct SearchLine: Sendable, Equatable {
    var game: GameKind
    var start: String
    var moves: [String]
}

/// One search's answer, copied out of core storage inside the callback and
/// carried to the main actor. Nothing here commits anything; whether the line
/// it answers is still the game's is the asker's question.
nonisolated struct SearchResult: Sendable {
    var outcome: SearchOutcome
    var ticket: UInt64
    var move: String
    var status: MxqStatus
    var nodes: UInt64
    var depth: Int
    var elapsedMilliseconds: Int
    var profileID: String

    init(_ result: MxqSearchResult) {
        outcome = SearchOutcome(result.outcome)
        ticket = result.ticket
        move = string(of: result.move.text, capacity: MXQ_MOVE_TEXT_CAP)
        status = result.status
        nodes = result.nodes
        depth = Int(result.depth)
        elapsedMilliseconds = Int(result.elapsed_ms)
        profileID = string(of: result.profile_id, capacity: MXQ_PROFILE_ID_CAP)
    }
}

// MARK: - The seam the opponent speaks through

/// Everything the human-versus-AI reply loop asks of the engine. A protocol
/// because a working engine will not fail on request, and a test has to reach
/// a preparation that fails and a search that comes back cancelled or stale.
/// The app only ever runs `Core`.
@MainActor
protocol AIEngine: AnyObject {
    /// A fresh probe of this machine. Called at every attempt, never cached.
    func memoryBudget() -> EngineBudget

    /// Whether the engine is ready to search this game right now.
    func engineIsReady(for game: GameKind) -> Bool

    /// Threads, Hash, and this game's pinned variant and network, applied away
    /// from this thread; the answer comes back here.
    ///
    /// A completion rather than `async`, like the animator and the clock: a
    /// test stand-in answers on the spot, with no suspension point in which
    /// the process-wide core could pass to another test mid-attempt.
    func prepareEngine(for game: GameKind, _ budget: EngineBudget,
                       completion: @escaping @MainActor (Result<EnginePlan, CoreError>) -> Void)

    /// Releases the transposition table and returns the engine to the
    /// uninitialized state. It must not block the asking thread (the
    /// platform's lifecycle-event thread is one), so it answers through `next`.
    func teardownEngine(then next: (@MainActor () -> Void)?)

    /// Starts the AI's search of the position at the end of `line` and returns
    /// its ticket. The completion runs on the main actor, the result having
    /// been copied out of core storage on the engine thread.
    func startSearch(_ line: SearchLine, movetimeMilliseconds: UInt32,
                     completion: @escaping @MainActor (SearchResult) -> Void) throws -> UInt64

    /// Starts a hint's search. To the core it is the same search; the seam
    /// keeps them apart so a test can drive the reply loop and the hint each
    /// on its own.
    func startHintSearch(_ line: SearchLine, movetimeMilliseconds: UInt32,
                         completion: @escaping @MainActor (SearchResult) -> Void) throws -> UInt64

    /// Cancels one search. Its completion still arrives, carrying `cancelled`.
    func cancelSearch(_ ticket: UInt64)

    /// Cancels every outstanding search, on the suspension path.
    /// `mxq_core_cancel_all` blocks until the engine quiesces and the caller's
    /// thread must not be blocked, so it is queued where the teardown that
    /// follows it is queued: the serial queue keeps cancel-before-release.
    func cancelAllSearches()
}

// MARK: - The core's implementation of it

extension Core: AIEngine {

    func memoryBudget() -> EngineBudget { .probe() }

    func engineIsReady(for game: GameKind) -> Bool {
        guard let query = try? engineQuery(), query.state == .ready,
              let expectedProfileID = try? engineProfileID(for: game) else {
            return false
        }
        return query.profileID == expectedProfileID
    }

    func engineQuery() throws -> (state: EngineState, profileID: String) {
        var state = MxqEngineState(MXQ_ENGINE_STATE_UNINITIALIZED)
        var buffer = [CChar](repeating: 0, count: Int(MXQ_PROFILE_ID_CAP))
        var length = 0
        var err = freshError()
        try check(mxq_engine_query(handle, &state, &buffer, buffer.count, &length, &err),
                  err)
        return (EngineState(state),
                String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)),
                       as: UTF8.self))
    }

    /// The core's identifier for one game's build profile, exactly what
    /// `engineQuery()` reports once that game is prepared. Never composed here:
    /// the core has more than one engine and only it knows which plays which
    /// game.
    func engineProfileID(for game: GameKind) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MXQ_PROFILE_ID_CAP))
        var length = 0
        var err = freshError()
        try check(mxq_engine_profile_id(game.raw, &buffer, buffer.count, &length, &err),
                  err)
        return String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)),
                      as: UTF8.self)
    }

    /// Whether any engine in this build plays this game. A game none plays
    /// (Jieqi) has no profile identifier, and its refusal is permanent. Static
    /// because it is a build fact, asked before any game exists.
    nonisolated static func isPlayedByAnEngine(_ game: GameKind) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(MXQ_PROFILE_ID_CAP))
        var length = 0
        return mxq_engine_profile_id(game.raw, &buffer, buffer.count, &length, nil)
            == MXQ_OK
    }

    func prepareEngine(for game: GameKind, _ budget: EngineBudget,
                       completion: @escaping @MainActor (Result<EnginePlan, CoreError>) -> Void) {
        EngineFacade(handle: handle).prepare(for: game, budget) { result in
            Task { @MainActor in completion(result) }
        }
    }

    func teardownEngine(then next: (@MainActor () -> Void)?) {
        EngineFacade(handle: handle).teardown {
            guard let next else { return }
            Task { @MainActor in next() }
        }
    }

    func startSearch(_ line: SearchLine, movetimeMilliseconds: UInt32,
                     completion: @escaping @MainActor (SearchResult) -> Void) throws -> UInt64 {
        let delivery = Unmanaged.passRetained(SearchDelivery(completion)).toOpaque()
        var ticket: UInt64 = 0
        var err = freshError()
        let status = withCStrings(line.moves) { texts in
            mxq_search_start(handle, line.game.raw, line.start, texts, line.moves.count,
                             movetimeMilliseconds, mxqSearchTrampoline, delivery,
                             &ticket, &err)
        }
        guard status == MXQ_OK else {
            // No callback will fire for a search that never started, so the
            // box is this side's to release.
            Unmanaged<SearchDelivery>.fromOpaque(delivery).release()
            try check(status, err)
            return 0
        }
        return ticket
    }

    func startHintSearch(_ line: SearchLine, movetimeMilliseconds: UInt32,
                         completion: @escaping @MainActor (SearchResult) -> Void) throws -> UInt64 {
        try startSearch(line, movetimeMilliseconds: movetimeMilliseconds, completion: completion)
    }

    func cancelSearch(_ ticket: UInt64) {
        mxq_search_cancel(handle, ticket, nil)
    }

    func cancelAllSearches() {
        EngineFacade(handle: handle).cancelAll()
    }

    /// Drains the engine queue before shutdown, so nothing this app enqueued is
    /// still inside the core when it stops being live. It blocks, which is
    /// fine here: shutdown already joins the engine thread, and the wait is
    /// bounded by the one prepare or teardown in flight. The suspension path
    /// never comes here.
    func quiesceEngineWork() {
        EngineFacade(handle: handle).quiesce()
    }
}

/// File-scope, nonisolated and non-capturing, so converting it to a C function
/// pointer carries no actor. A closure literal at the call site would inherit
/// the main-actor default and trap when the engine thread calls it.
private nonisolated func mxqSearchTrampoline(_ result: UnsafePointer<MxqSearchResult>?,
                                             _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    // Consumes the retain `mxq_search_start` was handed. Exactly one callback
    // fires per started search (a cancelled one still answers), so this is the
    // one place the box is released. Blocking here would deadlock the thread
    // the search runs on.
    let box = Unmanaged<SearchDelivery>.fromOpaque(userData).takeRetainedValue()
    guard let result else { return }
    box.deliver(SearchResult(result.pointee))
}

/// The boxed completion a C callback carries as `user_data`. `@unchecked
/// Sendable` because it crosses to the engine thread and back: it holds one
/// immutable closure and is read exactly once, by the callback that consumes
/// its retain.
private nonisolated final class SearchDelivery: @unchecked Sendable {
    private let completion: @MainActor (SearchResult) -> Void

    init(_ completion: @escaping @MainActor (SearchResult) -> Void) {
        self.completion = completion
    }

    /// Called on the engine thread. Scheduling a task does not block, and
    /// nothing here touches the core.
    func deliver(_ result: SearchResult) {
        let completion = completion
        Task { @MainActor in completion(result) }
    }
}

/// `mxq_engine_prepare` and `mxq_engine_teardown` over the core handle, off
/// every actor. The queue is serial because these calls are, and a dispatch
/// queue rather than the cooperative pool because they block for as long as
/// allocating gigabytes takes.
///
/// It must be drained before the core shuts down: the core asserts on a
/// handle that is no longer the live instance. `quiesce()` is that drain.
private nonisolated struct EngineFacade: @unchecked Sendable {
    let handle: OpaquePointer

    private static let queue = DispatchQueue(label: "com.chentianren.MiniXiangqi.engine",
                                             qos: .userInitiated)

    func prepare(for game: GameKind, _ budget: EngineBudget,
                 completion: @escaping @Sendable (Result<EnginePlan, CoreError>) -> Void) {
        Self.queue.async {
            var raw = budget.raw
            var plan = MxqEnginePlan()
            plan.struct_size = UInt32(MemoryLayout<MxqEnginePlan>.size)
            var err = freshError()
            let status = mxq_engine_prepare(handle, game.raw, &raw, &plan, &err)
            guard status == MXQ_OK else {
                completion(.failure(CoreError(
                    status: status,
                    detail: string(of: err.detail, capacity: MXQ_DETAIL_CAP))))
                return
            }
            completion(.success(EnginePlan(plan)))
        }
    }

    /// Reports no error: an engine never prepared is already down, and a busy
    /// one is an ordering bug the cancel-then-release order prevents. Queued
    /// because it must not block the asking thread.
    func teardown(_ completion: @escaping @Sendable () -> Void) {
        Self.queue.async {
            mxq_engine_teardown(handle, nil)
            completion()
        }
    }

    /// Queued where the teardown that follows it runs, so cancel-then-release
    /// is the queue's serialisation.
    func cancelAll() {
        Self.queue.async {
            mxq_core_cancel_all(handle, nil)
        }
    }

    /// Waits for what is already on the queue, and nothing else: a barrier, not
    /// a cancellation, so the core is not shut down under a prepare or a
    /// teardown already inside it.
    func quiesce() {
        Self.queue.sync { }
    }
}
