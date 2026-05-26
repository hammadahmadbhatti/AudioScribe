import XCTest
import AVFoundation
@testable import AudioScribe

@MainActor
final class LiveTranscriptionServiceTests: XCTestCase {

    func test_initialState_isIdleWithEmptyText() {
        let service = LiveTranscriptionService()
        XCTAssertEqual(service.status, .idle)
        XCTAssertTrue(service.finalizedText.isEmpty)
        XCTAssertTrue(service.interimText.isEmpty)
        XCTAssertTrue(service.finalizedPhrases.isEmpty)
    }

    func test_reset_returnsToIdleWithEmptyText() {
        let service = LiveTranscriptionService()
        service.stop()
        service.reset()
        XCTAssertEqual(service.status, .idle)
        XCTAssertTrue(service.finalizedText.isEmpty)
        XCTAssertTrue(service.interimText.isEmpty)
        XCTAssertTrue(service.finalizedPhrases.isEmpty)
    }

    func test_status_isListeningHelper() {
        XCTAssertTrue(LiveTranscriptionService.Status.listening(modelID: "openai_whisper-base").isListening)
        XCTAssertFalse(LiveTranscriptionService.Status.idle.isListening)
        XCTAssertFalse(LiveTranscriptionService.Status.stopped.isListening)
        XCTAssertFalse(LiveTranscriptionService.Status.preparing(modelID: "openai_whisper-base").isListening)
        XCTAssertFalse(LiveTranscriptionService.Status.failed("nope").isListening)
    }

    func test_status_userFacingMessage_onlySetForUserNoticeableStates() {
        XCTAssertNil(LiveTranscriptionService.Status.idle.userFacingMessage)
        XCTAssertNil(LiveTranscriptionService.Status.listening(modelID: "openai_whisper-base").userFacingMessage)
        XCTAssertNil(LiveTranscriptionService.Status.stopped.userFacingMessage)
        XCTAssertNotNil(LiveTranscriptionService.Status.preparing(modelID: "openai_whisper-base").userFacingMessage)
        XCTAssertNotNil(LiveTranscriptionService.Status.failed("oops").userFacingMessage)
    }

    func test_bufferConsumer_isANoOpForSourceCompatibility() {
        // WhisperKit captures its own audio internally; the consumer closure
        // exists only so callers that still set `recorder.onAudioBuffer = …`
        // don't have to be refactored. Calling it must be a safe no-op even
        // when the service hasn't been started.
        let service = LiveTranscriptionService()
        let consumer = service.bufferConsumer()
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        consumer(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
        // No crash, no state mutation.
        XCTAssertTrue(service.finalizedText.isEmpty)
        XCTAssertTrue(service.interimText.isEmpty)
    }
}

@MainActor
final class LiveTranscriptionUpdateMappingTests: XCTestCase {

    typealias Update = LiveTranscriptionService.StateUpdate

    func test_emptyState_yieldsEmptyTexts() {
        let update = LiveTranscriptionService.computeUpdate(
            previousConfirmedCount: 0,
            confirmedTexts: [],
            unconfirmedTexts: [],
            currentText: ""
        )
        XCTAssertEqual(update, Update(finalizedText: "", interimText: "", newlyPromotedPhrases: []))
    }

    func test_unconfirmedOnly_populatesInterim() {
        let update = LiveTranscriptionService.computeUpdate(
            previousConfirmedCount: 0,
            confirmedTexts: [],
            unconfirmedTexts: ["Hello world"],
            currentText: ""
        )
        XCTAssertEqual(update.finalizedText, "")
        XCTAssertEqual(update.interimText, "Hello world")
        XCTAssertEqual(update.newlyPromotedPhrases, [])
    }

    func test_confirmedSegments_buildFinalizedJoinedBySpaces() {
        let update = LiveTranscriptionService.computeUpdate(
            previousConfirmedCount: 0,
            confirmedTexts: ["Hello world.", "How are you?"],
            unconfirmedTexts: [],
            currentText: ""
        )
        XCTAssertEqual(update.finalizedText, "Hello world. How are you?")
        XCTAssertEqual(update.newlyPromotedPhrases, ["Hello world.", "How are you?"])
    }

    func test_promotionDelta_includesOnlyNewlyConfirmedSegments() {
        // Two segments were already confirmed; a third just got promoted.
        // Only that third one should fire as a new phrase.
        let update = LiveTranscriptionService.computeUpdate(
            previousConfirmedCount: 2,
            confirmedTexts: ["Hello world.", "How are you?", "I am fine."],
            unconfirmedTexts: [],
            currentText: ""
        )
        XCTAssertEqual(update.newlyPromotedPhrases, ["I am fine."])
        XCTAssertEqual(update.finalizedText, "Hello world. How are you? I am fine.")
    }

    func test_waitingForSpeechPlaceholder_isNotShownToUser() {
        // WhisperKit's stream sets currentText to this placeholder while the
        // buffer is silent. It must NOT leak into the caption box.
        let update = LiveTranscriptionService.computeUpdate(
            previousConfirmedCount: 0,
            confirmedTexts: [],
            unconfirmedTexts: [],
            currentText: "Waiting for speech..."
        )
        XCTAssertEqual(update.interimText, "")
    }

    func test_currentText_isAppendedWhenNotAlreadyInUnconfirmed() {
        let update = LiveTranscriptionService.computeUpdate(
            previousConfirmedCount: 0,
            confirmedTexts: [],
            unconfirmedTexts: ["The quick brown fox"],
            currentText: "jumps over"
        )
        XCTAssertEqual(update.interimText, "The quick brown fox jumps over")
    }

    func test_currentText_isNotDoubledIfAlreadyEmbeddedInUnconfirmed() {
        // Whisper's decoder progress callback can emit a current text that's
        // a substring of the assembled unconfirmed segments. Avoid showing
        // the same phrase twice.
        let update = LiveTranscriptionService.computeUpdate(
            previousConfirmedCount: 0,
            confirmedTexts: [],
            unconfirmedTexts: ["The quick brown fox jumps over"],
            currentText: "jumps over"
        )
        XCTAssertEqual(update.interimText, "The quick brown fox jumps over")
    }

    func test_whitespaceOnlySegments_areDropped() {
        let update = LiveTranscriptionService.computeUpdate(
            previousConfirmedCount: 0,
            confirmedTexts: ["Hello.", "   ", "World."],
            unconfirmedTexts: ["  "],
            currentText: ""
        )
        XCTAssertEqual(update.finalizedText, "Hello. World.")
        XCTAssertEqual(update.interimText, "")
    }
}

@MainActor
final class AudioRecorderMeterTests: XCTestCase {

    func test_silentBuffer_yieldsZeroMeter() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        let level = AudioRecorder.computeMeterLevel(from: buffer)
        XCTAssertEqual(level, 0, accuracy: 0.01)
    }

    func test_loudBuffer_yieldsHighMeter() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        guard let data = buffer.floatChannelData?[0] else {
            XCTFail("Expected float channel data on standard format buffer.")
            return
        }
        for i in 0..<1024 {
            data[i] = i.isMultiple(of: 2) ? 1.0 : -1.0
        }
        let level = AudioRecorder.computeMeterLevel(from: buffer)
        XCTAssertGreaterThan(level, 0.95)
    }

    func test_emptyBuffer_yieldsZero() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 0
        XCTAssertEqual(AudioRecorder.computeMeterLevel(from: buffer), 0)
    }
}
