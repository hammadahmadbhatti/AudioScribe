import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var playbackRate: Float = 1.0 {
        didSet { applyRate() }
    }

    private var player: AVAudioPlayer?
    private var displayTimer: Timer?
    private var loadedURL: URL?

    func load(url: URL) throws {
        if loadedURL == url, player != nil { return }
        let p = try AVAudioPlayer(contentsOf: url)
        p.delegate = self
        p.enableRate = true
        p.prepareToPlay()
        self.player = p
        self.loadedURL = url
        self.duration = p.duration
        self.currentTime = 0
        applyRate()
    }

    func play() {
        guard let player else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, min(seconds, player.duration))
        player.currentTime = clamped
        self.currentTime = clamped
    }

    func stopAndReset() {
        player?.stop()
        player = nil
        loadedURL = nil
        duration = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func applyRate() {
        player?.rate = playbackRate
    }

    private func startTimer() {
        stopTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func refresh() {
        guard let player else { return }
        currentTime = player.currentTime
        if !player.isPlaying && isPlaying {
            isPlaying = false
            stopTimer()
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = player.duration
            self.stopTimer()
        }
    }
}
