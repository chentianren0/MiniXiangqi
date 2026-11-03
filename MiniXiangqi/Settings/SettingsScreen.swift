// No interface-language control: the operating system owns the language, and
// ours would be a second source of truth. Groups are ordered by what a
// preference reaches, nearest first; a footer stands only where reach or
// consequence needs saying.
//
// Settings is silent: sound is an event of the board, not of a switch.

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
            // Grouped is the style that gives a section its header and footer
            // on macOS.
            .formStyle(.grouped)
            .navigationTitle("nav.settings")
        }
    }

    // The groups, each its own property: one Form body carrying all of them
    // stopped type-checking in reasonable time.

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
            // The surprise the footer answers: a jieqi move list ignores the
            // notation preference.
            Text("settings.board.footer")
                .accessibilityIdentifier("settings-board-footer")
        }
    }

    /// They initialize a draft only: an active game's side and level were
    /// frozen when it was created.
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

    /// 触感 is absent, not dead, on a device with no haptic hardware, such as
    /// most iPads. A Mac always offers it: whether the trackpad can answer is
    /// the system's, per machine.
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

    private static var offersHaptics: Bool {
        #if os(iOS)
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #else
        true
        #endif
    }

    /// The footer says what the flow is rather than warning: nothing here is
    /// irreversible, and Undo recovers either way.
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

    /// Pushed onto Settings' own stack rather than presented: nothing about it
    /// is modal.
    private var about: some View {
        Section {
            NavigationLink("about.title") { AboutScreen() }
                .accessibilityIdentifier("settings-about")
        }
    }
}
