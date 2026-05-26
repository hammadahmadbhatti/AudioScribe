import Foundation
import AVFoundation
import Combine
import WhisperKit

/// Live captions powered by **WhisperKit's `AudioStreamTranscriber`** — the
/// same Whisper model the app uses for the final saved transcript.
///
/// This replaces the previous Apple `SFSpeechRecognizer` implementation. Why:
///   * No 60-second per-task limit, so captions don't freeze on long recordings.
///   * Append-only by construction (`confirmedSegments` is internally append-only),
///     so prior text can never be erased by a recognizer reanchor.
///   * Same engine and quality as the post-recording Whisper transcript, with
///     full multilingual coverage including languages SFSpeech can't handle
///     on-device (e.g. Urdu, Polish).
///   * Built-in punctuation.
///
/// Tradeoff vs. SFSpeech:
///   * First-word latency is ~1–2 s instead of ~200–500 ms, because Whisper
///     needs to accumulate a buffer (~1 s of audio) before each inference pass.
///     The view shows the unconfirmed hypothesis as soon as it exists, so the
///     captions don't appear frozen — but words land in chunks, not letter-
///     by-letter.
///   * Continuous CPU/Neural-Engine load during recording. Use Tiny or Base
///     for snappiest live captions; Medium/Large will lag on older hardware.
///
/// Architecture:
///   * Borrows the loaded WhisperKit instance from `TranscriptionService`
///     (no second model load).
///   * Owns its audio capture via WhisperKit's own `AudioProcessor`. Runs
///     alongside `AudioRecorder`'s independent AVAudioEngine — both share
///     the same microphone; the OS arbitrates buffer delivery.
///   * `bufferConsumer()` is retained as a no-op closure for source-level
///     compatibility with the previous SFSpeech-based service. It does
///     nothing — the audio stream is captured internally, not fed in.
@MainActor
final class LiveTranscriptionService: ObservableObject {
    enum Status: Equatable {
        case idle
        case preparing(modelID: String)
        case listening(modelID: String)
        case stopped
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Text WhisperKit has confirmed. Append-only across the recording —
    /// `AudioStreamTranscriber.State.confirmedSegments` is itself append-only,
    /// and this property is rebuilt from that list, so promoted text can
    /// never be lost or rewritten.
    @Published private(set) var finalizedText: String = ""

    /// Whisper's current in-flight hypothesis: the unconfirmed trailing
    /// segments plus the decoder's current partial output. Replaced wholesale
    /// on each state update; promoted into `finalizedText` automatically as
    /// segments become confirmed.
    @Published private(set) var interimText: String = ""

    /// Confirmed phrases, one per stable segment. Useful for live translation,
    /// which should only translate stable text — translating an interim
    /// hypothesis wastes work and produces flicker.
    @Published private(set) var finalizedPhrases: [String] = []

    private var streamTranscriber: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var isStopping: Bool = false

    /// Microphone permission helper. Returns true when access is granted.
    /// Compatible-shaped wrapper for callers that previously asked
    /// `SFSpeechRecognizer` to authorize itself.
    func requestAuthorization() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    /// Source-compat no-op. The previous service consumed audio buffers fed
    /// in from `AudioRecorder` via this closure. WhisperKit captures its own
    /// audio internally, so the buffers it receives this way would just be
    /// discarded — returning an empty closure keeps the recorder's existing
    /// `onAudioBuffer = …` wiring valid without forcing a refactor.
    nonisolated func bufferConsumer() -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { _, _ in }
    }

    /// Start live captions. Loads the Whisper model if needed, then spins up
    /// a streaming transcription session.
    ///
    /// - Parameters:
    ///   - modelID: Whisper model variant ID (e.g. `"openai_whisper-base"`).
    ///     Must be one of `WhisperModelOption.all`.
    ///   - languageHint: BCP-47-ish language code Whisper understands
    ///     (`"en"`, `"de"`, …) or `nil` for auto-detect.
    ///   - transcriptionService: Owner of the loaded WhisperKit instance.
    func start(
        modelID: String,
        languageHint: String?,
        transcriptionService: TranscriptionService
    ) async {
        finalizedText = ""
        interimText = ""
        finalizedPhrases = []
        isStopping = false
        status = .preparing(modelID: modelID)

        do {
            try await transcriptionService.ensureLoaded(modelID: modelID)
        } catch {
            status = .failed("Couldn't load model for live captions: \(error.localizedDescription)")
            return
        }

        guard let whisperKit = transcriptionService.activeWhisperKit,
              let tokenizer = whisperKit.tokenizer
        else {
            status = .failed("Whisper model isn't available for live captions.")
            return
        }

        var options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: languageHint,
            temperature: 0,
            temperatureFallbackCount: 5,
            sampleLength: 224,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false
        )
        // Auto-detect only when no hint was supplied. Forcing detection on
        // every chunk wastes inference; pinning the language up front is
        // faster and more accurate when the user knows what they're speaking.
        options.detectLanguage = (languageHint == nil)

