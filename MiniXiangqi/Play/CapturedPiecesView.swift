// Discs use the board's own `PieceDrawing`, so a disc here and the disc it was
// on the board are one drawing. The losses a reader may not see are face-down
// discs at the row's end: the face-down disc already means a piece its reader
// cannot name, and an anonymous tail has no order worth keeping. A piece that
// left the board face down is drawn with its symbol partway arrived, so an
// open capture and a disclosed one never read the same.

import SwiftUI

struct CapturedPiecesView: View {
    var captured: CapturedPieces
    var game: GameKind
    var throughPly: Int
    /// Nil where one person holds both hands.
    var viewer: Side?
    /// Whether the game has ended.
    var disclosed: Bool
    var style: BoardStyle = .traditional
    /// The resident default, or the board's width-fitted pitch where a sheet
    /// passes it.
    var pitch: CGFloat = BoardLayout.capturedDiscPitch

    /// Read here so that flipping the preference repaints these discs as it
    /// does the board's.
    @AppStorage(PieceSymbols.key) private var symbols: PieceSymbols = .hanzi

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

    private func row(of panel: CapturedPieces.Panel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(game.sideName(panel.side))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            // Wraps rather than scrolls sideways: fifteen discs never fit a
            // panel's width, and scrolling would hide the very material shown.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: pitch),
                                         spacing: 0, alignment: .leading)],
                      alignment: .leading, spacing: 0) {
                let discs: [(piece: Piece, arrival: Double)] = panel.pieces.map {
                    (Piece(kind: $0.kind, side: $0.side),
                     $0.wasFaceDown ? BoardLayout.capturedWasHiddenArrival : 1)
                } + Array(repeating: (Piece(kind: nil, side: panel.side,
                                            isFaceDown: true), 1),
                          count: panel.hidden)
                ForEach(Array(discs.enumerated()), id: \.offset) { _, disc in
                    PieceDisc(piece: disc.piece, pitch: pitch,
                              board: game.board, style: style,
                              symbols: symbols,
                              symbolOpacity: disc.arrival)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(panel.side == .red ? "captured-red" : "captured-black")
        .accessibilityLabel(describe(panel))
    }

    private func describe(_ panel: CapturedPieces.Panel) -> String {
        var parts = [game.sideName(panel.side)]
        parts += panel.pieces.map { shown in
            // Says in words what the discs say by the symbol's partial arrival.
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
