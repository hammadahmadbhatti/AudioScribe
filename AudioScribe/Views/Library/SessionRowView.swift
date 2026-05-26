import SwiftUI

struct SessionRowView: View {
    let session: TranscriptionSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                if !session.fullTranscript.isEmpty {
                    Text(session.fullTranscript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 12) {
                    Label(session.formattedDuration, systemImage: "clock")
                    Label(session.createdAt.formatted(date: .abbreviated, time: .shortened),
                          systemImage: "calendar")
                    if let lang = session.detectedLanguage {
                        Label(lang.uppercased(), systemImage: "globe")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
