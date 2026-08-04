// The nearby-play spike's screen. Branch-only experiment code (issue #114):
// English-only by intention — none of this copy enters the catalog, because
// none of it is product copy. The product feature this spike informs is
// designed separately.
//
// The screen's shape is the experiment's checklist. Pairing offers both system
// roles side by side — one device shows itself, the other picks — because that
// asymmetry is Apple's and happens once. Everything below it is symmetric:
// one Start button runs publish and subscribe together on both devices.

#if os(iOS)

import SwiftUI
import DeviceDiscoveryUI
import WiFiAware

struct NearbySpikeScreen: View {
    @State private var session = NearbySpikeSession()

    var body: some View {
        NavigationStack {
            Group {
                if WACapabilities.supportedFeatures.contains(.wifiAware) {
                    supported
                } else {
                    ContentUnavailableView {
                        Label { Text(verbatim: "Wi-Fi Aware unavailable") } icon: {
                            Image(systemName: "wifi.slash")
                        }
                    } description: {
                        Text(verbatim: "This device or platform does not support the Wi-Fi Aware framework, so the nearby experiment cannot run here.")
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Nearby (spike)"))
        }
        .task {
            session.watchPairedDevices()
            applyLaunchConfiguration()
        }
    }

    /// Driven-run support, in the repo's `DebugLaunch` style: a harness can
    /// preset the experiment and start it from the command line —
    /// `-mxq-nearby-roles both|publish|subscribe`, `-mxq-nearby-stack tcp|udp`,
    /// `-mxq-nearby-autostart` — instead of walking the pickers by tap.
    private func applyLaunchConfiguration() {
        #if DEBUG
        if let roles = DebugLaunch.argument(after: "-mxq-nearby-roles"),
           let chosen = SpikeRoles(rawValue: roles) {
            session.roles = chosen
        }
        if let stack = DebugLaunch.argument(after: "-mxq-nearby-stack") {
            session.transport = stack == "udp" ? .udpRealtime : .tcpBulk
        }
        if DebugLaunch.contains("-mxq-nearby-autostart") {
            session.start()
        }
        #endif
    }

    private var supported: some View {
        Form {
            pairing
            pairedDevices
            mode
            controls
            peers
            log
        }
        .formStyle(.grouped)
    }

    /// The experiment variables. One at a time: the roles picker isolates the
    /// four-radio-operations question, the stack picker holds Apple's
    /// known-working sample shape (UDP + realtime) against the game's shape
    /// (TCP + bulk).
    private var mode: some View {
        Section {
            Picker(selection: $session.roles) {
                Text(verbatim: "Both").tag(SpikeRoles.both)
                Text(verbatim: "Publish only").tag(SpikeRoles.publish)
                Text(verbatim: "Subscribe only").tag(SpikeRoles.subscribe)
            } label: {
                Text(verbatim: "Roles")
            }

            Picker(selection: $session.transport) {
                Text(verbatim: SpikeTransport.tcpBulk.label).tag(SpikeTransport.tcpBulk)
                Text(verbatim: SpikeTransport.udpRealtime.label).tag(SpikeTransport.udpRealtime)
            } label: {
                Text(verbatim: "Stack")
            }
        } header: {
            Text(verbatim: "Experiment mode")
        } footer: {
            Text(verbatim: "Set before Start; both devices must use the same stack. For role isolation, set one device to Publish only and the other to Subscribe only.")
        }
        .disabled(session.isRunning)
    }

    /// The one place the two devices differ, once per pair of devices: someone
    /// shows, someone picks. Both buttons exist on both devices so either can
    /// take either role.
    private var pairing: some View {
        Section {
            DevicePairingView(.wifiAware(.connecting(to: .spikeService, from: .userSpecifiedDevices))) {
                Label { Text(verbatim: "Make this device discoverable") } icon: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
            } fallback: {
                Label { Text(verbatim: "Discoverable mode unavailable") } icon: {
                    Image(systemName: "xmark.circle")
                }
            }

            DevicePicker(.wifiAware(.connecting(to: .userSpecifiedDevices, from: .spikeService))) { endpoint in
                session.log("Paired via picker: \(String(describing: endpoint))")
            } label: {
                Label { Text(verbatim: "Find a nearby device") } icon: {
                    Image(systemName: "magnifyingglass")
                }
            } fallback: {
                Label { Text(verbatim: "Device picker unavailable") } icon: {
                    Image(systemName: "xmark.circle")
                }
            }
        } header: {
            Text(verbatim: "Pair (once per pair of devices)")
        } footer: {
            Text(verbatim: "One device shows itself, the other picks it — that direction is Apple's pairing design and does not matter afterwards.")
        }
    }

    private var pairedDevices: some View {
        Section {
            if session.pairedDevices.isEmpty {
                Text(verbatim: "No paired devices yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.pairedDevices, id: \.id) { device in
                    Text(verbatim: device.name ?? "Unnamed device")
                }
            }
        } header: {
            Text(verbatim: "Paired devices")
        }
    }

    private var controls: some View {
        Section {
            if session.isRunning {
                Button(role: .destructive) {
                    session.stop()
                } label: {
                    Text(verbatim: "Stop")
                }
            } else {
                Button {
                    session.start()
                } label: {
                    Text(verbatim: "Start nearby session (publish + subscribe)")
                }
            }

            Toggle(isOn: $session.autoRestart) {
                Text(verbatim: "Restart after failures")
            }

            LabeledContent {
                Text(verbatim: session.listenerState)
            } label: {
                Text(verbatim: "Listener")
            }

            LabeledContent {
                Text(verbatim: session.browserState)
            } label: {
                Text(verbatim: "Browser")
            }
        } header: {
            Text(verbatim: "Session (symmetric — press Start on both devices)")
        }
    }

    private var peers: some View {
        Section {
            if session.peers.isEmpty {
                Text(verbatim: "No connections.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.peers) { peer in
                    PeerRow(peer: peer)
                }
            }
        } header: {
            Text(verbatim: "Connections")
        } footer: {
            Text(verbatim: "Two rows for the same device means the publish and subscribe paths crossed — one of the facts this experiment is here to observe.")
        }
    }

    private var log: some View {
        Section {
            ForEach(session.lines.suffix(80).reversed()) { line in
                Text(verbatim: "\(line.at.formatted(date: .omitted, time: .standard))  \(line.text)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: "Log (newest first)")
        }
    }
}

private struct PeerRow: View {
    let peer: SpikePeer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: peer.direction == .incoming
                          ? "arrow.down.left.circle" : "arrow.up.right.circle")
                    Text(verbatim: title)
                    Spacer()
                    if peer.isReady {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.green)
                            .imageScale(.small)
                    }
                }
                Text(verbatim: details(at: context.date))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        peer.peerName ?? peer.deviceName ?? "Connection \(peer.id.suffix(8))"
    }

    private func details(at now: Date) -> String {
        var parts: [String] = ["\(peer.direction.rawValue)"]
        if let roundTrip = peer.lastRoundTrip {
            parts.append("rtt \(NearbySpikeSession.milliseconds(roundTrip))")
        }
        if let signal = peer.signalStrength {
            parts.append(String(format: "signal %.2f", signal))
        }
        if let lastHeard = peer.lastHeard {
            parts.append(String(format: "heard %.0fs ago", now.timeIntervalSince(lastHeard)))
        }
        parts.append("ping \(peer.pingsSent)/\(peer.pongsReceived)")
        return parts.joined(separator: "  ·  ")
    }
}

#endif
