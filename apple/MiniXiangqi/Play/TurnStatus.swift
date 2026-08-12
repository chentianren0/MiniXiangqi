// One coherent description of the current play state, near the board.
//
// docs/interaction-design.md, "Turn status": the primary line always identifies
// the side to move; a 将军 token accompanies it while that side is in check;
// Free Play carries no human-or-AI controller label, because the same person
// controls both sides. The design adds no separate instruction such as "your
// turn", and turn ownership is never carried by colour alone.
//
// **Where the element stands follows the layout shape**, and it keeps its
// duties wherever it stands. Beside the board it is the panel's first section;
// in the stacked shape it is the page's bar centre, in the title's place, which
// a board page does not spend on a name. The two forms say the same things at
// the room each has: the description and the acknowledgment beat on its own
// background in both, and in the bar nothing else — the lines a bar centre
// cannot hold hang beneath it, hung by the screen that knows what is under the
// bar. At an accessibility text size the bar cannot hold the element at all and
// the screen puts it back above the board.
//
// It carries nothing of the hint. The control, its activity and its disabling
// are the play-control cluster's, per "Hints".

import SwiftUI

struct TurnStatus: View {
    /// Where the element stands, which is the whole of what the two forms
    /// differ by: the room each has, and therefore what the element draws
    /// itself and what it leaves to the screen around it.
    enum Placement {
        /// The measured chrome above the board, and the panel's first section.
        case block
        /// The page's bar centre, in the title's place.
        case bar
    }

    var placement: Placement = .block

    /// Which game this is a status for, because what its two sides are called
    /// is the game's — 红方 and 黑方 on a xiangqi board, 黑方 and 白方 on a
    /// placement one. The side itself is the core's answer either way.
    var game: GameKind
    var state: GameState
    var reason: EndReason

    /// The reason line, where the caller has words the shared vocabulary does
    /// not. A nearby game can end by the two players agreeing a draw, which is
    /// not a verdict on a position and therefore not something the core — whose
    /// vocabulary `EndReason` is — has a word for. Everything else reads its
    /// reason, as it always did.
    var reasonText: String?

    var sideToMove: Side
    var inCheck: Bool

    /// Who controls the side to move, in human-versus-AI play. Free Play omits
    /// it, because the same person controls both sides.
    var controller: Controller?

    /// What the AI activity slot is carrying. Issue #71's decision 3: a small
    /// system activity indicator beside the AI controller label, appearing only
    /// once a search has run long enough to be worth showing, never replacing
    /// the side-to-move line, and carrying no material at all — it is present
    /// for a large share of every human-versus-AI game, and a persistent glass
    /// surface beside the board would be exactly the gratuitous application the
    /// platform's own guidance warns against.
    var activity: Opponent.Activity = .idle

    /// The inline retry the stalled slot carries, per decision 2. The alert has
    /// already been answered with 稍后 by the time this shows. In the bar the
    /// slot hangs beneath the element instead, so the screen passes none.
    var retry: (() -> Void)?

    /// Who controls the side to move, where the answer is not "the person
    /// holding this device". Free Play has none — the same person controls both
    /// sides — and the other two name what is on the other side of the turn: the
    /// machine, or the person at the other device.
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

    /// The acknowledgment beat's progress, 0 to 1 — how far through the beat
    /// this is, not how dark it gets; `Motion.beatPeakOpacity` is what full
    /// emphasis comes to. Input the game cannot accept is answered here, where
    /// the reason is already on screen, rather than on the board. The
    /// background rises to full emphasis and falls back — opacity only, no
    /// movement, so Reduce Motion changes nothing — in neutral primary,
    /// because tint on the play screen belongs to the sides.
    var beatEmphasis: Double = 0

    @ViewBuilder
    var body: some View {
        switch placement {
        case .block: block
        case .bar: bar
        }
    }

    /// The element as a block: the description, the stalled slot beneath it,
    /// and the beat over the whole.
    private var block: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                primaryText(.title3.weight(.medium))
                secondaryText(.callout)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("turn-status")
            .frame(maxWidth: .infinity, alignment: .leading)

            // The stalled slot: the AI cannot start right now, the game is
            // saved, and the retry lives where things about the game live. It
            // stays *outside* the combined element above, because a control
            // folded into one is a control a screen reader cannot reach.
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

