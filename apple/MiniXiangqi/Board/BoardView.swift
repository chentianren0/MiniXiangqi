// The board: a grid of *points*, never a checkerboard of squares.
//
// Everything is drawn from BoardGeometry, so the board scales without any
// dimension being re-tuned. The picture itself is BoardCanvas, which carries
// the accepted layering and every motion phase; this view supplies what
// surrounds the picture — the numeral strips, and the invisible grid of tap
// targets that gives the points names — and assembles the canvas's phase
// targets from the game and motion state it is handed.

import SwiftUI

struct BoardView: View {
    var geometry: BoardGeometry
    var placement: Placement
    var flipped: Bool = false

    /// Whether the two file-numeral strips are drawn. Always, in the product;
    /// a debug launch argument takes them off so the board can be looked at
    /// both ways at the same window size.
    var showsNumerals: Bool = true

    /// The point the player is holding: the piece taken up in a movement game,
    /// and the marked point awaiting confirmation in a placement one.
    var selected: Square?
    var destinations: Set<Square> = []
    var captures: Set<Square> = []
    /// The points the side to move may not play, where the game has any.
    var forbidden: Set<Square> = []
    /// The destination a shown hint suggests, where one is shown. It is one of
    /// the held piece's own destinations and is drawn as one; what it gains is
    /// the strengthening below and, for a screen reader, a state token beside
    /// the others.
    var suggested: Square?
    var lastMove: Move?
    var checkedGeneral: Square?

    /// The running committing transition and the emphasis phases, from
    /// PlayMotion. A static board — a snapshot, a preview — leaves them at
    /// rest and draws exactly the states it was given.
    var transit: Transit?
    /// The second disc of a paired transition — the two plies of a decision
    /// cycle rewinding together.
    var companion: Transit?
    var transitFade: Double = 0
    var checkEmphasis: Double = 0
    var markerEmphasis: Double = 0
    /// How strongly the suggested destination is drawn — the hint's own
    /// emphasis, which arrives with a swell in full motion and at once under
    /// Reduce Motion. It carries the muting and the halo with it: all three are
    /// the one suggestion, so all three ride the one phase.
    var hintEmphasis: Double = 0
    var policy = MotionPolicy(reduceMotion: false)

    /// When the running dash drift began, or nil when none is running. The
    /// dashes turn from where they are drawn at rest rather than from wherever
    /// a shared clock happens to stand, so a suggestion shown on a capture ring
    /// already on the board sets it turning instead of jolting it.
    @State private var driftStart: Date?

    var style: BoardStyle = .traditional

    /// How far the style's board surface runs past the block on each side.
    ///
    /// docs/interaction-design.md, "Layout shapes": a stacked board screen is
    /// fitted to the full width, and the surface runs to the screen edges
    /// beneath the numeral strips so the board meets the glass rather than
    /// leaving the whole-point pitch's remainder showing page. How many points
    /// that is belongs to the layout — `BoardLayout.surfaceBleed(in:board:)` —
    /// and every other board is drawn with none, which is the board's own width
    /// and nothing beside it.
    var surfaceBleed: CGFloat = 0

    var onTap: (Square) -> Void = { _ in }

    /// The 棋子符号 preference, read here because this is the one place every
    /// board comes from — play, replay, and any snapshot alike — so the switch
    /// reaches all of them without either screen having to know about it.
    ///
    /// Held as the stored string rather than as `PieceSymbols` so that an
    /// unrecognised value is the default rather than a crash, and observed
    /// rather than merely read so that flipping the preference in Settings
    /// repaints the board that is already on screen.
    @AppStorage(PieceSymbols.key, store: Preferences.defaults) private var storedSymbols: String?

    /// The 记谱法 preference, which the strips follow: the strips exist so a
    /// player can map the move list to the board, so a WXF list beside a 一二三
    /// edge would break the very mapping they are for. Read here so that
    /// changing the preference re-renders them live — and unchosen, it is the
    /// interface language's own reading, so the strips and the list agree from
    /// the first launch in either language.
    @AppStorage(NotationStyle.key, store: Preferences.defaults)
    private var notationStyle: NotationStyle = .resolvedForInterfaceLanguage

    /// The arrival wires, each fired on the frame its animation reaches its
    /// target — see ArrivalReporter for why the transaction completion alone
    /// cannot be trusted with a gate. Two belong to a committing transition;
    /// the third says the board has finished turning round, which is when the
    /// points below are back under the discs above them.
    var onTravelArrival: () -> Void = { }
    var onFadeArrival: () -> Void = { }
    var onFlipArrival: () -> Void = { }

    private var p: CGFloat { geometry.pitch }

