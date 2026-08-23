// Bringing a friend into the game, as the person in front of the screen meets
// it.
//
// docs/interaction-design.md, "Online play": the surface carries the side the
// proposer takes — which is the shared frame's, in the same two words nearby
// play uses — and "the two ways of bringing the friend: the system's own
// invitation, and a party code the system mints … beside a field for entering
// the one a friend said".
//
// **There is no room and no list**, which is the whole of what this section
// differs by: nobody is out there to be found, and the player is choosing a
// friend rather than a device. So there is nothing to pick from and nothing to
// press once they have chosen — the game goes out by itself the moment the
// friend arrives, and what stands here until then says so.
//
// **A code carries its own game.** Entering one a friend said joins the game
// that friend is offering whatever row raised this surface, because the game is
// the proposal the other device sends over the connection this makes — never
// something read out of the code.
//
// The words are the app's and the code is the system's: no sentence here names
// what carries the game, and the code itself is data rather than copy.

import SwiftUI

struct OnlineProposeSheet: View {
    let flow: NearbyFlow
    let game: GameKind
    let party: OnlineParty

    /// The code a friend said, as it is being typed. It lives with the field
    /// rather than with the party: it is a draft the surface discards, and
    /// nothing outside this screen has any use for a half-typed code.
    @State private var typed = ""

    var body: some View {
        ProposeSheet(flow: flow, game: game) {
            friend
            partyCode
        }
    }

    // MARK: - The friend

    /// The system's own invitation, and what stands while the friend is on
    /// their way.
    ///
    /// **The invitation is the one obvious next action on this surface**, and
    /// therefore the one thing on it the tint rule allows. Pressing it hands
    /// over to Game Center's own screen, where the friend is chosen; nothing
    /// about that screen is this app's, and no word on it was written here.
    @ViewBuilder
    private var friend: some View {
        Section {
            if flow.invited != nil {
                Text("nearby.waitingForAnswer")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nearby-waiting")
            } else {
                Button("online.invite") { party.invite() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("online-invite")
            }
        } header: {
            Text("online.friend")
        } footer: {
            Text("online.friend.footer")
        }
    }

    // MARK: - The code

    /// The code this device is offering, and the field for the one a friend
    /// said.
    ///
    /// **The code is shown where there is one and nothing stands in for it
    /// where there is not.** It is minted by the system against an activity the
    /// account may not carry, and a device that cannot be given one cannot be
    /// told anything useful about why — so the section is the field alone
    /// there, which is still a way in.
    @ViewBuilder
    private var partyCode: some View {
        Section {
            if let code = party.code {
                LabeledContent("online.code.yours") {
                    // The code is the system's own value, never translated and
                    // never re-spelled here. Monospaced because it is read
                    // aloud character by character and copied by eye.
                    Text(verbatim: code)
                        .monospaced()
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("online-code")
            }

            TextField("online.code.enter", text: $typed)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .onSubmit(join)
                .accessibilityIdentifier("online-code-field")

            Button("online.code.join", action: join)
                // A control is offered exactly where the act behind it would be
                // allowed, and what a code *is* is the system's own answer.
                .disabled(!party.canJoin(typed) || party.isJoining)
                .accessibilityIdentifier("online-code-join")
        } header: {
            Text("online.code")
        } footer: {
            Text("online.code.footer")
        }
    }

    private func join() {
        party.join(typed)
    }
}
