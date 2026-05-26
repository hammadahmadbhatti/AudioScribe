import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

struct RecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var transcriptionService: TranscriptionService
    @EnvironmentObject private var modelManager: ModelManager

    @StateObject private var recorder = AudioRecorder()
    @StateObject private var liveTranscription = LiveTranscriptionService()

    @State private var showImporter: Bool = false
    @State private var statusMessage: String = ""
    @State private var errorText: String?
    @State private var isProcessing: Bool = false
    @State private var lastSavedSession: TranscriptionSession?
    @State private var transcriptionMode: TranscriptionMode = .transcribe
    @State private var enableLiveCaptions: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                liveCaptureCard

                if enableLiveCaptions && (recorder.isRecording || liveTranscription.status.isListening || !liveTranscription.finalizedText.isEmpty || !liveTranscription.interimText.isEmpty) {
                    LiveCaptionView(
                        finalizedText: liveTranscription.finalizedText,
                        interimText: liveTranscription.interimText,
                        isListening: liveTranscription.status.isListening,
                        statusMessage: liveTranscription.status.userFacingMessage
                    )

                    if #available(iOS 18.0, macOS 15.0, *) {
                        LiveTranslationPanel(liveTranscription: liveTranscription)
                    }
                }

                if shouldShowProgressCard {
                    modelProgressCard
                }

                importCard

                if let lastSavedSession {
                    NavigationLink(value: lastSavedSession) {
                        EmptyView()
                    }
                    .hidden()

                    successCard(for: lastSavedSession)
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Record")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: AudioFileImporter.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .failure(let error):
                errorText = "Import failed: \(error.localizedDescription)"
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importAndTranscribe(from: url) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capture")
                .font(.largeTitle.bold())
            Text("Record live audio or import a file. Transcription runs entirely on this device.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var liveCaptureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Live recording")
                    .font(.headline)
                Spacer()
                Text(TimeFormatter.format(seconds: recorder.elapsedSeconds))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(recorder.isRecording ? .red : .primary)
            }

            WaveformView(level: recorder.meterLevel, isActive: recorder.isRecording)

            HStack(spacing: 12) {
                Button(action: toggleRecord) {
                    Label(recorder.isRecording ? "Stop & Transcribe" : "Start Recording",
                          systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .accentColor)
                .disabled(isProcessing)

                if recorder.isRecording {
                    Button(role: .destructive) {
                        liveTranscription.stop()
                        liveTranscription.reset()
                        recorder.onAudioBuffer = nil
                        recorder.cancel()
                        statusMessage = "Recording discarded."
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if isProcessing {
                    ProgressView().controlSize(.small)
                    Text(statusMessage.isEmpty ? "Working…" : statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Label("Model: \(modelManager.selectedOption.displayName)", systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Language: \(SupportedLanguage(rawValue: modelManager.preferredLanguage)?.label ?? "Auto-detect")",
                      systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Mode", selection: $transcriptionMode) {
                ForEach(TranscriptionMode.allCases) { mode in
                    Text(mode.displayLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(recorder.isRecording || isProcessing)

            if transcriptionMode == .translateToEnglish {
                Text("Whisper will output English regardless of the spoken language. Same speed, no extra download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $enableLiveCaptions) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live captions while recording")
                        .font(.callout.weight(.medium))
                    Text("Apple Speech, on-device only. Whisper still produces the final transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(recorder.isRecording || isProcessing)
        }
        .cardStyle()
    }

    private var shouldShowProgressCard: Bool {
        switch transcriptionService.loadState {
        case .downloading, .loading:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var modelProgressCard: some View {
        switch transcriptionService.loadState {
        case .downloading(let modelID, let fraction):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "icloud.and.arrow.down.fill")
                    Text("Downloading model")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .font(.system(.body, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: max(0.001, min(1.0, fraction)))
                    .progressViewStyle(.linear)
                Text(label(for: modelID) + " · downloads once, then runs offline forever.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()

        case .loading(let modelID):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Loading \(label(for: modelID)) into memory…")
                        .font(.headline)
                    Text("Compiling Core ML model. This is fastest the second time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

        default:
            EmptyView()
        }
    }

    private func label(for modelID: String) -> String {
        WhisperModelOption.option(for: modelID)?.displayName ?? modelID
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import audio")
                .font(.headline)
            Text("Choose a WAV, MP3, M4A, AIFF, or CAF file. The file is copied locally; nothing is uploaded.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                showImporter = true
            } label: {
                Label("Choose audio file…", systemImage: "tray.and.arrow.down.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing || recorder.isRecording)
        }
        .cardStyle()
    }

    private func successCard(for session: TranscriptionSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Saved to Library")
                    .font(.headline)
            }
            Text(session.title)
                .font(.body.weight(.semibold))
            if !session.fullTranscript.isEmpty {
                Text(session.fullTranscript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack {
                Label(session.formattedDuration, systemImage: "clock")
                if let lang = session.detectedLanguage {
                    Label(lang.uppercased(), systemImage: "globe")
                }
                Label(session.modelUsed.replacingOccurrences(of: "openai_whisper-", with: ""),
                      systemImage: "cpu")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func toggleRecord() {
        errorText = nil
        if recorder.isRecording {
            Task { await stopAndTranscribe() }
        } else {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        do {
            statusMessage = "Recording…"
            // The WhisperKit-backed caption service captures its own audio
            // stream internally; we don't fan recorder buffers into it.
            // `bufferConsumer()` is intentionally a no-op for source-level
            // compatibility — leave it wired so future swaps don't surprise.
            if enableLiveCaptions {
                liveTranscription.reset()
                recorder.onAudioBuffer = liveTranscription.bufferConsumer()
            } else {
                recorder.onAudioBuffer = nil
            }
            _ = try await recorder.start()
            if enableLiveCaptions {
                let hint = SupportedLanguage(rawValue: modelManager.preferredLanguage)?.whisperCode
                await liveTranscription.start(
                    modelID: modelManager.selectedModelID,
                    languageHint: hint,
                    transcriptionService: transcriptionService
                )
            }
        } catch {
            errorText = error.localizedDescription
            liveTranscription.stop()
        }
    }

    private func stopAndTranscribe() async {
        do {
            isProcessing = true
            defer { isProcessing = false }
            statusMessage = "Saving audio…"
            // Stop the live recognizer first so its delegate callbacks settle.
            liveTranscription.stop()
            recorder.onAudioBuffer = nil
            let url = try recorder.stop()
            let duration = recorder.elapsedSeconds
            statusMessage = "Loading model \(modelManager.selectedOption.displayName)…"
            try await transcriptionService.ensureLoaded(modelID: modelManager.selectedModelID)
            statusMessage = "Transcribing…"
            let lang = SupportedLanguage(rawValue: modelManager.preferredLanguage)?.whisperCode
            let payload = try await transcriptionService.transcribe(
                audioURL: url,
                modelID: modelManager.selectedModelID,
                languageHint: lang,
                mode: transcriptionMode
            )
            let title = "Recording \(Self.dateFormatter.string(from: Date()))"
            let session = try SessionStore.save(
                context: modelContext,
                title: title,
                audioURL: url,
                duration: duration,
                result: payload
            )
            self.lastSavedSession = session
            statusMessage = "Done."
        } catch {
            errorText = error.localizedDescription
            statusMessage = ""
        }
    }

    private func importAndTranscribe(from sourceURL: URL) async {
        do {
            isProcessing = true
            defer { isProcessing = false }
            statusMessage = "Copying file…"
            let copied = try AudioFileImporter.importFile(at: sourceURL)
            statusMessage = "Loading model \(modelManager.selectedOption.displayName)…"
            try await transcriptionService.ensureLoaded(modelID: modelManager.selectedModelID)
            statusMessage = "Transcribing…"
            let lang = SupportedLanguage(rawValue: modelManager.preferredLanguage)?.whisperCode
            let payload = try await transcriptionService.transcribe(
                audioURL: copied,
                modelID: modelManager.selectedModelID,
                languageHint: lang
            )
            let title = sourceURL.deletingPathExtension().lastPathComponent
            let duration = (try? AVAudioFileDuration.load(url: copied)) ?? 0
            let session = try SessionStore.save(
                context: modelContext,
                title: title,
                audioURL: copied,
                duration: duration,
                result: payload
            )
            self.lastSavedSession = session
            statusMessage = "Done."
        } catch {
            errorText = error.localizedDescription
            statusMessage = ""
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

enum AVAudioFileDuration {
    static func load(url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return Double(file.length) / sampleRate
    }
}
