// The BoardGame Protocol as one state machine.
//
// docs/boardgame-protocol-v2.md is binding, and this is the whole of it: hello,
// proposing, the deal handshake, playing, offers and requests, ending,
// interruption and resume, settlement, and the violations that close a
// connection. Nothing here is a rule of any game — every question about a move,
// a result, or whether a game's session opens with the handshake is asked of
// `BoardGameRules`.
//
// **No hidden identity is anywhere in this file.** A dealt game's deal is
// derived on both ends and never sent; what a move revealed is not on the wire,
// and no diagnostic below names an identity or the position that holds them.
//
// It is deterministic and synchronous. It holds no clock and no timer:
// reconnection timing, retries and back-off are transport policy and live
// above it. Every input answers with the sends and the close verdicts it
// produces, and the sessions it holds are the rest of the answer.
//
// It is not `Sendable` and one owner drives it, exactly as a core session has
// one owner: the state below is the state of a conversation, and two threads
// inside it would be two conversations.

import Foundation

/// What one input produced.
nonisolated enum BoardGameEffect: Sendable, Equatable {
    /// Send this message on this connection.
    case send(BoardGameMessage, on: ConnectionID)
    /// Close this connection. The session it concerned, if any, is already void.
    case close(ConnectionID, CloseVerdict)
    /// A proposal or a resume of this peer's was refused. The session is void by
    /// the time this is reported, so the reason is the one part of the answer
    /// the session state cannot carry.
    case declined(session: String, peer: PeerDeviceID, reason: DeclineReason)
}

/// Why a connection is being closed.
nonisolated enum CloseVerdict: Sendable, Equatable {
    case violation(Violation)
    /// A version this peer cannot or will not speak.
    case unsupportedVersion(Int)
}

/// A protocol violation: the detecting peer closes the connection and the
/// session is void.
nonisolated struct Violation: Sendable, Equatable {
    /// The contract's three classes.
    enum Kind: Sendable, Equatable {
        case malformed
        case illegalMove
        case noLawfulMeaning
    }

    var kind: Kind
    /// A short English diagnostic for the log, never user-facing copy.
    var detail: String

    static func malformed(_ detail: String) -> Violation {
        Violation(kind: .malformed, detail: detail)
    }

    static func illegalMove(_ detail: String) -> Violation {
        Violation(kind: .illegalMove, detail: detail)
    }

    static func meaningless(_ detail: String) -> Violation {
        Violation(kind: .noLawfulMeaning, detail: detail)
    }
}

/// What became of a session handed to `adopt`.
///
/// Three answers rather than two, because the two that are not refusals are not
/// the same answer either — and because a caller reading "already held" as a
/// refusal would let go of the very game it is playing.
nonisolated enum BoardGameAdoption: Sendable, Equatable {
    /// Taken up: this peer holds it now and did not before.
    case tookUp
    /// This peer was already holding it, so nothing changed and nothing is
    /// wrong: the engine is the authority on a live session, and a stored copy
    /// of one it is playing is behind by definition.
    case alreadyHeld
    /// Not a session this peer can play: a hidden-information session whose
    /// deal no longer verifies against everything it comes from, or one whose
    /// deal and whose game disagree about whether there should be one. This
    /// peer holds nothing for it afterwards, which is how it answers a `resume`
    /// naming it.
    case refused

    /// Whether this peer holds the session now, however it came to.
    var isHeld: Bool { self != .refused }
}

/// Why the engine refused something this peer's own player asked for. These are
/// this device's own state, never the other peer's conduct.
nonisolated enum BoardGameRefusal: Error, Equatable {
    case unknownConnection
    case unknownSession
    case unknownGame
    /// An active session already stands with that peer.
    case peerIsBusy
    /// This peer's own lingering copy is not settled yet.
    case lingeringSessionUnsettled
    case proposalOutstanding
    case notProposed
    case notActive
    /// Interrupted, or the resume exchange has not completed.
    case notInPlay
    case notYourTurn
    case offTurnOnly
    case itemStanding
    case noStandingItem
    case keepOutOfRange
    case unlawfulMove
    case nothingToResume
    /// The proposer sends `resume` on exactly one connection.
    case resumeConnectionChosen
    /// This peer's resume already travelled that connection, and the exchange
    /// it belongs to has not completed.
    case resumeOutstanding
}

