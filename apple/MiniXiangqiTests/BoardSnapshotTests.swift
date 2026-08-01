// Renders the board to a PNG so it can be looked at.
//
// Xcode's preview JIT does not run against this app's entitlements on the
// pinned toolchain, and a board nobody has rendered is exactly the kind of
// design a review cannot check. These write into the sandboxed host's own
// caches and attach the same image to the result bundle, and assert the
// render's size.

import Foundation
import SwiftUI
import Testing
@testable import MiniXiangqi

/// The app's own caches directory. The test host is a hardened process and may
/// not write outside its container, which is correct — a generated artefact
/// belongs in the app's cache, not in the source tree — so the path is reported
/// once per run and whoever wants to look at the images copies them out.
private var snapshotDirectory: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MiniXiangqiSnapshots", isDirectory: true)
}

@MainActor
private func render(_ view: some View, scale: CGFloat = 2, named name: String) throws -> CGSize {
    guard let (image, png) = renderPNG(view, scale: scale) else {
        Issue.record("the board did not render")
        return .zero
    }
    try FileManager.default.createDirectory(at: snapshotDirectory,
                                            withIntermediateDirectories: true)
    let url = snapshotDirectory.appendingPathComponent("\(name).png")
    try png.write(to: url)
    // Also into the result bundle, which is readable without standing in
    // front of the machine: the container is the sandboxed host's own, and
    // exporting attachments is how anything else gets to look.
    Attachment.record(image, named: name, as: .png)
    #expect(FileManager.default.fileExists(atPath: url.path), "wrote \(url.path)")
    return image.size
}

@Suite("Board snapshots")
@MainActor
struct BoardSnapshotTests {
    let geometry = BoardGeometry(pitch: BoardGeometry.minimumPitch)

    @Test("The starting position renders at the accepted floor")
    func startingPosition() throws {
        let view = BoardView(geometry: geometry,
                             placement: Placement(fen: Core.startFEN(for: .miniXiangqi)))
        let size = try render(view, named: "start")
        #expect(size == geometry.blockSize)
    }

    @Test("Every marker renders together")
    func markers() throws {
        // One position carrying a selection, empty destinations, a capture, the
        // last move, and a general in check — the cases that have to coexist.
        let view = BoardView(
            geometry: geometry,
            placement: Placement(fen: "rcnkncr/p1ppp1p/7/2C4/7/P1PPP1P/R1NKNCR w - - 0 1"),
            selected: Square("c4"),
            destinations: [Square("c5")!, Square("c6")!, Square("b4")!, Square("c2")!],
            captures: [Square("c6")!],
            lastMove: Move(text: "c1c4"),
            checkedGeneral: Square("d7"))
        let size = try render(view, named: "markers")
        #expect(size == geometry.blockSize)
    }

    @Test("The board renders flipped, with the numeral strips following it")
    func flipped() throws {
        let view = BoardView(geometry: geometry,
                             placement: Placement(fen: Core.startFEN(for: .miniXiangqi)),
                             flipped: true)
        let size = try render(view, named: "flipped")
        #expect(size == geometry.blockSize)
    }
}

/// Frames from the middle of each motion, rendered stilled. Animation cannot
/// be screenshotted, but every one of its frames is a drawing of explicit
/// phases, so the interesting instants — a capture giving way under an
/// arriving disc, the board mid-flip, the dissolve that stands in for travel
/// under Reduce Motion, the check rings at the peak of their swell — can be
/// rendered and looked at rather than reasoned about.
@Suite("Motion frames", .retiringItsCores)
@MainActor
struct MotionFrameTests {
    let geometry = BoardGeometry(pitch: BoardGeometry.minimumPitch)

    private func game(playing line: [String]) throws -> Game {
        let game = try openGame(on: TestCores.fresh())
        try game.replay(line)
        return game
    }

    private func frame(_ game: Game, transit: Transit? = nil,
                       phases: BoardPhases, reduceMotion: Bool = false) -> some View {
        BoardCanvas(geometry: geometry,
                    placement: game.placement,
                    style: .traditional,
                    policy: MotionPolicy(reduceMotion: reduceMotion),
                    destinations: game.destinations,
                    captures: game.captures,
                    lastMove: game.lastMove,
                    checkedGeneral: game.checkedGeneral,
                    transit: transit,
                    phases: phases)
            .frame(width: geometry.coreSide, height: geometry.coreSide)
            .background(BoardStyle.traditional.boardSurface)
    }

    @Test("A capture mid-arrival: the taken disc gives way under the mover")
    func captureMidArrival() throws {
        let game = try game(playing: GameTests.captureLine)
        let transit = Transit(kind: .move,
                              move: Move(text: "d5d4")!,
                              piece: Piece(kind: .soldier, side: .black),
                              fading: (Piece(kind: .soldier, side: .red), Square("d4")!))
        let size = try render(frame(game, transit: transit,
                                    phases: BoardPhases(travel: 0.85, fade: 0.35)),
                              named: "capture-mid-arrival")
        #expect(size == CGSize(width: geometry.coreSide, height: geometry.coreSide))
    }

    @Test("The flip midway: one coordinated re-layout, characters upright")
    func flipMidway() throws {
        let game = try game(playing: ["b1b4", "a6a5"])
        let size = try render(frame(game, phases: BoardPhases(flip: 0.45)),
                              named: "flip-midway")
        #expect(size == CGSize(width: geometry.coreSide, height: geometry.coreSide))
    }

    @Test("Reduce Motion travels by dissolve: both ends, no movement")
    func reducedMotionDissolve() throws {
        let game = try game(playing: ["b1b4"])
        let transit = Transit(kind: .move,
                              move: Move(text: "b1b4")!,
                              piece: Piece(kind: .cannon, side: .red),
                              fading: nil)
        let size = try render(frame(game, transit: transit,
                                    phases: BoardPhases(travel: 0.5),
                                    reduceMotion: true),
                              named: "reduced-motion-dissolve")
        #expect(size == CGSize(width: geometry.coreSide, height: geometry.coreSide))
    }

    @Test("The check rings at the peak of their one-time swell")
    func checkPulsePeak() throws {
        let game = try game(playing: GameTests.checkLine)
        let size = try render(frame(game, phases: BoardPhases(check: 1)),
                              named: "check-pulse-peak")
        #expect(size == CGSize(width: geometry.coreSide, height: geometry.coreSide))
    }

    @Test("The markers strengthened: the illegal-tap answer at full emphasis")
    func markersStrengthened() throws {
        let game = try game(playing: ["d2d3", "d6d5", "d3d4"])
        game.tap(Square("d5")!)   // Black holds the soldier facing a capture
        let size = try render(frame(game, phases: BoardPhases(marker: 1,
                                                              lifts: SquarePhases(raised: game.selected))),
                              named: "markers-strengthened")
        #expect(size == CGSize(width: geometry.coreSide, height: geometry.coreSide))
    }
}
