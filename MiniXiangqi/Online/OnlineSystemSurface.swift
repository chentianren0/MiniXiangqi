// Putting one of the system's own view controllers on screen, and taking it
// off again.
//
// Everything Game Center shows the player is Game Center's: the sign-in, the
// invitation to a friend, the sheet an accepted invitation opens. Each of them
// arrives as a view controller of whichever kit the platform has, and
// presenting one is the only thing about any of them that differs between
// iPhone, iPad and Mac. It is written once here so that no surface using one
// carries a platform split of its own.
//
// **Nothing about them is the app's.** No word on any of these screens was
// written here, none of them is configured beyond what the surface asking for
// it says, and the app learns nothing from them but what its delegate is told.

import Foundation
import OSLog

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
enum OnlineSystemSurface {

    private static func note(_ text: String) {
        NearbyLogger.log.info("\(text, privacy: .public)")
        #if DEBUG
        print("[nearby] \(text)")
        #endif
    }

    #if os(macOS)
    static func present(_ viewController: NSViewController) {
        guard let host = NSApp.keyWindow?.contentViewController
                ?? NSApp.windows.first(where: \.isVisible)?.contentViewController
        else {
            note("No window to present Game Center's own screen in.")
            return
        }
        host.presentAsSheet(viewController)
    }

    static func dismiss(_ viewController: NSViewController) {
        viewController.dismiss(nil)
    }
    #else
    static func present(_ viewController: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController
        else {
            note("No window to present Game Center's own screen in.")
            return
        }
        // Whatever is frontmost, so the screen is not put behind a sheet the
        // player already has open.
        var host = root
        while let presented = host.presentedViewController { host = presented }
        host.present(viewController, animated: true)
    }

    static func dismiss(_ viewController: UIViewController) {
        viewController.dismiss(animated: true)
    }
    #endif
}
