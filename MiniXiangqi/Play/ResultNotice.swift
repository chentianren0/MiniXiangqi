// The notice is dismissible and leaves the board undimmed: the moment a result
// arrives is when a learner wants to study the position, and closing it changes
// nothing about the game. 保存 is the tinted action because a finished game is
// wanted kept far more often than a new one dealt. 悔棋 stays in the play
// controls only; offering one action in two places teaches nothing about either.

import SwiftUI

struct ResultNotice: View {
    /// Who won is said in that game's own words for its two sides.
    var game: GameKind
    var state: GameState
    var reason: EndReason
    /// Whether the game is already an immutable History record.
    var recorded: Bool
    /// Files the game and leaves the board standing at the recorded result.
    var save: () -> Void
    /// Files the game and opens its mode's pre-start page, in one press.
    var startNewGame: () -> Void
    /// Back to the Play home, filing nothing a second time.
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

            // The tinted action is trailing, where this platform's default
            // action stands, and carries the Return key to match.
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
            // The system's own close control, so there is no new string to
            // translate.
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
            // Under Reduce Motion the notice crossfades in at full size.
        .scaleEffect(settled || policy.reduceMotion ? 1 : 0.92)
        .opacity(settled ? 1 : 0)
        .onAppear {
            withAnimation(policy.appear) {
                settled = true
            }
            // Announced rather than made modal, so the final position stays
            // explorable. Joined by a format string because the separator
            // differs by language (an ideographic comma in Chinese).
            AccessibilityNotification
                .Announcement(String(format: String(localized: "result.announcement"),
                                     title, reason.text))
                .post()
        }
    }

    /// Once the game is filed, says where it went instead; the turn status still
    /// carries the result.
    private var title: String {
        if recorded { return String(localized: "result.recorded") }
        switch state {
        case .redWins: return game.resultText(.red)
        case .blackWins: return game.resultText(.black)
        // A finished game that neither side won is a draw.
        case .draw, .ongoing, .claimableDraw: return String(localized: "result.draw")
        }
    }
}
