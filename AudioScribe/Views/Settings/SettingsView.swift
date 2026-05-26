import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var transcriptionService: TranscriptionService

    @State private var isPreloading = false
    @State private var preloadError: String?
    @State private var freeDiskMB: Int = -1
    @State private var showClearConfirm: Bool = false
    @State private var clearedNotice: String?

    var body: some View {
        Form {
            Section("Transcription model") {
                Picker("Default model", selection: $modelManager.selectedModelID) {
                    ForEach(WhisperModelOption.all) { option in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(option.displayName).font(.body.weight(.semibold))
                                if modelManager.downloadedModelIDs.contains(option.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .help("Already downloaded")
                                }
                            }
                            Text("≈\(option.approximateSizeMB) MB · \(option.qualityNote)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                preloadButton

                if let preloadError {
                    Text(preloadError).foregroundStyle(.red).font(.caption)
                }

                Text("Models are downloaded once and cached locally. Larger models are more accurate but slower and bigger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Language") {
                Picker("Preferred language", selection: $modelManager.preferredLanguage) {
                    ForEach(SupportedLanguage.allCases) { lang in
                        Text(lang.label).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Text("Auto-detect works well for most languages. Choosing a specific language can improve accuracy on short clips.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Free disk space",
                               value: freeDiskMB >= 0 ? "\(freeDiskMB) MB" : "—")
                LabeledContent("Models on disk",
                               value: "\(modelManager.downloadedModelIDs.count)")
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Clear all cached models", systemImage: "trash")
                }
                if let clearedNotice {
                    Text(clearedNotice)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Text("Use this if a model download was interrupted or the app fails to load a model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("App", value: "AudioScribe")
                LabeledContent("Version", value: Bundle.main.shortVersion)
                LabeledContent("Build", value: Bundle.main.buildNumber)
                Link("WhisperKit (open source)", destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                Text("All transcription is performed on-device. No audio leaves your Mac or iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task {
            await modelManager.refreshAvailableModels()
            freeDiskMB = TranscriptionService.availableDiskSpaceMB()
        }
        .confirmationDialog(
            "Clear all cached Whisper models?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will re-download the next time you transcribe.")
        }
    }

    @ViewBuilder
    private var preloadButton: some View {
        switch transcriptionService.loadState {
        case .downloading(let modelID, let fraction)
            where modelID == modelManager.selectedModelID:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloading \(modelManager.selectedOption.displayName)…")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: max(0.001, min(1.0, fraction)))
                Button(role: .destructive) {
                    transcriptionService.cancelInFlightLoad()
                    Task {
                        await modelManager.refreshAvailableModels()
                        freeDiskMB = TranscriptionService.availableDiskSpaceMB()
                    }
                } label: {
                    Label("Cancel download", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .loading(let modelID) where modelID == modelManager.selectedModelID:
            HStack { ProgressView().controlSize(.small); Text("Loading model into memory…") }
        default:
            Button {
                Task { await preload() }
            } label: {
                if isPreloading {
                    HStack { ProgressView().controlSize(.small); Text("Working…") }
                } else {
                    Label("Download / preload selected model", systemImage: "icloud.and.arrow.down")
                }
            }
            .disabled(isPreloading)
        }
    }

    private func preload() async {
        isPreloading = true
        preloadError = nil
        defer { isPreloading = false }
        do {
            try await transcriptionService.ensureLoaded(modelID: modelManager.selectedModelID)
            await modelManager.refreshAvailableModels()
            freeDiskMB = TranscriptionService.availableDiskSpaceMB()
        } catch {
            preloadError = error.localizedDescription
        }
    }

    private func clearAll() {
        transcriptionService.unloadCurrentModel()
        modelManager.clearAllCachedModels()
        Task {
            await modelManager.refreshAvailableModels()
            freeDiskMB = TranscriptionService.availableDiskSpaceMB()
            clearedNotice = "Cleared. \(freeDiskMB) MB free."
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            clearedNotice = nil
        }
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }
}