nonisolated final class BoardGameEngine {
    private let rules: any BoardGameRules
    private let mintSessionID: @Sendable () -> String
    private let drawContribution: @Sendable () -> String?

    private var connections: [ConnectionID: Connection] = [:]
    /// Keyed by the identifier's bytes, so two identifiers this contract calls
    /// different cannot become one entry.
    private var sessionsByID: [WireBytes: BoardGameSession] = [:]

    /// - Parameter sessionIDs: mints the identifier a proposal carries. The
    ///   contract wants a UUID; injecting it is what lets a test pin the
    ///   crossing rule's byte-wise sort.
    /// - Parameter contributions: draws one handshake contribution — the
    ///   dealer's seed, or the other end's nonce. Called once per handshake per
    ///   end and never cached, because "a contribution serves exactly one
    ///   handshake"; injecting it is what lets a test see that a second
    ///   handshake drew afresh.
    init(rules: any BoardGameRules,
         sessionIDs: @escaping @Sendable () -> String = { UUID().uuidString },
         contributions: @escaping @Sendable () -> String? = { DealHex.contribution() }) {
        self.rules = rules
        self.mintSessionID = sessionIDs
        self.drawContribution = contributions
    }

    private struct Connection {
        let peer: PeerDeviceID
        /// The version the other peer announced, once it has.
        var peerHello: Int?
    }

    // MARK: - What this peer holds

    /// Every session, in a stable order.
    var sessions: [BoardGameSession] {
        sessionsByID.values.sorted { $0.key < $1.key }
    }

    func session(_ id: String) -> BoardGameSession? { sessionsByID[WireBytes(id)] }

    /// Take up a session this peer already held, rebuilt from outside the
    /// engine: the interrupted game a relaunched application reads back.
    ///
    /// The contract has no message for it and needs none — an interrupted
    /// session is one the resume exchange continues, and this is that session
    /// arriving from the only other place it can survive. What comes back is
    /// what the store keeps and nothing more: no connection, no exchange, and no
    /// standing offer or request, because the protocol voids each peer's
    /// knowledge of those when the connection carrying them dies and a relaunch
    /// is at least that.
    ///
    /// A session this peer already holds is not replaced. The engine is the
    /// authority on a live session, and a stored copy of one it is playing is
    /// behind by definition.
    ///
    /// **A hidden-information session's deal is re-verified here**, which is
    /// the one door a persisted one comes through. "Before using that deal it
    /// re-verifies it locally, and against everything the deal comes from",
    /// and a failure "means what it holds is no longer the session, which it
    /// answers as a peer that does not know the session" — by not taking it up,
    /// after which every `resume` for it meets the `unknown_session` answer any
    /// session this peer holds nothing for meets.
    ///
    /// Answers what became of it, which the caller must tell apart: **a
    /// session already held and a session refused are opposite answers**, and a
    /// caller that read them as one would let go of a game it is playing.
    @discardableResult
    func adopt(_ session: BoardGameSession) -> BoardGameAdoption {
        guard sessionsByID[session.key] == nil else { return .alreadyHeld }
        var restored = session
        // A dealt game's session without a deal, or an undealt game's with one,
        // is not a session of the game it names.
        guard rules.dealsItsStart(restored.rulesID) == (restored.deal != nil) else {
            return .refused
        }
        if let held = restored.deal {
            guard let verified = BoardGameDeal.verified(
                commit: held.commit, nonce: held.nonce, seed: held.seed,
                digest: held.digest, of: restored.rulesID, by: rules)
            else { return .refused }
            restored.handshake = .dealt(verified)
        }
        restored.connection = nil
        restored.exchange = nil
        restored.item = nil
        restored.rulesEnd = rules.standing(after: restored.plies,
                                           from: restored.dealtStart,
                                           of: restored.rulesID).decision
        store(restored)
        return .tookUp
    }

    /// A session this device is giving up on, without a message.
    ///
    /// The protocol has no vocabulary for abandoning a game, and this invents
    /// none: what it does is exactly what a void does here — the session is
    /// forgotten, and the other peer learns of it from the `unknown_session`
    /// its next resume is answered with, which is the contract's own path for a
    /// peer that no longer holds a session.
    func abandon(_ id: String) {
        sessionsByID[WireBytes(id)] = nil
    }

    /// The proposed-or-active session with one peer. At most one stands.
    func session(with peer: PeerDeviceID) -> BoardGameSession? {
        sessionsByID.values.first { $0.peer == peer && $0.state != .ended }
    }

    /// The finished session lingering beside the pair's dealings.
    func lingeringSession(with peer: PeerDeviceID) -> BoardGameSession? {
        sessionsByID.values.first { $0.peer == peer && $0.state == .ended }
    }

    // MARK: - Connections

    /// A connection came up. `hello` opens it, before anything else.
    func connectionOpened(_ connection: ConnectionID, with peer: PeerDeviceID) -> [BoardGameEffect] {
        precondition(connections[connection] == nil,
                     "a connection identifier is opened once")
        connections[connection] = Connection(peer: peer)
        return [.send(.hello(BoardGameMessage.Hello()), on: connection)]
    }

    /// A connection went away. An unanswered proposal dies with it, a deal
    /// handshake in flight dies with it, a pending offer or request is void
    /// with it, and a session it carried is interrupted rather than lost.
    func connectionDied(_ connection: ConnectionID) {
        connections[connection] = nil
        for held in sessionsByID.values {
            var session = held
            // "A **dealing** session is bound to the connection its `propose`
            // travelled on and dies with it: it holds nothing worth
            // reconciling, it is never resumed, and the pair simply proposes
            // again and deals again."
            if session.state == .proposed || session.state == .dealing,
               session.connection == connection {
                forget(session)
                continue
            }
            if session.connection == connection {
                session.connection = nil
                session.item = nil
            }
            if var exchange = session.exchange {
                if exchange.completing == connection {
                    session.exchange = nil
                } else {
                    exchange.sentEnds.removeValue(forKey: connection)
                    let empty = exchange.completing == nil && exchange.sentEnds.isEmpty
                    session.exchange = empty ? nil : exchange
                }
            }
            store(session)
        }
    }

    /// The transport could not read a message: malformed, and malformed is a
    /// violation.
    func receivedMalformedMessage(on connection: ConnectionID) -> [BoardGameEffect] {
        close(connection, .violation(.malformed("the message did not decode")),
              voiding: sessionCarried(by: connection)?.id)
    }

    // MARK: - Arrivals

    func receive(_ message: BoardGameMessage, on connection: ConnectionID) -> [BoardGameEffect] {
        guard let record = connections[connection] else {
            // A close verdict leaves this engine at once and the transport acts
            // on it afterwards, so a message its receive loop had already taken
            // arrives for a connection this engine has forgotten. That race is
            // the transport's ordinary noise rather than a fault, and there is
            // nothing left here for the message to mean.
            return []
        }
        let peer = record.peer

        if case .hello(let hello) = message {
            guard record.peerHello == nil else {
                return close(connection,
                             .violation(.meaningless("a second hello on one connection")))
            }
            guard hello.protocolVersion == BoardGameMessage.version else {
                return close(connection, .unsupportedVersion(hello.protocolVersion))
            }
            connections[connection]?.peerHello = hello.protocolVersion
            return []
        }
        guard record.peerHello != nil else {
            return close(connection,
                         .violation(.meaningless("a message before the other peer's hello")),
                         voiding: sessionCarried(by: connection)?.id)
        }

        if case .propose(let proposal) = message {
            return receive(proposal, from: peer, on: connection)
        }

        guard let id = message.session else {
            preconditionFailure("every message but hello names a session")
        }
        guard var session = sessionsByID[WireBytes(id)], session.peer == peer else {
            switch message {
            case .resume:
                // Genuinely unknown: this peer holds nothing for it, retired
                // it, held only a proposal or a handshake that died with its
                // connection, or its own deal failed re-verification.
                return [.send(.decline(.init(session: id, reason: .unknownSession)),
                              on: connection)]
            case .decline(let decline) where decline.reason.voidsTheSession:
                // Both peers agree the session does not exist. `unknown_session`
                // and `deal_mismatch` both void it on both sides, so either can
                // cross the very exchange that provoked it.
                return []
            default:
                return close(connection,
                             .violation(.meaningless("a message for a session this peer does not hold")))
            }
        }

        if case .resume(let resume) = message {
            return receive(resume, into: &session, on: connection)
        }

        // A decline is judged before the connection is, because the answer to
        // this peer's own outstanding resume is the one message that arrives
        // for a session whose exchange has not yet named a completing
        // connection — and the reconciliation allowance must not swallow it.
        if case .decline(let decline) = message {
            return receive(decline, into: &session, on: connection)
        }

        // A session in **dealing** has exactly three messages with a lawful
        // meaning, and "any other message arriving for a session in dealing" is
        // a violation.
        if session.state == .dealing {
            return receiveWhileDealing(message, into: &session, on: connection)
        }

        if session.state == .ended {
            return receiveForEnded(message, into: &session, on: connection)
        }

        guard session.carries(connection) else {
            // Anything for a session mid-reconciliation that did not come on
            // the completing connection is the reconciliation allowance rather
            // than a violation.
            if session.exchange != nil { return [] }
            return close(connection,
                         .violation(.meaningless("a message on a connection this session is not bound to")),
                         voiding: id)
        }

        switch message {
        case .hello, .propose, .resume, .decline:
            preconditionFailure("handled above")

        case .dealCommit, .dealNonce, .dealSeed:
            // Every handshake message for a session that is not dealing is a
            // departure: one for a perfect-information game's session, one
            // before the proposal was answered, and one for a session whose
            // handshake has already completed.
            return close(connection,
                         .violation(.meaningless("a handshake message outside a dealing session")),
                         voiding: id)

        case .accept:
            guard session.state == .proposed, session.proposer == .local else {
                return close(connection,
                             .violation(.meaningless("an accept for a proposal this peer did not make")),
                             voiding: id)
            }
            session.accepted = true
            // "On `accept`, a perfect-information game's session becomes
            // **active** and play begins. A hidden-information game's becomes
            // **dealing**, and the proposer sends `deal_commit` at once."
            guard rules.dealsItsStart(session.rulesID) else {
                store(session)
                return []
            }
            guard let seed = drawContribution(),
                  let commit = DealHex.commitment(for: seed)
            else {
                // A cryptographic source that refused. There is no deal to make
                // from something weaker and no vocabulary for saying so, so the
                // handshake stops where it stands: this end forgets the session
                // and the other end's dies with the connection, which is what
                // the contract already does with an abandoned handshake.
                forget(session)
                return []
            }
            session.handshake = .awaitingNonce(commit: commit, seed: seed)
            store(session)
            return [.send(.dealCommit(.init(session: id, commit: commit)), on: connection)]

        case .move(let move):
            return receive(move, into: &session, on: connection)

        case .offerDraw(let offer):
            return receiveItem(.drawOffer, at: offer.at, into: &session, on: connection)

        case .requestUndo(let request):
            guard request.keep < request.at else {
                return close(connection,
                             .violation(.malformed("keep ranges from 0 to one less than the sender's count")),
                             voiding: id)
            }
            return receiveItem(.undoRequest(keep: request.keep), at: request.at,
                               into: &session, on: connection)

        case .acceptDraw:
            guard session.state == .active, let item = session.item,
                  item.opener == .local, item.kind == .drawOffer
            else {
                return close(connection,
                             .violation(.meaningless("an acceptance that matches no standing item")),
                             voiding: id)
            }
            session.merge(peerTerminal: .acceptDraw)
            session.item = nil
            store(session)
            return []

        case .acceptUndo:
            guard session.state == .active, let item = session.item,
                  item.opener == .local, case .undoRequest(let keep) = item.kind
            else {
                return close(connection,
                             .violation(.meaningless("an acceptance that matches no standing item")),
                             voiding: id)
            }
            retract(&session, to: keep)
            store(session)
            return []

        case .resign:
            guard session.state == .active else {
                return close(connection,
                             .violation(.meaningless("a resign outside an active session")),
                             voiding: id)
            }
            session.merge(peerTerminal: .resign)
            session.item = nil
            store(session)
            return []
        }
    }

    /// A proposal arriving.
    private func receive(_ proposal: BoardGameMessage.Propose, from peer: PeerDeviceID,
                         on connection: ConnectionID) -> [BoardGameEffect] {
        // An arriving propose retires the receiver's ended copy whatever its
        // settledness, and before anything can call the arriving identifier a
        // duplicate: a new proposal retires the ended session even where it
        // reuses that session's own identifier, and what stands afterwards is a
        // proposal of a session this peer holds nothing for.
        if let lingering = lingeringSession(with: peer) { forget(lingering) }

        // The crossing case is judged before anything can call the arriving
        // identifier a duplicate: this peer's own outstanding proposal is the
        // one session whose identifier an arriving proposal may lawfully carry.
        if let live = session(with: peer), live.state == .proposed, live.proposer == .local {
            let arriving = WireBytes(proposal.session)
            guard arriving != live.key else {
                // Neither sorts lower, so neither survives, and each peer
                // applies the same test to the same pair.
                forget(live)
                return []
            }
            // The proposal whose identifier sorts lower byte-wise survives; the
            // other is void without an answer.
            guard arriving < live.key else { return [] }
            forget(live)
        }

        guard sessionsByID[WireBytes(proposal.session)] == nil else {
            return close(connection,
                         .violation(.meaningless("a propose naming a session already held")))
        }

        if let live = session(with: peer) {
            // "`busy` answers a `propose` that arrives while a **dealing** or
            // **active** session exists with that peer." A proposal arriving
            // while one is merely unanswered is the crossing case above, and
            // anything left here is a second proposal, which is a violation.
            guard live.state == .active || live.state == .dealing else {
                return close(connection,
                             .violation(.meaningless("a second proposal while one is unanswered")),
                             voiding: live.id)
            }
            return [.send(.decline(.init(session: proposal.session, reason: .busy)),
                          on: connection)]
        }

        guard let version = rules.version(of: proposal.rulesID) else {
            return [.send(.decline(.init(session: proposal.session, reason: .unknownGame)),
                          on: connection)]
        }
        guard WireBytes(version) == WireBytes(proposal.rulesVersion) else {
            return [.send(.decline(.init(session: proposal.session, reason: .rulesMismatch)),
                          on: connection)]
        }

        var session = BoardGameSession(id: proposal.session, peer: peer,
                                       rulesID: proposal.rulesID,
                                       rulesVersion: proposal.rulesVersion,
                                       proposerMoves: proposal.proposerMoves,
                                       proposer: .peer)
        session.connection = connection
        store(session)
        // The proposal stands unanswered until this peer's own player answers.
        return []
    }

    // MARK: - The deal handshake

    /// The three messages a **dealing** session has a lawful meaning for, "in
    /// this order and no other".
    ///
    /// **The handshake's own state is the whole test.** Only the dealer ever
    /// stands at `awaitingNonce` and only the other end at `awaitingCommit` or
    /// `awaitingSeed`, so matching the message against it is at once the order
    /// check and the party check: a `deal_commit` or a `deal_seed` from the peer
    /// that is not the dealer, a `deal_nonce` from the dealer, any of the three
    /// out of order or a second time, and any other message at all fall through
    /// to one violation. A malformed value never arrives here — the codec
    /// refuses a handshake value that is not sixty-four lowercase hexadecimal
    /// digits, and the transport reports that as the malformed message it is.
    private func receiveWhileDealing(_ message: BoardGameMessage,
                                     into session: inout BoardGameSession,
                                     on connection: ConnectionID) -> [BoardGameEffect] {
        // The handshake's three messages travel "on the session's own
        // connection", which for a dealing session is the one its `propose`
        // travelled on and the only one it will ever have.
        guard session.carries(connection) else {
            return close(connection,
                         .violation(.meaningless("a handshake message on a connection this session is not bound to")),
                         voiding: session.id)
        }
        let id = session.id

        switch (message, session.handshake) {
        case (.dealCommit(let arriving), .awaitingCommit):
            guard let nonce = drawContribution() else { return abandon(&session) }
            session.handshake = .awaitingSeed(commit: arriving.commit, nonce: nonce)
            store(session)
            return [.send(.dealNonce(.init(session: id, nonce: nonce)), on: connection)]

        case (.dealNonce(let arriving), .awaitingNonce(_, let seed)):
            // The dealer holds both contributions now. **Its session becomes
            // active when it has sent `deal_seed`**, and the first ply may
            // follow immediately.
            guard let deal = rules.deal(seed: seed, nonce: arriving.nonce,
                                        of: session.rulesID)
            else {
                return close(connection,
                             .violation(.malformed("no deal derives from that contribution")),
                             voiding: id)
            }
            session.handshake = .dealt(deal)
            store(session)
            return [.send(.dealSeed(.init(session: id, seed: seed)), on: connection)]

        case (.dealSeed(let arriving), .awaitingSeed(let commit, let nonce)):
            // "The receiver hashes it and compares with the `commit` it holds;
            // a mismatch is a protocol violation", which is the one thing the
            // commitment exists to catch. The comparison is against the
            // commitment the deriving entry reports for that seed, so one
            // implementation answers it on both ends.
            guard let deal = rules.deal(seed: arriving.seed, nonce: nonce,
                                        of: session.rulesID)
            else {
                return close(connection,
                             .violation(.malformed("no deal derives from that seed")),
                             voiding: id)
            }
            guard deal.commit == commit else {
                return close(connection,
                             .violation(.meaningless("the seed does not open the commitment")),
                             voiding: id)
            }
            session.handshake = .dealt(deal)
            store(session)
            return []

        default:
            return close(connection,
                         .violation(.meaningless("a message with no lawful meaning while dealing")),
                         voiding: id)
        }
    }

    /// A handshake this device cannot carry on with, because its cryptographic
    /// source refused. Nothing is sent: there is no vocabulary for saying so,
    /// and a dealing session that stops is exactly the abandoned handshake the
    /// contract already describes — the other end's dies with the connection,
    /// and the pair proposes again and deals again.
    private func abandon(_ session: inout BoardGameSession) -> [BoardGameEffect] {
        forget(session)
        return []
    }

    /// A ply arriving for a proposed or active session.
    private func receive(_ move: BoardGameMessage.Move, into session: inout BoardGameSession,
                         on connection: ConnectionID) -> [BoardGameEffect] {
        guard session.state == .active else {
            return close(connection, .violation(.meaningless("a move outside an active session")),
                         voiding: session.id)
        }
        if let exchange = session.exchange, exchange.received == nil {
            return close(connection,
                         .violation(.meaningless("a move before the other peer's resume")),
                         voiding: session.id)
        }
        guard move.index == session.count else {
            return close(connection, .violation(.meaningless("a move whose index is not the count")),
                         voiding: session.id)
        }
        guard Mover.atPly(move.index) == session.peerMover else {
            return close(connection, .violation(.meaningless("a move out of turn")),
                         voiding: session.id)
        }
        guard case .lawful(let standing) = rules.verdict(for: move.move, after: session.plies,
                                                         from: session.dealtStart,
                                                         of: session.rulesID)
        else {
            return close(connection, .violation(.illegalMove("the move is not lawful here")),
                         voiding: session.id)
        }
        let effects = land(move.move, deciding: standing.decision, in: &session, on: connection)
        store(session)
        return effects
    }

    /// An offer or a request arriving.
    private func receiveItem(_ kind: NegotiationItem.Kind, at: Int,
                             into session: inout BoardGameSession,
                             on connection: ConnectionID) -> [BoardGameEffect] {
        guard session.state == .active else {
            return close(connection,
                         .violation(.meaningless("a negotiation outside an active session")),
                         voiding: session.id)
        }
        guard Mover.atPly(at) != session.peerMover else {
            return close(connection,
                         .violation(.meaningless("only the off-turn peer opens a negotiation")),
                         voiding: session.id)
        }
        guard session.item?.opener != .peer else {
            return close(connection,
                         .violation(.meaningless("the off-turn peer sends nothing further while its item stands")),
                         voiding: session.id)
        }
        // Stale: silently void.
        guard at == session.count else { return [] }
        session.item = NegotiationItem(opener: .peer, kind: kind, at: at)
        store(session)
        return []
    }

    /// A `decline` refuses a proposal or a resume, so it answers something this
    /// peer has outstanding on the connection it arrives on. Unprompted, it
    /// answers nothing.
    private func receive(_ decline: BoardGameMessage.Decline,
                         into session: inout BoardGameSession,
                         on connection: ConnectionID) -> [BoardGameEffect] {
        if session.awaitsAnswer(on: connection) {
            // A proposal is refused for any of its reasons; a resume only by an
            // answer that voids the session on both sides — the peer that does
            // not know it, and the peer holding a different deal under one
            // identifier.
            if session.state == .proposed || decline.reason.voidsTheSession {
                forget(session)
                return [.declined(session: session.id, peer: session.peer,
                                  reason: decline.reason)]
            }
        }
        // An ended session discards what it has no use for, never a violation.
        guard session.state != .ended else { return [] }
        return close(connection,
                     .violation(.meaningless("a decline answering nothing this peer has outstanding")),
                     voiding: session.id)
    }

    /// The ended session's allowances: it answers `resume`, applies a valid
    /// in-sequence `move`, merges arriving terminals, and discards the rest.
    private func receiveForEnded(_ message: BoardGameMessage,
                                 into session: inout BoardGameSession,
                                 on connection: ConnectionID) -> [BoardGameEffect] {
        var effects: [BoardGameEffect] = []
        switch message {
        case .move(let move):
            guard session.carries(connection), move.index == session.count,
                  Mover.atPly(move.index) == session.peerMover,
                  case .lawful(let standing) = rules.verdict(for: move.move, after: session.plies,
                                                             from: session.dealtStart,
                                                             of: session.rulesID)
            else { return [] }
            effects = land(move.move, deciding: standing.decision, in: &session, on: connection)

        case .resign:
            session.merge(peerTerminal: .resign)

        case .acceptDraw:
            session.merge(peerTerminal: .acceptDraw)

        default:
            // Discarded, never a violation.
            return []
        }
        store(session)
        return effects
    }

    // MARK: - Resume

    private func receive(_ resume: BoardGameMessage.Resume, into session: inout BoardGameSession,
                         on connection: ConnectionID) -> [BoardGameEffect] {
        switch session.state {
        case .proposed:
            return close(connection, .violation(.meaningless("a resume for a proposal")),
                         voiding: session.id)
        case .dealing:
            // A dealing session "is never resumed": it holds nothing worth
            // reconciling, and a resume naming one is a message with no lawful
            // meaning in that state.
            return close(connection,
                         .violation(.meaningless("a resume for a session whose handshake is in flight")),
                         voiding: session.id)
        case .active, .ended:
            break
        }

        switch (session.deal?.digest, resume.dealDigest) {
        case (nil, nil):
            break
        case (let ours?, let theirs?) where ours == theirs:
            break
        case (_?, _?):
            // "A `resume` whose `deal_digest` differs from the receiver's own is
            // two devices holding different games under one identifier": the
            // session is void on both sides, and the answer says which of the
            // two voiding reasons it is.
            forget(session)
            return [.send(.decline(.init(session: session.id, reason: .dealMismatch)),
                          on: connection)]
        default:
            // Present for a hidden-information session and absent for every
            // other; a `resume` whose presence disagrees with the session it
            // names is missing a member or carrying an extra one.
            return close(connection,
                         .violation(.malformed("a resume whose deal_digest does not match the session's game")),
                         voiding: session.id)
        }

        var exchange = session.exchange ?? .init()

        if session.proposer == .peer {
            // The proposer's resume names the connection the exchange completes
            // on; every other resume either peer sent is void once it does. A
            // later one of theirs on another connection re-targets the exchange
            // rather than being refused: a proposer that watched its first
            // connection die is choosing again, which is legitimate from its own
            // view while this side still holds that connection up.
            if exchange.completing != connection {
                exchange.completing = connection
                exchange.keepOnly(connection)
            }
        } else if let completing = exchange.completing {
            // This peer proposed and has chosen its connection already, so
            // every resume on another one is void.
            guard completing == connection else { return [] }
        } else {
            // This peer proposed and has not chosen. An ended session still
            // answers a resume, and an active one owes the same answer, so the
            // arrival's own connection is the choice — no exchange can complete
            // until the proposer's resume has travelled one.
            exchange.completing = connection
        }
        // A second resume of theirs on the completing connection reconciles
        // again. Only a peer that broke "sends on exactly one connection", or
        // re-sent where nothing was owed, states one twice, and reconciling
        // twice converges: the same stated session yields the same truncation
        // and the same merge, and the plies it re-sends are ones that peer
        // already holds.
        exchange.received = resume
        // Nothing an interrupted session was negotiating survives the exchange
        // that re-binds it.
        session.item = nil
        session.exchange = exchange

        let effects = reconcile(&session, with: resume, on: connection)
        store(session)
        return effects
    }

    /// Truncation, the end merge, the ply resend, and what completion is
    /// waiting for.
    private func reconcile(_ session: inout BoardGameSession,
                           with theirs: BoardGameMessage.Resume,
                           on connection: ConnectionID) -> [BoardGameEffect] {
        var effects: [BoardGameEffect] = []
        var exchange = session.exchange ?? .init()

        // `resume` states the session as the sender holds it, so this peer's
        // own goes out before reconciliation changes anything.
        if !exchange.sent(on: connection) {
            effects.append(.send(.resume(session.resumeMessage), on: connection))
            exchange.record(session.localTerminal, sentOn: connection)
        }

        let ourKeep = session.reportedKeep
        var ourEffectiveCount = session.count
        var theirEffectiveCount = theirs.count

        if theirs.undos > session.undos {
            ourEffectiveCount = min(session.count, theirs.keep)
            session.plies = Array(session.plies.prefix(ourEffectiveCount))
            session.undos = theirs.undos
            session.retractedTo = theirs.keep
            session.rulesEnd = rules.standing(after: session.plies, from: session.dealtStart,
                                              of: session.rulesID).decision
        } else if session.undos > theirs.undos {
            theirEffectiveCount = min(theirs.count, ourKeep)
        }

        // Their `end` merges by the precedence rule as if the terminal itself
        // had arrived.
        if let end = theirs.end { session.merge(peerTerminal: end) }

        // The peer holding more plies resends the missing ones as ordinary
        // moves.
        for index in stride(from: theirEffectiveCount, to: ourEffectiveCount, by: 1) {
            effects.append(.send(.move(.init(session: session.id, index: index,
                                             move: session.plies[index])),
                                 on: connection))
        }
        exchange.owed = max(0, theirEffectiveCount - ourEffectiveCount)
        session.exchange = exchange
        return effects + completeExchangeIfDone(&session)
    }

    /// The exchange is complete — and the session settled — once this peer
    /// holds the other's resume on the completing connection and has received
    /// every ply reconciliation owed it.
    ///
    /// A terminal taken after this peer's own resume had already travelled is
    /// carried by nothing, so the re-bind sends it as the ordinary message it
    /// is. That terminal then settles the way every sent terminal does: not
    /// here, but when a later resume exchange completes for it.
    private func completeExchangeIfDone(_ session: inout BoardGameSession) -> [BoardGameEffect] {
        guard let exchange = session.exchange, let completing = exchange.completing,
              exchange.received != nil, exchange.owed == 0
        else { return [] }

        session.connection = completing
        session.exchange = nil
        session.item = nil

        guard let held = session.localTerminal,
              exchange.end(statedOn: completing) != held
        else {
            session.settled = true
            return []
        }
        return [.send(held.message(for: session.id), on: completing)]
    }

    // MARK: - What this peer's own player asks for

    /// Offer a game. The version announced is this peer's own for that game;
    /// the other peer accepts only on exact equality.
    func propose(to peer: PeerDeviceID, on connection: ConnectionID,
                 rulesID: String, proposerMoves: Mover) throws(BoardGameRefusal) -> [BoardGameEffect] {
        guard let record = connections[connection], record.peer == peer else {
            throw .unknownConnection
        }
        guard let version = rules.version(of: rulesID) else { throw .unknownGame }
        if let live = session(with: peer) {
            // A session dealing is a session under way, exactly as an active
            // one is: the pair is busy until its handshake has finished or its
            // connection has taken it.
            throw live.state == .proposed ? .proposalOutstanding : .peerIsBusy
        }
        if let lingering = lingeringSession(with: peer) {
            // A peer proposes only when its own copy of the pair's lingering
            // session is settled; a new proposal then retires it.
            guard lingering.settled else { throw .lingeringSessionUnsettled }
            forget(lingering)
        }

        let id = mintSessionID()
        precondition(sessionsByID[WireBytes(id)] == nil, "a minted session identifier is fresh")
        var session = BoardGameSession(id: id, peer: peer, rulesID: rulesID,
                                       rulesVersion: version, proposerMoves: proposerMoves,
                                       proposer: .local)
        session.connection = connection
        store(session)
        return [.send(.propose(.init(session: id, rulesID: rulesID, rulesVersion: version,
                                     proposerMoves: proposerMoves)),
                      on: connection)]
    }

    /// The player's answer to an arriving proposal.
    func answer(_ id: String, accepting: Bool) throws(BoardGameRefusal) -> [BoardGameEffect] {
        guard var session = sessionsByID[WireBytes(id)] else { throw .unknownSession }
        guard session.state == .proposed, session.proposer == .peer else { throw .notProposed }
        guard let connection = session.connection, connections[connection] != nil else {
            throw .notInPlay
        }
        guard accepting else {
            forget(session)
            return [.send(.decline(.init(session: id, reason: .declined)), on: connection)]
        }
        session.accepted = true
        // The acceptor of a hidden-information game's proposal enters
        // **dealing** and waits: the proposer is the dealer, and `deal_commit`
        // is the first thing that travels.
        if rules.dealsItsStart(session.rulesID) {
            session.handshake = .awaitingCommit
        }
        store(session)
        return [.send(.accept(.init(session: id)), on: connection)]
    }

    /// One ply.
    func play(_ text: String, in id: String) throws(BoardGameRefusal) -> [BoardGameEffect] {
        guard var session = sessionsByID[WireBytes(id)] else { throw .unknownSession }
        guard session.state == .active else { throw .notActive }
        guard session.isInPlay, let connection = session.connection else { throw .notInPlay }
        guard session.isLocalTurn else { throw .notYourTurn }
        guard case .lawful(let standing) = rules.verdict(for: text, after: session.plies,
                                                         from: session.dealtStart,
                                                         of: session.rulesID)
        else { throw .unlawfulMove }

        let index = session.count
        // Being in play is having no exchange in flight, so this landing owes
        // no completion and produces no send of its own.
        _ = land(text, deciding: standing.decision, in: &session, on: connection)
        // A peer whose own ply decided the end holds the session unsettled.
        if session.rulesEnd != nil { session.settled = false }
        store(session)
        return [.send(.move(.init(session: id, index: index, move: text)), on: connection)]
    }

    /// The claimed draw, which is a ply like any other.
    func claim(in id: String) throws(BoardGameRefusal) -> [BoardGameEffect] {
        try play(TurnAction.claim, in: id)
    }

    func offerDraw(in id: String) throws(BoardGameRefusal) -> [BoardGameEffect] {
        try open(.drawOffer, in: id)
    }

    func requestUndo(keeping keep: Int, in id: String) throws(BoardGameRefusal) -> [BoardGameEffect] {
        try open(.undoRequest(keep: keep), in: id)
    }

    private func open(_ kind: NegotiationItem.Kind,
                      in id: String) throws(BoardGameRefusal) -> [BoardGameEffect] {
        guard var session = sessionsByID[WireBytes(id)] else { throw .unknownSession }
        guard session.state == .active else { throw .notActive }
        guard session.isInPlay, let connection = session.connection else { throw .notInPlay }
        guard !session.isLocalTurn else { throw .offTurnOnly }
        guard session.item == nil else { throw .itemStanding }
        if case .undoRequest(let keep) = kind, !(0..<session.count).contains(keep) {
            throw .keepOutOfRange
        }

        let at = session.count
        session.item = NegotiationItem(opener: .local, kind: kind, at: at)
        store(session)
        switch kind {
        case .drawOffer:
            return [.send(.offerDraw(.init(session: id, at: at)), on: connection)]
        case .undoRequest(let keep):
            return [.send(.requestUndo(.init(session: id, at: at, keep: keep)), on: connection)]
        }
    }

    func acceptDraw(in id: String) throws(BoardGameRefusal) -> [BoardGameEffect] {
        guard var session = sessionsByID[WireBytes(id)] else { throw .unknownSession }
        guard session.state == .active else { throw .notActive }
        guard session.isInPlay, let connection = session.connection else { throw .notInPlay }
        guard let item = session.item, item.opener == .peer, item.kind == .drawOffer else {
            throw .noStandingItem
        }
        session.localTerminal = .acceptDraw
        session.item = nil
        // A peer that sent a terminal holds the session unsettled.
        session.settled = false
        store(session)
        return [.send(.acceptDraw(.init(session: id)), on: connection)]
    }

    func acceptUndo(in id: String) throws(BoardGameRefusal) -> [BoardGameEffect] {
        guard var session = sessionsByID[WireBytes(id)] else { throw .unknownSession }
        guard session.state == .active else { throw .notActive }
        guard session.isInPlay, let connection = session.connection else { throw .notInPlay }
        guard let item = session.item, item.opener == .peer,
              case .undoRequest(let keep) = item.kind
        else { throw .noStandingItem }
        retract(&session, to: keep)
        store(session)
        return [.send(.acceptUndo(.init(session: id)), on: connection)]
    }

    /// Resign, which is valid at any point of an active session. With nowhere
    /// to send it, the terminal waits and rides the next resume's `end`.
    func resign(in id: String) throws(BoardGameRefusal) -> [BoardGameEffect] {
        guard var session = sessionsByID[WireBytes(id)] else { throw .unknownSession }
        guard session.state == .active else { throw .notActive }
        let outlet = session.isInPlay ? session.connection : nil
        session.localTerminal = .resign
        session.item = nil
        session.settled = false
        store(session)
        guard let outlet else { return [] }
        return [.send(.resign(.init(session: id)), on: outlet)]
    }

    /// Continue an interrupted session, or settle an ended one. The proposer's
    /// resume names the connection the exchange completes on, and it sends on
    /// exactly one connection of its choosing.
    func resume(_ id: String, on connection: ConnectionID) throws(BoardGameRefusal) -> [BoardGameEffect] {
        guard var session = sessionsByID[WireBytes(id)] else { throw .unknownSession }
        guard let record = connections[connection], record.peer == session.peer else {
            throw .unknownConnection
        }
        switch session.state {
        case .proposed:
            throw .nothingToResume
        case .dealing:
            // A dealing session "is never resumed": it holds nothing worth
            // reconciling, and it dies with the connection its proposal
            // travelled on rather than being carried to another.
            throw .nothingToResume
        case .active:
            guard session.connection != connection || session.exchange != nil else {
                throw .nothingToResume
            }
        case .ended:
            guard !session.settled else { throw .nothingToResume }
        }

        var exchange = session.exchange ?? .init()
        if session.proposer == .local, let completing = exchange.completing,
           completing != connection {
            throw .resumeConnectionChosen
        }
        // Once this peer's resume has travelled a connection, saying it again
        // states nothing new and would re-send plies the other peer already
        // holds.
        guard !exchange.sent(on: connection) else { throw .resumeOutstanding }

        if session.proposer == .local { exchange.completing = connection }
        exchange.record(session.localTerminal, sentOn: connection)
        session.exchange = exchange
        // Nothing an interrupted session was negotiating survives the exchange
        // that re-binds it.
        session.item = nil

        // Nothing to reconcile with yet: the other peer's resume is answered as
        // it arrives, so a session holding one has already sent this.
        store(session)
        return [.send(.resume(session.resumeMessage), on: connection)]
    }

    // MARK: - Shared state changes

    /// One ply lands: it joins the line and voids the standing item on both
    /// sides.
    private func land(_ text: String, deciding decision: RulesDecision?,
                      in session: inout BoardGameSession,
                      on connection: ConnectionID) -> [BoardGameEffect] {
        session.plies.append(text)
        session.item = nil
        session.rulesEnd = decision
        guard var exchange = session.exchange, exchange.completing == connection else { return [] }
        exchange.owed = max(0, exchange.owed - 1)
        session.exchange = exchange
        return completeExchangeIfDone(&session)
    }

    /// An accepted retraction: every ply beyond the first `keep` goes, and the
    /// session's count of accepted retractions rises by one.
    private func retract(_ session: inout BoardGameSession, to keep: Int) {
        session.plies = Array(session.plies.prefix(keep))
        session.undos += 1
        session.retractedTo = keep
        session.item = nil
        session.rulesEnd = rules.standing(after: session.plies, from: session.dealtStart,
                                              of: session.rulesID).decision
    }

    private func store(_ session: BoardGameSession) {
        sessionsByID[session.key] = session
    }

    /// A device forgets a void session, and a retired one.
    private func forget(_ session: BoardGameSession) {
        sessionsByID[session.key] = nil
    }

    private func sessionCarried(by connection: ConnectionID) -> BoardGameSession? {
        sessionsByID.values.first { $0.carries(connection) }
    }

    /// The detecting peer closes the connection, and the session is void.
    private func close(_ connection: ConnectionID, _ verdict: CloseVerdict,
                       voiding session: String? = nil) -> [BoardGameEffect] {
        if let session { sessionsByID[WireBytes(session)] = nil }
        connectionDied(connection)
        return [.close(connection, verdict)]
    }
}
