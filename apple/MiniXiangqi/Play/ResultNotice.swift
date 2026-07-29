// What the game says when it is over.
//
// docs/interaction-design.md, "Natural result presentation": the result is a
// notice in front of the board, and the board behind it is otherwise unchanged
// and undimmed. It is dismissible, because the moment a result arrives is
// exactly when a learner wants to study the position that produced it, and the
// squares under the notice are usually the ones worth studying. Closing it
// changes nothing about the game: the turn status still carries the result and
// the play controls still carry the actions.
//
// Until History exists the concluding action starts a new game directly, so
// this shows 开始新对局 where the contract's recorded flow will later show
// 结束对局. It is the one tinted element on screen, which the tint rule allows
// a moment with a single obvious next action.

import SwiftUI

struct ResultNotice: View {
    var state: GameState
    var reason: EndReason
    var canUndo: Bool
    var undo: () -> Void
    var startNewGame: () -> Void
    var close: () -> Void

    @Environment(\.motionPolicy) private var policy
    @State private var settled = false

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("result-title")

            if !reason.text.isEmpty {
                Text(reason.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("result-reason")
            }

            HStack(spacing: 10) {
                if canUndo {
                    Button("control.undo", action: undo)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("result-undo")
                }
                Button("control.newGame", action: startNewGame)
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("result-new-game")
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .overlay(alignment: .topTrailing) {
            // The system's own close control, so the one name this adds is the
            // platform's rather than a new string to translate. It shows as its
            // symbol: the word belongs to the screen reader, not to a corner of
            // a small panel.
            Button(role: .close) { close() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("result-close")
                .padding(8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        // The entrance consults the one Reduce Motion rule: the scale settle
        // is motion, so under the policy the notice crossfades in at full
        // size instead.
        .scaleEffect(settled || policy.reduceMotion ? 1 : 0.92)
        .opacity(settled ? 1 : 0)
        .onAppear {
            withAnimation(policy.appear) {
                settled = true
            }
            // Announced rather than made modal: the final position stays
            // explorable, so VoiceOver hears the result without losing the
            // board it came from. The two halves are joined by a format string
            // rather than by interpolation: the separator is an ideographic
            // comma in Chinese and a comma and a space in English, and neither
            // can be hard-coded around the other language's fragment.
            AccessibilityNotification
                .Announcement(String(format: String(localized: "result.announcement"),
                                     title, reason.text))
                .post()
        }
    }

    /// The fuller wording, which has room to be a sentence about the game
    /// where the status line has to be a line about the turn.
    private var title: String {
        switch state {
        case .redWins: String(localized: "result.redWins")
        case .blackWins: String(localized: "result.blackWins")
        // A finished game that neither side won is a draw, whether the core
        // adjudicated it or the player claimed it.
        case .draw, .ongoing, .claimableDraw: String(localized: "result.draw")
        }
    }
}
