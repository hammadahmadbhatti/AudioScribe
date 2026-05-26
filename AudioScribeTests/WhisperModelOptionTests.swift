import XCTest
@testable import AudioScribe

final class WhisperModelOptionTests: XCTestCase {
    func test_defaultModelExists() {
        XCTAssertNotNil(WhisperModelOption.option(for: WhisperModelOption.defaultID))
    }

    func test_defaultIsBase() {
        XCTAssertEqual(WhisperModelOption.defaultID, "openai_whisper-base")
    }

    func test_allUniqueIDs() {
        let ids = WhisperModelOption.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate Whisper model IDs detected.")
    }

    func test_unknownReturnsNil() {
        XCTAssertNil(WhisperModelOption.option(for: "openai_whisper-unicorn"))
    }

    func test_sizesAreSensible() {
        for option in WhisperModelOption.all {
            XCTAssertGreaterThan(option.approximateSizeMB, 0)
            XCTAssertLessThan(option.approximateSizeMB, 4096)
        }
    }
}
