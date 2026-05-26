import Foundation
import UniformTypeIdentifiers

enum AudioFileImporter {
    static let supportedTypes: [UTType] = [
        .audio,
        .wav,
        .mp3,
        .mpeg4Audio,
        UTType("public.aifc-audio") ?? .audio,
        UTType("com.apple.coreaudio-format") ?? .audio
    ]

    static func importFile(at sourceURL: URL) throws -> URL {
        let needsScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let ext = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension
        let destination = AudioStorage.newAudioFileURL(extension: ext)

        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: sourceURL, to: destination)
        return destination
    }
}
