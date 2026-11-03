// Bringing two friends together, never strangers: a Game Center invitation in
// invite-only matchmaking, or a party code Game Center mints against an
// activity App Store Connect carries. It holds no game; it hands each match to
// the transport, and the proposal that follows decides the game.
//
// Every synchronous GameKit call here is made on `daemon`: on a signed Mac
// build the Game Center daemon blocked waiting back on this process when
// registering on the main thread, and the app drew no window.

import Foundation
import GameKit
import Observation

@MainActor
@Observable
final class OnlineParty: NSObject {
    @ObservationIgnored private let transport: OnlineTransport

    /// The code a friend can join by, once Game Center has minted one.
    private(set) var code: String?

    /// Whether a code the player entered is being taken up.
    private(set) var isJoining = false

    /// Whether this device came to the other one: it joined their code or
    /// accepted their invitation. The device that brought the friend proposes;
    /// this one waits for its proposal.
    @ObservationIgnored private(set) var joinedTheFriend = false

    /// The game the surface now up was raised for, and the party started for
    /// it.
    @ObservationIgnored private var game: GameKind?
    @ObservationIgnored private var activity: GKGameActivity?

    /// The wait for somebody to arrive, cancelled when the surface goes.
    @ObservationIgnored private var waiting: Task<Void, Never>?

    /// The activity definitions Game Center has answered for, by identifier.
    /// They are App Store Connect's and immutable.
    @ObservationIgnored private var definitions: [String: GKGameActivityDefinition] = [:]

    init(transport: OnlineTransport) {
        self.transport = transport
        super.init()
    }

    /// The activity each game is played under, by the identifiers App Store
    /// Connect carries: the service's names, not `GameKind`'s raw values.
    static func activityID(of game: GameKind) -> String {
        switch game {
        case .xiangqi: "xiangqi"
        case .miniXiangqi: "minixiangqi"
        case .gomoku15: "gomoku"
        case .renju: "renju"
        case .jieqi: "jieqi"
        }
    }

    // MARK: - Listening for what the player accepted elsewhere

    /// Take up the listener Game Center delivers accepted invitations through.
    /// Called once, with the window.
    func listen() {
        Self.daemon.async { [self] in
            GKLocalPlayer.local.register(self)
        }
    }

    /// A queue rather than a task, because a blocked task holds a thread of the
    /// cooperative pool every `await` shares.
    private static let daemon = DispatchQueue(
        label: "com.chentianren.MiniXiangqi.game-center-party", qos: .utility)

    // MARK: - The surface

    /// The propose surface opened for a game: the party starts, which mints
    /// the code, and this device looks for whoever joins it.
    func open(_ game: GameKind) {
        close()
        self.game = game
        joinedTheFriend = false
        waiting = Task { [weak self] in await self?.offer(game) }
    }

    /// The surface went away, and the party and the looking end with it. A
    /// match already found stays with the transport.
    func close() {
        waiting?.cancel()
        waiting = nil
        activity.map(Self.end)
        activity = nil
        game = nil
        code = nil
        isJoining = false
    }

    /// The party this device is offering, and the wait for somebody to take it
    /// up.
    private func offer(_ game: GameKind) async {
        guard let definition = await definition(of: game) else { return }
        let (started, refusal) = await Self.started(definition, joining: nil)
        guard let activity = started else {
            NearbyLogger.note("Game Center would not start the party: \(refusal ?? "").")
            return
        }
        guard !Task.isCancelled else { return Self.end(activity) }
        self.activity = activity
        code = activity.partyCode
        await arrive(from: activity)
    }

    /// A code a friend said, taken up. The game is the one the friend's device
    /// proposes once connected, whatever row raised this surface.
    func join(_ typed: String) {
        guard let game, canJoin(typed) else { return }
        let code = Self.tidied(typed)
        close()
        self.game = game
        isJoining = true
        joinedTheFriend = true
        waiting = Task { [weak self] in await self?.take(up: code, in: game) }
    }

    /// Whether what has been typed is a code at all. Asked on the main thread,
    /// which is safe: the framework checks the string's shape and asks the
    /// daemon nothing.
    func canJoin(_ typed: String) -> Bool {
        GKGameActivity.isValidPartyCode(Self.tidied(typed))
    }

    /// A code as the service reads it.
    private static func tidied(_ typed: String) -> String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func take(up code: String, in game: GameKind) async {
        defer { isJoining = false }
        guard let definition = await definition(of: game) else { return }
        let (started, refusal) = await Self.started(definition, joining: code)
        guard let activity = started else {
            NearbyLogger.note("Game Center would not join that party: \(refusal ?? "").")
            return
        }
        guard !Task.isCancelled else { return Self.end(activity) }
        self.activity = activity
        await arrive(from: activity)
    }

