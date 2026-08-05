// What puts the BoardGame Protocol engine on a transport.
//
// The engine is deterministic and synchronous: every input answers with the
// sends and the close verdicts it produces, and the sessions it holds are the
// rest of the answer. Something has to hand it the transport's events, perform
// what it answers with, and pass this device's own player's intents down. That
// is all this is.
//
// **It holds no protocol logic.** Not one branch here reads a session's state
// to decide what the contract allows: where the contract says a peer does
// something, the engine is asked and its refusal is the answer. The resume a
// fresh connection owes is the clearest case — the driver offers every session
// it holds with that device, and the engine refuses the ones that need none.
//
// It is transport-free on purpose. `NearbyLink` is the whole of what it needs
// from a connection, so the Wi-Fi Aware layer above it is one implementation
// and a test's fake is another, and neither the engine nor this can tell.

import Foundation
import Observation
import OSLog

/// One live connection, as the driver needs it: a name, a way to send, and a
/// way to close. The transport names the connection; the paired device behind
/// it is named separately, once the transport has resolved it.
@MainActor
protocol NearbyLink: AnyObject {
    var id: ConnectionID { get }
    /// Send one message. The driver never calls this twice at once for one
    /// connection: per-direction order is the protocol's own model.
    func send(_ message: BoardGameMessage) async throws
    /// Close the connection. A close verdict of the engine's and the harness's
    /// Stop are the only callers.
    func close()
}

/// The subsystem the nearby layer logs under. `nonisolated` because the
/// transport writes to it from its own executors.
nonisolated enum NearbyLogger {
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MiniXiangqi",
                            category: "nearby")
}

/// The lines a nearby run leaves behind: every state change and every wire
/// event, in one place a screen can show and a driven run can read.
@MainActor
@Observable
final class NearbyLog {
    struct Line: Identifiable {
        let id = UUID()
        let at: Date
        let text: String
    }

    /// The kept lines, oldest first. Bounded, because a long session is a long
    /// game and nothing here is a record.
    private(set) var lines: [Line] = []

    private static let kept = 300

    func note(_ text: String) {
        NearbyLogger.log.info("\(text, privacy: .public)")
        #if DEBUG
        // `devicectl --console` bridges stdout only, not OSLog: a driven device
        // run reads this feature through this print.
        print("[nearby] \(text)")
        #endif
        lines.append(Line(at: Date(), text: text))
        if lines.count > Self.kept { lines.removeFirst(lines.count - Self.kept) }
    }
}

/// A refusal the other peer sent. The session is void by the time the engine
/// reports it, so the reason is the one part of the answer no session carries.
struct NearbyDecline: Identifiable {
    let id = UUID()
    let session: String
    let peer: PeerDeviceID
    let reason: DeclineReason
    let at: Date
}

@MainActor
@Observable
final class NearbyDriver {
    private let engine: BoardGameEngine
    private let rules: any BoardGameRules
    private let log: NearbyLog

    /// The engine's sessions, republished after every input so a screen has
    /// something to observe. The engine is the authority; this is its echo.
    private(set) var sessions: [BoardGameSession] = []
    /// The paired device behind every connection this driver holds.
    private(set) var peers: [ConnectionID: PeerDeviceID] = [:]
    /// The refusals the other peer sent, oldest first.
    private(set) var declines: [NearbyDecline] = []

    @ObservationIgnored private var links: [ConnectionID: any NearbyLink] = [:]
    /// What is waiting to go out on each connection, and which connections have
    /// a task draining theirs. Per-direction order is the protocol's model, so
    /// a send that suspends must not let the next one overtake it.
    @ObservationIgnored private var outbox: [ConnectionID: [BoardGameMessage]] = [:]
    @ObservationIgnored private var pumping: Set<ConnectionID> = []

    init(rules: any BoardGameRules, log: NearbyLog,
         sessionIDs: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.rules = rules
        self.log = log
        self.engine = BoardGameEngine(rules: rules, sessionIDs: sessionIDs)
    }

    // MARK: - What the transport reports

    /// A connection is ready and the transport has named the device behind it.
    /// The engine sends `hello` itself; the resume the contract owes a
    /// returning peer follows it.
    func connectionReady(_ link: any NearbyLink, with peer: PeerDeviceID) {
        let connection = link.id
        guard links[connection] == nil else {
            log.note("Connection \(Self.short(connection)) is open here already.")
            return
        }
        links[connection] = link
        peers[connection] = peer
        log.note("Connection \(Self.short(connection)) ready with \(peer.rawValue).")
        perform(engine.connectionOpened(connection, with: peer))
        initiateResumes(with: peer, on: connection)
    }

    /// One message arrived.
    func received(_ message: BoardGameMessage, on connection: ConnectionID) {
        log.note("← \(Self.short(connection)) \(Self.describe(message))")
        perform(engine.receive(message, on: connection))
    }