    var body: some View {
        block
        // The pitch is unchanged either way, so the two renderings differ by
        // exactly the room the strips take and by nothing else.
        .frame(width: showsNumerals ? geometry.blockSize.width : geometry.coreSize.width,
               height: showsNumerals ? geometry.blockSize.height : geometry.coreSize.height)
        // The surface behind the whole block, which is what runs past it where
        // the layout asks. The core and the strips carry their own fill too, so
        // this changes nothing at all where the bleed is none.
        .background {
            style.boardSurface.padding(.horizontal, -surfaceBleed)
        }
    }

    /// The board and whatever labels its edges, laid out the way its own
    /// convention asks: file numerals above and below, or Go-style letters
    /// beneath with numbers up the leading side.
    @ViewBuilder
    private var block: some View {
        switch geometry.coordinates {
        case .fileNumerals:
            VStack(spacing: 0) {
                if showsNumerals { numeralStrip(atTop: true) }
                core
                if showsNumerals { numeralStrip(atTop: false) }
            }
        case .goStyle:
            // Top-aligned, so the numbers up the side stand beside the core's
            // own rows rather than being centred against the block the letter
            // strip beneath makes taller.
            HStack(alignment: .top, spacing: 0) {
                if showsNumerals { rankNumberStrip }
                VStack(spacing: 0) {
                    core
                    if showsNumerals { fileLetterStrip }
                }
            }
        }
    }

    // MARK: - The board core

    private var core: some View {
        // Every other thing the board draws changes inside a transaction and is
        // interpolated as a phase. The drift is the exception — it turns for as
        // long as a suggestion stands rather than from one state to another —
        // so it is driven by the clock instead, on a schedule that ticks only
        // while it is running and is paused for every other moment of a game.
        // It ticks at the display's own rate, uncapped: motion never limits
        // its frame rate, and what bounds the drift's cost is the pause, not
        // the tick.
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
        .onChange(of: driftsDashes, initial: true) { _, drifting in
            driftStart = drifting ? .now : nil
        }
    }

