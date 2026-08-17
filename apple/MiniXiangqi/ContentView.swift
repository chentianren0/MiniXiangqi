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
//
// **The two board screens hide the container while they are up**, which is the
// owner's own recommendation twice over (2026-07-31) and is `hidesDestinationBar`
// below. The homes keep it; the board and the replay do not.

import Foundation
import SwiftUI

#if os(iOS)
/// Whether a board screen hides the destination bar at this width.
///
/// docs/interaction-design.md, "Navigation": the homes carry the destination
/// bar and the two board screens hide it — the owner's recommendation from the
/// device pass (2026-07-31), given first for replay's move list and then for
/// the play screen too, "to solve the space problem".
///
/// **The condition is the presentation, not the device**, which is the same
/// reasoning the layout shapes take: what the recommendation is about is a bar
/// standing across the bottom of the screen, directly under the board's own
/// controls and costing the layout its whole height. That is what the compact
/// presentation is. Where the container presents any other way — the iPad's
/// row of destinations inside the navigation bar, the Mac's sidebar — the bar
/// is not under the controls, hiding it returns little or nothing, and what it
/// does return is a visible way to the other destinations. Measured on both,
/// which is why this is a width test rather than `#if os(iOS)` alone: on a
/// phone the reclaimed height is 49 points; on an iPad in portrait it is one
/// collapsed title row on replay and *nothing at all* on the board, and in
/// landscape the container presents as a sidebar that this modifier does not
/// reach, so a device-wide rule would change one iPad orientation and not the
/// other.
///
/// A narrow iPadOS window is compact and gets the phone's answer, for the
/// phone's reason: there the bar really is across the bottom.
func hidesDestinationBar(_ widthClass: UserInterfaceSizeClass?) -> Bool {
    widthClass == .compact
}
#endif

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
            #if DEBUG && os(iOS)
            // `-mxq-open-nearby` opens the nearby developer harness *instead of*
            // the app. It is a debug instrument for driving the BoardGame
            // Protocol on two real devices, and this launch argument is its only
            // entry: the nearby feature's own surfaces are designed separately
            // and are not here yet.
            if NearbyLaunch.current.opensHarness {
                NearbyHarnessScreen(core: core)
            } else {
                Destinations(core: core)
            }
            #else
            Destinations(core: core)
            #endif
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

    #if os(iOS)
    /// The nearby feature, created once with the window like the game and the
    /// library, and for a stronger reason than either: a nearby session belongs
    /// to the *peer*, so the engine holding it has to outlive every page and
    /// every destination. Leaving the board is an interruption the protocol
    /// already models, and coming back finds the game where the two devices left
    /// it.
    @State private var nearby: NearbyFlow
    #endif

    private enum Destination: Hashable { case play, history, settings }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(core: Core) {
        self.core = core
        _play = State(initialValue: PlayState(core: core))
        _library = State(initialValue: HistoryLibrary(store: core.history))
        #if os(iOS)
        _nearby = State(initialValue: Self.nearbyFlow(over: core))
        #endif
    }

    #if os(iOS)
    /// The nearby stack: the log every layer writes to, the protocol engine's
    /// driver over it, the transport under that — both of its ways of reaching
    /// another device — and the flow the surfaces read. Assembled here because
    /// this is where the window is, and nothing below it is allowed to own a
    /// session.
    private static func nearbyFlow(over core: Core) -> NearbyFlow {
        #if DEBUG
        // `-mxq-nearby-board <stage>` stands the board up on a session nobody
        // is on the other end of. A Simulator has no Wi-Fi Aware, so it is the
        // only way a test sees this screen at all — and what it sees is the
        // real flow, board and positions, over a driver that speaks to nobody.
        if let stage = NearbyStage.named {
            return .staged(stage, positions: core.nearbyPositions,
                           rules: core.boardGameRules)
        }
        #endif
        let log = NearbyLog()
        // The library is the store's memory of the game: created with the
        // driver, because a ply can land while the board is down and the
        // driver is what every engine input funnels through.
        let record = NearbyRecord(library: core, rules: core.boardGameRules,
                                  log: log)
        let driver = NearbyDriver(rules: core.boardGameRules, log: log,
                                  record: record)
        let transport = NearbyTransport(driver: driver, log: log)
        return NearbyFlow(driver: driver, reach: transport,
                          positions: core.nearbyPositions,
                          isAvailable: NearbyFlow.isAvailableHere)
    }
    #endif

    /// The nearby feature, where the platform has one. A Mac never offers
    /// nearby play — the entitlement is signed for iPhone and iPad and the
    /// system's pairing UI does not exist there — so every surface that takes
    /// this takes nothing at all.
    private var nearbyFlow: NearbyFlow? {
        #if os(iOS)
        nearby
        #else
        nil
        #endif
    }

    var body: some View {
        TabView(selection: $destination) {
            Tab("nav.play", systemImage: "square.grid.3x3", value: Destination.play) {
                PlayDestination(play: play, replay: { record in
                    pendingReplay = record
                    destination = .history
                }, nearby: nearbyFlow)
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
        #if os(iOS)
        // The three nearby presentations that are not a page: the sheet a
        // game's own nearby row raises, the consent prompt an arriving
        // invitation puts up, and the refusal that answers one this device
        // sent. All three sit above the container rather than inside a
        // destination, because an invitation arrives when it arrives and a
        // refusal answers something the player may have sent from a sheet they
        // have already put away.
        .sheet(isPresented: proposing) {
            if let game = nearby.proposing {
                NearbyProposeSheet(flow: nearby, game: game)
            }
        }
        .nearbyAnswers(nearby) { destination = .play }
        // The engine publishes on every input, and this is where the flow reads
        // what moved: a proposal answered, or a refusal to present.
        .onChange(of: nearby.driver.sessions) { nearby.sessionsChanged() }
        .onChange(of: nearby.driver.declines.count) { nearby.sessionsChanged() }
        // The two objects that both have a claim on the library's one active
        // game, introduced to each other here because this is where both are
        // built. Nearby play makes room through the accepted 保存并继续, and
        // the paths that take the active game away tell whoever is playing it.
        .task {
            play.nearbyHolder = nearby
            play.resumeNearby = { [weak nearby] game in nearby?.reenter(game) }
            nearby.room = play
            nearby.libraryChanged = { [weak play] in play?.activeGameChanged() }
        }
        // A nearby board is drawn over every page of the Play destination, so
        // while one is up the local game's board is not on screen. The session,
        // the engine and any owed search go with the board that is showing:
        // down when the nearby board goes up, and open again on the local page
        // still standing underneath when it comes down.
        .onChange(of: nearby.boardSessionID) { _, session in
            play.nearbyBoardPresented(session != nil,
                                      policy: MotionPolicy(reduceMotion: reduceMotion))
        }
        #endif
        // **Which destination is showing is what the game's session hangs on.**
        // Issue #133's decision of 2026-08-05 gives the session, the engine and
        // any owed search to the board surface, so walking to another
        // destination puts them down and coming back opens them again — every
        // move is committed as it is made, so a board returned to reads the
        // same game back and thinks again about what it still owes.
        //
        // It is driven from this selection rather than from the play
        // destination's own `onDisappear`, and the difference is not
        // cosmetic: SwiftUI disposes tab content at moments that are not the
        // player leaving — the container builds and drops it while the window
        // is coming up — and a game torn down there is torn down under a board
        // that is still on screen. This value changes only when the player
        // moves.
        .onChange(of: destination) { _, showing in
            if showing == .play {
                play.enterBoard(policy: MotionPolicy(reduceMotion: reduceMotion))
            } else {
                play.leaveBoard()
            }
        }
        #if os(iOS)
        // Coming back from a suspension. Nothing about the game is at stake —
        // every ply was committed as it landed — but the radio's publisher and
        // browser stopped with the app, and the system's pairing snapshots can
        // end on their own, so both are taken up again. Returning to the page
        // that was showing stays in place.
        //
        // **Only `.active` is read here, and deliberately.**
        // docs/engine-integration.md is explicit that a teardown's trigger is
        // the platform's own suspension or memory-pressure signal and never a
        // change of visibility; `Suspension` subscribes to those signals and
        // this must not become a second, looser answer to the same question.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { nearby.returnedToForeground() }
        }
        #else
        // The window closing, which on this platform is not the app quitting.
        // The session and any search owed to it go with the surface they
        // belonged to; the engine stays, because a window is not sleep.
        .background(WindowCloseWatcher { play.windowClosed() })
        #endif
        // The two launch arguments that are about the *window* rather than
        // about a destination sit here, above the container: applied to a
        // destination they would be re-applied every time the player came back
        // to it, and the window would jump.
        #if DEBUG
        .preferredColorScheme(Self.launchColorScheme)
        #if os(macOS)
        .background(LaunchWindowSizer(contentSize: Self.launchWindowSize))
        #endif
        // `-mxq-open-replay` walks the launch to the newest record's replay,
        // which is the page a formatting screenshot is about and three clicks
        // from a launch otherwise. It waits for Play to have appeared, because
        // that appearance is what files the same launch's `-mxq-history` games:
        // switching sooner would open History onto a library nothing had
        // written to yet. History pushes the record whenever the list arrives,
        // so nothing here depends on this wait being long enough.
        .task {
            guard DebugLaunch.contains("-mxq-open-replay") else { return }
            try? await Task.sleep(for: .seconds(2))
            destination = .history
        }
        #endif
    }

    #if os(iOS)
    private var proposing: Binding<Bool> {
        Binding(get: { nearby.proposing != nil },
                set: { if !$0 { nearby.dismissSheet() } })
    }
    #endif

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

#if os(macOS)
/// The window this view is in, closing.
///
/// SwiftUI offers no scene-teardown signal to hang this on. `scenePhase`
/// reports *visibility*, which docs/engine-integration.md forbids treating as a
/// teardown on a platform where an unfocused window is still a running app, and
/// a view's `onDisappear` fires while a window is still coming up. What is
/// unambiguous is AppKit's own `willCloseNotification`.
///
/// It is observed **for this view's own window** rather than from the
/// notification centre at large, which is the whole reason it is a view and not
/// a modifier: a save panel, an open panel and a sheet are windows too, and
/// each posts the same notification. A player exporting a game mid-board must
/// not have their session put down by the panel closing.
private struct WindowCloseWatcher: NSViewRepresentable {
    var closed: @MainActor () -> Void

    func makeNSView(context: Context) -> NSView { Watcher(closed: closed) }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? Watcher)?.closed = closed
    }

    private final class Watcher: NSView {
        var closed: @MainActor () -> Void
        private var observation: NSObjectProtocol?

        init(closed: @escaping @MainActor () -> Void) {
            self.closed = closed
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not from a nib") }

        /// The window arrives after the view does, and can be replaced. The
        /// observation follows it, so this watches whatever window is holding
        /// the view now and never one it has left.
        ///
        /// This is also where the observation is given up, and it is enough:
        /// a window retains its view tree, so a view is taken out of its
        /// window before it is deallocated, and this runs with a nil window
        /// when that happens. A `deinit` would be the belt to this pair of
        /// braces, and it cannot have one — the token is not `Sendable` and a
        /// `deinit` is nonisolated.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observation {
                NotificationCenter.default.removeObserver(observation)
                self.observation = nil
            }
            guard let window else { return }
            observation = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window,
                queue: .main
            ) { [weak self] _ in
                // The main queue is where this was asked to arrive.
                MainActor.assumeIsolated { self?.closed() }
            }
        }
    }
}
#endif
