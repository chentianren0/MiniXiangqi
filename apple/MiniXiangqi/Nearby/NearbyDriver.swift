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
// Where the contract says a peer *may* — the exchange an unsettled peer opens
// on a live connection — the moment is this layer's to choose, because a moment
// is timing rather than permission; what the driver reads to choose it is the
// session's own derived answer, and whether the exchange is allowed at all is
// still the engine's.
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
    ///
    /// **It may throw only when the link is already dying.** A send failure is
    /// the one thing the driver reads as the connection's death, so a link that
    /// threw and then lived on would be a connection the transport still holds
    /// ready while the driver has forgotten it — nothing would dial it again,
    /// and the pair would sit idle until the radio timed it out. The driver
    /// closes such a link rather than trusting this, but a link that needs that
    /// close is already broken.
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

    /// A line of protocol traffic, which is public: it is what a driven run
    /// reads out of the system log, and none of it names a person or a device.
    func note(_ text: String) {
        NearbyLogger.log.info("\(text, privacy: .public)")
        mirror(text)
    }

    /// A line naming a device, whose name stays out of the public log stream.
    /// A device's name is routinely its owner's own name, and the system log is
    /// read far beyond this app. The rest of the line — the connection, the
    /// peer identifier, whatever a driven run compares — is public as ever, and
    /// the name itself is whole on this device's own screen and in the DEBUG
    /// console, neither of which leaves the device.
    func note(_ text: String, naming device: String, _ rest: String = "") {
        NearbyLogger.log.info(
            "\(text, privacy: .public)\(device, privacy: .private)\(rest, privacy: .public)")
        mirror(text + device + rest)
    }

    private func mirror(_ text: String) {
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
    /// How many of this device's own plies the library has refused to record.
    /// It only grows, so the board can tell a fresh refusal from one it has
    /// already spoken about.
    private(set) var ownMoveRefusals = 0

    /// The store's memory of the game being played, where this driver has one.
    /// Absent in the tests that are about the protocol and on the staged board,
    /// neither of which has a library.
    @ObservationIgnored private let record: (any NearbyRecording)?

    @ObservationIgnored private var links: [ConnectionID: any NearbyLink] = [:]
    /// What is waiting to go out on each connection, and which connections have
    /// a task draining theirs. Per-direction order is the protocol's model, so
    /// a send that suspends must not let the next one overtake it.
    @ObservationIgnored private var outbox: [ConnectionID: [BoardGameMessage]] = [:]
    @ObservationIgnored private var pumping: Set<ConnectionID> = []
    /// Whether a settling exchange is being opened right now. Performing one
    /// publishes again, and this is what makes the one level of re-entrance
    /// that follows evident rather than merely bounded.
    @ObservationIgnored private var pursuingSettlement = false

    init(rules: any BoardGameRules, log: NearbyLog,
         record: (any NearbyRecording)? = nil,
         sessionIDs: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.rules = rules
        self.log = log
        self.record = record
        self.engine = BoardGameEngine(rules: rules, sessionIDs: sessionIDs)
    }

    // MARK: - The game the library is holding

    /// Take up the interrupted nearby game the library holds, if it holds one,
    /// so that the connection the transport is about to make finds a session to
    /// resume. Answers the session's identifier where there was one.
    ///
    /// It is called when the player comes back to the game and never at launch:
    /// a nearby game needs the other person, so recovery is theirs to start.
    func resumeStoredGame() -> String? {
        guard let record else { return nil }
        let stored: BoardGameSession?
        do {
            stored = try record.standing()
        } catch {
            log.note("The library would not give back its nearby game: "
                     + "\(CoreError(wrapping: error)).")
            return nil
        }
        guard let stored else { return nil }
        engine.adopt(stored)
        publish()
        // Whatever connections already stand are owed the resume the contract
        // says an interrupted session initiates.
        for (connection, peer) in peers where peer == stored.peer {
            initiateResumes(with: peer, on: connection)
        }
        return stored.id
    }

    /// Give up the game the library holds: the player filed it, or started
    /// another one over it. The session is forgotten here as a void one is, and
    /// the other peer learns of it from its next resume.
    func abandonStoredGame() {
        guard let record else { return }
        for session in engine.sessions where session.state != .proposed {
            engine.abandon(session.id)
            log.note("\(Self.short(session.id)) given up: the library holds "
                     + "another game now.")
        }
        record.release()
        publish()
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
                // An exchange already open is the ordinary sight here, not a
                // fault: the settlement pursuit runs from the publication that
                // announced this connection, and a crossed connection can be
                // carrying the session's resume already.
                if error == .resumeOutstanding {
                    log.note("\(Self.short(session.id)) already has its exchange "
                             + "open on \(Self.short(connection)).")
                } else {
                    log.note("No resume for \(Self.short(session.id)) on "
                             + "\(Self.short(connection)): \(error).")
                }
            }
        }
    }

    /// The contract's "an unsettled peer may also open the exchange on the
    /// session's live connection", taken the moment there is an end to settle
    /// and a connection to settle it on.
    ///
    /// Settlement rides a resume exchange and nothing else, so the peer that
    /// ended the game — it sent the terminal, or its own ply decided the end —
    /// stays unsettled until one completes for it. Waiting for the next
    /// connection to open that exchange strands exactly that peer: the other
    /// side settles as the ending arrives, files its copy, leaves the board,
    /// and its radio rests, so the connection this side was waiting to be given
    /// again is the one that was standing all along.
    ///
    /// It converges on its own. Opening the exchange puts one in flight, which
    /// is what `awaitsSettlement` denies, so nothing here repeats while it
    /// stands; when it completes the session is settled and there is nothing
    /// left to pursue. Two cases come round again, each bounded by that same
    /// denial: a terminal taken mid-exchange, which the completion sends as the
    /// ordinary message it is and which the next exchange states in its `end`
    /// and settles — and an exchange whose connection dies under it, which the
    /// next connection to the peer opens afresh.
    private func pursueSettlement() {
        guard !pursuingSettlement else { return }
        pursuingSettlement = true
        defer { pursuingSettlement = false }
        for (id, connection) in settlingExchangesOwed() {
            do {
                let effects = try engine.resume(id, on: connection)
                log.note("Settling \(Self.short(id)) on \(Self.short(connection)).")
                perform(effects)
            } catch {
                // A connection dying in the same instant is the ordinary race:
                // the engine has let go of it, the session keeps its end, and
                // the next connection to come ready is owed the resume as any
                // interrupted session is.
                log.note("No settling resume for \(Self.short(id)) on "
                         + "\(Self.short(connection)): \(error).")
            }
        }
    }

    /// Each session waiting to be settled, with the connection to open its
    /// exchange on: the one it is bound to where this driver still holds that
    /// link, and otherwise whichever it holds to that peer.
    private func settlingExchangesOwed() -> [(String, ConnectionID)] {
        engine.sessions.compactMap { session -> (String, ConnectionID)? in
            guard session.awaitsSettlement,
                  let connection = connection(to: session.peer,
                                              preferring: session.connection)
            else { return nil }
            return (session.id, connection)
        }
    }

    private func connection(to peer: PeerDeviceID,
                            preferring bound: ConnectionID?) -> ConnectionID? {
        if let bound, links[bound] != nil, peers[bound] == peer { return bound }
        // Sorted rather than whichever the dictionary offers first, so two
        // crossed connections to one device settle on the same one every run.
        // Swift's own string ordering serves here: connection identifiers are
        // transport-local and never compared across devices, so the wire case
        // `WireBytes` exists for is not this one.
        return links.keys.filter { peers[$0] == peer }
            .min { $0.rawValue < $1.rawValue }
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
                    // `NearbyLink.send` promises to throw only when the link is
                    // already dying, and this closes it anyway: a link that
                    // broke that promise would otherwise be left standing on a
                    // transport that thinks it healthy, with no driver holding
                    // it and nothing to dial it again.
                    link.close()
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
        let before = sessions
        sessions = engine.sessions
        noteEnds(after: before)
        // The library follows every publication rather than selected events:
        // the engine is the authority on what the two devices have agreed the
        // game is, and this hands it that whole answer once per input instead
        // of a list of the changes somebody remembered to report.
        record?.follow(sessions)
        if let record { ownMoveRefusals = record.ownMoveRefusals }
        // Every engine input funnels through here, so this is where an end
        // appears the instant it is reached — the one this device's own player
        // just took, and the one an arriving message completed. Last, so that
        // what it performs publishes over this rather than under it.
        pursueSettlement()
    }

    /// The line a finished game leaves behind, said once, when the session's
    /// end first appears. An end is derived from the plies and the terminals
    /// rather than sent or stored, so no effect announces one and nothing else
    /// in a run's log says how a game finished — only the screen did. It states
    /// settledness beside the end because the two are a pair: an end this peer
    /// holds unsettled still owes a resume exchange.
    private func noteEnds(after before: [BoardGameSession]) {
        let ended = Set(before.filter { $0.end != nil }.map(\.key))
        for session in sessions {
            guard let end = session.end, !ended.contains(session.key) else { continue }
            log.note("\(Self.short(session.id)) ended: \(Self.describe(end)), "
                     + "\(session.settled ? "settled" : "unsettled").")
        }
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

    /// An end as the screen states it, so a log line and the session's details
    /// read the same.
    static func describe(_ end: BoardGameEnd) -> String {
        "\(end.result)/\(end.ending)"
    }

    static func describe(_ verdict: CloseVerdict) -> String {
        switch verdict {
        case .violation(let violation): "\(violation.kind) — \(violation.detail)"
        case .unsupportedVersion(let version): "protocol \(version) is not spoken here"
        }
    }
}
