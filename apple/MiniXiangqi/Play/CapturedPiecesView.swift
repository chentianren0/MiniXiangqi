// The captured-pieces surface: two rows of discs and two counts.
//
// docs/interaction-design.md, "Captured pieces". The rows are the losses of one
// side each, drawn as the board draws those pieces — the same `PieceDrawing` the
// board and the Custom Scene palette call, at whatever pitch this surface can
// spare, so a disc here and the disc it was on the board are one drawing. The
// count beside a row is what that reader may not see: their own hidden losses,
// which tell them a piece is gone and never which.
//
// **Where the rows and the counts stand, how large their discs are, and how a
// disclosure arrives are settled against the rendered board**, as every other
// visual specific in that document is. What is settled here is what each part
// says; what it looks like is the owner's to judge on a device.
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
                // The surface is resident, so it is here before there is
                // anything in it and says so rather than standing as a gap of
                // unexplained air.
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

    /// One side's losses: whose they are, the discs, and the count of the ones
    /// this reader may not see.
    private func row(of panel: CapturedPieces.Panel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(game.sideName(panel.side))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if panel.hidden > 0 {
                    Text(String(format: String(localized: "captured.hidden"),
                                panel.hidden))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            // A wrapping grid rather than one row: fifteen discs never fit a
            // panel's width, and a surface that scrolled sideways would hide
            // exactly the material it exists to show.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: BoardLayout.capturedDiscPitch),
                                         spacing: 0, alignment: .leading)],
                      alignment: .leading, spacing: 0) {
                ForEach(Array(panel.pieces.enumerated()), id: \.offset) { _, piece in
                    PieceDisc(piece: piece, pitch: BoardLayout.capturedDiscPitch,
                              board: game.board, style: style,
                              symbols: PieceSymbols.named(storedSymbols))
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
        parts += panel.pieces.compactMap { piece in
            piece.kind.map { $0.name(for: piece.side) }
        }
        if panel.hidden > 0 {
            parts.append(String(format: String(localized: "captured.hidden"),
                                panel.hidden))
        }
        return parts.joined(separator: " ")
    }
}
