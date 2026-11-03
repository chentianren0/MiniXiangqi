// macOS also keeps the system's About box in the app menu; that one is the
// platform's, this page is the app's, and they need not match.

import SwiftUI

struct AboutScreen: View {

    var body: some View {
        Form {
            identity
            licence
        }
        .formStyle(.grouped)
        .navigationTitle("about.title")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

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

    /// One group because the later rows exist on account of the first: GPLv3 is
    /// a licence about source.
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

/// Monospaced because the plain-text document aligns columns. Not localized: a
/// translation would not be the licence.
///
/// Paragraph by paragraph: one 35 KB `Text` is one accessibility element a
/// screen reader cannot move around inside, and one layout pass for the whole
/// document before anything appears.
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
            // The leading edge every text block on a page begins on.
            .padding(16)
        }
        .textSelection(.enabled)
        .navigationTitle("about.license")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Each footer carries its group's licence, since the licences differ by group.
/// The addresses are force-unwrapped for the reason `About.repository` is.
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
        }
        .formStyle(.grouped)
        .navigationTitle("about.acknowledgements")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// The name is verbatim: a project's name is not copy.
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
