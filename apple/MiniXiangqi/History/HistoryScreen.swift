// The History destination: every game the player has filed, and nothing else.
//
// docs/interaction-design.md, "History library": pinned records appear before
// unpinned ones, each group newest first. That order is the core's guarantee
// and this screen never re-sorts it — the two sections are the pinned prefix
// and the rest, which is what makes pinned-ness legible as ordering rather than
// as a badge, and what makes a pin that failed visible as a row that did not
// move.
//
// Selecting a row opens its read-only replay. The row actions are Pin or Unpin,
// 共享 and Delete, on a swipe and in the context menu. Deletion confirms unless
// the player has said not to: 删除前确认 is the Settings switch that defaults on,
// read at the moment a deletion is asked for, and with it off the record goes
// immediately — which is a promise the switch's own footer makes and this screen
// keeps. Every route to a deletion goes through one call, so the swipe, the
// complete swipe, the context menu and the screen-reader action all honour it.
//
// This is also where a game comes in. Import is one file at a time, from the
// toolbar, on the screen the list is already on — so the result of a successful
// import is the row appearing, scrolled to and briefly lit, rather than an
// alert about something the player can already see. Everything else an import
// can answer *is* an alert, because every one of those is a thing that did not
// happen.

import MiniXiangqiCore
import SwiftUI

struct HistoryScreen: View {
    /// The library, held above the container and handed down.
    ///
    /// It is the app's rather than this destination's, for the same reason the
    /// game is: the container tears one destination's content down and rebuilds
    /// it on every visit, so a library created in here would be a *different*
    /// library on every visit, each with its own copy of the list. That is
    /// merely wasteful until something writes to the store while another copy
    /// is on screen — an import is exactly that — at which point one copy holds
    /// the new record and the one being looked at does not.
    let library: HistoryLibrary

    /// A record another destination asked to be shown — the just-recorded
    /// game's 回放. It is resolved against the loaded list rather than pushed
    /// blind, because the destination takes a record and not an identifier.
    @Binding var pendingReplay: UInt64?

    /// Game files a debug launch asked to be imported, taken and cleared the
    /// first time this destination appears. Always empty in a release build.
    ///
    /// It lives above the container for the same reason the pending replay
    /// does: this destination is torn down and rebuilt on every visit, so a
    /// request held inside it would be made again on the second visit — and an
    /// import made twice is a duplicate, which is a test's own setup producing
    /// the very thing another test is about.
    @Binding var pendingImports: [Data]

    @State private var path: [RecordSummary] = []

    /// The record a deletion is about — while its confirmation is up, and
    /// afterwards while a refused deletion offers its retry.
    @State private var deleting: RecordSummary?
    @State private var confirmingDeletion = false

