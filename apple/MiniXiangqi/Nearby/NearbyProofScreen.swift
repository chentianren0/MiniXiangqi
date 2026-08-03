// The internal, physical-device proof for the Apple nearby transport.
//
// This is deliberately not a game mode and not a BoardGame protocol surface.
// It proves one thing before Stage 2 builds on it: two devices that a person
// explicitly paired and selected can exchange one fixed, opaque core-owned
// value over a peer-bound TLS 1.3 Wi-Fi Aware connection. Nothing here enters
// the game, history, preferences, logs, or persistent storage.

#if os(iOS) && !targetEnvironment(macCatalyst)
import DeviceDiscoveryUI
import Foundation
import Network
import Observation
import Security
import SwiftUI
import WiFiAware

struct NearbyProofScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var proof = NearbyProofModel()

    var body: some View {
        Form {
            introduction

            if proof.availability == .available {
                pairing
                pairedDevices
                proofActions
            } else {
                unavailable
            }

            status
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: "Nearby Transport Lab"))
        .navigationBarTitleDisplayMode(.inline)
        .task { proof.refresh() }
        .onDisappear { proof.stop() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { proof.stop() }
        }
    }

    private var introduction: some View {
        Section {
            Text(verbatim: "Internal Stage 1 proof only. This does not start, resume, or save a game.")
            Text(verbatim: "On both devices, pair once, refresh, and select the same peer. Then start Host on one device and Guest on the other.")
        }
    }

    @ViewBuilder
    private var pairing: some View {
        if let publishable = WAPublishableService.boardGameNearby,
           let subscribable = WASubscribableService.boardGameNearby {
            Section {
                DevicePairingView(
                    .wifiAware(.connecting(to: publishable, from: .userSpecifiedDevices))
                ) {
                    diagnosticRow("Pair as Host", systemImage: "antenna.radiowaves.left.and.right")
                } fallback: {
                    Text(verbatim: "Host pairing is unavailable on this device.")
                        .foregroundStyle(.secondary)
                }
                .disabled(proof.isBusy)

                DevicePicker(
                    .wifiAware(.connecting(to: .userSpecifiedDevices, from: subscribable)),
                    onSelect: { endpoint in proof.didPair(endpoint.device.id) }
                ) {
                    diagnosticRow("Pair as Guest", systemImage: "iphone.and.arrow.forward")
                } fallback: {
                    Text(verbatim: "Guest pairing is unavailable on this device.")
                        .foregroundStyle(.secondary)
                }
                .disabled(proof.isBusy)
            } header: {
                Text(verbatim: "First pairing")
            } footer: {
                Text(verbatim: "The system owns discovery and pairing. This app persists no peer identity of its own.")
            }
        }
    }

    private var pairedDevices: some View {
        Section {
            Button {
                proof.refresh()
            } label: {
                diagnosticRow("Refresh Paired Devices", systemImage: "arrow.clockwise")
            }
            .disabled(proof.isBusy)

            if proof.devices.isEmpty {
                Text(verbatim: "No paired devices are currently available.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(proof.devices, id: \.id) { device in
                    Button {
                        proof.select(device.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: proof.displayName(for: device))
                                    .foregroundStyle(.primary)
                                if let detail = proof.displayDetail(for: device) {
                                    Text(verbatim: detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if proof.selectedID == device.id {
                                Image(systemName: "checkmark")
                                    .accessibilityLabel(Text(verbatim: "Selected"))
                            }
                        }
                    }
                    .disabled(proof.isBusy)
                }
            }
        } header: {
            Text(verbatim: "Explicit peer selection")
        } footer: {
            Text(verbatim: "Every proof run refreshes this system-owned list and accepts only the selected device.")
        }
    }

    private var proofActions: some View {
        Section {
            Button {
                proof.host()
            } label: {
                diagnosticRow("Start Host", systemImage: "dot.radiowaves.left.and.right")
            }
            .disabled(!proof.canStart)

            Button {
                proof.join()
            } label: {
                diagnosticRow("Start Guest", systemImage: "arrow.up.right.square")
            }
            .disabled(!proof.canStart)

            if proof.canStop {
                Button(role: .cancel) {
                    proof.stop()
                } label: {
                    diagnosticRow("Stop", systemImage: "stop.circle")
                }
            }
        } header: {
            Text(verbatim: "Opaque byte proof")
        } footer: {
            Text(verbatim: "Uses Apple's Wi-Fi Aware TLS configuration and exchanges bytes only after the selected peer and TLS 1.3 are verified.")
        }
    }

    private var unavailable: some View {
        Section {
            Text(verbatim: proof.availabilityMessage)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Unavailable")
        }
    }

    private var status: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                if proof.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: proof.statusSymbol)
                        .foregroundStyle(proof.didPass ? .green : .secondary)
                }
                Text(verbatim: proof.statusMessage)
                    .monospaced()
            }
        } header: {
            Text(verbatim: "Status")
        }
    }

    private func diagnosticRow(_ title: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

@MainActor
@Observable
private final class NearbyProofModel {
    private enum Phase: Equatable {
        case idle
        case refreshing
        case stopping
        case hosting
        case browsing
        case connecting
        case exchanging
        case passed
        case failed(String)
    }

    private enum Failure: Error {
        case noSelection
        case selectedDeviceMissing
        case serviceDeclarationMissing
        case peerMismatch
        case tlsMetadataMissing
        case tlsVersionMismatch
        case probeMismatch

        var message: String {
            switch self {
            case .noSelection:
                "Select one paired device first."
            case .selectedDeviceMissing:
                "The selected device is no longer in the paired-device list."
            case .serviceDeclarationMissing:
                "The Wi-Fi Aware service declaration is unavailable."
            case .peerMismatch:
                "Rejected a connection whose authenticated path was not the selected peer."
            case .tlsMetadataMissing:
                "The connection did not expose negotiated TLS metadata."
            case .tlsVersionMismatch:
                "The connection did not negotiate TLS 1.3."
            case .probeMismatch:
                "The peer returned different opaque bytes."
            }
        }
    }

    private enum Control: Error {
        case completed
    }

    private(set) var devices: [WAPairedDevice] = []
    private(set) var selectedID: WAPairedDevice.ID?
    private(set) var availability = NearbyTransportSupport.current
    private var phase: Phase = .idle
    private let lifecycle = NearbySerializedOperation()

    var isBusy: Bool {
        switch phase {
        case .refreshing, .stopping, .hosting, .browsing, .connecting, .exchanging: true
        case .idle, .passed, .failed: false
        }
    }

    var canStop: Bool {
        switch phase {
        case .refreshing, .hosting, .browsing, .connecting, .exchanging: true
        case .idle, .stopping, .passed, .failed: false
        }
    }

    var canStart: Bool {
        availability == .available && selectedID != nil && !isBusy
    }

    var didPass: Bool { phase == .passed }

    var statusSymbol: String {
        switch phase {
        case .passed: "checkmark.seal.fill"
        case .failed: "xmark.octagon"
        default: "info.circle"
        }
    }

    var statusMessage: String {
        switch phase {
        case .idle: "Idle."
        case .refreshing: "Refreshing the system paired-device list…"
        case .stopping: "Waiting for the previous nearby operation to stop…"
        case .hosting: "Hosting for the selected paired device…"
        case .browsing: "Browsing only for the selected paired device…"
        case .connecting: "Opening the selected-peer TLS 1.3 connection…"
        case .exchanging: "The selected peer and TLS 1.3 passed; exchanging the opaque probe…"
        case .passed: "PASS: the selected peer echoed the exact opaque probe over TLS 1.3."
        case .failed(let message): "FAIL: \(message)"
        }
    }

    var availabilityMessage: String {
        switch availability {
        case .available:
            "Available."
        case .unsupportedHardware:
            "This iPhone or iPad does not report Wi-Fi Aware support."
        case .missingServiceDeclaration:
            "The app is missing its publishable or subscribable Wi-Fi Aware service declaration."
        case .unavailablePlatform:
            "This proof is available only on supported iPhone and iPad hardware."
        }
    }

    func displayName(for device: WAPairedDevice) -> String {
        device.name ?? device.pairingInfo?.pairingName ?? "Unnamed paired device"
    }

    func displayDetail(for device: WAPairedDevice) -> String? {
        guard let info = device.pairingInfo else { return nil }
        let detail = [info.vendorName, info.modelName]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return detail.isEmpty ? nil : detail
    }

    func select(_ id: WAPairedDevice.ID) {
        guard !isBusy, devices.contains(where: { $0.id == id }) else { return }
        selectedID = id
        phase = .idle
    }

    /// DeviceDiscoveryUI has already made the person choose this endpoint.
    /// Refresh through WAPairedDevice before remembering it so every later
    /// standalone listener/browser receives a current `.selected([device])`.
    func didPair(_ id: WAPairedDevice.ID) {
        replaceOperation(initial: .refreshing) { [weak self] token in
            guard let self else { return }
            let snapshot = try await self.readDevices()
            try self.requireCurrent(token)
            self.devices = snapshot
            guard snapshot.contains(where: { $0.id == id }) else {
                throw Failure.selectedDeviceMissing
            }
            self.selectedID = id
            self.phase = .idle
        }
    }

    func refresh() {
        availability = NearbyTransportSupport.current
        guard availability == .available else {
            stop()
            devices = []
            selectedID = nil
            return
        }
        replaceOperation(initial: .refreshing) { [weak self] token in
            guard let self else { return }
            let snapshot = try await self.readDevices()
            try self.requireCurrent(token)
            self.devices = snapshot
            if let selectedID,
               !snapshot.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
            self.phase = .idle
        }
    }

    func host() {
        replaceOperation(initial: .hosting) { [weak self] token in
            guard let self else { return }
            let (device, selectedID) = try await self.currentSelection(token: token)
            guard let service = WAPublishableService.boardGameNearby else {
                throw Failure.serviceDeclarationMissing
            }
            let expected = try Core.stageOneNearbyProbeBytes()
            let listener = try NetworkListener(
                for: .wifiAware(.connecting(to: service, from: .selected([device]))),
                using: { Self.wifiAwareTLS() }
            )
            .newConnectionLimit(1)

            do {
                try await listener.run { connection in
                    try self.requireCurrent(token)
                    self.phase = .connecting
                    try await self.verify(connection, selectedID: selectedID)
                    self.phase = .exchanging
                    let received = try await connection.receive(exactly: expected.count).content
                    guard received == expected else { throw Failure.probeMismatch }
                    try await connection.send(received)
                    try self.requireCurrent(token)
                    self.phase = .passed
                    throw Control.completed
                }
            } catch Control.completed {
                // Throwing out of `run` ends the one-connection proof listener.
            }
        }
    }

    func join() {
        replaceOperation(initial: .browsing) { [weak self] token in
            guard let self else { return }
            let (device, selectedID) = try await self.currentSelection(token: token)
            guard let service = WASubscribableService.boardGameNearby else {
                throw Failure.serviceDeclarationMissing
            }

            let browser = NetworkBrowser(
                for: .wifiAware(.connecting(to: .selected([device]), from: service))
            )
            let endpoint: WAEndpoint = try await browser.run { endpoints in
                try self.requireCurrent(token)
                guard let endpoint = endpoints.first(where: { $0.device.id == selectedID }) else {
                    return .continue
                }
                return .finish(endpoint)
            }

            try self.requireCurrent(token)
            self.phase = .connecting
            let expected = try Core.stageOneNearbyProbeBytes()
            let connection = NetworkConnection(to: endpoint, using: { Self.wifiAwareTLS() })
            try self.requireCurrent(token)
            try await self.verify(connection, selectedID: selectedID)
            self.phase = .exchanging
            try await connection.send(expected)
            let echoed = try await connection.receive(exactly: expected.count).content
            guard echoed == expected else { throw Failure.probeMismatch }
            try self.requireCurrent(token)
            self.phase = .passed
        }
    }

    func stop() {
        let isDraining = lifecycle.cancelAndDrain { [weak self] in
            self?.phase = .idle
        }
        phase = isDraining ? .stopping : .idle
    }

    private func replaceOperation(
        initial: Phase,
        _ work: @escaping @MainActor (UInt64) async throws -> Void
    ) {
        let isDraining = lifecycle.replace { [weak self] token in
            guard let self else { return }
            do {
                try self.requireCurrent(token)
                self.phase = initial
                try await work(token)
            } catch is CancellationError {
                // Cancellation is a user action or a stale generation, not a
                // transport verdict.
            } catch let failure as Failure {
                guard self.lifecycle.accepts(token) else { return }
                self.phase = .failed(failure.message)
            } catch {
                guard self.lifecycle.accepts(token) else { return }
                // System network errors are intentionally not interpolated:
                // their descriptions can contain peer identity or endpoints,
                // neither of which this lab logs or displays diagnostically.
                self.phase = .failed("The system network operation failed.")
            }
        }
        phase = isDraining ? .stopping : initial
    }

    private func currentSelection(
        token: UInt64
    ) async throws -> (WAPairedDevice, WAPairedDevice.ID) {
        guard let selectedID else { throw Failure.noSelection }
        let snapshot = try await readDevices()
        try requireCurrent(token)
        devices = snapshot
        guard let selected = snapshot.first(where: { $0.id == selectedID }) else {
            self.selectedID = nil
            throw Failure.selectedDeviceMissing
        }
        return (selected, selectedID)
    }

    private func readDevices() async throws -> [WAPairedDevice] {
        let snapshot = try await WAPairedDevice.allDevices.current() ?? [:]
        return snapshot.values.sorted {
            let left = displayName(for: $0)
            let right = displayName(for: $1)
            return left == right ? $0.id < $1.id : left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private func verify(
        _ connection: NetworkConnection<TLS>,
        selectedID: WAPairedDevice.ID
    ) async throws {
        // The establishment report resolves only after the connection reaches
        // ready. Both accepted and outbound paths cross this barrier before
        // inspecting peer/TLS metadata or sending an application byte.
        _ = try await connection.establishmentReport()
        guard let path = connection.currentPath,
              let wifiAwarePath = try await path.wifiAware,
              NearbyTransportSupport.peerMatches(
                selectedID: selectedID,
                observedID: wifiAwarePath.endpoint.device.id
              )
        else {
            throw Failure.peerMismatch
        }

        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition)
            as? NWProtocolTLS.Metadata
        else {
            throw Failure.tlsMetadataMissing
        }
        guard sec_protocol_metadata_get_negotiated_tls_protocol_version(
            metadata.securityProtocolMetadata
        ) == .TLSv13 else {
            throw Failure.tlsVersionMismatch
        }
    }

    private func requireCurrent(_ token: UInt64) throws {
        try Task.checkCancellation()
        guard lifecycle.accepts(token) else { throw CancellationError() }
    }

    private nonisolated static func wifiAwareTLS() -> TLS {
        // Match Apple's Wi-Fi Aware TCP/TLS example. The connection is still
        // rejected before application bytes if its authenticated Wi-Fi Aware
        // path is not the selected paired device or TLS 1.3 was not negotiated.
        TLS()
    }
}
#endif
