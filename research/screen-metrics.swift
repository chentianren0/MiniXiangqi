// Workspace-only measurement: what usable point-space a macOS window actually gets
// on this machine, at the current display scaling and Dock configuration.
// Run: DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift discussion-drafts/screen-metrics.swift

import AppKit

let screens = NSScreen.screens
print("screens: \(screens.count)")

for (i, s) in screens.enumerated() {
    let f = s.frame            // full logical size in points
    let v = s.visibleFrame     // minus menu bar and Dock — what a window may occupy
    let scale = s.backingScaleFactor
    let name = s.localizedName

    print("""

    [\(i)] \(name)\(s == NSScreen.main ? "  (main)" : "")
      frame          : \(Int(f.width)) x \(Int(f.height)) pt   (backing scale \(scale)x -> \(Int(f.width * scale)) x \(Int(f.height * scale)) px)
      visibleFrame   : \(Int(v.width)) x \(Int(v.height)) pt   at origin (\(Int(v.origin.x)), \(Int(v.origin.y)))
      lost to top    : \(Int(f.height - (v.origin.y - f.origin.y) - v.height)) pt  (menu bar / notch inset)
      lost to bottom : \(Int(v.origin.y - f.origin.y)) pt  (Dock, if bottom)
      lost to left   : \(Int(v.origin.x - f.origin.x)) pt
      lost to right  : \(Int(f.width - (v.origin.x - f.origin.x) - v.width)) pt
      safeAreaInsets : top \(Int(s.safeAreaInsets.top)) bottom \(Int(s.safeAreaInsets.bottom)) left \(Int(s.safeAreaInsets.left)) right \(Int(s.safeAreaInsets.right))
    """)
}

// A window also loses its own title bar to the content view.
for style in [NSWindow.StyleMask([.titled, .closable, .miniaturizable, .resizable])] {
    let probe = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                         styleMask: style, backing: .buffered, defer: true)
    let full = probe.frame.height
    let content = probe.contentRect(forFrameRect: probe.frame).height
    print("\ntitle bar height: \(Int(full - content)) pt (standard titled window)")
}

if let v = NSScreen.main?.visibleFrame {
    print("""

    => usable CONTENT box for a standard window on the main screen:
       \(Int(v.width)) x \(Int(v.height - 28)) pt   (visibleFrame minus a 28 pt title bar)
    """)
}
