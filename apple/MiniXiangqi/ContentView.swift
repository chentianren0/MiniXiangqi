import SwiftUI

struct ContentView: View {
    var body: some View {
        switch Core.shared {
        case .success(let core):
            PlayScreen(core: core)
        case .failure(let error):
            // A core that will not start is a packaging failure, and saying so
            // plainly beats an empty board that silently does nothing.
            ContentUnavailableView("The core did not start", systemImage: "exclamationmark.triangle",
                                   description: Text(error.description).monospaced())
        }
    }
}

private struct PlayScreen: View {
    @State private var game: Game?
    @State private var startFailure: CoreError?
    let core: Core

    var body: some View {
        Group {
            if let game {
                board(game)
            } else if let startFailure {
                ContentUnavailableView("The game did not start", systemImage: "exclamationmark.triangle",
                                       description: Text(startFailure.description).monospaced())
            } else {
                ProgressView()
            }
        }
        .task {
            guard game == nil else { return }
            do { game = try Game(core: core) }
            catch let error as CoreError { startFailure = error }
            catch { }
        }
    }

    private func board(_ game: Game) -> some View {
        GeometryReader { proxy in
            // The board is square and sized to the largest square fitting both
            // the available width and the height left after the chrome, with
            // the accepted floor of 44 points a point.
            let available = CGSize(width: proxy.size.width - 32,
                                   height: proxy.size.height - 72)
            let geometry = BoardGeometry.fitting(available)
                ?? BoardGeometry(pitch: BoardGeometry.minimumPitch)

            VStack(spacing: 16) {
                TurnStatus(game: game)
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
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minWidth: 7 * BoardGeometry.minimumPitch + 32,
               minHeight: BoardGeometry(pitch: BoardGeometry.minimumPitch).blockSize.height + 72)
    }
}

/// Provisional. The accepted turn status is a designed element with its own
/// tokens; this is the plain text that keeps the state visible until it is
/// built.
private struct TurnStatus: View {
    let game: Game

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
            if game.evaluation.inCheck && !game.evaluation.isOver {
                Text("将军").bold()
            }
        }
        .font(.title3)
        .monospacedDigit()
    }

    private var text: String {
        switch game.evaluation.state {
        case .redWins: "红胜 — \(reason)"
        case .blackWins: "黑胜 — \(reason)"
        case .draw: "和局 — \(reason)"
        case .claimableDraw: "可提和 — \(reason)"
        case .ongoing: game.evaluation.sideToMove == .red ? "红方走" : "黑方走"
        }
    }

    private var reason: String {
        switch game.evaluation.reason {
        case .checkmate: "将死"
        case .stalemate: "困毙"
        case .threefoldRepetition: "三次重复"
        case .perpetualCheck: "长将"
        case .perpetualChase: "长捉"
        case .mutualPerpetualCheck: "双方长将"
        case .mutualPerpetualChase: "双方长捉"
        case .resignation: "认输"
        case .endedEarly: "提前结束"
        case .none: "—"
        }
    }
}

#Preview("Board at the floor") {
    BoardView(geometry: BoardGeometry(pitch: BoardGeometry.minimumPitch),
              placement: Placement(fen: Core.startFEN),
              selected: Square("e1"),
              destinations: [Square("e2")!, Square("e4")!, Square("c4")!],
              captures: [Square("c4")!],
              lastMove: Move(text: "d7d6"),
              checkedGeneral: Square("d1"))
    .padding()
}
