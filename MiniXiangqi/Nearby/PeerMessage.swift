// What two devices playing a game say to each other, on both carriers: Nearby
// sends it framed on a Network.framework connection, Online as data on the
// Game Center match. Each message is JSON, in the shape Swift's synthesized
// Codable gives an enum.

import Foundation

nonisolated enum PeerMessage: Codable, Equatable, Sendable {
    /// Nearby only, first on every connection: who this install is, and what
    /// the other device's rows call it.
    case hello(peer: String, name: String)
    /// A game, the side the proposer takes, and for Jieqi the seed both devices
    /// deal from.
    case propose(game: UUID, kind: GameKind, proposerSide: Side, seed: String?)
    case accept(game: UUID)
    case decline(game: UUID, busy: Bool)
    /// The move at index `ply`.
    case move(game: UUID, ply: Int, move: String)
    /// An offer by the player not to move, with `ply` moves on the board. A
    /// move declines it.
    case offerDraw(game: UUID, ply: Int)
    case askTakeback(game: UUID, ply: Int)
    /// Takes back the move at index `ply - 1`.
    case acceptTakeback(game: UUID, ply: Int)
    /// An ending a player chose: resign, accept a draw, claim a draw, or give
    /// the game up. The other device answers with its resume.
    case end(game: UUID, ending: PeerEnding)
    /// What this device holds of a game: its moves, its takebacks, and an
    /// ending a player chose or the game being ended early. Sent on every new
    /// connection for the game in play and for every ending the other device
    /// has not shown it holds, and in answer to the other device's messages.
    case resume(game: UUID, moves: [String], takebacks: [Int], ending: PeerEnding?)
    /// This device has no such game: the answer to a resume or an acceptance,
    /// and the withdrawal of a proposal.
    case gone(game: UUID)
}

/// How a game ended, and where.
nonisolated struct PeerEnding: Codable, Equatable, Sendable {
    var outcome: Outcome
    var reason: EndReason
    /// The moves the game keeps: those on the board when a player chose the
    /// ending, or up to and including the move whose position the rules
    /// decided.
    var length: Int
    /// A result from the rules needs no message: each device reads it off the
    /// moves. Every other ending a player chose.
    var byRules = false

    /// A game given up on, or ended by a message that made no sense: no result,
    /// and it keeps every move either device holds.
    static func endedEarly(after length: Int) -> PeerEnding {
        PeerEnding(outcome: .none, reason: .endedEarly, length: length)
    }

    var isEndedEarly: Bool { reason == .endedEarly }

    /// The ply the ending happened at: a chosen ending's moves on the board,
    /// and a rules ending's deciding move.
    private var ply: Int { byRules ? length - 1 : length }

    /// Which of two endings at one ply stands, lowest first.
    private var rank: Int {
        if byRules { return 0 }
        switch reason {
        case .threefoldRepetition: return 1
        case .agreedDraw: return 2
        default: return 3
        }
    }

    /// The one ending both devices keep of two: any result beats ended early;
    /// the earlier ply wins; on an equal ply the rules result beats a chosen
    /// one, a claimed draw an agreed one, a draw a resignation, and two
    /// resignations are a draw.
    static func settled(_ a: PeerEnding?, _ b: PeerEnding?) -> PeerEnding? {
        guard let a else { return b }
        guard let b else { return a }
        switch (a.isEndedEarly, b.isEndedEarly) {
        case (true, true): return a.length >= b.length ? a : b
        case (true, false): return b
        case (false, true): return a
        case (false, false): break
        }
        if (a.ply, a.rank) < (b.ply, b.rank) { return a }
        if (b.ply, b.rank) < (a.ply, a.rank) { return b }
        if a.rank == 3, a != b {
            return PeerEnding(outcome: .draw, reason: .mutualResignation, length: a.length)
        }
        return a
    }
}
