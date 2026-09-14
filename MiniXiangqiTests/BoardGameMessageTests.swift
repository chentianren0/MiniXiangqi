// The wire format, read strictly.
//
// Every expectation here is docs/boardgame-protocol-v2.md's own: one object
// with exactly one member, whose value holds exactly the named fields, `end`
// and `deal_digest` the only omissible two. The malformed cases are the ones a
// lenient decoder would wave through, so each is written as the bytes a peer
// would actually send.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The BoardGame Protocol's messages")
struct BoardGameMessageTests {

    private func decode(_ json: String) throws -> BoardGameMessage {
        try JSONDecoder().decode(BoardGameMessage.self, from: Data(json.utf8))
    }

    /// The message's bytes, as a comparable object tree.
    private func encoded(_ message: BoardGameMessage) throws -> NSDictionary {
        let bytes = try JSONEncoder().encode(message)
        return try #require(try JSONSerialization.jsonObject(with: bytes) as? NSDictionary)
    }

    private func object(_ json: String) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
    }

    /// The message decodes from exactly those bytes and encodes back to them.
    private func roundTrip(_ message: BoardGameMessage, _ json: String) throws {
        #expect(try decode(json) == message)
        #expect(try encoded(message) == (try object(json)))
    }

    /// The corpus's dealt-start vector, which is where every handshake value
    /// written out below comes from: one seed, one nonce, and the commitment
    /// and digest the core derives from them.
    private static let seed = String(repeating: "0", count: 64)
    private static let nonce =
        "a144410000000000000000000000000000000000000000000000000000000000"
    private static let commit =
        "66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925"
    private static let digest =
        "98ec20c5cd254471f1b321de793bdb85683135b940e2a00558228637ea001baa"

    // MARK: - The fourteen

    @Test("hello carries the protocol version")
    func helloRoundTrips() throws {
        try roundTrip(.hello(.init()), #"{"hello":{"protocol":2}}"#)
    }

    @Test("propose carries the session, the game, its version, and which mover the proposer takes")
    func proposeRoundTrips() throws {
        try roundTrip(.propose(.init(session: "0b34", rulesID: "minixiangqi",
                                     rulesVersion: "1", proposerMoves: .second)),
                      #"{"propose":{"session":"0b34","rules_id":"minixiangqi","rules_version":"1","proposer_moves":"second"}}"#)
    }

    @Test("accept carries the session alone")
    func acceptRoundTrips() throws {
        try roundTrip(.accept(.init(session: "0b34")), #"{"accept":{"session":"0b34"}}"#)
    }

    @Test("decline carries one of the six reasons")
    func declineRoundTrips() throws {
        try roundTrip(.decline(.init(session: "0b34", reason: .unknownGame)),
                      #"{"decline":{"session":"0b34","reason":"unknown_game"}}"#)
        try roundTrip(.decline(.init(session: "0b34", reason: .rulesMismatch)),
                      #"{"decline":{"session":"0b34","reason":"rules_mismatch"}}"#)
        try roundTrip(.decline(.init(session: "0b34", reason: .unknownSession)),
                      #"{"decline":{"session":"0b34","reason":"unknown_session"}}"#)
        try roundTrip(.decline(.init(session: "0b34", reason: .busy)),
                      #"{"decline":{"session":"0b34","reason":"busy"}}"#)
        try roundTrip(.decline(.init(session: "0b34", reason: .declined)),
                      #"{"decline":{"session":"0b34","reason":"declined"}}"#)
        try roundTrip(.decline(.init(session: "0b34", reason: .dealMismatch)),
                      #"{"decline":{"session":"0b34","reason":"deal_mismatch"}}"#)
    }

    @Test("the handshake's three carry the session and one value each")
    func theHandshakeRoundTrips() throws {
        try roundTrip(.dealCommit(.init(session: "0b34", commit: Self.commit)),
                      #"{"deal_commit":{"session":"0b34","commit":"\#(Self.commit)"}}"#)
        try roundTrip(.dealNonce(.init(session: "0b34", nonce: Self.nonce)),
                      #"{"deal_nonce":{"session":"0b34","nonce":"\#(Self.nonce)"}}"#)
        try roundTrip(.dealSeed(.init(session: "0b34", seed: Self.seed)),
                      #"{"deal_seed":{"session":"0b34","seed":"\#(Self.seed)"}}"#)
    }

    @Test("move carries the ply's index and its text")
    func moveRoundTrips() throws {
        try roundTrip(.move(.init(session: "0b34", index: 7, move: "b1b3")),
                      #"{"move":{"session":"0b34","index":7,"move":"b1b3"}}"#)
    }

    @Test("the claim travels as an ordinary indexed move")
    func claimRoundTrips() throws {
        try roundTrip(.move(.init(session: "0b34", index: 8, move: "claim")),
                      #"{"move":{"session":"0b34","index":8,"move":"claim"}}"#)
    }

    @Test("offer_draw and accept_draw")
    func drawRoundTrips() throws {
        try roundTrip(.offerDraw(.init(session: "0b34", at: 12)),
                      #"{"offer_draw":{"session":"0b34","at":12}}"#)
        try roundTrip(.acceptDraw(.init(session: "0b34")),
                      #"{"accept_draw":{"session":"0b34"}}"#)
    }

    @Test("request_undo and accept_undo")
    func undoRoundTrips() throws {
        try roundTrip(.requestUndo(.init(session: "0b34", at: 12, keep: 10)),
                      #"{"request_undo":{"session":"0b34","at":12,"keep":10}}"#)
        try roundTrip(.acceptUndo(.init(session: "0b34")),
                      #"{"accept_undo":{"session":"0b34"}}"#)
    }

    @Test("resign carries the session alone")
    func resignRoundTrips() throws {
        try roundTrip(.resign(.init(session: "0b34")), #"{"resign":{"session":"0b34"}}"#)
    }

    @Test("resume states the session, and carries end only when the sender has sent one")
    func resumeRoundTrips() throws {
        try roundTrip(.resume(.init(session: "0b34", undos: 0, count: 12, keep: 12, end: nil)),
                      #"{"resume":{"session":"0b34","undos":0,"count":12,"keep":12}}"#)
        try roundTrip(.resume(.init(session: "0b34", undos: 2, count: 9, keep: 6, end: .resign)),
                      #"{"resume":{"session":"0b34","undos":2,"count":9,"keep":6,"end":"resign"}}"#)
        try roundTrip(.resume(.init(session: "0b34", undos: 1, count: 4, keep: 4, end: .acceptDraw)),
                      #"{"resume":{"session":"0b34","undos":1,"count":4,"keep":4,"end":"accept_draw"}}"#)
    }

    @Test("resume carries deal_digest for a hidden-information session and not otherwise")
    func resumeCarriesTheDigest() throws {
        try roundTrip(.resume(.init(session: "0b34", undos: 0, count: 3, keep: 3,
                                    end: nil, dealDigest: Self.digest)),
                      #"{"resume":{"session":"0b34","undos":0,"count":3,"keep":3,"deal_digest":"\#(Self.digest)"}}"#)
        try roundTrip(.resume(.init(session: "0b34", undos: 0, count: 3, keep: 3,
                                    end: .resign, dealDigest: Self.digest)),
                      #"{"resume":{"session":"0b34","undos":0,"count":3,"keep":3,"end":"resign","deal_digest":"\#(Self.digest)"}}"#)
    }

    // MARK: - Malformed

    @Test("an extra field in a message is malformed")
    func anExtraFieldIsMalformed() throws {
        #expect(throws: DecodingError.self) {
            try decode(#"{"accept":{"session":"0b34","spare":1}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"resign":{"session":"0b34","end":"resign"}}"#)
        }
    }

    @Test("a missing field is malformed")
    func aMissingFieldIsMalformed() throws {
        #expect(throws: DecodingError.self) {
            try decode(#"{"move":{"session":"0b34","index":7}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"resume":{"session":"0b34","undos":0,"count":3}}"#)
        }
        #expect(throws: DecodingError.self) { try decode(#"{"hello":{}}"#) }
    }

    @Test("a second top-level member is malformed, known name or not")
    func aSecondMemberIsMalformed() throws {
        #expect(throws: DecodingError.self) {
            try decode(#"{"accept":{"session":"0b34"},"resign":{"session":"0b34"}}"#)
        }
        // The one a decoder that only knows its own keys would wave through.
        #expect(throws: DecodingError.self) {
            try decode(#"{"accept":{"session":"0b34"},"spare":1}"#)
        }
    }

    @Test("an unknown message name is malformed")
    func anUnknownNameIsMalformed() throws {
        #expect(throws: DecodingError.self) { try decode(#"{"rematch":{"session":"0b34"}}"#) }
        #expect(throws: DecodingError.self) { try decode("{}") }
    }

    @Test("a field of the wrong type is malformed")
    func aWrongTypeIsMalformed() throws {
        #expect(throws: DecodingError.self) {
            try decode(#"{"move":{"session":"0b34","index":"7","move":"b1b3"}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"move":{"session":7,"index":7,"move":"b1b3"}}"#)
        }
        #expect(throws: DecodingError.self) { try decode(#"{"hello":{"protocol":true}}"#) }
        // A message's value is an object, never a bare value.
        #expect(throws: DecodingError.self) { try decode(#"{"resign":"0b34"}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"accept":[]}"#) }
    }

    @Test("a negative count is malformed")
    func aNegativeCountIsMalformed() throws {
        #expect(throws: DecodingError.self) {
            try decode(#"{"move":{"session":"0b34","index":-1,"move":"b1b3"}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"offer_draw":{"session":"0b34","at":-3}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"request_undo":{"session":"0b34","at":4,"keep":-1}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"resume":{"session":"0b34","undos":-1,"count":3,"keep":3}}"#)
        }
    }

    @Test("a word outside its vocabulary is malformed")
    func anUnknownWordIsMalformed() throws {
        #expect(throws: DecodingError.self) {
            try decode(#"{"decline":{"session":"0b34","reason":"nope"}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"propose":{"session":"0b34","rules_id":"minixiangqi","rules_version":"1","proposer_moves":"third"}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"resume":{"session":"0b34","undos":0,"count":3,"keep":3,"end":"withdraw"}}"#)
        }
    }

    @Test("a handshake value that is not sixty-four lowercase hexadecimal digits is malformed")
    func aMalformedHandshakeValueIsRefused() throws {
        // The same thirty-two bytes in capitals. It is another string, and the
        // spelling is part of the value rather than a way of writing it.
        let shouted = Self.commit.uppercased()
        #expect(throws: DecodingError.self) {
            try decode(#"{"deal_commit":{"session":"0b34","commit":"\#(shouted)"}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"deal_nonce":{"session":"0b34","nonce":"\#(Self.nonce.dropLast())"}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"deal_seed":{"session":"0b34","seed":"\#(Self.seed)0"}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"deal_seed":{"session":"0b34","seed":"\#(Self.seed.dropLast())g"}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(#"{"resume":{"session":"0b34","undos":0,"count":3,"keep":3,"deal_digest":"\#(shouted)"}}"#)
        }
    }

    @Test("hello reads a version this peer does not speak, so the engine can refuse it")
    func helloReadsAnyVersion() throws {
        #expect(try decode(#"{"hello":{"protocol":1}}"#) == .hello(.init(protocolVersion: 1)))
    }
}
