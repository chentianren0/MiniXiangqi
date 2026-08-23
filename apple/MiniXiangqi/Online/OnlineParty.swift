// Bringing the two players together, and the one door every match arrives
// through.
//
// docs/interaction-design.md, "Online play": "The people are friends the player
// brings, and never strangers a service found. Nothing matches, suggests, or
// lists a player this player did not choose." So there are exactly two ways in
// and both of them are the system's own — an invitation to a friend, and a
// party code Game Center mints for saying aloud — and neither of them is a
// search. The invitation is asked for in invite-only matchmaking, which is what
// forbids the automatch this product does not want.
//
// **It holds no game.** What it does is hand matches to the transport, and the
// game itself is the flow's from there: the proposal, the consent alert, the
// board and the record are nearby play's own, unchanged. A code carries its own
// game for the same reason — the device that raised the surface proposes the
// game its row named, so what the joining player is asked to consent to is that
// game whatever row they pressed.
//
// **The party is the system's, and so is what it is called.** The code is
// minted by Game Center against an activity App Store Connect carries, this
// device never composes one, and the only thing written about it here is a
// label saying it is a code.

import Foundation
import GameKit
import Observation

@MainActor
@Observable
final class OnlineParty: NSObject {
    @ObservationIgnored private let transport: OnlineTransport
    @ObservationIgnored private let log: NearbyLog

    /// The code a friend can join this game by, once Game Center has minted
    /// one. Nothing until it has, and nothing at all where the activity this
    /// game is played under does not carry codes.
    private(set) var code: String?

    /// Whether a code the player entered is being taken up. It is the one thing
    /// this surface has to wait for, because joining is a round trip through
    /// Game Center rather than something this device decides.
    private(set) var isJoining = false

    /// The game the surface now up was raised for, and the party started for
    /// it. The activity is Game Center's own object: it is what mints the code
    /// and what finds whoever joins with it.
    @ObservationIgnored private var game: GameKind?
    @ObservationIgnored private var activity: GKGameActivity?

    /// The errand waiting for somebody to arrive. Cancelled when the surface
    /// goes, so a party nobody joined stops looking with the screen that
    /// offered it.
    @ObservationIgnored private var waiting: Task<Void, Never>?

    /// The activity definitions Game Center has answered for, by identifier.
    /// They are App Store Connect's and immutable, so one answer per launch is
    /// the whole of the caching this needs.
    @ObservationIgnored private var definitions: [String: GKGameActivityDefinition] = [:]

    init(transport: OnlineTransport, log: NearbyLog) {
        self.transport = transport
        self.log = log
        super.init()
    }

    /// The activity each game is played under, by the identifiers App Store
    /// Connect carries. They are Game Center's own names for the games and are
    /// therefore written here verbatim rather than derived from anything: a
    /// `rules_id` is the protocol's vocabulary and these are the service's, and
    /// they agree for four of the five by coincidence rather than by rule.
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
    /// Called once, with the window: an invitation is accepted in the system's
    /// own surfaces, at a moment no screen of this app chose.
    ///
    /// **Off the thread that draws**, for the reason every synchronous GameKit
    /// call in this file is: registering asks the Game Center daemon what
    /// multiplayer this device allows before it returns, and a daemon that does
    /// not answer holds whichever thread asked. Measured on a signed Mac build,
    /// where the kernel reported the daemon blocked waiting back on this
    /// process — a deadlock that held the main thread from launch, so the app
    /// drew no window and loaded no accessibility at all.
    ///
    /// Nothing waits on it. What registering buys is callbacks, and they arrive
    /// when they arrive.
    func listen() {
        Task.detached(priority: .utility) { [self] in
            GKLocalPlayer.local.register(self)
        }
    }

    // MARK: - The surface

    /// The propose surface opened for a game: the party is started, which is
    /// what mints the code, and this device begins looking for whoever joins
    /// with it.
    func open(_ game: GameKind) {
        close()
        self.game = game
        waiting = Task { [weak self] in await self?.offer(game) }
    }

