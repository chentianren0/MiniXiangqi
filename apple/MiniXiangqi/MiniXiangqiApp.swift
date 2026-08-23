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

    /// Game Center's sign-in, and whether online play is on offer once it has
    /// answered.
    ///
    /// **It is started here because it is a launch errand rather than a
    /// screen's**: the answer gates whether a row exists at all, so it has to be
    /// asked before anything draws, and asking it twice would be two sign-ins.
    /// The scene owns it for the same reason it owns the window — one app, one
    /// account, one answer.
    @State private var gameCenter = GameCenterAvailability()

    /// The window's title is the app's own name: a proper noun, not copy, so
    /// it is typed as a plain string and never enters the catalog.
    private static let title = "MiniXiangqi"

    var body: some Scene {
        #if os(macOS)
        Window(Self.title, id: "play") {
            ContentView()
                .task { gameCenter.authenticate() }
        }
        .windowResizability(.contentMinSize)
        #else
        WindowGroup {
            ContentView()
                .task { gameCenter.authenticate() }
        }
        #endif
    }
}
