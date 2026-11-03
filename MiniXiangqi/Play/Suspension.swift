// The engine is released on the platform's suspension or memory-pressure
// signal, never on loss of focus. On macOS an unfocused window is still a
// running app; releasing gigabytes of Hash every time the user clicks another
// window would be worse than the problem this solves.

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class Suspension {
    enum Event {
        /// Cancel the search and release the transposition table whole.
        case suspend
        /// Nothing is prepared by this alone: preparation happens when a search
        /// is next owed.
        case resume
        /// The same cancel-and-release, but the app is still in front and
        /// nothing will say the pressure has passed, so it is not a suspension.
        case memoryPressure
    }

    private var observers: [NSObjectProtocol] = []
    private var memoryPressure: DispatchSourceMemoryPressure?

    init(_ handle: @escaping @MainActor (Event) -> Void) {
        let centre = NotificationCenter.default

        #if os(macOS)
        // Sleep and wake come from the workspace's own centre; the default one
        // never carries them.
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, .suspend, handle)
        observe(workspace, NSWorkspace.didWakeNotification, .resume, handle)
        // Termination is deliberately not observed: the app delegate's
        // `mxq_core_shutdown` already cancels every search and joins the engine
        // thread. A second, asynchronous teardown racing it delays the exit long
        // enough for the next launch to find the old process still there.
        #else
        observe(centre, UIApplication.didEnterBackgroundNotification, .suspend, handle)
        observe(centre, UIApplication.willEnterForegroundNotification, .resume, handle)
        // `os_proc_available_memory` measures this process's own headroom, which
        // rises as soon as the table is released, so the next search can ask
        // for a Hash the size of the one just given up. The fallback is that
        // the system reclaims the app after autosave has committed.
        observe(centre, UIApplication.didReceiveMemoryWarningNotification,
                .memoryPressure, handle)
        #endif

        // Delivered on the main queue so the handler is already where the state
        // lives.
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
