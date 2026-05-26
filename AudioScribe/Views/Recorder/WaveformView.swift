import SwiftUI

struct WaveformView: View {
    var level: Float           // 0..1 current input
    var isActive: Bool

    @State private var bars: [CGFloat] = Array(repeating: 0.05, count: 40)
    @State private var tickTimer: Timer?

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 4) {
                ForEach(bars.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: max(2, (geo.size.width / CGFloat(bars.count)) - 4),
                               height: max(4, geo.size.height * bars[i]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 64)
        .onAppear { restartTimer() }
        .onDisappear {
            tickTimer?.invalidate()
            tickTimer = nil
        }
        .onChange(of: isActive) { _, newValue in
            if newValue { restartTimer() }
        }
    }

    private func restartTimer() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            advance()
        }
    }

    private func advance() {
        var next = bars
        next.removeFirst()
        let value: CGFloat
        if isActive {
            // Add jitter so the waveform feels alive even at constant volume
            let jitter = CGFloat.random(in: -0.08...0.08)
            value = max(0.05, min(1.0, CGFloat(level) + jitter))
        } else {
            value = 0.05
        }
        next.append(value)
        bars = next
    }
}

#Preview {
    WaveformView(level: 0.6, isActive: true)
        .padding()
}
