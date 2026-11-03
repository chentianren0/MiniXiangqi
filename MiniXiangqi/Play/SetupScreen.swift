// The pre-start page is not an active game: the board is a noninteractive
// preview with no turn status, and the human-versus-AI settings are an
// in-memory draft, fresh from the Settings defaults on every entry. 随机 stays
// unresolved and previews Red at the bottom; only a successful creation that
// resolves it to AI 先手 flips the board.

import SwiftUI

struct SetupScreen: View {
    let play: PlayState
    var selection: PlaySelection

    private var mode: PlayMode { selection.mode }

    @Environment(\.motionPolicy) private var policy

    /// Measured: in the stacked shape the controls take what they need first,
    /// since the preview has no floor to protect.
    @State private var controlsHeight = BoardLayout.stackedChromeHeight

    var body: some View {
        GeometryReader { proxy in
            switch BoardLayout.shape(in: proxy.size, game: selection.game) {
            case .sideBySide:
                HStack(spacing: 0) {
                    preview(BoardLayout.previewGeometry(in: proxy.size,
                                                        game: selection.game))
                    panel(fillingHeight: true)
                        .frame(width: BoardLayout.panelWidth)
                }
            case .stacked:
                VStack(spacing: 0) {
                    preview(BoardLayout.stackedPreviewGeometry(in: proxy.size,
                                                               game: selection.game,
                                                               chrome: controlsHeight))
                    panel(fillingHeight: false)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) {
                            controlsHeight = $0
                        }
                }
            }
        }
    }

    /// The position made when the page was entered: the frozen start, or for a
    /// dealt game a deal of its own.
    private func preview(_ geometry: BoardGeometry) -> some View {
        BoardView(geometry: geometry,
                  placement: Placement(fen: play.preview, game: selection.game),
                  flipped: previewsFlipped,
                  selected: nil,
                  destinations: [],
                  captures: [],
                  lastMove: nil,
                  checkedGeneral: nil,
                  transit: nil,
                  policy: policy,
                  onTap: { _ in },
                  onTravelArrival: { },
                  onFadeArrival: { },
                  onFlipArrival: { })
            // Hidden so that a screen reader does not offer points that answer
            // to nothing.
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 随机 previews Red until it is resolved. A placement board has no
    /// orientation, so it previews as it will be played.
    private var previewsFlipped: Bool {
        mode == .humanVersusAI && !selection.game.isPlacement
            && play.draft.previewsHumanAsBlack
    }

    /// Beneath the preview the controls take only what they need, so the
    /// preview keeps the rest, and their material runs to the bottom edge.
    @ViewBuilder
    private func panel(fillingHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(selection.game.localizedName)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("setup-game")

            switch mode {
            case .humanVersusAI: humanVersusAISetup
            // Networked play reaches its opponent through the propose sheet, so
            // it has no pre-start state of its own here.
            case .freePlay, .nearby, .online: freePlaySetup
            }
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
        // One alert for two failures, which are exclusive: a creation fails at
        // one gate or the other. 取消 keeps the draft on the page; 重试 repeats
        // the whole attempt, memory probe and all.
        .alert(Text(failure.title), isPresented: presentingFailure) {
            Button("control.cancel", role: .cancel) { play.dismissCreationFailure() }
            Button("control.tryAgain") { start() }
        } message: {
            Text(failure.message)
        }
    }

    /// The not-saved message cannot borrow 无法保存对局's promise that the
    /// current game is unchanged: there is no current game.
    private var failure: (title: LocalizedStringResource, message: LocalizedStringResource) {
        switch play.creationFailure {
        case .notSaved: ("alert.gameNotStarted.title", "alert.gameNotStarted.message")
        // Also what nil reads as: the alert is not up then, so its words are
        // never seen.
        case .aiUnavailable, nil: ("alert.aiUnavailable.title", "alert.aiUnavailable.message")
        }
    }

    private var presentingFailure: Binding<Bool> {
        Binding(get: { play.creationFailure != nil },
                set: { if !$0 { play.dismissCreationFailure() } })
    }

    // MARK: - The two panels

    private var humanVersusAISetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("setup.thisGame")
                .font(.headline)
                .accessibilityIdentifier("setup-header")

            // The tags are the vocabulary itself, so the control, the frozen
            // configuration and the archive all say the same three words.
            Picker("setup.firstMover", selection: firstMover) {
                Text("setup.iMoveFirst").tag(FirstMoverChoice.humanFirst)
                Text("setup.aiMovesFirst").tag(FirstMoverChoice.aiFirst)
                Text("setup.random").tag(FirstMoverChoice.random)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("setup-first-mover")

            levelPicker

            startControl
        }
    }

    /// A menu picker outside a form shows its label on macOS but swallows it on
    /// iOS, so iOS is given the label explicitly: 标准 alone does not say what
    /// it is the standard of.
    @ViewBuilder
    private var levelPicker: some View {
        let picker = Picker("setup.aiLevel", selection: level) {
            Text("setup.level.fast").tag(AiLevel.fast)
            Text("setup.level.standard").tag(AiLevel.standard)
            Text("setup.level.deep").tag(AiLevel.deep)
        }
        .accessibilityIdentifier("setup-ai-level")

        #if os(macOS)
        picker
        #else
        LabeledContent {
            picker.labelsHidden()
        } label: {
            Text("setup.aiLevel")
        }
        #endif
    }

    /// Names the game's own sides: Red and Black on a xiangqi board, Black and
    /// White on a placement one.
    private var freePlaySetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(selection.game.isPlacement
                 ? "setup.freePlayExplanation.placement"
                 : "setup.freePlayExplanation")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("setup-explanation")
            startControl
        }
    }

    /// The page's one tinted control, as its one obvious next action. Disabled
    /// while creating; a failure re-enables it with the draft untouched.
    private var startControl: some View {
        Button("control.startGame") { start() }
            .buttonStyle(.glassProminent)
            .disabled(play.creating)
            .accessibilityIdentifier("setup-start")
    }

    private func start() {
        play.startGame(policy: policy)
    }

    // MARK: - Bindings

    private var firstMover: Binding<FirstMoverChoice> {
        Binding(get: { play.draft.firstMover },
                set: { play.draft.firstMover = $0 })
    }

    private var level: Binding<AiLevel> {
        Binding(get: { play.draft.level }, set: { play.draft.level = $0 })
    }
}
