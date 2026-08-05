// The wire format, read strictly.
//
// Every expectation here is docs/boardgame-protocol.md's own: one object with
// exactly one member, whose value holds exactly the named fields, `end` alone
// omissible. The malformed cases are the ones a lenient decoder would wave
// through, so each is written as the bytes a peer would actually send.

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

    // MARK: - The eleven

    @Test("hello carries the protocol version")
    func helloRoundTrips() throws {
        try roundTrip(.hello(.init()), #"{"hello":{"protocol":1}}"#)
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

    @Test("decline carries one of the five reasons")
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

    @Test("hello reads a version this peer does not speak, so the engine can refuse it")
    func helloReadsAnyVersion() throws {
        #expect(try decode(#"{"hello":{"protocol":2}}"#) == .hello(.init(protocolVersion: 2)))
    }
}
