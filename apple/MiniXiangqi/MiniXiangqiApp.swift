// The app and its one scene.
//
// docs/interaction-design.md's navigation exclusions have always excluded
// multiple main windows, and with games persisted the exclusion stopped being
// a taste question: two windows would be two sessions over the one active
// game, writing over each other with no diagnosis at all. On macOS the scene
// is therefore a `Window` — no File → New Window, by construction. iOS keeps
// `WindowGroup`, whose single-scene default already conforms.

import SwiftUI

/// Termination, answered with the core's deterministic teardown: close the
/// store and join the engine thread rather than relying on process exit. Best
/// effort — the store's journal is crash-safe by design, so a quit that never
/// reaches this loses nothing.
private final class AppDelegate: NSObject {
    fileprivate func shutdownCore() {
        Core.shutdownSharedIfLive()
    }
}

#if os(macOS)
extension AppDelegate: NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) { shutdownCore() }
}
#else
extension AppDelegate: UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) { shutdownCore() }
}
#endif

@main
struct MiniXiangqiApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif

    /// The window's title is the app's own name: a proper noun, not copy, so
    /// it is typed as a plain string and never enters the catalog.
    private static let title = "MiniXiangqi"

    var body: some Scene {
        #if os(macOS)
        Window(Self.title, id: "play") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
