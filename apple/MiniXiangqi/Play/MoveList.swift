// The moves so far, in traditional notation, paired by full move.
//
// Where the side-by-side layout applies — ordinary Mac windows, iPad landscape
// — the move list is permanently visible in the panel. It is presentation:
// what is stored is the canonical notation, and this never shows it.
//
// Replay reads the same list with two things added, because its accepted
// behaviour asks for them: the move the board is showing is indicated, and any
// move can be selected to jump to it. During play neither applies — the list
// is a record of what has happened, and the last row is always the position.

import SwiftUI

struct MoveList: View {
    var notation: [String]

    /// The move the board is showing, as an index into `notation`. `nil` during
    /// play, and at replay's initial position, where no move has produced what
    /// is on screen.
    var currentMove: Int?

    /// Jumping to a move, which replay allows and play does not.
    var onSelect: ((Int) -> Void)?

    @Environment(\.motionPolicy) private var policy

    private var rows: [(number: Int, red: String, black: String?)] {
        stride(from: 0, to: notation.count, by: 2).map { index in
            (number: index / 2 + 1,
             red: notation[index],
             black: index + 1 < notation.count ? notation[index + 1] : nil)
        }
    }

    /// The row the shown move sits in, which is what a walk scrolls to.
    private var currentRow: Int? {
        currentMove.map { $0 / 2 + 1 }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rows, id: \.number) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            // Numerals and a full stop, keyed all the same: it
                            // is what a row is numbered with, and what a
                            // language puts around a number is that language's
                            // to say.
                            Text(String(format: String(localized: "moveList.rowNumber"), row.number))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .trailing)
                            move(row.red, at: (row.number - 1) * 2)
                            if let black = row.black {
                                move(black, at: (row.number - 1) * 2 + 1)
                            } else {
                                Color.clear.frame(width: 76, height: 0)
                            }
                        }
                        .font(.callout)
                        .id(row.number)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: notation.count) {
                guard let last = rows.last else { return }
                scroll(proxy, to: last.number)
            }
            .onChange(of: currentRow) {
                guard let currentRow else { return }
                scroll(proxy, to: currentRow)
            }
        }
    }

    /// One half-move. The moves themselves are traditional notation: game
    /// presentation rather than interface copy, the same characters in every
    /// language.
    @ViewBuilder
    private func move(_ text: String, at index: Int) -> some View {
        let shown = index == currentMove
        let label = Text(verbatim: text)
            .frame(width: 76, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background {
                // The indicated move is carried by a filled shape rather than
                // by colour alone, and in neutral primary: tint on a board
                // screen belongs to the sides.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(shown ? 0.12 : 0))
            }
            .fontWeight(shown ? .semibold : .regular)

        if let onSelect {
            Button { onSelect(index) } label: { label }
                .buttonStyle(.plain)
                .accessibilityIdentifier("move-\(index)")
        } else {
            label
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to row: Int) {
        // An animated scroll is movement with no crossfade to fall back to, so
        // under Reduce Motion it arrives immediately.
        withAnimation(policy.scroll(.default)) {
            proxy.scrollTo(row, anchor: .bottom)
        }
    }
}
