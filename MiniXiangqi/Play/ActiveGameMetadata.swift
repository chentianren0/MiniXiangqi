// Every fact is read, never worked out: the mode and side from the record, the
// state from the core's replay. The side to move comes from the position, not
// the ply count, because a game begun from a composed position may have Black
// make ply 0.

import Foundation

extension GameKind {
    /// Shared by every surface. "Mini Xiangqi" names one ruleset; the app is
    /// Star River.
    var localizedName: String {
        switch self {
        case .miniXiangqi: String(localized: "game.miniXiangqi")
        case .xiangqi: String(localized: "game.xiangqi")
        case .gomoku15: String(localized: "game.gomoku")
        case .renju: String(localized: "game.renju")
        case .jieqi: String(localized: "game.jieqi")
        }
    }

    // MARK: - What a game calls its two sides
    //
    // `Side` is the core's axis: red is the first mover, which in the placement
    // games is the black stone. These only name a side; nothing above the core
    // decides which side moves first.

    /// The bare word for a side, as the accessibility labels use it.
    func sideName(_ side: Side) -> String {
        switch (isPlacement, side) {
        case (false, .red): String(localized: "board.a11y.red")
        case (false, .black): String(localized: "board.a11y.black")
        case (true, .red): String(localized: "board.a11y.black")
        case (true, .black): String(localized: "board.a11y.white")
        }
    }

    func sideToMoveText(_ side: Side) -> String {
        switch (isPlacement, side) {
        case (false, .red): String(localized: "status.redToMove")
        case (false, .black): String(localized: "status.blackToMove")
        case (true, .red): String(localized: "status.blackToMove")
        case (true, .black): String(localized: "status.whiteToMove")
        }
    }

    /// Who won, in the turn status's shorter register: 红方胜.
    func winsText(_ side: Side) -> String {
        switch (isPlacement, side) {
        case (false, .red): String(localized: "status.redWins")
        case (false, .black): String(localized: "status.blackWins")
        case (true, .red): String(localized: "status.blackWins")
        case (true, .black): String(localized: "status.whiteWins")
        }
    }

    /// Who won, in the longer register of the metadata lines and the result
    /// notice: 红方获胜.
    func resultText(_ side: Side) -> String {
        switch (isPlacement, side) {
        case (false, .red): String(localized: "result.redWins")
        case (false, .black): String(localized: "result.blackWins")
        case (true, .red): String(localized: "result.blackWins")
        case (true, .black): String(localized: "result.whiteWins")
        }
    }

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
        case .online: String(localized: "mode.online")
        }
    }

    /// A claimable repetition is still ongoing; the standing offer takes the
    /// place of the side to move.
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

    private var reasonParts: [String] {
        reason == .none ? [] : [reason.text]
    }

    private var sideToMoveText: String { game.sideToMoveText(sideToMove) }

    /// Plies, which is what 步 counts, and the core's own count of them.
    var moveCountText: String {
        String(format: String(localized: "metadata.moveCount"), moveCount)
    }
}
