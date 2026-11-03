// Every point on the board is a target, so it takes the play board's fitting
// and interactive pitch floor rather than a preview's. The page carries its own
// name, 自定排局, in the title, so the panel has no headline.

import SwiftUI

struct CustomSceneScreen: View {
    let play: PlayState
    let scene: CustomScene

    @Environment(\.motionPolicy) private var policy

    /// Measured: the palette is as tall as the text size makes it, and the
    /// board is fitted into what is left, never below its floor.
    @State private var panelHeight = BoardLayout.stackedChromeHeight

    /// Measured too: a palette row is the panel's width beside a board and the
    /// whole width beneath one, and a disc is drawn at whatever pitch that leaves.
    @State private var paletteWidth = BoardLayout.panelWidth - 2 * BoardLayout.panelInset

    /// Kept while its disc scales away; the draft has already given it back to
    /// the palette.
    @State private var leaving: (square: Square, piece: Piece)?

    /// How far through its answer a refused placement is, 0 at rest.
    @State private var refusalShake: Double = 0

    /// Read here, as `BoardView` reads it, so flipping the preference repaints
    /// the palette on the same frame as the board.
    @AppStorage(PieceSymbols.key) private var symbols: PieceSymbols = .hanzi

    private var game: GameKind { CustomScene.game }

    private var style: BoardStyle { .traditional }

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
        // Hidden at every width, unlike the board screens: switching destination
        // tears the page down, and the draft with it.
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        // Keyed on the attempt, so a second refusal at the same point is a
        // second answer.
        .task(id: scene.refusal?.attempt) {
            await answerRefusal()
        }
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

    /// No game exists yet, so there is no selection, destination, last move or
    /// check. The tags at its edges say whose half is whose, which only this
    /// page needs: on the play board the turn status says it.
    private func board(_ geometry: BoardGeometry, bleed: CGFloat) -> some View {
        BoardView(geometry: geometry,
                  placement: placement,
                  flipped: false,
                  selected: nil,
                  destinations: [],
                  captures: [],
                  lastMove: nil,
                  checkedGeneral: nil,
                  settled: Set(scene.pieces.keys),
                  leaving: leaving?.square,
                  refused: refused,
                  transit: nil,
                  policy: policy,
                  surfaceBleed: bleed,
                  onTap: { tap($0) },
                  onTravelArrival: { },
                  onFadeArrival: { },
                  onFlipArrival: { })
        .overlay(alignment: .topLeading) {
            halfTag(.black, identifier: "scene-half-black")
                .alignmentGuide(.top) { $0[.bottom] + Self.tagGap }
        }
        .overlay(alignment: .bottomLeading) {
            halfTag(.red, identifier: "scene-half-red")
                .alignmentGuide(.bottom) { _ in -Self.tagGap }
        }
    }

    private static let tagGap = BoardLayout.clusterAir

    private func halfTag(_ side: Side, identifier: String) -> some View {
        sideTag(side)
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
    }

    /// Built with the draft's own FEN composition, so the board draws exactly
    /// the position the core is asked about, plus a disc still leaving.
    private var placement: Placement {
        Placement(fen: CustomScene.fen(of: drawn, sideToMove: scene.sideToMove,
                                       game: game),
                  game: game)
    }

    private var drawn: [Square: Piece] {
        guard let leaving else { return scene.pieces }
        var pieces = scene.pieces
        pieces[leaving.square] = leaving.piece
        return pieces
    }

    private var refused: RefusedPlacement? {
        scene.refusal.map {
            RefusedPlacement(square: $0.square, piece: $0.piece, shake: refusalShake)
        }
    }

    // MARK: - Putting a piece down and taking it off

    /// The draft change is `CustomScene.tap`'s; this decides how it is shown.
    private func tap(_ square: Square) {
        guard let piece = scene.pieces[square] else {
            withAnimation(policy.appear) { scene.tap(square) }
            return
        }
        // The draft loses the piece at once, giving it back to the palette; the
        // disc stays drawn until it has scaled away.
        withAnimation(policy.appear) {
            leaving = (square, piece)
            scene.tap(square)
        } completion: {
            leaving = nil
        }
    }

    /// The disc shakes off the point and fades, then the refusal is spent.
    /// Keyed on the attempt, so a second refusal cancels the first answer and
    /// does the clearing itself.
    private func answerRefusal() async {
        guard let refusal = scene.refusal else { return }
            // The shake is only visible; without this announcement a refusal
            // happens silently.
        AccessibilityNotification.Announcement(refusal.reason).post()
        if refusalShake != 0 {
            // Restart from the point, not from the last swing; the brief sleep
            // lets the reset be drawn first.
            restShake()
            try? await Task.sleep(for: .milliseconds(1))
        }
        withAnimation(.linear(duration: Motion.refusal)) { refusalShake = 1 }
        try? await Task.sleep(for: .seconds(Motion.refusal))
        guard !Task.isCancelled else { return }
        restShake()
        scene.clearRefusal()
    }

