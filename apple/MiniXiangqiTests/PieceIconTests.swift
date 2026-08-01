// The 图标 set, rendered at the size it has to survive, and measured where it
// can be.
//
// This suite was the drawing loop. The glyphs were tuned against these images
// rather than against a description of them, because the whole difficulty of
// the set is that `symbolSize` is `0.50 p` — 17 points at Xiangqi's 34-point
// pitch floor — and nothing about a glyph that small can be judged from path data.
// It stays in the suite as the gate's artefact generator: these sheets are what
// the chariot-versus-cannon gate is read from, beside the UI tests' shots of
// the running board.
//
// The measurements below are the parts of the separation rule a machine can
// check — the envelopes' axes, which glyph is symmetric, that the wheel exists
// and that the cannon carries no hole. Whether the pair is *unmistakable* is
// not one of them; that is what the sheets and the eye reading them are for.
//
// Images are written into the sandboxed host's own caches and attached to the
// result bundle, exactly as BoardSnapshotTests does and for the same reason.

import Foundation
import SwiftUI
import Testing
@testable import MiniXiangqi

@Suite("Piece icons")
@MainActor
struct PieceIconTests {

    static let miniBoard = GameKind.miniXiangqi.board
    static let xiangqiBoard = GameKind.xiangqi.board
    /// The two accepted floors, and one pitch a large Mini board reaches.
    static let miniFloorPitch = BoardGeometry.minimumPitch(for: miniBoard)
    static let xiangqiFloorPitch = BoardGeometry.minimumPitch(for: xiangqiBoard)
    static let largePitch = miniFloorPitch * 2

    // MARK: - The sheets the gate is read from

    @Test("The starting position with icons, at the accepted floor")
    func startingPositionWithIcons() throws {
        let geometry = BoardGeometry(board: Self.miniBoard, pitch: Self.miniFloorPitch)
        let size = try render(board(Core.startFEN(for: .miniXiangqi), .miniXiangqi,
                                    geometry, symbols: .icons),
                              named: "icons-start-at-the-floor")
        #expect(size == geometry.coreSize)
    }

    @Test("The starting position with characters, for comparison")
    func startingPositionWithCharacters() throws {
        let geometry = BoardGeometry(board: Self.miniBoard, pitch: Self.miniFloorPitch)
        let size = try render(board(Core.startFEN(for: .miniXiangqi), .miniXiangqi,
                                    geometry, symbols: .hanzi),
                              named: "hanzi-start-at-the-floor")
        #expect(size == geometry.coreSize)
    }

    @Test("The starting position with icons, large")
    func startingPositionLarge() throws {
        let geometry = BoardGeometry(board: Self.miniBoard, pitch: Self.largePitch)
        let size = try render(board(Core.startFEN(for: .miniXiangqi), .miniXiangqi,
                                    geometry, symbols: .icons),
                              named: "icons-start-large")
        #expect(size == geometry.coreSize)
    }

