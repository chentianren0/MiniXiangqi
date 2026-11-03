// A game with somebody on another device, one engine per mode, over whichever
// carrier reaches them.
//
// The game in play is the library's active record of this mode, and the engine
// writes it as it goes: every move as it lands, a takeback, the ending. Both
// devices write the same record under the same id. Only what a dropped
// connection voids anyway lives here: proposals, a standing offer, and whether
// the current connection's resume exchange is done.
//
// Endings agree on both devices. A result from the rules needs no message. An
// ending a player chooses is written to the record, marked undelivered, before
// it is sent. On every new connection each device sends a resume for the game
// in play and for every undelivered ending: its moves, its takebacks and its
// chosen ending. Each merges the other's by one rule (`PeerEnding.settled`), so
// two endings that crossed, or one that a drop delayed, come out the same on
// both. A message that makes no sense ends the game early on both devices.

import Foundation
import Observation
import OSLog

nonisolated enum NearbyLogger {
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MiniXiangqi",
                            category: "nearby")

    static func note(_ text: String) {
        log.info("\(text, privacy: .public)")
    }
}

/// One connection to the other device. The carrier tells the engine when one
/// opens, what arrives on it, and when it closes.
@MainActor
protocol PeerLink: AnyObject {
    func send(_ message: PeerMessage)
    func close()
}

nonisolated struct PeerProposal: Equatable, Sendable {
    var game: UUID
    var peer: String
    var kind: GameKind
    var proposerSide: Side
    var seed: String?
}

/// The one offer that may stand, until the next move.
nonisolated struct PeerOffer: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case draw, takeback }

    var kind: Kind
    var fromPeer: Bool
    /// The moves on the board when it was made.
    var ply: Int
}

/// Why a game went away without a result.
nonisolated enum NearbyVoid: Equatable, Sendable {
    /// The other device no longer has it.
    case lostByPeer
    /// A message made no sense.
    case disagreement
    /// The other player proposed a new game.
    case retired

    var message: String {
        switch self {
        case .lostByPeer: String(localized: "nearby.refusal.unknownSession")
        case .disagreement: String(localized: "nearby.ended.disagreement")
        case .retired: String(localized: "nearby.ended.newGame")
        }
    }
}

/// The game a board shows, as the engine last wrote it.
nonisolated struct PeerGame: Equatable, Sendable {
    var id: UUID
    var kind: GameKind
    var localSide: Side
    var start: String
    var moves: [String]
    /// The result, once there is one.
    var outcome: Outcome?
    var reason: EndReason?
    /// The other device is connected.
    var linked: Bool
    /// Connected, resumed, and still going: moves and offers may travel.
    var inPlay: Bool
    var localTurn: Bool
    var claimable: Bool
    /// An ending this device chose that the other has not shown it holds.
    var undelivered: Bool
    var offer: PeerOffer?
    var voided: NearbyVoid?

    var isOver: Bool { outcome != nil || voided != nil }
}

@MainActor
@Observable
final class PeerEngine {
    let mode: PlayMode
    let library: GameLibrary

    /// The devices connected now, by id, with the name each gave.
    private(set) var connected: [String: String] = [:]
    /// The proposal this device sent and is waiting on.
    private(set) var outgoing: PeerProposal?
    /// The proposal waiting for this device's player.
    private(set) var incoming: PeerProposal?
    /// The game a board shows: the one in play, or the last one until the
    /// board lets it go.
    private(set) var game: PeerGame?

    /// The other device declined this device's proposal; true when busy.
    @ObservationIgnored var declined: ((Bool) -> Void)?
    /// This device's proposal became a game.
    @ObservationIgnored var started: ((UUID) -> Void)?
    @ObservationIgnored var libraryChanged: (() -> Void)?

    @ObservationIgnored private var links: [String: any PeerLink] = [:]
    /// The games whose resume has gone out on each peer's current link.
    @ObservationIgnored private var resumed: [String: Set<UUID>] = [:]
    @ObservationIgnored private var shown: UUID?
    @ObservationIgnored private var inPlay = false
    @ObservationIgnored private var offer: PeerOffer?
    @ObservationIgnored private var voided: NearbyVoid?

    init(mode: PlayMode, library: GameLibrary) {
        self.mode = mode
        self.library = library
    }

