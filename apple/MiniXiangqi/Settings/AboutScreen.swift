// 关于: what this build is, and what it is licensed under.
//
// docs/interaction-design.md, "Navigation": Settings contains an About page
// stating the application's licence and its version. It is the same page on
// every Apple platform, reached the same way — a row at the foot of Settings —
// because what it says is the same everywhere and a second arrangement of the
// same facts would be two pages to keep in step. macOS keeps the system's own
// About box in the app menu as well; that one is the platform's and this one is
// the application's, and they do not have to be the same thing.
//
// **It is the Settings screen's own vocabulary and nothing new**: one grouped
// `Form`, rows that are a label and a value, and one footer where a sentence is
// owed. The facts themselves are read from the bundle by `About`, which is why
// nothing on this page is a literal.
//
// **Nothing else is here.** No credits, no third-party notices, no diagnostics:
// the page exists for the licence and the release it identifies, and the source
// link is the licence's own other half rather than a fifth thing.

import SwiftUI

struct AboutScreen: View {

    var body: some View {
        Form {
            identity
            licence
        }
        .formStyle(.grouped)
        .navigationTitle("about.title")
        // A page walked into from a destination's root is titled beside the
        // control that walks back out, per docs/interaction-design.md
        // § Navigation — the same answer the replay screen gives, and the
        // platform's own for a pushed page.
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// What this build is: the name it ships under, the release, and the build
    /// within that release. Three rows of a label and a value, which is the
    /// platform's own way of stating a fact that cannot be changed from here —
    /// and the shape every row on the Settings screen already takes.
    private var identity: some View {
        Section {
            LabeledContent("about.name") { Text(verbatim: About.displayName) }
                .accessibilityIdentifier("about-name")
            LabeledContent("about.version") { Text(verbatim: About.version) }
                .accessibilityIdentifier("about-version")
            LabeledContent("about.build") { Text(verbatim: About.build) }
                .accessibilityIdentifier("about-build")
        }
    }

    /// The licence, its full text, and the source it is a licence about.
    ///
    /// The two rows are one group because the second exists on account of the
    /// first: GPLv3 is a licence about source, so the address is part of what
    /// the statement beneath them says rather than a separate offer. The
    /// statement is a footer because that is what a sentence of explanation is
    /// on this screen — the two footers in Settings are the same shape.
    private var licence: some View {
        Section {
            NavigationLink("about.license") { LicenseScreen() }
                .accessibilityIdentifier("about-license")
            Link("about.source", destination: About.repository)
                .accessibilityIdentifier("about-source")
        } footer: {
            Text("about.license.statement")
                .accessibilityIdentifier("about-license-statement")
        }
    }
}

/// The licence itself, read-only.
///
/// The document is shown as it is written — the GPL's own English, its own line
/// breaks, in a monospaced face because it is a plain-text document laid out in
/// columns and a proportional face would misalign what it aligns. It is not
/// copy and is not localized: the licence is one document in one language, and a
/// translation of it would not be the licence.
///
/// **Paragraph by paragraph rather than as one block of text.** Thirty-five
/// kilobytes in a single `Text` is one accessibility element a screen reader
/// cannot move around inside, and one layout pass for the whole document before
/// anything appears. Split on the blank lines the document already has, each
/// paragraph keeps its own line breaks exactly, so what is drawn is unchanged.
struct LicenseScreen: View {

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(About.licenseParagraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph)
                        .font(.footnote)
                        .monospaced()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // The one leading edge every text block on a page begins on, per
            // docs/interaction-design.md § Navigation.
            .padding(16)
        }
        .textSelection(.enabled)
        .navigationTitle("about.license")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
