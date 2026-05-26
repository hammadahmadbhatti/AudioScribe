import XCTest
import SwiftData
@testable import AudioScribe

final class SwiftDataModelTests: XCTestCase {
    var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([TranscriptionSession.self, TranscriptSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    func test_createsAndQueriesSession() throws {
        let context = container.mainContext
        let session = TranscriptionSession(
            title: "Test",
            durationSeconds: 12,
            audioFilename: "test.wav",
            modelUsed: "openai_whisper-base"
        )
        context.insert(session)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TranscriptionSession>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Test")
    }

    @MainActor
    func test_segmentRelationshipCascadeDeletes() throws {
        let context = container.mainContext
        let session = TranscriptionSession(
            title: "Lecture",
            durationSeconds: 120,
            audioFilename: "lecture.wav",
            modelUsed: "openai_whisper-medium"
        )
        context.insert(session)

        for i in 0..<5 {
            let seg = TranscriptSegment(
                index: i,
                startSeconds: Double(i * 10),
                endSeconds: Double(i * 10 + 9),
                text: "Segment \(i)"
            )
            seg.session = session
            context.insert(seg)
        }
        try context.save()

        XCTAssertEqual(session.segments.count, 5)

        context.delete(session)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<TranscriptSegment>())
        XCTAssertTrue(remaining.isEmpty, "Segments should cascade-delete with their session.")
    }

    func test_segmentContainsTime() {
        let s = TranscriptSegment(index: 0, startSeconds: 5, endSeconds: 10, text: "x")
        XCTAssertFalse(s.contains(time: 4.999))
        XCTAssertTrue(s.contains(time: 5))
        XCTAssertTrue(s.contains(time: 7.5))
        XCTAssertFalse(s.contains(time: 10))
        XCTAssertFalse(s.contains(time: 11))
    }
}
