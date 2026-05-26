import Foundation
import SwiftData

@Model
final class TranscriptionSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var durationSeconds: Double
    var audioFilename: String
    var modelUsed: String
    var detectedLanguage: String?
    var fullTranscript: String
    var isFavorite: Bool

    /// True when `fullTranscript` is the Whisper-translate-to-English output
    /// rather than a faithful transcription of the source language.
    var wasTranslatedDuringTranscription: Bool = false

    /// Cached Apple-Translation post-processed text (e.g. transcript translated into Spanish).
    var translatedText: String?
    /// BCP-47 language code of `translatedText` (e.g. "es", "fr"). Nil when no translation cached.
    var translatedLanguage: String?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.session)
    var segments: [TranscriptSegment] = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        durationSeconds: Double,
        audioFilename: String,
        modelUsed: String,
        detectedLanguage: String? = nil,
        fullTranscript: String = "",
        isFavorite: Bool = false,
        wasTranslatedDuringTranscription: Bool = false,
        translatedText: String? = nil,
        translatedLanguage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.audioFilename = audioFilename
        self.modelUsed = modelUsed
        self.detectedLanguage = detectedLanguage
        self.fullTranscript = fullTranscript
        self.isFavorite = isFavorite
        self.wasTranslatedDuringTranscription = wasTranslatedDuringTranscription
        self.translatedText = translatedText
        self.translatedLanguage = translatedLanguage
    }
}

extension TranscriptionSession {
    var audioURL: URL {
        AudioStorage.audioFolderURL.appendingPathComponent(audioFilename)
    }

    var formattedDuration: String {
        TimeFormatter.format(seconds: durationSeconds)
    }
}
