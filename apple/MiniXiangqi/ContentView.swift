// The app's navigation, and what outlives it.
//
// docs/interaction-design.md, "Layout shapes": navigation uses one adaptive
// container, presenting as a tab bar at narrow widths and as a sidebar at wide
// ones, by the same width-driven rule as the layout shapes rather than by
// device identity. `TabView` with the sidebar-adaptable style is exactly that
// container: one declaration, a sidebar on a Mac, a tab bar on a phone.
//
// Three destinations, in the product contract's own order — Play, History,
// Settings — and Play is the one that opens. Settings waited until there were
// preferences behind it, because a preference screen with none is a promise
// rather than a destination; it arrives now with the five it is for.
//
// **The game is held here rather than inside Play.** The container keeps one
// destination's content alive at a time, so the play screen is torn down and
// rebuilt on every visit; a game living in it would be resumed on each one, and
// a result notice the player had put away would come back with the rebuilt
// view. `PlayState` is what the screen re-renders against instead.

import Foundation
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
            Destinations(core: core)
        case .failure(let error):
            // A core that will not start is a packaging failure, and saying so
            // plainly beats an empty board that silently does nothing. The
            // description beneath it is the core's own diagnostic text: not
            // copy, and not localized.
            ContentUnavailableView("failure.coreDidNotStart", systemImage: "exclamationmark.triangle",
                                   description: Text(verbatim: error.description).monospaced())
        }
    }

    /// The game files `-mxq-import <base64>;<base64>` names. Debug only: a
    /// release build has no launch argument to read and no files to import, so
    /// the list is empty and History's launch-import path never runs.
    static var launchImports: [Data] {
        #if DEBUG
        (DebugLaunch.argument(after: "-mxq-import") ?? "")
            .split(separator: ";")
            .compactMap { Data(base64Encoded: String($0)) }
        #else
        []
        #endif
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

/// The container, and the one game beneath it.
private struct Destinations: View {
    private let core: Core

    /// Created once, with the window, and outliving every switch between the
    /// destinations inside it.
    @State private var play: PlayState

    /// Which destination is showing, and the record one of them has asked the
    /// other to open. 回放 on the just-recorded result crosses the container:
    /// the replay screen lives inside History's own stack, and this is the one
    /// piece of state that says so. Both live here rather than in a screen for
    /// the same reason the game does — a destination is rebuilt on every visit,
    /// and a request made in one has to survive the switch to the other.
    @State private var destination: Destination = .play
    @State private var pendingReplay: UInt64?

    /// The game files a debug launch asked to be imported, held here for the
    /// same reason and consumed by History the first time it appears. Always
    /// empty in a release build, where the launch argument does not exist.
    @State private var pendingImports: [Data] = ContentView.launchImports

    /// The library, created once with the window for the same reason the game
    /// is: a destination rebuilt on every visit would otherwise rebuild it too,
    /// and a record written while another copy of the list is on screen would
    /// be invisible to the copy being looked at.
    @State private var library: HistoryLibrary

    private enum Destination: Hashable { case play, history, settings }

    init(core: Core) {
        self.core = core
        _play = State(initialValue: PlayState(core: core))
        _library = State(initialValue: HistoryLibrary(store: core.history))
    }

    var body: some View {
        TabView(selection: $destination) {
            Tab("nav.play", systemImage: "square.grid.3x3", value: Destination.play) {
                PlayScreen(play: play, replay: { record in
                    pendingReplay = record
                    destination = .history
                })
            }

            Tab("nav.history", systemImage: "clock", value: Destination.history) {
                HistoryScreen(library: library, pendingReplay: $pendingReplay,
                              pendingImports: $pendingImports)
            }

            // Nothing is handed down: the preferences this writes are read from
            // the defaults database by whatever consumes them, at the moment it
            // does, so the screen has no state to be given and none to give back.
            Tab("nav.settings", systemImage: "gearshape", value: Destination.settings) {
                SettingsScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // The two launch arguments that are about the *window* rather than
        // about a destination sit here, above the container: applied to a
        // destination they would be re-applied every time the player came back
        // to it, and the window would jump.
        #if DEBUG
        .preferredColorScheme(Self.launchColorScheme)
        #if os(macOS)
        .background(LaunchWindowSizer(contentSize: Self.launchWindowSize))
        #endif
        #endif
    }

    #if DEBUG
    /// The appearance `-mxq-appearance dark` or `-mxq-appearance light` names.
    /// AppKit no longer takes `-AppleInterfaceStyle` from a launch argument, and
    /// glass has to be looked at in both appearances rather than reasoned about
    /// in one.
    ///
    /// `light` is named as explicitly as `dark` because the alternative is the
    /// machine's own appearance, and a Mac set to switch automatically changes it
    /// at sunset: a series photographed without saying which appearance it wanted
    /// is a series whose light half is light only until the evening.
    private static var launchColorScheme: ColorScheme? {
        switch DebugLaunch.argument(after: "-mxq-appearance") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    /// The size `-mxq-window 900x700` names, handed to AppKit as the window's
    /// content size — which on this window is the whole frame, title bar
    /// included, since the content view runs the full height of it. A
    /// screenshot series about layout has to state the size each frame was
    /// taken at, and a window a test resized by dragging its corner cannot.
    private static var launchWindowSize: CGSize? {
        guard let text = DebugLaunch.argument(after: "-mxq-window") else { return nil }
        let sides = text.split(separator: "x").compactMap { Double($0) }
        guard sides.count == 2, sides.allSatisfy({ $0 > 0 }) else { return nil }
        return CGSize(width: sides[0], height: sides[1])
    }
    #endif
}

#if DEBUG && os(macOS)
/// Applies `-mxq-window`'s size to the window, once there is a window to apply
/// it to. Debug only, and it asks AppKit for the size rather than asserting it:
/// the window's own minimum still clamps the request, which is how a test
/// measures what that minimum actually comes to.
private struct LaunchWindowSizer: NSViewRepresentable {
    var contentSize: CGSize?

    func makeNSView(context: Context) -> NSView { Sizer(contentSize: contentSize) }
    func updateNSView(_ view: NSView, context: Context) { }

    private final class Sizer: NSView {
        private let contentSize: CGSize?

        init(contentSize: CGSize?) {
            self.contentSize = contentSize
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not from a nib") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let contentSize else { return }
            // On the next pass, after AppKit has restored the saved frame and
            // SwiftUI has handed the window the content's minimum: either one
            // arriving afterwards would undo this.
            DispatchQueue.main.async { [weak window] in
                window?.setContentSize(contentSize)
                window?.center()
            }
        }
    }
}
#endif
