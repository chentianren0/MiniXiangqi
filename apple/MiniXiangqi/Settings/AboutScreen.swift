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
// **And the work it is built on.** The licence group's third row opens the
// Acknowledgements page, which names the open-source components the application
// embeds — each one, what it does here, and its home — because a free-software
// application says what it is made of. No diagnostics: the page exists for the
// licence, the release it identifies, and the work under both.

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

    /// The licence, its full text, the source it is a licence about, and the
    /// open-source work that arrived under the same terms.
    ///
    /// The three rows are one group because the later ones exist on account of
    /// the first: GPLv3 is a licence about source, so the address is part of
    /// what the statement beneath them says rather than a separate offer, and
    /// the acknowledgements name the work that licence was accepted for. The
    /// statement is a footer because that is what a sentence of explanation is
    /// on this screen — the two footers in Settings are the same shape.
    private var licence: some View {
        Section {
            NavigationLink("about.license") { LicenseScreen() }
                .accessibilityIdentifier("about-license")
            Link("about.source", destination: About.repository)
                .accessibilityIdentifier("about-source")
            NavigationLink("about.acknowledgements") { AcknowledgementsScreen() }
                .accessibilityIdentifier("about-acknowledgements")
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

/// The open-source work the application embeds, named.
///
/// docs/interaction-design.md, "Navigation": the About page names the
/// open-source components the application is built on — each one, what it does
/// here, its licence, and a link to its home. The components and their
/// licences are the ones `pinned-inputs.json` records; the addresses are
/// spelled here for the reason `About.repository` is, so a URL that failed to
/// parse would be a typo in its own line rather than a state the running
/// application can reach.
///
/// Three groups by what the components are — the engines, the networks they
/// play with, and the library beneath History — each footer carrying its
/// group's licence, because the licences differ by group and a sentence per
/// row would say each one three times.
struct AcknowledgementsScreen: View {

    var body: some View {
        Form {
            Section {
                row("Fairy-Stockfish", "about.acknowledgements.fairyStockfish",
                    "https://github.com/fairy-stockfish/Fairy-Stockfish",
                    id: "ack-fairy-stockfish")
                row("Rapfi", "about.acknowledgements.rapfi",
                    "https://github.com/dhbloo/rapfi",
                    id: "ack-rapfi")
                row("Pikafish", "about.acknowledgements.pikafish",
                    "https://github.com/official-pikafish/Pikafish",
                    id: "ack-pikafish")
            } footer: {
                Text("about.acknowledgements.engines.footer")
            }
            Section {
                row("Fairy-Stockfish NNUE", "about.acknowledgements.xiangqiNetwork",
                    "https://github.com/fairy-stockfish/Fairy-Stockfish-NNUE",
                    id: "ack-xiangqi-network")
                row("Rapfi Networks", "about.acknowledgements.rapfiNetworks",
                    "https://github.com/dhbloo/rapfi-networks",
                    id: "ack-rapfi-networks")
            } footer: {
                Text("about.acknowledgements.networks.footer")
            }
            Section {
                row("SQLite", "about.acknowledgements.sqlite",
                    "https://sqlite.org",
                    id: "ack-sqlite")
            } footer: {
                Text("about.acknowledgements.data.footer")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("about.acknowledgements")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// One component: its own name, what it does in this application, and a
    /// link out to where it lives. The name is verbatim — a project's name is
    /// not copy — and the row is the link, the way the source row on About is.
    private func row(_ name: String, _ role: LocalizedStringKey,
                     _ address: String, id: String) -> some View {
        Link(destination: URL(string: address)!) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                Text(role)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(id)
    }
}
