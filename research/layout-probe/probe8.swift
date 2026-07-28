import UIKit
import SwiftUI

// Probe 8 — the full constraint-table measurement.
// Measures, on one device in one orientation:
//   A. screen bounds, scale, window safe-area insets
//   B. the adaptive navigation container's cost, at EVERY Dynamic Type step
//   C. inline and large navigation-bar heights, at every Dynamic Type step
//   D. every accepted-copy element's height and ideal width, at every Dynamic Type step,
//      at the widths that matter
//   E. the tab container's cost at COMPACT horizontal size class in a 360 pt-wide container
//      (the windowed-iPad case that layout-budget.md could not measure)
//   F. system alert size (insufficient-memory notice) at every Dynamic Type step

func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
var OUT = ""
func r(_ s: String) { OUT += s + "\n"; print(s) }
func flush() {
    let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? OUT.write(to: d.appendingPathComponent("probe8.txt"), atomically: true, encoding: .utf8)
}

let SIZES: [(DynamicTypeSize, String)] = [
    (.xSmall, "xS"), (.small, "S"), (.medium, "M"), (.large, "L"),
    (.xLarge, "xL"), (.xxLarge, "xxL"), (.xxxLarge, "xxxL"),
    (.accessibility1, "AX1"), (.accessibility2, "AX2"), (.accessibility3, "AX3"),
    (.accessibility4, "AX4"), (.accessibility5, "AX5"),
]
let UICT: [(UIContentSizeCategory, String)] = [
    (.extraSmall, "xS"), (.small, "S"), (.medium, "M"), (.large, "L"),
    (.extraLarge, "xL"), (.extraExtraLarge, "xxL"), (.extraExtraExtraLarge, "xxxL"),
    (.accessibilityMedium, "AX1"), (.accessibilityLarge, "AX2"),
    (.accessibilityExtraLarge, "AX3"), (.accessibilityExtraExtraLarge, "AX4"),
    (.accessibilityExtraExtraExtraLarge, "AX5"),
]

