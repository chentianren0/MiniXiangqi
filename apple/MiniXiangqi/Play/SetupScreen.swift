// Before there is a game: one mode's pre-start page.
//
// docs/interaction-design.md, "Starting and configuring a game": the pre-start
// state is not an active game. It shows the initial board as a noninteractive
// preview and no side-to-move status; human-versus-AI adds a **本局设置** group
// of 我先手 / AI 先手 / 随机 plus **AI 等级**, initialized afresh from the
// Settings defaults on every entry and held only as an in-memory draft; Free
// Play adds no group at all, only the sentence that says what Free Play is.
// **开始对局** is what creates the game, and while creation is in progress it
// cannot be invoked again.
//
// The preview board stays here, where it always was. What left is the mode
// chooser that used to stand in front of it: choosing what to play is the Play
// home's, and this page is reached having already chosen.
//
// 随机 remains unresolved here and previews Red at the bottom. Only a successful
// creation flips the board, and only when Random resolved to AI 先手 — which is
// why the preview reads the draft's own preview rule rather than a resolved
// side that does not exist yet.

import SwiftUI

struct SetupScreen: View {
    let play: PlayState
    /// Which game and mode this pre-start page will create.
    var selection: PlaySelection

    private var mode: PlayMode { selection.mode }

    @Environment(\.motionPolicy) private var policy

    /// What the setup controls came to under the preview, in the stacked shape.
    /// They take the space they need first — the preview has no floor to
    /// protect — so the number is measured rather than allowed for.
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
                // The preview above, the controls below, in the same order the
                // play screen puts the board and its cluster. The preview
                // yields: it has no touch targets to protect, so the controls
                // take what they need and it fits into what is left.
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

    private func preview(_ geometry: BoardGeometry) -> some View {
        BoardView(geometry: geometry,
                  placement: Placement(fen: Core.startFEN(for: selection.game),
                                       game: selection.game),
                  flipped: previewsFlipped,
                  showsNumerals: true,
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
            // A preview has nothing to interact with, and saying so is what
            // keeps a screen reader from offering forty-nine or ninety points
            // that answer to nothing.
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The human's side is at the bottom, and 随机 previews Red until it is
    /// resolved. Red at the bottom is the unflipped board.
    private var previewsFlipped: Bool {
        mode == .humanVersusAI && play.draft.previewsHumanAsBlack
    }

    /// The setup controls, beside the preview or beneath it.
    ///
    /// Beside it they fill the height and read from the top, as a panel does.
    /// Beneath it they take exactly what they need and no more, because every
    /// point they do not take is a point the preview above them keeps — and the
    /// material then runs to the bottom edge rather than to the top, since that
    /// is the edge this shape puts them on.
    @ViewBuilder
    private func panel(fillingHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(selection.game.localizedName)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("setup-game")

            switch mode {
            case .humanVersusAI: humanVersusAISetup
            case .freePlay: freePlaySetup
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
        // One alert, two failures. They are exclusive by construction — a
        // creation fails at one gate or the other — and one presentation is
        // what keeps them exclusive on screen too. 取消 dismisses without
        // leaving the page, so the draft is still there and 开始对局 is on
        // offer again; 重试 repeats the whole attempt, probe and all.
        .alert(Text(failure.title), isPresented: presentingFailure) {
            Button("control.cancel", role: .cancel) { play.dismissCreationFailure() }
            Button("control.tryAgain") { start() }
        } message: {
            Text(failure.message)
        }
    }

    /// What the last failed attempt says. The insufficient-memory pair is the
    /// accepted notice; the other is the creation that could not be persisted,
    /// which cannot borrow 无法保存对局's promise that the current game is
    /// unchanged, there being no current game to keep.
    private var failure: (title: LocalizedStringResource, message: LocalizedStringResource) {
        switch play.creationFailure {
        case .notSaved: ("alert.gameNotStarted.title", "alert.gameNotStarted.message")
        // The AI case is also what an absent failure reads as: the alert is not
        // up, so its words are never seen, and a nil-safe default beats an
        // optional that every branch would have to unwrap.
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

    /// **AI 等级**, and the one control on this page whose label the two
    /// platforms do not present the same way.
    ///
    /// A menu picker outside a form shows its label on macOS and swallows it on
    /// iOS, where the row is expected to be a form row that carries the label
    /// itself. This page is a panel rather than a form on either platform, so
    /// iOS is given the pairing explicitly: 标准 alone says nothing about what
    /// it is the standard *of*, and a level nobody can name is a level nobody
    /// can choose. macOS keeps the picker's own label, unchanged.
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

    private var freePlaySetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("setup.freePlayExplanation")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("setup-explanation")
            startControl
        }
    }

    /// The one obvious next action, and therefore the one thing on this page
    /// the tint rule allows. It cannot be invoked again while creation is in
    /// progress, and a failure re-enables it with the draft untouched.
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
