// Renders the board to a PNG so it can be looked at.
//
// Xcode's preview JIT does not run against this app's entitlements on the
// pinned toolchain, and a board nobody has rendered is exactly the kind of
// design a review cannot check. These write into `.snapshots/` at the
// repository root, which is ignored by git, and assert the render's size.

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
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        Issue.record("the board did not render")
        return .zero
    }
    try FileManager.default.createDirectory(at: snapshotDirectory,
                                            withIntermediateDirectories: true)
    let url = snapshotDirectory.appendingPathComponent("\(name).png")
    try png.write(to: url)
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
                             placement: Placement(fen: Core.startFEN))
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
                             placement: Placement(fen: Core.startFEN),
                             flipped: true)
        let size = try render(view, named: "flipped")
        #expect(size == geometry.blockSize)
    }
}