    /// The transport could not read what arrived. Malformed is a violation, and
    /// the engine's verdict — a closed connection — is performed like any other.
    func receivedUnreadable(on connection: ConnectionID) {
        log.note("← \(Self.short(connection)) unreadable")
        perform(engine.receivedMalformedMessage(on: connection))
    }

    /// A connection went away, however it went: failed, cancelled, or closed by
    /// a verdict this driver performed.
    func connectionDied(_ connection: ConnectionID) {
        guard links[connection] != nil || peers[connection] != nil else { return }
        let peer = peers[connection]
        log.note("Connection \(Self.short(connection)) died.")
        forget(connection)
        engine.connectionDied(connection)
        publish()
        // A session the dead connection carried may have somewhere else to go
        // at once: the crossed connection the binding leaves standing is a
        // connection to the same device, and a session interrupted on one is
        // owed a resume on the other. Offering it here rather than only when a
        // connection first comes ready is what keeps an interrupted session
        // from waiting for a reconnection that has already happened.
        guard let peer else { return }
        for (other, its) in Array(peers) where its == peer {
            initiateResumes(with: peer, on: other)
        }
    }

    /// The contract's "It initiates `resume`, after `hello`", for every session
    /// this device holds with the peer that just came back. Which of them need
    /// one — active, or ended and unsettled — is the engine's question, and it
    /// answers by refusing the rest.
    private func initiateResumes(with peer: PeerDeviceID, on connection: ConnectionID) {
        for session in engine.sessions where session.peer == peer {
            do {
                let effects = try engine.resume(session.id, on: connection)
                log.note("Resuming \(Self.short(session.id)) on \(Self.short(connection)).")
                perform(effects)
            } catch {
                log.note("No resume for \(Self.short(session.id)) on "
                         + "\(Self.short(connection)): \(error).")
            }
        }
    }

    // MARK: - What this device's own player asks for

    func propose(to peer: PeerDeviceID, on connection: ConnectionID, rulesID: String,
                 proposerMoves: Mover) throws(BoardGameRefusal) {
        let what = "Proposing \(rulesID), taking the \(proposerMoves.rawValue) mover"
        do {
            performed(try engine.propose(to: peer, on: connection, rulesID: rulesID,
                                         proposerMoves: proposerMoves), what)
        } catch { throw refused(what, error) }
    }

    func answer(_ session: String, accepting: Bool) throws(BoardGameRefusal) {
        let what = "\(accepting ? "Accepting" : "Declining") \(Self.short(session))"
        do { performed(try engine.answer(session, accepting: accepting), what) }
        catch { throw refused(what, error) }
    }

    func play(_ text: String, in session: String) throws(BoardGameRefusal) {
        let what = "Playing \(text) in \(Self.short(session))"
        do { performed(try engine.play(text, in: session), what) }
        catch { throw refused(what, error) }
    }

    func claim(in session: String) throws(BoardGameRefusal) {
        let what = "Claiming the draw in \(Self.short(session))"
        do { performed(try engine.claim(in: session), what) }
        catch { throw refused(what, error) }
    }

    func offerDraw(in session: String) throws(BoardGameRefusal) {
        let what = "Offering a draw in \(Self.short(session))"
        do { performed(try engine.offerDraw(in: session), what) }
        catch { throw refused(what, error) }
    }

    func acceptDraw(in session: String) throws(BoardGameRefusal) {
        let what = "Accepting the draw in \(Self.short(session))"
        do { performed(try engine.acceptDraw(in: session), what) }
        catch { throw refused(what, error) }
    }

    func requestUndo(keeping keep: Int, in session: String) throws(BoardGameRefusal) {
        let what = "Requesting an undo down to \(keep) in \(Self.short(session))"
        do { performed(try engine.requestUndo(keeping: keep, in: session), what) }
        catch { throw refused(what, error) }
    }

    func acceptUndo(in session: String) throws(BoardGameRefusal) {
        let what = "Accepting the undo in \(Self.short(session))"
        do { performed(try engine.acceptUndo(in: session), what) }
        catch { throw refused(what, error) }
    }

    func resign(in session: String) throws(BoardGameRefusal) {
        let what = "Resigning \(Self.short(session))"
        do { performed(try engine.resign(in: session), what) }
        catch { throw refused(what, error) }
    }

    /// Whether the claimed draw is lawful as this device's next ply — the rules
    /// oracle's answer, which is the one the engine itself asks for when the
    /// claim is played. Nothing is re-derived here: both the affordance and the
    /// legality come from the core, through the oracle the engine holds.
    func claimStands(in session: BoardGameSession) -> Bool {
        guard session.isInPlay, session.isLocalTurn else { return false }
        return rules.verdict(for: TurnAction.claim, after: session.plies,
                             of: session.rulesID) != .unlawful
    }

    /// Every session this driver holds with that device, whatever its state.
    func sessions(with peer: PeerDeviceID) -> [BoardGameSession] {
        sessions.filter { $0.peer == peer }
    }

    /// Closes every connection this driver holds — the harness's Stop, and
    /// nothing else.
    func closeEverything() {
        for connection in Array(links.keys) {
            links[connection]?.close()
            connectionDied(connection)
        }
    }

