// The Play home: what to play, and the game already going.
//
// docs/interaction-design.md, "Starting and configuring a game": the Play
// destination's root is an independent page for choosing what to play, and there
// is no board anywhere on it. Selecting a way to play opens that mode's
// pre-start state, which is where the preview board lives.
//
// **Each game has a section of its own, and that is the whole of the
// extensibility.** A section offers the ways to play that game that the app can
// actually carry here — which leaves out the AI where the game has none, and
// leaves out a way of reaching another device that this platform or this
// player's own account cannot carry. The selection carried by every row is
// explicit, so neither its setup nor a game created from it can fall through to
// a hidden default.
//
// docs/interaction-design.md, "Saving the active game before choosing a new
// mode": with a game active the page shows its metadata and a direct Resume, and
// **the mode entries stay interactive**. Selecting one presents the accepted
// confirmation — one fixed title, header, message and pair of actions for every
// combination of old mode, new mode and game state, with only the metadata
// changing — and 保存并继续 archives the game as it stands before the selected
// mode's pre-start page opens. A refusal keeps the game and says so.

import SwiftUI

struct PlayHome: View {
    let play: PlayState

    /// The nearby feature, where this device has one. It is nil on a Mac, which
    /// never offers nearby play, and its own availability decides whether the
    /// rows below are drawn on a device that does.
    var nearby: NearbyFlow?

    /// Online play, on every platform this app runs on. Its availability is the
    /// player's own Game Center rather than the build's, so the answer is asked
    /// at every draw and the row comes and goes with it.
    var online: NearbyFlow?

    /// 回到对局 is what opens the session and starts the engine thinking, so the
    /// page needs the policy that game's motion will run under.
    @Environment(\.motionPolicy) private var policy

    var body: some View {
        Form {
            if let summary = play.activeSummary { currentGame(summary) }
            waysToPlay
        }
        // The native presentation of a grouped list of choices on this platform,
        // and the one that gives a section its header. The title is the
        // destination's rather than this page's, because every page in it carries
        // the same one.
        .formStyle(.grouped)
        // The accepted confirmation. A system alert, blocking until it is
        // answered, because the act does not happen until the player answers —
        // and the same one for every combination, which is why nothing in it
        // interpolates a mode or a state.
        //
        // The metadata header and the metadata line ride in the message, since
        // an alert on this platform is a title, a message and its actions. They
        // are separated from the sentence by a blank line and by nothing else: a
        // line break carries no punctuation and is the same in both languages,
        // so no format string stands between them.
        .alert("alert.newGame.title", isPresented: confirming) {
            Button("control.cancel", role: .cancel) { play.dismissConfirmation() }
            Button("control.saveAndContinue") { play.saveAndContinue() }
        } message: {
            Text(confirmationMessage)
        }
        // The accepted refusal: the game is unchanged, and 重试 repeats exactly
        // the same atomic archive rather than something near it.
        .alert("alert.saveFailed.title", isPresented: archiveFailed) {
            Button("control.cancel", role: .cancel) { play.dismissArchiveFailure() }
            Button("control.tryAgain") { play.saveAndContinue() }
        } message: {
            Text("alert.saveFailed.message")
        }
    }

    // MARK: - The sections

