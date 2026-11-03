// The app's navigation, and what outlives it.
//
// The game, the library and the networked flows are held here rather than in
// a destination: the container keeps one destination's content alive at a
// time, so a screen is rebuilt on every visit, and a game living in it would
// be resumed each time and a dismissed result notice would come back.

import Foundation
import SwiftUI

#if os(iOS)
/// Whether a board screen hides the destination bar at this width. The test
/// is the presentation, not the device: only the compact tab bar stands under
/// the board's controls, costing 49 points on a phone. On an iPad the bar sits
/// in the navigation bar or becomes a sidebar, and hiding it returns little
/// while taking away the way to the other destinations.
func hidesDestinationBar(_ widthClass: UserInterfaceSizeClass?) -> Bool {
    widthClass == .compact
}
#endif

struct ContentView: View {
    /// Whether the player's Game Center could carry a game, which the online
    /// rows stand on.
    let gameCenter: GameCenterAvailability

    var body: some View {
        #if DEBUG
        if Self.isHostingUnitTests {
            // The core is a process-wide singleton the unit suite needs for its
            // own cores, and test traffic must not reach the player's library,
            // so a hosted unit run presents nothing and touches nothing.
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
        switch Self.library {
        case .success(let library):
            Destinations(library: library, gameCenter: gameCenter)
        case .failure(let error):
            // A core or library that will not open is a packaging failure; say
            // so rather than show an empty board. The description is diagnostic
            // text, not localized.
            ContentUnavailableView("failure.coreDidNotStart", systemImage: "exclamationmark.triangle",
                                   description: Text(verbatim: error.description).monospaced())
        }
    }

    /// The core and the library over it, opened once for the app.
    private static let library: Result<GameLibrary, CoreError> = {
        do {
            let core = try Core.shared.get()
            let url = GameLibrary.appStoreURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            return .success(GameLibrary(core: core, container: try GameLibrary.container(at: url)))
        } catch {
            return .failure(CoreError(wrapping: error))
        }
    }()

    #if DEBUG
    /// Whether this process is the unit suite's host. The test bundle is
    /// injected into the app; an app driven by the UI-test runner is a separate
    /// process and shows neither marker.
    private static let isHostingUnitTests =
        ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("XCTest") }
            || NSClassFromString("XCTestCase") != nil
    #endif
}

/// The container, and the one game beneath it.
private struct Destinations: View {

    /// Created once with the window, outliving every switch between
    /// destinations.
    @State private var play: PlayState

    /// Which destination is showing, and the record one has asked the other to
    /// open: 回放 on a just-recorded result opens the replay inside History's
    /// stack, and the request has to survive the switch.
    @State private var destination: Destination = .play
    @State private var pendingReplay: UUID?

    /// Created once with the window, so a record written while the list is on
    /// screen is visible in that same list.
    @State private var library: HistoryLibrary

    /// Created once with the window: a nearby session belongs to the peer, so
    /// its engine has to outlive every page and destination. Nil where the
    /// platform has no nearby play (the Mac); the surfaces draw nothing for
    /// nil, so they are declared on every platform.
    @State private var nearby: NearbyFlow?

    /// Online play exists on every platform; whether it is offered depends on
    /// the player's account, which the flow answers for itself.
    @State private var online: NearbyFlow
    @State private var party: OnlineParty

    /// Read whenever a row is drawn or the app comes back to the front.
    private let gameCenter: GameCenterAvailability

    private enum Destination: Hashable { case play, history, settings }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(library games: GameLibrary, gameCenter: GameCenterAvailability) {
        self.gameCenter = gameCenter
        _play = State(initialValue: PlayState(library: games))
        _library = State(initialValue: HistoryLibrary(library: games))
        #if os(iOS)
        _nearby = State(initialValue: Self.nearbyFlow(over: games))
        #endif
        let online = Self.onlinePlay(over: games, gameCenter: gameCenter)
        _online = State(initialValue: online.flow)
        _party = State(initialValue: online.party)
    }