    /// The surface went away. The party ends with it — a code nobody can see
    /// any more is a code nobody can say — and so does the looking.
    ///
    /// **The match it may already have found is untouched.** A connection
    /// belongs to the peer rather than to a page, exactly as a session does,
    /// and the game standing over it is the flow's.
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
            log.note("Game Center would not start the party: \(refusal ?? "").")
            return
        }
        guard !Task.isCancelled else { return Self.end(activity) }
        self.activity = activity
        code = activity.partyCode
        await arrive(from: activity)
    }

    /// A code a friend said, taken up. It joins **the game that code carries**
    /// rather than the one whose row raised this surface: the two devices are
    /// brought together here, and which game they play is the proposal the
    /// other device sends afterwards.
    func join(_ typed: String) {
        guard let game, canJoin(typed) else { return }
        let code = Self.tidied(typed)
        close()
        self.game = game
        isJoining = true
        waiting = Task { [weak self] in await self?.take(up: code, in: game) }
    }

    /// Whether what has been typed is a code at all. Game Center's own answer,
    /// because the shape of a code is Game Center's: a control offered for a
    /// string the service would refuse is a control that fails on being
    /// pressed.
    ///
    /// **The one GameKit question this file asks on the drawing thread**, and
    /// the only one it can: a field's control is enabled while the field is
    /// drawn. What makes it safe is that the framework reads the shape of the
    /// string and asks the service nothing — a code is two parts of equal
    /// length from an alphabet the framework holds.
    func canJoin(_ typed: String) -> Bool {
        GKGameActivity.isValidPartyCode(Self.tidied(typed))
    }

    /// A code as the service reads it: without the spaces a person saying one
    /// aloud leaves in it, and in the case the framework uses.
    private static func tidied(_ typed: String) -> String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func take(up code: String, in game: GameKind) async {
        defer { isJoining = false }
        guard let definition = await definition(of: game) else { return }
        let (started, refusal) = await Self.started(definition, joining: code)
        guard let activity = started else {
            log.note("Game Center would not join that party: \(refusal ?? "").")
            return
        }
        guard !Task.isCancelled else { return Self.end(activity) }
        self.activity = activity
        await arrive(from: activity)
    }

    /// Game Center's own start, asked away from the thread that draws — a fresh
    /// party where `code` is nil, and a friend's party where it is one.
    ///
    /// **The work is detached deliberately.** Starting an activity is a
    /// synchronous round trip to the Game Center daemon, so it is one of the
    /// calls `listen()` above owns the reason for: nothing this app asks
    /// GameKit synchronously is asked where a slow answer would stop the screen
    /// from drawing. What comes back is the activity, or the refusal in the
    /// words the service used — carried as text, because an error is not
    /// something to move between isolations.
    private static func started(_ definition: GKGameActivityDefinition,
                                joining code: String?)
        async -> (GKGameActivity?, String?) {
        await Task.detached(priority: .utility) { () -> (GKGameActivity?, String?) in
            do {
                if let code {
                    return (try GKGameActivity.start(definition: definition,
                                                     partyCode: code), nil)
                }
                return (try GKGameActivity.start(definition: definition), nil)
            } catch {
                return (nil, String(describing: error))
            }
        }.value
    }

    /// A party this device is done offering, ended off the drawing thread for
    /// the same reason. Nothing waits for it: what it ends is Game Center's own
    /// record of what this player is doing.
    private static func end(_ activity: GKGameActivity) {
        Task.detached(priority: .utility) { activity.end() }
    }

    /// The system's own invitation, to friends and to nobody else.
    ///
    /// **Invite-only matchmaking is what forbids the stranger.** The mode is
    /// the one control this app sets on the system's screen, and setting it is
    /// the whole of "nothing matches, suggests, or lists a player this player
    /// did not choose" — the alternative modes are exactly the ones that would.
    func invite() {
        guard let request = matchRequest(),
              let controller = GKMatchmakerViewController(matchRequest: request)
        else {
            log.note("Game Center would not open its invitation screen.")
            return
        }
        controller.matchmakerDelegate = self
        controller.matchmakingMode = .inviteOnly
        OnlineSystemSurface.present(controller)
    }

    /// What the invitation asks for: two players and no third. The party's own
    /// request where there is a party, so the friend who accepts joins the
    /// activity this surface is already offering rather than a second one.
    private func matchRequest() -> GKMatchRequest? {
        let request = activity?.makeMatchRequest() ?? GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        return request
    }

    // MARK: - Arrivals

    /// Whoever an activity found, taken up.
    ///
    /// A friend who arrives after the surface has been put away arrives for
    /// nobody, and is told so rather than left connected to a screen that is no
    /// longer offering anything.
    private func arrive(from activity: GKGameActivity) async {
        do {
            let match = try await activity.findMatch()
            guard !Task.isCancelled else { return match.disconnect() }
            arrived(match)
        } catch {
            log.note("Game Center found nobody for the party: \(error).")
        }
    }

    /// **The one door.** Every way two players reach each other here — the
    /// invitation, a code entered, a code a friend opened, an invitation
    /// accepted in the system's own screens — ends at this line, so the
    /// transport is the only thing that ever holds a match and the rule it
    /// keeps about one connection per player has one place to be kept from.
    private func arrived(_ match: GKMatch) {
        transport.adopt(match)
    }

    /// The definition Game Center holds for that game, asked once.
    ///
    /// **They are App Store Connect's and cannot be made here**, which is why
    /// this can answer nothing: a build talking to an account that has not been
    /// told about these activities gets no definition, and a surface with no
    /// definition has no code to show. That is a fact about the account rather
    /// than something to explain on screen.
    private func definition(of game: GameKind) async -> GKGameActivityDefinition? {
        let id = Self.activityID(of: game)
        if let held = definitions[id] { return held }
        do {
            guard let loaded = try await GKGameActivityDefinition
                .loadGameActivityDefinitions(IDs: [id]).first
            else {
                log.note("Game Center holds no activity called \(id).")
                return nil
            }
            definitions[id] = loaded
            return loaded
        } catch {
            log.note("Game Center would not answer for the activity \(id): \(error).")
            return nil
        }
    }
}