    /// A fresh party where `code` is nil, a friend's party where it is one. The
    /// refusal comes back as text, because an error does not cross isolations.
    private static func started(_ definition: GKGameActivityDefinition,
                                joining code: String?)
        async -> (GKGameActivity?, String?) {
        await withCheckedContinuation { continuation in
            daemon.async {
                do {
                    let activity: GKGameActivity
                    if let code {
                        activity = try GKGameActivity.start(definition: definition,
                                                            partyCode: code)
                    } else {
                        activity = try GKGameActivity.start(definition: definition)
                    }
                    continuation.resume(returning: (activity, nil))
                } catch {
                    continuation.resume(returning: (nil, String(describing: error)))
                }
            }
        }
    }

    private static func end(_ activity: GKGameActivity) {
        daemon.async { activity.end() }
    }

    /// The system's own invitation. Invite-only matchmaking is what keeps
    /// strangers out.
    func invite() {
        guard let request = matchRequest(),
              let controller = GKMatchmakerViewController(matchRequest: request)
        else {
            NearbyLogger.note("Game Center would not open its invitation screen.")
            return
        }
        controller.matchmakerDelegate = self
        controller.matchmakingMode = .inviteOnly
        joinedTheFriend = false
        OnlineSystemSurface.present(controller)
    }

    /// Two players. The party's own request where there is a party, so the
    /// friend who accepts joins it rather than a second one.
    private func matchRequest() -> GKMatchRequest? {
        let request = activity?.makeMatchRequest() ?? GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        return request
    }

    // MARK: - Arrivals

    /// Whoever an activity found, taken up; disconnected if the surface has
    /// gone.
    private func arrive(from activity: GKGameActivity) async {
        do {
            let match = try await activity.findMatch()
            guard !Task.isCancelled else { return match.disconnect() }
            arrived(match)
        } catch {
            NearbyLogger.note("Game Center found nobody for the party: \(error).")
        }
    }

    /// Every way two players reach each other ends here, so the transport is
    /// the only holder of a match.
    private func arrived(_ match: GKMatch) {
        transport.adopt(match)
    }

    /// The definition Game Center holds for that game, asked once. Nil where
    /// the App Store Connect account does not carry it, which leaves the
    /// surface without a code.
    private func definition(of game: GameKind) async -> GKGameActivityDefinition? {
        let id = Self.activityID(of: game)
        if let held = definitions[id] { return held }
        do {
            guard let loaded = try await GKGameActivityDefinition
                .loadGameActivityDefinitions(IDs: [id]).first
            else {
                NearbyLogger.note("Game Center holds no activity called \(id).")
                return nil
            }
            definitions[id] = loaded
            return loaded
        } catch {
            NearbyLogger.note("Game Center would not answer for the activity \(id): \(error).")
            return nil
        }
    }
}

// MARK: - Game Center's own screens
//
// These callbacks arrive on the main thread, because what they carry opens a
// view controller; they assume the main actor rather than hop to it, since a
// `GKMatch` is not `Sendable`.

extension OnlineParty: GKMatchmakerViewControllerDelegate {
    nonisolated func matchmakerViewControllerWasCancelled(
        _ viewController: GKMatchmakerViewController
    ) {
        MainActor.assumeIsolated {
            OnlineSystemSurface.dismiss(viewController)
        }
    }

    nonisolated func matchmakerViewController(
        _ viewController: GKMatchmakerViewController, didFailWithError error: any Error
    ) {
        MainActor.assumeIsolated {
            NearbyLogger.note("Game Center's invitation screen failed: \(error).")
            OnlineSystemSurface.dismiss(viewController)
        }
    }

    nonisolated func matchmakerViewController(
        _ viewController: GKMatchmakerViewController, didFind match: GKMatch
    ) {
        // Region isolation cannot read the main thread off this unannotated
        // Objective-C protocol.
        nonisolated(unsafe) let match = match
        MainActor.assumeIsolated {
            OnlineSystemSurface.dismiss(viewController)
            arrived(match)
        }
    }
}

extension OnlineParty: GKLocalPlayerListener {

    /// An invitation the player accepted in Game Center's own surfaces. It
    /// consents to the connection; the game is the proposal that follows.
    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        nonisolated(unsafe) let invite = invite
        MainActor.assumeIsolated {
            guard let controller = GKMatchmakerViewController(invite: invite) else {
                NearbyLogger.note("Game Center would not open the accepted invitation.")
                return
            }
            controller.matchmakerDelegate = self
            joinedTheFriend = true
            OnlineSystemSurface.present(controller)
        }
    }

    /// A party a friend opened: a code's link followed, or the game chosen in
    /// Game Center's activity screens. The answer waits for the match.
    nonisolated func player(_ player: GKPlayer, wantsToPlay activity: GKGameActivity,
                            completionHandler: @escaping @Sendable (Bool) -> Void) {
        MainActor.assumeIsolated {
            joinedTheFriend = true
            takeUp(activity, answering: completionHandler)
        }
    }

    private func takeUp(_ activity: GKGameActivity,
                        answering answer: @escaping @Sendable (Bool) -> Void) {
        Task { [weak self] in
            guard let self else { return answer(false) }
            do {
                arrived(try await activity.findMatch())
                answer(true)
            } catch {
                NearbyLogger.note("Game Center found nobody for that party: \(error).")
                answer(false)
            }
        }
    }
}
