// The availability gate and declared service for the Apple nearby adapter.
//
// The BoardGame wire protocol does not live here. Stage 1 only proves that the
// Apple frontend can reach one explicitly selected paired device over the
// service declared in Info.plist. Framing, negotiation, and game messages stay
// in the shared core and arrive in Stage 2.

#if os(iOS) && !targetEnvironment(macCatalyst)
import WiFiAware
#endif

nonisolated enum NearbyTransportAvailability: Equatable, Sendable {
    case unavailablePlatform
    case unsupportedHardware
    case missingServiceDeclaration
    case available
}

nonisolated enum NearbyTransportSupport {
    /// Provisional until physical-device interoperability and the fresh IANA
    /// registry check required by docs/boardgame-nearby-protocol.md.
    static let serviceName = "_boardgame._tcp"

    static var current: NearbyTransportAvailability {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        resolve(
            platformAvailable: true,
            hardwareSupported: WACapabilities.supportedFeatures.contains(.wifiAware),
            hasPublishableService: WAPublishableService.boardGameNearby != nil,
            hasSubscribableService: WASubscribableService.boardGameNearby != nil
        )
        #else
        .unavailablePlatform
        #endif
    }

    /// Kept pure so the binding test can cover every gate on platforms where
    /// Wi-Fi Aware itself is unavailable, including the macOS test host.
    static func resolve(
        platformAvailable: Bool,
        hardwareSupported: Bool,
        hasPublishableService: Bool,
        hasSubscribableService: Bool
    ) -> NearbyTransportAvailability {
        guard platformAvailable else { return .unavailablePlatform }
        guard hardwareSupported else { return .unsupportedHardware }
        guard hasPublishableService, hasSubscribableService else {
            return .missingServiceDeclaration
        }
        return .available
    }

    static func peerMatches(selectedID: UInt64, observedID: UInt64?) -> Bool {
        observedID == selectedID
    }
}

/// Invalidates callbacks from every listener, browser, or connection that an
/// earlier operation owned. The live adapter is actor-isolated; this small
/// value makes that stale-generation rule independently testable.
nonisolated struct NearbyTransportGeneration: Sendable {
    private(set) var current: UInt64 = 0

    mutating func begin() -> UInt64 {
        current &+= 1
        return current
    }

    mutating func invalidate() {
        current &+= 1
    }

    func accepts(_ candidate: UInt64) -> Bool {
        candidate == current
    }
}

/// A cancellation barrier for the one nearby operation the lab may own.
///
/// Cancelling a Swift task is cooperative: it requests teardown but does not
/// wait for a listener, browser, or connection to release its resources. Every
/// replacement therefore waits for the previous task to return before its work
/// begins. The generation still rejects callbacks immediately while teardown
/// is in progress.
@MainActor
final class NearbySerializedOperation {
    private var task: Task<Void, Never>?
    private var generation = NearbyTransportGeneration()

    /// Returns whether the new operation has to wait for prior teardown.
    @discardableResult
    func replace(
        with work: @escaping @MainActor (UInt64) async -> Void
    ) -> Bool {
        let previous = task
        previous?.cancel()
        let token = generation.begin()

        task = Task { [weak self] in
            if let previous {
                await previous.value
            }
            guard let self, generation.accepts(token) else { return }
            await work(token)
            guard generation.accepts(token) else { return }
            task = nil
        }
        return previous != nil
    }

    /// Requests cancellation and reports idle only after teardown has returned.
    /// Returns whether there was an operation to drain.
    @discardableResult
    func cancelAndDrain(
        _ onDrained: @escaping @MainActor () -> Void
    ) -> Bool {
        guard let previous = task else {
            generation.invalidate()
            onDrained()
            return false
        }

        previous.cancel()
        let token = generation.begin()
        task = Task { [weak self] in
            await previous.value
            guard let self, generation.accepts(token) else { return }
            task = nil
            onDrained()
        }
        return true
    }

    func accepts(_ token: UInt64) -> Bool {
        generation.accepts(token)
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
extension WAPublishableService {
    static var boardGameNearby: WAPublishableService? {
        allServices[NearbyTransportSupport.serviceName]
    }
}

extension WASubscribableService {
    static var boardGameNearby: WASubscribableService? {
        allServices[NearbyTransportSupport.serviceName]
    }
}
#endif
