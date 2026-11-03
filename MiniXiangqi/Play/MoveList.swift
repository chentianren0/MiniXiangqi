// The words are chosen here, so changing the 记谱法 preference re-renders a
// game's whole list at once; only the words in the two columns change. What is
// stored is the canonical notation, which this never shows.

import SwiftUI

struct MoveList: View {
    var notation: [MoveReading]

    /// From the game or the record, which asked the core. Required, not
    /// defaulted to Red, so a call site that forgot it fails to compile rather
    /// than mis-pairing a Black-first game.
    var firstMover: Side

    /// An index into `notation`; nil during play and at replay's initial
    /// position, where no move has produced what is on screen.
    var currentMove: Int?

    /// Jumping to a move, which replay allows and play does not.
    var onSelect: ((Int) -> Void)?

    @Environment(\.motionPolicy) private var policy

    /// Read where the words are chosen, so changing it re-renders the list live.
    @AppStorage(NotationStyle.key)
    private var style: NotationStyle = .resolvedForInterfaceLanguage

    private var pairing: MovePairing {
        MovePairing(plies: notation.count, firstMover: firstMover)
    }

    private var currentRow: Int? {
        currentMove.map { pairing.row(of: $0) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(pairing.rows, id: \.number) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            // Keyed though it is only a numeral and a full
                            // stop: what goes around a number is each
                            // language's to say.
                            Text(String(format: String(localized: "moveList.rowNumber"), row.number))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .trailing)
                            // A Black-first game's empty first Red cell stays
                            // standing rather than closed up.
                            cell(row.red)
                            cell(row.black)
                        }
                        .font(.callout)
                        .id(row.number)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: notation.count) {
                guard let last = pairing.rows.last else { return }
                scroll(proxy, to: last.number)
            }
            .onChange(of: currentRow) {
                guard let currentRow else { return }
                scroll(proxy, to: currentRow)
            }
        }
    }

    @ViewBuilder
    private func cell(_ index: Int?) -> some View {
        if let index {
            move(notation[index].text(in: style), at: index)
        } else {
            Color.clear.frame(width: 76, height: 0)
        }
    }

    /// Verbatim: moves are game presentation, the same in every language, not
    /// interface copy.
    @ViewBuilder
    private func move(_ text: String, at index: Int) -> some View {
        let shown = index == currentMove
        let label = Text(verbatim: text)
            .frame(width: 76, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background {
                // Filled and in neutral primary: tint on a board screen belongs
                // to the sides.
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
        // No crossfade to fall back to, so under Reduce Motion it arrives at
        // once.
        withAnimation(policy.scroll(.default)) {
            proxy.scrollTo(row, anchor: .bottom)
        }
    }
}

/// A row is Red's cell then Black's in playing order, numbered from 1, and
/// which side opened is the start position's to say. A game Black opens has an
/// empty Red cell in row 1, so left to right is always forward in time. No
/// mover is read off a ply's parity.
nonisolated struct MovePairing: Equatable {
    struct Row: Equatable {
        var number: Int
        /// Nil in the first row of a game Black opened.
        var red: Int?
        /// Nil where the line stops at Red's ply.
        var black: Int?
    }

    var plies: Int
    var firstMover: Side

    private var offset: Int { firstMover == .red ? 0 : 1 }

    var rows: [Row] {
        guard plies > 0 else { return [] }
        return stride(from: 0, to: plies + offset, by: 2).map { slot in
            Row(number: slot / 2 + 1,
                red: ply(atSlot: slot),
                black: ply(atSlot: slot + 1))
        }
    }

    func row(of ply: Int) -> Int { (ply + offset) / 2 + 1 }

    private func ply(atSlot slot: Int) -> Int? {
        let index = slot - offset
        return (0..<plies).contains(index) ? index : nil
    }
}
