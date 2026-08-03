// The internal, physical-device proof for the Apple nearby transport.
//
// This is deliberately not a game mode and not a BoardGame protocol surface.
// It proves one thing before Stage 2 builds on it: two devices that a person
// explicitly paired and selected can exchange one fixed, opaque core-owned
// value over a peer-bound TCP Wi-Fi Aware connection. Nothing here enters
// the game, history, preferences, logs, or persistent storage.

#if os(iOS) && !targetEnvironment(macCatalyst)
import DeviceDiscoveryUI
import Foundation
import Network
import Observation
import SwiftUI
import WiFiAware

private nonisolated struct NearbyProbeMessage: Codable, Equatable, Sendable {
    let bytes: Data

    /// A lab-only value with no BoardGame wire meaning.
    static let proof = NearbyProbeMessage(bytes: Data([
        0x4d, 0x58, 0x51, 0x2d, 0x57, 0x41, 0x2d,
        0x50, 0x52, 0x4f, 0x4f, 0x46, 0x2d, 0x31,
    ]))
}

private typealias NearbyProbeProtocol = Coder<
    NearbyProbeMessage,
    NearbyProbeMessage,
    NetworkJSONCoder
>
private typealias NearbyProbeConnection = NetworkConnection<NearbyProbeProtocol>

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
            Text(verbatim: "Uses Apple's sample connection lifecycle with reliable TCP. Wi-Fi Aware provides a secure selected-device data path; this lab does not validate application TLS.")
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

    private nonisolated enum Failure: Error, Sendable {
        case noSelection
        case selectedDeviceMissing
        case serviceDeclarationMissing
        case peerMismatch
        case connectionEnded
        case timedOut
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
                "Rejected a connection whose secure Wi-Fi Aware path was not the selected peer."
            case .connectionEnded:
                "The connection ended before one complete probe message arrived."
            case .timedOut:
                "The nearby proof did not finish within 30 seconds."
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
    private var connectionState: String?
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
        let connectionStateSuffix = connectionState.map { " [state: \($0)]" } ?? ""
        return switch phase {
        case .idle: "Idle."
        case .refreshing: "Refreshing the system paired-device list…"
        case .stopping: "Waiting for the previous nearby operation to stop…"
        case .hosting: "Hosting for the selected paired device…\(connectionStateSuffix)"
        case .browsing: "Browsing only for the selected paired device…\(connectionStateSuffix)"
        case .connecting: "Opening the selected-peer Wi-Fi Aware TCP connection…\(connectionStateSuffix)"
        case .exchanging: "The selected Wi-Fi Aware path is ready; exchanging the opaque probe…"
        case .passed: "PASS: the selected peer echoed the exact opaque probe over Wi-Fi Aware TCP."
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
            try await self.withProofDeadline {
                let (device, selectedID) = try await self.currentSelection(token: token)
                guard let service = WAPublishableService.boardGameNearby else {
                    throw Failure.serviceDeclarationMissing
                }
                let expected = NearbyProbeMessage.proof
                let listener = try NetworkListener(
                    for: .wifiAware(.connecting(to: service, from: .selected([device]))),
                    using: .parameters {
                        Coder(NearbyProbeMessage.self, using: NetworkJSONCoder()) {
                            TCP()
                        }
                    }
                    .wifiAware { $0.performanceMode = .bulk }
                    .serviceClass(.bestEffort)
                )
                .onStateUpdate { [weak model = self] _, state in
                    model?.observeListenerState(state, token: token)
                }
                .newConnectionLimit(1)

                do {
                    try await listener.run { connection in
                        try self.requireCurrent(token)
                        self.phase = .connecting
                        let readyStates = self.observeConnection(connection, token: token)
                        // Apple's sample activates and retains every accepted
                        // connection by installing its receiver immediately.
                        async let pendingProbe = self.firstMessage(from: connection)
                        try await self.awaitReady(readyStates)
                        try await self.verifyPeer(connection, selectedID: selectedID)
                        self.phase = .exchanging
                        let received = try await pendingProbe
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
    }

    func join() {
        replaceOperation(initial: .browsing) { [weak self] token in
            guard let self else { return }
            try await self.withProofDeadline {
                let (device, selectedID) = try await self.currentSelection(token: token)
                guard let service = WASubscribableService.boardGameNearby else {
                    throw Failure.serviceDeclarationMissing
                }

                let browser = NetworkBrowser(
                    for: .wifiAware(.connecting(to: .selected([device]), from: service))
                )
                .onStateUpdate { [weak model = self] _, state in
                    model?.observeBrowserState(state, token: token)
                }
                let endpoint: WAEndpoint = try await browser.run { endpoints in
                    try self.requireCurrent(token)
                    guard let endpoint = endpoints.first(where: { $0.device.id == selectedID }) else {
                        return .continue
                    }
                    return .finish(endpoint)
                }

                try self.requireCurrent(token)
                self.phase = .connecting
                let expected = NearbyProbeMessage.proof
                let connection = NetworkConnection(
                    to: endpoint,
                    using: .parameters {
                        Coder(NearbyProbeMessage.self, using: NetworkJSONCoder()) {
                            TCP()
                        }
                    }
                    .wifiAware { $0.performanceMode = .bulk }
                    .serviceClass(.bestEffort)
                )
                try self.requireCurrent(token)
                let readyStates = self.observeConnection(connection, token: token)
                // Match Apple's sample: retain the connection with a receiver task
                // immediately, then let the ready state drive application work.
                async let pendingEcho = self.firstMessage(from: connection)
                try await self.awaitReady(readyStates)
                try await self.verifyPeer(connection, selectedID: selectedID)
                self.phase = .exchanging
                try await connection.send(expected)
                let echoed = try await pendingEcho
                guard echoed == expected else { throw Failure.probeMismatch }
                try self.requireCurrent(token)
                self.phase = .passed
            }
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
                self.connectionState = nil
                self.phase = initial
                try await work(token)
            } catch is CancellationError {
                // Cancellation is a user action or a stale generation, not a
                // transport verdict.
            } catch let failure as Failure {
                guard self.lifecycle.accepts(token) else { return }
                self.phase = .failed(failure.message)
            } catch let networkError as NWError {
                guard self.lifecycle.accepts(token) else { return }
                self.phase = .failed(Self.networkErrorMessage(networkError))
            } catch {
                guard self.lifecycle.accepts(token) else { return }
                // Keep non-NWError descriptions out of the UI because they can
                // contain peer identity or endpoints. NWError is mapped above
                // to a bounded domain, code, or Wi-Fi Aware case only.
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

    private func observeConnection(
        _ connection: NearbyProbeConnection,
        token: UInt64
    ) -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { continuation in
            connection.onStateUpdate { [weak self] _, state in
                guard let self, self.lifecycle.accepts(token) else { return }
                switch state {
                case .setup:
                    self.connectionState = "connection setup"
                case .preparing:
                    self.connectionState = "connection preparing"
                case .waiting(let error):
                    self.connectionState = "connection waiting: \(Self.networkErrorSummary(error))"
                case .ready:
                    self.connectionState = "connection ready"
                    continuation.yield(())
                    continuation.finish()
                case .failed(let error):
                    self.connectionState = "connection failed: \(Self.networkErrorSummary(error))"
                    continuation.finish(throwing: error)
                case .cancelled:
                    self.connectionState = "connection cancelled"
                    continuation.finish(throwing: Failure.connectionEnded)
                @unknown default:
                    self.connectionState = "connection unknown"
                }
            }
        }
    }

    private func awaitReady(
        _ states: AsyncThrowingStream<Void, Error>
    ) async throws {
        for try await _ in states { return }
        try Task.checkCancellation()
        throw Failure.connectionEnded
    }

    private func firstMessage(
        from connection: NearbyProbeConnection
    ) async throws -> NearbyProbeMessage {
        for try await (message, _) in connection.messages { return message }
        try Task.checkCancellation()
        throw Failure.connectionEnded
    }

    private func verifyPeer(
        _ connection: NearbyProbeConnection,
        selectedID: WAPairedDevice.ID
    ) async throws {
        // Apple reads the Wi-Fi Aware path after `.ready`. Keep MiniXiangqi's
        // stricter selected-device check before accepting application data.
        guard let path = connection.currentPath,
              let wifiAwarePath = try await path.wifiAware,
              NearbyTransportSupport.peerMatches(
                selectedID: selectedID,
                observedID: wifiAwarePath.endpoint.device.id
              )
        else {
            throw Failure.peerMismatch
        }
    }

    private func observeListenerState(
        _ state: NetworkListener<NearbyProbeProtocol>.State,
        token: UInt64
    ) {
        guard lifecycle.accepts(token) else { return }
        switch state {
        case .setup:
            connectionState = "listener setup"
        case .waiting(let error):
            connectionState = "listener waiting: \(Self.networkErrorSummary(error))"
        case .ready:
            connectionState = "listener ready"
        case .failed(let error):
            connectionState = "listener failed: \(Self.networkErrorSummary(error))"
            phase = .failed(Self.networkErrorMessage(error))
        case .cancelled:
            connectionState = "listener cancelled"
        @unknown default:
            connectionState = "listener unknown"
        }
    }

    private func observeBrowserState(
        _ state: NetworkBrowser<WASubscriberBrowser>.State,
        token: UInt64
    ) {
        guard lifecycle.accepts(token) else { return }
        switch state {
        case .setup:
            connectionState = "browser setup"
        case .waiting(let error):
            connectionState = "browser waiting: \(Self.networkErrorSummary(error))"
        case .ready:
            connectionState = "browser ready"
        case .failed(let error):
            connectionState = "browser failed: \(Self.networkErrorSummary(error))"
            phase = .failed(Self.networkErrorMessage(error))
        case .cancelled:
            connectionState = "browser cancelled"
        @unknown default:
            connectionState = "browser unknown"
        }
    }

    private func requireCurrent(_ token: UInt64) throws {
        try Task.checkCancellation()
        guard lifecycle.accepts(token) else { throw CancellationError() }
    }

    private func withProofDeadline(
        _ operation: @escaping @MainActor @Sendable () async throws -> Void
    ) async throws {
        let operationTask = Task { @MainActor in
            try await operation()
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await operationTask.value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw Failure.timedOut
            }
            defer {
                operationTask.cancel()
                group.cancelAll()
            }
            guard try await group.next() != nil else {
                throw Failure.connectionEnded
            }
        }
    }

    private nonisolated static func networkErrorMessage(_ error: NWError) -> String {
        "The system network operation failed (\(networkErrorSummary(error)))."
    }

    private nonisolated static func networkErrorSummary(_ error: NWError) -> String {
        if let wifiAware = error.wifiAware {
            return "Wi-Fi Aware \(wifiAwareErrorName(wifiAware))"
        }
        switch error {
        case .posix(let code):
            return "POSIX \(code.rawValue)"
        case .dns(let code):
            return "DNS \(code)"
        case .tls(let status):
            return "TLS \(status)"
        case .wifiAware(let code):
            return "Wi-Fi Aware \(code)"
        @unknown default:
            return "unknown network error"
        }
    }

    private nonisolated static func wifiAwareErrorName(_ error: WAError) -> String {
        switch error {
        case .wifiAwareUnsupported: "unsupported"
        case .entitlementMissing: "entitlement missing"
        case .noRadioResources: "no radio resources"
        case .serviceNotDeclared: "service not declared"
        case .serviceAlreadySubscribing: "already subscribing"
        case .serviceAlreadyPublishing: "already publishing"
        case .noPairedDevices: "no paired devices"
        case .deviceInvalid: "device invalid"
        case .deviceNoLongerAvailable: "device no longer available"
        case .publisherTimeout: "publisher timeout"
        case .subscriberTimeout: "subscriber timeout"
        case .connectionFailed: "connection failed"
        case .connectionIdleTimeout: "connection idle timeout"
        case .connectionTerminated: "connection terminated"
        case .error: "general error"
        @unknown default: "unknown error"
        }
    }
}
#endif
