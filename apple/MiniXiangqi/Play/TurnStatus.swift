// One coherent description of the current play state, near the board.
//
// docs/interaction-design.md, "Turn status": the primary line always identifies
// the side to move; a 将军 token accompanies it while that side is in check;
// Free Play carries no human-or-AI controller label, because the same person
// controls both sides. The design adds no separate instruction such as "your
// turn", and turn ownership is never carried by colour alone.

import SwiftUI

struct TurnStatus: View {
    var state: GameState
    var reason: EndReason
    var sideToMove: Side
    var inCheck: Bool

    /// The acknowledgment beat's progress, 0 to 1 — how far through the beat
    /// this is, not how dark it gets; `Motion.beatPeakOpacity` is what full
    /// emphasis comes to. Input the game cannot accept is answered here, where
    /// the reason is already on screen, rather than on the board. The
    /// background rises to full emphasis and falls back — opacity only, no
    /// movement, so Reduce Motion changes nothing — in neutral primary,
    /// because tint on the play screen belongs to the sides.
    var beatEmphasis: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(primaryLine)
                .font(.title3.weight(.medium))
                .contentTransition(.identity)

            if let secondary {
                Text(secondary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(Motion.beatPeakOpacity * beatEmphasis))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("turn-status")
    }

    private var primaryLine: String {
        switch state {
        case .ongoing, .claimableDraw:
            // The token accompanies the side-to-move line rather than replacing
            // it: whose turn it is remains true while they are in check.
            (sideToMove == .red ? "轮到红方" : "轮到黑方") + (inCheck ? "　将军" : "")
        case .redWins: "红方胜"
        case .blackWins: "黑方胜"
        case .draw: "和局"
        }
    }

    private var secondary: String? {
        switch state {
        case .ongoing: nil
        case .claimableDraw: "可判和 · " + reason.text
        default: reason.text
        }
    }
}

extension EndReason {
    /// How a result reads. One home for the vocabulary, because the status line
    /// and the result notice say the same thing about the same position and a
    /// second copy of these strings is a second thing to keep in step.
    var text: String {
        switch self {
        case .checkmate: "将死"
        case .stalemate: "困毙"
        case .threefoldRepetition: "三次重复"
        case .perpetualCheck: "长将"
        case .perpetualChase: "长捉"
        case .mutualPerpetualCheck: "双方长将"
        case .mutualPerpetualChase: "双方长捉"
        case .resignation: "认输"
        case .endedEarly: "提前结束"
        case .none: ""
        }
    }
}
