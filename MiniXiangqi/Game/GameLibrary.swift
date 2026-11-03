// The library: every GameRecord, in SwiftData.
//
// One record has no result, and that record is the game in play. Each move is
// checked against the core's rules, appended and saved before the call returns,
// so autosave is a save after each move and a relaunch reads the game back
// where it stood. A save that fails rolls the context back, so a refused move
// or Undo did not happen. Ending a game sets its result; History is the query
// of the records that have one, pinned first and then newest.
//
// A surface that is playing the game in play holds it here — `resumeActive()`,
// `create`, `endSession()` — and while one does, no other surface may take it.
// A networked game is never held: its engine writes it by id through `change`,
// and the local board does not open it.

import Foundation
import MiniXiangqiCore
import SwiftData

/// The game in play as the library describes it, with nothing held: the Play
/// home's card and the save-and-continue confirmation read this.
nonisolated struct ActiveGameSummary: Equatable, Sendable {
    var game: GameKind
    var mode: PlayMode
    /// The human's resolved side in human-versus-AI play.
    var humanSide: Side?
    /// The side this device's player took, in a networked game.
    var localSide: Side?
    /// Plies, which is what 步 counts.
    var moveCount: Int
    var state: GameState
    var reason: EndReason
    /// Whose turn it is, from the position: a game whose start has Black to
    /// move has Black making ply 0.
    var sideToMove: Side
}

/// What one import did. Both are success: a file the library already holds is
/// not an error, and the record is the one it already had.
nonisolated enum ImportOutcome: Sendable {
    case created
    case existing
}

/// Why an import filed nothing.
nonisolated enum ImportRefusal: Error, Equatable {
    /// Not a game file, or one that is incomplete.
    case unreadable
    /// Written by a newer version of the app.
    case newerVersion
    /// Written by a 3.x version of the app, whose files are not read.
    case earlierVersion
    /// A game these rules do not play: a start the setup predicate refuses, a
    /// move that is not legal at its turn, or a result the moves contradict.
    case illegal
}

/// Why the library refused to change the game in play. Every one is a caller
/// that asked for something the game does not offer.
nonisolated enum LibraryRefusal: Error {
    case noGameInPlay
    case gameInPlayExists
    case gameIsOver
    case unavailable
}

@MainActor
final class GameLibrary {
    let core: Core
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// The game in play, while a surface holds it.
    private(set) var attached: GameRecord?

    init(core: Core, container: ModelContainer) {
        self.core = core
        self.container = container
    }

