// A History record, read back.
//
// docs/interaction-design.md, "History replay": the board is read-only —
// replay offers no move input, no Undo, and no way to start a game from the
// displayed position — so this screen hands `BoardView` a position, the two
// states that are facts about it, and the step it is drawing, and nothing
// else. There is no selection, no legal destination, and no held piece
// anywhere in it, which is why the check rings alone carry check here: they
// are never hidden, because nothing is ever in the player's hand.
//
// The step is drawn by the same canvas that draws a played move, from the same
// transit state, and reports its arrival on the same two wires: a replayed
// game moves like a game.
//
// The same side-by-side shape play uses, with a different panel in it: what the
// game was, where in it the board is, the list, and the transport.

import SwiftUI

struct ReplayScreen: View {
    let record: RecordSummary
    let library: HistoryLibrary

    @State private var replay: Replay?
    @State private var failure: CoreError?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        Group {
            if let replay {
                layout(replay)
            } else if let failure {
                // The description under the title is the core's own diagnostic
                // text: not copy, and not localized.
                ContentUnavailableView("failure.gameDidNotStart",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(verbatim: failure.description).monospaced())
            } else {
                ProgressView()
            }
        }
        .environment(\.motionPolicy, policy)
        // The record's own instant names the screen: the destination is already
        // named by the back control beside it, and what a reader wants there is
        // which game this is. The words are the system's date formatting rather
        // than copy, so they are verbatim.
        .navigationTitle(Text(verbatim: record.whenText))
        .onAppear {
            guard replay == nil else { return }
            switch library.replay(of: record, policy: policy) {
            case .success(let opened): replay = opened
            case .failure(let error): failure = error
            }
        }
        // Reduce Motion switched under a walk takes effect on the next step,
        // exactly as it does on the play screen.
        .onChange(of: policy) { _, updated in replay?.policy = updated }
        .onDisappear {
            // The detached session is the core's to hold open only for as long
            // as this screen wants it.
            replay?.close()
            replay = nil
        }
        // The app leaving the foreground pauses playback, as the accepted
        // behaviour asks: a game walking itself forward behind another app is
        // a game nobody is watching.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { replay?.pause() }
        }
    }

    private func layout(_ replay: Replay) -> some View {
        GeometryReader { proxy in
            let geometry = BoardLayout.geometry(in: proxy.size)
            HStack(spacing: 0) {
                BoardView(geometry: geometry,
                          placement: replay.placement,
                          flipped: replay.flipped,
                          lastMove: replay.lastMove,
                          checkedGeneral: replay.checkedGeneral,
                          transit: replay.transit,
                          transitFade: replay.transitFade,
                          policy: policy,
                          onTravelArrival: { replay.travelArrived() },
                          onFadeArrival: { replay.fadeArrived() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                panel(replay)
                    .frame(width: BoardLayout.panelWidth)
            }
        }
        .frame(minWidth: BoardLayout.minimumWidth, minHeight: BoardLayout.minimumHeight)
    }

    private func panel(_ replay: Replay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(replay)
                .padding(.horizontal, BoardLayout.panelInset)
                .padding(.vertical, 12)

            Divider()

            // Replay is the exception to the on-demand move list: its accepted
            // behaviour needs the list to indicate the shown move and to let
            // one be selected, so the list is part of the screen rather than
            // something reached from it.
            MoveList(notation: replay.notation,
                     currentMove: replay.ply > 0 ? replay.ply - 1 : nil,
                     onSelect: { replay.show(move: $0 + 1) })
                .padding(.horizontal, BoardLayout.panelInset)
                .frame(maxHeight: .infinity)

            Divider()

            ReplayTransport(isAtStart: replay.isAtStart,
                            isAtEnd: replay.isAtEnd,
                            autoplaying: replay.autoplaying,
                            goToStart: { replay.goToStart() },
                            stepBack: { replay.stepBack() },
                            toggleAutoplay: { replay.toggleAutoplay() },
                            stepForward: { replay.stepForward() },
                            goToEnd: { replay.goToEnd() },
                            flip: { withAnimation(policy.movement(Motion.flipAnimation)) {
                                replay.flipped.toggle()
                            } })
                .padding(BoardLayout.panelInset)
        }
        .frame(maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    /// What the game was, and where in it the board is.
    ///
    /// Replay has no side-to-move line: describing a finished game's position
    /// as somebody's turn would be describing a game that is not being played.
    /// What stands in that place is the record's own metadata — the same line
    /// the History row carries — and the progress through it.
    private func header(_ replay: Replay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: String(localized: "replay.progress"),
                        replay.ply, replay.moves.count))
                .font(.title3.weight(.medium).monospacedDigit())
                .accessibilityIdentifier("replay-progress")

            Text(record.metadataLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("replay-metadata")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
