import UIKit
import SwiftUI

// Layout chrome + element probe for Mini Xiangqi.
// Everything printed here is measured on a booted simulator at the runtime named in the output.

func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }

var OUT = ""
func p(_ s: String) { OUT += s + "\n"; Swift.print(s) }
func flushOut() {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? OUT.write(to: dir.appendingPathComponent("probe.txt"), atomically: true, encoding: .utf8)
}

// MARK: - The elements the contract names

struct TurnStatus: View {
    var body: some View {
        HStack { Text("轮到红方 · 将军"); Spacer() }
            .font(.body)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
    }
}

struct ControlRow: View {   // 悔棋 · 判和 · 认输
    var body: some View {
        HStack(spacing: 12) {
            Button("悔棋") {}
            Button("判和") {}
            Button("认输") {}
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }
}

struct ResultCard: View {   // title + reason line + 悔棋 / 结束对局
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("红方获胜").font(.title2).bold()
            Text("黑方被将死").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("悔棋") {}.buttonStyle(.bordered)
                Button("结束对局") {}.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}

struct RepetitionNotice: View {  // copy per interaction-design.md :342
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("三次重复局面").font(.headline)
            Text("你可以判和，也可以继续对局。").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("继续对局") {}.buttonStyle(.bordered)
                Button("判和") {}.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}

struct TransportRow: View {  // jump-start, back, play/pause, forward, jump-end, 翻转棋盘
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill", "backward.fill", "play.fill", "forward.fill", "forward.end.fill"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
            Button { } label: { Image(systemName: "arrow.up.arrow.down") }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }
}

struct MoveListRow: View {
    var body: some View {
        HStack {
            Text("120.").monospacedDigit().foregroundStyle(.secondary)
            Text("炮二平五")
            Spacer(minLength: 16)
            Text("马８进７")
        }
        .font(.body)
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
    }
}

struct MetadataLine: View {
    var body: some View {
        Text("人机对局 · 我执红 · 标准 · 进行中 · 可判和 · 42 步")
            .font(.footnote)
            .padding(.horizontal, 16)
    }
}

struct AutoplaySpeed: View {
    var body: some View {
        Picker("", selection: .constant(1)) {
            Text("0.5×").tag(0); Text("1×").tag(1); Text("2×").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }
}

// A whole stacked panel column, to derive its minimum width from its contents.
struct PanelColumn: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TurnStatus()
            MetadataLine()
            MoveListRow()
            ControlRow()
        }
    }
}

// MARK: - Measuring

func measure(_ name: String, _ v: some View, widths: [CGFloat], cat: UIContentSizeCategory) {
    let dts: DynamicTypeSize = (cat == .large) ? .large : .accessibility5
    let hc = UIHostingController(rootView: AnyView(v.dynamicTypeSize(dts)))
    hc.traitOverrides.preferredContentSizeCategory = cat
    hc.view.traitOverrides.preferredContentSizeCategory = cat
    hc.view.backgroundColor = .clear
    hc.view.setNeedsLayout(); hc.view.layoutIfNeeded()
    let ideal = hc.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                           height: CGFloat.greatestFiniteMagnitude))
    var line = "ELEM \(name) ideal=\(f(ideal.width))x\(f(ideal.height))"
    for w in widths {
        let s = hc.sizeThatFits(in: CGSize(width: w, height: CGFloat.greatestFiniteMagnitude))
        line += "  h@\(Int(w))=\(f(s.height))"
    }
    p(line)
}

