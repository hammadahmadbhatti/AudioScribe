import XCTest
@testable import AudioScribe

final class TimeFormatterTests: XCTestCase {
    func test_formatsZero() {
        XCTAssertEqual(TimeFormatter.format(seconds: 0), "00:00")
    }

    func test_formatsLessThanOneMinute() {
        XCTAssertEqual(TimeFormatter.format(seconds: 9), "00:09")
        XCTAssertEqual(TimeFormatter.format(seconds: 59), "00:59")
    }

    func test_formatsMinutesAndSeconds() {
        XCTAssertEqual(TimeFormatter.format(seconds: 60), "01:00")
        XCTAssertEqual(TimeFormatter.format(seconds: 125), "02:05")
        XCTAssertEqual(TimeFormatter.format(seconds: 3599), "59:59")
    }

    func test_formatsHours() {
        XCTAssertEqual(TimeFormatter.format(seconds: 3600), "1:00:00")
        XCTAssertEqual(TimeFormatter.format(seconds: 3661), "1:01:01")
        XCTAssertEqual(TimeFormatter.format(seconds: 7325), "2:02:05")
    }

    func test_handlesInvalidInput() {
        XCTAssertEqual(TimeFormatter.format(seconds: -5), "00:00")
        XCTAssertEqual(TimeFormatter.format(seconds: .infinity), "00:00")
        XCTAssertEqual(TimeFormatter.format(seconds: .nan), "00:00")
    }
}