    /// The file picker. What the import it starts has to say is the library's,
    /// not this view's — see `HistoryLibrary.importAnswer`.
    @State private var importing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("nav.history")
                .navigationDestination(for: RecordSummary.self) { record in
                    ReplayScreen(record: record, library: library)
                }
                .toolbar {
                    ToolbarItem {
                        Button("control.import",
                               systemImage: "square.and.arrow.down") {
                            importing = true
                        }
                        .accessibilityIdentifier("history-import")
                    }
                }
        }
        .environment(\.motionPolicy, policy)
        .onAppear {
            // Filing a game happens on the other destination, so coming back
            // here is exactly when the list may have changed underneath. The
            // library revision is what says whether it did.
            library.loadIfChanged()
            showPendingReplay()
            importPendingFiles()
        }
        .onChange(of: pendingReplay) { _, _ in showPendingReplay() }
        // One file at a time is the accepted rule, and the picker is the
        // cheapest place to keep it: a player never selects five games and then
        // has four of them refused. The allowed type is the declared one, so
        // the in-band check the core makes is a second line of defence rather
        // than the only one.
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.miniXiangqiGame],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { open(url) }
            case .failure:
                // The picker could not hand the file over at all, which from
                // here is indistinguishable from a file that cannot be read.
                library.reportUnreadableFile()
            }
        }
    }

    private var content: some View {
        list
            .alert("alert.deleteGame.title", isPresented: $confirmingDeletion) {
                Button("control.cancel", role: .cancel) { deleting = nil }
                Button("control.delete", role: .destructive) {
                    if let record = deleting { library.delete(record) }
                }
            } message: {
                Text("alert.deleteGame.message")
            }
            // A deletion the store refused: the record is still there, and the
            // retry is the same deletion. Same shape as every other "could not
            // do it, nothing changed, try again" in the app.
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
            // Every answer an import has other than the row appearing. One
            // alert rather than five, because they differ in their words and
            // their actions and in nothing else.
            .alert(LocalizedStringKey(library.importAnswer?.title ?? ""),
                   isPresented: Binding(get: { library.importAnswer != nil },
                                        set: { if !$0 { library.dismissImportAnswer() } }),
                   presenting: library.importAnswer) { answer in
                actions(for: answer)
            } message: { answer in
                Text(LocalizedStringKey(answer.message))
            }
    }

    @ViewBuilder
    private var list: some View {
        if let failure = library.failure, library.records.isEmpty {
            // A library that cannot be read is worth saying so about: an empty
            // list here would be a claim about the player's games that this
            // screen has no evidence for. The description is the core's own
            // diagnostic text — not copy, and not localized.
            ContentUnavailableView("failure.historyDidNotLoad",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(verbatim: failure.description).monospaced())
        } else if library.isEmpty {
            // And an empty one says so quietly and offers nothing else to do.
            // Import is on the toolbar above it, where it is for a full library
            // too.
            ContentUnavailableView("history.empty.title", systemImage: "tray",
                                   description: Text("history.empty.description"))
        } else {
            ScrollViewReader { scroll in
                List {
                    if !library.pinnedRecords.isEmpty {
                        Section("history.section.pinned") {
                            rows(library.pinnedRecords)
                        }
                        Section("history.section.others") {
                            rows(library.unpinnedRecords)
                        }
                    } else {
                        // With nothing pinned there is one unheaded section, and
                        // the list looks like a plain list of games.
                        rows(library.unpinnedRecords)
                    }
                }
                .accessibilityIdentifier("history-list")
                .onChange(of: library.importedRecord) { _, id in
                    guard let id else { return }
                    // A scroll is travel, and travel is what Reduce Motion
                    // removes: the row still arrives, immediately. The light on
                    // it is colour, which the same rule leaves alone.
                    if let animation = policy.scroll(Motion.stateFadeAnimation) {
                        withAnimation(animation) { scroll.scrollTo(id, anchor: .center) }
                    } else {
                        scroll.scrollTo(id, anchor: .center)
                    }
                }
                // The light decays on its own; nothing here dismisses anything
                // the player has to read.
                .task(id: library.importedRecord) {
                    guard library.importedRecord != nil else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(policy.fade(Motion.stateFadeAnimation)) {
                        library.clearImportedRecord()
                    }
                }
            }
        }
    }

    private func rows(_ records: ArraySlice<RecordSummary>) -> some View {
        ForEach(records) { record in
            NavigationLink(value: record) {
                row(record)
            }
            // Addressed by position, because position is the thing the
            // ordering rule is about: `history-row-0` is whatever the core
            // put first.
            .accessibilityIdentifier("history-row-\(library.records.firstIndex(of: record) ?? 0)")
            .listRowBackground(library.importedRecord == record.id
                               ? Color.accentColor.opacity(0.18) : nil)
            // Delete is listed first so that it is the outermost trailing
            // action and the full-swipe default, which is what the accepted
            // "Delete nearest the trailing edge" and "a complete right-to-left
            // swipe invokes Delete" come to in this framework's own order.
            // 共享 is second, which puts it to Delete's left — the accepted
            // reading order of the pair.
            .swipeActions(edge: .trailing) {
                Button("control.delete", systemImage: "trash", role: .destructive) {
                    confirmDeletion(of: record)
                }
                shareButton(record).tint(.blue)
            }
            .swipeActions(edge: .leading) {
                pinButton(record).tint(.orange)
            }
            // The pointer equivalent the contract asks for, without adding a
            // permanent button to the row.
            .contextMenu {
                pinButton(record)
                shareButton(record)
                Button("control.delete", systemImage: "trash", role: .destructive) {
                    confirmDeletion(of: record)
                }
            }
            // And the screen-reader equivalent, in the same order.
            .accessibilityActions {
                pinButton(record)
                shareButton(record)
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

    private func pinButton(_ record: RecordSummary) -> some View {
        Button(record.pinned ? "control.unpin" : "control.pin",
               systemImage: record.pinned ? "pin.slash" : "pin") {
            library.setPinned(!record.pinned, on: record)
        }
    }

    /// 共享 exports the record as one game file. The export itself happens
    /// inside the transfer representation, when a service asks for the file, so
    /// presenting this costs nothing and no work is done for a share sheet the
    /// player dismisses.
    private func shareButton(_ record: RecordSummary) -> some View {
        ShareLink(item: GameFile(record: record, store: library.store),
                  preview: SharePreview(record.metadataLine)) {
            Label("control.share", systemImage: "square.and.arrow.up")
        }
    }

    /// Deletes the record, asking first where the preference says to ask.
    ///
    /// The record is held either way, because the deletion that a store refuses
    /// offers to be retried and the retry has to name the same record — that
    /// alert is about a deletion that did not happen and is not the confirmation
    /// this switch governs.
    private func confirmDeletion(of record: RecordSummary) {
        deleting = record
        if Preferences.deleteConfirmation.value() {
            confirmingDeletion = true
        } else {
            library.delete(record)
        }
    }

    // MARK: - Import

    /// Reads the chosen file and hands it to the core, which decides everything
    /// about it. The bytes are read inside the security scope the picker
    /// granted, and nothing about the file is kept afterwards — no bookmark, no
    /// reference, no second look. It is untrusted input that has been copied
    /// once and let go.
    private func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // The 1 MiB bound is the core's, and the core is what enforces it; this
        // only declines to allocate what it is about to be refused for. A file
        // whose size cannot be read at all is carried on and let the core
        // answer, because not knowing a size is not the same as knowing a bad
        // one.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard size.map({ $0 <= Self.importByteLimit }) ?? true,
              let bytes = try? Data(contentsOf: url) else {
            library.reportUnreadableFile()
            return
        }
        Task { await library.importGame(bytes) }
    }

    /// The accepted per-file import bound of docs/game-data.md, in bytes.
    private static let importByteLimit = 1024 * 1024

    @ViewBuilder
    private func actions(for answer: ImportAnswer) -> some View {
        switch answer {
        case .duplicate(let record):
            // The accepted "offers a way to view the existing record".
            Button("control.view") { path = [record] }
            Button("control.ok", role: .cancel) { }
        case .saveFailed(let bytes):
            Button("control.cancel", role: .cancel) { }
            Button("control.tryAgain") { Task { await library.importGame(bytes) } }
        // A damaged record joins the three that offer only acknowledgement, and
        // for the same reason each of them does: there is no action the app can
        // put behind a button that would change the answer. The route out of
        // this one is in its message, as the conflict's is.
        case .conflict, .unreadable, .newerVersion, .damagedRecord:
            Button("control.ok", role: .cancel) { }
        }
    }

    /// The files a debug launch asked for, taken once and imported in order.
    ///
    /// Each one goes through the same call the picker's completion makes, so
    /// the pipeline, the answer it produces and the presentation of that answer
    /// are all the real ones; the only thing standing aside is the system's
    /// open panel, which belongs to the system.
    private func importPendingFiles() {
        guard !pendingImports.isEmpty else { return }
        let files = pendingImports
        pendingImports = []
        Task {
            // In order, and one at a time: importing the same file twice is
            // exactly how the duplicate answer is reached, and the second
            // import must see what the first one wrote.
            for file in files { await library.importGame(file) }
        }
    }

    /// Pushes the record another destination asked for, once the list holding
    /// it has loaded. An identifier that names no record — a game deleted since
    /// — is dropped rather than reported: the request is a convenience, and the
    /// list it lands on is the answer either way.
    private func showPendingReplay() {
        guard let id = pendingReplay else { return }
        guard let record = library.records.first(where: { $0.id == id }) else {
            pendingReplay = nil
            return
        }
        path = [record]
        pendingReplay = nil
    }
}