    // MARK: - The carrier

    /// A connection to `peer` is up. A newer one replaces an older.
    func opened(_ link: any PeerLink, peer: String, name: String) {
        let old = links[peer]
        links[peer] = link
        old?.close()
        lost(peer)
        connected[peer] = name
        if let record = active(), record.peer == peer {
            show(record.id)
            resume(record, to: peer)
        }
        for record in (try? library.undelivered(in: mode, with: peer)) ?? [] {
            resume(record, to: peer)
        }
        refresh()
    }

    func closed(_ link: any PeerLink) {
        guard let peer = peer(of: link) else { return }
        links[peer] = nil
        connected[peer] = nil
        lost(peer)
        refresh()
    }

    private func lost(_ peer: String) {
        resumed[peer] = nil
        if outgoing?.peer == peer { outgoing = nil }
        if incoming?.peer == peer { incoming = nil }
        if active()?.peer == peer {
            inPlay = false
            offer = nil
        }
    }

    func received(_ message: PeerMessage, from link: any PeerLink) {
        // A link already replaced or closed says nothing any more.
        guard let peer = peer(of: link) else { return }
        NearbyLogger.note("← \(message)")
        handle(message, from: peer)
        refresh()
    }

    private func handle(_ message: PeerMessage, from peer: String) {
        switch message {
        case .hello:
            break
        case .propose(let game, let kind, let side, let seed):
            proposed(PeerProposal(game: game, peer: peer, kind: kind, proposerSide: side,
                                  seed: seed))
        case .accept(let game):
            guard let proposal = outgoing, proposal.game == game, proposal.peer == peer else {
                send(.gone(game: game), to: peer)
                break
            }
            outgoing = nil
            if begin(proposal, as: proposal.proposerSide) {
                started?(game)
            } else {
                send(.gone(game: game), to: peer)
            }
        case .decline(let game, let busy):
            guard outgoing?.game == game else { break }
            outgoing = nil
            declined?(busy)
        case .move(let game, let ply, let move):
            guard let record = held(game, with: peer) else { break }
            // A move that crossed this device's ending still counts toward
            // which ending stands.
            guard record.endedAt == nil else {
                if ply == record.moves.count {
                    merge(record, moves: record.moves + [move], takebacks: record.takebacks,
                          ending: nil)
                }
                break
            }
            guard ply == record.moves.count, !isLocalTurn(record),
                  (try? land(move, in: record)) != nil
            else { return disagree(record) }
        case .offerDraw(let game, let ply):
            offered(.draw, in: game, at: ply, by: peer)
        case .askTakeback(let game, let ply):
            offered(.takeback, in: game, at: ply, by: peer)
        case .acceptTakeback(let game, let ply):
            guard let record = held(game, with: peer), ply > 0 else { break }
            guard record.endedAt != nil || ply == record.moves.count else {
                return disagree(record)
            }
            merge(record, moves: Array(record.moves.prefix(ply - 1)),
                  takebacks: record.takebacks + [ply - 1], ending: nil)
        case .end(let game, let ending):
            guard let record = held(game, with: peer) else { break }
            merge(record, moves: record.moves, takebacks: record.takebacks, ending: ending)
        case .resume(let game, let moves, let takebacks, let ending):
            guard let record = held(game, with: peer) else {
                send(.gone(game: game), to: peer)
                break
            }
            if resumed[peer]?.contains(game) != true { resume(record, to: peer) }
            merge(record, moves: moves, takebacks: takebacks, ending: ending)
            guard record.reason != .endedEarly else { break }
            try? library.change(record) { $0.endingUndelivered = false }
            if record.endedAt == nil {
                show(record.id)
                inPlay = true
                offer = nil
            }
        case .gone(let game):
            if incoming?.game == game { incoming = nil }
            guard let record = held(game, with: peer) else { break }
            if record.endedAt == nil {
                file(record, .lostByPeer)
            } else {
                try? library.change(record) { $0.endingUndelivered = false }
            }
        }
    }

    /// An offer stands only where it was made on the moves this device holds,
    /// by the player not to move.
    private func offered(_ kind: PeerOffer.Kind, in game: UUID, at ply: Int, by peer: String) {
        guard let record = playing(game, with: peer), ply == record.moves.count,
              isLocalTurn(record) else { return }
        offer = PeerOffer(kind: kind, fromPeer: true, ply: ply)
    }

