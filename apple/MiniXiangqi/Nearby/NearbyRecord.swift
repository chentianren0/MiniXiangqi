// The store's memory of a nearby game.
//
// The board a nearby game is played on is a projection: it draws a position the
// session-free rules facade derives from the engine's ply list, and it persists
// nothing. The engine is the authority on what the two devices have agreed the
// game is. This is the one place that turns that authority into the library's
// active game — created when a session becomes active, rewritten as plies land
// from either side, filed into History when the two devices have settled on an
// ending — and back again, so an interrupted game survives a relaunch.
//
// **The seam is the driver's publication, not the board.** Every engine input,
// local or remote, funnels through one publish, and a ply can land while the
// board is down: the driver and the engine live as long as the app does, and
// leaving the board is the interruption the protocol already models. So this is
// held by the driver and told what the engine holds, once per input.
//
// **It writes what the engine holds; it decides nothing.** Which plies the game
// has, whether a retraction happened, whether the two peers have settled on an
// end and which end it is are all read off the session. What is decided here is
// only the store's own question: which core call carries that state, and when.

import Foundation

/// The store's memory of a nearby game, as the driver needs it.
///
/// A protocol so the driver can be driven without a library — the staged board,
/// and the engine tests, which are about the protocol and have no store.
@MainActor
protocol NearbyRecording: AnyObject {
    /// The interrupted nearby game the store holds, rebuilt as the session it
    /// was being played over. Nil where the library holds no nearby game to
    /// come back to.
    ///
    /// It opens the store's session and keeps it: the caller is about to hand
    /// this to the engine, and what it hands over and what this holds are one
    /// game.
    func standing() throws -> BoardGameSession?

    /// What the engine holds now. Called once per engine input.
    func follow(_ sessions: [BoardGameSession])

    /// Let go of the store's session without ending the game. The library keeps
    /// its active game, and the next `standing()` reads it back.
    func release()

    /// How many committed writes the library has refused on a ply of this
    /// device's player's own. It only grows, so the board can tell a fresh
    /// refusal from one it has already spoken about.
    ///
    /// A refusal following the *other* player's ply is not here: the store
    /// re-applies on the next publication, the retry is the app's rather than
    /// the player's, and the local board keeps exactly the same two apart.
    var ownMoveRefusals: Int { get }
}

/// The store's memory of a nearby game, over the shared core's library.
@MainActor
final class NearbyRecord: NearbyRecording {
    private let library: any NearbyLibrary
    /// The rules the restore asks one question of: what the stored line
    /// decides. It is the same oracle the protocol engine asks, over the same
    /// core, so a restored session's settledness cannot disagree with the
    /// engine's own reading of the same plies.
    private let rules: any BoardGameRules
    private let log: NearbyLog

    private(set) var ownMoveRefusals = 0

    /// The session a no-room refusal was last logged for. The retry itself is
    /// harmless and self-heals, but a line per wire message is a line that
    /// pushes the rest of a bounded log out.
    private var refusedRoomFor: String?

    /// The session this record is the memory of, as it last stood, and whether
    /// the store's session is attached to its game.
    ///
    /// The copy is held because a void takes the session out of the engine's
    /// list, and what the game ended as — where it ended at all — is exactly
    /// what has to be filed then.
    private var held: BoardGameSession?
    private var attached = false

    /// What the store's wire session holds, as this record last wrote it. It is
    /// the record of a committed write and not a second authority: every write
    /// sets it, and a failed write leaves it where it was so the next
    /// publication tries again.
    private var written: NearbyWireSession?

    init(library: any NearbyLibrary, rules: any BoardGameRules, log: NearbyLog) {
        self.library = library
        self.rules = rules
        self.log = log
    }

    // MARK: - Coming back to an interrupted game

    func standing() throws -> BoardGameSession? {
        guard held == nil else { return held }
        guard let summary = try library.activeGameSummary(),
              summary.mode == .nearby, let localSide = summary.localSide
        else { return nil }
        guard !library.hasSession else {
            log.note("The library's nearby game is held by another surface.")
            return nil
        }
        guard try library.resumeActive() else { return nil }
        attached = true
        guard let wire = try library.nearbyWireSession() else {
            // A nearby active game the protocol has already parted with: there
            // is nothing to resume, and it is the player's to file.
            log.note("The library's nearby game carries no wire session.")
            library.endSession()
            attached = false
            return nil
        }
        guard let session = Self.session(over: wire, game: summary.game,
                                         localSide: localSide,
                                         moves: try library.moveHistory(),
                                         rules: rules)
        else {
            // A dealt game whose stored handshake no longer derives the deal it
            // says it does. There is no position to play the line over, so
            // there is no session to give back; the game stays the library's
            // active one for the player to file.
            log.note("The library's nearby game does not verify against its "
                     + "own deal.")
            library.endSession()
            attached = false
            return nil
        }
        held = session
        written = wire
        log.note("Rebuilt \(NearbyDriver.short(session.id)) from the library: "
                 + "\(session.count) plies, undos=\(wire.undos), "
                 + "end=\(wire.sentEnd.map(String.init(describing:)) ?? "—").")
        return session
    }