        let state = LiveCaptionStateAdapter(owner: self)
        let stream = AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisperKit.audioProcessor,
            decodingOptions: options,
            // Confirm segments aggressively so durable text catches up quickly.
            // Default is 2; lowering to 1 means a segment promotes as soon as
            // a newer one starts, which feels more like real-time captions.
            requiredSegmentsForConfirmation: 1,
            silenceThreshold: 0.3,
            useVAD: true,
            stateChangeCallback: { oldState, newState in
                state.deliver(oldState: oldState, newState: newState)
            }
        )
        self.streamTranscriber = stream

        // `startStreamTranscription` enters an internal loop that only returns
        // when `stopStreamTranscription` is called or audio fails. Run it on a
        // detached Task so the main actor isn't blocked.
        status = .listening(modelID: modelID)
        let runTask = Task { [weak self] in
            do {
                try await stream.startStreamTranscription()
            } catch {
                await MainActor.run {
                    self?.status = .failed("Live caption stream stopped: \(error.localizedDescription)")
                }
            }
        }
        self.streamTask = runTask
    }

    /// Stop live captions and tear down the stream. Pending in-flight Whisper
    /// inference is allowed to finish so the last segment lands in
    /// `finalizedText` before the status flips.
    func stop() {
        guard !isStopping else { return }
        isStopping = true
        Task {
            await streamTranscriber?.stopStreamTranscription()
            streamTask?.cancel()
            streamTask = nil
            streamTranscriber = nil
            // Promote whatever was in-flight into the durable transcript so
            // the user sees the last sentence even if it wasn't yet confirmed.
            await MainActor.run {
                if !interimText.isEmpty {
                    appendToFinalized(interimText)
                    interimText = ""
                }
                if case .listening = status {
                    status = .stopped
                }
            }
        }
    }

    func reset() {
        isStopping = true
        Task {
            await streamTranscriber?.stopStreamTranscription()
        }
        streamTask?.cancel()
        streamTask = nil
        streamTranscriber = nil
        finalizedText = ""
        interimText = ""
        finalizedPhrases = []
        status = .idle
    }

    // MARK: - State application

    /// Pure-ish helper that maps a Whisper stream state into our published
    /// fields. Split out for testability — accepts plain segment lists, no
    /// WhisperKit dependency in the test surface.
    struct StateUpdate: Equatable {
        var finalizedText: String
        var interimText: String
        var newlyPromotedPhrases: [String]
    }

    static func computeUpdate(
        previousConfirmedCount: Int,
        confirmedTexts: [String],
        unconfirmedTexts: [String],
        currentText: String
    ) -> StateUpdate {
        let confirmedTrimmed = confirmedTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let unconfirmedTrimmed = unconfirmedTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let currentTrimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        let finalized = confirmedTrimmed.joined(separator: " ")

        // The decoder reports `"Waiting for speech..."` while the buffer is
        // silent; don't surface that placeholder to the caption box.
        let displayCurrent = (currentTrimmed == "Waiting for speech...") ? "" : currentTrimmed

        // Avoid double-printing: if the unconfirmed segments already contain
        // what the decoder is currently emitting, don't append it again.
        var interim = unconfirmedTrimmed.joined(separator: " ")
        if !displayCurrent.isEmpty && !interim.contains(displayCurrent) {
            interim = interim.isEmpty ? displayCurrent : interim + " " + displayCurrent
        }

        let promoted: [String]
        if confirmedTrimmed.count > previousConfirmedCount {
            promoted = Array(confirmedTrimmed.dropFirst(previousConfirmedCount))
        } else {
            promoted = []
        }

        return StateUpdate(
            finalizedText: finalized,
            interimText: interim,
            newlyPromotedPhrases: promoted
        )
    }

    fileprivate func apply(oldState: AudioStreamTranscriber.State, newState: AudioStreamTranscriber.State) {
        guard !isStopping else { return }
        let update = LiveTranscriptionService.computeUpdate(
            previousConfirmedCount: oldState.confirmedSegments.count,
            confirmedTexts: newState.confirmedSegments.map { $0.text },
            unconfirmedTexts: newState.unconfirmedSegments.map { $0.text },
            currentText: newState.currentText
        )
        if update.finalizedText != finalizedText {
            finalizedText = update.finalizedText
        }
        if update.interimText != interimText {
            interimText = update.interimText
        }
        if !update.newlyPromotedPhrases.isEmpty {
            finalizedPhrases.append(contentsOf: update.newlyPromotedPhrases)
        }
    }

    private func appendToFinalized(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if finalizedText.isEmpty {
            finalizedText = trimmed
        } else {
            finalizedText += " " + trimmed
        }
        finalizedPhrases.append(trimmed)
    }
}

/// Bridge from the WhisperKit actor's callback (which can fire from any
/// executor) onto our `@MainActor` service. Held weakly so it doesn't
/// retain the service after a `reset()` if the stream is slow to wind down.
private final class LiveCaptionStateAdapter: @unchecked Sendable {
    private weak var owner: LiveTranscriptionService?

    init(owner: LiveTranscriptionService) {
        self.owner = owner
    }

    func deliver(oldState: AudioStreamTranscriber.State, newState: AudioStreamTranscriber.State) {
        Task { @MainActor [weak owner] in
            owner?.apply(oldState: oldState, newState: newState)
        }
    }
}

extension LiveTranscriptionService.Status {
    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }

    var userFacingMessage: String? {
        switch self {
        case .idle, .listening, .stopped: return nil
        case .preparing(let id):
            return "Loading Whisper \(WhisperModelOption.option(for: id)?.displayName ?? "model") for live captions…"
        case .failed(let m):
            return "Live caption error: \(m)"
        }
    }
}
