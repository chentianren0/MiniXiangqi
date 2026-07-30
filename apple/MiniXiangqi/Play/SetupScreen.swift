// Before there is a game: the two mode entries, and each mode's pre-start page.
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
// 随机 remains unresolved here and previews Red at the bottom. Only a successful
// creation flips the board, and only when Random resolved to AI 先手 — which is
// why the preview reads the draft's own preview rule rather than a resolved
// side that does not exist yet.

import SwiftUI

struct SetupScreen: View {
    let play: PlayState
    /// Which page this is: the mode entries, or one mode's setup.
    var mode: PlayMode?

    @Environment(\.motionPolicy) private var policy

    var body: some View {
        GeometryReader { proxy in
            let geometry = BoardLayout.previewGeometry(in: proxy.size)
            HStack(spacing: 0) {
                BoardView(geometry: geometry,
                          placement: Placement(fen: Core.startFEN),
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
                    // A preview has nothing to interact with, and saying so is
                    // what keeps a screen reader from offering forty-nine
                    // points that answer to nothing.
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                panel
                    .frame(width: BoardLayout.panelWidth)
            }
        }
    }

    /// The human's side is at the bottom, and 随机 previews Red until it is
    /// resolved. Red at the bottom is the unflipped board.
    private var previewsFlipped: Bool {
        mode == .humanVersusAI && play.draft.previewsHumanAsBlack
    }

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch mode {
            case .humanVersusAI: humanVersusAISetup
            case .freePlay: freePlaySetup
            case nil: modeEntries
            }
            Spacer(minLength: 0)
        }
        .padding(BoardLayout.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(.container, edges: .top)
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

    // MARK: - The three panels

    private var modeEntries: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("mode.humanVersusAI") { play.choose(.humanVersusAI) }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("mode-human-versus-ai")
            Button("mode.freePlay") { play.choose(.freePlay) }
                .buttonStyle(.glass)
                .accessibilityIdentifier("mode-free-play")
        }
    }

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

            Picker("setup.aiLevel", selection: level) {
                Text("setup.level.fast").tag(AiLevel.fast)
                Text("setup.level.standard").tag(AiLevel.standard)
                Text("setup.level.deep").tag(AiLevel.deep)
            }
            .accessibilityIdentifier("setup-ai-level")

            startControl
        }
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
