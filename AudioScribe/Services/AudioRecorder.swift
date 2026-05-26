import Foundation
import AVFoundation
import Combine

#if os(iOS)
import UIKit
#endif

/// Captures microphone audio with `AVAudioEngine`, writes a 16 kHz mono WAV to disk,
/// publishes meter level + elapsed seconds, and fans the same buffers out to a
/// `onAudioBuffer` closure so a live transcription service can consume them.
///
/// Single mic source, three consumers:
///   1. AVAudioFile on disk → Whisper batch transcription path
///   2. RMS meter → waveform UI
///   3. `onAudioBuffer` callback → SFSpeechRecognizer live captions
@MainActor
final class AudioRecorder: ObservableObject {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case sessionConfigFailed(String)
        case recorderInitFailed(String)
        case notRecording

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission was denied. Enable it in Settings."
            case .sessionConfigFailed(let m):
                return "Audio session error: \(m)"
            case .recorderInitFailed(let m):
                return "Could not start recorder: \(m)"
            case .notRecording:
                return "No active recording."
            }
        }
    }

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var meterLevel: Float = 0  // 0.0 – 1.0 normalized

    /// Set BEFORE `start()` to receive captured PCM buffers from the audio thread.
    /// The closure runs off the main actor; do NOT touch SwiftUI state inside it.
    /// Used by `LiveTranscriptionService` to drive live captions.
    nonisolated(unsafe) var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    private let engine = AVAudioEngine()
    private nonisolated(unsafe) var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var startedAt: Date?
    private var meterTimer: Timer?

    /// Serial queue that drains disk writes off the realtime audio thread.
    /// Writing the WAV file synchronously inside the tap callback meant any
    /// filesystem hiccup (APFS flush, encryption, background indexing) would
    /// stall the audio thread — which in turn made live captions look stuck
    /// because SFSpeech started receiving audio in bursts. Disk writes are now
    /// dispatched here and the audio thread returns immediately.
    private let diskWriteQueue = DispatchQueue(
        label: "com.hammadahmad.audioscribe.diskwrite",
        qos: .userInitiated
    )

    func requestPermission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    func start() async throws -> URL {
        let granted = await requestPermission()
        guard granted else { throw RecorderError.permissionDenied }

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // .allowBluetoothHFP is the iOS 18+ replacement for the deprecated
            // .allowBluetooth. On iOS 17 we drop Bluetooth and use the built-in mic
            // — recording still works, just without HFP headsets. Warning-clean.
            var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
            if #available(iOS 18.0, *) {
                options.insert(.allowBluetoothHFP)
            }
            try session.setCategory(.playAndRecord, mode: .measurement, options: options)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw RecorderError.sessionConfigFailed(error.localizedDescription)
        }
        #endif

        let url = AudioStorage.newAudioFileURL(extension: "wav")
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Disk format: 16 kHz mono Int16 WAV — what Whisper expects, written
        // verbatim into the file header via `settings:`. AVAudioFile takes
        // care of encoding from its in-memory `processingFormat` down to this
        // on-disk representation. AVAudioFile does NOT resample sample rates,
        // so we still have to resample input → 16 kHz ourselves.
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: fileSettings)
        } catch {
            throw RecorderError.recorderInitFailed("AVAudioFile init failed: \(error.localizedDescription)")
        }
        self.audioFile = file
        self.currentURL = url

        // `processingFormat` is the format AVAudioFile.write(from:) actually
        // requires — by default a Float32 deinterleaved version of the file
        // format, regardless of what's in `settings:`. Handing it an Int16
        // buffer trips `CAAssertRtn` inside CoreAudio and crashes the realtime
        // audio thread with EXC_BREAKPOINT. So we convert TO this format.
        let processingFormat = file.processingFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: processingFormat) else {
            throw RecorderError.recorderInitFailed("Could not build AVAudioConverter for \(inputFormat) → \(processingFormat).")
        }

        // Snapshot the live-caption hook at start time. Setting `onAudioBuffer`
        // after start() takes effect on the next session.
        let bufferCallback = self.onAudioBuffer

        // Capture the file directly into the write closure (not via self.audioFile)
        // so the disk queue doesn't race with stop() niling the property. The
        // queue holds the file alive until the last write drains.
        let writeFile: @Sendable (AVAudioPCMBuffer) -> Void = { [diskWriteQueue, file] buffer in
            diskWriteQueue.async {
                try? file.write(from: buffer)
            }
        }
        let publishMeter: @Sendable (Float) -> Void = { [weak self] level in
            Task { @MainActor in
                self?.meterLevel = level
            }
        }

        let resampleRatio = processingFormat.sampleRate / inputFormat.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, time in
            // Convert input buffer → AVAudioFile's processing format for write.
            // Add a small headroom on the output capacity for the resampler tail.
            let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * resampleRatio + 1024)
            guard let converted = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: outCapacity) else {
                return
            }
            // AVAudioConverterInputBlock is called repeatedly until it returns
            // `.noDataNow` or `.endOfStream`. We supply the buffer exactly once
            // per tap invocation. Storing the "consumed" flag inside a class instance
            // avoids the Swift 6 captured-var-in-Sendable-closure warning.
            let pending = AudioRecorder.InputBufferGate(buffer: buffer)
            var convertError: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if let next = pending.takeBuffer() {
                    outStatus.pointee = .haveData
                    return next
                }
                outStatus.pointee = .noDataNow
                return nil
            }
            let status = converter.convert(to: converted, error: &convertError, withInputFrom: inputBlock)
            if convertError == nil && (status == .haveData || status == .inputRanDry) && converted.frameLength > 0 {
                writeFile(converted)
            }

            // Live caption + meter use the original native-format buffer:
            // SFSpeech accepts any PCM format and resamples internally.
            publishMeter(AudioRecorder.computeMeterLevel(from: buffer))
            bufferCallback?(buffer, time)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioFile = nil
            self.currentURL = nil
            throw RecorderError.recorderInitFailed("AVAudioEngine start failed: \(error.localizedDescription)")
        }

        self.startedAt = Date()
        self.isRecording = true
        self.elapsedSeconds = 0
        startMeterTimer()
        return url
    }

    @discardableResult
    func stop() throws -> URL {
        guard isRecording, let url = currentURL else {
            throw RecorderError.notRecording
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Drain any disk writes the tap callback dispatched but the queue
        // hasn't run yet. Without this, the returned URL may point at a WAV
        // that's missing its last fragment, and Whisper will transcribe a
        // truncated recording.
        diskWriteQueue.sync {}
        // Force AVAudioFile to flush by releasing it.
        audioFile = nil

        stopMeterTimer()
        isRecording = false
        meterLevel = 0

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        self.currentURL = nil
        self.startedAt = nil
        return url
    }

    func cancel() {
        let url = currentURL
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        // Drain pending writes so the file isn't being touched when we delete it.
        diskWriteQueue.sync {}
        audioFile = nil
        stopMeterTimer()
        isRecording = false
        meterLevel = 0

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        currentURL = nil
        startedAt = nil
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Meter

    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickElapsed()
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tickElapsed() {
        guard let startedAt else { return }
        elapsedSeconds = Date().timeIntervalSince(startedAt)
    }

    /// Holds a single PCM buffer pending consumption by `AVAudioConverterInputBlock`.
    /// Wrapping in a class instance lets the input-block closure remain Sendable
    /// while still mutating "have we delivered the buffer yet?" state.
    fileprivate final class InputBufferGate {
        private var buffer: AVAudioPCMBuffer?
        init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        func takeBuffer() -> AVAudioPCMBuffer? {
            let b = buffer
            buffer = nil
            return b
        }
    }

    /// Compute a normalized 0…1 meter level from a PCM buffer.
    /// Uses RMS in dB mapped from the [-60, 0] dB range.
    nonisolated static func computeMeterLevel(from buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sumSquares: Float = 0
        if let floatChannels = buffer.floatChannelData {
            let channel = floatChannels[0]
            for i in 0..<frames {
                let sample = channel[i]
                sumSquares += sample * sample
            }
        } else if let int16Channels = buffer.int16ChannelData {
            let channel = int16Channels[0]
            for i in 0..<frames {
                let sample = Float(channel[i]) / Float(Int16.max)
                sumSquares += sample * sample
            }
        } else {
            return 0
        }

        let rms = sqrt(sumSquares / Float(frames))
        let dB = 20 * log10(max(rms, 1e-7))
        let clamped = max(-60, min(0, dB))
        return (clamped + 60) / 60
    }
}
