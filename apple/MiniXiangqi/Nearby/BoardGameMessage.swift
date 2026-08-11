// The BoardGame Protocol's eleven messages, and the strict codec that is the
// only way in or out of them.
//
// docs/boardgame-protocol.md is binding, and this file implements its wire
// paragraph literally: one JSON object with exactly one member, the message's
// name, whose value is an object holding exactly its named fields — `end` alone
// may be omitted. An extra member, a missing one, a second top-level member, a
// wrong type, a negative count, or a name this version does not know is
// malformed, and malformed is a protocol violation rather than something to
// skip.
//
// Every container is therefore read through a key type that accepts any name.
// JSONDecoder's strictness stops at the keys its `CodingKey` type can spell:
// an unknown member alongside a valid one would decode as though the sender had
// never written it, which is exactly the message this protocol has to refuse.
//
// These are also the types the Network framework's JSON coder will carry, so
// the `Codable` conformance itself is the wire format and nothing composes the
// bytes a second time.

import Foundation

/// Which of a game's two movers a peer is. The protocol names no colours: the
/// mapping from movers to whatever the game calls them belongs to its
/// `rules_id`.
nonisolated enum Mover: String, Codable, Sendable, CaseIterable {
    case first, second

    var opponent: Mover { self == .first ? .second : .first }

    /// Whose ply the given index is. Plies are numbered from zero, so the first
    /// mover holds the even ones.
    static func atPly(_ index: Int) -> Mover {
        index.isMultiple(of: 2) ? .first : .second
    }
}

/// The closed reason vocabulary a `decline` carries.
nonisolated enum DeclineReason: String, Codable, Sendable, CaseIterable {
    case declined
    case unknownGame = "unknown_game"
    case rulesMismatch = "rules_mismatch"
    case busy
    case unknownSession = "unknown_session"
}

/// A terminal one peer sent: the two ends that need a message, and exactly what
/// `resume` reports as `end`.
nonisolated enum Terminal: String, Codable, Sendable, CaseIterable {
    case resign
    case acceptDraw = "accept_draw"

    /// The message this terminal travels as, for a terminal that has been held
    /// rather than sent.
    func message(for session: String) -> BoardGameMessage {
        switch self {
        case .resign: .resign(.init(session: session))
        case .acceptDraw: .acceptDraw(.init(session: session))
        }
    }
}

/// One protocol message.
nonisolated enum BoardGameMessage: Sendable, Equatable {
    case hello(Hello)
    case propose(Propose)
    case accept(Accept)
    case decline(Decline)
    case move(Move)
    case offerDraw(OfferDraw)
    case acceptDraw(AcceptDraw)
    case requestUndo(RequestUndo)
    case acceptUndo(AcceptUndo)
    case resign(Resign)
    case resume(Resume)

    /// The one protocol version this peer speaks, announced by `hello`.
    static let version = 1

    /// The session every message but `hello` names.
    var session: String? {
        switch self {
        case .hello: nil
        case .propose(let message): message.session
        case .accept(let message): message.session
        case .decline(let message): message.session
        case .move(let message): message.session
        case .offerDraw(let message): message.session
        case .acceptDraw(let message): message.session
        case .requestUndo(let message): message.session
        case .acceptUndo(let message): message.session
        case .resign(let message): message.session
        case .resume(let message): message.session
        }
    }
}

extension BoardGameMessage {

    nonisolated struct Hello: Sendable, Equatable {
        /// The wire member is `protocol`, which Swift cannot spell.
        var protocolVersion: Int

        init(protocolVersion: Int = BoardGameMessage.version) {
            self.protocolVersion = protocolVersion
        }
    }

    nonisolated struct Propose: Sendable, Equatable {
        var session: String
        var rulesID: String
        var rulesVersion: String
        /// Which mover the proposer takes.
        var proposerMoves: Mover
    }

    nonisolated struct Accept: Sendable, Equatable {
        var session: String
    }

    nonisolated struct Decline: Sendable, Equatable {
        var session: String
        var reason: DeclineReason
    }

    nonisolated struct Move: Sendable, Equatable {
        var session: String
        /// The ply's own number, which is the sender's `count` when it sent it.
        var index: Int
        /// A move in the game's own grammar; the receiver's rules judge it.
        var move: String
    }

    nonisolated struct OfferDraw: Sendable, Equatable {
        var session: String
        /// The sender's `count` when it sent this.
        var at: Int
    }

    nonisolated struct AcceptDraw: Sendable, Equatable {
        var session: String
    }

