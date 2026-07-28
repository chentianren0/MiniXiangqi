// The contrast requirements the accepted design states, measured rather than
// asserted in a comment.
//
// docs/interaction-design.md fixes ratios, not colours: the symbol at 4.5:1
// against its own disc face, the disc's boundary at 3:1 against the board
// surface, marker active ink at 4.5:1 and record ink at 3:1 against the board
// surface, the grid at 3:1. A style whose colours are re-tuned has to keep
// satisfying them, and this is what notices when it stops.

import SwiftUI
import Testing
@testable import MiniXiangqi

/// WCAG relative luminance and contrast, over the style's own sRGB components.
private func luminance(_ color: Color) -> Double {
    let components = NSColor(color).usingColorSpace(.sRGB)!
    func linear(_ channel: CGFloat) -> Double {
        let value = Double(channel)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(components.redComponent)
        + 0.7152 * linear(components.greenComponent)
        + 0.0722 * linear(components.blueComponent)
}

private func contrast(_ a: Color, _ b: Color) -> Double {
    let (first, second) = (luminance(a), luminance(b))
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
}

@Suite("Traditional style contrast")
@MainActor
struct BoardStyleTests {
    var style: BoardStyle { .traditional }

    @Test("The grid reaches 3:1 against the board surface")
    func gridContrast() {
        #expect(contrast(style.grid, style.boardSurface) >= 3.0)
    }

    @Test("Each disc boundary reaches 3:1 against the board surface", arguments: [Side.red, .black])
    func discEdgeContrast(side: Side) {
        #expect(contrast(style.discEdge(side), style.boardSurface) >= 3.0)
    }

    @Test("Each symbol reaches 4.5:1 against its own disc face", arguments: [Side.red, .black])
    func symbolContrast(side: Side) {
        #expect(contrast(style.symbol(side), style.discFace) >= 4.5)
    }

    @Test("Active ink reaches 4.5:1 against the board surface")
    func activeInkContrast() {
        #expect(contrast(style.activeInk, style.boardSurface) >= 4.5)
    }

    @Test("Record ink reaches 3:1 against the board surface")
    func recordInkContrast() {
        #expect(contrast(style.recordInk, style.boardSurface) >= 3.0)
    }

    @Test("A style's decoration stays inside the band markers are kept out of")
    func decorationClearsTheMarkerBand() {
        let geometry = BoardGeometry(pitch: BoardGeometry.minimumPitch)
        for side in [Side.red, .black] {
            let stroke = style.discEdgeStroke(side) * geometry.pitch
            #expect(geometry.decorationExtent(edgeStroke: stroke)
                    <= geometry.styleDecorationLimit)
        }
    }
}
