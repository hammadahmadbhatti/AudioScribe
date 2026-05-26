import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    @Attribute(.unique) var id: UUID
    var index: Int
    var startSeconds: Double
    var endSeconds: Double
    var text: String

    var session: TranscriptionSession?

    init(
        id: UUID = UUID(),
        index: Int,
        startSeconds: Double,
        endSeconds: Double,
        text: String
    ) {
        self.id = id
        self.index = index
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
    }
}

extension TranscriptSegment {
    func contains(time: Double) -> Bool {
        time >= startSeconds && time < endSeconds
    }
}