    // MARK: - Performing what the engine answers with

    /// An intent of this device's own player that the engine allowed. Every one
    /// of them is written out rather than routed through one closure-taking
    /// helper: a closure literal passed to such a helper infers `any Error` for
    /// its thrown type, and the refusal these intents promise would be lost.
    private func performed(_ effects: [BoardGameEffect], _ what: String) {
        log.note("\(what).")
        perform(effects)
    }

    /// One the engine refused, logged and handed back to be thrown.
    private func refused(_ what: String, _ refusal: BoardGameRefusal) -> BoardGameRefusal {
        log.note("\(what) refused: \(refusal).")
        return refusal
    }

    private func perform(_ effects: [BoardGameEffect]) {
        for effect in effects {
            switch effect {
            case .send(let message, let connection):
                enqueue(message, on: connection)
            case .close(let connection, let verdict):
                close(connection, verdict)
            case .declined(let session, let peer, let reason):
                log.note("\(Self.short(session)) refused by \(peer.rawValue): \(reason.rawValue).")
                declines.append(NearbyDecline(session: session, peer: peer,
                                              reason: reason, at: Date()))
            }
        }
        publish()
    }

    private func enqueue(_ message: BoardGameMessage, on connection: ConnectionID) {
        guard links[connection] != nil else {
            log.note("Nowhere to send \(Self.describe(message)): "
                     + "\(Self.short(connection)) is gone.")
            return
        }
        outbox[connection, default: []].append(message)
        pump(connection)
    }

    /// One task per connection drains its queue, so two sends never race and
    /// the order the engine produced them in is the order they leave in.
    ///
    /// Nothing else ever clears the pumping mark: the task that set it is the
    /// one that clears it, so a connection cannot end up with two pumps, and a
    /// message enqueued in the instant one is finishing is picked up by the
    /// same loop — the check and the mark are one synchronous step on this
    /// actor, with no suspension between them.
    private func pump(_ connection: ConnectionID) {
        guard !pumping.contains(connection) else { return }
        pumping.insert(connection)
        Task { [self] in
            defer { pumping.remove(connection) }
            while true {
                guard let link = links[connection],
                      var queue = outbox[connection], !queue.isEmpty
                else { return }
                let message = queue.removeFirst()
                outbox[connection] = queue
                do {
                    try await link.send(message)
                    log.note("→ \(Self.short(connection)) \(Self.describe(message))")
                } catch {
                    log.note("Send failed on \(Self.short(connection)): \(error).")
                    connectionDied(connection)
                    return
                }
            }
        }
    }

    /// A close verdict, performed. The engine has already voided whatever the
    /// connection carried, so this is the transport half alone.
    private func close(_ connection: ConnectionID, _ verdict: CloseVerdict) {
        log.note("Closing \(Self.short(connection)): \(Self.describe(verdict)).")
        let link = links[connection]
        forget(connection)
        link?.close()
    }

    private func forget(_ connection: ConnectionID) {
        outbox[connection] = nil
        links[connection] = nil
        peers[connection] = nil
    }

    private func publish() {
        sessions = engine.sessions
    }

    // MARK: - Reading the traffic

    /// The tail of an identifier, which is what a log line has room for and
    /// what a person compares across two devices.
    static func short(_ text: String) -> String { String(text.suffix(8)) }
    static func short(_ connection: ConnectionID) -> String { short(connection.rawValue) }

    static func describe(_ message: BoardGameMessage) -> String {
        switch message {
        case .hello(let hello):
            "hello protocol=\(hello.protocolVersion)"
        case .propose(let propose):
            "propose \(short(propose.session)) \(propose.rulesID)@\(propose.rulesVersion) "
                + "proposer=\(propose.proposerMoves.rawValue)"
        case .accept(let accept):
            "accept \(short(accept.session))"
        case .decline(let decline):
            "decline \(short(decline.session)) \(decline.reason.rawValue)"
        case .move(let move):
            "move \(short(move.session)) #\(move.index) \(move.move)"
        case .offerDraw(let offer):
            "offer_draw \(short(offer.session)) at=\(offer.at)"
        case .acceptDraw(let accept):
            "accept_draw \(short(accept.session))"
        case .requestUndo(let request):
            "request_undo \(short(request.session)) at=\(request.at) keep=\(request.keep)"
        case .acceptUndo(let accept):
            "accept_undo \(short(accept.session))"
        case .resign(let resign):
            "resign \(short(resign.session))"
        case .resume(let resume):
            "resume \(short(resume.session)) undos=\(resume.undos) count=\(resume.count) "
                + "keep=\(resume.keep) end=\(resume.end?.rawValue ?? "—")"
        }
    }

    static func describe(_ verdict: CloseVerdict) -> String {
        switch verdict {
        case .violation(let violation): "\(violation.kind) — \(violation.detail)"
        case .unsupportedVersion(let version): "protocol \(version) is not spoken here"
        }
    }
}
