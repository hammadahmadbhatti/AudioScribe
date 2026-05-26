import SwiftUI
import SwiftData

#if canImport(Translation)
import Translation
#endif

/// Panel rendered inside `TranscriptView`. Lets the user translate the
/// transcript into another language using Apple's free on-device
/// Translation framework. The result is persisted on the session.
struct TranslationPanel: View {
    @Bindable var session: TranscriptionSession
    @Environment(\.modelContext) private var modelContext

    @State private var targetCode: String = "en"
    @State private var isWorking: Bool = false
    @State private var errorText: String?
    @State private var pendingInput: String?
    @State private var showOriginal: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Translate")
                    .font(.headline)
                Spacer()
                if !isAppleTranslationAvailable() {
                    Text("Requires iOS 18.0+ / macOS 15.0+")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Picker("To", selection: $targetCode) {
                    ForEach(TranslationLanguageOption.presets) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!canTranslate || isWorking)

                Button {
                    startTranslation()
                } label: {
                    if isWorking {
                        HStack { ProgressView().controlSize(.small); Text("Translating…") }
                    } else {
                        Label("Translate", systemImage: "character.bubble")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canTranslate || isWorking || session.fullTranscript.isEmpty)

                if session.translatedText != nil {
                    Button(role: .destructive) {
                        clearTranslation()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if let translated = session.translatedText, !translated.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Translated · \(labelFor(code: session.translatedLanguage ?? targetCode))",
                              systemImage: "globe")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(showOriginal ? "Show translation" : "Show original") {
                            showOriginal.toggle()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    Text(showOriginal ? session.fullTranscript : translated)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            translationDriverView
        }
        .cardStyle()
    }

    private var canTranslate: Bool {
        isAppleTranslationAvailable() && !session.fullTranscript.isEmpty
    }

    private func startTranslation() {
        errorText = nil
        guard !session.fullTranscript.isEmpty else {
            errorText = TextTranslationError.emptyInput.localizedDescription
            return
        }
        guard isAppleTranslationAvailable() else {
            errorText = TextTranslationError.unavailable.localizedDescription
            return
        }
        isWorking = true
        pendingInput = session.fullTranscript
    }

    private func clearTranslation() {
        session.translatedText = nil
        session.translatedLanguage = nil
        showOriginal = false
        try? modelContext.save()
    }

    private func labelFor(code: String) -> String {
        TranslationLanguageOption.presets.first(where: { $0.code == code })?.label ?? code.uppercased()
    }

    /// Apple's `Translation` framework attaches translation work to a view via
    /// `.translationTask`. We render a tiny invisible view that owns the task.
    @ViewBuilder
    private var translationDriverView: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            TranslationDriver(
                pendingInput: $pendingInput,
                targetCode: targetCode,
                onResult: { translated in
                    session.translatedText = translated
                    session.translatedLanguage = targetCode
                    try? modelContext.save()
                    isWorking = false
                    showOriginal = false
                },
                onFailure: { message in
                    errorText = message
                    isWorking = false
                }
            )
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        } else {
            EmptyView()
        }
    }
}

#if canImport(Translation)
@available(iOS 18.0, macOS 15.0, *)
private struct TranslationDriver: View {
    @Binding var pendingInput: String?
    let targetCode: String
    let onResult: (String) -> Void
    let onFailure: (String) -> Void

    @State private var sourceLanguage: Locale.Language? = nil
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .translationTask(configuration) { session in
                guard let input = pendingInput, !input.isEmpty else { return }
                do {
                    let response = try await session.translate(input)
                    await MainActor.run {
                        pendingInput = nil
                        onResult(response.targetText)
                    }
                } catch {
                    await MainActor.run {
                        pendingInput = nil
                        onFailure(error.localizedDescription)
                    }
                }
            }
            .onChange(of: pendingInput) { _, newValue in
                guard newValue != nil else { return }
                // Setting/replacing the configuration is what kicks off the translationTask.
                configuration = TranslationSession.Configuration(
                    source: nil,
                    target: Locale.Language(identifier: targetCode)
                )
            }
    }
}
#endif
