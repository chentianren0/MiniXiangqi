// Every route to a deletion goes through `confirmDeletion`, so the swipe, the
// full swipe, the context menu and the screen-reader action all honour
// 删除前确认.

import SwiftUI

struct HistoryScreen: View {
    /// Held above the container, which rebuilds this destination on every
    /// visit: a library created in here would be a fresh copy each time, and an
    /// import could land in a copy that is not the one on screen.
    let library: HistoryLibrary

    /// Resolved against the loaded list rather than pushed blind, because the
    /// destination takes a record, not an identifier.
    @Binding var pendingReplay: UUID?

    @State private var path: [GameRecord] = []

    /// Held while the confirmation is up, and afterwards while a refused
    /// deletion offers its retry.
    @State private var deleting: GameRecord?
    @State private var confirmingDeletion = false
    @AppStorage("deleteConfirmation.enabled") private var confirmsDeletion = true

    @State private var importing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var policy: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("nav.history")
                .navigationDestination(for: GameRecord.self) { record in
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
            // here is exactly when the list may have changed underneath.
            library.load()
            showPendingReplay()
        }
        .onChange(of: pendingReplay) { _, _ in showPendingReplay() }
        // One file at a time, enforced in the picker, so a player never selects
        // five games and has four refused.
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.miniXiangqiGame],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { open(url) }
            case .failure:
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
        // One alert rather than five: the answers differ only in their words
        // and actions.
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
            // An empty list here would claim something about the player's games
            // with no evidence. The description is diagnostic, not localized.
            ContentUnavailableView("failure.historyDidNotLoad",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(verbatim: failure.description).monospaced())
        } else if library.isEmpty {
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
                        rows(library.unpinnedRecords)
                    }
                }
                .accessibilityIdentifier("history-list")
                .onChange(of: library.importedRecord) { _, id in
                    guard let id else { return }
                    // Reduce Motion removes the scroll's travel; the row still
                    // arrives, and its light is colour, which stays.
                    if let animation = policy.scroll(Motion.stateFadeAnimation) {
                        withAnimation(animation) { scroll.scrollTo(id, anchor: .center) }
                    } else {
                        scroll.scrollTo(id, anchor: .center)
                    }
                }
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

    private func rows(_ records: ArraySlice<GameRecord>) -> some View {
        ForEach(records) { record in
            NavigationLink(value: record) {
                row(record)
            }
            // Addressed by position, because position is what the ordering
            // rule is about.
            .accessibilityIdentifier("history-row-\(library.records.firstIndex(of: record) ?? 0)")
            .listRowBackground(library.importedRecord == record.id
                               ? Color.accentColor.opacity(0.18) : nil)
            // Listed first so Delete is the outermost trailing action and the
            // full-swipe default, with 共享 to its left.
            .swipeActions(edge: .trailing) {
                Button("control.delete", systemImage: "trash", role: .destructive) {
                    confirmDeletion(of: record)
                }
                shareButton(record).tint(.blue)
            }
            .swipeActions(edge: .leading) {
                pinButton(record).tint(.orange)
            }
            .contextMenu {
                pinButton(record)
                shareButton(record)
                Button("control.delete", systemImage: "trash", role: .destructive) {
                    confirmDeletion(of: record)
                }
            }
            .accessibilityActions {
                pinButton(record)
                shareButton(record)
                Button("control.delete") { confirmDeletion(of: record) }
            }
        }
    }

    private func row(_ record: GameRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(record.whenText)
            // Wraps rather than truncating: an ellipsis would drop a required
            // token.
            Text(record.metadataLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func pinButton(_ record: GameRecord) -> some View {
        Button(record.pinned ? "control.unpin" : "control.pin",
               systemImage: record.pinned ? "pin.slash" : "pin") {
            library.setPinned(!record.pinned, on: record)
        }
    }

    private func shareButton(_ record: GameRecord) -> some View {
        ShareLink(item: GameFile(record: record, in: library.library),
                  preview: SharePreview(record.metadataLine)) {
            Label("control.share", systemImage: "square.and.arrow.up")
        }
    }

    /// The record is held even without confirmation, so a refused deletion's
    /// retry names the same record.
    private func confirmDeletion(of record: GameRecord) {
        deleting = record
        if confirmsDeletion {
            confirmingDeletion = true
        } else {
            library.delete(record)
        }
    }

    // MARK: - Import

    /// Nothing about the file is kept afterwards, no bookmark and no second
    /// look: it is untrusted input, copied once.
    private func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // A game file is a few kilobytes. A size that cannot be read is let
        // through for the library to judge.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard size.map({ $0 <= Self.importByteLimit }) ?? true,
              let bytes = try? Data(contentsOf: url) else {
            library.reportUnreadableFile()
            return
        }
        library.importGame(bytes)
    }

    private static let importByteLimit = 1024 * 1024

    @ViewBuilder
    private func actions(for answer: ImportAnswer) -> some View {
        switch answer {
        case .duplicate(let record):
            Button("control.view") { path = [record] }
            Button("control.ok", role: .cancel) { }
        case .saveFailed(let bytes):
            Button("control.cancel", role: .cancel) { }
            Button("control.tryAgain") { library.importGame(bytes) }
        case .unreadable, .newerVersion, .earlierVersion, .illegalGame:
            Button("control.ok", role: .cancel) { }
        }
    }

    /// An identifier that names no record, a game deleted since, is dropped
    /// silently: the list it lands on is the answer either way.
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
