// The Swift veneer over the core's search facade, and the platform memory
// probe the Hash budget is computed from.
//
// docs/engine-integration.md, "AI difficulty profiles": the frontend supplies a
// fresh available-memory value at each calculation, and the arithmetic on top of
// it belongs to the core — `mxq_engine_plan` implements it and is pure, so the
// only thing this file decides is what the two numbers are on this platform.
// On macOS they are `host_statistics64` with `HOST_VM_INFO64`, taking free,
// inactive and purgeable pages, and `sysctlbyname("hw.memsize")`; on iOS and
// iPadOS, `os_proc_available_memory()` against the same physical figure.
//
// docs/core-interface.md's threading table puts `mxq_engine_prepare` and
// `mxq_engine_teardown` on a non-UI thread, blocking, with their work marshalled
// onto the core's engine thread. They are the two calls in this app that are
// genuinely expensive — a prepare allocates the transposition table and loads
// the network — so they run on a serial dispatch queue of this file's own rather
// than on the cooperative pool, which is what the contract's "blocking calls on
// a dedicated serial executor" asks for. Everything else in the facade is
// non-blocking and stays where its caller is.

import Foundation
import MiniXiangqiCore

#if canImport(Darwin)
import Darwin
#endif

// MARK: - The probe

/// The two numbers the accepted budget arithmetic is computed from, fresh at
/// every calculation. A cached probe is exactly what the contract forbids: the
/// retry that follows an insufficient-memory notice has to see the memory the
/// user just freed.
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

    /// A fresh reading of this machine. Never cached, and never remembered
    /// between attempts.
    static func probe() -> EngineBudget {
        EngineBudget(activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
                     availableBytes: forcedAvailableBytes ?? availableMemory(),
                     physicalBytes: physicalMemory())
    }

    /// The device's physical memory. `sysctlbyname("hw.memsize")` is the
    /// accepted source on both Apple platforms.
    private static func physicalMemory() -> UInt64 {
        var bytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &bytes, &size, nil, 0) == 0 else {
            // Foundation's own answer for the same question, as the fallback
            // that keeps a probe from reporting zero physical memory and
            // failing every game for a reason the user cannot act on.
            return ProcessInfo.processInfo.physicalMemory
        }
        return bytes
    }

    #if os(macOS)
    /// macOS has no per-process memory limit to ask about, so the accepted
    /// probe is the system's available physical memory: the free, inactive and
    /// purgeable pages, which are what the kernel can hand to a process that
    /// asks for gigabytes.
    private static func availableMemory() -> UInt64 {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        // A probe the kernel refused reports nothing available, which the
        // accepted arithmetic turns into the insufficient-memory notice — the
        // conservative direction, and the one the user can act on.
        guard result == KERN_SUCCESS else { return 0 }
        let pages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.purgeable_count)
        // The page size is asked of the host rather than read from the global
        // `vm_kernel_page_size`, which Swift 6 will not let a nonisolated
        // function touch and which this call answers exactly.
        var pageSize = vm_size_t(0)
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return 0 }
        return pages * UInt64(pageSize)
    }
    #else
    /// iOS and iPadOS: the process's own remaining limit, which is the number
    /// that actually bounds an allocation there.
    private static func availableMemory() -> UInt64 {
        UInt64(os_proc_available_memory())
    }
    #endif

    /// `-mxq-available-memory <bytes>` forces the probe's available figure, so
    /// the insufficient-memory flow can be reached on a machine that has plenty
    /// of memory. Debug only: the flow is one a person will meet, and a test
    /// that cannot reach it is a flow nobody has ever seen.
    private static var forcedAvailableBytes: UInt64? {
        #if DEBUG
        MainActor.assumeIsolated {
            DebugLaunch.argument(after: "-mxq-available-memory").flatMap(UInt64.init)
        }
        #else
        nil
        #endif
    }
}

