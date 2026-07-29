// The board: a 7-by-7 grid of *points*, never a checkerboard of squares.
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

    var selected: Square?
    var destinations: Set<Square> = []
    var captures: Set<Square> = []
    var lastMove: Move?
    var checkedGeneral: Square?

    /// The running committing transition and the emphasis phases, from
    /// PlayMotion. A static board — a snapshot, a preview — leaves them at
    /// rest and draws exactly the states it was given.
    var transit: Transit?
    var transitFade: Double = 0
    var checkEmphasis: Double = 0
    var markerEmphasis: Double = 0
    var policy = MotionPolicy(reduceMotion: false)

    var style: BoardStyle = .traditional
    var onTap: (Square) -> Void = { _ in }

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
        VStack(spacing: 0) {
            if showsNumerals { numeralStrip(atTop: true) }
            core
            if showsNumerals { numeralStrip(atTop: false) }
        }
        // The pitch is unchanged either way, so the two renderings differ by
        // exactly the room the strips take and by nothing else.
        .frame(width: geometry.blockSize.width,
               height: showsNumerals ? geometry.blockSize.height : geometry.coreSide)
    }

    // MARK: - The board core

    private var core: some View {
        BoardCanvas(geometry: geometry,
                    placement: placement,
                    style: style,
                    policy: policy,
                    destinations: destinations,
                    captures: captures,
                    lastMove: lastMove,
                    checkedGeneral: checkedGeneral,
                    transit: transit,
                    phases: BoardPhases(travel: transit == nil ? 0 : 1,
                                        fade: transitFade,
                                        flip: flipped ? 1 : 0,
                                        check: checkEmphasis,
                                        marker: markerEmphasis,
                                        lifts: SquarePhases(raised: selected)))
            .modifier(ArrivalReporter(progress: transit == nil ? 0 : 1,
                                      arrived: onTravelArrival))
            .modifier(ArrivalReporter(progress: transitFade, arrived: onFadeArrival))
            .modifier(ArrivalReporter(progress: flipped ? 1 : 0, arrived: onFlipArrival))
            .frame(width: geometry.coreSide, height: geometry.coreSide)
            .background(style.boardSurface)
            .overlay(points)
    }

    /// One element per point, over the drawn board.
    ///
    /// The board is drawn as a single canvas, which is right — it is one
    /// picture, not forty-nine views — but a picture has no points a pointer
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
            ForEach(0..<(Square.count * Square.count), id: \.self) { index in
                let square = Square(file: index % Square.count,
                                    rank: index / Square.count)
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
        .frame(width: geometry.coreSide, height: geometry.coreSide)
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
            parts.append(piece.side == .red
                         ? String(localized: "board.a11y.red")
                         : String(localized: "board.a11y.black"))
            parts.append(piece.kind.name(for: piece.side))
        } else {
            parts.append(String(localized: "board.a11y.empty"))
        }
        if square == selected { parts.append(String(localized: "board.a11y.selected")) }
        if captures.contains(square) { parts.append(String(localized: "board.a11y.capture")) }
        else if destinations.contains(square) { parts.append(String(localized: "board.a11y.legalMove")) }
        if square == checkedGeneral { parts.append(String(localized: "board.a11y.inCheck")) }
        return parts.joined(separator: " ")
    }

    // MARK: - File numerals

    /// One strip per side, showing the numerals of the player it faces —
    /// Chinese for Red, Arabic for Black — following the board's orientation.
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
        .frame(width: geometry.coreSide, height: geometry.stripHeight)
        .background(style.boardSurface)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(isRed ? "file-numerals-red" : "file-numerals-black")
        .accessibilityLabel((0..<Square.count)
            .map { numeral(file: flipped ? Square.count - 1 - $0 : $0, forRedPlayer: isRed) }
            .joined(separator: " "))
    }

    /// The strip at one physical position, rendered for one orientation:
    /// the top faces Red exactly when the board is flipped.
    private func stripContent(atTop: Bool, orientationFlipped: Bool) -> some View {
        let isRed = atTop ? orientationFlipped : !orientationFlipped
        return HStack(spacing: 0) {
            ForEach(0..<Square.count, id: \.self) { column in
                let file = orientationFlipped ? Square.count - 1 - column : column
                Text(numeral(file: file, forRedPlayer: isRed))
                    .font(.system(size: geometry.numeralSize,
                                  weight: isRed ? .semibold : .bold))
                    .foregroundStyle(style.grid)
                    .frame(width: p)
            }
        }
    }

    /// Files are numbered from each player's own right: Red's right is file g,
    /// Black's is file a.
    private func numeral(file: Int, forRedPlayer isRed: Bool) -> String {
        let index = isRed ? Square.count - 1 - file : file
        return isRed ? ["一", "二", "三", "四", "五", "六", "七"][index]
                     : String(index + 1)
    }
}
