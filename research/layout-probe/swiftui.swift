import UIKit
import SwiftUI

// Probe 2: measures the chrome of the adaptive navigation container the contract adopts
// (a sidebarAdaptable TabView), as seen from inside the Play destination's content.

func f2(_ v: CGFloat) -> String { String(format: "%.2f", v) }

var OUT2 = ""
func q(_ s: String) { OUT2 += s + "\n"; print(s) }
func flush2() {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? OUT2.write(to: dir.appendingPathComponent("probe2.txt"), atomically: true, encoding: .utf8)
}

var reported = Set<String>()

struct Reader: View {
    let tag: String
    var body: some View {
        GeometryReader { g in
            Color.clear.task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                let key = "\(tag)|\(f2(g.size.width))x\(f2(g.size.height))"
                if reported.contains(key) { return }
                reported.insert(key)
                q("CONTENT[\(tag)] size=\(f2(g.size.width))x\(f2(g.size.height)) safeArea t=\(f2(g.safeAreaInsets.top)) b=\(f2(g.safeAreaInsets.bottom)) l=\(f2(g.safeAreaInsets.leading)) r=\(f2(g.safeAreaInsets.trailing))")
            }
        }
    }
}

struct Root: View {
    @State private var sel = 0
    var body: some View {
        TabView(selection: $sel) {
            Tab("对局", systemImage: "square.grid.3x3", value: 0) {
                NavigationStack {
                    Reader(tag: "tab+navstack")
                        .navigationTitle("对局")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab("历史", systemImage: "clock", value: 1) {
                NavigationStack { Reader(tag: "history").navigationTitle("历史") }
            }
            Tab("设置", systemImage: "gearshape", value: 2) {
                NavigationStack { Reader(tag: "settings").navigationTitle("设置") }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

struct RootNoNav: View {
    @State private var sel = 0
    var body: some View {
        TabView(selection: $sel) {
            Tab("对局", systemImage: "square.grid.3x3", value: 0) { Reader(tag: "tab-only") }
            Tab("历史", systemImage: "clock", value: 1) { Color.clear }
            Tab("设置", systemImage: "gearshape", value: 2) { Color.clear }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

struct Bare: View {
    var body: some View { Reader(tag: "bare-window") }
}

final class AppDelegate2: UIResponder, UIApplicationDelegate {
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: s.role)
        c.delegateClass = SceneDelegate2.self
        return c
    }
}

final class SceneDelegate2: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.rootViewController = UIHostingController(rootView: AnyView(Root()))
        w.makeKeyAndVisible()
        window = w
        let wantLandscape = CommandLine.arguments.contains("landscape")
        ws.requestGeometryUpdate(.iOS(interfaceOrientations: wantLandscape ? .landscape : .portrait)) { e in
            q("orientation request error: \(e)")
        }
        let b = ws.screen.bounds
        q("SCREEN \(f2(b.width))x\(f2(b.height)) idiom=\(w.traitCollection.userInterfaceIdiom == .pad ? "pad" : "phone") os=\(UIDevice.current.systemVersion)")
        q("WINDOW safeArea t=\(f2(w.safeAreaInsets.top)) b=\(f2(w.safeAreaInsets.bottom)) l=\(f2(w.safeAreaInsets.left)) r=\(f2(w.safeAreaInsets.right))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            q("AFTER-ORIENTATION scene=\(f2(ws.effectiveGeometry.coordinateSpace.bounds.width))x\(f2(ws.effectiveGeometry.coordinateSpace.bounds.height)) window.safeArea t=\(f2(w.safeAreaInsets.top)) b=\(f2(w.safeAreaInsets.bottom)) l=\(f2(w.safeAreaInsets.left)) r=\(f2(w.safeAreaInsets.right))")
            w.rootViewController = UIHostingController(rootView: AnyView(RootNoNav()))
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                w.rootViewController = UIHostingController(rootView: AnyView(Bare()))
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    q("@@DONE@@")
                    flush2()
                }
            }
        }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate2.self))
