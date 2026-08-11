// What the transport puts on the wire, read as strictly as the protocol's own.
//
// Two claims are load-bearing here and neither is obvious from the type.
//
// The first is that **a game's bytes did not change** when the transport gained
// something of its own to say. A message inside a frame is encoded by the
// message, so the two encodings are compared byte for byte rather than argued
// about.
//
// The second is that **the refusal is untouched**. A member name no version
// knows still throws out of the decoder, which is what the connection layer
// reads as unreadable, which is malformed, which is a protocol violation. A
// frame that swallowed an unknown name would turn a violation into a shrug.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The transport's frames")
struct NearbyFrameTests {

    private func decode(_ json: String) throws -> NearbyFrame {
        try JSONDecoder().decode(NearbyFrame.self, from: Data(json.utf8))
    }

    private func bytes(_ frame: NearbyFrame) throws -> Data {
        try JSONEncoder().encode(frame)
    }

    /// An encoder whose member order is fixed.
    ///
    /// A JSON object's members have no order — the protocol's own document
    /// writes its examples in one and reads any — and `JSONEncoder` promises
    /// none either, so two encodings of one message can differ in the order of
    /// its fields and be the same message. Sorting the keys removes exactly
    /// that freedom and leaves everything else comparable byte for byte, which
    /// is what the claim below is about: whether the frame adds anything.
    private var canonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Every message shape the protocol has a distinct field set for: the empty
    /// one, the crowded one, the counted one, and the one with an omissible
    /// member.
    private static let messages: [BoardGameMessage] = [
        .hello(.init()),
        .propose(.init(session: "0b34", rulesID: "minixiangqi", rulesVersion: "1",
                       proposerMoves: .second)),
        .accept(.init(session: "0b34")),
        .decline(.init(session: "0b34", reason: .busy)),
        .move(.init(session: "0b34", index: 7, move: "b1b3")),
        .requestUndo(.init(session: "0b34", at: 8, keep: 6)),
        .resume(.init(session: "0b34", undos: 1, count: 8, keep: 6, end: .resign)),
        .resume(.init(session: "0b34", undos: 0, count: 8, keep: 8, end: nil)),
    ]

    // MARK: - The linkage

    @Test("A linkage frame carries the sender's identifier and nothing else")
    func aLinkageRoundTrips() throws {
        let json = #"{"peer":{"id":"9F3C1D2E"}}"#
        #expect(try decode(json) == .linkage(.init(id: "9F3C1D2E")))
        #expect(try bytes(.linkage(.init(id: "9F3C1D2E"))) == Data(json.utf8))
    }

    @Test("A linkage with anything more in it is refused, so no name can ever travel")
    func aLinkageCarriesExactlyItsOneField() throws {
        #expect(throws: (any Error).self) {
            try decode(#"{"peer":{"id":"9F3C","name":"somebody's iPhone"}}"#)
        }
        #expect(throws: (any Error).self) { try decode(#"{"peer":{}}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"peer":{"id":7}}"#) }
    }

    // MARK: - The messages

    @Test("A message inside a frame is byte for byte the message's own encoding")
    func aMessageIsExactlyTheMessagesBytes() throws {
        for message in Self.messages {
            #expect(try canonical.encode(NearbyFrame.message(message))
                    == (try canonical.encode(message)),
                    "the frame composes no bytes of its own around a message")
        }
    }

    @Test("A message's own bytes decode as the message they always were")
    func aMessagesBytesDecodeAsAMessage() throws {
        for message in Self.messages {
            let wire = try JSONEncoder().encode(message)
            #expect(try JSONDecoder().decode(NearbyFrame.self, from: wire) == .message(message))
        }
    }

    // MARK: - Refusal

    @Test("A member no version knows is still unreadable")
    func anUnknownMemberIsStillRefused() throws {
        #expect(throws: (any Error).self) { try decode(#"{"greet":{"protocol":1}}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"linkage":{"id":"9F3C"}}"#) }
    }

    @Test("One object, exactly one member — for both cases")
    func theSingleMemberLawHoldsForBoth() throws {
        #expect(throws: (any Error).self) { try decode("{}") }
        #expect(throws: (any Error).self) {
            try decode(#"{"peer":{"id":"9F3C"},"hello":{"protocol":1}}"#)
        }
        #expect(throws: (any Error).self) {
            try decode(#"{"hello":{"protocol":1},"move":{"session":"0b34","index":0,"move":"b1b2"}}"#)
        }
    }

    @Test("A malformed message inside a frame is as malformed as it ever was")
    func aMalformedMessageIsStillMalformed() throws {
        // Its own codec is what judges it: an extra field, a missing one, and a
        // count below zero, each of which the protocol calls malformed.
        #expect(throws: (any Error).self) {
            try decode(#"{"accept":{"session":"0b34","extra":1}}"#)
        }
        #expect(throws: (any Error).self) { try decode(#"{"move":{"session":"0b34"}}"#) }
        #expect(throws: (any Error).self) {
            try decode(#"{"move":{"session":"0b34","index":-1,"move":"b1b2"}}"#)
        }
    }
}