    /// The active game: what it is, and the way back into it.
    ///
    /// Every fact on the line is read from the store's own summary rather than
    /// worked out here — the page holds no session, and the game becomes live
    /// only when 回到对局 opens its board. The header is the same 当前对局 the
    /// confirmation puts over the same line.
    private func currentGame(_ summary: ActiveGameSummary) -> some View {
        Section {
            Text(summary.metadataLine)
                .font(.callout)
                // Every token on it is content the contract asks for, so it
                // wraps rather than truncating.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("home-current-game")

            // The one obvious next action on this page while a game is going,
            // and therefore the one thing on it the tint rule allows.
            Button("nav.resumeGame") { play.resume(policy: policy) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home-resume")
        } header: {
            Text("alert.newGame.metadataHeader")
        }
    }

    @ViewBuilder
    private var waysToPlay: some View {
        Section {
            entry(PlaySelection(game: .xiangqi, mode: .humanVersusAI),
                  "mode.humanVersusAI", "mode-xiangqi-human-versus-ai")
            entry(PlaySelection(game: .xiangqi, mode: .freePlay),
                  "mode.freePlay", "mode-xiangqi-free-play")
            reachEntry(nearby, "mode.nearby", .xiangqi, "mode-xiangqi-nearby")
            reachEntry(online, "mode.online", .xiangqi, "mode-xiangqi-online")
            // Last of all, and in this section alone: Custom Scene is Xiangqi's
            // own, because Xiangqi is the one game whose rules say which
            // positions it may be set up in. It is a row like the others and
            // not a fourth way to play — what it opens is the editor, and what
            // the editor starts is an ordinary Free Play game.
            row("mode.customScene", "mode-xiangqi-custom-scene") {
                play.chooseCustomScene()
            }
        } header: {
            Text(GameKind.xiangqi.localizedName)
        }

        Section {
            entry(PlaySelection(game: .miniXiangqi, mode: .humanVersusAI),
                  "mode.humanVersusAI", "mode-mini-xiangqi-human-versus-ai")
            entry(PlaySelection(game: .miniXiangqi, mode: .freePlay),
                  "mode.freePlay", "mode-mini-xiangqi-free-play")
            reachEntry(nearby, "mode.nearby", .miniXiangqi, "mode-mini-xiangqi-nearby")
            reachEntry(online, "mode.online", .miniXiangqi, "mode-mini-xiangqi-online")
        } header: {
            Text(GameKind.miniXiangqi.localizedName)
        }

        // **No Human versus AI row**, because the game has no AI to offer:
        // docs/interaction-design.md, "The Play home". The section opens on
        // Free Play instead, and the ways of playing somebody else follow it —
        // this peer speaks the handshake that settles the deal between
        // accepting and the first move, so a proposal of jieqi is taken exactly
        // where its row says it will be, however the two devices reached each
        // other.
        Section {
            entry(PlaySelection(game: .jieqi, mode: .freePlay),
                  "mode.freePlay", "mode-jieqi-free-play")
            reachEntry(nearby, "mode.nearby", .jieqi, "mode-jieqi-nearby")
            reachEntry(online, "mode.online", .jieqi, "mode-jieqi-online")
        } header: {
            Text(GameKind.jieqi.localizedName)
        }

        // The placement games, in the accepted order: Gomoku, then Renju as its
        // stricter sibling.
        Section {
            entry(PlaySelection(game: .gomoku15, mode: .humanVersusAI),
                  "mode.humanVersusAI", "mode-gomoku-human-versus-ai")
            entry(PlaySelection(game: .gomoku15, mode: .freePlay),
                  "mode.freePlay", "mode-gomoku-free-play")
            reachEntry(nearby, "mode.nearby", .gomoku15, "mode-gomoku-nearby")
            reachEntry(online, "mode.online", .gomoku15, "mode-gomoku-online")
        } header: {
            Text(GameKind.gomoku15.localizedName)
        }

        Section {
            entry(PlaySelection(game: .renju, mode: .humanVersusAI),
                  "mode.humanVersusAI", "mode-renju-human-versus-ai")
            entry(PlaySelection(game: .renju, mode: .freePlay),
                  "mode.freePlay", "mode-renju-free-play")
            reachEntry(nearby, "mode.nearby", .renju, "mode-renju-nearby")
            reachEntry(online, "mode.online", .renju, "mode-renju-online")
        } header: {
            Text(GameKind.renju.localizedName)
        }
    }

    /// One way to play. A row rather than a button-shaped control, because the
    /// two are a list of things to choose between and neither is the answer; the
    /// chevron says where choosing one goes, which is a page and not a game — a
    /// game is created by 开始对局 on the page it opens, and by nothing else.
    private func entry(_ selection: PlaySelection, _ title: LocalizedStringKey,
                       _ identifier: String) -> some View {
        row(title, identifier) { play.choose(selection) }
    }

    /// A row for playing that game with somebody on another device — one per
    /// way of reaching one, in the order the contract puts them in: the room
    /// this device is in, then anywhere at all.
    ///
    /// **Each stands where a game could actually be carried, and is otherwise
    /// absent rather than disabled**: a row that could never be pressed is a
    /// promise nobody can keep, and no explanation helps a reader who cannot
    /// change the answer. Nearby play asks the platform, which on iPhone and
    /// iPad is always yes — one of its two paths needs no hardware of its own —
    /// and on a Mac is no. Online play asks the player's own Game Center, which
    /// is nobody's build-time answer.
    ///
    /// **The absence is the flow's rather than the compiler's.** There is one
    /// question here on every platform — is there a flow, and does it say it is
    /// available — so a Mac withholds the nearby row by having no flow to ask,
    /// and this file needs no gate. It is also the only kind of answer that can
    /// change under the reader, which the online row's does.
    ///
    /// Where a game is already going in this row's own game *and* its own mode,
    /// the row leads back into it, exactly as the current-game card above leads
    /// back into a local one. The rest of that decision is the flow's.
    @ViewBuilder
    private func reachEntry(_ flow: NearbyFlow?, _ title: LocalizedStringKey,
                            _ game: GameKind, _ identifier: String) -> some View {
        if let flow, flow.isAvailable {
            row(title, identifier) { flow.open(game) }
        }
    }

    private func row(_ title: LocalizedStringKey, _ identifier: String,
                     _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - The two alerts

    /// The confirmation's whole message: the accepted metadata header, the
    /// active game's own line, and the accepted sentence.
    private var confirmationMessage: String {
        [String(localized: "alert.newGame.metadataHeader"),
         play.activeSummary?.metadataLine ?? "",
         "",
         String(localized: "alert.newGame.message")].joined(separator: "\n")
    }

    private var confirming: Binding<Bool> {
        Binding(get: { if case .confirming = play.modeSwitch { true } else { false } },
                set: { if !$0 { play.dismissConfirmation() } })
    }

    private var archiveFailed: Binding<Bool> {
        Binding(get: { if case .failed = play.modeSwitch { true } else { false } },
                set: { if !$0 { play.dismissArchiveFailure() } })
    }
}
