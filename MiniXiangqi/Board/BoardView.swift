// The board is a grid of points, never a checkerboard of squares.

import SwiftUI

/// `shake` runs from 0 as the piece is offered to 1 once it has gone. This
/// carries the core's answer, not the rule.
struct RefusedPlacement: Equatable {
    var square: Square
    var piece: Piece
    var shake: Double
}

struct BoardView: View {
    var geometry: BoardGeometry
    var placement: Placement
    var flipped: Bool = false

    /// The point the player is holding: the piece taken up in a movement game,
    /// and the marked point awaiting confirmation in a placement one.
    var selected: Square?
    var destinations: Set<Square> = []
    var captures: Set<Square> = []
    var forbidden: Set<Square> = []
    /// One of the held piece's destinations, drawn as one; it gains the
    /// strengthening below and a screen-reader token.
    var suggested: Square?
    var lastMove: Move?
    var checkedGeneral: Square?

    /// Only a board being composed hands these. A point nobody names scales in
    /// from nothing, and the leaving point stays named until its disc has gone,
    /// so it never snaps back to full size. A played board draws every disc at
    /// full size.
    var settled: Set<Square> = []
    var leaving: Square?

    /// Only the board being composed carries one; a played board refuses a
    /// move, which the markers already answer.
    var refused: RefusedPlacement?

    /// A static board, a snapshot or a preview, leaves them at rest.
    var transit: Transit?
    /// The second disc of a paired transition: two plies rewinding together.
    var companion: Transit?
    var transitFade: Double = 0
    /// A Jieqi reveal on the travelling disc.
    var transitReveal: Double = 0
    /// The end of a Jieqi game, which discloses every concealed identity to
    /// both players.
    var disclosure: Double = 0
    var checkEmphasis: Double = 0
    var markerEmphasis: Double = 0
    /// It carries the muting and the halo too: all three are one suggestion,
    /// so they ride one phase.
    var hintEmphasis: Double = 0
    var policy = MotionPolicy(reduceMotion: false)

    /// The dashes turn from where they rest rather than from a shared clock, so
    /// a suggestion on a ring already shown sets it turning without a jolt.
    @State private var driftStart: Date?

    var style: BoardStyle = .traditional

    /// Non-zero only on a stacked board screen; see
    /// `BoardLayout.surfaceBleed(in:board:)`.
    var surfaceBleed: CGFloat = 0

    var onTap: (Square) -> Void = { _ in }

    /// Read here because every board, in play, replay or a snapshot, comes
    /// through this view.
    @AppStorage(PieceSymbols.key) private var symbols: PieceSymbols = .hanzi

    /// The strips follow it: they map the move list to the board, so they must
    /// be in the list's script.
    @AppStorage(NotationStyle.key)
    private var notationStyle: NotationStyle = .resolvedForInterfaceLanguage

    /// Each fires on the frame its animation reaches its target; see
    /// ArrivalReporter for why a transaction completion cannot gate. The flip's
    /// says the points are back under their discs.
    var onTravelArrival: () -> Void = { }
    var onFadeArrival: () -> Void = { }
    var onFlipArrival: () -> Void = { }

    private var p: CGFloat { geometry.pitch }

    var body: some View {
        block
        .frame(width: geometry.blockSize.width, height: geometry.blockSize.height)
        // The core and the strips carry their own fill, so this shows only
        // where the surface bleeds past the block.
        .background {
            style.boardSurface.padding(.horizontal, -surfaceBleed)
        }
    }

    @ViewBuilder
    private var block: some View {
        switch geometry.coordinates {
        case .fileNumerals:
            VStack(spacing: 0) {
                numeralStrip(atTop: true)
                core
                numeralStrip(atTop: false)
            }
        case .goStyle:
            // Top-aligned, so the numbers up the side stand beside the core's
            // own rows rather than being centred against the block the letter
            // strip beneath makes taller.
            HStack(alignment: .top, spacing: 0) {
                rankNumberStrip
                VStack(spacing: 0) {
                    core
                    fileLetterStrip
                }
            }
        }
    }

    // MARK: - The board core

    private var core: some View {
        // The drift is the one motion that runs continuously rather than between
        // states, so the clock drives it, ticking only while it runs.
        TimelineView(.animation(paused: !driftsDashes)) { context in
            canvas(dashDrift: drift(at: context.date))
        }
        .modifier(ArrivalReporter(progress: transit == nil ? 0 : 1,
                                  arrived: onTravelArrival))
        .modifier(ArrivalReporter(progress: transitFade, arrived: onFadeArrival))
        .modifier(ArrivalReporter(progress: flipped ? 1 : 0, arrived: onFlipArrival))
        .frame(width: geometry.coreSize.width, height: geometry.coreSize.height)
        .background(style.boardSurface)
        .overlay(points)
        .overlay(refusal)
        .onChange(of: driftsDashes, initial: true) { _, drifting in
            driftStart = drifting ? .now : nil
        }
    }