    /// Every way this device can reach another one, in the order their rows
    /// stand on the Play home.
    private var flows: [NearbyFlow] { [nearby, online].compactMap { $0 } }

    #if os(iOS)
    /// The nearby stack: one log, the record, the protocol engine's driver and
    /// the transport under it, and the flow the surfaces read. Gated to iOS
    /// because the radio and the system's pairing live in the transport.
    private static func nearbyFlow(over library: GameLibrary) -> NearbyFlow {
        let core = library.core
        let log = NearbyLog()
        // Created with the driver because a ply can land while the board is
        // down, and every engine input goes through the driver.
        let record = NearbyRecord(library: library, rules: core.boardGameRules,
                                  log: log, mode: .nearby)
        let driver = NearbyDriver(rules: core.boardGameRules, log: log,
                                  record: record)
        let transport = NearbyTransport(driver: driver, log: log)
        return NearbyFlow(driver: driver, reach: transport,
                          positions: core.nearbyPositions, mode: .nearby,
                          availability: { NearbyFlow.isAvailableHere })
    }
    #endif

    /// The online stack, layer for layer the nearby one with another transport
    /// and mode. Assembled on every platform: GameKit reaches the Mac too.
    private static func onlinePlay(over library: GameLibrary,
                                   gameCenter: GameCenterAvailability)
        -> (flow: NearbyFlow, party: OnlineParty) {
        let core = library.core
        let log = NearbyLog()
        let record = NearbyRecord(library: library, rules: core.boardGameRules,
                                  log: log, mode: .online)
        let driver = NearbyDriver(rules: core.boardGameRules, log: log,
                                  record: record)
        let transport = OnlineTransport(driver: driver, log: log)
        let flow = NearbyFlow(driver: driver, reach: transport,
                              positions: core.nearbyPositions, mode: .online,
                              availability: { Self.onlineStands(gameCenter) })
        return (flow, OnlineParty(transport: transport, log: log))
    }

    /// Asked at every draw, so a sign-out or a restriction takes the online
    /// rows away under the reader.
    private static func onlineStands(_ gameCenter: GameCenterAvailability) -> Bool {
        return gameCenter.isAvailable
    }

