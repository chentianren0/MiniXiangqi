// What the About page says, held to what the bundle actually carries.
//
// docs/product.md, "Product identity and distribution": the application is
// licensed under GPLv3 and its source is public. The page inside Settings says
// so, and every fact on it is read from the running bundle rather than typed —
// which is exactly the kind of claim a screenshot cannot check, because a page
// showing a stale version looks the same as a page showing the right one.
//
// So this is where the four facts are held: that the licence is in the bundle
// at all and is the GPL rather than a truncated or placeholder file, that the
// version and the build are the bundle's own and not empty, that the name is
// the product name of record, and that the source address is the one the App
// Store listing links. The unit suite is hosted by the application, so the
// bundle read here is the application's own.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("What the application says about itself")
@MainActor
struct AboutTests {

    @Test("The name is the product name of record")
    func theDisplayNameIsTheProductName() {
        // docs/copy.md's `app.displayName`: one name in both languages, carried
        // by the project as the bundle's display name. The page reads it from
        // there, so a project that lost the key would show an empty row.
        #expect(About.displayName == "Mini Xiangqi")
    }

    @Test("The version and the build are the running bundle's own")
    func theVersionAndBuildAreRead() {
        // Not compared against a literal: the owner moves both, and a test that
        // pinned today's numbers would fail on the next release rather than on
        // a mistake. What is pinned is that something was read and that it is
        // shaped like what it claims to be — an absent key reads as empty, and
        // an empty version on the About page is the failure this catches.
        #expect(!About.version.isEmpty)
        #expect(!About.build.isEmpty)
        #expect(About.version.allSatisfy { $0.isNumber || $0 == "." },
                "a marketing version is digits and dots — it reads \(About.version)")
        #expect(About.build.allSatisfy { $0.isNumber || $0 == "." },
                "and so is a build — it reads \(About.build)")
    }

    @Test("The source address is the repository the licence is about")
    func theSourceAddressIsTheRepository() {
        #expect(About.repository.absoluteString
                == "https://github.com/chentianren0/MiniXiangqi")
    }

    /// The licence is a bundled resource, and a resource that fell out of the
    /// bundle leaves a blank page rather than an error — the same trade
    /// `BoardSounds` makes for a missing sample, and caught the same way.
    @Test("The bundled licence is the GNU General Public License v3, whole")
    func theBundledLicenceIsTheGPL() {
        let licence = About.licenseText
        #expect(licence.contains("GNU GENERAL PUBLIC LICENSE"),
                "the licence should be in the bundle and should be the GPL")
        #expect(licence.contains("Version 3, 29 June 2007"))
        #expect(licence.contains("TERMS AND CONDITIONS"))
        // Whole rather than truncated: the document runs to its end, where the
        // instructions for applying it are.
        #expect(licence.contains("How to Apply These Terms to Your New Programs"))
        #expect(licence.count > 30_000,
                "the GPL is a long document — this one is \(licence.count) characters")
    }

    /// The page draws the licence a paragraph at a time. Nothing may be lost in
    /// the split: a licence with a paragraph missing is not the licence.
    @Test("Splitting the licence into paragraphs drops nothing but blank lines")
    func theParagraphsAreTheWholeDocument() {
        let paragraphs = About.licenseParagraphs
        #expect(paragraphs.count > 1, "the document has paragraphs")

        let whitespace = CharacterSet.whitespacesAndNewlines
        func withoutSpacing(_ text: String) -> String {
            String(text.unicodeScalars.filter { !whitespace.contains($0) })
        }
        #expect(withoutSpacing(paragraphs.joined()) == withoutSpacing(About.licenseText),
                "every character of the licence that is not spacing is still drawn")
        // And each paragraph keeps its own line breaks, so the document's own
        // layout survives: the title block is two lines, not one.
        #expect(paragraphs.first?.contains("\n") == true)
    }
}
