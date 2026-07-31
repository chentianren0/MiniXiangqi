// The contrast requirements the accepted design states, measured rather than
// asserted in a comment.
//
// docs/interaction-design.md fixes ratios, not colours: the symbol at 4.5:1
// against its own disc face, the disc's boundary at 3:1 against the board
// surface, marker active ink at 4.5:1 and record ink at 3:1 against the board
// surface, the grid at 3:1. A style whose colours are re-tuned has to keep
// satisfying them, and this is what notices when it stops.

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import Testing
@testable import MiniXiangqi

/// The colour's sRGB components, asked of whichever platform colour type this
/// platform has. The ratios below are about the colours the app draws, so the
/// components are read out of the drawing framework rather than recomputed.
private func sRGB(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
    #if canImport(AppKit)
    let components = NSColor(color).usingColorSpace(.sRGB)!
    return (components.redComponent, components.greenComponent, components.blueComponent)
    #else
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue)
    #endif
}

/// WCAG relative luminance and contrast, over the style's own sRGB components.
private func luminance(_ color: Color) -> Double {
    let components = sRGB(color)
    func linear(_ channel: CGFloat) -> Double {
        let value = Double(channel)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(components.red)
        + 0.7152 * linear(components.green)
        + 0.0722 * linear(components.blue)
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

    @Test("A style's decoration stays inside the band markers are kept out of",
          arguments: [0.010, 0.028, 0.060, 0.100] as [CGFloat])
    func decorationClearsTheMarkerBand(strokeInPitches: CGFloat) {
        let geometry = BoardGeometry(pitch: BoardGeometry.minimumPitch)
        let stroke = strokeInPitches * geometry.pitch

        // The stroke is drawn inside the disc's own edge, so however heavy it
        // is it reaches no further than the disc — and never into the marker
        // band, which starts at 0.42 p.
        #expect(geometry.decorationExtent(edgeStroke: stroke) <= geometry.styleDecorationLimit)
        #expect(geometry.decorationExtent(edgeStroke: stroke) < geometry.markerInnerLimit)
        // …and it stays a stroke rather than collapsing through the centre.
        #expect(geometry.discEdgeRadius(stroke: stroke) > 0)
    }

    @Test("The styles in use satisfy that with room to spare", arguments: [Side.red, .black])
    func styleStrokesAreWithinTheLimit(side: Side) {
        let geometry = BoardGeometry(pitch: BoardGeometry.minimumPitch)
        let stroke = style.discEdgeStroke(side) * geometry.pitch
        #expect(geometry.decorationExtent(edgeStroke: stroke) <= geometry.styleDecorationLimit)
        #expect(geometry.discEdgeRadius(stroke: stroke) > geometry.symbolSize / 2)
    }
}
