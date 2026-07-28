// The Swift veneer over the shared core's C interface.
//
// Everything above this file speaks Swift; everything below it speaks `mxq_`.
// The veneer converts types and raises errors, and it decides nothing: no rule,
// no adjudication, and no affordance is re-derived here, because the whole
// point of the core is that every frontend gets the same answer from the same
// place.

import Foundation
import MiniXiangqiCore

/// A failed core call. `status` is the contract; `detail` is a short English
/// diagnostic for the log, never user-facing copy.
struct CoreError: Error, CustomStringConvertible {
    var status: MxqStatus
    var detail: String

    var description: String { "mxq status \(status): \(detail)" }
}

enum Side {
    case red, black

    init?(_ color: MxqColor) {
        switch color {
        case MxqColor(MXQ_COLOR_RED): self = .red
        case MxqColor(MXQ_COLOR_BLACK): self = .black
        default: return nil
        }
    }
}

/// The live game state. These are exactly the fixture state identifiers, and
/// exactly the core's own vocabulary: the C constants are mapped here so that
/// no view has to import the C module to ask whose turn it is.
enum GameState {
    case ongoing, claimableDraw, redWins, blackWins, draw

    init(_ state: MxqGameState) {
        switch state {
        case MxqGameState(MXQ_GAME_CLAIMABLE_DRAW): self = .claimableDraw
        case MxqGameState(MXQ_GAME_RED_WINS): self = .redWins
        case MxqGameState(MXQ_GAME_BLACK_WINS): self = .blackWins
        case MxqGameState(MXQ_GAME_DRAW): self = .draw
        // Every switch over a core vocabulary needs a default arm: a build of
        // the core newer than this app may report a state this one has not
        // heard of, and treating it as ongoing is the reading that neither
        // invents an outcome nor crashes.
        default: self = .ongoing
        }
    }

    /// Ongoing and claimable-draw can never be a committed outcome.
    var isOver: Bool { self != .ongoing && self != .claimableDraw }
}

enum EndReason {
    case none, checkmate, stalemate, threefoldRepetition
    case perpetualCheck, perpetualChase
    case mutualPerpetualCheck, mutualPerpetualChase
    case resignation, endedEarly

    init(_ reason: MxqEndReason) {
        switch reason {
        case MxqEndReason(MXQ_END_REASON_CHECKMATE): self = .checkmate
        case MxqEndReason(MXQ_END_REASON_STALEMATE): self = .stalemate
        case MxqEndReason(MXQ_END_REASON_THREEFOLD_REPETITION): self = .threefoldRepetition
        case MxqEndReason(MXQ_END_REASON_PERPETUAL_CHECK): self = .perpetualCheck
        case MxqEndReason(MXQ_END_REASON_PERPETUAL_CHASE): self = .perpetualChase
        case MxqEndReason(MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK): self = .mutualPerpetualCheck
        case MxqEndReason(MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE): self = .mutualPerpetualChase
        case MxqEndReason(MXQ_END_REASON_RESIGNATION): self = .resignation
        case MxqEndReason(MXQ_END_REASON_ENDED_EARLY): self = .endedEarly
        default: self = .none
        }
    }
}

/// A position and the game state that a history reaches, exactly as the core
/// reports them.
struct Evaluation {
    var fen: String
    var sideToMove: Side
    var inCheck: Bool
    var plyCount: Int

    var state: GameState
    var reason: EndReason
    /// The occurrence a repetition-based outcome attached at; 0 otherwise.
    var atOccurrence: Int
    var claimAvailable: Bool

    var isOver: Bool { state.isOver }
}

/// The process-wide core. Singleton because the core is singleton-enforced: a
/// second `mxq_core_init` before shutdown is an error, not a second instance.
final class Core {
    private let handle: OpaquePointer

    static let shared: Result<Core, CoreError> = Result { try Core() }
        .mapError { $0 as! CoreError }