    /// Over the core rather than in the canvas: nothing landed, and it moves,
    /// which the canvas's phases are not for. It takes no input, so a second
    /// tap on the point is a second attempt. Under Reduce Motion it fades
    /// without shaking.
    @ViewBuilder
    private var refusal: some View {
        if let refused {
            PieceDisc(piece: refused.piece, pitch: p, board: geometry.board,
                      style: style, symbols: symbols)
                .offset(x: policy.reduceMotion
                        ? 0 : Motion.refusalOffset(refused.shake) * p)
                .opacity(1 - refused.shake)
                .position(geometry.center(of: refused.square, flipped: flipped))
                .frame(width: geometry.coreSize.width, height: geometry.coreSize.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func canvas(dashDrift: Double) -> some View {
        BoardCanvas(geometry: geometry,
                    placement: placement,
                    style: style,
                    symbols: symbols,
                    policy: policy,
                    destinations: destinations,
                    captures: captures,
                    forbidden: forbidden,
                    dashDrift: dashDrift,
                    lastMove: lastMove,
                    checkedGeneral: checkedGeneral,
                    transit: transit,
                    companion: companion,
                    phases: BoardPhases(travel: transit == nil ? 0 : 1,
                                        fade: transitFade,
                                        reveal: transitReveal,
                                        disclosure: disclosure,
                                        flip: flipped ? 1 : 0,
                                        check: checkEmphasis,
                                        marker: markerEmphasis,
                                        hint: SquarePhases(suggested, at: hintEmphasis),
                                        lifts: SquarePhases(raised: selected),
                                        settled: settlePhases))
    }

    /// Empty on a played board, which leaves its discs at full size.
    private var settlePhases: SquarePhases {
        guard !settled.isEmpty || leaving != nil else { return SquarePhases() }
        var values = Dictionary(uniqueKeysWithValues: settled.map { ($0, 1.0) })
        if let leaving { values[leaving] = 0 }
        return SquarePhases(values)
    }

    /// A rotation is motion, so under Reduce Motion the dashes hold still.
    var driftsDashes: Bool {
        guard let suggested, !policy.reduceMotion else { return false }
        return captures.contains(suggested)
    }

    private func drift(at date: Date) -> Double {
        guard driftsDashes, let driftStart else { return 0 }
        return Motion.dashDrift(elapsed: date.timeIntervalSince(driftStart))
    }

    /// The canvas has no points a pointer can hit or a screen reader can name;
    /// this grid supplies both. Each element is placed by the canvas's own
    /// centre function rather than by a stack, whose stray inset would shift
    /// every point invisibly. During a flip the elements jump while the discs
    /// travel the arc, so PlayMotion discards board input for the flip.
    private var points: some View {
        ZStack {
            ForEach(0..<geometry.board.squareCount, id: \.self) { index in
                let square = Square(file: index % geometry.board.fileCount,
                                    rank: index / geometry.board.fileCount)
                let centre = geometry.center(of: square, flipped: flipped)
                Color.clear
                    .frame(width: p, height: p)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(square) }
                    .accessibilityElement()
                    .accessibilityIdentifier("point-\(square.name)")
                    .accessibilityLabel(describe(square))
                    .accessibilityAddTraits(.isButton)
                    .position(x: centre.x, y: centre.y)
            }
        }
        .frame(width: geometry.coreSize.width, height: geometry.coreSize.height)
    }

    /// What a screen reader says about a point: its name, what stands there,
    /// and any state on it.
    private func describe(_ square: Square) -> String {
        var parts = [square.name]
        if let piece = placement[square] {
            parts.append(placement.game.sideName(piece.side))
            // A face-down piece is announced by its side and as face down only:
            // not by its identity, nor by its role. Once the game's end has
            // disclosed it, it is named.
            if piece.isFaceDown, disclosure > 0,
               let identity = placement.concealedIdentity(at: square) {
                parts.append(identity.name(for: piece.side))
            } else if piece.isFaceDown {
                parts.append(String(localized: "board.a11y.faceDown"))
            } else if let kind = piece.kind {
                // A stone's side has already said what it is.
                parts.append(kind.name(for: piece.side))
            }
        } else {
            parts.append(String(localized: "board.a11y.empty"))
        }
        if square == selected {
            // Two names for two states: a piece taken up, and a point marked
            // for a stone not yet down.
            parts.append(geometry.board.play == .placement
                         ? String(localized: "board.a11y.pending")
                         : String(localized: "board.a11y.selected"))
        }
        if forbidden.contains(square) { parts.append(String(localized: "board.a11y.forbidden")) }
        if captures.contains(square) { parts.append(String(localized: "board.a11y.capture")) }
        else if destinations.contains(square) { parts.append(String(localized: "board.a11y.legalMove")) }
        // A suggested point is a legal destination first, so its token is added
        // rather than replacing one.
        if square == suggested { parts.append(String(localized: "board.a11y.suggested")) }
        if square == checkedGeneral { parts.append(String(localized: "board.a11y.inCheck")) }
        return parts.joined(separator: " ")
    }

    /// A format string, because the punctuation between the parts is copy that
    /// differs by language. The piece comes apart so a stone can never reach
    /// this.
    static func hintAnnouncement(game: GameKind, side: Side, kind: PieceKind,
                                 from: Square, to: Square) -> String {
        String(format: String(localized: "board.a11y.hint.announcement"),
               game.sideName(side), kind.name(for: side), from.name, to.name)
    }

    /// On a placement board there is no piece to name and no journey, so only
    /// the point is said.
    static func hintAnnouncement(point: Square) -> String {
        String(format: String(localized: "board.a11y.hint.point"), point.name)
    }

    // MARK: - Go-style coordinates

    /// No letter is skipped, matching the core's spelling: the list reads `h8`,
    /// and an edge without `i` would send a reader to the wrong line. The 记谱法
    /// preference does not apply.
    private var fileLetterStrip: some View {
        HStack(spacing: 0) {
            ForEach(0..<geometry.board.fileCount, id: \.self) { column in
                let file = flipped ? geometry.board.fileCount - 1 - column : column
                Text(Square(file: file, rank: 0).fileLetter)
                    .font(.system(size: geometry.numeralSize, weight: .bold))
                    .foregroundStyle(style.grid)
                    .frame(width: p)
            }
        }
        .frame(width: geometry.coreSize.width, height: geometry.stripHeight)
        .background(style.boardSurface)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("file-letters")
        .accessibilityLabel((0..<geometry.board.fileCount)
            .map { Square(file: $0, rank: 0).fileLetter }
            .joined(separator: " "))
    }

    /// The numbers up the leading side, `1` at the bottom.
    private var rankNumberStrip: some View {
        VStack(spacing: 0) {
            ForEach(0..<geometry.board.rankCount, id: \.self) { row in
                let rank = flipped ? row : geometry.board.rankCount - 1 - row
                Text(String(rank + 1))
                    .font(.system(size: geometry.numeralSize, weight: .bold))
                    .foregroundStyle(style.grid)
                    .frame(height: p)
            }
        }
        .frame(width: geometry.stripWidth, height: geometry.coreSize.height)
        .background(style.boardSurface)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("rank-numbers")
        .accessibilityLabel((1...geometry.board.rankCount)
            .map(String.init)
            .joined(separator: " "))
    }

    // MARK: - File numerals

    /// One strip per side, in the numerals of the player it faces. A numeral
    /// cannot glide into another, so in a flip both orientations stand in the
    /// strip and crossfade, under Reduce Motion too: opacity is not motion.
    private func numeralStrip(atTop: Bool) -> some View {
        let isRed = atTop ? flipped : !flipped
        return ZStack {
            stripContent(atTop: atTop, orientationFlipped: false)
                .opacity(flipped ? 0 : 1)
            stripContent(atTop: atTop, orientationFlipped: true)
                .opacity(flipped ? 1 : 0)
        }
        .frame(width: geometry.coreSize.width, height: geometry.stripHeight)
        .background(style.boardSurface)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(isRed ? "file-numerals-red" : "file-numerals-black")
        .accessibilityLabel((0..<geometry.board.fileCount)
            .map { numeral(file: flipped ? geometry.board.fileCount - 1 - $0 : $0,
                           forRedPlayer: isRed) }
            .joined(separator: " "))
    }

    /// The top faces Red exactly when the board is flipped.
    private func stripContent(atTop: Bool, orientationFlipped: Bool) -> some View {
        let isRed = atTop ? orientationFlipped : !orientationFlipped
        return HStack(spacing: 0) {
            ForEach(0..<geometry.board.fileCount, id: \.self) { column in
                let file = orientationFlipped ? geometry.board.fileCount - 1 - column : column
                Text(numeral(file: file, forRedPlayer: isRed))
                    .font(.system(size: geometry.numeralSize,
                                  weight: isChinese(forRedPlayer: isRed) ? .semibold : .bold))
                    .foregroundStyle(style.grid)
                    .frame(width: p)
            }
        }
    }

    /// Each edge counts from its player's own right, whatever the notation;
    /// only the script follows the 记谱法 preference.
    private func numeral(file: Int, forRedPlayer isRed: Bool) -> String {
        let index = isRed ? geometry.board.fileCount - 1 - file : file
        return isChinese(forRedPlayer: isRed)
            ? ["一", "二", "三", "四", "五", "六", "七", "八", "九"][index]
            : String(index + 1)
    }

    /// Chinese numerals carry more strokes, so the Arabic digits are set one
    /// step heavier to read as equal; the compensation follows the script, not
    /// the side.
    private func isChinese(forRedPlayer isRed: Bool) -> Bool {
        isRed && notationStyle == .traditional
    }
}