    /// A stored game and its wire session as the session the two devices were
    /// playing.
    ///
    /// Everything the protocol needs is here or derived from here, and nothing
    /// is invented: the mover comes from the store's own local side, the
    /// proposer's mover follows from it and from which peer proposed, and the
    /// plies are the committed move line with the claim the archive does not
    /// record put back on the end.
    ///
    /// **What is deliberately not restored is what the protocol voids anyway.**
    /// A pending offer or request does not survive the connection that carried
    /// it, and a relaunch is at least that; the connection and the exchange are
    /// per-connection by construction. The session comes back interrupted,
    /// which is what it is.
    ///
    /// **What a dealt session persists is the handshake, not the deal**, so the
    /// deal is derived from the stored seed and nonce again here — and verified
    /// against everything it comes from before anything is played over it. Nil
    /// where that fails, and where the row's deal and the game's disagree about
    /// whether there should be one.
    private static func session(over wire: NearbyWireSession, game: GameKind,
                                localSide: Side, moves: [String],
                                rules: any BoardGameRules) -> BoardGameSession? {
        let deals = rules.dealsItsStart(game.rulesID)
        guard deals == (wire.deal != nil) else { return nil }
        var handshake: DealHandshake?
        if let stored = wire.deal {
            guard let deal = BoardGameDeal.verified(
                commit: stored.commit, nonce: stored.nonce, seed: stored.seed,
                digest: stored.digest, of: game.rulesID, by: rules)
            else { return nil }
            handshake = .dealt(deal)
        }
        let localMover: Mover = localSide == .red ? .first : .second
        let proposerMoves = wire.proposedLocally ? localMover : localMover.opponent
        var session = BoardGameSession(
            id: wire.sessionID, peer: PeerDeviceID(wire.peerID),
            rulesID: game.rulesID,
            rulesVersion: CoreBoardGameRules.interpretationVersion,
            proposerMoves: proposerMoves,
            proposer: wire.proposedLocally ? .local : .peer)
        session.accepted = true
        session.handshake = handshake
        session.plies = wire.claimed ? moves + [TurnAction.claim] : moves
        session.undos = wire.undos
        session.retractedTo = wire.undos > 0 ? wire.keep : nil
        switch wire.sentEnd {
        case .resign: session.localTerminal = .resign
        case .acceptDraw: session.localTerminal = .acceptDraw
        case nil: break
        }
        // What the stored line decides, asked of the same oracle the engine
        // asks. It is not read out of the row: an end the rules decided is a
        // property of the plies, and a second copy of it in the store would be
        // a second place for it to be wrong.
        session.rulesEnd = rules.standing(after: session.plies,
                                          from: session.dealtStart,
                                          of: session.rulesID).decision
        // Settledness, by the contract's own rule and by both of its halves: a
        // peer that sent a terminal, **or whose own ply decided the end**,
        // holds the session unsettled until a resume exchange completes for it.
        // The second half is every rules-decided end this device played —
        // a mate, a stalemate, a claim — and not the claim alone.
        //
        // A game the *other* peer's terminal or ply ended was settled here the
        // moment it arrived, so it was filed rather than left standing; a row
        // still holding one is a filing that did not commit, and it comes back
        // settled and files on the next publication.
        session.settled = session.localTerminal == nil
            && !session.ownPlyDecidedTheEnd
        return session
    }

    // MARK: - Following the engine

    func follow(_ sessions: [BoardGameSession]) {
        if let standing = held {
            guard let live = sessions.first(where: { $0.key == standing.key })
            else {
                // The engine parted with it: an `unknown_session` answer, a
                // peer's fresh proposal, or a violation. The protocol says the
                // session is void on both sides, so there is no way back into
                // this game, and an active game nothing can play is not one to
                // leave in the library. It is filed as it stands.
                fileAway(standing, voided: true)
                return
            }
            held = live
            guard attached else { return }
            adopt(live)
            return
        }
        guard let live = Self.recordable(sessions) else { return }
        begin(live)
    }

    func release() {
        guard attached else { return }
        library.endSession()
        attached = false
        held = nil
        written = nil
    }

    /// The session the library's one active game is of: the game being played,
    /// or the finished one still settling. A proposal is not a game yet, and a
    /// settled finished session is one this record has already filed.
    private static func recordable(_ sessions: [BoardGameSession]) -> BoardGameSession? {
        sessions.first { $0.state == .active }
            ?? sessions.first { $0.state == .ended && !$0.settled }
    }