    nonisolated struct RequestUndo: Sendable, Equatable {
        var session: String
        var at: Int
        /// The plies to survive the retraction: 0 is the initial position, and
        /// the highest lawful value is one less than the sender's `count`.
        var keep: Int
    }

    nonisolated struct AcceptUndo: Sendable, Equatable {
        var session: String
    }

    nonisolated struct Resign: Sendable, Equatable {
        var session: String
    }

    nonisolated struct Resume: Sendable, Equatable {
        var session: String
        var undos: Int
        var count: Int
        /// The surviving count of the last accepted retraction; the sender's
        /// own `count` when `undos` is zero.
        var keep: Int
        /// The terminal the sender has sent for this session, absent when it
        /// has sent none.
        var end: Terminal?
    }
}

// MARK: - The wire format

extension BoardGameMessage: Codable {

    /// The eleven names, which are the only members a message object may have.
    fileprivate enum Name: String {
        case hello, propose, accept, decline, move
        case offerDraw = "offer_draw"
        case acceptDraw = "accept_draw"
        case requestUndo = "request_undo"
        case acceptUndo = "accept_undo"
        case resign, resume
    }

    init(from decoder: any Decoder) throws {
        let envelope = try decoder.container(keyedBy: WireKey.self)
        let members = envelope.allKeys
        guard members.count == 1, let member = members.first,
              let name = Name(rawValue: member.stringValue)
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "a message is one object with exactly one known member"))
        }
        let object = try envelope.nestedContainer(keyedBy: WireKey.self, forKey: member)

        switch name {
        case .hello:
            let fields = try WireObject(object, ["protocol"])
            self = .hello(Hello(protocolVersion: try fields.integer("protocol")))
        case .propose:
            let fields = try WireObject(object,
                                        ["session", "rules_id", "rules_version",
                                         "proposer_moves"])
            self = .propose(Propose(session: try fields.text("session"),
                                    rulesID: try fields.text("rules_id"),
                                    rulesVersion: try fields.text("rules_version"),
                                    proposerMoves: try fields.word("proposer_moves")))
        case .accept:
            let fields = try WireObject(object, ["session"])
            self = .accept(Accept(session: try fields.text("session")))
        case .decline:
            let fields = try WireObject(object, ["session", "reason"])
            self = .decline(Decline(session: try fields.text("session"),
                                    reason: try fields.word("reason")))
        case .move:
            let fields = try WireObject(object, ["session", "index", "move"])
            self = .move(Move(session: try fields.text("session"),
                              index: try fields.count("index"),
                              move: try fields.text("move")))
        case .offerDraw:
            let fields = try WireObject(object, ["session", "at"])
            self = .offerDraw(OfferDraw(session: try fields.text("session"),
                                        at: try fields.count("at")))
        case .acceptDraw:
            let fields = try WireObject(object, ["session"])
            self = .acceptDraw(AcceptDraw(session: try fields.text("session")))
        case .requestUndo:
            let fields = try WireObject(object, ["session", "at", "keep"])
            self = .requestUndo(RequestUndo(session: try fields.text("session"),
                                            at: try fields.count("at"),
                                            keep: try fields.count("keep")))
        case .acceptUndo:
            let fields = try WireObject(object, ["session"])
            self = .acceptUndo(AcceptUndo(session: try fields.text("session")))
        case .resign:
            let fields = try WireObject(object, ["session"])
            self = .resign(Resign(session: try fields.text("session")))
        case .resume:
            let fields = try WireObject(object, ["session", "undos", "count", "keep"],
                                        omissible: ["end"])
            self = .resume(Resume(session: try fields.text("session"),
                                  undos: try fields.count("undos"),
                                  count: try fields.count("count"),
                                  keep: try fields.count("keep"),
                                  end: try fields.wordIfPresent("end")))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var envelope = encoder.container(keyedBy: WireKey.self)

        switch self {
        case .hello(let message):
            var fields = envelope.object(Name.hello)
            try fields.encode(message.protocolVersion, forKey: WireKey("protocol"))
        case .propose(let message):
            var fields = envelope.object(Name.propose)
            try fields.encode(message.session, forKey: WireKey("session"))
            try fields.encode(message.rulesID, forKey: WireKey("rules_id"))
            try fields.encode(message.rulesVersion, forKey: WireKey("rules_version"))
            try fields.encode(message.proposerMoves, forKey: WireKey("proposer_moves"))
        case .accept(let message):
            var fields = envelope.object(Name.accept)
            try fields.encode(message.session, forKey: WireKey("session"))
        case .decline(let message):
            var fields = envelope.object(Name.decline)
            try fields.encode(message.session, forKey: WireKey("session"))
            try fields.encode(message.reason, forKey: WireKey("reason"))
        case .move(let message):
            var fields = envelope.object(Name.move)
            try fields.encode(message.session, forKey: WireKey("session"))
            try fields.encode(message.index, forKey: WireKey("index"))
            try fields.encode(message.move, forKey: WireKey("move"))
        case .offerDraw(let message):
            var fields = envelope.object(Name.offerDraw)
            try fields.encode(message.session, forKey: WireKey("session"))
            try fields.encode(message.at, forKey: WireKey("at"))
        case .acceptDraw(let message):
            var fields = envelope.object(Name.acceptDraw)
            try fields.encode(message.session, forKey: WireKey("session"))
        case .requestUndo(let message):
            var fields = envelope.object(Name.requestUndo)
            try fields.encode(message.session, forKey: WireKey("session"))
            try fields.encode(message.at, forKey: WireKey("at"))
            try fields.encode(message.keep, forKey: WireKey("keep"))
        case .acceptUndo(let message):
            var fields = envelope.object(Name.acceptUndo)
            try fields.encode(message.session, forKey: WireKey("session"))
        case .resign(let message):
            var fields = envelope.object(Name.resign)
            try fields.encode(message.session, forKey: WireKey("session"))
        case .resume(let message):
            var fields = envelope.object(Name.resume)
            try fields.encode(message.session, forKey: WireKey("session"))
            try fields.encode(message.undos, forKey: WireKey("undos"))
            try fields.encode(message.count, forKey: WireKey("count"))
            try fields.encode(message.keep, forKey: WireKey("keep"))
            try fields.encodeIfPresent(message.end, forKey: WireKey("end"))
        }
    }
}