    /// The element in the bar's centre: the same description at the weights a
    /// title and its subtitle take, and nothing else.
    ///
    /// Beside where the centre holds both lines, and over two lines where it
    /// does not — the degradation the play controls make for the same reason,
    /// and the one a bar's own title and subtitle already read as. Each line
    /// stays a single line either way: a status that wrapped would push the
    /// bar down over the board it is about.
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

    /// Whose turn it is, at the weight the form gives its first line.
    private func primaryText(_ font: Font) -> some View {
        Text(primaryLine)
            .font(font)
            .contentTransition(.identity)
    }

    /// What else is true of the turn, and the AI's activity riding beside it.
    @ViewBuilder
    private func secondaryText(_ font: Font) -> some View {
        if let secondary {
            HStack(spacing: 6) {
                Text(secondary)
                    .font(font)
                    .foregroundStyle(.secondary)

                // The indicator sits beside the controller label, which is
                // the head of this line. The system's own, at its smallest,
                // drawn directly like everything else the status says — and
                // carrying no material at all, which is the one thing this
                // indicator is not allowed.
                if activity == .thinking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("status.aiThinking"))
                        .accessibilityIdentifier("ai-thinking")
                }
            }
        }
    }

    /// The acknowledgment beat's own background. Input the game cannot accept
    /// is answered on the element wherever the element stands, which in the bar
    /// is the bar's centre rising and falling rather than the page's.
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

    /// Whose turn it is, and the check token where there is one.
    ///
    /// The token accompanies the side-to-move line rather than replacing it:
    /// whose turn it is remains true while they are in check. The two are
    /// joined by a format string rather than by concatenation, because what
    /// stands between them is copy — an ideographic space in Chinese, an
    /// ordinary one in English — and a separator hard-coded here would be one
    /// language's punctuation wrapped around the other language's words.
    private var sideToMoveLine: String {
        let side = game.sideToMoveText(sideToMove)
        // The placement games have no check to be in, and the core says so: it
        // reports `in_check` as 0 there. So the token needs no gate of its own —
        // it never has anything to accompany.
        guard inCheck else { return side }
        return String(format: String(localized: "status.sideToMove.checked"),
                      side, String(localized: "status.check"))
    }

    /// The second line: who owns the turn, and what else is true of the game.
    ///
    /// The two are joined by the accepted metadata format rather than by
    /// concatenation, and applied repeatedly rather than once per line length,
    /// exactly as the metadata lines elsewhere are composed.
    private var secondary: String? {
        let words = reasonText ?? reason.text
        let claimOrReason: String? = switch state {
        case .ongoing: nil
        case .claimableDraw: String(format: String(localized: "metadata.join"),
                                    String(localized: "status.drawAvailable"), words)
        default: words.isEmpty ? nil : words
        }
        // The controller label belongs to a turn, so it stops when the turn
        // does: a finished game is nobody's to move.
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
    /// The stalled state: the AI could not be prepared mid-game, the player
    /// answered 稍后, and the game is saved. Issue #71's decision 2 puts it in
    /// the turn status's own activity slot with an inline 重试 beside it.
    ///
    /// It is a type of its own because it stands in two places for one reason:
    /// inside the element where the element is a block, and beneath the bar
    /// where the element is in it. Same words, same identifiers, same act.
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

        /// 重试, in each platform's own inline-action weight.
        ///
        /// It sits inside a sentence about the game rather than in a control
        /// cluster, so it takes the style the platform gives an action written
        /// into text: AppKit's link style on macOS, which UIKit has no
        /// counterpart for, and the borderless style on iOS and iPadOS, which
        /// is the accent-tinted text button the platform puts beside a line of
        /// prose. Same control, same identifier, same words; only the weight is
        /// the platform's.
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
        case .fiftyMoveRule: String(localized: "reason.fiftyMoveRule")
        case .resignation: String(localized: "reason.resignation")
        case .endedEarly: String(localized: "reason.endedEarly")
        case .agreedDraw: String(localized: "reason.agreedDraw")
        case .mutualResignation: String(localized: "reason.mutualResignation")
        // No reason is no words, in every language.
        case .none: ""
        }
    }
}
