import XCTest
@testable import AudioScribe

final class SupportedLanguageTests: XCTestCase {
    func test_autoMapsToNilWhisperCode() {
        XCTAssertNil(SupportedLanguage.auto.whisperCode)
    }

    func test_otherLanguagesEmitTheirCode() {
        XCTAssertEqual(SupportedLanguage.en.whisperCode, "en")
        XCTAssertEqual(SupportedLanguage.ur.whisperCode, "ur")
        XCTAssertEqual(SupportedLanguage.zh.whisperCode, "zh")
    }

    func test_labelsAreNonEmpty() {
        for lang in SupportedLanguage.allCases {
            XCTAssertFalse(lang.label.isEmpty)
        }
    }
}
