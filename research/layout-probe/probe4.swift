import UIKit
var O4 = ""
func r4(_ s: String) { O4 += s + "\n"; print(s) }
func flush4() {
    let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? O4.write(to: d.appendingPathComponent("probe4.txt"), atomically: true, encoding: .utf8)
}
func fx(_ v: CGFloat) -> String { v > 1e6 ? "UNBOUNDED" : String(format: "%.2f", v) }
final class AD4: UIResponder, UIApplicationDelegate {
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: s.role); c.delegateClass = SD4.self; return c
    }
}
final class SD4: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws); w.rootViewController = UIViewController(); w.makeKeyAndVisible(); window = w
        r4("idiom=\(w.traitCollection.userInterfaceIdiom == .pad ? "pad" : "phone") os=\(UIDevice.current.systemVersion)")
        r4("supportsMultipleScenes=\(UIApplication.shared.supportsMultipleScenes)")
        guard let sr = ws.sizeRestrictions else { r4("sizeRestrictions NIL"); flush4(); return }
        r4("t0 min=\(fx(sr.minimumSize.width))x\(fx(sr.minimumSize.height)) max=\(fx(sr.maximumSize.width))x\(fx(sr.maximumSize.height)) allowsFullScreen=\(sr.allowsFullScreen)")
        sr.minimumSize = CGSize(width: 380, height: 500)
        r4("t1 immediately after set: min=\(fx(sr.minimumSize.width))x\(fx(sr.minimumSize.height))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            r4("t2 after 3s: min=\(fx(sr.minimumSize.width))x\(fx(sr.minimumSize.height))")
            r4("t2 same object? \(ws.sizeRestrictions === sr)")
            if let sr2 = ws.sizeRestrictions {
                r4("t2 fresh read: min=\(fx(sr2.minimumSize.width))x\(fx(sr2.minimumSize.height))")
                sr2.minimumSize.width = 640
                r4("t3 width-only set 640 -> \(fx(sr2.minimumSize.width))x\(fx(sr2.minimumSize.height))")
                sr2.allowsFullScreen = false
                r4("t4 allowsFullScreen=false -> \(sr2.allowsFullScreen)")
            }
            r4("scene bounds=\(fx(ws.effectiveGeometry.coordinateSpace.bounds.width))x\(fx(ws.effectiveGeometry.coordinateSpace.bounds.height))")
            r4("@@DONE4@@"); flush4()
        }
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AD4.self))
