// The app's navigation.
//
// docs/interaction-design.md, "Layout shapes": navigation uses one adaptive
// container, presenting as a tab bar at narrow widths and as a sidebar at wide
// ones, by the same width-driven rule as the layout shapes rather than by
// device identity. `TabView` with the sidebar-adaptable style is exactly that
// container: one declaration, a sidebar on a Mac, a tab bar on a phone.
//
// Two destinations, and Play is the one that opens. Settings is the third
// primary destination in the product contract and holds nothing yet — a
// preference screen with no preferences behind it would be a promise rather
// than a destination — so it arrives with the preferences it is for.

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
            TabView {
                Tab("nav.play", systemImage: "square.grid.3x3") {
                    PlayScreen(core: core)
                }
                .accessibilityIdentifier("destination-play")

                Tab("nav.history", systemImage: "clock") {
                    HistoryScreen(core: core)
                }
                .accessibilityIdentifier("destination-history")
            }
            .tabViewStyle(.sidebarAdaptable)
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