    /// The container at `url`, or in memory where there is none.
    static func container(at url: URL?) throws -> ModelContainer {
        let configuration = url.map { ModelConfiguration(url: $0) }
            ?? ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: GameRecord.self, configurations: configuration)
    }

    /// Where the app's own library lives. Debug builds take
    /// `-mxq-store-name <name>`, a scratch library in the temporary directory,
    /// so a UI test never plays into the player's own.
    static func appStoreURL() -> URL {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "mxq-store-name") {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("Library.store")
        }
        #endif
        return URL.applicationSupportDirectory.appendingPathComponent("Library.store")
    }

    // MARK: - The game in play

    /// The record without a result, if there is one.
    func activeRecord() throws -> GameRecord? {
        if let attached { return attached }
        var descriptor = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.endedAt == nil })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func activeGameSummary() throws -> ActiveGameSummary? {
        guard let record = try activeRecord() else { return nil }
        let evaluation = try core.evaluate(record.kind, from: record.start, moves: record.moves)
        return ActiveGameSummary(game: record.kind, mode: record.mode,
                                 humanSide: record.humanSide, localSide: record.localSide,
                                 moveCount: record.moves.count,
                                 state: evaluation.state, reason: evaluation.reason,
                                 sideToMove: evaluation.sideToMove)
    }

    var hasSession: Bool { attached != nil }

    /// Holds the game in play. False where there is none.
    func resumeActive() throws -> Bool {
        precondition(attached == nil, "a second surface over the game in play")
        attached = try activeRecord()
        return attached != nil
    }

    func endSession() {
        attached = nil
    }

    /// Creates the game in play and holds it. The library has one game in play,
    /// so creating one while another stands is refused.
    func create(_ configuration: GameConfiguration) throws {
        precondition(attached == nil, "created a game over a game")
        attached = try insert(GameRecord(configuration))
    }

    private func insert(_ record: GameRecord) throws -> GameRecord {
        guard try activeRecord() == nil else { throw LibraryRefusal.gameInPlayExists }
        // A start the rules will not begin from is refused before anything is
        // saved: the setup predicate first, so the engine never sees a position
        // offering the capture of a general, then the start's own verdict.
        if let setup = record.setup, core.setupVerdict(of: setup, game: record.kind) != .legal {
            throw CoreError(status: MxqStatus(MXQ_ERR_RULES_ILLEGAL_POSITION),
                            detail: "the start is not a position this game is set up in")
        }
        guard try !core.evaluate(record.kind, from: record.start, moves: []).isOver else {
            throw LibraryRefusal.gameIsOver
        }
        context.insert(record)
        try save()
        return record
    }

    private func held() throws -> GameRecord {
        guard let attached else { throw LibraryRefusal.noGameInPlay }
        return attached
    }

    func configuration() throws -> GameConfiguration {
        try held().configuration
    }

    func moveHistory() throws -> [String] {
        attached?.moves ?? []
    }

    /// The position and verdict of the held game.
    func evaluation() throws -> Evaluation {
        let record = try held()
        return try core.evaluate(record.kind, from: record.start, moves: record.moves)
    }

    func legalMoves() throws -> [String] {
        let record = try held()
        return try core.legalMoves(record.kind, from: record.start, moves: record.moves)
    }

    /// The position after the first `ply` plies of the held game.
    func fen(atPly ply: Int) throws -> String {
        let record = try held()
        return try core.evaluate(record.kind, from: record.start,
                                 moves: Array(record.moves.prefix(ply))).fen
    }

    /// Plays one move and saves. A move the rules refuse changes nothing. The
    /// callers offer no move once the rules have decided the game.
    func apply(_ move: String) throws {
        let record = try held()
        _ = try core.evaluate(record.kind, from: record.start, moves: record.moves + [move])
        record.moves.append(move)
        try save()
    }

    /// Takes back the last `plies` and saves. How many one Undo takes is the
    /// game's rule, not the library's.
    func undo(_ plies: Int) throws {
        let record = try held()
        guard plies > 0, plies <= record.moves.count else { throw LibraryRefusal.unavailable }
        record.moves.removeLast(plies)
        try save()
    }

    /// Claims the neutral repetition as a draw.
    func claimDraw() throws -> UUID {
        let evaluation = try evaluation()
        guard evaluation.claimAvailable else { throw LibraryRefusal.unavailable }
        return try end(.draw, .threefoldRepetition)
    }

    /// Ends the game with the result the rules gave its line.
    func confirmResult() throws -> UUID {
        let evaluation = try evaluation()
        guard let outcome = evaluation.state.outcome else { throw LibraryRefusal.unavailable }
        return try end(outcome, evaluation.reason)
    }

    /// The human resigns a human-versus-AI game that has no result of its own.
    func resign() throws -> UUID {
        let record = try held()
        guard record.mode == .humanVersusAI, let human = record.humanSide,
              try !evaluation().isOver else { throw LibraryRefusal.unavailable }
        return try end(.win(for: human.opponent), .resignation)
    }

    private func end(_ outcome: Outcome, _ reason: EndReason) throws -> UUID {
        let record = try held()
        record.end(outcome, reason)
        try save()
        attached = nil
        return record.id
    }

    /// 保存并继续: the game in play into History by its own state — a line the
    /// rules decided keeps its result, and anything else ended early — whether
    /// or not a surface holds it. Answers on a later turn, like a refusal
    /// would, so the caller's alert has gone before the answer arrives.
    func archiveActiveAndClear(
        completion: @escaping @MainActor (Result<UUID, CoreError>) -> Void
    ) {
        let result = Result { try archiveActive() }.mapError(CoreError.init(wrapping:))
        Task { @MainActor in completion(result) }
    }

    private func archiveActive() throws -> UUID {
        guard let record = try activeRecord() else { throw LibraryRefusal.noGameInPlay }
        let evaluation = try core.evaluate(record.kind, from: record.start, moves: record.moves)
        if let outcome = evaluation.state.outcome {
            record.end(outcome, evaluation.reason)
        } else {
            record.end(.none, .endedEarly)
        }
        try save()
        attached = nil
        return record.id
    }

    // MARK: - A game two devices play

    /// Creates the networked game in play under the id both devices share. It
    /// is not held: the networked engine writes it through `change`.
    func createNetworked(_ configuration: GameConfiguration, id: UUID,
                         peer: String) throws -> GameRecord {
        let record = GameRecord(configuration, id: id)
        record.peer = peer
        return try insert(record)
    }

    /// The finished networked games whose chosen ending has not yet reached
    /// that device.
    func undelivered(in mode: PlayMode, with peer: String) throws -> [GameRecord] {
        try context.fetch(FetchDescriptor<GameRecord>(predicate: #Predicate {
            $0.peer == peer && $0.endingUndelivered
        })).filter { $0.mode == mode }
    }

    /// Changes a record and saves, or puts it back as it was.
    func change(_ record: GameRecord, _ body: (GameRecord) throws -> Void) throws {
        do {
            try body(record)
        } catch {
            context.rollback()
            throw error
        }
        try save()
    }

    // MARK: - History

    /// Every finished game, pinned first and newest first within each group.
    func history() throws -> [GameRecord] {
        let newest = [SortDescriptor(\GameRecord.endedAt, order: .reverse)]
        let pinned = try context.fetch(FetchDescriptor<GameRecord>(
            predicate: #Predicate { $0.endedAt != nil && $0.pinned }, sortBy: newest))
        let others = try context.fetch(FetchDescriptor<GameRecord>(
            predicate: #Predicate { $0.endedAt != nil && !$0.pinned }, sortBy: newest))
        return pinned + others
    }

    func record(_ id: UUID) throws -> GameRecord? {
        var descriptor = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// One record as a game file.
    func fileData(of id: UUID) throws -> Data {
        guard let record = try record(id) else { throw LibraryRefusal.unavailable }
        return try record.fileData()
    }

    func setPinned(_ pinned: Bool, on record: GameRecord) throws {
        record.pinned = pinned
        try save()
    }

    func delete(_ record: GameRecord) throws {
        context.delete(record)
        try save()
    }

    /// One game file, checked whole and filed — or refused, with the library
    /// untouched. The moves are replayed through the rules, so a file can only
    /// bring in a game these rules play.
    func importGame(_ file: Data) throws -> (outcome: ImportOutcome, record: GameRecord) {
        let record: GameRecord
        do {
            record = try GameRecord.decoding(file: file)
        } catch is GameRecord.NewerVersion {
            throw ImportRefusal.newerVersion
        } catch is GameRecord.EarlierVersion {
            throw ImportRefusal.earlierVersion
        } catch {
            throw ImportRefusal.unreadable
        }
        guard let result = record.result, let reason = record.reason, record.endedAt != nil,
              record.mode != .humanVersusAI || (record.humanSide != nil && record.aiLevel != nil)
        else { throw ImportRefusal.unreadable }
        if let existing = try self.record(record.id) {
            return (.existing, existing)
        }
        try check(record, result: result, reason: reason)
        context.insert(record)
        try save()
        return (.created, record)
    }

    private func check(_ record: GameRecord, result: Outcome, reason: EndReason) throws {
        if let setup = record.setup {
            guard core.setupVerdict(of: setup, game: record.kind) == .legal else {
                throw ImportRefusal.illegal
            }
        } else if Core.frozenStartFEN(for: record.kind) == nil {
            throw ImportRefusal.illegal
        }
        guard let evaluation = try? core.evaluate(record.kind, from: record.start,
                                                  moves: record.moves) else {
            throw ImportRefusal.illegal
        }
        if let decided = evaluation.state.outcome,
           decided != result || evaluation.reason != reason {
            throw ImportRefusal.illegal
        }
    }

    // MARK: - Saving

    /// Saves, or puts everything back as it was saved last.
    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
