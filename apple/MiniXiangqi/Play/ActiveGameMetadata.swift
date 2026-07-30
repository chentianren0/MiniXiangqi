// What the active game says about itself.
//
// docs/interaction-design.md, "Saving the active game before choosing a new
// mode": the Play destination shows the active game's metadata, identifying at
// least the mode, the human's side where there is one, and the move count, plus
// the side to move for an ongoing game, the result and reason for a terminal
// one, and claim availability where it applies. The accepted example lines are
// 人机对弈 · 你执红, 进行中 · 轮到黑方 · 42 步, 红方获胜 · 将死 · 42 步 and
// 进行中 · 可判和 · 42 步.
//
// It is the same composition the History row applies to a filed game — mode,
// side, state, count, joined by the accepted middot — with the one difference
// that a live game has a live state where a record has a committed result. So
// the three state classes below are the whole of what is new here, and every
// token in them already exists in the register: 进行中, the two side-to-move
// lines, 可判和, the three result words, and the reason vocabulary.
//
// **Every fact is read, not worked out.** The mode and the human side come from
// the configuration frozen at creation; the state, the reason, the claim and the
// ply count come from the core's own status for the committed game. Nothing here
// decides what state a game is in.

import Foundation

extension Game {
    /// The metadata line: mode, human side, what is true of the game now, and
    /// the move count.
    var metadataLine: String {
        var parts = [modeText]
        if let humanSide {
            parts.append(humanSide == .red
                         ? String(localized: "metadata.youRed")
                         : String(localized: "metadata.youBlack"))
        }
        parts += stateParts
        parts.append(moveCountText)
        return parts.joined(by: String(localized: "metadata.join"))
    }

    var modeText: String {
        isHumanVersusAI
            ? String(localized: "mode.humanVersusAI")
            : String(localized: "mode.freePlay")
    }

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
        switch presentedState {
        case .ongoing:
            [String(localized: "metadata.inProgress"), sideToMoveText]
        case .claimableDraw:
            [String(localized: "metadata.inProgress"),
             String(localized: "status.drawAvailable")]
        case .redWins:
            [String(localized: "result.redWins")] + reasonParts
        case .blackWins:
            [String(localized: "result.blackWins")] + reasonParts
        case .draw:
            [String(localized: "result.draw")] + reasonParts
        }
    }

    /// The reason, where the core reports one. No reason is no words, so it
    /// contributes no segment rather than an empty one.
    private var reasonParts: [String] {
        presentedReason == .none ? [] : [presentedReason.text]
    }

    private var sideToMoveText: String {
        evaluation.sideToMove == .red
            ? String(localized: "status.redToMove")
            : String(localized: "status.blackToMove")
    }

    /// Plies, which is what 步 counts, and the core's own count of them.
    var moveCountText: String {
        String(format: String(localized: "metadata.moveCount"), evaluation.plyCount)
    }
}
