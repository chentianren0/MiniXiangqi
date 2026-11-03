import Foundation
import MiniXiangqiCore
import Testing

/// The core admits one instance per process, so every suite that starts one
/// is nested here and runs one test at a time.
@Suite(.serialized) struct Core {}

let repository = URL(filePath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let assets = repository.appending(path: "core/assets")

/// A core over a scratch store and `assets`, shut down when `body` returns.
func withCore<T>(assets directory: URL = assets, _ body: (OpaquePointer) throws -> T) throws -> T {
    let store = FileManager.default.temporaryDirectory
        .appending(path: "MiniXiangqiCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: store) }

    var config = MxqCoreConfig()
    config.struct_size = UInt32(MemoryLayout<MxqCoreConfig>.size)
    config.api_major = UInt32(MXQ_API_VERSION_MAJOR)
    config.api_minor = UInt32(MXQ_API_VERSION_MINOR)
    config.api_patch = UInt32(MXQ_API_VERSION_PATCH)
    config.flags = UInt32(MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY)
    var handle: OpaquePointer?
    var err = freshError()
    let status = store.path.withCString { storePath in
        directory.path.withCString { assetPath in
            config.store_directory = storePath
            config.asset_directory = assetPath
            return mxq_core_init(&config, &handle, &err)
        }
    }
    try #require(status == MXQ_OK, "mxq_core_init: \(describe(status, err))")
    let core = try #require(handle)
    defer { mxq_core_shutdown(core, nil) }
    return try body(core)
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

func string<T>(of fixedArray: T) -> String {
    withUnsafeBytes(of: fixedArray) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
}

func describe(_ status: MxqStatus, _ err: MxqError) -> String {
    "\(String(cString: mxq_status_name(status))) \(string(of: err.detail))"
}

func statusName(_ status: MxqStatus) -> String {
    String(cString: mxq_status_name(status))
}

func startFEN(_ game: Int) -> String {
    var buffer = [CChar](repeating: 0, count: Int(MXQ_FEN_CAP))
    var length = 0
    mxq_rules_start_fen(MxqGameKind(game), &buffer, buffer.count, &length, nil)
    return String(cString: buffer)
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
    return (state, String(cString: profile))
}
