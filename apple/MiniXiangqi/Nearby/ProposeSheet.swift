// Offering a game to somebody on another device: the part that is the same
// however the two devices reach each other.
//
// docs/interaction-design.md, "Nearby play" and "Online play". The surface is
// raised by a game's own row, so the game is not chosen again here: what is
// chosen is the side this device takes, and then the way the other player is
// reached. The first of those is one control with two words in it and is the
// same control in both modes — "an online game is the nearby game in everything
// but how the two devices reach each other" — so it is written once, and what
// each mode adds is the section beneath it.
//
// The consent prompt and the refusal are on neither sheet. Both belong above
// every destination: an invitation arrives when it arrives, and a refusal
// answers an invitation the player may have sent minutes ago from a surface
// they have already put away.

import SwiftUI

struct ProposeSheet<Connection: View>: View {
    let flow: NearbyFlow
    let game: GameKind
    /// How the other player is reached — the room and the pairing where the
    /// devices find each other locally, the invitation and the party code where
    /// Game Center carries them.
    @ViewBuilder var connection: () -> Connection

    var body: some View {
        NavigationStack {
            Form {
                // The side is chosen for a game that is about to exist, and
                // not for one that already does: a surface raised to meet
                // again over a standing game is about reaching the other
                // player, and the sides in that game were settled when the two
                // devices agreed to play it.
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
                    // The platform's own close, so the one name this adds is
                    // the platform's rather than a string to translate.
                    Button(role: .close) { flow.dismissSheet() }
                        .accessibilityIdentifier("propose-close")
                }
            }
        }
        .accessibilityIdentifier("propose-sheet")
    }

    /// Which mover this device takes. The proposer chooses, and the other
    /// device takes what is left — which is why the second option names the
    /// other player rather than a colour.
    private var side: some View {
        Section {
            Picker("setup.firstMover", selection: proposerMoves) {
                Text("setup.iMoveFirst").tag(Mover.first)
                Text("nearby.theyMoveFirst").tag(Mover.second)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("propose-side")
        } header: {
            Text("setup.thisGame")
        }
    }

    private var proposerMoves: Binding<Mover> {
        Binding(get: { flow.proposerMoves }, set: { flow.proposerMoves = $0 })
    }
}
