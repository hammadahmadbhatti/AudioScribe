import Foundation
import Combine

@MainActor
final class ModelManager: ObservableObject {
    @Published var selectedModelID: String {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: Self.selectedModelKey)
        }
    }

    @Published var preferredLanguage: String {
        didSet {
            UserDefaults.standard.set(preferredLanguage, forKey: Self.languageKey)
        }
    }

    @Published private(set) var downloadedModelIDs: Set<String> = []

    private static let selectedModelKey = "AudioScribe.selectedModelID"
    private static let languageKey = "AudioScribe.preferredLanguage"

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.selectedModelKey)
        self.selectedModelID = stored ?? WhisperModelOption.defaultID
        self.preferredLanguage = UserDefaults.standard.string(forKey: Self.languageKey) ?? "auto"
    }

    var selectedOption: WhisperModelOption {
        WhisperModelOption.option(for: selectedModelID) ?? WhisperModelOption.all.first!
    }

    func refreshAvailableModels() async {
        let folder = ModelManager.modelsFolderURL
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: folder.path) else {
            self.downloadedModelIDs = []
            return
        }
        let known = Set(WhisperModelOption.all.map { $0.id })
        // Only count a model as "downloaded" if its folder is also complete
        // (contains at least one `.mlmodelc` bundle). Half-downloaded folders
        // from interrupted runs would otherwise show a misleading green check.
        let downloaded = Set(entries.filter { entry in
            guard known.contains(entry) else { return false }
            return ModelManager.isModelComplete(at: folder.appendingPathComponent(entry))
        })
        self.downloadedModelIDs = downloaded
    }

    func clearCache(for modelID: String) {
        let folder = ModelManager.modelsFolderURL.appendingPathComponent(modelID)
        try? FileManager.default.removeItem(at: folder)
    }

    func clearAllCachedModels() {
        let folder = ModelManager.modelsFolderURL
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for entry in entries {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(entry))
        }
    }

    /// Bytes consumed on disk by the given model's cached folder.
    /// Returns 0 if the folder is missing.
    static func diskUsageBytes(for modelID: String) -> Int64 {
        let folder = modelsFolderURL.appendingPathComponent(modelID)
        return directorySizeBytes(at: folder)
    }

    /// Whether the variant folder actually contains a usable WhisperKit Core ML
    /// bundle. We look for at least one `.mlmodelc` directory inside — that's
    /// the load-bearing artefact. A folder that exists but contains nothing
    /// usable is treated as "not on disk" so the load path will re-download.
    static func isModelComplete(at folder: URL) -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: folder.path) else {
            return false
        }
        // WhisperKit ships at least AudioEncoder.mlmodelc and TextDecoder.mlmodelc
        // per variant. Either one being present indicates a real download; the
        // load step will surface a clearer error if one is missing.
        return entries.contains(where: { $0.hasSuffix(".mlmodelc") })
    }

    /// Recursively sums file sizes under a directory. Used for the per-model
    /// "size on disk" readout in Settings.
    private static func directorySizeBytes(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true, let size = values?.totalFileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Single canonical location for downloaded WhisperKit Core ML models.
    ///
    /// We pin this inside the sandbox's Application Support so:
    /// 1. Writes always succeed regardless of sandbox profile.
    /// 2. We can reliably scan it to know what is already on disk.
    /// 3. Clearing it is straightforward.
    static var downloadBaseURL: URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let folder = appSupport.appendingPathComponent("AudioScribeModels", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// The actual folder WhisperKit/HubApi writes model variants into.
    /// Pattern: `<downloadBase>/models/argmaxinc/whisperkit-coreml/<variant>`
    static var modelsFolderURL: URL {
        let fm = FileManager.default
        let folder = downloadBaseURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }
}

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case auto, en, es, fr, de, it, pt, nl, pl, ru, tr, ar, hi, zh, ja, ko, ur

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto-detect"
        case .en: return "English"
        case .es: return "Spanish"
        case .fr: return "French"
        case .de: return "German"
        case .it: return "Italian"
        case .pt: return "Portuguese"
        case .nl: return "Dutch"
        case .pl: return "Polish"
        case .ru: return "Russian"
        case .tr: return "Turkish"
        case .ar: return "Arabic"
        case .hi: return "Hindi"
        case .zh: return "Chinese"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        case .ur: return "Urdu"
        }
    }

    var whisperCode: String? {
        self == .auto ? nil : rawValue
    }
}
