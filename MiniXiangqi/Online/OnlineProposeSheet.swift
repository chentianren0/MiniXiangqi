// Bringing a friend into the game: the system's invitation, or a party code
// beside a field for the one a friend said. There is no list of devices, and
// nothing to press once the friend arrives: the game goes out by itself.

import SwiftUI

struct OnlineProposeSheet: View {
    let flow: NearbyFlow
    let game: GameKind
    let party: OnlineParty

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
    @ViewBuilder
    private var friend: some View {
        Section {
            if flow.invited != nil {
                Text("nearby.waitingForAnswer")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("propose-waiting")
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

    /// The code this device is offering, where Game Center minted one, and the
    /// field for the one a friend said.
    @ViewBuilder
    private var partyCode: some View {
        Section {
            if let code = party.code {
                LabeledContent("online.code.yours") {
                    // Monospaced: it is read aloud character by character.
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
