// Checks which font the Apple system-font cascade actually uses for each Xiangqi
// piece character, and whether any glyph is missing. Run with the project toolchain:
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
//     xcrun swift discussion-drafts/font-glyph-check.swift
import AppKit
import CoreText
import CoreGraphics
import Foundation

let candidates: [(String, String)] = [
    ("帥", "red general (traditional)"),
    ("帅", "red general (simplified)"),
    ("將", "black general (traditional)"),
    ("将", "black general (simplified)"),
    ("俥", "red chariot"),
    ("車", "black chariot (traditional)"),
    ("车", "black chariot (simplified)"),
    ("傌", "red horse"),
    ("馬", "black horse (traditional)"),
    ("马", "black horse (simplified)"),
    ("炮", "red cannon"),
    ("砲", "black cannon (stone radical)"),
    ("包", "black cannon (pychess form)"),
    ("兵", "red soldier"),
    ("卒", "black soldier"),
]

func resolved(_ text: String, base: CTFont) -> (name: String, missing: Bool, advance: Double) {
    let attrs = [kCTFontAttributeName: base] as CFDictionary
    guard let astr = CFAttributedStringCreate(nil, text as CFString, attrs) else {
        return ("<none>", true, 0)
    }
    let line = CTLineCreateWithAttributedString(astr)
    guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], let run = runs.first,
          let usedAny = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String]
    else { return ("<none>", true, 0) }

    let used = usedAny as! CTFont
    let name = CTFontCopyPostScriptName(used) as String

    let utf16 = Array(text.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
    let ok = CTFontGetGlyphsForCharacters(used, utf16, &glyphs, utf16.count)
    let missing = !ok || glyphs.contains(0)

    var advances = [CGSize](repeating: .zero, count: glyphs.count)
    CTFontGetAdvancesForGlyphs(used, .horizontal, glyphs, &advances, glyphs.count)
    let advance = advances.first.map { Double($0.width) } ?? 0

    return (name, missing, advance)
}

// Use the real system font at each weight. Building a descriptor from a weight trait
// alone resolves to Helvetica and silently drops the weight, which tests nothing.
let weights: [(String, NSFont.Weight)] = [
    ("regular", .regular), ("semibold", .semibold), ("bold", .bold), ("heavy", .heavy),
]
for (label, weight) in weights {
    let base = NSFont.systemFont(ofSize: 34.0, weight: weight) as CTFont
    print("=== weight \(label) — base: \(CTFontCopyPostScriptName(base) as String) ===")
    var fonts = Set<String>()
    var advances = Set<String>()
    for (ch, note) in candidates {
        let r = resolved(ch, base: base)
        fonts.insert(r.name)
        advances.insert(String(format: "%.2f", r.advance))
        let flag = r.missing ? "MISSING" : "ok"
        print("  \(ch)  \(flag.padding(toLength: 8, withPad: " ", startingAt: 0)) adv=\(String(format: "%6.2f", r.advance))  \(r.name)   [\(note)]")
    }
    print("  fonts used: \(fonts.sorted().joined(separator: ", "))")
    print("  distinct advances: \(advances.sorted().joined(separator: ", "))\n")
}
