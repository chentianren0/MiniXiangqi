// The Swift veneer over the shared core's C interface.
//
// Everything above this file speaks Swift; everything below it speaks `mxq_`.
// The veneer converts types and raises errors, and it decides nothing: no rule,
// no adjudication, and no affordance is re-derived here, because the whole
// point of the core is that every frontend gets the same answer from the same
// place.
//
// Since the app moved onto sessions, the veneer also holds the one live
// session over the one active game. The core commits every accepted move
// before returning — persistence is `mxq_game_apply_move`'s postcondition, not
// a feature written here — so nothing in this file saves anything: it attaches,
// asks, and releases.

import Foundation
import MiniXiangqiCore

/// A failed core call. `status` is the contract; `detail` is a short English
/// diagnostic for the log, never user-facing copy.
struct CoreError: Error, Equatable, CustomStringConvertible {
    var status: MxqStatus
    var detail: String

    var description: String { "mxq status \(status): \(detail)" }

    /// Any error, as one the app can show. The C vocabulary stops here, so
    /// nothing above this file has to import the core's module to report a
    /// failure that did not come from it.
    init(wrapping error: Error) {
        if let error = error as? CoreError {
            self = error
        } else {
            self.init(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                      detail: String(describing: error))
        }
    }

    init(status: MxqStatus, detail: String) {
        self.status = status
        self.detail = detail
    }
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

/// A position and the game state, exactly as the core reports them — for a
/// session, the session's; before one exists, the frozen start position's.
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
    /// The core's own Undo affordance. An archived or absent session offers
    /// none, and nothing above the interface works that out for itself.
    var undoAvailable: Bool

    var isOver: Bool { state.isOver }
}

/// The process-wide core. Singleton because the core is singleton-enforced: a
/// second `mxq_core_init` before shutdown is an error, not a second instance.
///
/// `shared` is the app's own core over the app's own store — the one whose
/// games the player keeps. Tests never touch it: they build cores of their own
/// against scratch store directories through the same initializer, which is
/// what keeps the seam honest — a test core is the real core over a store
/// nobody keeps, not a stand-in.
final class Core {
    private let handle: OpaquePointer

    /// The one attached session over the one active game, while there is one.
    /// Sessions are single-owner and this app is single-window, so the screen
    /// that holds the game is the owner and everything runs where it runs —
    /// the main actor, under the documented active-game exception in
    /// docs/core-interface.md's threading contract.
    private var session: OpaquePointer?

    /// Whether `shared` was ever asked for, so that termination can shut down
    /// a core that exists without creating one that does not.
    private static var sharedWasCreated = false

    static let shared: Result<Core, CoreError> = {
        sharedWasCreated = true
        do {
            return .success(try Core(storeDirectory: storeDirectory()))
        } catch {
            // A store directory that cannot be created is still a start-up
            // failure to show, not a reason to stop the process in a type cast.
            return .failure(CoreError(wrapping: error))
        }
    }()

    /// Best-effort deterministic teardown at termination: close the store and
    /// join the engine thread rather than relying on process exit. Best effort
    /// only — the store's journal is crash-safe by design, so nothing is owed
    /// beyond the call itself.
    static func shutdownSharedIfLive() {
        guard sharedWasCreated, case .success(let core) = shared else { return }
        core.shutdown()
    }

    init(storeDirectory: String) throws {
        // The bundled variant configuration the engine loads at initialisation.
        // Its absence is a packaging failure and surfaces here rather than at
        // the first move.
        guard let assets = Bundle.main.resourcePath else {
            throw CoreError(status: MxqStatus(MXQ_ERR_ENGINE_ASSET_MISSING),
                            detail: "the bundle has no resource path")
        }
        try FileManager.default.createDirectory(atPath: storeDirectory,
                                                withIntermediateDirectories: true)

        var handle: OpaquePointer?
        var err = MxqError()
        err.struct_size = UInt32(MemoryLayout<MxqError>.size)

        try storeDirectory.withCString { storePath in
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

    /// Deterministic teardown. Every handle this core issued — the session
    /// included — answers `MXQ_ERR_ARG_INVALID_HANDLE` afterwards instead of
    /// touching freed memory, which is exactly why nothing here has to be
    /// released first.
    func shutdown() {
        session = nil
        mxq_core_shutdown(handle, nil)
    }

    /// Where the app's own store lives. Debug builds take
    /// `-mxq-store-name <name>` so that every UI-test launch gets a store of
    /// its own and no test can touch a game the player is keeping. A name and
    /// deliberately not a path: the test runner and the app live in different
    /// sandbox containers, so an absolute path minted in the runner's world is
    /// exactly what the app cannot write. The name resolves inside the app's
    /// own temporary directory — relaunching with the same name is the same
    /// store, which is what the resume tests are about — and the system owns
    /// reclaiming it.
    private static func storeDirectory() -> String {
        #if DEBUG
        if let name = DebugLaunch.argument(after: "-mxq-store-name") {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(name, isDirectory: true).path
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
            .appendingPathComponent("MiniXiangqi", isDirectory: true).path
    }

    // MARK: - The ruleset's constants

    /// The frozen starting FEN. A constant of the ruleset, so it is read from
    /// the core rather than written a second time here.
    static var startFEN: String {
        var buffer = [CChar](repeating: 0, count: Int(MXQ_FEN_CAP))
        var length = 0
        let status = mxq_rules_start_fen(&buffer, buffer.count, &length, nil)
        precondition(status == MXQ_OK, "the starting FEN does not fit MXQ_FEN_CAP")
        return String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)),
                      as: UTF8.self)
    }

