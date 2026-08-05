// A nearby board stood up without a radio, for a screenshot to be taken of.
//
// A Simulator has no Wi-Fi Aware, so the nearby board is the one screen in this
// app that no UI test can reach by pressing things. What it *can* be handed is
// the state the board would be in — one session, in one of the moments this
// slice added a surface for — which is exactly what every other launch argument
// in this app does: `-mxq-history` seeds records, `-mxq-replay` opens one, and
// this seeds a game with somebody.
//
// **Nothing here is protocol logic and nothing here is product behaviour.** The
// driver below speaks to nobody and decides nothing: it holds one session, and
// every intent it is given is recorded and dropped. What the surfaces do with
// that session is the thing under test, and it is the real `NearbyFlow`, the
// real `NearbyPlay` and the real board drawing it, over the real core's
// positions. Release builds compile none of this.

#if DEBUG && os(iOS)

import Foundation

/// The moment a staged board is standing in.
enum NearbyStage: String, CaseIterable {
    /// The other player's turn: 提和 and 悔棋 are this player's to press.
    case offTurn = "off-turn"
    /// This player's turn, with nothing standing: 判和, and nothing to claim.
    case onTurn = "on-turn"
    /// This player's turn, with the other player's draw offer standing.
    case offered
    /// This player's turn, with the other player's take-back standing.
    case undoAsked = "undo-asked"
    /// This player's turn, in a position the claim stands in.
    case claimable

    /// `-mxq-nearby-board <stage>`, where one was named.
    static var named: Self? {
        DebugLaunch.argument(after: "-mxq-nearby-board").flatMap(Self.init(rawValue:))
    }

    /// The start position a third time, which is where the claim stands. The
    /// same line the oracle's own suite verifies against the core.
    private static let shuffle = ["b1b2", "b7b6", "b2b1", "b6b7",
                                  "b1b2", "b7b6", "b2b1", "b6b7"]

    /// One session in that moment.
    ///
    /// Whose turn it is is the ply count's own parity against the mover this
    /// device holds, exactly as it is in a real session — this device takes the
    /// first mover throughout, so an even line is its turn and an odd one is
    /// not. Every line here is one the rules oracle's own suite plays against
    /// the core, so the board behind these has a real position to draw.
    var session: BoardGameSession {
        var session = BoardGameSession(id: "staged-session",
                                       peer: PeerDeviceID("staged-peer"),
                                       rulesID: GameKind.miniXiangqi.rulesID,
                                       rulesVersion: "1",
                                       proposerMoves: .first, proposer: .local)
        session.accepted = true
        session.connection = ConnectionID("staged-connection")
        switch self {
        case .offTurn:
            // One ply, this device's own — which is both what makes it the
            // other player's turn and what 悔棋 would ask back.
            session.plies = ["b1b2"]
        case .onTurn, .offered:
            break
        case .undoAsked:
            // A full exchange, so the take-back the other player is asking for
            // is their own last ply.
            session.plies = ["b1b2", "b7b6"]
        case .claimable:
            session.plies = Self.shuffle
        }
        switch self {
        case .offered:
            session.item = NegotiationItem(opener: .peer, kind: .drawOffer,
                                           at: session.count)
        case .undoAsked:
            session.item = NegotiationItem(opener: .peer,
                                           kind: .undoRequest(keep: session.count - 1),
                                           at: session.count)
        default:
            break
        }
        return session
    }

    /// Whether the claim stands here. The staged driver answers this rather
    /// than the core, because what is under test is the *surface* the answer
    /// produces; that the answer itself is the core's is the oracle suite's.
    var claimStands: Bool { self == .claimable }
}

/// A driver holding one staged session, speaking to nobody.
@MainActor
final class NearbyStagedDriver: NearbyDriving {
    private(set) var sessions: [BoardGameSession]
    let declines: [NearbyDecline] = []

    private let stage: NearbyStage

    init(_ stage: NearbyStage) {
        self.stage = stage
        self.sessions = [stage.session]
    }

    func propose(to peer: PeerDeviceID, on connection: ConnectionID, rulesID: String,
                 proposerMoves: Mover) throws(BoardGameRefusal) { }
    func answer(_ session: String, accepting: Bool) throws(BoardGameRefusal) { }
    func play(_ text: String, in session: String) throws(BoardGameRefusal) { }
    func resign(in session: String) throws(BoardGameRefusal) { }
    func claim(in session: String) throws(BoardGameRefusal) { }
    func offerDraw(in session: String) throws(BoardGameRefusal) { }
    func acceptDraw(in session: String) throws(BoardGameRefusal) { }
    func requestUndo(keeping keep: Int, in session: String) throws(BoardGameRefusal) { }
    func acceptUndo(in session: String) throws(BoardGameRefusal) { }

    func claimStands(in session: BoardGameSession) -> Bool { stage.claimStands }
}

/// A radio that is not there, which is the truth on a Simulator.
@MainActor
final class NearbyStagedRadio: NearbyRadio {
    let isSupported = false
    let isRunning = false
    let peers: [NearbyPeer] = []

    func watchPairedDevices() { }
    func start() { }
    func stop() { }
}

extension NearbyFlow {
    /// The flow a staged launch gets: the real one, over a driver that holds
    /// the named moment and a radio that is honestly absent.
    static func staged(_ stage: NearbyStage, positions: any NearbyPositions) -> NearbyFlow {
        let flow = NearbyFlow(driver: NearbyStagedDriver(stage), radio: NearbyStagedRadio(),
                              positions: positions, isAvailable: true)
        flow.openBoard(stage.session.id)
        return flow
    }
}

#endif
