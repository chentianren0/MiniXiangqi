// One window: two would be two boards writing over the one game in play. On
// macOS the scene is a `Window`, so there is no File → New Window; iOS keeps
// `WindowGroup`, which is single-scene by default.

import SwiftUI

/// Joins the engine thread at termination rather than relying on process
/// exit. Best effort: every move was saved as it was played.
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

    /// Game Center's sign-in, started at launch: whether online play is on
    /// offer decides whether a row exists before anything draws, and asking
    /// twice would be two sign-ins.
    @State private var gameCenter = GameCenterAvailability()

    /// The window's title is the app's own name: a proper noun, not copy, so
    /// it is typed as a plain string and never enters the catalog.
    private static let title = "MiniXiangqi"

    var body: some Scene {
        #if os(macOS)
        Window(Self.title, id: "play") {
            ContentView(gameCenter: gameCenter)
                .task { gameCenter.authenticate() }
        }
        .windowResizability(.contentMinSize)
        #else
        WindowGroup {
            ContentView(gameCenter: gameCenter)
                .task { gameCenter.authenticate() }
        }
        #endif
    }
}
