// The Custom Scene editor, on screen.
//
// docs/interaction-design.md, "Custom Scene": a pre-start page over the Play
// home, left by the back control in the toolbar, creating nothing until
// 开始对局. The board is empty and **interactive**, so it takes the interactive
// pitch floor rather than the exemption that section grants a pre-start
// preview: every point on it is a target, and the fitting is the play board's
// own for exactly that reason.
//
// The page is the two layout shapes like every other board page — the board
// with the editor's controls beside it, or above them — and what stands in the
// panel is the palette, the side-to-move choice, the one reason the position is
// not one to start from, and 开始对局.
//
// Nothing here decides anything: the draft, the composed FEN and the core's
// verdict are `CustomScene`'s, and this draws them.

import SwiftUI

struct CustomSceneScreen: View {
    let play: PlayState
    let scene: CustomScene

    @Environment(\.motionPolicy) private var policy

    /// What the panel beneath the board came to, measured rather than allowed
    /// for: the palette is as tall as the reader's text size makes it, and the
    /// board is fitted into what is left — never below its own floor, which is
    /// what `BoardLayout.stackedChrome(in:game:asking:)` reserves first.
    @State private var panelHeight = BoardLayout.stackedChromeHeight

    private var game: GameKind { CustomScene.game }

    var body: some View {
        GeometryReader { proxy in
            switch BoardLayout.shape(in: proxy.size, game: game) {
            case .sideBySide:
                HStack(spacing: 0) {
                    board(BoardLayout.geometry(in: proxy.size, game: game), bleed: 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    panel(fillingHeight: true)
                        .frame(width: BoardLayout.panelWidth)
                }
            case .stacked:
                stacked(in: proxy.size)
            }
        }
        // The same alert the other pre-start pages present, for the same two
        // failures: a creation the store would not persist, and the AI the
        // scene never asks for. 取消 leaves the draft standing and 重试 asks
        // again.
        .alert(Text(failure.title), isPresented: presentingFailure) {
            Button("control.cancel", role: .cancel) { play.dismissCreationFailure() }
            Button("control.tryAgain") { play.startScene(policy: policy) }
        } message: {
            Text(failure.message)
        }
    }

    private func stacked(in size: CGSize) -> some View {
        let chrome = BoardLayout.stackedChrome(in: size, game: game,
                                               asking: panelHeight)
        let geometry = BoardLayout.stackedGeometry(in: size, game: game,
                                                   chrome: chrome)
        return VStack(spacing: 0) {
            board(geometry, bleed: BoardLayout.surfaceBleed(in: size.width,
                                                            board: geometry))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            panel(fillingHeight: false)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) {
                    panelHeight = $0
                }
        }
    }

    // MARK: - The board

    /// The board being composed. It is this document's Xiangqi board with the
    /// draft's pieces on it and no game state at all: there is no game yet, so
    /// there is no selection, no destination, no last move and no check to draw.
    private func board(_ geometry: BoardGeometry, bleed: CGFloat) -> some View {
        BoardView(geometry: geometry,
                  placement: placement,
                  flipped: false,
                  showsNumerals: true,
                  selected: nil,
                  destinations: [],
                  captures: [],
                  lastMove: nil,
                  checkedGeneral: nil,
                  transit: nil,
                  policy: policy,
                  surfaceBleed: bleed,
                  onTap: { scene.tap($0) },
                  onTravelArrival: { },
                  onFadeArrival: { },
                  onFlipArrival: { })
    }

    /// The draft as the board reads it. A `Placement` is built from a FEN, and
    /// the FEN is the draft's own — so what the board draws is exactly the
    /// position the core is being asked about.
    private var placement: Placement {
        Placement(fen: scene.fen, game: game)
    }

    // MARK: - The panel

