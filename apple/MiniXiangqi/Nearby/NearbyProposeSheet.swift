// Reaching somebody in the room, and answering somebody who offered a game.
//
// docs/interaction-design.md, "Nearby play". The sheet is raised by a game's own
// nearby row; the side is the shared frame's, and what this adds is the way the
// two devices reach each other — the devices in the room and the invitation to
// one of them. Pairing lives on the same surface because it is the same errand,
// and it is done once per pair of devices: the system's own pairing, which
// outlives the app.
//
// **The section is built on every platform, and pairing is the one part that is
// not.** The room and the invitation are the shape a local proposal has
// wherever two devices can reach each other; pairing is the system's own
// peer-to-peer errand, and its views exist only where that system service does.

import SwiftUI

#if os(iOS)
// Pairing's own frameworks, imported where pairing is built. Neither exists on
// macOS, and nothing outside the pairing section names either of them.
import DeviceDiscoveryUI
import WiFiAware
#endif

struct NearbyProposeSheet: View {
    let flow: NearbyFlow
    let game: GameKind

    var body: some View {
        ProposeSheet(flow: flow, game: game) {
            devices
            pairing
        }
    }

    // MARK: - The room

    @ViewBuilder
    private var devices: some View {
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
                invite
            }
        } header: {
            Text("nearby.devices")
        }
    }

    /// One device, chosen by pressing it. A room usually holds one, so the first
    /// is chosen already and the row is a confirmation rather than a step.
    private func deviceRow(_ device: NearbyPeer, at index: Int) -> some View {
        Button {
            flow.chosenPeer = device.peer
        } label: {
            HStack(spacing: 8) {
                // The device's own name where the system has one, which is data
                // rather than copy and is never translated — and the one
                // neutral label where it has none, which is copy and is. What a
                // row never carries is an identity: that is a diagnostic, and
                // this transport's own would spell out a carrier besides.
                Text(verbatim: device.label.text)
                Spacer(minLength: 0)
                if flow.chosenDevice?.peer == device.peer {
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

    /// The one obvious next action on this sheet, and therefore the one thing
    /// on it the tint rule allows.
    @ViewBuilder
    private var invite: some View {
        Button("nearby.invite") {
            guard let device = flow.chosenDevice else { return }
            flow.invite(device, to: game)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!flow.canInvite)
        .accessibilityIdentifier("nearby-invite")
    }

    // MARK: - Pairing

    /// The one place the two devices differ, once per pair of devices: somebody
    /// shows, somebody picks. Both are offered on both devices, since either can
    /// take either part. Pinned to the one declared service, because pairing
    /// grants access to the device rather than to a service.
    ///
    /// **The system's pairing views are built only where the radio is.** They
    /// are a hand-off to a system service that pairs two devices over
    /// peer-to-peer Wi-Fi, and where that does not exist the hand-off does not
    /// either: measured on a Simulator, which says in its own log that it does
    /// not support peer-to-peer Wi-Fi and then terminates the app that asked.
    /// There is nothing to pair with there, so the honest row says so.
    ///
    /// **This is the only thing in the feature the hardware decides.** The rows
    /// on the home, this sheet, the room and every game stand on a device with
    /// no radio, because reaching another device does not need one; what a
    /// device with no radio cannot do is the one errand this section is —
    /// pairing, which is the system's own and happens over that radio. What
    /// stands here instead says only that this device cannot pair, and names no
    /// reason for it, as no word this application writes may.
    ///
    /// **And they are built only where the system offers them at all**: the
    /// frameworks the two views come from ship on iPhone and iPad and nowhere
    /// else. Where they are absent the section is absent with them, rather than
    /// standing empty over a sentence about a device that was never going to
    /// pair.
    @ViewBuilder
    private var pairing: some View {
        #if os(iOS)
        Section {
            if flow.reach.hasRadio,
               let publishable = WAPublishableService.boardGame,
               let subscribable = WASubscribableService.boardGame {
                DevicePairingView(.wifiAware(.connecting(to: publishable,
                                                         from: .userSpecifiedDevices))) {
                    Label("nearby.discoverable",
                          systemImage: "dot.radiowaves.left.and.right")
                } fallback: {
                    unavailable
                }
                .accessibilityIdentifier("nearby-pair-publish")

                DevicePicker(.wifiAware(.connecting(to: .userSpecifiedDevices,
                                                    from: subscribable))) { _ in
                    // Pairing is the system's and it keeps it. Nothing is done
                    // with the endpoint here: the transport dials every paired
                    // device by itself, and a connection is not a game.
                } label: {
                    Label("nearby.findDevice", systemImage: "magnifyingglass")
                } fallback: {
                    unavailable
                }
                .accessibilityIdentifier("nearby-pair-browse")
            } else {
                unavailable
            }
        } header: {
            Text("nearby.pairing")
        } footer: {
            Text("nearby.pairing.footer")
        }
        #endif
    }

    #if os(iOS)
    private var unavailable: some View {
        Label("nearby.pairing.unavailable", systemImage: "xmark.circle")
            .foregroundStyle(.secondary)
    }
    #endif
}

// MARK: - The two answers that belong above every destination

extension View {
    /// The consent prompt and the refusal, presented over whatever the player is
    /// looking at.
    ///
    /// A confirmation of a consequential act is a system alert, blocking until
    /// it is answered — and accepting starts a game, which is as consequential
    /// as this feature gets. The refusal is the same "it did not happen, nothing
    /// changed" alert the rest of the app uses, and it says which of the
    /// protocol's reasons it was in words rather than in the wire's own code.
    ///
    /// **It is the same alert in the same words whatever carried the
    /// connection**, so it is declared once over whichever flows this device
    /// has and asks each of them whether anything is standing. Only one ever
    /// is: a proposal is a game about to exist, and the library has room for
    /// one game.
    ///
    /// With no flow at all — a platform that reaches nobody — every binding
    /// here is false and every observed value nil, so the declarations stand
    /// and present nothing.
    func nearbyAnswers(_ flows: [NearbyFlow],
                       opening board: @escaping () -> Void) -> some View {
        modifier(NearbyAnswers(flows: flows, opening: board))
    }
}

private struct NearbyAnswers: ViewModifier {
    let flows: [NearbyFlow]
    let opening: () -> Void

    /// Whichever flow has a proposal to answer, and whichever has a refusal to
    /// read.
    private var flow: NearbyFlow? { flows.first { $0.invitation != nil } }
    private var refusing: NearbyFlow? { flows.first { $0.refusal != nil } }

    func body(content: Content) -> some View {
        content
            .alert("alert.nearbyInvite.title", isPresented: inviting) {
                Button("control.decline", role: .cancel) {
                    if let flow, let invitation = flow.invitation {
                        flow.decline(invitation.id)
                    }
                }
                Button("control.accept") {
                    guard let flow, let invitation = flow.invitation else { return }
                    flow.accept(invitation.id)
                    opening()
                }
            } message: {
                Text(invitationMessage)
            }
            // The title says which of the two this is: a game that did not
            // start, or one that was under way and is not any more. The refusal
            // itself knows, because only one of the protocol's reasons ever
            // answers a resume.
            .alert(Text(LocalizedStringKey(refusalTitleKey)), isPresented: refused) {
                Button("control.ok") { refusing?.dismissRefusal() }
            } message: {
                if let refusal = refusing?.refusal {
                    Text(LocalizedStringKey(refusal.messageKey))
                }
            }
    }

    /// What the invitation is: who is asking, which game, and which side this
    /// device would take. The metadata line's own composition, so an invitation
    /// and the game it becomes describe themselves the same way — and the
    /// sentence beneath it says what accepting does, which is the one thing the
    /// line cannot say.
    private var invitationMessage: String {
        guard let flow, let invitation = flow.invitation else { return "" }
        var parts: [String] = []
        // **The alert always names the device.** A proposal arrives from
        // somebody, and a prompt that said only which game and which side would
        // be asking about a game with nobody in it. Where the system holds no
        // name for the device — which is the ordinary state of the side that
        // made itself discoverable when the two were paired — that is the
        // neutral label, the same one its row carries.
        let peer = flow.peers.first { $0.peer == invitation.peer }
        parts.append(NearbyLabel(name: peer?.name, peer: invitation.peer).text)
        // Which side a mover *is* is the game's own naming — 红 where a game
        // moves, 黑 where it places — so it is asked of the one place that
        // answers it, and asked of the game this invitation names. The mover
        // itself never moves: the first mover is `Side.red` in every game,
        // whatever that side's pieces are called.
        if let game = GameKind(rulesID: invitation.rulesID) {
            parts.append(game.localizedName)
            parts.append(game.youAreText(invitation.localMover == .first ? .red : .black))
        }
        return [parts.joined(by: String(localized: "metadata.join")),
                "",
                String(localized: "alert.nearbyInvite.message")].joined(separator: "\n")
    }

    private var inviting: Binding<Bool> {
        Binding(get: { flow?.invitation != nil },
                set: { _ in
                    // Deliberately nothing. The two buttons are the only
                    // answers there are, and each of them makes the invitation
                    // go away by itself — accepting turns it into a game,
                    // declining voids it — so the dismissal that follows has
                    // nothing left to do. Answering *here* would mean a prompt
                    // the system took away for its own reasons had refused a
                    // game on the player's behalf, and a proposal nobody
                    // answered is one that still stands.
                })
    }

    private var refused: Binding<Bool> {
        Binding(get: { refusing != nil },
                set: { if !$0 { refusing?.dismissRefusal() } })
    }

    /// A title is needed whether or not a refusal stands, and the one for a
    /// game that never began is the one this alert is usually about.
    private var refusalTitleKey: String {
        refusing?.refusal?.titleKey ?? "alert.nearbyDeclined.title"
    }
}