    // MARK: - Plumbing

    private static func freshError() -> MxqError {
        var err = MxqError()
        err.struct_size = UInt32(MemoryLayout<MxqError>.size)
        return err
    }

    /// The attached session, or the typed refusal that says the caller asked a
    /// session question with no session — an app bug, never a rules outcome.
    private func attachedSession() throws -> OpaquePointer {
        guard let session else {
            throw CoreError(status: MxqStatus(MXQ_ERR_STATE_ACTIVE_GAME_MISSING),
                            detail: "no session is attached")
        }
        return session
    }

    private static func string<T>(of fixedArray: T, capacity: Int32) -> String {
        withUnsafePointer(to: fixedArray) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(capacity)) {
                String(cString: $0)
            }
        }
    }

    private static func moveTexts(_ buffer: [MxqMove], count: Int) -> [String] {
        buffer.prefix(count).map { string(of: $0.text, capacity: MXQ_MOVE_TEXT_CAP) }
    }

    private static func evaluation(position: MxqPosition,
                                   status: MxqGameStatus) throws -> Evaluation {
        guard let side = Side(position.side_to_move) else {
            throw CoreError(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                            detail: "the core reported no side to move")
        }
        return Evaluation(
            fen: string(of: position.fen, capacity: MXQ_FEN_CAP),
            sideToMove: side,
            inCheck: position.in_check != 0,
            plyCount: Int(position.ply_count),
            state: GameState(status.state),
            reason: EndReason(status.reason),
            atOccurrence: Int(status.at_occurrence),
            claimAvailable: status.claim_available != 0,
            undoAvailable: status.undo_available != 0)
    }

    private static func check(_ status: MxqStatus, _ err: MxqError) throws {
        guard status != MXQ_OK else { return }
        throw CoreError(status: status,
                        detail: string(of: err.detail, capacity: MXQ_DETAIL_CAP))
    }
}

// MARK: - The rules seam

extension Core: Rules {

    var hasSession: Bool { session != nil }

    func resumeActive() throws -> Bool {
        precondition(session == nil, "a second session over the one active game")
        var game: OpaquePointer?
        var exists: UInt8 = 0
        var err = Self.freshError()
        try Self.check(mxq_game_resume_active(handle, &game, &exists, &err), err)
        session = game
        return exists != 0
    }

    func begin(with move: String) throws {
        precondition(session == nil, "began a game over a game")
        var config = MxqGameConfig()
        config.struct_size = UInt32(MemoryLayout<MxqGameConfig>.size)
        config.mode = MxqPlayMode(MXQ_PLAY_MODE_FREE_PLAY)
        config.human_side = MxqColor(MXQ_COLOR_NONE)
        config.ai_level = MxqAiLevel(MXQ_AI_LEVEL_NONE)
        config.first_mover_choice = MxqFirstMoverChoice(MXQ_FIRST_MOVER_NONE)
        config.ai_movetime_ms = 0

        var game: OpaquePointer?
        var err = Self.freshError()
        try Self.check(mxq_game_create(handle, &config, &game, &err), err)
        session = game
        // The first move follows in the same user-visible action. If its
        // commit is refused the session stays, holding a game of no moves:
        // the board is unchanged, the failure is the last attempt's, and the
        // retry applies to the session this action already created.
        try apply(move)
    }

    func apply(_ move: String) throws {
        let session = try attachedSession()
        var err = Self.freshError()
        try move.withCString {
            try Self.check(mxq_game_apply_move(session, $0, nil, nil, &err), err)
        }
    }

    func undo() throws -> Int {
        let session = try attachedSession()
        var removed: UInt32 = 0
        var err = Self.freshError()
        try Self.check(mxq_game_undo(session, &removed, &err), err)
        return Int(removed)
    }

