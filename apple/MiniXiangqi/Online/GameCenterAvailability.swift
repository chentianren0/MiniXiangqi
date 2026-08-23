// Signing the player in to Game Center, and what that leaves behind.
//
// Game Center is the carrier of online play and the authenticator of both
// players, so the sign-in happens once at launch — before anything asks whether
// online play is on offer, because the answer is what it produces.
//
// **There is no sign-in surface of the app's, and there will not be one.** The
// handler either says the player is signed in or hands over the system's own
// view controller, which is presented as it is. The app writes no words about
// Game Center, mints no account, holds no credential and asks for nothing: the
// whole ceremony belongs to the system, and this is the twenty lines that put it
// on screen.
//
// **What the surfaces read is one boolean, and its rule is the contract's.**
// The interaction contract says the Online Play row "stands where the player's
// own Game Center could carry a game; where it could not — nobody signed in, or
// multiplayer gaming restricted by the system — it is absent rather than
// disabled". Both halves are load-bearing. The first is the sign-in. The second
// is Screen Time's multiplayer restriction, which is a parental control rather
// than a preference of ours: a device where it is set must not offer the row at
// all, and honouring it is one of the obligations the feature was accepted with.
//
// Absent rather than disabled, so nothing here reports *why*: a row that is not
// there needs no explanation, and a row that explained itself would be the app
// writing words about Game Center.

import Foundation
import GameKit
import Observation
import OSLog

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Whether Game Center can carry a game on this device, and the sign-in that
/// decides it.
@MainActor
@Observable
final class GameCenterAvailability {

    /// Whether online play is on offer. False until the sign-in says otherwise,
    /// which is the right way round: a launch that never hears from Game Center
    /// is a launch with no online row.
    private(set) var isAvailable = false

    /// Whether the handler has been set. Setting it twice would be two
    /// sign-ins, and GameKit calls whichever it holds.
    @ObservationIgnored private var hasAuthenticated = false

    /// Ask Game Center to sign the player in. Called once, at launch;
    /// idempotent, so calling it again is nothing.
    func authenticate() {
        guard !hasAuthenticated else { return }
        hasAuthenticated = true
        watchForChanges()

        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            // **The handler's payload is a view controller**, which may only be
            // touched on the main thread — so GameKit necessarily calls this
            // there, and there is nowhere else it could hand one over. This
            // states that rather than assuming it silently, and there is no
            // alternative to state instead: a view controller is not something
            // that can be moved to another actor.
            MainActor.assumeIsolated {
                if let error {
                    // Not a failure of the app's and not a thing to say on
                    // screen: a player who declined, or has no account, is a
                    // player with no online row. The line is for a run's log.
                    Self.note("Game Center did not sign the player in: \(error).")
                }
                if let viewController {
                    Self.note("Presenting Game Center's own sign-in.")
                    Self.present(viewController)
                }
                self.refresh()
            }
        }
    }

    /// What the sign-in and the system's restrictions add up to, read again.
    func refresh() {
        let player = GKLocalPlayer.local
        let stands = Self.stands(authenticated: player.isAuthenticated,
                                 multiplayerRestricted: player.isMultiplayerGamingRestricted)
        guard stands != isAvailable else { return }
        isAvailable = stands
        Self.note("Online play is \(stands ? "available" : "not available") here.")
    }

    /// The rule itself, as a function of the two answers rather than of the
    /// framework, so that what the row is gated on can be stated and pinned in
    /// one place.
    nonisolated static func stands(authenticated: Bool,
                                   multiplayerRestricted: Bool) -> Bool {
        authenticated && !multiplayerRestricted
    }

    /// Game Center's own signal that the answer has changed — the player signed
    /// out in Settings, or a restriction was applied or lifted while the app was
    /// running. It is the documented way to hear about it, and the alternative
    /// is a row that goes on standing for an account that is gone.
    ///
    /// On the main queue, which is what makes the isolation below a statement
    /// rather than a hope. The observation lives as long as this object does,
    /// which is as long as the app does, so there is no token to keep.
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

    // MARK: - Putting the system's view controller on screen

    // The one platform split in this layer, and it is not about Game Center:
    // GameKit reaches the Mac exactly as it reaches iPhone and iPad, and the
    // handler hands back a view controller of whichever kit the platform has.
    // Presenting one is all that differs, so that is all that is written twice.

    #if os(macOS)
    private static func present(_ viewController: NSViewController) {
        guard let host = NSApp.keyWindow?.contentViewController
                ?? NSApp.windows.first(where: \.isVisible)?.contentViewController
        else {
            note("No window to present Game Center's sign-in in.")
            return
        }
        host.presentAsSheet(viewController)
    }
    #else
    private static func present(_ viewController: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController
        else {
            note("No window to present Game Center's sign-in in.")
            return
        }
        // Whatever is frontmost, so the sign-in is not put behind a sheet the
        // player already has open.
        var host = root
        while let presented = host.presentedViewController { host = presented }
        host.present(viewController, animated: true)
    }
    #endif
}
