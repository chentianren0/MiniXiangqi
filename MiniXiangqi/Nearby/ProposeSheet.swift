// Offering a game to somebody on another device: the part both modes share.
// The surface is raised by a game's own row, so what is chosen here is the side
// this device takes; each mode adds how the other player is reached.
//
// The consent prompt and the refusal belong above every destination instead:
// an invitation arrives when it arrives, and a refusal may answer one sent from
// a surface the player has already put away.

import SwiftUI

struct ProposeSheet<Connection: View>: View {
    let flow: NearbyFlow
    let game: GameKind
    /// How the other player is reached — the devices in the room where they
    /// find each other locally, the invitation and the party code where Game
    /// Center carries them.
    @ViewBuilder var connection: () -> Connection

    var body: some View {
        NavigationStack {
            Form {
                // No side to choose when meeting again over a game in play.
                if !flow.isMeetingAgain { side }
                connection()
            }
            .formStyle(.grouped)
            .navigationTitle(Text(game.localizedName))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { flow.dismissSheet() }
                        .accessibilityIdentifier("propose-close")
                }
            }
        }
    }

    /// Which side this device takes: the first mover, or the other. Not
    /// colours, because each game names its first mover.
    private var side: some View {
        Section {
            Picker("setup.firstMover", selection: proposerSide) {
                Text("setup.iMoveFirst").tag(Side.red)
                Text("nearby.theyMoveFirst").tag(Side.black)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("propose-side")
        } header: {
            Text("setup.thisGame")
        }
    }

    private var proposerSide: Binding<Side> {
        Binding(get: { flow.proposerSide }, set: { flow.proposerSide = $0 })
    }
}
