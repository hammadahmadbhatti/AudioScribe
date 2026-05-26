import SwiftUI
import SwiftData

struct TranscriptView: View {
    let session: TranscriptionSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    @State private var loadError: String?
    @State private var showDeleteConfirm: Bool = false

    var sortedSegments: [TranscriptSegment] {
        session.segments.sorted { $0.index < $1.index }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    TranslationPanel(session: session)

                    if !session.fullTranscript.isEmpty && sortedSegments.isEmpty {
                        Text(session.fullTranscript)
                            .font(.body)
                            .padding(.vertical, 8)
                    }

                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(sortedSegments) { segment in
                            TranscriptSegmentView(
                                segment: segment,
                                isActive: segment.contains(time: player.currentTime),
                                onTap: { jump(to: segment.startSeconds) }
                            )
                            .id(segment.id)
                        }
                    }

                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: activeSegmentID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
        .background(Color.groupedBackground)
        .navigationTitle(session.title)
        .toolbar {
            ToolbarItemGroup {
                ShareLink(item: session.fullTranscript, subject: Text(session.title))
                    .disabled(session.fullTranscript.isEmpty)
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            PlaybackControls(player: player)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
        .task(id: session.id) {
            await load()
        }
        .onDisappear {
            player.stopAndReset()
        }
        .confirmationDialog(
            "Delete this transcript?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(session.title)” and its audio file will be permanently removed. This cannot be undone.")
        }
    }

    private func performDelete() {
        player.stopAndReset()
        SessionStore.delete(session, context: modelContext)
        dismiss()
    }

    private var activeSegmentID: UUID? {
        sortedSegments.first(where: { $0.contains(time: player.currentTime) })?.id
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title)
                .font(.largeTitle.bold())
            HStack(spacing: 12) {
                Label(session.createdAt.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                Label(session.formattedDuration, systemImage: "clock")
                Label(session.modelUsed.replacingOccurrences(of: "openai_whisper-", with: ""),
                      systemImage: "cpu")
                if let lang = session.detectedLanguage {
                    Label(lang.uppercased(), systemImage: "globe")
                }
                if session.wasTranslatedDuringTranscription {
                    Label("Translated to English by Whisper", systemImage: "character.bubble")
                        .foregroundStyle(.blue)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        do {
            try player.load(url: session.audioURL)
            loadError = nil
        } catch {
            loadError = "Could not load audio file: \(error.localizedDescription)"
        }
    }

    private func jump(to seconds: Double) {
        player.seek(to: seconds)
        if !player.isPlaying { player.play() }
    }
}
