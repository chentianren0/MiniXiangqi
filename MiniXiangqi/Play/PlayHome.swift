// No board on this page: choosing a way to play opens that mode's pre-start
// page, where the preview lives. Every row carries an explicit selection, so
// neither its setup nor its game can fall through to a hidden default. With a
// game active the mode entries stay interactive, and choosing one asks to save
// that game first.

import SwiftUI

struct PlayHome: View {
    let play: PlayState

    var nearby: NearbyFlow?

    /// Its availability is the player's Game Center, not the build's, so it is
    /// asked at every draw and the row comes and goes with it.
    var online: NearbyFlow?

    /// 回到对局 is what opens the session and starts the engine thinking, so the
    /// page needs the policy that game's motion will run under.
    @Environment(\.motionPolicy) private var policy

    var body: some View {
        Form {
            if let summary = play.activeSummary { currentGame(summary) }
            waysToPlay
        }
        // The title is the destination's, since every page in it carries the
        // same one.
        .formStyle(.grouped)
        // The same alert for every combination of modes and game state, so
        // nothing in it interpolates a mode or a state. The metadata rides in
        // the message, set off by a blank line alone, which needs no format
        // string in either language.
        .alert("alert.newGame.title", isPresented: confirming) {
            Button("control.cancel", role: .cancel) { play.dismissConfirmation() }
            Button("control.saveAndContinue") { play.saveAndContinue() }
        } message: {
            Text(confirmationMessage)
        }
        // 重试 repeats exactly the same atomic archive.
        .alert("alert.saveFailed.title", isPresented: archiveFailed) {
            Button("control.cancel", role: .cancel) { play.dismissArchiveFailure() }
            Button("control.tryAgain") { play.saveAndContinue() }
        } message: {
            Text("alert.saveFailed.message")
        }
    }

    // MARK: - The sections

    /// Read from the library's summary: the page holds no session, and the game
    /// goes live only when 回到对局 opens its board.
    private func currentGame(_ summary: ActiveGameSummary) -> some View {
        Section {
            Text(summary.metadataLine)
                .font(.callout)
                // Wraps rather than truncating: every token on it is content.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("home-current-game")

            // The one obvious next action while a game is going, so the one
            // tinted control.
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
            // Xiangqi's alone, as the one game whose rules say which positions
            // it may be set up in. It opens the editor, which starts an ordinary
            // Free Play game.
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

        // No Human versus AI row: Jieqi has no AI. A proposal carries the seed
        // both devices deal from, so nearby and online play carry it.
        Section {
            entry(PlaySelection(game: .jieqi, mode: .freePlay),
                  "mode.freePlay", "mode-jieqi-free-play")
            reachEntry(nearby, "mode.nearby", .jieqi, "mode-jieqi-nearby")
            reachEntry(online, "mode.online", .jieqi, "mode-jieqi-online")
        } header: {
            Text(GameKind.jieqi.localizedName)
        }

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

    /// A row with a chevron, not a button: choosing goes to a page, not a game;
    /// only 开始对局 on that page creates a game.
    private func entry(_ selection: PlaySelection, _ title: LocalizedStringKey,
                       _ identifier: String) -> some View {
        row(title, identifier) { play.choose(selection) }
    }

    /// The room this device is in, then anywhere. A row stands only where a game
    /// could be carried, and is otherwise absent rather than disabled: a row
    /// that can never be pressed is a promise nobody can keep.
    ///
    /// The online answer can change under the reader. Where a game is already
    /// going in this game and mode, the flow leads the row back into it.
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
