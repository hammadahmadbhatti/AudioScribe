import XCTest
@testable import AudioScribe
import WhisperKit

@MainActor
final class TranscriptionModeTests: XCTestCase {

    func test_modeCases_haveStableRawValues() {
        // Raw values are persisted/serialized, so changing them is a breaking change.
        XCTAssertEqual(TranscriptionMode.transcribe.rawValue, "transcribe")
        XCTAssertEqual(TranscriptionMode.translateToEnglish.rawValue, "translateToEnglish")
        XCTAssertEqual(TranscriptionMode.allCases.count, 2)
    }

    func test_displayLabels_areHumanReadable() {
        XCTAssertFalse(TranscriptionMode.transcribe.displayLabel.isEmpty)
        XCTAssertTrue(TranscriptionMode.translateToEnglish.displayLabel.lowercased().contains("english"))
    }

    func test_decodingOptions_transcribeMode_usesTranscribeTask() {
        let opts = TranscriptionService.makeDecodingOptions(mode: .transcribe, languageHint: nil)
        XCTAssertEqual(opts.task, .transcribe)
        XCTAssertNil(opts.language)
        XCTAssertEqual(opts.detectLanguage, true,
                       "Auto-detect should be on when no hint is provided.")
    }

    func test_decodingOptions_translateMode_usesTranslateTask() {
        let opts = TranscriptionService.makeDecodingOptions(mode: .translateToEnglish, languageHint: nil)
        XCTAssertEqual(opts.task, .translate,
                       "Translate-to-English uses Whisper's free translate task — no API call.")
    }

    func test_decodingOptions_languageHint_disablesAutodetect() {
        let opts = TranscriptionService.makeDecodingOptions(mode: .transcribe, languageHint: "es")
        XCTAssertEqual(opts.language, "es")
        XCTAssertEqual(opts.detectLanguage, false,
                       "When the user pins a language, auto-detect must be off.")
    }

    func test_merge_propagatesWasTranslatedFlag() {
        let payload = TranscriptionService.merge(
            results: [],
            modelID: "openai_whisper-base",
            wasTranslated: true
        )
        XCTAssertTrue(payload.wasTranslated)
        XCTAssertEqual(payload.modelID, "openai_whisper-base")
    }

    func test_merge_defaultsToNotTranslated() {
        let payload = TranscriptionService.merge(results: [], modelID: "openai_whisper-base")
        XCTAssertFalse(payload.wasTranslated)
    }
}

final class TranslationLanguageOptionTests: XCTestCase {

    func test_presets_includeCommonLanguages() {
        let codes = Set(TranslationLanguageOption.presets.map { $0.code })
        for required in ["en", "es", "fr", "de", "zh", "ja", "ar"] {
            XCTAssertTrue(codes.contains(required),
                          "Expected \(required) to be in the translation presets list.")
        }
    }

    func test_presets_haveUniqueCodes() {
        let codes = TranslationLanguageOption.presets.map { $0.code }
        XCTAssertEqual(codes.count, Set(codes).count,
                       "Duplicate language codes would crash a SwiftUI Picker.")
    }

    func test_availabilityCheck_returnsBool() {
        // Just exercise the function — actual return depends on the OS we're testing on.
        let available = isAppleTranslationAvailable()
        XCTAssertTrue(available == true || available == false)
    }
}

final class TextTranslationErrorTests: XCTestCase {

    func test_unavailable_hasUserFacingMessage() {
        let message = TextTranslationError.unavailable.errorDescription
        XCTAssertNotNil(message)
        // Message should call out the OS requirement so users know why it's disabled.
        XCTAssertTrue(message!.contains("18.0") || message!.contains("15.0"),
                      "Unavailable message should reference the required OS version. Got: \(message!)")
    }

    func test_emptyInput_hasUserFacingMessage() {
        XCTAssertEqual(TextTranslationError.emptyInput.errorDescription, "Nothing to translate.")
    }

    func test_unsupportedPair_includesTargetCode() {
        let err = TextTranslationError.unsupportedPair(source: "en", target: "ja")
        XCTAssertTrue(err.errorDescription!.contains("EN"))
        XCTAssertTrue(err.errorDescription!.contains("JA"))
    }
}