/// What the accepted arithmetic yields, reported back so a test can read every
/// boundary and a log can name the applied values.
nonisolated struct EnginePlan: Sendable, Equatable {
    var threads: Int
    var hashMiB: Int
    var sufficient: Bool
    var reserveBytes: UInt64
    var usableBytes: UInt64
    var budgetBytes: UInt64

    init(_ plan: MxqEnginePlan) {
        threads = Int(plan.threads)
        hashMiB = Int(plan.hash_mib)
        sufficient = plan.sufficient != 0
        reserveBytes = plan.reserve_bytes
        usableBytes = plan.usable_bytes
        budgetBytes = plan.budget_bytes
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
    case move, cancelled, stale, malformed, illegal, failed

    init(_ outcome: MxqSearchOutcome) {
        switch outcome {
        case MxqSearchOutcome(MXQ_SEARCH_MOVE): self = .move
        case MxqSearchOutcome(MXQ_SEARCH_CANCELLED): self = .cancelled
        case MxqSearchOutcome(MXQ_SEARCH_STALE): self = .stale
        case MxqSearchOutcome(MXQ_SEARCH_MALFORMED): self = .malformed
        case MxqSearchOutcome(MXQ_SEARCH_ILLEGAL): self = .illegal
        default: self = .failed
        }
    }
}

/// One search's inert answer, copied out of core storage inside the callback
/// and carried to the main actor. Applying the move is a separate explicit act;
/// nothing here commits anything.
nonisolated struct SearchResult: Sendable {
    var outcome: SearchOutcome
    var ticket: UInt64
    /// The identity the search started from. The frontend compares this pair
    /// against the live session before applying — the second of the two
    /// staleness comparisons the interface requires, because neither check
    /// alone covers both race directions.
    var gameID: String
    var positionRevision: UInt64
    var move: String
    var status: MxqStatus
    var nodes: UInt64
    var depth: Int
    var elapsedMilliseconds: Int
    var profileID: String

    init(_ result: MxqSearchResult) {
        outcome = SearchOutcome(result.outcome)
        ticket = result.ticket
        gameID = string(of: result.game_id, capacity: MXQ_GAME_ID_CAP)
        positionRevision = result.position_revision
        move = string(of: result.move.text, capacity: MXQ_MOVE_TEXT_CAP)
        status = result.status
        nodes = result.nodes
        depth = Int(result.depth)
        elapsedMilliseconds = Int(result.elapsed_ms)
        profileID = string(of: result.profile_id, capacity: MXQ_PROFILE_ID_CAP)
    }
}

// MARK: - The seam the opponent speaks through

/// Everything the human-versus-AI reply loop asks of the engine.
///
/// It is a protocol for the reason `Rules` is one: a working engine will not
/// produce a refusal on request, and the states the app has to survive — a
/// preparation that fails, a search that comes back cancelled or stale — are
/// exactly the ones it refuses to produce. Nothing that implements this decides
/// a rule; the only implementation the app ever runs is `Core`.
@MainActor
protocol AIEngine: AnyObject {
    /// A fresh probe of this machine. Called at every attempt, never cached.
    func memoryBudget() -> EngineBudget

    /// Whether the engine is ready to search right now.
    func engineIsReady() -> Bool

    /// Threads, Hash, the pinned variant and the network, applied. The work is
    /// blocking and is performed away from this thread; the answer comes back
    /// here.
    ///
    /// A completion rather than an `async` call, like every other seam in this
    /// app — the animator, the clock. It buys the same thing they buy: a test
    /// stand-in answers on the spot, so the states this exists to reach are
    /// reached without a suspension point, and the one process-wide core the
    /// suite shares is never handed to another test mid-attempt.
    func prepareEngine(_ budget: EngineBudget,
                       completion: @escaping @MainActor (Result<EnginePlan, CoreError>) -> Void)

    /// Releases the transposition table whole and returns the engine to the
    /// uninitialized state. It must not block the thread that asked — the
    /// platform's lifecycle-event thread is one of them — so it answers, when
    /// it is asked to, rather than returning.
    func teardownEngine(then next: (@MainActor () -> Void)?)

    /// Starts a search over the attached session and returns its ticket. The
    /// completion is delivered on the main actor, having copied the result out
    /// of core storage on the engine thread as the callback contract requires.
    func startSearch(movetimeMilliseconds: UInt32,
                     completion: @escaping @MainActor (SearchResult) -> Void) throws -> UInt64

    /// Cancels one search. Its completion still arrives, carrying `cancelled`.
    func cancelSearch(_ ticket: UInt64)

    /// Cancels every outstanding search — the platform suspension path.
    func cancelAllSearches()
}

// MARK: - The core's implementation of it

extension Core: AIEngine {

    /// The pure plan, for the boundaries a test reads without an engine.
    /// Callable before `mxq_core_init`, which is why it is static.
    nonisolated static func plan(for budget: EngineBudget) throws -> EnginePlan {
        var raw = budget.raw
        var plan = MxqEnginePlan()
        plan.struct_size = UInt32(MemoryLayout<MxqEnginePlan>.size)
        var err = freshError()
        try check(mxq_engine_plan(&raw, &plan, &err), err)
        return EnginePlan(plan)
    }

    func memoryBudget() -> EngineBudget { .probe() }

    func engineIsReady() -> Bool {
        (try? engineState()) == .ready
    }

    func engineState() throws -> EngineState {
        var state = MxqEngineState(MXQ_ENGINE_STATE_UNINITIALIZED)
        var buffer = [CChar](repeating: 0, count: Int(MXQ_PROFILE_ID_CAP))
        var length = 0
        var err = freshError()
        try check(mxq_engine_query(handle, &state, &buffer, buffer.count, &length, &err),
                  err)
        return EngineState(state)
    }

    func prepareEngine(_ budget: EngineBudget,
                       completion: @escaping @MainActor (Result<EnginePlan, CoreError>) -> Void) {
        EngineFacade(handle: handle).prepare(budget) { result in
            Task { @MainActor in completion(result) }
        }
    }

    func teardownEngine(then next: (@MainActor () -> Void)?) {
        EngineFacade(handle: handle).teardown {
            guard let next else { return }
            Task { @MainActor in next() }
        }
    }

    func startSearch(movetimeMilliseconds: UInt32,
                     completion: @escaping @MainActor (SearchResult) -> Void) throws -> UInt64 {
        let session = try attachedSession()
        var request = MxqSearchRequest()
        request.struct_size = UInt32(MemoryLayout<MxqSearchRequest>.size)
        request.movetime_ms = movetimeMilliseconds

        // The standard non-capturing trampoline: the closure is boxed, the box
        // is passed as `user_data` at +1, and the callback consumes exactly one
        // retain. The engine thread's whole job inside it is to copy the result
        // and hand it on, which is what the callback contract requires — every
        // core call but the status and blob helpers answers `REENTRANT` there,
        // and blocking would deadlock the thread the search runs on.
        let delivery = Unmanaged.passRetained(SearchDelivery(completion)).toOpaque()
        var ticket: UInt64 = 0
        var err = freshError()
        let status = mxq_search_start(handle, session, &request,
                                      mxqSearchTrampoline, delivery, &ticket, &err)
        guard status == MXQ_OK else {
            // No callback will fire for a search that never started, so the
            // box is this side's to release.
            Unmanaged<SearchDelivery>.fromOpaque(delivery).release()
            try check(status, err)
            return 0
        }
        return ticket
    }

    func cancelSearch(_ ticket: UInt64) {
        mxq_search_cancel(handle, ticket, nil)
    }

    func cancelAllSearches() {
        mxq_core_cancel_all(handle, nil)
    }
}

/// The trampoline itself: a file-scope, nonisolated, non-capturing function, so
/// that converting it to a C function pointer carries no actor with it. A
/// closure literal written at the call site inherits this file's main-actor
/// default and asserts that isolation the moment the engine thread calls it,
/// which is a trap on the one thread the callback is documented to arrive on.
private nonisolated func mxqSearchTrampoline(_ result: UnsafePointer<MxqSearchResult>?,
                                             _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    // Consumes the retain `mxq_search_start` was handed. Exactly one callback
    // fires per started search — a cancelled one still answers — so this is the
    // one place the box is released.
    let box = Unmanaged<SearchDelivery>.fromOpaque(userData).takeRetainedValue()
    guard let result else { return }
    box.deliver(SearchResult(result.pointee))
}

/// The boxed completion a C callback carries as `user_data`.
///
/// `@unchecked Sendable` because the box crosses to the engine thread and back:
/// it holds one immutable closure and is read exactly once, by the callback that
/// consumes its retain. Hopping to the main actor is what the closure does, and
/// it is what the architecture contract requires before any UI mutation.
private nonisolated final class SearchDelivery: @unchecked Sendable {
    private let completion: @MainActor (SearchResult) -> Void

    init(_ completion: @escaping @MainActor (SearchResult) -> Void) {
        self.completion = completion
    }

    /// Called on the engine thread. It copies and returns: scheduling a task is
    /// not blocking, and nothing here touches the core.
    func deliver(_ result: SearchResult) {
        let completion = completion
        Task { @MainActor in completion(result) }
    }
}

/// `mxq_engine_prepare` and `mxq_engine_teardown` over the core handle, off
/// every actor.
///
/// A `Sendable` value over the handle for the same reason `HistoryStore` is one:
/// it holds no Swift state to race on, the core marshals the work onto its own
/// engine thread, and a handle outliving its core answers
/// `MXQ_ERR_ARG_INVALID_HANDLE` rather than touching freed memory. The queue is
/// serial because the two calls are, and it is a dispatch queue rather than the
/// cooperative pool because both block for as long as allocating gigabytes takes.
private nonisolated struct EngineFacade: @unchecked Sendable {
    let handle: OpaquePointer

    private static let queue = DispatchQueue(label: "com.chentianren.MiniXiangqi.engine",
                                             qos: .userInitiated)

    func prepare(_ budget: EngineBudget,
                 completion: @escaping @Sendable (Result<EnginePlan, CoreError>) -> Void) {
        Self.queue.async {
            var raw = budget.raw
            var plan = MxqEnginePlan()
            plan.struct_size = UInt32(MemoryLayout<MxqEnginePlan>.size)
            var err = freshError()
            let status = mxq_engine_prepare(handle, &raw, &plan, &err)
            guard status == MXQ_OK else {
                completion(.failure(CoreError(
                    status: status,
                    detail: string(of: err.detail, capacity: MXQ_DETAIL_CAP))))
                return
            }
            completion(.success(EnginePlan(plan)))
        }
    }

    /// Teardown answers nothing and refuses nothing the caller can act on: an
    /// engine that was never prepared is already down, and one that is busy is
    /// the caller's own ordering bug, which the cancel-then-release order this
    /// app always uses prevents. So it reports no error — what it must not do is
    /// block the thread that asked, which is why it is queued rather than run.
    func teardown(_ completion: @escaping @Sendable () -> Void) {
        Self.queue.async {
            mxq_engine_teardown(handle, nil)
            completion()
        }
    }
}
