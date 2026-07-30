// The Settings destination: the preferences the app keeps, and nothing else.
//
// docs/product.md, "Product navigation": Settings is the third primary
// destination, it holds the persistent preferences, it stores no game data, and
// changing one never alters an active game. It holds no interface-language
// control either — the operating system owns the language, and a control of ours
// would be a second source of truth for it.
//
// Issue #64's Stage 5 design fixes the shape: a grouped Form of three groups.
// The board's two choices sit together under 棋盘 because both are about what the
// board shows and because they are independent of each other — a learner may want
// 图标 discs beside the 中文 list they are learning to read. The two feedback
// switches are their own group with no header, of equal standing and neither
// nested under the other. 删除前确认 is a group of its own so that the one footer
// that matters is unmistakably about it: turning it off makes a deletion
// immediate, and a deletion cannot be undone.
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
    @State private var symbols = Preferences.pieceSymbols.value()
    @State private var notation = Preferences.notationStyle.value()

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.section.board") {
                    Picker("settings.symbols.label", selection: $symbols) {
                        Text("settings.symbols.hanzi")
                            .tag(Preferences.PieceSymbols.hanzi)
                        Text("settings.symbols.icons")
                            .tag(Preferences.PieceSymbols.icons)
                    }
                    .accessibilityIdentifier("settings-symbols")

                    Picker("settings.notation.label", selection: $notation) {
                        Text("settings.notation.traditional")
                            .tag(Preferences.NotationStyle.traditional)
                        Text("settings.notation.wxf")
                            .tag(Preferences.NotationStyle.wxf)
                    }
                    .accessibilityIdentifier("settings-notation")
                }

                Section {
                    Toggle("settings.sound.label", isOn: $sound)
                        .accessibilityIdentifier("settings-sound")
                    Toggle("settings.haptics.label", isOn: $haptics)
                        .accessibilityIdentifier("settings-haptics")
                }

                Section {
                    Toggle("settings.confirmDelete.label", isOn: $confirmsDeletion)
                        .accessibilityIdentifier("settings-confirm-delete")
                } footer: {
                    Text("settings.confirmDelete.footer")
                        .accessibilityIdentifier("settings-confirm-delete-footer")
                }
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
        .onChange(of: symbols) { Preferences.pieceSymbols.set(symbols) }
        .onChange(of: notation) { Preferences.notationStyle.set(notation) }
    }
}
