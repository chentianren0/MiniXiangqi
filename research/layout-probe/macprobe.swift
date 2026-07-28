import AppKit
import SwiftUI

// macOS chrome probe: title bar, toolbar, window chrome, screen budget.
// Run headless-ish: creates real NSWindows off-screen and measures their geometry.

func g(_ v: CGFloat) -> String { String(format: "%.2f", v) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

for s in NSScreen.screens {
    print("SCREEN frame=\(g(s.frame.width))x\(g(s.frame.height)) visibleFrame=\(g(s.visibleFrame.width))x\(g(s.visibleFrame.height)) backingScale=\(g(s.backingScaleFactor)) safeAreaTop=\(g(s.safeAreaInsets.top))")
    print("  menu bar + dock consumed: width \(g(s.frame.width - s.visibleFrame.width)), height \(g(s.frame.height - s.visibleFrame.height))")
}

func chrome(_ style: NSWindow.StyleMask, label: String, toolbar: NSToolbar? = nil,
            toolbarStyle: NSWindow.ToolbarStyle = .automatic) {
    let content = NSRect(x: 0, y: 0, width: 600, height: 400)
    let w = NSWindow(contentRect: content, styleMask: style, backing: .buffered, defer: false)
    if let tb = toolbar { w.toolbar = tb; w.toolbarStyle = toolbarStyle }
    let v = NSView(frame: content)
    w.contentView = v
    w.orderFront(nil)
    w.layoutIfNeeded()
    let frame = w.frame
    let cRect = w.contentRect(forFrameRect: frame)
    let cLayout = w.contentLayoutRect
    print("WINDOW[\(label)] frame=\(g(frame.width))x\(g(frame.height))")
    print("   contentRect=\(g(cRect.width))x\(g(cRect.height))  titlebar+chrome height=\(g(frame.height - cRect.height))  side chrome=\(g(frame.width - cRect.width))")
    print("   contentLayoutRect=\(g(cLayout.width))x\(g(cLayout.height))  above-content chrome (title bar + toolbar)=\(g(cRect.height - cLayout.height))")
    if let tb = w.toolbar {
        print("   toolbar visible=\(tb.isVisible) style=\(w.toolbarStyle.rawValue)")
    }
    w.orderOut(nil)
}

// Bare titled window: title bar only.
chrome([.titled, .closable, .miniaturizable, .resizable], label: "titled-only")

// Titled window with a toolbar, each toolbar style.
final class TB: NSObject, NSToolbarDelegate {
    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let i = NSToolbarItem(itemIdentifier: id)
        i.label = "悔棋"
        i.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        return i
    }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("undo")] }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("undo")] }
}
let d = TB()
for (name, style) in [("automatic", NSWindow.ToolbarStyle.automatic),
                      ("unified", .unified),
                      ("unifiedCompact", .unifiedCompact),
                      ("expanded", .expanded),
                      ("preference", .preference)] {
    let tb = NSToolbar(identifier: "probe-\(name)")
    tb.delegate = d
    chrome([.titled, .closable, .miniaturizable, .resizable], label: "titled+toolbar-\(name)", toolbar: tb, toolbarStyle: style)
}

// What the system will allow as a minimum: contentMinSize enforcement.
let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                  backing: .buffered, defer: false)
w2.contentMinSize = NSSize(width: 380, height: 500)
w2.orderFront(nil)
w2.setContentSize(NSSize(width: 100, height: 100))
print("MIN-CLAMP requested content 100x100 with contentMinSize 380x500 -> actual content \(g(w2.contentRect(forFrameRect: w2.frame).width))x\(g(w2.contentRect(forFrameRect: w2.frame).height))")
w2.orderOut(nil)

// SwiftUI element ideal sizes on macOS, for the panel-minimum derivation.
struct ControlRowMac: View {
    var body: some View {
        HStack(spacing: 12) { Button("悔棋") {}; Button("判和") {}; Button("认输") {} }
            .controlSize(.large).padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct TurnStatusMac: View {
    var body: some View { HStack { Text("轮到红方 · 将军"); Spacer() }.font(.body).padding(8) }
}
struct ResultCardMac: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("红方获胜").font(.title2).bold()
            Text("黑方被将死").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) { Button("悔棋") {}; Button("结束对局") {}.buttonStyle(.borderedProminent) }
        }.padding(16)
    }
}
struct MoveRowMac: View {
    var body: some View {
        HStack { Text("120.").monospacedDigit(); Text("炮二平五"); Spacer(minLength: 16); Text("马８进７") }
            .font(.body).padding(.vertical, 6).padding(.horizontal, 16)
    }
}
struct MetaMac: View {
    var body: some View { Text("人机对局 · 我执红 · 标准 · 进行中 · 可判和 · 42 步").font(.footnote).padding(.horizontal, 16) }
}
struct TransportMac: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill","arrow.up.arrow.down"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.controlSize(.large).padding(.vertical, 8).padding(.horizontal, 16)
    }
}

func mac(_ name: String, _ v: some View) {
    let hv = NSHostingView(rootView: AnyView(v))
    let ideal = hv.fittingSize
    hv.frame = NSRect(x: 0, y: 0, width: 400, height: 0)
    hv.layoutSubtreeIfNeeded()
    let at400 = hv.fittingSize
    print("MACELEM \(name) ideal=\(g(ideal.width))x\(g(ideal.height))  at400=\(g(at400.width))x\(g(at400.height))")
}
mac("turnStatus", TurnStatusMac())
mac("controlRow", ControlRowMac())
mac("resultCard", ResultCardMac())
mac("moveListRow", MoveRowMac())
mac("metadataLine", MetaMac())
mac("transportRow", TransportMac())

for style: NSFont.TextStyle in [.title2, .headline, .body, .subheadline, .footnote] {
    let ft = NSFont.preferredFont(forTextStyle: style)
    print("MACFONT[\(style.rawValue)] pointSize=\(g(ft.pointSize)) ascender+descender+leading=\(g(ft.ascender - ft.descender + ft.leading))")
}
print("@@MACDONE@@")
