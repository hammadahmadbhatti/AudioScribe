import Foundation
import OSLog

enum AppLogger {
    static let recorder = Logger(subsystem: "com.hammadahmad.audioscribe", category: "recorder")
    static let player = Logger(subsystem: "com.hammadahmad.audioscribe", category: "player")
    static let transcription = Logger(subsystem: "com.hammadahmad.audioscribe", category: "transcription")
    static let storage = Logger(subsystem: "com.hammadahmad.audioscribe", category: "storage")
    static let ui = Logger(subsystem: "com.hammadahmad.audioscribe", category: "ui")
}