    @Test("The Xiangqi starting position survives its smaller pitch")
    func xiangqiStartingPosition() throws {
        let geometry = BoardGeometry(board: Self.xiangqiBoard, pitch: Self.xiangqiFloorPitch)
        let fen = Core.startFEN(for: .xiangqi)
        let sheet = HStack(spacing: 0) {
            board(fen, .xiangqi, geometry, symbols: .icons)
            board(fen, .xiangqi, geometry, symbols: .hanzi)
        }
        let size = try render(sheet, named: "xiangqi-start-at-the-floor")
        #expect(size == CGSize(width: 2 * geometry.coreSize.width,
                              height: geometry.coreSize.height))
    }

    @Test("The seven, both sides, at the Xiangqi floor and large")
    func theSeven() throws {
        // One rank of each side, in the survey's convention-table order, so
        // every glyph stands beside every other on real discs in both inks.
        let fen = "kabrncp2/9/9/9/9/9/9/9/9/KABRNCP2"
        for (pitch, name) in [(Self.xiangqiFloorPitch, "the-seven-at-the-floor"),
                              (Self.largePitch, "the-seven-large")] {
            let geometry = BoardGeometry(board: Self.xiangqiBoard, pitch: pitch)
            _ = try render(board(fen, .xiangqi, geometry, symbols: .icons),
                           named: "icons-\(name)")
        }
    }

    @Test("The demanding pair, adjacent at the floor, icons against characters")
    func chariotAgainstCannon() throws {
        // Gate A in the form the contract states it: chariot beside cannon at
        // the smallest supported board size. Alternating them along both back
        // ranks is the hardest adjacency the board can produce, and the same
        // position in characters beneath it says what the icons are standing in
        // for.
        let geometry = BoardGeometry(board: Self.xiangqiBoard, pitch: Self.xiangqiFloorPitch)
        let fen = "rcrcrcrcr/9/9/9/9/9/9/9/9/RCRCRCRCR"
        let sheet = VStack(spacing: 0) {
            board(fen, .xiangqi, geometry, symbols: .icons)
            board(fen, .xiangqi, geometry, symbols: .hanzi)
        }
        _ = try render(sheet, named: "chariot-against-cannon-at-the-floor")
    }

    @Test("Every glyph as bare ink, at three sizes", arguments: PieceKind.allCases)
    func silhouettes(kind: PieceKind) throws {
        let gate = BoardGeometry(board: Self.xiangqiBoard,
                                 pitch: Self.xiangqiFloorPitch).symbolSize
        let sheet = HStack(alignment: .bottom, spacing: 10) {
            ForEach([gate, gate * 2, gate * 6], id: \.self) { size in
                PieceIcon(kind: kind)
                    .fill(BoardStyle.traditional.symbol(.black), style: FillStyle(eoFill: true))
                    .frame(width: size, height: size)
            }
        }
        .padding(10)
        .background(BoardStyle.traditional.discFace)
        _ = try render(sheet, named: "glyph-\(kind)")
    }

    // MARK: - What the box allows

    @Test("Every glyph stays inside its box", arguments: PieceKind.allCases)
    func containedByTheSymbolBox(kind: PieceKind) {
        // A glyph that overflowed `symbolSize` would reach past the disc face
        // and into the band the markers own, which the board metrics forbid.
        let box = CGRect(x: 11, y: 23, width: 22, height: 22)
        let bounds = PieceIcon.path(for: kind, in: box).boundingRect
        #expect(box.insetBy(dx: -0.01, dy: -0.01).contains(bounds),
                "\(kind) drew \(bounds) outside \(box)")
    }

    @Test("No glyph draws itself small", arguments: PieceKind.allCases)
    func fillsTheBox(kind: PieceKind) {
        // The seven envelopes differ deliberately, so none of them fills the box
        // both ways — this is a floor on smallness, not a target. A glyph that
        // filled neither direction would be quietly lighter than the character
        // it stands in for on the same disc.
        let bounds = design(kind).boundingRect
        #expect(max(bounds.width, bounds.height) >= 84,
                "\(kind) is \(bounds.size) in a \(PieceIcon.designSide)-point box")
    }

    // MARK: - The separation rule, where it can be measured

    @Test("The envelopes differ in axis")
    func envelopesDifferInAxis() {
        func aspect(_ kind: PieceKind) -> CGFloat {
            let bounds = design(kind).boundingRect
            return bounds.width / bounds.height
        }
        // The second separation channel: the cart is upright and the cannon is
        // wide, so the pair differs in a property of the bounding box — which
        // is what survives downsampling when internal detail does not.
        #expect(aspect(.chariot) < 1)
        #expect(aspect(.cannon) > 1.2)
        // And the other three do not rhyme with either of them.
        #expect(aspect(.general) > 1.2)
        #expect(aspect(.advisor) < 0.6)
        #expect(aspect(.elephant) > 1)
        #expect(aspect(.soldier) < 0.85)
        #expect(aspect(.horse) < 1)
    }

    @Test("The cart is not directional and the cannon is")
    func theThirdChannel() {
        // The third channel, measured as how much of a glyph its own mirror
        // image covers. A symmetric glyph and a one-sided one never look alike
        // however blurred they get.
        #expect(mirrorAgreement(.chariot) > 0.98)
        #expect(mirrorAgreement(.general) > 0.98)
        #expect(mirrorAgreement(.advisor) > 0.98)
        #expect(mirrorAgreement(.soldier) > 0.98)
        #expect(mirrorAgreement(.elephant) < 0.90)
        #expect(mirrorAgreement(.cannon) < 0.80)
        #expect(mirrorAgreement(.horse) < 0.80)
    }

    @Test("The chariot is wheeled: a hub knocked out of a solid rim")
    func theChariotIsWheeled() {
        let wheel = design(.chariot)
        let hub = CGPoint(x: 50, y: 74)
        #expect(!wheel.contains(hub, eoFill: true), "the hub is knocked out")
        // The rim is solid the whole way round, which is what makes the shape
        // read as a wheel rather than as a blob with a nick in it.
        for degrees in stride(from: 0, to: 360, by: 15) {
            let angle = CGFloat(degrees) * .pi / 180
            let point = CGPoint(x: hub.x + 15 * cos(angle), y: hub.y + 15 * sin(angle))
            #expect(wheel.contains(point, eoFill: true),
                    "the rim should be solid at \(degrees) degrees")
        }
    }

    @Test("The cannon carries no hole, so it carries no wheel")
    func theCannonIsNotWheeled() {
        // The first and strongest channel. A hole is what a wheel needs here,
        // so an enclosed gap anywhere in the cannon would be the beginning of
        // one; there is none, and the glyph is one unbroken mass.
        #expect(enclosedGaps(in: .cannon) == 0)
        #expect(enclosedGaps(in: .chariot) > 0, "the wheel's hub is exactly such a gap")
    }

    // MARK: - The preference

    @Test("Absent, the preference means 汉字")
    func absentMeansCharacters() {
        #expect(PieceSymbols.current(in: scratchDefaults()) == .hanzi)
    }

    @Test("The two accepted values name the two sets")
    func theAcceptedValues() {
        let defaults = scratchDefaults()
        defaults.set("icons", forKey: PieceSymbols.key)
        #expect(PieceSymbols.current(in: defaults) == .icons)
        defaults.set("hanzi", forKey: PieceSymbols.key)
        #expect(PieceSymbols.current(in: defaults) == .hanzi)
    }

    @Test("Anything else means 汉字 too")
    func nonsenseMeansCharacters() {
        let defaults = scratchDefaults()
        defaults.set("pictograms", forKey: PieceSymbols.key)
        #expect(PieceSymbols.current(in: defaults) == .hanzi,
                "an unrecognised value must not stop the board drawing")
    }

    @Test("A board told nothing about symbols draws characters")
    func theCanvasDefaultsToCharacters() {
        // What keeps every existing snapshot and motion frame identical: the
        // canvas's own default is the accepted one, so only a caller that asks
        // for icons gets them.
        let canvas = BoardCanvas(
                                 geometry: BoardGeometry(board: Self.miniBoard,
                                                         pitch: Self.miniFloorPitch),
                                 placement: Placement(fen: Core.startFEN(for: .miniXiangqi),
                                                      game: .miniXiangqi),
                                 style: .traditional,
                                 policy: MotionPolicy(reduceMotion: false),
                                 phases: BoardPhases())
        #expect(canvas.symbols == .hanzi)
    }

    private func scratchDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "mxq-icons-" + UUID().uuidString)!
        defaults.removeObject(forKey: PieceSymbols.key)
        return defaults
    }

    // MARK: - Measuring a glyph

    private func design(_ kind: PieceKind) -> Path {
        PieceIcon.design(for: kind)
    }

    /// Every sample point of the design box, at unit spacing.
    private static let samples: [CGPoint] = {
        let side = Int(PieceIcon.designSide)
        return (0..<side).flatMap { row in
            (0..<side).map { column in
                CGPoint(x: CGFloat(column) + 0.5, y: CGFloat(row) + 0.5)
            }
        }
    }()

    /// Which sample points a glyph's ink covers, as a grid indexed
    /// `[row][column]`.
    private func ink(_ kind: PieceKind) -> [[Bool]] {
        let path = design(kind)
        let side = Int(PieceIcon.designSide)
        return (0..<side).map { row in
            (0..<side).map { column in
                path.contains(CGPoint(x: CGFloat(column) + 0.5, y: CGFloat(row) + 0.5),
                              eoFill: true)
            }
        }
    }

    /// How much of a glyph its own mirror image covers, as the intersection
    /// over the union of the two. Background agreement is left out on purpose:
    /// counting it would score every small glyph as symmetric.
    private func mirrorAgreement(_ kind: PieceKind) -> Double {
        let grid = ink(kind)
        let side = grid.count
        var both = 0, either = 0
        for row in 0..<side {
            for column in 0..<side {
                let here = grid[row][column]
                let mirrored = grid[row][side - 1 - column]
                if here && mirrored { both += 1 }
                if here || mirrored { either += 1 }
            }
        }
        return either == 0 ? 0 : Double(both) / Double(either)
    }

    /// How many sample points are unfilled and yet have the glyph's ink in all
    /// four directions along their own row and column — the signature of a gap
    /// the glyph encloses, rather than of the air around it.
    private func enclosedGaps(in kind: PieceKind) -> Int {
        let grid = ink(kind)
        let side = grid.count
        var count = 0
        for row in 1..<(side - 1) {
            for column in 1..<(side - 1) where !grid[row][column] {
                let above = (0..<row).contains { grid[$0][column] }
                let below = ((row + 1)..<side).contains { grid[$0][column] }
                let left = (0..<column).contains { grid[row][$0] }
                let right = ((column + 1)..<side).contains { grid[row][$0] }
                if above && below && left && right { count += 1 }
            }
        }
        return count
    }

    // MARK: - The board, as the board draws it

    private func board(_ fen: String, _ game: GameKind, _ geometry: BoardGeometry,
                       symbols: PieceSymbols) -> some View {
        BoardCanvas(geometry: geometry,
                    placement: Placement(fen: fen, game: game),
                    style: .traditional,
                    symbols: symbols,
                    policy: MotionPolicy(reduceMotion: false),
                    phases: BoardPhases())
            .frame(width: geometry.coreSize.width, height: geometry.coreSize.height)
            .background(BoardStyle.traditional.boardSurface)
    }
}

/// The same writer BoardSnapshotTests uses: the app's own caches, plus the
/// result bundle, because the test host may not write outside its container.
@MainActor
private func render(_ view: some View, scale: CGFloat = 4, named name: String) throws -> CGSize {
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MiniXiangqiSnapshots", isDirectory: true)
    guard let (image, png) = renderPNG(view, scale: scale) else {
        Issue.record("the glyph did not render")
        return .zero
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(name).png")
    try png.write(to: url)
    Attachment.record(image, named: name, as: .png)
    #expect(FileManager.default.fileExists(atPath: url.path), "wrote \(url.path)")
    return image.size
}
