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
        .accessibilityElement(children: .combine)
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
        case .claimableDraw: "可判和 · " + describe(reason)
        default: describe(reason)
        }
    }

    private func describe(_ reason: EndReason) -> String {
        switch reason {
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
