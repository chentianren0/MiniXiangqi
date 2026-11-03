// Icon-only, with the words as accessibility labels: five labelled buttons
// would not fit beside a board. One gap everywhere and five equal cells, both
// rows filling their width, so the cluster lines up with the header and list.

import SwiftUI

struct ReplayTransport: View {
    var isAtStart: Bool
    var isAtEnd: Bool
    var autoplaying: Bool

    /// Absent rather than disabled on a placement record: absence says the
    /// capability is not there at all, as in the play cluster.
    var carriesFlip: Bool

    var goToStart: () -> Void
    var stepBack: () -> Void
    var toggleAutoplay: () -> Void
    var stepForward: () -> Void
    var goToEnd: () -> Void
    var flip: () -> Void

    /// Between two controls in the row and between the rows: one number, the
    /// one the play screen's cluster uses.
    private static let gap: CGFloat = 8

    var body: some View {
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                control("replay.first", "backward.end.fill", "replay-first",
                        enabled: !isAtStart, action: goToStart)
                control("replay.previous", "chevron.left", "replay-previous",
                        enabled: !isAtStart, action: stepBack)
                // At the end there is nothing to start.
                control(autoplaying ? "replay.pause" : "replay.autoplay",
                        autoplaying ? "pause.fill" : "play.fill",
                        "replay-autoplay",
                        enabled: !isAtEnd || autoplaying, action: toggleAutoplay)
                control("replay.next", "chevron.right", "replay-next",
                        enabled: !isAtEnd, action: stepForward)
                control("replay.last", "forward.end.fill", "replay-last",
                        enabled: !isAtEnd, action: goToEnd)
            }

            // Spans the transport's full width: the two are one cluster.
            if carriesFlip {
                Button {
                    flip()
                } label: {
                    Label("control.flipBoard", systemImage: "arrow.up.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(Text("control.flipBoard"))
                .accessibilityIdentifier("replay-flip")
            }
        }
    }

    /// The width is the row's to give, not the glyph's, so five steps draw as
    /// five equal cells. The frame is on the label so the glass itself, and the
    /// touch target, is the cell.
    private func control(_ label: LocalizedStringKey, _ symbol: String,
                         _ identifier: String, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }
}