    /// The first proposal to arrive wins: a player with one already standing,
    /// either way, or a game with somebody else, answers busy. A proposal from
    /// the player of the game in play means they have left it.
    private func proposed(_ proposal: PeerProposal) {
        if let record = active(), record.peer == proposal.peer {
            file(record, .retired)
        }
        let busy = outgoing != nil || incoming != nil
            || (try? library.activeRecord())?.mode.isNetworked == true
        if busy {
            send(.decline(game: proposal.game, busy: true), to: proposal.peer)
        } else {
            incoming = proposal
        }
    }

    // MARK: - This device's player

    /// Offers a game to a connected device. False where nothing could be sent.
    @discardableResult
    func propose(_ kind: GameKind, side: Side, to peer: String) -> Bool {
        guard links[peer] != nil, outgoing == nil, incoming == nil else { return false }
        var seed: String?
        if Core.frozenStartFEN(for: kind) == nil {
            guard let drawn = try? Core.dealSeed() else { return false }
            seed = drawn
        }
        let proposal = PeerProposal(game: UUID(), peer: peer, kind: kind, proposerSide: side,
                                    seed: seed)
        outgoing = proposal
        send(.propose(game: proposal.game, kind: kind, proposerSide: side, seed: seed),
             to: peer)
        return true
    }

    /// The proposal is no longer this player's to wait on.
    func withdraw() {
        guard let proposal = outgoing else { return }
        outgoing = nil
        send(.gone(game: proposal.game), to: proposal.peer)
    }

    /// Accepts the standing proposal, creating the game. False where the
    /// library would not.
    @discardableResult
    func accept() -> Bool {
        guard let proposal = incoming else { return false }
        incoming = nil
        guard begin(proposal, as: proposal.proposerSide.opponent) else {
            send(.decline(game: proposal.game, busy: true), to: proposal.peer)
            refresh()
            return false
        }
        send(.accept(game: proposal.game), to: proposal.peer)
        refresh()
        return true
    }

    func decline() {
        guard let proposal = incoming else { return }
        incoming = nil
        send(.decline(game: proposal.game, busy: false), to: proposal.peer)
        refresh()
    }

    /// Plays this player's move. False where it is not theirs to play or the
    /// rules refuse it.
    @discardableResult
    func play(_ move: String) -> Bool {
        guard let record = active(), inPlay, isLocalTurn(record), let peer = record.peer,
              (try? land(move, in: record)) != nil
        else { return false }
        send(.move(game: record.id, ply: record.moves.count - 1, move: move), to: peer)
        refresh()
        return true
    }

    /// Offers a draw or asks for this player's last move back, off turn.
    @discardableResult
    func offer(_ kind: PeerOffer.Kind) -> Bool {
        guard let record = active(), inPlay, !isLocalTurn(record), offer == nil,
              kind == .draw || !record.moves.isEmpty, let peer = record.peer
        else { return false }
        let ply = record.moves.count
        offer = PeerOffer(kind: kind, fromPeer: false, ply: ply)
        send(kind == .draw ? .offerDraw(game: record.id, ply: ply)
                           : .askTakeback(game: record.id, ply: ply), to: peer)
        refresh()
        return true
    }

    /// Accepts what the other player offered.
    @discardableResult
    func acceptOffer() -> Bool {
        guard let record = active(), inPlay, let offer, offer.fromPeer, let peer = record.peer
        else { return false }
        switch offer.kind {
        case .draw:
            choose(PeerEnding(outcome: .draw, reason: .agreedDraw, length: record.moves.count),
                   in: record)
        case .takeback:
            merge(record, moves: Array(record.moves.prefix(offer.ply - 1)),
                  takebacks: record.takebacks + [offer.ply - 1], ending: nil)
            send(.acceptTakeback(game: record.id, ply: offer.ply), to: peer)
        }
        refresh()
        return true
    }

    /// Resigns, connected or not: an ending that cannot travel now goes with
    /// the next resume.
    @discardableResult
    func resign() -> Bool {
        guard let record = active(), let side = record.localSide else { return false }
        choose(PeerEnding(outcome: .win(for: side.opponent), reason: .resignation,
                          length: record.moves.count), in: record)
        refresh()
        return true
    }