    @ViewBuilder
    private func panel(fillingHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(game.localizedName)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("scene-game")

            palette

            sideChoice

            // The one plain reason, where there is one to give. It takes the
            // room of a line whether or not it is filled, so the controls
            // beneath it do not move as the draft changes.
            Text(scene.verdict.reason ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("scene-reason")
                .accessibilityHidden(scene.verdict.reason == nil)

            // The one obvious next action, and therefore the one thing on this
            // page the tint rule allows.
            Button("control.startGame") { play.startScene(policy: policy) }
                .buttonStyle(.glassProminent)
                .disabled(!scene.canStart || play.creating)
                .accessibilityIdentifier("scene-start")

            if fillingHeight { Spacer(minLength: 0) }
        }
        .padding(BoardLayout.panelInset)
        .frame(maxWidth: .infinity, maxHeight: fillingHeight ? .infinity : nil,
               alignment: .topLeading)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(.container, edges: fillingHeight ? .top : .bottom)
        }
    }

    /// The palette: both sides' pieces, each with how many of it remain. The
    /// entry the player picks is what the next tap puts down, and an entry with
    /// none left is not selectable.
    ///
    /// One row per side, because the entries arrive Red's then Black's and a
    /// grid of the game's seven kinds lays them out that way by itself. The
    /// columns are flexible so the row holds at the narrowest panel this app
    /// draws as well as at a phone's full width.
    private var palette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("scene.palette")
                .font(.headline)
                .accessibilityIdentifier("scene-palette")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 22),
                                                         spacing: 4),
                                     count: PieceKind.allCases.count),
                      spacing: 4) {
                ForEach(CustomScene.entries, id: \.self) { entry($0) }
            }
        }
    }

    private func entry(_ piece: Piece) -> some View {
        let remaining = scene.remaining(piece)
        return Button { scene.pick(piece) } label: {
            VStack(spacing: 1) {
                Text(verbatim: piece.kind?.character(for: piece.side) ?? "")
                    .font(.title3)
                Text(remaining.formatted())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background {
                // Which entry is held is carried by a filled shape and a
                // heavier weight rather than by colour: on a board screen
                // saturated colour means which side a piece belongs to.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(scene.isHeld(piece) ? 0.14 : 0))
            }
        }
        .buttonStyle(.plain)
        .disabled(remaining == 0)
        .accessibilityIdentifier("palette-\(identifier(piece))")
        .accessibilityLabel(Text(verbatim: label(piece)))
        .accessibilityValue(Text(remaining.formatted()))
        .accessibilityAddTraits(scene.isHeld(piece) ? [.isSelected] : [])
    }

    /// Which side moves first, which is the side to move in the position the
    /// game will begin from.
    private var sideChoice: some View {
        Picker("scene.sideToMove", selection: sideToMove) {
            Text(verbatim: game.sideName(.red)).tag(Side.red)
            Text(verbatim: game.sideName(.black)).tag(Side.black)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("scene-side-to-move")
    }

    private var sideToMove: Binding<Side> {
        Binding(get: { scene.sideToMove }, set: { scene.sideToMove = $0 })
    }

    /// A palette entry's identifier: the side and the piece, in the vocabulary
    /// the archive and the core already use for both.
    private func identifier(_ piece: Piece) -> String {
        let side = piece.side == .red ? "red" : "black"
        let kind = piece.kind.map { String($0.rawValue) } ?? ""
        return "\(side)-\(kind)"
    }

    /// What a screen reader hears: the side and the piece, in the same order
    /// and the same words a point on the board is described in.
    private func label(_ piece: Piece) -> String {
        guard let kind = piece.kind else { return game.sideName(piece.side) }
        return game.sideName(piece.side) + " " + kind.name(for: piece.side)
    }

    // MARK: - The failure the creation can still be

    private var failure: (title: LocalizedStringResource, message: LocalizedStringResource) {
        switch play.creationFailure {
        case .notSaved: ("alert.gameNotStarted.title", "alert.gameNotStarted.message")
        case .aiUnavailable, nil: ("alert.aiUnavailable.title", "alert.aiUnavailable.message")
        }
    }

    private var presentingFailure: Binding<Bool> {
        Binding(get: { play.creationFailure != nil },
                set: { if !$0 { play.dismissCreationFailure() } })
    }
}
