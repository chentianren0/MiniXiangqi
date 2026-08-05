// One session as the BoardGame Protocol holds it, and the vocabulary the
// engine states its verdicts in.
//
// Everything derivable is derived: the session's state is its plies and its
// ends rather than a flag beside them, and its result is the contract's
// precedence rule read top to bottom. A stored copy of either would be a second
// place for them to be wrong.

import Foundation

/// A protocol string held the way the contract compares one: by its bytes.
///
/// `session` and `rules_version` are opaque strings compared byte-wise, and
/// Swift's own `String` equality is Unicode canonical equivalence, under which
/// two different byte strings are equal and one dictionary key stands for both.
/// A peer that compared bytes and a peer that compared graphemes would disagree
/// about which crossed proposal survives, so this compares bytes.
nonisolated struct WireBytes: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The string as it arrived, which is what a message echoes verbatim.
    let text: String
    private let bytes: [UInt8]

    init(_ text: String) {
        self.text = text
        self.bytes = Array(text.utf8)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }

    var description: String { text }
}

/// One transport connection, named by the transport. Two connections to one
/// peer can stand at once, so a session says which it is bound to.
nonisolated struct ConnectionID: Hashable, Sendable {
    var rawValue: String

    init(_ rawValue: String) { self.rawValue = rawValue }
}

/// The paired device behind a connection, as the transport reports it. This is
/// the identity sessions and resume rely on.
nonisolated struct PeerDeviceID: Hashable, Sendable {
    var rawValue: String

    init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Which of the two peers something belongs to, from this peer's side.
nonisolated enum Party: Sendable, Equatable {
    case local, peer

    var other: Party { self == .local ? .peer : .local }
}

nonisolated enum BoardGameSessionState: Sendable, Equatable {
    case proposed, active, ended
}

/// The one offer or request that may stand at a time.
nonisolated struct NegotiationItem: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case drawOffer
        /// Retract every ply beyond the first `keep`.
        case undoRequest(keep: Int)
    }

    /// The off-turn peer that opened it.
    var opener: Party
    var kind: Kind
    /// The opener's `count` when it opened, which is what makes a later arrival
    /// stale.
    var at: Int
}

/// How a finished session ended, by the one precedence rule.
nonisolated struct BoardGameEnd: Sendable, Equatable {
    enum Ending: Sendable, Equatable {
        /// From the reconciled plies; it outranks everything.
        case rulesDecided(EndReason)
        case agreedDraw
        /// Both peers resigned, so the game is a draw.
        case bothResigned
        case resignation(Party)
    }

    var result: GameResult
    var ending: Ending
}