// ---------- Accepted copy, verbatim from docs/interaction-design.md on main ----------
enum E {
    static let turnPrimary = "轮到红方"
    static let resultTitle = "红方获胜"
    static let resultReason = "黑方被将死"
    static let recordedLine = "已记录到历史"
    static let repetitionMsg = "局面已三次重复，可以和棋结束。"
    static let metaOngoing = "人机对局 · 我执红 · 轮到黑方 · 可判和 · 42 步"
    static let metaTerminal = "人机对局 · 我执黑 · 红方获胜 · 黑方被将死 · 137 步"
    static let memTitle = "无法启动 AI 对手"
    static let memMsg = "当前可用内存不足。请尝试关闭一些其他 App，然后重试。"
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
            .buttonStyle(.bordered).controlSize(.large)
            .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ControlRowAI: View {   // human-vs-AI: 悔棋 判和 认输 (same three)
    var body: some View { ControlRow() }
}
struct ControlRowFree: View { // Free Play: 悔棋 判和 翻转棋盘
    var body: some View {
        HStack(spacing: 12) { Button("悔棋") {}; Button("判和") {}; Button("翻转棋盘") {} }
            .buttonStyle(.bordered).controlSize(.large)
            .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ResultCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.resultReason).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("悔棋") {}.buttonStyle(.bordered)
                Button("结束对局") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
struct ResultCardRecorded: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.recordedLine).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("回放") {}.buttonStyle(.bordered)
                Button("完成") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
struct Repetition: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.repetitionMsg).font(.body)
            HStack(spacing: 12) {
                Button("继续对局") {}.buttonStyle(.bordered)
                Button("以和棋结束") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
struct Transport5: View {   // the five accepted transport controls only
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.buttonStyle(.bordered).controlSize(.large)
         .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct Transport6: View {   // + 翻转棋盘
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill","arrow.up.arrow.down"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.buttonStyle(.bordered).controlSize(.large)
         .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct Transport7: View {   // + the move-list affordance
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill","arrow.up.arrow.down","list.bullet"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.buttonStyle(.bordered).controlSize(.large)
         .padding(.vertical, 8).padding(.horizontal, 16)
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
struct MetaOngoing: View {
    var body: some View { Text(E.metaOngoing).font(.footnote).lineLimit(1).padding(.horizontal, 16) }
}
struct MetaTerminal: View {
    var body: some View { Text(E.metaTerminal).font(.footnote).lineLimit(1).padding(.horizontal, 16) }
}
struct PreStartControls: View {   // human-vs-AI pre-start: side choice, difficulty, 开始对局
    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: .constant(0)) { Text("我先手").tag(0); Text("AI 先手").tag(1); Text("随机").tag(2) }
                .pickerStyle(.segmented)
            Picker("", selection: .constant(1)) { Text("快速").tag(0); Text("标准").tag(1); Text("深思").tag(2) }
                .pickerStyle(.segmented)
            Button("开始对局") {}.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(16)
    }
}
struct PreStartFree: View {   // Free Play pre-start: explanatory line + 开始对局
    var body: some View {
        VStack(spacing: 12) {
            Text("一人执红黑双方，红方先行").font(.subheadline).foregroundStyle(.secondary)
            Button("开始对局") {}.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(16)
    }
}
struct DrawClaimAffordance: View {  // the retained 可判和 affordance, if it were its own element
    var body: some View {
        HStack { Button("可判和") {}.buttonStyle(.bordered); Spacer(minLength: 0) }
            .padding(.vertical, 8).padding(.horizontal, 16)
    }
}

let WIDTHS: [CGFloat] = [264, 280, 308, 320, 328, 343, 359, 375, 388, 398, 404, 424, 686, 712, 720]

func measure(_ name: String, _ v: some View, _ dts: DynamicTypeSize, _ label: String) {
    let hc = UIHostingController(rootView: AnyView(v.dynamicTypeSize(dts)))
    let inf = CGFloat.greatestFiniteMagnitude
    let ideal = hc.sizeThatFits(in: CGSize(width: inf, height: inf))
    var s = "E[\(label)] \(name) idealW=\(f(ideal.width)) idealH=\(f(ideal.height))"
    for w in WIDTHS {
        let h = hc.sizeThatFits(in: CGSize(width: w, height: inf)).height
        s += " h@\(Int(w))=\(f(h))"
    }
    r(s)
}

// ---------- chrome measurement ----------
final class Probe: UIViewController {
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .systemBackground }
}

func chrome(_ ws: UIWindowScene, _ window: UIWindow, _ cat: UIContentSizeCategory, _ label: String) {
    // UIKit tab + nav container, measured live.
    let inner = Probe()
    let nav = UINavigationController(rootViewController: inner)
    inner.title = "对局"
    let tabs = UITabBarController()
    tabs.viewControllers = [nav]
    tabs.tabBar.items?.first?.title = "对局"

    let host = UIWindow(windowScene: ws)
    host.rootViewController = tabs
    host.isHidden = false
    host.frame = ws.screen.bounds
    host.layoutIfNeeded()
    inner.view.layoutIfNeeded()

    let sa = window.safeAreaInsets
    let innerSA = inner.view.safeAreaInsets
    let navH = nav.navigationBar.frame.height
    let tabH = tabs.tabBar.frame.height
    let contentH = inner.view.bounds.height - innerSA.top - innerSA.bottom
    let contentW = inner.view.bounds.width - innerSA.left - innerSA.right
    r("CHROME[\(label)] winSafe=(t\(f(sa.top)) b\(f(sa.bottom)) l\(f(sa.left)) r\(f(sa.right))) " +
      "navBarH=\(f(navH)) tabBarH=\(f(tabH)) " +
      "innerSafe=(t\(f(innerSA.top)) b\(f(innerSA.bottom)) l\(f(innerSA.left)) r\(f(innerSA.right))) " +
      "content=\(f(contentW))x\(f(contentH)) viewBounds=\(f(inner.view.bounds.width))x\(f(inner.view.bounds.height))")

    // large-title variant
    nav.navigationBar.prefersLargeTitles = true
    host.layoutIfNeeded(); inner.view.layoutIfNeeded()
    r("CHROME[\(label)] largeTitle navBarH=\(f(nav.navigationBar.frame.height)) innerSafeTop=\(f(inner.view.safeAreaInsets.top))")

    // no nav bar at all
    nav.setNavigationBarHidden(true, animated: false)
    host.layoutIfNeeded(); inner.view.layoutIfNeeded()
    let sa2 = inner.view.safeAreaInsets
    r("CHROME[\(label)] noNavBar innerSafe=(t\(f(sa2.top)) b\(f(sa2.bottom))) contentH=\(f(inner.view.bounds.height - sa2.top - sa2.bottom))")

    // tab container alone (no navigation controller)
    let bare = Probe()
    let tabs2 = UITabBarController()
    tabs2.viewControllers = [bare]
    let host2 = UIWindow(windowScene: ws)
    host2.rootViewController = tabs2; host2.isHidden = false; host2.frame = ws.screen.bounds
    host2.layoutIfNeeded(); bare.view.layoutIfNeeded()
    let sa3 = bare.view.safeAreaInsets
    r("CHROME[\(label)] tabOnly innerSafe=(t\(f(sa3.top)) b\(f(sa3.bottom)) l\(f(sa3.left)) r\(f(sa3.right))) contentH=\(f(bare.view.bounds.height - sa3.top - sa3.bottom)) contentW=\(f(bare.view.bounds.width - sa3.left - sa3.right)) layoutMargins=(l\(f(bare.view.layoutMargins.left)) r\(f(bare.view.layoutMargins.right)))")
    host2.isHidden = true

    // COMPACT horizontal size class in a 360 pt-wide container — the windowed-iPad case
    if window.traitCollection.userInterfaceIdiom == .pad {
        for w: CGFloat in [320, 360, 375, 420, 500, 600, 700] {
            let c = Probe()
            let n2 = UINavigationController(rootViewController: c)
            c.title = "对局"
            let t2 = UITabBarController()
            t2.viewControllers = [n2]
            t2.view.frame = CGRect(x: 0, y: 0, width: w, height: 700)
            t2.traitOverrides.horizontalSizeClass = .compact
            let holder = Probe()
            holder.addChild(t2); holder.view.addSubview(t2.view); t2.didMove(toParent: holder)
            holder.view.frame = CGRect(x: 0, y: 0, width: w, height: 700)
            holder.view.layoutIfNeeded(); t2.view.layoutIfNeeded(); c.view.layoutIfNeeded()
            r("COMPACT[\(label)] w=\(Int(w)) tabBarH=\(f(t2.tabBar.frame.height)) navBarH=\(f(n2.navigationBar.frame.height)) innerSafe=(t\(f(c.view.safeAreaInsets.top)) b\(f(c.view.safeAreaInsets.bottom))) hSizeClass=\(t2.traitCollection.horizontalSizeClass.rawValue)")
        }
    }
    host.isHidden = true
}

// ---------- SwiftUI sidebarAdaptable container ----------
struct SUIRoot: View {
    var body: some View {
        TabView {
            Tab("对局", systemImage: "square.grid.3x3") {
                GeometryReader { g in
                    Color.clear
                        .onAppear {
                            r("SWIFTUI content=\(f(g.size.width))x\(f(g.size.height)) safeArea=(t\(f(g.safeAreaInsets.top)) b\(f(g.safeAreaInsets.bottom)) l\(f(g.safeAreaInsets.leading)) r\(f(g.safeAreaInsets.trailing)))")
                        }
                }
            }
            Tab("历史", systemImage: "clock") { Color.clear }
            Tab("设置", systemImage: "gear") { Color.clear }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

final class AD: UIResponder, UIApplicationDelegate {
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: s.role); c.delegateClass = SD.self; return c
    }
}

final class SD: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.rootViewController = UIHostingController(rootView: SUIRoot())
        w.makeKeyAndVisible(); window = w

        let idiom = w.traitCollection.userInterfaceIdiom == .pad ? "pad" : "phone"
        let ori = ws.interfaceOrientation
        let oriName: String
        switch ori {
        case .portrait: oriName = "portrait"
        case .portraitUpsideDown: oriName = "portraitUpsideDown"
        case .landscapeLeft: oriName = "landscapeLeft"
        case .landscapeRight: oriName = "landscapeRight"
        default: oriName = "unknown"
        }
        r("DEVICE idiom=\(idiom) model=\(UIDevice.current.model) os=\(UIDevice.current.systemVersion) orientation=\(oriName)")
        r("SCREEN bounds=\(f(ws.screen.bounds.width))x\(f(ws.screen.bounds.height)) scale=\(f(ws.screen.scale)) nativeScale=\(f(ws.screen.nativeScale)) nativeBounds=\(f(ws.screen.nativeBounds.width))x\(f(ws.screen.nativeBounds.height))")
        r("SCENE effectiveGeometry=\(f(ws.effectiveGeometry.coordinateSpace.bounds.width))x\(f(ws.effectiveGeometry.coordinateSpace.bounds.height))")
        if let sr = ws.sizeRestrictions {
            r("SIZERESTRICTIONS available min=\(f(sr.minimumSize.width))x\(f(sr.minimumSize.height)) max=\(f(sr.maximumSize.width))x\(f(sr.maximumSize.height)) allowsFullScreen=\(sr.allowsFullScreen)")
        } else {
            r("SIZERESTRICTIONS nil")
        }
        r("TRAITS hSize=\(w.traitCollection.horizontalSizeClass.rawValue) vSize=\(w.traitCollection.verticalSizeClass.rawValue)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            r("WINDOW safeArea=(t\(f(w.safeAreaInsets.top)) b\(f(w.safeAreaInsets.bottom)) l\(f(w.safeAreaInsets.left)) r\(f(w.safeAreaInsets.right)))")

            // chrome at every Dynamic Type step
            for (cat, label) in UICT {
                w.traitOverrides.preferredContentSizeCategory = cat
                w.layoutIfNeeded()
                chrome(ws, w, cat, label)
            }
            w.traitOverrides.preferredContentSizeCategory = .large

            // elements at every Dynamic Type step
            for (dts, label) in SIZES {
                measure("turnStatus", TurnStatus(), dts, label)
                measure("controlRowAI", ControlRowAI(), dts, label)
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
                measure("preStartAI", PreStartControls(), dts, label)
                measure("preStartFree", PreStartFree(), dts, label)
                measure("drawClaim", DrawClaimAffordance(), dts, label)
                r("---")
            }
            r("@@DONE8@@"); flush()
        }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AD.self))
