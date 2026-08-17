// The Settings destination: the preferences the app keeps, and nothing else.
//
// docs/product.md, "Product navigation": Settings is the third primary
// destination, it holds the persistent preferences, it stores no game data, and
// changing one never alters an active game. It holds no interface-language
// control either — the operating system owns the language, and a control of ours
// would be a second source of truth for it.
//
// The shape is a grouped Form, ordered by what a preference reaches, nearest
// first: what the board shows (棋盘), what a move gives back (the two feedback
// switches), how an action commits (落子前确认, 删除前确认), what the next game
// opens with (人机对弈默认设置), and last the way to what the application is
// (关于). The board's two choices sit together because both are about what the
// board shows and they are independent of each other — a learner may want 图标
// discs beside the 中文 list they are learning to read — and their footer says
// how far the pair reaches, jieqi's own move reading being the one surprise
// worth a sentence. The two feedback switches are their own group with no
// header, of equal standing and neither nested under the other. 落子前确认 and
// 删除前确认 are each a group of their own so that each footer is unmistakably
// about the switch above it: one changes how a stone is placed, the other
// makes a deletion immediate, and a deletion cannot be undone. 人机对弈默认设置
// is headed and footed because its two values need saying what they are for:
// they initialize the next game's setup and never reach the game already on
// the board. 关于 is not a preference at all: it is a page rather than a
// control, so it takes a group of its own at the foot where nothing above it
// has to make room. A footer stands only where reach or consequence needs
// saying — a footer under every group is a screen nobody reads.
//
// **Settings is silent.** Sound is an event of the board, per
// docs/interaction-design.md § Sound and haptics, and a screen that clicked back
// at every switch would be the app talking about itself.
//
// Every control reads and writes through `Preferences` — the same reader its
// consumers use — rather than through `@AppStorage`, which would state each
// preference's default a second time, in a property wrapper, where a screen that
// disagreed with the board about what an unset key means would be invisible until
// somebody's first launch.

import SwiftUI

struct SettingsScreen: View {

    /// The five values, mirrored into view state and written through as they
    /// change.
    ///
    /// Mirrored because a control needs somewhere to put the value it is given,
    /// and read at construction rather than kept anywhere longer-lived because
    /// the navigation container rebuilds this screen on every visit: the mirror
    /// is never older than the visit that made it, and nothing else in the app
    /// writes these keys.
    @State private var sound = Preferences.sound.value()
    @State private var haptics = Preferences.haptics.value()
    @State private var confirmsDeletion = Preferences.deleteConfirmation.value()
    @State private var confirmsPlacement = Preferences.placementConfirmation.value()
    @State private var symbols = Preferences.pieceSymbols.value()
    @State private var notation = Preferences.notationStyle.value()
    @State private var firstMover = Preferences.defaultFirstMover.value()
    @State private var aiLevel = Preferences.defaultAiLevel.value()

    var body: some View {
        NavigationStack {
            Form {
                board
                feedback
                placement
                deletion
                humanVersusAIDefaults
                about
            }
            // The macOS-native presentation of a preference list, and the one
            // that gives a section its header and its footer.
            .formStyle(.grouped)
            .navigationTitle("nav.settings")
        }
        // Written where it is read from, as it changes: a preference screen has
        // no Save button, and the next landing or the next deletion is entitled
        // to the new answer rather than to the one the app launched with.
        .onChange(of: sound) { Preferences.sound.set(sound) }
        .onChange(of: haptics) { Preferences.haptics.set(haptics) }
        .onChange(of: confirmsDeletion) {
            Preferences.deleteConfirmation.set(confirmsDeletion)
        }
        .onChange(of: confirmsPlacement) {
            Preferences.placementConfirmation.set(confirmsPlacement)
        }
        .onChange(of: symbols) { Preferences.pieceSymbols.set(symbols) }
        .onChange(of: notation) { Preferences.notationStyle.set(notation) }
        .onChange(of: firstMover) { Preferences.defaultFirstMover.set(firstMover) }
        .onChange(of: aiLevel) { Preferences.defaultAiLevel.set(aiLevel) }
    }

    // The groups, each its own property: one Form body carrying all of them
    // stopped type-checking in reasonable time, and a section is a
    // self-contained thing anyway.

