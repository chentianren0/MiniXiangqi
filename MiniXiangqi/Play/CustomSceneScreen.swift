// The Custom Scene editor, on screen.
//
// docs/interaction-design.md, "Custom Scene": a pre-start page over the Play
// home, left by the back control in the toolbar, creating nothing until
// 开始对局. The board is empty and **interactive**, so it takes the interactive
// pitch floor rather than the exemption that section grants a pre-start
// preview: every point on it is a target, and the fitting is the play board's
// own for exactly that reason.
//
// **The page stands alone.** It hides the destination bar while it is up — a
// switch to another destination discards the draft, and on a phone the bar was
// standing over 开始对局 — and it carries its own name, 自定排局, in the title
// beside the back control. That name is why the panel has no headline of its
// own: the page is already named where a page is named.
//
// The page is the two layout shapes like every other board page — the board
// with the editor's controls beside it, or above them — and what stands in the
// panel is the palette, the first-mover choice, the one reason the position is
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

    /// How wide one palette row came to, measured for the same reason: the row
    /// is 228 points beside a board and a phone's whole width beneath one, and
    /// a disc is drawn at whatever pitch that leaves.
    @State private var paletteWidth = BoardLayout.panelWidth - 2 * BoardLayout.panelInset

    /// The piece being taken off the board, kept while its disc scales away.
    /// The draft has already given it back to the palette — this is only what
    /// is still drawn.
    @State private var leaving: (square: Square, piece: Piece)?

    /// How far through its answer a refused placement is, 0 at rest.
    @State private var refusalShake: Double = 0

    /// The 棋子符号 preference, declared exactly as `BoardView` declares it and
    /// for the same reason: read here rather than sampled once, so that
    /// flipping the preference repaints the palette on the frame it repaints
    /// the board. A palette that read it any other way would be a second
    /// answer to which symbols a piece carries.
    @AppStorage(PieceSymbols.key, store: Preferences.defaults) private var storedSymbols: String?

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
        // docs/interaction-design.md, "Navigation": this page hides the
        // destination bar for as long as it is up. Unlike the board screens it
        // does so at every width, because what the bar costs here is not only
        // height: a switch to another destination tears the page down, and the
        // draft goes with it. Leaving by the back control is the way out, and
        // it puts the bar back.
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        // A refused placement, answered: the disc shakes off the point it was
        // offered to and goes, and the reason stands emphatically in the panel
        // while it does. Driven from the attempt rather than from the refusal
        // itself, so a second refusal at the same point is a second answer.
        .task(id: scene.refusal?.attempt) {
            await answerRefusal()
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
    ///
    /// The tags at its two edges say whose half is whose, which a board with no
    /// turn status over it cannot say any other way. They are this page's and
    /// never the play board's — there, the side to move is what the status
    /// carries — so they are put on here rather than inside the board.
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

    /// The air between a board-half tag and the board's own edge: the same air
    /// the stacked shape keeps around the controls beneath the board, rather
    /// than a number of this page's own.
    private static let tagGap = BoardLayout.clusterAir

    private func halfTag(_ side: Side, identifier: String) -> some View {
        sideTag(side)
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
    }

    /// The draft as the board reads it. A `Placement` is built from a FEN, and
    /// the FEN is composed the same way the draft's own is — so what the board
    /// draws is exactly the position the core is being asked about, plus the one
    /// disc that has been taken off and is still leaving.
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

    /// A tap on the board. What it does to the draft is `CustomScene.tap`'s;
    /// what is decided here is how the change is shown — a disc scaling onto
    /// the board, a disc scaling off it, or neither, when the point refused the
    /// piece.
    private func tap(_ square: Square) {
        guard let piece = scene.pieces[square] else {
            withAnimation(policy.appear) { scene.tap(square) }
            return
        }
        // Taking a piece off. The disc has to stay drawn while it scales away,
        // so it is held here for exactly as long as that takes: the draft loses
        // it at once, which is what gives it back to the palette.
        withAnimation(policy.appear) {
            leaving = (square, piece)
            scene.tap(square)
        } completion: {
            leaving = nil
        }
    }

    /// The refusal's answer: the disc shakes off the point and fades, and then
    /// the refusal is spent.
    ///
    /// It is a task keyed on the attempt, so a second refusal cancels the first
    /// answer rather than overlapping it — and a cancelled answer leaves the
    /// clearing to the one that replaced it.
    private func answerRefusal() async {
        guard let refusal = scene.refusal else { return }
        // The shake is the sighted answer and the disc it moves is hidden, so
        // without this a refusal happens silently: the point stays empty, the
        // piece stays held, and nothing says why. The sentence is the one the
        // panel is showing, so both readers are told the same thing.
        AccessibilityNotification.Announcement(refusal.reason).post()
        if refusalShake != 0 {
            // A refusal arriving inside another's answer starts from the point
            // rather than from wherever the last swing had reached. The frame
            // is what lets the reset be drawn before the new answer runs.
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

    /// The air between the panel's sections. Tighter than a page of settings
    /// would take, because in the stacked shape every point of it is a point
    /// the board does not get.
    private static let sectionAir: CGFloat = 8

    @ViewBuilder
    private func panel(fillingHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: Self.sectionAir) {
            palette

            firstMover

            // The one plain reason, where there is one to give. It takes the
            // room of a line whether or not it is filled, so the controls
            // beneath it do not move as the draft changes — and it is the one
            // line a refusal speaks through too, emphatically and for as long
            // as the refused disc is on the board.
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

            // The one obvious next action, and therefore the one thing on this
            // page the tint rule allows. It stands inside the safe area, which
            // is what the hidden destination bar leaves it: the panel's
            // material runs to the bottom of the screen and its contents do
            // not.
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

    /// What the reason line is saying, and how emphatically. One value, so the
    /// line transitions once when either changes.
    private struct Reason: Equatable {
        var text: String?
        var emphatic: Bool
    }

    /// A refusal is what the line says while it stands, because it is the
    /// sentence the draft would have carried had the piece landed — said at the
    /// moment of the attempt instead.
    private var reason: Reason {
        if let refusal = scene.refusal {
            return Reason(text: refusal.reason, emphatic: true)
        }
        return Reason(text: scene.verdict.reason, emphatic: false)
    }

    // MARK: - The palette

    /// The palette: both sides' pieces, each drawn exactly as it is drawn on
    /// the board, with how many of it remain. The entry the player picks is
    /// what the next tap puts down, and an entry with none left is not
    /// selectable.
    ///
    /// One row per side, each under its side's own tag — the entries arrive
    /// Red's then Black's, and the two sets share a disc face, so without the
    /// tag the two rows are told apart only by the characters on them.
    ///
    /// **The two tags are the palette's whole heading.** A line reading
    /// *Pieces* over two rows of pieces says nothing the pieces do not, and in
    /// the stacked shape it says it with height the board is not getting.
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
                      style: style, symbols: PieceSymbols.named(storedSymbols))
                // How many are left, on the disc's own corner rather than
                // beneath it. The panel beneath a stacked board is the height
                // the board is not getting, so a line of its own per row is a
                // line the board pays for.
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
                // An entry with none left has nothing to offer, and reads that
                // way rather than only refusing the press.
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

    /// The air between two palette entries, and the quantity the pitch below is
    /// what is left after seven of them.
    private static let paletteSpacing: CGFloat = 4
    /// A palette disc is never smaller than a character can be read at, and
    /// never larger than the room a stacked page can spare it: the panel's
    /// height comes out of the board's, so the ceiling is what the board can
    /// afford rather than what the width would allow.
    private static let discPitchRange: ClosedRange<CGFloat> = 24...32

    /// The pitch a palette disc is drawn at — the same quantity the board draws
    /// a piece at, spent on the room one row of seven can afford.
    private var discPitch: CGFloat {
        let columns = CGFloat(PieceKind.allCases.count)
        let cell = (paletteWidth - (columns - 1) * Self.paletteSpacing) / columns
        return min(max(cell, Self.discPitchRange.lowerBound),
                   Self.discPitchRange.upperBound)
    }

    /// A side's own name, in that side's ink on the board's own surface: the
    /// board's two halves are tagged with it, and so is each palette row.
    ///
    /// The surface behind it is what makes the ink legible: these are the
    /// board's colours, chosen against the board, and a red on a dark page
    /// would be a red nobody chose.
    private func sideTag(_ side: Side) -> some View {
        Text(side == .red ? "scene.side.red" : "scene.side.black")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(style.symbol(side))
            .padding(.horizontal, 5)
            .background(Capsule().fill(style.boardSurface))
    }

    // MARK: - Which side moves first

    /// The side whose move the game's first ply will be, named above the choice
    /// and explained under it. Neither the name nor the sentence is decoration:
    /// a bare Red-or-Black control on an editor says nothing about what the
    /// choice does.
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
