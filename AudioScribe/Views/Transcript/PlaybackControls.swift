import SwiftUI

struct PlaybackControls: View {
    @ObservedObject var player: AudioPlayer

    var body: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 0.01)
            )

            HStack {
                Text(TimeFormatter.format(seconds: player.currentTime))
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Button {
                    player.seek(to: max(0, player.currentTime - 10))
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title3)
                }
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38))
                }
                .buttonStyle(.plain)
                Button {
                    player.seek(to: min(player.duration, player.currentTime + 10))
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title3)
                }
                Spacer()
                Menu {
                    ForEach([Float(0.5), 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button("\(rate, specifier: "%.2g")×") { player.playbackRate = rate }
                    }
                } label: {
                    Text("\(player.playbackRate, specifier: "%.2g")×")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
                }
                Text(TimeFormatter.format(seconds: player.duration))
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }
}