/// One session, as this peer holds it.
nonisolated struct BoardGameSession: Sendable, Equatable {
    /// The opaque identifier the proposer minted, echoed verbatim and compared
    /// byte-wise.
    let id: String
    let peer: PeerDeviceID
    let rulesID: String
    let rulesVersion: String
    /// Which mover the proposer takes; with index parity it decides every turn.
    let proposerMoves: Mover
    /// Which peer proposed — the only asymmetry a session ever has.
    let proposer: Party

    /// A proposal answered with `accept`. Until then the session is proposed.
    var accepted = false
    /// The connection this session is bound to: the one its `propose` — or,
    /// resumed, its proposer's `resume` — travelled on. Nil while interrupted.
    var connection: ConnectionID?
    var plies: [String] = []
    /// Accepted retractions, zero at birth.
    var undos = 0
    /// The surviving count of the last accepted retraction. Nil until one has
    /// been accepted, when `resume` echoes the sender's own count instead.
    var retractedTo: Int?
    var item: NegotiationItem?
    /// The terminal this peer holds for the session, sent or waiting to ride a
    /// resume.
    var localTerminal: Terminal?
    /// The terminal the other peer sent, however this peer learned of it.
    var peerTerminal: Terminal?
    /// What the plies themselves decide. Refreshed whenever they change.
    var rulesEnd: RulesDecision?
    /// False from the moment this peer sent a terminal or its own ply decided
    /// the end, until a resume exchange completes for the session.
    var settled = true
    /// The resume exchange in flight, if one is.
    var exchange: Exchange?

    /// The resume exchange: what each peer has sent, what it holds, and what
    /// reconciliation still owes it.
    struct Exchange: Sendable, Equatable {
        /// The connections this peer's own `resume` has travelled on.
        var sentOn: Set<ConnectionID> = []
        /// The other peer's `resume` on the completing connection, which is the
        /// only one that ever counts.
        var received: BoardGameMessage.Resume?
        /// The connection the *proposer's* resume travelled on, once that is
        /// known. The exchange completes and the session re-binds there.
        var completing: ConnectionID?
        /// Plies reconciliation still owes this peer.
        var owed = 0
        /// The `end` this peer's own resume carried on the completing
        /// connection. A terminal taken after that resume travelled has ridden
        /// nothing, and this is what tells the two apart.
        var statedEnd: Terminal?
    }

    // MARK: - Everything derived

    var count: Int { plies.count }

    /// Which mover this peer is.
    var localMover: Mover {
        proposer == .local ? proposerMoves : proposerMoves.opponent
    }

    var peerMover: Mover { localMover.opponent }

    var isLocalTurn: Bool { Mover.atPly(count) == localMover }

    /// What `resume` reports as `keep`: the last retraction's surviving count,
    /// or this peer's own count where there has been none.
    var reportedKeep: Int { retractedTo ?? count }

    /// The result, by the precedence rule, or nil while the game has none.
    var end: BoardGameEnd? {
        if let rulesEnd {
            return BoardGameEnd(result: rulesEnd.result, ending: .rulesDecided(rulesEnd.reason))
        }
        if localTerminal == .acceptDraw || peerTerminal == .acceptDraw {
            return BoardGameEnd(result: .draw, ending: .agreedDraw)
        }
        if localTerminal == .resign, peerTerminal == .resign {
            return BoardGameEnd(result: .draw, ending: .bothResigned)
        }
        if localTerminal == .resign {
            return BoardGameEnd(result: .moverWins(peerMover), ending: .resignation(.local))
        }
        if peerTerminal == .resign {
            return BoardGameEnd(result: .moverWins(localMover), ending: .resignation(.peer))
        }
        return nil
    }

    var state: BoardGameSessionState {
        if end != nil { return .ended }
        return accepted ? .active : .proposed
    }

    /// Bound, exchanged, and free to play.
    var isInPlay: Bool { state == .active && connection != nil && exchange == nil }

    /// This session, keyed as the contract compares its identifier.
    var key: WireBytes { WireBytes(id) }

    /// The connection this session's ordinary traffic travels on: its own, or
    /// the completing connection while an exchange is in flight.
    func carries(_ connection: ConnectionID) -> Bool {
        if let exchange { return exchange.completing == connection }
        return self.connection == connection
    }

    /// Whether this peer has something outstanding on that connection for a
    /// `decline` to be answering — a proposal it made, or a resume it sent.
    /// Unprompted, a decline answers nothing.
    func awaitsAnswer(on connection: ConnectionID) -> Bool {
        if state == .proposed {
            return proposer == .local && self.connection == connection
        }
        return exchange?.sentOn.contains(connection) ?? false
    }

    /// Learn of a terminal the other peer sent. Terminals merge by the
    /// precedence rule rather than replace each other, so the order two of them
    /// arrive in cannot change the result.
    mutating func merge(peerTerminal terminal: Terminal) {
        guard peerTerminal != .acceptDraw else { return }
        peerTerminal = terminal
    }

    /// The session as `resume` states it.
    var resumeMessage: BoardGameMessage.Resume {
        BoardGameMessage.Resume(session: id, undos: undos, count: count,
                                keep: reportedKeep, end: localTerminal)
    }
}
