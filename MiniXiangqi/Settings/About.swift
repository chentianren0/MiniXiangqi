// Nothing here is a literal that could go stale: the version and build are the
// bundle's own, and the licence is the repository's LICENSE, bundled as a
// resource rather than retyped.

import Foundation

enum About {

    /// Star River, 闲敲棋子 in Chinese. Localized as the bundle's display name,
    /// so it answers in whichever language the app is running in.
    static var displayName: String {
        string("CFBundleDisplayName") ?? string("CFBundleName") ?? ""
    }

    /// What the App Store and TestFlight call a release.
    static var version: String { string("CFBundleShortVersionString") ?? "" }

    /// Moves within one marketing version.
    static var build: String { string("CFBundleVersion") ?? "" }

    /// The address the App Store listing links, so page and listing name one.
    /// Force-unwrapped: a literal that fails to parse is a typo in this line,
    /// not a state the running app can reach.
    static let repository = URL(string: "https://github.com/chentianren0/MiniXiangqi")!

    /// Empty where the resource is missing, which is a packaging failure rather
    /// than a state to draw around. The GPL's own English, never translated: a
    /// translation would not be the licence.
    static let licenseText: String = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }()

    /// Split on the document's own blank lines, each paragraph keeping its line
    /// breaks, so what is drawn is the document unchanged.
    static let licenseParagraphs: [String] = licenseText
        .components(separatedBy: "\n\n")
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private static func string(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
