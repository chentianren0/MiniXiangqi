// The Swift veneer over the core's C interface. It converts types and raises
// errors and decides no rule. The core is stateless: every question is asked
// of a game, a start and a move line, and the game itself is GameRecord.

import Foundation
import MiniXiangqiCore

/// A failed call. `status` is the core's code where the core refused, and
/// `detail` is a short English diagnostic for the log, never user-facing copy.
///
/// Pure-data types in this file are nonisolated because the target defaults
/// declarations to the main actor.
nonisolated struct CoreError: Error, Equatable, CustomStringConvertible {
    var status: MxqStatus
    var detail: String

    var description: String { "mxq status \(status): \(detail)" }

    /// Any error as a `CoreError`, so nothing above this file has to import
    /// the core's module to report one.
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

/// The side that moves first and the other, in every game. The placement games
/// call the first mover's stones black, so `red` is the black stone there.
nonisolated enum Side: String, Codable, Sendable {
    case red, black

    init?(_ color: MxqColor) {
        switch color {
        case MxqColor(MXQ_COLOR_RED): self = .red
        case MxqColor(MXQ_COLOR_BLACK): self = .black
        default: return nil
        }
    }

    var opponent: Side { self == .red ? .black : .red }
}

/// The rules' verdict on a line.
nonisolated enum GameState: Sendable {
    case ongoing, claimableDraw, redWins, blackWins, draw

    init(_ state: MxqGameState) {
        switch state {
        case MxqGameState(MXQ_GAME_CLAIMABLE_DRAW): self = .claimableDraw
        case MxqGameState(MXQ_GAME_RED_WINS): self = .redWins
        case MxqGameState(MXQ_GAME_BLACK_WINS): self = .blackWins
        case MxqGameState(MXQ_GAME_DRAW): self = .draw
        default: self = .ongoing
        }
    }

    /// Ongoing and claimable-draw are never a result.
    var isOver: Bool { self != .ongoing && self != .claimableDraw }

    /// The result a finished line gives, where it is finished.
    var outcome: Outcome? {
        switch self {
        case .redWins: .redWins
        case .blackWins: .blackWins
        case .draw: .draw
        case .ongoing, .claimableDraw: nil
        }
    }
}

/// The result of a finished game, which is not the same question as the
/// position's verdict: a resignation and an early end are results no position
/// produces. `none` is the ended-early record's, exactly when the reason is
/// `endedEarly`.
nonisolated enum Outcome: String, Codable, Sendable {
    case none
    case redWins = "red-wins"
    case blackWins = "black-wins"
    case draw

    static func win(for side: Side) -> Outcome { side == .red ? .redWins : .blackWins }
}

nonisolated enum PlayMode: String, Codable, Sendable {
    case humanVersusAI = "human-vs-ai"
    case freePlay = "free-play"
    case nearby, online

    /// The two networked modes differ only in how the devices reached each
    /// other, so a rule about a player on the other end asks this rather than
    /// naming a mode.
    var isNetworked: Bool {
        switch self {
        case .nearby, .online: true
        case .humanVersusAI, .freePlay: false
        }
    }
}

/// Which game is played. The raw values are the `rules_id`s the protocol and the
/// game file name the games by.
nonisolated enum GameKind: String, Codable, Sendable, Hashable, CaseIterable {
    case miniXiangqi = "minixiangqi"
    case xiangqi
    case gomoku15 = "gomoku-15"
    case renju
    case jieqi

    var raw: MxqGameKind {
        switch self {
        case .miniXiangqi: MxqGameKind(MXQ_GAME_KIND_MINI_XIANGQI)
        case .xiangqi: MxqGameKind(MXQ_GAME_KIND_XIANGQI)
        case .gomoku15: MxqGameKind(MXQ_GAME_KIND_GOMOKU_15)
        case .renju: MxqGameKind(MXQ_GAME_KIND_RENJU)
        case .jieqi: MxqGameKind(MXQ_GAME_KIND_JIEQI)
        }
    }

    /// Whether the ruleset hides identities. Asked of the game, never read off
    /// a board: a Jieqi position with nothing face down is spelled exactly as
    /// a Xiangqi position.
    var conceals: Bool { self == .jieqi }
}

nonisolated enum EndReason: String, Codable, Sendable {
    case none, checkmate, stalemate
    case threefoldRepetition = "threefold-repetition"
    case perpetualCheck = "perpetual-check"
    case perpetualChase = "perpetual-chase"
    case mutualPerpetualCheck = "mutual-perpetual-check"
    case mutualPerpetualChase = "mutual-perpetual-chase"
    case fiftyMoveRule = "fifty-move-rule"
    case resignation
    case endedEarly = "ended-early"
    /// Jieqi's no-capture draw, a reason of its own rather than Xiangqi's
    /// fifty under another name.
    case fortyMoveRule = "forty-move-rule"
    /// The two ends two players declare to each other, in networked play only.
    case agreedDraw = "agreed-draw"
    case mutualResignation = "mutual-resignation"
    /// The placement games' two, and theirs alone.
    case fiveInARow = "five-in-a-row"
    case boardFull = "board-full"

    init(_ reason: MxqEndReason) {
        switch reason {
        case MxqEndReason(MXQ_END_REASON_CHECKMATE): self = .checkmate
        case MxqEndReason(MXQ_END_REASON_STALEMATE): self = .stalemate
        case MxqEndReason(MXQ_END_REASON_THREEFOLD_REPETITION): self = .threefoldRepetition
        case MxqEndReason(MXQ_END_REASON_PERPETUAL_CHECK): self = .perpetualCheck
        case MxqEndReason(MXQ_END_REASON_PERPETUAL_CHASE): self = .perpetualChase
        case MxqEndReason(MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK): self = .mutualPerpetualCheck
        case MxqEndReason(MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE): self = .mutualPerpetualChase
        case MxqEndReason(MXQ_END_REASON_FIFTY_MOVE_RULE): self = .fiftyMoveRule
        case MxqEndReason(MXQ_END_REASON_FORTY_MOVE_RULE): self = .fortyMoveRule
        case MxqEndReason(MXQ_END_REASON_FIVE_IN_A_ROW): self = .fiveInARow
        case MxqEndReason(MXQ_END_REASON_BOARD_FULL): self = .boardFull
        default: self = .none
        }
    }
}

nonisolated enum AiLevel: String, Codable, Sendable, Hashable, CaseIterable {
    case fast, standard, deep

    var movetimeMilliseconds: UInt32 {
        switch self {
        case .fast: 1000
        case .standard: 3000
        case .deep: 5000
        }
    }

    /// The name the Settings default is stored under.
    var name: String { rawValue }

    init?(name: String) { self.init(rawValue: name) }
}

nonisolated enum FirstMoverChoice: String, Sendable, Hashable, CaseIterable {
    case humanFirst = "human-first"
    case aiFirst = "ai-first"
    case random

    /// The name the Settings default is stored under.
    var name: String { rawValue }

    init?(name: String) { self.init(rawValue: name) }
}

/// What a new game is created as. Free Play and networked play carry no AI
/// configuration, and only networked play carries a local side.
nonisolated struct GameConfiguration: Sendable, Hashable {
    var game: GameKind
    var mode: PlayMode
    /// The *resolved* human side — set even when the choice was 随机.
    var humanSide: Side?
    var aiLevel: AiLevel?
    /// The side this device's player took, in a networked game and nowhere else.
    var localSide: Side?

    /// The position the game begins from, where it is not the game's own frozen
    /// start. A composed start is Free Play's, and a dealt start is Jieqi's in
    /// every mode.
    var startFEN: String?

    /// The thinking time the AI's every search runs for, in human-versus-AI
    /// play; zero elsewhere.
    var movetimeMilliseconds: UInt32 { aiLevel?.movetimeMilliseconds ?? 0 }

    static func freePlay(game: GameKind, startFEN: String? = nil) -> GameConfiguration {
        GameConfiguration(game: game, mode: .freePlay, startFEN: startFEN)
    }

    /// A game with the other device over the BoardGame protocol. `startFEN` is
    /// the dealt start, which both devices derive from the handshake.
    static func nearby(game: GameKind, localSide: Side,
                       startFEN: String? = nil) -> GameConfiguration {
        GameConfiguration(game: game, mode: .nearby, localSide: localSide,
                          startFEN: startFEN)
    }

    /// The same game, the two devices having reached each other at a distance.
    static func online(game: GameKind, localSide: Side,
                       startFEN: String? = nil) -> GameConfiguration {
        GameConfiguration(game: game, mode: .online, localSide: localSide,
                          startFEN: startFEN)
    }

    /// A human-versus-AI game, with the first-mover choice already resolved to
    /// a side.
    static func humanVersusAI(game: GameKind, humanSide: Side,
                              level: AiLevel) -> GameConfiguration {
        GameConfiguration(game: game, mode: .humanVersusAI, humanSide: humanSide,
                          aiLevel: level)
    }

    private init(game: GameKind, mode: PlayMode, humanSide: Side? = nil,
                 aiLevel: AiLevel? = nil, localSide: Side? = nil,
                 startFEN: String? = nil) {
        self.game = game
        self.mode = mode
        self.humanSide = humanSide
        self.aiLevel = aiLevel
        self.localSide = localSide
        self.startFEN = startFEN
    }
}

/// Which setup rule a position breaks, as the core reports it. A closed class
/// vocabulary and never a sentence: the sentence is the frontend's to localize.
nonisolated enum SetupRule: Sendable, Equatable {
    case pieceCount, palace, elephantSide, soldierRank
    case facingGenerals, opponentInCheck, notFrozenStart

    init?(_ rule: MxqSetupRule) {
        switch rule {
        case MxqSetupRule(MXQ_SETUP_RULE_PIECE_COUNT): self = .pieceCount
        case MxqSetupRule(MXQ_SETUP_RULE_PALACE): self = .palace
        case MxqSetupRule(MXQ_SETUP_RULE_ELEPHANT_SIDE): self = .elephantSide
        case MxqSetupRule(MXQ_SETUP_RULE_SOLDIER_RANK): self = .soldierRank
        case MxqSetupRule(MXQ_SETUP_RULE_FACING_GENERALS): self = .facingGenerals
        case MxqSetupRule(MXQ_SETUP_RULE_OPPONENT_IN_CHECK): self = .opponentInCheck
        case MxqSetupRule(MXQ_SETUP_RULE_NOT_FROZEN_START): self = .notFrozenStart
        default: return nil
        }
    }
}

/// Why a position is not one to set up in: the first violation the core found,
/// whose it is, and where.
nonisolated struct SetupViolation: Sendable, Equatable {
    var rule: SetupRule
    /// The side the violation belongs to; absent where it belongs to neither.
    var side: Side?
    /// The point at fault; empty where the class names none.
    var square: String
}

/// What the core says about a position offered as a game's first one.
nonisolated enum SetupVerdict: Sendable, Equatable {
    /// A position this game may be set up in. Whether it is one to *play* is
    /// the separate question `Core.isPlayable` asks.
    case legal
    /// The predicate refused it, and this is the first rule it broke.
    case illegal(SetupViolation)
    /// Not a position of this game's board at all.
    case malformed
}

/// A position and the rules' verdict on the line that reached it.
nonisolated struct Evaluation: Sendable {
    var fen: String
    var sideToMove: Side
    var inCheck: Bool
    var plyCount: Int
    var state: GameState
    var reason: EndReason
    /// The occurrence a repetition-based outcome attached at; 0 otherwise.
    var atOccurrence: Int

    var isOver: Bool { state.isOver }
    /// The neutral repetition, which is the player's to claim.
    var claimAvailable: Bool { state == .claimableDraw }
}

// MARK: - Plumbing shared by every call into the core

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

nonisolated func check(_ status: MxqStatus, _ err: MxqError) throws {
    guard status != MXQ_OK else { return }
    throw CoreError(status: status, detail: string(of: err.detail, capacity: MXQ_DETAIL_CAP))
}

/// A move line as the C array of borrowed strings the rules entries take.
nonisolated func withCStrings<T>(_ strings: [String],
                                 _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> T) -> T {
    let copies = strings.map { strdup($0) }
    defer { copies.forEach { free($0) } }
    let pointers = copies.map { UnsafePointer($0) }
    return pointers.withUnsafeBufferPointer { body(pointers.isEmpty ? nil : $0.baseAddress) }
}

/// The process-wide core. Singleton because the core is: the engines' state is
/// process-global, so a second `mxq_core_init` before shutdown is an error.
final class Core {
    let handle: OpaquePointer

    /// Whether `shared` was ever asked for, so that termination can shut down
    /// a core that exists without creating one that does not.
    private static var sharedWasCreated = false

    static let shared: Result<Core, CoreError> = {
        sharedWasCreated = true
        do {
            return .success(try Core())
        } catch {
            return .failure(CoreError(wrapping: error))
        }
    }()

    /// Best-effort teardown at termination.
    static func shutdownSharedIfLive() {
        guard sharedWasCreated, case .success(let core) = shared else { return }
        core.shutdown()
    }

    init() throws {
        // Missing or unopenable assets are a packaging failure, surfaced here
        // rather than at the first move.
        let assets: String
        do {
            assets = try EngineAssets.directory().path
        } catch {
            throw CoreError(status: MxqStatus(MXQ_ERR_ENGINE_ASSET_MISSING),
                            detail: "cannot open the engine assets: \(error)")
        }
        var handle: OpaquePointer?
        var err = freshError()
        try assets.withCString { assetPath in
            var config = MxqCoreConfig()
            config.struct_size = UInt32(MemoryLayout<MxqCoreConfig>.size)
            config.asset_directory = assetPath
            try check(mxq_core_init(&config, &handle, &err), err)
        }
        guard let handle else {
            throw CoreError(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                            detail: "mxq_core_init reported success without a core")
        }
        self.handle = handle
    }

    /// Drains the engine queue first: a prepare or teardown can still be
    /// running there when the player quits, and the core asserts on a handle
    /// that is no longer the live instance.
    func shutdown() {
        quiesceEngineWork()
        mxq_core_shutdown(handle, nil)
    }

    // MARK: - The ruleset's constants

    /// One game's frozen starting FEN, where its rules freeze one. `nil` is a
    /// game whose rules freeze no start: Jieqi begins from a deal, and the core
    /// says so with `MXQ_ERR_ARG_RANGE`.
    nonisolated static func frozenStartFEN(for game: GameKind) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MXQ_FEN_CAP))
        var length = 0
        let status = mxq_rules_start_fen(game.raw, &buffer, buffer.count, &length, nil)
        guard status != MxqStatus(MXQ_ERR_ARG_RANGE) else { return nil }
        precondition(status == MXQ_OK, "the starting FEN does not fit MXQ_FEN_CAP")
        return String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)),
                      as: UTF8.self)
    }

    /// The position a game begins from: its own start where it names one, the
    /// game's frozen start where it does not. Empty for a game that has
    /// neither, which no position is, so every rules question about it is
    /// refused rather than answered about some other board.
    nonisolated static func start(of game: GameKind, setup: String?) -> String {
        setup ?? frozenStartFEN(for: game) ?? ""
    }

    // MARK: - The deal

    /// One deal: the dealt start a game of it begins from, the commitment the
    /// seed binds to, and the deal's own digest.
    nonisolated struct Deal: Sendable, Hashable {
        var startFEN: String
        var commit: String
        var digest: String
    }

    /// Deals one game of Jieqi from a 32-byte seed and nonce drawn from the
    /// platform's cryptographic source. If they cannot be drawn, no game is
    /// created; nothing weaker stands in.
    func deal(_ game: GameKind) throws -> Deal {
        var deal = MxqDeal()
        deal.struct_size = UInt32(MemoryLayout<MxqDeal>.size)
        var err = freshError()
        let seed = try Self.entropy()
        let nonce = try Self.entropy()
        try check(seed.withCString { seed in
            nonce.withCString { nonce in
                mxq_rules_deal(handle, game.raw, seed, nonce, &deal, &err)
            }
        }, err)
        return Deal(startFEN: string(of: deal.start_fen, capacity: MXQ_FEN_CAP),
                    commit: string(of: deal.commit, capacity: MXQ_DEAL_HEX_CAP),
                    digest: string(of: deal.digest, capacity: MXQ_DEAL_HEX_CAP))
    }

    private nonisolated static func entropy() throws -> String {
        guard let value = DealHex.contribution() else {
            throw CoreError(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                            detail: "the cryptographic source refused")
        }
        return value
    }

    // MARK: - The questions a position is asked

    /// The core's setup-legality predicate. Nothing composed or imported may
    /// reach an engine without passing it: a position offering a general
    /// capture trips an engine assertion.
    func setupVerdict(of fen: String, game: GameKind) -> SetupVerdict {
        var violation = MxqSetupViolation()
        violation.struct_size = UInt32(MemoryLayout<MxqSetupViolation>.size)
        var err = freshError()
        let status = fen.withCString {
            mxq_rules_validate_setup(handle, game.raw, $0, &violation, &err)
        }
        switch status {
        case MxqStatus(MXQ_OK):
            return .legal
        case MxqStatus(MXQ_ERR_RULES_ILLEGAL_POSITION):
            guard let rule = SetupRule(violation.rule) else { return .malformed }
            return .illegal(SetupViolation(rule: rule,
                                           side: Side(violation.side),
                                           square: string(of: violation.square,
                                                          capacity: MXQ_SQUARE_TEXT_CAP)))
        default:
            return .malformed
        }
    }

    /// Whether a position the predicate accepted is one to **play**: a position
    /// that already has a result of its own is no game to begin. Asked only of
    /// a position `setupVerdict(of:game:)` has accepted.
    func isPlayable(_ fen: String, game: GameKind) -> Bool {
        guard let evaluation = try? evaluate(game, from: fen, moves: []) else { return false }
        return !evaluation.isOver
    }

    /// One buffer wide enough for the legal moves of every game this app plays:
    /// a placement game's legal moves are at most its empty points, so the
    /// placement board's point count is the bound.
    nonisolated static let legalMoveCapacity = GameKind.gomoku15.board.squareCount

    // MARK: - A line, asked of the rules

    /// The position `moves` reach from `start`, and the rules' verdict on the
    /// line. A move that is not legal at its turn is
    /// `MXQ_ERR_RULES_INVALID_HISTORY`, with its index in the error's detail.
    func evaluate(_ game: GameKind, from start: String, moves: [String]) throws -> Evaluation {
        try Self.evaluate(handle, game, from: start, moves: moves)
    }

    /// The legal moves at the end of the line.
    func legalMoves(_ game: GameKind, from start: String, moves: [String]) throws -> [String] {
        try Self.legalMoves(handle, game, from: start, moves: moves)
    }

    /// The same two questions over a bare handle, for the values that ask them
    /// off the main actor: the core's rules entries are callable from any
    /// thread but a search callback.
    nonisolated static func evaluate(_ core: OpaquePointer, _ game: GameKind,
                                     from start: String, moves: [String]) throws -> Evaluation {
        var position = MxqPosition()
        position.struct_size = UInt32(MemoryLayout<MxqPosition>.size)
        var status = MxqGameStatus()
        status.struct_size = UInt32(MemoryLayout<MxqGameStatus>.size)
        var err = freshError()
        try check(withCStrings(moves) { texts in
            mxq_rules_evaluate(core, game.raw, start, texts, moves.count,
                               &position, &status, nil, &err)
        }, err)
        guard let side = Side(position.side_to_move) else {
            throw CoreError(status: MxqStatus(MXQ_ERR_INTERNAL_INVARIANT),
                            detail: "the core reported no side to move")
        }
        return Evaluation(fen: string(of: position.fen, capacity: MXQ_FEN_CAP),
                          sideToMove: side,
                          inCheck: position.in_check != 0,
                          plyCount: Int(position.ply_count),
                          state: GameState(status.state),
                          reason: EndReason(status.reason),
                          atOccurrence: Int(status.at_occurrence))
    }

    nonisolated static func legalMoves(_ core: OpaquePointer, _ game: GameKind,
                                       from start: String, moves: [String]) throws -> [String] {
        var buffer = [MxqMove](repeating: MxqMove(), count: legalMoveCapacity)
        var count = 0
        var err = freshError()
        try check(withCStrings(moves) { texts in
            mxq_rules_legal_moves(core, game.raw, start, texts, moves.count,
                                  &buffer, buffer.count, &count, &err)
        }, err)
        return buffer.prefix(count).map { string(of: $0.text, capacity: MXQ_MOVE_TEXT_CAP) }
    }
}
