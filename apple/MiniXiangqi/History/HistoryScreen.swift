// The History destination: every game the player has filed, and nothing else.
//
// docs/interaction-design.md, "History library": pinned records appear before
// unpinned ones, each group newest first. That order is the core's guarantee
// and this screen never re-sorts it — the two sections are the pinned prefix
// and the rest, which is what makes pinned-ness legible as ordering rather than
// as a badge, and what makes a pin that failed visible as a row that did not
// move.
//
// Selecting a row opens its read-only replay. The row actions are Pin or Unpin
// and Delete, on a swipe and in the context menu; 共享 arrives with import and
// export and is deliberately absent here. Deletion always confirms: 删除前确认
// is a Settings toggle that defaults on, and until a Settings screen exists to
// turn it off, on is what it is.

import SwiftUI

struct HistoryScreen: View {
    let core: Core

    @State private var library: HistoryLibrary?

    /// The record a deletion is about — while its confirmation is up, and
    /// afterwards while a refused deletion offers its retry.
    @State private var deleting: RecordSummary?
    @State private var confirmingDeletion = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("nav.history")
                .navigationDestination(for: RecordSummary.self) { record in
                    if let library {
                        ReplayScreen(record: record, library: library)
                    }
                }
        }
        .onAppear {
            // Filing a game happens on the other destination, so coming back
            // here is exactly when the list may have changed underneath. The
            // library revision is what says whether it did.
            let library = library ?? HistoryLibrary(store: core.history)
            self.library = library
            library.loadIfChanged()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let library {
            list(library)
                .alert("alert.deleteGame.title", isPresented: $confirmingDeletion) {
                    Button("control.cancel", role: .cancel) { deleting = nil }
                    Button("control.delete", role: .destructive) {
                        if let record = deleting { library.delete(record) }
                    }
                } message: {
                    Text("alert.deleteGame.message")
                }
                // A deletion the store refused: the record is still there, and
                // the retry is the same deletion. Same shape as every other
                // "could not do it, nothing changed, try again" in the app.
                .alert("alert.deleteFailed.title",
                       isPresented: Binding(get: { library.deletionFailure != nil },
                                            set: { if !$0 { library.dismissDeletionFailure() } })) {
                    Button("control.cancel", role: .cancel) {
                        library.dismissDeletionFailure()
                        deleting = nil
                    }
                    Button("control.tryAgain") {
                        library.dismissDeletionFailure()
                        if let record = deleting { library.delete(record) }
                    }
                } message: {
                    Text("alert.deleteFailed.message")
                }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func list(_ library: HistoryLibrary) -> some View {
        if let failure = library.failure, library.records.isEmpty {
            // A library that cannot be read is worth saying so about: an empty
            // list here would be a claim about the player's games that this
            // screen has no evidence for. The description is the core's own
            // diagnostic text — not copy, and not localized.
            ContentUnavailableView("failure.historyDidNotLoad",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(verbatim: failure.description).monospaced())
        } else if library.isEmpty {
            ContentUnavailableView("history.empty.title", systemImage: "tray",
                                   description: Text("history.empty.description"))
        } else {
            List {
                if !library.pinnedRecords.isEmpty {
                    Section("history.section.pinned") {
                        rows(library, library.pinnedRecords)
                    }
                    Section("history.section.others") {
                        rows(library, library.unpinnedRecords)
                    }
                } else {
                    // With nothing pinned there is one unheaded section, and
                    // the list looks like a plain list of games.
                    rows(library, library.unpinnedRecords)
                }
            }
            .accessibilityIdentifier("history-list")
        }
    }

    private func rows(_ library: HistoryLibrary,
                      _ records: ArraySlice<RecordSummary>) -> some View {
        ForEach(records) { record in
            NavigationLink(value: record) {
                row(record)
            }
            // Addressed by position, because position is the thing the
            // ordering rule is about: `history-row-0` is whatever the core
            // put first.
            .accessibilityIdentifier("history-row-\(library.records.firstIndex(of: record) ?? 0)")
            // Delete is listed first so that it is the outermost trailing
            // action and the full-swipe default, which is what the accepted
            // "Delete nearest the trailing edge" and "a complete right-to-left
            // swipe invokes Delete" come to in this framework's own order.
            .swipeActions(edge: .trailing) {
                Button("control.delete", systemImage: "trash", role: .destructive) {
                    confirmDeletion(of: record)
                }
            }
            .swipeActions(edge: .leading) {
                pinButton(library, record).tint(.orange)
            }
            // The pointer equivalent the contract asks for, without adding a
            // permanent button to the row.
            .contextMenu {
                pinButton(library, record)
                Button("control.delete", systemImage: "trash", role: .destructive) {
                    confirmDeletion(of: record)
                }
            }
            // And the screen-reader equivalent, in the same order.
            .accessibilityActions {
                pinButton(library, record)
                Button("control.delete") { confirmDeletion(of: record) }
            }
        }
    }

    private func row(_ record: RecordSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(record.whenText)
            // Every token in this line is contract-required row content, so it
            // wraps rather than truncating: an ellipsis here would drop one.
            Text(record.metadataLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
        }
        .padding(.vertical, 4)
        // One element per row, read as one sentence, so a screen-reader user
        // does not have to swipe twice per game.
        .accessibilityElement(children: .combine)
    }

    private func pinButton(_ library: HistoryLibrary,
                           _ record: RecordSummary) -> some View {
        Button(record.pinned ? "control.unpin" : "control.pin",
               systemImage: record.pinned ? "pin.slash" : "pin") {
            library.setPinned(!record.pinned, on: record)
        }
    }

    private func confirmDeletion(of record: RecordSummary) {
        deleting = record
        confirmingDeletion = true
    }
}
