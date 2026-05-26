import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptionSession.createdAt, order: .reverse)
    private var sessions: [TranscriptionSession]

    @State private var searchText: String = ""

    /// True while the user is in multi-select mode (Edit → Done).
    @State private var isSelecting: Bool = false

    /// IDs of sessions the user has ticked in selection mode.
    @State private var selectedIDs: Set<UUID> = []

    /// Sessions queued for confirmation. When non-empty, the alert appears.
    @State private var pendingDelete: [TranscriptionSession] = []

    var filtered: [TranscriptionSession] {
        guard !searchText.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.fullTranscript.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        sessions.isEmpty ? "No recordings yet" : "No matches",
                        systemImage: "tray",
                        description: Text(sessions.isEmpty
                                          ? "Record or import audio to see it here."
                                          : "Try a different search term.")
                    )
                } else {
                    ForEach(filtered) { session in
                        rowFor(session)
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search transcripts")
            .navigationDestination(for: TranscriptionSession.self) { session in
                TranscriptView(session: session)
            }
            .toolbar { toolbarContent }
            .confirmationDialog(
                confirmationTitle,
                isPresented: confirmationBinding,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { commitPendingDelete() }
                Button("Cancel", role: .cancel) { pendingDelete.removeAll() }
            } message: {
                Text(confirmationMessage)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func rowFor(_ session: TranscriptionSession) -> some View {
        Group {
            if isSelecting {
                selectableRow(for: session)
            } else {
                NavigationLink(value: session) {
                    SessionRowView(session: session)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = [session]
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = [session]
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                pendingDelete = []
                isSelecting = true
                selectedIDs = [session.id]
            } label: {
                Label("Select more…", systemImage: "checkmark.circle")
            }
        }
    }

    private func selectableRow(for session: TranscriptionSession) -> some View {
        Button {
            toggleSelection(of: session)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedIDs.contains(session.id)
                      ? "checkmark.circle.fill"
                      : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedIDs.contains(session.id) ? Color.accentColor : .secondary)
                SessionRowView(session: session)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    isSelecting = false
                    selectedIDs.removeAll()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    queueBulkDelete()
                } label: {
                    if selectedIDs.isEmpty {
                        Label("Delete", systemImage: "trash")
                    } else {
                        Label("Delete (\(selectedIDs.count))", systemImage: "trash")
                    }
                }
                .disabled(selectedIDs.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(filtered.map { $0.id })
                    }
                }
                .disabled(filtered.isEmpty)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isSelecting = true
                    selectedIDs.removeAll()
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                .disabled(filtered.isEmpty)
            }
        }
    }

    private var allSelected: Bool {
        !filtered.isEmpty && selectedIDs.count == filtered.count
    }

    // MARK: - Selection helpers

    private func toggleSelection(of session: TranscriptionSession) {
        if selectedIDs.contains(session.id) {
            selectedIDs.remove(session.id)
        } else {
            selectedIDs.insert(session.id)
        }
    }

    private func queueBulkDelete() {
        let toDelete = filtered.filter { selectedIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        pendingDelete = toDelete
    }

    // MARK: - Confirmation

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { !pendingDelete.isEmpty },
            set: { if !$0 { pendingDelete.removeAll() } }
        )
    }

    private var confirmationTitle: String {
        switch pendingDelete.count {
        case 0:  return ""
        case 1:  return "Delete this transcript?"
        default: return "Delete \(pendingDelete.count) transcripts?"
        }
    }

    private var confirmationMessage: String {
        if pendingDelete.count == 1, let only = pendingDelete.first {
            return "“\(only.title)” and its audio file will be permanently removed. This cannot be undone."
        }
        return "These transcripts and their audio files will be permanently removed. This cannot be undone."
    }

    private func commitPendingDelete() {
        let targets = pendingDelete
        pendingDelete.removeAll()
        for session in targets {
            SessionStore.delete(session, context: modelContext)
        }
        // Drop deleted IDs out of the selection set; if nothing left, leave selection mode.
        let deletedIDs = Set(targets.map { $0.id })
        selectedIDs.subtract(deletedIDs)
        if isSelecting && selectedIDs.isEmpty {
            // Stay in selection mode if there are still rows to act on, otherwise exit.
            if filtered.isEmpty { isSelecting = false }
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [TranscriptionSession.self, TranscriptSegment.self], inMemory: true)
}
