// Reaching somebody nearby: the devices in the room and the invitation to one
// of them. Also the consent prompt and the refusal, shared by both modes.

import SwiftUI

struct NearbyProposeSheet: View {
    let flow: NearbyFlow
    let game: GameKind

    var body: some View {
        ProposeSheet(flow: flow, game: game) {
            Section {
                if flow.peers.isEmpty {
                    Text("nearby.searching")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("nearby-searching")
                } else {
                    ForEach(Array(flow.peers.enumerated()), id: \.element.id) { index, device in
                        deviceRow(device, at: index)
                    }
                }

                if flow.invited != nil {
                    Text("nearby.waitingForAnswer")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("propose-waiting")
                } else {
                    Button("nearby.invite") {
                        guard let device = flow.chosenDevice else { return }
                        flow.invite(device, to: game)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!flow.canInvite)
                    .accessibilityIdentifier("nearby-invite")
                }
            } header: {
                Text("nearby.devices")
            }
        }
    }

    /// One device, chosen by pressing it. A room usually holds one, so the
    /// first is chosen already.
    private func deviceRow(_ device: NearbyPeer, at index: Int) -> some View {
        Button {
            flow.chosenPeer = device.id
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: device.name)
                Spacer(minLength: 0)
                if flow.chosenDevice?.id == device.id {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nearby-device-\(index)")
    }
}

// MARK: - The two answers that belong above every destination

extension View {
    /// The consent prompt and the refusal, presented over whatever the player is
    /// looking at, the same in both modes. Only one flow ever has either: a
    /// proposal is a game about to exist, and the library has room for one.
    func nearbyAnswers(_ flows: [NearbyFlow],
                       opening board: @escaping () -> Void) -> some View {
        modifier(NearbyAnswers(flows: flows, opening: board))
    }
}

private struct NearbyAnswers: ViewModifier {
    let flows: [NearbyFlow]
    let opening: () -> Void

    private var flow: NearbyFlow? { flows.first { $0.invitation != nil } }
    private var refusing: NearbyFlow? { flows.first { $0.refusal != nil } }

    func body(content: Content) -> some View {
        content
            .alert("alert.nearbyInvite.title", isPresented: inviting) {
                Button("control.decline", role: .cancel) { flow?.decline() }
                Button("control.accept") {
                    flow?.accept()
                    opening()
                }
            } message: {
                Text(invitationMessage)
            }
            .alert("alert.nearbyDeclined.title", isPresented: refused) {
                Button("control.ok") { refusing?.dismissRefusal() }
            } message: {
                if let refusal = refusing?.refusal {
                    Text(LocalizedStringKey(refusal.messageKey))
                }
            }
    }

    /// Who is asking, which game, and which side this device would take, in
    /// the metadata line's own composition, then what accepting does.
    private var invitationMessage: String {
        guard let flow, let invitation = flow.invitation else { return "" }
        let parts = [flow.name(of: invitation.peer),
                     invitation.kind.localizedName,
                     invitation.kind.youAreText(invitation.proposerSide.opponent)]
        return [parts.joined(separator: String(localized: "metadata.join")),
                "",
                String(localized: "alert.nearbyInvite.message")].joined(separator: "\n")
    }

    /// The two buttons are the only answers: a prompt the system takes away
    /// for its own reasons has refused nothing.
    private var inviting: Binding<Bool> {
        Binding(get: { flow?.invitation != nil }, set: { _ in })
    }

    private var refused: Binding<Bool> {
        Binding(get: { refusing != nil },
                set: { if !$0 { refusing?.dismissRefusal() } })
    }
}