    private func canvas(dashDrift: Double) -> some View {
        BoardCanvas(geometry: geometry,
                    placement: placement,
                    style: style,
                    symbols: PieceSymbols.named(storedSymbols),
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
                                        flip: flipped ? 1 : 0,
                                        check: checkEmphasis,
                                        marker: markerEmphasis,
                                        hint: SquarePhases(suggested, at: hintEmphasis),
                                        lifts: SquarePhases(raised: selected)))
    }

    /// Whether the board's one continuous motion is running: a suggested
    /// capture's dashes turn for as long as the suggestion stands, and stop the
    /// instant anything takes it off the board. A rotation is motion, so under
    /// Reduce Motion they hold still and the suggestion is said by the marks
    /// that do not move.
    var driftsDashes: Bool {
        guard let suggested, !policy.reduceMotion else { return false }
        return captures.contains(suggested)
    }

    /// How far the dashes have turned by `date`, from the instant the drift
    /// began. At rest, and for every ring but the suggested one, they are drawn
    /// exactly where the pattern places them.
    private func drift(at date: Date) -> Double {
        guard driftsDashes, let driftStart else { return 0 }
        return Motion.dashDrift(elapsed: date.timeIntervalSince(driftStart))
    }

    /// One element per point, over the drawn board.
    ///
    /// The board is drawn as a single canvas, which is right — it is one
    /// picture, not a view per point — but a picture has no points a pointer
    /// can hit or a screen reader can name. This grid supplies both: it is what
    /// makes a tap land on a point rather than at a coordinate, and what lets
    /// someone who cannot see the board hear where the pieces are.
    ///
    /// Each element is placed at the same centre the canvas draws that point
    /// at, from the same function, rather than laid out by a stack that happens
    /// to divide the board evenly. A stack invites a stray inset — an earlier
    /// version had one, and it silently shifted every point by a fraction of a
    /// cell while remaining perfectly self-consistent, so clicking by name
    /// still worked and no test could see it. Sharing the geometry is what
    /// makes the two agree at every orientation the board settles in.
    ///
    /// They disagree in exactly one window: these elements jump to the flipped
    /// positions when the flip begins, while the canvas carries each disc
    /// along the arc of the rotation. For those 350 ms a point's element is
    /// not under its drawn disc, so PlayMotion discards board input for the
    /// length of the flip rather than committing a move the player did not
    /// aim. What is accepted with it is that a screen reader's frames drift
    /// for the same 350 ms: the labels stay true throughout — they are read
    /// from the position, which a flip does not touch — and the frames are
    /// right again the moment the board is.
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
    /// and any state that is on it.
    ///
    /// The point's name is a coordinate and is the same in every language. The
    /// piece is named by `PieceKind.name(for:)`, which is where the two
    /// languages part company — Chinese says the character on the disc, English
    /// says the piece's name — so `b1 红 炮 已选择` is `b1 Red Cannon Selected`.
    private func describe(_ square: Square) -> String {
        var parts = [square.name]
        if let piece = placement[square] {
            parts.append(placement.game.sideName(piece.side))
            // A stone has no kind and therefore no name of its own: what it is
            // has already been said by the side beside it.
            if let kind = piece.kind { parts.append(kind.name(for: piece.side)) }
        } else {
            parts.append(String(localized: "board.a11y.empty"))
        }
        if square == selected {
            // The same state under two names, because it is two states: a piece
            // taken up, and a point marked for a stone that is not down yet.
            parts.append(geometry.board.play == .placement
                         ? String(localized: "board.a11y.pending")
                         : String(localized: "board.a11y.selected"))
        }
        if forbidden.contains(square) { parts.append(String(localized: "board.a11y.forbidden")) }
        if captures.contains(square) { parts.append(String(localized: "board.a11y.capture")) }
        else if destinations.contains(square) { parts.append(String(localized: "board.a11y.legalMove")) }
        // A suggested point is a legal destination first and a suggestion
        // second, so its token joins the vocabulary rather than replacing any
        // of it.
        if square == suggested { parts.append(String(localized: "board.a11y.suggested")) }
        if square == checkedGeneral { parts.append(String(localized: "board.a11y.inCheck")) }
        return parts.joined(separator: " ")
    }

    /// What a screen reader is told when a suggestion appears, composed from
    /// the same vocabulary a point's own description is composed from: the
    /// side, the piece, and the two point names. `Suggestion: Red Cannon b1 to
    /// b5`, and its Chinese counterpart.
    ///
    /// The parts are joined by a format string rather than by interpolation,
    /// because what stands between them is copy — a colon and spaces in
    /// English, an ideographic colon and no space between side and piece in
    /// Chinese — and a separator hard-coded here would be one language's
    /// punctuation wrapped around the other language's words.
    static func hintAnnouncement(game: GameKind, piece: Piece,
                                 from: Square, to: Square) -> String {
        String(format: String(localized: "board.a11y.hint.announcement"),
               game.sideName(piece.side),
               piece.kind?.name(for: piece.side) ?? String(localized: "board.a11y.empty"),
               from.name, to.name)
    }

    // MARK: - Go-style coordinates

    /// The letters along the bottom edge, `a` at the leading end.
    ///
    /// A coordinate is absolute, so an orientation re-orders the labels and
    /// never renames them — and these are the coordinates the core itself
    /// spells, letter for letter, with no letter skipped: the move list beside
    /// the board reads `h8`, and an edge that had left `i` out would send a
    /// reader to the wrong line.
    ///
    /// The 记谱法 preference is not consulted anywhere in this pair. These games
    /// have one convention of their own, and a xiangqi reading has nothing to
    /// say about a board with no files to number from a player's own right.
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

    /// One strip per side, showing the numerals of the player it faces —
    /// Chinese for Red and Arabic for Black under the traditional reading,
    /// Arabic for both under WXF — following the board's orientation.
    /// A numeral cannot glide into a different numeral, so while the pieces
    /// re-lay themselves in a flip the strip crossfades in place: both
    /// orientations' renderings stand in the one strip and trade opacity in
    /// the flip's own transaction — under Reduce Motion exactly as in full
    /// motion, since opacity is not motion.
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

    /// The strip at one physical position, rendered for one orientation:
    /// the top faces Red exactly when the board is flipped.
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

    /// Files are numbered from each player's own right: Red's right is the
    /// board's final file,
    /// Black's is file a. Which way each edge counts is the board's, not the
    /// notation's, and never changes; the script does. The traditional reading
    /// writes Red's numbers in Chinese numerals and Black's in Arabic, and WXF
    /// writes both sides' in Arabic, so under WXF Red's edge changes script and
    /// nothing else.
    private func numeral(file: Int, forRedPlayer isRed: Bool) -> String {
        let index = isRed ? geometry.board.fileCount - 1 - file : file
        return isChinese(forRedPlayer: isRed)
            ? ["一", "二", "三", "四", "五", "六", "七", "八", "九"][index]
            : String(index + 1)
    }

    /// Whether a strip is written in Chinese numerals, which only Red's is and
    /// only under the traditional reading.
    ///
    /// It settles the weight as well as the script. Chinese numerals carry more
    /// strokes than digits do at the same weight, so the digits are set one step
    /// heavier for the two edges to read as equal in weight — the accepted
    /// requirement — and that compensation belongs to the script rather than to
    /// the side: two Arabic edges at different weights would read as unequal.
    private func isChinese(forRedPlayer isRed: Bool) -> Bool {
        isRed && notationStyle == .traditional
    }
}
