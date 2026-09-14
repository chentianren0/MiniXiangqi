// Replay's controls: the transport, and 翻转棋盘.
//
// docs/interaction-design.md, "Play controls": replay offers no move input, so
// no play control applies — the cluster here is the transport plus the flip
// control, where the record's game has an orientation to change, and it is one
// of the three surfaces custom glass belongs to.
//
// The transport is the five the contract names: jump to beginning, one move
// back, play or pause, one move forward, jump to end. Every one of them is
// icon-only and carries its words as an accessibility label, because five
// labelled buttons would not fit beside a board and a transport is the one
// place a glyph is genuinely the familiar form.
//
// **The cluster is a grid, and the grid is what was wrong with it.** The owner
// asked from the iPhone (2026-07-30) for the buttons' positional relationships
// and alignment rather than for different buttons: they worked and they sat in
// reasonable places. What they did not do was line up. The five transport
// controls were sized by their own glyphs, so a row that means *one control per
// step* was drawn as five different widths; the gap inside the row was 4 points
// while the gap to the row beneath it was 8; and neither row's trailing edge
// was anywhere in particular, so the cluster had a left edge and no right one.
//
// So: one gap everywhere, five equal cells, and both rows filling the width
// they are given. The cluster's leading and trailing edges are now the same two
// as the header's and the move list's, and the whole page reads down one
// column.

import SwiftUI

struct ReplayTransport: View {
    var isAtStart: Bool
    var isAtEnd: Bool
    var autoplaying: Bool

    /// Whether the record's game has an orientation to change. A placement
    /// record has none, and the control is absent rather than disabled: absence
    /// is what says a capability is not there at all, which is the same answer
    /// the play cluster gives on the same boards.
    var carriesFlip: Bool

    var goToStart: () -> Void
    var stepBack: () -> Void
    var toggleAutoplay: () -> Void
    var stepForward: () -> Void
    var goToEnd: () -> Void
    var flip: () -> Void

    /// The one distance in the cluster: between two controls in the row, and
    /// between the row and the control under it. Two numbers where one will do
    /// is what makes a cluster look assembled rather than laid out, and this is
    /// the number the play screen's own cluster already uses.
    private static let gap: CGFloat = 8

    var body: some View {
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) {
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
            }

            // The accepted orientation control, which replay keeps for the
            // games that have an orientation: a visible control rather than a
            // hidden gesture, with the same label it carries during play. It
            // spans the same width the transport above it spans, because the
            // two are one cluster and a control whose trailing edge stops
            // halfway is a control that has been dropped next to the row rather
            // than placed under it. Without it the row is the whole cluster,
            // and its own edges are already the ones the grid promises.
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

    /// One transport control, in a cell the same size as its four neighbours'.
    ///
    /// The width is the row's to give and not the glyph's to ask for: a chevron
    /// is narrower than a bar-and-triangle, and five buttons sized by their own
    /// symbols draw a ragged row out of five equal steps. The frame is on the
    /// label rather than on the button so that the glass itself is the cell,
    /// which is also what makes each step's touch target the same size as the
    /// step beside it.
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
