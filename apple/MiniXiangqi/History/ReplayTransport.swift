// Replay's controls: the transport, and 翻转棋盘.
//
// docs/interaction-design.md, "Play controls": replay offers no move input, so
// no play control applies — the cluster here is the transport plus the flip
// control, and it is one of the three surfaces custom glass belongs to.
//
// The transport is the five the contract names: jump to beginning, one move
// back, play or pause, one move forward, jump to end. Every one of them is
// icon-only and carries its words as an accessibility label, because five
// labelled buttons would not fit beside a board and a transport is the one
// place a glyph is genuinely the familiar form.

import SwiftUI

struct ReplayTransport: View {
    var isAtStart: Bool
    var isAtEnd: Bool
    var autoplaying: Bool

    var goToStart: () -> Void
    var stepBack: () -> Void
    var toggleAutoplay: () -> Void
    var stepForward: () -> Void
    var goToEnd: () -> Void
    var flip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                control("replay.first", "backward.end.fill", "replay-first",
                        enabled: !isAtStart, action: goToStart)
                control("replay.previous", "chevron.left", "replay-previous",
                        enabled: !isAtStart, action: stepBack)
                // Playback starts only after a user action and stops at the
                // final position, so at the end there is nothing to start.
                control(autoplaying ? "replay.pause" : "replay.autoplay",
                        autoplaying ? "pause.fill" : "play.fill",
                        "replay-autoplay",
                        enabled: !isAtEnd || autoplaying, action: toggleAutoplay)
                control("replay.next", "chevron.right", "replay-next",
                        enabled: !isAtEnd, action: stepForward)
                control("replay.last", "forward.end.fill", "replay-last",
                        enabled: !isAtEnd, action: goToEnd)
                Spacer(minLength: 0)
            }

            // The accepted orientation control, which replay keeps: a visible
            // control rather than a hidden gesture, with the same label it
            // carries during play.
            Button {
                flip()
            } label: {
                Label("control.flipBoard", systemImage: "arrow.up.arrow.down")
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("control.flipBoard"))
            .accessibilityIdentifier("replay-flip")
        }
    }

    private func control(_ label: LocalizedStringKey, _ symbol: String,
                         _ identifier: String, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label(label, systemImage: symbol).labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }
}