    private var container: some View {
        TabView(selection: $destination) {
            Tab("nav.play", systemImage: "square.grid.3x3", value: Destination.play) {
                PlayDestination(play: play, replay: { record in
                    pendingReplay = record
                    destination = .history
                }, nearby: nearby, online: online)
            }

            Tab("nav.history", systemImage: "clock", value: Destination.history) {
                HistoryScreen(library: library, pendingReplay: $pendingReplay)
            }

            // The preferences this writes are read from the defaults by their
            // consumers, so nothing is handed down.
            Tab("nav.settings", systemImage: "gearshape", value: Destination.settings) {
                SettingsScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    /// Written in pieces because one chain grew past what the type checker
    /// accepts in a single expression.
    var body: some View {
        playingSomebody(container)
            // The session, the engine and any owed search belong to the board,
            // so leaving the Play destination puts them down and returning opens
            // them again. Driven from the selection rather than the destination's
            // `onDisappear`: SwiftUI builds and drops tab content while the window
            // is coming up, and a game torn down then is torn down under a board
            // still on screen.
            .onChange(of: destination) { _, showing in
                if showing == .play {
                    play.enterBoard(policy: MotionPolicy(reduceMotion: reduceMotion))
                } else {
                    play.leaveBoard()
                }
            }
            // Coming back to the front takes up what a suspension put down: the
            // radio's publisher and browser and the system's pairing snapshots.
            // Game Center is asked again because a restriction applied in the
            // background arrives with no notification. Only `.active` is read:
            // engine teardown follows the platform's suspension and memory
            // signals (`Suspension`), never a change of visibility.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                gameCenter.refresh()
                for flow in flows { flow.returnedToForeground() }
            }
            #if !os(iOS)
            // A window closing here is not the app quitting. The session and any
            // owed search go with it; the engine stays, because a window is not
            // sleep.
            .background(WindowCloseWatcher { play.windowClosed() })
            #endif
    }

    /// What playing somebody on another device hangs above the container
    /// rather than inside a destination.
    private func playingSomebody(_ content: some View) -> some View {
        publications(surfaces(presentations(content)))
    }

    /// The three presentations that are not a page.
    private func presentations(_ content: some View) -> some View {
        content
        // The propose surface, the consent prompt an invitation raises, and the
        // refusal that answers one this device sent sit above the container: an
        // invitation arrives when it arrives, and a refusal may answer a surface
        // the player already put away. With no flow every binding is false, so
        // a platform without nearby play presents none of them.
        .sheet(isPresented: proposing) {
            if let game = online.proposing {
                OnlineProposeSheet(flow: online, game: game, party: party)
            } else if let nearby, let game = nearby.proposing {
                NearbyProposeSheet(flow: nearby, game: game)
            }
        }
        .nearbyAnswers(flows) { destination = .play }
    }

    /// The engine publishes once per input; this is where a flow reads what
    /// moved.
    private func publications(_ content: some View) -> some View {
        content
        .onChange(of: nearby?.driver.sessions) { nearby?.sessionsChanged() }
        .onChange(of: nearby?.driver.declines.count) { nearby?.sessionsChanged() }
        .onChange(of: online.driver.sessions) { online.sessionsChanged() }
        .onChange(of: online.driver.declines.count) { online.sessionsChanged() }
    }

    private func surfaces(_ content: some View) -> some View {
        content
        // A friend the player already chose has arrived: propose, with nothing
        // left for them to press.
        .onChange(of: online.peers) { online.roomChanged() }
        // The party lives exactly as long as the surface offering it: opening
        // it mints the code a friend joins by.
        .onChange(of: online.proposing) { _, game in
            if let game { party.open(game) } else { party.close() }
        }
        // The objects with a claim on the library's one active game, introduced
        // here because this is where they are built. The captures are explicit:
        // each object lives as long as the window, and a stored closure that
        // kept another alive would be a cycle.
        .task { [play, party, nearby, online, flows] in
            play.resumeNetworkedGame = { [weak nearby, weak online] mode, game in
                (mode == .online ? online : nearby)?.reenter(game)
            }
            play.giveUpNetworkedGame = { [weak nearby, weak online] mode in
                (mode == .online ? online : nearby)?.giveUpActiveGame()
            }
            for flow in flows {
                flow.room = play
                flow.libraryChanged = { [weak play] in play?.activeGameChanged() }
            }
            // An invitation is accepted in Game Center's own surfaces at a
            // moment no screen chose, so the listener lives with the window.
            party.listen()
        }
        // A networked board is drawn over every Play page. The local session,
        // engine and owed search go down while it is up and open again when it
        // comes down.
        .onChange(of: boardIsUp) { _, up in
            play.nearbyBoardPresented(up,
                                      policy: MotionPolicy(reduceMotion: reduceMotion))
        }
    }

    /// At most one flow is proposing: raising a surface first takes the
    /// library's one active-game slot.
    private var proposing: Binding<Bool> {
        Binding(get: { flows.contains { $0.proposing != nil } },
                set: { up in
                    guard !up else { return }
                    for flow in flows { flow.dismissSheet() }
                })
    }

    private var boardIsUp: Bool {
        flows.contains { $0.boardSessionID != nil }
    }

}

#if os(macOS)
/// The window this view is in, closing. SwiftUI has no scene-teardown signal:
/// `scenePhase` reports visibility, and `onDisappear` fires while a window is
/// still coming up. It is a view so it can observe its own window only: save
/// and open panels and sheets post the same `willCloseNotification`, and a
/// player exporting mid-game must not have the session put down.
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

        /// The window arrives after the view and can be replaced, so the
        /// observation follows it. This is also where the observation is given
        /// up: a view leaves its window before it is deallocated. There is no
        /// `deinit` backstop because the token is not `Sendable` and a `deinit`
        /// is nonisolated.
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
                MainActor.assumeIsolated { self?.closed() }
            }
        }
    }
}
#endif
