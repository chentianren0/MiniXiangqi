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
// rather than about this view. While the result is unconfirmed, both actions
// save it: 保存 files the game and leaves the board exactly where the result
// left it, and 保存并开始新对局 files it and resets the board in one press.
// 保存 is the tinted one, because the owner's own use said so — after a game
// they want the finished game kept far more often than they want the next one
// dealt. Once the game has been filed — by either of those, or by a claimed
// draw the moment the claim commits — the record exists, and the notice says
// so: 已记录到历史, with 回放 to watch it back and 完成 to return to the start
// state. So a saved natural result reads as the two-beat it is: result, save,
// recorded.
//
// 悔棋 is not here. It was offered twice for as long as the notice carried it —
// once in front of the board and once in the cluster behind it — and offering
// one action in two places teaches nothing about either. The cluster keeps it,
// where every other play control lives, and closing the notice with the X
// leaves it exactly as available as it was: closing saves nothing, so an
// unconfirmed result is still the player's to take back. (Owner decision,
// 2026-07-29.)
//
// 保存并开始新对局 is the longer label the cluster's 开始新对局 grew into, and
// it is still 开始新对局's own act: the concluding action always filed the game
// before it reset the board, and naming the filing is what the notice's first
// action being 保存 makes necessary. The two sit side by side here as they did
// on macOS before; iOS revisits whether they stack at Stage 6, where the
// stacked layout arrives.
//
// Whichever state it is in, one action is tinted, which the tint rule allows a
// moment with a single obvious next step.

import SwiftUI

struct ResultNotice: View {
    /// Which game the result belongs to, because who won is said in that game's
    /// own words for its two sides.
    var game: GameKind
    var state: GameState
    var reason: EndReason
    /// Whether the game is already an immutable History record.
    var recorded: Bool
    /// Files the game and leaves the board standing at the recorded result.
    var save: () -> Void
    /// Files the game and opens its mode's pre-start page, in one press.
    var startNewGame: () -> Void
    /// 完成: back to the Play home, filing nothing a second time.
    var finish: () -> Void
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

            // The tinted action is the trailing one in both states, which is
            // where this platform's default action stands, and it carries the
            // Return key to match — the cancel key already closes the notice,
            // and a moment with one obvious next step should answer to the
            // keyboard as well as to the pointer.
            HStack(spacing: 10) {
                if recorded {
                    Button("control.replay", action: replay)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("result-replay")
                    Button("control.done", action: finish)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("result-done")
                } else {
                    Button("control.saveAndNewGame", action: startNewGame)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("result-new-game")
                    Button("control.save", action: save)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("result-save")
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
        case .redWins: return game.resultText(.red)
        case .blackWins: return game.resultText(.black)
        // A finished game that neither side won is a draw, whether the core
        // adjudicated it or the player claimed it.
        case .draw, .ongoing, .claimableDraw: return String(localized: "result.draw")
        }
    }
}
