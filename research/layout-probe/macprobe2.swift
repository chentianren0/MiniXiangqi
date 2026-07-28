import AppKit
import SwiftUI

// macOS probe 2 — the same element inventory as probe8.swift, measured on macOS,
// swept over every Dynamic Type step, plus window chrome for every toolbar style.

func g(_ v: CGFloat) -> String { String(format: "%.2f", v) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

for s in NSScreen.screens {
    print("SCREEN frame=\(g(s.frame.width))x\(g(s.frame.height)) visibleFrame=\(g(s.visibleFrame.width))x\(g(s.visibleFrame.height)) backingScale=\(g(s.backingScaleFactor))")
    print("  menu bar + Dock consumed: width \(g(s.frame.width - s.visibleFrame.width)) height \(g(s.frame.height - s.visibleFrame.height))")
}

// ---- window chrome, every toolbar style ----
final class TB: NSObject, NSToolbarDelegate {
    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let i = NSToolbarItem(itemIdentifier: id); i.label = "悔棋"
        i.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil); return i
    }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("undo")] }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("undo")] }
}
let d = TB()
func chrome(_ label: String, toolbar: NSToolbar? = nil, style: NSWindow.ToolbarStyle = .automatic) {
    let content = NSRect(x: 0, y: 0, width: 600, height: 400)
    let w = NSWindow(contentRect: content, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    if let tb = toolbar { w.toolbar = tb; w.toolbarStyle = style }
    w.contentView = NSView(frame: content)
    w.orderFront(nil); w.layoutIfNeeded()
    let cRect = w.contentRect(forFrameRect: w.frame)
    let cLayout = w.contentLayoutRect
    print("WINDOW[\(label)] contentRect=\(g(cRect.width))x\(g(cRect.height)) frameChromeH=\(g(w.frame.height - cRect.height)) sideChrome=\(g(w.frame.width - cRect.width)) aboveContentChrome=\(g(cRect.height - cLayout.height)) usableContentH=\(g(cLayout.height))")
    w.orderOut(nil)
}
chrome("titled-only")
for (n, s) in [("automatic", NSWindow.ToolbarStyle.automatic), ("unified", .unified), ("unifiedCompact", .unifiedCompact), ("expanded", .expanded), ("preference", .preference)] {
    let tb = NSToolbar(identifier: "p-\(n)"); tb.delegate = d
    chrome("toolbar-\(n)", toolbar: tb, style: s)
}

// ---- elements, identical definitions to probe8.swift ----
enum E {
    static let turnPrimary = "轮到红方"
    static let resultTitle = "红方获胜"
    static let resultReason = "黑方被将死"
    static let recordedLine = "已记录到历史"
    static let repetitionMsg = "局面已三次重复，可以和棋结束。"
    static let metaOngoing = "人机对局 · 我执红 · 轮到黑方 · 可判和 · 42 步"
    static let metaTerminal = "人机对局 · 我执黑 · 红方获胜 · 黑方被将死 · 137 步"
}
struct TurnStatus: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(E.turnPrimary).font(.body)
            Text("AI").font(.subheadline).foregroundStyle(.secondary)
            Text("将军").font(.subheadline).bold()
            Spacer(minLength: 0)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ControlRow: View {
    var body: some View {
        HStack(spacing: 12) { Button("悔棋") {}; Button("判和") {}; Button("认输") {} }
            .buttonStyle(.bordered).controlSize(.large).padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ControlRowFree: View {
    var body: some View {
        HStack(spacing: 12) { Button("悔棋") {}; Button("判和") {}; Button("翻转棋盘") {} }
            .buttonStyle(.bordered).controlSize(.large).padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ResultCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.resultReason).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) { Button("悔棋") {}.buttonStyle(.bordered); Button("结束对局") {}.buttonStyle(.borderedProminent) }
        }.padding(16)
    }
}
struct ResultCardRecorded: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.recordedLine).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) { Button("回放") {}.buttonStyle(.bordered); Button("完成") {}.buttonStyle(.borderedProminent) }
        }.padding(16)
    }
}
struct Repetition: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.repetitionMsg).font(.body)
            HStack(spacing: 12) { Button("继续对局") {}.buttonStyle(.bordered); Button("以和棋结束") {}.buttonStyle(.borderedProminent) }
        }.padding(16)
    }
}
struct Transport5: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.buttonStyle(.bordered).controlSize(.large).padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct Transport6: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill","arrow.up.arrow.down"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.buttonStyle(.bordered).controlSize(.large).padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct Transport7: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill","arrow.up.arrow.down","list.bullet"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.buttonStyle(.bordered).controlSize(.large).padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct TransportPlusSpeed: View {
    var body: some View {
        VStack(spacing: 8) {
            Transport6()
            Picker("", selection: .constant(1)) { Text("0.5×").tag(0); Text("1×").tag(1); Text("2×").tag(2) }
                .pickerStyle(.segmented).padding(.horizontal, 16)
        }
    }
}
struct MoveRow: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("120.").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            Text("炮二平五").padding(.leading, 12)
            Spacer(minLength: 16)
            Text("马８进７")
        }.font(.body).padding(.vertical, 6).padding(.horizontal, 16)
    }
}
struct MetaTerminal: View {
    var body: some View { Text(E.metaTerminal).font(.footnote).lineLimit(1).padding(.horizontal, 16) }
}
struct MetaOngoing: View {
    var body: some View { Text(E.metaOngoing).font(.footnote).lineLimit(1).padding(.horizontal, 16) }
}
struct PreStartAI: View {
    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: .constant(0)) { Text("我先手").tag(0); Text("AI 先手").tag(1); Text("随机").tag(2) }.pickerStyle(.segmented)
            Picker("", selection: .constant(1)) { Text("快速").tag(0); Text("标准").tag(1); Text("深思").tag(2) }.pickerStyle(.segmented)
            Button("开始对局") {}.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(16)
    }
}

