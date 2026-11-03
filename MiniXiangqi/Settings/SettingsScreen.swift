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

import SwiftUI
#if os(iOS)
import CoreHaptics
#endif

struct SettingsScreen: View {

    @AppStorage("sound.enabled") private var sound = true
    @AppStorage("haptics.enabled") private var haptics = true
    @AppStorage("deleteConfirmation.enabled") private var confirmsDeletion = true
    @AppStorage("placementConfirmation.enabled") private var confirmsPlacement = false
    @AppStorage(PieceSymbols.key) private var symbols: PieceSymbols = .hanzi
    @AppStorage(NotationStyle.key) private var notation: NotationStyle = .resolvedForInterfaceLanguage
    @AppStorage(FirstMoverChoice.key) private var firstMover = FirstMoverChoice.humanFirst.name
    @AppStorage(AiLevel.key) private var aiLevel = AiLevel.standard.name

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
    }

    // The groups, each its own property: one Form body carrying all of them
    // stopped type-checking in reasonable time, and a section is a
    // self-contained thing anyway.

    private var board: some View {
        Section {
            Picker("settings.symbols.label", selection: $symbols) {
                Text("settings.symbols.hanzi").tag(PieceSymbols.hanzi)
                Text("settings.symbols.icons").tag(PieceSymbols.icons)
            }
            .accessibilityIdentifier("settings-symbols")

            Picker("settings.notation.label", selection: $notation) {
                Text("settings.notation.traditional").tag(NotationStyle.traditional)
                Text("settings.notation.wxf").tag(NotationStyle.wxf)
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
    /// 触感 is **absent** on a device with no haptic hardware, such as most
    /// iPads, rather than present and dead. A Mac always offers it: whether the
    /// trackpad can answer is the system's, per machine.
    private var feedback: some View {
        Section {
            Toggle("settings.sound.label", isOn: $sound)
                .accessibilityIdentifier("settings-sound")
            if Self.offersHaptics {
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
    private static var offersHaptics: Bool {
        #if os(iOS)
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #else
        true
        #endif
    }

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
