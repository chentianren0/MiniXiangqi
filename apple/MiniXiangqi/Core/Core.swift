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
///
/// Nonisolated, as every type in this file that is pure data is: the target
/// defaults declarations to the main actor, which is right for a view and
/// wrong for a value the store surface builds off it.
nonisolated struct CoreError: Error, Equatable, CustomStringConvertible {
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

nonisolated enum Side: Sendable {
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
nonisolated enum GameState: Sendable {
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

/// The committed result of a finished game, which is not the same question as
/// the position's verdict: a resignation and an early end are outcomes no
/// position produces. `none` is the ended-early record's outcome, exactly when
/// the reason is `endedEarly`.
nonisolated enum Outcome: Sendable {
    case none, redWins, blackWins, draw

    init(_ outcome: MxqOutcome) {
        switch outcome {
        case MxqOutcome(MXQ_OUTCOME_RED_WINS): self = .redWins
        case MxqOutcome(MXQ_OUTCOME_BLACK_WINS): self = .blackWins
        case MxqOutcome(MXQ_OUTCOME_DRAW): self = .draw
        default: self = .none
        }
    }
}

nonisolated enum PlayMode: Sendable {
    case humanVersusAI, freePlay

    init(_ mode: MxqPlayMode) {
        self = mode == MxqPlayMode(MXQ_PLAY_MODE_HUMAN_VS_AI) ? .humanVersusAI : .freePlay
    }
}

nonisolated enum EndReason: Sendable {
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

nonisolated enum AiLevel: Sendable, Hashable, CaseIterable {
    case fast, standard, deep

    init?(_ level: MxqAiLevel) {
        switch level {
        case MxqAiLevel(MXQ_AI_LEVEL_FAST): self = .fast
        case MxqAiLevel(MXQ_AI_LEVEL_STANDARD): self = .standard
        case MxqAiLevel(MXQ_AI_LEVEL_DEEP): self = .deep
        default: return nil
        }
    }

    var raw: MxqAiLevel {
        switch self {
        case .fast: MxqAiLevel(MXQ_AI_LEVEL_FAST)
        case .standard: MxqAiLevel(MXQ_AI_LEVEL_STANDARD)
        case .deep: MxqAiLevel(MXQ_AI_LEVEL_DEEP)
        }
    }

    /// The exact thinking time frozen with a created game. Read from the
    /// core's own constants rather than written a second time here: the
    /// accepted 1/3/5 seconds are the engine contract's, not this app's.
    var movetimeMilliseconds: UInt32 {
        switch self {
        case .fast: MXQ_MOVETIME_FAST_MS
        case .standard: MXQ_MOVETIME_STANDARD_MS
        case .deep: MXQ_MOVETIME_DEEP_MS
        }
    }

    /// The serialized identifier in docs/game-data.md's archive vocabulary,
    /// which is also the name the Settings default is stored under.
    var name: String {
        switch self {
        case .fast: "fast"
        case .standard: "standard"
        case .deep: "deep"
        }
    }

    init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = match
    }
}

nonisolated enum FirstMoverChoice: Sendable, Hashable, CaseIterable {
    case humanFirst, aiFirst, random

    init?(_ choice: MxqFirstMoverChoice) {
        switch choice {
        case MxqFirstMoverChoice(MXQ_FIRST_MOVER_HUMAN_FIRST): self = .humanFirst
        case MxqFirstMoverChoice(MXQ_FIRST_MOVER_AI_FIRST): self = .aiFirst
        case MxqFirstMoverChoice(MXQ_FIRST_MOVER_RANDOM): self = .random
        default: return nil
        }
    }

    var raw: MxqFirstMoverChoice {
        switch self {
        case .humanFirst: MxqFirstMoverChoice(MXQ_FIRST_MOVER_HUMAN_FIRST)
        case .aiFirst: MxqFirstMoverChoice(MXQ_FIRST_MOVER_AI_FIRST)
        case .random: MxqFirstMoverChoice(MXQ_FIRST_MOVER_RANDOM)
        }
    }

    /// docs/game-data.md's serialized identifiers, and the stored preference
    /// names with them.
    var name: String {
        switch self {
        case .humanFirst: "human-first"
        case .aiFirst: "ai-first"
        case .random: "random"
        }
    }

    init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = match
    }
}

/// A game's frozen configuration, as the core holds it. Free Play carries the
/// absent constants, exactly as the archive omits the members.
nonisolated struct GameConfiguration: Sendable, Hashable {
    var mode: PlayMode
    /// The *resolved* human side — set even when the choice was 随机, because
    /// it cannot be reconstructed later.
    var humanSide: Side?
    var aiLevel: AiLevel?
    var firstMoverChoice: FirstMoverChoice?
    var movetimeMilliseconds: UInt32

    static let freePlay = GameConfiguration(mode: .freePlay, humanSide: nil,
                                            aiLevel: nil, firstMoverChoice: nil,
                                            movetimeMilliseconds: 0)

    /// A human-versus-AI game, with the first-mover choice already resolved to
    /// a side. Resolution happens in the creation flow, after preparation
    /// succeeds, and is committed only by a successful create.
    static func humanVersusAI(humanSide: Side, level: AiLevel,
                              choice: FirstMoverChoice) -> GameConfiguration {
        GameConfiguration(mode: .humanVersusAI, humanSide: humanSide,
                          aiLevel: level, firstMoverChoice: choice,
                          movetimeMilliseconds: level.movetimeMilliseconds)
    }

    init(mode: PlayMode, humanSide: Side?, aiLevel: AiLevel?,
         firstMoverChoice: FirstMoverChoice?, movetimeMilliseconds: UInt32) {
        self.mode = mode
        self.humanSide = humanSide
        self.aiLevel = aiLevel
        self.firstMoverChoice = firstMoverChoice
        self.movetimeMilliseconds = movetimeMilliseconds
    }

    init(_ config: MxqGameConfig) {
        self.init(mode: PlayMode(config.mode),
                  humanSide: Side(config.human_side),
                  aiLevel: AiLevel(config.ai_level),
                  firstMoverChoice: FirstMoverChoice(config.first_mover_choice),
                  movetimeMilliseconds: config.ai_movetime_ms)
    }

    var raw: MxqGameConfig {
        var config = MxqGameConfig()
        config.struct_size = UInt32(MemoryLayout<MxqGameConfig>.size)
        config.mode = mode == .humanVersusAI
            ? MxqPlayMode(MXQ_PLAY_MODE_HUMAN_VS_AI) : MxqPlayMode(MXQ_PLAY_MODE_FREE_PLAY)
        config.human_side = switch humanSide {
        case .red: MxqColor(MXQ_COLOR_RED)
        case .black: MxqColor(MXQ_COLOR_BLACK)
        case nil: MxqColor(MXQ_COLOR_NONE)
        }
        config.ai_level = aiLevel?.raw ?? MxqAiLevel(MXQ_AI_LEVEL_NONE)
        config.first_mover_choice = firstMoverChoice?.raw
            ?? MxqFirstMoverChoice(MXQ_FIRST_MOVER_NONE)
        config.ai_movetime_ms = movetimeMilliseconds
        return config
    }
}

/// A position and the game state, exactly as the core reports them — for a
/// session, the session's; before one exists, the frozen start position's.
nonisolated struct Evaluation: Sendable {
    var fen: String
    var sideToMove: Side
    var inCheck: Bool
    var plyCount: Int
    /// The per-session monotonic counter every accepted mutation bumps. It is
    /// the staleness authority, and the frontend's own comparison against it —
    /// the second of the two the interface requires — is what rejects a search
    /// result the core could not have known was stale.
    var positionRevision: UInt64

    var state: GameState
    var reason: EndReason
    /// The occurrence a repetition-based outcome attached at; 0 otherwise.
    var atOccurrence: Int
    var claimAvailable: Bool
    /// The core's own Undo affordance. An archived or absent session offers
    /// none, and nothing above the interface works that out for itself.
    var undoAvailable: Bool
    /// 1 or 2, by the decision-cycle rule. The core computes it; nothing above
    /// the interface counts plies to reach the same answer.
    var undoPlies: Int
    /// Exactly when `mxq_game_resign` is legal, so the affordance and the
    /// refusal are one rule.
    var resignAvailable: Bool
    /// Whether the committed state expects a search — the AI to move in an
    /// unfinished human-versus-AI game. This is what "a search is owed" means,
    /// and it is the core's answer rather than a derivation from the mode and
    /// the side to move.
    var searchExpected: Bool

    var isOver: Bool { state.isOver }
}

// MARK: - Plumbing shared by every call in this file

// Nonisolated because the store surface below is a value that may leave the
// main actor, and it speaks through exactly the same four helpers the session
// calls do.

// Internal rather than private since the engine and search veneer moved into
// Core/Engine.swift: it is the same four helpers over the same handle, and a
// second copy of them beside the second file would be a second place for the
// error conversion to drift.

nonisolated func freshError() -> MxqError {
    var err = MxqError()
    err.struct_size = UInt32(MemoryLayout<MxqError>.size)
    return err
}

nonisolated func string<T>(of fixedArray: T, capacity: Int32) -> String {
    withUnsafePointer(to: fixedArray) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(capacity)) {
            String(cString: $0)
        }
    }
}

