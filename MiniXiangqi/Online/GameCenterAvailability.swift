// Signing the player in to Game Center, once at launch, and whether Online Play
// is on offer: only where somebody is signed in and Screen Time does not
// restrict multiplayer games. Where it is not, the row is absent, so nothing
// here says why. The sign-in is the system's own view controller, presented as
// it is.

import Foundation
import GameKit
import Observation
import OSLog

/// Whether Game Center can carry a game on this device, and the sign-in that
/// decides it.
@MainActor
@Observable
final class GameCenterAvailability {

    /// Whether online play is on offer.
    private(set) var isAvailable = false

    /// Whether the handler has been set. Setting it twice would be two
    /// sign-ins, and GameKit calls whichever it holds.
    @ObservationIgnored private var hasAuthenticated = false

    /// How many reads have been asked for, and so which one is the newest.
    @ObservationIgnored private var reads = 0

    /// Ask Game Center to sign the player in. Idempotent.
    func authenticate() {
        guard !hasAuthenticated else { return }
        hasAuthenticated = true
        watchForChanges()

        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            // GameKit calls this on the main thread: it hands over a view
            // controller.
            MainActor.assumeIsolated {
                if let error {
                    // A player who declined, or has no account, simply has no
                    // online row.
                    Self.note("Game Center did not sign the player in: \(error).")
                }
                if let viewController {
                    Self.note("Presenting Game Center's own sign-in.")
                    OnlineSystemSurface.present(viewController)
                }
                self.refresh()
            }
        }
    }

    /// What the sign-in and the system's restrictions add up to, asked again.
    ///
    /// Off the main thread: both answers reach the Game Center daemon over
    /// synchronous XPC, and on a signed Mac build
    /// `isMultiplayerGamingRestricted` blocked in
    /// `-[GKDaemonProxy effectiveValueForSetting:]` and never returned, which
    /// asked from the sign-in handler left the app without a first frame.
    func refresh() {
        let read = issueRead()
        Self.daemon.async { [weak self] in
            let player = GKLocalPlayer.local
            let stands = Self.stands(
                authenticated: player.isAuthenticated,
                multiplayerRestricted: player.isMultiplayerGamingRestricted)
            Task { @MainActor in self?.adopt(stands, from: read) }
        }
    }

    /// A queue rather than a task, because a blocked task holds a thread of the
    /// cooperative pool every `await` shares. Its own rather than the party's,
    /// so a registration the daemon does not answer cannot hold up the row.
    private static let daemon = DispatchQueue(
        label: "com.chentianren.MiniXiangqi.game-center-availability", qos: .utility)

    func issueRead() -> Int {
        reads += 1
        return reads
    }

    /// Only the newest read may write: an older one still in flight answers
    /// for an account that may have signed out, and nothing orders the hops
    /// back onto this actor.
    func adopt(_ stands: Bool, from read: Int) {
        guard read == reads else { return }
        guard stands != isAvailable else { return }
        isAvailable = stands
        Self.note("Online play is \(stands ? "available" : "not available") here.")
    }

    nonisolated static func stands(authenticated: Bool,
                                   multiplayerRestricted: Bool) -> Bool {
        authenticated && !multiplayerRestricted
    }

    /// Game Center's signal that the player signed in or out, or that a
    /// restriction changed. This object lives as long as the app, so there is
    /// no token to keep.
    private func watchForChanges() {
        NotificationCenter.default.addObserver(
            forName: .GKPlayerAuthenticationDidChangeNotificationName,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private static func note(_ text: String) {
        NearbyLogger.log.info("\(text, privacy: .public)")
        #if DEBUG
        print("[nearby] \(text)")
        #endif
    }
}
