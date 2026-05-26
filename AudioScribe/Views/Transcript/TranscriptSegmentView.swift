import SwiftUI

struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Text(TimeFormatter.format(seconds: segment.startSeconds))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 56, alignment: .leading)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)

                Text(segment.text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
