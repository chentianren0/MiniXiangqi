// What the application says about itself: the name it ships under, the release
// it is, the licence it is under, and where its source is.
//
// docs/product.md, "Product identity and distribution": the application is
// licensed under GPLv3, matching its Fairy-Stockfish dependency, and the App
// Store listing states that licence and links the complete source. The About
// page inside Settings says the same things inside the application, and this is
// where it reads them from.
//
// **Nothing here is a literal that could go stale.** The version and the build
// are the bundle's own, so they are whatever the owner set on the build that is
// running rather than a number typed beside it; the licence is the repository's
// own LICENSE, bundled as a resource rather than retyped, so the text on screen
// is the document the source is actually under.

import Foundation

enum About {

    /// The name the application ships under — **Star River**, and **闲敲棋子**
    /// in Chinese: the product name docs/product.md fixes, which the project
    /// carries as the bundle's display name and localizes there like any other
    /// copy. Read rather than typed, for the reason the version is, so this
    /// answers in whichever language the application is running in.
    static var displayName: String {
        string("CFBundleDisplayName") ?? string("CFBundleName") ?? ""
    }

    /// The marketing version: `CFBundleShortVersionString`, which is what the
    /// App Store and TestFlight call a release.
    static var version: String { string("CFBundleShortVersionString") ?? "" }

    /// The build: `CFBundleVersion`, which moves within one marketing version.
    static var build: String { string("CFBundleVersion") ?? "" }

    /// Where the source is. GPLv3 is a licence about source, and this is the
    /// repository the App Store listing already links, so the page and the
    /// listing name one address rather than two.
    ///
    /// Force-unwrapped because it is a literal spelled here: a URL that failed
    /// to parse would be a typo in this line rather than a state the running
    /// application can reach, and `AboutTests` reads it.
    static let repository = URL(string: "https://github.com/chentianren0/MiniXiangqi")!

    /// The licence, bundled from the repository root.
    ///
    /// Empty where the resource is missing, which is a packaging failure rather
    /// than a state to draw around — the same choice `BoardSounds` makes about a
    /// sample that fell out of the bundle, and caught the same way: by a test
    /// that reads this rather than by somebody noticing a blank page.
    ///
    /// It is the GPL's own English text and never translated: the licence is one
    /// document in one language, and a translation of it would not be the
    /// licence. It carries no copy key for the same reason.
    static let licenseText: String = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }()

    /// The licence's paragraphs, split where the document separates them itself
    /// — a blank line — and each keeping its own line breaks, so that what is
    /// drawn is the document unchanged. `LicenseScreen` draws them one at a
    /// time; the reasoning for not drawing the whole thing as one block is
    /// there, and the split is here so that a test can hold it to losing
    /// nothing.
    static let licenseParagraphs: [String] = licenseText
        .components(separatedBy: "\n\n")
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private static func string(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