    /// The shake put back to nothing without animating it: the disc is already
    /// gone, and animating the number back would draw it returning.
    private func restShake() {
        var immediate = Transaction()
        immediate.disablesAnimations = true
        withTransaction(immediate) { refusalShake = 0 }
    }

    // MARK: - The panel

    /// Tight because in the stacked shape every point here is taken from the
    /// board.
    private static let sectionAir: CGFloat = 8

    @ViewBuilder
    private func panel(fillingHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: Self.sectionAir) {
            palette

            firstMover

            // Reserves a line even when empty, so the controls below do not move
            // as the draft changes. A refusal speaks through it too, emphatically.
            Text(reason.text ?? " ")
                .font(.callout)
                .fontWeight(reason.emphatic ? .semibold : .regular)
                .foregroundStyle(reason.emphatic ? AnyShapeStyle(.primary)
                                                 : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(policy.fade(Motion.stateFadeAnimation), value: reason)
                .accessibilityIdentifier("scene-reason")
                .accessibilityHidden(reason.text == nil)

            // The page's one tinted control, as its one obvious next action. The
            // panel's material runs to the screen's bottom; its contents stay
            // inside the safe area.
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

    /// One value, so the line transitions once when either changes.
    private struct Reason: Equatable {
        var text: String?
        var emphatic: Bool
    }

    private var reason: Reason {
        if let refusal = scene.refusal {
            return Reason(text: refusal.reason, emphatic: true)
        }
        return Reason(text: scene.verdict.reason, emphatic: false)
    }

    // MARK: - The palette

    /// One row per side under its side's tag: the two sets share a disc face,
    /// so without it the rows differ only by their characters. The tags are the
    /// whole heading; a title over them would cost the stacked board height.
    private var palette: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([Side.red, .black], id: \.self) { side in
                sideTag(side)
                    .accessibilityIdentifier(side == .red ? "palette-side-red"
                                                          : "palette-side-black")
                row(side)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { paletteWidth = $0 }
    }

    private func row(_ side: Side) -> some View {
        HStack(spacing: Self.paletteSpacing) {
            ForEach(CustomScene.entries.filter { $0.side == side }, id: \.self) {
                entry($0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entry(_ piece: Piece) -> some View {
        let remaining = scene.remaining(piece)
        return Button { scene.pick(piece) } label: {
            PieceDisc(piece: piece, pitch: discPitch, board: game.board,
                      style: style, symbols: symbols)
                // On the disc's corner rather than beneath it: a line per row
                // would come out of the stacked board's height.
                .overlay(alignment: .bottomTrailing) {
                    Text(remaining.formatted())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(.regularMaterial))
                        .alignmentGuide(.bottom) { $0[.bottom] - 2 }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .opacity(remaining == 0 ? 0.35 : 1)
                .background {
                    // Which entry is held is carried by a filled shape and a
                    // heavier weight rather than by colour: on a board screen
                    // saturated colour means which side a piece belongs to.
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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

    private static let paletteSpacing: CGFloat = 4
    /// At least readable, and at most what a stacked page can spare, since the
    /// panel's height comes out of the board's.
    private static let discPitchRange: ClosedRange<CGFloat> = 24...32

    private var discPitch: CGFloat {
        let columns = CGFloat(PieceKind.allCases.count)
        let cell = (paletteWidth - (columns - 1) * Self.paletteSpacing) / columns
        return min(max(cell, Self.discPitchRange.lowerBound),
                   Self.discPitchRange.upperBound)
    }

    /// On the board's own surface because the side inks were chosen against
    /// it; a red on a dark page would be a red nobody chose.
    private func sideTag(_ side: Side) -> some View {
        Text(side == .red ? "scene.side.red" : "scene.side.black")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(style.symbol(side))
            .padding(.horizontal, 5)
            .background(Capsule().fill(style.boardSurface))
    }

    // MARK: - Which side moves first

    /// Named above and explained below: a bare Red-or-Black control says
    /// nothing about what the choice does.
    private var firstMover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("scene.firstMover")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("scene-first-mover")

            Picker("scene.firstMover", selection: sideToMove) {
                Text(verbatim: game.sideName(.red)).tag(Side.red)
                Text(verbatim: game.sideName(.black)).tag(Side.black)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("scene-side-to-move")

            Text("scene.firstMover.caption")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scene-first-mover-caption")
        }
    }

    private var sideToMove: Binding<Side> {
        Binding(get: { scene.sideToMove }, set: { scene.sideToMove = $0 })
    }

    private func identifier(_ piece: Piece) -> String {
        let side = piece.side == .red ? "red" : "black"
        let kind = piece.kind.map { String($0.rawValue) } ?? ""
        return "\(side)-\(kind)"
    }

    /// The same order and words a point on the board is described in.
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
