import Foundation
import SwiftData

@MainActor
enum SessionStore {
    static func save(
        context: ModelContext,
        title: String,
        audioURL: URL,
        duration: Double,
        result: TranscriptionResultPayload
    ) throws -> TranscriptionSession {
        let session = TranscriptionSession(
            title: title,
            durationSeconds: duration,
            audioFilename: audioURL.lastPathComponent,
            modelUsed: result.modelID,
            detectedLanguage: result.detectedLanguage,
            fullTranscript: result.fullText,
            wasTranslatedDuringTranscription: result.wasTranslated
        )
        context.insert(session)

        for s in result.segments {
            let segment = TranscriptSegment(
                index: s.id,
                startSeconds: s.startSeconds,
                endSeconds: s.endSeconds,
                text: s.text
            )
            segment.session = session
            context.insert(segment)
        }

        try context.save()
        return session
    }

    static func delete(_ session: TranscriptionSession, context: ModelContext) {
        let filename = session.audioFilename
        context.delete(session)
        try? context.save()
        AudioStorage.deleteAudio(named: filename)
    }
}
