import SwiftUI

struct ContentView: View {
    var body: some View {
        #if DEBUG
        if Self.isHostingUnitTests {
            // The unit suite builds cores of its own against scratch stores,
            // and the core is singleton-enforced: a host app that opened the
            // player's real store at launch would both occupy the one slot
            // those cores need and put test traffic where the kept games
            // live. So under a hosted unit run the app presents nothing and
            // touches nothing.
            Color.clear
        } else {
            screen
        }
        #else
        screen
        #endif
    }

    @ViewBuilder
    private var screen: some View {
        switch Core.shared {
        case .success(let core):
            PlayScreen(core: core)
        case .failure(let error):
            // A core that will not start is a packaging failure, and saying so
            // plainly beats an empty board that silently does nothing. The
            // description beneath it is the core's own diagnostic text: not
            // copy, and not localized.
            ContentUnavailableView("failure.coreDidNotStart", systemImage: "exclamationmark.triangle",
                                   description: Text(verbatim: error.description).monospaced())
        }
    }

    #if DEBUG
    /// Whether this process is the unit suite's host. The test bundle is
    /// injected into the app, so the testing environment and the XCTest
    /// runtime are visible from inside it; an app driven by the UI-test
    /// runner is a separate process and shows neither.
    private static let isHostingUnitTests =
        ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("XCTest") }
            || NSClassFromString("XCTestCase") != nil
    #endif
}
