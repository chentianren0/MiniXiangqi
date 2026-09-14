// What actually travels on a nearby connection: either the transport's own
// linkage, or one BoardGame Protocol message.
//
// The protocol contract asks a transport for whole messages and for a stable
// peer identity named behind every connection. The first is the coder's job and
// was always this layer's; the second is what this frame carries. A device's
// identity is the application's own — one identifier per install — and it
// reaches the other device by travelling on the connection whose peer it names,
// which is what makes "exactly one identity per peer" a fact of the code rather
// than a rule somebody has to keep.
//
// **The frame is the transport's, not the protocol's.** A protocol message's
// bytes are exactly the bytes it produces on its own: the message case encodes
// through `BoardGameMessage`'s own encoder and decodes through its own strict
// initialiser, so nothing about the wire format of a game changed when this
// type appeared. The one member name this adds is `peer`, which is not one of
// the eleven, and the single-member-object law holds for both cases.
//
// **The driver never sees one.** The transport wraps what goes out and strips
// what comes in, so `NearbyLink` carries protocol messages alone and neither
// the driver nor the engine can tell a frame exists.
//
// Refusal is unchanged. A member name neither this nor the protocol knows
// throws from the message's own codec, which the connection layer reads as
// unreadable, which is malformed, which is a violation.

import Foundation

/// One thing a nearby connection carries.
nonisolated enum NearbyFrame: Sendable, Equatable {
    /// Who is sending, as the application names itself.
    case linkage(Linkage)
    /// One message of the game the two devices are playing.
    case message(BoardGameMessage)

    /// The identity exchange, which is the whole of what this transport says
    /// for itself: the sender's own identifier and nothing else.
    ///
    /// **No name travels.** A device's name is its owner's name as often as
    /// not, and a row on a screen is not worth that.
    nonisolated struct Linkage: Sendable, Equatable {
        /// The sender's application-minted identifier.
        var id: String
    }

    /// The one member name the transport claims. It is not one of the eleven
    /// message names, so a frame is unambiguous by its member alone.
    static let linkageName = "peer"
}

// MARK: - The wire format

extension NearbyFrame: Codable {

    init(from decoder: any Decoder) throws {
        let envelope = try decoder.container(keyedBy: WireKey.self)
        let members = envelope.allKeys
        guard members.count == 1, let member = members.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "a frame is one object with exactly one member"))
        }
        guard member.stringValue == Self.linkageName else {
            // Every other name is the protocol's to judge, including the ones
            // no version knows: its initialiser refuses them exactly as it does
            // when nothing wraps it.
            self = .message(try BoardGameMessage(from: decoder))
            return
        }
        let object = try envelope.nestedContainer(keyedBy: WireKey.self, forKey: member)
        let fields = try WireObject(object, ["id"])
        self = .linkage(Linkage(id: try fields.text("id")))
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .message(let message):
            // The message's own bytes, composed once, by the type that owns
            // them.
            try message.encode(to: encoder)
        case .linkage(let linkage):
            var envelope = encoder.container(keyedBy: WireKey.self)
            var fields = envelope.nestedContainer(keyedBy: WireKey.self,
                                                  forKey: WireKey(Self.linkageName))
            try fields.encode(linkage.id, forKey: WireKey("id"))
        }
    }
}
