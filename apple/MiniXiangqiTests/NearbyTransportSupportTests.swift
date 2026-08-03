// The platform gate for BoardGame Nearby Protocol's Apple transport.

import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@Suite("Nearby transport support")
struct NearbyTransportSupportTests {
    @Test("Only a supported platform with both service roles is available")
    func everyGateIsRequired() {
        #expect(NearbyTransportSupport.resolve(
            platformAvailable: true,
            hardwareSupported: true,
            hasPublishableService: true,
            hasSubscribableService: true
        ) == .available)

        #expect(NearbyTransportSupport.resolve(
            platformAvailable: false,
            hardwareSupported: true,
            hasPublishableService: true,
            hasSubscribableService: true
        ) == .unavailablePlatform)

        #expect(NearbyTransportSupport.resolve(
            platformAvailable: true,
            hardwareSupported: false,
            hasPublishableService: true,
            hasSubscribableService: true
        ) == .unsupportedHardware)

        #expect(NearbyTransportSupport.resolve(
            platformAvailable: true,
            hardwareSupported: true,
            hasPublishableService: false,
            hasSubscribableService: true
        ) == .missingServiceDeclaration)

        #expect(NearbyTransportSupport.resolve(
            platformAvailable: true,
            hardwareSupported: true,
            hasPublishableService: true,
            hasSubscribableService: false
        ) == .missingServiceDeclaration)
    }

    @Test("The provisional service is one stable declaration")
    func serviceName() {
        #expect(NearbyTransportSupport.serviceName == "_boardgame._tcp")
    }

    @Test("Only the explicitly selected peer is accepted")
    func selectedPeerBinding() {
        #expect(NearbyTransportSupport.peerMatches(selectedID: 42, observedID: 42))
        #expect(!NearbyTransportSupport.peerMatches(selectedID: 42, observedID: 7))
        #expect(!NearbyTransportSupport.peerMatches(selectedID: 42, observedID: nil))
    }

    @Test("Starting or stopping invalidates callbacks from the old operation")
    func staleGenerations() {
        var generations = NearbyTransportGeneration()
        let first = generations.begin()
        #expect(generations.accepts(first))

        let second = generations.begin()
        #expect(!generations.accepts(first))
        #expect(generations.accepts(second))

        generations.invalidate()
        #expect(!generations.accepts(second))
    }

    @Test("A replacement waits until cancelled operation cleanup returns")
    @MainActor
    func replacementWaitsForCleanup() async {
        let lifecycle = NearbySerializedOperation()
        let gate = NearbyOperationGate()

        #expect(!lifecycle.replace { _ in
            await gate.runFirst()
        })
        #expect(await eventually { await gate.hasEvent("first-start") })

        #expect(lifecycle.replace { _ in
            await gate.runSecond()
        })
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await gate.snapshot() == ["first-start"],
                "the replacement must not start while cancellation cleanup is held")

        await gate.releaseFirst()
        #expect(await eventually { await gate.hasEvent("second-start") })
        #expect(await gate.snapshot() == [
            "first-start", "first-cleanup", "second-start",
        ])
    }

}

/// Holds a cancelled operation in cleanup so the serialization test controls
/// exactly when its replacement is allowed to begin.
private actor NearbyOperationGate {
    private var released = false
    private var events: [String] = []

    func runFirst() async {
        events.append("first-start")
        while !released {
            // Deliberately cooperative but cancellation-insensitive: a real
            // Network operation may also need time to unwind after cancel().
            await Task.yield()
        }
        events.append("first-cleanup")
    }

    func runSecond() {
        events.append("second-start")
    }

    func releaseFirst() {
        released = true
    }

    func hasEvent(_ event: String) -> Bool {
        events.contains(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private func eventually(
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<10_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}
