import SwiftUI
import SwiftData

@main
struct AudioScribeApp: App {
    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var modelManager = ModelManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TranscriptionSession.self,
            TranscriptSegment.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }
        // The on-disk store is unreadable (most often a schema change between
        // builds, or a corrupted sandbox after a crash). Falling back to an
        // in-memory store lets the app launch instead of crashing on first
        // run — sessions saved this run won't persist, but the user can still
        // record, transcribe, and adjust settings to recover.
        let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: [inMemory]) {
            return container
        }
        // Last-ditch: an empty schema container. Should never happen, but
        // crashing on launch is worse than launching with degraded persistence.
        return try! ModelContainer(for: Schema([]))
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(transcriptionService)
                .environmentObject(modelManager)
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(modelManager)
                .environmentObject(transcriptionService)
                .modelContainer(sharedModelContainer)
                .frame(width: 520, height: 480)
        }
        #endif
    }
}