final class ProbeVC: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "对局"
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: s.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var tabBar: UITabBarController?
    var nav: UINavigationController?
    var probe: ProbeVC?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        let vc = ProbeVC()
        let n = UINavigationController(rootViewController: vc)
        let t = UITabBarController()
        let vc2 = ProbeVC(); vc2.title = "历史"
        vc2.tabBarItem = UITabBarItem(title: "历史", image: UIImage(systemName: "clock"), tag: 1)
        let vc3 = ProbeVC(); vc3.title = "设置"
        vc3.tabBarItem = UITabBarItem(title: "设置", image: UIImage(systemName: "gearshape"), tag: 2)
        vc.tabBarItem = UITabBarItem(title: "对局", image: UIImage(systemName: "square.grid.3x3"), tag: 0)
        t.viewControllers = [n,
                             UINavigationController(rootViewController: vc2),
                             UINavigationController(rootViewController: vc3)]
        w.rootViewController = t
        w.makeKeyAndVisible()
        self.window = w; self.tabBar = t; self.nav = n; self.probe = vc
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.report() }
    }

    func dump(_ tag: String) {
        guard let w = window, let t = tabBar, let n = nav, let pv = probe else { return }
        w.layoutIfNeeded(); t.view.layoutIfNeeded(); n.view.layoutIfNeeded(); pv.view.layoutIfNeeded()
        let scene = w.windowScene
        let screen = scene?.screen.bounds ?? .zero
        let cat = w.traitCollection.preferredContentSizeCategory
        let idiom = w.traitCollection.userInterfaceIdiom == .pad ? "pad" : "phone"

        p("### \(tag)")
        p("idiom=\(idiom) contentSizeCategory=\(cat.rawValue) osVersion=\(UIDevice.current.systemVersion) model=\(UIDevice.current.model)")
        let sc = scene?.screen
        p("screen.bounds=\(f(screen.width))x\(f(screen.height)) scale=\(f(sc?.scale ?? 0)) nativeScale=\(f(sc?.nativeScale ?? 0)) nativeBounds=\(f(sc?.nativeBounds.width ?? 0))x\(f(sc?.nativeBounds.height ?? 0))")
        p("window.safeAreaInsets top=\(f(w.safeAreaInsets.top)) bottom=\(f(w.safeAreaInsets.bottom)) left=\(f(w.safeAreaInsets.left)) right=\(f(w.safeAreaInsets.right))")
        p("tabBar.frame=\(f(t.tabBar.frame.width))x\(f(t.tabBar.frame.height)) origin=(\(f(t.tabBar.frame.origin.x)),\(f(t.tabBar.frame.origin.y)))")
        p("navBar.frame.height=\(f(n.navigationBar.frame.height)) largeTitles=\(n.navigationBar.prefersLargeTitles) hidden=\(n.isNavigationBarHidden)")
        p("probeView.frame=\(f(pv.view.frame.width))x\(f(pv.view.frame.height))")
        p("probeView.safeAreaInsets top=\(f(pv.view.safeAreaInsets.top)) bottom=\(f(pv.view.safeAreaInsets.bottom)) left=\(f(pv.view.safeAreaInsets.left)) right=\(f(pv.view.safeAreaInsets.right))")
        let usableH = pv.view.frame.height - pv.view.safeAreaInsets.top - pv.view.safeAreaInsets.bottom
        let usableW = pv.view.frame.width - pv.view.safeAreaInsets.left - pv.view.safeAreaInsets.right
        p("USABLE=\(f(usableW))x\(f(usableH))  TOTAL_VERTICAL_CHROME=\(f(screen.height - usableH))")
        p("layoutMargins l=\(f(pv.view.layoutMargins.left)) r=\(f(pv.view.layoutMargins.right))")

        let widths: [CGFloat] = [328, 343, 360, 375, 400, 500]
        measure("turnStatus", TurnStatus(), widths: widths, cat: cat)
        measure("controlRow", ControlRow(), widths: widths, cat: cat)
        measure("resultCard", ResultCard(), widths: widths, cat: cat)
        measure("repetitionNotice", RepetitionNotice(), widths: widths, cat: cat)
        measure("transportRow", TransportRow(), widths: widths, cat: cat)
        measure("moveListRow", MoveListRow(), widths: widths, cat: cat)
        measure("metadataLine", MetadataLine(), widths: widths, cat: cat)
        measure("autoplaySpeed", AutoplaySpeed(), widths: widths, cat: cat)
        measure("panelColumn", PanelColumn(), widths: widths, cat: cat)

        for style: UIFont.TextStyle in [.title2, .headline, .body, .subheadline, .footnote] {
            let tc = UITraitCollection(preferredContentSizeCategory: cat)
            let fnt = UIFont.preferredFont(forTextStyle: style, compatibleWith: tc)
            p("font[\(style.rawValue)] pointSize=\(f(fnt.pointSize)) lineHeight=\(f(fnt.lineHeight))")
        }
        p("### end \(tag)")
    }

    func report() {
        dump("A-DEFAULT-navbar-inline")
        window?.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.dump("B-AX5")
            self.window?.traitOverrides.preferredContentSizeCategory = .large
            self.nav?.setNavigationBarHidden(true, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.dump("C-DEFAULT-no-navbar")
                self.window?.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.dump("D-AX5-no-navbar")
                    self.window?.traitOverrides.preferredContentSizeCategory = .large
                    self.nav?.setNavigationBarHidden(false, animated: false)
                    if let ws = self.window?.windowScene {
                        ws.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { e in
                            p("landscape request error: \(e)")
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.dump("E-LANDSCAPE-default")
                        p("@@PROBE-DONE@@")
                        flushOut()
                    }
                }
            }
        }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
