// The Play home: what to play, and the game already going.
//
// docs/interaction-design.md, "Starting and configuring a game": the Play
// destination's root is an independent page for choosing what to play, and there
// is no board anywhere on it. Selecting a way to play opens that mode's
// pre-start state, which is where the preview board lives.
//
// **Each game has a section of its own, and that is the whole of the
// extensibility.** A section offers the ways to play that game that the app can
// actually carry: the two xiangqi games offer all three, and the placement games
// offer 自由对弈 while the other two are being built. The selection carried by
// every row is explicit, so neither its setup nor a game created from it can
// fall through to a hidden default.
//
// docs/interaction-design.md, "Saving the active game before choosing a new
// mode": with a game active the page shows its metadata and a direct Resume, and
// **both mode entries stay interactive**. Selecting one presents the accepted
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
        // destination's rather than this page's, because all three pages carry
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
            nearbyEntry(.xiangqi, "mode-xiangqi-nearby")
        } header: {
            Text(GameKind.xiangqi.localizedName)
        }

        Section {
            entry(PlaySelection(game: .miniXiangqi, mode: .humanVersusAI),
                  "mode.humanVersusAI", "mode-mini-xiangqi-human-versus-ai")
            entry(PlaySelection(game: .miniXiangqi, mode: .freePlay),
                  "mode.freePlay", "mode-mini-xiangqi-free-play")
            nearbyEntry(.miniXiangqi, "mode-mini-xiangqi-nearby")
        } header: {
            Text(GameKind.miniXiangqi.localizedName)
        }

        // The placement games, in the accepted order: Gomoku, then Renju as its
        // stricter sibling.
        //
        // **Two rows each for now**: 附近对弈 waits on the game modules a nearby
        // placement game needs, and until they exist a row leading to a board
        // that could not carry a game would be a promise the app cannot keep. A
        // row arriving late is the smaller cost.
        Section {
            entry(PlaySelection(game: .gomoku15, mode: .humanVersusAI),
                  "mode.humanVersusAI", "mode-gomoku-human-versus-ai")
            entry(PlaySelection(game: .gomoku15, mode: .freePlay),
                  "mode.freePlay", "mode-gomoku-free-play")
        } header: {
            Text(GameKind.gomoku15.localizedName)
        }

        Section {
            entry(PlaySelection(game: .renju, mode: .humanVersusAI),
                  "mode.humanVersusAI", "mode-renju-human-versus-ai")
            entry(PlaySelection(game: .renju, mode: .freePlay),
                  "mode.freePlay", "mode-renju-free-play")
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

    /// The third row in each game's section: playing that game with somebody in
    /// the room.
    ///
    /// **It stands wherever either way of reaching another device could carry a
    /// game**, which on iPhone and iPad is always — one of the two needs no
    /// hardware of its own. It is absent altogether on a Mac, which has neither
    /// the entitlement nor the system's pairing UI: a row that could never be
    /// pressed would be a promise the platform cannot keep, and no explanation
    /// would help a reader who cannot change the answer.
    ///
    /// Where a nearby game is already going in this row's own game, the row
    /// leads back into it, exactly as the current-game card above leads back
    /// into a local one. The rest of that decision is the flow's.
    @ViewBuilder
    private func nearbyEntry(_ game: GameKind, _ identifier: String) -> some View {
        #if os(iOS)
        if let nearby, nearby.isAvailable {
            row("mode.nearby", identifier) { nearby.open(game) }
        }
        #endif
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