    // MARK: - Creating

    /// A session that has just become active, as the library's active game.
    ///
    /// It is created at its birth and then caught up, rather than created at
    /// whatever length it happens to have: the core takes a wire session at
    /// birth only, and a line applied ply by ply is a line the rules accepted
    /// ply by ply.
    private func begin(_ session: BoardGameSession) {
        guard let game = GameKind(rulesID: session.rulesID) else { return }
        // The library already holds a game, and this record is not the surface
        // that puts one down: the nearby entry asks for the slot before a
        // session is ever accepted, so reaching this means the slot was taken
        // between the asking and the acceptance.
        //
        // The attempt itself is repeated on every publication, because the room
        // can be made at any moment and the next wire message is as good a time
        // to notice as any; what is said about it is not. A line per message
        // would push the rest of a bounded log out of it, so the refusal is
        // stated once per session.
        guard !library.hasSession else {
            noteNoRoom(session, "another surface holds the active game.")
            return
        }
        do {
            guard try library.activeGameSummary() == nil else {
                noteNoRoom(session, "it holds another game.")
                return
            }
        } catch {
            log.note("The library would not say what it holds: "
                     + "\(CoreError(wrapping: error)).")
            return
        }
        let localSide: Side = session.localMover == .first ? .red : .black
        // A dealt game's start is the deal, and the three values it came from
        // stand beside it: they are facts about the game rather than about
        // either device, and what makes the finished record checkable by
        // anybody. The digest is not among the archive's three and is here for
        // the session's own re-verification.
        let birth = NearbyWireSession(sessionID: session.id,
                                      peerID: session.peer.rawValue,
                                      proposedLocally: session.proposer == .local,
                                      deal: Self.deal(of: session))
        do {
            try library.createNearby(.nearby(game: game, localSide: localSide,
                                             startFEN: session.dealtStart),
                                     wire: birth)
        } catch {
            log.note("The library refused \(NearbyDriver.short(session.id)): "
                     + "\(CoreError(wrapping: error)).")
            return
        }
        attached = true
        held = session
        written = birth
        refusedRoomFor = nil
        // The side is named through the game, as every surface names one: `Side`
        // is the core's first-mover axis, and a line that spelled it 红 would
        // tell a Gomoku player holding black stones they had red ones.
        log.note("\(NearbyDriver.short(session.id)) is the library's active "
                 + "game, \(game.sideName(localSide)) here.")
        adopt(session)
    }

    /// The no-room refusal, said once for the session it is about.
    private func noteNoRoom(_ session: BoardGameSession, _ why: String) {
        guard refusedRoomFor != session.id else { return }
        refusedRoomFor = session.id
        log.note("No room in the library for "
                 + "\(NearbyDriver.short(session.id)): \(why)")
    }

    // MARK: - Keeping the library in step

    /// The library brought to what the engine holds: the move line first, then
    /// the wire session, then the ending if the two devices have settled on one.
    private func adopt(_ session: BoardGameSession) {
        let wire = Self.wire(of: session, over: written)
        guard align(session, to: wire) else { return }
        guard session.end != nil, session.settled else { return }
        fileAway(session, voided: false)
    }

    /// The wire session the engine's copy states, keeping the identity the
    /// library was created with: identity is frozen, and a session identifier
    /// this record did not create is not this game's.
    private static func wire(of session: BoardGameSession,
                             over written: NearbyWireSession?) -> NearbyWireSession {
        NearbyWireSession(sessionID: written?.sessionID ?? session.id,
                          peerID: written?.peerID ?? session.peer.rawValue,
                          proposedLocally: written?.proposedLocally
                              ?? (session.proposer == .local),
                          undos: session.undos,
                          // The surviving count of the last accepted
                          // retraction, and zero where there has been none —
                          // deliberately not `reportedKeep`, which is the live
                          // count there and would move with every ply, making
                          // every accepted ply a second committed transaction
                          // for a value the restore then ignores.
                          keep: session.retractedTo ?? 0,
                          sentEnd: Self.terminal(session.localTerminal),
                          claimed: session.plies.last == TurnAction.claim,
                          // Frozen with the identity, and for the same reason:
                          // "a session's identity is not something a later call
                          // revises, and its deal is what the game is being
                          // played over".
                          deal: written?.deal ?? Self.deal(of: session))
    }

    /// The four values the row keeps of a dealt session's handshake. Nil for
    /// every game whose start is frozen, which is the row's own pairing.
    private static func deal(of session: BoardGameSession) -> NearbyWireSession.Deal? {
        session.deal.map {
            .init(commit: $0.commit, nonce: $0.nonce, seed: $0.seed, digest: $0.digest)
        }
    }