    @discardableResult
    func claimDraw() -> Bool {
        guard let record = active(), inPlay, isLocalTurn(record), claimable(record)
        else { return false }
        choose(PeerEnding(outcome: .draw, reason: .threefoldRepetition,
                          length: record.moves.count), in: record)
        refresh()
        return true
    }

    /// The game in play, for a board coming back to it. Nil where the library
    /// holds no game of this mode.
    func takeUpStoredGame() -> UUID? {
        guard let record = active() else { return nil }
        show(record.id)
        refresh()
        return record.id
    }

    /// The board let go of the game it showed. A game still going stays shown.
    func letGo() {
        guard game?.isOver == true else { return }
        shown = nil
        voided = nil
        refresh()
    }

    /// The library is about to file the game in play as ended early. The other
    /// device hears now if it is connected, and on its next resume otherwise.
    func giveUp() {
        guard let record = active() else { return }
        if let peer = record.peer { send(.gone(game: record.id), to: peer) }
        shown = nil
        inPlay = false
        offer = nil
        refresh()
    }

    // MARK: - The record

    /// The library's game in play, where it is this mode's.
    private func active() -> GameRecord? {
        guard let record = try? library.activeRecord(), record.mode == mode else { return nil }
        return record
    }

    /// A record of this mode with that peer, ended early or not.
    private func held(_ game: UUID, with peer: String) -> GameRecord? {
        guard let record = try? library.record(game), record.mode == mode, record.peer == peer,
              record.reason != .endedEarly
        else { return nil }
        return record
    }

    /// The game in play, where it is that one.
    private func playing(_ game: UUID, with peer: String) -> GameRecord? {
        guard let record = active(), record.id == game, record.peer == peer else { return nil }
        return record
    }

    private func begin(_ proposal: PeerProposal, as localSide: Side) -> Bool {
        do {
            let start = try proposal.seed.map {
                try library.core.deal(proposal.kind, seed: $0).startFEN
            }
            let configuration: GameConfiguration = mode == .online
                ? .online(game: proposal.kind, localSide: localSide, startFEN: start)
                : .nearby(game: proposal.kind, localSide: localSide, startFEN: start)
            let record = try library.createNetworked(configuration, id: proposal.game,
                                                     peer: proposal.peer)
            show(record.id)
            inPlay = true
            offer = nil
            resumed[proposal.peer, default: []].insert(record.id)
            libraryChanged?()
            return true
        } catch {
            return false
        }
    }

    /// Lands a move the rules allow, ending the game where they decide it.
    private func land(_ move: String, in record: GameRecord) throws {
        let evaluation = try library.core.evaluate(record.kind, from: record.start,
                                                   moves: record.moves + [move])
        try library.change(record) {
            $0.moves.append(move)
            if let outcome = evaluation.state.outcome { $0.end(outcome, evaluation.reason) }
        }
        offer = nil
        if record.endedAt != nil { libraryChanged?() }
    }

    /// Written before it is sent, so a drop delays it and never loses it.
    private func choose(_ ending: PeerEnding, in record: GameRecord) {
        guard (try? library.change(record, {
            $0.end(ending.outcome, ending.reason)
            $0.chosenAt = ending.length
            $0.endingUndelivered = true
        })) != nil, let peer = record.peer else { return }
        offer = nil
        send(.end(game: record.id, ending: ending), to: peer)
        libraryChanged?()
    }

    /// The record's ending where a player chose it; a rules result is read off
    /// the moves instead.
    private func chosenEnding(of record: GameRecord) -> PeerEnding? {
        guard let length = record.chosenAt, let outcome = record.result,
              let reason = record.reason else { return nil }
        return PeerEnding(outcome: outcome, reason: reason, length: length)
    }

