// The play screen.
//
// docs/interaction-design.md, "Layout shapes": ordinary Mac windows use the
// side-by-side shape — the board on one side, with a panel beside it carrying
// the turn status, the move list, and controls that do not need to sit under
// the thumb. The stacked shape, for narrow windows and iPhone, comes with iOS.
//
// The board is square and sized to the largest square fitting both the
// available width and the height left after the chrome, never below the
// 44-point floor and never above the 720-point ceiling; surplus space goes to
// the layout rather than to the board. When space is short the chrome tightens
// first, and the window stops resizing where either would go below its floor.

import SwiftUI

struct PlayScreen: View {
    @State private var game: Game?
    @State private var startFailure: CoreError?

    let core: Core

    private static let panelWidth: CGFloat = 260
    private static let boardPadding: CGFloat = 24

    var body: some View {
        Group {
            if let game {
                layout(game)
            } else if let startFailure {
                ContentUnavailableView("The game did not start",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(startFailure.description).monospaced())
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        .task {
            guard game == nil else { return }
            do { game = try Game(core: core) }
            catch let error as CoreError { startFailure = error }
            catch { }
        }
    }

    private func layout(_ game: Game) -> some View {
        GeometryReader { proxy in
            let geometry = boardGeometry(in: proxy.size)
            HStack(spacing: 0) {
                ZStack {
                    BoardView(geometry: geometry,
                              placement: game.placement,
                              flipped: game.flipped,
                              selected: game.selected,
                              destinations: game.destinations,
                              captures: game.captures,
                              lastMove: game.lastMove,
                              checkedGeneral: game.checkedGeneral,
                              onTap: { game.tap($0) })
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                panel(game)
                    .frame(width: Self.panelWidth)
            }
        }
    }

    private func panel(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TurnStatus(state: game.evaluation.state,
                       reason: game.evaluation.reason,
                       sideToMove: game.evaluation.sideToMove,
                       inCheck: game.evaluation.inCheck)
                .padding(20)

            Divider()

            MoveList(notation: game.notation)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)

            Divider()

            // The play control cluster: the one custom glass surface on screen
            // during ordinary play. It carries no tint, because saturated
            // colour on the play screen means which side a piece belongs to.
            HStack {
                Button {
                    withAnimation(.snappy) { game.flipped.toggle() }
                } label: {
                    Label("翻转棋盘", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.glass)
                .accessibilityLabel("翻转棋盘")

                Spacer()
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    /// The largest board that fits beside the panel, bounded by the accepted
    /// floor and ceiling.
    private func boardGeometry(in size: CGSize) -> BoardGeometry {
        let available = CGSize(width: size.width - Self.panelWidth - 2 * Self.boardPadding,
                               height: size.height - 2 * Self.boardPadding)
        let fitted = BoardGeometry.fitting(available)
            ?? BoardGeometry(pitch: BoardGeometry.minimumPitch)
        return BoardGeometry(pitch: min(fitted.pitch, BoardGeometry.maximumPitch))
    }

    /// Both the board and the chrome have floors, so the window has one too.
    static var minimumWidth: CGFloat {
        BoardGeometry(pitch: BoardGeometry.minimumPitch).coreSide
            + panelWidth + 2 * boardPadding
    }

    static var minimumHeight: CGFloat {
        BoardGeometry(pitch: BoardGeometry.minimumPitch).blockSize.height
            + 2 * boardPadding
    }
}
