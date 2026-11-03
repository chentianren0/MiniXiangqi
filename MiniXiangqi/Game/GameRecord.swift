// One game, as the library keeps it and as a game file carries it.
//
// The game in play is the record without a result; a finished game is a
// History record. Both are this one model, and the moves are the whole of the
// game: every position, every verdict and every reading is the core's replay of
// them from the record's start.
//
// A game file is the record encoded as JSON. It carries the game's own facts
// and none of the library's: whether it is pinned, whether it was imported,
// which side this device's player took and what a networked game needs to
// resume stay on this device.
//
// A networked game has the same id on both devices: the proposer mints it.

import Foundation
import SwiftData

@Model
final class GameRecord {
    @Attribute(.unique) var id: UUID
    var kind: GameKind
    var mode: PlayMode
    /// The human's resolved side and the AI's level, in human-versus-AI play.
    var humanSide: Side?
    var aiLevel: AiLevel?
    /// The position the game began from, where it is not the game's frozen
    /// start: a composed Xiangqi scene, or a Jieqi deal.
    var setup: String?
    var moves: [String]
    /// Nil while the game is in play; `reason` and `endedAt` are set with it.
    var result: Outcome?
    var reason: EndReason?
    var startedAt: Date
    var endedAt: Date?
    var pinned: Bool
    /// Whether the record came from a game file rather than being played here.
    var imported: Bool
    /// The side this device's player took, in a networked game played here.
    var localSide: Side?
    /// The other device in a networked game: its install's id on Nearby, the
    /// Game Center player id on Online.
    var peer: String?
    /// The line length each accepted takeback kept, in order.
    var takebacks: [Int] = []
    /// The moves on the board when a player chose the ending, which can be
    /// more than this device holds until the last of them arrives. Nil for a
    /// result the rules decided.
    var chosenAt: Int?
    /// An ending this device's player chose, written before it was sent, that
    /// the other device has not yet shown it holds.
    var endingUndelivered = false

    init(_ configuration: GameConfiguration, id: UUID = UUID(), startedAt: Date = .now) {
        self.id = id
        kind = configuration.game
        mode = configuration.mode
        humanSide = configuration.humanSide
        aiLevel = configuration.aiLevel
        localSide = configuration.localSide
        // The frozen start spelled out is the frozen start, so one game reads
        // back one way however its start was named.
        setup = configuration.startFEN == Core.frozenStartFEN(for: configuration.game)
            ? nil : configuration.startFEN
        moves = []
        self.startedAt = startedAt
        pinned = false
        imported = false
    }

    /// The position the moves are replayed from.
    var start: String { Core.start(of: kind, setup: setup) }

    var configuration: GameConfiguration {
        switch mode {
        case .humanVersusAI:
            .humanVersusAI(game: kind, humanSide: humanSide ?? .red, level: aiLevel ?? .standard)
        case .freePlay:
            .freePlay(game: kind, startFEN: setup)
        case .nearby:
            .nearby(game: kind, localSide: localSide ?? .red, startFEN: setup)
        case .online:
            .online(game: kind, localSide: localSide ?? .red, startFEN: setup)
        }
    }

    var isFinished: Bool { result != nil }

    func end(_ outcome: Outcome, _ reason: EndReason, at date: Date = .now) {
        result = outcome
        self.reason = reason
        endedAt = date
    }

    // MARK: - The game file

    /// The version of the file format this build writes and the newest it
    /// reads.
    static let fileVersion = 1

    enum CodingKeys: String, CodingKey {
        case version, id, kind, mode, humanSide, aiLevel, setup, moves
        case result, reason, startedAt, endedAt
    }

    /// A file written by a newer version of the app.
    struct NewerVersion: Error {}

    /// A file written by a 3.x version of the app, which spelled a game in
    /// another format altogether.
    struct EarlierVersion: Error {}

    /// The one member every 3.x file carries.
    private struct EarlierFile: Decodable {
        var archiveVersion: Int

        enum CodingKeys: String, CodingKey {
            case archiveVersion = "archive_version"
        }
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .version) <= Self.fileVersion else {
            throw NewerVersion()
        }
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(GameKind.self, forKey: .kind)
        mode = try container.decode(PlayMode.self, forKey: .mode)
        humanSide = try container.decodeIfPresent(Side.self, forKey: .humanSide)
        aiLevel = try container.decodeIfPresent(AiLevel.self, forKey: .aiLevel)
        setup = try container.decodeIfPresent(String.self, forKey: .setup)
        moves = try container.decode([String].self, forKey: .moves)
        result = try container.decodeIfPresent(Outcome.self, forKey: .result)
        reason = try container.decodeIfPresent(EndReason.self, forKey: .reason)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        pinned = false
        imported = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.fileVersion, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(humanSide, forKey: .humanSide)
        try container.encodeIfPresent(aiLevel, forKey: .aiLevel)
        try container.encodeIfPresent(setup, forKey: .setup)
        try container.encode(moves, forKey: .moves)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
    }

    /// The record as a game file.
    func fileData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// A game file as a record, not yet in any library and not yet checked
    /// against the rules.
    static func decoding(file data: Data) throws -> GameRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(GameRecord.self, from: data)
        } catch let error as DecodingError {
            if (try? decoder.decode(EarlierFile.self, from: data)) != nil {
                throw EarlierVersion()
            }
            throw error
        }
    }
}

extension GameRecord: Codable {}
