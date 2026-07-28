import UIKit
import SwiftUI

// Probe 9 — the three things probe8 could not settle:
//   A. chrome measured against the REAL window bounds in the REAL orientation
//      (probe8 used screen.bounds, which is portrait-fixed on iPad).
//   B. the width at which TabView(.sidebarAdaptable) flips from tab bar to SIDEBAR,
//      and what the sidebar costs horizontally.
//   C. safe-area insets in landscape.

func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
var OUT = ""
func r(_ s: String) { OUT += s + "\n"; print(s) }
func flush() {
    let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? OUT.write(to: d.appendingPathComponent("probe9.txt"), atomically: true, encoding: .utf8)
}

final class Probe: UIViewController {
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .systemBackground }
}

final class Box: ObservableObject { @Published var tag = "" }

struct Adaptive: View {
    let tag: String
    var body: some View {
        TabView {
            Tab("对局", systemImage: "square.grid.3x3") {
                GeometryReader { g in
                    Color.clear.onAppear {
                        r("ADAPT[\(tag)] content=\(f(g.size.width))x\(f(g.size.height)) insets=(t\(f(g.safeAreaInsets.top)) b\(f(g.safeAreaInsets.bottom)) lead\(f(g.safeAreaInsets.leading)) trail\(f(g.safeAreaInsets.trailing)))")
                    }
                }
            }
            Tab("历史", systemImage: "clock") { Color.clear }
            Tab("设置", systemImage: "gear") { Color.clear }
        }.tabViewStyle(.sidebarAdaptable)
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
    var holders: [UIWindow] = []
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.rootViewController = Probe()
        w.makeKeyAndVisible(); window = w

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let b = w.bounds
            let sa = w.safeAreaInsets
            let idiom = w.traitCollection.userInterfaceIdiom == .pad ? "pad" : "phone"
            r("WINBOUNDS idiom=\(idiom) bounds=\(f(b.width))x\(f(b.height)) safeArea=(t\(f(sa.top)) b\(f(sa.bottom)) l\(f(sa.left)) r\(f(sa.right))) screen=\(f(ws.screen.bounds.width))x\(f(ws.screen.bounds.height))")
            r("WINBOUNDS traits h=\(w.traitCollection.horizontalSizeClass.rawValue) v=\(w.traitCollection.verticalSizeClass.rawValue) layoutMargins=(l\(f(w.layoutMargins.left)) r\(f(w.layoutMargins.right)))")

            // A. UIKit chrome measured against the real window bounds.
            let inner = Probe(); inner.title = "对局"
            let nav = UINavigationController(rootViewController: inner)
            let tabs = UITabBarController(); tabs.viewControllers = [nav]
            let h1 = UIWindow(windowScene: ws); h1.frame = b
            h1.rootViewController = tabs; h1.isHidden = false
            h1.layoutIfNeeded(); inner.view.layoutIfNeeded()
            let isa = inner.view.safeAreaInsets
            r("UIKIT navBar+tab: navBarH=\(f(nav.navigationBar.frame.height)) tabBarH=\(f(tabs.tabBar.frame.height)) innerSafe=(t\(f(isa.top)) b\(f(isa.bottom)) l\(f(isa.left)) r\(f(isa.right))) content=\(f(inner.view.bounds.width - isa.left - isa.right))x\(f(inner.view.bounds.height - isa.top - isa.bottom))")
            nav.setNavigationBarHidden(true, animated: false)
            h1.layoutIfNeeded(); inner.view.layoutIfNeeded()
            let isa2 = inner.view.safeAreaInsets
            r("UIKIT tabOnly: innerSafe=(t\(f(isa2.top)) b\(f(isa2.bottom)) l\(f(isa2.left)) r\(f(isa2.right))) content=\(f(inner.view.bounds.width - isa2.left - isa2.right))x\(f(inner.view.bounds.height - isa2.top - isa2.bottom)) layoutMargins=(l\(f(inner.view.layoutMargins.left)) r\(f(inner.view.layoutMargins.right)))")
            h1.isHidden = true

            // B. the sidebar flip: host the adaptive container in real windows of many widths.
            let widths: [CGFloat] = [320, 360, 400, 440, 500, 560, 600, 640, 680, 700, 720, 744, 760, 780, 800, 820, 834, 900, 960, 1000, 1024, 1032, 1080, 1133, 1194, 1210, 1366, 1376]
            var delay = 0.0
            for cw in widths {
                guard cw <= max(ws.screen.bounds.width, ws.screen.bounds.height) else { continue }
                delay += 0.35
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let hw = UIWindow(windowScene: ws)
                    hw.frame = CGRect(x: 0, y: 0, width: cw, height: min(b.height, 900))
                    hw.rootViewController = UIHostingController(rootView: Adaptive(tag: "w\(Int(cw))"))
                    hw.isHidden = false
                    hw.layoutIfNeeded()
                    self.holders.append(hw)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 3.0) {
                r("@@DONE9@@"); flush()
            }
        }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AD.self))
