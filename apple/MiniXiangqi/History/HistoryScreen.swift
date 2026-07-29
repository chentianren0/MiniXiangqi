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
// 共享 and Delete, on a swipe and in the context menu. Deletion always confirms:
// 删除前确认 is a Settings toggle that defaults on, and until a Settings screen
// exists to turn it off, on is what it is.
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
    let core: Core

    /// A record another destination asked to be shown — the just-recorded
    /// game's 回放. It is resolved against the loaded list rather than pushed
    /// blind, because the destination takes a record and not an identifier.
    @Binding var pendingReplay: UInt64?

    @State private var library: HistoryLibrary?
    @State private var path: [RecordSummary] = []

    /// The record a deletion is about — while its confirmation is up, and
    /// afterwards while a refused deletion offers its retry.
    @State private var deleting: RecordSummary?
    @State private var confirmingDeletion = false

    /// The file picker, and what the import it started had to say.
    @State private var importing = false
    @State private var answer: ImportAnswer?

    /// The record a successful import just added, while the list lights it.
    @State private var revealed: UInt64?

    #if DEBUG
    @State private var launchFilesImported = false
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("nav.history")
                .navigationDestination(for: RecordSummary.self) { record in
                    if let library {
                        ReplayScreen(record: record, library: library)
                    }
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
            let library = library ?? HistoryLibrary(store: core.history)
            self.library = library
            library.loadIfChanged()
            showPendingReplay(library)
            #if DEBUG
            importLaunchFiles()
            #endif
        }
        .onChange(of: pendingReplay) { _, _ in
            if let library { showPendingReplay(library) }
        }
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
                answer = .unreadable
            }
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
                // Every answer an import has other than the row appearing. One
                // alert rather than five, because they differ in their words
                // and their actions and in nothing else.
                .alert(LocalizedStringKey(answer?.title ?? ""),
                       isPresented: Binding(get: { answer != nil },
                                            set: { if !$0 { answer = nil } }),
                       presenting: answer) { answer in
                    actions(for: answer)
                } message: { answer in
                    Text(LocalizedStringKey(answer.message))
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
                .onChange(of: revealed) { _, id in
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
            }
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
            .listRowBackground(revealed == record.id
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
                pinButton(library, record).tint(.orange)
            }
            // The pointer equivalent the contract asks for, without adding a
            // permanent button to the row.
            .contextMenu {
                pinButton(library, record)
                shareButton(record)
                Button("control.delete", systemImage: "trash", role: .destructive) {
                    confirmDeletion(of: record)
                }
            }
            // And the screen-reader equivalent, in the same order.
            .accessibilityActions {
                pinButton(library, record)
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

    private func pinButton(_ library: HistoryLibrary,
                           _ record: RecordSummary) -> some View {
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
        ShareLink(item: GameFile(record: record, store: core.history),
                  preview: SharePreview(record.metadataLine)) {
            Label("control.share", systemImage: "square.and.arrow.up")
        }
    }

    private func confirmDeletion(of record: RecordSummary) {
        deleting = record
        confirmingDeletion = true
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
        guard let bytes = try? Data(contentsOf: url) else {
            answer = .unreadable
            return
        }
        Task { await load(bytes) }
    }

    private func load(_ bytes: Data) async {
        guard let library else { return }
        switch await library.importGame(bytes) {
        case .success(let imported) where imported.outcome == .created:
            // No alert. The row is the answer, and it is already on screen.
            answer = nil
            reveal(imported.record.id)
        case .success(let imported):
            answer = .duplicate(imported.record)
        case .failure(let error):
            answer = ImportAnswer(refusing: error, retrying: bytes)
        }
    }

    /// Scrolls the new record into view and lights it briefly. The light decays
    /// on its own; nothing here dismisses anything the player has to read.
    private func reveal(_ record: UInt64) {
        withAnimation(policy.fade(Motion.stateFadeAnimation)) { revealed = record }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(policy.fade(Motion.stateFadeAnimation)) { revealed = nil }
        }
    }

    @ViewBuilder
    private func actions(for answer: ImportAnswer) -> some View {
        switch answer {
        case .duplicate(let record):
            // The accepted "offers a way to view the existing record".
            Button("control.view") { path = [record] }
            Button("control.ok", role: .cancel) { }
        case .saveFailed(let bytes):
            Button("control.cancel", role: .cancel) { }
            Button("control.tryAgain") { Task { await load(bytes) } }
        case .conflict, .unreadable, .newerVersion:
            Button("control.ok", role: .cancel) { }
        }
    }

    #if DEBUG
    /// The game files `-mxq-import <base64>;<base64>` names, imported in order
    /// the first time this destination appears.
    ///
    /// Each one goes through `load(_:)` — the very call the picker's completion
    /// makes — so the pipeline, the answer it produces and the presentation of
    /// that answer are all the real ones; the only thing standing aside is the
    /// system's open panel, which belongs to the system. The bytes travel in
    /// the argument rather than as a path because the runner and the app are
    /// separate sandboxes and a path one of them can read the other cannot.
    private func importLaunchFiles() {
        guard !launchFilesImported else { return }
        launchFilesImported = true
        let files = (DebugLaunch.argument(after: "-mxq-import") ?? "")
            .split(separator: ";")
            .compactMap { Data(base64Encoded: String($0)) }
        guard !files.isEmpty else { return }
        Task {
            // In order, and one at a time: importing the same file twice is
            // exactly how the duplicate answer is reached, and the second
            // import must see what the first one wrote.
            for file in files { await load(file) }
        }
    }
    #endif

    /// Pushes the record another destination asked for, once the list holding
    /// it has loaded. An identifier that names no record — a game deleted since
    /// — is dropped rather than reported: the request is a convenience, and the
    /// list it lands on is the answer either way.
    private func showPendingReplay(_ library: HistoryLibrary) {
        guard let id = pendingReplay else { return }
        guard let record = library.records.first(where: { $0.id == id }) else {
            pendingReplay = nil
            return
        }
        path = [record]
        pendingReplay = nil
    }
}

