import SwiftUI

#if canImport(Translation)
import Translation
#endif

/// Live translation panel that mirrors the live caption transcript — including
/// its append-only behaviour.
///
/// The previous implementation translated the entire cumulative transcript on a
/// debounce and replaced the displayed translation each tick. On long
/// recordings that meant re-translating the same prefix repeatedly (slow), and
/// the displayed translation would visibly lag behind the caption.
///
/// New strategy:
/// - Observe the caption service directly (reference semantics) so a
///   long-running translation loop sees live updates instead of a value
///   captured at view-build time.
/// - Translate each `finalizedPhrases[i]` exactly once, append the result into
///   `translatedConfirmed`, and never re-touch it. The confirmed translation
///   grows alongside the caption.
/// - Re-translate only the `interimText` hypothesis on changes (debounced),
///   replacing the trailing translated-interim. When a phrase graduates from
///   interim to confirmed in the caption, its translation also gets promoted
///   here — the displayed output stays consistent.
///
/// Requires iOS 18.0+ / macOS 15.0+ for `TranslationSession`.
@available(iOS 18.0, macOS 15.0, *)
struct LiveTranslationPanel: View {
    /// Observed so reading `finalizedPhrases` / `interimText` from inside the
    /// long-running `translationTask` closure always sees the current values.
    /// A by-value `let finalizedPhrases: [String]` parameter would be frozen at
    /// the time the task captured `self`.
    @ObservedObject var liveTranscription: LiveTranscriptionService

    @State private var targetCode: String = "es"

    /// Translations of confirmed caption segments, one entry per phrase, in
    /// the same order as `liveTranscription.finalizedPhrases`. Append-only
    /// for the duration of one recording: once a phrase is translated it is
    /// never re-translated, and never replaced by a later pass.
    @State private var translatedConfirmed: [String] = []

    /// Translation of the current interim caption hypothesis. Replaced on each
    /// debounced update; cleared when the caption interim is empty.
    @State private var translatedInterim: String = ""

    /// Snapshot of the interim source text we most recently asked the
    /// translator to render. Used to skip work when nothing has actually
    /// changed between two polling ticks.
    @State private var lastTranslatedInterimSource: String = ""

    @State private var configuration: TranslationSession.Configuration?
    @State private var errorText: String?
    @State private var isTranslating: Bool = false

    private var displayText: String {
        let confirmed = translatedConfirmed.joined(separator: " ")
        let interim = translatedInterim.trimmingCharacters(in: .whitespacesAndNewlines)
        if interim.isEmpty { return confirmed }
        if confirmed.isEmpty { return interim }
        return confirmed + " " + interim
    }

    private var isListening: Bool {
        liveTranscription.status.isListening
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "character.bubble")
                    .foregroundStyle(.tint)
                Text("Live translation")
                    .font(.headline)
                if isTranslating {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                Picker("To", selection: $targetCode) {
                    ForEach(TranslationLanguageOption.presets) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: targetCode) { _, _ in
                    // Switching target language invalidates everything we've
                    // translated so far. Wipe and rebuild the session.
                    translatedConfirmed = []
                    translatedInterim = ""
                    lastTranslatedInterimSource = ""
                    errorText = nil
                    rebuildConfiguration()
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            translationDisplay
        }
        .cardStyle()
        .translationTask(configuration) { session in
            await runIncrementalTranslation(session: session)
        }
        .onAppear {
            if configuration == nil { rebuildConfiguration() }
        }
    }

    @ViewBuilder
    private var translationDisplay: some View {
        if displayText.isEmpty {
            Text(isListening
                 ? "Translation appears here as each sentence is confirmed by Whisper."
                 : "Start recording with live captions on to see live translation.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .id("LiveTranslationPanel.bottom")
                }
                .frame(minHeight: 80, maxHeight: 200)
                .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: displayText) { _, _ in
                    proxy.scrollTo("LiveTranslationPanel.bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Translation pipeline

    /// Long-running translation loop. Stays alive for the lifetime of one
    /// `TranslationSession.Configuration` (i.e. until the target language
    /// changes). Polls the live caption state every 250 ms; that's well below
    /// Whisper's per-segment cadence so confirmed phrases are picked up
    /// promptly without burning the CPU on tight spins.
    private func runIncrementalTranslation(session: TranslationSession) async {
        while !Task.isCancelled {
            await translatePendingConfirmedPhrases(session: session)
            await translateInterimIfChanged(session: session)
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Translate every `finalizedPhrases` entry beyond the ones we've already
    /// translated, in order, appending each result to `translatedConfirmed`.
    /// Append-only: once a phrase is in `translatedConfirmed` it stays there.
    private func translatePendingConfirmedPhrases(session: TranslationSession) async {
        let liveSnapshot = liveTranscription.finalizedPhrases
        while translatedConfirmed.count < liveSnapshot.count {
            guard !Task.isCancelled else { return }
            let index = translatedConfirmed.count
            // Re-snapshot in case more phrases were appended while we were
            // awaiting the previous translate(). Reading the live array via
            // the @ObservedObject is safe and current.
            let currentLive = liveTranscription.finalizedPhrases
            guard index < currentLive.count else { return }
            let phrase = currentLive[index]
            isTranslating = true
            do {
                let response = try await session.translate(phrase)
                // Defensive: a `targetCode` change could have wiped the array
                // while we were awaiting. Only append if the index is still
                // the expected next slot.
                if translatedConfirmed.count == index {
                    translatedConfirmed.append(response.targetText)
                }
                errorText = nil
            } catch {
                isTranslating = false
                let nsErr = error as NSError
                errorText = "Translation failed (\(nsErr.code)): \(error.localizedDescription). Try a different target language or check Settings → Translate."
                return
            }
        }
        isTranslating = false
    }

    /// Translate the current interim hypothesis if it has changed since the
    /// last pass. Interim translations are best-effort and replace each other
    /// — they exist for visual feedback only. Once a phrase becomes confirmed
    /// upstream, it appears in `finalizedPhrases` and gets re-translated by
    /// `translatePendingConfirmedPhrases` for the durable record.
    private func translateInterimIfChanged(session: TranslationSession) async {
        let interim = liveTranscription.interimText.trimmingCharacters(in: .whitespacesAndNewlines)
        if interim.isEmpty {
            if !translatedInterim.isEmpty { translatedInterim = "" }
            lastTranslatedInterimSource = ""
            return
        }
        guard interim != lastTranslatedInterimSource else { return }
        lastTranslatedInterimSource = interim
        do {
            let response = try await session.translate(interim)
            // If the interim was promoted to confirmed while we were awaiting,
            // skip the update — the confirmed path will produce the canonical
            // translation. Cheap check: source mismatch ⇒ stale.
            if liveTranscription.interimText.trimmingCharacters(in: .whitespacesAndNewlines) == interim {
                translatedInterim = response.targetText
            }
        } catch {
            // Best-effort: don't surface interim failures to the user. The
            // next pass will retry. Confirmed-phrase failures are still shown.
        }
    }

    private func rebuildConfiguration() {
        configuration = TranslationSession.Configuration(
            source: nil,
            target: Locale.Language(identifier: targetCode)
        )
    }
}
