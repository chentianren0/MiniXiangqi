import Foundation
import MiniXiangqiCore
import Testing

/// The core admits one instance per process, so every suite that starts one
/// is nested here and runs one test at a time.
@Suite(.serialized) struct Core {}

let repository = URL(filePath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let assets = repository.appending(path: "core/assets")

/// A core over `assets`, shut down when `body` returns.
func withCore<T>(assets directory: URL = assets, _ body: (OpaquePointer) throws -> T) throws -> T {
    let core = try makeCore(assets: directory)
    defer { mxq_core_shutdown(core, nil) }
    return try body(core)
}

/// A core over `assets`, which the caller shuts down.
func makeCore(assets directory: URL = assets) throws -> OpaquePointer {
    var config = MxqCoreConfig()
    config.struct_size = UInt32(MemoryLayout<MxqCoreConfig>.size)
    var handle: OpaquePointer?
    var err = freshError()
    let status = directory.path.withCString { assetPath in
        config.asset_directory = assetPath
        return mxq_core_init(&config, &handle, &err)
    }
    try #require(status == MXQ_OK, "mxq_core_init: \(describe(status, err))")
    return try #require(handle)
}

/// A scratch asset directory holding copies of `names` from the bundled assets.
func scratchAssets(_ names: [String]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "MiniXiangqiCoreTests-assets-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for name in names {
        try FileManager.default.copyItem(at: assets.appending(path: name), to: directory.appending(path: name))
    }
    return directory
}

func freshError() -> MxqError {
    var err = MxqError()
    err.struct_size = UInt32(MemoryLayout<MxqError>.size)
    return err
}

func string(_ buffer: [CChar]) -> String {
    String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

func string<T>(of fixedArray: T) -> String {
    withUnsafeBytes(of: fixedArray) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
}

func describe(_ status: MxqStatus, _ err: MxqError) -> String {
    "status \(status): \(string(of: err.detail))"
}

func statusName(_ status: MxqStatus) -> String {
    "status \(status)"
}

func startFEN(_ game: Int) -> String {
    var buffer = [CChar](repeating: 0, count: Int(MXQ_FEN_CAP))
    var length = 0
    mxq_rules_start_fen(MxqGameKind(game), &buffer, buffer.count, &length, nil)
    return string(buffer)
}

/// Where replaying `moves` from `fen` arrives, through mxq_rules_evaluate.
struct Arrival {
    var status: MxqStatus
    var detail: String
    var position = MxqPosition()
    var state = MxqGameStatus()
    var firstIllegal = 0

    var fen: String { string(of: position.fen) }
}

func evaluate(_ core: OpaquePointer, _ game: Int, _ fen: String, _ moves: [String]) -> Arrival {
    var arrival = Arrival(status: MxqStatus(MXQ_OK), detail: "")
    arrival.position.struct_size = UInt32(MemoryLayout<MxqPosition>.size)
    arrival.state.struct_size = UInt32(MemoryLayout<MxqGameStatus>.size)
    var err = freshError()
    arrival.status = withCStrings(moves) { texts in
        mxq_rules_evaluate(core, MxqGameKind(game), fen, texts, moves.count,
                           &arrival.position, &arrival.state, &arrival.firstIllegal, &err)
    }
    arrival.detail = string(of: err.detail)
    return arrival
}

/// The legal moves after `moves`, through the two-call buffer protocol.
func legalMoves(_ core: OpaquePointer, _ game: Int, _ fen: String, _ moves: [String] = []) throws -> [String] {
    var count = 0
    let probe = withCStrings(moves) { texts in
        mxq_rules_legal_moves(core, MxqGameKind(game), fen, texts, moves.count, nil, 0, &count, nil)
    }
    try #require(probe == MXQ_OK || probe == MXQ_ERR_ARG_BUFFER_TOO_SMALL, "legal moves: \(statusName(probe))")
    if count == 0 {
        return []
    }
    var buffer = [MxqMove](repeating: MxqMove(), count: count)
    for index in buffer.indices {
        buffer[index].struct_size = UInt32(MemoryLayout<MxqMove>.size)
    }
    var written = 0
    var err = freshError()
    let status = withCStrings(moves) { texts in
        mxq_rules_legal_moves(core, MxqGameKind(game), fen, texts, moves.count,
                              &buffer, buffer.count, &written, &err)
    }
    try #require(status == MXQ_OK, "legal moves: \(describe(status, err))")
    return buffer.prefix(written).map { string(of: $0.text) }
}

func withCStrings<T>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> T) -> T {
    let copies = strings.map { strdup($0) }
    defer { copies.forEach { free($0) } }
    let pointers = copies.map { UnsafePointer($0) }
    return pointers.withUnsafeBufferPointer { body(pointers.isEmpty ? nil : $0.baseAddress) }
}

