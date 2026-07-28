import SwiftUI

@main
struct MiniXiangqiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        #endif
    }
}