    private init() throws {
        // The bundled variant configuration the engine loads at initialisation.
        // Its absence is a packaging failure and surfaces here rather than at
        // the first move.
        guard let assets = Bundle.main.resourcePath else {
            throw CoreError(status: MxqStatus(MXQ_ERR_ENGINE_ASSET_MISSING),
                            detail: "the bundle has no resource path")
        }
        let store = try Self.storeDirectory()

        var handle: OpaquePointer?
        var err = MxqError()
        err.struct_size = UInt32(MemoryLayout<MxqError>.size)

        try store.withCString { storePath in
            try assets.withCString { assetPath in
                var config = MxqCoreConfig()
                config.struct_size = UInt32(MemoryLayout<MxqCoreConfig>.size)
                config.api_major = UInt32(MXQ_API_VERSION_MAJOR)
                config.api_minor = UInt32(MXQ_API_VERSION_MINOR)
                config.api_patch = UInt32(MXQ_API_VERSION_PATCH)
                config.store_directory = storePath
                config.asset_directory = assetPath
                try Self.check(mxq_core_init(&config, &handle, &err), err)
            }
        }
        guard let handle else {
            throw CoreError(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                            detail: "mxq_core_init reported success without a core")
        }
        self.handle = handle
    }

    private static func storeDirectory() throws -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("MiniXiangqi", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.path
    }

    // MARK: - Rules

    /// The frozen starting FEN. A constant of the ruleset, so it is read from
    /// the core rather than written a second time here.
    static var startFEN: String {
        var buffer = [CChar](repeating: 0, count: Int(MXQ_FEN_CAP))
        var length = 0
        let status = mxq_rules_start_fen(&buffer, buffer.count, &length, nil)
        precondition(status == MXQ_OK, "the starting FEN does not fit MXQ_FEN_CAP")
        return String(cString: buffer)
    }

    func evaluate(from startFEN: String, moves: [String]) throws -> Evaluation {
        var position = MxqPosition()
        position.struct_size = UInt32(MemoryLayout<MxqPosition>.size)
        var status = MxqGameStatus()
        status.struct_size = UInt32(MemoryLayout<MxqGameStatus>.size)
        var err = MxqError()
        err.struct_size = UInt32(MemoryLayout<MxqError>.size)

        try startFEN.withCString { fen in
            try Self.withMoveList(moves) { list, count in
                try Self.check(
                    mxq_rules_evaluate(handle, fen, list, count,
                                       &position, &status, nil, &err), err)
            }
        }

        guard let side = Side(position.side_to_move) else {
            throw CoreError(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                            detail: "the core reported no side to move")
        }
        return Evaluation(
            fen: withUnsafePointer(to: position.fen) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MXQ_FEN_CAP)) {
                    String(cString: $0)
                }
            },
            sideToMove: side,
            inCheck: position.in_check != 0,
            plyCount: Int(position.ply_count),
            state: GameState(status.state),
            reason: EndReason(status.reason),
            atOccurrence: Int(status.at_occurrence),
            claimAvailable: status.claim_available != 0)
    }

    func legalMoves(from startFEN: String, moves: [String]) throws -> [String] {
        var err = MxqError()
        err.struct_size = UInt32(MemoryLayout<MxqError>.size)
        var count = 0

        // One call sized to the widest position this ruleset can reach. The
        // count comes back either way, so an undersized buffer is a bug here
        // rather than a routine outcome to loop on.
        var buffer = [MxqMove](repeating: MxqMove(), count: 128)

        try startFEN.withCString { fen in
            try Self.withMoveList(moves) { list, moveCount in
                try Self.check(
                    mxq_rules_legal_moves(handle, fen, list, moveCount,
                                          &buffer, buffer.count, &count, &err), err)
            }
        }

        return buffer.prefix(count).map { move in
            withUnsafePointer(to: move.text) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MXQ_MOVE_TEXT_CAP)) {
                    String(cString: $0)
                }
            }
        }
    }

    // MARK: - Plumbing

    /// `const char *const *` from a Swift array, valid for the call's duration.
    private static func withMoveList<R>(
        _ moves: [String],
        _ body: (UnsafePointer<UnsafePointer<CChar>?>?, Int) throws -> R
    ) rethrows -> R {
        guard !moves.isEmpty else { return try body(nil, 0) }
        var copies = moves.map { UnsafePointer<CChar>(strdup($0)) }
        defer { copies.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        return try copies.withUnsafeBufferPointer { try body($0.baseAddress, moves.count) }
    }

    private static func check(_ status: MxqStatus, _ err: MxqError) throws {
        guard status != MXQ_OK else { return }
        let detail = withUnsafePointer(to: err.detail) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MXQ_DETAIL_CAP)) {
                String(cString: $0)
            }
        }
        throw CoreError(status: status, detail: detail)
    }
}
