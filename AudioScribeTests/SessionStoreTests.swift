import XCTest
import SwiftData
@testable import AudioScribe

@MainActor
final class SessionStoreTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([TranscriptionSession.self, TranscriptSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Helpers

    private func insertSession(title: String, audioFilename: String) throws -> TranscriptionSession {
        let session = TranscriptionSession(
            title: title,
            durationSeconds: 30,
            audioFilename: audioFilename,
            modelUsed: "openai_whisper-base"
        )
        container.mainContext.insert(session)
        try container.mainContext.save()
        return session
    }

    private func writeFakeAudio(named filename: String) throws -> URL {
        let url = AudioStorage.audioFolderURL.appendingPathComponent(filename)
        let data = Data("fake-audio".utf8)
        try data.write(to: url)
        return url
    }

    // MARK: - Tests

    func test_delete_removesSessionFromStore() throws {
        let session = try insertSession(title: "First", audioFilename: "a.wav")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TranscriptionSession>()).count, 1)

        SessionStore.delete(session, context: container.mainContext)

        let remaining = try container.mainContext.fetch(FetchDescriptor<TranscriptionSession>())
        XCTAssertEqual(remaining.count, 0, "SessionStore.delete must remove the SwiftData record.")
    }

    func test_delete_removesAudioFileFromDisk() throws {
        let filename = "delete-me-\(UUID().uuidString).wav"
        let audioURL = try writeFakeAudio(named: filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))

        let session = try insertSession(title: "Audio cleanup", audioFilename: filename)
        SessionStore.delete(session, context: container.mainContext)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path),
                       "Audio file must be cleaned up alongside the session record.")
    }

    func test_delete_doesNotTouchOtherSessions() throws {
        let keep = try insertSession(title: "Keeper", audioFilename: "keep.wav")
        let drop = try insertSession(title: "Doomed", audioFilename: "drop.wav")

        SessionStore.delete(drop, context: container.mainContext)

        let remaining = try container.mainContext.fetch(FetchDescriptor<TranscriptionSession>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, keep.id, "Only the targeted session should be deleted.")
    }

    func test_bulkDelete_removesAllTargetedSessions() throws {
        let a = try insertSession(title: "A", audioFilename: "a.wav")
        let b = try insertSession(title: "B", audioFilename: "b.wav")
        let c = try insertSession(title: "C", audioFilename: "c.wav")
        let keep = try insertSession(title: "Keep", audioFilename: "keep.wav")

        // Simulate the LibraryView bulk-delete flow.
        for session in [a, b, c] {
            SessionStore.delete(session, context: container.mainContext)
        }

        let remaining = try container.mainContext.fetch(FetchDescriptor<TranscriptionSession>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, keep.id)
    }

    func test_delete_cascadesToSegments() throws {
        let session = try insertSession(title: "With segments", audioFilename: "seg.wav")
        for i in 0..<4 {
            let seg = TranscriptSegment(
                index: i,
                startSeconds: Double(i),
                endSeconds: Double(i + 1),
                text: "seg \(i)"
            )
            seg.session = session
            container.mainContext.insert(seg)
        }
        try container.mainContext.save()
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TranscriptSegment>()).count, 4)

        SessionStore.delete(session, context: container.mainContext)

        let remaining = try container.mainContext.fetch(FetchDescriptor<TranscriptSegment>())
        XCTAssertTrue(remaining.isEmpty, "Cascade rule should wipe child segments on delete.")
    }
}