private extension KeyedEncodingContainer where Key == WireKey {
    mutating func object(_ name: BoardGameMessage.Name) -> KeyedEncodingContainer<WireKey> {
        nestedContainer(keyedBy: WireKey.self, forKey: WireKey(name.rawValue))
    }
}

/// A coding key that accepts any member name, so `allKeys` reports what the
/// sender actually wrote rather than only the names this build can spell.
///
/// Shared with `NearbyFrame`, which reads the same single-member object this
/// does before deciding whose member it is. One strictness, written once.
nonisolated struct WireKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { nil }
}

/// One message's field object, read strictly: exactly the named members, each
/// of its stated type, and no integer below zero. `NearbyFrame` reads its own
/// one-field object through it, for the same reason.
nonisolated struct WireObject {
    private let fields: KeyedDecodingContainer<WireKey>
    private let path: [any CodingKey]

    init(_ fields: KeyedDecodingContainer<WireKey>,
         _ named: [String], omissible: [String] = []) throws {
        let present = Set(fields.allKeys.map(\.stringValue))
        let required = Set(named)
        guard required.isSubset(of: present),
              present.isSubset(of: required.union(omissible))
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: fields.codingPath,
                      debugDescription: "a message carries exactly its named fields"))
        }
        self.fields = fields
        self.path = fields.codingPath
    }

    func text(_ name: String) throws -> String {
        try fields.decode(String.self, forKey: WireKey(name))
    }

    /// An integer field with no further constraint. `protocol` is the only one:
    /// the contract calls the five counted fields non-negative and this one
    /// merely an integer, and a version outside what this peer speaks is
    /// answered by closing the connection rather than by refusing to read it.
    func integer(_ name: String) throws -> Int {
        try fields.decode(Int.self, forKey: WireKey(name))
    }

    /// One of the non-negative integers: `index`, `at`, `count`, `keep`,
    /// `undos`.
    func count(_ name: String) throws -> Int {
        let value = try integer(name)
        guard value >= 0 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: path,
                      debugDescription: "\(name) is a non-negative integer"))
        }
        return value
    }

    /// A field whose value is one word of a closed vocabulary.
    func word<Word>(_ name: String) throws -> Word
    where Word: RawRepresentable, Word.RawValue == String {
        guard let word = Word(rawValue: try text(name)) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: path,
                      debugDescription: "\(name) is outside its vocabulary"))
        }
        return word
    }

    func wordIfPresent<Word>(_ name: String) throws -> Word?
    where Word: RawRepresentable, Word.RawValue == String {
        guard fields.contains(WireKey(name)) else { return nil }
        return try word(name)
    }
}