    private static func terminal(_ terminal: Terminal?) -> WireTerminal? {
        switch terminal {
        case .resign: .resign
        case .acceptDraw: .acceptDraw
        case nil: nil
        }
    }

    /// The committed move line, which is the ply list without the claim: the
    /// archive records a claimed draw as its terminal trio and never as a move,
    /// so one game has one recorded move line however it was played.
    private static func line(of session: BoardGameSession) -> [String] {
        session.plies.last == TurnAction.claim ? Array(session.plies.dropLast())
                                               : session.plies
    }

    /// Brings the library's move line and wire session to the session's, and
    /// answers whether it got there.
    ///
    /// The order is the one the store's own invariant asks for: a retraction
    /// carries the counts that produced it in its own transaction, plies carry
    /// the counts they did not change, and what is left over — a terminal this
    /// device sent, a claim, which move neither — is written on its own.
    private func align(_ session: BoardGameSession,
                       to wire: NearbyWireSession) -> Bool {
        do {
            let stored = try library.moveHistory()
            let wanted = Self.line(of: session)
            let shared = zip(stored, wanted).prefix { $0.0 == $0.1 }.count
            if shared < stored.count {
                try library.retractNearby(to: shared, wire: wire)
                written = wire
                log.note("\(NearbyDriver.short(session.id)) retracted to "
                         + "\(shared) in the library, undos=\(wire.undos).")
            }
            for move in wanted.dropFirst(shared) {
                try library.apply(move)
            }
            if written != wire {
                try library.setNearbyWireSession(wire)
                written = wire
            }
            return true
        } catch {
            // **A nearby ply is not left at its pre-mutation state, because it
            // is not this device's to take back.** It has gone on the wire and
            // the other peer has accepted it; the game the two devices are
            // playing has it, and what failed is the library's memory of it.
            // The next publication realigns from whatever the library holds, so
            // this heals itself in the ordinary case.
            //
            // The player is told, and only about a ply of their own: a refusal
            // following the other player's ply is the app's to heal rather than
            // theirs to act on, which is the same line the local board draws
            // between its own two refusals.
            log.note("The library would not follow "
                     + "\(NearbyDriver.short(session.id)): "
                     + "\(CoreError(wrapping: error)).")
            if session.count > 0,
               Mover.atPly(session.count - 1) == session.localMover {
                ownMoveRefusals += 1
            }
            return false
        }
    }

    // MARK: - Filing

    /// The game into History, by the ending the two devices reached — or, where
    /// the session went away without one, by the store's own classification of
    /// a game that stopped.
    private func fileAway(_ session: BoardGameSession, voided: Bool) {
        guard attached else {
            held = nil
            written = nil
            return
        }
        if voided, session.end == nil {
            // No result, and no way back to the game: the library's own
            // archive-and-clear decides what a game that stopped is worth, as
            // it does for 保存并继续.
            let id = session.id
            library.archiveActiveAndClear { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let record):
                    log.note("\(NearbyDriver.short(id)) filed as it stood, "
                             + "record \(record).")
                case .failure(let error):
                    // A refusal puts the session back, and the game is still
                    // the library's active one. It is the player's to file from
                    // the home, exactly as any interrupted game is, and this
                    // record has nothing more to do with it.
                    log.note("\(NearbyDriver.short(id)) would not file: \(error).")
                    library.endSession()
                }
                attached = false
            }
            held = nil
            written = nil
            return
        }
        guard let end = session.end else { return }
        do {
            let record = try file(end, of: session)
            log.note("\(NearbyDriver.short(session.id)) filed into History as "
                     + "\(NearbyDriver.describe(end)), record \(record).")
            library.endSession()
            attached = false
            held = nil
            written = nil
        } catch {
            log.note("\(NearbyDriver.short(session.id)) would not file: "
                     + "\(CoreError(wrapping: error)).")
        }
    }

    /// Which terminal commit an ending is. The three the two players declare to
    /// each other are the fourth commit's; an end the rules decided is the
    /// board's own verdict, and the core already holds it — the claimed draw
    /// through the claim, everything else through the confirmation.
    private func file(_ end: BoardGameEnd, of session: BoardGameSession) throws -> UInt64 {
        switch end.ending {
        case .rulesDecided:
            return session.plies.last == TurnAction.claim
                ? try library.claimDraw()
                : try library.confirmResult()
        case .agreedDraw:
            return try library.commitNearbyEnd(.agreedDraw)
        case .bothResigned:
            return try library.commitNearbyEnd(.mutualResignation)
        case .resignation(let party):
            let mover = party == .local ? session.localMover : session.peerMover
            return try library.commitNearbyEnd(
                .resignation(mover == .first ? .red : .black))
        }
    }
}