private nonisolated func moveTexts(_ buffer: [MxqMove], count: Int) -> [String] {
    buffer.prefix(count).map { string(of: $0.text, capacity: MXQ_MOVE_TEXT_CAP) }
}

nonisolated func check(_ status: MxqStatus, _ err: MxqError) throws {
    guard status != MXQ_OK else { return }
    throw CoreError(status: status, detail: string(of: err.detail, capacity: MXQ_DETAIL_CAP))
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
    // Internal rather than private since Core/Engine.swift carries the search
    // facade's half of this veneer: it is the same handle, and the split is by
    // subject rather than by visibility.
    let handle: OpaquePointer

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
                try check(mxq_core_init(&config, &handle, &err), err)
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

    /// The attached session, or the typed refusal that says the caller asked a
    /// session question with no session — an app bug, never a rules outcome.
    func attachedSession() throws -> OpaquePointer {
        guard let session else {
            throw CoreError(status: MxqStatus(MXQ_ERR_STATE_ACTIVE_GAME_MISSING),
                            detail: "no session is attached")
        }
        return session
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
            positionRevision: position.position_revision,
            state: GameState(status.state),
            reason: EndReason(status.reason),
            atOccurrence: Int(status.at_occurrence),
            claimAvailable: status.claim_available != 0,
            undoAvailable: status.undo_available != 0,
            undoPlies: Int(status.undo_plies),
            resignAvailable: status.resign_available != 0,
            searchExpected: status.search_expected != 0)
    }

}

