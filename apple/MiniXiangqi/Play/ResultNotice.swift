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
// The notice has two states, and which one it is in is a fact about the game
// rather than about this view. While the result is still the player's to undo,
// the actions are 悔棋 and the concluding one. Once the game has been filed —
// which a claimed draw is the moment the claim commits — the record exists, and
// the notice says so: 已记录到历史, with 回放 to watch it back and 完成 to
// return to the start state. There is nothing left to undo at that point, and
// offering it would be offering to undo a History record.
//
// The concluding action is still 开始新对局 rather than the contract's 结束对局
// because in this app it still does both things at once: it files the game and
// resets the board in one press. Splitting the two is a flow change and not a
// label change, and it is not this PR's.
//
// Whichever state it is in, one action is tinted, which the tint rule allows a
// moment with a single obvious next step.

import SwiftUI

struct ResultNotice: View {
    var state: GameState
    var reason: EndReason
    var canUndo: Bool
    /// Whether the game is already an immutable History record.
    var recorded: Bool
    var undo: () -> Void
    var startNewGame: () -> Void
    var replay: () -> Void
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
                if recorded {
                    Button("control.replay", action: replay)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("result-replay")
                    Button("control.done", action: startNewGame)
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("result-done")
                } else {
                    if canUndo {
                        Button("control.undo", action: undo)
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("result-undo")
                    }
                    Button("control.newGame", action: startNewGame)
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("result-new-game")
                }
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
    /// where the status line has to be a line about the turn — and, once the
    /// game is filed, the accepted sentence about where it went instead. The
    /// result itself is not lost by that: the turn status is still carrying it,
    /// a few points below, and the reason line under this title is unchanged.
    private var title: String {
        if recorded { return String(localized: "result.recorded") }
        switch state {
        case .redWins: return String(localized: "result.redWins")
        case .blackWins: return String(localized: "result.blackWins")
        // A finished game that neither side won is a draw, whether the core
        // adjudicated it or the player claimed it.
        case .draw, .ongoing, .claimableDraw: return String(localized: "result.draw")
        }
    }
}
