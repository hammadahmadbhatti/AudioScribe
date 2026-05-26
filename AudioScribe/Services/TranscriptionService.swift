import Foundation
import Combine
import WhisperKit

struct TranscribedSegment: Identifiable, Equatable {
    let id: Int
    let startSeconds: Double
    let endSeconds: Double
    let text: String
}

struct TranscriptionResultPayload: Equatable {
    let fullText: String
    let detectedLanguage: String?
    let segments: [TranscribedSegment]
    let modelID: String
    /// True when produced via Whisper's translate task (foreign speech → English text).
    let wasTranslated: Bool
}

/// What to ask Whisper to do with the audio.
/// `.transcribe` returns text in the spoken language.
/// `.translateToEnglish` returns English regardless of spoken language — costs the same single inference pass.
enum TranscriptionMode: String, CaseIterable, Identifiable {
    case transcribe
    case translateToEnglish

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .transcribe: return "Transcribe (original language)"
        case .translateToEnglish: return "Translate to English"
        }
    }
}

@MainActor
final class TranscriptionService: ObservableObject {
    enum ServiceError: LocalizedError {
        case modelNotLoaded
        case transcriptionFailed(String)
        case fileNotFound(URL)
        case downloadFailed(String)
        case loadFailed(String)
        case insufficientDiskSpace(requiredMB: Int, availableMB: Int)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "The transcription model has not finished loading."
            case .transcriptionFailed(let m):
                return "Transcription failed: \(m)"
            case .fileNotFound(let url):
                return "Audio file not found at \(url.path)."
            case .downloadFailed(let m):
                return "Model download failed: \(m)"
            case .loadFailed(let m):
                return "Could not load model: \(m)"
            case .insufficientDiskSpace(let r, let a):
                return "Not enough free disk space. This model needs about \(r) MB; only \(a) MB available. Free up space and try again."
            }
        }
    }

    enum LoadState: Equatable {
        case idle
        case downloading(modelID: String, fractionCompleted: Double)
        case loading(modelID: String)
        case ready(modelID: String)
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isTranscribing: Bool = false

    private var whisperKit: WhisperKit?
    private var loadedModelID: String?

    /// Tracks the in-flight load so concurrent callers (e.g. Settings preload
    /// + recording auto-load) coalesce onto one download instead of racing
    /// two simultaneous downloads of the same large model into the sandbox.
    private var inFlightLoad: (modelID: String, task: Task<Void, Error>)?

    var activeModelID: String? { loadedModelID }

    /// The currently-loaded WhisperKit instance, or nil. Exposed so the live
    /// caption service can build an `AudioStreamTranscriber` from the same
    /// loaded model components without paying for a second model load.
    var activeWhisperKit: WhisperKit? { whisperKit }

    /// Downloads the model (if needed) and loads it into memory.
    /// Surfaces download progress through `loadState`. Concurrent calls for the
    /// same model await the existing in-flight task instead of starting a new one.
    func ensureLoaded(modelID: String) async throws {
        if let loadedModelID, loadedModelID == modelID, whisperKit != nil {
            return
        }
        if let inFlight = inFlightLoad {
            if inFlight.modelID == modelID {
                try await inFlight.task.value
                return
            }
            // Different model requested mid-flight (e.g. user switched the
            // picker). Cancel the previous load instead of letting two large
            // downloads race for the same sandbox.
            inFlight.task.cancel()
        }
        let task = Task { try await performLoad(modelID: modelID) }
        inFlightLoad = (modelID, task)
        defer {
            if inFlightLoad?.modelID == modelID { inFlightLoad = nil }
        }
        try await task.value
    }

    private func performLoad(modelID: String) async throws {
        let modelFolder = ModelManager.modelsFolderURL.appendingPathComponent(modelID)
        let folderExists = FileManager.default.fileExists(atPath: modelFolder.path)
        // A folder can exist from an earlier failed/cancelled download but be
        // missing the actual `.mlmodelc` bundles. Treat that as "not on disk"
        // so we re-download instead of failing forever with a confusing error.
        let alreadyOnDisk = folderExists && ModelManager.isModelComplete(at: modelFolder)
        if folderExists && !alreadyOnDisk {
            // Wipe the half-baked folder before retrying — otherwise the next
            // download appends into a dirty state and disk usage balloons.
            try? FileManager.default.removeItem(at: modelFolder)
        }

        if !alreadyOnDisk, let option = WhisperModelOption.option(for: modelID) {
            let availableMB = Self.availableDiskSpaceMB()
            // `diskRequiredMB` accounts for the unpacked Core ML bundle plus
            // download/compile headroom. The previous `size * 2` estimate
            // routinely under-counted by ~2× for the medium and large variants.
            let requiredMB = option.diskRequiredMB
            if availableMB > 0 && availableMB < requiredMB {
                throw ServiceError.insufficientDiskSpace(requiredMB: requiredMB, availableMB: availableMB)
            }
        }

        whisperKit = nil
        loadedModelID = nil

        let folderURL: URL
        if alreadyOnDisk {
            folderURL = modelFolder
        } else {
            loadState = .downloading(modelID: modelID, fractionCompleted: 0)
            do {
                folderURL = try await WhisperKit.download(
                    variant: modelID,
                    downloadBase: ModelManager.downloadBaseURL,
                    useBackgroundSession: false,
                    progressCallback: { [weak self] progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in
                            self?.loadState = .downloading(modelID: modelID, fractionCompleted: fraction)
                        }
                    }
                )
            } catch {
                // Network drop, cancellation, or disk-full mid-download leaves
                // partial files behind. Clean them up so the next attempt
                // starts fresh and doesn't double-bill disk space.
                try? FileManager.default.removeItem(at: modelFolder)
                loadState = .failed(error.localizedDescription)
                throw ServiceError.downloadFailed(error.localizedDescription)
            }
        }

        loadState = .loading(modelID: modelID)
        do {
            let config = WhisperKitConfig(
                model: modelID,
                downloadBase: ModelManager.downloadBaseURL,
                modelFolder: folderURL.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            self.loadedModelID = modelID
            self.loadState = .ready(modelID: modelID)
        } catch {
            // A load failure on a "complete-looking" folder usually means the
            // Core ML bundles are corrupt (truncated download, OS update broke
            // compilation cache, etc). Wipe so the user can retry from clean.
            try? FileManager.default.removeItem(at: modelFolder)
            loadState = .failed(error.localizedDescription)
            throw ServiceError.loadFailed(error.localizedDescription)
        }
    }

    /// Cancel any in-flight download/load. Safe to call when nothing is loading.
    func cancelInFlightLoad() {
        inFlightLoad?.task.cancel()
        inFlightLoad = nil
        if case .downloading = loadState {
            loadState = .idle
        }
    }

    func transcribe(
        audioURL: URL,
        modelID: String,
        languageHint: String? = nil,
        mode: TranscriptionMode = .transcribe
    ) async throws -> TranscriptionResultPayload {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ServiceError.fileNotFound(audioURL)
        }
        try await ensureLoaded(modelID: modelID)
        guard let whisperKit else { throw ServiceError.modelNotLoaded }

        isTranscribing = true
        defer { isTranscribing = false }

        let decodingOptions = TranscriptionService.makeDecodingOptions(
            mode: mode,
            languageHint: languageHint
        )

        do {
            let results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: decodingOptions
            )
            return TranscriptionService.merge(
                results: results,
                modelID: modelID,
                wasTranslated: mode == .translateToEnglish
            )
        } catch {
            throw ServiceError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Builds a `DecodingOptions` for the chosen mode. Pulled out for testability.
    static func makeDecodingOptions(
        mode: TranscriptionMode,
        languageHint: String?
    ) -> DecodingOptions {
        var options = DecodingOptions(
            verbose: false,
            task: mode == .translateToEnglish ? .translate : .transcribe,
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
        // Auto-detect source when no hint is supplied. Whisper's translate task
        // always emits English regardless of source, so detection is still useful.
        options.detectLanguage = (languageHint == nil)
        return options
    }

    func unloadCurrentModel() {
        whisperKit = nil
        loadedModelID = nil
        loadState = .idle
    }

    static func merge(
        results: [TranscriptionResult],
        modelID: String,
        wasTranslated: Bool = false
    ) -> TranscriptionResultPayload {
        var segments: [TranscribedSegment] = []
        var fullText = ""
        var detectedLanguage: String?
        var idCounter = 0

        for result in results {
            if detectedLanguage == nil { detectedLanguage = result.language }
            for s in result.segments {
                segments.append(
                    TranscribedSegment(
                        id: idCounter,
                        startSeconds: Double(s.start),
                        endSeconds: Double(s.end),
                        text: s.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                idCounter += 1
            }
            if !fullText.isEmpty { fullText += " " }
            fullText += result.text
        }

        return TranscriptionResultPayload(
            fullText: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedLanguage: detectedLanguage,
            segments: segments,
            modelID: modelID,
            wasTranslated: wasTranslated
        )
    }

    static func availableDiskSpaceMB() -> Int {
        let fm = FileManager.default
        guard let path = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path else {
            return -1
        }
        guard let attrs = try? fm.attributesOfFileSystem(forPath: path),
              let bytes = attrs[.systemFreeSize] as? NSNumber else {
            return -1
        }
        return Int(bytes.int64Value / (1024 * 1024))
    }
}
