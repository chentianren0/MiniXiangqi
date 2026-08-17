// The captured-pieces surface: two rows of discs.
//
// docs/interaction-design.md, "Captured pieces". The rows are the losses of one
// side each, drawn as the board draws those pieces — the same `PieceDrawing` the
// board and the Custom Scene palette call, at whatever pitch this surface can
// spare, so a disc here and the disc it was on the board are one drawing. The
// losses a reader may not see — their own hidden ones, which tell them a piece
// is gone and never which — are that many face-down discs at the row's end,
// after the revealed pieces: the face-down disc is already the surface's word
// for a piece its reader cannot name, and an anonymous tail carries no order
// worth keeping. A piece that left the board face down is drawn with its
// symbol partway arrived — the reveal's own axis, held — wherever this reader
// sees it whole, so an open capture and a disclosed one never read the same.
//
// **Where the rows stand, how large their discs are, and how a disclosure
// arrives are settled against the rendered board**, as every other visual
// specific in that document is. What is settled here is what each part says;
// what it looks like is the owner's to judge on a device.
//
// It derives nothing. `CapturedPieces` is what a game took and who may see it,
// and this draws that answer.

import SwiftUI

struct CapturedPiecesView: View {
    var captured: CapturedPieces
    var game: GameKind
    /// How far into the game the surface stands — a live board's own ply count,
    /// or wherever a replay has walked to.
    var throughPly: Int
    /// Whose eyes these are, or nil where one person holds both hands.
    var viewer: Side?
    /// Whether the game has ended, which discloses everything to both players.
    var disclosed: Bool
    var style: BoardStyle = .traditional

    /// The 棋子符号 preference, read here for the reason the board reads it:
    /// these are the board's own discs, and flipping the preference has to
    /// repaint them with it.
    @AppStorage(PieceSymbols.key, store: Preferences.defaults) private var storedSymbols: String?

    private var panels: [CapturedPieces.Panel] {
        [Side.red, .black].map {
            captured.panel(of: $0, throughPly: throughPly, seenBy: viewer,
                           disclosed: disclosed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let panels = panels
            if panels.allSatisfy({ $0.pieces.isEmpty && $0.hidden == 0 }) {
                // The empty state stands wherever the surface stands —
                // resident in a panel or raised as a sheet — and says so
                // rather than answering a reader with unexplained air.
                Text("captured.empty")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("captured-empty")
            } else {
                ForEach(panels, id: \.side) { row(of: $0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One side's losses: whose they are, then the discs — the revealed pieces
    /// first, and the ones this reader may not see as face-down discs after
    /// them. The count still reaches a screen reader in words, through the
    /// row's own label, where discs cannot be counted at a glance.
    private func row(of panel: CapturedPieces.Panel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(game.sideName(panel.side))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            // A wrapping grid rather than one row: fifteen discs never fit a
            // panel's width, and a surface that scrolled sideways would hide
            // exactly the material it exists to show.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: BoardLayout.capturedDiscPitch),
                                         spacing: 0, alignment: .leading)],
                      alignment: .leading, spacing: 0) {
                let discs: [(piece: Piece, arrival: Double)] = panel.pieces.map {
                    (Piece(kind: $0.kind, side: $0.side),
                     $0.wasFaceDown ? BoardLayout.capturedWasHiddenArrival : 1)
                } + Array(repeating: (Piece(kind: nil, side: panel.side,
                                            isFaceDown: true), 1),
                          count: panel.hidden)
                ForEach(Array(discs.enumerated()), id: \.offset) { _, disc in
                    PieceDisc(piece: disc.piece, pitch: BoardLayout.capturedDiscPitch,
                              board: game.board, style: style,
                              symbols: PieceSymbols.named(storedSymbols),
                              symbolOpacity: disc.arrival)
                }
            }
        }
        // One element per side, because that is what a reader is asking about:
        // whose pieces are gone, which ones, and how many they cannot see. The
        // vocabulary is the board's own — the same side word and the same piece
        // names a point's description is composed from.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(panel.side == .red ? "captured-red" : "captured-black")
        .accessibilityLabel(describe(panel))
    }

    private func describe(_ panel: CapturedPieces.Panel) -> String {
        var parts = [game.sideName(panel.side)]
        parts += panel.pieces.map { shown in
            // The telling reaches a reader who hears the row too: the hidden
            // word joined to the name, where the discs say it by arrival.
            let name = shown.kind.name(for: shown.side)
            return shown.wasFaceDown
                ? String(format: String(localized: "captured.wasHidden"), name)
                : name
        }
        if panel.hidden > 0 {
            parts.append(String(format: String(localized: "captured.hidden"),
                                panel.hidden))
        }
        return parts.joined(separator: " ")
    }
}
