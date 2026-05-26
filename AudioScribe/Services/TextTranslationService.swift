import Foundation

#if canImport(Translation)
import Translation
#endif

/// Free, on-device text translation using Apple's `Translation` framework
/// (iOS 18.0+ / macOS 15.0+ — Apple shipped Translation on Mac in macOS Sequoia).
///
/// Cost: $0. Apple downloads each language pair on first use, then runs offline.
/// On older OS versions, calls throw `.unavailable` so the UI can hide the feature
/// while still leaving Whisper-based translate-to-English available.
enum TextTranslationError: LocalizedError, Equatable {
    case unavailable
    case emptyInput
    case unsupportedPair(source: String?, target: String)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "On-device text translation requires iOS 18.0+ or macOS 15.0+ (Sequoia)."
        case .emptyInput:
            return "Nothing to translate."
        case .unsupportedPair(let source, let target):
            if let source {
                return "This device cannot translate \(source.uppercased()) → \(target.uppercased())."
            }
            return "This device cannot translate to \(target.uppercased())."
        case .underlying(let m):
            return "Translation failed: \(m)"
        }
    }
}

struct TranslationLanguageOption: Identifiable, Hashable {
    let code: String
    let label: String
    var id: String { code }

    /// Languages we surface to users. We intentionally keep this short and
    /// well-supported. Apple's framework will gracefully fall back if a pair
    /// is unavailable on the device's OS version.
    static let presets: [TranslationLanguageOption] = [
        .init(code: "en", label: "English"),
        .init(code: "es", label: "Spanish"),
        .init(code: "fr", label: "French"),
        .init(code: "de", label: "German"),
        .init(code: "it", label: "Italian"),
        .init(code: "pt", label: "Portuguese"),
        .init(code: "nl", label: "Dutch"),
        .init(code: "pl", label: "Polish"),
        .init(code: "ru", label: "Russian"),
        .init(code: "tr", label: "Turkish"),
        .init(code: "ar", label: "Arabic"),
        .init(code: "hi", label: "Hindi"),
        .init(code: "zh", label: "Chinese (Simplified)"),
        .init(code: "ja", label: "Japanese"),
        .init(code: "ko", label: "Korean")
    ]
}

/// Returns true on the OS versions that ship Apple's Translation framework.
/// The programmatic `TranslationSession` API ships in iOS 18.0 and macOS 15.0 (Sequoia).
@inlinable
func isAppleTranslationAvailable() -> Bool {
    if #available(iOS 18.0, macOS 15.0, *) {
        return true
    }
    return false
}