let WIDTHS: [CGFloat] = [264, 280, 308, 320, 328, 343, 359, 375, 388, 398, 404, 424, 686, 712, 720]

func measure(_ name: String, _ v: some View, _ dts: DynamicTypeSize, _ label: String) {
    let hv = NSHostingView(rootView: AnyView(v.dynamicTypeSize(dts)))
    let ideal = hv.fittingSize
    var s = "MACELEM[\(label)] \(name) idealW=\(g(ideal.width)) idealH=\(g(ideal.height))"
    for w in WIDTHS {
        let hv2 = NSHostingView(rootView: AnyView(v.dynamicTypeSize(dts)))
        hv2.frame = NSRect(x: 0, y: 0, width: w, height: 100000)
        hv2.layoutSubtreeIfNeeded()
        let h = hv2.fittingSize.height
        s += " h@\(Int(w))=\(g(h))"
    }
    print(s)
}

let SIZES: [(DynamicTypeSize, String)] = [
    (.xSmall, "xS"), (.small, "S"), (.medium, "M"), (.large, "L"), (.xLarge, "xL"),
    (.xxLarge, "xxL"), (.xxxLarge, "xxxL"), (.accessibility1, "AX1"), (.accessibility2, "AX2"),
    (.accessibility3, "AX3"), (.accessibility4, "AX4"), (.accessibility5, "AX5"),
]
for (dts, label) in SIZES {
    measure("turnStatus", TurnStatus(), dts, label)
    measure("controlRowAI", ControlRow(), dts, label)
    measure("controlRowFree", ControlRowFree(), dts, label)
    measure("resultCard", ResultCard(), dts, label)
    measure("resultCardRecorded", ResultCardRecorded(), dts, label)
    measure("repetitionNotice", Repetition(), dts, label)
    measure("transport5", Transport5(), dts, label)
    measure("transport6", Transport6(), dts, label)
    measure("transport7", Transport7(), dts, label)
    measure("transportPlusSpeed", TransportPlusSpeed(), dts, label)
    measure("moveListRow", MoveRow(), dts, label)
    measure("metaOngoing", MetaOngoing(), dts, label)
    measure("metaTerminal", MetaTerminal(), dts, label)
    measure("preStartAI", PreStartAI(), dts, label)
    print("---")
}
print("@@MACDONE2@@")
