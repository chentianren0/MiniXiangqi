// The moves so far, in whichever notation the 记谱法 preference selects, paired
// by full move.
//
// Each row's words are chosen here rather than upstream, so a preference changed
// while a game is on screen re-renders that game's whole list at once — and the
// list's structure, its numbering, its pairing and its layout, is the same
// either way. Only the words in the two columns change.
//
// Where the side-by-side layout applies — most Mac windows, iPad landscape —
// the move list is permanently visible in the panel. Where the stacked layout
// applies it is the same list on a different surface: `PlayScreen` reaches it
// from a toolbar item over a half-height sheet, so it costs the board and the
// controls nothing until it is asked for. Either way it is presentation: what
// is stored is the canonical notation, and this never shows it.
//
// Replay reads the same list with two things added, because its accepted
// behaviour asks for them: the move the board is showing is indicated, and any
// move can be selected to jump to it. During play neither applies — the list
// is a record of what has happened, and the last row is always the position.
//
// **A row is Red's cell then Black's, in the order the two were played**, and
// which side opened is the game's start position's to say. A game composed in
// the Custom Scene editor may open with Black: its first row is numbered 1 and
// carries Black's opening ply beside an empty Red cell, and Red's answer opens
// the next row. Left to right is always forward in time, which is what a score
// sheet reads as. No mover is read off a ply's parity.

import SwiftUI

struct MoveList: View {
    var notation: [MoveReading]

    /// Whose ply index 0 is. It comes from the game or the record — which asked
    /// the core — and never from anything worked out here.
    ///
    /// Required rather than defaulted: a default would be Red, and a call site
    /// that forgot it would silently pair a Black-first game the old wrong way
    /// instead of failing to compile.
    var firstMover: Side

    /// The move the board is showing, as an index into `notation`. `nil` during
    /// play, and at replay's initial position, where no move has produced what
    /// is on screen.
    var currentMove: Int?

    /// Jumping to a move, which replay allows and play does not.
    var onSelect: ((Int) -> Void)?

    @Environment(\.motionPolicy) private var policy

    /// The 记谱法 preference, read where the words are chosen so that changing it
    /// re-renders the list live. Unchosen, it is the interface language's own
    /// reading — `NotationStyle.resolvedForInterfaceLanguage`.
    @AppStorage(NotationStyle.key, store: Preferences.defaults)
    private var style: NotationStyle = .resolvedForInterfaceLanguage

    private var pairing: MovePairing {
        MovePairing(plies: notation.count, firstMover: firstMover)
    }

    /// The row the shown move sits in, which is what a walk scrolls to.
    private var currentRow: Int? {
        currentMove.map { pairing.row(of: $0) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(pairing.rows, id: \.number) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            // Numerals and a full stop, keyed all the same: it
                            // is what a row is numbered with, and what a
                            // language puts around a number is that language's
                            // to say.
                            Text(String(format: String(localized: "moveList.rowNumber"), row.number))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .trailing)
                            // A row whose Red cell is empty is a Black-first
                            // game's first row: the pair is still Red's slot
                            // and Black's, and the slot nobody played is left
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

    /// One half-move, already rendered in the selected notation. The moves
    /// themselves are game presentation rather than interface copy — the same
    /// characters, or the same letters and digits, in every language — so a row
    /// is read out as exactly what it shows, whichever notation that is.
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

/// How a line of plies falls into numbered pairs, given who opened it.
///
/// It is a value rather than a computation inside the view because the answer
/// is the contract's own — a row is Red's cell then Black's in the order the
/// two were played, the first row is numbered 1, and which side opened is the
/// start position's to say — and because the words in the cells are the only
/// thing about the list that a notation preference changes. A Red-first game is
/// the identity case: slot and ply index are the same number.
nonisolated struct MovePairing: Equatable {
    /// One printed row: its number, and the ply in each side's cell where the
    /// line has one.
    struct Row: Equatable {
        var number: Int
        /// The index into the line of the Red cell's ply, or nil where the row
        /// has none — the first row of a game Black opened.
        var red: Int?
        /// The same for the Black cell, nil where the line stops at Red's ply.
        var black: Int?
    }

    var plies: Int
    var firstMover: Side

    /// How far the first mover's ply sits into its pair. Zero when Red opened,
    /// one when Black did — Black's ply being the second cell of the pair.
    private var offset: Int { firstMover == .red ? 0 : 1 }

    var rows: [Row] {
        guard plies > 0 else { return [] }
        return stride(from: 0, to: plies + offset, by: 2).map { slot in
            Row(number: slot / 2 + 1,
                red: ply(atSlot: slot),
                black: ply(atSlot: slot + 1))
        }
    }

    /// Which row a ply is printed in, which is what a walk scrolls to.
    func row(of ply: Int) -> Int { (ply + offset) / 2 + 1 }

    private func ply(atSlot slot: Int) -> Int? {
        let index = slot - offset
        return (0..<plies).contains(index) ? index : nil
    }
}
