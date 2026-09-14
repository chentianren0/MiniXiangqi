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
// whole ceremony belongs to the system, and this file only puts it on screen.
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

    /// How many reads have been asked for, and so which one is the newest.
    @ObservationIgnored private var reads = 0

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
                    OnlineSystemSurface.present(viewController)
                }
                self.refresh()
            }
        }
    }

    /// What the sign-in and the system's restrictions add up to, asked again.
    ///
    /// **Neither answer is read on the main thread, and that is not a
    /// nicety.** Both of them reach the Game Center daemon over synchronous
    /// XPC and return when it answers — measured on a signed Mac build, where
    /// `isMultiplayerGamingRestricted` blocked in
    /// `-[GKDaemonProxy effectiveValueForSetting:]` and did not come back. The
    /// one place this is asked from at launch is the sign-in handler, which
    /// GameKit calls on the main thread, so asking there is an app that draws
    /// nothing at all: no window, no accessibility, no first frame. The
    /// question therefore goes away from the screen and only the answer comes
    /// back to it.
    ///
    /// That makes the answer arrive rather than be had, which is the right way
    /// round anyway: `isAvailable` starts false, a launch that never hears from
    /// Game Center is a launch with no online row, and a row that appears a
    /// moment later is a row appearing when its answer does.
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

    /// **A call that blocks is carried by a queue rather than by a task.** The
    /// cooperative pool is a thread per core, and a task that blocks holds one
    /// of them until the block ends — so a daemon that never answers takes a
    /// share of every `await` in the process with it, which is a whole app made
    /// slow by one question about a row. A queue's thread is the queue's own,
    /// and one never given back is paid for here alone.
    ///
    /// Its own rather than the party's, so that a registration the daemon does
    /// not answer still leaves the row free to appear when its answer does.
    /// Serial, because two reads at once ask one daemon one question.
    private static let daemon = DispatchQueue(
        label: "com.chentianren.MiniXiangqi.game-center-availability", qos: .utility)

    /// The number the next read carries, minted here so the order is the order
    /// the reads were asked for in.
    func issueRead() -> Int {
        reads += 1
        return reads
    }

    /// What a read that has come back is allowed to write.
    ///
    /// **Only the newest read may write.** Two are in flight together whenever
    /// the answer changes while one is still out — signing out asks again — and
    /// the older one carries an answer about an account that has since gone. It
    /// is the read's own number that decides, not the order the landings happen
    /// to arrive in: nothing orders a hop onto this actor, and a row left
    /// standing for a gone account stands until the next foreground return.
    func adopt(_ stands: Bool, from read: Int) {
        guard read == reads else { return }
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
}