    /// The tags are the stored names themselves. A picker row is a choice being
    /// written to a preference, and the preference holds a name: a type in
    /// between would be one this screen invented for a choice whose consumer
    /// already has its own.
    private var board: some View {
        Section {
            Picker("settings.symbols.label", selection: $symbols) {
                Text("settings.symbols.hanzi").tag("hanzi")
                Text("settings.symbols.icons").tag("icons")
            }
            .accessibilityIdentifier("settings-symbols")

            Picker("settings.notation.label", selection: $notation) {
                Text("settings.notation.traditional").tag("traditional")
                Text("settings.notation.wxf").tag("wxf")
            }
            .accessibilityIdentifier("settings-notation")
        } header: {
            Text("settings.section.board")
        } footer: {
            // The scope note: the stone games have no symbols to swap, and the
            // one genuine surprise — flipping the notation preference in a
            // jieqi game and seeing its move list unmoved — is what the
            // sentence answers.
            Text("settings.board.footer")
                .accessibilityIdentifier("settings-board-footer")
        }
    }

    /// The two values a new human-versus-AI game's setup page opens with. They
    /// initialize a draft and nothing more: an active game's own side and level
    /// were frozen when it was created, and changing either of these never
    /// reaches it — which is what the footer says out loud.
    private var humanVersusAIDefaults: some View {
        Section {
            Picker("settings.defaults.firstMover", selection: $firstMover) {
                Text("setup.iMoveFirst").tag("human-first")
                Text("setup.aiMovesFirst").tag("ai-first")
                Text("setup.random").tag("random")
            }
            .accessibilityIdentifier("settings-first-mover")

            Picker("settings.defaults.aiLevel", selection: $aiLevel) {
                Text("setup.level.fast").tag("fast")
                Text("setup.level.standard").tag("standard")
                Text("setup.level.deep").tag("deep")
            }
            .accessibilityIdentifier("settings-ai-level")
        } header: {
            Text("settings.defaults.group")
        } footer: {
            Text("settings.defaults.footer")
                .accessibilityIdentifier("settings-defaults-footer")
        }
    }

    /// The two switches, of equal standing and neither conditioned on the other
    /// — except by the hardware, which conditions one of them out of existence.
    ///
    /// 触感 is **absent** on a device with no engine to drive, rather than
    /// present and dead: "on a device without them the toggle is unavailable
    /// rather than silently ineffective". `Haptics` owns the question and the
    /// reasoning for answering it by removal; what matters here is that the group
    /// survives losing a row — it has no header to be left stranded, and 声音
    /// stands alone without meaning anything different.
    private var feedback: some View {
        Section {
            Toggle("settings.sound.label", isOn: $sound)
                .accessibilityIdentifier("settings-sound")
            if Haptics.isOffered {
                Toggle("settings.haptics.label", isOn: $haptics)
                    .accessibilityIdentifier("settings-haptics")
            }
        }
    }

    /// 落子前确认: the optional pending stone of the placement games.
    ///
    /// A group of its own with a footer, the shape 删除前确认 already set for an
    /// optional confirmation — and the footer says what the flow *is* rather
    /// than warning about it, because nothing here is irreversible: what the
    /// switch buys is a second look before a stone goes down, and Undo is the
    /// recovery whichever way it stands.
    private var placement: some View {
        Section {
            Toggle("settings.confirmPlacement.label", isOn: $confirmsPlacement)
                .accessibilityIdentifier("settings-confirm-placement")
        } footer: {
            Text("settings.confirmPlacement.footer")
                .accessibilityIdentifier("settings-confirm-placement-footer")
        }
    }

    private var deletion: some View {
        Section {
            Toggle("settings.confirmDelete.label", isOn: $confirmsDeletion)
                .accessibilityIdentifier("settings-confirm-delete")
        } footer: {
            Text("settings.confirmDelete.footer")
                .accessibilityIdentifier("settings-confirm-delete-footer")
        }
    }

    /// The way to `AboutScreen`, and the screen's only row that writes nothing.
    /// It is pushed onto Settings' own stack rather than presented, because it
    /// is a page walked into from a destination's root — the platform's back
    /// control is what leaves it, and nothing about it is modal.
    private var about: some View {
        Section {
            NavigationLink("about.title") { AboutScreen() }
                .accessibilityIdentifier("settings-about")
        }
    }
}