// MARK: - Game Center's own screens
//
// **Every callback below is stated as arriving on the main thread rather than
// hopped onto it**, which is the opposite of what `OnlineConnection` does with
// a match's delegate and for a reason that is the mirror image: what these
// carry — a view controller being presented, an invitation that opens one — may
// only be touched there, so there is nowhere else GameKit could be calling
// them from. A hop would also cost the one thing this side cannot give up: a
// `GKMatch` is not `Sendable`, and nothing may carry one across an isolation
// boundary.

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
            log.note("Game Center's invitation screen failed: \(error).")
            OnlineSystemSurface.dismiss(viewController)
        }
    }

    nonisolated func matchmakerViewController(
        _ viewController: GKMatchmakerViewController, didFind match: GKMatch
    ) {
        // The match is stated to be the main actor's, which is the same
        // statement the isolation below makes and for the same reason: GameKit
        // formed it for a screen it is presenting there. Region isolation
        // cannot read that off an Objective-C protocol with no isolation on it,
        // so it is said here instead of hidden behind a hop that would have to
        // carry the match anyway.
        nonisolated(unsafe) let match = match
        MainActor.assumeIsolated {
            OnlineSystemSurface.dismiss(viewController)
            arrived(match)
        }
    }
}

extension OnlineParty: GKLocalPlayerListener {

    /// An invitation the player accepted in Game Center's own surfaces, which
    /// is where the whole of that ceremony belongs. What it consents to is the
    /// **connection**; the game is still ahead of them, as the proposal the
    /// other device sends and this device's own consent alert answers.
    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        // The invitation is the main actor's, for the reason above: what it is
        // handed over for is a view controller.
        nonisolated(unsafe) let invite = invite
        MainActor.assumeIsolated {
            guard let controller = GKMatchmakerViewController(invite: invite) else {
                log.note("Game Center would not open the accepted invitation.")
                return
            }
            controller.matchmakerDelegate = self
            OnlineSystemSurface.present(controller)
        }
    }

    /// A party a friend opened — a code's own link followed, or this game
    /// chosen from Game Center's own activity screens. It is the same arrival
    /// as a code typed in, reached without anybody typing anything.
    ///
    /// The answer waits for the match, because it is a claim about what
    /// happened rather than about what was attempted.
    nonisolated func player(_ player: GKPlayer, wantsToPlay activity: GKGameActivity,
                            completionHandler: @escaping @Sendable (Bool) -> Void) {
        MainActor.assumeIsolated {
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
                log.note("Game Center found nobody for that party: \(error).")
                answer(false)
            }
        }
    }
}
