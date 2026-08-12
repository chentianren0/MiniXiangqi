// What the active game says about itself.
//
// docs/interaction-design.md, "Saving the active game before choosing a new
// mode": the Play destination shows the active game's metadata, identifying at
// least the game, the mode, the human's side where there is one, and the move
// count, plus the side to move for an ongoing game, the result and reason for a
// terminal one, and claim availability where it applies. The accepted example
// lines begin 象棋 · 人机对弈 or 迷你象棋 · 自由对弈 before those facts.
//
// It is the same composition the History row applies to a filed game — game,
// mode, side, state, count, joined by the accepted middot — with the one
// difference that a live game has a live state where a record has a committed
// result. The three state classes below are the whole of what differs.
//
// **Every fact is read, not worked out.** The mode and the human side come from
// the configuration frozen at creation; the state, the reason, the claim and the
// ply count come from the core's own status for the committed game. Nothing here
// decides what state a game is in.
//
// **It is read without a session.** `Core.activeGameSummary` is
// `mxq_store_active_summary`, which the C interface built for this surface and
// the save-and-continue confirmation — the live game belongs to the board, and
// the home has no business holding one to describe it. The one segment the
// summary does not carry is whose turn it is, and that is arithmetic on the ply
// count it does carry; see `sideToMove` below.

import Foundation

extension GameKind {
    /// The one display name for a game, shared by section headings, setup and
    /// every metadata line. The application is named Star River; this is the
    /// name of the ruleset a particular row or game belongs to, and **Mini
    /// Xiangqi** here is one of the four games rather than the product.
    var localizedName: String {
        switch self {
        case .miniXiangqi: String(localized: "game.miniXiangqi")
        case .xiangqi: String(localized: "game.xiangqi")
        case .gomoku15: String(localized: "game.gomoku")
        case .renju: String(localized: "game.renju")
        }
    }

    // MARK: - What a game calls its two sides
    //
    // `Side` is the core's own axis and means "the side that moves first" and
    // "the other" in every game: MXQ_COLOR_RED is the first mover, and in the
    // placement games the first mover is the *black* stone. So everything below
    // is a naming and never a re-derivation — the same `Side` reads 红 on a
    // xiangqi board and 黑 on a gomoku one, and nothing above the interface
    // decides which side moves first.
    //
    // One home, because six surfaces ask it: the turn status, the two metadata
    // lines, the result notice, the setup page and the board's accessibility
    // labels. A second copy would be a second place for a game to be told its
    // sides are something they are not.

    /// The bare word for a side — the accessibility labels' vocabulary, and the
    /// one every register below is built on.
    func sideName(_ side: Side) -> String {
        switch (isPlacement, side) {
        case (false, .red): String(localized: "board.a11y.red")
        case (false, .black): String(localized: "board.a11y.black")
        case (true, .red): String(localized: "board.a11y.black")
        case (true, .black): String(localized: "board.a11y.white")
        }
    }

    /// Whose turn it is, in the turn status's own register.
    func sideToMoveText(_ side: Side) -> String {
        switch (isPlacement, side) {
        case (false, .red): String(localized: "status.redToMove")
        case (false, .black): String(localized: "status.blackToMove")
        case (true, .red): String(localized: "status.blackToMove")
        case (true, .black): String(localized: "status.whiteToMove")
        }
    }

    /// Who won, in the turn status's shorter register — 红方胜.
    func winsText(_ side: Side) -> String {
        switch (isPlacement, side) {
        case (false, .red): String(localized: "status.redWins")
        case (false, .black): String(localized: "status.blackWins")
        case (true, .red): String(localized: "status.blackWins")
        case (true, .black): String(localized: "status.whiteWins")
        }
    }

    /// Who won, in the longer register the metadata lines and the result notice
    /// use — 红方获胜.
    func resultText(_ side: Side) -> String {
        switch (isPlacement, side) {
        case (false, .red): String(localized: "result.redWins")
        case (false, .black): String(localized: "result.blackWins")
        case (true, .red): String(localized: "result.blackWins")
        case (true, .black): String(localized: "result.whiteWins")
        }
    }

    /// Which side the player has, on a metadata line.
    func youAreText(_ side: Side) -> String {
        switch (isPlacement, side) {
        case (false, .red): String(localized: "metadata.youRed")
        case (false, .black): String(localized: "metadata.youBlack")
        case (true, .red): String(localized: "metadata.youBlack")
        case (true, .black): String(localized: "metadata.youWhite")
        }
    }
}

extension ActiveGameSummary {
    /// The metadata line: game, mode, human side, what is true of the game now,
    /// and the move count.
    var metadataLine: String {
        var parts = [game.localizedName, modeText]
        if mode == .humanVersusAI, let humanSide {
            parts.append(game.youAreText(humanSide))
        }
        parts += stateParts
        parts.append(moveCountText)
        return parts.joined(by: String(localized: "metadata.join"))
    }

    var modeText: String {
        switch mode {
        case .humanVersusAI: String(localized: "mode.humanVersusAI")
        case .freePlay: String(localized: "mode.freePlay")
        case .nearby: String(localized: "mode.nearby")
        }
    }

    /// Whose turn it is, from the ply count the store returned.
    ///
    /// **Presentation arithmetic, not a rules decision.** It rests on two
    /// frozen contract facts and on nothing else: Red moves first — the FEN
    /// side field of docs/xiangqi-rules.md, and the same for both games — and
    /// plies strictly alternate, neither ruleset having a pass, which is why
    /// docs/boardgame-protocol.md decides whose turn each ply is from index
    /// parity too. So an even count is Red to move and an odd one is Black's.
    /// Nothing here judges legality, adjudication or an affordance; the state
    /// beside it is the core's own answer.
    ///
    /// A game that ever gained a pass would break this, which is why the two
    /// facts are named rather than assumed.
    var sideToMove: Side { moveCount.isMultiple(of: 2) ? .red : .black }

    /// What is true of the game right now, in the three classes the accepted
    /// examples give.
    ///
    /// An ongoing game is 进行中 and whose turn it is. A claimable repetition is
    /// still ongoing — that is the whole point of it being a claim — and what it
    /// adds is the standing offer, in the same words the turn status uses for
    /// it; the side to move gives way to it, as the accepted example line does.
    /// A terminal game is its result and the reason for it, in the longer
    /// register the metadata composition uses everywhere: 红方获胜, not the
    /// status line's 红方胜.
    private var stateParts: [String] {
        switch state {
        case .ongoing:
            [String(localized: "metadata.inProgress"), sideToMoveText]
        case .claimableDraw:
            [String(localized: "metadata.inProgress"),
             String(localized: "status.drawAvailable")]
        case .redWins:
            [game.resultText(.red)] + reasonParts
        case .blackWins:
            [game.resultText(.black)] + reasonParts
        case .draw:
            [String(localized: "result.draw")] + reasonParts
        }
    }

    /// The reason, where the core reports one. No reason is no words, so it
    /// contributes no segment rather than an empty one.
    private var reasonParts: [String] {
        reason == .none ? [] : [reason.text]
    }

    private var sideToMoveText: String { game.sideToMoveText(sideToMove) }

    /// Plies, which is what 步 counts, and the core's own count of them.
    var moveCountText: String {
        String(format: String(localized: "metadata.moveCount"), moveCount)
    }
}