    /// Brings the record to what both devices hold: the takebacks either has
    /// accepted, the longer line, and the ending that settles first.
    private func merge(_ record: GameRecord, moves theirMoves: [String],
                       takebacks theirTakebacks: [Int], ending theirEnding: PeerEnding?) {
        var mine = record.moves
        var theirs = theirMoves
        let ours = record.takebacks
        guard ours.starts(with: theirTakebacks) || theirTakebacks.starts(with: ours) else {
            return disagree(record)
        }
        for keep in theirTakebacks.dropFirst(ours.count) { mine = Array(mine.prefix(keep)) }
        for keep in ours.dropFirst(theirTakebacks.count) { theirs = Array(theirs.prefix(keep)) }
        guard mine.starts(with: theirs) || theirs.starts(with: mine) else {
            return disagree(record)
        }
        var line = mine.count >= theirs.count ? mine : theirs
        guard let evaluation = try? library.core.evaluate(record.kind, from: record.start,
                                                          moves: line)
        else { return disagree(record) }
        let rules = evaluation.state.outcome.map {
            PeerEnding(outcome: $0, reason: evaluation.reason, length: line.count, byRules: true)
        }
        let ending = [chosenEnding(of: record), theirEnding].reduce(rules, PeerEnding.settled)
        if let ending { line = Array(line.prefix(ending.length)) }
        let takebacks = ours.count >= theirTakebacks.count ? ours : theirTakebacks

        let wasActive = record.endedAt == nil
        if line != record.moves { offer = nil }
        try? library.change(record) {
            if $0.moves != line { $0.moves = line }
            if $0.takebacks != takebacks { $0.takebacks = takebacks }
            guard let ending else { return }
            $0.chosenAt = ending.byRules ? nil : ending.length
            if $0.endedAt == nil {
                $0.end(ending.outcome, ending.reason)
            } else if $0.result != ending.outcome || $0.reason != ending.reason {
                $0.result = ending.outcome
                $0.reason = ending.reason
            }
        }
        if wasActive, record.endedAt != nil { libraryChanged?() }
    }

    /// A message that makes no sense ends the game early on both devices.
    private func disagree(_ record: GameRecord) {
        if record.endedAt == nil { file(record, .disagreement) }
        if let peer = record.peer { send(.gone(game: record.id), to: peer) }
    }

    /// Files the game as it stood, which is ended early: a result the rules
    /// decided was written when its move landed.
    private func file(_ record: GameRecord, _ reason: NearbyVoid) {
        try? library.change(record) {
            $0.end(.none, .endedEarly)
            $0.chosenAt = nil
        }
        if shown == nil || shown == record.id {
            shown = record.id
            voided = reason
        }
        inPlay = false
        offer = nil
        libraryChanged?()
    }

    private func isLocalTurn(_ record: GameRecord) -> Bool {
        let evaluation = try? library.core.evaluate(record.kind, from: record.start,
                                                    moves: record.moves)
        return evaluation?.sideToMove == record.localSide
    }

    private func claimable(_ record: GameRecord) -> Bool {
        (try? library.core.evaluate(record.kind, from: record.start,
                                    moves: record.moves))?.claimAvailable == true
    }

    private func show(_ game: UUID) {
        if shown != game { voided = nil }
        shown = game
    }

    // MARK: - Sending

    private func resume(_ record: GameRecord, to peer: String) {
        resumed[peer, default: []].insert(record.id)
        send(.resume(game: record.id, moves: record.moves, takebacks: record.takebacks,
                     ending: chosenEnding(of: record)), to: peer)
    }

    private func send(_ message: PeerMessage, to peer: String) {
        guard let link = links[peer] else { return }
        NearbyLogger.note("→ \(message)")
        link.send(message)
    }

    private func peer(of link: any PeerLink) -> String? {
        links.first { $0.value === link }?.key
    }

    // MARK: - What the board reads

    private func refresh() {
        guard let shown, let record = try? library.record(shown), let side = record.localSide
        else {
            game = nil
            return
        }
        let evaluation = try? library.core.evaluate(record.kind, from: record.start,
                                                    moves: record.moves)
        let going = record.endedAt == nil
        let linked = record.peer.map { links[$0] != nil } ?? false
        let playing = going && linked && inPlay
        let localTurn = evaluation?.sideToMove == side
        game = PeerGame(id: record.id, kind: record.kind, localSide: side, start: record.start,
                        moves: record.moves,
                        outcome: record.reason == .endedEarly ? nil : record.result,
                        reason: record.reason == .endedEarly ? nil : record.reason,
                        linked: linked, inPlay: playing, localTurn: localTurn,
                        claimable: playing && localTurn && evaluation?.claimAvailable == true,
                        undelivered: record.endingUndelivered,
                        offer: going ? offer : nil, voided: voided)
    }
}
