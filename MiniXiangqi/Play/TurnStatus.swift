// The primary line always names the side to move; there is no separate "your
// turn", and turn ownership is never carried by colour alone. Beside the board
// it is the panel's first section; in the stacked shape it takes the bar's
// title place, and the screen hangs whatever the bar cannot hold beneath it.

import SwiftUI

struct TurnStatus: View {
    enum Placement {
        case block
        case bar
    }

    var placement: Placement = .block

    /// What the two sides are called is the game's: 红方 and 黑方 on a xiangqi
    /// board, 黑方 and 白方 on a placement one.
    var game: GameKind
    var state: GameState
    var reason: EndReason

    /// Words the shared vocabulary lacks: a nearby game can end by agreement,
    /// which is not a verdict on a position, so the core has no word for it.
    var reasonText: String?

    var sideToMove: Side
    var inCheck: Bool

    /// Free Play omits it, because the same person controls both sides.
    var controller: Controller?

    /// The indicator appears only once a search has run long enough to be worth
    /// showing, and carries no glass: it is present for much of every
    /// human-versus-AI game.
    var activity: Opponent.Activity = .idle

    /// The alert has already been answered with 稍后 by the time this shows. In
    /// the bar the slot hangs beneath the element instead, so the screen passes
    /// none.
    var retry: (() -> Void)?

    /// Who is on the other side of the turn, where it is not the person holding
    /// this device.
    enum Controller {
        case you, ai, peer

        var text: String {
            switch self {
            case .you: String(localized: "status.controller.you")
            case .ai: String(localized: "status.controller.ai")
            case .peer: String(localized: "status.controller.peer")
            }
        }
    }

    /// The acknowledgment beat's progress, 0 to 1 — how far through the beat,
    /// not how dark; `Motion.beatPeakOpacity` is full emphasis. Opacity only, so
    /// Reduce Motion changes nothing, and neutral because tint on the play
    /// screen belongs to the sides.
    var beatEmphasis: Double = 0

    @ViewBuilder
    var body: some View {
        switch placement {
        case .block: block
        case .bar: bar
        }
    }

    private var block: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                primaryText(.title3.weight(.medium))
                secondaryText(.callout)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("turn-status")
            .frame(maxWidth: .infinity, alignment: .leading)

            // Outside the combined element above, because a control folded into
            // one is a control a screen reader cannot reach.
            if activity == .stalled, let retry {
                StalledSlot(retry: retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // PlayScreen counts on this 12: the panel's one left edge is its
        // panelInset less this padding. They move together or not at all.
        .padding(12)
        .background { beat(cornerRadius: 10) }
    }

    /// Each line stays a single line: a status that wrapped would push the bar
    /// down over the board.
    private var bar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                primaryText(.subheadline.weight(.semibold))
                secondaryText(.caption)
            }
            VStack(spacing: 1) {
                primaryText(.subheadline.weight(.semibold))
                secondaryText(.caption)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("turn-status")
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background { beat(cornerRadius: 8) }
    }

    private func primaryText(_ font: Font) -> some View {
        Text(primaryLine)
            .font(font)
            .contentTransition(.identity)
    }

    @ViewBuilder
    private func secondaryText(_ font: Font) -> some View {
        if let secondary {
            HStack(spacing: 6) {
                Text(secondary)
                    .font(font)
                    .foregroundStyle(.secondary)

                // No material on the indicator.
                if activity == .thinking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("status.aiThinking"))
                        .accessibilityIdentifier("ai-thinking")
                }
            }
        }
    }

    /// In the bar the beat is the bar's centre rising and falling, not the
    /// page's.
    private func beat(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(Motion.beatPeakOpacity * beatEmphasis))
            .accessibilityHidden(true)
    }

    private var primaryLine: String {
        switch state {
        case .ongoing, .claimableDraw: sideToMoveLine
        case .redWins: game.winsText(.red)
        case .blackWins: game.winsText(.black)
        case .draw: String(localized: "status.draw")
        }
    }

    /// The check token accompanies the side-to-move line rather than replacing
    /// it. Joined by a format string because the separator is copy (an
    /// ideographic space in Chinese).
    private var sideToMoveLine: String {
        let side = game.sideToMoveText(sideToMove)
        // The core reports `in_check` as 0 in the placement games, so the token
        // needs no gate of its own.
        guard inCheck else { return side }
        return String(format: String(localized: "status.sideToMove.checked"),
                      side, String(localized: "status.check"))
    }

    /// Who owns the turn, and what else is true of the game.
    private var secondary: String? {
        let words = reasonText ?? reason.text
        let claimOrReason: String? = switch state {
        case .ongoing: nil
        case .claimableDraw: String(format: String(localized: "metadata.join"),
                                    String(localized: "status.drawAvailable"), words)
        default: words.isEmpty ? nil : words
        }
        // A finished game is nobody's to move.
        let owner = state.isOver ? nil : controller?.text
        return switch (owner, claimOrReason) {
        case (let owner?, let rest?): String(format: String(localized: "metadata.join"),
                                             owner, rest)
        case (let owner?, nil): owner
        case (nil, let rest?): rest
        case (nil, nil): nil
        }
    }
}

extension TurnStatus {
    /// The AI could not be prepared mid-game, the player answered 稍后, and the
    /// game is saved. It stands inside the block, or beneath the bar.
    struct StalledSlot: View {
        var retry: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Text("status.aiUnavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-stalled")
                inlineRetry
                    .accessibilityIdentifier("ai-retry")
            }
        }

    /// An action written into text: the link style on macOS, which UIKit lacks,
    /// and borderless on iOS.
        @ViewBuilder
        private var inlineRetry: some View {
            #if os(macOS)
            Button("control.tryAgain", action: retry).buttonStyle(.link)
            #else
            Button("control.tryAgain", action: retry).buttonStyle(.borderless)
            #endif
        }
    }
}

extension EndReason {
    /// Shared by the status line and the result notice.
    var text: String {
        switch self {
        case .checkmate: String(localized: "reason.checkmate")
        case .stalemate: String(localized: "reason.stalemate")
        case .threefoldRepetition: String(localized: "reason.threefoldRepetition")
        case .perpetualCheck: String(localized: "reason.perpetualCheck")
        case .perpetualChase: String(localized: "reason.perpetualChase")
        case .mutualPerpetualCheck: String(localized: "reason.mutualPerpetualCheck")
        case .mutualPerpetualChase: String(localized: "reason.mutualPerpetualChase")
        case .fiftyMoveRule: String(localized: "reason.fiftyMoveRule")
        case .fortyMoveRule: String(localized: "reason.fortyMoveRule")
        case .resignation: String(localized: "reason.resignation")
        case .endedEarly: String(localized: "reason.endedEarly")
        case .agreedDraw: String(localized: "reason.agreedDraw")
        case .mutualResignation: String(localized: "reason.mutualResignation")
        case .fiveInARow: String(localized: "reason.fiveInARow")
        case .boardFull: String(localized: "reason.boardFull")
        case .none: ""
        }
    }
}