/// Everything an import can answer other than a row appearing.
///
/// The classes are the ones the core's own taxonomy distinguishes, and no
/// others: a file that is not ours and a file that is damaged are both
/// `MXQ_ERR_ARCHIVE_MALFORMED`, and telling them apart above the interface
/// would mean reading a diagnostic string the contract reserves for logs. The
/// picker is where the wrong-file case is actually prevented, by filtering to
/// the declared type.
///
/// The created-by-a-newer-version answer is the one the data contract requires
/// to be distinct and never to be presented as corruption, and it is.
private enum ImportAnswer {
    case duplicate(RecordSummary)
    case conflict
    case newerVersion
    case unreadable
    /// The file was fine; the library would not take it. The bytes are held so
    /// that 重试 is a retry of the same import.
    case saveFailed(Data)

    init(refusing error: CoreError, retrying bytes: Data) {
        switch error.status {
        case MxqStatus(MXQ_ERR_STORE_IDENTITY_CONFLICT):
            self = .conflict
        case MxqStatus(MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION):
            self = .newerVersion
        default:
            // Which side refused decides which sentence is true: the archive
            // domain means the file, and anything else that reaches here means
            // the write that would have filed it.
            self = mxq_status_domain(error.status) == MxqStatus(MXQ_DOMAIN_ARCHIVE)
                ? .unreadable : .saveFailed(bytes)
        }
    }

    var title: String {
        switch self {
        case .duplicate: "alert.importDuplicate.title"
        case .conflict: "alert.importConflict.title"
        case .newerVersion: "alert.importNewerVersion.title"
        case .unreadable: "alert.importUnreadable.title"
        case .saveFailed: "alert.importSaveFailed.title"
        }
    }

    var message: String {
        switch self {
        case .duplicate: "alert.importDuplicate.message"
        case .conflict: "alert.importConflict.message"
        case .newerVersion: "alert.importNewerVersion.message"
        case .unreadable: "alert.importUnreadable.message"
        case .saveFailed: "alert.importSaveFailed.message"
        }
    }
}
