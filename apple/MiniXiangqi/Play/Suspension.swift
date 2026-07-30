// The platform signals that release the engine, and the ones that do not.
//
// docs/engine-integration.md, "Accepted backgrounding and teardown behavior":
// the trigger is **the platform's own suspension or memory-pressure signal, not
// loss of focus**. On macOS an unfocused window is still a running app, so the
// signals are system sleep, app termination, and a memory-pressure notification;
// switching windows changes nothing. Releasing gigabytes of Hash every time the
// user clicks another window would be worse than the problem the rule exists to
// solve, and it is the one mistake this file exists to not make.
//
// iOS and iPadOS take scene backgrounding and the foreground memory-pressure
// warning instead — the last signal before the system reclaims the process, on
// the platform where the per-process limit applies. They are wired here so that
// the shape is one shape, though only macOS runs today.

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class Suspension {
    enum Event {
        /// Cancel the search and release the transposition table whole. The app
        /// is going away, and something will say when it is back.
        case suspend
        /// The machine is back. Nothing is prepared by this alone: preparation
        /// happens when a search is next owed.
        case resume
        /// The same cancel-and-release, but the app is still in front of the
        /// player and nothing will ever say the pressure has passed. It is
        /// therefore not a suspension, and is kept apart from one.
        case memoryPressure
    }

    private var observers: [NSObjectProtocol] = []
    private var memoryPressure: DispatchSourceMemoryPressure?

    init(_ handle: @escaping @MainActor (Event) -> Void) {
        let centre = NotificationCenter.default

        #if os(macOS)
        // Sleep and termination come from the workspace's own centre rather
        // than the default one, which never carries them.
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, .suspend, handle)
        observe(workspace, NSWorkspace.didWakeNotification, .resume, handle)
        // Termination is deliberately *not* here. The accepted teardown order
        // at quit is `mxq_core_shutdown`, which the app delegate already
        // performs: it cancels every search, joins the engine thread and closes
        // the store, in one deterministic call. A second, asynchronous teardown
        // racing it buys nothing and delays the exit, which on this platform is
        // long enough for the next launch to find the old process still there.
        #else
        observe(centre, UIApplication.didEnterBackgroundNotification, .suspend, handle)
        observe(centre, UIApplication.willEnterForegroundNotification, .resume, handle)
        observe(centre, UIApplication.didReceiveMemoryWarningNotification,
                .memoryPressure, handle)
        #endif

        // Memory pressure, on every platform that has the source. Delivered on
        // the main queue so the handler is already where the state lives, and
        // the teardown it starts does not block the thread that delivered it.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical],
                                                            queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { handle(.memoryPressure) }
        }
        source.resume()
        memoryPressure = source
    }

    private func observe(_ centre: NotificationCenter, _ name: Notification.Name,
                         _ event: Event,
                         _ handle: @escaping @MainActor (Event) -> Void) {
        observers.append(centre.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handle(event) }
        })
    }

    deinit {
        memoryPressure?.cancel()
    }
}