    func claimDraw() throws -> UInt64 {
        let session = try attachedSession()
        var recordID: UInt64 = 0
        var err = Self.freshError()
        try Self.check(mxq_game_claim_draw(session, &recordID, &err), err)
        return recordID
    }

    func confirmResult() throws -> UInt64 {
        let session = try attachedSession()
        var recordID: UInt64 = 0
        var err = Self.freshError()
        try Self.check(mxq_game_confirm_result(session, &recordID, &err), err)
        return recordID
    }

    func evaluation() throws -> Evaluation {
        var position = MxqPosition()
        position.struct_size = UInt32(MemoryLayout<MxqPosition>.size)
        var status = MxqGameStatus()
        status.struct_size = UInt32(MemoryLayout<MxqGameStatus>.size)
        var err = Self.freshError()

        if let session {
            try Self.check(mxq_game_position(session, &position, &err), err)
            try Self.check(mxq_game_status(session, &status, &err), err)
        } else {
            // Before a session exists the board shows the frozen start
            // position, and the stateless facade is what answers for it: the
            // empty board's state is still the core's to adjudicate, not this
            // file's to assume.
            try Core.startFEN.withCString { fen in
                try Self.check(mxq_rules_evaluate(handle, fen, nil, 0,
                                                  &position, &status, nil, &err), err)
            }
        }
        return try Self.evaluation(position: position, status: status)
    }

    func moveHistory() throws -> [String] {
        guard let session else { return [] }
        var err = Self.freshError()
        var count = 0
        // The count alone first: a resumed game is as long as it is, and the
        // resume path deliberately lifts the import bounds, so no fixed buffer
        // is always sufficient here. The probe's buffer-too-small answer is
        // the count arriving, routine by the interface's own words.
        let probe = mxq_game_move_history(session, nil, 0, &count, &err)
        if probe != MXQ_ERR_ARG_BUFFER_TOO_SMALL { try Self.check(probe, err) }
        guard count > 0 else { return [] }
        var buffer = [MxqMove](repeating: MxqMove(), count: count)
        try Self.check(mxq_game_move_history(session, &buffer, buffer.count,
                                             &count, &err), err)
        return Self.moveTexts(buffer, count: count)
    }

    func legalMoves() throws -> [String] {
        var err = Self.freshError()
        var count = 0
        // One call sized to the widest position this ruleset can reach. The
        // count comes back either way, so an undersized buffer is a bug here
        // rather than a routine outcome to loop on.
        var buffer = [MxqMove](repeating: MxqMove(), count: 128)

        if let session {
            try Self.check(mxq_game_legal_moves(session, &buffer, buffer.count,
                                                &count, &err), err)
        } else {
            // The empty board again: the start position's moves are a rules
            // question, and the stateless facade is the session-free way to
            // ask it.
            try Core.startFEN.withCString { fen in
                try Self.check(mxq_rules_legal_moves(handle, fen, nil, 0,
                                                     &buffer, buffer.count,
                                                     &count, &err), err)
            }
        }
        return Self.moveTexts(buffer, count: count)
    }

    func fen(atPly ply: Int) throws -> String {
        let session = try attachedSession()
        var position = MxqPosition()
        position.struct_size = UInt32(MemoryLayout<MxqPosition>.size)
        var err = Self.freshError()
        try Self.check(mxq_game_position_at(session, UInt32(ply), &position, &err),
                       err)
        return Self.string(of: position.fen, capacity: MXQ_FEN_CAP)
    }
}

// MARK: - Session lifecycle above the seam

extension Core {
    /// Releases the session, if one is attached. The screen calls this as it
    /// replaces the game — after filing a finished one, or before resuming at
    /// launch — because a released session is the single-session rule's
    /// precondition, and release itself cannot fail and refuses nothing, so it
    /// is no part of the refusal seam.
    func endSession() {
        mxq_game_release(session)
        session = nil
    }
}

#if DEBUG
// MARK: - Test evidence

// The store read-backs the session tests assert against. Debug-only because
// they exist as evidence — the History screen's real read surface arrives with
// its own PR — and internal so a test reads the store through the same veneer
// the app trusts rather than through a second one.
extension Core {
    /// Whether the library holds an active game.
    func activeGameExists() throws -> Bool {
        var exists: UInt8 = 0
        var err = Self.freshError()
        try Self.check(mxq_store_active_exists(handle, &exists, &err), err)
        return exists != 0
    }

    /// The number of immutable History records.
    func historyCount() throws -> Int {
        var count: UInt32 = 0
        var revision: UInt64 = 0
        var err = Self.freshError()
        try Self.check(mxq_store_history_count(handle, &count, &revision, &err),
                       err)
        return Int(count)
    }
}
#endif
