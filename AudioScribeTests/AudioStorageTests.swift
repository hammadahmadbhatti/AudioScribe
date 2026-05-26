import XCTest
@testable import AudioScribe

final class AudioStorageTests: XCTestCase {
    func test_audioFolderExists() {
        let url = AudioStorage.audioFolderURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_newAudioFileURLIsUnique() {
        let urls = (0..<10).map { _ in AudioStorage.newAudioFileURL() }
        let uniques = Set(urls.map { $0.lastPathComponent })
        XCTAssertEqual(uniques.count, urls.count)
    }

    func test_newAudioFileURLHasCorrectExtension() {
        let url = AudioStorage.newAudioFileURL(extension: "m4a")
        XCTAssertEqual(url.pathExtension, "m4a")
    }

    func test_deleteAudioRemovesFile() throws {
        let url = AudioStorage.newAudioFileURL(extension: "wav")
        try Data([0, 1, 2, 3]).write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        AudioStorage.deleteAudio(named: url.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