/// An engine budget generous enough that the plan lands well above the minimum
/// table without asking the machine for gigabytes.
func ampleBudget() -> MxqEngineBudget {
    var budget = MxqEngineBudget()
    budget.struct_size = UInt32(MemoryLayout<MxqEngineBudget>.size)
    budget.active_processor_count = 2
    budget.available_bytes = 4 << 30
    budget.physical_bytes = 16 << 30
    return budget
}

func prepare(_ core: OpaquePointer, _ game: Int, _ budget: MxqEngineBudget = ampleBudget()) -> (MxqStatus, String) {
    var budget = budget
    var plan = MxqEnginePlan()
    plan.struct_size = UInt32(MemoryLayout<MxqEnginePlan>.size)
    var err = freshError()
    let status = mxq_engine_prepare(core, MxqGameKind(game), &budget, &plan, &err)
    return (status, string(of: err.detail))
}

func engineQuery(_ core: OpaquePointer) throws -> (state: MxqEngineState, profile: String) {
    var state = MxqEngineState(MXQ_ENGINE_STATE_UNINITIALIZED)
    var profile = [CChar](repeating: 0, count: Int(MXQ_PROFILE_ID_CAP))
    var length = 0
    var err = freshError()
    let status = mxq_engine_query(core, &state, &profile, profile.count, &length, &err)
    try #require(status == MXQ_OK, "mxq_engine_query: \(describe(status, err))")
    return (state, string(profile))
}

/// The thinking times of the app's fast and deep levels.
let fast: UInt32 = 1000
let deep: UInt32 = 5000

/// Starts a search of the position `moves` reach from `game`'s frozen start, or
/// from `start`, with `delivery` recording the callback.
func search(_ core: OpaquePointer, _ game: Int, start: String? = nil, _ moves: [String],
            movetime: UInt32 = fast, _ delivery: Delivery) throws -> UInt64 {
    let record: MxqSearchCallback = { result, context in
        guard let result, let context else { return }
        Unmanaged<Delivery>.fromOpaque(context).takeUnretainedValue().record(result.pointee)
    }
    var ticket: UInt64 = 0
    var err = freshError()
    let status = withCStrings(moves) { texts in
        mxq_search_start(core, MxqGameKind(game), start ?? startFEN(game), texts, moves.count,
                         movetime, record, Unmanaged.passUnretained(delivery).toOpaque(),
                         &ticket, &err)
    }
    try #require(status == MXQ_OK, "mxq_search_start: \(describe(status, err))")
    return ticket
}

/// Searches and waits for the answer.
func searched(_ core: OpaquePointer, _ game: Int, start: String? = nil, _ moves: [String],
              movetime: UInt32 = fast) throws -> MxqSearchResult {
    let delivery = Delivery()
    _ = try search(core, game, start: start, moves, movetime: movetime, delivery)
    return try #require(delivery.wait(), "the search answered within thirty seconds")
}

/// What a search callback delivered, written on the engine thread.
final class Delivery: @unchecked Sendable {
    private let lock = NSCondition()
    private var result: MxqSearchResult?

    var called: Bool { lock.withLock { result != nil } }
    var outcome: Int32 { lock.withLock { result?.outcome ?? -1 } }
    var status: Int32 { lock.withLock { result?.status ?? 0 } }

    func record(_ delivered: MxqSearchResult) {
        lock.withLock {
            result = delivered
            lock.broadcast()
        }
    }

    func wait(seconds: Double = 30) -> MxqSearchResult? {
        lock.withLock {
            let deadline = Date().addingTimeInterval(seconds)
            while result == nil, lock.wait(until: deadline) {}
            return result
        }
    }
}
