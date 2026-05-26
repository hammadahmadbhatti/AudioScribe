import Foundation

struct WhisperModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Approximate on-disk size of the compiled WhisperKit Core ML bundle.
    /// This is meaningfully larger than the raw model parameter count — Core ML
    /// stores encoder, decoder, mel spectrogram, and tokenizer artefacts as
    /// separate `.mlmodelc` folders, and the published parameter size does not
    /// reflect that overhead. Numbers below come from `argmaxinc/whisperkit-coreml`.
    let approximateSizeMB: Int
    /// Free disk space required to *safely* download and unpack this model.
    /// Includes the unpacked size plus headroom for temporary download artefacts
    /// and Core ML compilation overhead. Used by the pre-flight space check —
    /// `approximateSizeMB * 2` is not enough for the large variants.
    let diskRequiredMB: Int
    let isMultilingual: Bool
    let qualityNote: String

    static let all: [WhisperModelOption] = [
        WhisperModelOption(
            id: "openai_whisper-tiny",
            displayName: "Tiny",
            approximateSizeMB: 80,
            diskRequiredMB: 250,
            isMultilingual: true,
            qualityNote: "Fastest. OK for clear speech."
        ),
        WhisperModelOption(
            id: "openai_whisper-base",
            displayName: "Base",
            approximateSizeMB: 150,
            diskRequiredMB: 400,
            isMultilingual: true,
            qualityNote: "Fast and balanced. Recommended default."
        ),
        WhisperModelOption(
            id: "openai_whisper-small",
            displayName: "Small",
            approximateSizeMB: 500,
            diskRequiredMB: 1200,
            isMultilingual: true,
            qualityNote: "Strong multilingual quality."
        ),
        WhisperModelOption(
            id: "openai_whisper-medium",
            displayName: "Medium",
            approximateSizeMB: 1500,
            diskRequiredMB: 3500,
            isMultilingual: true,
            qualityNote: "Excellent. Needs ~3.5 GB free disk; not recommended on devices with <4 GB RAM."
        ),
        WhisperModelOption(
            id: "openai_whisper-large-v3",
            displayName: "Large v3",
            approximateSizeMB: 3000,
            diskRequiredMB: 6500,
            isMultilingual: true,
            qualityNote: "Highest accuracy. Needs ~6.5 GB free disk and 6+ GB RAM. Avoid on iPhone/older iPads."
        )
    ]

    static let defaultID: String = "openai_whisper-base"

    static func option(for id: String) -> WhisperModelOption? {
        all.first { $0.id == id }
    }
}
