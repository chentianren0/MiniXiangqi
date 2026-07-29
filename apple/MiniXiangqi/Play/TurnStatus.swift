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
        // PlayScreen counts on this 12: the panel's one left edge is its
        // panelInset less this padding. They move together or not at all.
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
        case .ongoing, .claimableDraw: sideToMoveLine
        case .redWins: String(localized: "status.redWins")
        case .blackWins: String(localized: "status.blackWins")
        case .draw: String(localized: "status.draw")
        }
    }

    /// Whose turn it is, and the check token where there is one.
    ///
    /// The token accompanies the side-to-move line rather than replacing it:
    /// whose turn it is remains true while they are in check. The two are
    /// joined by a format string rather than by concatenation, because what
    /// stands between them is copy — an ideographic space in Chinese, an
    /// ordinary one in English — and a separator hard-coded here would be one
    /// language's punctuation wrapped around the other language's words.
    private var sideToMoveLine: String {
        let side = sideToMove == .red
            ? String(localized: "status.redToMove")
            : String(localized: "status.blackToMove")
        guard inCheck else { return side }
        return String(format: String(localized: "status.sideToMove.checked"),
                      side, String(localized: "status.check"))
    }

    private var secondary: String? {
        switch state {
        case .ongoing: nil
        // The metadata join, applied here to the standing offer and the reason
        // behind it. Its middot is the same in both languages, and it is still
        // a format string: what a language does around a separator is copy.
        case .claimableDraw: String(format: String(localized: "metadata.join"),
                                    String(localized: "status.drawAvailable"), reason.text)
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
        case .checkmate: String(localized: "reason.checkmate")
        case .stalemate: String(localized: "reason.stalemate")
        case .threefoldRepetition: String(localized: "reason.threefoldRepetition")
        case .perpetualCheck: String(localized: "reason.perpetualCheck")
        case .perpetualChase: String(localized: "reason.perpetualChase")
        case .mutualPerpetualCheck: String(localized: "reason.mutualPerpetualCheck")
        case .mutualPerpetualChase: String(localized: "reason.mutualPerpetualChase")
        case .resignation: String(localized: "reason.resignation")
        case .endedEarly: String(localized: "reason.endedEarly")
        // No reason is no words, in every language.
        case .none: ""
        }
    }
}