// MARK: - The rules seam

extension Core: Rules {

    var hasSession: Bool { session != nil }

    func resumeActive() throws -> Bool {
        precondition(session == nil, "a second session over the one active game")
        var game: OpaquePointer?
        var exists: UInt8 = 0
        var err = freshError()
        try check(mxq_game_resume_active(handle, &game, &exists, &err), err)
        session = game
        return exists != 0
    }

    func create(_ configuration: GameConfiguration) throws {
        precondition(session == nil, "created a game over a game")
        var config = configuration.raw
        var game: OpaquePointer?
        var err = freshError()
        try check(mxq_game_create(handle, &config, &game, &err), err)
        session = game
    }

    func configuration() throws -> GameConfiguration {
        let session = try attachedSession()
        var config = MxqGameConfig()
        config.struct_size = UInt32(MemoryLayout<MxqGameConfig>.size)
        var err = freshError()
        try check(mxq_game_config(session, &config, &err), err)
        return GameConfiguration(config)
    }

    /// The session's stable identity — the version 7 UUID frozen at creation.
    /// Half of the staleness comparison a search result is judged by.
    func gameID() throws -> String {
        let session = try attachedSession()
        var buffer = [CChar](repeating: 0, count: Int(MXQ_GAME_ID_CAP))
        var length = 0
        var err = freshError()
        try check(mxq_game_id(session, &buffer, buffer.count, &length, &err), err)
        return String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)),
                      as: UTF8.self)
    }

    func resign() throws -> UInt64 {
        let session = try attachedSession()
        var recordID: UInt64 = 0
        var err = freshError()
        try check(mxq_game_resign(session, &recordID, &err), err)
        return recordID
    }

    func apply(_ move: String) throws {
        let session = try attachedSession()
        var err = freshError()
        try move.withCString {
            try check(mxq_game_apply_move(session, $0, nil, nil, &err), err)
        }
    }

    func undo() throws -> Int {
        let session = try attachedSession()
        var removed: UInt32 = 0
        var err = freshError()
        try check(mxq_game_undo(session, &removed, &err), err)
        return Int(removed)
    }

    func claimDraw() throws -> UInt64 {
        let session = try attachedSession()
        var recordID: UInt64 = 0
        var err = freshError()
        try check(mxq_game_claim_draw(session, &recordID, &err), err)
        return recordID
    }

    func confirmResult() throws -> UInt64 {
        let session = try attachedSession()
        var recordID: UInt64 = 0
        var err = freshError()
        try check(mxq_game_confirm_result(session, &recordID, &err), err)
        return recordID
    }

    func evaluation() throws -> Evaluation {
        var position = MxqPosition()
        position.struct_size = UInt32(MemoryLayout<MxqPosition>.size)
        var status = MxqGameStatus()
        status.struct_size = UInt32(MemoryLayout<MxqGameStatus>.size)
        var err = freshError()

        if let session {
            try check(mxq_game_position(session, &position, &err), err)
            try check(mxq_game_status(session, &status, &err), err)
        } else {
            // Before a session exists the board shows the frozen start
            // position, and the stateless facade is what answers for it: the
            // empty board's state is still the core's to adjudicate, not this
            // file's to assume.
            try Core.startFEN.withCString { fen in
                try check(mxq_rules_evaluate(handle, fen, nil, 0,
                                                  &position, &status, nil, &err), err)
            }
        }
        return try Self.evaluation(position: position, status: status)
    }

    func moveHistory() throws -> [String] {
        guard let session else { return [] }
        var err = freshError()
        var count = 0
        // The count alone first: a resumed game is as long as it is, and the
        // resume path deliberately lifts the import bounds, so no fixed buffer
        // is always sufficient here. The probe's buffer-too-small answer is
        // the count arriving, routine by the interface's own words.
        let probe = mxq_game_move_history(session, nil, 0, &count, &err)
        if probe != MXQ_ERR_ARG_BUFFER_TOO_SMALL { try check(probe, err) }
        guard count > 0 else { return [] }
        var buffer = [MxqMove](repeating: MxqMove(), count: count)
        try check(mxq_game_move_history(session, &buffer, buffer.count,
                                             &count, &err), err)
        return moveTexts(buffer, count: count)
    }

    func legalMoves() throws -> [String] {
        var err = freshError()
        var count = 0
        // One call sized to the widest position this ruleset can reach. The
        // count comes back either way, so an undersized buffer is a bug here
        // rather than a routine outcome to loop on.
        var buffer = [MxqMove](repeating: MxqMove(), count: 128)

        if let session {
            try check(mxq_game_legal_moves(session, &buffer, buffer.count,
                                                &count, &err), err)
        } else {
            // The empty board again: the start position's moves are a rules
            // question, and the stateless facade is the session-free way to
            // ask it.
            try Core.startFEN.withCString { fen in
                try check(mxq_rules_legal_moves(handle, fen, nil, 0,
                                                     &buffer, buffer.count,
                                                     &count, &err), err)
            }
        }
        return moveTexts(buffer, count: count)
    }

    func fen(atPly ply: Int) throws -> String {
        let session = try attachedSession()
        var position = MxqPosition()
        position.struct_size = UInt32(MemoryLayout<MxqPosition>.size)
        var err = freshError()
        try check(mxq_game_position_at(session, UInt32(ply), &position, &err),
                       err)
        return string(of: position.fen, capacity: MXQ_FEN_CAP)
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

// MARK: - The library's History surface

/// One stored game, as the History list reads it: the core's own summary,
/// converted and nothing more. Every field here is the store's answer; the row
/// composes them and judges none of them.
nonisolated struct RecordSummary: Identifiable, Sendable, Hashable {
    /// The store's `record_id`, never reissued after a deletion — so a stale
    /// one dangles rather than naming some later game.
    var id: UInt64
    var mode: PlayMode
    /// The human's resolved side in human-versus-AI play; absent in Free Play,
    /// where the same person controls both.
    var humanSide: Side?
    var outcome: Outcome
    var reason: EndReason
    /// Plies, which is what 步 counts.
    var moveCount: Int
    var pinned: Bool
    var imported: Bool
    /// When the game ended — the instant that made it a record. The store
    /// orders the list by its own History-added time instead, and for a game
    /// played on this device the two are one transaction apart.
    var endedAt: Date
}

/// The library's History surface.
///
/// The screen calls these on the main actor, under the documented exception in
/// docs/core-interface.md's threading contract that the active game's commits
/// already run under: a page read commits nothing and does not fsync, and a pin
/// or a delete is one commit per user action, which is exactly the shape the
/// owner's proportionality ruling accepted. `mxq_store_history_open` is the one
/// the argument does not bound — it decodes and replays a whole game — and it
/// is named in the contract as the call to measure at Stage 6.
///
/// It is nonetheless a `Sendable` value over the core handle alone rather than
/// a method on `Core`: it holds no Swift state to race on, and the core
/// serializes store work behind one mutex and one connection, so moving these
/// calls back off the main actor is a change of call site rather than of
/// design. That is what makes the contract's "held in reserve" mean something.
///
/// A handle outliving its core is safe by the interface's own promise: after
/// `mxq_core_shutdown` every handle it issued answers
/// `MXQ_ERR_ARG_INVALID_HANDLE` rather than touching freed memory.
///
/// `@unchecked` because `OpaquePointer` carries no sendability of its own and
/// cannot: what makes this one safe to send is the C contract above it, which
/// Swift cannot read. The claim being made is exactly the header's — any thread
/// except inside a search callback — and nothing else in the struct can race.
nonisolated struct HistoryStore: @unchecked Sendable {
    fileprivate let handle: OpaquePointer

    /// How many records there are, and the library revision — a monotonic
    /// counter every committed store mutation bumps. Return values plus this
    /// cheap staleness check are the interface's whole answer to observing the
    /// library; there is no notification to subscribe to.
    func count() throws -> (records: Int, revision: UInt64) {
        var count: UInt32 = 0
        var revision: UInt64 = 0
        var err = freshError()
        try check(mxq_store_history_count(handle, &count, &revision, &err), err)
        return (Int(count), revision)
    }

    /// One page, in the core's own order — pinned first, then newest within
    /// each group. The order is a core guarantee and nothing above re-sorts it.
    func page(offset: Int, limit: Int) throws -> (records: [RecordSummary],
                                                  revision: UInt64) {
        var buffer = [MxqRecordSummary](repeating: MxqRecordSummary(), count: limit)
        var written = 0
        var revision: UInt64 = 0
        var err = freshError()
        // The caller chose the page size, so a buffer smaller than the limit is
        // this code's bug rather than a routine way to ask for the count: the
        // two are the same number here by construction.
        try check(mxq_store_history_page(handle, UInt32(offset), UInt32(limit),
                                         &buffer, buffer.count, &written,
                                         &revision, &err), err)
        return (buffer.prefix(written).map(RecordSummary.init), revision)
    }

    /// Every record, read a page at a time. The target MVP has no search and no
    /// filters, so the list is the library, and a few thousand summaries is a
    /// few hundred kilobytes.
    func all() throws -> (records: [RecordSummary], revision: UInt64) {
        var records: [RecordSummary] = []
        var revision: UInt64 = 0
        while true {
            let page = try page(offset: records.count, limit: Self.pageSize)
            records += page.records
            revision = page.revision
            // Short of the page size means the end of the list, by the
            // interface's own words.
            if page.records.count < Self.pageSize { return (records, revision) }
        }
    }

    private static let pageSize = 200

    /// Pin or unpin — the only mutable field a History record has.
    func setPinned(_ pinned: Bool, on record: UInt64) throws {
        var err = freshError()
        try check(mxq_store_history_set_pinned(handle, record, pinned ? 1 : 0, &err),
                  err)
    }

    /// Permanent, whole, and with no undo behind it.
    func delete(_ record: UInt64) throws {
        var err = freshError()
        try check(mxq_store_history_delete(handle, record, &err), err)
    }

    /// Opens the record as a detached read-only session and hands back its
    /// handle. Ownership passes to whoever receives it — the replay screen,
    /// where every remaining call on it is a non-blocking session query.
    func open(_ record: UInt64) throws -> ReplayHandle {
        var replay: OpaquePointer?
        var err = freshError()
        try check(mxq_store_history_open(handle, record, &replay, &err), err)
        guard let replay else {
            throw CoreError(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                            detail: "mxq_store_history_open reported success without a session")
        }
        return ReplayHandle(handle: replay)
    }
}

/// What one import did. Both cases are success: a file the library already
/// holds is not an error, and the record it names is the one it already had.
nonisolated enum ImportOutcome: Sendable {
    case created
    case existing
}

/// One import's answer: which of the two happened, and the record either way.
nonisolated struct ImportedGame: Sendable {
    var outcome: ImportOutcome
    var record: RecordSummary
}

/// Interchange: one game out as a file, one game in from one.
///
/// These two are the calls `docs/core-interface.md` keeps **outside** the
/// main-actor exception the rest of this surface runs under, so every caller
/// reaches them from a detached context. Both are unbounded in a way the
/// exception's argument does not cover: an export decodes and re-encodes a
/// whole game, and an import validates an untrusted file — replaying every ply
/// of it — against a two-second budget before it writes anything.
nonisolated extension HistoryStore {
    /// One immutable History record, as the portable file that leaves the app.
    ///
    /// The bytes are the record's own content with the export event stamped on
    /// it; the core owns both halves of that sentence, and nothing here reads
    /// or edits the document.
    func export(_ record: UInt64) throws -> Data {
        var blob: OpaquePointer?
        var err = freshError()
        try check(mxq_store_export(handle, record, &blob, &err), err)
        guard let blob else {
            throw CoreError(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                            detail: "mxq_store_export reported success without a blob")
        }
        // The one pointer into core memory this interface hands out, valid
        // until the release below — so the bytes are copied before it goes.
        defer { mxq_blob_release(blob) }
        guard let bytes = mxq_blob_bytes(blob) else { return Data() }
        return Data(bytes: bytes, count: mxq_blob_len(blob))
    }

    /// One game file, validated whole and filed — or refused, with the library
    /// untouched. The bytes are untrusted input and the core treats them as
    /// such; this hands them over and reports what came back.
    func importGame(_ file: Data) throws -> ImportedGame {
        var outcome = MxqImportOutcome(MXQ_IMPORT_CREATED)
        var record: UInt64 = 0
        var summary = MxqRecordSummary()
        summary.struct_size = UInt32(MemoryLayout<MxqRecordSummary>.size)
        var err = freshError()
        // A zero-byte file is one the picker will really hand over, and the
        // core has an answer for it — the archive is empty — but a null pointer
        // is a programming error rather than a bad file. An empty buffer has no
        // address, so a spare byte lends one and the length stays 0.
        var spare: UInt8 = 0
        let status = withUnsafePointer(to: &spare) { lent in
            file.withUnsafeBytes { raw in
                mxq_store_import(handle,
                                 raw.bindMemory(to: UInt8.self).baseAddress ?? lent,
                                 raw.count, &outcome, &record, &summary, &err)
            }
        }
        try check(status, err)
        return ImportedGame(outcome: outcome == MxqImportOutcome(MXQ_IMPORT_EXISTING)
                                     ? .existing : .created,
                            record: RecordSummary(summary))
    }
}

/// A detached replay session in transit, between the call that opened it and
/// the object that will own it. The type exists to make that one hand-off
/// visible, since a session is single-owner and this is the moment its owner is
/// decided — and to keep the handle sendable, so that opening it off the main
/// actor stays a change of call site rather than of design.
nonisolated struct ReplayHandle: @unchecked Sendable {
    fileprivate let handle: OpaquePointer
}

private nonisolated extension RecordSummary {
    init(_ summary: MxqRecordSummary) {
        self.init(id: summary.record_id,
                  mode: PlayMode(summary.mode),
                  humanSide: Side(summary.human_side),
                  outcome: Outcome(summary.outcome),
                  reason: EndReason(summary.end_reason),
                  moveCount: Int(summary.move_count),
                  pinned: summary.pinned != 0,
                  imported: summary.provenance == MxqProvenance(MXQ_PROVENANCE_IMPORTED),
                  endedAt: Date(milliseconds: summary.ended_at_ms != 0
                                ? summary.ended_at_ms : summary.added_at_ms))
    }
}

private nonisolated extension Date {
    init(milliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}

/// The position at one ply of a replayed game.
nonisolated struct ReplayPosition: Sendable {
    var fen: String
    var sideToMove: Side
    var inCheck: Bool
}

/// A History record open for replay: the core's detached read-only session.
/// Every query answers as it does on any session, every affordance reads 0, and
/// a mutation is refused — which is why the replay screen has no rule of its
/// own to enforce about what the board will not do.
///
/// The queries below are the session's owner's to make and are non-blocking, so
/// once the handle has arrived they cost a frame nothing: the walk is a lookup
/// into a game the core has already replayed.
final class ReplaySession {
    private var handle: OpaquePointer?

    init(_ opened: ReplayHandle) {
        self.handle = opened.handle
    }

    /// The recorded line, whole.
    func moves() throws -> [String] {
        let session = try live()
        var err = freshError()
        var count = 0
        let probe = mxq_game_move_history(session, nil, 0, &count, &err)
        if probe != MXQ_ERR_ARG_BUFFER_TOO_SMALL { try check(probe, err) }
        guard count > 0 else { return [] }
        var buffer = [MxqMove](repeating: MxqMove(), count: count)
        try check(mxq_game_move_history(session, &buffer, buffer.count, &count, &err),
                  err)
        return moveTexts(buffer, count: count)
    }

    /// The position after the first `ply` plies. This is the walk: replay never
    /// applies a move, it asks the core what the position was.
    func position(atPly ply: Int) throws -> ReplayPosition {
        let session = try live()
        var position = MxqPosition()
        position.struct_size = UInt32(MemoryLayout<MxqPosition>.size)
        var err = freshError()
        try check(mxq_game_position_at(session, UInt32(ply), &position, &err), err)
        guard let side = Side(position.side_to_move) else {
            throw CoreError(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                            detail: "the core reported no side to move")
        }
        return ReplayPosition(fen: string(of: position.fen, capacity: MXQ_FEN_CAP),
                              sideToMove: side,
                              inCheck: position.in_check != 0)
    }

    /// Releases the session. The screen calls this as it closes, because a
    /// detached session is a handle the core is holding open for it; release
    /// cannot fail and refuses nothing.
    func close() {
        mxq_game_release(handle)
        handle = nil
    }

    /// The safety net under `close()`. Isolated, because releasing a session
    /// is its owner's call and this class is the owner: an ordinary deinit
    /// could run anywhere and would be exactly the cross-thread release the
    /// single-owner rule forbids.
    isolated deinit { mxq_game_release(handle) }

    private func live() throws -> OpaquePointer {
        guard let handle else {
            throw CoreError(status: MxqStatus(MXQ_ERR_ARG_INVALID_HANDLE),
                            detail: "the replay session is closed")
        }
        return handle
    }
}

extension Core {
    /// The library's History surface over this core.
    var history: HistoryStore { HistoryStore(handle: handle) }
}

#if DEBUG
// MARK: - Test evidence

// The store read-backs the session tests assert against. Debug-only because
// they exist as evidence rather than as product surface — the History screen
// reads through `history` above — and internal so a test reads the store
// through the same veneer the app trusts rather than through a second one.
extension Core {
    /// Whether the library holds an active game.
    func activeGameExists() throws -> Bool {
        var exists: UInt8 = 0
        var err = freshError()
        try check(mxq_store_active_exists(handle, &exists, &err), err)
        return exists != 0
    }

    /// The number of immutable History records.
    func historyCount() throws -> Int {
        try history.count().records
    }
}
#endif
