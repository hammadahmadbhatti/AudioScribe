import SwiftUI

/// Live caption box rendered while recording.
/// - Finalized text: full-opacity primary color.
/// - Interim hypothesis: dimmed secondary color, replaced as the recognizer revises.
/// - Auto-scrolls to bottom as text grows.
struct LiveCaptionView: View {
    let finalizedText: String
    let interimText: String
    let isListening: Bool
    let statusMessage: String?

    /// Stable sentinel id for the bottom-of-content anchor. Used as the target
    /// for `ScrollViewReader.scrollTo`. We deliberately do NOT rotate this id
    /// per update — mutating @State inside `onChange` is what produced the
    /// "action tried to update multiple times per frame" SwiftUI warning.
    private static let bottomAnchorID = "AudioScribe.captionBottomAnchor"

    /// Single observable that combines both texts. Watching one derived value
    /// instead of two raw @Published strings collapses the case where
    /// `LiveTranscriptionService` updates both in the same frame into a
    /// single onChange invocation.
    private var captionSignal: String {
        finalizedText + "\u{1F}" + interimText
    }

    private var hasContent: Bool {
        !finalizedText.isEmpty || !interimText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isListening ? "waveform.badge.mic" : "captions.bubble")
                    .foregroundStyle(isListening ? .red : .secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: isListening)
                Text("Live captions")
                    .font(.headline)
                Spacer()
                if isListening {
                    Text("Listening…")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if !hasContent && isListening {
                            Text("Start speaking — words appear here as Apple Speech recognises them.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .italic()
                        }

                        // Combine finalized + interim into a single Text run with
                        // styled segments so they wrap together naturally.
                        captionText
                            .font(.body)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(Self.bottomAnchorID)
                    }
                    .padding(12)
                }
                .frame(minHeight: 100, maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondaryBackground)
                )
                .onChange(of: captionSignal) { _, _ in
                    // Snap to the bottom on any text change. Animation was
                    // removed: at 5–10 interim updates per second the queued
                    // easeOut transitions piled up on the main thread and made
                    // the captions feel sluggish on longer recordings.
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var captionText: some View {
        if !finalizedText.isEmpty && !interimText.isEmpty {
            (Text(finalizedText)
                .foregroundStyle(.primary)
             + Text(" " + interimText)
                .foregroundStyle(.secondary))
        } else if !finalizedText.isEmpty {
            Text(finalizedText).foregroundStyle(.primary)
        } else if !interimText.isEmpty {
            Text(interimText).foregroundStyle(.secondary)
        } else {
            EmptyView()
        }
    }
}
