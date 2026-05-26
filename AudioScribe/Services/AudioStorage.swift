import Foundation

enum AudioStorage {
    static var rootFolderURL: URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let folder = appSupport.appendingPathComponent("AudioScribe", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    static var audioFolderURL: URL {
        let folder = rootFolderURL.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    static func newAudioFileURL(extension ext: String = "wav") -> URL {
        let filename = "rec-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).\(ext)"
        return audioFolderURL.appendingPathComponent(filename)
    }

    static func deleteAudio(named name: String) {
        let url = audioFolderURL.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }
}
